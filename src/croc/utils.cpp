#include <string.h>

#include "croc/utils.hpp"

namespace croc
{
	// Returns closest power of 2 that is >= n. Taken from the Stanford Bit Twiddling Hacks page.
	size_t largerPow2(size_t n)
	{
		if(n == 0)
			return 0;

		n--;
		n |= n >> 1;
		n |= n >> 2;
		n |= n >> 4;
		n |= n >> 8;
		n |= n >> 16;
		n |= n >> ((sizeof(size_t) > 4) * 32);
		n++;
		return n;
	}

	/**
	Compares char[] strings stupidly (just by character value, not lexicographically).
	*/
	int scmp(DArray<const char> s1, DArray<const char> s2)
	{
		size_t len = s1.length;

		if(s2.length < len)
			len = s2.length;

		int result = strncmp(s1.ptr, s2.ptr, len);

		if(result == 0)
			return Compare3(s1.length, s2.length);
		else
			return result;
	}
}