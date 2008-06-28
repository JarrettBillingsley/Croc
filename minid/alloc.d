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

module minid.alloc;

import tango.stdc.string;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

/**
The type of the memory allocation function that the MiniD library uses to allocate, reallocate, and free memory.
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
	ctx = The context pointer that was associated with the VM upon creation.  This pointer is just passed to the allocation
		function on every call; MiniD doesn't use it.
	p = The pointer that is being operated on.  If this is null, an allocation is being requested.  Otherwise, either a
		reallocation or a deallocation is being requested.
	oldSize = The current size of the block pointed to by p.  If p is null, this will always be 0.
	newSize = The new size of the block pointed to by p.  If p is null, this is the requested size of the new block.
		Otherwise, if this is 0, a deallocation is being requested.  Otherwise, a reallocation is being requested.
	
Returns:
	If a deallocation was requested, should return null.  Otherwise, should return a $(B non-null) pointer.  If memory cannot
	be allocated, the memory allocation function should throw an exception, not return null.
*/
public alias void* function(void* ctx, void* p, size_t oldSize, size_t newSize) MemFunc;

// ================================================================================================================================================
// package
// ================================================================================================================================================

template GCMixin()
{
	package GCObject* next;
	package uint marked; // uint for future possibilities (more flags than just 'marked')
}

align(1) struct GCObject
{
	mixin GCMixin;
}

align(1) struct Allocator
{
	package MemFunc memFunc;
	package void* ctx;

	package GCObject* gcHead = null;

	// TODO: make the GC work on thresholds of bytes, remove object counts
	package int gcCount = 0;
	package int gcLimit = 128;
	package bool markVal = true;
	package size_t totalBytes = 0;

	debug(LEAK_DETECTOR)
	{
		struct MemBlock
		{
			size_t len;
			TypeInfo ti;
		}

		MemBlock[void*] _memBlocks;
	}

	package T* allocate(T)(size_t size = T.sizeof)
	{
		auto ret = cast(T*)realloc!(T)(null, 0, size);
		*ret = T.init;

		ret.marked = !markVal;
		addToList(cast(GCObject*)ret);

		return ret;
	}

	package T* duplicate(T)(T* o, size_t size = T.sizeof)
	{
		auto ret = cast(T*)realloc!(T)(null, 0, size);
		memcpy(ret, o, size);

		addToList(cast(GCObject*)ret);

		return ret;
	}

	package void free(T)(T* o, size_t size = T.sizeof)
	{
		static if(is(T == GCObject))
		{
			pragma(msg, "free must be called on a type other than GCObject*");
			OKASFPOKASMVMVmavpmasvmo();
		}

		gcCount--;
		realloc!(T)(o, size, 0);
	}

	package T[] allocArray(T)(size_t size)
	{
		if(size == 0)
			return null;

		auto ret = (cast(T*)realloc!(T[])(null, 0, size * T.sizeof))[0 .. size];
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

		if(newLen > oldLen)
			arr[oldLen .. newLen] = T.init;
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
			void* realloc(void* p, size_t oldSize, size_t newSize)
			{
				auto ret = reallocImpl(p, oldSize, newSize);

				if(newSize == 0)
					_memBlocks.remove(p);
				else if(oldSize == 0)
					_memBlocks[ret] = MemBlock(newSize, typeid(T));
				else
				{
					if(p is ret)
						_memBlocks[ret].len = newSize;
					else
					{
						_memBlocks.remove(p);
						_memBlocks[ret] = MemBlock(newSize, typeid(T));
					}
				}
				
				return ret;
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
	
	private void addToList(GCObject* o)
	{
		o.next = gcHead;
		gcHead = o;
		gcCount++;
	}
}