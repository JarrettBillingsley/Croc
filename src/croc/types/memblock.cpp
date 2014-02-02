#include <string.h>

#include "croc/types/memblock.hpp"

namespace croc
{
	namespace memblock
	{
		// Create a new memblock object of the given length.
		Memblock* create(Memory& mem, uword itemLength)
		{
			auto ret = ALLOC_OBJ_ACYC(mem, Memblock);
			ret->data = DArray<uint8_t>::alloc(mem, itemLength);
			ret->ownData = true;
			return ret;
		}

		// Create a new memblock object that only views the given array, but does not own that data.
		Memblock* createView(Memory& mem, DArray<uint8_t> data)
		{
			auto ret = ALLOC_OBJ_ACYC(mem, Memblock);
			ret->data = data;
			ret->ownData = false;
			return ret;
		}

		// Free a memblock object.
		void free(Memory& mem, Memblock* m)
		{
			if(m->ownData)
				m->data.free(mem);

			FREE_OBJ(mem, Memblock, m);
		}

		// Change a memblock so it's a view into a given array (but does not own it).
		void view(Memory& mem, Memblock* m, DArray<uint8_t> data)
		{
			if(m->ownData)
				m->data.free(mem);

			m->data = data;
			m->ownData = false;
		}

		// Resize a memblock object.
		void resize(Memory& mem, Memblock* m, uword newLength)
		{
			assert(m->ownData);
			m->data.resize(mem, newLength);
		}

		// Slice a memblock object to create a new memblock object with its own data.
		Memblock* slice(Memory& mem, Memblock* m, uword lo, uword hi)
		{
			auto n = ALLOC_OBJ_ACYC(mem, Memblock);
			n->data = m->data.slice(lo, hi).dup(mem);
			n->ownData = true;
			return n;
		}

		// Assign an entire other memblock into a slice of the destination memblock. Handles overlapping copies as well.
		void sliceAssign(Memblock* m, uword lo, uword hi, Memblock* other)
		{
			auto dest = m->data.slice(lo, hi);
			auto src = other->data;

			assert(dest.length == src.length);

			auto len = dest.length;

			if((dest.ptr + len) <= src.ptr || (src.ptr + len) <= dest.ptr)
				memcpy(dest.ptr, src.ptr, len);
			else
				memmove(dest.ptr, src.ptr, len);
		}

		// Returns a new memblock that is the concatenation of the two source memblocks.
		Memblock* cat(Memory& mem, Memblock* a, Memblock* b)
		{
			auto ret = create(mem, a->data.length + b->data.length);
			auto split = a->data.length;
			ret->data.slicea(0, split, a->data);
			ret->data.slicea(split, ret->data.length, b->data);
			return ret;
		}
	}
}
