#include <string.h>

#include <stdio.h>

#include "croc/apitypes.h"
#include "croc/base/deque.hpp"
#include "croc/base/gcobject.hpp"
#include "croc/base/leakdetector.hpp"
#include "croc/base/memory.hpp"
#include "croc/base/sanity.hpp"

#ifdef CROC_STOMP_MEMORY
#  define STOMPYSTOMP(ptr, len) memset(ptr, 0xCD, len)
#else
#  define STOMPYSTOMP(ptr, len) {}
#endif

namespace croc
{
	void Memory::init(CrocMemFunc func, void* context)
	{
		memFunc = func;
		ctx = context;

		LEAK_DETECT(leaks.init());
		modBuffer.init();
		decBuffer.init();
		nursery.init();

		gcDisabled = 0;
		totalBytes = 0;
		nurseryBytes = 0;
		nurseryLimit = 512 * 1024;
		metadataLimit = 128 * 1024;
		nurserySizeCutoff = 256;
		cycleCollectCountdown = 0;
		nextCycleCollect = 50;
		cycleMetadataLimit = 128 * 1024;
	}

	// ------------------------------------------------------------
	// Interfacing stuff

	void Memory::resizeNurserySpace(size_t newSize)
	{
		nurseryLimit = newSize;
	}

	void Memory::clearNurserySpace()
	{
		nursery.clear(*this);
		nurseryBytes = 0;
		LEAK_DETECT(leaks.clearNursery());
	}

	void Memory::cleanup()
	{
		clearNurserySpace();
		modBuffer.clear(*this);
		decBuffer.clear(*this);
	}

	// ------------------------------------------------------------
	// GC objects

	GCObject* Memory::allocate(size_t size, bool acyclic TYPEID_PARAM)
	{
		if(size >= nurserySizeCutoff || gcDisabled > 0)
			return allocateRC(size, acyclic TYPEID_ARG);
		else
		{
			GCObject* ret = allocateGCObject(size, acyclic, 0);
			nurseryBytes += size;
			nursery.add(*this, ret);
			LEAK_DETECT(leaks.newNursery(ret, size, ti));
			return ret;
		}
	}

	GCObject* Memory::allocateFinalizable(size_t size TYPEID_PARAM)
	{
		GCObject* ret = allocateRC(size, false TYPEID_ARG);
		SET_FLAG(ret->gcflags, GCFlags_Finalizable);
		return ret;
	}

	void Memory::makeRC(GCObject* obj)
	{
		assert(!GCOBJ_INRC(obj));
		GCOBJ_TORC(obj);
		LEAK_DETECT(leaks.makeRC(obj));

		obj->refCount = 0;

		if(GCOBJ_COLOR(obj) != GCFlags_Green)
			modBuffer.add(*this, obj);

		// debug(INCDEC) Stdout.formatln("object at {} is now in RC and its refcount is {}", obj, obj.refCount).flush;
	}

	void Memory::free(GCObject* o TYPEID_PARAM)
	{
#ifdef CROC_LEAK_DETECTOR
		if(GCOBJ_INRC(o))
			leaks.freeRC(o, ti);
		else
			leaks.freeNursery(o, ti);
#endif
		size_t sz = o->memSize;
		STOMPYSTOMP((cast(uint8_t*)o), sz);
		realloc(o, sz, 0);
	}

	// ------------------------------------------------------------
	// Raw blocks

	void* Memory::allocRaw(size_t size TYPEID_PARAM)
	{
		if(size == 0)
			return nullptr;

		void* ret = realloc(nullptr, 0, size);
		LEAK_DETECT(leaks.newRaw(ret, size, ti));
		return ret;
	}

	void Memory::resizeRaw(void*& ptr, size_t& len, size_t newLen TYPEID_PARAM)
	{
		if(len > 0)
		{	LEAK_DETECT(leaks.checkRawExists(ptr, ti)); }

		if(newLen == 0)
		{
			freeRaw(ptr, len TYPEID_ARG);
			return;
		}
		else if(newLen == len)
			return;

		size_t oldLen = len;
#ifdef CROC_STOMP_MEMORY
		if(newLen < oldLen)
		{
			char* tmp = cast(char*)ptr; // appease the compiler..
			STOMPYSTOMP(tmp + newLen, oldLen - newLen);
		}
#endif
		void* ret = realloc(ptr, oldLen, newLen);
		LEAK_DETECT(leaks.relocateRaw(ptr, ret, newLen, ti));

		ptr = ret;
		len = newLen;
	}

	void Memory::freeRaw(void*& ptr, size_t& len TYPEID_PARAM)
	{
		if(len == 0)
			return;

		LEAK_DETECT(leaks.freeRaw(ptr, ti));
		STOMPYSTOMP(ptr, len);
		realloc(ptr, len, 0);
		ptr = nullptr;
		len = 0;
	}

	// =================================================================================================================
	// Private
	// =================================================================================================================

	GCObject* Memory::allocateRC(size_t size, bool acyclic TYPEID_PARAM)
	{
		// RC space objects start off logged since we put them on the mod buffer (or they're green and don't need to be)
		GCObject* ret = allocateGCObject(size, acyclic, GCFlags_InRC);

		ret->refCount = 1;

		if(!acyclic)
			modBuffer.add(*this, ret);

		decBuffer.add(*this, ret);

		nurseryBytes += size; // yes, this is right; this prevents large RC objects from never triggering collections.

		LEAK_DETECT(leaks.newRC(ret, size, ti));
		return ret;
	}

	GCObject* Memory::allocateGCObject(size_t size, bool acyclic, uint32_t gcflags)
	{
		GCObject* ret = cast(GCObject*)realloc(nullptr, 0, size);
		memset(ret, 0, size);
		ret->memSize = size;
		ret->gcflags = gcflags | (acyclic ? GCFlags_Green : 0);
		return ret;
	}

	void* Memory::realloc(void* p, size_t oldSize, size_t newSize)
	{
		void* ret = memFunc(ctx, p, oldSize, newSize);

		if(ret == nullptr && newSize != 0)
			assert(false); // TODO:

		totalBytes += newSize - oldSize;

		// DBGPRINT("REALLOC p = %p, old = %d, new = %d ret = %p\n", p, oldSize, newSize, ret);

		return ret;
	}
}