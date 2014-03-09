
#include <cstdio>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/all.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
	// =================================================================================================================
	// Function metatable

	word_t _functionIsNative(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Function);
		croc_pushBool(t, croc_function_isNative(t, 0));
		return 1;
	}

	word_t _functionNumParams(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Function);
		croc_pushInt(t, croc_function_getNumParams(t, 0));
		return 1;
	}

	word_t _functionMaxParams(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Function);
		croc_pushInt(t, croc_function_getMaxParams(t, 0));
		return 1;
	}

	word_t _functionIsVararg(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Function);
		croc_pushBool(t, croc_function_isVararg(t, 0));
		return 1;
	}

	word_t _functionIsCacheable(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Function);
		auto f = getFunction(Thread::from(t), 0);
		croc_pushBool(t, f->isNative ? false : f->scriptFunc->upvals.length == 0);
		return 1;
	}

	// =================================================================================================================
	// Funcdef metatable

	word_t _funcdefNumParams(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Funcdef);
		croc_pushInt(t, getFuncdef(Thread::from(t), 0)->numParams);
		return 1;
	}

	word_t _funcdefIsVararg(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Funcdef);
		croc_pushBool(t, getFuncdef(Thread::from(t), 0)->isVararg);
		return 1;
	}

	word_t _funcdefIsCacheable(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Funcdef);
		croc_pushBool(t, getFuncdef(Thread::from(t), 0)->upvals.length == 0);
		return 1;
	}

	word_t _funcdefIsCached(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Funcdef);
		croc_pushBool(t, getFuncdef(Thread::from(t), 0)->cachedFunc != nullptr);
		return 1;
	}

	word_t _funcdefClose(CrocThread* t)
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

	// =================================================================================================================
	// Weak reference stuff

	word_t _weakref(CrocThread* t)
	{
		croc_ex_checkAnyParam(t, 1);
		croc_weakref_push(t, 1);
		return 1;
	}

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

	// =================================================================================================================
	// Reflection-esque stuff

	word_t _typeof(CrocThread* t)
	{
		croc_ex_checkAnyParam(t, 1);
		croc_pushString(t, typeToString(croc_type(t, 1)));
		return 1;
	}

	word_t _nameOf(CrocThread* t)
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

	word_t _hasField(CrocThread* t)
	{
		croc_ex_checkAnyParam(t, 1);
		croc_ex_checkParam(t, 2, CrocType_String);
		croc_pushBool(t, croc_hasFieldStk(t, 1, 2));
		return 1;
	}

	word_t _hasMethod(CrocThread* t)
	{
		croc_ex_checkAnyParam(t, 1);
		croc_ex_checkParam(t, 2, CrocType_String);
		croc_pushBool(t, croc_hasMethodStk(t, 1, 2));
		return 1;
	}

#define MAKE_IS_PARAM(T)\
	word_t _is##T(CrocThread* t)\
	{\
		croc_ex_checkAnyParam(t, 1);\
		croc_pushBool(t, croc_type(t, 1) == CrocType_##T);\
		return 1;\
	}

	MAKE_IS_PARAM(Null)
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

	// =================================================================================================================
	// Conversions

	word_t _toString(CrocThread* t)
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

	word_t _rawToString(CrocThread* t)
	{
		croc_ex_checkAnyParam(t, 1);
		croc_pushToStringRaw(t, 1);
		return 1;
	}

	word_t _toBool(CrocThread* t)
	{
		croc_ex_checkAnyParam(t, 1);
		croc_pushBool(t, croc_isTrue(t, 1));
		return 1;
	}

	word_t _toInt(CrocThread* t)
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

	word_t _toFloat(CrocThread* t)
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
							printf("\\u%4x", cast(uword)c);
						else
							printf("\\U%8x", cast(uword)c);
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
				bool first = true;
				croc_dup(t, tab);

				word_t state;
				croc_foreachBegin(t, &state, 1);
				while(croc_foreachNext(t, &state, 2))
				{
					if(first)
						first = false;
					else
						printf(", ");

					if(croc_thread_hasPendingHalt(t))
						croc_thread_halt(t);

					printf("[");
					outputRepr(t, -2, shown);
					printf("] = ");
					croc_dup(t, -1);
					outputRepr(t, -1, shown);
					croc_popTop(t);
				}
				croc_foreachEnd(t, &state);
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
				croc_dup(t, ns);
				bool first = true;

				word_t state;
				croc_foreachBegin(t, &state, 1);
				while(croc_foreachNext(t, &state, 2))
				{
					if(croc_thread_hasPendingHalt(t))
						croc_thread_halt(t);

					if(first)
						first = false;
					else
						printf(", ");

					printf("%s", croc_getString(t, -2));
				}
				croc_foreachEnd(t, &state);
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

	// =================================================================================================================
	// Registration

	const CrocRegisterFunc _funcMetatable[] =
	{
		{"isNative",    0, &_functionIsNative   },
		{"numParams",   0, &_functionNumParams  },
		{"maxParams",   0, &_functionMaxParams  },
		{"isVararg",    0, &_functionIsVararg   },
		{"isCacheable", 0, &_functionIsCacheable},
		{nullptr, 0, nullptr}
	};

	const CrocRegisterFunc _funcdefMetatable[] =
	{
		{"numParams",   0, &_funcdefNumParams  },
		{"isVararg",    0, &_funcdefIsVararg   },
		{"isCacheable", 0, &_funcdefIsCacheable},
		{"isCached",    0, &_funcdefIsCached   },
		{"close",       1, &_funcdefClose      },
		{nullptr, 0, nullptr}
	};

	const CrocRegisterFunc _weakrefFuncs[] =
	{
		{"weakref", 1, &_weakref},
		{"deref",   1, &_deref  },
		{nullptr, 0, nullptr}
	};

	const CrocRegisterFunc _reflFuncs[] =
	{
		{"typeof",      1, &_typeof     },
		{"nameOf",      1, &_nameOf     },
		{"hasField",    2, &_hasField   },
		{"hasMethod",   2, &_hasMethod  },

		{"isNull",      1, &_isNull     },
		{"isBool",      1, &_isBool     },
		{"isInt",       1, &_isInt      },
		{"isFloat",     1, &_isFloat    },
		{"isNativeobj", 1, &_isNativeobj},
		{"isString",    1, &_isString   },
		{"isWeakref",   1, &_isWeakref  },
		{"isTable",     1, &_isTable    },
		{"isNamespace", 1, &_isNamespace},
		{"isArray",     1, &_isArray    },
		{"isMemblock",  1, &_isMemblock },
		{"isFunction",  1, &_isFunction },
		{"isFuncdef",   1, &_isFuncdef  },
		{"isClass",     1, &_isClass    },
		{"isInstance",  1, &_isInstance },
		{"isThread",    1, &_isThread   },
		{nullptr, 0, nullptr}
	};

	const CrocRegisterFunc _convFuncs[] =
	{
		{"toString",    1, &_toString   },
		{"rawToString", 1, &_rawToString},
		{"toBool",      1, &_toBool     },
		{"toInt",       1, &_toInt      },
		{"toFloat",     1, &_toFloat    },
		{nullptr, 0, nullptr}
	};
	}

	void initMiscLib(CrocThread* t)
	{
		croc_namespace_new(t, "function");
			croc_ex_registerFields(t, _funcMetatable);
		croc_vm_setTypeMT(t, CrocType_Function);

		croc_namespace_new(t, "funcdef");
			croc_ex_registerFields(t, _funcdefMetatable);
		croc_vm_setTypeMT(t, CrocType_Funcdef);

		croc_ex_registerGlobals(t, _weakrefFuncs);
		croc_ex_registerGlobals(t, _reflFuncs);
		croc_ex_registerGlobals(t, _convFuncs);

			croc_function_new(t, "dumpValWork", 2, &_dumpValWork, 0);
			croc_table_new(t, 0);
		croc_function_new(t, "dumpVal", 2, &_dumpVal, 2);
		croc_newGlobal(t, "dumpVal");

		initMiscLib_Vector(t);
	}
}