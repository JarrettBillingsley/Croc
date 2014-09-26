
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
	/** Runs a garbage collection cycle, but only if the VM decides it needs one. */
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

	/** Forces a garbage collection cycle. */
	uword_t croc_gc_collect(CrocThread* t_)
	{
		auto ret = gcInternal(Thread::from(t_), false);
		runPostGCCallbacks(t_);
		return ret;
	}

	/** Forces a full garbage collection cycle. This will also scan reference cycles for garbage. */
	uword_t croc_gc_collectFull(CrocThread* t_)
	{
		auto ret = gcInternal(Thread::from(t_), true);
		runPostGCCallbacks(t_);
		return ret;
	}

	/** Sets various limits used by the garbage collector. Most have an effect on how often GC collections are run. You
	can set these limits to better suit your program, or to enforce certain behaviors, but setting them incorrectly can
	cause the GC to thrash, collecting way too often and hogging the CPU. Be careful.

	\param type
	\parblock
	is the limit type to set. The values are as follows:

	- \c CrocGCLimit_NurseryLimit - The size, in bytes, of the nursery generation. Defaults to 512KB. Most objects are
	initially allocated in the nursery. When the nursery fills up (the number of bytes allocated exceeds this limit), a
	collection will be triggered. Setting the nursery limit higher will cause collections to run less often, but they
	will take longer to complete. Setting the nursery limit lower will put more pressure on the older generation as it
	will not give young objects a chance to die off, as they usually do. Setting the nursery limit to 0 will cause a
	collection to be triggered on every allocation. That's probably bad.

	- \c CrocGCLimit_MetadataLimit - The size, in bytes, of the GC metadata. Defaults to 128KB. The metadata includes
	two buffers: one keeps track of which old-generation objects have been modified; the other keeps track of which old-
	generation objects need to have their reference counts decreased. This is pretty low-level stuff, but generally
	speaking, the more object mutation your program has, the faster these buffers will fill up. When they do, a
	collection is triggered. Much like the nursery limit, setting this value higher will cause collections to occur less
	often but they will take longer. Setting it lower will put more pressure on the older generation, as it will tend to
	pull objects out of the nursery before they can have a chance to die off. Setting the metadata limit to 0 will cause
	a collection to be triggered on every mutation. That's also probably bad!

	- \c CrocGCLimit_NurserySizeCutoff - The maximum size, in bytes, of an object that can be allocated in the nursery.
	Defaults to 256. If an object is bigger than this, it will be allocated directly in the old generation instead. This
	avoids having large objects fill up the nursery and causing more collections than necessary. Chances are this won't
	happen too often, unless you're allocating really huge class instances. Setting this value to 0 will effectively
	turn the GC algorithm into a regular deferred reference counting GC, with only one generation. Maybe that'd be
	useful for you?

	- \c CrocGCLimit_CycleCollectInterval - Since the Croc reference implementation uses a form of reference counting to
	do garbage collection, it must detect cyclic garbage (which would otherwise never be freed). Cyclic garbage usually
	forms only a small part of all garbage, but ignoring it would cause memory leaks. In order to avoid that, the GC
	must occasionally run a separate cycle collection algorithm during the GC cycle. This is triggered when enough
	potential cyclic garbage is buffered (see the next limit type for that), or every \a n collections, whichever comes
	first. This limit is that \a n. It defaults to 50; that is, every 50 garbage collection cycles, a cycle collection
	will be forced, regardless of how much potential cyclic garbage has been buffered. Setting this limit to 0 will
	force a cycle collection at every GC cycle, which isn't that great for performance. Setting this limit very high
	will cause cycle collections only to be triggered if enough potential cyclic garbage is buffered, but it's then
	possible that that garbage can hang around until program end, wasting memory.

	- \c CrocGCLimit_CycleMetadataLimit - As explained above, the GC will buffer potential cyclic garbage during normal
	GC cycles, and then when a cycle collection is initiated, it will look at that buffered garbage and determine
	whether it really is garbage. This limit is similar to metadataLimit in that it measures the size of a buffer, and
	when that buffer size crosses this limit, a cycle collection is triggered. This defaults to 128KB. The more cyclic
	garbage your program produces, the faster this buffer will fill up. Note that Croc is somewhat smart about what it
	considers potential cyclic garbage; only objects whose reference counts decrease to a non-zero value are candidates
	for cycle collection. Of course, this is only a heuristic, and can have false positives, meaning non-cyclic objects
	(living or dead) can be scanned by the cycle collector as well. Thus the cycle collector must be run to reclaim ALL
	dead objects.

	\endparblock

	\param lim is the value of the limit.
	\returns the previous value of the limit that you set. */
	uword_t croc_gc_setLimit(CrocThread* t_, CrocGCLimit type, uword_t lim)
	{
		auto t = Thread::from(t_);
		uword_t* p;

		switch(type)
		{
			case CrocGCLimit_NurseryLimit:         p = &t->vm->mem.nurseryLimit;       break;
			case CrocGCLimit_MetadataLimit:        p = &t->vm->mem.metadataLimit;      break;
			case CrocGCLimit_NurserySizeCutoff:    p = &t->vm->mem.nurserySizeCutoff;  break;
			case CrocGCLimit_CycleCollectInterval: p = &t->vm->mem.nextCycleCollect;   break;
			case CrocGCLimit_CycleMetadataLimit:   p = &t->vm->mem.cycleMetadataLimit; break;
			default:
				croc_eh_throwStd(t_, "ValueError", "Invalid limit type");
				assert(false);
				p = nullptr;
		}

		auto ret = *p;
		*p = lim;
		return ret;
	}

	/** Gets GC limits as explained above.
	\param type is the type of limit to get.
	\returns the current value of that limit. */
	uword_t croc_gc_getLimit(CrocThread* t_, CrocGCLimit type)
	{
		auto t = Thread::from(t_);

		switch(type)
		{
			case CrocGCLimit_NurseryLimit:         return t->vm->mem.nurseryLimit;
			case CrocGCLimit_MetadataLimit:        return t->vm->mem.metadataLimit;
			case CrocGCLimit_NurserySizeCutoff:    return t->vm->mem.nurserySizeCutoff;
			case CrocGCLimit_CycleCollectInterval: return t->vm->mem.nextCycleCollect;
			case CrocGCLimit_CycleMetadataLimit:   return t->vm->mem.cycleMetadataLimit;
			default:
				return croc_eh_throwStd(t_, "ValueError", "Invalid limit type");
		}
	}
}