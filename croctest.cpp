#include <functional>
#include <stdio.h>
#include <stdlib.h>

#include "croc/api.h"

#include "croc/compiler/types.hpp"
#include "croc/util/misc.hpp"

using namespace croc;

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

	_try(t, "<main>", [](CrocThread* t) -> word_t
	{
		int ret = 0;
		{

			Compiler c(t);
			c.leaveDocTable(false);
			crocstr modNameStr;
			ret = c.compileModule(atoda("module"), ATODA("dorple"), modNameStr);
		}

		if(ret < 0)
			croc_eh_throw(t);

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