
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** Creates and pushes a weakref from the value at slot \c idx. If the value is a value type or quasi-value type,
	the value will just be duplicated. Otherwise, a weakref object will be created (if one hasn't been created for that
	object already) and pushed. This mirrors the behavior of the Croc stdlib \c weakref function.

	\returns the stack index of the pushed value. */
	word_t croc_weakref_push(CrocThread* t_, word_t idx)
	{
		auto t = Thread::from(t_);
		return push(t, Weakref::makeref(t->vm, *getValue(t, idx)));
	}

	/** Given a weakref (or a value of any value or quasi-value type) at slot \c idx, pushes the referenced object. If
	the value is a value or quasi-value type, just duplicates the value. Otherwise, it must be a weakref object, and the
	weakref's referent will be pushed (or null if it was collected). This mirrors the behavior of the Croc stdlib \c
	deref function.

	\returns the stack index of the pushed value. */
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