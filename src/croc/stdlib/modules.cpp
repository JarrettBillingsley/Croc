
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{
#include "croc/stdlib/modules.croc.hpp"
}

void initModulesLib(CrocThread* t)
{
	croc_table_new(t, 1);
		croc_function_new(t, "_setfenv", 2, [](CrocThread* t) -> word_t
		{
			croc_dup(t, 2);
			croc_function_setEnv(t, 1);
			return 0;
		}, 0);
		croc_fielda(t, -2, "_setfenv");

		croc_array_new(t, 0);
		for(auto addon = croc_vm_includedAddons(); *addon != nullptr; addon++)
		{
			croc_pushString(t, *addon);
			croc_cateq(t, -2, 1);
		}
		croc_fielda(t, -2, "IncludedAddons");
	croc_newGlobal(t, "_modulestmp");

	registerModuleFromString(t, "modules", modules_croc_text, "modules.croc");

	croc_vm_pushGlobals(t);
	croc_pushString(t, "_modulestmp");
	croc_removeKey(t, -2);
	croc_popTop(t);
}
}