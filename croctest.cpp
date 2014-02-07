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

	croc_function_new(t, "println", -1, &println, 0);
	croc_newGlobal(t, "println");

	system("..\\croctest.exe > foo.txt");
	LOAD_FUNCDEF_FROM_FILE(t, "foo.txt");

	croc_function_newScript(t, -1);
	croc_pushNull(t);
	croc_call(t, -2, 0);

	croc_vm_close(t);
	return 0;
}