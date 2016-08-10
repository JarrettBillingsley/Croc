#include <functional>
#include <stdio.h>
#include <stdlib.h>

#include "croc/compiler/types.hpp"
#include "croc/util/misc.hpp"

int main()
{
	FILE* f = fopen("../test.croc", "r");

	if(f == nullptr)
	{
		printf("NO EXIST!\n");
		return 1;
	}

	fseek(f, 0, SEEK_END);
	auto size = ftell(f);
	fseek(f, 0, SEEK_SET);
	auto src = cast(char*)malloc(size + 1);
	src[size] = 0;
	fread(cast(void*)src, size, 1, f);
	fclose(f);

	try
	{
		Compiler c;
		c.leaveDocTable(false);
		c.compileModule(atoda(src), ATODA("dorple"));
		return 0;
	}
	catch(CompileEx& e)
	{
		printf("%.*s(%d:%d): %s\n", e.loc.file.length, e.loc.file.ptr, e.loc.line, e.loc.col, e.msg);
	}
	catch(...)
	{
		printf("Something went wrong.\n");
	}

	return 1;
}