/******************************************************************************
This module contains the garbage collector (gc) standard library module.

License:
Copyright (c) 2011 Jarrett Billingsley

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

module croc.stdlib_gc;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.types;
import croc.vm;

struct GCLib
{
static:
	const PostGCCallbacks = "gc.postGCCallbacks";

	public void init(CrocThread* t)
	{
		// TODO: expand this interface
		makeModule(t, "gc", function uword(CrocThread* t)
		{
			newFunction(t, 0, &collect,            "collect");            newGlobal(t, "collect");
			newFunction(t, 0, &allocated,          "allocated");          newGlobal(t, "allocated");
			newFunction(t, 1, &postCallback,       "postCallback");       newGlobal(t, "postCallback");
			newFunction(t, 1, &removePostCallback, "removePostCallback"); newGlobal(t, "removePostCallback");

			newArray(t, 0); setRegistryVar(t, PostGCCallbacks);

			return 0;
		});

		importModuleNoNS(t, "gc");
	}

	uword collect(CrocThread* t)
	{
		pushInt(t, gc(t));
		return 1;
	}

	uword allocated(CrocThread* t)
	{
		pushInt(t, .bytesAllocated(getVM(t)));
		return 1;
	}

	uword postCallback(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Function);

		auto callbacks = getRegistryVar(t, PostGCCallbacks);

		if(!opin(t, 1, callbacks))
		{
			dup(t, 1);
			cateq(t, callbacks, 1);
		}

		return 0;
	}
	
	uword removePostCallback(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Function);

		auto callbacks = getRegistryVar(t, PostGCCallbacks);
		
		dup(t);
		pushNull(t);
		dup(t, 1);
		methodCall(t, -3, "find", 1);
		auto idx = getInt(t, -1);
		pop(t);
		
		if(idx != len(t, callbacks))
		{
			dup(t);
			pushNull(t);
			pushInt(t, idx);
			methodCall(t, -3, "pop", 0);
		}
		
		return 0;
	}
}