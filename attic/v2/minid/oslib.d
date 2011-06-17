/******************************************************************************
License:
Copyright (c) 2007 Jarrett Billingsley

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

import minid.iolib;
import minid.types;
import minid.utils;

import tango.stdc.stdlib;
import tango.stdc.stringz;
import tango.sys.Environment;
import tango.sys.Process;

final class OSLib
{
	private MDProcessClass processClass;
	private IOLib.MDInputStreamClass inputStreamClass;
	private IOLib.MDOutputStreamClass outputStreamClass;

	private this(MDObject _Object, MDNamespace ioLib)
	{
		processClass = new MDProcessClass(_Object);
		inputStreamClass = ioLib["InputStream"d].to!(IOLib.MDInputStreamClass);
		outputStreamClass = ioLib["OutputStream"d].to!(IOLib.MDOutputStreamClass);
	}

	public static void init(MDContext context)
	{
		context.setModuleLoader("os", context.newClosure(function int(MDState s, uint numParams)
		{
			auto ioLib = s.context.importModule("io");
			auto osLib = new OSLib(s.context.globals.get!(MDObject)("Object"d), ioLib);

			auto lib = s.getParam!(MDNamespace)(1);

			lib.addList
			(
				"Process"d,      osLib.processClass,
				"system"d,       new MDClosure(lib, &system,     "os.system"),
				"getEnv"d,       new MDClosure(lib, &getEnv,     "os.getEnv")
			);

			return 0;
		}, "os"));

		context.importModule("os");
	}

	static int system(MDState s, uint numParams)
	{
		if(numParams == 0)
			s.push(.system(null) ? true : false);
		else
			s.push(.system(toStringz(s.getParam!(char[])(0))));

		return 1;
	}

	static int getEnv(MDState s, uint numParams)
	{
		if(numParams == 0)
			s.push(Environment.get());
		else
		{
			char[] def = null;
			
			if(numParams > 1)
				def = s.getParam!(char[])(1);

			char[] val = Environment.get(s.getParam!(char[])(0), def);

			if(val is null)
				s.pushNull();
			else
				s.push(val);
		}
		
		return 1;
	}

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
		
		public int clone(MDState s, uint numParams)
		{
			s.push(new MDProcess(this));
			return 1;
		}
		
		public int isRunning(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDProcess)().mProcess.isRunning()));
			return 1;
		}
		
		public int workDir(MDState s, uint numParams)
		{
			if(numParams == 0)
			{
				s.push(s.safeCode(s.getContext!(MDProcess)().mProcess.workDir()));
				return 1;
			}

			s.safeCode(s.getContext!(MDProcess)().mProcess.workDir(s.getParam!(char[])(0)));
			return 0;
		}

		public int execute(MDState s, uint numParams)
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
		
		public int stdin(MDState s, uint numParams)
		{
			auto self = s.getContext!(MDProcess);

			if(!self.mStdin)
				self.mStdin = outputStreamClass.nativeClone(self.mProcess.stdin.output);

			s.push(self.mStdin);
			return 1;
		}
		
		public int stdout(MDState s, uint numParams)
		{
			auto self = s.getContext!(MDProcess);

			if(!self.mStdout)
				self.mStdout = inputStreamClass.nativeClone(self.mProcess.stdout.input);

			s.push(self.mStdout);
			return 1;
		}
		
		public int stderr(MDState s, uint numParams)
		{
			auto self = s.getContext!(MDProcess);

			if(!self.mStderr)
				self.mStderr = inputStreamClass.nativeClone(self.mProcess.stderr.input);

			s.push(self.mStderr);
			return 1;
		}
		
		public int wait(MDState s, uint numParams)
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

		public int kill(MDState s, uint numParams)
		{
			s.safeCode(s.getContext!(MDProcess)().mProcess.kill());
			return 0;
		}
	}
}