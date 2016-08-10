#include "croc/util/misc.hpp"

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