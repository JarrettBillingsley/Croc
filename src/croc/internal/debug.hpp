#ifndef CROC_INTERNAL_DEBUG_HPP
#define CROC_INTERNAL_DEBUG_HPP

#include "croc/types.hpp"

namespace croc
{
	ActRecord* getActRec(Thread* t, uword depth);
	word pcToLine(ActRecord* ar, Instruction* pc);
	word getDebugLine(Thread* t, uword depth = 0);
	word pushDebugLoc(Thread* t, ActRecord* ar = nullptr);
}

#endif