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

module minid.stdlib_gc;

import minid.ex;
import minid.interpreter;
import minid.types;
import minid.vm;

struct GCLib
{
static:

	public void init(MDThread* t)
	{
		makeModule(t, "gc", function uword(MDThread* t)
		{
			newFunction(t, 0, &collectGarbage, "collect");   newGlobal(t, "collect");
			newFunction(t, 0, &bytesAllocated, "allocated"); newGlobal(t, "allocated");
			return 0;
		});
		
		importModuleNoNS(t, "gc");
	}

	uword collectGarbage(MDThread* t)
	{
		pushInt(t, gc(t));
		return 1;
	}
	
	uword bytesAllocated(MDThread* t)
	{
		pushInt(t, .bytesAllocated(getVM(t)));
		return 1;
	}
}