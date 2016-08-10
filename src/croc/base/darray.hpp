#ifndef CROC_BASE_DARRAY_HPP
#define CROC_BASE_DARRAY_HPP

#include <string.h>
#include <stdlib.h>

#include "croc/base/sanity.hpp"

#define ARRAY_BYTE_SIZE(len) (cast(size_t)((len) * sizeof(T)))

#ifdef CROC_LEAK_DETECTOR
#  define MEMBERTYPEID , typeid(DArray<T>)
#else
#  define MEMBERTYPEID
#endif

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

	static DArray<T> alloc(size_t length)
	{
		auto ptr = cast(T*)malloc(ARRAY_BYTE_SIZE(length));
		DArray<T> ret = {ptr, length};
		ret.zeroFill();
		return ret;
	}

	template<typename U>
	DArray<U> as()
	{
		auto thisSize = ARRAY_BYTE_SIZE(length);
		auto newLen = thisSize / sizeof(U);
		assert(newLen * sizeof(U) == thisSize);
		return DArray<U>::n(cast(U*)ptr, newLen);
	}

	inline operator DArray<const T>() const
	{
		return DArray<const T>::n(cast(const T*)ptr, length);
	}

	void free()
	{
		if(length == 0)
			return;

		void* tmp = ptr;
		::free(tmp);
		ptr = nullptr;
		length = 0;
	}

	void resize(size_t newLength)
	{
		if(length == newLength)
			return;

		ptr = cast(T*)realloc(ptr, ARRAY_BYTE_SIZE(newLength));

		size_t oldLength = length;
		length = newLength;

		if(newLength > oldLength)
			slice(oldLength, newLength).zeroFill();
	}

	DArray<T> dup()
	{
		auto retPtr = cast(T*)malloc(ARRAY_BYTE_SIZE(length));
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

	struct ReverseIteration
	{
	private:
		DArray<T>& arr;

	public:
		ReverseIteration(DArray<T>& a) : arr(a) {}

		struct iter
		{
		private:
			T* p;

		public:
			iter(T* arr) : p(arr) {}
			iter(const iter& other) : p(other.p) {}
			iter& operator++() { p--; return *this; }
			iter operator++(int) { iter tmp(*this); operator++(); return tmp; }
			bool operator==(const iter& rhs) { return p == rhs.p; }
			bool operator!=(const iter& rhs) { return !operator==(rhs); }
			T& operator*() { return *p; }
		};

		inline iter begin()
		{
			return iter(arr.ptr + (arr.length - 1));
		}

		inline iter end()
		{
			return iter(arr.ptr - 1);
		}
	};

	inline ReverseIteration reverse()
	{
		return ReverseIteration(*this);
	}

	inline uint32_t toHash() const
	{
		// return hashlittle(ptr, ARRAY_BYTE_SIZE(length), 0xFACEDAB5); // face dabs!
		return 0;
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

	inline void slicea(DArray<const T> src)
	{
		slicea(0, length, src);
	}

	inline void slicea(size_t lo, size_t hi, DArray<const T> src)
	{
		assert(lo <= hi);
		assert(hi <= length);
		assert(hi - lo == src.length);
#ifdef NDEBUG
		(void)hi;
#endif
		memcpy(ptr + lo, src.ptr, ARRAY_BYTE_SIZE(src.length));
	}

	inline DArray<T> slice(size_t lo, size_t hi) const
	{
		assert(lo <= hi);
		assert(hi <= length);

		auto len = hi - lo;

		if(len)
			return DArray<T>::n(ptr + lo, len);
		else
			return DArray<T>();
	}

	inline DArray<T> sliceToEnd(size_t lo) const
	{
		return slice(lo, length);
	}

	inline void fill(T val)
	{
		for(auto &v: *this)
			v = val;
	}

	inline void zeroFill()
	{
		memset(ptr, 0, ARRAY_BYTE_SIZE(length));
	}

	inline bool operator==(const DArray<T>& other) const
	{
		size_t len = length;

		if(other.length < len)
			len = other.length;

		if(len != 0 && memcmp(ptr, other.ptr, ARRAY_BYTE_SIZE(len)))
			return false;
		else
			return length == other.length;
	}

	inline bool operator!=(const DArray<T>& other) const { return !this->operator==(other); }

	inline int cmp(const DArray<T>& other) const
	{
		size_t len = length;

		if(other.length < len)
			len = other.length;

		if(len != 0)
		{
			if(int ret = memcmp(ptr, other.ptr, ARRAY_BYTE_SIZE(len)))
				return ret;
		}

		return length < other.length ? -1 : length > other.length ? 1 : 0;
	}

	inline bool operator< (const DArray<T>& other) const { return this->cmp(other) <  0; }
	inline bool operator<=(const DArray<T>& other) const { return this->cmp(other) <= 0; }
	inline bool operator> (const DArray<T>& other) const { return this->cmp(other) >  0; }
	inline bool operator>=(const DArray<T>& other) const { return this->cmp(other) >= 0; }
};

#undef ARRAY_BYTE_SIZE
#undef MEMBERTYPEID

#endif