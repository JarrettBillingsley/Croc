
#include "croc/base/writebarrier.hpp"
#include "croc/types/thread.hpp"

namespace croc
{
	namespace thread
	{
		// Create a new thread object.
		Thread* create(VM* vm)
		{
			auto t = createPartial(vm);
			auto &mem = vm->mem;

			t->tryRecs = DArray<TryRecord>::alloc(mem, 10);
			t->actRecs = DArray<ActRecord>::alloc(mem, 10);
			t->stack =   DArray<Value>::alloc(mem, 20);
			t->results = DArray<Value>::alloc(mem, 8);
			t->stackIndex = cast(AbsStack)1; // So that there is a 'this' at top-level.
			return t;
		}

		// Partially create a new thread. Doesn't allocate any memory for its various stacks. Used for serialization.
		Thread* createPartial(VM* vm)
		{
			auto t = ALLOC_OBJ(vm->mem, Thread);
			t->vm = vm;
			t->next = vm->allThreads;

			if(t->next)
				t->next->prev = t;

			vm->allThreads = t;
			return t;
		}

		// Create a new thread object with a function to be used as the thread body.
		Thread* create(VM* vm, Function* coroFunc)
		{
			auto t = create(vm);
			t->coroFunc = coroFunc;
			return t;
		}

		// Free a thread object.
		void free(Thread* t)
		{
			if(t->next) t->next->prev = t->prev;
			if(t->prev) t->prev->next = t->next;

			if(t->vm->allThreads == t)
				t->vm->allThreads = t->next;

			for(auto uv = t->upvalHead; uv != nullptr; uv = t->upvalHead)
			{
				t->upvalHead = uv->nextuv;
				uv->closedValue = *uv->value;
				uv->value = &uv->closedValue;
			}

			auto &mem = t->vm->mem;

			t->results.free(mem);
			t->stack.free(mem);
			t->actRecs.free(mem);
			t->tryRecs.free(mem);
			FREE_OBJ(mem, Thread, t);
		}

		void reset(Thread* t)
		{
			assert(t->upvalHead == nullptr); // should be..?
			t->currentTR = nullptr;
			t->trIndex = 0;
			t->currentAR = nullptr;
			t->arIndex = 0;
			t->stackIndex = cast(AbsStack)1;
			t->stackBase = cast(AbsStack)0;
			t->resultIndex = 0;
			t->shouldHalt = false;
			t->state = CrocThreadState_Initial;
		}

		void setHookFunc(Memory& mem, Thread* t, Function* f)
		{
			if(t->hookFunc != f)
			{
				WRITE_BARRIER(mem, t);
				t->hookFunc = f;
			}
		}

		void setCoroFunc(Memory& mem, Thread* t, Function* f)
		{
			if(t->coroFunc != f)
			{
				WRITE_BARRIER(mem, t);
				t->coroFunc = f;
			}
		}
	}
}