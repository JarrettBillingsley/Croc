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

module croc.stdlib_base;

import Float = tango.text.convert.Float;
import Integer = tango.text.convert.Integer;
import tango.io.Console;
import tango.io.Stdout;
import tango.stdc.ctype;

import croc.ex;
import croc.ex_format;
import croc.interpreter;
import croc.stackmanip;
import croc.stdlib_stringbuffer;
import croc.stdlib_vector;
import croc.types;
import croc.types_class;
import croc.types_instance;
import croc.types_namespace;

private void register(CrocThread* t, char[] name, NativeFunc func, uword numUpvals = 0)
{
	newFunction(t, func, name, numUpvals);
	newGlobal(t, name);
}

private void register(CrocThread* t, uint numParams, char[] name, NativeFunc func, uword numUpvals = 0)
{
	newFunction(t, numParams, func, name, numUpvals);
	newGlobal(t, name);
}

struct BaseLib
{
static:
	private const AttrTableName = "baselib.attributes";

	public void init(CrocThread* t)
	{
		// Vector
		VectorObj.init(t);

		// StringBuffer
		StringBufferObj.init(t);

		// The Function type's metatable
		newNamespace(t, "function");
			newFunction(t, 0, &functionIsNative,    "function.isNative");    fielda(t, -2, "isNative");
			newFunction(t, 0, &functionNumParams,   "function.numParams");   fielda(t, -2, "numParams");
			newFunction(t, 0, &functionMaxParams,   "function.maxParams");   fielda(t, -2, "maxParams");
			newFunction(t, 0, &functionIsVararg,    "function.isVararg");    fielda(t, -2, "isVararg");
			newFunction(t, 0, &functionIsCacheable, "function.isCacheable"); fielda(t, -2, "isCacheable");
		setTypeMT(t, CrocValue.Type.Function);

		// Weak reference stuff
		register(t, 1, "weakref", &weakref);
		register(t, 1, "deref", &deref);

		// Reflection-esque stuff
		register(t, 1, "findGlobal", &findGlobal);
		register(t, 1, "isSet", &isSet);
		register(t, 1, "typeof", &croctypeof);
		register(t, 1, "nameOf", &nameOf);
		register(t, 1, "fieldsOf", &fieldsOf);
		register(t, 1, "allFieldsOf", &allFieldsOf);
		register(t, 2, "hasField", &hasField);
		register(t, 2, "hasMethod", &hasMethod);
		register(t, 2, "findField", &findField);
		register(t, 3, "rawSetField", &rawSetField);
		register(t, 2, "rawGetField", &rawGetField);
		register(t, 1, "isNull", &isParam!(CrocValue.Type.Null));
		register(t, 1, "isBool", &isParam!(CrocValue.Type.Bool));
		register(t, 1, "isInt", &isParam!(CrocValue.Type.Int));
		register(t, 1, "isFloat", &isParam!(CrocValue.Type.Float));
		register(t, 1, "isChar", &isParam!(CrocValue.Type.Char));
		register(t, 1, "isString", &isParam!(CrocValue.Type.String));
		register(t, 1, "isTable", &isParam!(CrocValue.Type.Table));
		register(t, 1, "isArray", &isParam!(CrocValue.Type.Array));
		register(t, 1, "isFunction", &isParam!(CrocValue.Type.Function));
		register(t, 1, "isClass", &isParam!(CrocValue.Type.Class));
		register(t, 1, "isInstance", &isParam!(CrocValue.Type.Instance));
		register(t, 1, "isNamespace", &isParam!(CrocValue.Type.Namespace));
		register(t, 1, "isThread", &isParam!(CrocValue.Type.Thread));
		register(t, 1, "isNativeObj", &isParam!(CrocValue.Type.NativeObj));
		register(t, 1, "isWeakRef", &isParam!(CrocValue.Type.WeakRef));
		register(t, 1, "isFuncDef", &isParam!(CrocValue.Type.FuncDef));

		register(t, 2, "attrs", &attrs);
		register(t, 1, "hasAttributes", &hasAttributes);
		register(t, 1, "attributesOf", &attributesOf);
		newTable(t);
		setRegistryVar(t, AttrTableName);

		// Conversions
		register(t, 2, "toString", &toString);
		register(t, 1, "rawToString", &rawToString);
		register(t, 1, "toBool", &toBool);
		register(t, 1, "toInt", &toInt);
		register(t, 1, "toFloat", &toFloat);
		register(t, 1, "toChar", &toChar);
		register(t, "format", &format);

		// Console IO
		register(t, "write", &write);
		register(t, "writeln", &writeln);
		register(t, "writef", &writef);
		register(t, "writefln", &writefln);
		register(t, 0, "readln", &readln);

			newTable(t);
		register(t, 2, "dumpVal", &dumpVal, 1);
	}

	// ===================================================================================================================================
	// Function metatable

	uword functionIsNative(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Function);
		pushBool(t, funcIsNative(t, 0));
		return 1;
	}

	uword functionNumParams(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Function);
		pushInt(t, funcNumParams(t, 0));
		return 1;
	}

	uword functionMaxParams(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Function);
		pushInt(t, funcMaxParams(t, 0));
		return 1;
	}

	uword functionIsVararg(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Function);
		pushBool(t, funcIsVararg(t, 0));
		return 1;
	}
	
	uword functionIsCacheable(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Function);
		auto f = getFunction(t, 0);
		pushBool(t, f.isNative ? false : f.scriptFunc.numUpvals == 0);
		return 1;
	}

	// ===================================================================================================================================
	// Weak reference stuff

	uword weakref(CrocThread* t)
	{
		checkAnyParam(t, 1);
		pushWeakRef(t, 1);
		return 1;
	}

	uword deref(CrocThread* t)
	{
		checkAnyParam(t, 1);

		switch(type(t, 1))
		{
			case
				CrocValue.Type.Null,
				CrocValue.Type.Bool,
				CrocValue.Type.Int,
				CrocValue.Type.Float,
				CrocValue.Type.Char:

				dup(t, 1);
				return 1;

			case CrocValue.Type.WeakRef:
				.deref(t, 1);
				return 1;

			default:
				paramTypeError(t, 1, "null|bool|int|float|char|weakref");
		}

		assert(false);
	}

	// ===================================================================================================================================
	// Reflection-esque stuff

	uword findGlobal(CrocThread* t)
	{
		if(!.findGlobal(t, checkStringParam(t, 1), 1))
			pushNull(t);

		return 1;
	}

	uword isSet(CrocThread* t)
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

	uword croctypeof(CrocThread* t)
	{
		checkAnyParam(t, 1);
		pushString(t, CrocValue.typeString(type(t, 1)));
		return 1;
	}

	uword nameOf(CrocThread* t)
	{
		checkAnyParam(t, 1);

		switch(type(t, 1))
		{
			case CrocValue.Type.Function:  pushString(t, funcName(t, 1)); break;
			case CrocValue.Type.Class:     pushString(t, className(t, 1)); break;
			case CrocValue.Type.Namespace: pushString(t, namespaceName(t, 1)); break;
			default:
				paramTypeError(t, 1, "function|class|namespace");
		}

		return 1;
	}

	uword fieldsOf(CrocThread* t)
	{
		checkAnyParam(t, 1);

		if(isClass(t, 1) || isInstance(t, 1))
			.fieldsOf(t, 1);
		else
			paramTypeError(t, 1, "class|instance");

		return 1;
	}

	uword allFieldsOf(CrocThread* t)
	{
		// Upvalue 0 is the current object
		// Upvalue 1 is the current index into the namespace
		// Upvalue 2 is the duplicates table
		static uword iter(CrocThread* t)
		{
			CrocInstance* i;
			CrocClass* c;
			CrocNamespace* n;
			CrocString** key = void;
			CrocValue* value = void;
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
					n = null;
					haveField = instance.next(i, index, key, value);
				}
				else if(isClass(t, -1))
				{
					c = getClass(t, -1);
					i = null;
					n = null;
					haveField = classobj.next(c, index, key, value);
				}
				else
				{
					n = getNamespace(t, -1);
					i = null;
					c = null;
					haveField = namespace.next(n, index, key, value);
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
				push(t, CrocValue(*key));

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

			push(t, CrocValue(*key));
			push(t, *value);

			if(c)
				push(t, CrocValue(c));
			else if(i)
				push(t, CrocValue(i));
			else
				push(t, CrocValue(n));

			return 3;
		}

		checkAnyParam(t, 1);

		if(!isClass(t, 1) && !isInstance(t, 1) && !isNamespace(t, 1))
			paramTypeError(t, 1, "class|instance|namespace");

		dup(t, 1);
		pushInt(t, 0);
		newTable(t);
		newFunction(t, &iter, "allFieldsOfIter", 3);
		return 1;
	}

	uword hasField(CrocThread* t)
	{
		checkAnyParam(t, 1);
		auto n = checkStringParam(t, 2);
		pushBool(t, .hasField(t, 1, n));
		return 1;
	}

	uword hasMethod(CrocThread* t)
	{
		checkAnyParam(t, 1);
		auto n = checkStringParam(t, 2);
		pushBool(t, .hasMethod(t, 1, n));
		return 1;
	}

	uword findField(CrocThread* t)
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

	uword rawSetField(CrocThread* t)
	{
		checkInstParam(t, 1);
		checkStringParam(t, 2);
		checkAnyParam(t, 3);
		dup(t, 2);
		dup(t, 3);
		fielda(t, 1, true);
		return 0;
	}

	uword rawGetField(CrocThread* t)
	{
		checkInstParam(t, 1);
		checkStringParam(t, 2);
		dup(t, 2);
		field(t, 1, true);
		return 1;
	}

	uword isParam(CrocValue.Type Type)(CrocThread* t)
	{
		checkAnyParam(t, 1);
		pushBool(t, type(t, 1) == Type);
		return 1;
	}

	uword attrs(CrocThread* t)
	{
		checkAnyParam(t, 2);

		if(!isNull(t, 2) && !isTable(t, 2))
			paramTypeError(t, 2, "null|table");

		switch(type(t, 1))
		{
			case
				CrocValue.Type.Null,
				CrocValue.Type.Bool,
				CrocValue.Type.Int,
				CrocValue.Type.Float,
				CrocValue.Type.Char,
				CrocValue.Type.String:

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

	uword hasAttributes(CrocThread* t)
	{
		checkAnyParam(t, 1);

		getRegistryVar(t, AttrTableName);
		pushWeakRef(t, 1);
		pushBool(t, opin(t, -1, -2));
		return 1;
	}

	uword attributesOf(CrocThread* t)
	{
		checkAnyParam(t, 1);

		switch(type(t, 1))
		{
			case
				CrocValue.Type.Null,
				CrocValue.Type.Bool,
				CrocValue.Type.Int,
				CrocValue.Type.Float,
				CrocValue.Type.Char,
				CrocValue.Type.String:

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

	uword toString(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkAnyParam(t, 1);

		if(isInt(t, 1))
		{
			char[1] style = "d";

			if(numParams > 1)
				style[0] = checkCharParam(t, 2);

			char[80] buffer = void;
			pushString(t, safeCode(t, Integer.format(buffer, getInt(t, 1), style)));
		}
		else
			pushToString(t, 1);

		return 1;
	}

	uword rawToString(CrocThread* t)
	{
		checkAnyParam(t, 1);
		pushToString(t, 1, true);
		return 1;
	}

	uword toBool(CrocThread* t)
	{
		checkAnyParam(t, 1);
		pushBool(t, isTrue(t, 1));
		return 1;
	}

	uword toInt(CrocThread* t)
	{
		checkAnyParam(t, 1);

		switch(type(t, 1))
		{
			case CrocValue.Type.Bool:   pushInt(t, cast(crocint)getBool(t, 1)); break;
			case CrocValue.Type.Int:    dup(t, 1); break;
			case CrocValue.Type.Float:  pushInt(t, cast(crocint)getFloat(t, 1)); break;
			case CrocValue.Type.Char:   pushInt(t, cast(crocint)getChar(t, 1)); break;
			case CrocValue.Type.String: pushInt(t, safeCode(t, cast(crocint)Integer.toLong(getString(t, 1), 10))); break;

			default:
				pushTypeString(t, 1);
				throwException(t, "Cannot convert type '{}' to int", getString(t, -1));
		}

		return 1;
	}

	uword toFloat(CrocThread* t)
	{
		checkAnyParam(t, 1);

		switch(type(t, 1))
		{
			case CrocValue.Type.Bool: pushFloat(t, cast(crocfloat)getBool(t, 1)); break;
			case CrocValue.Type.Int: pushFloat(t, cast(crocfloat)getInt(t, 1)); break;
			case CrocValue.Type.Float: dup(t, 1); break;
			case CrocValue.Type.Char: pushFloat(t, cast(crocfloat)getChar(t, 1)); break;
			case CrocValue.Type.String: pushFloat(t, safeCode(t, cast(crocfloat)Float.toFloat(getString(t, 1)))); break;

			default:
				pushTypeString(t, 1);
				throwException(t, "Cannot convert type '{}' to float", getString(t, -1));
		}

		return 1;
	}

	uword toChar(CrocThread* t)
	{
		pushChar(t, cast(dchar)checkIntParam(t, 1));
		return 1;
	}

import croc.api_debug;
	uword format(CrocThread* t)
	{
		uint sink(char[] s)
		{
			if(s.length)
				pushString(t, s);

			return s.length;
		}

		auto startSize = stackSize(t);
		formatImpl(t, startSize - 1, &sink);
		cat(t, stackSize(t) - startSize);
		return 1;
	}

	// ===================================================================================================================================
	// Console IO

	uword write(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		
		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);
			Stdout(getString(t, -1));
		}

		Stdout.flush;
		return 0;
	}

	uword writeln(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;

		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);
			Stdout(getString(t, -1));
		}

		Stdout.newline;
		return 0;
	}

	uword writef(CrocThread* t)
	{
		uint sink(char[] data)
		{
			Stdout(data);
			return data.length;
		}

		auto numParams = stackSize(t) - 1;
		checkStringParam(t, 1);
		formatImpl(t, numParams, &sink);
		Stdout.flush;
		return 0;
	}

	uword writefln(CrocThread* t)
	{
		uint sink(char[] data)
		{
			Stdout(data);
			return data.length;
		}

		auto numParams = stackSize(t) - 1;
		checkStringParam(t, 1);
		formatImpl(t, numParams, &sink);
		Stdout.newline;
		return 0;
	}
	
	uword readln(CrocThread* t)
	{
		char[] s;
		Cin.readln(s);
		pushString(t, s);
		return 1;
	}

	uword dumpVal(CrocThread* t)
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
				pushToString(t, ns);
				Stdout(getString(t, -1))(" { ");
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
							Stdout(", ");

						Stdout(getString(t, k));
					}
				}

				Stdout(" }");
			}

			if(isString(t, v))
			{
				Stdout('"');

				foreach(dchar c; getString(t, v))
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
			else if(isWeakRef(t, v))
			{
				Stdout("weakref(");
				.deref(t, v);
				outputRepr(-1);
				pop(t);
				Stdout(")");
			}
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
}