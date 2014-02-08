
#include "croc/api.h"
#include "croc/internal/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

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
}
}