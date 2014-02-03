
#include "croc/api.h"
#include "croc/internal/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

namespace croc
{
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

	// TODO:api
	// word_t croc_pushTypeString(CrocThread* t, word_t slot)
}
}