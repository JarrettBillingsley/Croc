#ifndef CROC_INTERNAL_CALLS_HPP
#define CROC_INTERNAL_CALLS_HPP

#include "croc/base/metamethods.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	Namespace* getEnv(Thread* t, uword depth = 0);
	Value lookupMethod(Thread* t, Value v, String* name);
	Value getInstanceMethod(Thread* t, Instance* inst, String* name);
	Value getGlobalMetamethod(Thread* t, CrocType type, String* name);
	Function* getMM(Thread* t, Value obj, Metamethod method);
	Namespace* getMetatable(Thread* t, CrocType type);
	void closeUpvals(Thread* t, AbsStack index);
	Upval* findUpval(Thread* t, uword num);
	ActRecord* pushAR(Thread* t);
	// void popAR(Thread* t);
	void popARTo(Thread* t, uword removeTo);
	void callEpilogue(Thread* t);
	void saveResults(Thread* t, Thread* from, AbsStack first, uword num);
	DArray<Value> loadResults(Thread* t);
	bool callPrologue(Thread* t, AbsStack slot, word expectedResults, uword numParams);
	bool funcCallPrologue(Thread* t, Function* func, AbsStack returnSlot, word expectedResults, AbsStack paramSlot, uword numParams);
	uword commonCall(Thread* t, AbsStack slot, word numReturns, bool isScript);
	bool methodCallPrologue(Thread* t, AbsStack slot, Value self, String* methodName, word numReturns, uword numParams);
	bool tryMMDest(Thread* t, Metamethod mm, AbsStack dest, Value src1);
	bool tryMMDest(Thread* t, Metamethod mm, AbsStack dest, Value src1, Value src2);
	bool tryMMDest(Thread* t, Metamethod mm, AbsStack dest, Value src1, Value src2, Value src3);
	bool tryMM(Thread* t, Metamethod mm, Value src1, Value src2);
	bool tryMM(Thread* t, Metamethod mm, Value src1, Value src2, Value src3);
	bool tryMM(Thread* t, Metamethod mm, Value src1, Value src2, Value src3, Value src4);
}

#endif