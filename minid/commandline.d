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

module minid.commandline;

private import minid.compiler;
private import minid.minid;
private import minid.types;
private import minid.utils;

private import tango.io.Print;
private import tango.io.model.IConduit;
private import tango.text.convert.Layout;
private import tango.text.stream.LineIterator;
private import tango.stdc.ctype;
private import tango.stdc.signal;
private import Uni = tango.text.Unicode;

private import utf = tango.text.convert.Utf;

public class CommandLine
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

In interactive mode, you will also have access to a function \"repr()\"
which will print out a readable representation of a variable, more
readable than what you get from toString() anyway.  The first param is
the value to output; the optional second param should be 'true' to output
a newline after printing the value, or 'false' not to.  Defaults to true.
";
/+ Stupid editor has issues with multiline strings. "+/

	private Print!(char) mOutput;
	private LineIterator!(char) mInput;

	public this(Print!(char) output, InputStream inputStream)
	{
		mOutput = output;
		mInput = new LineIterator!(char)(inputStream);
	}

	public this(OutputStream outputStream, InputStream inputStream)
	{
		this(new Print!(char)(new Layout!(char), outputStream), inputStream);
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

	void run(char[][] args = null, MDContext ctx = null)
	{
		bool printedVersion = false;
		bool interactive = false;
		char[] inputFile;
		char[][] scriptArgs;
		char[][] importPaths;
		char[] progname = (args.length > 0) ? args[0] : "";

		if(args.length == 1 || args == null)
		{
			interactive = true;
		}
		
		_argLoop: for(int i = 1; i < args.length; i++)
		{
			switch(args[i])
			{
			case "-i":
				interactive = true;
				break;

			case "-v":
				if(printedVersion == false)
				{
					printedVersion = true;
					printVersion();
				}
				break;
				
			case "-h":
				printUsage(progname);
				return;
				
			case "-I":
				i++;
				
				if(i >= args.length)
				{
					mOutput("-I must be followed by a path").newline;
					printUsage(progname);
					return;
				}
				
				importPaths ~= args[i];
				break;

			default:
				if(args[i][0] == '-')
				{
					mOutput("Unknown flag '{}'.", args[i]);
					return;
				}

				inputFile = args[i];
				scriptArgs = args[i + 1 .. $];
				break _argLoop;
			}
		}

		if(ctx is null)
			ctx = NewContext();
		
		// static so it can be accessed by the signal handler
		static MDState state;
		state = ctx.mainThread();

		foreach(path; importPaths)
			ctx.addImportPath(path);

		if(inputFile.length > 0)
		{
			MDModuleDef def;

			if(inputFile.length >= 3 && inputFile[$ - 3 .. $] == ".md")
				def = compileModule(inputFile);
			else if(inputFile.length >= 4 && inputFile[$ - 4 .. $] == ".mdm")
				def = MDModuleDef.loadFromFile(inputFile);

			MDValue[] params = new MDValue[scriptArgs.length];

			foreach(i, arg; scriptArgs)
				params[i] = arg;

			if(def is null)
			{
				try
				{
					if(ctx.loadModuleFromFile(state, utf.toString32(inputFile), params) is null)
						mOutput.formatln("Error: could not find module '{}'", inputFile);
				}
				catch(MDException e)
				{
					mOutput.formatln("Error: {}", e);
					mOutput.formatln("{}", ctx.getTracebackString());
				}
			}
			else
			{
				try
					ctx.initializeModule(state, def, params);
				catch(MDException e)
				{
					mOutput.formatln("Error: {}", e);
					mOutput.formatln("{}", ctx.getTracebackString());
				}
			}
		}

		if(interactive)
		{
			if(!printedVersion)
				printVersion();

			dchar[1024] utf32buffer;
			List!(MDValue) returnBuffer;

			char[] buffer;
			bool run = true;

			ctx.globals["exit"d] = ctx.newClosure
			(
				(MDState s, uint numParams)
				{
					run = false;
					return 0;
				}, "exit"
			);
			
			auto reprFunc = ctx.globals["dumpVal"d];

			mOutput("Use the \"exit()\" function to end.").newline;
			mOutput(Prompt1)();
			
			// static so the interrupt can access it.
			static bool didHalt = false;
			
			static extern(C) void interruptHandler(int s)
			{
				state.pendingHalt();
				didHalt = true;
				signal(s, &interruptHandler);
			}
			
			auto oldInterrupt = signal(SIGINT, &interruptHandler);

			scope(exit)
				signal(SIGINT, oldInterrupt);

			bool couldBeDecl()
			{
				if(buffer.length == 0)
					return false;

				size_t i = 0;

				for( ; i < buffer.length && Uni.isWhitespace(buffer[i]); i++)
				{}
				
				auto temp = buffer[i .. $];

				return temp.startsWith("function") || temp.startsWith("object") || temp.startsWith("namespace");
			}

			bool tryAsStatement(Exception e = null)
			{
				try
				{
					auto def = compileStatements(utf.toString32(buffer), "stdin");
					state.call(ctx.newClosure(def), 0);
				}
				catch(MDCompileException e2)
				{
					if(e2.atEOF)
					{
						mOutput(Prompt2)();
						return true;
					}
					else if(e2.solitaryExpression)
					{
						if(e)
						{
							mOutput.formatln("When attempting to evaluate as an expression:");
							mOutput.formatln("Error: {}", e);
							mOutput.formatln("When attempting to evaluate as a statement:");
						}

						mOutput.formatln("Error: {}", e2);
						mOutput.newline;
					}
					else
					{
						mOutput.formatln("Error: {}", e2);
						mOutput.newline;
					}
				}
				catch(MDException e2)
				{
					mOutput.formatln("Error: {}", e2);
					mOutput.formatln("{}", ctx.getTracebackString());
					mOutput.newline;
				}

				return false;
			}
			
			bool tryAsExpression()
			{
				try
				{
					auto numRets = evalMultRet(state, utf.toString32(buffer, utf32buffer));

					if(numRets > 0)
					{
						mOutput(" => ");
						returnBuffer.length = 0;
						
						for(uint i = 0; i < numRets; i++)
							returnBuffer ~= state.pop();

						auto returns = returnBuffer.toArray();
						
						state.call(reprFunc, 0, returns[$ - 1], false);

						foreach_reverse(val; returns[0 .. $ - 1])
						{
							mOutput(", ");
							state.call(reprFunc, 0, val, false);
						}
						
						mOutput.newline;
					}
				}
				catch(MDCompileException e)
				{
					if(e.atEOF)
					{
						mOutput(Prompt2)();
						return true;
					}
					else
						return tryAsStatement(e);
				}
				catch(MDException e)
				{
					mOutput.formatln("Error: {}", e);
					mOutput.formatln("{}", ctx.getTracebackString());
					mOutput.newline;
				}

				return false;
			}

			while(run)
			{
				char[] line = mInput.next();

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

				if(buffer.length is 0 && line.length is 0)
				{
					mOutput(Prompt1)();
					continue;
				}

				buffer ~= '\n' ~ line;

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
				
				if(didHalt)
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
