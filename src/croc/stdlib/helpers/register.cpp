
#include "croc/api.h"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	void registerGlobals(CrocThread* t, const StdlibRegister* funcs)
	{
		for(auto f = funcs; f->name != nullptr; f++)
			croc_ex_registerGlobal(t, CrocRegisterFunc { f->name, f->maxParams, f->func});
	}

	void registerFields(CrocThread* t, const StdlibRegister* funcs)
	{
		for(auto f = funcs; f->name != nullptr; f++)
			croc_ex_registerField(t, CrocRegisterFunc { f->name, f->maxParams, f->func});
	}

	void registerMethods(CrocThread* t, const StdlibRegister* funcs)
	{
		for(auto f = funcs; f->name != nullptr; f++)
			croc_ex_registerMethod(t, CrocRegisterFunc { f->name, f->maxParams, f->func});
	}

#ifdef CROC_BUILTIN_DOCS
	void docGlobals(CrocDoc* d, const StdlibRegister* funcs)
	{
		for(auto f = funcs; f->docs != nullptr; f++)
			croc_ex_docGlobal(d, f->docs);
	}
	void docFields(CrocDoc* d, const StdlibRegister* funcs)
	{
		for(auto f = funcs; f->docs != nullptr; f++)
			croc_ex_docField(d, f->docs);
	}
#endif
}