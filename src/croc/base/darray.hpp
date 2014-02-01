#ifndef CROC_BASE_DARRAY_HPP
#define CROC_BASE_DARRAY_HPP

#include <string.h>

#include "croc/base/memory.hpp"
#include "croc/base/sanity.hpp"
#include "croc/ext/jhash.hpp"

#define ARRAY_BYTE_SIZE(len) ((len) * sizeof(T))

#ifdef CROC_LEAK_DETECTOR
#  define MEMBERTYPEID , typeid(DArray<T>)
#else
#  define MEMBERTYPEID
#endif

namespace croc
{
	template<typename T>
	struct DArray
	{
		T* ptr;
		size_t length;

		static inline DArray<T> n(T* ptr, size_t length)
		{
			DArray<T> ret = {ptr, length};
			return ret;
		}

		static DArray<T> alloc(Memory& mem, size_t length)
		{
			T* ptr = cast(T*)mem.allocRaw(ARRAY_BYTE_SIZE(length) MEMBERTYPEID);
			DArray<T> ret = {ptr, length};
			ret.zeroFill();
			return ret;
		}

		void free(Memory& mem)
		{
			if(length == 0)
				return;

			size_t byteLength = ARRAY_BYTE_SIZE(length);
			void* tmp = ptr;
			mem.freeRaw(tmp, byteLength MEMBERTYPEID);
			ptr = nullptr;
			length = 0;
		}

		void resize(Memory& mem, size_t newLength)
		{
			size_t byteLength = ARRAY_BYTE_SIZE(length);
			size_t newByteLength = ARRAY_BYTE_SIZE(newLength);
			void* tmp = ptr;
			mem.resizeRaw(tmp, byteLength, newByteLength MEMBERTYPEID);
			ptr = cast(T*)tmp;

			size_t oldLength = length;
			length = newLength;

			if(newLength > oldLength)
				slice(oldLength, newLength).zeroFill();
		}

		DArray<T> dup(Memory& mem)
		{
			T* retPtr = cast(T*)mem.allocRaw(ARRAY_BYTE_SIZE(length) MEMBERTYPEID);
			DArray<T> ret = {retPtr, this->length};
			ret.slicea(*this);
			return ret;
		}

		inline T* begin()
		{
			return ptr;
		}

		inline T* end()
		{
			return ptr + length;
		}

		inline uint32_t toHash() const
		{
			return hashlittle(ptr, ARRAY_BYTE_SIZE(length), 0xFACEDAB5); // face dabs!
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

		inline void slicea(size_t lo, size_t hi, DArray<T> src)
		{
			assert(lo <= hi);
			assert(hi <= length);
			assert(hi - lo == src.length);

			memcpy(ptr + lo, src.ptr, ARRAY_BYTE_SIZE(src.length));
		}

		inline DArray<T> slice(size_t lo, size_t hi) const
		{
			assert(lo <= hi);
			assert(hi <= length);

			return DArray<T>::n(ptr + lo, hi - lo);
		}

		inline void fill(T val)
		{
			for(T* i = ptr, *end = ptr + length; ptr < end; ptr++)
				*i = val;
		}

		inline void zeroFill()
		{
			memset(ptr, 0, ARRAY_BYTE_SIZE(length));
		}

		inline bool operator==(const DArray<T>& other) const
		{
			assert(length == other.length);
			return memcmp(ptr, other.ptr, length) == 0;
		}
	};
}

#undef ARRAY_BYTE_SIZE
#undef MEMBERTYPEID

#endif