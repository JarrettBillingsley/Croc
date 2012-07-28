/******************************************************************************
This module contains internal implementation of the thread object.

License:
Copyright (c) 2008 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module croc.types_thread;

import croc.base_alloc;
import croc.base_writebarrier;
import croc.types;
import croc.types_nativeobj;

struct thread
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

package:

	// Create a new thread object.
	CrocThread* create(CrocVM* vm)
	{
		auto alloc = &vm.alloc;
		auto t = alloc.allocate!(CrocThread);

		t.tryRecs = alloc.allocArray!(TryRecord)(10);
		t.currentTR = t.tryRecs.ptr;

		t.actRecs = alloc.allocArray!(ActRecord)(10);
		t.currentAR = t.actRecs.ptr;

		t.stack = alloc.allocArray!(CrocValue)(20);
		t.stackIndex = cast(AbsStack)1; // So that there is a 'this' at top-level.
		t.results = alloc.allocArray!(CrocValue)(8);

		t.tryRecs[0].actRecord = uword.max;

		t.vm = vm;
		*vm.allThreads.insert(vm.alloc, t) = true;

		return t;
	}

	// Create a new thread object with a function to be used as the coroutine body.
	CrocThread* create(CrocVM* vm, CrocFunction* coroFunc)
	{
		auto t = create(vm);
		t.coroFunc = coroFunc;
		*vm.allThreads.insert(vm.alloc, t) = true;
		return t;
	}
	
	void setHookFunc(ref Allocator alloc, CrocThread* t, CrocFunction* f)
	{
		if(t.hookFunc !is f)
		{
			mixin(writeBarrier!("alloc", "t"));
			t.hookFunc = f;
		}
	}
	
	void setCoroFunc(ref Allocator alloc, CrocThread* t, CrocFunction* f)
	{
		if(t.coroFunc !is f)
		{
			mixin(writeBarrier!("alloc", "t"));
			t.coroFunc = f;
		}
	}
	
	// Free a thread object.
	void free(CrocThread* t)
	{
		auto b = t.vm.allThreads.remove(t);
		assert(b);

		for(auto uv = t.upvalHead; uv !is null; uv = t.upvalHead)
		{
			t.upvalHead = uv.nextuv;
			uv.closedValue = *uv.value;
			uv.value = &uv.closedValue;
		}

		auto alloc = &t.vm.alloc;

		alloc.freeArray(t.results);
		alloc.freeArray(t.stack);
		alloc.freeArray(t.actRecs);
		alloc.freeArray(t.tryRecs);
		alloc.free(t);
	}
}