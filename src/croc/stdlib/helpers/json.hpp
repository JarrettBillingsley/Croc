#ifndef CROC_STDLIB_HELPERS_JSON_HPP
#define CROC_STDLIB_HELPERS_JSON_HPP

#include <functional>

#include "croc/api.h"
#include "croc/types/base.hpp"

namespace croc
{
	word_t fromJSON(CrocThread* t, crocstr source);
	void toJSON(CrocThread* t, word_t root, bool pretty, std::function<void(crocstr)> output, std::function<void()> nl);
}

#endif