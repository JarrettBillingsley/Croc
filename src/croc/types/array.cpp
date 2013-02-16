#include <string.h>

//#include "croc/base/writebarrier.hpp"
#include "croc/base/opcodes.hpp"
#include "croc/base/memory.hpp"
#include "croc/types/array.hpp"
#include "croc/types.hpp"
#include "croc/utils.hpp"

#ifdef CROC_LEAK_DETECTOR
#  define ARRAYTYPEID ,typeid(Array)
#else
#  define ARRAYTYPEID
#endif

#define ARRAY_ADDREF(slot)\
	do {\
	if((slot).value.isGCObject())\
		(slot).modified = true;\
	} while(false)

#define ARRAY_REMOVEREF(mem, slot)\
	do {\
		if(!(slot).modified && (slot).value.isGCObject())\
			(mem).decBuffer.add((mem), (slot).value.toGCObject());\
	} while(false)

#define ARRAY_ADDREFS(arr)\
	do {\
		for(size_t iarr = 0; iarr < (arr).length; iarr++)\
			ARRAY_ADDREF((arr)[iarr]);\
	} while(false)

#define ARRAY_REMOVEREFS(mem, arr)\
	do {\
		for(size_t iarr = 0; iarr < (arr).length; iarr++)\
			ARRAY_REMOVEREF((mem), (arr)[iarr]);\
	} while(false)

namespace croc
{
	namespace array
	{
		// Create a new array object of the given length.
		Array* create(Memory& mem, uword size)
		{
			Array* ret = ALLOC_OBJ(mem, Array);
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

			uword oldSize = a->length;
			a->length = newSize;

			if(newSize < oldSize)
			{
				DArray<Array::Slot> tmp = a->data.slice(newSize, oldSize);
				ARRAY_REMOVEREFS(mem, tmp);
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
			Array* n = ALLOC_OBJ(mem, Array);
			n->length = hi - lo;
			n->data = a->data.slice(lo, hi).dup(mem);
			// don't have to write barrier n cause it starts logged
			DArray<Array::Slot> tmp = n->data.slice(0, n->length);
			ARRAY_ADDREFS(tmp);
			return n;
		}

		// Assign an entire other array into a slice of the destination array. Handles overlapping copies as well.
		void sliceAssign(Memory& mem, Array* a, uword lo, uword hi, Array* other)
		{
			DArray<Array::Slot> dest = a->data.slice(lo, hi);
			DArray<Array::Slot> src = other->toArray();

			assert(dest.length == src.length);

			uword len = dest.length * sizeof(Array::Slot);

			if(len > 0)
			{
				ARRAY_REMOVEREFS(mem, dest);

				if((dest.ptr + len) <= src.ptr || (src.ptr + len) <= dest.ptr)
					memcpy(dest.ptr, src.ptr, len);
				else
					memmove(dest.ptr, src.ptr, len);

				// CONTAINER_WRITE_BARRIER(mem, a);
				ARRAY_ADDREFS(dest);
			}
		}

		void sliceAssign(Memory& mem, Array* a, uword lo, uword hi, DArray<Value> other)
		{
			DArray<Array::Slot> dest = a->data.slice(lo, hi);

			assert(dest.length == other.length);

			uword len = dest.length * sizeof(Array::Slot);

			if(len > 0)
			{
				ARRAY_REMOVEREFS(mem, dest);
				// CONTAINER_WRITE_BARRIER(mem, a);

				for(uword i = 0; i < dest.length; i++)
				{
					dest[i].value = other[i];
					dest[i].modified = false;
					ARRAY_ADDREF(dest[i]);
				}
			}
		}

		// Sets a block of values (only called by the SetArray instruction in the interpreter).
		void setBlock(Memory& mem, Array* a, uword block, DArray<Value> data)
		{
			uword start = block * INST_ARRAY_SET_FIELDS;
			uword end = start + data.length;

			// Since Op.SetArray can use a variadic number of values, the number
			// of elements actually added to the array in the array constructor
			// may exceed the size with which the array was created. So it should be
			// resized.
			if(end > a->length)
				array::resize(mem, a, end);

			// CONTAINER_WRITE_BARRIER(mem, a);

			DArray<Array::Slot> tmp = a->data.slice(start, end);

			for(uword i = 0; i < tmp.length; i++)
			{
				tmp[i].value = data[i];
				ARRAY_ADDREF(tmp[i]);
			}
		}

		// Fills an entire array with a value.
		void fill(Memory& mem, Array* a, Value val)
		{
			if(a->length > 0)
			{
				DArray<Array::Slot> tmp = a->toArray();
				ARRAY_REMOVEREFS(mem, tmp);

				Array::Slot slot;
				slot.value = val;

				if(val.isGCObject())
				{
					// CONTAINER_WRITE_BARRIER(mem, a);
					slot.modified = true;
				}
				else
					slot.modified = false;

				tmp.fill(slot);
			}
		}

		// Index-assigns an element.
		void idxa(Memory& mem, Array* a, uword idx, Value val)
		{
			Array::Slot& slot = a->toArray()[idx];

			if(slot.value != val)
			{
				ARRAY_REMOVEREF(mem, slot);
				slot.value = val;

				if(val.isGCObject())
				{
					// CONTAINER_WRITE_BARRIER(mem, a);
					slot.modified = true;
				}
				else
					slot.modified = false;
			}
		}

		// Returns `true` if one of the values in the array is identical to ('is') the given value.
		bool contains(Array* a, Value& v)
		{
			DArray<Array::Slot> data = a->toArray();

			for(uword i = 0; i < data.length; i++)
			{
				if(data[i].value == v)
					return true;
			}

			return false;
		}

		// Returns a new array that is the concatenation of the two source arrays.
		Array* cat(Memory& mem, Array* a, Array* b)
		{
			Array* ret = array::create(mem, a->length + b->length);
			ret->data.slicea(0, a->length, a->toArray());
			ret->data.slicea(a->length, ret->length, b->toArray());
			DArray<Array::Slot> tmp = ret->toArray();
			ARRAY_ADDREFS(tmp);
			return ret;
		}

		// Returns a new array that is the concatenation of the source array and value.
		Array* cat(Memory& mem, Array* a, Value* v)
		{
			Array* ret = array::create(mem, a->length + 1);
			ret->data.slicea(0, ret->length - 1, a->toArray());
			ret->data[ret->length - 1].value = *v;
			DArray<Array::Slot> tmp = ret->toArray();
			ARRAY_ADDREFS(tmp);
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