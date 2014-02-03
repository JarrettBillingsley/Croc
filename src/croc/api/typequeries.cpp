
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

	// TODO:api
	// word_t croc_pushTypeString(CrocThread* t, word_t slot)
}
}