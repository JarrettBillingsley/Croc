
#ifdef _WIN32
#include "windows.h"
#else
#include <sys/time.h>
#endif

#include "croc/util/rng.hpp"

#define M_RAN_INVM32 2.32830643653869628906e-010
#define M_RAN_INVM52 2.22044604925031308085e-016

namespace croc
{
	void RNG::seed()
	{
		uint64_t s;

#ifdef _WIN32
		LARGE_INTEGER t;
		QueryPerformanceCounter(&t);
		s = t.QuadPart;
#else
		timeval t;
		gettimeofday(&t, nullptr);
		s = t.tv_usec;
#endif

		seed((uint32_t)s);
	}

	void RNG::seed(uint32_t seed)
	{
		initialSeed = seed;
		x = seed | 1;
		y = seed | 2;
		z = seed | 4;
		w = seed | 8;
		carry = 0;
	}

	uint32_t RNG::getSeed()
	{
		return initialSeed;
	}

	uint32_t RNG::next()
	{
		x = x * 69069 + 1;
		y ^= y << 13;
		y ^= y >> 17;
		y ^= y << 5;
		k = (z >> 2) + (w >> 3) + (carry >> 2);
		m = w + w + z + carry;
		z = w;
		w = m;
		carry = k >> 30;
		return x + y + w;
	}

	uint64_t RNG::next64()
	{
		return next() | (((uint64_t)next()) << 32);
	}

	double RNG::nextf32()
	{
		return ((int32_t)next()) * M_RAN_INVM32 + (0.5 + M_RAN_INVM32 / 2);
	}

	double RNG::nextf52()
	{
		return
			((int32_t)next()) * M_RAN_INVM32 + (0.5 + M_RAN_INVM52 / 2) +
			(((int32_t)next()) & 0x000FFFFF) * M_RAN_INVM52;
	}
}