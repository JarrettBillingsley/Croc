#ifndef CROC_INTERNAL_INTERPRETER_HPP
#define CROC_INTERNAL_INTERPRETER_HPP

#include "croc/types/base.hpp"

namespace croc
{
	void execute(Thread* t, uword startARIndex);
}

#endif