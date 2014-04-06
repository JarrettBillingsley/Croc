
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	word_t croc_weakref_push(CrocThread* t_, word_t idx)
	{
		auto t = Thread::from(t_);
		return push(t, Weakref::makeref(t->vm, *getValue(t, idx)));
	}

	word_t croc_weakref_deref(CrocThread* t_, word_t idx)
	{
		auto t = Thread::from(t_);

		switch(croc_type(t_, idx))
		{
			case CrocType_Null:
			case CrocType_Bool:
			case CrocType_Int:
			case CrocType_Float:
			case CrocType_String:
			case CrocType_Nativeobj:
			case CrocType_Upval:
				return croc_dup(t_, idx);

			case CrocType_Weakref:
				if(auto o = getValue(t, idx)->mWeakref->obj)
					return push(t, Value::from(o));
				else
					return croc_pushNull(t_);

			default:
				API_PARAM_TYPE_ERROR(idx, "value", "null|bool|int|float|string|nativeobj|weakref");
				assert(false);
				return 0; // dummy
		}
	}
}