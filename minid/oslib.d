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
// 			auto ioLib = importModule(t, "io");
			// Don't forget to pop ioLib!
// 			auto osLib = new OSLib(s.context.globals.get!(MDObject)("Object"d), ioLib);

// 			"Process"d,      osLib.processClass,
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

/+
	class MDProcessClass : MDObject
	{
		static class MDProcess : MDObject
		{
			protected Process mProcess;
			protected MDObject mStdin;
			protected MDObject mStdout;
			protected MDObject mStderr;

			public this(MDObject owner)
			{
				super("Process", owner);
				mProcess = new Process();
			}
		}

		public this(MDObject owner)
		{
			super("Process", owner);
			
			fields.addList
			(
				"clone"d,     new MDClosure(fields, &clone,     "Process.clone"),
				"isRunning"d, new MDClosure(fields, &isRunning, "Process.isRunning"),
				"workDir"d,   new MDClosure(fields, &workDir,   "Process.workDir"),
				"stdin"d,     new MDClosure(fields, &stdin,     "Process.stdin"),
				"stdout"d,    new MDClosure(fields, &stdout,    "Process.stdout"),
				"stderr"d,    new MDClosure(fields, &stderr,    "Process.stderr"),
				"execute"d,   new MDClosure(fields, &execute,   "Process.execute"),
				"wait"d,      new MDClosure(fields, &wait,      "Process.wait"),
				"kill"d,      new MDClosure(fields, &kill,      "Process.kill")
			);
		}
		
		public uword clone(MDThread* t, uword numParams)
		{
			s.push(new MDProcess(this));
			return 1;
		}
		
		public uword isRunning(MDThread* t, uword numParams)
		{
			s.push(s.safeCode(s.getContext!(MDProcess)().mProcess.isRunning()));
			return 1;
		}
		
		public uword workDir(MDThread* t, uword numParams)
		{
			if(numParams == 0)
			{
				s.push(s.safeCode(s.getContext!(MDProcess)().mProcess.workDir()));
				return 1;
			}

			s.safeCode(s.getContext!(MDProcess)().mProcess.workDir(s.getParam!(char[])(0)));
			return 0;
		}

		public uword execute(MDThread* t, uword numParams)
		{
			auto self = s.getContext!(MDProcess);

			char[][char[]] env = null;

			if(numParams > 1)
				env = s.getParam!(char[][char[]])(1);

			if(s.isParam!("string")(0))
				s.safeCode(self.mProcess.execute(s.getParam!(char[])(0), env));
			else
				s.safeCode(self.mProcess.execute(s.getParam!(char[][])(0), env));

			self.mStdin = null;
			self.mStdout = null;
			self.mStderr = null;

			return 0;
		}
		
		public uword stdin(MDThread* t, uword numParams)
		{
			auto self = s.getContext!(MDProcess);

			if(!self.mStdin)
				self.mStdin = outputStreamClass.nativeClone(self.mProcess.stdin.output);

			s.push(self.mStdin);
			return 1;
		}
		
		public uword stdout(MDThread* t, uword numParams)
		{
			auto self = s.getContext!(MDProcess);

			if(!self.mStdout)
				self.mStdout = inputStreamClass.nativeClone(self.mProcess.stdout.input);

			s.push(self.mStdout);
			return 1;
		}
		
		public uword stderr(MDThread* t, uword numParams)
		{
			auto self = s.getContext!(MDProcess);

			if(!self.mStderr)
				self.mStderr = inputStreamClass.nativeClone(self.mProcess.stderr.input);

			s.push(self.mStderr);
			return 1;
		}
		
		public uword wait(MDThread* t, uword numParams)
		{
			auto res = s.safeCode(s.getContext!(MDProcess)().mProcess.wait());
			
			switch(res.reason)
			{
				case Process.Result.Exit:     s.push("exit"); break;
				case Process.Result.Signal:   s.push("signal"); break;
				case Process.Result.Stop:     s.push("stop"); break;
				case Process.Result.Continue: s.push("continue"); break;
				case Process.Result.Error:    s.push("error"); break;
			}

			s.push(res.status);
			return 2;
		}

		public uword kill(MDThread* t, uword numParams)
		{
			s.safeCode(s.getContext!(MDProcess)().mProcess.kill());
			return 0;
		}
	}
+/
}