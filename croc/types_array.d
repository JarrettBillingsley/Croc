/******************************************************************************
This module contains internal implementation of the array object.

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

module croc.types_array;

import tango.stdc.string;

import croc.base_alloc;
import croc.base_gc;
import croc.base_opcodes;
import croc.types;
import croc.utils;

struct array
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	// Create a new array object of the given length.
	package CrocArray* create(ref Allocator alloc, uword size)
	{
		auto ret = alloc.allocate!(CrocArray)();
		mixin(writeBarrier!("alloc", "ret"));
		ret.data = allocData!(false)(alloc, size);
		ret.length = size;
		return ret;
	}

	// Free an array object.
	package void free(ref Allocator alloc, CrocArray* a)
	{
		alloc.freeArray(a.data);
		alloc.free(a);
	}

	// Resize an array object.
	package void resize(ref Allocator alloc, CrocArray* a, uword newSize)
	{
		if(newSize == a.length)
			return;

		auto oldSize = a.length;

		if(newSize < oldSize)
			mixin(writeBarrier!("alloc", "a"));

		a.length = newSize;

		if(newSize < oldSize)
		{
			a.data[newSize .. oldSize] = CrocValue.init;

			if(newSize < (a.data.length >> 1))
				alloc.resizeArray(a.data, largerPow2(a.length));
		}
		else if(newSize > a.data.length)
			alloc.resizeArray(a.data, largerPow2(newSize));
	}

	// Slice an array object to create a new array object with its own data.
	package CrocArray* slice(ref Allocator alloc, CrocArray* a, uword lo, uword hi)
	{
		auto n = alloc.allocate!(CrocArray);
		n.length = hi - lo;
		n.data = alloc.dupArray(a.data[lo .. hi]);
		return n;
	}

	// Assign an entire other array into a slice of the destination array. Handles overlapping copies as well.
	package void sliceAssign(ref Allocator alloc, CrocArray* a, uword lo, uword hi, CrocArray* other)
	{
		auto dest = a.data[lo .. hi];
		auto src = other.toArray();

		assert(dest.length == src.length);

		auto len = dest.length * CrocValue.sizeof;

		if(len > 0)
			mixin(writeBarrier!("alloc", "a"));

		if((dest.ptr + len) <= src.ptr || (src.ptr + len) <= dest.ptr)
			memcpy(dest.ptr, src.ptr, len);
		else
			memmove(dest.ptr, src.ptr, len);
	}

	// Sets a block of values (only called by the SetArray instruction in the interpreter).
	package void setBlock(ref Allocator alloc, CrocArray* a, uword block, CrocValue[] data)
	{
		auto start = block * Instruction.arraySetFields;
		auto end = start + data.length;

		// Since Op.SetArray can use a variadic number of values, the number
		// of elements actually added to the array in the array constructor
		// may exceed the size with which the array was created. So it should be
		// resized.
		if(end > a.length)
			array.resize(alloc, a, end);

		mixin(writeBarrier!("alloc", "a"));
		a.data[start .. end] = data[];
	}

	// Fills an entire array with a value.
	package void fill(ref Allocator alloc, CrocArray* a, CrocValue val)
	{
		if(a.length > 0)
		{
			mixin(writeBarrier!("alloc", "a"));
			a.toArray()[] = val;
		}
	}

	// Index-assigns an element.
	package void idxa(ref Allocator alloc, CrocArray* a, uword idx, CrocValue val)
	{
		auto slot = &a.toArray()[idx];

		if(((*slot).isObject() || val.isObject()) && *slot != val)
			mixin(writeBarrier!("alloc", "a"));

		*slot = val;
	}

	// Returns `true` if one of the values in the array is identical to ('is') the given value.
	package bool contains(CrocArray* a, ref CrocValue v)
	{
		foreach(ref val; a.toArray())
			if(val.opEquals(v))
				return true;

		return false;
	}

	// Returns a new array that is the concatenation of the two source arrays.
	package CrocArray* cat(ref Allocator alloc, CrocArray* a, CrocArray* b)
	{
		auto ret = array.create(alloc, a.length + b.length);
		mixin(writeBarrier!("alloc", "ret"));
		ret.data[0 .. a.length] = a.toArray();
		ret.data[a.length .. $] = b.toArray();
		return ret;
	}

	// Returns a new array that is the concatenation of the source array and value.
	package CrocArray* cat(ref Allocator alloc, CrocArray* a, CrocValue* v)
	{
		auto ret = array.create(alloc, a.length + 1);
		mixin(writeBarrier!("alloc", "ret"));
		ret.data[0 .. $ - 1] = a.toArray();
		ret.data[$ - 1] = *v;
		return ret;
	}

	// Append the value v to the end of array a.
	package void append(ref Allocator alloc, CrocArray* a, CrocValue* v)
	{
		mixin(writeBarrier!("alloc", "a"));
		array.resize(alloc, a, a.length + 1);
		a.data[a.length - 1] = *v;
	}

	// ================================================================================================================================================
	// Private
	// ================================================================================================================================================

	// Allocate the array that holds an array's data. This is separate from the array object so that
	// it can be resized.
	private CrocValue[] allocData(bool overallocate)(ref Allocator alloc, uword size)
	{
		static if(overallocate)
			return alloc.allocArray!(CrocValue)(largerPow2(size));
		else
			return alloc.allocArray!(CrocValue)(size);
	}
}
