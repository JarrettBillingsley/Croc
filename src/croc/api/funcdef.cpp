
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
extern "C"
{
	const char* croc_funcdef_getName(CrocThread* t_, word_t funcdef)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(fd, funcdef, Funcdef, "funcdef");
		return fd->name->toCString();
	}

	const char* croc_funcdef_getNamen(CrocThread* t_, word_t funcdef, uword_t* len)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(fd, funcdef, Funcdef, "funcdef");
		*len = fd->name->length;
		return fd->name->toCString();
	}
}
}