#include <stdio.h>
#include <stdlib.h>

#include "croc/api.h"

#include "croc/util/str.hpp"
#include "croc/types/base.hpp"

word_t println(CrocThread* t)
{
	auto size = croc_getStackSize(t);

	for(unsigned int i = 1; i < size; i++)
	{
		croc_pushToString(t, i);
		printf("%s", croc_getString(t, -1));
		croc_popTop(t);
	}

	printf("\n");

	return 0;
}

word_t nasty(CrocThread* t)
{
	croc_eh_throwStd(t, "StateError", "YOU'RE MEAN!");
	return 0;
}

word_t newThread(CrocThread* t)
{
	croc_ex_checkParam(t, 1, CrocType_Function);
	croc_thread_new(t, 1);
	return 1;
}

const CrocRegisterFunc _stupidFuncs[] =
{
	{"println",   -1, &println  },
	{"nasty",      0, &nasty    },
	{"newThread",  1, &newThread},
	{nullptr, 0, nullptr}
};

word_t mainStuff(CrocThread* t)
{
	croc_compiler_setFlags(t, CrocCompilerFlags_All | CrocCompilerFlags_DocDecorators);
	croc_ex_registerGlobals(t, _stupidFuncs);

	croc_pushGlobal(t, "modules");
	croc_field(t, -1, "path");
	croc_pushString(t, ";..");
	croc_cat(t, 2);
	croc_fielda(t, -2, "path");
	croc_popTop(t);

	croc_ex_importModule(t, "samples.simple");
	croc_pushNull(t);
	croc_ex_lookup(t, "modules.runMain");
	croc_swapTopWith(t, -3);
	croc_call(t, -3, 0);

	return 0;
}

int main()
{
	auto t = croc_vm_openDefault();
	croc_vm_loadUnsafeLibs(t, CrocUnsafeLib_ReallyAll);
	croc_vm_loadAllAvailableAddons(t);

	croc_function_new(t, "<main>", 0, &mainStuff, 0);
	croc_pushNull(t);

	if(croc_tryCall(t, -2, 0) < 0)
	{
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

	fflush(stdout);
	croc_vm_close(t);
	return 0;
}