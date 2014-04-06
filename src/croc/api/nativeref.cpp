
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
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

	word_t croc_ref_push(CrocThread* t_, crocref_t r)
	{
		auto t = Thread::from(t_);

		auto v = t->vm->refTab.lookup(r);

		if(v == nullptr)
			croc_eh_throwStd(t_, "ApiError", "%s - Reference '%" CROC_UINTEGER_FORMAT "' does not exist",
				__FUNCTION__, r);

		return push(t, Value::from(*v));
	}

	void croc_ref_remove(CrocThread* t_, crocref_t r)
	{
		auto t = Thread::from(t_);

		if(!t->vm->refTab.remove(r))
			croc_eh_throwStd(t_, "ApiError", "%s - Reference '%" CROC_UINTEGER_FORMAT "' does not exist",
				__FUNCTION__, r);
	}
}