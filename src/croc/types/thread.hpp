#ifndef CROC_TYPES_THREAD_HPP
#define CROC_TYPES_THREAD_HPP

#include "croc/types.hpp"

namespace croc
{
	namespace thread
	{
		Thread* create(VM* vm);
		Thread* createPartial(VM* vm);
		Thread* create(VM* vm, Function* coroFunc);
		void free(Thread* t);
		void reset(Thread* t);
		void setHookFunc(Memory& mem, Thread* t, Function* f);
		void setCoroFunc(Memory& mem, Thread* t, Function* f);
	}
}

#endif