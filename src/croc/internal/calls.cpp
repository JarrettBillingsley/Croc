
#include "croc/api.h"
#include "croc/base/metamethods.hpp"
#include "croc/internal/basic.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/class.hpp"
#include "croc/internal/debug.hpp"
#include "croc/internal/interpreter.hpp"
#include "croc/internal/stack.hpp"
#include "croc/internal/thread.hpp"
#include "croc/internal/eh.hpp"

namespace croc
{
	Namespace* getEnv(Thread* t, uword depth)
	{
		if(t->arIndex == 0)
			return t->vm->globals;
		else if(depth == 0)
			return t->currentAR->func->environment;

		for(word idx = t->arIndex - 1; idx >= 0; idx--)
		{
			if(depth == 0)
				return t->actRecs[cast(uword)idx].func->environment;
			else if(depth <= t->actRecs[cast(uword)idx].numTailcalls)
				croc_eh_throwStd(*t, "RuntimeError",
					"Attempting to get environment of function whose activation record was overwritten by a tail call");

			depth -= (t->actRecs[cast(uword)idx].numTailcalls + 1);
		}

		return t->vm->globals;
	}

	Value lookupMethod(Thread* t, Value v, String* name)
	{
		switch(v.type)
		{
			case CrocType_Class:
				if(auto ret = v.mClass->getMethod(name))
					return *ret;
				else
					return Value::nullValue;

			case CrocType_Instance:
				return getInstanceMethod(t, v.mInstance, name);

			case CrocType_Namespace:
				if(auto ret = v.mNamespace->get(name))
					return *ret;
				else
					return Value::nullValue;

			case CrocType_Table:
				if(auto ret = v.mTable->get(Value::from(name)))
					return *ret;
				// fall through
			default:
				return getGlobalMetamethod(t, v.type, name);
		}
	}

	Value getInstanceMethod(Thread* t, Instance* inst, String* name)
	{
		(void)t;
		if(auto ret = inst->getMethod(name))
			return *ret;
		else
			return Value::nullValue;
	}

	Value getGlobalMetamethod(Thread* t, CrocType type, String* name)
	{
		if(auto mt = getMetatable(t, type))
		{
			if(auto ret = mt->get(name))
				return *ret;
		}

		return Value::nullValue;
	}

	Function* getMM(Thread* t, Value obj, Metamethod method)
	{
		auto name = t->vm->metaStrings[method];
		Value ret;

		if(obj.type == CrocType_Instance)
			ret = getInstanceMethod(t, obj.mInstance, name);
		else
			ret = getGlobalMetamethod(t, obj.type, name);

		if(ret.type == CrocType_Function)
			return ret.mFunction;

		return nullptr;
	}

	Namespace* getMetatable(Thread* t, CrocType type)
	{
		assert(type >= CrocType_FirstUserType && type <= CrocType_LastUserType);
		return t->vm->metaTabs[type];
	}

	void closeUpvals(Thread* t, AbsStack index)
	{
		auto base = &t->stack[index];

		for(auto uv = t->upvalHead; uv != nullptr && uv->value >= base; uv = t->upvalHead)
		{
			t->upvalHead = uv->nextuv;
			uv->closedValue = *uv->value;
			uv->value = &uv->closedValue;
		}
	}

	Upval* findUpval(Thread* t, uword num)
	{
		auto slot = &t->stack[t->currentAR->base + num];
		auto puv = &t->upvalHead;

		for(auto uv = *puv; uv != nullptr && uv->value >= slot; puv = &uv->nextuv, uv = *puv)
			if(uv->value == slot)
				return uv;

		auto ret = ALLOC_OBJ(t->vm->mem, Upval);
		ret->type = CrocType_Upval;
		ret->value = slot;
		ret->nextuv = *puv;
		*puv = ret;
		return ret;
	}

	ActRecord* pushAR(Thread* t)
	{
		if(t->arIndex >= t->actRecs.length)
			t->actRecs.resize(t->vm->mem, t->actRecs.length * 2);

		t->currentAR = &t->actRecs[t->arIndex];
		t->arIndex++;
		return t->currentAR;
	}

	// TODO: move this somewhere else
	void makeDead(Thread* t)
	{
		t->state = CrocThreadState_Dead;
		t->shouldHalt = false;
	}

	void popARTo(Thread* t, uword removeTo)
	{
		uword numResultsToPop = 0;

		for(uword i = removeTo; i < t->arIndex; i++)
			numResultsToPop += t->actRecs[i].numResults;

		assert(numResultsToPop <= t->resultIndex);
		t->resultIndex -= numResultsToPop;

		closeUpvals(t, t->actRecs[removeTo].base);
		t->arIndex = removeTo;
		unwindThisFramesEH(t);

		if(removeTo == 0)
		{
			makeDead(t);
			t->currentAR = nullptr;
			t->stackBase = 0;
			t->stackIndex = 1;
			t->numYields = 0;
		}
		else
		{
			t->currentAR = &t->actRecs[t->arIndex - 1];
			t->stackBase = t->currentAR->base;
		}
	}

	void callEpilogue(Thread* t)
	{
		if(t->hooks & CrocThreadHook_Ret)
			callHook(t, CrocThreadHook_Ret);

		// Get results before popARTo takes them away
		auto destSlot = t->currentAR->returnSlot;
		auto expectedResults = t->currentAR->expectedResults;
		auto results = loadResults(t);

		// Pop the act record (which also closes upvals and removes EH frames)
		popARTo(t, t->arIndex - 1);

		// Copy and adjust results
		bool isMultRet = expectedResults == -1;
		auto actualResults = results.length;

		if(isMultRet)
			expectedResults = actualResults;

		auto stk = t->stack;
		auto slotAfterRets = destSlot + expectedResults;

		if(cast(uword)expectedResults <= actualResults)
			stk.slicea(destSlot, slotAfterRets, results.slice(0, expectedResults));
		else
		{
			stk.slicea(destSlot, destSlot + actualResults, results);
			stk.slice(destSlot + actualResults, slotAfterRets).fill(Value::nullValue);
		}

		t->numYields = actualResults;

		// Set stack index appropriately
		if(t->arIndex == 0 || isMultRet || t->currentAR->savedTop < slotAfterRets) // last case happens in native -> native calls
			t->stackIndex = slotAfterRets;
		else
			t->stackIndex = t->currentAR->savedTop;

		assert(t->stackIndex > 0);
	}

	void saveResults(Thread* t, Thread* from, AbsStack first, uword num)
	{
		if(num == 0)
			return;

		if((t->results.length - t->resultIndex) < num)
		{
			auto newLen = t->results.length * 2;

			if(newLen - t->resultIndex < num)
				newLen = t->resultIndex + num;

			t->results.resize(t->vm->mem, newLen);
		}

		assert(t->currentAR->firstResult == 0 && t->currentAR->numResults == 0);

		t->results.slicea(t->resultIndex, t->resultIndex + num, from->stack.slice(first, first + num));
		t->currentAR->firstResult = t->resultIndex;
		t->currentAR->numResults = num;
		t->resultIndex += num;
	}

	DArray<Value> loadResults(Thread* t)
	{
		auto first = t->currentAR->firstResult;
		auto num = t->currentAR->numResults;
		auto ret = t->results.slice(first, first + num);
		t->currentAR->firstResult = 0;
		t->currentAR->numResults = 0;
		t->resultIndex -= num;
		return ret;
	}

	bool callPrologue(Thread* t, AbsStack slot, word expectedResults, uword numParams, bool isTailcall)
	{
		assert(numParams > 0);
		auto func = t->stack[slot];

		switch(func.type)
		{
			case CrocType_Function:
				return funcCallPrologue(t, func.mFunction, slot, expectedResults, slot + 1, numParams, isTailcall);

			case CrocType_Class: {
				auto cls = func.mClass;

				if(!cls->isFrozen)
					freezeImpl(t, cls);

				if(cls->constructor == nullptr && numParams > 1)
					croc_eh_throwStd(*t, "ParamError",
						"Class '%s' has no constructor but was called with %" CROC_SIZE_T_FORMAT " parameters",
						cls->name->toCString(), numParams - 1);

				auto inst = Instance::create(t->vm->mem, cls);

				// call any constructor
				if(cls->constructor)
				{
					t->stack[slot] = Value::from(cls->constructor->mFunction);
					t->stack[slot + 1] = Value::from(inst);

					// TODO: remove the native call from class ctor calls

					t->nativeCallDepth++;

					if(callPrologue(t, slot, 0, numParams))
						execute(t, t->arIndex);

					t->nativeCallDepth--;
				}

				t->stack[slot] = Value::from(inst);

				// TODO: my god stop fucking duplicating code, me
				// besides, shouldn't this all have been handled by callEpilogue...?
				if(expectedResults == -1)
					t->stackIndex = slot + 1;
				else
				{
					if(expectedResults > 1)
						t->stack.slice(slot + 1, slot + expectedResults).fill(Value::nullValue);

					if(t->arIndex == 0)
					{
						t->state = CrocThreadState_Dead;
						t->shouldHalt = false;
						t->stackIndex = slot + expectedResults;

						if(t == t->vm->mainThread)
							t->vm->curThread = t;
					}
					else if(t->currentAR->savedTop < slot + expectedResults)
						t->stackIndex = slot + expectedResults;
					else
						t->stackIndex = t->currentAR->savedTop;
				}

				return false;
			}
			case CrocType_Thread: {
				auto thread = func.mThread;

				if(thread == t)
					croc_eh_throwStd(*t, "RuntimeError", "Thread attempting to resume itself");

				if(thread == t->vm->mainThread)
					croc_eh_throwStd(*t, "RuntimeError", "Attempting to resume VM's main thread");

				if(thread->state != CrocThreadState_Initial && thread->state != CrocThreadState_Suspended)
					croc_eh_throwStd(*t, "StateError", "Attempting to resume a %s thread",
						ThreadStateStrings[thread->state]);

				resume(thread, t, slot, expectedResults, numParams);
				return false;
			}
			default:
				if(auto method = getMM(t, func, MM_Call))
				{
					t->stack[slot] = Value::from(method);
					t->stack[slot + 1] = func;
					return funcCallPrologue(t, method, slot, expectedResults, slot + 1, numParams);
				}
				else
				{
					pushTypeStringImpl(t, func);
					return croc_eh_throwStd(*t, "TypeError", "No implementation of %s for type '%s'", MetaNames[MM_Call],
						croc_getString(*t, -1));
				}
		}
	}

	bool funcCallPrologue(Thread* t, Function* func, AbsStack returnSlot, word expectedResults, AbsStack paramSlot,
		uword numParams, bool isTailcall)
	{
		if(numParams > func->maxParams)
			croc_eh_throwStd(*t, "ParamError",
				"Function %s expected at most %" CROC_SIZE_T_FORMAT " parameters but was given %" CROC_SIZE_T_FORMAT,
				func->name->toCString(), func->maxParams - 1, numParams - 1);

		if(!func->isNative)
		{
			// Script function
			auto funcdef = func->scriptFunc;
			auto ar = isTailcall ? t->currentAR : pushAR(t);

			if(isTailcall)
			{
				assert(ar && ar->func && !ar->func->isNative);
				assert(paramSlot == returnSlot + 1);

				closeUpvals(t, ar->base);
				ar->numTailcalls++;
				memmove(&t->stack[ar->returnSlot], &t->stack[returnSlot], sizeof(Value) * (numParams + 1));
				returnSlot = ar->returnSlot;
				paramSlot = returnSlot + 1;
			}

			if(funcdef->isVararg && numParams > func->numParams)
			{
				// In this case, we move the formal parameters after the varargs and null out where the formal
				// params used to be.
				ar->base = paramSlot + numParams;
				ar->vargBase = paramSlot + func->numParams;
				checkStack(t, ar->base + funcdef->stackSize - 1);
				auto oldParams = t->stack.slice(paramSlot, paramSlot + func->numParams);
				t->stack.slicea(ar->base, ar->base + func->numParams, oldParams);
				oldParams.fill(Value::nullValue);

				// For nulling out the stack.
				numParams = func->numParams;
			}
			else
			{
				// In this case, everything is where it needs to be already.
				ar->base = paramSlot;
				ar->vargBase = paramSlot;
				checkStack(t, ar->base + funcdef->stackSize - 1);
				// If we have too few params, the extra param slots will be nulled out.
			}

			// Null out the stack frame after the parameters.
			t->stack.slice(ar->base + numParams, ar->base + funcdef->stackSize).fill(Value::nullValue);

			// Fill in the rest of the activation record.
			ar->returnSlot = returnSlot;
			ar->func = func;
			ar->pc = funcdef->code.ptr;
			ar->firstResult = 0;
			ar->numResults = 0;
			ar->savedTop = ar->base + funcdef->stackSize;
			ar->unwindCounter = 0;
			ar->unwindReturn = nullptr;

			if(!isTailcall)
			{
				ar->expectedResults = expectedResults;
				ar->numTailcalls = 0;
			}

			// Set the stack indices.
			t->stackBase = ar->base;
			t->stackIndex = ar->savedTop;

			// Call any hook.
			if(t->hooks & CrocThreadHook_Call)
				callHook(t, isTailcall ? CrocThreadHook_TailCall : CrocThreadHook_Call);

			return true;
		}
		else
		{
			// Native function
			t->stackIndex = paramSlot + numParams;
			checkStack(t, t->stackIndex);

			auto ar = pushAR(t);

			ar->base = paramSlot;
			ar->vargBase = paramSlot;
			ar->returnSlot = returnSlot;
			ar->func = func;
			ar->expectedResults = expectedResults;
			ar->firstResult = 0;
			ar->numResults = 0;
			ar->savedTop = t->stackIndex;
			ar->numTailcalls = 0;
			ar->unwindCounter = 0;
			ar->unwindReturn = nullptr;

			t->stackBase = ar->base;

			if(t->hooks & CrocThreadHook_Call)
				callHook(t, CrocThreadHook_Call);

			t->vm->curThread = t;
			t->nativeCallDepth++;
			auto savedState = t->state;
			t->state = CrocThreadState_Running;
			uword actualReturns = func->nativeFunc(*t);
			t->state = savedState;
			t->nativeCallDepth--;

			saveResults(t, t, t->stackIndex - actualReturns, actualReturns);
			callEpilogue(t);
			return false;
		}
	}

	uword commonCall(Thread* t, AbsStack slot, word numReturns, bool isScript)
	{
		if(isScript)
		{
			t->nativeCallDepth++;
			execute(t, t->arIndex);
			t->nativeCallDepth--;
		}

		uword ret;

		if(numReturns == -1)
			ret = t->stackIndex - slot;
		else
		{
			t->stackIndex = slot + numReturns;
			ret = numReturns;
		}

		croc_gc_maybeCollect(*t);
		return ret;
	}

	bool methodCallPrologue(Thread* t, AbsStack slot, Value self, String* methodName, word numReturns, uword numParams,
		bool isTailcall)
	{
		auto method = lookupMethod(t, self, methodName);

		// Idea is like this:

		// If we're calling the real method, the object is moved to the 'this' slot and the method takes its place.

		// If we're calling opMethod, the object is left where it is (or the custom context is moved to its place),
		// the method name goes where the context was, and we use callPrologue2 with a closure that's not on the stack.

		if(method.type != CrocType_Null)
		{
			t->stack[slot] = method;
			t->stack[slot + 1] = self;
			return callPrologue(t, slot, numReturns, numParams, isTailcall);
		}
		else
		{
			if(auto mm = getMM(t, self, MM_Method))
			{
				t->stack[slot] = self;
				t->stack[slot + 1] = Value::from(methodName);
				return funcCallPrologue(t, mm, slot, numReturns, slot, numParams + 1, isTailcall);
			}
			else
			{
				pushTypeStringImpl(t, self);
				return croc_eh_throwStd(*t, "MethodError", "No implementation of method '%s' or %s for type '%s'",
					methodName->toCString(), MetaNames[MM_Method], croc_getString(*t, -1));
			}
		}
	}

	// I *could* come up with some way to get rid of all the boilerplate but eh, I don't feel like dealing with C++
	// template "magic" or whatever
#define TRYMM_BEGIN()\
	auto method = getMM(t, src1, mm);\
\
	if(method == nullptr)\
		return false;\
\
	auto funcSlot = push(t, Value::from(method)) + t->stackBase;

	bool tryMMDest(Thread* t, Metamethod mm, AbsStack dest, Value src1)
	{
		TRYMM_BEGIN();
		push(t, src1);
		commonCall(t, funcSlot, 1, callPrologue(t, funcSlot, 1, 1));
		t->stack[dest] = t->stack[--t->stackIndex];
		return true;
	}

	bool tryMMDest(Thread* t, Metamethod mm, AbsStack dest, Value src1, Value src2)
	{
		TRYMM_BEGIN();
		push(t, src1);
		push(t, src2);
		commonCall(t, funcSlot, 1, callPrologue(t, funcSlot, 1, 2));
		t->stack[dest] = t->stack[--t->stackIndex];
		return true;
	}

	bool tryMMDest(Thread* t, Metamethod mm, AbsStack dest, Value src1, Value src2, Value src3)
	{
		TRYMM_BEGIN();
		push(t, src1);
		push(t, src2);
		push(t, src3);
		commonCall(t, funcSlot, 1, callPrologue(t, funcSlot, 1, 3));
		t->stack[dest] = t->stack[--t->stackIndex];
		return true;
	}

	bool tryMM(Thread* t, Metamethod mm, Value src1, Value src2)
	{
		TRYMM_BEGIN();
		push(t, src1);
		push(t, src2);
		commonCall(t, funcSlot, 0, callPrologue(t, funcSlot, 0, 2));
		return true;
	}

	bool tryMM(Thread* t, Metamethod mm, Value src1, Value src2, Value src3)
	{
		TRYMM_BEGIN();
		push(t, src1);
		push(t, src2);
		push(t, src3);
		commonCall(t, funcSlot, 0, callPrologue(t, funcSlot, 0, 3));
		return true;
	}

	bool tryMM(Thread* t, Metamethod mm, Value src1, Value src2, Value src3, Value src4)
	{
		TRYMM_BEGIN();
		push(t, src1);
		push(t, src2);
		push(t, src3);
		push(t, src4);
		commonCall(t, funcSlot, 0, callPrologue(t, funcSlot, 0, 4));
		return true;
	}
}