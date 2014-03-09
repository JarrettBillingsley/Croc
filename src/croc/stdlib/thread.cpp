
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
	word_t _new(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Function);
		croc_thread_new(t, 1);
		return 1;
	}

	word_t _halt(CrocThread* t)
	{
		// TODO:halt
		croc_eh_throwStd(t, "ApiError", "thread.halt() Unimplemented");
		return 0;
	}

	word_t _current(CrocThread* t)
	{
		croc_pushThread(t, t);
		return 1;
	}

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

	word_t _state(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Thread);
		croc_pushString(t, croc_thread_getStateString(croc_getThread(t, 0)));
		return 1;
	}

	word_t _isInitial(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Thread);
		croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Initial);
		return 1;
	}

	word_t _isRunning(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Thread);
		croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Running);
		return 1;
	}

	word_t _isWaiting(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Thread);
		croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Waiting);
		return 1;
	}

	word_t _isSuspended(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Thread);
		croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Suspended);
		return 1;
	}

	word_t _isDead(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Thread);
		croc_pushBool(t, croc_thread_getState(croc_getThread(t, 0)) == CrocThreadState_Dead);
		return 1;
	}

	const CrocRegisterFunc _globalFuncs[] =
	{
		{"new",     1, &_new    },
		{"halt",    1, &_halt   },
		{"current", 0, &_current},
		{nullptr, 0, nullptr}
	};

	const CrocRegisterFunc _methodFuncs[] =
	{
		{"reset",       1, &_reset      },
		{"state",       0, &_state      },
		{"isInitial",   0, &_isInitial  },
		{"isRunning",   0, &_isRunning  },
		{"isWaiting",   0, &_isWaiting  },
		{"isSuspended", 0, &_isSuspended},
		{"isDead",      0, &_isDead     },
		{nullptr, 0, nullptr}
	};

	word loader(CrocThread* t)
	{
		croc_ex_registerGlobals(t, _globalFuncs);

		croc_namespace_new(t, "thread");
			croc_ex_registerFields(t, _methodFuncs);
		croc_vm_setTypeMT(t, CrocType_Thread);
		return 0;
	}
	}

	void initThreadLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "thread", &loader);
		croc_ex_import(t, "thread");
	}
}