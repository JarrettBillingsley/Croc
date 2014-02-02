#ifdef CROC_LEAK_DETECTOR

#include <stdio.h>
#include <stdlib.h>

#ifdef __GNUC__
#  include <cxxabi.h>
#endif

#include "croc/base/leakdetector.hpp"
#include "croc/base/sanity.hpp"
#include "croc/base/gcobject.hpp"

namespace croc
{
	namespace
	{
		void dumpTypeName(const std::type_info* ti)
		{
#ifdef __GNUC__
			// gcc returns a mangled name which we have to demangle so it doesn't look like ass!
			int status;
			char* realname = abi::__cxa_demangle(ti->name(), 0, 0, &status);

			if(status < 0)
				fprintf(stderr, "<error demangling>\n");
			else
				fprintf(stderr, "%s", realname);

			free(realname);
#else
			fprintf(stderr, "%s", ti->name());
#endif
		}

		void invalidFree(const std::type_info& ti)
		{
			fprintf(stderr, "AWFUL: You're trying to free something that wasn't allocated on the Croc Heap, or are"
				" performing a double free! It's of type ");

			dumpTypeName(&ti);
			fprintf(stderr, "\n");
			assert(false);
		}

		void invalidResize(const std::type_info& ti)
		{
			fprintf(stderr,
				"AWFUL: You're trying to resize an array that wasn't allocated on the Croc Heap! It's of type ");

			dumpTypeName(&ti);
			fprintf(stderr, "\n");
			assert(false);
		}

		void dumpBlock(void* ptr, LeakMemBlock& block, bool raw)
		{
			fprintf(stderr, "    address %p, ", ptr);

			if(!raw)
			{
				GCObject* obj = cast(GCObject*)ptr;
				fprintf(stderr, "refcount %d, flags %03x, ", obj->refCount, obj->gcflags);
			}

			fprintf(stderr, "length %d bytes, type ", block.len);
			dumpTypeName(block.ti);
			fprintf(stderr, "\n");
		}

		void dumpList(LeakDetector::BlockMap& blocks, const char* name, bool raw)
		{
			if(blocks.size() > 0)
			{
				fprintf(stderr, "Unfreed %s blocks:\n", name);

				for(LeakDetector::iter i = blocks.begin(); i != blocks.end(); i++)
					dumpBlock((*i).first, (*i).second, raw);
			}
		}
	}

	void LeakDetector::init()
	{
		nurseryBlocks = BlockMap();
		rcBlocks = BlockMap();
		rawBlocks = BlockMap();
	}

	void LeakDetector::cleanup()
	{
		nurseryBlocks.clear();
		rcBlocks.clear();
		rawBlocks.clear();
	}

	void LeakDetector::newRaw(void* ptr, size_t size TYPEID_PARAM)
	{
		LeakMemBlock& n = rawBlocks[ptr];
		n.len = size;
		n.ti = &ti;
	}

	void LeakDetector::newNursery(void* ptr, size_t size TYPEID_PARAM)
	{
		LeakMemBlock& n = nurseryBlocks[ptr];
		n.len = size;
		n.ti = &ti;
	}

	void LeakDetector::newRC(void* ptr, size_t size TYPEID_PARAM)
	{
		LeakMemBlock& n = rcBlocks[ptr];
		n.len = size;
		n.ti = &ti;
	}

	void LeakDetector::freeRaw(void* ptr TYPEID_PARAM)
	{
		if(rawBlocks.erase(ptr) == 0)
			invalidFree(ti);
	}

	void LeakDetector::freeNursery(void* obj TYPEID_PARAM)
	{
		if(nurseryBlocks.erase(obj) == 0)
			invalidFree(ti);
	}

	void LeakDetector::freeRC(void* obj TYPEID_PARAM)
	{
		if(rcBlocks.erase(obj) == 0)
			invalidFree(ti);
	}

	void LeakDetector::checkRawExists(void* ptr TYPEID_PARAM)
	{
		LeakDetector::iter i = rawBlocks.find(ptr);

		if(i == rawBlocks.end())
			invalidResize(ti);
	}

	void LeakDetector::relocateRaw(void* oldPtr, void* newPtr, size_t newSize TYPEID_PARAM)
	{
		if(oldPtr == newPtr)
			rawBlocks[oldPtr].len = newSize;
		else
		{
			rawBlocks.erase(oldPtr);
			newRC(newPtr, newSize, ti);
		}
	}

	void LeakDetector::clearNursery()
	{
		nurseryBlocks.clear();
	}

	void LeakDetector::makeRC(void* obj)
	{
		LeakDetector::iter i = nurseryBlocks.find(obj);
		assert(i != nurseryBlocks.end());
		rcBlocks[obj] = (*i).second;
	}

	void LeakDetector::dumpBlocks()
	{
		dumpList(nurseryBlocks, "nursery", false);
		dumpList(rcBlocks, "RC", false);
		dumpList(rawBlocks, "raw", true);
	}
}

#endif