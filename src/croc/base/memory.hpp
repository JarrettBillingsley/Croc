#ifndef CROC_BASE_MEMORY_HPP
#define CROC_BASE_MEMORY_HPP

#include "croc/apitypes.h"
#include "croc/base/deque.hpp"
#include "croc/base/gcobject.hpp"
#include "croc/base/leakdetector.hpp"
#include "croc/base/sanity.hpp"

namespace croc
{
	struct Memory
	{
		CrocMemFunc memFunc;
		void* ctx;

		Deque modBuffer;
		Deque decBuffer;
		Deque nursery;

		// 0 for enabled, positive for disabled
		size_t gcDisabled;
		size_t totalBytes;
		size_t nurseryBytes;
		size_t nurseryLimit;
		size_t metadataLimit;
		size_t nurserySizeCutoff;
		size_t cycleCollectCountdown;
		size_t nextCycleCollect;
		size_t cycleMetadataLimit;
		LEAK_DETECT(LeakDetector leaks;)

		void init(CrocMemFunc func, void* context);

		inline bool couldUseGC() const
		{
			return
				nurseryBytes >= nurseryLimit ||
				(modBuffer.length() + decBuffer.length()) * sizeof(GCObject*) >= metadataLimit;
		}

		void resizeNurserySpace(size_t newSize);
		void clearNurserySpace();
		void cleanup();

		GCObject* allocate(size_t size, bool acyclic TYPEID_PARAM);
		GCObject* allocateFinalizable(size_t size TYPEID_PARAM);
		void makeRC(GCObject* obj);
		void free(GCObject* o TYPEID_PARAM);

		void* allocRaw(size_t size TYPEID_PARAM);
		void resizeRaw(void*& ptr, size_t& len, size_t newLen TYPEID_PARAM);
		void freeRaw(void*& ptr, size_t& len TYPEID_PARAM);

	private:
		GCObject* allocateRC(size_t size, bool acyclic TYPEID_PARAM);
		GCObject* allocateGCObject(size_t size, bool acyclic, uint32_t gcflags);
		void* realloc(void* p, size_t oldSize, size_t newSize);
	};
}

#endif