#ifndef CROC_BASE_LEAKDETECTOR_HPP
#define CROC_BASE_LEAKDETECTOR_HPP

#ifndef CROC_LEAK_DETECTOR
#  define TYPEID_PARAM
#  define TYPEID_ARG
#  define LEAK_DETECT(x)
#else // else, rest of module!

#include <typeinfo>
#include <map>

#include "croc/base/sanity.hpp"

#define TYPEID_PARAM ,const std::type_info& ti
#define TYPEID_ARG ,ti
#define LEAK_DETECT(x) x

namespace croc
{
	struct LeakMemBlock
	{
		size_t len;
		const std::type_info* ti;
	};

	struct LeakDetector
	{
		typedef std::map<void*, LeakMemBlock> BlockMap;
		typedef BlockMap::iterator iter;

		BlockMap nurseryBlocks;
		BlockMap rcBlocks;
		BlockMap rawBlocks;

		void init();
		void cleanup();

		void newRaw(void* ptr, size_t size TYPEID_PARAM);
		void newNursery(void* ptr, size_t size TYPEID_PARAM);
		void newRC(void* ptr, size_t size TYPEID_PARAM);

		void freeRaw(void* ptr TYPEID_PARAM);
		void freeNursery(void* obj TYPEID_PARAM);
		void freeRC(void* obj TYPEID_PARAM);

		void checkRawExists(void* ptr TYPEID_PARAM);
		void relocateRaw(void* oldPtr, void* newPtr, size_t newSize TYPEID_PARAM);
		void clearNursery();
		void makeRC(void* obj);

		void dumpBlocks();
	};
}

#endif
#endif