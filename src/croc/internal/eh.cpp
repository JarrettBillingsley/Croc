
#include <cstdio>
#include <stdlib.h>

#include "croc/api.h"
#include "croc/internal/basic.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/debug.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	word defaultUnhandledEx(CrocThread* t)
	{
		fprintf(stderr, "-------- UNHANDLED CROC EXCEPTION --------\n");
		croc_pushToString(t, 1);
		fprintf(stderr, "%s\n", croc_getString(t, -1));
		croc_popTop(t);
		croc_dup(t, 1);
		croc_pushNull(t);
		croc_methodCall(t, -2, "tracebackString", 1);
		fprintf(stderr, "%s\n", croc_getString(t, -1));
		return 0;
	}

	void pushNativeEHFrame(Thread* t, RelStack slot, jmp_buf& buf)
	{
		auto vm = t->vm;
		if(vm->ehIndex >= vm->ehFrames.length)
			vm->ehFrames.resize(vm->mem, vm->ehFrames.length * 2);

		auto eh = &vm->ehFrames[vm->ehIndex++];
		vm->currentEH = eh;
		eh->t = t;
		eh->actRecord = t->arIndex - 1;
		eh->slot = fakeToAbs(t, slot);
		eh->jbuf = &buf;
	}

	void pushExecEHFrame(Thread* t, jmp_buf& buf)
	{
		pushNativeEHFrame(t, t->stackIndex - 1 - t->stackBase, buf);
		t->vm->currentEH->actRecord--;
	}

	void pushScriptEHFrame(Thread* t, bool isCatch, RelStack slot, Instruction* pc)
	{
		if(t->ehIndex >= t->ehFrames.length)
			t->ehFrames.resize(t->vm->mem, t->ehFrames.length * 2);

		auto eh = &t->ehFrames[t->ehIndex++];
		t->currentEH = eh;
		eh->actRecord = t->arIndex - 1;
		eh->slot = fakeToAbs(t, slot);
		eh->isCatch = isCatch;
		eh->pc = pc;
	}

	void popNativeEHFrame(Thread* t)
	{
		auto vm = t->vm;
		assert(vm->ehIndex > 0);
		assert(vm->currentEH->t == t);

		vm->ehIndex--;

		if(vm->ehIndex > 0)
			vm->currentEH = &vm->ehFrames[vm->ehIndex - 1];
		else
			vm->currentEH = nullptr;
	}

	void popScriptEHFrame(Thread* t)
	{
		assert(t->ehIndex > 0);

		t->ehIndex--;

		if(t->ehIndex > 0)
			t->currentEH = &t->ehFrames[t->ehIndex - 1];
		else
			t->currentEH = nullptr;
	}

	void unwindThisFramesEH(Thread* t)
	{
		while(t->ehIndex > 0 && t->currentEH->actRecord >= t->arIndex)
			popScriptEHFrame(t);
	}

	bool tryCode(Thread* t, RelStack slot, std::function<void()> dg)
	{
		jmp_buf buf;
		bool ret;
		auto savedNativeDepth = t->nativeCallDepth;
#ifndef NDEBUG
		auto ehCheck = t->vm->ehIndex;
#endif
		pushNativeEHFrame(t, slot, buf);

		if(setjmp(buf) == 0)
		{
			dg();
			ret = false;
		}
		else
			ret = true;

		popNativeEHFrame(t);
		assert(t->vm->ehIndex == ehCheck);
		t->nativeCallDepth = savedNativeDepth;
		return ret;
	}

	word pushTraceback(Thread* t)
	{
		auto ret = croc_array_new(*t, 0);

		for(auto &ar: t->actRecs.slice(0, t->arIndex).reverse())
		{
			pushDebugLoc(t, &ar);
			croc_cateq(*t, ret, 1);

			if(ar.numTailcalls > 0)
			{
				croc_pushFormat(*t,
					"<%" CROC_SIZE_T_FORMAT " tailcall%s>", ar.numTailcalls, ar.numTailcalls == 1 ? "" : "s");
				croc_eh_pushLocationObject(*t, croc_getString(*t, -1), -1, CrocLocation_Script);
				croc_cateq(*t, ret, 1);
				croc_popTop(*t);
			}
		}

		return ret;
	}

	void continueTraceback(Thread* t, Value ex)
	{
		push(t, ex);
		croc_field(*t, -1, "traceback");
		pushTraceback(t);
		croc_cateq(*t, -2, 1);
		croc_pop(*t, 2);
	}

	void addLocationInfo(Thread* t, Value ex)
	{
		auto e = push(t, ex);
		auto loc = croc_field(*t, e, "location");
		auto col = croc_field(*t, loc, "col");

		if(croc_getInt(*t, col) == CrocLocation_Unknown)
		{
			croc_pop(*t, 2);

			auto tb = pushTraceback(t);

			if(croc_len(*t, tb) > 0)
				croc_idxi(*t, tb, 0);
			else
				pushDebugLoc(t);

			croc_fielda(*t, e, "location");
			croc_fielda(*t, e, "traceback");
		}
		else
			croc_pop(*t, 2);
	}

	void throwImpl(Thread* t, Value ex, bool rethrowing)
	{
		if(ex.type != CrocType_Instance)
		{
			pushTypeStringImpl(t, ex);
			croc_eh_throwStd(*t, "TypeError", "Only instances can be thrown, not '%s'", croc_getString(*t, -1));
		}

		if(!rethrowing)
			addLocationInfo(t, ex);

		if(t->currentAR)
		{
			t->currentAR->unwindCounter = 0;
			t->currentAR->unwindReturn = nullptr;
		}

		auto vm = t->vm;
		vm->exception = ex.mInstance;
		auto jumpFrame = vm->currentEH;
		auto destThread = jumpFrame ? jumpFrame->t : nullptr;

		// Kill any threads between here and where the exception is being caught
		for(auto curThread = t; curThread != destThread; curThread = curThread->threadThatResumedThis)
		{
			popARTo(curThread, 0);
			vm->curThread = curThread->threadThatResumedThis;
		}

		if(jumpFrame == nullptr)
		{
			// Uh oh, no handler; call the unhandled handler. At this point, there are no running threads, so let's use
			// the main thread.
			t = vm->mainThread;

			push(t, Value::from(vm->unhandledEx));
			push(t, Value::nullValue);
			push(t, Value::from(vm->exception));
			vm->exception = nullptr;

			if(croc_tryCall(*t, -3, 0) < 0)
				fprintf(stderr, "Error in unhandled exception handler!\n");

			abort();
		}
		else
		{
			t = vm->curThread;
			auto threadFrame = t->currentEH;
			// Signed, since native EH frames can have an AR of -1 which means it's at top-level
			bool isScript = threadFrame && cast(word)threadFrame->actRecord > cast(word)jumpFrame->actRecord;

			uword destAR, slot;

			if(isScript)
			{
				destAR = threadFrame->actRecord;
				slot = threadFrame->slot;
			}
			else
			{
				destAR = jumpFrame->actRecord;
				slot = jumpFrame -> slot;
			}

			popARTo(t, destAR + 1);
			closeUpvals(t, slot);

			// This can happen at top-level, when popARTo sets the stack index to 1.
			if(t->stackIndex <= slot)
				t->stackIndex = slot + 1;

			t->stack.slice(slot + 1, t->stackIndex).fill(Value::nullValue);

			if(!isScript || threadFrame->isCatch)
			{
				t->stack[slot] = ex;
				t->vm->exception = nullptr;
			}

			if(isScript)
				t->currentAR->pc = threadFrame->pc;
			else
				t->stackIndex = slot + 1;

			longjmp(*jumpFrame->jbuf, 1);
		}
	}

	void unwind(Thread* t)
	{
		while(t->currentAR->unwindCounter > 0)
		{
			assert(t->ehIndex > 0);
			assert(t->currentEH->actRecord == t->arIndex);

			auto frame = *t->currentEH;
			popScriptEHFrame(t);
			closeUpvals(t, frame.slot);
			t->currentAR->unwindCounter--;

			if(!frame.isCatch)
			{
				// finally in the middle of an unwind
				t->currentAR->pc = frame.pc;
				return;
			}
		}

		t->currentAR->pc = t->currentAR->unwindReturn;
		t->currentAR->unwindReturn = nullptr;
	}
}