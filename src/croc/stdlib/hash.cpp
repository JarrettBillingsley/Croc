
#include <stdlib.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

namespace croc
{
	namespace
	{
#include "croc/stdlib/hash_weaktables.croc.hpp"

	const CrocRegisterFunc _globalFuncs[] =
	{
		{nullptr, 0, nullptr, 0}
	};

	word loader(CrocThread* t)
	{
		// TODO:doc
		// version(CrocBuiltinDocs)
		// 	scope c = new Compiler(t, Compiler.getDefaultFlags(t) | Compiler.DocTable);
		// else
		// 	scope c = new Compiler(t);

		croc_pushStringn(t, hash_weaktables_croc_text, hash_weaktables_croc_length);
		croc_compiler_compileStmtsEx(t, "hash_weaktables.croc");

		croc_function_newScript(t, -1);
		croc_pushNull(t);
		croc_call(t, -2, 0);
		croc_popTop(t);

		return 0;
	}
	}

	void initHashLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "hash", &loader);
		croc_ex_importModuleNoNS(t, "hash");
	}
}