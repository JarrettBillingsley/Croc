#ifndef CROC_UTILS_HPP
#define CROC_UTILS_HPP

#include <stddef.h>

#include "croc/base/darray.hpp"

namespace croc
{
	size_t largerPow2(size_t n);
	int scmp(DArray<const char> s1, DArray<const char> s2);

	template<typename T>
	int Compare3(T a, T b)
	{
		return a < b ? -1 : a > b ? 1 : 0;
	}
}

#endif