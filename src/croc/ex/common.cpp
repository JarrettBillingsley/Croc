
#include "croc/api.h"
#include "croc/types.hpp"

namespace croc
{
extern "C"
{
	word_t croc_ex_lookup(CrocThread* t, const char* name)
	{
		auto len = strlen(name);

		if(len == 0)
			croc_eh_throwStd(t, "ApiError", "The name '%s' is not formatted correctly", name);

		auto end = name + len;
		auto dot = strchr(name, '.');

		if(dot == nullptr)
			return croc_pushGlobal(t, name);

		auto origName = name;
		croc_pushStringn(t, name, dot - name);
		auto idx = croc_pushGlobalStk(t);

		for(name = dot + 1; (name < end) && (dot = strchr(name, '.')); name = dot + 1)
		{
			if(dot == name)
				croc_eh_throwStd(t, "ApiError", "The name '%s' is not formatted correctly", origName);

			croc_pushStringn(t, name, dot - name);
			croc_fieldStk(t, -1);
		}

		if(name == end)
			croc_eh_throwStd(t, "ApiError", "The name '%s' is not formatted correctly", origName);

		croc_pushStringn(t, name, end - name);
		croc_fieldStk(t, -1);

		if(croc_getStackSize(t) > cast(uword)idx + 1)
			croc_insertAndPop(t, idx);

		return idx;
	}

	word_t croc_ex_pushRegistryVar(CrocThread* t, const char* name)
	{
		croc_vm_pushRegistry(t);
		croc_field(t, -1, name);
		croc_insertAndPop(t, -2);
		return croc_getStackSize(t) - 1;
	}

	void croc_ex_setRegistryVar(CrocThread* t, const char* name)
	{
		croc_vm_pushRegistry(t);
		croc_swapTop(t);
		croc_fielda(t, -2, name);
		croc_popTop(t);
	}
}
}