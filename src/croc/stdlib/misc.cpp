
#include <cstdio>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/all.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{
// =====================================================================================================================
// Function metatable

const StdlibRegisterInfo _function_isNative_info =
{
	Docstr(DFunc("isNative")
	R"(\returns a bool telling if the function is implemented in native code or in Croc.)"),

	"isNative", 0
};

word_t _function_isNative(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Function);
	croc_pushBool(t, croc_function_isNative(t, 0));
	return 1;
}

const StdlibRegisterInfo _function_numParams_info =
{
	Docstr(DFunc("numParams")
	R"(\returns an integer telling how many \em{non-variadic} parameters the function takes.)"),

	"numParams", 0
};

word_t _function_numParams(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Function);
	croc_pushInt(t, croc_function_getNumParams(t, 0));
	return 1;
}

const StdlibRegisterInfo _function_maxParams_info =
{
	Docstr(DFunc("maxParams")
	R"(\returns an integer of how many parameters this function this may be passed without throwing an error. Passing
	more parameters than this will guarantee that an error is thrown. Variadic functions will simply return a very large
	number from this method.)"),

	"maxParams", 0
};

word_t _function_maxParams(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Function);
	croc_pushInt(t, croc_function_getMaxParams(t, 0));
	return 1;
}

const StdlibRegisterInfo _function_isVararg_info =
{
	Docstr(DFunc("isVararg")
	R"(\returns a bool telling whether or not the function takes variadic parameters.)"),

	"isVararg", 0
};

word_t _function_isVararg(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Function);
	croc_pushBool(t, croc_function_isVararg(t, 0));
	return 1;
}

const StdlibRegisterInfo _function_numReturns_info =
{
	Docstr(DFunc("numReturns")
	R"(\returns an integer telling how many \em{non-variadic} values the function returns.)"),

	"numReturns", 0
};

word_t _function_numReturns(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Function);
	croc_pushInt(t, croc_function_getNumReturns(t, 0));
	return 1;
}

const StdlibRegisterInfo _function_maxReturns_info =
{
	Docstr(DFunc("maxReturns")
	R"(\returns an integer of the maximum number of values this function can return. Variadic return functions will
	simply return a very large number from this method.)"),

	"maxReturns", 0
};

word_t _function_maxReturns(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Function);
	croc_pushInt(t, croc_function_getMaxReturns(t, 0));
	return 1;
}

const StdlibRegisterInfo _function_isVarret_info =
{
	Docstr(DFunc("isVarret")
	R"(\returns a bool telling whether or not the function has variadic returns (i.e. can return any number of
	values). Always returns \tt{true} for native functions, currently.)"),

	"isVarret", 0
};

word_t _function_isVarret(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Function);
	croc_pushBool(t, croc_function_isVarret(t, 0));
	return 1;
}

const StdlibRegisterInfo _function_isCacheable_info =
{
	Docstr(DFunc("isCacheable")
	R"(\returns a bool telling whether or not a function is cacheable. Cacheable functions are script functions which
	have no upvalues, generally speaking. A cacheable function only has a single function closure object allocated for
	it during its lifetime. Only script functions can be cacheable; native functions always return false.)"),

	"isCacheable", 0
};

word_t _function_isCacheable(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Function);
	auto f = getFunction(Thread::from(t), 0);
	croc_pushBool(t, f->isNative ? false : f->scriptFunc->upvals.length == 0);
	return 1;
}

const StdlibRegisterInfo _function_funcdef_info =
{
	Docstr(DFunc("funcdef")
	R"(\returns the \tt{funcdef} object that this function was instantiated from, or \tt{null} if this function is
	native.)"),

	"funcdef", 0
};

word_t _function_funcdef(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Function);
	croc_function_pushDef(t, 0);
	return 1;
}

const StdlibRegister _function_metatable[] =
{
	_DListItem(_function_isNative),
	_DListItem(_function_numParams),
	_DListItem(_function_maxParams),
	_DListItem(_function_isVararg),
	_DListItem(_function_numReturns),
	_DListItem(_function_maxReturns),
	_DListItem(_function_isVarret),
	_DListItem(_function_isCacheable),
	_DListItem(_function_funcdef),
	_DListEnd
};

// =====================================================================================================================
// Funcdef metatable

const StdlibRegisterInfo _funcdef_numParams_info =
{
	Docstr(DFunc("numParams")
	R"(\returns an integer telling how many \em{non-variadic} parameters the function described by the funcdef
	takes.)"),

	"numParams", 0
};

word_t _funcdef_numParams(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Funcdef);
	croc_pushInt(t, getFuncdef(Thread::from(t), 0)->numParams);
	return 1;
}

const StdlibRegisterInfo _funcdef_isVararg_info =
{
	Docstr(DFunc("isVararg")
	R"(\returns a bool telling whether or not the function described by the funcdef takes variadic parameters.)"),

	"isVararg", 0
};

word_t _funcdef_isVararg(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Funcdef);
	croc_pushBool(t, getFuncdef(Thread::from(t), 0)->isVararg);
	return 1;
}

const StdlibRegisterInfo _funcdef_numReturns_info =
{
	Docstr(DFunc("numReturns")
	R"(\returns an integer telling how many \em{non-variadic} values the function described by the funcdef returns.)"),

	"numReturns", 0
};

word_t _funcdef_numReturns(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Funcdef);
	croc_pushInt(t, getFuncdef(Thread::from(t), 0)->numReturns);
	return 1;
}

const StdlibRegisterInfo _funcdef_isVarret_info =
{
	Docstr(DFunc("isVarret")
	R"(\returns a bool telling whether or not the function has variadic returns (i.e. can return any number of
	values).)"),

	"isVarret", 0
};

word_t _funcdef_isVarret(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Funcdef);
	croc_pushBool(t, getFuncdef(Thread::from(t), 0)->isVarret);
	return 1;
}

const StdlibRegisterInfo _funcdef_isCacheable_info =
{
	Docstr(DFunc("isCacheable")
	R"(\returns a bool telling whether or not a funcdef is cacheable. Funcdefs are cacheable if they have no upvals.)"),

	"isCacheable", 0
};

word_t _funcdef_isCacheable(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Funcdef);
	croc_pushBool(t, getFuncdef(Thread::from(t), 0)->upvals.length == 0);
	return 1;
}

const StdlibRegisterInfo _funcdef_isCached_info =
{
	Docstr(DFunc("isCached")
	R"(\returns a bool telling whether or not a funcdef has already been cached (that is, a function closure has been
	created with it). Non-cacheable funcdefs always return \tt{false} for this.)"),

	"isCached", 0
};

word_t _funcdef_isCached(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Funcdef);
	croc_pushBool(t, getFuncdef(Thread::from(t), 0)->cachedFunc != nullptr);
	return 1;
}

const StdlibRegisterInfo _funcdef_close_info =
{
	Docstr(DFunc("close") DParamD("env", "namespace", "null")
	R"(Creates a function closure from this funcdef. The same rules about environment namespace apply here as elsewhere:
	if you try to close the closure with a different namespace than it was initially closed with, it will fail.

	The funcdef may also not have any upvalues.

	\param[env] is the environment namespace that the closure will use. If you pass none, it will use the environment
	of the function that called this method.

	\returns the new closure.)"),

	"close", 1
};

word_t _funcdef_close(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Funcdef);

	if(croc_ex_optParam(t, 1, CrocType_Namespace))
		croc_dup(t, 1);
	else
		croc_pushEnvironment(t, 1);

	croc_function_newScriptWithEnv(t, 0);
	return 1;
}

const StdlibRegister _funcdef_metatable[] =
{
	_DListItem(_funcdef_numParams),
	_DListItem(_funcdef_isVararg),
	_DListItem(_funcdef_numReturns),
	_DListItem(_funcdef_isVarret),
	_DListItem(_funcdef_isCacheable),
	_DListItem(_funcdef_isCached),
	_DListItem(_funcdef_close),
	_DListEnd
};

// =====================================================================================================================
// Weak reference stuff

const StdlibRegisterInfo _weakref_info =
{
	Docstr(DFunc("weakref") DParamAny("obj")
	R"(This function is used to create weak reference objects. If the given object is a value type (null, bool,
	int, or float), it simply returns them as-is. Otherwise returns a weak reference object that refers to the
	object. For each object, there will be exactly one weak reference object that refers to it. This means that
	if two objects are identical, their weak references will be identical and vice versa.)"),

	"weakref", 1
};

word_t _weakref(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);
	croc_weakref_push(t, 1);
	return 1;
}

const StdlibRegisterInfo _deref_info =
{
	Docstr(DFunc("deref") DParam("obj", "null|bool|int|float|weakref")
	R"(The parameter types for this might look a bit odd, but it's because this function acts as the inverse of
	\link{weakref}. If you pass a value type into the function, it will return it as-is. Otherwise, it will
	dereference the weak reference and return that object. If the object that the weak reference referred to has
	been collected, it will return \tt{null}.)"),

	"deref", 1
};

word_t _deref(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);

	switch(croc_type(t, 1))
	{
		case CrocType_Null:
		case CrocType_Bool:
		case CrocType_Int:
		case CrocType_Float:
		case CrocType_Nativeobj:
			croc_dup(t, 1);
			return 1;

		case CrocType_Weakref:
			croc_weakref_deref(t, 1);
			return 1;

		default:
			return croc_ex_paramTypeError(t, 1, "null|bool|int|float|nativeobj|weakref");
	}
}

const StdlibRegister _weakrefFuncs[] =
{
	_DListItem(_weakref),
	_DListItem(_deref),
	_DListEnd
};

// =====================================================================================================================
// Reflection-esque stuff

const StdlibRegisterInfo _typeof_info =
{
	Docstr(DFunc("typeof") DParamAny("value")
	R"(This will get the type of the passed-in value and return it as a string. Possible return values are "null",
	"bool", "int", "float", "string", "table", "array", "function", "class", "instance", "namespace", "thread",
	"nativeobj", "weakref", and "funcdef".)"),

	"typeof", 1
};

word_t _typeof(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);
	croc_pushString(t, typeToString(croc_type(t, 1)));
	return 1;
}

const StdlibRegisterInfo _niceTypeof_info =
{
	Docstr(DFunc("niceTypeof") DParamAny("value")
	R"(This will get a more human-readable version of \tt{value}'s type and return it as a string. This is good for
	error messages and the like.

	For classes, returns a string of the form \tt{"class <name>"}, where \tt{<name>} is the name of the class.

	For instances, returns a string of the form \tt{"instance of <name>"}, where \tt{<name>} is the name of the
	instance's class.

	For all other types, returns the same thing as \link{typeof}.)"),

	"niceTypeof", 1
};

word_t _niceTypeof(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);
	croc_pushTypeString(t, 1);
	return 1;
}

const StdlibRegisterInfo _nameOf_info =
{
	Docstr(DFunc("nameOf") DParam("value", "class|function|namespace|funcdef")
	R"(Returns the name of the given value as a string. This is the name that the class, function, namespace, or funcdef
	was declared with, or an autogenerated one if it wasn't declared with a name (such as anonymous function
	literals in certain cases).)"),

	"nameOf", 1
};

word_t _nameOf(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);

	switch(croc_type(t, 1))
	{
		case CrocType_Function:
		case CrocType_Class:
		case CrocType_Namespace:
		case CrocType_Funcdef: {
			uword_t length;
			auto s = croc_getNameOfn(t, 1, &length);
			croc_pushStringn(t, s, length);
			break;
		}
		default:
			croc_ex_paramTypeError(t, 1, "function|class|namespace|funcdef");
	}

	return 1;
}

const StdlibRegisterInfo _superOf_info =
{
	Docstr(DFunc("superOf") DParam("value", "instance|namespace")
	R"(\returns the super of the given value. For instances, this is the class that it was instantiated from; for
	namespaces, this is the parent namespace, or \tt{null} if it has none.)"),

	"superOf", 1
};

word_t _superOf(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);

	if(!croc_isInstance(t, 1) && !croc_isNamespace(t, 1))
		croc_ex_paramTypeError(t, 1, "instance|namespace");

	croc_superOf(t, 1);
	return 1;
}

const StdlibRegisterInfo _hasField_info =
{
	Docstr(DFunc("hasField") DParamAny("value") DParam("name", "string")
	R"(Sees if \tt{value} contains the field \tt{name}. Works for tables, namespaces, classes, and instances. For any
	other type, always returns \tt{false}. Does not take opField metamethods into account.)"),

	"hasField", 2
};

word_t _hasField(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);
	croc_ex_checkParam(t, 2, CrocType_String);
	croc_pushBool(t, croc_hasFieldStk(t, 1, 2));
	return 1;
}

const StdlibRegisterInfo _hasMethod_info =
{
	Docstr(DFunc("hasMethod") DParamAny("value") DParam("name", "string")
	R"(Sees if the method named \tt{name} can be called on \tt{value}. Looks in metatables as well, e.g. for strings
	and arrays. Works for all types. Does not take opMethod metamethods into account.)"),

	"hasMethod", 2
};

word_t _hasMethod(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);
	croc_ex_checkParam(t, 2, CrocType_String);
	croc_pushBool(t, croc_hasMethodStk(t, 1, 2));
	return 1;
}

const StdlibRegisterInfo _isNull_info =
{
	Docstr(DFunc("isNull") DParamAny("o")
	R"(All these functions return \tt{true} if the passed-in value is of the given type, and \tt{false} otherwise. The
	fastest way to test if something is \tt{null}, however, is to use '\tt{x is null}'.)"),
	"isNull", 1
};

word_t _isNull(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);
	croc_pushBool(t, croc_type(t, 1) == CrocType_Null);
	return 1;
}

#define MAKE_IS_PARAM(T)\
	const StdlibRegisterInfo _is##T##_info =\
	{\
		Docstr(DFunc("is"#T) DParamAny("o") "ditto"),\
		"is"#T, 1\
	};\
	word_t _is##T(CrocThread* t)\
	{\
		croc_ex_checkAnyParam(t, 1);\
		croc_pushBool(t, croc_type(t, 1) == CrocType_##T);\
		return 1;\
	}

	MAKE_IS_PARAM(Bool)
	MAKE_IS_PARAM(Int)
	MAKE_IS_PARAM(Float)
	MAKE_IS_PARAM(Nativeobj)
	MAKE_IS_PARAM(String)
	MAKE_IS_PARAM(Weakref)
	MAKE_IS_PARAM(Table)
	MAKE_IS_PARAM(Namespace)
	MAKE_IS_PARAM(Array)
	MAKE_IS_PARAM(Memblock)
	MAKE_IS_PARAM(Function)
	MAKE_IS_PARAM(Funcdef)
	MAKE_IS_PARAM(Class)
	MAKE_IS_PARAM(Instance)
	MAKE_IS_PARAM(Thread)

const StdlibRegister _reflFuncs[] =
{
	_DListItem(_typeof),
	_DListItem(_niceTypeof),
	_DListItem(_nameOf),
	_DListItem(_superOf),
	_DListItem(_hasField),
	_DListItem(_hasMethod),
	_DListItem(_isNull),
	_DListItem(_isBool),
	_DListItem(_isInt),
	_DListItem(_isFloat),
	_DListItem(_isNativeobj),
	_DListItem(_isString),
	_DListItem(_isWeakref),
	_DListItem(_isTable),
	_DListItem(_isNamespace),
	_DListItem(_isArray),
	_DListItem(_isMemblock),
	_DListItem(_isFunction),
	_DListItem(_isFuncdef),
	_DListItem(_isClass),
	_DListItem(_isInstance),
	_DListItem(_isThread),
	_DListEnd
};

// =====================================================================================================================
// Conversions

const StdlibRegisterInfo _toString_info =
{
	Docstr(DFunc("toString") DParamAny("value")
	R"(This is like \link{rawToString}, but it will call any \b{\tt{toString}} metamethods defined for the value.
	Arrays have a \b{\tt{toString}} metamethod defined for them by default, and any \b{\tt{toString}} methods defined
	for class instances will be used.

	Note that ints and floats will be converted to strings with default formatting (base 10, etc). If you need more
	control over the string formatting of numbers, use the \link[string.string.format]{string.format} method.)"),

	"toString", 1
};

word_t _toString(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);
	croc_pushToString(t, 1);
	return 1;
}

const StdlibRegisterInfo _rawToString_info =
{
	Docstr(DFunc("rawToString") DParamAny("value")
	R"x(This returns a string representation of the given value depending on its type, as follows:
	\blist
		\li \b{\tt{null}}: the string \tt{"null"}.
		\li \b{\tt{bool}}: \tt{"true"} or \tt{"false"}.
		\li \b{\tt{int}}: The decimal representation of the number.
		\li \b{\tt{float}}: The decimal representation of the number, to about 7 digits of precision.
		\li \b{\tt{string}}: The string itself.
		\li \b{\tt{nativeobj}}: A string formatted as \tt{"nativeobj 0x00000000"}, where 0x00000000 is the address of
			the native object that it references.
		\li \b{\tt{namespace}}: A string formatted as \tt{"namespace <name>"}, where <name> is the hierarchical name of
			the namespace.
		\li \b{\tt{function}}: If the function is native code, a string formatted as \tt{"native function <name>"};
			if script code, a string formatted as \tt{"script function <name>(<location>)"}.
		\li \b{\tt{funcdef}}: A string formatted as \tt{"funcdef <name>(<location>)"}.

		\li For all other types, a string formatted as \tt{"<type> 0x<address>"}, where <type> is the name of the type
			and <address> is the memory address of the object.
	\endlist)x"),

	"rawToString", 1
};

word_t _rawToString(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);
	croc_pushToStringRaw(t, 1);
	return 1;
}

const StdlibRegister _convFuncs[] =
{
	_DListItem(_toString),
	_DListItem(_rawToString),
	_DListEnd
};
}

// =====================================================================================================================
// Loader

void initMiscLib(CrocThread* t)
{
	croc_namespace_new(t, "function");
		registerFields(t, _function_metatable);
	croc_vm_setTypeMT(t, CrocType_Function);

	croc_namespace_new(t, "funcdef");
		registerFields(t, _funcdef_metatable);
	croc_vm_setTypeMT(t, CrocType_Funcdef);

	registerGlobals(t, _weakrefFuncs);
	registerGlobals(t, _reflFuncs);
	registerGlobals(t, _convFuncs);

	initMiscLib_Vector(t);
}

#ifdef CROC_BUILTIN_DOCS
void docMiscLib(CrocThread* t)
{
	CrocDoc doc;
	croc_ex_doc_init(t, &doc, __FILE__);

	croc_ex_doc_push(&doc,
	DModule("Misc Library")
	R"(The base library is a set of functions dealing with some language aspects which aren't covered by the syntax
	of the language, as well as miscellaneous functions that don't really fit anywhere else. The base library is
	always loaded when you create an instance of the Croc VM.)");

	croc_vm_pushTypeMT(t, CrocType_Function);
		croc_ex_doc_push(&doc, DNs("function")
		R"(This is the method namespace for function objects.)");
		docFields(&doc, _function_metatable);
		croc_ex_doc_pop(&doc, -1);
	croc_popTop(t);

	croc_vm_pushTypeMT(t, CrocType_Funcdef);
		croc_ex_doc_push(&doc, DNs("funcdef")
		R"(This is the method namespace for funcdef objects.)");
		docFields(&doc, _funcdef_metatable);
		croc_ex_doc_pop(&doc, -1);
	croc_popTop(t);

	docGlobals(&doc, _weakrefFuncs);
	docGlobals(&doc, _reflFuncs);
	docGlobals(&doc, _convFuncs);

	docMiscLib_Vector(t, &doc);

	croc_vm_pushGlobals(t);
	croc_ex_doc_pop(&doc, -1);
	croc_popTop(t);
	croc_ex_doc_finish(&doc);
}
#endif
}