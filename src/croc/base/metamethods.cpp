#include "croc/base/metamethods.hpp"

namespace croc
{
#define POOP(_, x, __, ___) x
	const char* MetaNames[] =
	{
		METAMETHOD_LIST(POOP)
	};
#undef POOP
#define POOP(_, __, x, ___) cast(Metamethod)x
	const Metamethod MMRev[] =
	{
		METAMETHOD_LIST(POOP)
	};
#undef POOP
#define POOP(_, __, ___, x) x
	const bool MMCommutative[] =
	{
		METAMETHOD_LIST(POOP)
	};
#undef POOP
}