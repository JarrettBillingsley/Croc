#include <stdio.h>

#include "croc/api.h"

int main()
{
	auto t = croc_vm_open(&croc_DefaultMemFunc, nullptr);
	croc_vm_close(t);
	return 0;
}