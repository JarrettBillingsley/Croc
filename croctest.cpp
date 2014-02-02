#include <stdio.h>
#include <stdlib.h>
#include <typeinfo>

#include "croc/base/memory.hpp"
#include "croc/base/darray.hpp"
#include "croc/utils.hpp"
#include "croc/base/gcobject.hpp"
#include "croc/types.hpp"
#include "croc/base/gc.hpp"

using namespace croc;

void* DefaultMemFunc(void* ctx, void* p, size_t oldSize, size_t newSize)
{
	(void)ctx;
	(void)oldSize;

	if(newSize == 0)
	{
		free(p);
		return nullptr;
	}
	else
	{
		void* ret = cast(void*)realloc(p, newSize);
		assert(ret != nullptr);
		return ret;
	}
}

void disableGC(VM* vm)
{
	vm->mem.gcDisabled++;
}

void enableGC(VM* vm)
{
	vm->mem.gcDisabled--;
	assert(vm->mem.gcDisabled != cast(size_t)-1);
}

String* createString(Thread* t, DArray<const char> data)
{
	uword h;

	if(auto s = String::lookup(t->vm, data, h))
		return s;

	uword cpLen;

	if(verifyUtf8(data, cpLen) != UtfError_OK)
		assert(false);

	return String::create(t->vm, data, h, cpLen);
}

const size_t FinalizeLoopLimit = 1000;

void freeAll(VM* vm)
{
	vm->globals->clear(vm->mem);
	vm->registry->clear(vm->mem);
	vm->refTab.clear(vm->mem);

	for(auto t = vm->allThreads; t != nullptr; t = t->next)
	{
		if(t->state == CrocThreadState_Dead)
			t->reset();
	}

	gcCycle(vm, GCCycleType_Full);

	size_t limit = 0;

	do
	{
		if(limit > FinalizeLoopLimit)
			assert(false);
			// throw new Exception("Failed to clean up - you've got an awful lot of finalizable trash or something's broken.");

		// runFinalizers(vm->mainThread);
		gcCycle(vm, GCCycleType_Full);
		limit++;
	} while(!vm->toFinalize.isEmpty());

	gcCycle(vm, GCCycleType_NoRoots);

	if(!vm->toFinalize.isEmpty())
		assert(false);
		// throw new Exception("Did you stick a finalizable object in a global metatable or something? I think you did. Stop doing that.");
}

DArray<const char> atoda(const char* str)
{
	return DArray<const char>::n(str, strlen(str));
}

void openVMImpl(VM* vm, MemFunc memFunc, void* ctx = nullptr)
{
	assert(vm->mainThread == nullptr);

	vm->mem.init(memFunc, ctx);

	disableGC(vm);

	vm->metaTabs = DArray<Namespace*>::alloc(vm->mem, CrocType_NUMTYPES);
	vm->mainThread = Thread::create(vm);
	auto t = vm->mainThread;

	vm->metaStrings = DArray<String*>::alloc(vm->mem, MM_NUMMETAMETHODS + 2);

	for(uword i = 0; i < MM_NUMMETAMETHODS; i++)
		vm->metaStrings[i] = createString(t, atoda(MetaNames[i]));

	vm->ctorString = createString(t, atoda("constructor"));
	vm->finalizerString = createString(t, atoda("finalizer"));
	vm->metaStrings[vm->metaStrings.length - 2] = vm->ctorString;
	vm->metaStrings[vm->metaStrings.length - 1] = vm->finalizerString;

	vm->curThread = vm->mainThread;
	vm->globals = Namespace::create(vm->mem, createString(t, atoda("")));
	vm->registry = Namespace::create(vm->mem, createString(t, atoda("<registry>")));

	enableGC(vm);
	// _G = _G._G = _G._G._G = _G._G._G._G = ...
	// push(t, CrocValue(vm->globals));
	// newGlobal(t, "_G");
}

void closeVMImpl(VM* vm)
{
	assert(vm->mainThread != nullptr);

	freeAll(vm);
	vm->metaTabs.free(vm->mem);
	vm->metaStrings.free(vm->mem);
	vm->stringTab.clear(vm->mem);
	vm->weakrefTab.clear(vm->mem);
	vm->refTab.clear(vm->mem);
	vm->stdExceptions.clear(vm->mem);
	vm->roots[0].clear(vm->mem);
	vm->roots[1].clear(vm->mem);
	vm->cycleRoots.clear(vm->mem);
	vm->toFree.clear(vm->mem);
	vm->toFinalize.clear(vm->mem);
	vm->mem.cleanup();

	if(vm->mem.totalBytes != 0)
	{
		LEAK_DETECT(vm->mem.leaks.dumpBlocks());
		printf("There are %d total unfreed bytes!\n", vm->mem.totalBytes);
	}

	LEAK_DETECT(vm->mem.leaks.cleanup());

	memset(vm, 0, sizeof(VM));
}

int main()
{
	VM vm;
	openVMImpl(&vm, DefaultMemFunc);

	// auto &mem = vm.mem;

	// Hash<int, int> h;
	// h.init();

	// for(int i = 1; i <= 10; i++)
	// {
	// 	auto n = h.insertNode(mem, i);
	// 	n->value = i * 5;

	// 	if(i & 1)
	// 		SET_KEY_MODIFIED(n);
	// }

	// for(auto n: h.modifiedNodes())
	// 	printf("h[%d (%d)] = %d (%d) \n", n->key, IS_KEY_MODIFIED(n) != 0, n->value, IS_VAL_MODIFIED(n) != 0);

	closeVMImpl(&vm);

	return 0;
}