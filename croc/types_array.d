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
import croc.base_writebarrier;
import croc.base_opcodes;
import croc.types;
import croc.utils;

struct array
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

package:

	// Create a new array object of the given length.
	CrocArray* create(ref Allocator alloc, uword size)
	{
		auto ret = alloc.allocate!(CrocArray)();
		ret.data = alloc.allocArray!(CrocArray.Slot)(size);
		ret.length = size;
		return ret;
	}

	// Free an array object.
	void free(ref Allocator alloc, CrocArray* a)
	{
		alloc.freeArray(a.data);
		alloc.free(a);
	}

	// Resize an array object.
	void resize(ref Allocator alloc, CrocArray* a, uword newSize)
	{
		if(newSize == a.length)
			return;

		auto oldSize = a.length;
		a.length = newSize;

		if(newSize < oldSize)
		{
			mixin(removeRefs!("alloc", "a.data[newSize .. oldSize]"));
			a.data[newSize .. oldSize] = CrocArray.Slot.init;

			if(newSize < (a.data.length >> 1))
				alloc.resizeArray(a.data, largerPow2(newSize));
		}
		else if(newSize > a.data.length)
			alloc.resizeArray(a.data, largerPow2(newSize));
	}

	// Slice an array object to create a new array object with its own data.
	CrocArray* slice(ref Allocator alloc, CrocArray* a, uword lo, uword hi)
	{
		auto n = alloc.allocate!(CrocArray);
		n.length = hi - lo;
		n.data = alloc.dupArray(a.data[lo .. hi]);
		// don't have to write barrier n cause it starts logged
		mixin(addRefs!("n.data[0 .. n.length]"));
		return n;
	}

	// Assign an entire other array into a slice of the destination array. Handles overlapping copies as well.
	void sliceAssign(ref Allocator alloc, CrocArray* a, uword lo, uword hi, CrocArray* other)
	{
		auto dest = a.data[lo .. hi];
		auto src = other.toArray();

		assert(dest.length == src.length);

		auto len = dest.length * CrocArray.Slot.sizeof;

		if(len > 0)
		{
			mixin(removeRefs!("alloc", "dest"));

			if((dest.ptr + len) <= src.ptr || (src.ptr + len) <= dest.ptr)
				memcpy(dest.ptr, src.ptr, len);
			else
				memmove(dest.ptr, src.ptr, len);

			mixin(containerWriteBarrier!("alloc", "a"));
			mixin(addRefs!("dest"));
		}
	}

	void sliceAssign(ref Allocator alloc, CrocArray* a, uword lo, uword hi, CrocValue[] other)
	{
		auto dest = a.data[lo .. hi];
		assert(dest.length == other.length);
		auto len = dest.length * CrocArray.Slot.sizeof;

		if(len > 0)
		{
			mixin(removeRefs!("alloc", "dest"));
			mixin(containerWriteBarrier!("alloc", "a"));

			foreach(i, ref slot; dest)
			{
				slot.value = other[i];
				slot.modified = false;
				mixin(addRef!("slot"));
			}
		}
	}

	// Sets a block of values (only called by the SetArray instruction in the interpreter).
	void setBlock(ref Allocator alloc, CrocArray* a, uword block, CrocValue[] data)
	{
		auto start = block * Instruction.ArraySetFields;
		auto end = start + data.length;

		// Since Op.SetArray can use a variadic number of values, the number
		// of elements actually added to the array in the array constructor
		// may exceed the size with which the array was created. So it should be
		// resized.
		if(end > a.length)
			array.resize(alloc, a, end);

		mixin(containerWriteBarrier!("alloc", "a"));

		foreach(i, ref slot; a.data[start .. end])
		{
			slot.value = data[i];
			mixin(addRef!("slot"));
		}
	}

	// Fills an entire array with a value.
	void fill(ref Allocator alloc, CrocArray* a, CrocValue val)
	{
		if(a.length > 0)
		{
			mixin(removeRefs!("alloc", "a.toArray()"));

			CrocArray.Slot slot = void;
			slot.value = val;

			if(val.isObject())
			{
				mixin(containerWriteBarrier!("alloc", "a"));
				slot.modified = true;
			}
			else
				slot.modified = false;

			a.toArray()[] = slot;
		}
	}

	// Index-assigns an element.
	void idxa(ref Allocator alloc, CrocArray* a, uword idx, CrocValue val)
	{
		auto slot = &a.toArray()[idx];

		if(slot.value != val)
		{
			mixin(removeRef!("alloc", "slot"));
			slot.value = val;

			if(val.isObject())
			{
				mixin(containerWriteBarrier!("alloc", "a"));
				slot.modified = true;
			}
			else
				slot.modified = false;
		}
	}

	// Returns `true` if one of the values in the array is identical to ('is') the given value.
	bool contains(CrocArray* a, ref CrocValue v)
	{
		foreach(ref slot; a.toArray())
			if(slot.value.opEquals(v))
				return true;

		return false;
	}

	// Returns a new array that is the concatenation of the two source arrays.
	CrocArray* cat(ref Allocator alloc, CrocArray* a, CrocArray* b)
	{
		auto ret = array.create(alloc, a.length + b.length);
		ret.data[0 .. a.length] = a.toArray();
		ret.data[a.length .. ret.length] = b.toArray();
		mixin(addRefs!("ret.toArray()"));
		return ret;
	}

	// Returns a new array that is the concatenation of the source array and value.
	CrocArray* cat(ref Allocator alloc, CrocArray* a, CrocValue* v)
	{
		auto ret = array.create(alloc, a.length + 1);
		ret.data[0 .. ret.length - 1] = a.toArray();
		ret.data[ret.length - 1].value = *v;
		mixin(addRefs!("ret.toArray()"));
		return ret;
	}

	// Append the value v to the end of array a.
	void append(ref Allocator alloc, CrocArray* a, CrocValue* v)
	{
		array.resize(alloc, a, a.length + 1);
		array.idxa(alloc, a, a.length - 1, *v);
	}

	// ================================================================================================================================================
	// Private
	// ================================================================================================================================================

private:

	template addRef(char[] slot)
	{
		const char[] addRef = "if(" ~ slot ~ ".value.isObject()) " ~ slot ~ ".modified = true;";
	}

	template removeRef(char[] alloc, char[] slot)
	{
		const char[] removeRef =
		"if(!" ~ slot  ~ ".modified && " ~ slot  ~ ".value.isObject()) " ~ alloc ~ ".decBuffer.add(" ~ alloc ~ ", " ~ slot  ~ ".value.toGCObject());";
	}

	template addRefs(char[] arr)
	{
		const char[] addRefs = "foreach(ref slot; " ~ arr ~ ") " ~ addRef!("slot");
	}

	template removeRefs(char[] alloc, char[] arr)
	{
		const char[] removeRefs = "foreach(ref slot; " ~ arr ~ ") " ~ removeRef!(alloc, "slot");
	}
}
