
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
extern "C"
{
	word_t croc_array_new(CrocThread* t_, uword_t len)
	{
		auto t = Thread::from(t_);
		croc_gc_maybeCollect(t_);
		return push(t, Value::from(Array::create(t->vm->mem, len)));
	}

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

	void croc_array_fill(CrocThread* t_, word_t arr)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(a, arr, Array, "arr");
		a->fill(t->vm->mem, t->stack[t->stackIndex - 1]);
		croc_popTop(t_);
	}
}
}