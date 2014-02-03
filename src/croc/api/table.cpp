
#include "croc/api.h"
#include "croc/internal/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

namespace croc
{
extern "C"
{
	word_t croc_table_new(CrocThread* t_, uword_t size)
	{
		auto t = Thread::from(t_);
		croc_gc_maybeCollect(t_);
		return push(t, Value::from(Table::create(t->vm->mem, size)));
	}

	void croc_table_clear(CrocThread* t_, word_t tab)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(tabObj, tab, Table, "tab");
		tabObj->clear(t->vm->mem);
	}
}
}