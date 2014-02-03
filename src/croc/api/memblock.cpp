
#include "croc/api.h"
#include "croc/internal/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

namespace croc
{
extern "C"
{
	word_t croc_memblock_new(CrocThread* t_, uword_t len)
	{
		auto t = Thread::from(t_);
		croc_gc_maybeCollect(t_);
		return push(t, Value::from(Memblock::create(t->vm->mem, len)));
	}

	word_t croc_memblock_fromNativeArray(CrocThread* t_, void* arr, uword_t arrLen)
	{
		auto t = Thread::from(t_);
		auto ret = croc_memblock_new(t_, arrLen);
		auto data = getMemblock(t, ret)->data;
		data.slicea(DArray<uint8_t>::n(cast(uint8_t*)arr, arrLen));
		return ret;
	}

	word_t croc_memblock_viewNativeArray(CrocThread* t_, void* arr, uword_t arrLen)
	{
		auto t = Thread::from(t_);
		return push(t, Value::from(Memblock::createView(t->vm->mem, DArray<uint8_t>::n(cast(uint8_t*)arr, arrLen))));
	}

	void croc_memblock_reviewNativeArray(CrocThread* t_, word_t slot, void* arr, uword_t arrLen)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(m, slot, Memblock, "slot");
		m->view(t->vm->mem, DArray<uint8_t>::n(cast(uint8_t*)arr, arrLen));
	}

	char* croc_memblock_getData(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(m, slot, Memblock, "slot");
		return cast(char*)m->data.ptr;
	}

	char* croc_memblock_getDatan(CrocThread* t_, word_t slot, uword_t* len)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(m, slot, Memblock, "slot");
		*len = m->data.length;
		return cast(char*)m->data.ptr;
	}
}
}