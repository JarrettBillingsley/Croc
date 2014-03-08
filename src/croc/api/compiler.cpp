
#include "croc/api.h"
#include "croc/compiler/types.hpp"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
extern "C"
{
	uword_t croc_compiler_setFlags(CrocThread* t, uword_t flags)
	{
		auto reg = croc_vm_pushRegistry(t);
		croc_pushString(t, CompilerRegistryFlags);
		uword_t ret;

		if(croc_in(t, -1, reg))
		{
			croc_fieldStk(t, reg);
			ret = cast(uword)croc_getInt(t, -1);
			croc_popTop(t);
		}
		else
			ret = CrocCompilerFlags_All;

		croc_pushInt(t, flags);
		croc_fieldaStk(t, reg);
		croc_popTop(t);

		return ret;
	}

	uword_t croc_compiler_getFlags(CrocThread* t)
	{
		auto reg = croc_vm_pushRegistry(t);
		croc_pushString(t, CompilerRegistryFlags);
		uword_t ret;

		if(croc_in(t, -1, reg))
		{
			croc_fieldStk(t, reg);
			ret = cast(uword)croc_getInt(t, -1);
		}
		else
			ret = CrocCompilerFlags_All;

		croc_pop(t, 2);
		return ret;
	}

	namespace
	{
		int commonCompileModule(CrocThread* t_, const char* name, const char** modName, bool leaveDocTable)
		{
			auto t = Thread::from(t_);
			API_CHECK_NUM_PARAMS(1);
			API_CHECK_PARAM(src, -1, String, "source code");
			Compiler c(t);
			crocstr modNameStr;
			c.leaveDocTable(leaveDocTable);
			auto ret = c.compileModule(src->toDArray(), atoda(name), modNameStr);
			*modName = cast(const char*)modNameStr.ptr;
			croc_remove(t_, (ret >= 0 && leaveDocTable) ? -3 : -2);
			return (ret >= 0) ? ret - 1 : ret;
		}

		int commonCompileStmts(CrocThread* t_, const char* name, bool leaveDocTable)
		{
			auto t = Thread::from(t_);
			API_CHECK_NUM_PARAMS(1);
			API_CHECK_PARAM(src, -1, String, "source code");
			Compiler c(t);
			c.leaveDocTable(leaveDocTable);
			auto ret = c.compileStmts(src->toDArray(), atoda(name));
			croc_remove(t_, (ret >= 0 && leaveDocTable) ? -3 : -2);
			return (ret >= 0) ? ret - 1 : ret;
		}
	}

	int croc_compiler_compileModule(CrocThread* t_, const char* name, const char** modName)
	{
		return commonCompileModule(t_, name, modName, false);
	}

	int croc_compiler_compileStmts(CrocThread* t_, const char* name)
	{
		return commonCompileStmts(t_, name, false);
	}

	int croc_compiler_compileModuleDT(CrocThread* t_, const char* name, const char** modName)
	{
		return commonCompileModule(t_, name, modName, true);
	}

	int croc_compiler_compileStmtsDT(CrocThread* t_, const char* name)
	{
		return commonCompileStmts(t_, name, true);
	}

	int croc_compiler_compileExpr(CrocThread* t_, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(src, -1, String, "source code");
		Compiler c(t);
		auto ret = c.compileExpr(src->toDArray(), atoda(name));
		croc_insertAndPop(t_, -2);
		return (ret >= 0) ? ret - 1 : ret;
	}
}
}