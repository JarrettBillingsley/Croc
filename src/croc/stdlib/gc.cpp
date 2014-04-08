
#include <limits>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
	const char* PostGCCallbacks = "gc.postGCCallbacks";

	CrocGCLimit stringToLimit(CrocThread* t, word slot)
	{
		auto s = getCrocstr(t, slot);

		if(s == ATODA("nurseryLimit")) return CrocGCLimit_NurseryLimit;
		if(s == ATODA("metadataLimit")) return CrocGCLimit_MetadataLimit;
		if(s == ATODA("nurserySizeCutoff")) return CrocGCLimit_NurserySizeCutoff;
		if(s == ATODA("cycleCollectInterval")) return CrocGCLimit_CycleCollectInterval;
		if(s == ATODA("cycleMetadataLimit")) return CrocGCLimit_CycleMetadataLimit;

		return cast(CrocGCLimit)croc_eh_throwStd(t, "ValueError", "Invalid limit type '%.*s'",
			cast(int)s.length, s.ptr);
	}

DBeginList(_globalFuncs)
	Docstr(DFunc("collect")
	R"(Performs a normal garbage collection cycle. Usually you won't have to call this because the GC will be run
	periodically on its own, but sometimes it's useful to force a cycle.

	\returns the number of bytes reclaimed by the GC.)"),

	"collect", 0, [](CrocThread* t) -> word_t
	{
		croc_pushInt(t, croc_gc_collect(t));
		return 1;
	}

DListSep()
	Docstr(DFunc("collectFull")
	R"(Performs a full garbage collection cycle. Most GC cycles are relatively quick, but there are some kinds of
	objects which are put off for once-in-a-while processing because they would be too expensive to process every cycle.
	A full GC cycle will process these objects. Again, normally you don't have to call this because the GC will perform
	a full cycle on its own every once in a while, but running a full cycle will guarantee that ANY garbage objects will
	be collected, so it can be useful.

	\returns the number of bytes reclaimed by the GC.)"),

	"collectFull", 0, [](CrocThread* t) -> word_t
	{
		croc_pushInt(t, croc_gc_collectFull(t));
		return 1;
	}

DListSep()
	Docstr(DFunc("allocated")
	R"(\returns the total bytes currently allocated by this VM instance.)"),

	"allocated", 0, [](CrocThread* t) -> word_t
	{
		croc_pushInt(t, croc_vm_bytesAllocated(t));
		return 1;
	}

DListSep()
	Docstr(DFunc("limit") DParam("type", "string") DParamD("size", "int", "null")
	R"(Gets or sets various limits used by the garbage collector. Most have an effect on how often GC collections are
	run. You can set these limits to better suit your program, or to enforce certain behaviors, but setting them
	incorrectly can cause the GC to thrash, collecting way too often and hogging the CPU. Be careful.

	If only called with a \tt{type} parameter and no \tt{size} parameter, gets the given limit. If a \tt{size} parameter
	is passed, sets the given limit to that size and returns the previously-set limit.

	The \tt{type} parameter is a string that must be one of the following values:

	\blist
		\li "nurseryLimit" - The size, in bytes, of the nursery generation. Defaults to 512KB. Most objects are
			initially allocated in the nursery. When the nursery fills up (the number of bytes allocated exceeds this
			limit), a collection will be triggered. Setting the nursery limit higher will cause collections to run less
			often, but they will take longer to complete. Setting the nursery limit lower will put more pressure on the
			older generation as it will not give young objects a chance to die off, as they usually do. Setting the
			nursery limit to 0 will cause a collection to be triggered on every allocation. That's probably bad.

		\li "metadataLimit" - The size, in bytes, of the GC metadata. Defaults to 128KB. The metadata includes two
			buffers: one keeps track of which old-generation objects have been modified; the other keeps track of which
			old-generation objects need to have their reference counts decreased. This is pretty low-level stuff, but
			generally speaking, the more object mutation your program has, the faster these buffers will fill up. When
			they do, a collection is triggered. Much like the nursery limit, setting this value higher will cause
			collections to occur less often but they will take longer. Setting it lower will put more pressure on the
			older generation, as it will tend to pull objects out of the nursery before they can have a chance to die
			off. Setting the metadata limit to 0 will cause a collection to be triggered on every mutation. That's also
			probably bad!

		\li "nurserySizeCutoff" - The maximum size, in bytes, of an object that can be allocated in the nursery.
			Defaults to 256. If an object is bigger than this, it will be allocated directly in the old generation
			instead. This avoids having large objects fill up the nursery and causing more collections than necessary.
			Chances are this won't happen too often, unless you're allocating really huge class instances. Setting this
			value to 0 will effectively turn the GC algorithm into a regular deferred reference counting GC, with only
			one generation. Maybe that'd be useful for you?

		\li "cycleCollectInterval" - Since the Croc reference implementation uses a form of reference counting to do
			garbage collection, it must detect cyclic garbage (which would otherwise never be freed). Cyclic garbage
			usually forms only a small part of all garbage, but ignoring it would cause memory leaks. In order to avoid
			that, the GC must occasionally run a separate cycle collection algorithm during the GC cycle. This is
			triggered when enough potential cyclic garbage is buffered (see the next limit type for that), or every
			\em{n} collections, whichever comes first. This limit is that \em{n}. It defaults to 50; that is, every 50
			garbage collection cycles, a cycle collection will be forced, regardless of how much potential cyclic
			garbage has been buffered. Setting this limit to 0 will force a cycle collection at every GC cycle, which
			isn't that great for performance. Setting this limit very high will cause cycle collections only to be
			triggered if enough potential cyclic garbage is buffered, but it's then possible that that garbage can hang
			around until program end, wasting memory.

		\li "cycleMetadataLimit" - As explained above, the GC will buffer potential cyclic garbage during normal GC
			cycles, and then when a cycle collection is initiated, it will look at that buffered garbage and determine
			whether it really is garbage. This limit is similar to metadataLimit in that it measures the size of a
			buffer, and when that buffer size crosses this limit, a cycle collection is triggered. This defaults to
			128KB. The more cyclic garbage your program produces, the faster this buffer will fill up. Note that Croc
			is somewhat smart about what it considers potential cyclic garbage; only objects whose reference counts
			decrease to a non-zero value are candidates for cycle collection. Of course, this is only a heuristic, and
			can have false positives, meaning non-cyclic objects (living or dead) can be scanned by the cycle collector
			as well. Thus the cycle collector must be run to reclaim ALL dead objects.
	\endlist)"),

	"limit", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		auto limType = stringToLimit(t, 1);

		if(croc_isValidIndex(t, 2))
		{
			auto lim = croc_ex_checkIntParam(t, 2);

			if(lim < 0 || cast(uword)lim > std::numeric_limits<uword_t>::max())
				croc_eh_throwStd(t, "RangeError", "Invalid limit (%" CROC_INTEGER_FORMAT ")", lim);

			croc_pushInt(t, croc_gc_setLimit(t, limType, cast(uword_t)lim));
		}
		else
			croc_pushInt(t, croc_gc_getLimit(t, limType));

		return 1;
	}

DListSep()
	Docstr(DFunc("postCallback") DParam("cb", "function")
	R"(The Croc GC can maintain a list of callback functions which are called whenever the GC completes a cycle.
	Sometimes this can be a useful feature, but it's probably best not to overuse it; after all, the GC can run
	arbitrarily, and each time it's run, these callbacks are run as well. The standard library uses a post-GC callback
	to clean out empty entries from weak tables (defined in the hash library). Post-GC callbacks are a nice time to
	clean out caches and such, but it's also probably a good idea to count the number of times your callback is called
	and only perform its action once in a while instead of every GC cycle, so you don't make the GC take a long time.

	When the callbacks are called, everything is safe; these are not like finalizer functions in which the GC is
	disabled and errors are fatal. By the time the callbacks are called, the GC has completed its cycle.

	If you try to register one function more than once, nothing will happen; each function will only be called once per
	GC cycle.)"),

	"postCallback", 1, [](CrocThread* t) -> word_t
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

DListSep()
	Docstr(DFunc("removePostCallback") DParam("cb", "function")

	R"(Removes a post-GC callback function that was previously added with \link{gc.postCallback}. If the given function
	is not in the list of callbacks, nothing happens.)"),

	"removePostCallback", 1, [](CrocThread* t) -> word_t
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
DEndList()

	word loader(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);
		croc_array_new(t, 0);
		croc_ex_setRegistryVar(t, PostGCCallbacks);
		return 0;
	}
	}

	void initGCLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "gc", &loader);
		croc_ex_import(t, "gc");
	}

#ifdef CROC_BUILTIN_DOCS
	void docGCLib(CrocThread* t)
	{
		CrocDoc doc;
		croc_ex_doc_init(t, &doc, __FILE__);
		croc_ex_doc_push(&doc,
		DModule("gc")
		R"(This library is the interface to the Croc garbage collector. This interface might differ from implementation
		to implementation since different implementations can use different garbage collection algorithms. Not sure how
		to deal with that yet, but there it is.)");

		croc_pushGlobal(t, "gc");
		docFields(&doc, _globalFuncs);
		croc_ex_doc_pop(&doc, -1);
		croc_popTop(t);
		croc_ex_doc_finish(&doc);
	}
#endif
}