#ifndef CROC_WRITEBARRIER_HPP
#define CROC_WRITEBARRIER_HPP

// #ifndef NDEBUG
// #include <stdio.h>
// #endif

#include <functional>

#include "croc/base/memory.hpp"
#include "croc/base/gcobject.hpp"
#include "croc/types/base.hpp"

#define WRITE_BARRIER(mem, srcObj)\
	assert((srcObj)->type != CrocType_Array && (srcObj)->type != CrocType_Table);\
	if(GCOBJ_UNLOGGED((srcObj)))\
		writeBarrierSlow((mem), (srcObj));

#define CONTAINER_WRITE_BARRIER(mem, srcObj)\
	if(GCOBJ_UNLOGGED((srcObj)))\
	{\
		(mem).modBuffer.add((mem), (srcObj));\
		GCOBJ_LOG((srcObj));\
	}

namespace croc
{
	typedef std::function<void(GCObject* obj)> WBCallback;

	void writeBarrierSlow(Memory& mem, GCObject* srcObj);
	void visitRoots(VM* vm, WBCallback callback);
	void visitObj(GCObject* o, bool isModifyPhase, WBCallback callback);
}

#endif