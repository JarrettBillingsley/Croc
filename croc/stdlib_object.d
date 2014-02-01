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
	{"newClass",          &_newClass                       },
	{"fieldsOf",          &_fieldsOf,          maxParams: 1},
	{"methodsOf",         &_methodsOf,         maxParams: 1},
	{"rawSetField",       &_rawSetField,       maxParams: 3},
	{"rawGetField",       &_rawGetField,       maxParams: 2},
	{"addMethod",         &_addMethod,         maxParams: 3},
	{"addField",          &_addField,          maxParams: 3},
	{"addMethodOverride", &_addMethodOverride, maxParams: 3},
	{"addFieldOverride",  &_addFieldOverride,  maxParams: 3},
	{"removeMember",      &_removeMember,      maxParams: 2},
	{"freeze",            &_freeze,            maxParams: 1},
	{"isFrozen",          &_isFrozen,          maxParams: 1},
	{"isFinalizable",     &_isFinalizable,     maxParams: 1},
	{"instanceOf",        &_instanceOf,        maxParams: 2},
];

uword _newClass(CrocThread* t)
{
	auto name = checkStringParam(t, 1);

	for(int slot = 2; slot < stackSize(t); slot++)
		checkParam(t, slot, CrocValue.Type.Class);

	newClass(t, name, stackSize(t) - 2);
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

uword _addMethodOverride(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Class);
	checkStringParam(t, 2);
	checkParam(t, 3, CrocValue.Type.Function);

	dup(t, 2);
	dup(t, 3);
	addMethodOverride(t, 1);
	return 0;
}

uword _addFieldOverride(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Class);
	checkStringParam(t, 2);

	if(!isValidIndex(t, 3))
		pushNull(t);

	dup(t, 2);
	dup(t, 3);
	addFieldOverride(t, 1);
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

uword _isFinalizable(CrocThread* t)
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

uword _instanceOf(CrocThread* t)
{
	checkParam(t, 2, CrocValue.Type.Class);

	if(isInstance(t, 1))
	{
		superOf(t, 1);
		pushBool(t, opis(t, -1, 2));
	}
	else
		pushBool(t, false);

	return 1;
}

const Docs[] _globalFuncDocs =
[
	{kind: "function", name: "newClass",
	params: [Param("name", "string"), Param("vararg", "vararg")],
	docs:
	`A function for creating a class from a name and optional base classes. The built-in class declaration syntax in
	Croc doesn't allow you to parameterize the name, so this function allows you to do so.

	The varargs are the optional base classes, and they must all be of type \tt{class}.`},

	{kind: "function", name: "fieldsOf",
	params: [Param("value", "class|instance")],
	docs:
	`Given a class or instance, returns an iterator function which iterates over all the fields in that object.

	The iterator gives two indices: the name of the field, then its value. For example:

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

foreach(name, val; object.fieldsOf(Derived))
	writefln("{} = {}", name, val)
\endcode

	This will print out (though not necessarily in this order):

\verbatim
x = 20
y = 10
z = 30
\endverbatim

	\param[value] is the class or instance whose fields you want to iterate over.
	\returns an iterator function. `},

	{kind: "function", name: "methodsOf",
	params: [Param("value", "class|instance")],
	docs:
	`Just like \link{fieldsOf}, but iterates over methods instead.

	\param[value] is the class or instance whose methods you want to iterate over. If you pass an \tt{instance}, it will
	just iterate over its class's methods instead (since instances don't store methods).
	\returns an iterator function.`},

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

	{kind: "function", name: "addField",
	params: [Param("cls", "class"), Param("name", "string"), Param("value", "any", "null")],
	docs:
	`Adds a new field to a class.

	The class must not be frozen, and no method or field of the same name may exist. The \tt{value} parameter is
	optional.`},

	{kind: "function", name: "addMethodOverride",
	params: [Param("cls", "class"), Param("name", "string"), Param("func", "function")],
	docs:
	`Adds a new method to a class, overriding any existing method of the same name. Works just like the \tt{override}
	keyword in an actual class declaration.

	The class must not be frozen, and a method of the same name must exist.`},

	{kind: "function", name: "addFieldOverride",
	params: [Param("cls", "class"), Param("name", "string"), Param("value", "any", "null")],
	docs:
	`Adds a new field to a class, overriding any existing field of the same name. Works just like the \tt{override}
	keyword in an actual class declaration.

	The class must not be frozen, and a field of the same name must exist. The \tt{value} parameter is optional.`},

	{kind: "function", name: "removeMember",
	params: [Param("cls", "class"), Param("name", "string")],
	docs:
	`Removes a member (method or field) from a class.

	The class must not be frozen, and there must be a member of the given name to remove.`},

	{kind: "function", name: "freeze",
	params: [Param("cls", "class")],
	docs:
	`Forces a class to be frozen.

	Normally classes are frozen when they are instantiated or derived from, but you can force them to be frozen with
	this function to prevent any tampering.`},

	{kind: "function", name: "isFrozen",
	params: [Param("cls", "class")],
	docs:
	`\returns a bool indicating whether or not the given class is frozen.`},

	{kind: "function", name: "addMethod",
	params: [Param("cls", "class"), Param("name", "string"), Param("func", "function")],
	docs:
	`Adds a new method to a class.

	The class must not be frozen, and no method or field of the same name may exist.`},

	{kind: "function", name: "isFinalizable",
	params: [Param("value", "class|instance")],
	docs:
	`\returns a bool indicating whether or not the given class or instance is finalizable.

	\b{If \tt{value} is an unfrozen class, it will be frozen!} There is no way to be sure a class is finalizable without
	freezing it first.`},

	{kind: "function", name: "instanceOf",
	params: [Param("value"), Param("cls", "class")],
	docs:
	`\returns \tt{true} if \tt{value} is an instance and it is an instance of \tt{cls}, and \tt{false} otherwise.`},
];