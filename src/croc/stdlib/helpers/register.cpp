
#include "croc/api.h"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"
#include "croc/util/str.hpp"

namespace croc
{
	namespace
	{
		void makeModuleNamespace(CrocThread* t, const char* name)
		{
			croc_pushGlobal(t, "_G");

			delimiters(atoda(name), ATODA("."), [&](crocstr piece)
			{
				croc_pushStringn(t, cast(const char*)piece.ptr, piece.length);

				if(croc_hasFieldStk(t, -2, -1))
				{
					croc_fieldStk(t, -2);
					croc_insertAndPop(t, -2);
				}
				else
				{
					croc_namespace_new(t, croc_getString(t, -1));
					croc_insert(t, -3);
					croc_dup(t, -3);
					croc_fieldaStk(t, -3);
					croc_popTop(t);
				}
			});
		}
	}

	void registerModule(CrocThread* t, const char* name, CrocNativeFunc loader)
	{
		makeModuleNamespace(t, name);
		croc_dupTop(t);
		croc_function_newWithEnv(t, name, 0, loader, 0);
		croc_swapTop(t);
		croc_call(t, -2, 0);
	}

	void registerModuleFromString(CrocThread* t, const char* name, const char* source, const char* sourceName)
	{
		makeModuleNamespace(t, name);

		croc_pushString(t, source);
		const char* modName;
		croc_compiler_compileModuleEx(t, sourceName, &modName);

		if(strcmp(name, modName) != 0)
			croc_eh_throwStd(t, "ImportException",
				"Import name (%s) does not match name given in module statement (%s)", name, modName);

		croc_swapTop(t);
		croc_dupTop(t);
		croc_function_newScriptWithEnv(t, -3);
		croc_swapTop(t);
		croc_call(t, -2, 0);
		croc_popTop(t);
	}

#define MAKE_REGISTER_MULTI(Type)\
	void register##Type##s(CrocThread* t, const StdlibRegister* funcs)\
	{\
		for(auto f = funcs; f->info.name != nullptr; f++)\
			croc_ex_register##Type(t, (CrocRegisterFunc { f->info.name, f->info.maxParams, f->func}));\
	}

	MAKE_REGISTER_MULTI(Global)
	MAKE_REGISTER_MULTI(Field)
	MAKE_REGISTER_MULTI(Method)

#define MAKE_REGISTER_UV(Type)\
	void register##Type##UV(CrocThread* t, const StdlibRegister* func)\
	{\
		uword numUVs = 0;\
		for(auto f = func; f->info.name != nullptr; f++)\
		{\
			if(f[1].info.name == nullptr)\
			{\
				register##Type(t, *f, numUVs);\
				break;\
			}\
			else\
			{\
				croc_function_new(t, f->info.name, f->info.maxParams, f->func, 0);\
				numUVs++;\
			}\
		}\
	}

	MAKE_REGISTER_UV(Global)
	MAKE_REGISTER_UV(Field)
	MAKE_REGISTER_UV(Method)

#define MAKE_REGISTER(Type)\
	void register##Type(CrocThread* t, const StdlibRegister& func, uword numUVs)\
	{\
		croc_ex_register##Type##UV(t, (CrocRegisterFunc { func.info.name, func.info.maxParams, func.func }), numUVs);\
	}

	MAKE_REGISTER(Global)
	MAKE_REGISTER(Field)
	MAKE_REGISTER(Method)

#ifdef CROC_BUILTIN_DOCS
#define MAKE_DOC_MULTI(Type)\
	void doc##Type##s(CrocDoc* d, const StdlibRegister* funcs)\
	{\
		for(auto f = funcs; f->info.docs != nullptr; f++)\
			croc_ex_doc##Type(d, f->info.docs);\
	}

	MAKE_DOC_MULTI(Global)
	MAKE_DOC_MULTI(Field)

#define MAKE_DOC_UV(Type)\
	void doc##Type##UV(CrocDoc* d, const StdlibRegister* func)\
	{\
		for(auto f = func; f->info.name != nullptr; f++)\
		{\
			if(f[1].info.name == nullptr)\
			{\
				croc_ex_doc##Type(d, f->info.docs);\
				break;\
			}\
		}\
	}

	MAKE_DOC_UV(Global)
	MAKE_DOC_UV(Field)

#define MAKE_DOC(Type)\
	void doc##Type(CrocDoc* d, const StdlibRegister& func)\
	{\
		croc_ex_doc##Type(d, func.info.docs);\
	}

	MAKE_DOC(Global)
	MAKE_DOC(Field)
#endif
}