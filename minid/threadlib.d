/******************************************************************************
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

module minid.threadlib;

import minid.ex;
import minid.interpreter;
import minid.types;
import minid.vm;

struct ThreadLib
{
static:
	public void init(MDThread* t)
	{
		pushGlobal(t, "modules");
		field(t, -1, "customLoaders");
		
		newFunction(t, function uword(MDThread* t, uword numParams)
		{
// 			newFunction(t, &traceback, "traceback"); newGlobal(t, "traceback");
			newFunction(t, &halt,      "halt");      newGlobal(t, "halt");
			newFunction(t, &current,   "current");   newGlobal(t, "current");

			newNamespace(t, "thread");
				newFunction(t, &reset,       "reset");       fielda(t, -2, "reset");
				newFunction(t, &state,       "state");       fielda(t, -2, "state");
				newFunction(t, &isInitial,   "isInitial");   fielda(t, -2, "isInitial");
				newFunction(t, &isRunning,   "isRunning");   fielda(t, -2, "isRunning");
				newFunction(t, &isWaiting,   "isWaiting");   fielda(t, -2, "isWaiting");
				newFunction(t, &isSuspended, "isSuspended"); fielda(t, -2, "isSuspended");
				newFunction(t, &isDead,      "isDead");      fielda(t, -2, "isDead");

					newFunction(t, &iterator, "iterator");
				newFunction(t, &opApply, "opApply", 1);      fielda(t, -2, "opApply");
			setTypeMT(t, MDValue.Type.Thread);

			return 0;
		}, "thread");

		fielda(t, -2, "thread");
		importModule(t, "thread");
		pop(t, 3);
	}
	
/*
	uword traceback(MDThread* t, uword numParams)
	{
		s.push(new MDString(s.context.getTracebackString()));
		return 1;
	}
*/
	uword halt(MDThread* t, uword numParams)
	{
		if(numParams == 0)
			haltThread(t);
		else
		{
			checkParam(t, 1, MDValue.Type.Thread);
			auto thread = getThread(t, 1);
			// if thread is t, this immediately halts, otherwise it puts a pending halt on it
			haltThread(thread);
			auto reg = pushThread(t, thread);
			pushNull(t);
			rawCall(t, reg, 0);
		}

		return 0;
	}

	uword current(MDThread* t, uword numParams)
	{
		if(t is mainThread(getVM(t)))
			pushNull(t);
		else
			pushThread(t, t);

		return 1;
	}

	uword reset(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);

		if(optParam(t, 1, MDValue.Type.Function))
		{
			dup(t, 1);
			resetThread(t, 0, true);
		}
		else
			resetThread(t, 0);

		return 0;
	}

	uword state(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		pushString(t, .stateString(getThread(t, 0)));
		return 1;
	}

	uword isInitial(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		pushBool(t, .state(getThread(t, 0)) == MDThread.State.Initial);
		return 1;
	}

	uword isRunning(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		pushBool(t, .state(getThread(t, 0)) == MDThread.State.Running);
		return 1;
	}

	uword isWaiting(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		pushBool(t, .state(getThread(t, 0)) == MDThread.State.Waiting);
		return 1;
	}

	uword isSuspended(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		pushBool(t, .state(getThread(t, 0)) == MDThread.State.Suspended);
		return 1;
	}

	uword isDead(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		pushBool(t, .state(getThread(t, 0)) == MDThread.State.Dead);
		return 1;
	}

	uword iterator(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		auto thread = getThread(t, 0);

		pushInt(t, checkIntParam(t, 1) + 1);

		auto slot = pushThread(t, thread);
		pushNull(t);
		auto numRets = rawCall(t, slot, -1);

		if(.state(thread) == MDThread.State.Dead)
			return 0;

		return numRets + 1;
	}

	uword opApply(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Thread);
		auto haveParam = isValidIndex(t, 1);
		auto thread = getThread(t, 0);

		if(.state(thread) != MDThread.State.Initial)
			throwException(t, "Iterated coroutine must be in the initial state");

		auto slot = pushThread(t, thread);
		dup(t);

		if(haveParam)
			dup(t, 1);
		else
			pushNull(t);

		rawCall(t, slot, 0);

		getUpval(t, 0);
		pushThread(t, thread);
		pushInt(t, -1);
		return 3;
	}
}