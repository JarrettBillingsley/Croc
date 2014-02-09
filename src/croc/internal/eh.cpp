
#include <stdlib.h>

#include "croc/api.h"
#include "croc/internal/basic.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/debug.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

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

	EHFrame* pushEHFrame(Thread* t)
	{
		if(t->ehIndex >= t->ehFrames.length)
			t->ehFrames.resize(t->vm->mem, t->ehFrames.length * 2);

		t->currentEH = &t->ehFrames[t->ehIndex];
		t->ehIndex++;
		t->currentEH->actRecord = t->arIndex - 1;
		return t->currentEH;
	}

	void pushNativeEHFrame(Thread* t, RelStack slot, jmp_buf& buf)
	{
		auto eh = pushEHFrame(t);
		eh->isCatch = true;
		eh->slot = croc_absIndex(*t, slot);
		eh->native = &buf;
		eh->pc = nullptr;
	}

	void pushScriptEHFrame(Thread* t, bool isCatch, RelStack slot, word pcOffset)
	{
		auto eh = pushEHFrame(t);
		eh->isCatch = isCatch;
		eh->slot = slot;
		eh->native = nullptr;
		eh->pc = t->currentAR->pc + pcOffset;
	}

	void popEHFrame(Thread* t)
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
		while(t->ehIndex > 0 && cast(word)t->currentEH->actRecord >= cast(word)t->arIndex)
			popEHFrame(t);
	}

	bool tryCode(Thread* t, RelStack slot, std::function<void()> dg)
	{
		jmp_buf buf;
		bool ret;
		auto savedNativeDepth = t->nativeCallDepth;
		pushNativeEHFrame(t, slot, buf);

		if(setjmp(buf) == 0)
		{
			dg();
			ret = false;
		}
		else
			ret = true;

		popEHFrame(t);
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
				croc_pushFormat(*t, "<%u tailcall%s>", ar.numTailcalls, ar.numTailcalls == 1 ? "" : "s");
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

		t->vm->exception = ex.mInstance;

		EHFrame* frame = nullptr;
		Thread* curThread = t;

		for( ; curThread != nullptr; curThread = curThread->threadThatResumedThis)
		{
			if(curThread->ehIndex > 0)
			{
				frame = curThread->currentEH;
				break;
			}

			popARTo(curThread, 0);
			t->vm->curThread = curThread->threadThatResumedThis;
		}

		if(frame == nullptr)
		{
			// Uh oh, no handler; call the unhandled handler. At this point, there are no running threads, so let's use
			// the main thread.
			t = t->vm->mainThread;

			push(t, Value::from(t->vm->unhandledEx));
			push(t, Value::nullValue);
			push(t, Value::from(t->vm->exception));
			t->vm->exception = nullptr;
			croc_call(*t, -3, 0);
			abort();
		}
		else
		{
			t = curThread;

			popARTo(curThread, frame->actRecord + 1);
			auto base = t->stackBase + frame->slot;
			closeUpvals(t, base);

			// This can happen at top-level, when popARTo sets the stack index to 1.
			if(t->stackIndex <= base)
				t->stackIndex = base + 1;

			t->stack.slice(base + 1, t->stackIndex).fill(Value::nullValue);

			if(frame->isCatch)
			{
				t->stack[base] = ex;
				t->vm->exception = nullptr;
			}

			if(frame->native)
			{
				t->stackIndex = base + 1;
				longjmp(*frame->native, 1);
			}
			else
				t->currentAR->pc = frame->pc;
		}
	}

	void unwind(Thread* t)
	{
		while(t->currentAR->unwindCounter > 0)
		{
			assert(t->ehIndex > 0);
			assert(t->currentEH->actRecord == t->arIndex);

			auto frame = *t->currentEH;
			popEHFrame(t);
			closeUpvals(t, t->stackBase + frame.slot);
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