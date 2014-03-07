#ifndef CROC_INTERNAL_BASIC_HPP
#define CROC_INTERNAL_BASIC_HPP

#include "croc/types/base.hpp"

namespace croc
{
	bool validIndices(crocint lo, crocint hi, uword len);
	bool correctIndices(crocint& loIndex, crocint& hiIndex, Value lo, Value hi, uword len);
	word toStringImpl(Thread* t, Value v, bool raw);
	word pushFullNamespaceName(Thread* t, Namespace* ns);
	word pushTypeStringImpl(Thread* t, Value v);
	bool inImpl(Thread* t, Value item, Value container);
	crocint cmpImpl(Thread* t, Value a, Value b);
	bool switchCmpImpl(Thread* t, Value a, Value b);
	bool equalsImpl(Thread* t, Value a, Value b);
	void idxImpl(Thread* t, AbsStack dest, Value container, Value key);
	void tableIdxImpl(Thread* t, AbsStack dest, Table* container, Value key);
	void idxaImpl(Thread* t, AbsStack container, Value key, Value value);
	void tableIdxaImpl(Thread* t, Table* container, Value key, Value value);
	void sliceImpl(Thread* t, AbsStack dest, Value src, Value lo, Value hi);
	void sliceaImpl(Thread* t, Value container, Value lo, Value hi, Value value);
	void fieldImpl(Thread* t, AbsStack dest, Value container, String* name, bool raw);
	void fieldaImpl(Thread* t, AbsStack container, String* name, Value value, bool raw);
	void lenImpl(Thread* t, AbsStack dest, Value src);
	void lenaImpl(Thread* t, Value dest, Value len);
	void catImpl(Thread* t, AbsStack dest, AbsStack firstSlot, uword num);
	void arrayConcat(Thread* t, DArray<Value> vals, uword len);
	void stringConcat(Thread* t, Value first, DArray<Value> vals, uword len, uword cpLen);
	void catEqImpl(Thread* t, AbsStack dest, AbsStack firstSlot, uword num);
	void arrayAppend(Thread* t, Array* a, DArray<Value> vals);
	Value superOfImpl(Thread* t, Value v);
}

#endif