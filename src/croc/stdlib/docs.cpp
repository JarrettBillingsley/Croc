
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
#include "croc/stdlib/docs.croc.hpp"

	word_t _processComment(CrocThread* t)
	{
		croc_ex_checkStringParam(t, 1);
		croc_ex_checkParam(t, 2, CrocType_Table);
		croc_dup(t, 2);
		croc_dup(t, 1);
		croc_compiler_processDocComment(t);
		return 1;
	}

	word_t _parseCommentText(CrocThread* t)
	{
		croc_ex_checkStringParam(t, 1);
		croc_dup(t, 1);
		croc_compiler_parseDocCommentText(t);
		return 1;
	}

	word_t _getMetatable(CrocThread* t)
	{
		auto type = CrocType_Null;
		croc_ex_checkParam(t, 1, CrocType_String);
		auto s = getCrocstr(t, 1);

		if(s == ATODA("null"))      type = CrocType_Null;
		if(s == ATODA("bool"))      type = CrocType_Bool;      else
		if(s == ATODA("int"))       type = CrocType_Int;       else
		if(s == ATODA("float"))     type = CrocType_Float;     else
		if(s == ATODA("nativeobj")) type = CrocType_Nativeobj; else
		if(s == ATODA("string"))    type = CrocType_String;    else
		if(s == ATODA("weakref"))   type = CrocType_Weakref;   else
		if(s == ATODA("table"))     type = CrocType_Table;     else
		if(s == ATODA("namespace")) type = CrocType_Namespace; else
		if(s == ATODA("array"))     type = CrocType_Array;     else
		if(s == ATODA("memblock"))  type = CrocType_Memblock;  else
		if(s == ATODA("function"))  type = CrocType_Function;  else
		if(s == ATODA("funcdef"))   type = CrocType_Funcdef;   else
		if(s == ATODA("class"))     type = CrocType_Class;     else
		if(s == ATODA("instance"))  type = CrocType_Instance;  else
		if(s == ATODA("thread"))    type = CrocType_Thread;    else
		{
			croc_pushBool(t, false);
			return 1;
		}

		croc_pushBool(t, true);
		croc_vm_pushTypeMT(t, type);
		return 2;
	}

	const CrocRegisterFunc _globalFuncs[] =
	{
		{"processComment",   2, &_processComment  },
		{"parseCommentText", 2, &_parseCommentText},
		{"getMetatable",     1, &_getMetatable    },
		{nullptr, 0, nullptr}
	};
	}

	void initDocsLib(CrocThread* t)
	{
		croc_table_new(t, 0);
			croc_ex_registerFields(t, _globalFuncs);
		croc_newGlobal(t, "_docstmp");

		registerModuleFromString(t, "docs", docs_croc_text, "docs.croc");

		croc_vm_pushGlobals(t);
		croc_pushString(t, "_docstmp");
		croc_removeKey(t, -2);
		croc_popTop(t);
	}
}