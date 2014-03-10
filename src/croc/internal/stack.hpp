#ifndef CROC_INTERNAL_STACK_HPP
#define CROC_INTERNAL_STACK_HPP

#include "croc/types/base.hpp"

namespace croc
{
	void       checkStack   (Thread* t, AbsStack idx);
	RelStack   fakeToRel    (Thread* t, word fake);
	AbsStack   fakeToAbs    (Thread* t, word fake);
	word       push         (Thread* t, Value val);
	word       pushCrocstr  (CrocThread* t, crocstr s);
	Value*     getValue     (Thread* t, word slot);
	String*    getStringObj (Thread* t, word slot);
	crocstr    getCrocstr   (Thread* t, word slot);
	Weakref*   getWeakref   (Thread* t, word slot);
	Table*     getTable     (Thread* t, word slot);
	Namespace* getNamespace (Thread* t, word slot);
	Array*     getArray     (Thread* t, word slot);
	Memblock*  getMemblock  (Thread* t, word slot);
	Function*  getFunction  (Thread* t, word slot);
	Funcdef*   getFuncdef   (Thread* t, word slot);
	Class*     getClass     (Thread* t, word slot);
	Instance*  getInstance  (Thread* t, word slot);
	Thread*    getThread    (Thread* t, word slot);
}

#endif