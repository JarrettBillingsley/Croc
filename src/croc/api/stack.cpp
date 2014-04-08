
#include <string.h>

#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** Gets the size of the stack. This is how many slots there are from the bottom of the current function's stack
	frame to the top of the stack. Valid stack indices range from 0 (the 'this' parameter) to the stack size minus one.
	Valid negative indices range from -1 to -stack size. */
	uword_t croc_getStackSize(CrocThread* t_)
	{
		auto t = Thread::from(t_);

		assert(t->stackIndex > t->stackBase);
		return t->stackIndex - t->stackBase;
	}

	/** Sets the size of the current function's stack. The size must always be at least 1 (you can't get rid of the
	'this' parameter). If you expand the stack, new slots will be filled with \c null; if you shrink it, values at the
	top will be removed. */
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

	/** Converts a given stack index to an absolute index. For positive indices, this returns the index unchanged. For
	negative indices, this returns the equivalent positive index.

	This is useful when you write your own functions which take stack indices as parameters and then do stack
	manipulation. In these cases, if a negative stack index is passed to your function, pushing and popping values would
	change the meaning of the index, so it's best to turn it into an absolute index upon entry to the function. */
	word_t croc_absIndex(CrocThread* t, word_t idx)
	{
		return cast(word_t)fakeToRel(Thread::from(t), idx);
	}

	/** \returns a nonzero value if the given index is valid (either positive or negative), and 0 if not. */
	int croc_isValidIndex(CrocThread* t, word_t idx)
	{
		if(idx < 0)
			return idx >= -cast(word_t)croc_getStackSize(t);
		else
			return idx < cast(word_t)croc_getStackSize(t);
	}

	/** Pushes a copy of the value at \c slot on top of the stack. */
	word_t croc_dup(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		return push(t, *getValue(t, slot));
	}

	/** Swaps the values held in stack slots \c first and \c second. */
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

	/** Copies the value from the stack slot \c src into the stack slot \c dest, overwriting whatever value was in
	it. \c dest cannot be 0. */
	void croc_copy(CrocThread* t_, word_t src, word_t dest)
	{
		auto t = Thread::from(t_);
		auto s = fakeToAbs(t, src);
		auto d = fakeToAbs(t, dest);

		if(d == t->stackBase)
			croc_eh_throwStd(t_, "ApiError", "%s - Cannot use 'this' as the destination", __FUNCTION__);

		if(s == d)
			return;

		t->stack[d] = t->stack[s];
	}

	/** Pops the top value off the stack, and replaces the stack slot \c dest with the value that was popped. \c dest
	cannot be 0. */
	void croc_replace(CrocThread* t_, word_t dest)
	{
		auto t = Thread::from(t_);
		auto d = fakeToAbs(t, dest);

		croc_eh_throwStd(t_, "ApiError", "%s - Cannot use 'this' as the destination", __FUNCTION__);

		if(d != t->stackIndex - 1)
			t->stack[d] = t->stack[t->stackIndex - 1];

		croc_popTop(t_);
	}

	/** Pops the top value off the stack, and inserts it before the value at \c slot, sliding the values from \c slot
	up. \c slot cannot be 0. */
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

	/** Places the value on top of the stack into \c slot and pops all the values above that slot, making \c slot the
	new top of the stack. This is like doing an insert followed by a pop, but does so more efficiently. \c slot cannot
	be 0. */
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

	/** Removes the stack slot \c slot, sliding the values above it down. \c slot cannot be 0. */
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

	/** Removes the stack slot \c slot, slides the values above it down, and pushes the removed slot on top of the
	stack. \c slot cannot be 0. */
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

	/** Sort of a generic version of \ref croc_insert, this "rotates" the top \c numSlot stack slots by \c dist.

	To illustrate, suppose the stack looks like:

	\verbatim
	1 2 3 4 5 6
	\endverbatim

	If you perform <tt>croc_rotate(t, 5, 3)</tt>, the top 5 slots will be rotated by 3. This means the top 3 slots will
	exchange positions with the other two slots, giving:

	\verbatim
	1 4 5 6 2 3
	\endverbatim

	If the \c dist parameter is 1, it works exactly like \ref croc_insert, and if it's <tt>numSlots - 1</tt>, it works
	exactly like \ref croc_moveToTop.

	You cannot rotate slot 0.

	Rotating 0 or 1 slots is valid and does nothing.*/
	void croc_rotate(CrocThread* t_, uword_t numSlots, uword_t dist)
	{
		auto t = Thread::from(t_);

		if(numSlots > (croc_getStackSize(t_) - 1))
			croc_eh_throwStd(t_, "ApiError",
				"%s - Trying to rotate %" CROC_SIZE_T_FORMAT " values, but only have %" CROC_SIZE_T_FORMAT,
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

	/** Rotates all stack slots except slot 0. */
	void croc_rotateAll(CrocThread* t, uword_t dist)
	{
		croc_rotate(t, croc_getStackSize(t) - 1, dist);
	}

	/** Pops 1 or more slots off the top of the stack, moving the top of the stack down. You cannot pop 0 slots, and you
	cannot pop slot 0. */
	void croc_pop(CrocThread* t_, uword_t n)
	{
		auto t = Thread::from(t_);

		if(n == 0)
			croc_eh_throwStd(t_, "ApiError", "%s - Trying to pop zero items", __FUNCTION__);

		if(n > (t->stackIndex - (t->stackBase + 1)))
			croc_eh_throwStd(t_, "ApiError", "%s - Stack underflow", __FUNCTION__);

		t->stackIndex -= n;
	}

	/** Moves values from one thread to another. Both threads must belong to the same VM or an error will be thrown in
	the source thread. The top \c num values are popped off the source thread's stack and pushed onto the destination
	thread's stack in the same order as they originally appeared. */
	void croc_transferVals(CrocThread* src, CrocThread* dest, uword_t num)
	{
		auto t = Thread::from(src);
		auto d = Thread::from(dest);

		if(t->vm != d->vm)
			croc_eh_throwStd(src, "ApiError", "transferVals - Source and destination threads belong to different VMs");

		if(num == 0 || d == t)
			return;

		API_CHECK_NUM_PARAMS(num);
		checkStack(d, d->stackIndex + num);

		auto vals = t->stack.slice(t->stackIndex - num, t->stackIndex);
		d->stack.slicea(d->stackIndex, d->stackIndex + num, vals);
		d->stackIndex += num;
		t->stackIndex -= num;
	}
}