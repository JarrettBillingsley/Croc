#ifndef CROC_STDLIB_HELPERS_FORMAT_HPP
#define CROC_STDLIB_HELPERS_FORMAT_HPP

#include <functional>

#include "croc/types/base.hpp"

namespace croc
{
	uword formatImpl(CrocThread* t, uword numParams);
	uword formatImpl(CrocThread* t, uword startIndex, uword numParams);
}

#endif