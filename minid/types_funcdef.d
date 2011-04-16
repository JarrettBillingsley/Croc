/******************************************************************************
This module contains internal implementation of the funcdef object.  This is
the definition of a function, as opposed to the function object, which is a
closure which points to a function definition.

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

module minid.types_funcdef;

import minid.alloc;
import minid.types;

struct funcdef
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	package MDFuncDef* create(ref Allocator alloc)
	{
		return alloc.allocate!(MDFuncDef);
	}

	package void free(ref Allocator alloc, MDFuncDef* fd)
	{
		alloc.freeArray(fd.paramMasks);
		alloc.freeArray(fd.innerFuncs);
		alloc.freeArray(fd.constants);
		alloc.freeArray(fd.code);

		foreach(ref st; fd.switchTables)
			st.offsets.clear(alloc);

		alloc.freeArray(fd.switchTables);
		alloc.freeArray(fd.lineInfo);
		alloc.freeArray(fd.upvalNames);
		alloc.freeArray(fd.locVarDescs);

		alloc.free(fd);
	}
}