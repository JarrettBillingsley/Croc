
#include "croc/api.h"
#include "croc/base/metamethods.hpp"
#include "croc/internal/calls.hpp"
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
					return ret->value;
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
			return ret->value;
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
		// ORDER CROCTYPE
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

	// void popAR(Thread* t)
	// {
	// 	t->arIndex--;
	// 	t->currentAR->func = nullptr;

	// 	if(t->arIndex > 0)
	// 	{
	// 		t->currentAR = &t->actRecs[t->arIndex - 1];
	// 		t->stackBase = t->currentAR->base;
	// 	}
	// 	else
	// 	{
	// 		t->currentAR = nullptr;
	// 		t->stackBase = 0;
	// 	}
	// }

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

		auto ar = &t->actRecs[removeTo];
		t->arIndex = removeTo;
		closeUpvals(t, ar->base);
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
}