
#include "croc/internal/calls.hpp"

namespace croc
{
	Namespace* getEnv(Thread* t, uword depth)
	{
		if(t->arIndex == 0)
			return t->vm->globals;
		else if(depth == 0)
			return t->currentAR->func->environment;

		for(word idx = t->arIndex - 1; idx >= 0; idx--)
		{
			if(depth == 0)
				return t->actRecs[cast(uword)idx].func->environment;
			else if(depth <= t->actRecs[cast(uword)idx].numTailcalls)
				assert(false); // TODO:ex
				// throwStdException(t, "RuntimeError", "Attempting to get environment of function whose activation record was overwritten by a tail call");

			depth -= (t->actRecs[cast(uword)idx].numTailcalls + 1);
		}

		return t->vm->globals;
	}
}