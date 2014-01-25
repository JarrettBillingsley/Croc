/******************************************************************************
This module contains the 'object' standard library.

License:
Copyright (c) 2012 Jarrett Billingsley

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

module croc.stdlib_object;

import croc.api_debug;
import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_library;
import croc.interpreter;
import croc.types;
import croc.types_class;
import croc.types_instance;
import croc.utils;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initObjectLib(CrocThread* t)
{
	makeModule(t, "object", function uword(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);

			newTable(t);
			dup(t);
		registerGlobal(t, _bindClassMethodFunc);
		registerGlobal(t, _bindInstMethodFunc);

		return 0;
	});

	importModule(t, "object");

	version(CrocBuiltinDocs)
	{
		scope doc = new CrocDoc(t, __FILE__);
		doc.push(Docs("module", "object",
		`The \tt{object} library provides access to aspects of the object model not covered by Croc's syntax. This
		includes adding and removing fields and methods of classes and reflecting over the members of classes and
		instances.`));

		docFields(t, doc, _globalFuncDocs);
		doc.pop(-1);
	}

	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

const RegisterFunc[] _globalFuncs =
[
	{"newClass",     &_newClass,     maxParams: 2},
	{"fieldsOf",     &_fieldsOf,     maxParams: 1},
	{"methodsOf",    &_methodsOf,    maxParams: 1},
	{"rawSetField",  &_rawSetField,  maxParams: 3},
	{"rawGetField",  &_rawGetField,  maxParams: 2},
	{"addMethod",    &_addMethod,    maxParams: 3},
	{"addField",     &_addField,     maxParams: 3},
	{"removeMember", &_removeMember, maxParams: 2},
	{"freeze",       &_freeze,       maxParams: 1},
	{"isFrozen",     &_isFrozen,     maxParams: 1},
	{"finalizable",  &_finalizable,  maxParams: 1},
];

const RegisterFunc _bindClassMethodFunc =
	{"bindClassMethod", &_bindClassMethod, maxParams: 2, numUpvals: 1};

const RegisterFunc _bindInstMethodFunc =
	{"bindInstMethod",  &_bindInstMethod,  maxParams: 2, numUpvals: 1};

uword _newClass(CrocThread* t)
{
	auto name = checkStringParam(t, 1);
	auto haveBase = optParam(t, 2, CrocValue.Type.Class);

	if(haveBase)
		dup(t, 2);
	else
		pushNull(t);

	newClass(t, -1, name);
	return 1;
}

uword _fieldsOf(CrocThread* t)
{
	static const Obj = 0;
	static const Idx = 1;

	static uword classIter(CrocThread* t)
	{
		getUpval(t, Obj);
		auto c = getClass(t, -1);
		getUpval(t, Idx);
		auto index = cast(uword)getInt(t, -1);
		pop(t, 2);

		CrocString** key = void;
		CrocValue* value = void;

		while(classobj.nextField(c, index, key, value))
		{
			pushInt(t, index);
			setUpval(t, Idx);

			push(t, CrocValue(*key));
			push(t, *value);
			return 2;
		}

		return 0;
	}

	static uword instanceIter(CrocThread* t)
	{
		getUpval(t, Obj);
		auto c = getInstance(t, -1);
		getUpval(t, Idx);
		auto index = cast(uword)getInt(t, -1);
		pop(t, 2);

		CrocString** key = void;
		CrocValue* value = void;

		while(instance.nextField(c, index, key, value))
		{
			pushInt(t, index);
			setUpval(t, Idx);

			push(t, CrocValue(*key));
			push(t, *value);
			return 2;
		}

		return 0;
	}

	checkAnyParam(t, 1);
	dup(t, 1);
	pushInt(t, 0);

	if(isClass(t, 1))
		newFunction(t, &classIter, "fieldsOfClassIter", 2);
	else if(isInstance(t, 1))
		newFunction(t, &instanceIter, "fieldsOfInstanceIter", 2);
	else
		paramTypeError(t, 1, "class|instance");

	return 1;
}

uword _methodsOf(CrocThread* t)
{
	static const Obj = 0;
	static const Idx = 1;

	static uword iter(CrocThread* t)
	{
		getUpval(t, Obj);
		auto c = getClass(t, -1);
		getUpval(t, Idx);
		auto index = cast(uword)getInt(t, -1);
		pop(t, 2);

		CrocString** key = void;
		CrocValue* value = void;

		while(classobj.nextMethod(c, index, key, value))
		{
			pushInt(t, index);
			setUpval(t, Idx);

			push(t, CrocValue(*key));
			push(t, *value);
			return 2;
		}

		return 0;
	}

	checkAnyParam(t, 1);

	if(isClass(t, 1))
		dup(t, 1);
	else if(isInstance(t, 1))
		superOf(t, 1);
	else
		paramTypeError(t, 1, "class|instance");

	pushInt(t, 0);
	newFunction(t, &iter, "methodsOfIter", 2);
	return 1;
}

uword _rawSetField(CrocThread* t)
{
	checkInstParam(t, 1);
	checkStringParam(t, 2);
	checkAnyParam(t, 3);
	dup(t, 2);
	dup(t, 3);
	fielda(t, 1, true);
	return 0;
}

uword _rawGetField(CrocThread* t)
{
	checkInstParam(t, 1);
	checkStringParam(t, 2);
	dup(t, 2);
	field(t, 1, true);
	return 1;
}

uword _addMethod(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Class);
	checkStringParam(t, 2);
	checkParam(t, 3, CrocValue.Type.Function);

	dup(t, 2);
	dup(t, 3);
	addMethod(t, 1);
	return 0;
}

uword _addField(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Class);
	checkStringParam(t, 2);

	if(!isValidIndex(t, 3))
		pushNull(t);

	dup(t, 2);
	dup(t, 3);
	addField(t, 1);
	return 0;
}

uword _removeMember(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Class);
	checkStringParam(t, 2);

	dup(t, 2);
	removeMember(t, 1);
	return 0;
}

uword _freeze(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Class);
	freezeClass(t, 1);
	dup(t, 1);
	return 1;
}

uword _isFrozen(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Class);
	pushBool(t, isClassFrozen(t, 1));
	return 1;
}

uword _finalizable(CrocThread* t)
{
	checkAnyParam(t, 1);

	if(isClass(t, 1))
	{
		freezeClass(t, 1);
		auto c = getClass(t, 1);
		pushBool(t, c.finalizer !is null);
	}
	else if(isInstance(t, 1))
	{
		auto i = getInstance(t, 1);
		pushBool(t, i.parent.finalizer !is null);
	}
	else
		paramTypeError(t, 1, "class|instance");

	return 1;
}

uword _binder(CrocThread* t)
{
	enum
	{
		Func,
		Proto
	}

	checkParam(t, 0, CrocValue.Type.Instance);

	getUpval(t, Proto);
	auto proto = getClass(t, -1);

	if(!as(t, 0, -1))
		paramTypeError(t, 0, proto.name.toString());

	getUpval(t, Func);
	auto func = getFunction(t, -1);
	pop(t, 2);

	// this seems .. scary, but I don't see why it wouldn't work.
	// FEEL FREE TO SHOOT ME, FUTURE SELF
	auto slot = fakeToAbs(t, 0);
	return commonCall(t, slot, -1, callPrologue2(t, func, slot, -1, slot, stackSize(t), proto));
}

void _bindImpl(CrocThread* t, CrocClass* cls, CrocString* name)
{
	// First, get the method.
	auto slot = classobj.getMethod(cls, name);

	if(slot is null)
	{
		throwStdException(t, "MethodError", "Class '{}' has no method named '{}'",
			cls.name.toString(), name.toString());
	}

	if(slot.value.type != CrocValue.Type.Function)
	{
		push(t, slot.value);
		pushTypeString(t, -1);
		throwStdException(t, "TypeError", "'{}' is not a function, it is a '{}'", name.toString(), getString(t, -1));
	}

	auto realMethod = slot.value.mFunction;

	// Next, check to see if we have this method cached.
	auto tab = getUpval(t, 0); // [tab]
	push(t, CrocValue(cls));
	auto methods = idx(t, tab); // [tab methods]

	if(!isNull(t, methods))
	{
		push(t, CrocValue(name));
		auto cached = idx(t, methods); // [tab methods cached]

		if(isNull(t, cached))
			pop(t); // [tab methods]
		else
		{
			field(t, cached, "func"); // [tab methods cached cachedFunc]
			auto cachedFunc = getFunction(t, -1);

			if(cachedFunc is realMethod)
			{
				field(t, cached, "bound");
				insertAndPop(t, tab);
				return;
			}

			// The method changed; clear the cache and re-create.
			pop(t, 2); // [tab methods]
			push(t, CrocValue(name));
			pushNull(t);
			idxa(t, methods); // [tab methods]
		}
	}

	// No cached function: create it anew.
		push(t, CrocValue(realMethod));
		push(t, CrocValue(cls));
	auto newFunc = newFunction(t, &_binder, "binder", 2); // [tab methods newFunc]

	if(isNull(t, methods))
	{
		// methods = {}
		newTable(t);
		swap(t, methods);
		pop(t);

		// tab[cls] = methods
		push(t, CrocValue(cls));
		dup(t, methods);
		idxa(t, tab); // [tab methods newFunc]
	}

	push(t, CrocValue(name)); // [tab methods newFunc name]
	newTable(t); // [tab methods newFunc name <table>]
		push(t, CrocValue(realMethod)); fielda(t, -2, "func");
		dup(t, newFunc);                fielda(t, -2, "bound");
	idxa(t, methods); // [tab methods newFunc]

	insertAndPop(t, tab); // [newFunc]
}

uword _bindClassMethod(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Class);
	checkStringParam(t, 2);
	_bindImpl(t, getClass(t, 1), getStringObj(t, 2));
	return 1;
}

uword _binderInst(CrocThread* t)
{
	enum
	{
		Func,
		Self
	}

	getUpval(t, Func);
	getUpval(t, Self);
	rotate(t, stackSize(t) - 1, 2);
	return rawCall(t, 1, -1);
}

uword _bindInstMethod(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Instance);
	checkStringParam(t, 2);
	_bindImpl(t, getInstance(t, 1).parent, getStringObj(t, 2));
	dup(t, 1);
	newFunction(t, &_binderInst, "binderInst", 2);
	return 1;
}

const Docs[] _globalFuncDocs =
[
	{kind: "function", name: "newClass",
	params: [Param("name", "string"), Param("base", "class", "null")],
	docs:
	`A function for creating a class from a name and an optional base class. The built-in class declaration syntax in
	Croc doesn't allow you to parameterize the name, so this function allows you to do so.`},

	{kind: "function", name: "fieldsOf",
	params: [Param("value", "class|instance")],
	docs:
	`Given a class or instance, returns an iterator function which iterates over all the public fields accessible from
	that object.

	The iterator gives three indices: the name of the field, its value, and the class in which it was defined. For
	example:

\code
class Base
{
	x = 5
	y = 10
}

class Derived : Base
{
	x = 20
	z = 30
}

foreach(name, val, cls; object.fieldsOf(Derived))
	writefln("{} = {} ({})", name, val, nameOf(cls))
\endcode

	This will print out (though not necessarily in this order):

\verbatim
x = 20 (Derived)
y = 10 (Base)
z = 30 (Derived)
\endverbatim

	Notice that \tt{x}'s owner is \tt{Derived}, even though there is an \tt{x} in \tt{Base} as well, because
	\tt{Derived} redefined it.

	\param[value] is the class or instance whose fields you want to iterate over.
	\returns an iterator function.
	`},

	{kind: "function", name: "methodsOf",
	params: [Param("value", "class|instance")],
	docs:
	`Just like \link{fieldsOf}, but iterates over methods instead.

	\param[value] is the class or instance whose methods you want to iterate over. If you pass an \tt{instance}, it will
	just iterate over its class's methods instead (since instances don't store methods).
	\returns an iterator function`},

	{kind: "function", name: "rawSetField",
	params: [Param("o", "instance"), Param("name", "string"), Param("value")],
	docs:
	`Sets a field into an instance bypassing any \b{\tt{opFieldAssign}} metamethods.`},

	{kind: "function", name: "rawGetField",
	params: [Param("o", "instance"), Param("name", "string")],
	docs:
	`Gets a field from an instance bypassing any \b{\tt{opField}} metamethods.`},

	{kind: "function", name: "addMethod",
	params: [Param("cls", "class"), Param("name", "string"), Param("func", "function")],
	docs:
	`Adds a new method to a class.

	The class must not be frozen, and no method or field of the same name may exist.`},

	{kind: "function", name: "bindClassMethod",
	params: [Param("cls", "class"), Param("name", "string")],
	docs:
	`Given a class and the name of a (public) method from that class, returns a function which allows you to call that
	method using a normal function call. This is often useful for situations where you want to transparently forward a
	call to an instance's method, such as when making mock objects.

	The returned function has the signature \tt{function(this: instance(cls), vararg)}; that is, the \tt{this} parameter
	must be an instance of the \tt{cls} from which the method is bound, and then a variable number of arguments which
	will be passed through unchanged to the bound method. The \tt{this} parameter will then become the \tt{this}
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

local boundGetProt = object.bindClassMethod(C, "getProt")

writeln(boundGetProt(with c)) // also prints 5
\endcode

	This function can be used to bind protected and private methods as well, but only as long as you call it from within
	a method from the appropriate class. It uses the exact same rules as normal field/method access in this regard. If
	you want to bind a private method, pass its unmangled name (such as \tt{"__foo"}) to this function; it will be
	automatically mangled for you.

	Note that this function will intelligently cache the function that it returns. If you use
	\tt{bindClassMethod(C, name)} twice, both times it will return the same function closure. If you happen to change
	the method in the class in between those calls (such as might happen before the class is frozen), the cache will
	adapt and a new closure will be returned which binds the new method.

	\param[cls] is the class from which the method should be bound.
	\param[name] is the name of the method to bind.
	\returns a function closure as described above.
	\throws[exceptions.MethodError] if the given method doesn't exist or can't be accessed.
	\throws[exceptions.TypeError] if \tt{name} names a method which is not a function.`},

	{kind: "function", name: "bindInstMethod",
	params: [Param("inst", "instance"), Param("name", "string")],
	docs:
	`Similar to \link{bindClassMethod}, but works on an instance instead of a class. Basically what it does is the
	following:

\code
function bindInstMethod(inst: instance, name: string)
{
	local boundFunc = bindClassMethod(inst.super, name)
	return function(vararg)
	{
		return boundFunc(with inst, vararg)
	}
}
\endcode

	That is, it just uses \link{bindClassMethod} to get a bound class method, and then returns a closure that will call
	that bound method with \tt{inst} as the \tt{this} parameter. However, if you tried to implement this function in
	Croc as above, it wouldn't work for binding protected or private methods. This native implementation gets around
	that and allows you to bind non-public methods as well. In this regard it behaves exactly as \link{bindClassMethod}.

	You can use it like:

\code
class C
{
	_prot = 5
	function getProt() = :_prot
}

local c = C()

writeln(c.getProt()) // prints 5

local bound = object.bindInstMethod(c, "getProt")

writeln(bound()) // also prints 5
\endcode

	\param[inst] is the instance from which the method should be bound.
	\param[name] is the name of the method to bind.
	\returns a function closure as described above.
	\throws[exceptions.MethodError] if the given method doesn't exist or can't be accessed.
	\throws[exceptions.TypeError] if \tt{name} names a method which is not a function.`},
];