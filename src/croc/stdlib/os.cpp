
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

const _StdlibRegisterInfo _haveShell_info =
{
	Docstr(DFunc("haveShell")
	R"(\returns a bool indicating whether or not there is a shell command processor available. If there is, you can use
	the \link{shellCmd} function to run shell commands.)"),

	"haveShell", 0
};

word_t _haveShell(CrocThread* t)
{
	croc_pushBool(t, system(nullptr) ? true : false);
	return 1;
}

const _StdlibRegisterInfo _shellCmd_info =
{
	Docstr(DFunc("shellCmd") DParam("cmd", "string")
	R"(Executes the string \tt{cmd} through the system's shell command processor, spawning a subprocess. Execution of
	the calling process waits until the subprocess completes.

	\returns the exit code from the subprocess as an integer. The meaning of this code is platform-dependent.)"),

	"shellCmd", 1
};

word_t _shellCmd(CrocThread* t)
{
	croc_pushInt(t, system(croc_ex_checkStringParam(t, 1)));
	return 1;
}

const _StdlibRegisterInfo _sleep_info =
{
	Docstr(DFunc("sleep") DParam("duration", "float")
	R"(Pauses execution of the current system thread for at least \tt{duration} seconds.)"),

	"sleep", 1
};

word_t _sleep(CrocThread* t)
{
	auto dur = croc_ex_checkNumParam(t, 1);

	if(dur < 0)
		croc_eh_throwStd(t, "RangeError", "Invalid sleep duration: %g", dur);

	if(dur > 0)
		oscompat::sleep(cast(uword)(dur * 1000));
	return 0;
}

const _StdlibRegister _globalFuncs[] =
{
	_DListItem(_haveShell),
	_DListItem(_shellCmd),
	_DListItem(_sleep),
	_DListEnd
};

#ifdef CROC_BUILTIN_DOCS
const char* ProcessDocs = DClass("Process")
R"(This class lets you spawn external processes asynchronously and communicate with them in a one-way fashion.

You can only have access to either its stdin or its stdout stream, but not both. This is because attempting to imitate a
tty programmatically is asking for deadlocks because of buffering in C stdio. Or something like that.

If you need to give the subprocess both input and output, you'll have to use an intermediate file and redirect it in the
command line you pass in the constructor.

\examples

Here's a simple program that just lists the current directory and prints it to stdout.

\code
local p = os.Process("ls .", "r")
console.stdout.getStream().copy(p.stream())
writeln("Exited with code ", p.wait())
\endcode)";
#endif

const _StdlibRegisterInfo _Process_constructor_info =
{
	Docstr(DFunc("constructor") DParam("cmd", "string") DParam("mode", "string")
	R"(Starts a new subprocess.

	\param[cmd] is the command line which will be executed through the shell. As such you can use things like
		redirection and piping. You'll have to use redirection for either input or output if you need both input and
		output.
	\param[mode] should be either \tt{"r"} or \tt{"w"}. If it's \tt{"r"}, the subprocess will inherit this process's
		stdin stream, and its stdout will be redirected to a pipe which you can get with the \link{stream} method. If
		it's \tt{"w"}, the subprocess will inherit this process's stdout stream, and its stdin will be redirected
		instead.)"),

	"constructor", 2
};

word_t _Process_constructor(CrocThread* t)
{
	croc_hfield(t, 0, "proc");

	if(!croc_isNull(t, -1))
		croc_eh_throwStd(t, "StateError", "Calling constructor on already-initialized process");

	croc_popTop(t);

	croc_ex_checkParam(t, 1, CrocType_String);
	croc_ex_checkParam(t, 2, CrocType_String);

	auto cmd = getCrocstr(t, 1);
	auto mode = getCrocstr(t, 2);
	auto access = oscompat::FileAccess::Read;

	if(mode == ATODA("r"))
		access = oscompat::FileAccess::Read;
	else if(mode == ATODA("w"))
		access = oscompat::FileAccess::Write;
	else
		croc_eh_throwStd(t, "ValueError", "Invalid process mode");

	auto proc = oscompat::openProcess(t, cmd, access);
	auto procStream = oscompat::getProcessStream(t, proc);

	if(procStream == oscompat::InvalidHandle)
		oscompat::throwOSEx(t);

	croc_pushNativeobj(t, proc);
	croc_hfielda(t, 0, "proc");

	croc_ex_lookup(t, "stream.NativeStream");
	croc_pushNull(t);
	croc_pushNativeobj(t, cast(void*)cast(uword)procStream);
	croc_dup(t, 2); // gonna be either 'r' or 'w'
	croc_call(t, -4, 1);
	croc_hfielda(t, 0, "stream");

	return 0;
}

const _StdlibRegisterInfo _Process_finalizer_info =
{
	Docstr(DFunc("finalizer")
	R"(Closes the subprocess if it hasn't been already.)"),

	"finalizer", 0
};

word_t _Process_finalizer(CrocThread* t)
{
	croc_hfield(t, 0, "proc");

	if(!croc_isNull(t, -1))
	{
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "wait", 0);
	}

	return 0;
}

const _StdlibRegisterInfo _Process_wait_info =
{
	Docstr(DFunc("wait")
	R"(Waits for the subprocess to complete (if it hasn't yet already) and returns its exit code as an integer.

	This will block as long as necessary.)"),

	"wait", 0
};

word_t _Process_wait(CrocThread* t)
{
	croc_hfield(t, 0, "proc");

	if(croc_isNull(t, -1))
		croc_eh_throwStd(t, "StateError", "Waiting on a dead process");

	auto proc = cast(oscompat::ProcessHandle)croc_getNativeobj(t, -1);
	auto ret = oscompat::closeProcess(t, proc);

	croc_pushNull(t);
	croc_hfielda(t, 0, "proc");
	croc_pushInt(t, ret);
	return 1;
}

const _StdlibRegisterInfo _Process_stream_info =
{
	Docstr(DFunc("stream")
	R"(Gets a \link{stream.NativeStream} instance which represents whichever standard stream was redirected in the
	subprocess (see the \link{constructor} for info).)"),

	"stream", 0
};

word_t _Process_stream(CrocThread* t)
{
	croc_hfield(t, 0, "stream");
	return 1;
}

const _StdlibRegister _Process_methods[] =
{
	_DListItem(_Process_constructor),
	_DListItem(_Process_finalizer),
	_DListItem(_Process_wait),
	_DListItem(_Process_stream),
	_DListEnd
};

word loader(CrocThread* t)
{
	_registerGlobals(t, _globalFuncs);

	croc_class_new(t, "Process", 0);
		croc_pushNull(t); croc_class_addHField(t, -2, "proc");
		croc_pushNull(t); croc_class_addHField(t, -2, "stream");
		_registerMethods(t, _Process_methods);
	croc_newGlobal(t, "Process");
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
		_docFields(&doc, _globalFuncs);

		croc_field(t, -1, "Process");
			croc_ex_doc_push(&doc, ProcessDocs);
			_docFields(&doc, _Process_methods);
			croc_ex_doc_pop(&doc, -1);
		croc_popTop(t);
	croc_ex_doc_pop(&doc, -1);
	croc_ex_doc_finish(&doc);
#endif
	croc_popTop(t);
}
}