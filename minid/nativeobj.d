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

module minid.nativeobj;

import minid.types;

struct nativeobj
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================
	
	// Create a new native object, or if one already exists for the given Object, return
	// that one.  For any D object, there is exactly one MiniD Native Object.
	package MDNativeObj* create(MDVM* vm, Object obj)
	{
		if(auto o = obj in vm.nativeObjs)
			return *o;
	
		auto ret = vm.alloc.allocate!(MDNativeObj);
		ret.obj = obj;
	
		// What's with the tempObj?  Well there's a tiny (but nonzero) possibility
		// that, upon inserting the native object into nativeObjs, it will cause the
		// host to perform a GC sweep.  Since this native object may or may not
		// be referenced in the main program until it's inserted into the table (which
		// wouldn't be till *after* the GC sweep), the object could get collected
		// before we even insert it.  So we put it in tempObj to expose at least
		// one reference to the object to the D host.
		// Multiple GCs are fun.
		vm.tempObj = obj;
		vm.nativeObjs[obj] = ret;
		vm.tempObj = null;
	
		return ret;
	}
	
	// Free a native object.
	package void free(MDVM* vm, MDNativeObj* obj)
	{
		assert(obj.obj in vm.nativeObjs);
	
		vm.nativeObjs.remove(obj.obj);
		vm.alloc.free(obj);
	}
}