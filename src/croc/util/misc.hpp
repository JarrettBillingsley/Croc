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

	inline DArray<const char> atoda(const char* str)
	{
		return DArray<const char>::n(str, strlen(str));
	}
}

#endif