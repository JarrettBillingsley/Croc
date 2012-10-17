#ifndef CROC_TYPES_ARRAY_HPP
#define CROC_TYPES_ARRAY_HPP

#include "croc/base/alloc.hpp"
#include "croc/types.hpp"

namespace croc
{
	namespace array
	{
		Array* create(Allocator& alloc, uword size);
		void free(Allocator& alloc, Array* a);
		void resize(Allocator& alloc, Array* a, uword newSize);
		Array* slice(Allocator& alloc, Array* a, uword lo, uword hi);
		void sliceAssign(Allocator& alloc, Array* a, uword lo, uword hi, Array* other);
		void sliceAssign(Allocator& alloc, Array* a, uword lo, uword hi, DArray<Value> other);
		void setBlock(Allocator& alloc, Array* a, uword block, DArray<Value> data);
		void fill(Allocator& alloc, Array* a, Value val);
		void idxa(Allocator& alloc, Array* a, uword idx, Value val);
		bool contains(Array* a, Value& v);
		Array* cat(Allocator& alloc, Array* a, Array* b);
		Array* cat(Allocator& alloc, Array* a, Value* v);
		void append(Allocator& alloc, Array* a, Value* v);
	}
}

#endif