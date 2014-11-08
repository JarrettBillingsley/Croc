#include "croc/types/base.hpp"

namespace croc
{
	Funcdef* Funcdef::create(Memory& mem)
	{
		auto ret = ALLOC_OBJ(mem, Funcdef);
		ret->type = CrocType_Funcdef;
		return ret;
	}

	// Free a function definition.
	void Funcdef::free(Memory& mem, Funcdef* fd)
	{
		fd->paramMasks.free(mem);
		fd->returnMasks.free(mem);
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
