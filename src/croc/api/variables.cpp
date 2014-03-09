
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/stack.hpp"
#include "croc/internal/variables.hpp"
#include "croc/types/base.hpp"

namespace croc
{
extern "C"
{
	word_t croc_pushEnvironment(CrocThread* t_, uword_t depth)
	{
		auto t = Thread::from(t_);
		return push(t, Value::from(getEnv(t, depth)));
	}

	void croc_setUpval(CrocThread* t_, uword_t idx)
	{
		auto t = Thread::from(t_);

		if(t->arIndex == 0)
			croc_eh_throwStd(t_, "ApiError", "%s - No function to set upvalue (can't call this function at top level)",
				__FUNCTION__);

		API_CHECK_NUM_PARAMS(1);

		auto func = t->currentAR->func;

		if(idx >= func->nativeUpvals().length)
			croc_eh_throwStd(t_, "BoundsError", "%s - Invalid upvalue index %" CROC_SIZE_T_FORMAT " (only have %" CROC_SIZE_T_FORMAT ")",
				__FUNCTION__, idx, func->nativeUpvals().length);

		func->setNativeUpval(t->vm->mem, idx, *getValue(t, -1));
		croc_popTop(t_);
	}

	word_t croc_pushUpval(CrocThread* t_, uword_t idx)
	{
		auto t = Thread::from(t_);

		if(t->arIndex == 0)
			croc_eh_throwStd(t_, "ApiError", "%s - No function to get upvalue (can't call this function at top level)",
				__FUNCTION__);

		// It is impossible for this function to be called from script code, because the only way that could happen is
		// if the interpreter itself called it.
		assert(t->currentAR->func->isNative);

		auto upvals = t->currentAR->func->nativeUpvals();

		if(idx >= upvals.length)
			croc_eh_throwStd(t_, "BoundsError", "%s - Invalid upvalue index %" CROC_SIZE_T_FORMAT " (only have %" CROC_SIZE_T_FORMAT ")",
				__FUNCTION__, idx, upvals.length);

		return push(t, upvals[idx]);
	}

	void croc_newGlobal(CrocThread* t_, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		croc_pushString(t_, name);
		croc_swapTop(t_);
		croc_newGlobalStk(t_);
	}

	void croc_newGlobalStk(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(name, -2, String, "global name");
		newGlobalImpl(t, name, getEnv(t), t->stack[t->stackIndex - 1]);
		croc_pop(t_, 2);
	}

	word_t croc_pushGlobal(CrocThread* t_, const char* name)
	{
		croc_pushString(t_, name);
		return croc_pushGlobalStk(t_);
	}

	word_t croc_pushGlobalStk(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(name, -1, String, "global name");
		t->stack[t->stackIndex - 1] = getGlobalImpl(t, name, getEnv(t));
		return croc_getStackSize(t_) - 1;
	}

	void croc_setGlobal(CrocThread* t_, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		croc_pushString(t_, name);
		croc_swapTop(t_);
		croc_setGlobalStk(t_);
	}

	void croc_setGlobalStk(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(name, -2, String, "global name");
		setGlobalImpl(t, name, getEnv(t), t->stack[t->stackIndex - 1]);
		croc_pop(t_, 2);
	}
}
}