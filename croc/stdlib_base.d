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

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_format;
import croc.stdlib_utils;
import croc.types;
import croc.types_class;
import croc.types_instance;
import croc.types_namespace;
import croc.utils;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

struct BaseLib
{
static:
	void init(CrocThread* t)
	{
		version(CrocBuiltinDocs)
		{
			scope doc = new CrocDoc(t, __FILE__);
			doc.push(Docs("module", "Base Library",
			"The base library is a set of functions dealing with some language aspects which aren't covered
			by the syntax of the language, as well as miscellaneous functions that don't really fit anywhere
			else. The base library is always loaded when you create an instance of the Croc VM."));
		}

		// The Function type's metatable
		newNamespace(t, "function");
			mixin(RegisterField!(0, "functionIsNative",    0, "function.isNative",    "isNative"));
			mixin(RegisterField!(0, "functionNumParams",   0, "function.numParams",   "numParams"));
			mixin(RegisterField!(0, "functionMaxParams",   0, "function.maxParams",   "maxParams"));
			mixin(RegisterField!(0, "functionIsVararg",    0, "function.isVararg",    "isVararg"));
			mixin(RegisterField!(0, "functionIsCacheable", 0, "function.isCacheable", "isCacheable"));
		setTypeMT(t, CrocValue.Type.Function);

		// Weak reference stuff
		mixin(Register!(1, "weakref"));
		mixin(Register!(1, "deref"));

		// Reflection-esque stuff
		mixin(Register!(1, "findGlobal"));
		mixin(Register!(1, "isSet"));
		mixin(Register!(1, "croctypeof", 0, "typeof"));
		mixin(Register!(1, "nameOf"));
		mixin(Register!(1, "fieldsOf"));
		mixin(Register!(1, "allFieldsOf"));
		mixin(Register!(2, "hasField"));
		mixin(Register!(2, "hasMethod"));
		mixin(Register!(2, "findField"));
		mixin(Register!(3, "rawSetField"));
		mixin(Register!(2, "rawGetField"));

		mixin(Register!(1, "crocIsNull",      0, "isNull"));
		mixin(Register!(1, "crocIsBool",      0, "isBool"));
		mixin(Register!(1, "crocIsInt",       0, "isInt"));
		mixin(Register!(1, "crocIsFloat",     0, "isFloat"));
		mixin(Register!(1, "crocIsChar",      0, "isChar"));
		mixin(Register!(1, "crocIsString",    0, "isString"));
		mixin(Register!(1, "crocIsTable",     0, "isTable"));
		mixin(Register!(1, "crocIsArray",     0, "isArray"));
		mixin(Register!(1, "crocIsMemblock",  0, "isMemblock"));
		mixin(Register!(1, "crocIsFunction",  0, "isFunction"));
		mixin(Register!(1, "crocIsClass",     0, "isClass"));
		mixin(Register!(1, "crocIsInstance",  0, "isInstance"));
		mixin(Register!(1, "crocIsNamespace", 0, "isNamespace"));
		mixin(Register!(1, "crocIsThread",    0, "isThread"));
		mixin(Register!(1, "crocIsNativeObj", 0, "isNativeObj"));
		mixin(Register!(1, "crocIsWeakRef",   0, "isWeakRef"));
		mixin(Register!(1, "crocIsFuncDef",   0, "isFuncDef"));

			newTable(t);
			dup(t);
			dup(t);
		mixin(Register!(2, "attrs", 1));
		mixin(Register!(1, "hasAttributes", 1));
		mixin(Register!(1, "attributesOf", 1));

		mixin(Register!(1, "Finalizable"));

		// Conversions
		mixin(Register!(2, "toString"));
		mixin(Register!(1, "rawToString"));
		mixin(Register!(1, "toBool"));
		mixin(Register!(1, "toInt"));
		mixin(Register!(1, "toFloat"));
		mixin(Register!(1, "toChar"));
		mixin(Register!(   "format"));

		// Console IO
		mixin(Register!(   "write"));
		mixin(Register!(   "writeln"));
		mixin(Register!(   "writef"));
		mixin(Register!(   "writefln"));
		mixin(Register!(0, "readln"));

			newTable(t);
		mixin(Register!(2, "dumpVal", 1));

		version(CrocBuiltinDocs)
		{
			pushGlobal(t, "_G");
			doc.pop(-1);
			pop(t);
		}
	}

	// ===================================================================================================================================
	// Function metatable

	version(CrocBuiltinDocs) Docs functionIsNative_docs = {kind: "function", name: "isNative", docs:
	"Returns a bool telling if the function is implemented in native code or in Croc.",
	extra: [Extra("section", "Function metamethods")]};

	uword functionIsNative(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Function);
		pushBool(t, funcIsNative(t, 0));
		return 1;
	}

	version(CrocBuiltinDocs) Docs functionNumParams_docs = {kind: "function", name: "numParams", docs:
	"Returns an integer telling how many ''non-variadic'' parameters the function takes.",
	extra: [Extra("section", "Function metamethods")]};

	uword functionNumParams(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Function);
		pushInt(t, funcNumParams(t, 0));
		return 1;
	}

	version(CrocBuiltinDocs) Docs functionMaxParams_docs = {kind: "function", name: "maxParams", docs:
	"Returns an integer of how many parameters this function this may be passed without throwing an error.
	Passing more parameters than this will guarantee that an error is thrown. Variadic functions will
	simply return a very large number from this method.",
	extra: [Extra("section", "Function metamethods")]};

	uword functionMaxParams(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Function);
		pushInt(t, funcMaxParams(t, 0));
		return 1;
	}

	version(CrocBuiltinDocs) Docs functionIsVararg_docs = {kind: "function", name: "isVararg", docs:
	"Returns a bool telling whether or not the function takes variadic parameters.",
	extra: [Extra("section", "Function metamethods")]};

	uword functionIsVararg(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Function);
		pushBool(t, funcIsVararg(t, 0));
		return 1;
	}

	version(CrocBuiltinDocs) Docs functionIsCacheable_docs = {kind: "function", name: "isCacheable", docs:
	"Returns a bool telling whether or not a function is cacheable. Cacheable functions are script functions
	which have no upvalues, generally speaking. A cacheable function only has a single function closure object
	allocated for it during its lifetime. Only script functions can be cacheable; native functions always
	return false.",
	extra: [Extra("section", "Function metamethods")]};

	uword functionIsCacheable(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Function);
		auto f = getFunction(t, 0);
		pushBool(t, f.isNative ? false : f.scriptFunc.numUpvals == 0);
		return 1;
	}

	// ===================================================================================================================================
	// Weak reference stuff

	version(CrocBuiltinDocs) Docs weakref_docs = {kind: "function", name: "weakref", docs:
	"This function is used to create weak reference objects. If the given object is a value type (null, bool, int,
	float, or char), it simply returns them as-is. Otherwise returns a weak reference object that refers to the
	object. For each object, there will be exactly one weak reference object that refers to it. This means that if
	two objects are identical, their weak references will be identical and vice versa. ",
	params: [Param("obj")],
	extra: [Extra("section", "Weak References"), Extra("protection", "global")]};

	uword weakref(CrocThread* t)
	{
		checkAnyParam(t, 1);
		pushWeakRef(t, 1);
		return 1;
	}

	version(CrocBuiltinDocs) Docs deref_docs = {kind: "function", name: "deref", docs:
	"The parameter types for this might look a bit odd, but it's because this function acts as the inverse of
	'''`weakref()`'''. If you pass a value type into the function, it will return it as-is. Otherwise, it will
	dereference the weak reference and return that object. If the object that the weak reference referred to has
	been collected, it will return `null`.",
	params: [Param("obj", "null|bool|int|float|char|weakref")],
	extra: [Extra("section", "Weak References"), Extra("protection", "global")]};

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

	version(CrocBuiltinDocs) Docs findGlobal_docs = {kind: "function", name: "findGlobal", docs:
	"Looks for a global in the current environment with the given name. If found, returns ''the namespace that
	contains it;'' otherwise, returns `null`.",
	params: [Param("name", "string")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

	uword findGlobal(CrocThread* t)
	{
		if(!.findGlobal(t, checkStringParam(t, 1), 1))
			pushNull(t);

		return 1;
	}

	version(CrocBuiltinDocs) Docs isSet_docs = {kind: "function", name: "isSet", docs:
	"Similar to '''`findGlobal`''', except returns a boolean value: `true` if the global exists, `false` otherwise.",
	params: [Param("name", "string")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

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

	version(CrocBuiltinDocs) Docs croctypeof_docs = {kind: "function", name: "typeof", docs:
	"This will get the type of the passed-in value and return it as a string. Possible return values are \"null\",
	\"bool\", \"int\", \"float\", \"char\", \"string\", \"table\", \"array\", \"function\", \"class\", \"instance\",
	\"namespace\", \"thread\", \"nativeobj\", \"weakref\", and \"funcdef\".",
	params: [Param("value")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

	uword croctypeof(CrocThread* t)
	{
		checkAnyParam(t, 1);
		pushString(t, CrocValue.typeStrings[type(t, 1)]);
		return 1;
	}

	version(CrocBuiltinDocs) Docs nameOf_docs = {kind: "function", name: "nameOf", docs:
	"Returns the name of the given value as a string. This is the name that the class, function, namespace, or funcdef was
	declared with, or an autogenerated one if it wasn't declared with a name (such as anonymous function literals).",
	params: [Param("value", "class|function|namespace|funcdef")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

	uword nameOf(CrocThread* t)
	{
		checkAnyParam(t, 1);

		switch(type(t, 1))
		{
			case CrocValue.Type.Function:  pushString(t, funcName(t, 1)); break;
			case CrocValue.Type.Class:     pushString(t, className(t, 1)); break;
			case CrocValue.Type.Namespace: pushString(t, namespaceName(t, 1)); break;
			case CrocValue.Type.FuncDef:   pushString(t, funcDefName(t, 1)); break;
			default:
				paramTypeError(t, 1, "function|class|namespace|funcdef");
		}

		return 1;
	}

	version(CrocBuiltinDocs) Docs fieldsOf_docs = {kind: "function", name: "fieldsOf", docs:
	"Returns a namespace that holds the fields of the given class or instance. Each class or instance has its own
	unique field namespace. Note, however, that since the fields are lazily created (i.e. a class or instance will
	not have a field unless it has been assigned into it), you won't necessarily get ''all'' the fields that can be
	accessed from the class or instance, only those which have been set in it. If you want to get all the fields,
	use the '''`allFieldsOf`''' iterator function.",
	params: [Param("value", "class|instance")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

	uword fieldsOf(CrocThread* t)
	{
		checkAnyParam(t, 1);

		if(isClass(t, 1) || isInstance(t, 1))
			.fieldsOf(t, 1);
		else
			paramTypeError(t, 1, "class|instance");

		return 1;
	}

	version(CrocBuiltinDocs) Docs allFieldsOf_docs = {kind: "function", name: "allFieldsOf", docs:
	"Returns an iterator function that will iterate through all fields accessible from the given class, instance,
	or namespace, traversing the base class/parent namespace links up to the root. This iterator actually gives up
	to three indices: the first is the name of the field, the second its value, and the third the class, instance,
	or namespace that owns it. Example use:
{{{
#!croc
class A
{
	x = 5
	function foo() {}
}

class B : A
{
	x = 10
}

// prints \"x: 5\" and \"foo: script function foo\"
foreach(k, v; allFieldsOf(A))
	writefln(\"{}: {}\", k, v)

writeln()

// this time prints 10 for x, and the owner is B; foo's owner is A
foreach(k, v, o; allFieldsOf(B))
	writefln(\"{}: {} (owned by {})\", k, v, o)
}}}

	Note in the second example that both B and its base class A have a field 'x', but only the 'x' accessible from
	B with value 10 is printed.",
	params: [Param("value", "class|instance|namespace")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

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

	version(CrocBuiltinDocs) Docs hasField_docs = {kind: "function", name: "hasField", docs:
	"Sees if `value` contains the field `name`. Works for tables, namespaces, classes, and instances. For any
	other type, always returns `false`. Does not take opField metamethods into account.",
	params: [Param("value"), Param("name", "string")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

	uword hasField(CrocThread* t)
	{
		checkAnyParam(t, 1);
		auto n = checkStringParam(t, 2);
		pushBool(t, .hasField(t, 1, n));
		return 1;
	}

	version(CrocBuiltinDocs) Docs hasMethod_docs = {kind: "function", name: "hasMethod", docs:
	"Sees if the method named `name` can be called on `value`. Looks in metatables as well, for i.e. strings
	and arrays. Works for all types. Does not take opMethod metamethods into account.",
	params: [Param("value"), Param("name", "string")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

	uword hasMethod(CrocThread* t)
	{
		checkAnyParam(t, 1);
		auto n = checkStringParam(t, 2);
		pushBool(t, .hasMethod(t, 1, n));
		return 1;
	}

	version(CrocBuiltinDocs) Docs findField_docs = {kind: "function", name: "findField", docs:
	"Searches the given class, instance, or namespace's inheritance/parent chain for the class/instance/namespace
	that holds the field with the given name. Returns the class/instance/namespace that holds the field, or
	`null` if the given field name was not found. Does not take opField metamethods into account.",
	params: [Param("value", "class|instance|namespace"), Param("name", "string")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

	uword findField(CrocThread* t)
	{
		checkAnyParam(t, 1);

		if(!isInstance(t, 1) && !isClass(t, 1) && !isNamespace(t, 1))
			paramTypeError(t, 1, "class|instance|namespace");

		checkStringParam(t, 2);

		while(!isNull(t, 1))
		{
			word fields;

			if(!isNamespace(t, 1))
				fields = .fieldsOf(t, 1);
			else
				fields = dup(t, 1);

			if(opin(t, 2, fields))
			{
				dup(t, 1);
				return 1;
			}

			superOf(t, 1);
			swap(t, 1);
			pop(t, 2);
		}

		pushNull(t);
		return 1;
	}

	version(CrocBuiltinDocs) Docs rawSetField_docs = {kind: "function", name: "rawSetField", docs:
	"Sets a field into an instance bypassing any '''`opFieldAssign`''' metamethods.",
	params: [Param("o", "instance"), Param("name", "string"), Param("value")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

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

	version(CrocBuiltinDocs) Docs rawGetField_docs = {kind: "function", name: "rawGetField", docs:
	"Gets a field from an instance bypassing any '''`opField`''' metamethods.",
	params: [Param("o", "instance"), Param("name", "string")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

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

	alias isParam!(CrocValue.Type.Null)      crocIsNull;
	alias isParam!(CrocValue.Type.Bool)      crocIsBool;
	alias isParam!(CrocValue.Type.Int)       crocIsInt;
	alias isParam!(CrocValue.Type.Float)     crocIsFloat;
	alias isParam!(CrocValue.Type.Char)      crocIsChar;
	alias isParam!(CrocValue.Type.String)    crocIsString;
	alias isParam!(CrocValue.Type.Table)     crocIsTable;
	alias isParam!(CrocValue.Type.Array)     crocIsArray;
	alias isParam!(CrocValue.Type.Memblock)  crocIsMemblock;
	alias isParam!(CrocValue.Type.Function)  crocIsFunction;
	alias isParam!(CrocValue.Type.Class)     crocIsClass;
	alias isParam!(CrocValue.Type.Instance)  crocIsInstance;
	alias isParam!(CrocValue.Type.Namespace) crocIsNamespace;
	alias isParam!(CrocValue.Type.Thread)    crocIsThread;
	alias isParam!(CrocValue.Type.NativeObj) crocIsNativeObj;
	alias isParam!(CrocValue.Type.WeakRef)   crocIsWeakRef;
	alias isParam!(CrocValue.Type.FuncDef)   crocIsFuncDef;

	version(CrocBuiltinDocs) Docs crocIsNull_docs = {kind: "function", name: "isNull", docs:
	"All these functions return `true` if the passed-in value is of the given type, and `false`
	otherwise. The fastest way to test if something is `null`, however, is to use "`x is null`".",
	params: [Param("o")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

	version(CrocBuiltinDocs) Docs crocIsBool_docs      = {kind: "function", name: "isBool",      docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsInt_docs       = {kind: "function", name: "isInt",       docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsFloat_docs     = {kind: "function", name: "isFloat",     docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsChar_docs      = {kind: "function", name: "isChar",      docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsString_docs    = {kind: "function", name: "isString",    docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsTable_docs     = {kind: "function", name: "isTable",     docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsArray_docs     = {kind: "function", name: "isArray",     docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsMemblock_docs  = {kind: "function", name: "isMemblock",  docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsFunction_docs  = {kind: "function", name: "isFunction",  docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsClass_docs     = {kind: "function", name: "isClass",     docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsInstance_docs  = {kind: "function", name: "isInstance",  docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsNamespace_docs = {kind: "function", name: "isNamespace", docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsThread_docs    = {kind: "function", name: "isThread",    docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsNativeObj_docs = {kind: "function", name: "isNativeObj", docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsWeakRef_docs   = {kind: "function", name: "isWeakRef",   docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};
	version(CrocBuiltinDocs) Docs crocIsFuncDef_docs   = {kind: "function", name: "isFuncDef",   docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

	version(CrocBuiltinDocs) Docs attrs_docs = {kind: "function", name: "attrs", docs:
	"This is a function which can be used to set (or remove) a user-defined attribute table on
	any '''non-string''' reference object. It's meant to be used as a decorator on declarations
	but it can be simply called as a normal function as well.
{{{
#!croc
// Using it as a decorator
@attrs({
	x = 5
	blah = \"Blah blah blah.\"
})
function foo() = 12

// Using it as a normal function
local v = attrs(memblock.new(\"f32\", 5), {blerf = \"derf\"})
}}}

	You can check if an object has attributes and retrieve them using the following functions.",
	params: [Param("o", "..."), Param("t", "table|null")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

	uword attrs(CrocThread* t)
	{
		checkAnyParam(t, 2);

		// ORDER CROCVALUE TYPE
		if(type(t, 1) <= CrocValue.Type.String)
			paramTypeError(t, 1, "non-string reference type");

		if(!isNull(t, 2) && !isTable(t, 2))
			paramTypeError(t, 2, "null|table");

		// TODO: make this use a weak key table
		getUpval(t, 0);
		pushWeakRef(t, 1);
		dup(t, 2);
		idxa(t, -3);
		pop(t);

		setStackSize(t, 2);
		return 1;
	}

	version(CrocBuiltinDocs) Docs hasAttributes_docs = {kind: "function", name: "hasAttributes", docs:
	"Returns whether or not the given value has an attributes table. Works for all types, but always returns
	false for value types and strings.",
	params: [Param("value")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

	uword hasAttributes(CrocThread* t)
	{
		checkAnyParam(t, 1);

		getUpval(t, 0);
		pushWeakRef(t, 1);
		pushBool(t, opin(t, -1, -2));
		return 1;
	}

	version(CrocBuiltinDocs) Docs attributesOf_docs = {kind: "function", name: "attributesOf", docs:
	"Returns the attributes table of `value`, or `null` if it has none. Only works for non-string reference
	types; errors otherwise.",
	params: [Param("value", "...")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

	uword attributesOf(CrocThread* t)
	{
		checkAnyParam(t, 1);

		// ORDER CROCVALUE TYPE
		if(type(t, 1) <= CrocValue.Type.String)
			paramTypeError(t, 1, "non-string reference type");

		getUpval(t, 0);
		pushWeakRef(t, 1);
		idx(t, -2);
		return 1;
	}

	version(CrocBuiltinDocs) Docs Finalizable_docs = {kind: "function", name: "Finalizable", docs:
	`Used as a class decorator. You can use this decorator to make script classes have finalizers. The class should
	have a method called \"finalizer\". This method will be set as the class finalizer, and will be called on instances
	of this class when they are about to be collected.`,
	params: [Param("cls", "class")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]};

	uword Finalizable(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Class);

		if(!.hasField(t, 1, "finalizer"))
			throwStdException(t, "ValueException", "Class {} does not have a 'finalizer' field", className(t, 1));

		field(t, 1, "finalizer");

		if(!isFunction(t, -1))
		{
			pushTypeString(t, -1);
			throwStdException(t, "TypeException", "{}.finalizer is a '{}', not a function", className(t, 1), getString(t, -1));
		}

		setFinalizer(t, 1);
		dup(t, 1);
		return 1;
	}

	// ===================================================================================================================================
	// Conversions

	version(CrocBuiltinDocs) Docs toString_docs = {kind: "function", name: "toString", docs:
	"This is like '''`rawToString`''', but it will call any '''`toString`''' metamethods defined for the value.
	Arrays have a '''`toString`''' metamethod defined for them if the array stdlib is loaded, and any
	'''`toString`''' methods defined for class instances will be used.

	The optional `style` parameter only has meaning if the `value` is an integer. It can be one of the following:
 * 'd': Default: signed base 10.
 * 'b': Binary.
 * 'o': Octal.
 * 'x': Lowercase hexadecimal.
 * 'X': Uppercase hexadecimal.
 * 'u': Unsigned base 10.",
	params: [Param("value"), Param("style", "char", "'d'")],
	extra: [Extra("section", "Conversions"), Extra("protection", "global")]};

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
			pushString(t, safeCode(t, "exceptions.ValueException", Integer.format(buffer, getInt(t, 1), style)));
		}
		else
			pushToString(t, 1);

		return 1;
	}

	version(CrocBuiltinDocs) Docs rawToString_docs = {kind: "function", name: "rawToString", docs:
	"This returns a string representation of the given value depending on its type, as follows:
 * '''`null`''': the string `\"null\"`.
 * '''`bool`''': `\"true\"` or `\"false\"`.
 * '''`int`''': The decimal representation of the number.
 * '''`float`''': The decimal representation of the number, to about 7 digits of precision.
 * '''`char`''': A string with just one character, the character that was passed in.
 * '''`string`''': The string itself.
 * '''`table`''': A string in the format `\"table 0x00000000\"` where 0x00000000 is the address of
   the table.
 * '''`array`''': A string in the format `\"array 0x00000000\"` where 0x00000000 is the address of
   the array.
 * '''`memblock`''': A string in the format `\"memblock 0x00000000\"` where 0x00000000 is the address of
   the memblock.
 * '''`function`''': If the function is native code, a string formatted as `\"native function <name>\"`;
   if script code, a string formatted as `\"script function <name>(<location>)\"`.
 * '''`class`''': A string formatted as `\"class <name> (0x00000000)\"`, where 0x00000000 is the address
   of the class.
 * '''`instance`''': A string formatted as `\"instance of class <name> (0x00000000)\"`, where 0x00000000
   is the address of the instance.
 * '''`namespace`''': A string formatted as `\"namespace <names>\"`, where <name> is the hierarchical
   name of the namespace.
 * '''`thread`''': A string formatted as `\"thread 0x00000000\"`, where 0x00000000 is the address of the
   thread.
 * '''`nativeobj`''': A string formatted as `\"nativeobj 0x00000000\"`, where 0x00000000 is the address
   of the native object that it references.
 * '''`weakref`''': A string formatted as `\"weakref 0x00000000\"`, where 0x00000000 is the address of
   the weak reference object.
 * '''`funcdef`''': A string formatted as `\"funcdef <name>(<location>)\"`.",
	params: [Param("value")],
	extra: [Extra("section", "Conversions"), Extra("protection", "global")]};

	uword rawToString(CrocThread* t)
	{
		checkAnyParam(t, 1);
		pushToString(t, 1, true);
		return 1;
	}

	version(CrocBuiltinDocs) Docs toBool_docs = {kind: "function", name: "toBool", docs:
	"This returns the truth value of the given value. `null`, `false`, integer 0, and float 0.0 will all
	return `false`; all other values and types will return `true`.",
	params: [Param("value")],
	extra: [Extra("section", "Conversions"), Extra("protection", "global")]};

	uword toBool(CrocThread* t)
	{
		checkAnyParam(t, 1);
		pushBool(t, isTrue(t, 1));
		return 1;
	}

	version(CrocBuiltinDocs) Docs toInt_docs = {kind: "function", name: "toInt", docs:
	"This will convert a value into an integer. Only the following types can be converted:
 * '''`bool`''': Converts `true` to 1 and `false` to 0.
 * '''`int`''': Just returns the value.
 * '''`float`''': Truncates the fraction and returns the integer portion.
 * '''`char`''': Returns the UTF-32 character code of the character.
 * '''`string`''': Attempts to convert the string to an integer, and assumes it's in base 10. Throws an
   error if it fails. If you want to convert a string to an integer with a base other than 10, use the
   string object's `toInt` method.",
	params: [Param("value", "bool|int|float|char|string")],
	extra: [Extra("section", "Conversions"), Extra("protection", "global")]};

	uword toInt(CrocThread* t)
	{
		checkAnyParam(t, 1);

		switch(type(t, 1))
		{
			case CrocValue.Type.Bool:   pushInt(t, cast(crocint)getBool(t, 1)); break;
			case CrocValue.Type.Int:    dup(t, 1); break;
			case CrocValue.Type.Float:  pushInt(t, cast(crocint)getFloat(t, 1)); break;
			case CrocValue.Type.Char:   pushInt(t, cast(crocint)getChar(t, 1)); break;
			case CrocValue.Type.String: pushInt(t, safeCode(t, "exceptions.ValueException", cast(crocint)Integer.toLong(getString(t, 1), 10))); break;

			default:
				pushTypeString(t, 1);
				throwStdException(t, "TypeException", "Cannot convert type '{}' to int", getString(t, -1));
		}

		return 1;
	}

	version(CrocBuiltinDocs) Docs toFloat_docs = {kind: "function", name: "toFloat", docs:
	"This will convert a value into a float. Only the following types can be converted:
 * '''`bool`''': Converts `true` to 1.0 and `false` to 0.0.
 * '''`int`''': Returns the value cast to a float.
 * '''`float`''': Just returns the value.
 * '''`char`''': Returns a float holding the UTF-32 character code of the character.
 * '''`string`''': Attempts to convert the string to a float. Throws an error if it fails.

 Other types will throw an error.",
	params: [Param("value", "bool|int|float|char|string")],
	extra: [Extra("section", "Conversions"), Extra("protection", "global")]};

	uword toFloat(CrocThread* t)
	{
		checkAnyParam(t, 1);

		switch(type(t, 1))
		{
			case CrocValue.Type.Bool: pushFloat(t, cast(crocfloat)getBool(t, 1)); break;
			case CrocValue.Type.Int: pushFloat(t, cast(crocfloat)getInt(t, 1)); break;
			case CrocValue.Type.Float: dup(t, 1); break;
			case CrocValue.Type.Char: pushFloat(t, cast(crocfloat)getChar(t, 1)); break;
			case CrocValue.Type.String: pushFloat(t, safeCode(t, "exceptions.ValueException", cast(crocfloat)Float.toFloat(getString(t, 1)))); break;

			default:
				pushTypeString(t, 1);
				throwStdException(t, "TypeException", "Cannot convert type '{}' to float", getString(t, -1));
		}

		return 1;
	}

	version(CrocBuiltinDocs) Docs toChar_docs = {kind: "function", name: "toChar", docs:
	"This will convert an integer value to a single character. Only integer parameters are allowed.",
	params: [Param("value", "int")],
	extra: [Extra("section", "Conversions"), Extra("protection", "global")]};

	uword toChar(CrocThread* t)
	{
		pushChar(t, cast(dchar)checkIntParam(t, 1));
		return 1;
	}

	version(CrocBuiltinDocs) Docs format_docs = {kind: "function", name: "format", docs:
	"Functions much like Tango's tango.text.convert.Layout class. `fmt` is a formatting string, in
	which may be embedded formatting specifiers, which use the same '`{}`' syntax as found in Tango,
	.Net, and ICU.

	By default, when you format an item, it will call any '''`toString`''' metamethod defined for it.
	If you want to use the \"raw\" formatting for a parameter instead, write a lowercase 'r' immediately
	after the opening brace of a format specifier. So something like \"`format(\"{r}\", [1, 2, 3])`\"
	will call '''`rawToString`''' on the array parameter, resulting in something like \"`array 0x00000000`\"
	instead of a string representation of the contents of the array.

	Just about everything else works exactly as it does in Tango. You can use any field width and formatting
	characters that Tango allows.

	Croc's '''`writef`''' and '''`writefln`''' functions (as well as their analogues in the IO library) use
	the same internal formatting as this function, so any rules that apply here apply for those functions as
	well.",
	params: [Param("fmt", "string"), Param("vararg", "vararg")],
	extra: [Extra("section", "Conversions"), Extra("protection", "global")]};

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

	version(CrocBuiltinDocs) Docs write_docs = {kind: "function", name: "write", docs:
	"Prints out all its arguments to the console without any formatting (i.e. strings will not be searched
	for formatting specifiers). It's as if each argument has `toString` called on it, and the resulting strings
	are output to the console.",
	params: [Param("vararg", "vararg")],
	extra: [Extra("section", "Console IO"), Extra("protection", "global")]};

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

	version(CrocBuiltinDocs) Docs writeln_docs = {kind: "function", name: "writeln", docs:
	"Same as `write`, but prints a newline after the text has been output.",
	params: [Param("vararg", "vararg")],
	extra: [Extra("section", "Console IO"), Extra("protection", "global")]};

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

	version(CrocBuiltinDocs) Docs writef_docs = {kind: "function", name: "writef", docs:
	"Formats the arguments using the same formatting rules as `format`, outputting the results to the console.
	No newline is printed.",
	params: [Param("fmt", "string"), Param("vararg", "vararg")],
	extra: [Extra("section", "Console IO"), Extra("protection", "global")]};

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

	version(CrocBuiltinDocs) Docs writefln_docs = {kind: "function", name: "writefln", docs:
	"Just like `writef`, but prints a newline after the text has been output.",
	params: [Param("fmt", "string"), Param("vararg", "vararg")],
	extra: [Extra("section", "Console IO"), Extra("protection", "global")]};

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

	version(CrocBuiltinDocs) Docs readln_docs = {kind: "function", name: "readln", docs:
	"Reads one line of input (up to a linefeed) from the console and returns it as a string, without
	any trailing linefeed characters.",
	params: [],
	extra: [Extra("section", "Console IO"), Extra("protection", "global")]};

	uword readln(CrocThread* t)
	{
		char[] s;
		Cin.readln(s);
		pushString(t, s);
		return 1;
	}

	version(CrocBuiltinDocs) Docs dumpVal_docs = {kind: "function", name: "dumpVal", docs:
	"Dumps an exhaustive string representation of the given value to the console. This will recurse
	(safely, you don't need to worry about infinite recursion) into arrays and tables, as well as escape
	non-printing characters in strings and character values. It will also print out the names of the
	fields in namespaces, though it won't recurse into them. All other values will basically have
	'''`toString`''' called on them.

	If the `printNewline` parameter is passed `false`, no newline will be printed after the dumped
	representation. Defaults to `true`.",
	params: [Param("value"), Param("printNewline", "bool", "true")],
	extra: [Extra("section", "Console IO"), Extra("protection", "global")]};

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