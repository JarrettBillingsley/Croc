#include "croc/base/metamethods.hpp"

namespace croc
{
#define POOP(_, x) x
	const char* MetaNames[] =
	{
		METAMETHOD_LIST(POOP)
	};
#undef POOP
}