/******************************************************************************
This module contains internal implementation of the nativeobj object.

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

module croc.types_nativeobj;

import croc.types;

struct nativeobj
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================
	
	// Create a new native object, or if one already exists for the given Object, return
	// that one. For any D object, there is exactly one Croc Native Object.
	package CrocNativeObj* create(CrocVM* vm, Object obj)
	{
		if(auto o = obj in vm.nativeObjs)
			return *o;

		auto ret = vm.alloc.allocate!(CrocNativeObj);
		ret.obj = obj;
		vm.nativeObjs[obj] = ret;

		return ret;
	}

	// Finalize a native object.
	package void finalize(CrocVM* vm, CrocNativeObj* obj)
	{
		assert(obj.obj in vm.nativeObjs);
		vm.nativeObjs.remove(obj.obj);
	}
}