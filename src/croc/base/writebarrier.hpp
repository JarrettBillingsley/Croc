#ifndef CROC_WRITEBARRIER_HPP
#define CROC_WRITEBARRIER_HPP

#ifndef NDEBUG
#include <stdio.h>
#endif

#include "croc/base/memory.hpp"
#include "croc/base/gcobject.hpp"
#include "croc/types.hpp"

#define WRITE_BARRIER(mem, srcObj)\
	assert((srcObj).type != CrocType_Array && srcObj.type != CrocType_Table);\
	if(GCOBJ_UNLOGGED((srcObj)))\
		writeBarrierSlow(mem, (srcObj));

#define CONTAINER_WRITE_BARRIER(mem, srcObj)\
	if(GCOBJ_UNLOGGED((srcObj)))\
	{\
		(mem).modBuffer.add((mem), (srcObj));\
		GCOBJ_LOG((srcObj));\
	}

namespace croc
{
	typedef void (*WBCallback)(GCObject* obj, void* ctx);

	void writeBarrierSlow(Memory& mem, GCObject* srcObj);
	void visitRoots(VM* vm, WBCallback callback, void* ctx);
	void visitObj(GCObject* o, bool isModifyPhase, WBCallback callback, void* ctx);
}

#endif