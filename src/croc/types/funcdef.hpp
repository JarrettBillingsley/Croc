#ifndef CROC_TYPES_FUNCDEF_HPP
#define CROC_TYPES_FUNCDEF_HPP

#include "croc/types.hpp"

namespace croc
{
	namespace funcdef
	{
		Funcdef* create(Memory& mem);
		void free(Memory& mem, Funcdef* fd);
	}
}

#endif