
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{
const StdlibRegisterInfo _new_info =
{
	Docstr(DFunc("new") DParam("func", "function")
	R"(Create a new thread.

	\param[func] will be the thread's main function.

	\returns the new thread.)"),

	"new", 1
};

word_t _new(CrocThread* t)
{
	croc_ex_checkParam(t, 1, CrocType_Function);
	croc_thread_new(t, 1);
	return 1;
}

const StdlibRegisterInfo _halt_info =
{
	Docstr(DFunc("halt") DParamD("t", "thread", "null")
	R"(Halt a thread of execution.

	\param[t] is the thread to halt. If you don't pass anything for this, the current thread will be halted. If \tt{t}
		is not running, it will have a pending halt placed on it; that is, the next time it is resumed, it will halt
		immediately.)"),

	"halt", 1
};

word_t _halt(CrocThread* t)
{
	if(croc_ex_optParam(t, 1, CrocType_Thread))
		croc_thread_halt(croc_getThread(t, 1));
	else
		croc_thread_halt(t);

	return 0;
}

const StdlibRegisterInfo _current_info =
{
	Docstr(DFunc("current")
	R"(\returns the current thread of execution.)"),

	"current", 0
};

word_t _current(CrocThread* t)
{
	croc_pushThread(t, t);
	return 1;
}

const StdlibRegister _globalFuncs[] =
{
	_DListItem(_new),
	_DListItem(_halt),
	_DListItem(_current),
	_DListEnd
};

const StdlibRegisterInfo _reset_info =
{
	Docstr(DFunc("reset") DParamD("newFunc", "function", "null")
	R"(Resets a dead thread to the initial state.

	\param[newFunc] is an optional function that will replace the thread's old main function. If you pass nothing for
	this, the thread will just use the same main function that it was created with.)"),

	"reset", 1
};

word_t _reset(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Thread);

	if(croc_ex_optParam(t, 1, CrocType_Function))
	{
		croc_dup(t, 1);
		croc_thread_resetWithFunc(t, 0);
	}
	else
		croc_thread_reset(t, 0);

	return 0;
}

const StdlibRegisterInfo _state_info =
{
	Docstr(DFunc("state")
	R"(\returns the state of this thread as one of the following strings:

	\blist
		\li \tt{"initial"}: the thread has not yet been called.
		\li \tt{"running"}: the thread is currently running. Only the current thread is in this state.
		\li \tt{"waiting"}: the thread resumed another thread and is waiting for that thread to yield.
		\li \tt{"suspended"}: the thread yielded and is waiting to be resumed.
		\li \tt{"dead"}: the thread exited its main function. The only thing you can do with a dead thread is call
			\link{reset} on it.
	\endlist)"),

	"state", 0
};

word_t _state(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Thread);
	croc_pushString(t, croc_thread_getStateString(croc_getThread(t, 0)));
	return 1;
}

const StdlibRegisterInfo _isInitial_info =
{
	Docstr(DFunc("isInitial")
	R"(These are just convenience methods to test the state of a thread without having to write out a longer string
	comparison.

	\returns a bool indicating whether this thread is in the given state.)"),

	"isInitial", 0
};

word_t _isInitial(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Thread);
	croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Initial);
	return 1;
}

const StdlibRegisterInfo _isRunning_info =
{
	Docstr(DFunc("isRunning")
	R"(ditto)"),

	"isRunning", 0
};

word_t _isRunning(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Thread);
	croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Running);
	return 1;
}

const StdlibRegisterInfo _isWaiting_info =
{
	Docstr(DFunc("isWaiting")
	R"(ditto)"),

	"isWaiting", 0
};

word_t _isWaiting(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Thread);
	croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Waiting);
	return 1;
}

const StdlibRegisterInfo _isSuspended_info =
{
	Docstr(DFunc("isSuspended")
	R"(ditto)"),

	"isSuspended", 0
};

word_t _isSuspended(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Thread);
	croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Suspended);
	return 1;
}

const StdlibRegisterInfo _isDead_info =
{
	Docstr(DFunc("isDead")
	R"(ditto)"),

	"isDead", 0
};

word_t _isDead(CrocThread* t)
{
	croc_ex_checkParam(t, 0, CrocType_Thread);
	croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Dead);
	return 1;
}

const StdlibRegister _methodFuncs[] =
{
	_DListItem(_reset),
	_DListItem(_state),
	_DListItem(_isInitial),
	_DListItem(_isRunning),
	_DListItem(_isWaiting),
	_DListItem(_isSuspended),
	_DListItem(_isDead),
	_DListEnd
};

word loader(CrocThread* t)
{
	registerGlobals(t, _globalFuncs);

	croc_namespace_new(t, "thread");
		registerFields(t, _methodFuncs);
	croc_vm_setTypeMT(t, CrocType_Thread);
	return 0;
}
}

void initThreadLib(CrocThread* t)
{
	registerModule(t, "thread", &loader);
	croc_pushGlobal(t, "thread");
#ifdef CROC_BUILTIN_DOCS
	CrocDoc doc;
	croc_ex_doc_init(t, &doc, __FILE__);
	croc_ex_doc_push(&doc,
	DModule("thread")
	R"()");
		docFields(&doc, _globalFuncs);

		croc_vm_pushTypeMT(t, CrocType_Thread);
			croc_ex_doc_push(&doc,
			DNs("thread")
			R"(This is the method namespace for thread objects.)");
			docFields(&doc, _methodFuncs);
			croc_ex_doc_pop(&doc, -1);
		croc_popTop(t);
	croc_ex_doc_pop(&doc, -1);
	croc_ex_doc_finish(&doc);
#endif
	croc_popTop(t);
}
}