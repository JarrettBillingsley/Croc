
#include <string.h>

#include "croc/api.h"
#include "croc/base/gc.hpp"
#include "croc/api/apichecks.hpp"
#include "croc/internal/gc.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

namespace
{
	uword gcInternal(Thread* t, bool fullCollect)
	{
		auto vm = t->vm;

		if(vm->mem.gcDisabled > 0)
			return 0;

		auto beforeSize = vm->mem.totalBytes;
		gcCycle(vm, fullCollect ? GCCycleType_Full : GCCycleType_Normal);
		runFinalizers(t);

		vm->stringTab.minimize(vm->mem);
		vm->weakrefTab.minimize(vm->mem);

		// This is.. possible? TODO: figure out how.
		return beforeSize > vm->mem.totalBytes ? beforeSize - vm->mem.totalBytes : 0;
	}

	void runPostGCCallbacks(CrocThread* t)
	{
		croc_vm_pushRegistry(t);
		croc_field(t, -1, "gc.postGCCallbacks");

		word_t state;
		for(state = croc_foreachBegin(t, 1); croc_foreachNext(t, state, 1); )
		{
			croc_dup(t, -1);
			croc_pushNull(t);
			croc_call(t, -2, 0);
		}
		croc_foreachEnd(t, state);

		croc_popTop(t);
	}
}

extern "C"
{
	uword_t croc_gc_maybeCollect(CrocThread* t_)
	{
		auto t = Thread::from(t_);

		if(t->vm->mem.gcDisabled > 0)
			return 0;

		if(t->vm->mem.couldUseGC())
			return croc_gc_collect(t_);
		else
			return 0;
	}

	uword_t croc_gc_collect(CrocThread* t_)
	{
		auto ret = gcInternal(Thread::from(t_), false);
		runPostGCCallbacks(t_);
		return ret;
	}

	uword_t croc_gc_collectFull(CrocThread* t_)
	{
		auto ret = gcInternal(Thread::from(t_), true);
		runPostGCCallbacks(t_);
		return ret;
	}

	uword_t croc_gc_setLimit(CrocThread* t_, const char* type, uword_t lim)
	{
		auto t = Thread::from(t_);
		uword_t* p;

		if(strncmp(type, "nurseryLimit",         30) == 0) p = &t->vm->mem.nurseryLimit;       else
		if(strncmp(type, "metadataLimit",        30) == 0) p = &t->vm->mem.metadataLimit;      else
		if(strncmp(type, "nurserySizeCutoff",    30) == 0) p = &t->vm->mem.nurserySizeCutoff;  else
		if(strncmp(type, "cycleCollectInterval", 30) == 0) p = &t->vm->mem.nextCycleCollect;   else
		if(strncmp(type, "cycleMetadataLimit",   30) == 0) p = &t->vm->mem.cycleMetadataLimit; else
		{
			croc_eh_throwStd(t_, "ValueError", "Invalid limit type '%s'", type);
			assert(false);
			p = nullptr;
		}

		auto ret = *p;
		*p = lim;
		return ret;
	}

	uword_t croc_gc_getLimit(CrocThread* t_, const char* type)
	{
		auto t = Thread::from(t_);

		if(strncmp(type, "nurseryLimit",         30) == 0) return t->vm->mem.nurseryLimit;       else
		if(strncmp(type, "metadataLimit",        30) == 0) return t->vm->mem.metadataLimit;      else
		if(strncmp(type, "nurserySizeCutoff",    30) == 0) return t->vm->mem.nurserySizeCutoff;  else
		if(strncmp(type, "cycleCollectInterval", 30) == 0) return t->vm->mem.nextCycleCollect;   else
		if(strncmp(type, "cycleMetadataLimit",   30) == 0) return t->vm->mem.cycleMetadataLimit; else
		return croc_eh_throwStd(t_, "ValueError", "Invalid limit type '%s'", type);
	}
}