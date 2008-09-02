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

module minid.oslib;

import tango.stdc.stdlib;
import tango.stdc.stringz;
import tango.sys.Environment;
import tango.sys.Process;

import minid.ex;
import minid.interpreter;
import minid.types;
import minid.utils;

struct OSLib
{
static:
// 	private MDProcessClass processClass;
// 	private IOLib.MDInputStreamClass inputStreamClass;
// 	private IOLib.MDOutputStreamClass outputStreamClass;

// 	private this(MDObject _Object, MDNamespace ioLib)
// 	{
// 		processClass = new MDProcessClass(_Object);
// 		inputStreamClass = ioLib["InputStream"d].to!(IOLib.MDInputStreamClass);
// 		outputStreamClass = ioLib["OutputStream"d].to!(IOLib.MDOutputStreamClass);
// 	}
// 
	public void init(MDThread* t)
	{
		pushGlobal(t, "modules");
		field(t, -1, "customLoaders");

		newFunction(t, function uword(MDThread* t, uword numParams)
		{
			importModule(t, "io");
			pop(t);

			ProcessObj.init(t);
			newFunction(t, &system, "system"); newGlobal(t, "system");
			newFunction(t, &getEnv, "getEnv"); newGlobal(t, "getEnv");

			return 0;
		}, "os");
		
		fielda(t, -2, "os");
		importModule(t, "os");
		pop(t, 3);
	}

	uword system(MDThread* t, uword numParams)
	{
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

	uword getEnv(MDThread* t, uword numParams)
	{
		if(numParams == 0)
		{
			newTable(t);

			foreach(k, v; Environment.get())
			{
				pushString(t, k);
				pushString(t, v);
				idxa(t, -3);
			}
		}
		else
		{
			auto val = Environment.get(checkStringParam(t, 1), optStringParam(t, 2, null));

			if(val is null)
				pushNull(t);
			else
				pushString(t, val);
		}

		return 1;
	}

	struct ProcessObj
	{
	static:
		enum Members
		{
			process,
			stdin,
			stdout,
			stderr
		}

		public static void init(MDThread* t)
		{
			CreateObject(t, "Process", (CreateObject* o)
			{
				o.method("clone",     &clone);
				o.method("isRunning", &isRunning);
				o.method("workDir",   &workDir);
				o.method("stdin",     &stdin);
				o.method("stdout",    &stdout);
				o.method("stderr",    &stderr);
				o.method("execute",   &execute);
				o.method("wait",      &wait);
				o.method("kill",      &kill);
			});

			newGlobal(t, "Process");
		}

		Process getProcess(MDThread* t)
		{
			checkObjParam(t, 0, "Process");
			pushExtraVal(t, 0, Members.process);
			auto ret = cast(Process)getNativeObj(t, -1);
			assert(ret !is null);
			pop(t);
			return ret;
		}

		public uword clone(MDThread* t, uword numParams)
		{
			newObject(t, 0, null, 4);
			pushNativeObj(t, new Process());
			setExtraVal(t, -2, Members.process);
			return 1;
		}

		public uword isRunning(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);
			pushBool(t, safeCode(t, p.isRunning()));
			return 1;
		}
		
		public uword workDir(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);

			if(numParams == 0)
			{
				pushString(t, safeCode(t, p.workDir));
				return 1;
			}

			safeCode(t, p.workDir = checkStringParam(t, 1));
			return 0;
		}

		public uword execute(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);

			char[][char[]] env = null;

			if(numParams > 1)
			{
				checkParam(t, 2, MDValue.Type.Table);
				dup(t, 2);

				foreach(word k, word v; foreachLoop(t, 1))
				{
					if(!isString(t, k) || !isString(t, v))
						throwException(t, "env parameter must be a table mapping from strings to strings");

					env[getString(t, k)] = getString(t, v);
				}
			}
			
			if(isString(t, 1))
				safeCode(t, p.execute(getString(t, 1), env));
			else
			{
				checkParam(t, 1, MDValue.Type.Array);
				auto num = len(t, 1);
				auto cmd = new char[][num];
		
				for(uword i = 0; i < num; i++)
				{
					idxi(t, 1, i);
					
					if(!isString(t, -1))
						throwException(t, "cmd parameter must be an array of strings");
						
					cmd[i] = getString(t, -1);
					pop(t);
				}

				safeCode(t, p.execute(cmd, env));
			}

			pushNull(t);
			dup(t);
			setExtraVal(t, 0, Members.stdin);
			dup(t);
			setExtraVal(t, 0, Members.stdout);
			setExtraVal(t, 0, Members.stderr);

			return 0;
		}
		
		public uword stdin(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);

			pushExtraVal(t, 0, Members.stdin);
			
			if(isNull(t, -1))
			{
				pop(t);
				lookupCT!("io.OutputStream")(t);
				pushNull(t);
				pushNativeObj(t, cast(Object)p.stdin.output);
				methodCall(t, -3, "clone", 1);
				dup(t);
				setExtraVal(t, 0, Members.stdin);
			}

			return 1;
		}
		
		public uword stdout(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);

			pushExtraVal(t, 0, Members.stdout);
			
			if(isNull(t, -1))
			{
				pop(t);
				lookupCT!("io.InputStream")(t);
				pushNull(t);
				pushNativeObj(t, cast(Object)p.stdout.input);
				methodCall(t, -3, "clone", 1);
				dup(t);
				setExtraVal(t, 0, Members.stdout);
			}

			return 1;
		}
		
		public uword stderr(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);

			pushExtraVal(t, 0, Members.stderr);
			
			if(isNull(t, -1))
			{
				pop(t);
				lookupCT!("io.InputStream")(t);
				pushNull(t);
				pushNativeObj(t, cast(Object)p.stderr.input);
				methodCall(t, -3, "clone", 1);
				dup(t);
				setExtraVal(t, 0, Members.stderr);
			}

			return 1;
		}
		
		public uword wait(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);
			auto res = safeCode(t, p.wait());

			switch(res.reason)
			{
				case Process.Result.Exit:     pushString(t, "exit"); break;
				case Process.Result.Signal:   pushString(t, "signal"); break;
				case Process.Result.Stop:     pushString(t, "stop"); break;
				case Process.Result.Continue: pushString(t, "continue"); break;
				case Process.Result.Error:    pushString(t, "error"); break;
				default: assert(false);
			}

			pushInt(t, res.status);
			return 2;
		}

		public uword kill(MDThread* t, uword numParams)
		{
			auto p = getProcess(t);
			safeCode(t, p.kill());
			return 0;
		}
	}
}