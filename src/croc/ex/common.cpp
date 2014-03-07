
#include "croc/api.h"
#include "croc/types/base.hpp"
#include "croc/util/str.hpp"

namespace croc
{
extern "C"
{
	word_t croc_ex_lookup(CrocThread* t, const char* name)
	{
		auto len = strlen(name);

		if(len == 0)
			croc_eh_throwStd(t, "ApiError", "The name '%s' is not formatted correctly", name);

		bool isFirst = true;
		word_t idx;

		delimiters(crocstr::n(cast(uchar*)name, len), atoda("."), [&](crocstr segment)
		{
			if(segment.length == 0)
				croc_eh_throwStd(t, "ApiError", "The name '%s' is not formatted correctly", name);

			if(isFirst)
			{
				isFirst = false;
				idx = croc_pushStringn(t, cast(const char*)segment.ptr, segment.length);
				croc_pushGlobalStk(t);
			}
			else
			{
				croc_pushStringn(t, cast(const char*)segment.ptr, segment.length);
				croc_fieldStk(t, -2);
			}
		});

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