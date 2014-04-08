
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** Creates a new array object and pushes it onto the stack.

	\param len is how long the new array should be. It will be filled with \c null.
	\returns the stack index of the pushed value. */
	word_t croc_array_new(CrocThread* t_, uword_t len)
	{
		auto t = Thread::from(t_);
		croc_gc_maybeCollect(t_);
		return push(t, Value::from(Array::create(t->vm->mem, len)));
	}

	/** Creates a new array object using values on top of the stack to fill it. This pops the values, and pushes the new
	array.

	\param len is how long the array will be. There should be this many values sitting on top of the stack.
	\returns the stack index of the pushed value. */
	word_t croc_array_newFromStack(CrocThread* t_, uword_t len)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(len);
		croc_gc_maybeCollect(t_);
		auto a = Array::create(t->vm->mem, len);
		a->sliceAssign(t->vm->mem, 0, len, t->stack.slice(t->stackIndex - len, t->stackIndex));
		croc_pop(t_, len);
		return push(t, Value::from(a));
	}

	/** Fills every slot of the array at slot \c arr with the value on top of the stack, and then pops that value. */
	void croc_array_fill(CrocThread* t_, word_t arr)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(a, arr, Array, "arr");
		a->fill(t->vm->mem, t->stack[t->stackIndex - 1]);
		croc_popTop(t_);
	}
}