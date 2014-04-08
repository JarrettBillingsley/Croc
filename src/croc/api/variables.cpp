
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/stack.hpp"
#include "croc/internal/variables.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** Pushes the environment namespace of the function at the given call stack depth. A \c depth of 0 means the
	currently-executing function; 1 means the function which called this one; and so on. If you pass a depth greater
	than the call stack depth, pushes the global namespace instead.

	It is an error to get the environment of a call stack index which was overwritten by a tailcall.

	\returns the stack slot of the pushed value. */
	word_t croc_pushEnvironment(CrocThread* t_, uword_t depth)
	{
		auto t = Thread::from(t_);
		return push(t, Value::from(getEnv(t, depth)));
	}

	/** Inside a native function which had upvalues associated with it at creation, you can use this to set the upvalue
	with the given index. */
	void croc_setUpval(CrocThread* t_, uword_t idx)
	{
		auto t = Thread::from(t_);

		if(t->arIndex == 0)
			croc_eh_throwStd(t_, "ApiError", "%s - No function to set upvalue (can't call this function at top level)",
				__FUNCTION__);

		API_CHECK_NUM_PARAMS(1);

		auto func = t->currentAR->func;

		if(idx >= func->nativeUpvals().length)
			croc_eh_throwStd(t_, "BoundsError",
				"%s - Invalid upvalue index %" CROC_SIZE_T_FORMAT " (only have %" CROC_SIZE_T_FORMAT ")",
				__FUNCTION__, idx, func->nativeUpvals().length);

		func->setNativeUpval(t->vm->mem, idx, *getValue(t, -1));
		croc_popTop(t_);
	}

	/** Inside a native function which had upvalues associated with it at creation, pushes the upvalue with the given
	index.

	\returns the stack slot of the pushed value. */
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
			croc_eh_throwStd(t_, "BoundsError",
				"%s - Invalid upvalue index %" CROC_SIZE_T_FORMAT " (only have %" CROC_SIZE_T_FORMAT ")",
				__FUNCTION__, idx, upvals.length);

		return push(t, upvals[idx]);
	}

	/** Expects a value on top of the stack. Pops the value and creates a new global named \c name in the current
	function's environment, just like declaring a global in Croc. */
	void croc_newGlobal(CrocThread* t_, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		croc_pushString(t_, name);
		croc_swapTop(t_);
		croc_newGlobalStk(t_);
	}

	/** Expects two values on top of the stack: the value on top, and the name of the global to create below that.
	Creates the global and pops both values. */
	void croc_newGlobalStk(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(name, -2, String, "global name");
		newGlobalImpl(t, name, getEnv(t), t->stack[t->stackIndex - 1]);
		croc_pop(t_, 2);
	}

	/** Pushes the value of the global variable named \c name, just like accessing a global in Croc.

	\returns the stack slot of the pushed value. */
	word_t croc_pushGlobal(CrocThread* t_, const char* name)
	{
		croc_pushString(t_, name);
		return croc_pushGlobalStk(t_);
	}

	/** Expects a string on top of the stack as the name of the global to get. Replaces the top of the stack with the
	value of the global.

	\returns the stack slot of the pushed value. */
	word_t croc_pushGlobalStk(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(name, -1, String, "global name");
		t->stack[t->stackIndex - 1] = getGlobalImpl(t, name, getEnv(t));
		return croc_getStackSize(t_) - 1;
	}

	/* Expects a value on top of the stack. Pops the value and assigns it into the global named \c name in the current
	function's environment, just like setting a global in Croc. */
	void croc_setGlobal(CrocThread* t_, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		croc_pushString(t_, name);
		croc_swapTop(t_);
		croc_setGlobalStk(t_);
	}

	/** Expects two values on top of the stack: the value on top, and the name of the global to set below that. Sets
	the global and pops both values. */
	void croc_setGlobalStk(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(name, -2, String, "global name");
		setGlobalImpl(t, name, getEnv(t), t->stack[t->stackIndex - 1]);
		croc_pop(t_, 2);
	}
}