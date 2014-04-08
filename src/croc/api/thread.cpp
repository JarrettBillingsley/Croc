
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** Creates and pushes a new thread object in this VM, using the script function at \c func as its main function.
	The new thread will be in the initial state and can be started by calling it like a function.

	\returns the stack index of the pushed value. */
	word_t croc_thread_new(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "thread function");

		if(f->isNative)
			croc_eh_throwStd(t_, "ValueError", "%s - Native functions may not be used as the body of a thread",
				__FUNCTION__);

		croc_gc_maybeCollect(t_);
		auto nt = Thread::create(t->vm, f);
		nt->setHookFunc(t->vm->mem, t->hookFunc);
		nt->hooks = t->hooks;
		nt->hookDelay = t->hookDelay;
		nt->hookCounter = t->hookCounter;
		return croc_pushThread(t_, *nt);
	}

	/** \returns the execution state of the given thread. */
	CrocThreadState croc_thread_getState(CrocThread* t_)
	{
		return Thread::from(t_)->state;
	}

	/** \returns a string representation of the execution state of the given thread. This is a constant string, so it's
	safe to store a pointer to it. */
	const char* croc_thread_getStateString(CrocThread* t_)
	{
		return ThreadStateStrings[Thread::from(t_)->state];
	}

	/** \returns the call depth of the given thread. This is how many function calls are on the call stack. Note that
	there can be more calls than are "actually" on it, since this function also counts tailcalls. */
	uword_t croc_thread_getCallDepth(CrocThread* t_)
	{
		auto t = Thread::from(t_);

		uword depth = 0;

		for(uword i = 0; i < t->arIndex; i++)
			depth += t->actRecs[i].numTailcalls + 1;

		return depth;
	}

	/** Resets a dead thread at \c slot to the initial state, keeping the same main function. */
	void croc_thread_reset(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(other, slot, Thread, "slot");

		// This shouldn't be possible, but it can't hurt to check
		if(t->vm != other->vm)
			croc_eh_throwStd(t_, "ValueError", "%s - Attempting to reset a thread that belongs to a different VM",
				__FUNCTION__);

		if(other->state != CrocThreadState_Dead)
			croc_eh_throwStd(t_, "StateError", "%s - Attempting to reset a %s thread (must be dead)",
				__FUNCTION__, ThreadStateStrings[other->state]);

		other->reset();
	}

	/** Resets a dead thread at \c slot to the initial state, but changes its main function to the script function that
	is on top of the stack. The function is popped. */
	void croc_thread_resetWithFunc(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(other, slot, Thread, "slot");
		API_CHECK_PARAM(f, -1, Function, "thread function");

		// This shouldn't be possible, but it can't hurt to check
		if(t->vm != other->vm)
			croc_eh_throwStd(t_, "ValueError", "%s - Attempting to reset a thread that belongs to a different VM",
				__FUNCTION__);

		if(other->state != CrocThreadState_Dead)
			croc_eh_throwStd(t_, "StateError", "%s - Attempting to reset a %s thread (must be dead)",
				__FUNCTION__, ThreadStateStrings[other->state]);

		if(f->isNative)
			croc_eh_throwStd(t_, "ValueError", "%s - Native functions may not be used as the body of a thread",
				__FUNCTION__);

		other->setCoroFunc(t->vm->mem, f);
		croc_popTop(t_);
		other->reset();
	}

	/** Halts the given thread. If the thread is currently running, immediately throws a \c HaltException on it.
	Otherwise, it places a pending halt on the thread (see \ref croc_thread_pendingHalt). */
	void croc_thread_halt(CrocThread* t_)
	{
		auto t = Thread::from(t_);

		if(t->state == CrocThreadState_Running)
			croc_eh_throwStd(t_, "HaltException", "Thread halted");
		else
			croc_thread_pendingHalt(t_);
	}

	/** Places a pending halt on the thread. The thread will not halt immediately, but as soon as it begins executing
	script code, it will. */
	void croc_thread_pendingHalt(CrocThread* t_)
	{
		auto t = Thread::from(t_);

		if(t->state != CrocThreadState_Dead && t->arIndex > 0)
			t->shouldHalt = true;
	}

	/** \returns nonzero if there is a pending halt on the given thread. */
	int croc_thread_hasPendingHalt(CrocThread* t_)
	{
		return Thread::from(t_)->shouldHalt;
	}
}