#include <stdio.h>
#include <stdlib.h>

#include "croc/api.h"

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

int main()
{
	auto t = croc_vm_open(&croc_DefaultMemFunc, nullptr);
	// croc_vm_loadUnsafeLibs(t, CrocUnsafeLib_ReallyAll);
	// croc_vm_loadAvailableAddons(t);
	// croc_compiler_setFlags(t, CrocCompilerFlags_All | CrocCompilerFlags_DocDecorators);
	// runModule(t, "samples.simple");

	croc_function_new(t, "println", -1, &println, 0);
	croc_newGlobal(t, "println");

	system("..\\croctest.exe > foo.txt");
	LOAD_FUNCDEF_FROM_FILE(t, "foo.txt");

	croc_function_newScript(t, -1);
	croc_pushNull(t);
	auto result = croc_tryCall(t, -2, 0);

	if(result < 0)
	{
		printf("------------ ERROR ------------\n");
		croc_pushToString(t, -1);
		printf("%s\n", croc_getString(t, -1));
		croc_popTop(t);

		croc_dupTop(t);
		croc_pushNull(t);
		croc_methodCall(t, -2, "tracebackString", 1);
		printf("%s\n", croc_getString(t, -1));

		croc_pop(t, 2);
	}

	croc_vm_close(t);
	fflush(stdout);
}