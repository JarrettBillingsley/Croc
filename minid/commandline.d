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

module minid.commandline;

import tango.io.Console;
import tango.io.device.FileConduit;
import tango.io.model.IConduit;
import tango.io.Print;
import tango.io.protocol.Reader;
import tango.io.Stdout;
import tango.stdc.ctype;
import tango.stdc.signal;
import tango.text.convert.Layout;
import tango.text.stream.LineIterator;
import tango.text.Util;
import Uni = tango.text.Unicode;
import Utf = tango.text.convert.Utf;

import minid.compiler;
import minid.ex;
import minid.interpreter;
import minid.serialization;
import minid.types;
import minid.utils;

/**
This struct encapsulates a MiniD command-line interpreter.  This is the CLI that
MDCL uses, so you can actually embed an MDCL-like interpreter in your application
by using this struct.

This struct installs a signal handler that catches Ctrl+C (SIGINT) signals.  It restores
the old signal handler when it exits.
*/
struct CommandLine
{
	const char[] Prompt1 = ">>> ";
	const char[] Prompt2 = "... ";
	const char[] Usage =
"
Flags:
    -i        Enter interactive mode, after executing any script file.
    -v        Print the version of the CLI.
    -h        Print this message and end.
    -I path   Specifies an import path to search when importing modules.

If mdcl is called without any arguments, it will be as if you passed it
the -v and -i arguments (it will print the version and enter interactive
mode).

If the filename has no extension, it will be treated as a MiniD import-
style module name.  So \"a.b\" will look for a module named b in the a
directory.  The -I flag also affects the search paths used for this.

When passing a filename followed by args, all the args will be available
to the script by using the vararg expression.  The arguments will all be
strings.

In interactive mode, you will be given a >>> prompt.  When you hit enter,
you may be given a ... prompt.  That means you need to type more to make
the code complete.  Once you enter enough code to make it complete, the
code will be run.  If there is an error, the code buffer is cleared.
To end interactive mode, use the \"exit()\" function.
";
/+ Stupid editor has issues with multiline strings. "+/

	private Print!(char) mOutput;
	private LineIterator!(char) mInput;

	/**
	Construct an instance of the CLI.
	
	Params:
		output = The Print object to which output will be sent.
		input = The InputStream from which user input will be gathered.
		
	Returns:
		An initialized instance of CommandLine.
	*/
	public static CommandLine opCall(Print!(char) output, InputStream input)
	{
		CommandLine ret;
		ret.mOutput = output;
		ret.mInput = new LineIterator!(char)(input);
		return ret;
	}
	
	/**
	Same as above, but takes a raw OutputStream for the output instead of
	a Print instance.
	*/
	public static CommandLine opCall(OutputStream output, InputStream input)
	{
		return opCall(new Print!(char)(new Layout!(char), output), input);
	}
	
	/**
	Constructs a default instance of CommandLine which uses stdin for the input
	and stdout for the output.
	*/
	public static CommandLine opCall()
	{
		return opCall(Stdout, Cin.stream);
	}

	private void printVersion()
	{
		mOutput("MiniD Command-Line interpreter 2.0 beta").newline;
	}

	private void printUsage(char[] progname)
	{
		printVersion();
		mOutput("Usage:").newline;
		mOutput("\t")(progname)(" [flags] [filename [args]]").newline;
		mOutput(Usage);
	}

	/**
	After you've created an instance of this struct, call this method on it.  The arguments
	are the arguments that would be passed to MDCL, including the program name as item 0.
	This function returns when the user exits the interpreter (by using the exit() function,
	usually).
	
	Params:
		t = The thread to use for this CLI.
		args = The arguments to the interpreter.  Defaults to null, in which case no arguments
			will be passed.
	*/
	public void run(MDThread* t, char[][] args = null)
	{
		bool printedVersion = false;
		bool printedUsage = false;
		bool interactive = false;
		char[] inputFile;
		char[] progname = (args.length > 0) ? args[0] : "";

		if(args.length == 1 || args == null)
			interactive = true;

		_argLoop: for(int i = 1; i < args.length; i++)
		{
			switch(args[i])
			{
				case "-i":
					interactive = true;
					break;
	
				case "-v":
					if(!printedVersion)
					{
						printedVersion = true;
						printVersion();
					}
					break;
					
				case "-h":
					if(!printedUsage)
					{
						printedUsage = true;
						printUsage(progname);
					}
					return;
					
				case "-I":
					i++;
					
					if(i >= args.length)
					{
						mOutput("-I must be followed by a path").newline;
						printUsage(progname);
						return;
					}
					
					pushGlobal(t, "modules");
					field(t, -1, "path");
					pushChar(t, ';');
					pushString(t, args[i]);
					cateq(t, -3, 2);
					fielda(t, -2, "path");
					pop(t);
					break;

				default:
					if(args[i][0] == '-')
					{
						mOutput("Unknown flag '{}'.", args[i]);
						return;
					}
	
					inputFile = args[i];
					args = args[i + 1 .. $];
					break _argLoop;
			}
		}

		if(inputFile.length > 0)
		{
			word reg;

			try
			{
				if(!inputFile.endsWith(".md") && !inputFile.endsWith(".mdm"))
					reg = importModule(t, inputFile);
				else
				{
					if(inputFile.endsWith(".md"))
					{
						scope c = new Compiler(t);
						c.compileModule(inputFile);
					}
					else
					{
						scope fc = new FileConduit(inputFile, FileConduit.ReadExisting);
						scope r = new Reader(fc);
						deserializeModule(t, r);
					}

					lookup(t, "modules.initModule");
					swap(t);
					pushNull(t);
					swap(t);
					pushString(t, funcName(t, -1));
					rawCall(t, -4, 1);
					reg = stackSize(t) - 1;
				}

				pushNull(t);
				lookup(t, "modules.runMain");
				swap(t, -3);

				foreach(a; args)
					pushString(t, a);

				rawCall(t, reg, 0);
			}
			catch(MDException e)
			{
				catchException(t);
				pop(t);

				mOutput.formatln("Error: {}", e);

				auto tb = getTraceback(t);
				mOutput.formatln("{}", getString(t, tb));
				pop(t);
				mOutput.newline;
			}
		}

		if(interactive)
		{
			if(!printedVersion)
				printVersion();

			char[] buffer;

			// static so exit can access it.
			static bool run;
			run = true;

			newFunction(t, function uword(MDThread* t, uword numParams)
				{
					run = false;
					return 0;
				}, "exit");
			newGlobal(t, "exit");

			mOutput("Use the \"exit()\" function to end.").newline;
			mOutput(Prompt1)();

			// static so the interrupt handler can access it.
			static bool didHalt = false;
			didHalt = false;
			static MDThread* thread;
			thread = t;

			static extern(C) void interruptHandler(int s)
			{
				pendingHalt(thread);
				didHalt = true;
				signal(s, &interruptHandler);
			}

			auto oldInterrupt = signal(SIGINT, &interruptHandler);

			scope(exit)
				signal(SIGINT, oldInterrupt);

			bool couldBeDecl()
			{
				auto temp = buffer.triml();
				return temp.startsWith("function") || temp.startsWith("class") || temp.startsWith("namespace") || temp.startsWith("@");
			}

			bool tryAsStatement(Exception e = null)
			{
				scope c = new Compiler(t);
				word reg;

				try
					reg = c.compileStatements(buffer, "stdin");
				catch(MDException e2)
				{
					catchException(t);
					pop(t);

					if(c.isEof())
					{
						mOutput(Prompt2).flush;
						return true;
					}
					else if(c.isLoneStmt())
					{
						if(e)
						{
							mOutput.formatln("When attempting to evaluate as an expression:");
							mOutput.formatln("Error: {}", e);
							mOutput.formatln("When attempting to evaluate as a statement:");
						}
					}

					mOutput.formatln("Error: {}", e2).newline;
					
					return false;
				}

				try
				{
					pushNull(t);
					rawCall(t, reg, 0);
				}
				catch(MDException e2)
				{
					catchException(t);
					pop(t);

					mOutput.formatln("Error: {}", e2);

					getTraceback(t);
					mOutput.formatln("{}", getString(t, -1));
					pop(t);
					mOutput.newline;
				}

				return false;
			}

			bool tryAsExpression()
			{
				scope c = new Compiler(t);
				word reg;

				try
					reg = c.compileExpression(buffer, "stdin");
				catch(MDException e)
				{
					catchException(t);
					pop(t);

					if(c.isEof())
					{
						mOutput(Prompt2)();
						return true;
					}
					else
						return tryAsStatement(e);
				}

				try
				{
					pushNull(t);
					auto numRets = rawCall(t, reg, -1);

					if(numRets > 0)
					{
						mOutput(" => ");

						bool first = true;

						for(word i = stackSize(t) - numRets; i < stackSize(t); i++)
						{
							if(first)
								first = false;
							else
								mOutput(", ");

							reg = pushGlobal(t, "dumpVal");
							pushNull(t);
							dup(t, i);
							pushBool(t, false);
							rawCall(t, reg, 0);
						}

						mOutput.newline;
					}
				}
				catch(MDException e)
				{
					catchException(t);
					pop(t);

					mOutput.formatln("Error: {}", e);

					getTraceback(t);
					mOutput.formatln("{}", getString(t, -1));
					pop(t);
					mOutput.newline;
				}

				return false;
			}

			auto stackIdx = stackSize(t);

			while(run)
			{
				if(auto diff = stackSize(t) - stackIdx)
					pop(t, diff);

				auto line = mInput.next();

				if(line.ptr is null)
				{
					if(didHalt)
					{
						didHalt = false;
						mOutput.newline;
					}
					else
						break;
				}

				if(buffer.length is 0 && line.trim().length is 0)
				{
					mOutput(Prompt1)();
					continue;
				}

				if(buffer.length == 0)
					buffer ~= line;
				else
					buffer ~= '\n' ~ line;

				try
				{
					if(couldBeDecl())
					{
						if(tryAsStatement())
							continue;
					}
					else
					{
						if(tryAsExpression())
							continue;
					}
				}
				catch(MDHaltException e)
				{
					mOutput.formatln("Halted by keyboard interrupt.");
					didHalt = false;
				}

				mOutput(Prompt1)();
				buffer.length = 0;
			}
		}
	}
}