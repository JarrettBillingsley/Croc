#ifndef CROC_INTERNAL_CALLS_HPP
#define CROC_INTERNAL_CALLS_HPP

#include "croc/types.hpp"

namespace croc
{
	Namespace* getEnv(Thread* t, uword depth = 0);
}

#endif