
#include "croc/api.h"
#include "croc/internal/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

namespace croc
{
extern "C"
{
	word_t croc_thread_new(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "thread function");

		if(f->isNative)
			assert(false); // TODO:ex
			// throwStdException(t, "ValueError", __FUNCTION__ ~ " - Native functions may not be used as the body of a thread");

		croc_gc_maybeCollect(t_);
		auto nt = Thread::create(t->vm, f);
		nt->setHookFunc(t->vm->mem, t->hookFunc);
		nt->hooks = t->hooks;
		nt->hookDelay = t->hookDelay;
		nt->hookCounter = t->hookCounter;
		return croc_pushThread(t_, *nt);
	}

	CrocThreadState croc_thread_getState(CrocThread* t_)
	{
		return Thread::from(t_)->state;
	}

	const char* croc_thread_getStateString(CrocThread* t_)
	{
		return ThreadStateStrings[Thread::from(t_)->state];
	}

	uword_t croc_thread_getCallDepth(CrocThread* t_)
	{
		auto t = Thread::from(t_);

		uword depth = 0;

		for(uword i = 0; i < t->arIndex; i++)
			depth += t->actRecs[i].numTailcalls + 1;

		return depth;
	}

	void croc_thread_reset(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(other, slot, Thread, "slot");

		// This shouldn't be possible, but it can't hurt to check
		if(t->vm != other->vm)
			assert(false); // TODO:ex
			// throwStdException(t, "ValueError", __FUNCTION__ ~ " - Attempting to reset a thread that belongs to a different VM");

		if(other->state != CrocThreadState_Dead)
			assert(false); // TODO:ex
			// throwStdException(t, "StateError", __FUNCTION__ ~ " - Attempting to reset a {} thread (must be dead)", stateString(other));

		other->reset();
	}

	void croc_thread_resetWithFunc(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(other, slot, Thread, "slot");
		API_CHECK_PARAM(f, -1, Function, "thread function");

		// This shouldn't be possible, but it can't hurt to check
		if(t->vm != other->vm)
			assert(false); // TODO:ex
			// throwStdException(t, "ValueError", __FUNCTION__ ~ " - Attempting to reset a thread that belongs to a different VM");

		if(other->state != CrocThreadState_Dead)
			assert(false); // TODO:ex
			// throwStdException(t, "StateError", __FUNCTION__ ~ " - Attempting to reset a {} thread (must be dead)", stateString(other));

		if(f->isNative)
			assert(false); // TODO:ex
			// throwStdException(t, "ValueError", __FUNCTION__ ~ " - Native functions may not be used as the body of a thread");

		other->setCoroFunc(t->vm->mem, f);
		croc_popTop(t_);
		other->reset();
	}

	void croc_thread_halt(CrocThread* t_)
	{
		auto t = Thread::from(t_);

		if(t->state == CrocThreadState_Running)
			assert(false); // TODO:ex
			// throw new CrocHaltException();
		else
			croc_thread_pendingHalt(t_);
	}

	void croc_thread_pendingHalt(CrocThread* t_)
	{
		auto t = Thread::from(t_);

		if(t->state != CrocThreadState_Dead && t->arIndex > 0)
			t->shouldHalt = true;
	}

	int croc_thread_hasPendingHalt(CrocThread* t_)
	{
		return Thread::from(t_)->shouldHalt;
	}
}
}