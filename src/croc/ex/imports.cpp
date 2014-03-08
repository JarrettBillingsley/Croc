
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
extern "C"
{
	word_t croc_ex_importNS(CrocThread* t, const char* name)
	{
		croc_pushString(t, name);
		croc_ex_importNSStk(t, -1);
		croc_insertAndPop(t, -2);
		return croc_getStackSize(t) - 1;
	}

	word_t croc_ex_importNSStk(CrocThread* t_, word_t name)
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

	word_t croc_ex_importFromStringNSStk(CrocThread* t_, const char* name, const char* srcName)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(_, -1, String, "source");
		(void)_;

		if(name == nullptr)
			croc_eh_throwStd(t_, "ApiError", "'name' is null");

		if(srcName == nullptr)
			srcName = name;

		croc_ex_lookup(t_, "modules.customLoaders");
		croc_insert(t_, -2);
		const char* modName;
		croc_compiler_compileModuleEx(t_, srcName, &modName);

		if(strcmp(name, modName) != 0)
			croc_eh_throwStd(t_, "ImportException",
				"Import name (%s) does not match name given in module statement (%s)", name, modName);

		croc_fielda(t_, -2, modName);
		croc_popTop(t_);
		return croc_ex_importNS(t_, modName);
	}
}
}