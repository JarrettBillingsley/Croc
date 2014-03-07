#ifndef CROC_INTERNAL_CLASS_HPP
#define CROC_INTERNAL_CLASS_HPP

#include "croc/types/base.hpp"

namespace croc
{
	void classDeriveImpl(Thread* t, Class* c, Class* base);
	void freezeImpl(Thread* t, Class* c);
}

#endif