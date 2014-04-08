
#include "croc/api.h"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	namespace
	{
	void pushRegisterFunc(CrocThread* t, CrocRegisterFunc& f, uword_t numUpvals)
	{
		croc_function_new(t, f.name, f.maxParams, f.func, numUpvals);
	}
	}

	/** Given a \c name and a \c loader native function which will act as the top-level function for the module, inserts
	an entry into the Croc \c modules.customLoaders table which will call the \c loader when \c name is imported. */
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

	/** Like \ref croc_ex_registerGlobal, but expects \c numUpvals values on top of the stack, and creates the function
	with them as its upvalues. */
	void croc_ex_registerGlobalUV(CrocThread* t, CrocRegisterFunc f, uword_t numUpvals)
	{
		pushRegisterFunc(t, f, numUpvals);
		croc_newGlobal(t, f.name);
	}

	/** Like \ref croc_ex_registerField, but expects \c numUpvals values on top of the stack, and creates the function
	with them as its upvalues. The object that will be given the field should be below the upvalues. */
	void croc_ex_registerFieldUV(CrocThread* t, CrocRegisterFunc f, uword_t numUpvals)
	{
		pushRegisterFunc(t, f, numUpvals);
		croc_fielda(t, -2, f.name);
	}

	/** Like \ref croc_ex_registerMethod, but expects \c numUpvals values on top of the stack, and creates the function
	with them as its upvalues. The object that will be given the method should be below the upvalues. */
	void croc_ex_registerMethodUV(CrocThread* t, CrocRegisterFunc f, uword_t numUpvals)
	{
		pushRegisterFunc(t, f, numUpvals);
		croc_class_addMethod(t, -2, f.name);
	}

	/** Takes an array of \ref CrocRegisterFunc structs, terminated by a struct whose \c name member is \c NULL, and
	registers them all as globals in the current environment.

	For example:

	\code{.c}
	const CrocRegisterFunc funcs[] =
	{
		{ "func1", 0, &func1 },
		{ "func2", 1, &func2 },
		{ NULL, 0, NULL }
	};

	// Later, perhaps in the loader function that was set using croc_ex_makeModule...
	croc_ex_registerGlobals(t, funcs);
	\endcode */
	void croc_ex_registerGlobals(CrocThread* t, const CrocRegisterFunc* funcs)
	{
		for(auto f = funcs; f->name != nullptr; f++)
			croc_ex_registerGlobal(t, *f);
	}

	/** Like \ref croc_ex_registerGlobals, but field-assigns them into the value on top of the stack. */
	void croc_ex_registerFields(CrocThread* t, const CrocRegisterFunc* funcs)
	{
		for(auto f = funcs; f->name != nullptr; f++)
			croc_ex_registerField(t, *f);
	}

	/** Like \ref croc_ex_registerGlobals, but adds them as methods into the class on top of the stack. */
	void croc_ex_registerMethods(CrocThread* t, const CrocRegisterFunc* funcs)
	{
		for(auto f = funcs; f->name != nullptr; f++)
			croc_ex_registerMethod(t, *f);
	}
}