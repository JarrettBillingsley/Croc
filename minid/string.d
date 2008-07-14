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

module minid.string;

import tango.text.Util;

import minid.types;
import minid.utils;

struct string
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	// Create a new string object.  String objects with the same data are reused.  Thus,
	// if two string objects are identical, they are also equal.
	package MDString* create(MDVM* vm, dchar[] data)
	{
		auto h = jhash(data);

		if(auto s = vm.stringTab.lookup(data, h))
			return *s;

		auto ret = vm.alloc.allocate!(MDString)(StringSize(data.length));
		ret.hash = h;
		ret.length = data.length;
		ret.toString32()[] = data[];

		*vm.stringTab.insert(vm.alloc, ret.toString32()) = ret;

		return ret;
	}

	// Free a string object.
	package void free(MDVM* vm, MDString* s)
	{
		auto b = vm.stringTab.remove(s.toString32());
		assert(b);
		vm.alloc.free(s, StringSize(s.length));
	}
	
	// Compare two string objects.
	package mdint compare(MDString* a, MDString* b)
	{
		return dcmp(a.toString32(), b.toString32());
	}

	// See if the string contains the given character.
	package bool contains(MDString* s, dchar c)
	{
		foreach(ch; s.toString32())
			if(c == ch)
				return true;

		return false;	
	}
	
	package MDString* slice(MDVM* vm, MDString* s, uword lo, uword hi)
	{
		return create(vm, s.toString32()[lo .. hi]);
	}

	// ================================================================================================================================================
	// Private
	// ================================================================================================================================================
	
	private uword StringSize(uword length)
	{
		return MDString.sizeof + (dchar.sizeof * length);
	}
}