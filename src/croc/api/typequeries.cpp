
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/basic.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	CrocType croc_type(CrocThread* t, word_t slot)
	{
		return getValue(Thread::from(t), slot)->type;
	}

	int croc_isTrue(CrocThread* t, word_t slot)
	{
		return !getValue(Thread::from(t), slot)->isFalse();
	}

	int croc_isNum(CrocThread* t, word_t slot)
	{
		auto v = getValue(Thread::from(t), slot);
		return v->type == CrocType_Int || v->type == CrocType_Float;
	}

	int croc_isChar(CrocThread* t, word_t slot)
	{
		auto v = getValue(Thread::from(t), slot);
		return v->type == CrocType_String && v->mString->cpLength == 1;
	}

	word_t croc_pushTypeString(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		return pushTypeStringImpl(t, *getValue(t, slot));
	}
}