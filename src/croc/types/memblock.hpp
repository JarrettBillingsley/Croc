#ifndef CROC_TYPES_MEMBLOCK_HPP
#define CROC_TYPES_MEMBLOCK_HPP

#include "croc/types.hpp"

namespace croc
{
	namespace memblock
	{
		Memblock* create(Memory& mem, uword itemLength);
		Memblock* createView(Memory& mem, DArray<uint8_t> data);
		void free(Memory& mem, Memblock* m);
		void view(Memory& mem, Memblock* m, DArray<uint8_t> data);
		void resize(Memory& mem, Memblock* m, uword newLength);
		Memblock* slice(Memory& mem, Memblock* m, uword lo, uword hi);
		void sliceAssign(Memblock* m, uword lo, uword hi, Memblock* other);
		Memblock* cat(Memory& mem, Memblock* a, Memblock* b);
	}
}

#endif