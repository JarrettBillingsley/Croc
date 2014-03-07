#ifndef CROC_BASE_GC_HPP
#define CROC_BASE_GC_HPP

#include "croc/types/base.hpp"

namespace croc
{
	typedef enum GCCycleType
	{
		GCCycleType_Normal,
		GCCycleType_Full,
		GCCycleType_NoRoots
	} GCCycleType;

	void gcCycle(VM* vm, GCCycleType cycleType);
}

#endif
