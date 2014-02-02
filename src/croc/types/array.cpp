#include <string.h>

#include "croc/base/memory.hpp"
#include "croc/base/opcodes.hpp"
#include "croc/base/writebarrier.hpp"
#include "croc/types.hpp"
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
	// Create a new array object of the given length.
	Array* Array::create(Memory& mem, uword size)
	{
		auto ret = ALLOC_OBJ(mem, Array);
		ret->type = CrocType_Array;
		ret->data = DArray<Array::Slot>::alloc(mem, size);
		ret->length = size;
		return ret;
	}

	// Free an array object.
	void Array::free(Memory& mem, Array* a)
	{
		a->data.free(mem);
		FREE_OBJ(mem, Array, a);
	}

	// Resize an array object.
	void Array::resize(Memory& mem, uword newSize)
	{
		if(newSize == this->length)
			return;

		auto oldSize = this->length;
		this->length = newSize;

		if(newSize < oldSize)
		{
			REMOVEREFS(mem, this->data.slice(newSize, oldSize));
			this->data.slice(newSize, oldSize).fill(Array::Slot());

			if(newSize < (this->data.length >> 1))
				this->data.resize(mem, largerPow2(newSize));
		}
		else if(newSize > this->data.length)
			this->data.resize(mem, largerPow2(newSize));
	}

	// Slice an array object to create a new array object with its own data.
	Array* Array::slice(Memory& mem, uword lo, uword hi)
	{
		auto n = ALLOC_OBJ(mem, Array);
		n->type = CrocType_Array;
		n->length = hi - lo;
		n->data = this->data.slice(lo, hi).dup(mem);
		// don't have to write barrier n cause it starts logged
		ADDREFS(n->data.slice(0, n->length));
		return n;
	}

	// Assign an entire other array into a slice of the destination array. Handles overlapping copies as well.
	void Array::sliceAssign(Memory& mem, uword lo, uword hi, Array* other)
	{
		auto dest = this->data.slice(lo, hi);
		auto src = other->toDArray();

		assert(dest.length == src.length);

		auto len = dest.length * sizeof(Array::Slot);

		if(len > 0)
		{
			REMOVEREFS(mem, dest);

			if((dest.ptr + len) <= src.ptr || (src.ptr + len) <= dest.ptr)
				memcpy(dest.ptr, src.ptr, len);
			else
				memmove(dest.ptr, src.ptr, len);

			CONTAINER_WRITE_BARRIER(mem, this);
			ADDREFS(dest);
		}
	}

	void Array::sliceAssign(Memory& mem, uword lo, uword hi, DArray<Value> other)
	{
		auto dest = this->data.slice(lo, hi);
		assert(dest.length == other.length);
		auto len = dest.length * sizeof(Array::Slot);

		if(len > 0)
		{
			REMOVEREFS(mem, dest);
			CONTAINER_WRITE_BARRIER(mem, this);

			for(uword i = 0; i < dest.length; i++)
			{
				dest[i].value = other[i];
				dest[i].modified = false;
				ADDREF(dest[i]);
			}
		}
	}

	// Sets a block of values (only called by the SetArray instruction in the interpreter).
	void Array::setBlock(Memory& mem, uword block, DArray<Value> data)
	{
		auto start = block * INST_ARRAY_SET_FIELDS;
		auto end = start + data.length;

		// Since Op.SetArray can use a variadic number of values, the number
		// of elements actually added to the array in the array constructor
		// may exceed the size with which the array was created. So it should be
		// resized.
		if(end > this->length)
			this->resize(mem, end);

		CONTAINER_WRITE_BARRIER(mem, this);

		DArray<Array::Slot> dest = this->data.slice(start, end);

		for(uword i = 0; i < dest.length; i++)
		{
			dest[i].value = data[i];
			ADDREF(dest[i]);
		}
	}

	// Fills an entire array with a value.
	void Array::fill(Memory& mem, Value val)
	{
		if(this->length > 0)
		{
			auto data = this->toDArray();
			REMOVEREFS(mem, data);

			Array::Slot slot;
			slot.value = val;

			if(val.isGCObject())
			{
				CONTAINER_WRITE_BARRIER(mem, this);
				slot.modified = true;
			}
			else
				slot.modified = false;

			data.fill(slot);
		}
	}

	// Index-assigns an element.
	void Array::idxa(Memory& mem, uword idx, Value val)
	{
		auto &slot = this->toDArray()[idx];

		if(slot.value != val)
		{
			REMOVEREF(mem, slot);
			slot.value = val;

			if(val.isGCObject())
			{
				CONTAINER_WRITE_BARRIER(mem, this);
				slot.modified = true;
			}
			else
				slot.modified = false;
		}
	}

	// Returns `true` if one of the values in the array is identical to ('is') the given value.
	bool Array::contains(Value& v)
	{
		for(auto &slot: this->toDArray())
			if(slot.value == v)
				return true;

		return false;
	}

	// Returns a new array that is the concatenation of the two source arrays.
	Array* Array::cat(Memory& mem, Array* other)
	{
		auto ret = Array::create(mem, this->length + other->length);
		ret->data.slicea(0, this->length, this->toDArray());
		ret->data.slicea(this->length, ret->length, other->toDArray());
		ADDREFS(ret->toDArray());
		return ret;
	}

	// Returns a new array that is the concatenation of the source array and value.
	Array* Array::cat(Memory& mem, Value* v)
	{
		Array* ret = Array::create(mem, this->length + 1);
		ret->data.slicea(0, ret->length - 1, this->toDArray());
		ret->data[ret->length - 1].value = *v;
		ADDREFS(ret->toDArray());
		return ret;
	}

	// Append the value v to the end of array a.
	void Array::append(Memory& mem, Value* v)
	{
		this->resize(mem, this->length + 1);
		this->idxa(mem, this->length - 1, *v);
	}
}