/******************************************************************************
This contains the memory allocator interface for Croc. Most of this module is
for internal use only, but it does define the type of the memory allocation
function which you can pass to croc.api.openVM.

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

module croc.base_alloc;

import tango.stdc.string;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

/**
The type of the memory allocation function that the Croc library uses to allocate, reallocate, and free memory.
You pass a memory allocation function when you create a VM, and all allocations by the VM go through that function.

This type is defined as a void* function(void* ctx, void* p, size_t oldSize, size_t newSize).

The memory function works as follows:

If a new block is being requested, it will be called with a p of null, an oldSize of 0, and a newSize of the size of
the requested block.

If an existing block is to be resized, it will be called with p being the pointer to the block, an oldSize of the current
block size, and a newSize of the new expected size of the block.

If an existing block is to be deallocated, it will be called with p being the pointer to the block, an oldSize of the
current block size, and a newSize of 0.

Params:
	ctx = The context pointer that was associated with the VM upon creation. This pointer is just passed to the allocation
		function on every call; Croc doesn't use it.
	p = The pointer that is being operated on. If this is null, an allocation is being requested. Otherwise, either a
		reallocation or a deallocation is being requested.
	oldSize = The current size of the block pointed to by p. If p is null, this will always be 0.
	newSize = The new size of the block pointed to by p. If p is null, this is the requested size of the new block.
		Otherwise, if this is 0, a deallocation is being requested. Otherwise, a reallocation is being requested.
	
Returns:
	If a deallocation was requested, should return null. Otherwise, should return a $(B non-null) pointer. If memory cannot
	be allocated, the memory allocation function should throw an exception, not return null.
*/
alias void* function(void* ctx, void* p, size_t oldSize, size_t newSize) MemFunc;

// ================================================================================================================================================
// package
// ================================================================================================================================================

package:

enum GCBits
{
	Marked = 0x1,
	Finalized = 0x8
}

template GCMixin()
{
	package GCObject* next;
	package uint flags;
}

align(1) struct GCObject
{
	mixin GCMixin;
}

void append(T)(ref T[] arr, Allocator* alloc, T item)
{
	alloc.resizeArray(arr, arr.length + 1);
	arr[$ - 1] = item;
}

align(1) struct Allocator
{
	package MemFunc memFunc;
	package void* ctx;

	package GCObject* gcHead = null;
	package GCObject* finalizable = null;

	// Init to max so that no collection cycles happen until the VM is fully initialized
	package size_t gcLimit = size_t.max;
	package uint markVal = GCBits.Marked;
	package size_t totalBytes = 0;

	debug(LEAK_DETECTOR)
	{
		pragma(msg, "Compiling Croc with the leak detector enabled.");

		// Trick dimple into thinking there's no import (which there isn't, really).
		mixin("import croc.base_hash;");

		struct MemBlock
		{
			size_t len;
			TypeInfo ti;
		}

		Hash!(void*, MemBlock) _memBlocks;
	}

	package T* allocate(T)(size_t size = T.sizeof)
	{
		auto ret = cast(T*)realloc!(T)(null, 0, size);
		*ret = T.init;

		ret.flags |= !markVal;
		(cast(GCObject*)ret).next = gcHead;
		gcHead = cast(GCObject*)ret;

		return ret;
	}

	package T* duplicate(T)(T* o, size_t size = T.sizeof)
	{
		auto ret = cast(T*)realloc!(T)(null, 0, size);
		memcpy(ret, o, size);

		(cast(GCObject*)ret).next = gcHead;
		gcHead = cast(GCObject*)ret;

		return ret;
	}

	package void free(T)(T* o, size_t size = T.sizeof)
	{
		static if(is(T == GCObject))
		{
			pragma(msg, "free must be called on a type other than GCObject*");
			OKASFPOKASMVMVmavpmasvmo();
		}

		realloc!(T)(o, size, 0);
	}

	package T[] allocArray(T)(size_t size)
	{
		if(size == 0)
			return null;

		auto ret = (cast(T*)realloc!(T[])(null, 0, size * T.sizeof))[0 .. size];
		
		static if(!is(T == void))
			ret[] = T.init;

		return ret;
	}

	package void resizeArray(T)(ref T[] arr, size_t newLen)
	{
		if(newLen == 0)
		{
			freeArray(arr);
			arr = null;
			return;
		}
		else if(newLen == arr.length)
			return;

		auto oldLen = arr.length;
		arr = (cast(T*)realloc!(T[])(arr.ptr, oldLen * T.sizeof, newLen * T.sizeof))[0 .. newLen];

		static if(!is(T == void))
		{
			if(newLen > oldLen)
				arr[oldLen .. newLen] = T.init;
		}
	}

	package T[] dupArray(T)(T[] a)
	{
		if(a.length == 0)
			return null;

		auto ret = (cast(T*)realloc!(T[])(null, 0, a.length * T.sizeof))[0 .. a.length];
		ret[] = a[];
		return ret;
	}

	package void freeArray(T)(ref T[] a)
	{
		if(a.length)
		{
			realloc!(T[])(a.ptr, a.length * T.sizeof, 0);
			a = null;
		}
	}

	template realloc(T)
	{
		debug(LEAK_DETECTOR)
		{
			// Do this so that the leak detector does not cause infinite recursion and also so it doesn't mess with the totalBytes
			static if(is(T == Hash!(void*, MemBlock).Node[]))
			{
				void* realloc(void* p, size_t oldSize, size_t newSize)
				{
					auto ret = memFunc(ctx, p, oldSize, newSize);
					assert(newSize == 0 || ret !is null, "allocation function should never return null");
					return ret;
				}
			}
			else
			{
				void* realloc(void* p, size_t oldSize, size_t newSize)
				{
					if(oldSize > 0 && _memBlocks.lookup(p) is null)
						throw new Exception("AWFUL: You're trying to free something that wasn't allocated on the Croc Heap, or are performing a double free! It's of type " ~ typeid(T).toString());

					auto ret = reallocImpl(p, oldSize, newSize);

					if(newSize == 0)
						_memBlocks.remove(p);
					else if(oldSize == 0)
						*_memBlocks.insert(*this, ret) = MemBlock(newSize, typeid(T));
					else
					{
						if(p is ret)
							_memBlocks.lookup(ret).len = newSize;
						else
						{
							_memBlocks.remove(p);
							*_memBlocks.insert(*this, ret) = MemBlock(newSize, typeid(T));
						}
					}

					return ret;
				}
			}
		}
		else
			alias reallocImpl realloc;
	}

	private void* reallocImpl(void* p, size_t oldSize, size_t newSize)
	{
		auto ret = memFunc(ctx, p, oldSize, newSize);
		assert(newSize == 0 || ret !is null, "allocation function should never return null");
		totalBytes += newSize - oldSize;
		return ret;
	}
}