
#include "croc/api.h"
#include "croc/internal/calls.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

namespace croc
{
extern "C"
{
	uword_t croc_call(CrocThread* t_, word_t slot, word_t numReturns)
	{
		// auto t = Thread::from(t_);
		(void)t_;
		(void)slot;
		(void)numReturns;
		assert(false);
	}

	// uword_t croc_methodCall(CrocThread* t_, word_t slot, const char* name, word_t numReturns)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// uword_t croc_methodCallStk(CrocThread* t_, word_t slot, word_t numReturns)
	// {
	// 	auto t = Thread::from(t_);
	// }
}
}