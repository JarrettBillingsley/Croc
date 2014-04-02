
#include <stdlib.h>
#include <chrono>
#include <thread>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
#ifdef CROC_BUILTIN_DOCS
const char* ModuleDocs =
DModule("os")
R"(This module contains some unsafe operating system interfaces for things like spawning processes.)";
#endif

DBeginList(_globalFuncs)
	Docstr(DFunc("haveShell")
	R"(\returns a bool indicating whether or not there is a shell command processor available. If there is, you can use
	the \link{shellCmd} function to run shell commands.)"),

	"haveShell", 0, [](CrocThread* t) -> word_t
	{
		croc_pushBool(t, system(nullptr) ? true : false);
		return 1;
	}

DListSep()
	Docstr(DFunc("shellCmd") DParam("cmd", "string")
	R"(Executes the string \tt{cmd} through the system's shell command processor, spawning a subprocess. Execution of
	the calling process waits until the subprocess completes.

	\returns the exit code from the subprocess as an integer. The meaning of this code is platform-dependent.)"),

	"shellCmd", 1, [](CrocThread* t) -> word_t
	{
		croc_pushInt(t, system(croc_ex_checkStringParam(t, 1)));
		return 1;
	}

DListSep()
	Docstr(DFunc("sleep") DParam("duration", "float")
	R"(Pauses execution of the current system thread for at least \tt{duration} seconds.)"),

	"sleep", 1, [](CrocThread* t) -> word_t
	{
		auto dur = croc_ex_checkNumParam(t, 1);

		if(dur < 0)
			croc_eh_throwStd(t, "RangeError", "Invalid sleep duration: %g", dur);

		if(dur > 0)
			oscompat::sleep(cast(uword)(dur * 1000));
		return 0;
	}
DEndList()

	word loader(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);
		return 0;
	}
	}

	void initOSLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "os", &loader);
		croc_ex_importNS(t, "os");
#ifdef CROC_BUILTIN_DOCS
		CrocDoc doc;
		croc_ex_doc_init(t, &doc, __FILE__);
		croc_ex_doc_push(&doc, ModuleDocs);
			docFields(&doc, _globalFuncs);
		croc_ex_doc_pop(&doc, -1);
		croc_ex_doc_finish(&doc);
#endif
		croc_popTop(t);
	}
}