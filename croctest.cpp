#include <functional>
#include <stdio.h>
#include <stdlib.h>

#include "croc/compiler/types.hpp"
#include "croc/util/misc.hpp"

using namespace croc;

int main()
{
	try
	{
		Compiler c;
		c.leaveDocTable(false);
		crocstr modNameStr;
		c.compileModule(atoda("module"), ATODA("dorple"), modNameStr);
	}
	catch(CompileEx& e)
	{
		printf("%.*s(%d:%d): %s\n", e.loc.file.length, e.loc.file.ptr, e.loc.line, e.loc.col, e.msg);
	}
	catch(...)
	{
		printf("Something went wrong.\n");
	}

	return 0;
}