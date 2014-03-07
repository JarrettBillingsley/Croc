
#include <stdio.h>

#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

namespace croc
{
extern "C"
{
	void croc_debug_setHookFunc(CrocThread* t_, uword_t mask, uword_t hookDelay)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);

		auto f = getFunction(t, -1);

		if(f == nullptr && !croc_isNull(t_, -1))
			API_PARAM_TYPE_ERROR(-1, "hook function", "function|null");

		if(f == nullptr || mask == 0)
		{
			t->hookDelay = 0;
			t->hookCounter = 0;
			t->setHookFunc(t->vm->mem, nullptr);
			t->hooks = 0;
		}
		else
		{
			if(hookDelay == 0)
				CLEAR_FLAG(mask, CrocThreadHook_Delay);
			else
				SET_FLAG(mask, CrocThreadHook_Delay);

			if(TEST_FLAG(mask, CrocThreadHook_TailCall))
			{
				SET_FLAG(mask, CrocThreadHook_Call);
				CLEAR_FLAG(mask, CrocThreadHook_TailCall);
			}

			t->hookDelay = hookDelay;
			t->hookCounter = hookDelay;
			t->setHookFunc(t->vm->mem, f);
			t->hooks = mask;
		}

		croc_popTop(t_);
	}

	word_t croc_debug_pushHookFunc(CrocThread* t_)
	{
		auto t = Thread::from(t_);

		if(t->hookFunc == nullptr)
			return croc_pushNull(t_);
		else
			return push(t, Value::from(t->hookFunc));
	}

	uword_t croc_debug_getHookMask(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		return t->hooks;
	}

	uword_t croc_debug_getHookDelay(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		return t->hookDelay;
	}

	namespace
	{
		void printStackImpl(Thread* t, bool wholeStack)
		{
			printf("\n-----Stack Dump-----\n");

			auto tmp = t->stackBase;
			t->stackBase = 0;
			auto top = t->stackIndex;

			for(uword i = wholeStack ? 0 : tmp; i < top; i++)
			{
				// ORDER CROCTYPE
				if(t->stack[i].type >= CrocType_FirstUserType && t->stack[i].type <= CrocType_LastUserType)
				{
					croc_pushToStringRaw(*t, i);
					croc_pushTypeString(*t, i);
					printf("[%3u:%4d]: '%s': %s\n",
						i, cast(word)i - cast(word)tmp, croc_getString(*t, -2), croc_getString(*t, -1));
					croc_pop(*t, 2);
				}
				else
					printf("[%3u:%4d]: %.16" CROC_HEX64_FORMAT ": %u\n",
						i, cast(word)i - cast(word)tmp, *cast(uint64_t*)&t->stack[i].mInt, t->stack[i].type);
			}

			t->stackBase = tmp;
			printf("\n");
		}
	}

	void croc_debug_printStack(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		printStackImpl(t, false);
	}

	void croc_debug_printWholeStack(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		printStackImpl(t, true);
	}

	void croc_debug_printCallStack(CrocThread* t_)
	{
		auto t = Thread::from(t_);

		printf("\n-----Call Stack-----\n");

		for(auto &ar: t->actRecs.slice(0, t->arIndex).reverse())
		{
			if(ar.func == nullptr)
				printf("Record ???\n");
			else
				printf("Record %s\n", ar.func->name->toCString());

			printf("\tBase: %u\n", ar.base);
			printf("\tSaved Top: %u\n", ar.savedTop);
			printf("\tVararg Base: %u\n", ar.vargBase);
			printf("\tReturns Slot: %u\n", ar.returnSlot);
			printf("\tExpected results: %u\n", ar.expectedResults);
			printf("\tNative call depth incd: %s\n", ar.incdNativeDepth ? "true" : "false");
		}

		printf("\n");
	}
}
}