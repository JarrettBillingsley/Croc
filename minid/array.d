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

module minid.array;

import tango.core.BitManip;
import tango.stdc.string;

import minid.alloc;
import minid.opcodes;
import minid.types;

struct array
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================
	
	// Create a new array object of the given length.
	package MDArray* create(ref Allocator alloc, uword size)
	{
		auto a = alloc.allocate!(MDArray);
		a.data = allocData!(false)(alloc, size);
		a.slice = a.data.toArray()[0 .. size];
		return a;
	}

	// Free an array object.
	package void free(ref Allocator alloc, MDArray* a)
	{
		alloc.free(a);
	}

	// Free an array data object.
	package void freeData(ref Allocator alloc, MDArrayData* d)
	{
		alloc.free(d, DataSize(d.length));
	}
	
	// Resize an array object.
	package void resize(ref Allocator alloc, MDArray* a, uword newSize)
	{
		if(newSize == a.slice.length)
			return;
		else if(newSize < a.slice.length)
			a.slice = a.data.toArray()[0 .. newSize];
		else
		{
			if(!a.isSlice && newSize <= a.data.length)
				a.slice = a.data.toArray()[0 .. newSize];
			else
			{
				a.data = allocData!(true)(alloc, newSize);

				auto d = a.data.toArray()[0 .. newSize];
				d[0 .. a.slice.length] = a.slice[];
				d[a.slice.length .. $] = MDValue.init;
				a.slice = d;
				
				// We reallocated so this array is not a slice, even if it used to be.
				a.isSlice = false;
			}
		}
	}
	
	// Slice an array object to create a new array object that references the source's data.
	package MDArray* slice(ref Allocator alloc, MDArray* a, uword lo, uword hi)
	{
		auto n = alloc.allocate!(MDArray);
		n.data = a.data;
		n.slice = a.slice[lo .. hi];
		n.isSlice = true;
		return n;
	}

	// Assign an entire other array into a slice of the destination array.  Handles overlapping copies as well.
	package void sliceAssign(MDArray* a, uword lo, uword hi, MDArray* other)
	{
		auto dest = a.slice[lo .. hi];
		auto src = other.slice;

		assert(dest.length == src.length);

		auto len = dest.length * MDValue.sizeof;

		if((dest.ptr + len) <= src.ptr || (src.ptr + len) <= dest.ptr)
			memcpy(dest.ptr, src.ptr, len);
		else
			memmove(dest.ptr, src.ptr, len);
	}

	// Sets a block of values (only called by the SetArray instruction in the interpreter).
	package void setBlock(ref Allocator alloc, MDArray* a, uword block, MDValue[] data)
	{
		auto start = block * Instruction.arraySetFields;
		auto end = start + data.length;
		
		// Since Op.SetArray can use a variadic number of values, the number
		// of elements actually added to the array in the array constructor
		// may exceed the size with which the array was created.  So it should be
		// resized.
		if(end > a.slice.length)
			array.resize(alloc, a, end);
			
		a.slice[start .. end] = data[];
	}
	
	// Returns `true` if one of the values in the array is identical to ('is') the given value.
	package bool contains(MDArray* a, ref MDValue v)
	{
		foreach(ref val; a.slice)
			if(val.opEquals(v))
				return true;
				
		return false;
	}
	
	// Returns a new array that is the concatenation of the two source arrays.
	package MDArray* cat(ref Allocator alloc, MDArray* a, MDArray* b)
	{
		auto ret = array.create(alloc, a.slice.length + b.slice.length);
		ret.slice[0 .. a.slice.length] = a.slice[];
		ret.slice[a.slice.length .. $] = b.slice[];
		return ret;
	}

	// Returns a new array that is the concatenation of the source array and value.
	package MDArray* cat(ref Allocator alloc, MDArray* a, MDValue* v)
	{
		auto ret = array.create(alloc, a.slice.length + 1);
		ret.slice[0 .. $ - 1] = a.slice[];
		ret.slice[$ - 1] = *v;
		return ret;
	}

	// Append array b to the end of array a.
	package void append(ref Allocator alloc, MDArray* a, MDArray* b)
	{
		auto oldLen = a.slice.length;
		array.resize(alloc, a, a.slice.length + b.slice.length);
		a.slice[oldLen .. $] = b.slice[];
	}

	// Append the value v to the end of array a.
	package void append(ref Allocator alloc, MDArray* a, MDValue* v)
	{
		array.resize(alloc, a, a.slice.length + 1);
		a.slice[$ - 1] = *v;
	}
	
	// ================================================================================================================================================
	// Private
	// ================================================================================================================================================

	// Allocate an MDArrayData object that will have at least 'size' elements allocated.
	// overallocate only controls whether over-allocation will be done for large (> 1 page)
	// arrays.
	private MDArrayData* allocData(bool overallocate)(ref Allocator alloc, uword size)
	{
		const BigArraySize = overallocate ? "size + (size / 10)" : "size";
		uword realSize = void;

		if(size <= ElemsInPage)
		{
			realSize = largerPow2(size);

			if(realSize > LargestPow2)
				realSize = mixin(BigArraySize);
		}
		else
			realSize = mixin(BigArraySize);

		auto ret = alloc.allocate!(MDArrayData)(DataSize(realSize));
		ret.length = realSize;
		
		return ret;
	}

	// Figure out the size of an MDArrayData object given that it has 'length' items.
	private uword DataSize(uword length)
	{
		return MDArrayData.sizeof + (MDValue.sizeof * length);
	}
	
	// Returns closest power of 2 that is >= n.  The 'ct' template parameter should
	// be true if you want to evaluate at compile time; at runtime it uses a faster
	// bitwise intrinsic function.
	private uword largerPow2(bool ct = false)(uword n)
	{
		static if(ct)
		{
			if(n == 0 || n == 1)
				return n;
			else if(!(n & (n - 1)))
				return n;
		
			uword ret = 1;

			while(n)
			{
				n >>>= 1;
				ret <<= 1;
			}
		
			return ret;
		}
		else
		{
			if(n == 0)
				return 0;

			return 1 << (bsr(n) + 1);
		}
	}
	
	// The size of a memory page.  I'm just guessing that most OSes use 4k pages.
	// Please change this as necessary.
	private const uword PageSize = 4096;
	
	// How many elements can fit within an array data object that's only one page.
	private const uword ElemsInPage = (PageSize - MDArrayData.sizeof) / MDValue.sizeof;
	
	// The largest power of 2 that's < ElemsInPage.
	private const uword LargestPow2 = largerPow2!(true)(ElemsInPage) >> 1;
}