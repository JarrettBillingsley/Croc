
#include "croc/api.h"
#include "croc/types.hpp"

namespace croc
{
	namespace
	{

	word loader(CrocThread* t)
	{
		(void)t;
		return 0;
	}
	}

	void initExceptionsLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "exceptions", &loader);
		croc_ex_importModuleNoNS(t, "exceptions");
	}
}