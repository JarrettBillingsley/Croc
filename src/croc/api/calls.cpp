
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

#define COMMON_CALL_GUNK()\
	auto t = Thread::from(t_);\
	auto absSlot = fakeToAbs(t, slot);\
	auto numParams = t->stackIndex - (absSlot + 1);\
\
	if(numParams < 1)\
		croc_eh_throwStd(t_, "ApiError", "%s - too few parameters (must have at least 1 for the context)",\
			__FUNCTION__);\
\
	if(numReturns < -1)\
		croc_eh_throwStd(t_, "ApiError", "%s - invalid number of returns (must be >= -1)", __FUNCTION__);

#define TRYCALL_BEGIN\
	COMMON_CALL_GUNK();\
	int results = 0;\
	auto failed = tryCode(t, slot, [&]\
	{

#define TRYCALL_END\
	});\
\
	if(failed)\
		return CrocCallRet_Error;\
	else\
		return results;

using namespace croc;

extern "C"
{
	uword_t croc_call(CrocThread* t_, word_t slot, word_t numReturns)
	{
		COMMON_CALL_GUNK();
		return commonCall(t, absSlot, numReturns, callPrologue(t, absSlot, numReturns, numParams));
	}

	uword_t croc_methodCall(CrocThread* t_, word_t slot, const char* name, word_t numReturns)
	{
		COMMON_CALL_GUNK();
		auto mname = String::create(t->vm, atoda(name));
		return commonCall(t, absSlot, numReturns,
			methodCallPrologue(t, absSlot, t->stack[absSlot], mname, numReturns, numParams));
	}

	int croc_tryCall(CrocThread* t_, word_t slot, word_t numReturns)
	{
		TRYCALL_BEGIN
			results = commonCall(t, absSlot, numReturns, callPrologue(t, absSlot, numReturns, numParams));
		TRYCALL_END
	}

	int croc_tryMethodCall(CrocThread* t_, word_t slot, const char* name, word_t numReturns)
	{
		TRYCALL_BEGIN
			auto mname = String::create(t->vm, atoda(name));
			results = commonCall(t, absSlot, numReturns,
				methodCallPrologue(t, absSlot, t->stack[absSlot], mname, numReturns, numParams));
		TRYCALL_END
	}
}