
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

namespace croc
{
extern "C"
{
	word_t croc_weakref_push(CrocThread* t_, word_t idx)
	{
		auto t = Thread::from(t_);
		return push(t, Weakref::makeref(t->vm, *getValue(t, idx)));
	}

	word_t croc_weakref_deref(CrocThread* t, word_t idx)
	{
		switch(croc_type(t, idx))
		{
			case CrocType_Null:
			case CrocType_Bool:
			case CrocType_Int:
			case CrocType_Float:
			case CrocType_String:
			case CrocType_Nativeobj:
			case CrocType_Upval:
				return croc_dup(t, idx);

			case CrocType_Weakref:
				if(auto o = getValue(Thread::from(t), idx)->mWeakref->obj)
					return push(Thread::from(t), Value::from(o));
				else
					return croc_pushNull(t);

			default:
				// TODO:ex
				assert(false);
				// croc_pushTypeString(t, idx);
				// croc_eh_throwStd(t, "TypeError", __FUNCTION__ ~ " - idx must be a weakref or non-weakref-able type, not a '{}'", getString(t, -1));
		}
	}
}
}