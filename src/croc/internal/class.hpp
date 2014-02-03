#ifndef CROC_INTERNAL_CLASS_HPP
#define CROC_INTERNAL_CLASS_HPP

#include "croc/types.hpp"

namespace croc
{
	Value superOfImpl(Thread* t, Value* v);
	void classDeriveImpl(Thread* t, Class* c, Class* base);
	void freezeImpl(Thread* t, Class* c);
}

#endif