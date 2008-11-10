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
	package MDString* create(MDVM* vm, char[] data)
	{
		// We don't have to verify the string if it already exists in the string table,
		// because if it does, it means it's a legal string.
		auto h = jhash(data);

		if(auto s = vm.stringTab.lookup(data, h))
			return *s;

		// _Now_ we verify it.
		auto cpLen = verify(data);
		auto ret = vm.alloc.allocate!(MDString)(StringSize(data.length));
		ret.hash = h;
		ret.length = data.length;
		ret.cpLength = cpLen;
		ret.toString()[] = data[];

		*vm.stringTab.insert(vm.alloc, ret.toString()) = ret;

		return ret;
	}

	// Free a string object.
	package void free(MDVM* vm, MDString* s)
	{
		auto b = vm.stringTab.remove(s.toString());
		assert(b);
		vm.alloc.free(s, StringSize(s.length));
	}
	
	// Compare two string objects.
	package mdint compare(MDString* a, MDString* b)
	{
		return scmp(a.toString(), b.toString());
	}

	// See if the string contains the given character.
	package bool contains(MDString* s, dchar c)
	{
		foreach(dchar ch; s.toString())
			if(c == ch)
				return true;

		return false;	
	}

	// The slice indices are in codepoints, not byte indices.
	// And these indices better be good.
	package MDString* slice(MDVM* vm, MDString* s, uword lo, uword hi)
	{
		return create(vm, uniSlice(s.toString(), lo, hi));
	}

	// Like slice, the index is in codepoints, not byte indices.
	package dchar charAt(MDString* s, uword idx)
	{
		return uniCharAt(s.toString(), idx);
	}

	// ================================================================================================================================================
	// Private
	// ================================================================================================================================================

	private uword StringSize(uword length)
	{
		return MDString.sizeof + (char.sizeof * length);
	}
}