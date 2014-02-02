#ifndef CROC_TYPES_WEAKREF_HPP
#define CROC_TYPES_WEAKREF_HPP

#include "croc/types.hpp"

namespace croc
{
	namespace weakref
	{
		Weakref* create(VM* vm, GCObject* obj);
		Value makeref(VM* vm, Value val);
		void free(VM* vm, Weakref* r);
		GCObject* getObj(VM* vm, Weakref* r);
	}
}

#endif