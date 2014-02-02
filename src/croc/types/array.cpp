#include <string.h>

#include "croc/base/memory.hpp"
#include "croc/base/opcodes.hpp"
#include "croc/base/writebarrier.hpp"
#include "croc/types.hpp"
#include "croc/types/array.hpp"
#include "croc/utils.hpp"

#define ADDREF(slot)\
	do {\
	if((slot).value.isGCObject())\
		(slot).modified = true;\
	} while(false)

#define REMOVEREF(mem, slot)\
	do {\
		if(!(slot).modified && (slot).value.isGCObject())\
			(mem).decBuffer.add((mem), (slot).value.toGCObject());\
	} while(false)

#define ADDREFS(arr)\
	do {\
		for(auto &_slot: (arr))\
			ADDREF(_slot);\
	} while(false)

#define REMOVEREFS(mem, arr)\
	do {\
		for(auto &_slot: (arr))\
			REMOVEREF((mem), _slot);\
	} while(false)

namespace croc
{
	namespace array
	{
		// Create a new array object of the given length.
		Array* create(Memory& mem, uword size)
		{
			auto ret = ALLOC_OBJ(mem, Array);
			ret->data = DArray<Array::Slot>::alloc(mem, size);
			ret->length = size;
			return ret;
		}

		// Free an array object.
		void free(Memory& mem, Array* a)
		{
			a->data.free(mem);
			FREE_OBJ(mem, Array, a);
		}

		// Resize an array object.
		void resize(Memory& mem, Array* a, uword newSize)
		{
			if(newSize == a->length)
				return;

			auto oldSize = a->length;
			a->length = newSize;

			if(newSize < oldSize)
			{
				REMOVEREFS(mem, a->data.slice(newSize, oldSize));
				a->data.slice(newSize, oldSize).fill(Array::Slot());

				if(newSize < (a->data.length >> 1))
					a->data.resize(mem, largerPow2(newSize));
			}
			else if(newSize > a->data.length)
				a->data.resize(mem, largerPow2(newSize));
		}

		// Slice an array object to create a new array object with its own data.
		Array* slice(Memory& mem, Array* a, uword lo, uword hi)
		{
			auto n = ALLOC_OBJ(mem, Array);
			n->length = hi - lo;
			n->data = a->data.slice(lo, hi).dup(mem);
			// don't have to write barrier n cause it starts logged
			ADDREFS(n->data.slice(0, n->length));
			return n;
		}

		// Assign an entire other array into a slice of the destination array. Handles overlapping copies as well.
		void sliceAssign(Memory& mem, Array* a, uword lo, uword hi, Array* other)
		{
			auto dest = a->data.slice(lo, hi);
			auto src = other->toArray();

			assert(dest.length == src.length);

			auto len = dest.length * sizeof(Array::Slot);

			if(len > 0)
			{
				REMOVEREFS(mem, dest);

				if((dest.ptr + len) <= src.ptr || (src.ptr + len) <= dest.ptr)
					memcpy(dest.ptr, src.ptr, len);
				else
					memmove(dest.ptr, src.ptr, len);

				CONTAINER_WRITE_BARRIER(mem, a);
				ADDREFS(dest);
			}
		}

		void sliceAssign(Memory& mem, Array* a, uword lo, uword hi, DArray<Value> other)
		{
			auto dest = a->data.slice(lo, hi);
			assert(dest.length == other.length);
			auto len = dest.length * sizeof(Array::Slot);

			if(len > 0)
			{
				REMOVEREFS(mem, dest);
				CONTAINER_WRITE_BARRIER(mem, a);

				for(uword i = 0; i < dest.length; i++)
				{
					dest[i].value = other[i];
					dest[i].modified = false;
					ADDREF(dest[i]);
				}
			}
		}

		// Sets a block of values (only called by the SetArray instruction in the interpreter).
		void setBlock(Memory& mem, Array* a, uword block, DArray<Value> data)
		{
			auto start = block * INST_ARRAY_SET_FIELDS;
			auto end = start + data.length;

			// Since Op.SetArray can use a variadic number of values, the number
			// of elements actually added to the array in the array constructor
			// may exceed the size with which the array was created. So it should be
			// resized.
			if(end > a->length)
				array::resize(mem, a, end);

			CONTAINER_WRITE_BARRIER(mem, a);

			DArray<Array::Slot> dest = a->data.slice(start, end);

			for(uword i = 0; i < dest.length; i++)
			{
				dest[i].value = data[i];
				ADDREF(dest[i]);
			}
		}

		// Fills an entire array with a value.
		void fill(Memory& mem, Array* a, Value val)
		{
			if(a->length > 0)
			{
				auto data = a->toArray();
				REMOVEREFS(mem, data);

				Array::Slot slot;
				slot.value = val;

				if(val.isGCObject())
				{
					CONTAINER_WRITE_BARRIER(mem, a);
					slot.modified = true;
				}
				else
					slot.modified = false;

				data.fill(slot);
			}
		}

		// Index-assigns an element.
		void idxa(Memory& mem, Array* a, uword idx, Value val)
		{
			auto &slot = a->toArray()[idx];

			if(slot.value != val)
			{
				REMOVEREF(mem, slot);
				slot.value = val;

				if(val.isGCObject())
				{
					CONTAINER_WRITE_BARRIER(mem, a);
					slot.modified = true;
				}
				else
					slot.modified = false;
			}
		}

		// Returns `true` if one of the values in the array is identical to ('is') the given value.
		bool contains(Array* a, Value& v)
		{
			for(auto &slot: a->toArray())
				if(slot.value == v)
					return true;

			return false;
		}

		// Returns a new array that is the concatenation of the two source arrays.
		Array* cat(Memory& mem, Array* a, Array* b)
		{
			auto ret = array::create(mem, a->length + b->length);
			ret->data.slicea(0, a->length, a->toArray());
			ret->data.slicea(a->length, ret->length, b->toArray());
			ADDREFS(ret->toArray());
			return ret;
		}

		// Returns a new array that is the concatenation of the source array and value.
		Array* cat(Memory& mem, Array* a, Value* v)
		{
			Array* ret = array::create(mem, a->length + 1);
			ret->data.slicea(0, ret->length - 1, a->toArray());
			ret->data[ret->length - 1].value = *v;
			ADDREFS(ret->toArray());
			return ret;
		}

		// Append the value v to the end of array a.
		void append(Memory& mem, Array* a, Value* v)
		{
			array::resize(mem, a, a->length + 1);
			array::idxa(mem, a, a->length - 1, *v);
		}
	}
}