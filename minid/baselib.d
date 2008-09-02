/******************************************************************************
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

module minid.baselib;

import Integer = tango.text.convert.Integer;
import tango.io.Buffer;
import tango.io.Console;
import tango.io.Print;
import tango.io.Stdout;
import tango.stdc.ctype;
import tango.stdc.string;
import Utf = tango.text.convert.Utf;

import minid.compiler;
import minid.ex;
import minid.func;
import minid.interpreter;
import minid.misc;
import minid.namespace;
import minid.obj;
import minid.string;
import minid.types;
import minid.utils;
import minid.vm;

private void register(MDThread* t, char[] name, NativeFunc func, uword numUpvals = 0)
{
	newFunction(t, func, name, numUpvals);
	newGlobal(t, name);
}

struct BaseLib
{
static:
	public void init(MDThread* t)
	{
		// Object
		pushObject(t, obj.create(t.vm.alloc, string.create(t.vm, "Object"), null));
			newFunction(t, &objectClone, "Object.clone"); fielda(t, -2, "clone");
		newGlobal(t, "Object");

		// StringBuffer
		StringBufferObj.init(t);

		// Really basic stuff
// 		register(t, "getTraceback", &getTraceback);
		register(t, "haltThread", &haltThread);
		register(t, "currentThread", &currentThread);
// 		register(t, "reloadModule", &reloadModule);
		register(t, "runMain", &runMain);

		// Functional stuff
		register(t, "curry", &curry);
		register(t, "bindContext", &bindContext);

		// Reflection-esque stuff
		register(t, "findGlobal", &findGlobal);
		register(t, "isSet", &isSet);
		register(t, "typeof", &mdtypeof);
		register(t, "fieldsOf", &fieldsOf);
		register(t, "allFieldsOf", &allFieldsOf);
		register(t, "hasField", &hasField);
		register(t, "hasMethod", &hasMethod);
		register(t, "rawSetField", &rawSetField);
		register(t, "rawGetField", &rawGetField);
		register(t, "attrs", &attrs);
		register(t, "hasAttributes", &hasAttributes);
		register(t, "attributesOf", &attributesOf);
		register(t, "isNull", &isParam!(MDValue.Type.Null));
		register(t, "isBool", &isParam!(MDValue.Type.Bool));
		register(t, "isInt", &isParam!(MDValue.Type.Int));
		register(t, "isFloat", &isParam!(MDValue.Type.Float));
		register(t, "isChar", &isParam!(MDValue.Type.Char));
		register(t, "isString", &isParam!(MDValue.Type.String));
		register(t, "isTable", &isParam!(MDValue.Type.Table));
		register(t, "isArray", &isParam!(MDValue.Type.Array));
		register(t, "isFunction", &isParam!(MDValue.Type.Function));
		register(t, "isObject", &isParam!(MDValue.Type.Object));
		register(t, "isNamespace", &isParam!(MDValue.Type.Namespace));
		register(t, "isThread", &isParam!(MDValue.Type.Thread));
		register(t, "isNativeObj", &isParam!(MDValue.Type.NativeObj));

		// Conversions
		register(t, "toString", &toString);
		register(t, "rawToString", &rawToString);
		register(t, "toBool", &toBool);
		register(t, "toInt", &toInt);
		register(t, "toFloat", &toFloat);
		register(t, "toChar", &toChar);
		register(t, "format", &format);

		// Console IO
		register(t, "write", &write);
		register(t, "writeln", &writeln);
		register(t, "writef", &writef);
		register(t, "writefln", &writefln);
		register(t, "readln", &readln);

			newTable(t);
		register(t, "dumpVal", &dumpVal, 1);

		// Dynamic compilation stuff
		register(t, "loadString", &loadString);
		register(t, "eval", &eval);
// 		register(t, "loadJSON", &loadJSON);
// 		register(t, "toJSON", &toJSON);

		// The Thread type's metatable
		newNamespace(t, "thread");
			newFunction(t, &threadReset, "thread.reset");       fielda(t, -2, "reset");
			newFunction(t, &threadState, "thread.state");       fielda(t, -2, "state");
			newFunction(t, &isInitial,   "thread.isInitial");   fielda(t, -2, "isInitial");
			newFunction(t, &isRunning,   "thread.isRunning");   fielda(t, -2, "isRunning");
			newFunction(t, &isWaiting,   "thread.isWaiting");   fielda(t, -2, "isWaiting");
			newFunction(t, &isSuspended, "thread.isSuspended"); fielda(t, -2, "isSuspended");
			newFunction(t, &isDead,      "thread.isDead");      fielda(t, -2, "isDead");
	
				newFunction(t, &threadIterator, "thread.iterator");
			newFunction(t, &threadApply, "thread.opApply", 1); fielda(t, -2, "opApply");
		setTypeMT(t, MDValue.Type.Thread);

		// The Function type's metatable
		newNamespace(t, "function");
			newFunction(t, &functionEnvironment, "function.environment"); fielda(t, -2, "environment");
			newFunction(t, &functionIsNative,    "function.isNative");    fielda(t, -2, "isNative");
			newFunction(t, &functionNumParams,   "function.numParams");   fielda(t, -2, "numParams");
			newFunction(t, &functionIsVararg,    "function.isVararg");    fielda(t, -2, "isVararg");
		setTypeMT(t, MDValue.Type.Function);
	}

	// ===================================================================================================================================
	// Object

	// function clone() = object : this {}
	uword objectClone(MDThread* t, uword numParams)
	{
		newObject(t, 0);
		return 1;
	}

	// ===================================================================================================================================
	// Basic functions
/*
	uword getTraceback(MDThread* t, uword numParams)
	{
		s.push(new MDString(s.context.getTracebackString()));
		return 1;
	}
*/
	uword haltThread(MDThread* t, uword numParams)
	{
		if(numParams == 0)
			.haltThread(t);
		else
		{
			auto thread = getThread(t, 1);
			pendingHalt(thread);

			auto reg = pushThread(t, thread);
			pushNull(t);
			rawCall(t, reg, 0);
		}

		return 0;
	}

	uword currentThread(MDThread* t, uword numParams)
	{
		if(t is mainThread(getVM(t)))
			pushNull(t);
		else
			pushThread(t, t);

		return 1;
	}
/*
	uword reloadModule(MDThread* t, uword numParams)
	{
		s.push(s.context.reloadModule(s.getParam!(MDString)(0).mData, s));
		return 1;
	}
*/

	uword runMain(MDThread* t, uword numParams)
	{
		checkParam(t, 1, MDValue.Type.Namespace);

		if(.hasField(t, 1, "main"))
		{
			auto main = field(t, 1, "main");
	
			if(isFunction(t, main))
			{
				insert(t, 1);
				rawCall(t, 1, 0);
			}
		}

		return 0;
	}

	// ===================================================================================================================================
	// Functional stuff

	uword curry(MDThread* t, uword numParams)
	{
		static uword call(MDThread* t, uword numParams)
		{
			auto funcReg = getUpval(t, 0);
			dup(t, 0);
			getUpval(t, 1);

			for(uword i = 1; i <= numParams; i++)
				dup(t, i);

			return rawCall(t, funcReg, -1);
		}

		checkParam(t, 1, MDValue.Type.Function);
		checkAnyParam(t, 2);

		newFunction(t, &call, "curryClosure", 2);
		return 1;
	}

	uword bindContext(MDThread* t, uword numParams)
	{
		static uword call(MDThread* t, uword numParams)
		{
			auto funcReg = getUpval(t, 0);
			getUpval(t, 1);

			for(uword i = 1; i <= numParams; i++)
				dup(t, i);

			return rawCall(t, funcReg, -1);
		}
		
		checkParam(t, 1, MDValue.Type.Function);
		checkAnyParam(t, 2);

		newFunction(t, &call, "boundFunction", 2);
		return 1;
	}

	// ===================================================================================================================================
	// Reflection-esque stuff

	uword findGlobal(MDThread* t, uword numParams)
	{
		if(!.findGlobal(t, checkStringParam(t, 1)))
			pushNull(t);

		return 1;
	}

	uword isSet(MDThread* t, uword numParams)
	{
		if(!.findGlobal(t, checkStringParam(t, 1)))
			pushBool(t, false);
		else
		{
			pop(t);
			pushBool(t, true);
		}

		return 1;
	}

	uword mdtypeof(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		pushString(t, MDValue.typeString(type(t, 1)));
		return 1;
	}

	uword fieldsOf(MDThread* t, uword numParams)
	{
		checkObjParam(t, 1);
		.fieldsOf(t, 1);
		return 1;
	}

	uword allFieldsOf(MDThread* t, uword numParams)
	{
		// Upvalue 0 is the current object
		// Upvalue 1 is the current index into the namespace
		static uword iter(MDThread* t, uword numParams)
		{
			MDString** key = void;
			MDValue* value = void;
			uword index = void;

			while(true)
			{
				getUpval(t, 0);
				auto o = getObject(t, -1);

				getUpval(t, 1);
				index = getInt(t, -1);

				if(!obj.next(o, index, key, value))
				{
					superOf(t, -2);
	
					if(isNull(t, -1))
						return 0;
	
					setUpval(t, 0);
					pushInt(t, -1);
					setUpval(t, 1);
					pop(t, 2);

					// try again
					continue;
				}

				break;
			}

			pop(t, 2);

			pushInt(t, index);
			setUpval(t, 1);
	
			pushStringObj(t, *key);
			push(t, *value);

			return 2;
		}

		checkParam(t, 1, MDValue.Type.Object);
		dup(t, 1);
		pushInt(t, 0);
		newFunction(t, &iter, "allFieldsOfIter", 2);
		return 1;
	}

	uword hasField(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		auto n = checkStringParam(t, 2);
		pushBool(t, .hasField(t, 1, n));
		return 1;
	}

	uword hasMethod(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		auto n = checkStringParam(t, 2);
		pushBool(t, .hasMethod(t, 1, n));
		return 1;
	}
	
	uword rawSetField(MDThread* t, uword numParams)
	{
		checkObjParam(t, 1);
		checkStringParam(t, 2);
		checkAnyParam(t, 3);
		dup(t, 2);
		dup(t, 3);
		fielda(t, 1, true);
		return 0;
	}

	uword rawGetField(MDThread* t, uword numParams)
	{
		checkObjParam(t, 1);
		checkStringParam(t, 2);
		dup(t, 2);
		field(t, 1, true);
		return 1;
	}

	uword attrs(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		checkParam(t, 2, MDValue.Type.Table);
		dup(t, 2);
		setAttributes(t, 1);
		dup(t, 1);
		return 1;
	}

	uword hasAttributes(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		pushBool(t, .hasAttributes(t, 1));
		return 1;
	}

	uword attributesOf(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		getAttributes(t, 1);
		return 1;
	}

	uword isParam(MDValue.Type Type)(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		pushBool(t, type(t, 1) == Type);
		return 1;
	}

	// ===================================================================================================================================
	// Conversions

	uword toString(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);

		if(isInt(t, 1))
		{
			char[1] style = "d";

			if(numParams > 1)
				style[0] = getChar(t, 2);

			char[80] buffer = void;
			pushString(t, safeCode(t, Integer.format(buffer, getInt(t, 1), style)));
		}
		else
			pushToString(t, 1);

		return 1;
	}

	uword rawToString(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		pushToString(t, 1, true);
		return 1;
	}

	uword toBool(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		pushBool(t, isTrue(t, 1));
		return 1;
	}

	uword toInt(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);

		switch(type(t, 1))
		{
			case MDValue.Type.Bool:   pushInt(t, cast(mdint)getBool(t, 1)); break;
			case MDValue.Type.Int:    dup(t, 1); break;
			case MDValue.Type.Float:  pushInt(t, cast(mdint)getFloat(t, 1)); break;
			case MDValue.Type.Char:   pushInt(t, cast(mdint)getChar(t, 1)); break;
			case MDValue.Type.String: pushInt(t, safeCode(t, cast(mdint)Integer.parse(getString(t, 1), 10))); break;

			default:
				pushTypeString(t, 1);
				throwException(t, "Cannot convert type '{}' to int", getString(t, -1));
		}

		return 1;
	}

	uword toFloat(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);

		switch(type(t, 1))
		{
			case MDValue.Type.Bool: pushFloat(t, cast(mdfloat)getBool(t, 1)); break;
			case MDValue.Type.Int: pushFloat(t, cast(mdfloat)getInt(t, 1)); break;
			case MDValue.Type.Float: dup(t, 1); break;
			case MDValue.Type.Char: pushFloat(t, cast(mdfloat)getChar(t, 1)); break;
			case MDValue.Type.String: pushFloat(t, safeCode(t, cast(mdfloat)Float.parse(getString(t, 1)))); break;

			default:
				pushTypeString(t, 1);
				throwException(t, "Cannot convert type '{}' to float", getString(t, -1));
		}

		return 1;
	}

	uword toChar(MDThread* t, uword numParams)
	{
		pushChar(t, cast(dchar)checkIntParam(t, 1));
		return 1;
	}

	uword format(MDThread* t, uword numParams)
	{
		auto buf = StrBuffer(t);
		formatImpl(t, numParams, &buf.sink);
		buf.finish();
		return 1;
	}

	// ===================================================================================================================================
	// Console IO

	uword write(MDThread* t, uword numParams)
	{
		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);
			Stdout(getString(t, -1));
		}

		Stdout.flush;
		return 0;
	}

	uword writeln(MDThread* t, uword numParams)
	{
		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);
			Stdout(getString(t, -1));
		}

		Stdout.newline;
		return 0;
	}

	uword writef(MDThread* t, uword numParams)
	{
		uint sink(char[] data)
		{
			Stdout(data);
			return data.length;
		}

		formatImpl(t, numParams, &sink);
		Stdout.flush;
		return 0;
	}

	uword writefln(MDThread* t, uword numParams)
	{
		uint sink(char[] data)
		{
			Stdout(data);
			return data.length;
		}

		formatImpl(t, numParams, &sink);
		Stdout.newline;
		return 0;
	}

	uword dumpVal(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		auto newline = optBoolParam(t, 2, true);

		auto shown = getUpval(t, 0);

		void outputRepr(word v)
		{
			v = absIndex(t, v);

			if(hasPendingHalt(t))
				.haltThread(t);

			void escape(dchar c)
			{
				switch(c)
				{
					case '\'': Stdout(`\'`); break;
					case '\"': Stdout(`\"`); break;
					case '\\': Stdout(`\\`); break;
					case '\a': Stdout(`\a`); break;
					case '\b': Stdout(`\b`); break;
					case '\f': Stdout(`\f`); break;
					case '\n': Stdout(`\n`); break;
					case '\r': Stdout(`\r`); break;
					case '\t': Stdout(`\t`); break;
					case '\v': Stdout(`\v`); break;

					default:
						if(c <= 0x7f && isprint(c))
							Stdout(c);
						else if(c <= 0xFFFF)
							Stdout.format("\\u{:x4}", cast(uint)c);
						else
							Stdout.format("\\U{:x8}", cast(uint)c);
						break;
				}
			}

			void outputArray(word arr)
			{
				if(opin(t, arr, shown))
				{
					Stdout("[...]");
					return;
				}

				dup(t, arr);
				pushBool(t, true);
				idxa(t, shown);

				scope(exit)
				{
					dup(t, arr);
					pushNull(t);
					idxa(t, shown);
				}

				Stdout('[');
				
				auto length = len(t, arr);

				if(length > 0)
				{
					pushInt(t, 0);
					idx(t, arr);
					outputRepr(-1);
					pop(t);

					for(uword i = 1; i < length; i++)
					{
						if(hasPendingHalt(t))
							.haltThread(t);

						Stdout(", ");
						pushInt(t, i);
						idx(t, arr);
						outputRepr(-1);
						pop(t);
					}
				}

				Stdout(']');
			}

			void outputTable(word tab)
			{
				if(opin(t, tab, shown))
				{
					Stdout("{...}");
					return;
				}
				
				dup(t, tab);
				pushBool(t, true);
				idxa(t, shown);
				
				scope(exit)
				{
					dup(t, tab);
					pushNull(t);
					idxa(t, shown);
				}

				Stdout('{');

				auto length = len(t, tab);

				if(length > 0)
				{
					bool first = true;
					dup(t, tab);

					foreach(word k, word v; foreachLoop(t, 1))
					{
						if(first)
							first = !first;
						else
							Stdout(", ");

						if(hasPendingHalt(t))
							.haltThread(t);

						Stdout('[');
						outputRepr(k);
						Stdout("] = ");
						dup(t, v);
						outputRepr(-1);
						pop(t);
					}
				}

				Stdout('}');
			}
			
			void outputNamespace(word ns)
			{
				if(opin(t, ns, shown))
				{
					pushToString(t, ns);
					Stdout(getString(t, -1))(" {...}");
					pop(t);
					return;
				}
				
				dup(t, ns);
				pushBool(t, true);
				idxa(t, shown);
				
				scope(exit)
				{
					dup(t, ns);
					pushNull(t);
					idxa(t, shown);
				}

				pushToString(t, ns);
				Stdout(getString(t, -1))(" {").newline;
				pop(t);

				auto length = len(t, ns);

				if(length > 0)
				{
					dup(t, ns);

					foreach(word k, word v; foreachLoop(t, 1))
					{
						if(hasPendingHalt(t))
							.haltThread(t);

						Stdout(getString(t, k))(" = ");
						dup(t, v);
						outputRepr(-1);
						pop(t);
						Stdout.newline;
					}
				}

				Stdout('}');
			}

			if(isString(t, v))
			{
				Stdout('"');
				
				foreach(c; getString(t, v))
					escape(c);

				Stdout('"');
			}
			else if(isChar(t, v))
			{
				Stdout("'");
				escape(getChar(t, v));
				Stdout("'");
			}
			else if(isArray(t, v))
				outputArray(v);
			else if(isTable(t, v) && !.hasMethod(t, v, "toString"))
				outputTable(v);
			else if(isNamespace(t, v))
				outputNamespace(v);
			else
			{
				pushToString(t, v);
				Stdout(getString(t, -1));
				pop(t);
			}
		}

		outputRepr(1);
		
		if(newline)
			Stdout.newline;

		return 0;
	}

	uword readln(MDThread* t, uword numParams)
	{
		char[] s;
		Cin.readln(s);
		pushString(t, s);
		return 1;
	}

	// ===================================================================================================================================
	// Dynamic Compilation

	uword loadString(MDThread* t, uword numParams)
	{
		auto code = checkStringParam(t, 1);
		char[] name = "<loaded by loadString>";

		if(numParams > 1)
		{
			if(isString(t, 2))
			{
				name = getString(t, 2);

				if(numParams > 2)
				{
					checkParam(t, 3, MDValue.Type.Namespace);
					dup(t, 3);
				}
				else
					pushEnvironment(t, 1);
			}
			else
			{
				checkParam(t, 2, MDValue.Type.Namespace);
				dup(t, 2);
			}
		}
		else
			pushEnvironment(t, 1);
			
		scope c = new Compiler(t);
		c.compileStatements(code, name);
		insert(t, -2);
		setFuncEnv(t, -2);
		return 1;
	}

	uword eval(MDThread* t, uword numParams)
	{
		auto code = checkStringParam(t, 1);
		scope c = new Compiler(t);
		c.compileExpression(code, "<loaded by eval>");

		if(numParams > 1)
		{
			checkParam(t, 2, MDValue.Type.Namespace);
			dup(t, 2);
		}
		else
			pushEnvironment(t, 1);

		setFuncEnv(t, -2);
		pushNull(t);
		return rawCall(t, -2, -1);
	}

/*
	uword loadJSON(MDThread* t, uword numParams)
	{
		s.push(Compiler().loadJSON(s.getParam!(dchar[])(0)));
		return 1;
	}

	uword toJSON(MDThread* t, uword numParams)
	{
		MDValue root = s.getParam(0u);
		bool pretty = false;

		if(numParams > 1)
			pretty = s.getParam!(bool)(1);

		scope cond = new GrowBuffer();
		scope printer = new Print!(dchar)(FormatterD, cond);

		toJSONImpl(s, root, pretty, printer);

		s.push(cast(dchar[])cond.slice());
		return 1;
	}
*/

	// ===================================================================================================================================
	// Thread metatable

	uword threadReset(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);

		if(optParam(t, 1, MDValue.Type.Function))
		{
			dup(t, 1);
			resetThread(t, 0, true);
		}
		else
			resetThread(t, 0);

		return 0;
	}

	uword threadState(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		pushInt(t, state(getThread(t, 0)));
		return 1;
	}

	uword isInitial(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		pushBool(t, state(getThread(t, 0)) == MDThread.State.Initial);
		return 1;
	}

	uword isRunning(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		pushBool(t, state(getThread(t, 0)) == MDThread.State.Running);
		return 1;
	}

	uword isWaiting(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		pushBool(t, state(getThread(t, 0)) == MDThread.State.Waiting);
		return 1;
	}

	uword isSuspended(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		pushBool(t, state(getThread(t, 0)) == MDThread.State.Suspended);
		return 1;
	}

	uword isDead(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		pushBool(t, state(getThread(t, 0)) == MDThread.State.Dead);
		return 1;
	}
	
	uword threadIterator(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		auto thread = getThread(t, 0);

		pushInt(t, checkIntParam(t, 1) + 1);

		auto slot = pushThread(t, thread);
		pushNull(t);
		auto numRets = rawCall(t, slot, -1);

		if(state(thread) == MDThread.State.Dead)
			return 0;

		return numRets + 1;
	}

	uword threadApply(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		auto haveParam = isValidIndex(t, 1);
		auto thread = getThread(t, 0);

		if(state(thread) != MDThread.State.Initial)
			throwException(t, "Iterated coroutine must be in the initial state");

		auto slot = pushThread(t, thread);
		dup(t);

		if(haveParam)
			dup(t, 1);
		else
			pushNull(t);

		rawCall(t, slot, 0);

		getUpval(t, 0);
		pushThread(t, thread);
		pushInt(t, -1);
		return 3;
	}

	// ===================================================================================================================================
	// Function metatable

	uword functionEnvironment(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Function);
		getFuncEnv(t, 0);

		if(numParams > 0)
		{
			checkParam(t, 1, MDValue.Type.Namespace);
			dup(t, 1);
			setFuncEnv(t, 0);
		}

		return 1;
	}

	uword functionIsNative(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Function);
		pushBool(t, func.isNative(getFunction(t, 0)));
		return 1;
	}

	uword functionNumParams(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Function);
		pushInt(t, func.numParams(getFunction(t, 0)));
		return 1;
	}

	uword functionIsVararg(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Function);
		pushBool(t, func.isVararg(getFunction(t, 0)));
		return 1;
	}

	// ===================================================================================================================================
	// StringBuffer

	struct StringBufferObj
	{
	static:
		struct Members
		{
			dchar[] data;
			uword length = 0;
		}

		void init(MDThread* t)
		{
			CreateObject(t, "StringBuffer", (CreateObject* o)
			{
					newFunction(t, &finalizer, "StringBuffer.finalizer");
				o.method("clone",          &clone, 1);

				o.method("append",         &opCatAssign);
				o.method("insert",         &insert);
				o.method("remove",         &remove);
				o.method("toString",       &toString);
				o.method("opLengthAssign", &opLengthAssign);
				o.method("opLength",       &opLength);
				o.method("opIndex",        &opIndex);
				o.method("opIndexAssign",  &opIndexAssign);
				o.method("opSlice",        &opSlice);
				o.method("opSliceAssign",  &opSliceAssign);
				o.method("reserve",        &reserve);
				o.method("format",         &format);
				o.method("formatln",       &formatln);

					newFunction(t, &iterator, "StringBuffer.iterator");
					newFunction(t, &iteratorReverse, "StringBuffer.iteratorReverse");
				o.method("opApply", &opApply, 2);
			});

			field(t, -1, "append");
			fielda(t, -2, "opCatAssign");

			newGlobal(t, "StringBuffer");
		}

		private Members* getThis(MDThread* t)
		{
			return checkObjParam!(Members)(t, 0, "StringBuffer");
		}

		private void resize(MDThread* t, Members* memb, uword length)
		{
			if(length > (memb.data.length - memb.length))
				t.vm.alloc.resizeArray(memb.data, memb.data.length + length);
		}
		
		private void append(MDThread* t, Members* memb, char[] str, uword cpLength)
		{
			resize(t, memb, cpLength);
			uint ate = 0;
			Utf.toString32(str, memb.data[memb.length .. $], &ate);
			assert(ate == str.length);
			memb.length += cpLength;
		}

		uword finalizer(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			t.vm.alloc.resizeArray(memb.data, 0);
			memb.length = 0;
			return 0;
		}

		uword clone(MDThread* t, uword numParams)
		{
			auto ret = newObject(t, 0, null, 0, Members.sizeof);
			auto memb = getMembers!(Members)(t, ret);
			*memb = Members.init;

			if(numParams > 0)
			{
				if(isInt(t, 1))
				{
					auto size = getInt(t, 1);

					if(size < 0)
						throwException(t, "Size must be >= 0, not {}", size);

					t.vm.alloc.resizeArray(memb.data, size);
				}
				else if(isString(t, 1))
				{
					auto length = len(t, 1);
					t.vm.alloc.resizeArray(memb.data, length);
					memb.length = length;
					auto str = getString(t, 1);
					uint ate = 0;
					Utf.toString32(str, memb.data, &ate);
				}
				else
					paramTypeError(t, 1, "int|string");
			}
			else
				t.vm.alloc.resizeArray(memb.data, 32);
				
			getUpval(t, 0);
			setFinalizer(t, -2);

			return 1;
		}

		uword opCatAssign(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			auto sb = pushGlobal(t, "StringBuffer");

			for(uword i = 1; i <= numParams; i++)
			{
				if(as(t, i, sb))
				{
					auto other = getMembers!(Members)(t, i);
					resize(t, memb, other.length);
					memb.data[memb.length .. $] = other.data[0 .. other.length];
					memb.length += other.length;
				}
				else
				{
					pushToString(t, i);
					auto str = getStringObj(t, -1);
					append(t, memb, str.toString(), str.cpLength);
					pop(t);
				}
			}

			return 0;
		}

		uword insert(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			auto idx = checkIntParam(t, 1);
			checkAnyParam(t, 2);

			if(idx < 0 || idx > memb.length)
				throwException(t, "Invalid index {} (valid indices are [0 .. {}])", idx, memb.length);

			pushGlobal(t, "StringBuffer");

			if(as(t, 2, -1))
			{
				auto other = getMembers!(Members)(t, 2);
				resize(t, memb, other.length);
				memmove(&memb.data[idx + other.length], &memb.data[idx], other.length * dchar.sizeof);
				memb.data[idx .. idx + other.length] = other.data[0 .. other.length];
				memb.length += other.length;
			}
			else
			{
				pushToString(t, 2);
				auto str = getStringObj(t, -1);
				resize(t, memb, str.cpLength);
				memmove(&memb.data[idx + str.cpLength], &memb.data[idx], str.cpLength * dchar.sizeof);
				uint ate = 0;
				Utf.toString32(str.toString(), memb.data[idx .. idx + str.cpLength], &ate);
				assert(ate == str.toString().length);
				memb.length += str.cpLength;
			}

			return 0;
		}

		uword remove(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);

			// start is in the range [0 .. memb.length]
			// end is in the range [start .. memb.length]
			// if start == end, no-op.

			auto start = checkIntParam(t, 1);

			if(start < 0)
				start += memb.length;

			if(start < 0 || start > memb.length)
				throwException(t, "Invalid start index: {} (buffer length: {})", start, memb.length);

			auto end = optIntParam(t, 2, start + 1);

			if(end < 0)
				end += memb.length;

			if(end < start || end > memb.length)
				throwException(t, "Invalid indices: {} .. {} (buffer length: {})", start, end, memb.length);

			if(start == end)
				return 0;

			memmove(&memb.data[start], &memb.data[end], (memb.length - end) * dchar.sizeof);
			memb.length -= (end - start);

			if(memb.length < (memb.data.length >> 2))
				t.vm.alloc.resizeArray(memb.data, memb.data.length >> 2);

			return 0;
		}

		uword toString(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			pushFormat(t, "{}", memb.data[0 .. memb.length]);
			return 1;
		}

		uword opLengthAssign(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			auto newLen = checkIntParam(t, 1);

			if(newLen < 0)
				throwException(t, "Invalid length: {}", newLen);

			auto oldLen = memb.length;
			memb.length = newLen;

			if(memb.length > memb.data.length)
				t.vm.alloc.resizeArray(memb.data, memb.length);

			if(newLen > oldLen)
				memb.data[oldLen .. newLen] = dchar.init;

			return 0;
		}

		uword opLength(MDThread* t, uword numParams)
		{
			pushInt(t, getThis(t).length);
			return 1;
		}

		uword opIndex(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			auto index = checkIntParam(t, 1);

			if(index < 0)
				index += memb.length;

			if(index < 0 || index >= memb.length)
				throwException(t, "Invalid index: {} (buffer length: {})", index, memb.length);

			pushChar(t, memb.data[index]);
			return 1;
		}

		uword opIndexAssign(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			auto index = checkIntParam(t, 1);
			auto ch = checkCharParam(t, 2);

			if(index < 0)
				index += memb.length;

			if(index < 0 || index >= memb.length)
				throwException(t, "Invalid index: {} (buffer length: {})", index, memb.length);

			memb.data[index] = ch;
			return 0;
		}

		uword iterator(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			auto index = checkIntParam(t, 1) + 1;

			if(index >= memb.length)
				return 0;

			pushInt(t, index);
			pushChar(t, memb.data[index]);

			return 2;
		}

		uword iteratorReverse(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			auto index = checkIntParam(t, 1) - 1;

			if(index < 0)
				return 0;

			pushInt(t, index);
			pushChar(t, memb.data[index]);

			return 2;
		}

		uword opApply(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);

			if(optStringParam(t, 1, "") == "reverse")
			{
				getUpval(t, 1);
				dup(t, 0);
				pushInt(t, memb.length);
			}
			else
			{
				getUpval(t, 0);
				dup(t, 0);
				pushInt(t, -1);
			}

			return 3;
		}

		uword opSlice(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			auto lo = optIntParam(t, 1, 0);
			auto hi = optIntParam(t, 2, -1);

			if(lo < 0)
				lo += memb.length;

			if(lo < 0 || lo > memb.length)
				throwException(t, "Invalid low index: {} (buffer length: {})", lo, memb.length);

			if(hi < 0)
				hi += memb.length;

			if(hi < lo || hi > memb.length)
				throwException(t, "Invalid slice indices: {} .. {} (buffer length: {})", lo, hi, memb.length);

			pushFormat(t, "{}", memb.data[lo .. hi]);
			return 1;
		}

		uword opSliceAssign(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			auto lo = optIntParam(t, 1, 0);
			auto hi = optIntParam(t, 2, -1);
			checkAnyParam(t, 3);

			if(lo < 0)
				lo += memb.length;

			if(lo < 0 || lo > memb.length)
				throwException(t, "Invalid low index: {} (buffer length: {})", lo, memb.length);

			if(hi < 0)
				hi += memb.length;

			if(hi < lo || hi > memb.length)
				throwException(t, "Invalid slice indices: {} .. {} (buffer length: {})", lo, hi, memb.length);

			auto sliceLen = hi - lo;

			if(isChar(t, 3))
				memb.data[lo .. hi] = getChar(t, 3);
			else if(isString(t, 3))
			{
				auto str = getStringObj(t, 3);

				if(str.cpLength != sliceLen)
					throwException(t, "Slice length ({}) does not match length of string ({})", sliceLen, str.cpLength);

				uint ate = 0;
				Utf.toString32(str.toString(), memb.data[lo .. hi], &ate);
				assert(ate == str.toString().length);
			}
			else
			{
				pushGlobal(t, "StringBuffer");
				
				if(as(t, 3, -1))
				{
					auto other = getMembers!(Members)(t, 3);
					
					if(other.length != sliceLen)
						throwException(t, "Slice length ({}) does not match length of string buffer ({})", sliceLen, other.length);
						
					memb.data[lo .. hi] = other.data[0 .. other.length];
				}
				else
					paramTypeError(t, 3, "char|string|StringBuffer");
			}

			return 0;
		}

		uword reserve(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			auto newLen = checkIntParam(t, 1);

			if(newLen > memb.data.length)
				t.vm.alloc.resizeArray(memb.data, newLen);

			return 0;
		}

		uword format(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);

			uint sink(char[] data)
			{
				append(t, memb, data, verify(data));
				return data.length;
			}

			formatImpl(t, numParams, &sink);
			return 0;
		}

		uword formatln(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);

			uint sink(char[] data)
			{
				append(t, memb, data, verify(data));
				return data.length;
			}

			formatImpl(t, numParams, &sink);
			append(t, memb, "\n", 1);
			return 0;
		}
	}
}