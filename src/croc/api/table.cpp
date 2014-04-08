
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** Creates a new empty table and pushes it onto the stack.

	\param size is available as a hint to the allocator to preallocate this many slots in the table. Use this if you
	know in advance how many things you'll be adding, or if you'll be adding a ton.

	\returns the stack index of the pushed value. */
	word_t croc_table_new(CrocThread* t_, uword_t size)
	{
		auto t = Thread::from(t_);
		croc_gc_maybeCollect(t_);
		return push(t, Value::from(Table::create(t->vm->mem, size)));
	}

	/** Removes all key-value pairs from the table at slot \c idx. */
	void croc_table_clear(CrocThread* t_, word_t tab)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(tabObj, tab, Table, "tab");
		tabObj->clear(t->vm->mem);
	}
}