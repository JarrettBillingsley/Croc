#ifndef CROC_UTIL_RNG_HPP
#define CROC_UTIL_RNG_HPP

#include <stddef.h>
#include <stdint.h>

namespace croc
{
	struct RNG
	{
	private:
		uint32_t initialSeed;
		uint32_t k;
		uint32_t m;
		uint32_t x;
		uint32_t y;
		uint32_t z;
		uint32_t w;
		uint32_t carry;

	public:
		RNG():
			initialSeed(0),
			k(0),
			m(0),
			x(1),
			y(2),
			z(4),
			w(8),
			carry(0)
		{}

		void seed();
		void seed(uint32_t seed);
		uint32_t getSeed();
		uint32_t next();
		uint64_t next64();
		double nextf32();
		double nextf52();
	};
}

#endif