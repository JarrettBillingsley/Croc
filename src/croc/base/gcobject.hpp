#ifndef CROC_BASE_GCOBJECT_HPP
#define CROC_BASE_GCOBJECT_HPP

#include "croc/apitypes.h"
#include "croc/base/sanity.hpp"

#ifdef CROC_LEAK_DETECTOR
#  define ALLOC_OBJ(mem, type)               cast(type*)mem.allocate(sizeof(type),           false, typeid(type))
#  define ALLOC_OBJ_ACYC(mem, type)          cast(type*)mem.allocate(sizeof(type),           true,  typeid(type))
#  define ALLOC_OBJSZ(mem, type, extra)      cast(type*)mem.allocate(sizeof(type) + (extra), false, typeid(type))
#  define ALLOC_OBJSZ_ACYC(mem, type, extra) cast(type*)mem.allocate(sizeof(type) + (extra), true,  typeid(type))
#  define ALLOC_OBJ_FINAL(mem, type)               cast(type*)mem.allocateFinalizable(sizeof(type),           typeid(type))
#  define ALLOC_OBJSZ_FINAL(mem, type, extra)      cast(type*)mem.allocateFinalizable(sizeof(type) + (extra), typeid(type))
#  define FREE_OBJ(mem, type, ptr)           mem.free((ptr), typeid(type))
#else
#  define ALLOC_OBJ(mem, type)               cast(type*)mem.allocate(sizeof(type),           false)
#  define ALLOC_OBJ_ACYC(mem, type)          cast(type*)mem.allocate(sizeof(type),           true)
#  define ALLOC_OBJSZ(mem, type, extra)      cast(type*)mem.allocate(sizeof(type) + (extra), false)
#  define ALLOC_OBJSZ_ACYC(mem, type, extra) cast(type*)mem.allocate(sizeof(type) + (extra), true)
#  define ALLOC_OBJ_FINAL(mem, type)               cast(type*)mem.allocateFinalizable(sizeof(type)          )
#  define ALLOC_OBJSZ_FINAL(mem, type, extra)      cast(type*)mem.allocateFinalizable(sizeof(type) + (extra))
#  define FREE_OBJ(mem, type, ptr)           mem.free((ptr))
#endif

#define GCOBJ_UNLOGGED(o) TEST_FLAG((o)->gcflags, GCFlags_Unlogged)
#define GCOBJ_LOG(o) CLEAR_FLAG((o)->gcflags, GCFlags_Unlogged)
#define GCOBJ_UNLOG(o) SET_FLAG((o)->gcflags, GCFlags_Unlogged)

#define GCOBJ_INRC(o) TEST_FLAG((o)->gcflags, GCFlags_InRC)
#define GCOBJ_TORC(o) SET_FLAG((o)->gcflags, GCFlags_InRC | GCFlags_JustMoved | GCFlags_Unlogged)
#define GCOBJ_CLEARJUSTMOVED(o) CLEAR_FLAG((o)->gcflags, GCFlags_JustMoved)

#define GCOBJ_COLOR(o) ((o)->gcflags & GCFlags_ColorMask)
#define GCOBJ_SETCOLOR(o, c) ((o)->gcflags = ((o)->gcflags & ~GCFlags_ColorMask) | (c))

#define GCOBJ_CYCLELOGGED(o) TEST_FLAG((o)->gcflags, GCFlags_CycleLogged)
#define GCOBJ_CYCLELOG(o) SET_FLAG((o)->gcflags, GCFlags_CycleLogged)
#define GCOBJ_CYCLEUNLOG(o) CLEAR_FLAG((o)->gcflags, GCFlags_CycleLogged)

#define GCOBJ_FINALIZABLE(o) TEST_FLAG((o)->gcflags, GCFlags_Finalizable)
#define GCOBJ_FINALIZED(o) TEST_FLAG((o)->gcflags, GCFlags_Finalized)
#define GCOBJ_SETFINALIZED(o) SET_FLAG((o)->gcflags, GCFlags_Finalized)

namespace croc
{
	enum GCFlags
	{
		GCFlags_Unlogged =    (1 << 0), // 0b0_00000001
		GCFlags_InRC =        (1 << 1), // 0b0_00000010

		GCFlags_Black =       (0 << 2), // 0b0_00000000
		GCFlags_Grey =        (1 << 2), // 0b0_00000100
		GCFlags_White =       (2 << 2), // 0b0_00001000
		GCFlags_Purple =      (3 << 2), // 0b0_00001100
		GCFlags_Green =       (4 << 2), // 0b0_00010000
		GCFlags_ColorMask =   (7 << 2), // 0b0_00011100

		GCFlags_CycleLogged = (1 << 5), // 0b0_00100000

		GCFlags_Finalizable = (1 << 6), // 0b0_01000000
		GCFlags_Finalized =   (1 << 7), // 0b0_10000000

		GCFlags_JustMoved =   (1 << 8)  // 0b1_00000000
	};

	struct GCObject
	{
		uint32_t gcflags;
		uint32_t refCount;
		size_t memSize;
		CrocType type;
	};
}

#endif