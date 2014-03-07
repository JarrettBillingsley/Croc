#ifndef CROC_INTERNAL_VARIABLES_HPP
#define CROC_INTERNAL_VARIABLES_HPP

#include "croc/types/base.hpp"

namespace croc
{
	Value getGlobalImpl(Thread* t, String* name, Namespace* env);
	void setGlobalImpl(Thread* t, String* name, Namespace* env, Value val);
	void newGlobalImpl(Thread* t, String* name, Namespace* env, Value val);
}

#endif