
#include <limits>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
	const char* PostGCCallbacks = "gc.postGCCallbacks";

	word_t _collect(CrocThread* t)
	{
		croc_pushInt(t, croc_gc_collect(t));
		return 1;
	}

	word_t _collectFull(CrocThread* t)
	{
		croc_pushInt(t, croc_gc_collectFull(t));
		return 1;
	}

	word_t _allocated(CrocThread* t)
	{
		croc_pushInt(t, croc_vm_bytesAllocated(t));
		return 1;
	}

	word_t _limit(CrocThread* t)
	{
		auto limType = croc_ex_checkStringParam(t, 1);

		if(croc_isValidIndex(t, 2))
		{
			auto lim = croc_ex_checkIntParam(t, 2);

			if(lim < 0 || lim > std::numeric_limits<uword_t>::max())
				croc_eh_throwStd(t, "RangeError", "Invalid limit (%" CROC_INTEGER_FORMAT ")", lim);

			croc_pushInt(t, croc_gc_setLimit(t, limType, cast(uword_t)lim));
		}
		else
			croc_pushInt(t, croc_gc_getLimit(t, limType));

		return 1;
	}

	word_t _postCallback(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Function);

		auto callbacks = croc_ex_pushRegistryVar(t, PostGCCallbacks);

		if(!croc_in(t, 1, callbacks))
		{
			croc_dup(t, 1);
			croc_cateq(t, callbacks, 1);
		}

		return 0;
	}

	word_t _removePostCallback(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Function);

		auto callbacks = croc_ex_pushRegistryVar(t, PostGCCallbacks);

		croc_dupTop(t);
		croc_pushNull(t);
		croc_dup(t, 1);
		croc_methodCall(t, -3, "find", 1);
		auto idx = croc_getInt(t, -1);
		croc_popTop(t);

		if(idx != croc_len(t, callbacks))
		{
			croc_dupTop(t);
			croc_pushNull(t);
			croc_pushInt(t, idx);
			croc_methodCall(t, -3, "pop", 0);
		}

		return 0;
	}

	const CrocRegisterFunc _globalFuncs[] =
	{
		{"collect",            0, &_collect           },
		{"collectFull",        0, &_collectFull       },
		{"allocated",          0, &_allocated         },
		{"limit",              2, &_limit             },
		{"postCallback",       1, &_postCallback      },
		{"removePostCallback", 1, &_removePostCallback},
		{nullptr, 0, nullptr}
	};

	word loader(CrocThread* t)
	{
		croc_ex_registerGlobals(t, _globalFuncs);
		croc_array_new(t, 0);
		croc_ex_setRegistryVar(t, PostGCCallbacks);
		return 0;
	}
	}

	void initGCLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "gc", &loader);
		croc_ex_importModuleNoNS(t, "gc");
	}
}