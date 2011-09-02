/******************************************************************************
WIP

License:
Copyright (c) 2011 Jarrett Billingsley

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

module croc.interpreter;

import Integer = tango.text.convert.Integer;
import tango.core.Tuple;
import Utf = tango.text.convert.Utf;

import tango.stdc.string;

import croc.api_debug;
import croc.api_interpreter;
import croc.api_stack;
import croc.base_alloc;
import croc.base_gc;
import croc.base_opcodes;
import croc.types;
import croc.types_array;
import croc.types_class;
import croc.types_function;
import croc.types_instance;
import croc.types_memblock;
import croc.types_namespace;
import croc.types_string;
import croc.types_table;
import croc.types_thread;
import croc.utils;

// ================================================================================================================================================
// Package
// ================================================================================================================================================

package:

// Free all objects.
void freeAll(CrocThread* t)
{
	for(auto pcur = &t.vm.alloc.gcHead; *pcur !is null; )
	{
		auto cur = *pcur;

		if((cast(CrocBaseObject*)cur).mType == CrocValue.Type.Instance)
		{
			auto i = cast(CrocInstance*)cur;

			if(i.parent.finalizer && ((cur.flags & GCBits.Finalized) == 0))
			{
				*pcur = cur.next;

				cur.flags |= GCBits.Finalized;
				cur.next = t.vm.alloc.finalizable;
				t.vm.alloc.finalizable = cur;
			}
			else
				pcur = &cur.next;
		}
		else
			pcur = &cur.next;
	}

	runFinalizers(t);
	assert(t.vm.alloc.finalizable is null);

	GCObject* next = void;

	for(auto cur = t.vm.alloc.gcHead; cur !is null; cur = next)
	{
		next = cur.next;
		free(t.vm, cur);
	}
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

void runFinalizers(CrocThread* t)
{
	auto alloc = &t.vm.alloc;

	if(alloc.finalizable)
	{
		for(auto pcur = &alloc.finalizable; *pcur !is null; )
		{
			auto cur = *pcur;
			auto i = cast(CrocInstance*)cur;

			*pcur = cur.next;
			cur.next = alloc.gcHead;
			alloc.gcHead = cur;

			cur.flags = (cur.flags & ~GCBits.Marked) | !alloc.markVal;

			// sanity check
			if(i.parent.finalizer)
			{
				auto oldLimit = alloc.gcLimit;
				alloc.gcLimit = typeof(oldLimit).max;
				scope(exit) alloc.gcLimit = oldLimit;

				auto size = stackSize(t);

				try
				{
					push(t, CrocValue(i.parent.finalizer));
					push(t, CrocValue(i));
					commonCall(t, t.stackIndex - 2, 0, callPrologue(t, t.stackIndex - 2, 0, 1, null));
				}
				catch(CrocException e)
				{
					// TODO: this seems like a bad idea.
					catchException(t);
					setStackSize(t, size);
				}
			}
		}
	}
}

// ============================================================================
// Function Calling

CrocNamespace* getEnv(CrocThread* t, uword depth = 0)
{
	if(t.arIndex == 0)
		return t.vm.globals;
	else if(depth == 0)
		return t.currentAR.func.environment;

	for(word idx = t.arIndex - 1; idx >= 0; idx--)
	{
		if(depth == 0)
			return t.actRecs[cast(uword)idx].func.environment;
		else if(depth <= t.actRecs[cast(uword)idx].numTailcalls)
			throwException(t, "Attempting to get environment of function whose activation record was overwritten by a tail call");

		depth -= (t.actRecs[cast(uword)idx].numTailcalls + 1);
	}

	return t.vm.globals;
}

uword commonCall(CrocThread* t, AbsStack slot, word numReturns, bool isScript)
{
	t.nativeCallDepth++;
	scope(exit) t.nativeCallDepth--;

	if(isScript)
		execute(t);

	maybeGC(t);

	if(numReturns == -1)
		return t.stackIndex - slot;
	else
	{
		t.stackIndex = slot + numReturns;
		return numReturns;
	}
}

bool commonMethodCall(CrocThread* t, AbsStack slot, CrocValue* self, CrocValue* lookup, CrocString* methodName, word numReturns, uword numParams, bool customThis)
{
	CrocClass* proto;
	auto method = lookupMethod(t, lookup, methodName, proto);

	// Idea is like this:

	// If we're calling the real method, the object is moved to the 'this' slot and the method takes its place.

	// If we're calling opMethod, the object is left where it is (or the custom context is moved to its place),
	// the method name goes where the context was, and we use callPrologue2 with a closure that's not on the stack.

	if(method.type != CrocValue.Type.Null)
	{
		if(!customThis)
			t.stack[slot + 1] = *self;

		t.stack[slot] = method;

		return callPrologue(t, slot, numReturns, numParams, proto);
	}
	else
	{
		auto mm = getMM(t, lookup, MM.Method, proto);

		if(mm is null)
		{
			typeString(t, lookup);
			throwException(t, "No implementation of method '{}' or {} for type '{}'", methodName.toString(), MetaNames[MM.Method], getString(t, -1));
		}

		if(customThis)
			t.stack[slot] = t.stack[slot + 1];
		else
			t.stack[slot] = *self;

		t.stack[slot + 1] = methodName;

		return callPrologue2(t, mm, slot, numReturns, slot, numParams + 1, proto);
	}
}

CrocValue lookupMethod(CrocThread* t, CrocValue* v, CrocString* name, out CrocClass* proto)
{
	switch(v.type)
	{
		case CrocValue.Type.Class:
			if(auto ret = classobj.getField(v.mClass, name, proto))
				return *ret;

			goto default;

		case CrocValue.Type.Instance:
			return getInstanceMethod(v.mInstance, name, proto);

		case CrocValue.Type.Table:
			if(auto ret = table.get(v.mTable, CrocValue(name)))
				return *ret;

			goto default;

		case CrocValue.Type.Namespace:
			if(auto ret = namespace.get(v.mNamespace, name))
				return *ret;
			else
				return CrocValue.nullValue;

		default:
			return getGlobalMetamethod(t, v.type, name);
	}
}

CrocValue getInstanceMethod(CrocInstance* inst, CrocString* name, out CrocClass* proto)
{
	CrocValue dummy;

	if(auto ret = instance.getField(inst, name, dummy))
	{
		if(dummy == CrocValue(inst))
			proto = inst.parent;
		else
		{
			assert(dummy.type == CrocValue.Type.Class);
			proto = dummy.mClass;
		}

		return *ret;
	}
	else
		return CrocValue.nullValue;
}

CrocValue getGlobalMetamethod(CrocThread* t, CrocValue.Type type, CrocString* name)
{
	if(auto mt = getMetatable(t, type))
	{
		if(auto ret = namespace.get(mt, name))
			return *ret;
	}

	return CrocValue.nullValue;
}

CrocFunction* getMM(CrocThread* t, CrocValue* obj, MM method)
{
	CrocClass* dummy = void;
	return getMM(t, obj, method, dummy);
}

CrocFunction* getMM(CrocThread* t, CrocValue* obj, MM method, out CrocClass* proto)
{
	auto name = t.vm.metaStrings[method];
	CrocValue ret = void;

	if(obj.type == CrocValue.Type.Instance)
		ret = getInstanceMethod(obj.mInstance, name, proto);
	else
		ret = getGlobalMetamethod(t, obj.type, name);

	if(ret.type == CrocValue.Type.Function)
		return ret.mFunction;

	return null;
}

template tryMMParams(int numParams, int n = 1)
{
	static if(n <= numParams)
		const char[] tryMMParams = (n > 1 ? ", " : "") ~ "CrocValue* src" ~ n.stringof ~ tryMMParams!(numParams, n + 1);
	else
		const char[] tryMMParams = "";
}

template tryMMSaves(int numParams, int n = 1)
{
	static if(n <= numParams)
		const char[] tryMMSaves = "\tauto srcsave" ~ n.stringof ~ " = *src" ~ n.stringof ~ ";\n" ~ tryMMSaves!(numParams, n + 1);
	else
		const char[] tryMMSaves = "";
}

template tryMMPushes(int numParams, int n = 1)
{
	static if(n <= numParams)
		const char[] tryMMPushes = "\tpush(t, srcsave" ~ n.stringof ~ ");\n" ~ tryMMPushes!(numParams, n + 1);
	else
		const char[] tryMMPushes = "";
}

template tryMMImpl(int numParams, bool hasDest)
{
	const char[] tryMMImpl =
	"bool tryMM(CrocThread* t, MM mm, " ~ (hasDest? "CrocValue* dest, " : "") ~ tryMMParams!(numParams) ~ ")\n"
	"{\n"
	"	CrocClass* proto = null;"
	"	auto method = getMM(t, src1, mm, proto);\n"
	"\n"
	"	if(method is null)\n"
	"		return false;\n"
	"\n"
	~
	(hasDest?
		"	bool shouldLoad = void;\n"
		"	savePtr(t, dest, shouldLoad);\n"
	:
		"")
	~
	"\n"
	~ tryMMSaves!(numParams) ~
	"\n"
	"	auto funcSlot = push(t, CrocValue(method));\n"
	~ tryMMPushes!(numParams) ~
	"	commonCall(t, funcSlot + t.stackBase, " ~ (hasDest ? "1" : "0") ~ ", callPrologue(t, funcSlot + t.stackBase, " ~ (hasDest ? "1" : "0") ~ ", " ~ numParams.stringof ~ ", proto));\n"
	~
	(hasDest?
		"	if(shouldLoad)\n"
		"		loadPtr(t, dest);\n"
		"	*dest = t.stack[t.stackIndex - 1];\n"
		"	pop(t);\n"
	:
		"")
	~
	"	return true;\n"
	"}";
}

template tryMM(int numParams, bool hasDest)
{
	static assert(numParams > 0, "Need at least one param");
	mixin(tryMMImpl!(numParams, hasDest));
}

bool callPrologue(CrocThread* t, AbsStack slot, word numReturns, uword numParams, CrocClass* proto)
{
	assert(numParams > 0);
	auto func = &t.stack[slot];

	switch(func.type)
	{
		case CrocValue.Type.Function:
			return callPrologue2(t, func.mFunction, slot, numReturns, slot + 1, numParams, proto);

		case CrocValue.Type.Class:
			auto cls = func.mClass;

			if(cls.allocator)
			{
				t.stack[slot] = cls.allocator;
				t.stack[slot + 1] = cls;
				commonCall(t, slot, 1, callPrologue(t, slot, 1, numParams, null));

				if(t.stack[slot].type != CrocValue.Type.Instance)
				{
					typeString(t, &t.stack[slot]);
					throwException(t, "class allocator expected to return an 'instance', not a '{}'", getString(t, -1));
				}
			}
			else
			{
				auto inst = instance.create(t.vm.alloc, cls);

				// call any constructor
				auto ctor = classobj.getField(cls, t.vm.ctorString);

				if(ctor !is null)
				{
					if(ctor.type != CrocValue.Type.Function)
					{
						typeString(t, ctor);
						throwException(t, "class constructor expected to be a 'function', not '{}'", getString(t, -1));
					}

					t.nativeCallDepth++;
					scope(exit) t.nativeCallDepth--;
					t.stack[slot] = ctor.mFunction;
					t.stack[slot + 1] = inst;

					// do this instead of rawCall so the proto is set correctly
					if(callPrologue(t, slot, 0, numParams, cls))
						execute(t);
				}

				t.stack[slot] = inst;
			}

			if(numReturns == -1)
				t.stackIndex = slot + 1;
			else
			{
				if(numReturns > 1)
					t.stack[slot + 1 .. slot + numReturns] = CrocValue.nullValue;

				if(t.arIndex == 0)
				{
					t.state = CrocThread.State.Dead;
					t.shouldHalt = false;
					t.stackIndex = slot + numReturns;

					if(t is t.vm.mainThread)
						t.vm.curThread = t;
				}
				else if(t.currentAR.savedTop < slot + numReturns)
					t.stackIndex = slot + numReturns;
				else
					t.stackIndex = t.currentAR.savedTop;
			}

			return false;

		case CrocValue.Type.Thread:
			auto thread = func.mThread;

			if(thread is t)
				throwException(t, "Thread attempting to resume itself");

			if(thread is t.vm.mainThread)
				throwException(t, "Attempting to resume VM's main thread");

			if(thread.state != CrocThread.State.Initial && thread.state != CrocThread.State.Suspended)
				throwException(t, "Attempting to resume a {} coroutine", CrocThread.StateStrings[thread.state]);

			auto ar = pushAR(t);

			ar.base = slot;
			ar.savedTop = t.stackIndex;
			ar.vargBase = slot;
			ar.returnSlot = slot;
			ar.func = null;
			ar.pc = null;
			ar.numReturns = numReturns;
			ar.proto = null;
			ar.numTailcalls = 0;
			ar.firstResult = 0;
			ar.numResults = 0;
			ar.unwindCounter = 0;
			ar.unwindReturn = null;

			t.stackIndex = slot;

			uword numRets = void;

			try
			{
				if(thread.state == CrocThread.State.Initial)
				{
					checkStack(thread, cast(AbsStack)(numParams + 1));
					thread.stack[1 .. 1 + numParams] = t.stack[slot + 1 .. slot + 1 + numParams];
					thread.stackIndex += numParams;
				}
				else
				{
					// Get rid of 'this'
					numParams--;
					saveResults(thread, t, slot + 2, numParams);
				}

				auto savedState = t.state;
				t.state = CrocThread.State.Waiting;

				scope(exit)
				{
					t.state = savedState;
					t.vm.curThread = t;
				}

				numRets = resume(thread, numParams);
			}
			catch(CrocException e)
			{
				callEpilogue(t, false);
				throw e;
			}
			// Don't have to handle halt exceptions; they can't propagate out of a thread

			saveResults(t, thread, thread.stackIndex - numRets, numRets);
			thread.stackIndex -= numRets;

			callEpilogue(t, true);
			return false;

		default:
			auto method = getMM(t, func, MM.Call, proto);

			if(method is null)
			{
				typeString(t, func);
				throwException(t, "No implementation of {} for type '{}'", MetaNames[MM.Call], getString(t, -1));
			}

			t.stack[slot + 1] = *func;
			*func = method;
			return callPrologue2(t, method, slot, numReturns, slot + 1, numParams, proto);
	}
}

bool callPrologue2(CrocThread* t, CrocFunction* func, AbsStack returnSlot, word numReturns, AbsStack paramSlot, word numParams, CrocClass* proto)
{
	const char[] wrapEH =
		"catch(CrocException e)
		{
			t.vm.traceback.append(&t.vm.alloc, getDebugLoc(t));
			callEpilogue(t, false);
			throw e;
		}
		catch(CrocHaltException e)
		{
			unwindEH(t);
			callEpilogue(t, false);
			throw e;
		}";


	if(numParams > func.maxParams)
		throwException(t, "Function {} expected at most {} parameters but was given {}", func.name.toString(), func.maxParams - 1, numParams - 1);

	if(!func.isNative)
	{
		// Script function
		auto funcDef = func.scriptFunc;
		auto ar = pushAR(t);

		if(funcDef.isVararg && numParams > func.numParams)
		{
			// In this case, we move the formal parameters after the varargs and null out where the formal
			// params used to be.
			ar.base = paramSlot + numParams;
			ar.vargBase = paramSlot + func.numParams;

			checkStack(t, ar.base + funcDef.stackSize - 1);

			auto oldParams = t.stack[paramSlot .. paramSlot + func.numParams];
			t.stack[ar.base .. ar.base + func.numParams] = oldParams;
			oldParams[] = CrocValue.nullValue;

			// For nulling out the stack.
			numParams = func.numParams;
		}
		else
		{
			// In this case, everything is where it needs to be already.
			ar.base = paramSlot;
			ar.vargBase = paramSlot;

			checkStack(t, ar.base + funcDef.stackSize - 1);

			// If we have too few params, the extra param slots will be nulled out.
		}

		// Null out the stack frame after the parameters.
		t.stack[ar.base + numParams .. ar.base + funcDef.stackSize] = CrocValue.nullValue;

		// Fill in the rest of the activation record.
		ar.returnSlot = returnSlot;
		ar.func = func;
		ar.pc = funcDef.code.ptr;
		ar.numReturns = numReturns;
		ar.firstResult = 0;
		ar.numResults = 0;
		ar.proto = proto is null ? null : proto.parent;
		ar.numTailcalls = 0;
		ar.savedTop = ar.base + funcDef.stackSize;
		ar.unwindCounter = 0;
		ar.unwindReturn = null;

		// Set the stack indices.
		t.stackBase = ar.base;
		t.stackIndex = ar.savedTop;

		// Call any hook.
		mixin(
		"if(t.hooks & CrocThread.Hook.Call)
		{
			try
				callHook(t, CrocThread.Hook.Call);
		" ~ wrapEH ~ "
		}");

		return true;
	}
	else
	{
		// Native function
		t.stackIndex = paramSlot + numParams;
		checkStack(t, t.stackIndex);

		auto ar = pushAR(t);

		ar.base = paramSlot;
		ar.vargBase = paramSlot;
		ar.returnSlot = returnSlot;
		ar.func = func;
		ar.numReturns = numReturns;
		ar.firstResult = 0;
		ar.numResults = 0;
		ar.savedTop = t.stackIndex;
		ar.proto = proto is null ? null : proto.parent;
		ar.numTailcalls = 0;
		ar.unwindCounter = 0;
		ar.unwindReturn = null;

		t.stackBase = ar.base;

		uword actualReturns = void;

		mixin("try
		{
			if(t.hooks & CrocThread.Hook.Call)
				callHook(t, CrocThread.Hook.Call);

			t.nativeCallDepth++;
			scope(exit) t.nativeCallDepth--;

			auto savedState = t.state;
			t.state = CrocThread.State.Running;
			t.vm.curThread = t;
			scope(exit) t.state = savedState;

			actualReturns = func.nativeFunc(t);
		}" ~ wrapEH);

		saveResults(t, t, t.stackIndex - actualReturns, actualReturns);
		callEpilogue(t, true);
		return false;
	}
}

void callEpilogue(CrocThread* t, bool needResults)
{
	if(t.hooks & CrocThread.Hook.Ret)
		callReturnHooks(t);

	auto destSlot = t.currentAR.returnSlot;
	auto numExpRets = t.currentAR.numReturns;
	auto results = loadResults(t);

	bool isMultRet = false;

	if(numExpRets == -1)
	{
		isMultRet = true;
		numExpRets = results.length;
	}

	popAR(t);

	if(needResults)
	{
		t.numYields = results.length;

		auto stk = t.stack;

		if(numExpRets <= results.length)
			stk[destSlot .. destSlot + numExpRets] = results[0 .. numExpRets];
		else
		{
			stk[destSlot .. destSlot + results.length] = results[];
			stk[destSlot + results.length .. destSlot + numExpRets] = CrocValue.nullValue;
		}
	}
	else
		t.numYields = 0;

	if(t.arIndex == 0)
	{
		t.state = CrocThread.State.Dead;
		t.shouldHalt = false;
		t.stackIndex = destSlot + numExpRets;

		if(t is t.vm.mainThread)
			t.vm.curThread = t;
	}
	else if(needResults && (isMultRet || t.currentAR.savedTop < destSlot + numExpRets)) // last case happens in native -> native calls
		t.stackIndex = destSlot + numExpRets;
	else
		t.stackIndex = t.currentAR.savedTop;
}

void saveResults(CrocThread* t, CrocThread* from, AbsStack first, uword num)
{
	if(num == 0)
		return;

	if((t.results.length - t.resultIndex) < num)
	{
		auto newLen = t.results.length * 2;

		if(newLen - t.resultIndex < num)
			newLen = t.resultIndex + num;

		t.vm.alloc.resizeArray(t.results, newLen);
	}

	assert(t.currentAR.firstResult is 0 && t.currentAR.numResults is 0);

	auto tmp = from.stack[first .. first + num];
	t.results[t.resultIndex .. t.resultIndex + num] = tmp;
	t.currentAR.firstResult = t.resultIndex;
	t.currentAR.numResults = num;

	t.resultIndex += num;
}

CrocValue[] loadResults(CrocThread* t)
{
	auto first = t.currentAR.firstResult;
	auto num = t.currentAR.numResults;
	auto ret = t.results[first .. first + num];
	t.currentAR.firstResult = 0;
	t.currentAR.numResults = 0;
	t.resultIndex -= num;
	return ret;
}

void unwindEH(CrocThread* t)
{
	while(t.trIndex > 0 && t.currentTR.actRecord >= t.arIndex)
		popTR(t);
}

// ============================================================================
// Implementations

word toStringImpl(CrocThread* t, CrocValue v, bool raw)
{
	// ORDER CROCVALUE TYPE
	if(v.type <= CrocValue.Type.String)
	{
		char[80] buffer = void;

		switch(v.type)
		{
			case CrocValue.Type.Null:  return pushString(t, "null");
			case CrocValue.Type.Bool:  return pushString(t, v.mBool ? "true" : "false");
			case CrocValue.Type.Int:   return pushString(t, Integer.format(buffer, v.mInt));
			case CrocValue.Type.Float:
				uword pos = 0;

				auto size = t.vm.formatter.convert((char[] s)
				{
					if(pos + s.length > buffer.length)
						s.length = buffer.length - pos;

					buffer[pos .. pos + s.length] = s[];
					pos += s.length;
					return cast(uint)s.length; // the cast is there to make things work on x64 :P
				}, "{}", v.mFloat);

				return pushString(t, buffer[0 .. pos]);

			case CrocValue.Type.Char:
				auto inbuf = v.mChar;

				if(!Utf.isValid(inbuf))
					throwException(t, "Character '{:X}' is not a valid Unicode codepoint", cast(uint)inbuf);

				uint ate = 0;
				return pushString(t, Utf.toString((&inbuf)[0 .. 1], buffer, &ate));

			case CrocValue.Type.String:
				return push(t, v);

			default: assert(false);
		}
	}

	if(!raw)
	{
		CrocClass* proto;
		if(auto method = getMM(t, &v, MM.ToString, proto))
		{
			auto funcSlot = push(t, CrocValue(method));
			push(t, v);
			commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 1, proto));

			if(t.stack[t.stackIndex - 1].type != CrocValue.Type.String)
			{
				typeString(t, &t.stack[t.stackIndex - 1]);
				throwException(t, "toString was supposed to return a string, but returned a '{}'", getString(t, -1));
			}

			return stackSize(t) - 1;
		}
	}

	switch(v.type)
	{
		case CrocValue.Type.Function:
			auto f = v.mFunction;

			if(f.isNative)
				return pushFormat(t, "native {} {}", CrocValue.typeStrings[CrocValue.Type.Function], f.name.toString());
			else
			{
				auto loc = f.scriptFunc.location;
				return pushFormat(t, "script {} {}({}({}:{}))", CrocValue.typeStrings[CrocValue.Type.Function], f.name.toString(), loc.file.toString(), loc.line, loc.col);
			}

		case CrocValue.Type.Class:    return pushFormat(t, "{} {} (0x{:X8})", CrocValue.typeStrings[CrocValue.Type.Class], v.mClass.name.toString(), cast(void*)v.mClass);
		case CrocValue.Type.Instance: return pushFormat(t, "{} of {} (0x{:X8})", CrocValue.typeStrings[CrocValue.Type.Instance], v.mInstance.parent.name.toString(), cast(void*)v.mInstance);

		case CrocValue.Type.Namespace:
			if(raw)
				goto default;

			pushString(t, CrocValue.typeStrings[CrocValue.Type.Namespace]);
			pushChar(t, ' ');
			pushNamespaceNamestring(t, v.mNamespace);

			auto slot = t.stackIndex - 3;
			catImpl(t, &t.stack[slot], slot, 3);
			pop(t, 2);
			return slot - t.stackBase;

		case CrocValue.Type.FuncDef:
			auto d = v.mFuncDef;
			auto loc = d.location;
			return pushFormat(t, "{} {}({}({}:{}))", CrocValue.typeStrings[CrocValue.Type.FuncDef], d.name.toString(), loc.file.toString(), loc.line, loc.col);

		default:
			return pushFormat(t, "{} 0x{:X8}", CrocValue.typeStrings[v.type], cast(void*)v.mBaseObj);
	}
}

bool inImpl(CrocThread* t, CrocValue* item, CrocValue* container)
{
	switch(container.type)
	{
		case CrocValue.Type.String:
			if(item.type == CrocValue.Type.Char)
				return string.contains(container.mString, item.mChar);
			else if(item.type == CrocValue.Type.String)
				return string.contains(container.mString, item.mString.toString());
			else
			{
				typeString(t, item);
				throwException(t, "Can only use characters to look in strings, not '{}'", getString(t, -1));
			}

		case CrocValue.Type.Table:
			return table.contains(container.mTable, *item);

		case CrocValue.Type.Array:
			return array.contains(container.mArray, *item);

		case CrocValue.Type.Namespace:
			if(item.type != CrocValue.Type.String)
			{
				typeString(t, item);
				throwException(t, "Can only use strings to look in namespaces, not '{}'", getString(t, -1));
			}

			return namespace.contains(container.mNamespace, item.mString);

		default:
			CrocClass* proto;
			auto method = getMM(t, container, MM.In, proto);

			if(method is null)
			{
				typeString(t, container);
				throwException(t, "No implementation of {} for type '{}'", MetaNames[MM.In], getString(t, -1));
			}

			auto containersave = *container;
			auto itemsave = *item;

			auto funcSlot = push(t, CrocValue(method));
			push(t, containersave);
			push(t, itemsave);
			commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 2, proto));

			auto ret = !t.stack[t.stackIndex - 1].isFalse();
			pop(t);
			return ret;
	}
}

void idxImpl(CrocThread* t, CrocValue* dest, CrocValue* container, CrocValue* key)
{
	switch(container.type)
	{
		case CrocValue.Type.Array:
			if(key.type != CrocValue.Type.Int)
			{
				typeString(t, key);
				throwException(t, "Attempting to index an array with a '{}'", getString(t, -1));
			}

			auto index = key.mInt;
			auto arr = container.mArray;

			if(index < 0)
				index += arr.length;

			if(index < 0 || index >= arr.length)
				throwException(t, "Invalid array index {} (length is {})", key.mInt, arr.length);

			*dest = arr.toArray()[cast(uword)index];
			return;

		case CrocValue.Type.Memblock:
			if(key.type != CrocValue.Type.Int)
			{
				typeString(t, key);
				throwException(t, "Attempting to index a memblock with a '{}'", getString(t, -1));
			}

			auto index = key.mInt;
			auto mb = container.mMemblock;

			if(mb.kind.code == CrocMemblock.TypeCode.v)
				throwException(t, "Attempting to index a void memblock");

			if(index < 0)
				index += mb.itemLength;

			if(index < 0 || index >= mb.itemLength)
				throwException(t, "Invalid memblock index {} (length is {})", key.mInt, mb.itemLength);

			*dest = memblock.index(mb, cast(uword)index);
			return;

		case CrocValue.Type.String:
			if(key.type != CrocValue.Type.Int)
			{
				typeString(t, key);
				throwException(t, "Attempting to index a string with a '{}'", getString(t, -1));
			}

			auto index = key.mInt;
			auto str = container.mString;

			if(index < 0)
				index += str.cpLength;

			if(index < 0 || index >= str.cpLength)
				throwException(t, "Invalid string index {} (length is {})", key.mInt, str.cpLength);

			*dest = string.charAt(str, cast(uword)index);
			return;

		case CrocValue.Type.Table:
			return tableIdxImpl(t, dest, container, key);

		default:
			if(tryMM!(2, true)(t, MM.Index, dest, container, key))
				return;

			typeString(t, container);
			throwException(t, "Attempting to index a value of type '{}'", getString(t, -1));
	}
}

void tableIdxImpl(CrocThread* t, CrocValue* dest, CrocValue* container, CrocValue* key)
{
	auto v = table.get(container.mTable, *key);

	if(v !is null)
		*dest = *v;
	else
		*dest = CrocValue.nullValue;
}

void idxaImpl(CrocThread* t, CrocValue* container, CrocValue* key, CrocValue* value)
{
	switch(container.type)
	{
		case CrocValue.Type.Array:
			if(key.type != CrocValue.Type.Int)
			{
				typeString(t, key);
				throwException(t, "Attempting to index-assign an array with a '{}'", getString(t, -1));
			}

			auto index = key.mInt;
			auto arr = container.mArray;

			if(index < 0)
				index += arr.length;

			if(index < 0 || index >= arr.length)
				throwException(t, "Invalid array index {} (length is {})", key.mInt, arr.length);

			arr.toArray()[cast(uword)index] = *value;
			return;

		case CrocValue.Type.Memblock:
			if(key.type != CrocValue.Type.Int)
			{
				typeString(t, key);
				throwException(t, "Attempting to index-assign a memblock with a '{}'", getString(t, -1));
			}

			auto index = key.mInt;
			auto mb = container.mMemblock;

			if(mb.kind.code == CrocMemblock.TypeCode.v)
				throwException(t, "Attempting to index-assign a void memblock");

			if(index < 0)
				index += mb.itemLength;

			if(index < 0 || index >= mb.itemLength)
				throwException(t, "Invalid memblock index {} (length is {})", key.mInt, mb.itemLength);

			CrocValue src = void;

			// ORDER MEMBLOCK TYPE
			if(mb.kind.code <= CrocMemblock.TypeCode.u64)
			{
				if(value.type != CrocValue.Type.Int)
				{
					typeString(t, value);
					throwException(t, "Attempting to index-assign a value of type '{}' into a {} memblock", getString(t, -1), mb.kind.name);
				}

				src = *value;
			}
			else
			{
				if(value.type == CrocValue.Type.Float)
					src = *value;
				else if(value.type == CrocValue.Type.Int)
					src = cast(crocfloat)value.mInt;
				else
				{
					typeString(t, value);
					throwException(t, "Attempting to index-assign a value of type '{}' into a {} memblock", getString(t, -1), mb.kind.name);
				}
			}

			memblock.indexAssign(mb, cast(uword)index, src);
			return;

		case CrocValue.Type.Table:
			return tableIdxaImpl(t, container, key, value);

		default:
			if(tryMM!(3, false)(t, MM.IndexAssign, container, key, value))
				return;

			typeString(t, container);
			throwException(t, "Attempting to index-assign a value of type '{}'", getString(t, -1));
	}
}

void tableIdxaImpl(CrocThread* t, CrocValue* container, CrocValue* key, CrocValue* value)
{
	if(key.type == CrocValue.Type.Null)
		throwException(t, "Attempting to index-assign a table with a key of type 'null'");

	// If the key or value is a null weakref, just remove the key-value pair from the table entirely
	if((value.type == CrocValue.Type.WeakRef && value.mWeakRef.obj is null) ||
		(key.type == CrocValue.Type.WeakRef && key.mWeakRef.obj is null))
	{
		table.remove(container.mTable, *key);
		return;
	}

	auto v = table.get(container.mTable, *key);

	if(v !is null)
	{
		if(value.type == CrocValue.Type.Null)
			table.remove(container.mTable, *key);
		else
			*v = *value;
	}
	else if(value.type != CrocValue.Type.Null)
		table.set(t.vm.alloc, container.mTable, *key, *value);

	// otherwise, do nothing (val is null and it doesn't exist)
}

word commonField(CrocThread* t, AbsStack container, bool raw)
{
	auto slot = t.stackIndex - 1;
	fieldImpl(t, &t.stack[slot], &t.stack[container], t.stack[slot].mString, raw);
	return stackSize(t) - 1;
}

void commonFielda(CrocThread* t, AbsStack container, bool raw)
{
	auto slot = t.stackIndex - 2;
	fieldaImpl(t, &t.stack[container], t.stack[slot].mString, &t.stack[slot + 1], raw);
	pop(t, 2);
}

void fieldImpl(CrocThread* t, CrocValue* dest, CrocValue* container, CrocString* name, bool raw)
{
	switch(container.type)
	{
		case CrocValue.Type.Table:
			// This is right, tables do not distinguish between field access and indexing.
			return tableIdxImpl(t, dest, container, &CrocValue(name));

		case CrocValue.Type.Class:
			auto v = classobj.getField(container.mClass, name);

			if(v is null)
			{
				typeString(t, container);
				throwException(t, "Attempting to access nonexistent field '{}' from '{}'", name.toString(), getString(t, -1));
			}

			return *dest = *v;

		case CrocValue.Type.Instance:
			auto v = instance.getField(container.mInstance, name);

			if(v is null)
			{
				if(!raw && tryMM!(2, true)(t, MM.Field, dest, container, &CrocValue(name)))
					return;

				typeString(t, container);
				throwException(t, "Attempting to access nonexistent field '{}' from '{}'", name.toString(), getString(t, -1));
			}

			return *dest = *v;


		case CrocValue.Type.Namespace:
			auto v = namespace.get(container.mNamespace, name);

			if(v is null)
			{
				toStringImpl(t, *container, false);
				throwException(t, "Attempting to access nonexistent field '{}' from '{}'", name.toString(), getString(t, -1));
			}

			return *dest = *v;

		default:
			if(!raw && tryMM!(2, true)(t, MM.Field, dest, container, &CrocValue(name)))
				return;

			typeString(t, container);
			throwException(t, "Attempting to access field '{}' from a value of type '{}'", name.toString(), getString(t, -1));
	}
}

void fieldaImpl(CrocThread* t, CrocValue* container, CrocString* name, CrocValue* value, bool raw)
{
	switch(container.type)
	{
		case CrocValue.Type.Table:
			// This is right, tables do not distinguish between field access and indexing.
			return tableIdxaImpl(t, container, &CrocValue(name), value);

		case CrocValue.Type.Class:
			return classobj.setField(t.vm.alloc, container.mClass, name, value);

		case CrocValue.Type.Instance:
			auto i = container.mInstance;

			CrocValue owner;
			auto field = instance.getField(i, name, owner);

			if(field is null)
			{
				if(!raw && tryMM!(3, false)(t, MM.FieldAssign, container, &CrocValue(name), value))
					return;
				else
					instance.setField(t.vm.alloc, i, name, value);
			}
			else if(owner != CrocValue(i))
				instance.setField(t.vm.alloc, i, name, value);
			else
				*field = *value;
			return;

		case CrocValue.Type.Namespace:
			return namespace.set(t.vm.alloc, container.mNamespace, name, value);

		default:
			if(!raw && tryMM!(3, false)(t, MM.FieldAssign, container, &CrocValue(name), value))
				return;

			typeString(t, container);
			throwException(t, "Attempting to assign field '{}' into a value of type '{}'", name.toString(), getString(t, -1));
	}
}

crocint compareImpl(CrocThread* t, CrocValue* a, CrocValue* b)
{
	if(a.type == CrocValue.Type.Int)
	{
		if(b.type == CrocValue.Type.Int)
			return Compare3(a.mInt, b.mInt);
		else if(b.type == CrocValue.Type.Float)
			return Compare3(cast(crocfloat)a.mInt, b.mFloat);
	}
	else if(a.type == CrocValue.Type.Float)
	{
		if(b.type == CrocValue.Type.Int)
			return Compare3(a.mFloat, cast(crocfloat)b.mInt);
		else if(b.type == CrocValue.Type.Float)
			return Compare3(a.mFloat, b.mFloat);
	}

	if(a.type == b.type)
	{
		switch(a.type)
		{
			case CrocValue.Type.Null:   return 0;
			case CrocValue.Type.Bool:   return (cast(crocint)a.mBool - cast(crocint)b.mBool);
			case CrocValue.Type.Char:   return Compare3(a.mChar, b.mChar);
			case CrocValue.Type.String: return (a.mString is b.mString) ? 0 : string.compare(a.mString, b.mString);
			default: break;
		}
	}

	CrocClass* proto;
	if(a.type == b.type || b.type != CrocValue.Type.Instance)
	{
		if(auto method = getMM(t, a, MM.Cmp, proto))
			return commonCompare(t, method, a, b, proto);
		else if(auto method = getMM(t, b, MM.Cmp, proto))
			return -commonCompare(t, method, b, a, proto);
	}
	else
	{
		if(auto method = getMM(t, b, MM.Cmp, proto))
			return -commonCompare(t, method, b, a, proto);
		else if(auto method = getMM(t, a, MM.Cmp, proto))
			return commonCompare(t, method, a, b, proto);
	}

	auto bsave = *b;
	typeString(t, a);
	typeString(t, &bsave);
	throwException(t, "Can't compare types '{}' and '{}'", getString(t, -2), getString(t, -1));
	assert(false);
}

crocint commonCompare(CrocThread* t, CrocFunction* method, CrocValue* a, CrocValue* b, CrocClass* proto)
{
	auto asave = *a;
	auto bsave = *b;

	auto funcReg = push(t, CrocValue(method));
	push(t, asave);
	push(t, bsave);
	commonCall(t, funcReg + t.stackBase, 1, callPrologue(t, funcReg + t.stackBase, 1, 2, proto));

	auto ret = *getValue(t, -1);
	pop(t);

	if(ret.type != CrocValue.Type.Int)
	{
		typeString(t, &ret);
		throwException(t, "{} is expected to return an int, but '{}' was returned instead", MetaNames[MM.Cmp], getString(t, -1));
	}

	return ret.mInt;
}

bool switchCmpImpl(CrocThread* t, CrocValue* a, CrocValue* b)
{
	if(a.type != b.type)
		return false;

	if(a.opEquals(*b))
		return true;

	CrocClass* proto;

	if(a.type == CrocValue.Type.Instance)
	{
		if(auto method = getMM(t, a, MM.Cmp, proto))
			return commonCompare(t, method, a, b, proto) == 0;
		else if(auto method = getMM(t, b, MM.Cmp, proto))
			return commonCompare(t, method, b, a, proto) == 0;
	}

	return false;
}

bool equalsImpl(CrocThread* t, CrocValue* a, CrocValue* b)
{
	if(a.type == CrocValue.Type.Int)
	{
		if(b.type == CrocValue.Type.Int)
			return a.mInt == b.mInt;
		else if(b.type == CrocValue.Type.Float)
			return (cast(crocfloat)a.mInt) == b.mFloat;
	}
	else if(a.type == CrocValue.Type.Float)
	{
		if(b.type == CrocValue.Type.Int)
			return a.mFloat == (cast(crocfloat)b.mInt);
		else if(b.type == CrocValue.Type.Float)
			return a.mFloat == b.mFloat;
	}

	if(a.type == b.type)
	{
		switch(a.type)
		{
			case CrocValue.Type.Null:   return true;
			case CrocValue.Type.Bool:   return a.mBool == b.mBool;
			case CrocValue.Type.Char:   return a.mChar == b.mChar;
			case CrocValue.Type.String: return a.mString is b.mString;
			default: break;
		}
	}

	CrocClass* proto;
	if(a.type == b.type || b.type != CrocValue.Type.Instance)
	{
		if(auto method = getMM(t, a, MM.Equals, proto))
			return commonEquals(t, method, a, b, proto);
		else if(auto method = getMM(t, b, MM.Equals, proto))
			return commonEquals(t, method, b, a, proto);
	}
	else
	{
		if(auto method = getMM(t, b, MM.Equals, proto))
			return commonEquals(t, method, b, a, proto);
		else if(auto method = getMM(t, a, MM.Equals, proto))
			return commonEquals(t, method, a, b, proto);
	}

	auto bsave = *b;
	typeString(t, a);
	typeString(t, &bsave);
	throwException(t, "Can't compare types '{}' and '{}' for equality", getString(t, -2), getString(t, -1));
	assert(false);
}

bool commonEquals(CrocThread* t, CrocFunction* method, CrocValue* a, CrocValue* b, CrocClass* proto)
{
	auto asave = *a;
	auto bsave = *b;

	auto funcReg = push(t, CrocValue(method));
	push(t, asave);
	push(t, bsave);
	commonCall(t, funcReg + t.stackBase, 1, callPrologue(t, funcReg + t.stackBase, 1, 2, proto));

	auto ret = *getValue(t, -1);
	pop(t);

	if(ret.type != CrocValue.Type.Bool)
	{
		typeString(t, &ret);
		throwException(t, "{} is expected to return a bool, but '{}' was returned instead", MetaNames[MM.Equals], getString(t, -1));
	}

	return ret.mBool;
}

void lenImpl(CrocThread* t, CrocValue* dest, CrocValue* src)
{
	switch(src.type)
	{
		case CrocValue.Type.String:    return *dest = cast(crocint)src.mString.cpLength;
		case CrocValue.Type.Table:     return *dest = cast(crocint)table.length(src.mTable);
		case CrocValue.Type.Array:     return *dest = cast(crocint)src.mArray.length;
		case CrocValue.Type.Memblock:  return *dest = cast(crocint)src.mMemblock.itemLength;
		case CrocValue.Type.Namespace: return *dest = cast(crocint)namespace.length(src.mNamespace);

		default:
			if(tryMM!(1, true)(t, MM.Length, dest, src))
				return;

			typeString(t, src);
			throwException(t, "Can't get the length of a '{}'", getString(t, -1));
	}
}

void lenaImpl(CrocThread* t, CrocValue* dest, CrocValue* len)
{
	switch(dest.type)
	{
		case CrocValue.Type.Array:
			if(len.type != CrocValue.Type.Int)
			{
				typeString(t, len);
				throwException(t, "Attempting to set the length of an array using a length of type '{}'", getString(t, -1));
			}

			auto l = len.mInt;

			if(l < 0 || l > uword.max)
				throwException(t, "Invalid length ({})", l);

			return array.resize(t.vm.alloc, dest.mArray, cast(uword)l);

		case CrocValue.Type.Memblock:
			if(len.type != CrocValue.Type.Int)
			{
				typeString(t, len);
				throwException(t, "Attempting to set the length of a memblock using a length of type '{}'", getString(t, -1));
			}
			
			auto mb = dest.mMemblock;

			if(!mb.ownData)
				throwException(t, "Attempting to resize a memblock which does not own its data");

			if(mb.kind.code == CrocMemblock.TypeCode.v)
				throwException(t, "Attempting to resize a void memblock");

			auto l = len.mInt;

			if(l < 0 || l > uword.max)
				throwException(t, "Invalid length ({})", l);

			return memblock.resize(t.vm.alloc, mb, cast(uword)l);

		default:
			if(tryMM!(2, false)(t, MM.LengthAssign, dest, len))
				return;

			typeString(t, dest);
			throwException(t, "Can't set the length of a '{}'", getString(t, -1));
	}
}

void sliceImpl(CrocThread* t, CrocValue* dest, CrocValue* src, CrocValue* lo, CrocValue* hi)
{
	switch(src.type)
	{
		case CrocValue.Type.Array:
			auto arr = src.mArray;
			crocint loIndex = void;
			crocint hiIndex = void;

			if(lo.type == CrocValue.Type.Null && hi.type == CrocValue.Type.Null)
				return *dest = *src;

			if(!correctIndices(loIndex, hiIndex, lo, hi, arr.length))
			{
				auto hisave = *hi;
				typeString(t, lo);
				typeString(t, &hisave);
				throwException(t, "Attempting to slice an array with indices of type '{}' and '{}'", getString(t, -2), getString(t, -1));
			}

			if(!validIndices(loIndex, hiIndex, arr.length))
				throwException(t, "Invalid slice indices [{} .. {}] (array length = {})", loIndex, hiIndex, arr.length);

			return *dest = array.slice(t.vm.alloc, arr, cast(uword)loIndex, cast(uword)hiIndex);

		case CrocValue.Type.Memblock:
			auto mb = src.mMemblock;
			crocint loIndex = void;
			crocint hiIndex = void;

			if(lo.type == CrocValue.Type.Null && hi.type == CrocValue.Type.Null)
				return *dest = *src;

			if(!correctIndices(loIndex, hiIndex, lo, hi, mb.itemLength))
			{
				auto hisave = *hi;
				typeString(t, lo);
				typeString(t, &hisave);
				throwException(t, "Attempting to slice a memblock with indices of type '{}' and '{}'", getString(t, -2), getString(t, -1));
			}

			if(!validIndices(loIndex, hiIndex, mb.itemLength))
				throwException(t, "Invalid slice indices [{} .. {}] (memblock length = {})", loIndex, hiIndex, mb.itemLength);

			return *dest = memblock.slice(t.vm.alloc, mb, cast(uword)loIndex, cast(uword)hiIndex);

		case CrocValue.Type.String:
			auto str = src.mString;
			crocint loIndex = void;
			crocint hiIndex = void;

			if(lo.type == CrocValue.Type.Null && hi.type == CrocValue.Type.Null)
				return *dest = *src;

			if(!correctIndices(loIndex, hiIndex, lo, hi, str.cpLength))
			{
				auto hisave = *hi;
				typeString(t, lo);
				typeString(t, &hisave);
				throwException(t, "Attempting to slice a string with indices of type '{}' and '{}'", getString(t, -2), getString(t, -1));
			}

			if(!validIndices(loIndex, hiIndex, str.cpLength))
				throwException(t, "Invalid slice indices [{} .. {}] (string length = {})", loIndex, hiIndex, str.cpLength);

			return *dest = string.slice(t, str, cast(uword)loIndex, cast(uword)hiIndex);

		default:
			if(tryMM!(3, true)(t, MM.Slice, dest, src, lo, hi))
				return;

			typeString(t, src);
			throwException(t, "Attempting to slice a value of type '{}'", getString(t, -1));
	}
}

void sliceaImpl(CrocThread* t, CrocValue* container, CrocValue* lo, CrocValue* hi, CrocValue* value)
{
	switch(container.type)
	{
		case CrocValue.Type.Array:
			auto arr = container.mArray;
			crocint loIndex = void;
			crocint hiIndex = void;

			if(!correctIndices(loIndex, hiIndex, lo, hi, arr.length))
			{
				auto hisave = *hi;
				typeString(t, lo);
				typeString(t, &hisave);
				throwException(t, "Attempting to slice-assign an array with indices of type '{}' and '{}'", getString(t, -2), getString(t, -1));
			}

			if(!validIndices(loIndex, hiIndex, arr.length))
				throwException(t, "Invalid slice-assign indices [{} .. {}] (array length = {})", loIndex, hiIndex, arr.length);

			if(value.type == CrocValue.Type.Array)
			{
				if((hiIndex - loIndex) != value.mArray.length)
					throwException(t, "Array slice-assign lengths do not match (destination is {}, source is {})", hiIndex - loIndex, value.mArray.length);

				return array.sliceAssign(arr, cast(uword)loIndex, cast(uword)hiIndex, value.mArray);
			}
			else
			{
				typeString(t, value);
				throwException(t, "Attempting to slice-assign a value of type '{}' into an array", getString(t, -1));
			}

		default:
			if(tryMM!(4, false)(t, MM.SliceAssign, container, lo, hi, value))
				return;

			typeString(t, container);
			throwException(t, "Attempting to slice-assign a value of type '{}'", getString(t, -1));
	}
}

void binOpImpl(CrocThread* t, MM operation, CrocValue* dest, CrocValue* RS, CrocValue* RT)
{
	crocfloat f1 = void;
	crocfloat f2 = void;

	if(RS.type == CrocValue.Type.Int)
	{
		if(RT.type == CrocValue.Type.Int)
		{
			auto i1 = RS.mInt;
			auto i2 = RT.mInt;

			switch(operation)
			{
				case MM.Add: return *dest = i1 + i2;
				case MM.Sub: return *dest = i1 - i2;
				case MM.Mul: return *dest = i1 * i2;

				case MM.Div:
					if(i2 == 0)
						throwException(t, "Integer divide by zero");

					return *dest = i1 / i2;

				case MM.Mod:
					if(i2 == 0)
						throwException(t, "Integer modulo by zero");

					return *dest = i1 % i2;

				default:
					assert(false);
			}
		}
		else if(RT.type == CrocValue.Type.Float)
		{
			f1 = RS.mInt;
			f2 = RT.mFloat;
			goto _float;
		}
	}
	else if(RS.type == CrocValue.Type.Float)
	{
		if(RT.type == CrocValue.Type.Int)
		{
			f1 = RS.mFloat;
			f2 = RT.mInt;
			goto _float;
		}
		else if(RT.type == CrocValue.Type.Float)
		{
			f1 = RS.mFloat;
			f2 = RT.mFloat;

			_float:
			switch(operation)
			{
				case MM.Add: return *dest = f1 + f2;
				case MM.Sub: return *dest = f1 - f2;
				case MM.Mul: return *dest = f1 * f2;
				case MM.Div: return *dest = f1 / f2;
				case MM.Mod: return *dest = f1 % f2;

				default:
					assert(false);
			}
		}
	}

	return commonBinOpMM(t, operation, dest, RS, RT);
}

void commonBinOpMM(CrocThread* t, MM operation, CrocValue* dest, CrocValue* RS, CrocValue* RT)
{
	bool swap = false;
	CrocClass* proto;

	auto method = getMM(t, RS, operation, proto);

	if(method is null)
	{
		method = getMM(t, RT, MMRev[operation], proto);

		if(method !is null)
			swap = true;
		else
		{
			if(!MMCommutative[operation])
			{
				auto RTsave = *RT;
				typeString(t, RS);
				typeString(t, &RTsave);
				throwException(t, "Cannot perform the arithmetic operation '{}' on a '{}' and a '{}'", MetaNames[operation], getString(t, -2), getString(t, -1));
			}

			method = getMM(t, RS, MMRev[operation], proto);

			if(method is null)
			{
				method = getMM(t, RT, operation, proto);

				if(method is null)
				{
					auto RTsave = *RT;
					typeString(t, RS);
					typeString(t, &RTsave);
					throwException(t, "Cannot perform the arithmetic operation '{}' on a '{}' and a '{}'", MetaNames[operation], getString(t, -2), getString(t, -1));
				}

				swap = true;
			}
		}
	}

	bool shouldLoad = void;
	savePtr(t, dest, shouldLoad);

	auto RSsave = *RS;
	auto RTsave = *RT;

	auto funcSlot = push(t, CrocValue(method));

	if(swap)
	{
		push(t, RTsave);
		push(t, RSsave);
	}
	else
	{
		push(t, RSsave);
		push(t, RTsave);
	}

	commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 2, proto));

	if(shouldLoad)
		loadPtr(t, dest);

	*dest = t.stack[t.stackIndex - 1];
	pop(t);
}

void reflBinOpImpl(CrocThread* t, MM operation, CrocValue* dest, CrocValue* src)
{
	crocfloat f1 = void;
	crocfloat f2 = void;

	if(dest.type == CrocValue.Type.Int)
	{
		if(src.type == CrocValue.Type.Int)
		{
			auto i2 = src.mInt;

			switch(operation)
			{
				case MM.AddEq: return dest.mInt += i2;
				case MM.SubEq: return dest.mInt -= i2;
				case MM.MulEq: return dest.mInt *= i2;

				case MM.DivEq:
					if(i2 == 0)
						throwException(t, "Integer divide by zero");

					return dest.mInt /= i2;

				case MM.ModEq:
					if(i2 == 0)
						throwException(t, "Integer modulo by zero");

					return dest.mInt %= i2;

				default: assert(false);
			}
		}
		else if(src.type == CrocValue.Type.Float)
		{
			f1 = dest.mInt;
			f2 = src.mFloat;
			goto _float;
		}
	}
	else if(dest.type == CrocValue.Type.Float)
	{
		if(src.type == CrocValue.Type.Int)
		{
			f1 = dest.mFloat;
			f2 = src.mInt;
			goto _float;
		}
		else if(src.type == CrocValue.Type.Float)
		{
			f1 = dest.mFloat;
			f2 = src.mFloat;

			_float:
			dest.type = CrocValue.Type.Float;

			switch(operation)
			{
				case MM.AddEq: return dest.mFloat = f1 + f2;
				case MM.SubEq: return dest.mFloat = f1 - f2;
				case MM.MulEq: return dest.mFloat = f1 * f2;
				case MM.DivEq: return dest.mFloat = f1 / f2;
				case MM.ModEq: return dest.mFloat = f1 % f2;

				default: assert(false);
			}
		}
	}
	
	if(tryMM!(2, false)(t, operation, dest, src))
		return;

	auto srcsave = *src;
	typeString(t, dest);
	typeString(t, &srcsave);
	throwException(t, "Cannot perform the reflexive arithmetic operation '{}' on a '{}' and a '{}'", MetaNames[operation], getString(t, -2), getString(t, -1));
}

void negImpl(CrocThread* t, CrocValue* dest, CrocValue* src)
{
	if(src.type == CrocValue.Type.Int)
		return *dest = -src.mInt;
	else if(src.type == CrocValue.Type.Float)
		return *dest = -src.mFloat;
		
	if(tryMM!(1, true)(t, MM.Neg, dest, src))
		return;

	typeString(t, src);
	throwException(t, "Cannot perform negation on a '{}'", getString(t, -1));
}

void binaryBinOpImpl(CrocThread* t, MM operation, CrocValue* dest, CrocValue* RS, CrocValue* RT)
{
	if(RS.type == CrocValue.Type.Int && RT.type == CrocValue.Type.Int)
	{
		switch(operation)
		{
			case MM.And:  return *dest = RS.mInt & RT.mInt;
			case MM.Or:   return *dest = RS.mInt | RT.mInt;
			case MM.Xor:  return *dest = RS.mInt ^ RT.mInt;
			case MM.Shl:  return *dest = RS.mInt << RT.mInt;
			case MM.Shr:  return *dest = RS.mInt >> RT.mInt;
			case MM.UShr: return *dest = RS.mInt >>> RT.mInt;
			default: assert(false);
		}
	}

	return commonBinOpMM(t, operation, dest, RS, RT);
}

void reflBinaryBinOpImpl(CrocThread* t, MM operation, CrocValue* dest, CrocValue* src)
{
	if(dest.type == CrocValue.Type.Int && src.type == CrocValue.Type.Int)
	{
		switch(operation)
		{
			case MM.AndEq:  return dest.mInt &= src.mInt;
			case MM.OrEq:   return dest.mInt |= src.mInt;
			case MM.XorEq:  return dest.mInt ^= src.mInt;
			case MM.ShlEq:  return dest.mInt <<= src.mInt;
			case MM.ShrEq:  return dest.mInt >>= src.mInt;
			case MM.UShrEq: return dest.mInt >>>= src.mInt;
			default: assert(false);
		}
	}

	if(tryMM!(2, false)(t, operation, dest, src))
		return;

	auto srcsave = *src;
	typeString(t, dest);
	typeString(t, &srcsave);
	throwException(t, "Cannot perform reflexive binary operation '{}' on a '{}' and a '{}'", MetaNames[operation], getString(t, -2), getString(t, -1));
}

void comImpl(CrocThread* t, CrocValue* dest, CrocValue* src)
{
	if(src.type == CrocValue.Type.Int)
		return *dest = ~src.mInt;

	if(tryMM!(1, true)(t, MM.Com, dest, src))
		return;

	typeString(t, src);
	throwException(t, "Cannot perform bitwise complement on a '{}'", getString(t, -1));
}

void incImpl(CrocThread* t, CrocValue* dest)
{
	if(dest.type == CrocValue.Type.Int)
		dest.mInt++;
	else if(dest.type == CrocValue.Type.Float)
		dest.mFloat++;
	else
	{
		if(tryMM!(1, false)(t, MM.Inc, dest))
			return;

		typeString(t, dest);
		throwException(t, "Cannot increment a '{}'", getString(t, -1));
	}
}

void decImpl(CrocThread* t, CrocValue* dest)
{
	if(dest.type == CrocValue.Type.Int)
		dest.mInt--;
	else if(dest.type == CrocValue.Type.Float)
		dest.mFloat--;
	else
	{
		if(tryMM!(1, false)(t, MM.Dec, dest))
			return;

		typeString(t, dest);
		throwException(t, "Cannot decrement a '{}'", getString(t, -1));
	}
}

void catImpl(CrocThread* t, CrocValue* dest, AbsStack firstSlot, uword num)
{
	auto slot = firstSlot;
	auto endSlot = slot + num;
	auto endSlotm1 = endSlot - 1;
	auto stack = t.stack;

	bool shouldLoad = void;
	savePtr(t, dest, shouldLoad);

	while(slot < endSlotm1)
	{
		CrocFunction* method = null;
		CrocClass* proto = null;
		bool swap = false;

		switch(stack[slot].type)
		{
			case CrocValue.Type.String, CrocValue.Type.Char:
				uword len = 0;
				uword idx = slot;

				for(; idx < endSlot; idx++)
				{
					if(stack[idx].type == CrocValue.Type.String)
						len += stack[idx].mString.length;
					else if(stack[idx].type == CrocValue.Type.Char)
					{
						if(!Utf.isValid(stack[idx].mChar))
							throwException(t, "Attempting to concatenate an invalid character (\\U{:x8})", cast(uint)stack[idx].mChar);

						len += charLen(stack[idx].mChar);
					}
					else
						break;
				}

				if(idx > (slot + 1))
				{
					stringConcat(t, stack[slot], stack[slot + 1 .. idx], len);
					slot = idx - 1;
				}

				if(slot == endSlotm1)
					break; // to exit function

				if(stack[slot + 1].type == CrocValue.Type.Array)
					goto array;
				else if(stack[slot + 1].type == CrocValue.Type.Instance)
					goto cat_r;
				else
				{
					typeString(t, &stack[slot + 1]);
					throwException(t, "Can't concatenate 'string|char' and '{}'", getString(t, -1));
				}

			case CrocValue.Type.Array:
				array:
				uword idx = slot + 1;
				uword len = stack[slot].type == CrocValue.Type.Array ? stack[slot].mArray.length : 1;

				for(; idx < endSlot; idx++)
				{
					if(stack[idx].type == CrocValue.Type.Array)
						len += stack[idx].mArray.length;
					else if(stack[idx].type == CrocValue.Type.Instance)
					{
						method = getMM(t, &stack[idx], MM.Cat_r, proto);

						if(method is null)
							len++;
						else
							break;
					}
					else
						len++;
				}

				if(idx > (slot + 1))
				{
					arrayConcat(t, stack[slot .. idx], len);
					slot = idx - 1;
				}

				if(slot == endSlotm1)
					break; // to exit function

				assert(method !is null);
				goto cat_r;

			case CrocValue.Type.Instance:
				if(stack[slot + 1].type == CrocValue.Type.Array)
				{
					method = getMM(t, &stack[slot], MM.Cat, proto);

					if(method is null)
						goto array;
				}

				if(method is null)
				{
					method = getMM(t, &stack[slot], MM.Cat, proto);

					if(method is null)
						goto cat_r;
				}

				goto common_mm;

			default:
				// Basic
				if(stack[slot + 1].type == CrocValue.Type.Array)
					goto array;
				else
				{
					method = getMM(t, &stack[slot], MM.Cat, proto);

					if(method is null)
						goto cat_r;
					else
						goto common_mm;
				}

			cat_r:
				if(method is null)
				{
					method = getMM(t, &stack[slot + 1], MM.Cat_r, proto);

					if(method is null)
						goto error;
				}

				swap = true;
				// fall through

			common_mm:
				assert(method !is null);

				auto src1save = stack[slot];
				auto src2save = stack[slot + 1];

				auto funcSlot = push(t, CrocValue(method));

				if(swap)
				{
					push(t, src2save);
					push(t, src1save);
				}
				else
				{
					push(t, src1save);
					push(t, src2save);
				}

				commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 2, proto));

				// stack might have changed.
				stack = t.stack;

				slot++;
				stack[slot] = stack[t.stackIndex - 1];
				pop(t);
				continue;

			error:
				typeString(t, &t.stack[slot]);
				typeString(t, &stack[slot + 1]);
				throwException(t, "Can't concatenate '{}' and '{}'", getString(t, -2), getString(t, -1));
		}

		break;
	}

	if(shouldLoad)
		loadPtr(t, dest);

	*dest = stack[slot];
}

void arrayConcat(CrocThread* t, CrocValue[] vals, uword len)
{
	if(vals.length == 2 && vals[0].type == CrocValue.Type.Array)
	{
		if(vals[1].type == CrocValue.Type.Array)
			return vals[1] = array.cat(t.vm.alloc, vals[0].mArray, vals[1].mArray);
		else
			return vals[1] = array.cat(t.vm.alloc, vals[0].mArray, &vals[1]);
	}

	auto ret = array.create(t.vm.alloc, len);
	auto retArr = ret.toArray();

	uword i = 0;

	foreach(ref v; vals)
	{
		if(v.type == CrocValue.Type.Array)
		{
			auto a = v.mArray;

			retArr[i .. i + a.length] = a.toArray()[];
			i += a.length;
		}
		else
		{
			retArr[i] = v;
			i++;
		}
	}

	vals[$ - 1] = ret;
}

void stringConcat(CrocThread* t, CrocValue first, CrocValue[] vals, uword len)
{
	auto tmpBuffer = t.vm.alloc.allocArray!(char)(len);
	scope(exit) t.vm.alloc.freeArray(tmpBuffer);
	uword i = 0;

	void add(ref CrocValue v)
	{
		char[] s = void;

		if(v.type == CrocValue.Type.String)
			s = v.mString.toString();
		else
		{
			dchar[1] inbuf = void;
			inbuf[0] = v.mChar;
			char[4] outbuf = void;
			uint ate = 0;
			s = Utf.toString(inbuf, outbuf, &ate);
		}

		tmpBuffer[i .. i + s.length] = s[];
		i += s.length;
	}

	add(first);

	foreach(ref v; vals)
		add(v);

	vals[$ - 1] = createString(t, tmpBuffer);
}

void catEqImpl(CrocThread* t, CrocValue* dest, AbsStack firstSlot, uword num)
{
	assert(num >= 1);

	auto slot = firstSlot;
	auto endSlot = slot + num;
	auto stack = t.stack;

	switch(dest.type)
	{
		case CrocValue.Type.String, CrocValue.Type.Char:
			uword len = void;

			if(dest.type == CrocValue.Type.Char)
			{
				if(!Utf.isValid(dest.mChar))
					throwException(t, "Attempting to concatenate an invalid character (\\U{:x8})", dest.mChar);

				len = charLen(dest.mChar);
			}
			else
				len = dest.mString.length;

			for(uword idx = slot; idx < endSlot; idx++)
			{
				if(stack[idx].type == CrocValue.Type.String)
					len += stack[idx].mString.length;
				else if(stack[idx].type == CrocValue.Type.Char)
				{
					if(!Utf.isValid(stack[idx].mChar))
						throwException(t, "Attempting to concatenate an invalid character (\\U{:x8})", cast(uint)stack[idx].mChar);

					len += charLen(stack[idx].mChar);
				}
				else
				{
					typeString(t, &stack[idx]);
					throwException(t, "Can't append a '{}' to a 'string/char'", getString(t, -1));
				}
			}

			auto first = *dest;
			bool shouldLoad = void;
			savePtr(t, dest, shouldLoad);

			stringConcat(t, first, stack[slot .. endSlot], len);

			if(shouldLoad)
				loadPtr(t, dest);

			*dest = stack[endSlot - 1];
			return;

		case CrocValue.Type.Array:
			return arrayAppend(t, dest.mArray, stack[slot .. endSlot]);

		default:
			CrocClass* proto;
			auto method = getMM(t, dest, MM.CatEq, proto);

			if(method is null)
			{
				typeString(t, dest);
				throwException(t, "Can't append to a value of type '{}'", getString(t, -1));
			}

			bool shouldLoad = void;
			savePtr(t, dest, shouldLoad);

			checkStack(t, t.stackIndex);

			if(shouldLoad)
				loadPtr(t, dest);

			for(auto i = t.stackIndex; i > firstSlot; i--)
				t.stack[i] = t.stack[i - 1];

			t.stack[firstSlot] = *dest;

			t.nativeCallDepth++;
			scope(exit) t.nativeCallDepth--;

			if(callPrologue2(t, method, firstSlot, 0, firstSlot, num + 1, proto))
				execute(t);
			return;
	}
}

void arrayAppend(CrocThread* t, CrocArray* a, CrocValue[] vals)
{
	uword len = a.length;

	foreach(ref val; vals)
	{
		if(val.type == CrocValue.Type.Array)
			len += val.mArray.length;
		else
			len++;
	}

	uword i = a.length;
	array.resize(t.vm.alloc, a, len);

	foreach(ref v; vals)
	{
		if(v.type == CrocValue.Type.Array)
		{
			auto arr = v.mArray;
			a.toArray()[i .. i + arr.length] = arr.toArray()[];
			i += arr.length;
		}
		else
		{
			a.toArray()[i] = v;
			i++;
		}
	}
}

void throwImpl(CrocThread* t, CrocValue ex, bool rethrowing = false)
{
	if(!rethrowing)
	{
		pushDebugLocStr(t, getDebugLoc(t));
		pushString(t, ": ");

		auto size = stackSize(t);

		try
			toStringImpl(t, ex, false);
		catch(CrocException e)
		{
			catchException(t);
			setStackSize(t, size);
			toStringImpl(t, ex, true);
		}

		auto slot = t.stackIndex - 3;
		catImpl(t, &t.stack[slot], slot, 3);

		t.vm.alloc.resizeArray(t.vm.traceback, 0);

		// dup'ing since we're removing the only Croc reference and handing it off to D
		t.vm.exMsg = getString(t, -3).dup;
		pop(t, 3);
	}

	t.vm.exception = ex;
	t.vm.isThrowing = true;
	throw new CrocException(t.vm.exMsg);
}

bool asImpl(CrocThread* t, CrocValue* o, CrocValue* p)
{
	if(p.type != CrocValue.Type.Class)
	{
		typeString(t, p);
		throwException(t, "Attempting to use 'as' with a '{}' instead of a 'class' as the type", getString(t, -1));
	}

	return o.type == CrocValue.Type.Instance && instance.derivesFrom(o.mInstance, p.mClass);
}

CrocValue superOfImpl(CrocThread* t, CrocValue* v)
{
	if(v.type == CrocValue.Type.Class)
	{
		if(auto p = v.mClass.parent)
			return CrocValue(p);
		else
			return CrocValue.nullValue;
	}
	else if(v.type == CrocValue.Type.Instance)
		return CrocValue(v.mInstance.parent);
	else if(v.type == CrocValue.Type.Namespace)
	{
		if(auto p = v.mNamespace.parent)
			return CrocValue(p);
		else
			return CrocValue.nullValue;
	}
	else
	{
		typeString(t, v);
		throwException(t, "Can only get super of classes, instances, and namespaces, not values of type '{}'", getString(t, -1));
	}

	assert(false);
}

// ============================================================================
// Helper functions

CrocValue* lookupGlobal(CrocString* name, CrocNamespace* env)
{
	if(auto glob = namespace.get(env, name))
		return glob;

	auto ns = env;
	for(; ns.parent !is null; ns = ns.parent){}

	return namespace.get(ns, name);
}

void savePtr(CrocThread* t, ref CrocValue* ptr, out bool shouldLoad)
{
	if(ptr >= t.stack.ptr && ptr < t.stack.ptr + t.stack.length)
	{
		shouldLoad = true;
		ptr = cast(CrocValue*)(cast(uword)ptr - cast(uword)t.stack.ptr);
	}
}

void loadPtr(CrocThread* t, ref CrocValue* ptr)
{
	ptr = cast(CrocValue*)(cast(uword)ptr + cast(uword)t.stack.ptr);
}

CrocNamespace* getMetatable(CrocThread* t, CrocValue.Type type)
{
	// ORDER CROCVALUE TYPE
	assert(type >= CrocValue.Type.Null && type <= CrocValue.Type.FuncDef);
	return t.vm.metaTabs[type];
}

bool correctIndices(out crocint loIndex, out crocint hiIndex, CrocValue* lo, CrocValue* hi, uword len)
{
	if(lo.type == CrocValue.Type.Null)
		loIndex = 0;
	else if(lo.type == CrocValue.Type.Int)
	{
		loIndex = lo.mInt;

		if(loIndex < 0)
			loIndex += len;
	}
	else
		return false;

	if(hi.type == CrocValue.Type.Null)
		hiIndex = len;
	else if(hi.type == CrocValue.Type.Int)
	{
		hiIndex = hi.mInt;

		if(hiIndex < 0)
			hiIndex += len;
	}
	else
		return false;

	return true;
}

bool validIndices(crocint lo, crocint hi, uword len)
{
	return lo >= 0 && hi <= len && lo <= hi;
}

uword charLen(dchar c)
{
	dchar[1] inbuf = void;
	inbuf[0] = c;
	char[4] outbuf = void;
	uint ate = 0;
	return Utf.toString(inbuf, outbuf, &ate).length;
}

word pushNamespaceNamestring(CrocThread* t, CrocNamespace* ns)
{
	uword namespaceName(CrocNamespace* ns)
	{
		if(ns.name.cpLength == 0)
			return 0;

		uword n = 0;

		if(ns.parent)
		{
			auto ret = namespaceName(ns.parent);

			if(ret > 0)
			{
				pushChar(t, '.');
				n = ret + 1;
			}
		}

		push(t, CrocValue(ns.name));
		return n + 1;
	}

	auto x = namespaceName(ns);

	if(x == 0)
		return pushString(t, "");
	else
	{
		auto slot = t.stackIndex - x;
		catImpl(t, &t.stack[slot], slot, x);

		if(x > 1)
			pop(t, x - 1);

		return slot - t.stackBase;
	}
}

word typeString(CrocThread* t, CrocValue* v)
{
	switch(v.type)
	{
		case CrocValue.Type.Null,
			CrocValue.Type.Bool,
			CrocValue.Type.Int,
			CrocValue.Type.Float,
			CrocValue.Type.Char,
			CrocValue.Type.String,
			CrocValue.Type.Table,
			CrocValue.Type.Array,
			CrocValue.Type.Memblock,
			CrocValue.Type.Function,
			CrocValue.Type.Namespace,
			CrocValue.Type.Thread,
			CrocValue.Type.WeakRef,
			CrocValue.Type.FuncDef:

			return pushString(t, CrocValue.typeStrings[v.type]);

		case CrocValue.Type.Class:
			// LEAVE ME UP HERE PLZ, don't inline, thx. (WHY, ME?!? WHY CAN'T I INLINE THIS FFFFF)
			auto n = v.mClass.name.toString();
			return pushFormat(t, "{} {}", CrocValue.typeStrings[CrocValue.Type.Class], n);

		case CrocValue.Type.Instance:
			// don't inline me either.
			auto n = v.mInstance.parent.name.toString();
			return pushFormat(t, "{} of {}", CrocValue.typeStrings[CrocValue.Type.Instance], n);

		case CrocValue.Type.NativeObj:
			pushString(t, CrocValue.typeStrings[CrocValue.Type.NativeObj]);
			pushChar(t, ' ');

			if(auto o = v.mNativeObj.obj)
				pushString(t, o.classinfo.name);
			else
				pushString(t, "(??? null)");

			auto slot = t.stackIndex - 3;
			catImpl(t, &t.stack[slot], slot, 3);
			pop(t, 2);
			return slot - t.stackBase;

		default: assert(false);
	}
}

// ============================================================================
// Coroutines

version(CrocExtendedCoro)
{
	class ThreadFiber : Fiber
	{
		CrocThread* t;
		uword numParams;

		this(CrocThread* t, uword numParams)
		{
			super(&run, 16384); // TODO: provide the stack size as a user-settable value
			this.t = t;
			this.numParams = numParams;
		}

		void run()
		{
			assert(t.state == CrocThread.State.Initial);

			push(t, CrocValue(t.coroFunc));
			insert(t, 1);

			if(callPrologue(t, cast(AbsStack)1, -1, numParams, null))
				execute(t);
		}
	}
}

void yieldImpl(CrocThread* t, AbsStack firstValue, word numReturns, word numValues)
{
	auto ar = pushAR(t);

	assert(t.arIndex > 1);
	*ar = t.actRecs[t.arIndex - 2];

	ar.func = null;
	ar.returnSlot = firstValue;
	ar.numReturns = numReturns;
	ar.firstResult = 0;
	ar.numResults = 0;

	if(numValues == -1)
		t.numYields = t.stackIndex - firstValue;
	else
	{
		t.stackIndex = firstValue + numValues;
		t.numYields = numValues;
	}

	t.state = CrocThread.State.Suspended;

	version(CrocExtendedCoro)
	{
		Fiber.yield();
		t.state = CrocThread.State.Running;
		t.vm.curThread = t;
		callEpilogue(t, true);
	}
}

uword resume(CrocThread* t, uword numParams)
{
	try
	{
		version(CrocExtendedCoro)
		{
			if(t.state == CrocThread.State.Initial)
			{
				if(t.coroFiber is null)
					t.coroFiber = nativeobj.create(t.vm, new ThreadFiber(t, numParams));
				else
				{
					auto f = cast(ThreadFiber)cast(void*)t.coroFiber.obj;
					f.t = t;
					f.numParams = numParams;
				}
			}

			t.getFiber().call();
		}
		else
		{
			if(t.state == CrocThread.State.Initial)
			{
				push(t, CrocValue(t.coroFunc));
				insert(t, 1);
				auto result = callPrologue(t, cast(AbsStack)1, -1, numParams, null);
				assert(result == true, "resume callPrologue must return true");
				execute(t);
			}
			else
			{
				callEpilogue(t, true);
				execute(t, t.savedCallDepth);
			}
		}
	}
	catch(CrocHaltException e)
	{
		assert(t.arIndex == 0);
		assert(t.upvalHead is null);
		assert(t.resultIndex == 0);
		assert(t.trIndex == 0);
		assert(t.nativeCallDepth == 0);
	}

	return t.numYields;
}

// ============================================================================
// Interpreter State

ActRecord* pushAR(CrocThread* t)
{
	if(t.arIndex >= t.actRecs.length)
		t.vm.alloc.resizeArray(t.actRecs, t.actRecs.length * 2);

	t.currentAR = &t.actRecs[t.arIndex];
	t.arIndex++;
	return t.currentAR;
}

void popAR(CrocThread* t)
{
	t.arIndex--;
	t.currentAR.func = null;
	t.currentAR.proto = null;

	if(t.arIndex > 0)
	{
		t.currentAR = &t.actRecs[t.arIndex - 1];
		t.stackBase = t.currentAR.base;
	}
	else
	{
		t.currentAR = null;
		t.stackBase = 0;
	}
}

TryRecord* pushTR(CrocThread* t)
{
	if(t.trIndex >= t.tryRecs.length)
		t.vm.alloc.resizeArray(t.tryRecs, t.tryRecs.length * 2);

	t.currentTR = &t.tryRecs[t.trIndex];
	t.trIndex++;
	return t.currentTR;
}

protected final void popTR(CrocThread* t)
{
	t.trIndex--;

	if(t.trIndex > 0)
		t.currentTR = &t.tryRecs[t.trIndex - 1];
	else
		t.currentTR = null;
}

void close(CrocThread* t, AbsStack index)
{
	auto base = &t.stack[index];

	for(auto uv = t.upvalHead; uv !is null && uv.value >= base; uv = t.upvalHead)
	{
		t.upvalHead = uv.nextuv;
		uv.closedValue = *uv.value;
		uv.value = &uv.closedValue;
	}
}

CrocUpval* findUpvalue(CrocThread* t, uword num)
{
	auto slot = &t.stack[t.currentAR.base + num];
	auto puv = &t.upvalHead;

	for(auto uv = *puv; uv !is null && uv.value >= slot; puv = &uv.nextuv, uv = *puv)
		if(uv.value is slot)
			return uv;

	auto ret = t.vm.alloc.allocate!(CrocUpval)();
	ret.value = slot;
	ret.nextuv = *puv;
	*puv = ret;
	return ret;
}

// ============================================================================
// Debugging

void callHook(CrocThread* t, CrocThread.Hook hook)
{
	if(!t.hooksEnabled || !t.hookFunc)
		return;

	auto savedTop = t.stackIndex;
	t.hooksEnabled = false;

	auto slot = push(t, CrocValue(t.hookFunc));
	push(t, CrocValue(t));

	switch(hook)
	{
		case CrocThread.Hook.Call:    pushString(t, "call"); break;
		case CrocThread.Hook.Ret:     pushString(t, "ret"); break;
		case CrocThread.Hook.TailRet: pushString(t, "tailret"); break;
		case CrocThread.Hook.Delay:   pushString(t, "delay"); break;
		case CrocThread.Hook.Line:    pushString(t, "line"); break;
		default: assert(false);
	}

	try
		commonCall(t, t.stackBase + slot, 0, callPrologue(t, t.stackBase + slot, 0, 1, null));
	finally
	{
		t.hooksEnabled = true;
		t.stackIndex = savedTop;
	}
}

void callReturnHooks(CrocThread* t)
{
	if(!t.hooksEnabled)
		return;

	callHook(t, CrocThread.Hook.Ret);

	if(!t.currentAR.func.isNative)
	{
		while(t.currentAR.numTailcalls > 0)
		{
			t.currentAR.numTailcalls--;
			callHook(t, CrocThread.Hook.TailRet);
		}
	}
}

// ============================================================================
// Main interpreter loop

void execute(CrocThread* t, uword depth = 1)
{
	CrocException currentException = null;
	bool rethrowingException = false;
	CrocValue RS;
	CrocValue RT;

	_exceptionRetry:
	t.state = CrocThread.State.Running;
	t.vm.curThread = t;

	_reentry:
	auto stackBase = t.stackBase;
	auto constTable = t.currentAR.func.scriptFunc.constants;
	auto env = t.currentAR.func.environment;
	auto upvals = t.currentAR.func.scriptUpvals();
	auto pc = &t.currentAR.pc;

	try
	{
		CrocValue* get(uint index)
		{
			switch(index & Instruction.locMask)
			{
				case Instruction.locLocal: return &t.stack[stackBase + (index & ~Instruction.locMask)];
				case Instruction.locConst: return &constTable[index & ~Instruction.locMask];
				case Instruction.locUpval: return upvals[index & ~Instruction.locMask].value;

				default:
					auto name = constTable[index & ~Instruction.locMask].mString;

					if(auto glob = namespace.get(env, name))
						return glob;

					auto ns = env;
					for(; ns.parent !is null; ns = ns.parent){}

					if(ns !is env)
					{
						if(auto glob = namespace.get(ns, name))
							return glob;
					}

					throwException(t, "Attempting to get nonexistent global '{}'", name.toString());
			}

			assert(false);
		}

		const char[] GetRD = "((i.rd & 0x8000) == 0) ? (&t.stack[stackBase + (i.rd & ~Instruction.locMask)]) : get(i.rd)";
		const char[] GetRDplus1 = "(((i.rd + 1) & 0x8000) == 0) ? (&t.stack[stackBase + ((i.rd + 1) & ~Instruction.locMask)]) : get(i.rd + 1)";
		const char[] GetRS = "((i.rs & 0x8000) == 0) ? (((i.rs & 0x4000) == 0) ? (&t.stack[stackBase + (i.rs & ~Instruction.locMask)]) : (&constTable[i.rs & ~Instruction.locMask])) : (get(i.rs))";
		const char[] GetRT = "((i.rt & 0x8000) == 0) ? (((i.rt & 0x4000) == 0) ? (&t.stack[stackBase + (i.rt & ~Instruction.locMask)]) : (&constTable[i.rt & ~Instruction.locMask])) : (get(i.rt))";

		Instruction* oldPC = null;

		_interpreterLoop: while(true)
		{
			if(t.shouldHalt)
				throw new CrocHaltException;

			pc = &t.currentAR.pc;
			Instruction* i = (*pc)++;

			if(t.hooksEnabled)
			{
				if(t.hooks & CrocThread.Hook.Delay)
				{
					assert(t.hookCounter > 0);
					t.hookCounter--;

					if(t.hookCounter == 0)
					{
						t.hookCounter = t.hookDelay;
						callHook(t, CrocThread.Hook.Delay);
					}
				}

				if(t.hooks & CrocThread.Hook.Line)
				{
					auto curPC = t.currentAR.pc - 1;

					// when oldPC is null, it means we've either just started executing this func,
					// or we've come back from a yield, or we've just caught an exception, or something
					// like that.
					// When curPC < oldPC, we've jumped back, like to the beginning of a loop.

					if(curPC is t.currentAR.func.scriptFunc.code.ptr || curPC < oldPC || pcToLine(t.currentAR, curPC) != pcToLine(t.currentAR, curPC - 1))
						callHook(t, CrocThread.Hook.Line);
				}
			}

			oldPC = *pc;

			switch(i.opcode)
			{
				// Binary Arithmetic
				case Op.Add: binOpImpl(t, MM.Add, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Sub: binOpImpl(t, MM.Sub, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Mul: binOpImpl(t, MM.Mul, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Div: binOpImpl(t, MM.Div, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Mod: binOpImpl(t, MM.Mod, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;

				// Unary Arithmetic
				case Op.Neg: negImpl(t, mixin(GetRD), mixin(GetRS)); break;

				// Reflexive Arithmetic
				case Op.AddEq: reflBinOpImpl(t, MM.AddEq, mixin(GetRD), mixin(GetRS)); break;
				case Op.SubEq: reflBinOpImpl(t, MM.SubEq, mixin(GetRD), mixin(GetRS)); break;
				case Op.MulEq: reflBinOpImpl(t, MM.MulEq, mixin(GetRD), mixin(GetRS)); break;
				case Op.DivEq: reflBinOpImpl(t, MM.DivEq, mixin(GetRD), mixin(GetRS)); break;
				case Op.ModEq: reflBinOpImpl(t, MM.ModEq, mixin(GetRD), mixin(GetRS)); break;

				// Inc/Dec
				case Op.Inc: incImpl(t, mixin(GetRD)); break;
				case Op.Dec: decImpl(t, mixin(GetRD)); break;

				// Binary Bitwise
				case Op.And:  binaryBinOpImpl(t, MM.And,  mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Or:   binaryBinOpImpl(t, MM.Or,   mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Xor:  binaryBinOpImpl(t, MM.Xor,  mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Shl:  binaryBinOpImpl(t, MM.Shl,  mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Shr:  binaryBinOpImpl(t, MM.Shr,  mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.UShr: binaryBinOpImpl(t, MM.UShr, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;

				// Unary Bitwise
				case Op.Com: comImpl(t, mixin(GetRD), mixin(GetRS)); break;

				// Reflexive Bitwise
				case Op.AndEq:  reflBinaryBinOpImpl(t, MM.AndEq,  mixin(GetRD), mixin(GetRS)); break;
				case Op.OrEq:   reflBinaryBinOpImpl(t, MM.OrEq,   mixin(GetRD), mixin(GetRS)); break;
				case Op.XorEq:  reflBinaryBinOpImpl(t, MM.XorEq,  mixin(GetRD), mixin(GetRS)); break;
				case Op.ShlEq:  reflBinaryBinOpImpl(t, MM.ShlEq,  mixin(GetRD), mixin(GetRS)); break;
				case Op.ShrEq:  reflBinaryBinOpImpl(t, MM.ShrEq,  mixin(GetRD), mixin(GetRS)); break;
				case Op.UShrEq: reflBinaryBinOpImpl(t, MM.UShrEq, mixin(GetRD), mixin(GetRS)); break;

				// Data Transfer
				case Op.Move: *mixin(GetRD) = *mixin(GetRS); break;
				case Op.MoveLocal: t.stack[stackBase + i.rd] = t.stack[stackBase + i.rs]; break;
				case Op.LoadConst: t.stack[stackBase + i.rd] = constTable[i.rs & ~Instruction.locMask]; break;

				case Op.LoadBool: *mixin(GetRD) = cast(bool)i.rs; break;
				case Op.LoadNull: *mixin(GetRD) = CrocValue.nullValue; break;

				case Op.LoadNulls:
					auto start = stackBase + i.rd;
					t.stack[start .. start + i.imm] = CrocValue.nullValue;
					break;

				case Op.NewGlobal:
					auto name = constTable[i.rt & ~Instruction.locMask].mString;

					if(namespace.contains(env, name))
						throwException(t, "Attempting to create global '{}' that already exists", name.toString());

					namespace.set(t.vm.alloc, env, name, mixin(GetRS));
					break;

				// Logical and Control Flow
				case Op.Not: *mixin(GetRD) = mixin(GetRS).isFalse(); break;

				case Op.Cmp:
					auto jump = (*pc)++;

					auto cmpValue = compareImpl(t, mixin(GetRS), mixin(GetRT));

					if(jump.rd)
					{
						switch(jump.opcode)
						{
							case Op.Je:  if(cmpValue == 0) (*pc) += jump.imm; break;
							case Op.Jle: if(cmpValue <= 0) (*pc) += jump.imm; break;
							case Op.Jlt: if(cmpValue < 0)  (*pc) += jump.imm; break;
							default: assert(false, "invalid 'cmp' jump");
						}
					}
					else
					{
						switch(jump.opcode)
						{
							case Op.Je:  if(cmpValue != 0) (*pc) += jump.imm; break;
							case Op.Jle: if(cmpValue > 0)  (*pc) += jump.imm; break;
							case Op.Jlt: if(cmpValue >= 0) (*pc) += jump.imm; break;
							default: assert(false, "invalid 'cmp' jump");
						}
					}
					break;

				case Op.Equals:
					auto jump = (*pc)++;

					auto cmpValue = equalsImpl(t, mixin(GetRS), mixin(GetRT));

					if(cmpValue == cast(bool)jump.rd)
						(*pc) += jump.imm;
					break;

				case Op.Cmp3:
					// Doing this to ensure evaluation of mixin(GetRD) happens _after_ compareImpl has executed
					auto val = compareImpl(t, mixin(GetRS), mixin(GetRT));
					*mixin(GetRD) = val;
					break;

				case Op.SwitchCmp:
					auto jump = (*pc)++;

					if(switchCmpImpl(t, mixin(GetRS), mixin(GetRT)))
						(*pc) += jump.imm;

					break;

				case Op.Is:
					auto jump = (*pc)++;

					if(mixin(GetRS).opEquals(*mixin(GetRT)) == jump.rd)
						(*pc) += jump.imm;

					break;

				case Op.IsTrue:
					auto jump = (*pc)++;

					if(mixin(GetRS).isFalse() != cast(bool)jump.rd)
						(*pc) += jump.imm;

					break;

				case Op.Jmp:
					if(i.rd != 0)
						(*pc) += i.imm;
					break;

				case Op.Switch:
					auto st = &t.currentAR.func.scriptFunc.switchTables[i.rt];

					if(auto ptr = st.offsets.lookup(*mixin(GetRS)))
						(*pc) += *ptr;
					else
					{
						if(st.defaultOffset == -1)
							throwException(t, "Switch without default");

						(*pc) += st.defaultOffset;
					}
					break;

				case Op.Close: close(t, stackBase + i.rd); break;

				case Op.For:
					auto idx = &t.stack[stackBase + i.rd];
					auto hi = idx + 1;
					auto step = hi + 1;

					if(idx.type != CrocValue.Type.Int || hi.type != CrocValue.Type.Int || step.type != CrocValue.Type.Int)
						throwException(t, "Numeric for loop low, high, and step values must be integers");

					auto intIdx = idx.mInt;
					auto intHi = hi.mInt;
					auto intStep = step.mInt;

					if(intStep == 0)
						throwException(t, "Numeric for loop step value may not be 0");

					if(intIdx > intHi && intStep > 0 || intIdx < intHi && intStep < 0)
						intStep = -intStep;

					if(intStep < 0)
						*idx = intIdx + intStep;

					*step = intStep;
					(*pc) += i.imm;
					break;

				case Op.ForLoop:
					auto idx = t.stack[stackBase + i.rd].mInt;
					auto hi = t.stack[stackBase + i.rd + 1].mInt;
					auto step = t.stack[stackBase + i.rd + 2].mInt;

					if(step > 0)
					{
						if(idx < hi)
						{
							t.stack[stackBase + i.rd + 3] = idx;
							t.stack[stackBase + i.rd] = idx + step;
							(*pc) += i.imm;
						}
					}
					else
					{
						if(idx >= hi)
						{
							t.stack[stackBase + i.rd + 3] = idx;
							t.stack[stackBase + i.rd] = idx + step;
							(*pc) += i.imm;
						}
					}
					break;

				case Op.Foreach:
					auto rd = i.rd;
					auto src = &t.stack[stackBase + rd];

					if(src.type != CrocValue.Type.Function && src.type != CrocValue.Type.Thread)
					{
						CrocClass* proto;
						auto method = getMM(t, src, MM.Apply, proto);

						if(method is null)
						{
							typeString(t, src);
							throwException(t, "No implementation of {} for type '{}'", MetaNames[MM.Apply], getString(t, -1));
						}

						t.stack[stackBase + rd + 2] = t.stack[stackBase + rd + 1];
						t.stack[stackBase + rd + 1] = *src;
						t.stack[stackBase + rd] = method;

						t.stackIndex = stackBase + rd + 3;
						commonCall(t, stackBase + rd, 3, callPrologue(t, stackBase + rd, 3, 2, proto));
						t.stackIndex = t.currentAR.savedTop;

						src = &t.stack[stackBase + rd];

						if(src.type != CrocValue.Type.Function && src.type != CrocValue.Type.Thread)
						{
							typeString(t, src);
							throwException(t, "Invalid iterable type '{}' returned from opApply", getString(t, -1));
						}
					}

					if(src.type == CrocValue.Type.Thread && src.mThread.state != CrocThread.State.Initial)
						throwException(t, "Attempting to iterate over a thread that is not in the 'initial' state");

					(*pc) += i.imm;
					break;

				case Op.ForeachLoop:
					auto jump = (*pc)++;

					auto rd = i.rd;
					auto funcReg = rd + 3;
					auto src = &t.stack[stackBase + rd];

					t.stack[stackBase + funcReg + 2] = t.stack[stackBase + rd + 2];
					t.stack[stackBase + funcReg + 1] = t.stack[stackBase + rd + 1];
					t.stack[stackBase + funcReg] = t.stack[stackBase + rd];

					t.stackIndex = stackBase + funcReg + 3;
					commonCall(t, stackBase + funcReg, i.imm, callPrologue(t, stackBase + funcReg, i.imm, 2, null));
					t.stackIndex = t.currentAR.savedTop;

					if(src.type == CrocValue.Type.Function)
					{
						if(t.stack[stackBase + funcReg].type != CrocValue.Type.Null)
						{
							t.stack[stackBase + rd + 2] = t.stack[stackBase + funcReg];
							(*pc) += jump.imm;
						}
					}
					else
					{
						if(src.mThread.state != CrocThread.State.Dead)
							(*pc) += jump.imm;
					}
					break;

				// Exception Handling
				case Op.PushCatch:
					auto tr = pushTR(t);
					tr.isCatch = true;
					tr.slot = cast(RelStack)i.rd;
					tr.pc = (*pc) + i.imm;
					tr.actRecord = t.arIndex;
					break;

				case Op.PushFinally:
					auto tr = pushTR(t);
					tr.isCatch = false;
					tr.slot = cast(RelStack)i.rd;
					tr.pc = (*pc) + i.imm;
					tr.actRecord = t.arIndex;
					break;

				case Op.PopCatch: popTR(t); break;

				case Op.PopFinally:
					currentException = null;
					popTR(t);
					break;

				case Op.EndFinal:
					if(currentException !is null)
					{
						rethrowingException = true;
						throw currentException;
					}

					if(t.currentAR.unwindReturn !is null)
						goto _commonEHUnwind;

					break;

				case Op.Throw:
					rethrowingException = cast(bool)i.rt;
					throwImpl(t, *mixin(GetRS), rethrowingException);
					break;

				// Function Calling
			{
				bool isScript = void;
				word numResults = void;

				case Op.Method, Op.MethodNC, Op.SuperMethod:
					auto call = (*pc)++;

					RT = *mixin(GetRT);

					if(RT.type != CrocValue.Type.String)
					{
						typeString(t, &RT);
						throwException(t, "Attempting to get a method with a non-string name (type '{}' instead)", getString(t, -1));
					}

					auto methodName = RT.mString;
					auto self = mixin(GetRS);

					if(i.opcode != Op.SuperMethod)
						RS = *self;
					else
					{
						if(t.currentAR.proto is null)
							throwException(t, "Attempting to perform a supercall in a function where there is no super class");

						if(self.type != CrocValue.Type.Instance && self.type != CrocValue.Type.Class)
						{
							typeString(t, self);
							throwException(t, "Attempting to perform a supercall in a function where 'this' is a '{}', not an 'instance' or 'class'", getString(t, -1));
						}

						RS = t.currentAR.proto;
					}

					numResults = call.rt - 1;
					uword numParams = void;

					if(call.rs == 0)
						numParams = t.stackIndex - (stackBase + i.rd + 1);
					else
					{
						numParams = call.rs - 1;
						t.stackIndex = stackBase + i.rd + call.rs;
					}

					isScript = commonMethodCall(t, stackBase + i.rd, self, &RS, methodName, numResults, numParams, i.opcode == Op.MethodNC);

					if(call.opcode == Op.Call)
						goto _commonCall;
					else
						goto _commonTailcall;

				case Op.Call:
					numResults = i.rt - 1;
					uword numParams = void;

					if(i.rs == 0)
						numParams = t.stackIndex - (stackBase + i.rd + 1);
					else
					{
						numParams = i.rs - 1;
						t.stackIndex = stackBase + i.rd + i.rs;
					}

					auto self = &t.stack[stackBase + i.rd + 1];
					CrocClass* proto = void;

					if(self.type == CrocValue.Type.Instance)
						proto = self.mInstance.parent;
					else if(self.type == CrocValue.Type.Class)
						proto = self.mClass;
					else
						proto = null;

					isScript = callPrologue(t, stackBase + i.rd, numResults, numParams, proto);

					// fall through
				_commonCall:
					maybeGC(t);

					if(isScript)
					{
						depth++;
						goto _reentry;
					}
					else
					{
						if(numResults >= 0)
							t.stackIndex = t.currentAR.savedTop;
					}
					break;

				case Op.Tailcall:
					numResults = i.rt - 1;
					uword numParams = void;

					if(i.rs == 0)
						numParams = t.stackIndex - (stackBase + i.rd + 1);
					else
					{
						numParams = i.rs - 1;
						t.stackIndex = stackBase + i.rd + i.rs;
					}

					auto self = &t.stack[stackBase + i.rd + 1];
					CrocClass* proto = void;

					if(self.type == CrocValue.Type.Instance)
						proto = self.mInstance.parent;
					else if(self.type == CrocValue.Type.Class)
						proto = self.mClass;
					else
						proto = null;

					isScript = callPrologue(t, stackBase + i.rd, numResults, numParams, proto);

					// fall through
				_commonTailcall:
					maybeGC(t);

					if(isScript)
					{
						auto prevAR = t.currentAR - 1;
						close(t, prevAR.base);

						auto diff = cast(ptrdiff_t)(t.currentAR.returnSlot - prevAR.returnSlot);

						auto tc = prevAR.numTailcalls + 1;
						t.currentAR.numReturns = prevAR.numReturns;
						*prevAR = *t.currentAR;
						prevAR.numTailcalls = tc;
						prevAR.base -= diff;
						prevAR.savedTop -= diff;
						prevAR.vargBase -= diff;
						prevAR.returnSlot -= diff;

						popAR(t);

						//memmove(&t.stack[prevAR.returnSlot], &t.stack[prevAR.returnSlot + diff], (prevAR.savedTop - prevAR.returnSlot) * CrocValue.sizeof);

						for(auto idx = prevAR.returnSlot; idx < prevAR.savedTop; idx++)
							t.stack[idx] = t.stack[idx + diff];

						goto _reentry;
					}

					// Do nothing for native calls.  The following return instruction will catch it.
					break;
			}

				case Op.SaveRets:
					auto firstResult = stackBase + i.rd;

					if(i.imm == 0)
					{
						saveResults(t, t, firstResult, t.stackIndex - firstResult);
						t.stackIndex = t.currentAR.savedTop;
					}
					else
						saveResults(t, t, firstResult, i.imm - 1);
					break;

				case Op.Ret:
					unwindEH(t);
					close(t, stackBase);
					callEpilogue(t, true);

					depth--;

					if(depth == 0)
						return;

					goto _reentry;

				case Op.Unwind:
					t.currentAR.unwindReturn = (*pc);
					t.currentAR.unwindCounter = i.uimm;

					// fall through
				_commonEHUnwind:
					while(t.currentAR.unwindCounter > 0)
					{
						assert(t.trIndex > 0);
						assert(t.currentTR.actRecord is t.arIndex);

						auto tr = *t.currentTR;
						popTR(t);
						close(t, t.stackBase + tr.slot);
						t.currentAR.unwindCounter--;

						if(!tr.isCatch)
						{
							// finally in the middle of an unwind
							(*pc) = tr.pc;
							continue _interpreterLoop;
						}
					}

					(*pc) = t.currentAR.unwindReturn;
					t.currentAR.unwindReturn = null;
					break;

				case Op.Vararg:
					auto numVarargs = stackBase - t.currentAR.vargBase;
					auto dest = stackBase + i.rd;

					uword numNeeded = void;

					if(i.uimm == 0)
					{
						numNeeded = numVarargs;
						t.stackIndex = dest + numVarargs;
						checkStack(t, t.stackIndex);
					}
					else
						numNeeded = i.uimm - 1;

					auto src = t.currentAR.vargBase;
					
					if(numNeeded <= numVarargs)
						memmove(&t.stack[dest], &t.stack[src], numNeeded * CrocValue.sizeof);
					else
					{
						memmove(&t.stack[dest], &t.stack[src], numVarargs * CrocValue.sizeof);
						t.stack[dest + numVarargs .. dest + numNeeded] = CrocValue.nullValue;
					}

					break;

				case Op.VargLen: *mixin(GetRD) = cast(crocint)(stackBase - t.currentAR.vargBase); break;

				case Op.VargIndex:
					auto numVarargs = stackBase - t.currentAR.vargBase;

					RS = *mixin(GetRS);

					if(RS.type != CrocValue.Type.Int)
					{
						typeString(t, &RS);
						throwException(t, "Attempting to index 'vararg' with a '{}'", getString(t, -1));
					}

					auto index = RS.mInt;

					if(index < 0)
						index += numVarargs;

					if(index < 0 || index >= numVarargs)
						throwException(t, "Invalid 'vararg' index: {} (only have {})", index, numVarargs);

					*mixin(GetRD) = t.stack[t.currentAR.vargBase + cast(uword)index];
					break;

				case Op.VargIndexAssign:
					auto numVarargs = stackBase - t.currentAR.vargBase;

					RS = *mixin(GetRS);

					if(RS.type != CrocValue.Type.Int)
					{
						typeString(t, &RS);
						throwException(t, "Attempting to index 'vararg' with a '{}'", getString(t, -1));
					}

					auto index = RS.mInt;

					if(index < 0)
						index += numVarargs;

					if(index < 0 || index >= numVarargs)
						throwException(t, "Invalid 'vararg' index: {} (only have {})", index, numVarargs);

					t.stack[t.currentAR.vargBase + cast(uword)index] = *mixin(GetRT);
					break;

				case Op.VargSlice:
					auto numVarargs = stackBase - t.currentAR.vargBase;
					
					crocint lo = void;
					crocint hi = void;

					auto loSrc = mixin(GetRD);
					auto hiSrc = mixin(GetRDplus1);

					if(!correctIndices(lo, hi, loSrc, hiSrc, numVarargs))
					{
						typeString(t, loSrc);
						typeString(t, hiSrc);
						throwException(t, "Attempting to slice 'vararg' with '{}' and '{}'", getString(t, -2), getString(t, -1));
					}

					if(lo > hi || lo < 0 || lo > numVarargs || hi < 0 || hi > numVarargs)
						throwException(t, "Invalid vararg slice indices [{} .. {}]", lo, hi);

					auto sliceSize = cast(uword)(hi - lo);
					auto src = t.currentAR.vargBase + cast(uword)lo;
					auto dest = stackBase + cast(uword)i.rd;

					uword numNeeded = void;

					if(i.uimm == 0)
					{
						numNeeded = sliceSize;
						t.stackIndex = dest + sliceSize;
						checkStack(t, t.stackIndex);
					}
					else
						numNeeded = i.uimm - 1;

					if(numNeeded <= sliceSize)
						memmove(&t.stack[dest], &t.stack[src], numNeeded * CrocValue.sizeof);
					else
					{
						memmove(&t.stack[dest], &t.stack[src], sliceSize * CrocValue.sizeof);
						t.stack[dest + sliceSize .. dest + numNeeded] = CrocValue.nullValue;
					}
					break;

				case Op.Yield:
					if(t is t.vm.mainThread)
						throwException(t, "Attempting to yield out of the main thread");

					version(CrocExtendedCoro)
					{
						yieldImpl(t, stackBase + i.rd, i.rt - 1, i.rs - 1);
						break;
					}
					else
					{
						if(t.nativeCallDepth > 0)
							throwException(t, "Attempting to yield across native / metamethod call boundary");

						t.savedCallDepth = depth;
						yieldImpl(t, stackBase + i.rd, i.rt - 1, i.rs - 1);
						return;
					}

				case Op.CheckParams:
					auto val = &t.stack[stackBase];

					foreach(idx, mask; t.currentAR.func.scriptFunc.paramMasks)
					{
						if(!(mask & (1 << val.type)))
						{
							typeString(t, val);

							if(idx == 0)
								throwException(t, "'this' parameter: type '{}' is not allowed", getString(t, -1));
							else
								throwException(t, "Parameter {}: type '{}' is not allowed", idx, getString(t, -1));
						}

						val++;
					}
					break;

				case Op.CheckObjParam:
					RS = t.stack[stackBase + i.rs];

					if(RS.type != CrocValue.Type.Instance)
						*mixin(GetRD) = true;
					else
					{
						RT = *mixin(GetRT);

						if(RT.type != CrocValue.Type.Class)
						{
							typeString(t, &RT);
							throwException(t, "Parameter {}: instance type constraint type must be 'class', not '{}'", i.rs, getString(t, -1));
						}

						*mixin(GetRD) = instance.derivesFrom(RS.mInstance, RT.mClass);
					}
					break;

				case Op.ObjParamFail:
					typeString(t, &t.stack[stackBase + i.rs]);

					if(i.rs == 0)
						throwException(t, "'this' parameter: type '{}' is not allowed", getString(t, -1));
					else
						throwException(t, "Parameter {}: type '{}' is not allowed", i.rs, getString(t, -1));
						
					break;

				// Array and List Operations
				case Op.Length: lenImpl(t, mixin(GetRD), mixin(GetRS)); break;
				case Op.LengthAssign: lenaImpl(t, mixin(GetRD), mixin(GetRS)); break;
				case Op.Append: array.append(t.vm.alloc, t.stack[stackBase + i.rd].mArray, mixin(GetRS)); break;

				case Op.SetArray:
					auto sliceBegin = stackBase + i.rd + 1;
					auto a = t.stack[stackBase + i.rd].mArray;

					if(i.rs == 0)
					{
						array.setBlock(t.vm.alloc, a, i.rt, t.stack[sliceBegin .. t.stackIndex]);
						t.stackIndex = t.currentAR.savedTop;
					}
					else
						array.setBlock(t.vm.alloc, a, i.rt, t.stack[sliceBegin .. sliceBegin + i.rs - 1]);

					break;

				case Op.Cat:
					catImpl(t, mixin(GetRD), stackBase + i.rs, i.rt);
					maybeGC(t);
					break;

				case Op.CatEq:
					catEqImpl(t, mixin(GetRD), stackBase + i.rs, i.rt);
					maybeGC(t);
					break;

				case Op.Index: idxImpl(t, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.IndexAssign: idxaImpl(t, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;

				case Op.Field:
					RT = *mixin(GetRT);

					if(RT.type != CrocValue.Type.String)
					{
						typeString(t, &RT);
						throwException(t, "Field name must be a string, not a '{}'", getString(t, -1));
					}

					fieldImpl(t, mixin(GetRD), mixin(GetRS), RT.mString, false);
					break;

				case Op.FieldAssign:
					RS = *mixin(GetRS);

					if(RS.type != CrocValue.Type.String)
					{
						typeString(t, &RS);
						throwException(t, "Field name must be a string, not a '{}'", getString(t, -1));
					}

					fieldaImpl(t, mixin(GetRD), RS.mString, mixin(GetRT), false);
					break;

				case Op.Slice:
					auto base = &t.stack[stackBase + i.rs];
					sliceImpl(t, mixin(GetRD), base, base + 1, base + 2);
					break;

				case Op.SliceAssign:
					auto base = &t.stack[stackBase + i.rd];
					sliceaImpl(t, base, base + 1, base + 2, mixin(GetRS));
					break;

				case Op.NotIn:
					auto val = !inImpl(t, mixin(GetRS), mixin(GetRT));
					*mixin(GetRD) = val;
					break;

				case Op.In:
					auto val = inImpl(t, mixin(GetRS), mixin(GetRT));
					*mixin(GetRD) = val;
					break;

				// Value Creation
				case Op.NewArray:
					t.stack[stackBase + i.rd] = array.create(t.vm.alloc, i.uimm);
					maybeGC(t);
					break;

				case Op.NewTable:
					t.stack[stackBase + i.rd] = table.create(t.vm.alloc);
					maybeGC(t);
					break;

				case Op.Closure:
					auto newDef = t.currentAR.func.scriptFunc.innerFuncs[i.rs];
					auto funcEnv = i.rt == 0 ? env : t.stack[stackBase + i.rt].mNamespace;
					auto n = func.create(t.vm.alloc, funcEnv, newDef);

					if(n is null)
					{
						CrocValue def = newDef;
						toStringImpl(t, def, false);
						throwException(t, "Attempting to instantiate {} with a different namespace than was associated with it", getString(t, -1));
					}

					foreach(ref uv; n.scriptUpvals())
					{
						if((*pc).rd == 0)
							uv = findUpvalue(t, (*pc).rs);
						else
							uv = upvals[(*pc).uimm];

						(*pc)++;
					}

					*mixin(GetRD) = n;
					maybeGC(t);
					break;

				case Op.Class:
					RS = *mixin(GetRS);
					RT = *mixin(GetRT);

					if(RT.type != CrocValue.Type.Class)
					{
						typeString(t, &RT);
						throwException(t, "Attempting to derive a class from a value of type '{}'", getString(t, -1));
					}
					else
						*mixin(GetRD) = classobj.create(t.vm.alloc, RS.mString, RT.mClass);

					maybeGC(t);
					break;
				
				case Op.ClassNB:
					RS = *mixin(GetRS);
					*mixin(GetRD) = classobj.create(t.vm.alloc, RS.mString, t.vm.object);
					maybeGC(t);
					break;

				case Op.Coroutine:
					RS = *mixin(GetRS);

					if(RS.type != CrocValue.Type.Function)
					{
						typeString(t, &RS);
						throwException(t, "Coroutines must be created with a function, not '{}'", getString(t, -1));
					}

					version(CrocExtendedCoro) {} else
					{
						if(RS.mFunction.isNative)
							throwException(t, "Native functions may not be used as the body of a coroutine");
					}

					auto nt = thread.create(t.vm, RS.mFunction);
					nt.hookFunc = t.hookFunc;
					nt.hooks = t.hooks;
					nt.hookDelay = t.hookDelay;
					nt.hookCounter = t.hookCounter;
					*mixin(GetRD) = nt;
					break;

				case Op.Namespace:
					auto name = constTable[i.rs].mString;
					RT = *mixin(GetRT);

					if(RT.type == CrocValue.Type.Null)
						*mixin(GetRD) = namespace.create(t.vm.alloc, name);
					else if(RT.type != CrocValue.Type.Namespace)
					{
						typeString(t, &RT);
						push(t, CrocValue(name));
						throwException(t, "Attempted to use a '{}' as a parent namespace for namespace '{}'", getString(t, -2), getString(t, -1));
					}
					else
						*mixin(GetRD) = namespace.create(t.vm.alloc, name, RT.mNamespace);

					maybeGC(t);
					break;

				case Op.NamespaceNP:
					auto tmp = namespace.create(t.vm.alloc, constTable[i.rs].mString, env);
					*mixin(GetRD) = tmp;
					maybeGC(t);
					break;

				// Class stuff
				case Op.As:
					RS = *mixin(GetRS);

					if(asImpl(t, &RS, mixin(GetRT)))
						*mixin(GetRD) = RS;
					else
						*mixin(GetRD) = CrocValue.nullValue;

					break;

				case Op.SuperOf:
					*mixin(GetRD) = superOfImpl(t, mixin(GetRS));
					break;

				default:
					// TODO: make this a little more.. severe?
					throwException(t, "Unimplemented opcode {}", *i);
			}
		}
	}
	catch(CrocException e)
	{
		t.currentAR.unwindCounter = 0;
		t.currentAR.unwindReturn = null;

		while(depth > 0)
		{
			if(t.trIndex > 0 && t.currentTR.actRecord is t.arIndex)
			{
				auto tr = *t.currentTR;
				popTR(t);

				auto base = t.stackBase + tr.slot;
				close(t, base);

				// remove any results that may have been saved
				loadResults(t);

				if(rethrowingException)
					rethrowingException = false;
				else
					t.vm.traceback.append(&t.vm.alloc, getDebugLoc(t));

				if(tr.isCatch)
				{
					t.stack[base] = t.vm.exception;
					t.vm.exception = CrocValue.nullValue;
					t.vm.isThrowing = false;
					currentException = null;

					t.stack[base + 1 .. t.stackIndex] = CrocValue.nullValue;
					t.currentAR.pc = tr.pc;
					goto _exceptionRetry;
				}
				else
				{
					currentException = e;
					t.currentAR.pc = tr.pc;
					goto _exceptionRetry;
				}
			}

			if(rethrowingException)
				rethrowingException = false;
			else if(t.currentAR && t.currentAR.func !is null)
			{
				t.vm.traceback.append(&t.vm.alloc, getDebugLoc(t));

				// as far as I can reason, it would be impossible to have tailcalls AND have rethrowingException == true, since you can't do a tailcall in a try block.
				if(t.currentAR.numTailcalls > 0)
				{
					pushFormat(t, "<{} tailcalls>", t.currentAR.numTailcalls);
					t.vm.traceback.append(&t.vm.alloc, Location(getStringObj(t, -1), -1, Location.Type.Script));
					pop(t);
				}
			}

			close(t, t.stackBase);
			callEpilogue(t, false);
			depth--;
		}

		throw e;
	}
	catch(CrocHaltException e)
	{
		while(depth > 0)
		{
			close(t, t.stackBase);
			callEpilogue(t, false);
			depth--;
		}

		unwindEH(t);
		throw e;
	}
}