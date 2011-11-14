/******************************************************************************
This module contains internal implementation of the string object.

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

module croc.types_string;

import tango.text.Util;

import croc.types;
import croc.utils;

struct string
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

package:

	CrocString* lookup(CrocVM* vm, char[] data, ref uword h)
	{
		// We don't have to verify the string if it already exists in the string table,
		// because if it does, it means it's a legal string.
		// Neither hashing nor lookup require the string to be valid UTF-8.
		h = jhash(data);

		if(auto s = vm.stringTab.lookup(data, h))
			return *s;

		return null;
	}
	
	// Create a new string object. String objects with the same data are reused. Thus,
	// if two string objects are identical, they are also equal.
	CrocString* create(CrocVM* vm, char[] data, uword h, uword cpLen)
	{
		auto ret = vm.alloc.allocate!(CrocString)(StringSize(data.length));
		ret.hash = h;
		ret.length = data.length;
		ret.cpLength = cpLen;
		ret.toString()[] = data[];

		*vm.stringTab.insert(vm.alloc, ret.toString()) = ret;
		return ret;
	}

	// Free a string object.
	void free(CrocVM* vm, CrocString* s)
	{
		auto b = vm.stringTab.remove(s.toString());
		assert(b);
		vm.alloc.free(s);
	}

	// Compare two string objects.
	crocint compare(CrocString* a, CrocString* b)
	{
		return scmp(a.toString(), b.toString());
	}

	// See if the string contains the given character.
	bool contains(CrocString* s, dchar c)
	{
		foreach(dchar ch; s.toString())
			if(c == ch)
				return true;

		return false;
	}

	// See if the string contains the given substring.
	bool contains(CrocString* s, char[] sub)
	{
		if(s.length < sub.length)
			return false;

		return s.toString().locatePattern(sub) != s.length;
	}

	// The slice indices are in codepoints, not byte indices.
	// And these indices better be good.
	CrocString* slice(CrocVM* vm, CrocString* s, uword lo, uword hi)
	{
		auto str = uniSlice(s.toString(), lo, hi);
		uword h = void;

		if(auto s = lookup(vm, str, h))
			return s;

		// don't have to verify since we're slicing from a string we know is good
		return create(vm, uniSlice(s.toString(), lo, hi), h, hi - lo);
	}

	// Like slice, the index is in codepoints, not byte indices.
	dchar charAt(CrocString* s, uword idx)
	{
		return uniCharAt(s.toString(), idx);
	}

	// ================================================================================================================================================
	// Private
	// ================================================================================================================================================

private:

	uword StringSize(uword length)
	{
		return CrocString.sizeof + (char.sizeof * length);
	}
}