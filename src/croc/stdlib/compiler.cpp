
#include <string.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
	void _pushFlagsArray(CrocThread* t, uword f)
	{
		auto start = croc_getStackSize(t);

		if(f & CrocCompilerFlags_TypeConstraints) croc_pushString(t, "typeconstraints");
		if(f & CrocCompilerFlags_Asserts)         croc_pushString(t, "asserts");
		if(f & CrocCompilerFlags_Debug)           croc_pushString(t, "debug");
		if(f & CrocCompilerFlags_Docs)            croc_pushString(t, "docs");

		croc_array_newFromStack(t, croc_getStackSize(t) - start);
	}

	uword _stringToFlag(CrocThread* t, word idx)
	{
		auto s = croc_ex_checkStringParam(t, idx);

		if(strcmp(s, "typeconstraints") == 0)
			return CrocCompilerFlags_TypeConstraints;
		if(strcmp(s, "asserts") == 0)
			return CrocCompilerFlags_Asserts;
		if(strcmp(s, "debug") == 0)
			return CrocCompilerFlags_Debug;
		if(strcmp(s, "docs") == 0)
			return CrocCompilerFlags_Docs;
		if(strcmp(s, "all") == 0)
			return CrocCompilerFlags_All;
		if(strcmp(s, "alldocs") == 0)
			return CrocCompilerFlags_AllDocs;

		croc_eh_throwStd(t, "ValueError", "Invalid flag '%s'", s);
		return 0; // dummy
	}

	void _pushResultToString(CrocThread* t, word result)
	{
		switch(result)
		{
			case CrocCompilerReturn_UnexpectedEOF: croc_pushString(t, "unexpectedeof"); break;
			case CrocCompilerReturn_LoneStatement: croc_pushString(t, "lonestatement"); break;
			case CrocCompilerReturn_DanglingDoc:   croc_pushString(t, "danglingdoc");   break;
			case CrocCompilerReturn_Error:         croc_pushString(t, "error");         break;
			default: assert(false);
		}
	}

	word_t _compileModuleImpl(CrocThread* t, bool dt)
	{
		croc_ex_checkStringParam(t, 1);
		auto name = croc_ex_optStringParam(t, 2, "<compiled from string>");

		croc_dup(t, 1);
		const char* modName;
		auto result = (dt ? croc_compiler_compileModuleDT : croc_compiler_compileModule)(t, name, &modName);

		if(result >= 0)
		{
			croc_pushString(t, modName);

			if(dt)
			{
				croc_moveToTop(t, -3);
				return 3;
			}
			else
				return 2;
		}

		_pushResultToString(t, result);
		return 2;
	}

	word_t _compileStmtsImpl(CrocThread* t, bool dt)
	{
		croc_ex_checkStringParam(t, 1);
		auto name = croc_ex_optStringParam(t, 2, "<compiled from string>");
		croc_dup(t, 1);
		auto result = (dt ? croc_compiler_compileStmtsDT : croc_compiler_compileStmts)(t, name);

		if(result >= 0)
		{
			if(dt)
				croc_swapTop(t);

			return dt ? 2 : 1;
		}

		_pushResultToString(t, result);
		return 2;
	}

	word_t _setFlags(CrocThread* t)
	{
		uword f = 0;

		for(uword i = 1; i < croc_getStackSize(t); i++)
			f |= _stringToFlag(t, i);

		_pushFlagsArray(t, croc_compiler_setFlags(t, f));
		return 1;
	}

	word_t _getFlags(CrocThread* t)
	{
		_pushFlagsArray(t, croc_compiler_getFlags(t));
		return 1;
	}

	word_t _compileModule(CrocThread* t)
	{
		return _compileModuleImpl(t, false);
	}

	word_t _compileStmts(CrocThread* t)
	{
		return _compileStmtsImpl(t, false);
	}

	word_t _compileExpr(CrocThread* t)
	{
		croc_ex_checkStringParam(t, 1);
		auto name = croc_ex_optStringParam(t, 2, "<compiled from string>");
		croc_dup(t, 1);
		auto result = croc_compiler_compileExpr(t, name);

		if(result >= 0)
			return 1;

		_pushResultToString(t, result);
		return 2;
	}

	word_t _compileModuleDT(CrocThread* t)
	{
		return _compileModuleImpl(t, true);
	}

	word_t _compileStmtsDT(CrocThread* t)
	{
		return _compileStmtsImpl(t, true);
	}

	word_t _compileModuleEx(CrocThread* t)
	{
		_compileModuleImpl(t, false);

		if(!croc_isFuncdef(t, -2))
		{
			croc_popTop(t);
			croc_eh_throw(t);
		}

		return 2;
	}

	word_t _compileStmtsEx(CrocThread* t)
	{
		if(_compileStmtsImpl(t, false) == 2)
		{
			croc_popTop(t);
			croc_eh_throw(t);
		}

		return 1;
	}

	word_t _compileExprEx(CrocThread* t)
	{
		if(_compileExpr(t) == 2)
		{
			croc_popTop(t);
			croc_eh_throw(t);
		}

		return 1;
	}

	word_t _compileModuleDTEx(CrocThread* t)
	{
		if(_compileModuleImpl(t, true) == 2)
		{
			croc_popTop(t);
			croc_eh_throw(t);
		}

		return 3;
	}

	word_t _compileStmtsDTEx(CrocThread* t)
	{
		_compileStmtsImpl(t, true);

		if(!croc_isFuncdef(t, -2))
		{
			croc_popTop(t);
			croc_eh_throw(t);
		}

		return 2;
	}

	word_t _runString(CrocThread* t)
	{
		auto haveEnv = croc_ex_optParam(t, 3, CrocType_Namespace);

		if(_compileStmtsImpl(t, false) == 2)
		{
			croc_popTop(t);
			croc_eh_throw(t);
		}

		if(haveEnv)
			croc_dup(t, 3);
		else
			croc_pushCurEnvironment(t);

		croc_function_newScriptWithEnv(t, -2);
		croc_pushNull(t);
		return croc_call(t, -2, -1);
	}

	word_t _eval(CrocThread* t)
	{
		auto haveEnv = croc_ex_optParam(t, 3, CrocType_Namespace);
		_compileExprEx(t);

		if(haveEnv)
			croc_dup(t, 3);
		else
			croc_pushCurEnvironment(t);

		croc_function_newScriptWithEnv(t, -2);
		croc_pushNull(t);
		return croc_call(t, -2, -1);
	}

	const CrocRegisterFunc _globalFuncs[] =
	{
		{"setFlags",          -1, &_setFlags         },
		{"getFlags",           0, &_getFlags         },
		{"compileModule",      2, &_compileModule    },
		{"compileStmts",       2, &_compileStmts     },
		{"compileExpr",        2, &_compileExpr      },
		{"compileModuleDT",    2, &_compileModuleDT  },
		{"compileStmtsDT",     2, &_compileStmtsDT   },
		{"compileModuleEx",    2, &_compileModuleEx  },
		{"compileStmtsEx",     2, &_compileStmtsEx   },
		{"compileExprEx",      2, &_compileExprEx    },
		{"compileModuleDTEx",  2, &_compileModuleDTEx},
		{"compileStmtsDTEx",   2, &_compileStmtsDTEx },
		{"runString",          3, &_runString        },
		{"eval",               3, &_eval             },
		{nullptr, 0, nullptr}
	};

	word loader(CrocThread* t)
	{
		croc_ex_registerGlobals(t, _globalFuncs);
		return 0;
	}
	}

	void initCompilerLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "compiler", &loader);
		croc_ex_import(t, "compiler");
	}
}