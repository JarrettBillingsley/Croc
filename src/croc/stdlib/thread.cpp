
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
DBeginList(_globalFuncs)
	Docstr(DFunc("new") DParam("func", "function")
	R"(Create a new thread.

	\param[func] will be the thread's main function.

	\returns the new thread.)"),

	"new", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_Function);
		croc_thread_new(t, 1);
		return 1;
	}

DListSep()
	Docstr(DFunc("halt") DParamD("t", "thread", "null")
	R"(Halt a thread of execution.

	\param[t] is the thread to halt. If you don't pass anything for this, the current thread will be halted.)"),

	"halt", 1, [](CrocThread* t) -> word_t
	{
		// TODO:halt
		croc_eh_throwStd(t, "ApiError", "thread.halt() Unimplemented");
		return 0;
	}

DListSep()
	Docstr(DFunc("current")
	R"(\returns the current thread of execution.)"),

	"current", 0, [](CrocThread* t) -> word_t
	{
		croc_pushThread(t, t);
		return 1;
	}
DEndList()

DBeginList(_methodFuncs)
	Docstr(DFunc("reset") DParamD("newFunc", "function", "null")
	R"(Resets a dead thread to the initial state.

	\param[newFunc] is an optional function that will replace the thread's old main function. If you pass nothing for
	this, the thread will just use the same main function that it was created with.)"),

	"reset", 1, [](CrocThread* t) -> word_t
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

DListSep()
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

	"state", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Thread);
		croc_pushString(t, croc_thread_getStateString(croc_getThread(t, 0)));
		return 1;
	}

DListSep()
	Docstr(DFunc("isInitial")
	R"(These are just convenience methods to test the state of a thread without having to write out a longer string
	comparison.

	\returns a bool indicating whether this thread is in the given state.)"),

	"isInitial", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Thread);
		croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Initial);
		return 1;
	}

DListSep()
	Docstr(DFunc("isRunning")
	R"(ditto)"),

	"isRunning", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Thread);
		croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Running);
		return 1;
	}

DListSep()
	Docstr(DFunc("isWaiting")
	R"(ditto)"),

	"isWaiting", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Thread);
		croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Waiting);
		return 1;
	}

DListSep()
	Docstr(DFunc("isSuspended")
	R"(ditto)"),

	"isSuspended", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Thread);
		croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Suspended);
		return 1;
	}

DListSep()
	Docstr(DFunc("isDead")
	R"(ditto)"),

	"isDead", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Thread);
		croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Dead);
		return 1;
	}
DEndList()

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
		croc_ex_makeModule(t, "thread", &loader);
		croc_ex_importNS(t, "thread");
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