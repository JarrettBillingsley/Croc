
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/basic.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** \returns a member of the \ref CrocType enumeration telling what type of value is in the given stack slot. */
	CrocType croc_type(CrocThread* t, word_t slot)
	{
		return getValue(Thread::from(t), slot)->type;
	}

	/** \returns nonzero if the given stack slot holds either an int or a float, and 0 otherwise. */
	int croc_isNum(CrocThread* t, word_t slot)
	{
		auto v = getValue(Thread::from(t), slot);
		return v->type == CrocType_Int || v->type == CrocType_Float;
	}

	/** \returns nonzero if the given stack slot holds a string that is exactly one codepoint long, and 0 otherwise. */
	int croc_isChar(CrocThread* t, word_t slot)
	{
		auto v = getValue(Thread::from(t), slot);
		return v->type == CrocType_String && v->mString->cpLength == 1;
	}

	/** Pushes a nice string representation of the type of the value in \c slot, which is useful for error messages.
	This is equivalent to Croc's \c niceTypeof library function. */
	word_t croc_pushTypeString(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		return pushTypeStringImpl(t, *getValue(t, slot));
	}
}