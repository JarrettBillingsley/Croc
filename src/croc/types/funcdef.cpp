#include "croc/types/funcdef.hpp"

namespace croc
{
	namespace funcdef
	{
		Funcdef* create(Memory& mem)
		{
			return ALLOC_OBJ(mem, Funcdef);
		}

		// Free a function definition.
		void free(Memory& mem, Funcdef* fd)
		{
			fd->paramMasks.free(mem);
			fd->upvals.free(mem);
			fd->innerFuncs.free(mem);
			fd->constants.free(mem);
			fd->code.free(mem);

			for(auto &st: fd->switchTables)
				st.offsets.clear(mem);

			fd->switchTables.free(mem);
			fd->lineInfo.free(mem);
			fd->upvalNames.free(mem);
			fd->locVarDescs.free(mem);
			FREE_OBJ(mem, Funcdef, fd);
		}
	}
}
