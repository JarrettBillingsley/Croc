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

import tango.io.Console;
import tango.io.Stdout;
import tango.stdc.ctype;
import tango.text.convert.Float;
import tango.text.convert.Integer;

alias tango.text.convert.Float.toFloat Float_toFloat;
alias tango.text.convert.Integer.format Integer_format;
alias tango.text.convert.Integer.toLong Integer_toLong;

import croc.api_debug;
import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_library;
import croc.interpreter;
import croc.stdlib_vector;
import croc.types;
import croc.types_class;
import croc.types_instance;
import croc.types_namespace;
import croc.utils;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initBaseLib(CrocThread* t)
{
	newNamespace(t, "function");
		registerFields(t, _funcMetatable);
	setTypeMT(t, CrocValue.Type.Function);

	registerGlobals(t, _weakrefFuncs);
	registerGlobals(t, _reflFuncs);

	registerGlobals(t, _convFuncs);

		newTable(t);
	registerGlobal(t, _dumpValFunc);

	initVector(t);
}

version(CrocBuiltinDocs) void docBaseLib(CrocThread* t)
{
	scope doc = new CrocDoc(t, __FILE__);
	doc.push(Docs("module", "Base Library",
	`The base library is a set of functions dealing with some language aspects which aren't covered
	by the syntax of the language, as well as miscellaneous functions that don't really fit anywhere
	else. The base library is always loaded when you create an instance of the Croc VM.`));

	getTypeMT(t, CrocValue.Type.Function);
		docFields(t, doc, _funcMetatableDocs);
	pop(t);

	docGlobals(t, doc, _docTables);

	docVector(t, doc);

	pushGlobal(t, "_G");
	doc.pop(-1);
	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

// ===================================================================================================================================
// Function metatable

const RegisterFunc[] _funcMetatable =
[
	{"isNative",    &_functionIsNative,    maxParams: 0},
	{"numParams",   &_functionNumParams,   maxParams: 0},
	{"maxParams",   &_functionMaxParams,   maxParams: 0},
	{"isVararg",    &_functionIsVararg,    maxParams: 0},
	{"isCacheable", &_functionIsCacheable, maxParams: 0}
];

uword _functionIsNative(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Function);
	pushBool(t, funcIsNative(t, 0));
	return 1;
}

uword _functionNumParams(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Function);
	pushInt(t, funcNumParams(t, 0));
	return 1;
}

uword _functionMaxParams(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Function);
	pushInt(t, funcMaxParams(t, 0));
	return 1;
}

uword _functionIsVararg(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Function);
	pushBool(t, funcIsVararg(t, 0));
	return 1;
}

uword _functionIsCacheable(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Function);
	auto f = getFunction(t, 0);
	pushBool(t, f.isNative ? false : f.scriptFunc.numUpvals == 0);
	return 1;
}

// ===================================================================================================================================
// Weak reference stuff

const RegisterFunc[] _weakrefFuncs =
[
	{"weakref", &_weakref, maxParams: 1},
	{"deref",   &_deref,   maxParams: 1}
];

uword _weakref(CrocThread* t)
{
	checkAnyParam(t, 1);
	pushWeakRef(t, 1);
	return 1;
}

uword _deref(CrocThread* t)
{
	checkAnyParam(t, 1);

	switch(type(t, 1))
	{
		case
			CrocValue.Type.Null,
			CrocValue.Type.Bool,
			CrocValue.Type.Int,
			CrocValue.Type.Float:

			dup(t, 1);
			return 1;

		case CrocValue.Type.WeakRef:
			deref(t, 1);
			return 1;

		default:
			paramTypeError(t, 1, "null|bool|int|float|weakref");
	}

	assert(false);
}

// ===================================================================================================================================
// Reflection-esque stuff

const RegisterFunc[] _reflFuncs =
[
	{"findGlobal",  &_findGlobal,  maxParams: 1},
	{"isSet",       &_isSet,       maxParams: 1},
	{"typeof",      &_typeof,      maxParams: 1},
	{"nameOf",      &_nameOf,      maxParams: 1},
	{"hasField",    &_hasField,    maxParams: 2},
	{"hasMethod",   &_hasMethod,   maxParams: 2},
	{"bindMethod",  &_bindMethod,  maxParams: 2},

	{"isNull",      &_isNull,      maxParams: 1},
	{"isBool",      &_isBool,      maxParams: 1},
	{"isInt",       &_isInt,       maxParams: 1},
	{"isFloat",     &_isFloat,     maxParams: 1},
	{"isString",    &_isString,    maxParams: 1},
	{"isTable",     &_isTable,     maxParams: 1},
	{"isArray",     &_isArray,     maxParams: 1},
	{"isMemblock",  &_isMemblock,  maxParams: 1},
	{"isFunction",  &_isFunction,  maxParams: 1},
	{"isClass",     &_isClass,     maxParams: 1},
	{"isInstance",  &_isInstance,  maxParams: 1},
	{"isNamespace", &_isNamespace, maxParams: 1},
	{"isThread",    &_isThread,    maxParams: 1},
	{"isNativeObj", &_isNativeObj, maxParams: 1},
	{"isWeakRef",   &_isWeakRef,   maxParams: 1},
	{"isFuncDef",   &_isFuncDef,   maxParams: 1},
];

uword _findGlobal(CrocThread* t)
{
	if(!findGlobal(t, checkStringParam(t, 1), 1))
		pushNull(t);

	return 1;
}

uword _isSet(CrocThread* t)
{
	if(!findGlobal(t, checkStringParam(t, 1), 1))
		pushBool(t, false);
	else
	{
		pop(t);
		pushBool(t, true);
	}

	return 1;
}

uword _typeof(CrocThread* t)
{
	checkAnyParam(t, 1);
	pushString(t, CrocValue.typeStrings[type(t, 1)]);
	return 1;
}

uword _nameOf(CrocThread* t)
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

uword _hasField(CrocThread* t)
{
	checkAnyParam(t, 1);
	auto n = checkStringParam(t, 2);
	pushBool(t, hasField(t, 1, n));
	return 1;
}

uword _hasMethod(CrocThread* t)
{
	checkAnyParam(t, 1);
	auto n = checkStringParam(t, 2);
	pushBool(t, hasMethod(t, 1, n));
	return 1;
}

uword _bindMethod(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Class);
	auto cls = getClass(t, 1);
	checkStringParam(t, 2);
	auto name = getStringObj(t, 2);

	auto AR = getActRec(t, 1);
	auto slot = classobj.getMethod(cls, name);

	if(slot is null)
	{
		throwStdException(t, "MethodException", "Class '{}' has no method named '{}'",
			cls.name.toString(), name.toString());
	}

	if(!checkAccess(slot.value, AR))
	{
		throwStdException(t, "MethodException", "Attempting to bind method '{}' from outside class '{}'",
			name.toString(), cls.name.toString());
	}

	if(slot.value.value.type != CrocValue.Type.Function)
	{
		push(t, slot.value.value);
		pushTypeString(t, -1);
		throwStdException(t, "TypeException", "'{}' is not a function, it is a '{}'", name.toString(), getString(t, -1));
	}

	static uword binder(CrocThread* t)
	{
		enum
		{
			Func,
			Proto
		}

		checkParam(t, 1, CrocValue.Type.Instance);

		getUpval(t, Proto);
		auto proto = getClass(t, -1);

		if(!as(t, 1, -1))
			paramTypeError(t, 1, proto.name.toString());

		getUpval(t, Func);
		auto func = getFunction(t, -1);
		pop(t, 2);

		auto slot = fakeToAbs(t, 1);

		return commonCall(t, slot, -1, callPrologue2(t, func, slot, -1, slot, stackSize(t) - 1, proto));
	}

	push(t, slot.value.value);
	push(t, CrocValue(slot.value.proto));
	newFunction(t, &binder, "binder", 2);

	return 1;
}

uword _isParam(CrocValue.Type Type)(CrocThread* t)
{
	checkAnyParam(t, 1);
	pushBool(t, type(t, 1) == Type);
	return 1;
}

alias _isParam!(CrocValue.Type.Null)      _isNull;
alias _isParam!(CrocValue.Type.Bool)      _isBool;
alias _isParam!(CrocValue.Type.Int)       _isInt;
alias _isParam!(CrocValue.Type.Float)     _isFloat;
alias _isParam!(CrocValue.Type.String)    _isString;
alias _isParam!(CrocValue.Type.Table)     _isTable;
alias _isParam!(CrocValue.Type.Array)     _isArray;
alias _isParam!(CrocValue.Type.Memblock)  _isMemblock;
alias _isParam!(CrocValue.Type.Function)  _isFunction;
alias _isParam!(CrocValue.Type.Class)     _isClass;
alias _isParam!(CrocValue.Type.Instance)  _isInstance;
alias _isParam!(CrocValue.Type.Namespace) _isNamespace;
alias _isParam!(CrocValue.Type.Thread)    _isThread;
alias _isParam!(CrocValue.Type.NativeObj) _isNativeObj;
alias _isParam!(CrocValue.Type.WeakRef)   _isWeakRef;
alias _isParam!(CrocValue.Type.FuncDef)   _isFuncDef;

// ===================================================================================================================================
// Conversions

const RegisterFunc[] _convFuncs =
[
	{"toString",    &_toString,    maxParams: 2},
	{"rawToString", &_rawToString, maxParams: 1},
	{"toBool",      &_toBool,      maxParams: 1},
	{"toInt",       &_toInt,       maxParams: 1},
	{"toFloat",     &_toFloat,     maxParams: 1},
];

uword _toString(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	checkAnyParam(t, 1);

	if(isInt(t, 1))
	{
		auto style = optStringParam(t, 2, "d");
		char[80] buffer = void;
		pushString(t, safeCode(t, "exceptions.ValueException", Integer_format(buffer, getInt(t, 1), style)));
	}
	else
		pushToString(t, 1);

	return 1;
}

uword _rawToString(CrocThread* t)
{
	checkAnyParam(t, 1);
	pushToString(t, 1, true);
	return 1;
}

uword _toBool(CrocThread* t)
{
	checkAnyParam(t, 1);
	pushBool(t, isTrue(t, 1));
	return 1;
}

uword _toInt(CrocThread* t)
{
	checkAnyParam(t, 1);

	switch(type(t, 1))
	{
		case CrocValue.Type.Bool:   pushInt(t, cast(crocint)getBool(t, 1)); break;
		case CrocValue.Type.Int:    dup(t, 1); break;
		case CrocValue.Type.Float:  pushInt(t, cast(crocint)getFloat(t, 1)); break;
		case CrocValue.Type.String: pushInt(t, safeCode(t, "exceptions.ValueException", cast(crocint)Integer_toLong(getString(t, 1), 10))); break;

		default:
			pushTypeString(t, 1);
			throwStdException(t, "TypeException", "Cannot convert type '{}' to int", getString(t, -1));
	}

	return 1;
}

uword _toFloat(CrocThread* t)
{
	checkAnyParam(t, 1);

	switch(type(t, 1))
	{
		case CrocValue.Type.Bool: pushFloat(t, cast(crocfloat)getBool(t, 1)); break;
		case CrocValue.Type.Int: pushFloat(t, cast(crocfloat)getInt(t, 1)); break;
		case CrocValue.Type.Float: dup(t, 1); break;
		case CrocValue.Type.String: pushFloat(t, safeCode(t, "exceptions.ValueException", cast(crocfloat)Float_toFloat(getString(t, 1)))); break;

		default:
			pushTypeString(t, 1);
			throwStdException(t, "TypeException", "Cannot convert type '{}' to float", getString(t, -1));
	}

	return 1;
}

// ===================================================================================================================================
// Console IO

const RegisterFunc _dumpValFunc = {"dumpVal", &_dumpVal, maxParams: 2, numUpvals: 1};

uword _dumpVal(CrocThread* t)
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
			haltThread(t);

		void escape(dchar c)
		{
			switch(c)
			{
				case '\'': Stdout(`\'`); break;
				case '\"': Stdout(`\"`); break;
				case '\\': Stdout(`\\`); break;
				case '\n': Stdout(`\n`); break;
				case '\r': Stdout(`\r`); break;
				case '\t': Stdout(`\t`); break;

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
						haltThread(t);

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
						haltThread(t);

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
		else if(isArray(t, v))
			outputArray(v);
		else if(isTable(t, v) && !hasMethod(t, v, "toString"))
			outputTable(v);
		else if(isNamespace(t, v))
			outputNamespace(v);
		else if(isWeakRef(t, v))
		{
			Stdout("weakref(");
			deref(t, v);
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

version(CrocBuiltinDocs) const Docs[] _funcMetatableDocs =
[
	{kind: "function", name: "isNative",
	extra: [Extra("section", "Function metamethods")],
	docs:
	`\returns a bool telling if the function is implemented in native code or in Croc.`},

	{kind: "function", name: "numParams",
	extra: [Extra("section", "Function metamethods")],
	docs:
	`\returns an integer telling how many \em{non-variadic} parameters the function takes.`},

	{kind: "function", name: "maxParams",
	extra: [Extra("section", "Function metamethods")],
	docs:
	`\returns an integer of how many parameters this function this may be passed without throwing an error.
	Passing more parameters than this will guarantee that an error is thrown. Variadic functions will
	simply return a very large number from this method.`},

	{kind: "function", name: "isVararg",
	extra: [Extra("section", "Function metamethods")],
	docs:
	`\returns a bool telling whether or not the function takes variadic parameters.`},

	{kind: "function", name: "isCacheable",
	extra: [Extra("section", "Function metamethods")],
	docs:
	`\returns a bool telling whether or not a function is cacheable. Cacheable functions are script functions
	which have no upvalues, generally speaking. A cacheable function only has a single function closure object
	allocated for it during its lifetime. Only script functions can be cacheable; native functions always
	return false.`}
];

version(CrocBuiltinDocs) const Docs[] _docTables =
[
	{kind: "function", name: "weakref",
	params: [Param("obj")],
	extra: [Extra("section", "Weak References"), Extra("protection", "global")],
	docs:
	`This function is used to create weak reference objects. If the given object is a value type (null, bool, int,
	or float), it simply returns them as-is. Otherwise returns a weak reference object that refers to the
	object. For each object, there will be exactly one weak reference object that refers to it. This means that if
	two objects are identical, their weak references will be identical and vice versa.`},

	{kind: "function", name: "deref",
	params: [Param("obj", "null|bool|int|float|weakref")],
	extra: [Extra("section", "Weak References"), Extra("protection", "global")],
	docs:
	`The parameter types for this might look a bit odd, but it's because this function acts as the inverse of
	\link{weakref}. If you pass a value type into the function, it will return it as-is. Otherwise, it will
	dereference the weak reference and return that object. If the object that the weak reference referred to has
	been collected, it will return \tt{null}.`},

	{kind: "function", name: "findGlobal",
	params: [Param("name", "string")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")],
	docs:
	`Looks for a global in the current environment with the given name. If found, returns ''the namespace that
	contains it;'' otherwise, returns \tt{null}.`},

	{kind: "function", name: "isSet",
	params: [Param("name", "string")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")],
	docs:
	`Similar to \link{findGlobal}, except returns a boolean value.

	\returns \tt{true} if the global exists, \tt{false} otherwise.`},

	{kind: "function", name: "typeof",
	params: [Param("value")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")],
	docs:
	`This will get the type of the passed-in value and return it as a string. Possible return values are "null",
	"bool", "int", "float", "string", "table", "array", "function", "class", "instance", "namespace", "thread",
	"nativeobj", "weakref", and "funcdef".`},

	{kind: "function", name: "nameOf",
	params: [Param("value", "class|function|namespace|funcdef")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")],
	docs:
	`Returns the name of the given value as a string. This is the name that the class, function, namespace, or funcdef was
	declared with, or an autogenerated one if it wasn't declared with a name (such as anonymous function literals).`},

	{kind: "function", name: "hasField",
	params: [Param("value"), Param("name", "string")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")],
	docs:
	`Sees if \tt{value} contains the field \tt{name}. Works for tables, namespaces, classes, and instances. For any
	other type, always returns \tt{false}. Does not take opField metamethods into account.`},

	{kind: "function", name: "hasMethod",
	params: [Param("value"), Param("name", "string")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")],
	docs:
	`Sees if the method named \tt{name} can be called on \tt{value}. Looks in metatables as well, for i.e. strings
	and arrays. Works for all types. Does not take opMethod metamethods into account.`},

	{kind: "function", name: "bindMethod",
	params: [Param("cls", "class"), Param("name", "string")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")],
	docs:
	`Given a class and the name of a (public) method from that class, returns a function which allows you to call that
	method using a normal function call. This is often useful for situations where you want to transparently forward a
	call to an instance's method, such as when making mock objects.

	The returned function has the signature \tt{function(self: instance(cls), vararg)}; that is, the first parameter
	must be an instance of the \tt{cls} from which the method is bound, and then a variable number of arguments which
	will be passed through unchanged to the bound method. The \tt{self} parameter will then become the \tt{this}
	parameter in the underlying method call.

	For example:

\code
class C
{
	_prot = 5
	function getProt() = :_prot
}

local c = C()

writeln(c.getProt()) // prints 5

local boundGetProt = bindMethod(C, "getProt")

writeln(boundGetProt(c)) // also prints 5
\endcode

	\param[cls] is the class from which the method should be bound.
	\param[name] is the name of the method to bind.
	\throws[exceptions.MethodException] if \tt{name} names a protected or private method.
	\throws[exceptions.TypeException] if \tt{name} names a method which is not a function.`},

	{kind: "function", name: "isNull",
	params: [Param("o")],
	extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")],
	docs:
	`All these functions return \tt{true} if the passed-in value is of the given type, and \tt{false}
	otherwise. The fastest way to test if something is \tt{null}, however, is to use "\tt{x is null}".`},

	{kind: "function", name: "isBool",      docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isInt",       docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isFloat",     docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isString",    docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isTable",     docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isArray",     docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isMemblock",  docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isFunction",  docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isClass",     docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isInstance",  docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isNamespace", docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isThread",    docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isNativeObj", docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isWeakRef",   docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},
	{kind: "function", name: "isFuncDef",   docs: "ditto", params: [Param("o")], extra: [Extra("section", "Reflection Functions"), Extra("protection", "global")]},

	{kind: "function", name: "toString",
	params: [Param("value"), Param("style", "string", "\"d\"")],
	extra: [Extra("section", "Conversions"), Extra("protection", "global")],
	docs:
	`This is like \link{rawToString}, but it will call any \b{\tt{toString}} metamethods defined for the value.
	Arrays have a \b{\tt{toString}} metamethod defined for them by default, and any \b{\tt{toString}} methods defined
	for class instances will be used.

	The optional \tt{style} parameter only has meaning if the \tt{value} is an integer. It can be one of the following:
	\blist
		\li "d": Default: signed base 10.
		\li "b": Binary.
		\li "o": Octal.
		\li "x": Lowercase hexadecimal.
		\li "X": Uppercase hexadecimal.
		\li "u": Unsigned base 10.
	\endlist`},

	{kind: "function", name: "rawToString",
	params: [Param("value")],
	extra: [Extra("section", "Conversions"), Extra("protection", "global")],
	docs:
	`This returns a string representation of the given value depending on its type, as follows:
	\blist
		\li \b{\tt{null}}: the string \tt{"null"}.
		\li \b{\tt{bool}}: \tt{"true"} or \tt{"false"}.
		\li \b{\tt{int}}: The decimal representation of the number.
		\li \b{\tt{float}}: The decimal representation of the number, to about 7 digits of precision.
		\li \b{\tt{string}}: The string itself.
		\li \b{\tt{table}}: A string in the format \tt{"table 0x00000000"} where 0x00000000 is the address of the table.
		\li \b{\tt{array}}: A string in the format \tt{"array 0x00000000"} where 0x00000000 is the address of the array.
		\li \b{\tt{memblock}}: A string in the format \tt{"memblock 0x00000000"} where 0x00000000 is the address of the memblock.
		\li \b{\tt{function}}: If the function is native code, a string formatted as \tt{"native function <name>"};
			if script code, a string formatted as \tt{"script function <name>(<location>)"}.
		\li \b{\tt{class}}: A string formatted as \tt{"class <name> (0x00000000)"}, where 0x00000000 is the address of the class.
		\li \b{\tt{instance}}: A string formatted as \tt{"instance of class <name> (0x00000000)"}, where 0x00000000 is the
			address of the instance.
		\li \b{\tt{namespace}}: A string formatted as \tt{"namespace <name>"}, where <name> is the hierarchical name of the
			namespace.
		\li \b{\tt{thread}}: A string formatted as \tt{"thread 0x00000000"}, where 0x00000000 is the address of the thread.
		\li \b{\tt{nativeobj}}: A string formatted as \tt{"nativeobj 0x00000000"}, where 0x00000000 is the address of the native
			object that it references.
		\li \b{\tt{weakref}}: A string formatted as \tt{"weakref 0x00000000"}, where 0x00000000 is the address of the weak
			reference object.
		\li \b{\tt{funcdef}}: A string formatted as \tt{"funcdef <name>(<location>)"}.
	\endlist`},

	{kind: "function", name: "toBool",
	params: [Param("value")],
	extra: [Extra("section", "Conversions"), Extra("protection", "global")],
	docs:
	`This returns the truth value of the given value. \tt{null}, \tt{false}, integer 0, and float 0.0 will all
	return \tt{false}; all other values and types will return \tt{true}.`},

	{kind: "function", name: "toInt",
	params: [Param("value", "bool|int|float|string")],
	extra: [Extra("section", "Conversions"), Extra("protection", "global")],
	docs:
	`This will convert a value into an integer. Only the following types can be converted:
	\blist
		\li \b{\tt{bool}}: Converts \tt{true} to 1 and \tt{false} to 0.
		\li \b{\tt{int}}: Just returns the value.
		\li \b{\tt{float}}: Truncates the fraction and returns the integer portion.
		\li \b{\tt{string}}: Attempts to convert the string to an integer, and assumes it's in base 10. Throws an
			error if it fails. If you want to convert a string to an integer with a base other than 10, use the
			string object's \b{\tt{toInt}} method.
	\endlist`},

	{kind: "function", name: "toFloat",
	params: [Param("value", "bool|int|float|string")],
	extra: [Extra("section", "Conversions"), Extra("protection", "global")],
	docs:
	`This will convert a value into a float. Only the following types can be converted:
	\blist
		\li \b{\tt{bool}}: Converts \tt{true} to 1.0 and \tt{false} to 0.0.
		\li \b{\tt{int}}: Returns the value cast to a float.
		\li \b{\tt{float}}: Just returns the value.
		\li \b{\tt{string}}: Attempts to convert the string to a float. Throws an error if it fails.
	\endlist

	Other types will throw an error.`},

	{kind: "function", name: "dumpVal",
	params: [Param("value"), Param("printNewline", "bool", "true")],
	extra: [Extra("section", "Console IO"), Extra("protection", "global")],
	docs:
	`Dumps an exhaustive string representation of the given value to the console. This will recurse
	(safely, you don't need to worry about infinite recursion) into arrays and tables, as well as escape
	non-printing characters in strings. It will also print out the names of the fields in namespaces, though it won't
	recurse into them. All other values will basically have \link{toString} called on them.

	If the \tt{printNewline} parameter is passed \tt{false}, no newline will be printed after the dumped
	representation. Defaults to \tt{true}.`}
];