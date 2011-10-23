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

import croc.base_deque;

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

alias size_t uword;

enum GCFlags : uint
{
	Unlogged =    0b0_00000001,
	InRC =        0b0_00000010,

	Black =       0b0_00000000,
	Grey =        0b0_00000100,
	White =       0b0_00001000,
	Purple =      0b0_00001100,
	Green =       0b0_00010000,
	ColorMask =   0b0_00011100,

	CycleLogged = 0b0_00100000,

	Finalizable = 0b0_01000000,
	Finalized =   0b0_10000000,

	Forwarded =   0b1_00000000,
}

template GCObjectMembers()
{
	align(1)
	{
		uint gcflags = 0;
		uint refCount = 1;
		uword memSize;
		GCObject* forwardPointer;
	}
}

struct GCObject
{
	mixin GCObjectMembers;
}

void append(T)(ref T[] arr, Allocator* alloc, T item)
{
	alloc.resizeArray(arr, arr.length + 1);
	arr[$ - 1] = item;
}

align(1) struct Allocator
{
package:
	MemFunc memFunc;
	void* ctx;

	Deque!(GCObject*) modBuffer;
	Deque!(GCObject*) decBuffer;

	size_t totalBytes = 0;

	void* nurseryStart;
	void* nurseryEnd;
	void* nurseryPtr;

	// 0 for enabled, positive for disabled
	uword gcDisabled;
	// TODO: FIX THIIIIIIS
	const uword nurserySizeCutoff = 256;
	const uword nurseryAlignment = 4 - 1;

	debug(CROC_LEAK_DETECTOR)
	{
		pragma(msg, "Compiling Croc with the leak detector enabled.");

		import croc.base_hash;

		struct MemBlock
		{
			size_t len;
			TypeInfo ti;
		}

		Hash!(void*, MemBlock) _nurseryBlocks, _rcBlocks, _rawBlocks;
	}

	// ALLOCATION: most objects are allocated in the nursery. If they're too big, or finalizable, they're allocated directly in the RC space. When this
	// happens, we push them onto the modified buffer and the decrement buffer, and initialize their reference count to 1. This way, when the collection
	// cycle happens, if they're referenced, their reference count will be incremented then decremented (no-op); if they're not referenced, their
	// reference count will be decremented to 0, freeing them. Putting them in the modified buffer is, I guess, to prevent memory leaks..? Couldn't hurt.

	T* allocate(T)(uword size = T.sizeof)
	{
		if(size >= nurserySizeCutoff || gcDisabled > 0)
			return allocateRC!(T)(size);
		else
			return allocateNursery!(T)(size);
	}

	T* allocateFinalizable(T)(uword size = T.sizeof)
	{
		auto ret = allocateRC!(T)(size);
		ret.gcflags |= GCFlags.Finalizable;
		return ret;
	}

	// Returns null to indicate that we need to do a GC cycle.
	private T* allocateNursery(T)(uword size = T.sizeof)
	{
		auto ptr = cast(void*)((cast(uword)nurseryPtr + nurseryAlignment) & ~nurseryAlignment);

		if(nurseryEnd - ptr < size)
		{
			assert(false, "UNIMPLEMENTED");
			return null;
		}

		totalBytes += cast(uword)(ptr + size - nurseryPtr);

		nurseryPtr = ptr + size;

		auto ret = cast(T*)ptr;
		*ret = T.init;
		ret.memSize = size;

		static if(is(typeof(T.ACYCLIC)))
			ret.gcflags |= GCFlags.Green;

		debug(CROC_LEAK_DETECTOR)
			*_nurseryBlocks.insert(*this, ret) = MemBlock(size, typeid(T));
			
		static if(T.stringof == "CrocString")
			assert((ret.gcflags & GCFlags.ColorMask) == GCFlags.Green);

		return ret;
	}

	private T* allocateRC(T)(uword size = T.sizeof)
	{
		auto ret = cast(T*)realloc(null, 0, size);
		(cast(void*)ret)[0 .. T.sizeof] = (cast(void*)&T.init)[0 .. T.sizeof];
		*ret = T.init;
		ret.memSize = size;
		ret.gcflags = GCFlags.InRC; // RC space objects start off logged since we put them on the mod buffer.

		static if(is(typeof(T.ACYCLIC)))
			ret.gcflags |= GCFlags.Green;

		ret.refCount = 1;
		modBuffer.add(*this, cast(GCObject*)ret);
		decBuffer.add(*this, cast(GCObject*)ret);

		debug(CROC_LEAK_DETECTOR)
			*_rcBlocks.insert(*this, ret) = MemBlock(size, typeid(T));
			
		static if(T.stringof == "CrocString")
			assert((ret.gcflags & GCFlags.ColorMask) == GCFlags.Green);

		return ret;
	}

	GCObject* copyToRC(GCObject* obj)
	{
		assert((obj.gcflags & GCFlags.InRC) == 0);
		assert((obj.gcflags & GCFlags.Forwarded) == 0);

		auto ret = realloc(null, 0, obj.memSize);
		ret[0 .. obj.memSize] = (cast(void*)obj)[0 .. obj.memSize];

		debug(CROC_LEAK_DETECTOR)
		{
			auto b = _nurseryBlocks.lookup(obj);
			assert(b !is null);
			*_rcBlocks.insert(*this, ret) = *b;
		}
		
		if(*(cast(uint*)(ret + GCObject.sizeof)) == 5)
			assert(((cast(GCObject*)ret).gcflags & GCFlags.ColorMask) == GCFlags.Green);

		return cast(GCObject*)ret;
	}

	void free(T)(T* o)
	{
		assert(o.gcflags & GCFlags.InRC, "attempting to free an object that isn't in the RC space!");

		debug(CROC_LEAK_DETECTOR)
		{
			if(_rcBlocks.lookup(o) is null)
				throw new Exception("AWFUL: You're trying to free something that wasn't allocated on the Croc RC Heap, or are performing a double free! It's of type " ~ typeid(T).toString());

			_rcBlocks.remove(o);
		}

		realloc(o, o.memSize, 0);
	}

	package T[] allocArray(T)(size_t size)
	{
		if(size == 0)
			return null;

		auto ret = (cast(T*)realloc(null, 0, size * T.sizeof))[0 .. size];

		debug(CROC_LEAK_DETECTOR)
		{
			static if(is(T == Hash!(void*, MemBlock).Node))
				totalBytes -= size * T.sizeof;
			else
				*_rawBlocks.insert(*this, ret.ptr) = MemBlock(size * T.sizeof, typeid(T[]));
		}
	
		static if(!is(T == void))
			ret[] = T.init;
	
		return ret;
	}

	package void resizeArray(T)(ref T[] arr, size_t newLen)
	{
		debug(CROC_LEAK_DETECTOR)
		{
			static if(is(T == Hash!(void*, MemBlock).Node))
				static assert(false, "we can't resize arrays of memblock hash nodes! nonoNONONO-- god--godDAMMIT! YOU BROKE THE RULES!");

			if(arr.length > 0 && _rawBlocks.lookup(arr.ptr) is null)
				throw new Exception("AWFUL: You're trying to resize an array that wasn't allocated on the Croc RC Heap! It's of type " ~ typeid(T[]).toString());
		}

		if(newLen == 0)
		{
			freeArray(arr);
			arr = null;
			return;
		}
		else if(newLen == arr.length)
			return;
	
		auto oldLen = arr.length;
		auto ret = (cast(T*)realloc(arr.ptr, oldLen * T.sizeof, newLen * T.sizeof))[0 .. newLen];
	
		debug(CROC_LEAK_DETECTOR)
		{
			if(arr.ptr is ret.ptr)
				_rawBlocks.lookup(ret.ptr).len = newLen * T.sizeof;
			else
			{
				_rawBlocks.remove(arr.ptr);
				*_rawBlocks.insert(*this, ret.ptr) = MemBlock(newLen * T.sizeof, typeid(T[]));
			}
		}

		arr = ret;
	
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
	
		auto ret = (cast(T*)realloc(null, 0, a.length * T.sizeof))[0 .. a.length];
		ret[] = a[];
	
		debug(CROC_LEAK_DETECTOR)
		{
			static if(is(T == Hash!(void*, MemBlock).Node))
				totalBytes -= ret.length * T.sizeof;
			else
				*_rawBlocks.insert(*this, ret.ptr) = MemBlock(ret.length * T.sizeof, typeid(T[]));
		}
	
		return ret;
	}

	package void freeArray(T)(ref T[] a)
	{
		if(a.length)
		{
			debug(CROC_LEAK_DETECTOR)
			{
				static if(!is(T == Hash!(void*, MemBlock).Node))
					if(_rawBlocks.lookup(a.ptr) is null)
						throw new Exception("AWFUL: You're trying to free an array that wasn't allocated on the Croc RC Heap, or are performing a double free! It's of type " ~ typeid(T[]).toString());
			}
	
			realloc(a.ptr, a.length * T.sizeof, 0);
	
			debug(CROC_LEAK_DETECTOR)
			{
				static if(is(T == Hash!(void*, MemBlock).Node))
					totalBytes += a.length * T.sizeof;
				else
					_rawBlocks.remove(a.ptr);
			}
	
			a = null;
		}
	}
	
	private void* realloc(void* p, size_t oldSize, size_t newSize)
	{
		auto ret = memFunc(ctx, p, oldSize, newSize);
		assert(newSize == 0 || ret !is null, "allocation function should never return null");
		totalBytes += newSize - oldSize;
		return ret;
	}
	
	void resizeNurserySpace(uword newSize)
	{
		assert(nurseryPtr is nurseryStart);

		nurseryStart = realloc(nurseryStart, nurseryEnd - nurseryStart, newSize);
		nurseryEnd = nurseryStart + newSize;
		nurseryPtr = nurseryStart;
	}
	
	void clearNurserySpace()
	{
		nurseryPtr = nurseryStart;

		debug(CROC_NURSERY_STOMP)
			(cast(ubyte*)nurseryStart)[0 .. nurseryEnd - nurseryStart] = 0xCD;
	
		debug(CROC_LEAK_DETECTOR)
			_nurseryBlocks.clear(*this);
	}
	
	void cleanup()
	{
		clearNurserySpace();
		resizeNurserySpace(0);
		modBuffer.clear(*this);
		decBuffer.clear(*this);
	}
}