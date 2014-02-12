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
	{"println",   -1, &println,   0},
	{"nasty",      0, &nasty,     0},
	{"newThread",  1, &newThread, 0},
	{nullptr, 0, nullptr, 0}
};

int main()
{
	auto t = croc_vm_open(&croc_DefaultMemFunc, nullptr);
	croc_vm_loadUnsafeLibs(t, CrocUnsafeLib_ReallyAll);
	croc_vm_loadAllAvailableAddons(t);
	croc_compiler_setFlags(t, CrocCompilerFlags_All | CrocCompilerFlags_DocDecorators);
	// runModule(t, "samples.simple");

	auto f = fopen("..\\samples\\simple.croc", "rb");

	if(!f)
	{
		printf("Oh dear :(\n");
		return 1;
	}

	fseek(f, 0, SEEK_END);
	auto size = ftell(f);
	fseek(f, 0, SEEK_SET);
	auto data = (char*)malloc(size + 1);
	fread(data, 1, size, f);
	data[size] = 0;
	fclose(f);

	croc_pushString(t, data);
	free(data);
	const char* modName;

	auto result = croc_compiler_compileModule(t, "samples\\simple.croc", &modName);

	if(result >= 0)
		printf("It's called %s\n", modName);
	else
	{
		printf("OH NO! ");

		switch(result)
		{
			case CrocCompilerReturn_UnexpectedEOF: printf("unexpected end-of-file!\n"); break;
			case CrocCompilerReturn_LoneStatement: printf("lone statement!\n"); break;
			case CrocCompilerReturn_DanglingDoc:   printf("dangling doc!\n"); break;
			case CrocCompilerReturn_Error:         printf("something else!\n"); break;
		}

		croc_pushToString(t, -1);
		printf("%s\n", croc_getString(t, -1));
		croc_pop(t, 2);
	}

	// croc_ex_registerGlobals(t, _stupidFuncs);

	// croc_function_newScript(t, -1);
	// croc_pushNull(t);
	// auto result = croc_tryCall(t, -2, 0);

	// if(result < 0)
	// {
	// 	printf("------------ ERROR ------------\n");
	// 	croc_pushToString(t, -1);
	// 	printf("%s\n", croc_getString(t, -1));
	// 	croc_popTop(t);

	// 	croc_dupTop(t);
	// 	croc_pushNull(t);
	// 	croc_methodCall(t, -2, "tracebackString", 1);
	// 	printf("%s\n", croc_getString(t, -1));

	// 	croc_pop(t, 2);
	// }

	croc_vm_close(t);
	fflush(stdout);
}