/******************************************************************************
This module contains the 'os' standard library.

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

module croc.stdlib_os;

import tango.core.Thread;
import tango.stdc.stdlib;
import tango.stdc.stringz;
import tango.sys.Process;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_library;
import croc.types;
import croc.utils;

struct OSLib
{
static:
	void init(CrocThread* t)
	{
		makeModule(t, "os", function uword(CrocThread* t)
		{
			importModuleNoNS(t, "stream");

			ProcessObj.init(t);
			newFunction(t,    &system, "system"); newGlobal(t, "system");
			newFunction(t, 1, &sleep,  "sleep");  newGlobal(t, "sleep");

			return 0;
		});

		importModuleNoNS(t, "os");
	}

	uword system(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		if(numParams == 0)
			pushBool(t, .system(null) ? true : false);
		else
		{
			auto cmd = checkStringParam(t, 1);

			if(cmd.length < 128)
			{
				char[128] buf = void;
				buf[0 .. cmd.length] = cmd[];
				buf[cmd.length] = 0;
				pushInt(t, .system(buf.ptr));
			}
			else
			{
				auto arr = t.vm.alloc.allocArray!(char)(cmd.length + 1);
				scope(exit) t.vm.alloc.freeArray(arr);
				arr[0 .. cmd.length] = cmd[];
				arr[cmd.length] = 0;
				pushInt(t, .system(arr.ptr));
			}
		}

		return 1;
	}

	uword sleep(CrocThread* t)
	{
		auto dur = checkNumParam(t, 1);

		if(dur < 0)
			throwStdException(t, "RangeException", "Invalid sleep duration: {}", dur);

		Thread.sleep(dur);
		return 0;
	}

	struct ProcessObj
	{
	static:
		enum Fields
		{
			process,
			stdin,
			stdout,
			stderr
		}

		static void init(CrocThread* t)
		{
			CreateClass(t, "Process", (CreateClass* c)
			{
				c.method("constructor", &constructor);
				c.method("isRunning",   &isRunning);
				c.method("workDir",     &workDir);
				c.method("stdin",       &stdin);
				c.method("stdout",      &stdout);
				c.method("stderr",      &stderr);
				c.method("execute",     &execute);
				c.method("wait",        &wait);
				c.method("kill",        &kill);
			});

			newFunction(t, &allocator, "Process.allocator");
			setAllocator(t, -2);

			newGlobal(t, "Process");
		}

		Process getProcess(CrocThread* t)
		{
			checkInstParam(t, 0, "Process");
			getExtraVal(t, 0, Fields.process);
			auto ret = cast(Process)getNativeObj(t, -1);
			assert(ret !is null);
			pop(t);
			return ret;
		}

		uword allocator(CrocThread* t)
		{
			newInstance(t, 0, Fields.max + 1);

			dup(t);
			pushNull(t);
			rotateAll(t, 3);
			methodCall(t, 2, "constructor", 0);
			return 1;
		}

		uword constructor(CrocThread* t)
		{
			auto numParams = stackSize(t) - 1;
			checkInstParam(t, 0, "Process");

			getExtraVal(t, 0, Fields.process);

			if(!isNull(t, -1))
				throwStdException(t, "StateException", "Attempting to call constructor on an already-initialized Process");

			pop(t);

			pushNativeObj(t, new Process());
			setExtraVal(t, 0, Fields.process);

			if(numParams > 0)
			{
				dup(t, 0);
				pushNull(t);
				rotateAll(t, 2);
				methodCall(t, 1, "execute", 0);
			}

			return 0;
		}

		uword isRunning(CrocThread* t)
		{
			auto p = getProcess(t);
			pushBool(t, safeCode(t, "exceptions.OSException", p.isRunning()));
			return 1;
		}

		uword workDir(CrocThread* t)
		{
			auto numParams = stackSize(t) - 1;
			auto p = getProcess(t);

			if(numParams == 0)
			{
				pushString(t, safeCode(t, "exceptions.OSException", p.workDir));
				return 1;
			}

			safeCode(t, "exceptions.OSException", p.workDir = checkStringParam(t, 1));
			return 0;
		}

		uword execute(CrocThread* t)
		{
			auto numParams = stackSize(t) - 1;
			auto p = getProcess(t);

			char[][char[]] env = null;

			if(numParams > 1)
			{
				checkParam(t, 2, CrocValue.Type.Table);
				dup(t, 2);

				foreach(word k, word v; foreachLoop(t, 1))
				{
					if(!isString(t, k) || !isString(t, v))
						throwStdException(t, "ValueException", "env parameter must be a table mapping from strings to strings");

					env[getString(t, k)] = getString(t, v);
				}
			}

			p.env = env;

			if(isString(t, 1))
			{
				p.programName = getString(t, 1);
				safeCode(t, "exceptions.OSException", p.execute());
			}
			else
			{
				checkParam(t, 1, CrocValue.Type.Array);
				auto num = len(t, 1);
				auto cmd = new char[][cast(uword)num];

				for(uword i = 0; i < num; i++)
				{
					idxi(t, 1, i);

					if(!isString(t, -1))
						throwStdException(t, "ValueException", "cmd parameter must be an array of strings");

					cmd[i] = getString(t, -1);
					pop(t);
				}

				p.args(cmd[0], cmd[1 .. $]);
				safeCode(t, "exceptions.OSException", p.execute());
			}

			clearStreams(t);

			return 0;
		}

		uword stdin(CrocThread* t)
		{
			auto p = getProcess(t);

			if(!safeCode(t, "exceptions.OSException", p.isRunning()))
				throwStdException(t, "StateException", "Attempting to get stdin of process that isn't running");

			getExtraVal(t, 0, Fields.stdin);

			if(isNull(t, -1))
			{
				pop(t);
				lookupCT!("stream.OutStream")(t);
				pushNull(t);
				pushNativeObj(t, cast(Object)p.stdin.output);
				pushBool(t, true);
				rawCall(t, -4, 1);
				dup(t);
				setExtraVal(t, 0, Fields.stdin);
			}

			return 1;
		}

		uword stdout(CrocThread* t)
		{
			auto p = getProcess(t);

			if(!safeCode(t, "exceptions.OSException", p.isRunning()))
				throwStdException(t, "StateException", "Attempting to get stdout of process that isn't running");

			getExtraVal(t, 0, Fields.stdout);

			if(isNull(t, -1))
			{
				pop(t);
				lookupCT!("stream.InStream")(t);
				pushNull(t);
				pushNativeObj(t, cast(Object)p.stdout.input);
				pushBool(t, true);
				rawCall(t, -4, 1);
				dup(t);
				setExtraVal(t, 0, Fields.stdout);
			}

			return 1;
		}

		uword stderr(CrocThread* t)
		{
			auto p = getProcess(t);

			if(!safeCode(t, "exceptions.OSException", p.isRunning()))
				throwStdException(t, "StateException", "Attempting to get stderr of process that isn't running");

			getExtraVal(t, 0, Fields.stderr);

			if(isNull(t, -1))
			{
				pop(t);
				lookupCT!("stream.InStream")(t);
				pushNull(t);
				pushNativeObj(t, cast(Object)p.stderr.input);
				pushBool(t, true);
				rawCall(t, -4, 1);
				dup(t);
				setExtraVal(t, 0, Fields.stderr);
			}

			return 1;
		}

		uword wait(CrocThread* t)
		{
			auto p = getProcess(t);

			getExtraVal(t, 0, Fields.stdin);

			if(!isNull(t, -1))
			{
				dup(t, -1);
				pushNull(t);
				methodCall(t, -2, "isOpen", 1);

				if(getBool(t, -1))
				{
					pop(t);
					pushNull(t);
					methodCall(t, -2, "flush", 0);
				}
				else
					pop(t, 2);
			}
			else
				pop(t);

			auto res = safeCode(t, "exceptions.OSException", p.wait());

			switch(res.reason)
			{
				case Process.Result.Exit:     pushString(t, "exit");     break;
				case Process.Result.Signal:   pushString(t, "signal");   break;
				case Process.Result.Stop:     pushString(t, "stop");     break;
				case Process.Result.Continue: pushString(t, "continue"); break;
				case Process.Result.Error:    pushString(t, "error");    break;
				default: assert(false);
			}

			clearStreams(t);
			pushInt(t, res.status);
			return 2;
		}

		uword kill(CrocThread* t)
		{
			auto p = getProcess(t);
			safeCode(t, "exceptions.OSException", p.kill());
			clearStreams(t);
			return 0;
		}

		void clearStreams(CrocThread* t)
		{
			pushNull(t);
			dup(t);
			dup(t);
			setExtraVal(t, 0, Fields.stdin);
			setExtraVal(t, 0, Fields.stdout);
			setExtraVal(t, 0, Fields.stderr);
		}
	}
}