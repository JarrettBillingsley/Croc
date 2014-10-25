
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** Creates and pushes a new memblock object that is \c len bytes long.
	\returns the stack index of the pushed value. */
	word_t croc_memblock_new(CrocThread* t_, uword_t len)
	{
		auto t = Thread::from(t_);
		croc_gc_maybeCollect(t_);
		return push(t, Value::from(Memblock::create(t->vm->mem, len)));
	}

	/** Creates and pushes a new memblock whose data is a \a copy of the given array.

	\param arr is the pointer to the array.
	\param arrLen is the length of the array, in bytes.
	\returns the stack index of the pushed value. */
	word_t croc_memblock_fromNativeArray(CrocThread* t_, const void* arr, uword_t arrLen)
	{
		auto t = Thread::from(t_);
		auto ret = croc_memblock_new(t_, arrLen);
		auto data = getMemblock(t, ret)->data;
		data.slicea(DArray<uint8_t>::n(cast(uint8_t*)arr, arrLen));
		return ret;
	}

	/** Creates and pushes a new memblock object that is a view of the given array. The memblock will not own its data.

	\param arr is the pointer to the array. <b>It is your responsibility to keep this array around as long as the
		memblock which views it exists. </b>
	\param arrLen is the length of the array, in bytes.
	\returns the stack index of the pushed value. */
	word_t croc_memblock_viewNativeArray(CrocThread* t_, void* arr, uword_t arrLen)
	{
		auto t = Thread::from(t_);
		return push(t, Value::from(Memblock::createView(t->vm->mem, DArray<uint8_t>::n(cast(uint8_t*)arr, arrLen))));
	}

	/** Same as \ref croc_memblock_viewNativeArray, except instead of creating a new memblock, it changes an existing
	memblock at \c slot so that its data points to the native array. If the memblock had any data (and owned it), that
	data will be freed.

	\param arr is the pointer to the array. <b>It is your responsibility to keep this array around as long as the
		memblock which views it exists. </b>
	\param arrLen is the length of the array, in bytes.	*/
	void croc_memblock_reviewNativeArray(CrocThread* t_, word_t slot, void* arr, uword_t arrLen)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(m, slot, Memblock, "slot");
		m->view(t->vm->mem, DArray<uint8_t>::n(cast(uint8_t*)arr, arrLen));
	}

	/** Returns a pointer to the data of the memblock in the given \c slot.

	<b>The pointer returned from this may point into Croc's memory (if the memblock owns its data). You are allowed to
	modify the data at this pointer, but don't store it unless you know the memblock won't be collected!</b> */
	char* croc_memblock_getData(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(m, slot, Memblock, "slot");
		return cast(char*)m->data.ptr;
	}

	/** Same as \ref croc_memblock_getData, except it also returns the length of the memblock's data in bytes through
	the \c len parameter.

	<b>The pointer returned from this may point into Croc's memory (if the memblock owns its data). You are allowed to
	modify the data at this pointer, but don't store it unless you know the memblock won't be collected!</b> */
	char* croc_memblock_getDatan(CrocThread* t_, word_t slot, uword_t* len)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(m, slot, Memblock, "slot");
		*len = m->data.length;
		return cast(char*)m->data.ptr;
	}

	/** \returns nonzero if the memblock at the given \c slot owns its data (it is allocated on the Croc heap). If this
	returns 0, it means the memblock is a view of a native array. */
	int croc_memblock_ownData(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(m, slot, Memblock, "slot");
		return m->ownData;
	}
}