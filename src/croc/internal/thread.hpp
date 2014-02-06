#ifndef CROC_INTERNAL_THREAD_HPP
#define CROC_INTERNAL_THREAD_HPP

#include "croc/types.hpp"

namespace croc
{
	void yieldImpl(Thread* t, AbsStack firstValue, word numValues, word expectedResults);
	void resume(Thread* t, Thread* from, uword numParams);
}

#endif