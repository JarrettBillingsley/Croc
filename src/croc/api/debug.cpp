
#include <stdio.h>

#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** Sets the thread's <em>hook function</em>, which is a special function called at certain points during program
	execution which allows you to trace execution and inspect the internals of the program as it runs. This can be used
	to make a debugger.

	This expects the hook function to be on top of the stack. It can be either a function closure or \c null to remove
	the hook function instead. The hook function is popped.

	There are four places the hook function can be called:

	- When any function is called, right after its stack frame has been set up, but before the function begins
		execution;
	- When any function returns, right after the last instruction has executed, but before its stack frame is torn down;
	- At a new line of source code;
	- After every \a n bytecode instructions have been executed.

	There is only one hook function, and it will be called for any combination of these events that you specify; it's up
	to the hook function to see what kind of event it is and respond appropriately.

	This hook function (as well as the mask and delay) is inherited by any new threads which the given thread creates
	after the hook was set.

	While the hook function is being run, no hooks will be called (obviously, or else it would result in infinite
	recursion). When the hook function returns, execution will resume as normal until the hook function is called again.

	You cannot yield from within the hook function.

	\par The hook function
	When the hook function is called, the thread being hooked will be passed as \c this (since you could possibly set
	the same hook function to multiple threads) and the type of the hook event will be a string, its only parameter.
	This string can be one of the following values:

	- \c "call" for normal function calls.
	- \c "tailcall" which is the same as \c "call" except there will not be a corresponding \c "return" when this
		function returns (or more precisely, the \a previously called function will not have a \c "return" event).
	- \c "return" for when a function is about to return.
	- \c "line" for when execution reaches a new line of source code.
	- \c "delay" for when a certain number of bytecode instructions have been executed.

	\param mask
		controls which of the following events the hook function will be called for. It should be an
		or-ing together of the \ref CrocThreadHook enum values. Note that if you use either one of \ref
		CrocThreadHook_Call or \ref CrocThreadHook_TailCall, you will get both kinds of call events. Also, the
		\ref CrocThreadHook_Delay flag isn't controlled by this mask, but by the \c hookDelay parameter. <br>
		<br>
		If this parameter is 0, the hook function is removed from the thread.

	\param hookDelay controls whether or not the hook function will be called for \c "delay" events. If this parameter
		is 0, it won't be. Otherwise, it indicates how often the \c "delay" hook event will occur. A value of 1 means
		it will occur after every bytecode instruction; a value of 2 means every other instruction, and so on. */
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

	/** Pushes the given thread's hook function onto its stack, or \c null if none is set on that thread. */
	word_t croc_debug_pushHookFunc(CrocThread* t_)
	{
		auto t = Thread::from(t_);

		if(t->hookFunc == nullptr)
			return croc_pushNull(t_);
		else
			return push(t, Value::from(t->hookFunc));
	}

	/** Gets the hook mask of the given thread (like was set with \ref croc_debug_setHookFunc), or 0 if there is no hook
	set on that thread. */
	uword_t croc_debug_getHookMask(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		return t->hooks;
	}

	/** Gets the hook delay of the given thread (like was set with \ref croc_debug_setHookFunc), or 0 if there is no
	delay hook on that thread. */
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
				if(t->stack[i].type >= CrocType_FirstUserType && t->stack[i].type <= CrocType_LastUserType)
				{
					croc_pushToStringRaw(*t, i);
					croc_pushTypeString(*t, i);
					printf("[%3" CROC_SIZE_T_FORMAT ":%4" CROC_SSIZE_T_FORMAT "]: '%s': %s\n",
						i, cast(word)i - cast(word)tmp, croc_getString(*t, -2), croc_getString(*t, -1));
					croc_pop(*t, 2);
				}
				else
					printf("[%3" CROC_SIZE_T_FORMAT ":%4" CROC_SSIZE_T_FORMAT "]: %.16" CROC_HEX64_FORMAT ": %u\n",
						i, cast(word)i - cast(word)tmp, *cast(uint64_t*)&t->stack[i].mInt, t->stack[i].type);
			}

			t->stackBase = tmp;
			printf("\n");
		}
	}

	/** Prints out the contents of the current function's stack frame to standard output in the following format:

	\verbatim
[xxx:yyyy] val: type
	\endverbatim

	Where \c xxx is the absolute stack index (within the thread's entire stack), yyyy is the stack index relative to
	the current function's stack frame, val is a raw string representation of the value, and type is its type. */
	void croc_debug_printStack(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		printStackImpl(t, false);
	}

	/** Same as \ref croc_debug_printStack, but prints the thread's \a whole stack, for all stack frames. In this case
	the relative stack indexes can be negative, which means that the slot is in a previous stack frame. */
	void croc_debug_printWholeStack(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		printStackImpl(t, true);
	}

	/** Prints out the thread's call stack to standard output in reverse, starting with the currently-executing
	function, in the following format:

	\verbatim
Record <name>:
	Base: <base>
	Saved top: <top>
	Vararg base: <vargBase>
	Return slot: <retSlot>
	Expected results: <numResults>
	\endverbatim

	Where \c name is the name of the function at that level (or ??? if there is no function at that level); \c base is
	the absolute stack index where this activation record's stack frame begins; \c top is the absolute stack index of
	the end of its stack frame (which may and often does overlap the next frame); \c vargBase is the absolute stack
	index of where its variadic arguments, if any, begin; \c retSlot is the absolute stack index where its return values
	will be copied upon returning to the calling function; and \c numResults is the number of results the calling
	function is expecting it to return (or -1 for "all of them").

	This only prints the current thread's call stack; it does not cross thread resume boundaries.*/
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

			printf("\tBase: %" CROC_SIZE_T_FORMAT "\n", ar.base);
			printf("\tSaved Top: %" CROC_SIZE_T_FORMAT "\n", ar.savedTop);
			printf("\tVararg Base: %" CROC_SIZE_T_FORMAT "\n", ar.vargBase);
			printf("\tReturn Slot: %" CROC_SIZE_T_FORMAT "\n", ar.returnSlot);
			printf("\tExpected results: %" CROC_SIZE_T_FORMAT "\n", ar.expectedResults);
		}

		printf("\n");
	}
}