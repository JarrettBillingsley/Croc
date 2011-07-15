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

alias CrocMemblock.TypeStruct TypeStruct;

struct memblock
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	// Create a new memblock object of the given length.
	package CrocMemblock* create(ref Allocator alloc, TypeStruct* ts, uword itemLength)
	{
		auto ret = alloc.allocate!(CrocMemblock)();
		ret.data = alloc.allocArray!(void)(ts.itemSize * itemLength);
		ret.itemLength = itemLength;
		ret.kind = ts;
		ret.ownData = true;

		version(CrocNoMemblockClear) {} else
			(cast(ubyte*)ret.data.ptr)[0 .. ret.data.length] = 0;

		return ret;
	}

	// Create a new memblock object that only views the given array, but does not own that data.
	// The length of data must be an even multiple of the item size of the given type.
	package CrocMemblock* createView(ref Allocator alloc, TypeStruct* ts, void[] data)
	{
		assert(data.length % ts.itemSize == 0);

		auto ret = alloc.allocate!(CrocMemblock)();
		ret.data = data;
		ret.itemLength = data.length / ts.itemSize;
		ret.kind = ts;
		ret.ownData = false;

		return ret;
	}

	// Free a memblock object.
	package void free(ref Allocator alloc, CrocMemblock* m)
	{
		if(m.ownData)
			alloc.freeArray(m.data);
		alloc.free(m);
	}

	// Change a memblock so it's a view into a given array (but does not own it).
	// The length of data must be an even multiple of the item size of the given type.
	package void view(ref Allocator alloc, CrocMemblock* m, TypeStruct* ts, void[] data)
	{
		assert(data.length % ts.itemSize == 0);

		if(m.ownData)
			alloc.freeArray(m.data);

		m.data = data;
		m.itemLength = data.length / ts.itemSize;
		m.kind = ts;
		m.ownData = false;
	}

	// Resize a memblock object.
	package void resize(ref Allocator alloc, CrocMemblock* m, uword newLength)
	{
		assert(m.ownData);

		if(newLength == m.itemLength)
			return;

		version(CrocNoMemblockClear) {} else
			auto oldLength = m.itemLength;

		alloc.resizeArray(m.data, m.kind.itemSize * newLength);
		m.itemLength = newLength;

		version(CrocNoMemblockClear) {} else
		{
			if(oldLength < newLength)
				(cast(ubyte*)m.data.ptr)[oldLength * m.kind.itemSize .. m.data.length] = 0;
		}
	}

	// Slice a memblock object to create a new memblock object with its own data.
	package CrocMemblock* slice(ref Allocator alloc, CrocMemblock* m, uword lo, uword hi)
	{
		auto n = alloc.allocate!(CrocMemblock);
		n.data = alloc.dupArray(m.data[lo * m.kind.itemSize .. hi * m.kind.itemSize]);
		n.itemLength = hi - lo;
		n.kind = m.kind;
		n.ownData = true;
		return n;
	}

	// Assign an entire other memblock into a slice of the destination memblock.  Handles overlapping copies as well.
	// Both memblocks must be the same type.
	package void sliceAssign(CrocMemblock* m, uword lo, uword hi, CrocMemblock* other)
	{
		assert(m.kind is other.kind);

		auto dest = m.data[lo * m.kind.itemSize .. hi * m.kind.itemSize];
		auto src = other.data;

		assert(dest.length == src.length);

		auto len = dest.length;

		if((dest.ptr + len) <= src.ptr || (src.ptr + len) <= dest.ptr)
			memcpy(dest.ptr, src.ptr, len);
		else
			memmove(dest.ptr, src.ptr, len);
	}

	// Returns a new memblock that is the concatenation of the two source memblocks. Both memblocks must be the same type.
	package CrocMemblock* cat(ref Allocator alloc, CrocMemblock* a, CrocMemblock* b)
	{
		assert(a.kind is b.kind);
		auto ret = memblock.create(alloc, a.kind, a.itemLength + b.itemLength);
		auto split = a.itemLength * a.kind.itemSize;
		ret.data[0 .. split] = a.data[];
		ret.data[split .. $] = b.data[];
		return ret;
	}

	// Returns a new memblock that is the concatenation of a memblock and a value. The value must be of the appropriate type.
	package CrocMemblock* cat(ref Allocator alloc, CrocMemblock* a, CrocValue b)
	{
		auto ret = memblock.create(alloc, a.kind, a.itemLength + 1);
		auto split = a.itemLength * a.kind.itemSize;
		ret.data[0 .. split] = a.data[];
		indexAssign(ret, a.itemLength, b);
		return ret;
	}

	// Returns a new memblock that is the concatenation of a value and a memblock (in that order). The value must be of the
	// appropriate type.
	package CrocMemblock* cat_r(ref Allocator alloc, CrocValue a, CrocMemblock* b)
	{
		auto ret = memblock.create(alloc, b.kind, b.itemLength + 1);
		indexAssign(ret, 0, a);
		ret.data[b.kind.itemSize .. $] = b.data[];
		return ret;
	}

	// Indexes the memblock and returns the value. Expects the index to be in a valid range and the kind not to be void.
	package CrocValue index(CrocMemblock* m, uword idx)
	{
		assert(idx < m.itemLength);
		assert(m.kind.code != CrocMemblock.TypeCode.v);

		switch(m.kind.code)
		{
			case CrocMemblock.TypeCode.i8:  return CrocValue(cast(crocint)(cast(byte*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.i16: return CrocValue(cast(crocint)(cast(short*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.i32: return CrocValue(cast(crocint)(cast(int*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.i64: return CrocValue(cast(crocint)(cast(long*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.u8:  return CrocValue(cast(crocint)(cast(ubyte*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.u16: return CrocValue(cast(crocint)(cast(ushort*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.u32: return CrocValue(cast(crocint)(cast(uint*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.u64: return CrocValue(cast(crocint)(cast(ulong*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.f32: return CrocValue(cast(crocfloat)(cast(float*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.f64: return CrocValue(cast(crocfloat)(cast(double*)m.data.ptr)[idx]);

			default: assert(false);
		}
	}

	// Index assigns a value into a memblock. Expects the index to be in a valid range, the kind not to be void, and the value
	// to be of the appropriate type.
	package void indexAssign(CrocMemblock* m, uword idx, CrocValue val)
	{
		assert(idx < m.itemLength);
		assert(m.kind.code != CrocMemblock.TypeCode.v);

		switch(m.kind.code)
		{
			case CrocMemblock.TypeCode.i8:  return (cast(byte*)m.data.ptr)[idx]   = cast(byte)val.mInt;
			case CrocMemblock.TypeCode.i16: return (cast(short*)m.data.ptr)[idx]  = cast(short)val.mInt;
			case CrocMemblock.TypeCode.i32: return (cast(int*)m.data.ptr)[idx]    = cast(int)val.mInt;
			case CrocMemblock.TypeCode.i64: return (cast(long*)m.data.ptr)[idx]   = cast(long)val.mInt;
			case CrocMemblock.TypeCode.u8:  return (cast(ubyte*)m.data.ptr)[idx]  = cast(ubyte)val.mInt;
			case CrocMemblock.TypeCode.u16: return (cast(ushort*)m.data.ptr)[idx] = cast(ushort)val.mInt;
			case CrocMemblock.TypeCode.u32: return (cast(uint*)m.data.ptr)[idx]   = cast(uint)val.mInt;
			case CrocMemblock.TypeCode.u64: return (cast(ulong*)m.data.ptr)[idx]  = cast(ulong)val.mInt;
			case CrocMemblock.TypeCode.f32: return (cast(float*)m.data.ptr)[idx]  = val.type == CrocValue.Type.Int ? cast(float)val.mInt  : cast(float)val.mFloat;
			case CrocMemblock.TypeCode.f64: return (cast(double*)m.data.ptr)[idx] = val.type == CrocValue.Type.Int ? cast(double)val.mInt : cast(double)val.mFloat;

			default: assert(false);
		}
	}

}