#ifndef CROC_BASE_DARRAY_HPP
#define CROC_BASE_DARRAY_HPP

#include <string.h>

#include "croc/base/sanity.hpp"
#include "croc/ext/jhash.hpp"

namespace croc
{
	template<typename T>
	struct DArray
	{
		T* ptr;
		size_t length;

		DArray():
			ptr(NULL), length(0)
		{}

		DArray(T* _ptr, size_t _length):
			ptr(_ptr), length(_length)
		{}

		uint32_t toHash() const
		{
			return hashlittle(ptr, length * sizeof(T), 0xFACEDAB5); // face dabs!
		}

		inline T operator[](size_t idx) const
		{
			assert(idx < length);
			return ptr[idx];
		}

		inline T& operator[](size_t idx)
		{
			assert(idx < length);
			return ptr[idx];
		}

		inline void slicea(DArray<T> src)
		{
			slicea(0, length, src);
		}

		void slicea(size_t lo, size_t hi, DArray<T> src)
		{
			assert(lo <= hi);
			assert(hi <= length);
			assert(hi - lo == src.length);

			memcpy(ptr + lo, src.ptr, src.length * sizeof(T));
		}

		DArray<T> slice(size_t lo, size_t hi)
		{
			assert(lo <= hi);
			assert(hi <= length);

			return DArray<T>(ptr + lo, hi - lo);
		}

		void fill(T val)
		{
			for(size_t i = 0; i < length; i++)
				ptr[i] = val;
		}

		bool operator==(const DArray<T>& other) const
		{
			assert(length == other.length);
			return memcmp(ptr, other.ptr, length) == 0;
		}
	};
}

#endif