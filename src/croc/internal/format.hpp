#ifndef CROC_INTERNAL_FORMAT_HPP
#define CROC_INTERNAL_FORMAT_HPP

#include <functional>

#include "croc/types/base.hpp"

namespace croc
{
	uword formatImpl(CrocThread* t, uword numParams);
	uword formatImpl(CrocThread* t, uword startIndex, uword numParams);
}

#endif