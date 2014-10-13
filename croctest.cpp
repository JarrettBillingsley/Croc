#include <functional>
#include <stdio.h>
#include <stdlib.h>

#include "croc/api.h"

void _try(CrocThread* t, const char* name, CrocNativeFunc f, std::function<void()> _catch)
{
	croc_function_new(t, name, 0, f, 0);
	croc_pushNull(t);
	if(croc_tryCall(t, -2, 0) < 0)
		_catch();
}

int main()
{
	auto t = croc_vm_openDefault();
	croc_vm_loadUnsafeLibs(t, CrocUnsafeLib_ReallyAll);
	croc_vm_loadAllAvailableAddons(t);

	_try(t, "<main>", [](CrocThread* t) -> word_t
	{
		croc_compiler_setFlags(t, CrocCompilerFlags_AllDocs);

		croc_pushGlobal(t, "modules");
		croc_field(t, -1, "path");
		croc_pushString(t, ";..");
		croc_cat(t, 2);
		croc_fielda(t, -2, "path");
		croc_popTop(t);

		croc_ex_runModule(t, "test", 0);
		return 0;
	},
	[&]{
		if(croc_ex_isHaltException(t, -1))
			printf("\n------------ Thread halted. ------------\n");
		else
		{
			croc_pushNull(t);
			croc_debug_setHookFunc(t, 0, 0);

			printf("\n------------ ERROR ------------\n");
			croc_pushToString(t, -1);
			printf("%s\n", croc_getString(t, -1));
			croc_popTop(t);

			croc_dupTop(t);
			croc_pushNull(t);
			croc_methodCall(t, -2, "tracebackString", 1);
			printf("%s\n", croc_getString(t, -1));

			croc_pop(t, 2);
		}
	});

	fflush(stdout);
	croc_vm_close(t);
	return 0;
}