/******************************************************************************
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

module minid.thread;

version(MDRestrictedCoro) {} else
	import tango.core.Thread;

import minid.nativeobj;
import minid.types;

// ================================================================================================================================================
// Package
// ================================================================================================================================================

struct thread
{
static:
	// Create a new thread object.
	package MDThread* create(MDVM* vm)
	{
		auto alloc = &vm.alloc;
		auto t = alloc.allocate!(MDThread);

		t.tryRecs = alloc.allocArray!(TryRecord)(10);
		t.currentTR = t.tryRecs.ptr;

		t.actRecs = alloc.allocArray!(ActRecord)(10);
		t.currentAR = t.actRecs.ptr;

		t.stack = alloc.allocArray!(MDValue)(20);
		t.stackIndex = cast(AbsStack)1; // So that there is a 'this' at top-level.
		t.results = alloc.allocArray!(MDValue)(8);

		t.tryRecs[0].actRecord = uword.max;

		t.vm = vm;

		return t;
	}

	// Create a new thread object with a function to be used as the coroutine body.
	package MDThread* create(MDVM* vm, MDFunction* coroFunc)
	{
		auto t = create(vm);
		t.coroFunc = coroFunc;
		
		version(MDRestrictedCoro) {} else
		{
			version(MDPoolFibers)
			{
				if(vm.fiberPool.length > 0)
				{
					Fiber f = void;

					foreach(fiber, _; vm.fiberPool)
					{
						f = fiber;
						break;
					}

					vm.fiberPool.remove(f);
					t.coroFiber = nativeobj.create(vm, f);
				}
			}
		}

		return t;
	}

	// Free a thread object.
	package void free(MDThread* t)
	{
		version(MDRestrictedCoro) {} else
		{
			version(MDPoolFibers)
			{
				if(t.coroFiber)
					t.vm.fiberPool[t.getFiber()] = true;
			}
		}

		auto alloc = &t.vm.alloc;

		alloc.freeArray(t.results);
		alloc.freeArray(t.stack);
		alloc.freeArray(t.actRecs);
		alloc.freeArray(t.tryRecs);
		alloc.free(t);
	}
}