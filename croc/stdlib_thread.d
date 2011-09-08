/******************************************************************************
This module contains the 'thread' standard library, which is part of the base
library.

License:
Copyright (c) 2008 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module croc.stdlib_thread;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.types;
import croc.vm;

struct ThreadLib
{
static:
	public void init(CrocThread* t)
	{
		makeModule(t, "thread", function uword(CrocThread* t)
		{
			newFunction(t, 1, &halt,      "halt");      newGlobal(t, "halt");
			newFunction(t, 0, &current,   "current");   newGlobal(t, "current");

			newNamespace(t, "thread");
				newFunction(t, 1, &reset,       "reset");       fielda(t, -2, "reset");
				newFunction(t, 0, &state,       "state");       fielda(t, -2, "state");
				newFunction(t, 0, &isInitial,   "isInitial");   fielda(t, -2, "isInitial");
				newFunction(t, 0, &isRunning,   "isRunning");   fielda(t, -2, "isRunning");
				newFunction(t, 0, &isWaiting,   "isWaiting");   fielda(t, -2, "isWaiting");
				newFunction(t, 0, &isSuspended, "isSuspended"); fielda(t, -2, "isSuspended");
				newFunction(t, 0, &isDead,      "isDead");      fielda(t, -2, "isDead");
			setTypeMT(t, CrocValue.Type.Thread);

			return 0;
		});

		importModuleNoNS(t, "thread");
	}

	uword halt(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		if(numParams == 0)
			haltThread(t);
		else
		{
			checkParam(t, 1, CrocValue.Type.Thread);
			auto thread = getThread(t, 1);
			// if thread is t, this immediately halts, otherwise it puts a pending halt on it
			haltThread(thread);
			auto reg = pushThread(t, thread);
			pushNull(t);
			rawCall(t, reg, 0);
		}

		return 0;
	}

	uword current(CrocThread* t)
	{
		if(t is mainThread(getVM(t)))
			pushNull(t);
		else
			pushThread(t, t);

		return 1;
	}

	uword reset(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Thread);

		if(optParam(t, 1, CrocValue.Type.Function))
		{
			dup(t, 1);
			resetThread(t, 0, true);
		}
		else
			resetThread(t, 0);

		return 0;
	}

	uword state(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Thread);
		pushString(t, .stateString(getThread(t, 0)));
		return 1;
	}

	uword isInitial(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Thread);
		pushBool(t, .state(getThread(t, 0)) == CrocThread.State.Initial);
		return 1;
	}

	uword isRunning(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Thread);
		pushBool(t, .state(getThread(t, 0)) == CrocThread.State.Running);
		return 1;
	}

	uword isWaiting(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Thread);
		pushBool(t, .state(getThread(t, 0)) == CrocThread.State.Waiting);
		return 1;
	}

	uword isSuspended(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Thread);
		pushBool(t, .state(getThread(t, 0)) == CrocThread.State.Suspended);
		return 1;
	}

	uword isDead(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Thread);
		pushBool(t, .state(getThread(t, 0)) == CrocThread.State.Dead);
		return 1;
	}
}