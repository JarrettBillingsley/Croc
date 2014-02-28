
#include <cstdio>
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
		auto vm = t->vm;

		if(vm->ehIndex >= vm->ehFrames.length)
			vm->ehFrames.resize(vm->mem, vm->ehFrames.length * 2);

		vm->currentEH = &vm->ehFrames[vm->ehIndex];
		vm->ehIndex++;
		vm->currentEH->t = t;
		vm->currentEH->actRecord = t->arIndex - 1;
		return vm->currentEH;
	}

	void pushNativeEHFrame(Thread* t, RelStack slot, jmp_buf& buf)
	{
		auto eh = pushEHFrame(t);
		eh->flags = EHFlags_Catch | EHFlags_Native;
		eh->slot = fakeToAbs(t, slot);
		eh->nativePC = &buf;
		t->vm->lastNativeEHPlusOne = t->vm->ehIndex;
	}

	void pushExecEHFrame(Thread* t, jmp_buf& buf)
	{
		pushNativeEHFrame(t, t->stackIndex - 1 - t->stackBase, buf);
		t->vm->currentEH->actRecord--;
	}

	void pushScriptEHFrame(Thread* t, bool isCatch, RelStack slot, word pcOffset)
	{
		auto eh = pushEHFrame(t);
		eh->flags = isCatch ? EHFlags_Catch : 0;
		eh->slot = fakeToAbs(t, slot);
		eh->scriptPC = t->currentAR->pc + pcOffset;
	}

	void popEHFrame(Thread* t)
	{
		auto vm = t->vm;
		assert(vm->ehIndex > 0);
		assert(vm->currentEH->t == t);

		if(EH_IS_NATIVE(vm->currentEH))
		{
			for(uword i = vm->ehIndex - 2; cast(word)i >= 0; i--)
			{
				if(EH_IS_NATIVE(&vm->ehFrames[i]))
				{
					vm->lastNativeEHPlusOne = i + 1;
					goto _found;
				}
			}

			vm->lastNativeEHPlusOne = 0;
		_found:;
		}

		vm->ehIndex--;

		if(vm->ehIndex > 0)
			vm->currentEH = &vm->ehFrames[vm->ehIndex - 1];
		else
			vm->currentEH = nullptr;
	}

	void unwindThisFramesEH(Thread* t)
	{
		auto vm = t->vm;
		// This uses signed comparison because the EH actRecord index can be -1, which indicates there IS no
		// corresponding AR; this is the case when a native EH frame is installed on the main thread.
		while(vm->ehIndex > 0 && vm->currentEH->t == t && cast(word)vm->currentEH->actRecord >= cast(word)t->arIndex)
			popEHFrame(t);
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

		popEHFrame(t);
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

		auto vm = t->vm;
		vm->exception = ex.mInstance;
		auto jumpFrame = (vm->lastNativeEHPlusOne == 0) ? nullptr : &vm->ehFrames[vm->lastNativeEHPlusOne - 1];
		assert(!jumpFrame || EH_IS_NATIVE(jumpFrame));
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
			croc_call(*t, -3, 0);
			abort();
		}
		else
		{
			t = vm->curThread;
			auto destFrame = vm->currentEH;
			assert(destFrame->t == t);
			popARTo(t, destFrame->actRecord + 1);
			auto slot = destFrame->slot;
			closeUpvals(t, slot);

			// This can happen at top-level, when popARTo sets the stack index to 1.
			if(t->stackIndex <= slot)
				t->stackIndex = slot + 1;

			t->stack.slice(slot + 1, t->stackIndex).fill(Value::nullValue);

			if(EH_IS_CATCH(destFrame))
			{
				t->stack[slot] = ex;
				t->vm->exception = nullptr;
			}

			if(EH_IS_NATIVE(destFrame))
				t->stackIndex = slot + 1;
			else
				t->currentAR->pc = destFrame->scriptPC;

			longjmp(*jumpFrame->nativePC, 1);
		}
	}

	void unwind(Thread* t)
	{
		auto vm = t->vm;

		while(t->currentAR->unwindCounter > 0)
		{
			assert(vm->ehIndex > 0);
			assert(vm->currentEH->t == t);
			assert(vm->currentEH->actRecord == t->arIndex);

			auto frame = *vm->currentEH;
			popEHFrame(t);
			closeUpvals(t, frame.slot);
			t->currentAR->unwindCounter--;

			if(!EH_IS_CATCH(&frame))
			{
				// finally in the middle of an unwind
				t->currentAR->pc = frame.scriptPC;
				return;
			}
		}

		t->currentAR->pc = t->currentAR->unwindReturn;
		t->currentAR->unwindReturn = nullptr;
	}
}