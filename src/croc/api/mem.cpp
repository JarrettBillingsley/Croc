
#include "croc/api.h"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** Allocates a block of memory through the Croc memory allocator, using the allocator function that the thread's VM
	was created with.

	<b>This is not garbage-collected; you are entirely responsible for managing this memory.</b> It will, however, be
	tracked for memory leaks if the library was compiled with the CROC_LEAK_DETECTOR option.

	\param size is the number of bytes to allocate.
	\returns a pointer to the allocated memory. */
	void* croc_mem_alloc(CrocThread* t_, uword_t size)
	{
		auto t = Thread::from(t_);
		return DArray<uint8_t>::alloc(t->vm->mem, size).ptr;
	}

	/** Resizes a block of memory that was allocated with \ref croc_mem_alloc.

	\param[in,out] mem is the address of the pointer to the block to resize. This pointer may change as a result of
		resizing the block.
	\param[in,out] memSize is the address of the existing size of the memory block. It will be changed to \c newSize.
	\param newSize is the new size of the memory block. */
	void croc_mem_resize(CrocThread* t_, void** mem, uword_t* memSize, uword_t newSize)
	{
		auto t = Thread::from(t_);
		auto arr = DArray<uint8_t>::n(cast(uint8_t*)*mem, *memSize);
		arr.resize(t->vm->mem, newSize);
		*mem = arr.ptr;
		*memSize = arr.length;
	}

	/** Duplicates a block of memory that was allocated with \ref croc_mem_alloc. The new memory block is the same size
	and contains the same data. */
	void* croc_mem_dup(CrocThread* t_, void* mem, uword_t memSize)
	{
		auto t = Thread::from(t_);
		auto arr = DArray<uint8_t>::n(cast(uint8_t*)mem, memSize);
		return arr.dup(t->vm->mem).ptr;
	}

	/** Frees a block of memory that was allocated with \ref croc_mem_alloc. You must free every block that you
	allocated! */
	void croc_mem_free(CrocThread* t_, void** mem, uword_t* memSize)
	{
		auto t = Thread::from(t_);
		auto arr = DArray<uint8_t>::n(cast(uint8_t*)*mem, *memSize);
		arr.free(t->vm->mem);
		*mem = nullptr;
		*memSize = 0;
	}
}