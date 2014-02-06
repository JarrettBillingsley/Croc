
#include <stdio.h>
#include <stdlib.h>

#include "croc/api.h"
#include "croc/internal/apichecks.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

namespace croc
{
extern "C"
{
	void croc_eh_throw(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		throwImpl(t, t->stack[t->stackIndex - 1], false);
	}

	void croc_eh_rethrow(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		throwImpl(t, t->stack[t->stackIndex - 1], true);
	}

	word_t croc_eh_pushStd(CrocThread* t_, const char* exName)
	{
		auto t = Thread::from(t_);
		auto ex = t->vm->stdExceptions.lookup(String::create(t->vm, atoda(exName)));

		if(ex == nullptr)
		{
			auto check = t->vm->stdExceptions.lookup(String::create(t->vm, atoda("ApiError")));

			if(check == nullptr)
			{
				fprintf(stderr, "Fatal -- exception thrown before exception library was loaded");
				abort();
			}

			croc_eh_throwStd(*t, "ApiError", "Unknown standard exception type '%s'", exName);
		}

		return push(t, Value::from(*ex));
	}

	void croc_eh_throwStd(CrocThread* t, const char* exName, const char* fmt, ...)
	{
		va_list args;
		va_start(args, fmt);
		croc_eh_vthrowStd(t, exName, fmt, args);
		va_end(args);
	}

	void croc_eh_vthrowStd(CrocThread* t, const char* exName, const char* fmt, va_list args)
	{
		croc_eh_pushStd(t, exName);
		croc_pushNull(t);
		croc_vpushFormat(t, fmt, args);
		croc_call(t, -3, 1);
		croc_eh_throw(t);
	}

	int croc_eh_tryCall(CrocThread* t_, word_t slot, word_t numReturns)
	{
		auto t = Thread::from(t_);
		auto absSlot = fakeToAbs(t, slot);
		auto numParams = t->stackIndex - (absSlot + 1);

		if(numParams < 1)
			croc_eh_throwStd(*t, "ApiError", "%s - too few parameters (must have at least 1 for the context)", __FUNCTION__);

		if(numReturns < -1)
			croc_eh_throwStd(*t, "ApiError", "%s - invalid number of returns (must be >= -1)", __FUNCTION__);

		int results = 0;

		auto failed = tryCode(t, slot, [&results, &t, &slot, &numReturns]
		{
			results = croc_call(*t, slot, numReturns);
		});

		if(failed)
			return CrocCallRet_Error;
		else
			return results;
	}
}
}