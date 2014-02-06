
#include "croc/api.h"
#include "croc/internal/apichecks.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

namespace croc
{
extern "C"
{
	uword_t croc_call(CrocThread* t_, word_t slot, word_t numReturns)
	{
		auto t = Thread::from(t_);
		auto absSlot = fakeToAbs(t, slot);
		auto numParams = t->stackIndex - (absSlot + 1);

		if(numParams < 1)
			croc_eh_throwStd(t_, "ApiError", "%s - too few parameters (must have at least 1 for the context)",
				__FUNCTION__);

		if(numReturns < -1)
			croc_eh_throwStd(t_, "ApiError", "%s - invalid number of returns (must be >= -1)", __FUNCTION__);

		return commonCall(t, absSlot, numReturns, callPrologue(t, absSlot, numReturns, numParams));
	}

	uword_t croc_methodCall(CrocThread* t_, word_t slot, const char* name, word_t numReturns)
	{
		auto t = Thread::from(t_);
		auto absSlot = fakeToAbs(t, slot);
		auto numParams = t->stackIndex - (absSlot + 1);

		if(numParams < 1)
			croc_eh_throwStd(t_, "ApiError", "%s - too few parameters (must have at least 1 for the context)",
				__FUNCTION__);

		if(numReturns < -1)
			croc_eh_throwStd(t_, "ApiError", "%s - invalid number of returns (must be >= -1)", __FUNCTION__);

		auto self = t->stack[absSlot];
		auto methodName = String::create(t->vm, atoda(name));
		auto isScript = commonMethodCall(t, absSlot, self, self, methodName, numReturns, numParams);
		return commonCall(t, absSlot, numReturns, isScript);
	}

	uword_t croc_methodCallStk(CrocThread* t_, word_t slot, word_t numReturns)
	{
		auto t = Thread::from(t_);
		auto absSlot = fakeToAbs(t, slot);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(methodName, -1, String, "method name");
		croc_popTop(t_);

		auto numParams = t->stackIndex - (absSlot + 1);

		if(numParams < 1)
			croc_eh_throwStd(t_, "ApiError", "%s - too few parameters (must have at least 1 for the context)",
				__FUNCTION__);

		if(numReturns < -1)
			croc_eh_throwStd(t_, "ApiError", "%s - invalid number of returns (must be >= -1)", __FUNCTION__);

		auto self = t->stack[absSlot];
		auto isScript = commonMethodCall(t, absSlot, self, self, methodName, numReturns, numParams);
		return commonCall(t, absSlot, numReturns, isScript);
	}
}
}