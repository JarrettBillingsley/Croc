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
import utf = tango.text.convert.Utf;

import minid.ex;
import minid.func;
import minid.interpreter;
import minid.misc;
import minid.namespace;
import minid.obj;
import minid.string;
import minid.types;
import minid.vm;

private void register(MDThread* t, dchar[] name, NativeFunc func, uword numUpvals = 0)
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
		auto s = pushObject(t, obj.create(t.vm.alloc, string.create(t.vm, "Object"), null));
		newFunction(t, &objectClone, "Object.clone");
		fielda(t, s, "clone");
		newGlobal(t, "Object");

		// StringBuffer
// 		globals["StringBuffer"d] =    new MDStringBufferClass(_Object);

		// Really basic stuff
// 		globals["getTraceback"d] =    new MDClosure(globals.ns, &getTraceback,          "getTraceback");
// 		globals["haltThread"d] =      new MDClosure(globals.ns, &haltThread,            "haltThread");
		register(t, "currentThread", &currentThread);
// 		globals["setModuleLoader"d] = new MDClosure(globals.ns, &setModuleLoader,       "setModuleLoader");
// 		globals["reloadModule"d] =    new MDClosure(globals.ns, &reloadModule,          "reloadModule");
		register(t, "removeKey", &removeKey);
		register(t, "rawSet", &rawSet);
		register(t, "rawGet", &rawGet);
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
// 		globals["hasAttributes"d] =   new MDClosure(globals.ns, &hasAttributes,         "hasAttributes");
// 		globals["attributesOf"d] =    new MDClosure(globals.ns, &attributesOf,          "attributesOf");
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

		newTable(t);
		register(t, "dumpVal", &dumpVal, 1);

// 		register(t, "readln", &readln);

		// Dynamic compilation stuff
// 		globals["loadString"d] =      new MDClosure(globals.ns, &loadString,            "loadString");
// 		globals["eval"d] =            new MDClosure(globals.ns, &eval,                  "eval");
// 		globals["loadJSON"d] =        new MDClosure(globals.ns, &loadJSON,              "loadJSON");
// 		globals["toJSON"d] =          new MDClosure(globals.ns, &toJSON,                "toJSON");

		// The Namespace type's metatable
		newNamespace(t, "namespace");
		
		newFunction(t, &namespaceApply, "namespace.opApply"); fielda(t, -2, "opApply");

		setTypeMT(t, MDValue.Type.Namespace);

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
		newFunction(t, &threadApply, "thread.opApply", 1);
		fielda(t, -2, "opApply");

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

	uword objectClone(MDThread* t, uword numParams)
	{
		newObject(t, 0);
		return 1;
	}
	
/*
	// ===================================================================================================================================
	// Basic functions

	uword getTraceback(MDThread* t, uword numParams)
	{
		s.push(new MDString(s.context.getTracebackString()));
		return 1;
	}

	uword haltThread(MDThread* t, uword numParams)
	{
		if(numParams == 0)
			s.halt();
		else
		{
			auto thread = s.getParam!(MDState)(0);
			thread.pendingHalt();
			s.call(thread, 0);
		}

		return 0;
	}
*/

	uword currentThread(MDThread* t, uword numParams)
	{
		if(t is mainThread(getVM(t)))
			pushNull(t);
		else
			pushThread(t, t);

		return 1;
	}
/*
	uword setModuleLoader(MDThread* t, uword numParams)
	{
		s.context.setModuleLoader(s.getParam!(dchar[])(0), s.getParam!(MDClosure)(1));
		return 0;
	}

	uword reloadModule(MDThread* t, uword numParams)
	{
		s.push(s.context.reloadModule(s.getParam!(MDString)(0).mData, s));
		return 1;
	}
*/
	uword removeKey(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);

		if(isTable(t, 1))
		{
			checkAnyParam(t, 2);
			dup(t, 2);
			pushNull(t);
			idxa(t, 1);
		}
		else if(isNamespace(t, 1))
		{
			checkStringParam(t, 2);

			if(!opin(t, 2, 1))
			{
				pushToString(t, 2);
				throwException(t, "Key '{}' does not exist in namespace '{}'", getString(t, 2), getString(t, -1));
			}

			// TODO: is this OK?
			namespace.remove(getNamespace(t, 1), getStringObj(t, 2));
		}
		else
			paramTypeError(t, 1, "table|namespace");
			
		return 0;
	}

	uword rawSet(MDThread* t, uword numParams)
	{
		if(numParams < 3)
			throwException(t, "3 parameters expected; only got {}", numParams);

		if(isTable(t, 1))
			idxa(t, 1, true);
		else if(isObject(t, 1))
			fielda(t, 1, true);
		else
		{
			pushTypeString(t, 1);
			throwException(t, "'table' or 'object' expected, not '{}'", getString(t, -1));
		}

		return 0;
	}

	uword rawGet(MDThread* t, uword numParams)
	{
		if(numParams < 2)
			throwException(t, "2 parameters expected; only got {}", numParams);

		if(isTable(t, 1))
			idx(t, 1, true);
		else if(isObject(t, 1))
			field(t, 1, true);
		else
		{
			pushTypeString(t, 1);
			throwException(t, "'table' or 'object' expected, not '{}'", getString(t, -1));
		}

		return 1;
	}

	uword runMain(MDThread* t, uword numParams)
	{
		checkParam(t, 1, MDValue.Type.Namespace);

		auto main = field(t, 1, "main");

		if(isFunction(t, main))
		{
			insert(t, 1);
			rawCall(t, 1, 0);
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
			getUpval(t, 0);
			auto o = getObject(t, -1);

			getUpval(t, 1);
			ptrdiff_t index = getInt(t, -1);

			MDString** key = void;
			MDValue* value = void;

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
				return iter(t, numParams);
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
		pushInt(t, -1);
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

/*
	uword hasAttributes(MDThread* t, uword numParams)
	{
		MDTable ret;

		if(s.isParam!("function")(0))
			ret = s.getParam!(MDClosure)(0).attributes;
		else if(s.isParam!("object")(0))
			ret = s.getParam!(MDObject)(0).attributes;
		else if(s.isParam!("namespace")(0))
			ret = s.getParam!(MDNamespace)(0).attributes;

		s.push(ret !is null);
		return 1;
	}

	uword attributesOf(MDThread* t, uword numParams)
	{
		MDTable ret;

		if(s.isParam!("function")(0))
			ret = s.getParam!(MDClosure)(0).attributes;
		else if(s.isParam!("object")(0))
			ret = s.getParam!(MDObject)(0).attributes;
		else if(s.isParam!("namespace")(0))
			ret = s.getParam!(MDNamespace)(0).attributes;
		else
			s.throwRuntimeException("Expected function, class, or namespace, not '{}'", s.getParam(0u).typeString());

		if(ret is null)
			s.pushNull();
		else
			s.push(ret);

		return 1;
	}
*/
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
			dchar[1] style = "d";

			if(numParams > 1)
				style[0] = getChar(t, 2);

			dchar[80] buffer = void;
			pushString(t, Integer.format(buffer, getInt(t, 1), style)); // TODO: make this safe
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
			case MDValue.Type.String: pushInt(t, cast(mdint)Integer.parse(getString(t, 1), 10)); break; // TODO: make this safe

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
			case MDValue.Type.String: pushFloat(t, cast(mdfloat)Float.parse(getString(t, 1))); break; // TODO: make this safe

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
		uint sink(dchar[] data)
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
		uint sink(dchar[] data)
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
				haltThread(t);

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
							haltThread(t);

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

				// TODO: this
// 				if(length > 0)
// 				{
// 					if(length == 1)
// 					{
// 						foreach(k, v; t)
// 						{
// 							if(s.hasPendingHalt())
// 								throw new MDHaltException();
//
// 							Stdout('[');
// 							outputRepr(k);
// 							Stdout("] = ");
// 							outputRepr(v);
// 						}
// 					}
// 					else
// 					{
// 						bool first = true;
// 	
// 						foreach(k, v; t)
// 						{
// 							if(first)
// 								first = !first;
// 							else
// 								Stdout(", ");
// 								
// 							if(s.hasPendingHalt())
// 								throw new MDHaltException();
// 	
// 							Stdout('[');
// 							outputRepr(k);
// 							Stdout("] = ");
// 							outputRepr(v);
// 						}
// 					}
// 				}
				Stdout('!');

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

/*
	uword readln(MDThread* t, uword numParams)
	{
		pushString(t, Cin.copyln());
		return 1;
	}

/*
	// ===================================================================================================================================
	// Dynamic Compilation

	uword loadString(MDThread* t, uword numParams)
	{
		char[] name;
		MDNamespace env;

		if(numParams > 1)
		{
			if(s.isParam!("string")(1))
			{
				name = s.getParam!(char[])(1);

				if(numParams > 2)
					env = s.getParam!(MDNamespace)(2);
				else
					env = s.environment(1);
			}
			else
				env = s.getParam!(MDNamespace)(1);
		}
		else
		{
			name = "<loaded by loadString>";
			env = s.environment(1);
		}

		MDFuncDef def = Compiler().compileStatements(s.getParam!(dchar[])(0), name);
		s.push(new MDClosure(env, def));
		return 1;
	}
	
	uword eval(MDThread* t, uword numParams)
	{
		MDFuncDef def = Compiler().compileExpression(s.getParam!(dchar[])(0), "<loaded by eval>");
		MDNamespace env;

		if(numParams > 1)
			env = s.getParam!(MDNamespace)(1);
		else
			env = s.environment(1);

		return s.call(new MDClosure(env, def), -1);
	}
	
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

	// ===================================================================================================================================
	// Namespace metatable
*/
	uword namespaceApply(MDThread* t, uword numParams)
	{
		static uword iter(MDThread* t, uword numParams)
		{
			getUpval(t, 0);
			auto ns = getNamespace(t, -1);
			pop(t);
	
			getUpval(t, 1);
			ptrdiff_t index = getInt(t, -1);
			pop(t);
	
			MDString** key = void;
			MDValue* value = void;
	
			if(!namespace.next(ns, index, key, value))
				return 0;
	
			pushInt(t, index);
			setUpval(t, 1);
	
			pushStringObj(t, *key);
			push(t, *value);
	
			return 2;
		}

		checkParam(t, 0, MDValue.Type.Namespace);
		dup(t, 0);
		pushInt(t, -1);
		newFunction(t, &iter, "namespaceIterator", 2);
		return 1;
	}

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
/*
	// ===================================================================================================================================
	// StringBuffer

	static class MDStringBufferClass : MDObject
	{
		MDClosure iteratorClosure;
		MDClosure iteratorReverseClosure;

		public this(MDObject owner)
		{
			super("StringBuffer", owner);

			iteratorClosure = new MDClosure(fields, &iterator, "StringBuffer.iterator");
			iteratorReverseClosure = new MDClosure(fields, &iteratorReverse, "StringBuffer.iteratorReverse");
			auto catEq = new MDClosure(fields, &opCatAssign, "StringBuffer.opCatAssign");

			fields.addList
			(
				"clone"d,          new MDClosure(fields, &clone,          "StringBuffer.clone"),
				"append"d,         catEq,
				"opCatAssign"d,    catEq,
				"insert"d,         new MDClosure(fields, &insert,         "StringBuffer.insert"),
				"remove"d,         new MDClosure(fields, &remove,         "StringBuffer.remove"),
				"toString"d,       new MDClosure(fields, &toString,       "StringBuffer.toString"),
				"opLengthAssign"d, new MDClosure(fields, &opLengthAssign, "StringBuffer.opLengthAssign"),
				"opLength"d,       new MDClosure(fields, &opLength,       "StringBuffer.opLength"),
				"opIndex"d,        new MDClosure(fields, &opIndex,        "StringBuffer.opIndex"),
				"opIndexAssign"d,  new MDClosure(fields, &opIndexAssign,  "StringBuffer.opIndexAssign"),
				"opApply"d,        new MDClosure(fields, &opApply,        "StringBuffer.opApply"),
				"opSlice"d,        new MDClosure(fields, &opSlice,        "StringBuffer.opSlice"),
				"opSliceAssign"d,  new MDClosure(fields, &opSliceAssign,  "StringBuffer.opSliceAssign"),
				"reserve"d,        new MDClosure(fields, &reserve,        "StringBuffer.reserve"),
				"format"d,         new MDClosure(fields, &format,         "StringBuffer.format"),
				"formatln"d,       new MDClosure(fields, &formatln,       "StringBuffer.formatln")
			);
		}

		public uword clone(MDThread* t, uword numParams)
		{
			MDStringBuffer ret;

			if(numParams > 0)
			{
				if(s.isParam!("int")(0))
					ret = new MDStringBuffer(this, s.getParam!(uint)(0));
				else if(s.isParam!("string")(0))
					ret = new MDStringBuffer(this, s.getParam!(dchar[])(0));
				else
					s.throwRuntimeException("'int' or 'string' expected for constructor, not '{}'", s.getParam(0u).typeString());
			}
			else
				ret = new MDStringBuffer(this);

			s.push(ret);
			return 1;
		}

		public uword opCatAssign(MDThread* t, uword numParams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);
			
			for(uint j = 0; j < numParams; j++)
			{
				MDValue param = s.getParam(j);

				if(param.isObj)
				{
					if(param.isObject)
					{
						MDStringBuffer other = cast(MDStringBuffer)param.as!(MDObject);
		
						if(other)
						{
							i.append(other);
							continue;
						}
					}
		
					i.append(s.valueToString(param));
				}
				else
					i.append(param.toString());
			}
			
			return 0;
		}

		public uword insert(MDThread* t, uword numParams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);
			MDValue param = s.getParam(1u);

			if(param.isObj)
			{
				if(param.isObject)
				{
					MDStringBuffer other = cast(MDStringBuffer)param.as!(MDObject);

					if(other)
					{
						i.insert(s.getParam!(int)(0), other);
						return 0;
					}
				}
				
				i.insert(s.getParam!(int)(0), s.valueToString(param));
			}
			else
				i.insert(s.getParam!(int)(0), param.toString());

			return 0;
		}

		public uword remove(MDThread* t, uword numParams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);
			uint start = s.getParam!(uint)(0);
			uint end = start + 1;

			if(numParams > 1)
				end = s.getParam!(uint)(1);

			i.remove(start, end);
			return 0;
		}
		
		public uword toString(MDThread* t, uword numParams)
		{
			s.push(s.getContext!(MDStringBuffer).toMDString());
			return 1;
		}
		
		public uword opLengthAssign(MDThread* t, uword numParams)
		{
			int newLen = s.getParam!(int)(0);
			
			if(newLen < 0)
				s.throwRuntimeException("Invalid length ({})", newLen);

			s.getContext!(MDStringBuffer).length = newLen;
			return 0;
		}

		public uword opLength(MDThread* t, uword numParams)
		{
			s.push(s.getContext!(MDStringBuffer).length);
			return 1;
		}
		
		public uword opIndex(MDThread* t, uword numParams)
		{
			s.push(s.getContext!(MDStringBuffer)()[s.getParam!(int)(0)]);
			return 1;
		}

		public uword opIndexAssign(MDThread* t, uword numParams)
		{
			s.getContext!(MDStringBuffer)()[s.getParam!(int)(0)] = s.getParam!(dchar)(1);
			return 0;
		}

		public uword iterator(MDThread* t, uword numParams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);
			int index = s.getParam!(int)(0);

			index++;

			if(index >= i.length)
				return 0;

			s.push(index);
			s.push(i[index]);

			return 2;
		}
		
		public uword iteratorReverse(MDThread* t, uword numParams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);
			int index = s.getParam!(int)(0);
			
			index--;
	
			if(index < 0)
				return 0;
				
			s.push(index);
			s.push(i[index]);
			
			return 2;
		}
		
		public uword opApply(MDThread* t, uword numParams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);

			if(s.isParam!("string")(0) && s.getParam!(MDString)(0) == "reverse"d)
			{
				s.push(iteratorReverseClosure);
				s.push(i);
				s.push(cast(int)i.length);
			}
			else
			{
				s.push(iteratorClosure);
				s.push(i);
				s.push(-1);
			}

			return 3;
		}

		public uword opSlice(MDThread* t, uword numParams)
		{
			s.push(s.getContext!(MDStringBuffer)()[s.getParam!(int)(0) .. s.getParam!(int)(1)]);
			return 1;
		}
		
		public uword opSliceAssign(MDThread* t, uword numParams)
		{
			s.getContext!(MDStringBuffer)()[s.getParam!(int)(0) .. s.getParam!(int)(1)] = s.getParam!(dchar[])(2);
			return 0;
		}

		public uword reserve(MDThread* t, uword numParams)
		{
			s.getContext!(MDStringBuffer).reserve(s.getParam!(uint)(0));
			return 0;
		}
		
		public uword format(MDThread* t, uword numParams)
		{
			auto self = s.getContext!(MDStringBuffer);

			uint sink(dchar[] data)
			{
				self.append(data);
				return data.length;
			}

			formatImpl(s, s.getAllParams(), &sink);
			return 0;
		}

		public uword formatln(MDThread* t, uword numParams)
		{
			auto self = s.getContext!(MDStringBuffer);

			uint sink(dchar[] data)
			{
				self.append(data);
				return data.length;
			}

			formatImpl(s, s.getAllParams(), &sink);
			self.append("\n"d);
			return 0;
		}
	}

	static class MDStringBuffer : MDObject
	{
		protected dchar[] mBuffer;
		protected uword mLength = 0;

		public this(MDStringBufferClass owner)
		{
			super("StringBuffer", owner);
			mBuffer = new dchar[32];
		}

		public this(MDStringBufferClass owner, uword size)
		{
			super("StringBuffer", owner);
			mBuffer = new dchar[size];
		}

		public this(MDStringBufferClass owner, dchar[] data)
		{
			super("StringBuffer", owner);
			mBuffer = data;
			mLength = mBuffer.length;
		}
		
		public void append(MDStringBuffer other)
		{
			resize(other.mLength);
			mBuffer[mLength .. mLength + other.mLength] = other.mBuffer[0 .. other.mLength];
			mLength += other.mLength;
		}

		public void append(MDString str)
		{
			resize(str.mData.length);
			mBuffer[mLength .. mLength + str.mData.length] = str.mData[];
			mLength += str.mData.length;
		}
		
		public void append(char[] s)
		{
			append(utf.toString32(s));
		}
		
		public void append(dchar[] s)
		{
			resize(s.length);
			mBuffer[mLength .. mLength + s.length] = s[];
			mLength += s.length;
		}
		
		public void insert(int offset, MDStringBuffer other)
		{
			if(offset > mLength)
				throw new MDException("Offset out of bounds: {}", offset);

			resize(other.mLength);
			
			for(int i = mLength + other.mLength - 1, j = mLength - 1; j >= offset; i--, j--)
				mBuffer[i] = mBuffer[j];
				
			mBuffer[offset .. offset + other.mLength] = other.mBuffer[0 .. other.mLength];
			mLength += other.mLength;
		}
		
		public void insert(int offset, MDString str)
		{
			if(offset > mLength)
				throw new MDException("Offset out of bounds: {}", offset);

			resize(str.mData.length);

			for(int i = mLength + str.mData.length - 1, j = mLength - 1; j >= offset; i--, j--)
				mBuffer[i] = mBuffer[j];

			mBuffer[offset .. offset + str.mData.length] = str.mData[];
			mLength += str.mData.length;
		}

		public void insert(int offset, char[] s)
		{
			if(offset > mLength)
				throw new MDException("Offset out of bounds: {}", offset);

			dchar[] str = utf.toString32(s);
			resize(str.length);

			for(int i = mLength + str.length - 1, j = mLength - 1; j >= offset; i--, j--)
				mBuffer[i] = mBuffer[j];

			mBuffer[offset .. offset + str.length] = str[];
			mLength += str.length;
		}
		
		public void remove(uint start, uint end)
		{
			if(end > mLength)
				end = mLength;

			if(start > mLength || start > end)
				throw new MDException("Invalid indices: {} .. {}", start, end);

			for(int i = start, j = end; j < mLength; i++, j++)
				mBuffer[i] = mBuffer[j];

			mLength -= (end - start);
		}

		public MDString toMDString()
		{
			return new MDString(mBuffer[0 .. mLength]);
		}
		
		public void length(uint len)
		{
			uint oldLength = mLength;
			mLength = len;

			if(mLength > mBuffer.length)
				mBuffer.length = mLength;
				
			if(mLength > oldLength)
				mBuffer[oldLength .. mLength] = dchar.init;
		}
		
		public uint length()
		{
			return mLength;
		}
		
		public dchar opIndex(int index)
		{
			if(index < 0)
				index += mLength;

			if(index < 0 || index >= mLength)
				throw new MDException("Invalid index: {}", index);

			return mBuffer[index];
		}

		public void opIndexAssign(dchar c, int index)
		{
			if(index < 0)
				index += mLength;

			if(index >= mLength)
				throw new MDException("Invalid index: {}", index);

			mBuffer[index] = c;
		}

		public dchar[] opSlice(int lo, int hi)
		{
			if(lo < 0)
				lo += mLength;

			if(hi < 0)
				hi += mLength;

			if(lo < 0 || lo > hi || hi >= mLength)
				throw new MDException("Invalid indices: {} .. {}", lo, hi);

			return mBuffer[lo .. hi];
		}

		public void opSliceAssign(dchar[] s, int lo, int hi)
		{
			if(lo < 0)
				lo += mLength;

			if(hi < 0)
				hi += mLength;

			if(lo < 0 || lo > hi || hi >= mLength)
				throw new MDException("Invalid indices: {} .. {}", lo, hi);

			if(hi - lo != s.length)
				throw new MDException("Slice length ({}) does not match length of string ({})", hi - lo, s.length);

			mBuffer[lo .. hi] = s[];
		}
		
		public void reserve(int size)
		{
			if(size > mBuffer.length)
				mBuffer.length = size;
		}

		protected void resize(uint length)
		{
			if(length > (mBuffer.length - mLength))
				mBuffer.length = mBuffer.length + length;
		}
	}

*/
}