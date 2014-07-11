
#include <string.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{
const StdlibRegisterInfo _getVar_info =
{
	Docstr(DFunc("getVar") DParam("name", "string") DParamD("defaultVal", "string", "null")
	R"(Get the value of the environment variable named \tt{name}.

	\param[name] is the name of the environment variable to retrieve.
	\param[defaultVal] is an optional value that will be returned in the case that there is no environment variable
		named \tt{name}.

	\returns the value of the environment variable, if any. If no variable named \tt{name} exists, it will return
		\tt{defaultVal} instead (which defaults to \tt{null}).)"),

	"getVar", 2
};

word_t _getVar(CrocThread* t)
{
	croc_ex_checkStringParam(t, 1);
	auto haveDef = croc_ex_optParam(t, 2, CrocType_String);
	auto name = getCrocstr(t, 1);

	if(!oscompat::getEnv(t, name))
	{
		if(haveDef)
			croc_dup(t, 2);
		else
			croc_pushNull(t);
	}

	return 1;
}

const StdlibRegisterInfo _getAllVars_info =
{
	Docstr(DFunc("getAllVars")
	R"(\returns a table containing all variables in this process's environment. The keys are the names and the values
	are... the values.)"),

	"getAllVars", 0
};

word_t _getAllVars(CrocThread* t)
{
	oscompat::getAllEnvVars(t);
	return 1;
}

const StdlibRegisterInfo _setVar_info =
{
	Docstr(DFunc("setVar") DParam("name", "string") DParamD("val", "string", "null")
	R"(Set or unset a variable in this process's environment.

	\param[name] is the name of the variable to set or unset.
	\param[val] is the value to set the variable to. If you set the variable to the empty string or \tt{null}, the
		variable will be unset (removed from the process's environment).)"),

	"setVar", 2
};

word_t _setVar(CrocThread* t)
{
	croc_ex_checkStringParam(t, 1);
	auto haveVal = croc_ex_optParam(t, 2, CrocType_String);
	auto name = getCrocstr(t, 1);

	if(haveVal)
		oscompat::setEnv(t, name, getCrocstr(t, 2));
	else
		oscompat::setEnv(t, name, crocstr());

	return 0;
}

const StdlibRegister _globalFuncs[] =
{
	_DListItem(_getVar),
	_DListItem(_getAllVars),
	_DListItem(_setVar),
	_DListEnd
};

word loader(CrocThread* t)
{
	registerGlobals(t, _globalFuncs);
	return 0;
}
}

void initEnvLib(CrocThread* t)
{
	croc_ex_makeModule(t, "env", &loader);
	croc_ex_importNS(t, "env");
#ifdef CROC_BUILTIN_DOCS
	CrocDoc doc;
	croc_ex_doc_init(t, &doc, __FILE__);
	croc_ex_doc_push(&doc,
	DModule("env")
	R"(This small module allows you to get and set process environment variables.)");
		docFields(&doc, _globalFuncs);
	croc_ex_doc_pop(&doc, -1);
	croc_ex_doc_finish(&doc);
#endif
	croc_popTop(t);
}
}