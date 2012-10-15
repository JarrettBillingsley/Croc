/******************************************************************************
This module contains the 'debug' standard library.

License:
Copyright (c) 2008 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module croc.stdlib_debug;

import croc.api_debug;
import croc.api_interpreter;
import croc.api_stack;
import croc.base_alloc;
import croc.base_gc;
import croc.base_writebarrier;
import croc.ex;
import croc.ex_library;
import croc.types;
import croc.types_function;
import croc.utils;

debug import tango.io.Stdout;

struct DebugLib
{
static:
	void init(CrocThread* t)
	{
		makeModule(t, "debug", function uword(CrocThread* t)
		{
			newFunction(t, 3, &setHook,        "setHook");        newGlobal(t, "setHook");
			newFunction(t, 1, &getHook,        "getHook");        newGlobal(t, "getHook");
			newFunction(t, 1, &callDepth,      "callDepth");      newGlobal(t, "callDepth");
			newFunction(t, 2, &sourceName,     "sourceName");     newGlobal(t, "sourceName");
			newFunction(t, 2, &sourceLine,     "sourceLine");     newGlobal(t, "sourceLine");
			newFunction(t, 2, &getFunc,        "getFunc");        newGlobal(t, "getFunc");
			newFunction(t, 2, &numLocals,      "numLocals");      newGlobal(t, "numLocals");
			newFunction(t, 3, &localName,      "localName");      newGlobal(t, "localName");
			newFunction(t, 3, &getLocal,       "getLocal");       newGlobal(t, "getLocal");
			newFunction(t, 4, &setLocal,       "setLocal");       newGlobal(t, "setLocal");
			newFunction(t, 2, &numUpvals,      "numUpvals");      newGlobal(t, "numUpvals");
			newFunction(t, 3, &upvalName,      "upvalName");      newGlobal(t, "upvalName");
			newFunction(t, 3, &getUpval,       "getUpval");       newGlobal(t, "getUpval");
			newFunction(t, 4, &setUpval,       "setUpval");       newGlobal(t, "setUpval");
			newFunction(t, 2, &getFuncEnv,     "getFuncEnv");     newGlobal(t, "getFuncEnv");
			newFunction(t, 3, &setFuncEnv,     "setFuncEnv");     newGlobal(t, "setFuncEnv");
			newFunction(t, 2, &currentLine,    "currentLine");    newGlobal(t, "currentLine");
			newFunction(t, 2, &lineInfo,       "lineInfo");       newGlobal(t, "lineInfo");
			newFunction(t, 1, &getMetatable,   "getMetatable");   newGlobal(t, "getMetatable");
			newFunction(t, 2, &setMetatable,   "setMetatable");   newGlobal(t, "setMetatable");
			newFunction(t, 0, &getRegistry,    "getRegistry");    newGlobal(t, "getRegistry");

			return 0;
		});

		importModuleNoNS(t, "debug");
	}

	ubyte strToMask(char[] str)
	{
		ubyte mask = 0;

		if(str.contains('c')) mask |= CrocThread.Hook.Call;
		if(str.contains('r')) mask |= CrocThread.Hook.Ret;
		if(str.contains('l')) mask |= CrocThread.Hook.Line;

		return mask;
	}

	char[] maskToStr(char[] buf, ubyte mask)
	{
		uword i = 0;

		if(mask & CrocThread.Hook.Call)  buf[i++] = 'c';
		if(mask & CrocThread.Hook.Ret)   buf[i++] = 'r';
		if(mask & CrocThread.Hook.Line)  buf[i++] = 'l';
		if(mask & CrocThread.Hook.Delay) buf[i++] = 'd';

		return buf[0 .. i];
	}

	CrocThread* getThreadParam(CrocThread* t, out word arg)
	{
		if(isValidIndex(t, 1) && isThread(t, 1))
		{
			arg = 1;
			return getThread(t, 1);
		}
		else
		{
			arg = 0;
			return t;
		}
	}

	ActRecord* getAR(CrocThread* t, CrocThread* thread, crocint depth)
	{
		auto maxDepth = .callDepth(thread);

		if(t is thread)
		{
			// ignore call to whatever this function is
			if(depth < 0 || depth >= maxDepth - 1)
				throwStdException(t, "RangeException", "invalid call depth {}", depth);

			return getActRec(thread, cast(uword)depth + 1);
		}
		else
		{
			if(depth < 0 || depth >= maxDepth)
				throwStdException(t, "RangeException", "invalid call depth {}", depth);

			return getActRec(thread, cast(uword)depth);
		}
	}

	CrocFunction* getFuncParam(CrocThread* t, CrocThread* thread, word arg)
	{
		if(isInt(t, arg))
			return getAR(t, thread, getInt(t, arg)).func;
		else if(isFunction(t, arg))
			return getFunction(t, arg);
		else
			paramTypeError(t, arg, "int|function");

		assert(false);
	}

	uword setHook(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);

		checkAnyParam(t, arg + 1);

		if(!isNull(t, arg + 1) && !isFunction(t, arg + 1))
			paramTypeError(t, arg + 1, "null|function");

		auto maskStr = optStringParam(t, arg + 2, "");
		auto delay = optIntParam(t, arg + 3, 0);

		if(delay < 0 || delay > uword.max)
			throwStdException(t, "RangeException", "invalid delay value ({})", delay);

		auto mask = strToMask(maskStr);

		if(delay > 0)
			mask |= CrocThread.Hook.Delay;

		dup(t, arg + 1);
		transferVals(t, thread, 1);
		setHookFunc(thread, mask, cast(uword)delay);
		return 0;
	}

	uword getHook(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);

		getHookFunc(thread);
		transferVals(thread, t, 1);
		char[8] buf;
		pushString(t, maskToStr(buf, getHookMask(thread)));
		pushInt(t, getHookDelay(thread));
		return 3;
	}

	uword callDepth(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);

		if(t is thread)
			pushInt(t, .callDepth(t) - 1); // - 1 to ignore "callDepth" itself
		else
			pushInt(t, .callDepth(thread));

		return 1;
	}

	uword sourceName(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null || func.isNative)
			pushString(t, "");
		else
			push(t, CrocValue(func.scriptFunc.locFile));

		return 1;
	}

	uword sourceLine(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null || func.isNative)
			pushInt(t, 0);
		else
			pushInt(t, func.scriptFunc.locLine);

		return 1;
	}

	uword getFunc(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		checkIntParam(t, arg + 1);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null)
			pushNull(t);
		else
			push(t, CrocValue(func));

		return 1;
	}

	uword numLocals(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto ar = getAR(t, thread, checkIntParam(t, arg + 1));

		if(ar.func is null || ar.func.isNative)
			pushInt(t, 0);
		else
		{
			crocint num = 0;
			auto pc = ar.pc - ar.func.scriptFunc.code.ptr;

			foreach(ref var; ar.func.scriptFunc.locVarDescs)
				if(pc >= var.pcStart && pc < var.pcEnd)
					num++;

			pushInt(t, num);
		}

		return 1;
	}

	uword localName(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto ar = getAR(t, thread, checkIntParam(t, arg + 1));
		auto idx = checkIntParam(t, arg + 2);

		if(idx < 0 || ar.func is null || ar.func.isNative)
			throwStdException(t, "BoundsException", "invalid local index '{}'", idx);

		auto originalIdx = idx;
		auto pc = ar.pc - ar.func.scriptFunc.code.ptr;
		bool found = false;

		foreach(ref var; ar.func.scriptFunc.locVarDescs)
		{
			if(pc >= var.pcStart && pc < var.pcEnd)
			{
				if(idx == 0)
				{
					push(t, CrocValue(var.name));
					found = true;
					break;
				}

				idx--;
			}
		}

		if(!found)
			throwStdException(t, "BoundsException", "invalid local index '{}'", originalIdx);

		return 1;
	}

	uword getLocal(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto ar = getAR(t, thread, checkIntParam(t, arg + 1));

		crocint idx = 1;
		CrocString* name;

		if(isInt(t, arg + 2))
			idx = getInt(t, arg + 2);
		else if(isString(t, arg + 2))
			name = getStringObj(t, arg + 2);
		else
			paramTypeError(t, arg + 2, "int|string");

		if(idx < 0 || ar.func is null || ar.func.isNative)
			throwStdException(t, "BoundsException", "invalid local index '{}'", idx);

		auto originalIdx = idx;
		auto pc = ar.pc - ar.func.scriptFunc.code.ptr;
		bool found = false;

		foreach(ref var; ar.func.scriptFunc.locVarDescs)
		{
			if(pc >= var.pcStart && pc < var.pcEnd)
			{
				if(name is null)
				{
					if(idx == 0)
					{
						// don't inline; if t is thread, invalid push
						auto v = thread.stack[ar.base + var.reg];
						push(t, v);
						found = true;
						break;
					}

					idx--;
				}
				else if(var.name is name)
				{
					auto v = thread.stack[ar.base + var.reg];
					push(t, v);
					found = true;
					break;
				}
			}
		}

		if(!found)
		{
			if(name is null)
				throwStdException(t, "BoundsException", "invalid local index '{}'", originalIdx);
			else
				throwStdException(t, "NameException", "invalid local name '{}'", name.toString());
		}

		return 1;
	}

	uword setLocal(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto ar = getAR(t, thread, checkIntParam(t, arg + 1));

		crocint idx = 1;
		CrocString* name;

		if(isInt(t, arg + 2))
			idx = getInt(t, arg + 2);
		else if(isString(t, arg + 2))
			name = getStringObj(t, arg + 2);
		else
			paramTypeError(t, arg + 2, "int|string");

		checkAnyParam(t, arg + 3);

		if(idx < 0 || ar.func is null || ar.func.isNative)
			throwStdException(t, "BoundsException", "invalid local index '{}'", idx);

		auto originalIdx = idx;
		auto pc = ar.pc - ar.func.scriptFunc.code.ptr;
		bool found = false;

		foreach(ref var; ar.func.scriptFunc.locVarDescs)
		{
			if(pc >= var.pcStart && pc < var.pcEnd)
			{
				if(name is null)
				{
					if(idx == 0)
					{
						if(var.reg == 0)
							throwStdException(t, "ValueException", "Cannot set the value of 'this'");

						thread.stack[ar.base + var.reg] = *getValue(t, arg + 3);
						found = true;
						break;
					}

					idx--;
				}
				else if(var.name is name)
				{
					if(var.reg == 0)
						throwStdException(t, "ValueException", "Cannot set the value of 'this'");

					thread.stack[ar.base + var.reg] = *getValue(t, arg + 3);
					found = true;
					break;
				}
			}
		}

		if(!found)
		{
			if(name is null)
				throwStdException(t, "BoundsException", "invalid local index '{}'", originalIdx);
			else
				throwStdException(t, "NameException", "invalid local name '{}'", name.toString());
		}

		return 0;
	}

	uword numUpvals(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null)
			pushInt(t, 0);
		else
			pushInt(t, func.numUpvals);

		return 1;
	}

	uword upvalName(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);
		auto idx = checkIntParam(t, arg + 2);

		if(func is null || idx < 0 || idx >= func.numUpvals)
			throwStdException(t, "BoundsException", "invalid upvalue index '{}'", idx);

		if(func.isNative)
			pushString(t, "");
		else
			push(t, CrocValue(func.scriptFunc.upvalNames[cast(uword)idx]));

		return 1;
	}

	uword getUpval(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null)
			throwStdException(t, "ValueException", "invalid function");

		if(isInt(t, arg + 2))
		{
			auto idx = getInt(t, arg + 2);

			if(idx < 0 || idx >= func.numUpvals)
				throwStdException(t, "BoundsException", "invalid upvalue index '{}'", idx);

			if(func.isNative)
				push(t, func.nativeUpvals()[cast(uword)idx]);
			else
			{
				// don't inline; if t is thread, invalid push
				auto v = *func.scriptUpvals()[cast(uword)idx].value;
				push(t, v);
			}
		}
		else if(isString(t, arg + 2))
		{
			if(func.isNative)
				throwStdException(t, "ValueException", "cannot get upvalues by name for native functions");

			auto name = getStringObj(t, arg + 2);

			bool found = false;

			foreach(i, n; func.scriptFunc.upvalNames)
			{
				if(n is name)
				{
					found = true;
					auto v = *func.scriptUpvals()[i].value;
					push(t, v);
					break;
				}
			}

			if(!found)
				throwStdException(t, "NameException", "invalid upvalue name '{}'", name.toString());
		}
		else
			paramTypeError(t, arg + 2, "int|string");

		return 1;
	}

	uword setUpval(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);
		checkAnyParam(t, arg + 3);

		if(func is null)
			throwStdException(t, "ValueException", "invalid function");

		if(isInt(t, arg + 2))
		{
			auto idx = getInt(t, arg + 2);

			if(idx < 0 || idx >= func.numUpvals)
				throwStdException(t, "BoundsException", "invalid upvalue index '{}'", idx);

			if(func.isNative)
				.func.setNativeUpval(t.vm.alloc, func, cast(uword)idx, getValue(t, arg + 3));
			else
			{
				mixin(writeBarrier!("t.vm.alloc", "func"));
				*func.scriptUpvals()[cast(uword)idx].value = *getValue(t, arg + 3);
			}
		}
		else if(isString(t, arg + 2))
		{
			if(func.isNative)
				throwStdException(t, "ValueException", "cannot get upvalues by name for native functions");

			auto name = getStringObj(t, arg + 2);

			bool found = false;

			foreach(i, n; func.scriptFunc.upvalNames)
			{
				if(n is name)
				{
					found = true;

					if(func.isNative)
						.func.setNativeUpval(t.vm.alloc, func, i, getValue(t, arg + 3));
					else
					{
						mixin(writeBarrier!("t.vm.alloc", "func"));
						*func.scriptUpvals()[i].value = *getValue(t, arg + 3);
					}

					break;
				}
			}

			if(!found)
				throwStdException(t, "NameException", "invalid upvalue name '{}'", name.toString());
		}
		else
			paramTypeError(t, arg + 2, "int|string");

		return 0;
	}

	uword getFuncEnv(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null)
			throwStdException(t, "ValueException", "invalid function");

		push(t, CrocValue(func.environment));
		return 1;
	}

	uword setFuncEnv(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null)
			throwStdException(t, "ValueException", "invalid function");

		if(!func.isNative)
			throwStdException(t, "ValueException", "can only set the environment of native functions");

		checkParam(t, arg + 2, CrocValue.Type.Namespace);
		push(t, CrocValue(func.environment));
		push(t, CrocValue(func));
		dup(t, arg + 2);
		.setFuncEnv(t, -2);
		pop(t);
		return 1;
	}

	uword currentLine(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto depth = checkIntParam(t, arg + 1);
		auto maxDepth = .callDepth(thread);

		if(t is thread)
		{
			if(depth < 0 || depth >= maxDepth - 1)
				throwStdException(t, "RangeException", "invalid call depth {}", depth);

			pushInt(t, getDebugLine(t, cast(uword)depth + 1));
		}
		else
		{
			if(depth < 0 || depth >= maxDepth)
				throwStdException(t, "RangeException", "invalid call depth {}", depth);

			pushInt(t, getDebugLine(t, cast(uword)depth));
		}
		return 1;
	}

	uword lineInfo(CrocThread* t)
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func is null || func.isNative)
			newArray(t, 0);
		else
		{
			auto info = func.scriptFunc.lineInfo;

			newTable(t, info.length);

			foreach(i, l; info)
			{
				pushBool(t, true);
				idxai(t, -2, l);
			}

			pushNull(t);
			methodCall(t, -2, "keys", 1);
			pushNull(t);
			methodCall(t, -2, "sort", 1);
		}

		return 1;
	}

	uword getMetatable(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);

		switch(name)
		{
			case "null":      getTypeMT(t, CrocValue.Type.Null);      break;
			case "bool":      getTypeMT(t, CrocValue.Type.Bool);      break;
			case "int":       getTypeMT(t, CrocValue.Type.Int);       break;
			case "float":     getTypeMT(t, CrocValue.Type.Float);     break;
			case "char":      getTypeMT(t, CrocValue.Type.Char);      break;
			case "string":    getTypeMT(t, CrocValue.Type.String);    break;
			case "table":     getTypeMT(t, CrocValue.Type.Table);     break;
			case "array":     getTypeMT(t, CrocValue.Type.Array);     break;
			case "memblock":  getTypeMT(t, CrocValue.Type.Memblock);  break;
			case "function":  getTypeMT(t, CrocValue.Type.Function);  break;
			case "class":     getTypeMT(t, CrocValue.Type.Class);     break;
			case "instance":  getTypeMT(t, CrocValue.Type.Instance);  break;
			case "namespace": getTypeMT(t, CrocValue.Type.Namespace); break;
			case "thread":    getTypeMT(t, CrocValue.Type.Thread);    break;
			case "nativeobj": getTypeMT(t, CrocValue.Type.NativeObj); break;
			case "weakref":   getTypeMT(t, CrocValue.Type.WeakRef);   break;
			case "funcdef":   getTypeMT(t, CrocValue.Type.FuncDef);   break;

			default:
				throwStdException(t, "ValueException", "invalid type name '{}'", name);
		}

		return 1;
	}

	uword setMetatable(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);

		checkAnyParam(t, 2);

		if(!isNull(t, 2) && !isNamespace(t, 2))
			paramTypeError(t, 2, "null|namespace");

		setStackSize(t, 3);

		switch(name)
		{
			case "null":      setTypeMT(t, CrocValue.Type.Null);      break;
			case "bool":      setTypeMT(t, CrocValue.Type.Bool);      break;
			case "int":       setTypeMT(t, CrocValue.Type.Int);       break;
			case "float":     setTypeMT(t, CrocValue.Type.Float);     break;
			case "char":      setTypeMT(t, CrocValue.Type.Char);      break;
			case "string":    setTypeMT(t, CrocValue.Type.String);    break;
			case "table":     setTypeMT(t, CrocValue.Type.Table);     break;
			case "array":     setTypeMT(t, CrocValue.Type.Array);     break;
			case "memblock":  setTypeMT(t, CrocValue.Type.Memblock);  break;
			case "function":  setTypeMT(t, CrocValue.Type.Function);  break;
			case "class":     setTypeMT(t, CrocValue.Type.Class);     break;
			case "instance":  setTypeMT(t, CrocValue.Type.Instance);  break;
			case "namespace": setTypeMT(t, CrocValue.Type.Namespace); break;
			case "thread":    setTypeMT(t, CrocValue.Type.Thread);    break;
			case "nativeobj": setTypeMT(t, CrocValue.Type.NativeObj); break;
			case "weakref":   setTypeMT(t, CrocValue.Type.WeakRef);   break;
			case "funcdef":   setTypeMT(t, CrocValue.Type.FuncDef);   break;

			default:
				throwStdException(t, "ValueException", "invalid type name '{}'", name);
		}

		return 0;
	}

	uword getRegistry(CrocThread* t)
	{
		.getRegistry(t);
		return 1;
	}
}