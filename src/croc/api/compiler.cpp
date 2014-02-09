
#include "croc/api.h"
#include "croc/compiler/types.hpp"
#include "croc/internal/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

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

	int croc_compiler_compileModule(CrocThread* t_, const char* name, const char** modName)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(src, -1, String, "source code");

		Compiler c(t);
		return c.compileModule(src->toCString(), name, *modName);
	}

	int croc_compiler_compileStmts(CrocThread* t_, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(src, -1, String, "source code");

		Compiler c(t);
		return c.compileStmts(src->toCString(), name);

	}

	int croc_compiler_compileExpr(CrocThread* t_, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(src, -1, String, "source code");

		Compiler c(t);
		return c.compileExpr(src->toCString(), name);
	}
}
}