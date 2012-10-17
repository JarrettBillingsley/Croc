#include <string.h>

#include "croc/base/alloc.hpp"
//#include "croc/base/writebarrier.hpp"
#include "croc/base/opcodes.hpp"
#include "croc/types/array.hpp"
#include "croc/types.hpp"
#include "croc/utils.hpp"

#define ARRAY_ADDREF(slot)\
	do {\
	if((slot).value.isGCObject())\
		(slot).modified = true;\
	} while(false)

#define ARRAY_REMOVEREF(alloc, slot)\
	do {\
		if(!(slot).modified && (slot).value.isGCObject())\
			(alloc).decBuffer.add((alloc), (slot).value.toGCObject());\
	} while(false)

#define ARRAY_ADDREFS(arr)\
	do {\
		for(int iarr = 0; iarr < (arr).length; iarr++)\
			ARRAY_ADDREF((arr)[iarr]);\
	} while(false)

#define ARRAY_REMOVEREFS(alloc, arr)\
	do {\
		for(int iarr = 0; iarr < (arr).length; iarr++)\
			ARRAY_REMOVEREF((alloc), (arr)[iarr]);\
	} while(false)

namespace croc
{
	namespace array
	{
		// Create a new array object of the given length.
		Array* create(Allocator& alloc, uword size)
		{
			Array* ret = alloc.allocate<Array>();
			ret->data = alloc.allocArray<Array::Slot>(size);
			ret->length = size;
			return ret;
		}

		// Free an array object.
		void free(Allocator& alloc, Array* a)
		{
			alloc.freeArray(a->data);
			alloc.free(a);
		}

		// Resize an array object.
		void resize(Allocator& alloc, Array* a, uword newSize)
		{
			if(newSize == a->length)
				return;

			uword oldSize = a->length;
			a->length = newSize;

			if(newSize < oldSize)
			{
				DArray<Array::Slot> tmp = a->data.slice(newSize, oldSize);
				ARRAY_REMOVEREFS(alloc, tmp);
				a->data.slice(newSize, oldSize).fill(Array::Slot());

				if(newSize < (a->data.length >> 1))
					alloc.resizeArray(a->data, largerPow2(newSize));
			}
			else if(newSize > a->data.length)
				alloc.resizeArray(a->data, largerPow2(newSize));
		}

		// Slice an array object to create a new array object with its own data.
		Array* slice(Allocator& alloc, Array* a, uword lo, uword hi)
		{
			Array* n = alloc.allocate<Array>();
			n->length = hi - lo;
			n->data = alloc.dupArray(a->data.slice(lo, hi));
			// don't have to write barrier n cause it starts logged
			DArray<Array::Slot> tmp = n->data.slice(0, n->length);
			ARRAY_ADDREFS(tmp);
			return n;
		}

		// Assign an entire other array into a slice of the destination array. Handles overlapping copies as well.
		void sliceAssign(Allocator& alloc, Array* a, uword lo, uword hi, Array* other)
		{
			DArray<Array::Slot> dest = a->data.slice(lo, hi);
			DArray<Array::Slot> src = other->toArray();

			assert(dest.length == src.length);

			uword len = dest.length * sizeof(Array::Slot);

			if(len > 0)
			{
				ARRAY_REMOVEREFS(alloc, dest);

				if((dest.ptr + len) <= src.ptr || (src.ptr + len) <= dest.ptr)
					memcpy(dest.ptr, src.ptr, len);
				else
					memmove(dest.ptr, src.ptr, len);

				// CONTAINER_WRITE_BARRIER(alloc, a);
				ARRAY_ADDREFS(dest);
			}
		}

		void sliceAssign(Allocator& alloc, Array* a, uword lo, uword hi, DArray<Value> other)
		{
			DArray<Array::Slot> dest = a->data.slice(lo, hi);

			assert(dest.length == other.length);

			uword len = dest.length * sizeof(Array::Slot);

			if(len > 0)
			{
				ARRAY_REMOVEREFS(alloc, dest);
				// CONTAINER_WRITE_BARRIER(alloc, a);

				for(uword i = 0; i < dest.length; i++)
				{
					dest[i].value = other[i];
					dest[i].modified = false;
					ARRAY_ADDREF(dest[i]);
				}
			}
		}

		// Sets a block of values (only called by the SetArray instruction in the interpreter).
		void setBlock(Allocator& alloc, Array* a, uword block, DArray<Value> data)
		{
			uword start = block * INST_ARRAY_SET_FIELDS;
			uword end = start + data.length;

			// Since Op.SetArray can use a variadic number of values, the number
			// of elements actually added to the array in the array constructor
			// may exceed the size with which the array was created. So it should be
			// resized.
			if(end > a->length)
				array::resize(alloc, a, end);

			// CONTAINER_WRITE_BARRIER(alloc, a);

			DArray<Array::Slot> tmp = a->data.slice(start, end);

			for(uword i = 0; i < tmp.length; i++)
			{
				tmp[i].value = data[i];
				ARRAY_ADDREF(tmp[i]);
			}
		}

		// Fills an entire array with a value.
		void fill(Allocator& alloc, Array* a, Value val)
		{
			if(a->length > 0)
			{
				DArray<Array::Slot> tmp = a->toArray();
				ARRAY_REMOVEREFS(alloc, tmp);

				Array::Slot slot;
				slot.value = val;

				if(val.isGCObject())
				{
					// CONTAINER_WRITE_BARRIER(alloc, a);
					slot.modified = true;
				}
				else
					slot.modified = false;

				tmp.fill(slot);
			}
		}

		// Index-assigns an element.
		void idxa(Allocator& alloc, Array* a, uword idx, Value val)
		{
			Array::Slot& slot = a->toArray()[idx];

			if(slot.value != val)
			{
				ARRAY_REMOVEREF(alloc, slot);
				slot.value = val;

				if(val.isGCObject())
				{
					// CONTAINER_WRITE_BARRIER(alloc, a);
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
		Array* cat(Allocator& alloc, Array* a, Array* b)
		{
			Array* ret = array::create(alloc, a->length + b->length);
			ret->data.slicea(0, a->length, a->toArray());
			ret->data.slicea(a->length, ret->length, b->toArray());
			DArray<Array::Slot> tmp = ret->toArray();
			ARRAY_ADDREFS(tmp);
			return ret;
		}

		// Returns a new array that is the concatenation of the source array and value.
		Array* cat(Allocator& alloc, Array* a, Value* v)
		{
			Array* ret = array::create(alloc, a->length + 1);
			ret->data.slicea(0, ret->length - 1, a->toArray());
			ret->data[ret->length - 1].value = *v;
			DArray<Array::Slot> tmp = ret->toArray();
			ARRAY_ADDREFS(tmp);
			return ret;
		}

		// Append the value v to the end of array a.
		void append(Allocator& alloc, Array* a, Value* v)
		{
			array::resize(alloc, a, a->length + 1);
			array::idxa(alloc, a, a->length - 1, *v);
		}
	}
}