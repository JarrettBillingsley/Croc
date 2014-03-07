
#include "croc/api.h"
#include "croc/types/base.hpp"

namespace croc
{
extern "C"
{
	void* croc_mem_alloc(CrocThread* t_, uword_t size)
	{
		auto t = Thread::from(t_);
		return DArray<char>::alloc(t->vm->mem, size).ptr;
	}

	void croc_mem_resize(CrocThread* t_, void** mem, uword_t* memSize, uword_t newSize)
	{
		auto t = Thread::from(t_);
		auto arr = DArray<char>::n(cast(char*)*mem, *memSize);
		arr.resize(t->vm->mem, newSize);
		*mem = arr.ptr;
		*memSize = arr.length;
	}

	void* croc_mem_dup(CrocThread* t_, void* mem, uword_t memSize)
	{
		auto t = Thread::from(t_);
		auto arr = DArray<char>::n(cast(char*)mem, memSize);
		return arr.dup(t->vm->mem).ptr;
	}

	void croc_mem_free(CrocThread* t_, void** mem, uword_t* memSize)
	{
		auto t = Thread::from(t_);
		auto arr = DArray<char>::n(cast(char*)*mem, *memSize);
		arr.free(t->vm->mem);
		*mem = nullptr;
		*memSize = 0;
	}
}
}