#include "croc/base/opcodes.hpp"

namespace croc
{
#define POOP(x) #x

	const char* OpNames[] =
	{
		INSTRUCTION_LIST(POOP)
	};
#undef POOP
}
