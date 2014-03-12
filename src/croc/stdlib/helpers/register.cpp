
#include "croc/api.h"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
#define MAKE_REGISTER_MULTI(Type)\
	void register##Type##s(CrocThread* t, const StdlibRegister* funcs)\
	{\
		for(auto f = funcs; f->name != nullptr; f++)\
			croc_ex_register##Type(t, (CrocRegisterFunc { f->name, f->maxParams, f->func}));\
	}

	MAKE_REGISTER_MULTI(Global)
	MAKE_REGISTER_MULTI(Field)
	MAKE_REGISTER_MULTI(Method)

#define MAKE_REGISTER_UV(Type)\
	void register##Type##UV(CrocThread* t, const StdlibRegister* func)\
	{\
		uword numUVs = 0;\
		for(auto f = func; f->name != nullptr; f++)\
		{\
			if(f[1].name == nullptr)\
			{\
				register##Type(t, *f, numUVs);\
				break;\
			}\
			else\
			{\
				croc_function_new(t, f->name, f->maxParams, f->func, 0);\
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
		croc_ex_register##Type##UV(t, (CrocRegisterFunc { func.name, func.maxParams, func.func }), numUVs);\
	}

	MAKE_REGISTER(Global)
	MAKE_REGISTER(Field)
	MAKE_REGISTER(Method)

#ifdef CROC_BUILTIN_DOCS
#define MAKE_DOC_MULTI(Type)\
	void doc##Type##s(CrocDoc* d, const StdlibRegister* funcs)\
	{\
		for(auto f = funcs; f->docs != nullptr; f++)\
			croc_ex_doc##Type(d, f->docs);\
	}

	MAKE_DOC_MULTI(Global)
	MAKE_DOC_MULTI(Field)

#define MAKE_DOC_UV(Type)\
	void doc##Type##UV(CrocDoc* d, const StdlibRegister* func)\
	{\
		for(auto f = func; f->name != nullptr; f++)\
		{\
			if(f[1].name == nullptr)\
			{\
				croc_ex_doc##Type(d, f->docs);\
				break;\
			}\
		}\
	}

	MAKE_DOC_UV(Global)
	MAKE_DOC_UV(Field)

#define MAKE_DOC(Type)\
	void doc##Type(CrocDoc* d, const StdlibRegister& func)\
	{\
		croc_ex_doc##Type(d, func.docs);\
	}

	MAKE_DOC(Global)
	MAKE_DOC(Field)
#endif
}