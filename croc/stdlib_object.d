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

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_library;
import croc.types;
import croc.types_class;
import croc.types_instance;

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
		includes adding and removing fields and methods of classes, reflecting over the members of classes and
		instances, and marking classes as finalizable.`));

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
	{"fieldsOf",     &_fieldsOf,     maxParams: 1},
	{"methodsOf",    &_methodsOf,    maxParams: 1},
	{"rawSetField",  &_rawSetField,  maxParams: 3},
	{"rawGetField",  &_rawGetField,  maxParams: 2},
	{"Finalizable",  &_Finalizable,  maxParams: 1},
	{"memberOwner",  &_memberOwner,  maxParams: 2},
	{"addMethod",    &_addMethod,    maxParams: 3},
	{"addField",     &_addField,     maxParams: 3},
	{"removeMember", &_removeMember, maxParams: 2},
	{"freeze",       &_freeze,       maxParams: 1},
	{"isFrozen",     &_isFrozen,     maxParams: 1},
];

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
		FieldValue* value = void;

		while(classobj.nextField(c, index, key, value))
		{
			if(value.isPublic)
			{
				pushInt(t, index);
				setUpval(t, Idx);

				push(t, CrocValue(*key));
				push(t, value.value);
				push(t, CrocValue(value.proto));
				return 3;
			}
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
		FieldValue* value = void;

		while(instance.nextField(c, index, key, value))
		{
			if(value.isPublic)
			{
				pushInt(t, index);
				setUpval(t, Idx);

				push(t, CrocValue(*key));
				push(t, value.value);
				push(t, CrocValue(value.proto));
				return 3;
			}
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
		FieldValue* value = void;

		while(classobj.nextMethod(c, index, key, value))
		{
			if(value.isPublic)
			{
				pushInt(t, index);
				setUpval(t, Idx);

				push(t, CrocValue(*key));
				push(t, value.value);
				push(t, CrocValue(value.proto));
				return 3;
			}
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

uword _Finalizable(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Class);

	if(!hasField(t, 1, "finalizer"))
		throwStdException(t, "FieldException", "Class {} does not have a 'finalizer' field", className(t, 1));

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

uword _memberOwner(CrocThread* t)
{
	checkAnyParam(t, 1);
	checkStringParam(t, 2);
	dup(t, 2);
	getMemberOwner(t, 1);
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
	return 0;
}

uword _isFrozen(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Class);
	pushBool(t, isClassFrozen(t, 1));
	return 1;
}

const Docs[] _globalFuncDocs =
[

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

	{kind: "function", name: "Finalizable",
	params: [Param("cls", "class")],
	docs:
	`Used as a class decorator to make classes have finalizers.

	The class should have a method called "finalizer". This method will be set as the class finalizer, and will be
	called on instances of this class when they are about to be collected.

	\param[cls] is the class to have its finalizer set.
	\returns \tt{cls} as per the decorator protocol.
	\throws[exceptions.FieldException] if \tt{cls} has no field named "finalizer".
	\throws[exceptions.TypeException] if the "finalizer" field is not a function.`},

	{kind: "function", name: "memberOwner",
	params: [Param("o", "class|instance"), Param("name", "string")],
	docs:
	`Gets the class in which the given member (field or method) was defined.

	When you use \link{fieldsOf} or \link{methodsOf}, each field has an associated "owner" which is the class in which
	that field or method was defined. You can directly access this owner class with this function. For instance,

\code
class C
{
	x = 5
}
\endcode

	With this class, \tt{object.memberOwner(C, "x")} returns \tt{C} itself, as this is the class in which \tt{"x"} was
	defined.

	\param[o] is the class or instance in which to look.
	\param[name] is the name of the field whose owner is to be retrieved.
	\returns the class in which the given field was defined.`},

	{kind: "function", name: "addMethod",
	params: [Param("cls", "class"), Param("name", "string"), Param("func", "function")],
	docs:
	`Adds a new method to a class.

	The class must not be frozen, and no method or field of the same name may exist.`},

];