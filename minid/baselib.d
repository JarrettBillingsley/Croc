/******************************************************************************
This module contains the 'baselib' part of the standard library.

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

import std.conv;
import std.ctype;
import std.stdio;

import minid.alloc;
import minid.classobj;
import minid.compiler;
import minid.ex;
import minid.instance;
import minid.interpreter;
import minid.misc;
import minid.string;
import minid.stringbuffer;
import minid.types;
import minid.utils;
import minid.vector;
import minid.vm;

private void register(MDThread* t, string name, NativeFunc func, uword numUpvals = 0)
{
	newFunction(t, func, name, numUpvals);
	newGlobal(t, name);
}

struct BaseLib
{
static:
	private const AttrTableName = "baselib.attributes";

	public void init(MDThread* t)
	{
		// Object
		pushClass(t, classobj.create(t.vm.alloc, createString(t, "Object"), null));
		newGlobal(t, "Object");

		// Vector
		VectorObj.init(t);

		// StringBuffer
		StringBufferObj.init(t);

		// GC
		makeModule(t, "gc", function uword(MDThread* t, uword numParams)
		{
			newFunction(t, &collectGarbage, "collect");   newGlobal(t, "collect");
			newFunction(t, &bytesAllocated, "allocated"); newGlobal(t, "allocated");
			return 0;
		});

		importModuleNoNS(t, "gc");

		// Functional stuff
		register(t, "curry", &curry);
		register(t, "bindContext", &bindContext);

		// Reflection-esque stuff
		register(t, "findGlobal", &findGlobal);
		register(t, "isSet", &isSet);
		register(t, "typeof", &mdtypeof);
		register(t, "nameOf", &nameOf);
		register(t, "fieldsOf", &fieldsOf);
		register(t, "allFieldsOf", &allFieldsOf);
		register(t, "hasField", &hasField);
		register(t, "hasMethod", &hasMethod);
		register(t, "findField", &findField);
		register(t, "rawSetField", &rawSetField);
		register(t, "rawGetField", &rawGetField);
		register(t, "getFuncEnv", &getFuncEnv);
		register(t, "setFuncEnv", &setFuncEnv);
		register(t, "isNull", &isParam!(MDValue.Type.Null));
		register(t, "isBool", &isParam!(MDValue.Type.Bool));
		register(t, "isInt", &isParam!(MDValue.Type.Int));
		register(t, "isFloat", &isParam!(MDValue.Type.Float));
		register(t, "isChar", &isParam!(MDValue.Type.Char));
		register(t, "isString", &isParam!(MDValue.Type.String));
		register(t, "isTable", &isParam!(MDValue.Type.Table));
		register(t, "isArray", &isParam!(MDValue.Type.Array));
		register(t, "isFunction", &isParam!(MDValue.Type.Function));
		register(t, "isClass", &isParam!(MDValue.Type.Class));
		register(t, "isInstance", &isParam!(MDValue.Type.Instance));
		register(t, "isNamespace", &isParam!(MDValue.Type.Namespace));
		register(t, "isThread", &isParam!(MDValue.Type.Thread));
		register(t, "isNativeObj", &isParam!(MDValue.Type.NativeObj));
		register(t, "isWeakRef", &isParam!(MDValue.Type.WeakRef));

		register(t, "attrs", &attrs);
		register(t, "hasAttributes", &hasAttributes);
		register(t, "attributesOf", &attributesOf);
		newTable(t);
		setRegistryVar(t, AttrTableName);

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
		register(t, "loadJSON", &loadJSON);
		register(t, "toJSON", &toJSON);

		// The Function type's metatable
		newNamespace(t, "function");
			newFunction(t, &functionIsNative,    "function.isNative");    fielda(t, -2, "isNative");
			newFunction(t, &functionNumParams,   "function.numParams");   fielda(t, -2, "numParams");
			newFunction(t, &functionIsVararg,    "function.isVararg");    fielda(t, -2, "isVararg");
		setTypeMT(t, MDValue.Type.Function);

		// Weak reference stuff
		register(t, "weakref", &weakref);
		register(t, "deref", &deref);
	}

	// ===================================================================================================================================
	// GC

	uword collectGarbage(MDThread* t, uword numParams)
	{
		pushInt(t, gc(t));
		return 1;
	}
	
	uword bytesAllocated(MDThread* t, uword numParams)
	{
		pushInt(t, .bytesAllocated(getVM(t)));
		return 1;
	}

	// ===================================================================================================================================
	// Functional stuff

	uword curry(MDThread* t, uword numParams)
	{
		static uword call(MDThread* t, uword numParams)
		{
			getUpval(t, 0);
			dup(t, 0);
			getUpval(t, 1);
			rotateAll(t, 3);
			return rawCall(t, 1, -1);
		}

		checkParam(t, 1, MDValue.Type.Function);
		checkAnyParam(t, 2);
		setStackSize(t, 3);
		newFunction(t, &call, "curryClosure", 2);
		return 1;
	}

	uword bindContext(MDThread* t, uword numParams)
	{
		static uword call(MDThread* t, uword numParams)
		{
			getUpval(t, 0);
			getUpval(t, 1);
			rotateAll(t, 2);
			return rawCall(t, 1, -1);
		}

		checkParam(t, 1, MDValue.Type.Function);
		checkAnyParam(t, 2);
		setStackSize(t, 3);
		newFunction(t, &call, "boundFunction", 2);
		return 1;
	}

	// ===================================================================================================================================
	// Reflection-esque stuff

	uword findGlobal(MDThread* t, uword numParams)
	{
		if(!.findGlobal(t, checkStringParam(t, 1), 1))
			pushNull(t);

		return 1;
	}

	uword isSet(MDThread* t, uword numParams)
	{
		if(!.findGlobal(t, checkStringParam(t, 1), 1))
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
	
	uword nameOf(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		
		switch(type(t, 1))
		{
			case MDValue.Type.Function:  pushString(t, funcName(t, 1)); break;
			case MDValue.Type.Class:     pushString(t, className(t, 1)); break;
			case MDValue.Type.Namespace: pushString(t, namespaceName(t, 1)); break;
			default:
				paramTypeError(t, 1, "function|class|namespace");
		}
		
		return 1;
	}

	uword fieldsOf(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		
		if(isClass(t, 1) || isInstance(t, 1))
			.fieldsOf(t, 1);
		else
			paramTypeError(t, 1, "class|instance");

		return 1;
	}

	uword allFieldsOf(MDThread* t, uword numParams)
	{
		// Upvalue 0 is the current object
		// Upvalue 1 is the current index into the namespace
		// Upvalue 2 is the duplicates table
		static uword iter(MDThread* t, uword numParams)
		{
			MDInstance* i;
			MDClass* c;
			MDString** key = void;
			MDValue* value = void;
			uword index = 0;

			while(true)
			{
				// Get the next field
				getUpval(t, 0);

				getUpval(t, 1);
				index = cast(uword)getInt(t, -1);
				pop(t);

				bool haveField = void;

				if(isInstance(t, -1))
				{
					i = getInstance(t, -1);
					c = null;
					haveField = instance.next(i, index, key, value);
				}
				else
				{
					c = getClass(t, -1);
					i = null;
					haveField = classobj.next(c, index, key, value);
				}

				if(!haveField)
				{
					superOf(t, -1);

					if(isNull(t, -1))
						return 0;

					setUpval(t, 0);
					pushInt(t, 0);
					setUpval(t, 1);
					pop(t);

					// try again
					continue;
				}

				// See if we've already seen this field
				getUpval(t, 2);
				pushStringObj(t, *key);

				if(opin(t, -1, -2))
				{
					pushInt(t, index);
					setUpval(t, 1);
					pop(t, 3);

					// We have, try again
					continue;
				}

				// Mark the field as seen
				pushBool(t, true);
				idxa(t, -3);
				pop(t, 3);

				break;
			}

			pushInt(t, index);
			setUpval(t, 1);

			pushStringObj(t, *key);
			push(t, *value);
			
			if(i is null)
				pushClass(t, c);
			else
				pushInstance(t, i);

			return 3;
		}

		checkAnyParam(t, 1);
		
		if(!isClass(t, 1) && !isInstance(t, 1))
			paramTypeError(t, 1, "class|instance");

		dup(t, 1);
		pushInt(t, 0);
		newTable(t);
		newFunction(t, &iter, "allFieldsOfIter", 3);
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

	uword findField(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		
		if(!isInstance(t, 1) && !isClass(t, 1))
			paramTypeError(t, 1, "class|instance");

		checkStringParam(t, 2);

		while(!isNull(t, 1))
		{
			auto fields = .fieldsOf(t, 1);

			if(opin(t, 2, fields))
			{
				dup(t, 1);
				return 1;
			}

			superOf(t, 1);
			swap(t, 1);
			pop(t, 2);
		}

		return 0;
	}

	uword rawSetField(MDThread* t, uword numParams)
	{
		checkInstParam(t, 1);
		checkStringParam(t, 2);
		checkAnyParam(t, 3);
		dup(t, 2);
		dup(t, 3);
		fielda(t, 1, true);
		return 0;
	}

	uword rawGetField(MDThread* t, uword numParams)
	{
		checkInstParam(t, 1);
		checkStringParam(t, 2);
		dup(t, 2);
		field(t, 1, true);
		return 1;
	}
	
	uword getFuncEnv(MDThread* t, uword numParams)
	{
		checkParam(t, 1, MDValue.Type.Function);
		.getFuncEnv(t, 1);
		return 1;
	}

	uword setFuncEnv(MDThread* t, uword numParams)
	{
		checkParam(t, 1, MDValue.Type.Function);
		checkParam(t, 2, MDValue.Type.Namespace);
		.getFuncEnv(t, 1);
		dup(t, 2);
		.setFuncEnv(t, 1);
		return 1;
	}

	uword isParam(MDValue.Type Type)(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		pushBool(t, type(t, 1) == Type);
		return 1;
	}

	uword attrs(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 2);
		
		if(!isNull(t, 2) && !isTable(t, 2))
			paramTypeError(t, 2, "null|table");

		switch(type(t, 1))
		{
			case
				MDValue.Type.Null,
				MDValue.Type.Bool,
				MDValue.Type.Int,
				MDValue.Type.Float,
				MDValue.Type.Char,
				MDValue.Type.String:

				paramTypeError(t, 1, "non-string reference type");

			default:
				break;
		}

		getRegistryVar(t, AttrTableName);
		pushWeakRef(t, 1);
		dup(t, 2);
		idxa(t, -3);
		pop(t);

		setStackSize(t, 2);
		return 1;
	}

	uword hasAttributes(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);

		getRegistryVar(t, AttrTableName);
		pushWeakRef(t, 1);
		pushBool(t, opin(t, -1, -2));
		return 1;
	}

	uword attributesOf(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);

		switch(type(t, 1))
		{
			case
				MDValue.Type.Null,
				MDValue.Type.Bool,
				MDValue.Type.Int,
				MDValue.Type.Float,
				MDValue.Type.Char,
				MDValue.Type.String:

				paramTypeError(t, 1, "non-string reference type");

			default:
				break;
		}

		getRegistryVar(t, AttrTableName);
		pushWeakRef(t, 1);
		idx(t, -2);
		return 1;
	}

	// ===================================================================================================================================
	// Conversions

	uword toString(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);

		if(isInt(t, 1))
		{
			uint radix = 10;

			if(numParams > 1)
				radix = cast(uint)getInt(t, 2);
				
			// TODO: make this not allocate memory
			pushString(t, to!(string)(getInt(t, 1), radix));
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
			case MDValue.Type.String: pushInt(t, safeCode(t, to!(mdint)(getString(t, 1)))); break;

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
			case MDValue.Type.String: pushFloat(t, safeCode(t, to!(mdfloat)(getString(t, 1)))); break;

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
		formatImpl(t, numParams, &buf.addString);
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
			.write(getString(t, -1));
		}

		stdout.flush();
		return 0;
	}

	uword writeln(MDThread* t, uword numParams)
	{
		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);
			.write(getString(t, -1));
		}

		.writeln();
		return 0;
	}

	uword writef(MDThread* t, uword numParams)
	{
		void sink(string data)
		{
			.write(data);
		}

		formatImpl(t, numParams, &sink);
		stdout.flush();
		return 0;
	}

	uword writefln(MDThread* t, uword numParams)
	{
		void sink(string data)
		{
			.write(data);
		}

		formatImpl(t, numParams, &sink);
		.writeln();
		return 0;
	}

	uword dumpVal(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		auto newline = optBoolParam(t, 2, true);

		auto shown = getUpval(t, 0);

		assert(len(t, shown) == 0);

		scope(exit)
		{
			getUpval(t, 0);
			clearTable(t, -1);
			pop(t);
		}

		void outputRepr(word v)
		{
			v = absIndex(t, v);

			if(hasPendingHalt(t))
				.haltThread(t);

			void escape(dchar c)
			{
				switch(c)
				{
					case '\'': .write(`\'`); break;
					case '\"': .write(`\"`); break;
					case '\\': .write(`\\`); break;
					case '\a': .write(`\a`); break;
					case '\b': .write(`\b`); break;
					case '\f': .write(`\f`); break;
					case '\n': .write(`\n`); break;
					case '\r': .write(`\r`); break;
					case '\t': .write(`\t`); break;
					case '\v': .write(`\v`); break;

					default:
						if(c <= 0x7f && isprint(c))
							.write(c);
						else if(c <= 0xFFFF)
							.writef("\\u%4x", cast(uint)c);
						else
							.writef("\\U%8x", cast(uint)c);
						break;
				}
			}

			void outputArray(word arr)
			{
				if(opin(t, arr, shown))
				{
					.write("[...]");
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

				.write('[');

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

						.write(", ");
						pushInt(t, i);
						idx(t, arr);
						outputRepr(-1);
						pop(t);
					}
				}

				.write(']');
			}

			void outputTable(word tab)
			{
				if(opin(t, tab, shown))
				{
					.write("{...}");
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

				.write('{');

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
							.write(", ");

						if(hasPendingHalt(t))
							.haltThread(t);

						.write('[');
						outputRepr(k);
						.write("] = ");
						dup(t, v);
						outputRepr(-1);
						pop(t);
					}
				}

				.write('}');
			}

			void outputNamespace(word ns)
			{
				pushToString(t, ns);
				.write(getString(t, -1), " { ");
				pop(t);

				auto length = len(t, ns);

				if(length > 0)
				{
					dup(t, ns);
					bool first = true;

					foreach(word k, word v; foreachLoop(t, 1))
					{
						if(hasPendingHalt(t))
							.haltThread(t);

						if(first)
							first = false;
						else
							.write(", ");

						.write(getString(t, k));
					}
				}

				.write(" }");
			}

			if(isString(t, v))
			{
				.write('"');

				foreach(dchar c; getString(t, v))
					escape(c);

				.write('"');
			}
			else if(isChar(t, v))
			{
				.write("'");
				escape(getChar(t, v));
				.write("'");
			}
			else if(isArray(t, v))
				outputArray(v);
			else if(isTable(t, v) && !.hasMethod(t, v, "toString"))
				outputTable(v);
			else if(isNamespace(t, v))
				outputNamespace(v);
			else if(isWeakRef(t, v))
			{
				.write("weakref(");
				.deref(t, v);
				outputRepr(-1);
				pop(t);
				.write(")");
			}
			else
			{
				pushToString(t, v);
				.write(getString(t, -1));
				pop(t);
			}
		}

		outputRepr(1);

		if(newline)
			.writeln();

		return 0;
	}

	uword readln(MDThread* t, uword numParams)
	{
		auto s = .readln()[0 .. $ - 1];
		
		if(s.length && s[$ - 1] == '\r')
			s = s[0 .. $ - 1];

		pushString(t, s);
		return 1;
	}

	// ===================================================================================================================================
	// Dynamic Compilation

	uword loadString(MDThread* t, uword numParams)
	{
		auto code = checkStringParam(t, 1);
		string name = "<loaded by loadString>";

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
		.setFuncEnv(t, -2);
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

		.setFuncEnv(t, -2);
		pushNull(t);
		return rawCall(t, -2, -1);
	}

	uword loadJSON(MDThread* t, uword numParams)
	{
		JSON.load(t, checkStringParam(t, 1));
		return 1;
	}

	uword toJSON(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		auto pretty = optBoolParam(t, 2, false);

		// TODO: make this not allocate memory
		string buf;
		JSON.save(t, 1, pretty, delegate void(string s) { buf ~= s; });
		pushString(t, buf);
		return 1;
	}

	// ===================================================================================================================================
	// Function metatable

	uword functionIsNative(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Function);
		pushBool(t, funcIsNative(t, 0));
		return 1;
	}

	uword functionNumParams(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Function);
		pushInt(t, funcNumParams(t, 0));
		return 1;
	}

	uword functionIsVararg(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Function);
		pushBool(t, funcIsVararg(t, 0));
		return 1;
	}

	// ===================================================================================================================================
	// Weak reference stuff

	uword weakref(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		pushWeakRef(t, 1);
		return 1;
	}

	uword deref(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);

		switch(type(t, 1))
		{
			case
				MDValue.Type.Null,
				MDValue.Type.Bool,
				MDValue.Type.Int,
				MDValue.Type.Float,
				MDValue.Type.Char:

				dup(t, 1);
				return 1;

			case MDValue.Type.WeakRef:
				.deref(t, 1);
				return 1;

			default:
				paramTypeError(t, 1, "null|bool|int|float|char|weakref");
		}

		assert(false);
	}
}