
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
	// =================================================================================================================
	// Function metatable

DBeginList(_funcMetatable)
	Docstr(DFunc("isNative")
	R"(\returns a bool telling if the function is implemented in native code or in Croc.)"),

	"isNative", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Function);
		croc_pushBool(t, croc_function_isNative(t, 0));
		return 1;
	}

DListSep()
	Docstr(DFunc("numParams")
	R"(\returns an integer telling how many \em{non-variadic} parameters the function takes.)"),

	"numParams", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Function);
		croc_pushInt(t, croc_function_getNumParams(t, 0));
		return 1;
	}

DListSep()
	Docstr(DFunc("maxParams")
	R"(\returns an integer of how many parameters this function this may be passed without throwing an error. Passing
	more parameters than this will guarantee that an error is thrown. Variadic functions will simply return a very large
	number from this method.)"),

	"maxParams", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Function);
		croc_pushInt(t, croc_function_getMaxParams(t, 0));
		return 1;
	}

DListSep()
	Docstr(DFunc("isVararg")
	R"(\returns a bool telling whether or not the function takes variadic parameters.)"),

	"isVararg", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Function);
		croc_pushBool(t, croc_function_isVararg(t, 0));
		return 1;
	}

DListSep()
	Docstr(DFunc("isCacheable")
	R"(\returns a bool telling whether or not a function is cacheable. Cacheable functions are script functions which
	have no upvalues, generally speaking. A cacheable function only has a single function closure object allocated for
	it during its lifetime. Only script functions can be cacheable; native functions always return false.)"),

	"isCacheable", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Function);
		auto f = getFunction(Thread::from(t), 0);
		croc_pushBool(t, f->isNative ? false : f->scriptFunc->upvals.length == 0);
		return 1;
	}
DEndList()

	// =================================================================================================================
	// Funcdef metatable

DBeginList(_funcdefMetatable)
	Docstr(DFunc("numParams")
	R"(\returns an integer telling how many \em{non-variadic} parameters the function described by the funcdef
	takes.)"),

	"numParams", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Funcdef);
		croc_pushInt(t, getFuncdef(Thread::from(t), 0)->numParams);
		return 1;
	}

DListSep()
	Docstr(DFunc("isVararg")
	R"(\returns a bool telling whether or not the function described by the funcdef takes variadic parameters.)"),

	"isVararg", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Funcdef);
		croc_pushBool(t, getFuncdef(Thread::from(t), 0)->isVararg);
		return 1;
	}

DListSep()
	Docstr(DFunc("isCacheable")
	R"(\returns a bool telling whether or not a funcdef is cacheable. Funcdefs are cacheable if they have no upvals.)"),

	"isCacheable", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Funcdef);
		croc_pushBool(t, getFuncdef(Thread::from(t), 0)->upvals.length == 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("isCached")
	R"(\returns a bool telling whether or not a funcdef has already been cached (that is, a function closure has been
	created with it). Non-cacheable funcdefs always return \tt{false} for this.)"),

	"isCached", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Funcdef);
		croc_pushBool(t, getFuncdef(Thread::from(t), 0)->cachedFunc != nullptr);
		return 1;
	}

DListSep()
	Docstr(DFunc("close") DParamD("env", "namespace", "null")
	R"(Creates a function closure from this funcdef. The same rules about environment namespace apply here as elsewhere:
	if you try to close the closure with a different namespace than it was initially closed with, it will fail.

	The funcdef may also not have any upvalues.

	\param[env] is the environment namespace that the closure will use. If you pass none, it will use the environment
	of the function that called this method.

	\returns the new closure.)"),

	"close", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Funcdef);

		if(croc_ex_optParam(t, 1, CrocType_Namespace))
		{
			croc_dup(t, 1);
			croc_function_newScriptWithEnv(t, 0);
		}
		else
			croc_function_newScript(t, 0);

		return 1;
	}
DEndList()

	// =================================================================================================================
	// Weak reference stuff

DBeginList(_weakrefFuncs)
	Docstr(DFunc("weakref") DParamAny("obj")
	R"(This function is used to create weak reference objects. If the given object is a value type (null, bool,
	int, or float), it simply returns them as-is. Otherwise returns a weak reference object that refers to the
	object. For each object, there will be exactly one weak reference object that refers to it. This means that
	if two objects are identical, their weak references will be identical and vice versa.)"),

	"weakref", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);
		croc_weakref_push(t, 1);
		return 1;
	}

DListSep()
	Docstr(DFunc("deref") DParam("obj", "null|bool|int|float|weakref")
	R"(The parameter types for this might look a bit odd, but it's because this function acts as the inverse of
	\link{weakref}. If you pass a value type into the function, it will return it as-is. Otherwise, it will
	dereference the weak reference and return that object. If the object that the weak reference referred to has
	been collected, it will return \tt{null}.)"),

	"deref", 1, [](CrocThread* t) -> word_t
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
DEndList()

	// =================================================================================================================
	// Reflection-esque stuff

DBeginList(_reflFuncs)
	Docstr(DFunc("typeof") DParamAny("value")
	R"(This will get the type of the passed-in value and return it as a string. Possible return values are "null",
	"bool", "int", "float", "string", "table", "array", "function", "class", "instance", "namespace", "thread",
	"nativeobj", "weakref", and "funcdef".)"),

	"typeof", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);
		croc_pushString(t, typeToString(croc_type(t, 1)));
		return 1;
	}

DListSep()
	Docstr(DFunc("nameOf") DParam("value", "class|function|namespace|funcdef")
	R"(Returns the name of the given value as a string. This is the name that the class, function, namespace, or funcdef
	was declared with, or an autogenerated one if it wasn't declared with a name (such as anonymous function
	literals in certain cases).)"),

	"nameOf", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);

		switch(croc_type(t, 1))
		{
			case CrocType_Function:
			case CrocType_Class:
			case CrocType_Namespace:
			case CrocType_Funcdef:
				croc_pushString(t, croc_getNameOf(t, 1));
				break;

			default:
				croc_ex_paramTypeError(t, 1, "function|class|namespace|funcdef");
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("hasField") DParamAny("value") DParam("name", "string")
	R"(Sees if \tt{value} contains the field \tt{name}. Works for tables, namespaces, classes, and instances. For any
	other type, always returns \tt{false}. Does not take opField metamethods into account.)"),

	"hasField", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);
		croc_ex_checkParam(t, 2, CrocType_String);
		croc_pushBool(t, croc_hasFieldStk(t, 1, 2));
		return 1;
	}

DListSep()
	Docstr(DFunc("hasMethod") DParamAny("value") DParam("name", "string")
	R"(Sees if the method named \tt{name} can be called on \tt{value}. Looks in metatables as well, e.g. for strings
	and arrays. Works for all types. Does not take opMethod metamethods into account.)"),

	"hasMethod", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);
		croc_ex_checkParam(t, 2, CrocType_String);
		croc_pushBool(t, croc_hasMethodStk(t, 1, 2));
		return 1;
	}

DListSep()
	Docstr(DFunc("isNull") DParamAny("o")
	R"(All these functions return \tt{true} if the passed-in value is of the given type, and \tt{false} otherwise. The
	fastest way to test if something is \tt{null}, however, is to use '\tt{x is null}'.)"),
	"isNull", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);
		croc_pushBool(t, croc_type(t, 1) == CrocType_Null);
		return 1;
	}

#define MAKE_IS_PARAM(T)\
	DListSep()\
	Docstr(DFunc("is"#T) DParamAny("o") "ditto"),\
	"is"#T, 1, [](CrocThread* t) -> word_t\
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
DEndList()

	// =================================================================================================================
	// Conversions

DBeginList(_convFuncs)
	Docstr(DFunc("toString") DParamAny("value") DParamD("style", "string", "\"d\"")
	R"(This is like \link{rawToString}, but it will call any \b{\tt{toString}} metamethods defined for the value.
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
	\endlist)"),

	"toString", 1, [](CrocThread* t) -> word_t
	{
		// auto numParams = croc_getStackSize(t) - 1;
		croc_ex_checkAnyParam(t, 1);

		// TODO:
		// if(croc_isInt(t, 1))
		// {
		// 	auto style = croc_ex_optStringParam(t, 2, "d");
		// 	char[80] buffer = void;
		// 	croc_pushString(t, safeCode(t, "exceptions.ValueError", Integer_format(buffer, getInt(t, 1), style)));
		// }
		// else

		croc_pushToString(t, 1);
		return 1;
	}

DListSep()
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

	"rawToString", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);
		croc_pushToStringRaw(t, 1);
		return 1;
	}

DListSep()
	Docstr(DFunc("toBool")
	R"(This returns the truth value of the given value. \tt{null}, \tt{false}, integer 0, and float 0.0 will all return
	\tt{false}; all other values and types will return \tt{true}.)"),

	"toBool", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);
		croc_pushBool(t, croc_isTrue(t, 1));
		return 1;
	}

DListSep()
	Docstr(DFunc("toInt")
	R"(This will convert a value into an integer. Only the following types can be converted:
	\blist
		\li \b{\tt{bool}}: Converts \tt{true} to 1 and \tt{false} to 0.
		\li \b{\tt{int}}: Just returns the value.
		\li \b{\tt{float}}: Truncates the fraction and returns the integer portion.
		\li \b{\tt{string}}: Attempts to convert the string to an integer, and assumes it's in base 10. Throws an error
			if it fails. If you want to convert a string to an integer with a base other than 10, use the string
			object's \b{\tt{toInt}} method.
	\endlist)"),

	"toInt", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);

		switch(croc_type(t, 1))
		{
			case CrocType_Bool:   croc_pushInt(t, cast(crocint)croc_getBool(t, 1)); break;
			case CrocType_Int:    croc_dup(t, 1); break;
			case CrocType_Float:  croc_pushInt(t, cast(crocint)croc_getFloat(t, 1)); break;

			// TODO: bug #73
			// case CrocType_String:
			// 	croc_pushInt(t, safeCode(t, "exceptions.ValueError", cast(crocint)Integer_toLong(getString(t, 1), 10)));
			// 	break;

			default:
				croc_pushTypeString(t, 1);
				croc_eh_throwStd(t, "TypeError", "Cannot convert type '%s' to int", croc_getString(t, -1));
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("toFloat")
	R"(This will convert a value into a float. Only the following types can be converted:
	\blist
		\li \b{\tt{bool}}: Converts \tt{true} to 1.0 and \tt{false} to 0.0.
		\li \b{\tt{int}}: Returns the value cast to a float.
		\li \b{\tt{float}}: Just returns the value.
		\li \b{\tt{string}}: Attempts to convert the string to a float. Throws an error if it fails.
	\endlist

	Other types will throw an error.)"),

	"toFloat", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);

		switch(croc_type(t, 1))
		{
			case CrocType_Bool:   croc_pushFloat(t, cast(crocfloat)croc_getBool(t, 1)); break;
			case CrocType_Int:    croc_pushFloat(t, cast(crocfloat)croc_getInt(t, 1)); break;
			case CrocType_Float:  croc_dup(t, 1); break;

			// TODO:
			// case CrocType_String:
			// 	pushFloat(t, safeCode(t, "exceptions.ValueError", cast(crocfloat)Float_toFloat(getString(t, 1))));
			// 	break;

			default:
				croc_pushTypeString(t, 1);
				croc_eh_throwStd(t, "TypeError", "Cannot convert type '%s' to float", croc_getString(t, -1));
		}

		return 1;
	}
DEndList()

	// =================================================================================================================
	// Console IO

	namespace
	{
		void outputString(CrocThread* t, word_t v)
		{
			printf("\"");

			uword_t n;
			auto s = cast(const uchar*)croc_getStringn(t, v, &n);
			auto end = s + n;

			while(s < end)
			{
				// TODO: make this faster for common case
				switch(auto c = fastDecodeUtf8Char(s))
				{
					case '\'': printf("\\\'"); break;
					case '\"': printf("\\\""); break;
					case '\\': printf("\\\\"); break;
					case '\n': printf("\\n");  break;
					case '\r': printf("\\r");  break;
					case '\t': printf("\\t");  break;

					default:
						if(c <= 0x7f && isprint(c))
							printf("%c", c);
						else if(c <= 0xFFFF)
							printf("\\u%4x", cast(uint32_t)c);
						else
							printf("\\U%8x", cast(uint32_t)c);
						break;
				}
			}

			printf("\"");
		}

		void outputRepr(CrocThread* t, word_t v, word_t shown);

		void outputArray(CrocThread* t, word_t arr, word_t shown)
		{
			if(croc_in(t, arr, shown))
			{
				printf("[...]");
				return;
			}

			croc_dup(t, arr);
			croc_pushBool(t, true);
			croc_idxa(t, shown);

			printf("[");

			auto length = croc_len(t, arr);

			if(length > 0)
			{
				croc_pushInt(t, 0);
				croc_idx(t, arr);
				outputRepr(t, -1, shown);
				croc_popTop(t);

				for(uword i = 1; i < cast(uword)length; i++)
				{
					if(croc_thread_hasPendingHalt(t))
						croc_thread_halt(t);

					printf(", ");
					croc_pushInt(t, i);
					croc_idx(t, arr);
					outputRepr(t, -1, shown);
					croc_popTop(t);
				}
			}

			printf("]");

			croc_dup(t, arr);
			croc_pushNull(t);
			croc_idxa(t, shown);
		}

		void outputTable(CrocThread* t, word_t tab, word_t shown)
		{
			if(croc_in(t, tab, shown))
			{
				printf("{...}");
				return;
			}

			croc_dup(t, tab);
			croc_pushBool(t, true);
			croc_idxa(t, shown);

			printf("{");

			auto length = croc_len(t, tab);

			if(length > 0)
			{
				auto t_ = Thread::from(t);
				bool first = true;
				for(auto node: getTable(t_, tab)->data)
				{
					if(first)
						first = false;
					else
						printf(", ");

					if(croc_thread_hasPendingHalt(t))
						croc_thread_halt(t);

					push(t_, node->key);
					push(t_, node->value);
					printf("[");
					outputRepr(t, -2, shown);
					printf("] = ");
					outputRepr(t, -1, shown);
					croc_pop(t, 2);
				}
			}

			printf("}");

			croc_dup(t, tab);
			croc_pushNull(t);
			croc_idxa(t, shown);
		}

		void outputNamespace(CrocThread* t, word ns)
		{
			croc_pushToString(t, ns);
			printf("%s { ", croc_getString(t, -1));
			croc_popTop(t);

			auto length = croc_len(t, ns);

			if(length > 0)
			{
				auto t_ = Thread::from(t);
				bool first = true;
				for(auto node: getNamespace(t_, ns)->data)
				{
					if(croc_thread_hasPendingHalt(t))
						croc_thread_halt(t);

					if(first)
						first = false;
					else
						printf(", ");

					auto s = node->key->toDArray();
					printf("%.*s", cast(int)s.length, s.ptr);
				}
			}

			printf(" }");
		}

		void outputRepr(CrocThread* t, word_t v, word_t shown)
		{
			v = croc_absIndex(t, v);

			if(croc_thread_hasPendingHalt(t))
				croc_thread_halt(t);

			switch(croc_type(t, v))
			{
				case CrocType_String:    outputString(t, v);       break;
				case CrocType_Array:     outputArray(t, v, shown); break;
				case CrocType_Namespace: outputNamespace(t, v);    break;
				case CrocType_Table:     outputTable(t, v, shown); break;

				case CrocType_Weakref:
					printf("weakref(");
					croc_weakref_deref(t, v);
					outputRepr(t, -1, shown);
					croc_popTop(t);
					printf(")");
					break;

				default:
					croc_pushToString(t, v);
					printf("%s", croc_getString(t, -1));
					croc_popTop(t);
			}
		}
	}

	word_t _dumpValWork(CrocThread* t)
	{
		word shown = 1;
		outputRepr(t, 2, shown);
		fflush(stdout);
		return 0;
	}

	word_t _dumpVal(CrocThread* t)
	{
		croc_ex_checkAnyParam(t, 1);
		auto newline = croc_ex_optBoolParam(t, 2, true);

		auto dumpValWork = croc_pushUpval(t, 0);
		croc_pushNull(t);
		auto shown = croc_pushUpval(t, 1);
		croc_dup(t, 1);

		assert(croc_len(t, shown) == 0);
#ifdef NDEBUG
		(void)shown;
#endif
		auto result = croc_tryCall(t, dumpValWork, 0);

		croc_pushUpval(t, 1);
		croc_table_clear(t, -1);
		croc_popTop(t);

		if(result < 0)
			croc_eh_rethrow(t);

		if(newline)
			printf("\n");

		return 0;
	}
	}

	void initMiscLib(CrocThread* t)
	{
		croc_namespace_new(t, "function");
			registerFields(t, _funcMetatable);
		croc_vm_setTypeMT(t, CrocType_Function);

		croc_namespace_new(t, "funcdef");
			registerFields(t, _funcdefMetatable);
		croc_vm_setTypeMT(t, CrocType_Funcdef);

		registerGlobals(t, _weakrefFuncs);
		registerGlobals(t, _reflFuncs);
		registerGlobals(t, _convFuncs);

			croc_function_new(t, "dumpValWork", 2, &_dumpValWork, 0);
			croc_table_new(t, 0);
		croc_function_new(t, "dumpVal", 2, &_dumpVal, 2);
		croc_newGlobal(t, "dumpVal");

		initMiscLib_Vector(t);
	}

#ifdef CROC_BUILTIN_DOCS
	void docMiscLib(CrocThread* t)
	{
		CrocDoc doc;
		croc_ex_doc_init(t, &doc, __FILE__);

		croc_ex_doc_push(&doc,
		DModule("Base Library")
		R"(The base library is a set of functions dealing with some language aspects which aren't covered by the syntax
		of the language, as well as miscellaneous functions that don't really fit anywhere else. The base library is
		always loaded when you create an instance of the Croc VM.)");

		croc_vm_pushTypeMT(t, CrocType_Function);
			docFields(&doc, _funcMetatable);
		croc_popTop(t);

		croc_vm_pushTypeMT(t, CrocType_Funcdef);
			docFields(&doc, _funcdefMetatable);
		croc_popTop(t);

		docGlobals(&doc, _weakrefFuncs);
		docGlobals(&doc, _reflFuncs);
		docGlobals(&doc, _convFuncs);

		croc_pushGlobal(t, "_G");
		croc_ex_doc_pop(&doc, -1);
		croc_popTop(t);
		croc_ex_doc_finish(&doc);
	}
#endif
}