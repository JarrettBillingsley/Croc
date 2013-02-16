#ifndef CROC_TYPES_ARRAY_HPP
#define CROC_TYPES_ARRAY_HPP

#include "croc/base/memory.hpp"
#include "croc/types.hpp"

namespace croc
{
	namespace array
	{
		Array* create(Memory& alloc, uword size);
		void free(Memory& alloc, Array* a);
		void resize(Memory& alloc, Array* a, uword newSize);
		Array* slice(Memory& alloc, Array* a, uword lo, uword hi);
		void sliceAssign(Memory& alloc, Array* a, uword lo, uword hi, Array* other);
		void sliceAssign(Memory& alloc, Array* a, uword lo, uword hi, DArray<Value> other);
		void setBlock(Memory& alloc, Array* a, uword block, DArray<Value> data);
		void fill(Memory& alloc, Array* a, Value val);
		void idxa(Memory& alloc, Array* a, uword idx, Value val);
		bool contains(Array* a, Value& v);
		Array* cat(Memory& alloc, Array* a, Array* b);
		Array* cat(Memory& alloc, Array* a, Value* v);
		void append(Memory& alloc, Array* a, Value* v);
	}
}

#endif