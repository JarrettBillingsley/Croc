
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** Create a native reference to an object.

	Native references are a way for native code to keep a reference to a Croc object without having it get collected.
	You create a reference to the object, then use \ref croc_ref_push to get the object associated with that reference.
	When you no longer need to reference the object, use \ref croc_ref_remove to remove it.

	You can create multiple references to the same object. In this case, you must remove all the references separately.
	In this way it works something like a reference counting scheme. As long as at least one native reference to an
	object exists, it will never be collected.

	\param idx is the stack slot of the object to get a reference to. It must be a GC-able type.
	\returns the unique reference value to be passed to the other native reference functions. This is a 64-bit count,
		so you don't have to worry about a reference value that was removed with \ref croc_ref_remove ever being valid
		again (unless you generate millions of references per second for hundreds of thousands of years). */
	crocref_t croc_ref_create(CrocThread* t_, word_t idx)
	{
		auto t = Thread::from(t_);
		auto v = *getValue(t, idx);

		if(!v.isGCObject())
		{
			croc_pushTypeString(t_, idx);
			croc_eh_throwStd(t_, "ApiError", "%s - Can only get references to reference types, not '%s'",
				__FUNCTION__,
				croc_getString(t_, -1));
		}

		auto ret = t->vm->currentRef++;
		*t->vm->refTab.insert(t->vm->mem, ret) = v.mGCObj;
		return ret;
	}

	/** Given a reference value that was returned from \ref croc_ref_create, pushes the object associated with that
	reference onto the stack. */
	word_t croc_ref_push(CrocThread* t_, crocref_t r)
	{
		auto t = Thread::from(t_);

		auto v = t->vm->refTab.lookup(r);

		if(v == nullptr)
			croc_eh_throwStd(t_, "ApiError", "%s - Reference '%" CROC_UINTEGER_FORMAT "' does not exist",
				__FUNCTION__, r);

		return push(t, Value::from(*v));
	}

	/** Given a reference value that was returned from \ref croc_ref_create, removes the reference to the object. The
	reference value will then be invalid for the rest of the life of the program. */
	void croc_ref_remove(CrocThread* t_, crocref_t r)
	{
		auto t = Thread::from(t_);

		if(!t->vm->refTab.remove(r))
			croc_eh_throwStd(t_, "ApiError", "%s - Reference '%" CROC_UINTEGER_FORMAT "' does not exist",
				__FUNCTION__, r);
	}
}