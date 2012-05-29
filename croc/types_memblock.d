/******************************************************************************
This module contains internal implementation of the memblock object.

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

module croc.types_memblock;

import tango.stdc.string;

import croc.base_alloc;
import croc.types;

 struct memblock
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

package:

	// Create a new memblock object of the given length.
	CrocMemblock* create(ref Allocator alloc, uword itemLength)
	{
		auto ret = alloc.allocate!(CrocMemblock)();
		ret.data = alloc.allocArray!(ubyte)(itemLength);
		ret.ownData = true;

		version(CrocNoMemblockClear) {} else
			ret.data[] = 0;

		return ret;
	}

	// Create a new memblock object that only views the given array, but does not own that data.
	CrocMemblock* createView(ref Allocator alloc, void[] data)
	{
		auto ret = alloc.allocate!(CrocMemblock)();
		ret.data = cast(ubyte[])data;
		ret.ownData = false;

		return ret;
	}

	// Free a memblock object.
	void free(ref Allocator alloc, CrocMemblock* m)
	{
		if(m.ownData)
			alloc.freeArray(m.data);

		alloc.free(m);
	}

	// Change a memblock so it's a view into a given array (but does not own it).
	void view(ref Allocator alloc, CrocMemblock* m, void[] data)
	{
		if(m.ownData)
			alloc.freeArray(m.data);

		m.data = cast(ubyte[])data;
		m.ownData = false;
	}

	// Resize a memblock object.
	void resize(ref Allocator alloc, CrocMemblock* m, uword newLength)
	{
		assert(m.ownData);

		if(newLength == m.data.length)
			return;

		version(CrocNoMemblockClear) {} else
			auto oldLength = m.data.length;

		alloc.resizeArray(m.data, newLength);

		version(CrocNoMemblockClear) {} else
		{
			if(oldLength < newLength)
				m.data[oldLength .. $] = 0;
		}
	}

	// Slice a memblock object to create a new memblock object with its own data.
	CrocMemblock* slice(ref Allocator alloc, CrocMemblock* m, uword lo, uword hi)
	{
		auto n = alloc.allocate!(CrocMemblock);
		n.data = alloc.dupArray(m.data[lo .. hi]);
		n.ownData = true;
		return n;
	}

	// Assign an entire other memblock into a slice of the destination memblock. Handles overlapping copies as well.
	void sliceAssign(CrocMemblock* m, uword lo, uword hi, CrocMemblock* other)
	{
		auto dest = m.data[lo .. hi];
		auto src = other.data;

		assert(dest.length == src.length);

		auto len = dest.length;

		if((dest.ptr + len) <= src.ptr || (src.ptr + len) <= dest.ptr)
			memcpy(dest.ptr, src.ptr, len);
		else
			memmove(dest.ptr, src.ptr, len);
	}

	// Returns a new memblock that is the concatenation of the two source memblocks.
	CrocMemblock* cat(ref Allocator alloc, CrocMemblock* a, CrocMemblock* b)
	{
		auto ret = memblock.create(alloc, a.data.length + b.data.length);
		auto split = a.data.length;
		ret.data[0 .. split] = a.data[];
		ret.data[split .. $] = b.data[];
		return ret;
	}
}