
#include "croc/api.h"
#include "croc/internal/stack.hpp"
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
		auto s = croc_ex_checkStringParam(t, 1);

		if(strcmp(s, "null") == 0)      type = CrocType_Null;
		if(strcmp(s, "bool") == 0)      type = CrocType_Bool;      else
		if(strcmp(s, "int") == 0)       type = CrocType_Int;       else
		if(strcmp(s, "float") == 0)     type = CrocType_Float;     else
		if(strcmp(s, "nativeobj") == 0) type = CrocType_Nativeobj; else
		if(strcmp(s, "string") == 0)    type = CrocType_String;    else
		if(strcmp(s, "weakref") == 0)   type = CrocType_Weakref;   else
		if(strcmp(s, "table") == 0)     type = CrocType_Table;     else
		if(strcmp(s, "namespace") == 0) type = CrocType_Namespace; else
		if(strcmp(s, "array") == 0)     type = CrocType_Array;     else
		if(strcmp(s, "memblock") == 0)  type = CrocType_Memblock;  else
		if(strcmp(s, "function") == 0)  type = CrocType_Function;  else
		if(strcmp(s, "funcdef") == 0)   type = CrocType_Funcdef;   else
		if(strcmp(s, "class") == 0)     type = CrocType_Class;     else
		if(strcmp(s, "instance") == 0)  type = CrocType_Instance;  else
		if(strcmp(s, "thread") == 0)    type = CrocType_Thread;    else
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

		croc_ex_importFromString(t, "docs", docs_croc_text, "docs.croc");

		croc_pushGlobal(t, "_G");
		croc_pushString(t, "_docstmp");
		croc_removeKey(t, -2);
		croc_popTop(t);
	}
}