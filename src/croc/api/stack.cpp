
#include <string.h>

#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
extern "C"
{
	uword_t croc_getStackSize(CrocThread* t_)
	{
		auto t = Thread::from(t_);

		assert(t->stackIndex > t->stackBase);
		return t->stackIndex - t->stackBase;
	}

	void croc_setStackSize(CrocThread* t_, uword_t newSize)
	{
		if(newSize == 0)
			croc_eh_throwStd(t_, "ApiError", "%s - newSize must be nonzero", __FUNCTION__);

		auto curSize = croc_getStackSize(t_);

		if(newSize != curSize)
		{
			auto t = Thread::from(t_);

			t->stackIndex = t->stackBase + newSize;

			if(newSize > curSize)
			{
				checkStack(t, t->stackIndex);
				t->stack.slice(t->stackBase + curSize, t->stackIndex).fill(Value::nullValue);
			}
		}
	}

	word_t croc_absIndex(CrocThread* t, word_t idx)
	{
		return cast(word_t)fakeToRel(Thread::from(t), idx);
	}

	int croc_isValidIndex(CrocThread* t, word_t idx)
	{
		if(idx < 0)
			return idx >= -cast(word_t)croc_getStackSize(t);
		else
			return idx < cast(word_t)croc_getStackSize(t);
	}

	word_t croc_dup(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		return push(t, *getValue(t, slot));
	}

	void croc_swap(CrocThread* t_, word_t first, word_t second)
	{
		auto t = Thread::from(t_);
		auto f = fakeToAbs(t, first);
		auto s = fakeToAbs(t, second);

		if(f == s)
			return;

		auto tmp = t->stack[f];
		t->stack[f] = t->stack[s];
		t->stack[s] = tmp;
	}

	void croc_insert(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		auto s = fakeToAbs(t, slot);

		if(s == t->stackBase)
			croc_eh_throwStd(t_, "ApiError", "%s - Cannot use 'this' as the destination", __FUNCTION__);

		if(s == t->stackIndex - 1)
			return;

		auto tmp = t->stack[t->stackIndex - 1];
		memmove(&t->stack[s + 1], &t->stack[s], (t->stackIndex - s - 1) * sizeof(Value));
		t->stack[s] = tmp;
	}

	void croc_insertAndPop(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		auto s = fakeToAbs(t, slot);

		if(s == t->stackBase)
			croc_eh_throwStd(t_, "ApiError", "%s - Cannot use 'this' as the destination", __FUNCTION__);

		if(s == t->stackIndex - 1)
			return;

		t->stack[s] = t->stack[t->stackIndex - 1];
		t->stackIndex = s + 1;
	}

	void croc_remove(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		auto s = fakeToAbs(t, slot);

		if(s == t->stackBase)
			croc_eh_throwStd(t_, "ApiError", "%s - Cannot remove 'this'", __FUNCTION__);

		if(s != t->stackIndex - 1)
			memmove(&t->stack[s], &t->stack[s + 1], (t->stackIndex - s - 1) * sizeof(Value));

		croc_pop(t_, 1);
	}

	void croc_moveToTop(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		auto s = fakeToAbs(t, slot);

		if(s == t->stackBase)
			croc_eh_throwStd(t_, "ApiError", "%s - Cannot move 'this' to the top of the stack", __FUNCTION__);

		if(s == t->stackIndex - 1)
			return;

		auto tmp = t->stack[s];
		memmove(&t->stack[s], &t->stack[s + 1], (t->stackIndex - s - 1) * sizeof(Value));
		t->stack[t->stackIndex - 1] = tmp;
	}

	void croc_rotate(CrocThread* t_, uword_t numSlots, uword_t dist)
	{
		auto t = Thread::from(t_);

		if(numSlots > (croc_getStackSize(t_) - 1))
			croc_eh_throwStd(t_, "ApiError", "%s - Trying to rotate more values (%u) than can be rotated (%u)",
				__FUNCTION__, numSlots, croc_getStackSize(t_) - 1);

		if(numSlots == 0)
			return;

		if(dist >= numSlots)
			dist %= numSlots;

		if(dist == 0)
			return;
		else if(dist == 1)
			return croc_insert(t_, -numSlots);
		else if(dist == numSlots - 1)
			return croc_moveToTop(t_, -numSlots);

		auto slots = t->stack.slice(t->stackIndex - numSlots, t->stackIndex);

		if(dist <= 8)
		{
			Value temp_[8];
			auto temp = DArray<Value>::n(temp_, 8);
			temp.slicea(0, dist, slots.slice(slots.length - dist, slots.length));
			auto numOthers = numSlots - dist;
			memmove(&slots[slots.length - numOthers], &slots[0], numOthers * sizeof(Value));
			slots.slicea(0, dist, temp.slice(0, dist));
		}
		else
		{
			dist = numSlots - dist;
			uword c = 0;

			for(uword v = 0; c < slots.length; v++)
			{
				auto i = v;
				auto j = v + dist;
				auto tmp = slots[v];
				c++;

				while(j != v)
				{
					slots[i] = slots[j];
					i = j;
					j += dist;

					if(j >= slots.length)
						j -= slots.length;

					c++;
				}

				slots[i] = tmp;
			}
		}
	}

	void croc_rotateAll(CrocThread* t, uword_t dist)
	{
		croc_rotate(t, croc_getStackSize(t) - 1, dist);
	}

	void croc_pop(CrocThread* t_, uword_t n)
	{
		auto t = Thread::from(t_);

		if(n == 0)
			croc_eh_throwStd(t_, "ApiError", "%s - Trying to pop zero items", __FUNCTION__);

		if(n > (t->stackIndex - (t->stackBase + 1)))
			croc_eh_throwStd(t_, "ApiError", "%s - Stack underflow", __FUNCTION__);

		t->stackIndex -= n;
	}

	void croc_transferVals(CrocThread* src_, CrocThread* dest_, uword_t num)
	{
		auto t = Thread::from(src_);
		auto dest = Thread::from(dest_);

		if(t->vm != dest->vm)
			croc_eh_throwStd(src_, "ApiError", "transferVals - Source and destination threads belong to different VMs");

		if(num == 0 || dest == t)
			return;

		API_CHECK_NUM_PARAMS(num);
		checkStack(dest, dest->stackIndex + num);

		dest->stack.slicea(dest->stackIndex, dest->stackIndex + num, t->stack.slice(t->stackIndex - num, t->stackIndex));
		dest->stackIndex += num;
		t->stackIndex -= num;
	}
} // extern "C"
}