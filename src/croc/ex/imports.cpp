
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
extern "C"
{
	word_t croc_ex_importModule(CrocThread* t, const char* name)
	{
		croc_pushString(t, name);
		croc_ex_importModuleStk(t, -1);
		croc_insertAndPop(t, -2);
		return croc_getStackSize(t) - 1;
	}

	word_t croc_ex_importModuleStk(CrocThread* t_, word_t name)
	{
		auto t = Thread::from(t_);
		name = croc_absIndex(t_, name);
		API_CHECK_PARAM(_, name, String, "module name");
		(void)_;
		croc_ex_lookup(t_, "modules.load");
		croc_pushNull(t_);
		croc_dup(t_, name);
		croc_call(t_, -3, 1);
		return croc_getStackSize(t_) - 1;
	}

	word_t croc_ex_importModuleFromString(CrocThread* t, const char* name, const char* src, const char* srcName)
	{
		if(name == nullptr)
			croc_eh_throwStd(t, "ApiError", "'name' is null");

		if(srcName == nullptr)
			srcName = name;

		croc_ex_lookup(t, "modules.customLoaders");
		croc_pushString(t, src);
		const char* modName;
		croc_compiler_compileModuleEx(t, srcName, &modName);

		if(strcmp(name, modName) != 0)
			croc_eh_throwStd(t, "ImportException",
				"Import name (%s) does not match name given in module statement (%s)", name, modName);

		croc_fielda(t, -2, modName);
		croc_popTop(t);
		return croc_ex_importModule(t, modName);
	}
}
}