#ifndef CROC_INTERNAL_CALLS_HPP
#define CROC_INTERNAL_CALLS_HPP

#include "croc/base/metamethods.hpp"
#include "croc/types.hpp"

namespace croc
{
	Namespace* getEnv(Thread* t, uword depth = 0);
	Value lookupMethod(Thread* t, Value v, String* name);
	Value getInstanceMethod(Thread* t, Instance* inst, String* name);
	Value getGlobalMetamethod(Thread* t, CrocType type, String* name);
	Function* getMM(Thread* t, Value obj, Metamethod method);
	Namespace* getMetatable(Thread* t, CrocType type);
}

#endif