#ifndef CROC_UTIL_MISC_HPP
#define CROC_UTIL_MISC_HPP

#include <functional>
#include <stddef.h>

#include "croc/base/darray.hpp"

namespace croc
{
	size_t largerPow2(size_t n);

	template<typename T>
	inline int Compare3(T a, T b)
	{
		return a < b ? -1 : a > b ? 1 : 0;
	}

	template<typename T>
	inline T abs(T t) { if(t < 0) return -t; else return t; }

	template<typename T>
	inline T min(T a, T b) { if(a < b) return a; else return b; }

	template<typename T>
	inline T max(T a, T b) { if(a > b) return a; else return b; }

	inline DArray<const unsigned char> atoda(const char* str)
	{
		return DArray<const unsigned char>::n(cast(const unsigned char*)str, strlen(str));
	}

#define ATODA(lit) (DArray<const unsigned char>{cast(const unsigned char*)(lit), (sizeof(lit) / sizeof(char)) - 1})
}

#endif