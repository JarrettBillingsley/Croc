
#include "croc/api.h"
#include "croc/types/base.hpp"

namespace croc
{
extern "C"
{
	namespace
	{
	void pushRegisterFunc(CrocThread* t, CrocRegisterFunc& f, uword_t numUpvals)
	{
		croc_function_new(t, f.name, f.maxParams, f.func, numUpvals);
	}
	}

	void croc_ex_makeModule(CrocThread* t, const char* name, CrocNativeFunc loader)
	{
		croc_pushGlobal(t, "modules");
		croc_field(t, -1, "customLoaders");

		if(croc_hasField(t, -1, name))
			croc_eh_throwStd(t, "LookupError",
				"%s - Module '%s' already has a loader set for it in modules.customLoaders", __FUNCTION__, name);

		croc_function_new(t, name, 1, loader, 0);
		croc_fielda(t, -2, name);
		croc_pop(t, 2);
	}

	void croc_ex_registerGlobalUV(CrocThread* t, CrocRegisterFunc f, uword_t numUpvals)
	{
		pushRegisterFunc(t, f, numUpvals);
		croc_newGlobal(t, f.name);
	}

	void croc_ex_registerFieldUV(CrocThread* t, CrocRegisterFunc f, uword_t numUpvals)
	{
		pushRegisterFunc(t, f, numUpvals);
		croc_fielda(t, -2, f.name);
	}

	void croc_ex_registerMethodUV(CrocThread* t, CrocRegisterFunc f, uword_t numUpvals)
	{
		pushRegisterFunc(t, f, numUpvals);
		croc_class_addMethod(t, -2, f.name);
	}

	void croc_ex_registerGlobals(CrocThread* t, const CrocRegisterFunc* funcs)
	{
		for(auto f = funcs; f->name != nullptr; f++)
			croc_ex_registerGlobal(t, *f);
	}

	void croc_ex_registerFields(CrocThread* t, const CrocRegisterFunc* funcs)
	{
		for(auto f = funcs; f->name != nullptr; f++)
			croc_ex_registerField(t, *f);
	}

	void croc_ex_registerMethods(CrocThread* t, const CrocRegisterFunc* funcs)
	{
		for(auto f = funcs; f->name != nullptr; f++)
			croc_ex_registerMethod(t, *f);
	}
}
}