
#include "croc/base/writebarrier.hpp"

namespace croc
{
	// Create a new thread object.
	Thread* Thread::create(VM* vm)
	{
		auto t = createPartial(vm);
		auto &mem = vm->mem;

		t->ehFrames = DArray<ScriptEHFrame>::alloc(mem, 10);
		t->actRecs =  DArray<ActRecord>::alloc(mem, 10);
		t->stack =    DArray<Value>::alloc(mem, 20);
		t->results =  DArray<Value>::alloc(mem, 8);
		t->stackIndex = cast(AbsStack)1; // So that there is a 'this' at top-level.
		t->hooksEnabled = true;
		return t;
	}

	// Partially create a new thread. Doesn't allocate any memory for its various stacks. Used for serialization.
	Thread* Thread::createPartial(VM* vm)
	{
		auto t = ALLOC_OBJ(vm->mem, Thread);
		t->type = CrocType_Thread;
		t->vm = vm;
		t->next = vm->allThreads;

		if(t->next)
			t->next->prev = t;

		vm->allThreads = t;
		return t;
	}

	// Create a new thread object with a function to be used as the thread body.
	Thread* Thread::create(VM* vm, Function* coroFunc)
	{
		auto t = create(vm);
		t->coroFunc = coroFunc;
		return t;
	}

	// Free a thread object.
	void Thread::free(Thread* t)
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
		t->ehFrames.free(mem);
		FREE_OBJ(mem, Thread, t);
	}

	void Thread::reset()
	{
		assert(this->upvalHead == nullptr); // should be..?
		this->currentEH = nullptr;
		this->ehIndex = 0;
		this->currentAR = nullptr;
		this->arIndex = 0;
		this->stackIndex = cast(AbsStack)1;
		this->stackBase = cast(AbsStack)0;
		this->resultIndex = 0;
		this->shouldHalt = false;
		this->state = CrocThreadState_Initial;
	}

	void Thread::setHookFunc(Memory& mem, Function* f)
	{
		if(this->hookFunc != f)
		{
			WRITE_BARRIER(mem, this);
			this->hookFunc = f;
		}
	}

	void Thread::setCoroFunc(Memory& mem, Function* f)
	{
		if(this->coroFunc != f)
		{
			WRITE_BARRIER(mem, this);
			this->coroFunc = f;
		}
	}
}