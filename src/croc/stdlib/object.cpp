
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{
const StdlibRegisterInfo _newClass_info =
{
	Docstr(DFunc("newClass") DParam("name", "string") DVararg
	R"(A function for creating a class from a name and optional base classes. The built-in class declaration syntax in
	Croc doesn't allow you to parameterize the name, so this function allows you to do so.

	The varargs are the optional base classes, and they must all be of type \tt{class}. Of course, you can pass zero
	base classes.)"),

	"newClass", -1
};

word_t _newClass(CrocThread* t)
{
	auto name = croc_ex_checkStringParam(t, 1);
	auto size = croc_getStackSize(t);

	for(word slot = 2; slot < cast(word)size; slot++)
		croc_ex_checkParam(t, slot, CrocType_Class);

	croc_class_new(t, name, size - 2);
	return 1;
}

word_t _classFieldsOfIter(CrocThread* t)
{
	croc_pushUpval(t, 0);
	auto c = getClass(Thread::from(t), -1);
	croc_pushUpval(t, 1);
	auto index = cast(uword)croc_getInt(t, -1);
	croc_pop(t, 2);

	String** key;
	Value* value;

	if(c->nextField(index, key, value))
	{
		croc_pushInt(t, index);
		croc_setUpval(t, 1);

		push(Thread::from(t), Value::from(*key));
		push(Thread::from(t), *value);
		return 2;
	}

	return 0;
}

word_t _instanceFieldsOfIter(CrocThread* t)
{
	croc_pushUpval(t, 0);
	auto c = getInstance(Thread::from(t), -1);
	croc_pushUpval(t, 1);
	auto index = cast(uword)croc_getInt(t, -1);
	croc_pop(t, 2);

	String** key;
	Value* value;

	if(c->nextField(index, key, value))
	{
		croc_pushInt(t, index);
		croc_setUpval(t, 1);

		push(Thread::from(t), Value::from(*key));
		push(Thread::from(t), *value);
		return 2;
	}

	return 0;
}

const StdlibRegisterInfo _fieldsOf_info =
{
	Docstr(DFunc("fieldsOf") DParam("value", "class|instance")
	R"(Given a class or instance, returns an iterator function which iterates over all the fields in that object.

	The iterator gives two indices: the name of the field, then its value. For example:

\code
class Base
{
	x = 5
	y = 10
}

class Derived : Base
{
	override x = 20
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
	\returns an iterator function.)"),

	"fieldsOf", 1
};

word_t _fieldsOf(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);
	croc_dup(t, 1);
	croc_pushInt(t, 0);

	if(croc_isClass(t, 1))
		croc_function_new(t, "fieldsOfClassIter", 1, &_classFieldsOfIter, 2);
	else if(croc_isInstance(t, 1))
		croc_function_new(t, "fieldsOfInstanceIter", 1, &_instanceFieldsOfIter, 2);
	else
		croc_ex_paramTypeError(t, 1, "class|instance");

	return 1;
}

word_t _methodsOfIter(CrocThread* t)
{
	croc_pushUpval(t, 0);
	auto c = getClass(Thread::from(t), -1);
	croc_pushUpval(t, 1);
	auto index = cast(uword)croc_getInt(t, -1);
	croc_pop(t, 2);

	String** key;
	Value* value;

	while(c->nextMethod(index, key, value))
	{
		croc_pushInt(t, index);
		croc_setUpval(t, 1);

		push(Thread::from(t), Value::from(*key));
		push(Thread::from(t), *value);
		return 2;
	}

	return 0;
}

const StdlibRegisterInfo _methodsOf_info =
{
	Docstr(DFunc("methodsOf") DParam("value", "class|instance")
	R"(Just like \link{fieldsOf}, but iterates over methods instead.

	\param[value] is the class or instance whose methods you want to iterate over. If you pass an \tt{instance}, it will
	just iterate over its class's methods instead (since instances don't store methods).
	\returns an iterator function.)"),

	"methodsOf", 1
};

word_t _methodsOf(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);

	if(croc_isClass(t, 1))
		croc_dup(t, 1);
	else if(croc_isInstance(t, 1))
		croc_superOf(t, 1);
	else
		croc_ex_paramTypeError(t, 1, "class|instance");

	croc_pushInt(t, 0);
	croc_function_new(t, "methodsOfIter", 1, &_methodsOfIter, 2);
	return 1;
}

const StdlibRegisterInfo _addMethod_info =
{
	Docstr(DFunc("addMethod") DParam("cls", "class") DParam("name", "string") DParamAny("value")
	R"(Adds a new method to a class. The method can be any type, not just functions.

	The class must not be frozen, and no method or field of the same name may exist.)"),

	"addMethod", 3
};

word_t _addMethod(CrocThread* t)
{
	croc_ex_checkParam(t, 1, CrocType_Class);
	croc_ex_checkStringParam(t, 2);
	croc_ex_checkAnyParam(t, 3);
	croc_dup(t, 2);
	croc_dup(t, 3);
	croc_class_addMethodStk(t, 1);
	return 0;
}

const StdlibRegisterInfo _addField_info =
{
	Docstr(DFunc("addField") DParam("cls", "class") DParam("name", "string") DParamD("value", "any", "null")
	R"(Adds a new field to a class.

	The class must not be frozen, and no method or field of the same name may exist. The \tt{value} parameter is
	optional.)"),

	"addField", 3
};

word_t _addField(CrocThread* t)
{
	croc_ex_checkParam(t, 1, CrocType_Class);
	croc_ex_checkStringParam(t, 2);

	if(!croc_isValidIndex(t, 3))
		croc_pushNull(t);

	croc_dup(t, 2);
	croc_dup(t, 3);
	croc_class_addFieldStk(t, 1);
	return 0;
}

const StdlibRegisterInfo _addMethodOverride_info =
{
	Docstr(DFunc("addMethodOverride") DParam("cls", "class") DParam("name", "string") DParamAny("value")
	R"(Adds a new method to a class, overriding any existing method of the same name. Works just like the \tt{override}
	keyword in an actual class declaration.

	The class must not be frozen, and a method of the same name must exist.)"),

	"addMethodOverride", 3
};

word_t _addMethodOverride(CrocThread* t)
{
	croc_ex_checkParam(t, 1, CrocType_Class);
	croc_ex_checkStringParam(t, 2);
	croc_ex_checkAnyParam(t, 3);
	croc_dup(t, 2);
	croc_dup(t, 3);
	croc_class_addMethodOStk(t, 1);
	return 0;
}

const StdlibRegisterInfo _addFieldOverride_info =
{
	Docstr(DFunc("addFieldOverride") DParam("cls", "class") DParam("name", "string") DParamD("value", "any", "null")
	R"(Adds a new field to a class, overriding any existing field of the same name. Works just like the \tt{override}
	keyword in an actual class declaration.

	The class must not be frozen, and a field of the same name must exist. The \tt{value} parameter is optional.)"),

	"addFieldOverride", 3
};

word_t _addFieldOverride(CrocThread* t)
{
	croc_ex_checkParam(t, 1, CrocType_Class);
	croc_ex_checkStringParam(t, 2);

	if(!croc_isValidIndex(t, 3))
		croc_pushNull(t);

	croc_dup(t, 2);
	croc_dup(t, 3);
	croc_class_addFieldOStk(t, 1);
	return 0;
}

const StdlibRegisterInfo _removeMember_info =
{
	Docstr(DFunc("removeMember") DParam("cls", "class") DParam("name", "string")
	R"(Removes a member (method or field) from a class.

	The class must not be frozen, and there must be a member of the given name to remove.)"),

	"removeMember", 2
};

word_t _removeMember(CrocThread* t)
{
	croc_ex_checkParam(t, 1, CrocType_Class);
	croc_ex_checkStringParam(t, 2);
	croc_dup(t, 2);
	croc_class_removeMemberStk(t, 1);
	return 0;
}

const StdlibRegisterInfo _freeze_info =
{
	Docstr(DFunc("freeze") DParam("cls", "class")
	R"(Forces a class to be frozen.

	Normally classes are frozen when they are instantiated or derived from, but you can force them to be frozen with
	this function to prevent any tampering.)"),

	"freeze", 1
};

word_t _freeze(CrocThread* t)
{
	croc_ex_checkParam(t, 1, CrocType_Class);
	croc_class_freeze(t, 1);
	croc_dup(t, 1);
	return 1;
}

const StdlibRegisterInfo _isFrozen_info =
{
	Docstr(DFunc("isFrozen") DParam("cls", "class")
	R"(\returns a bool indicating whether or not the given class is frozen.)"),

	"isFrozen", 1
};

word_t _isFrozen(CrocThread* t)
{
	croc_ex_checkParam(t, 1, CrocType_Class);
	croc_pushBool(t, croc_class_isFrozen(t, 1));
	return 1;
}

const StdlibRegisterInfo _isFinalizable_info =
{
	Docstr(DFunc("isFinalizable") DParam("value", "class|instance")
	R"(\returns a bool indicating whether or not the given class or instance is finalizable.

	\b{If \tt{value} is an unfrozen class, it will be frozen!} There is no way to be sure a class is finalizable without
	freezing it first.)"),

	"isFinalizable", 1
};

word_t _isFinalizable(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);

	if(croc_isClass(t, 1))
	{
		croc_class_freeze(t, 1);
		croc_pushBool(t, getClass(Thread::from(t), 1)->finalizer != nullptr);
	}
	else if(croc_isInstance(t, 1))
		croc_pushBool(t, getInstance(Thread::from(t), 1)->parent->finalizer != nullptr);
	else
		croc_ex_paramTypeError(t, 1, "class|instance");

	return 1;
}

const StdlibRegisterInfo _instanceOf_info =
{
	Docstr(DFunc("instanceOf") DParamAny("value") DParam("cls", "class")
	R"(\returns \tt{true} if \tt{value} is an instance and it is an instance of \tt{cls}, and \tt{false} otherwise. In
	other words, it returns \tt{isInstance(value) && value.super is cls}.)"),

	"instanceOf", 2
};

word_t _instanceOf(CrocThread* t)
{
	croc_ex_checkParam(t, 2, CrocType_Class);

	if(croc_isInstance(t, 1))
	{
		croc_superOf(t, 1);
		croc_pushBool(t, croc_is(t, -1, 2));
	}
	else
		croc_pushBool(t, false);

	return 1;
}

const StdlibRegister _globalFuncs[] =
{
	_DListItem(_newClass),
	_DListItem(_fieldsOf),
	_DListItem(_methodsOf),
	_DListItem(_addMethod),
	_DListItem(_addField),
	_DListItem(_addMethodOverride),
	_DListItem(_addFieldOverride),
	_DListItem(_removeMember),
	_DListItem(_freeze),
	_DListItem(_isFrozen),
	_DListItem(_isFinalizable),
	_DListItem(_instanceOf),
	_DListEnd
};

word loader(CrocThread* t)
{
	registerGlobals(t, _globalFuncs);
	return 0;
}
}

void initObjectLib(CrocThread* t)
{
	croc_ex_makeModule(t, "object", &loader);
	croc_ex_importNS(t, "object");
#ifdef CROC_BUILTIN_DOCS
	CrocDoc doc;
	croc_ex_doc_init(t, &doc, __FILE__);
	croc_ex_doc_push(&doc,
	DModule("object")
	R"(The \tt{object} library provides access to aspects of the object model not covered by Croc's syntax. This
	includes adding and removing fields and methods of classes and reflecting over the members of classes and
	instances.)");
		docFields(&doc, _globalFuncs);
	croc_ex_doc_pop(&doc, -1);
	croc_ex_doc_finish(&doc);
#endif
	croc_popTop(t);
}
}