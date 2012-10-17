#include <string.h>

#include "croc/utils.hpp"

namespace croc
{
	template<int> inline void largerPow2Helper(size_t& val);
	template<> inline void largerPow2Helper<4>(size_t& val) {}
	template<> inline void largerPow2Helper<8>(size_t& val) { val |= val >> 32; }

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
		largerPow2Helper<sizeof(size_t)>(n);
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