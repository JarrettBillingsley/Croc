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

private import tango.io.Print;
private import tango.io.model.IConduit;
private import tango.text.convert.Layout;
private import tango.text.stream.LineIterator;

private import utf = tango.text.convert.Utf;

public class CommandLine
{
	const char[] Prompt1 = ">>> ";
	const char[] Prompt2 = "... ";

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
		mOutput("MiniD Command-Line interpreter beta").newline;
	}
	
	private void printUsage(char[] progname)
	{
		printVersion();
		mOutput("Usage:").newline;
		mOutput("\t")(progname)(" [flags] [filename [args]]").newline;
		mOutput.newline;
		mOutput("Flags:").newline;
		mOutput("\t-i		Enter interactive mode, after executing any script file.").newline;
		mOutput("\t-v		Print the version of the CLI.").newline;
		mOutput("\t-h		Print this message and end.").newline;
		mOutput("\t-I path Specifies an import path to search when importing modules.").newline;
		mOutput.newline;
		mOutput("If mdcl is called without any arguments, it will be as if you passed it").newline;
		mOutput("the -v and -i arguments (it will print the version and enter interactive").newline;
		mOutput("mode).").newline;
		mOutput.newline;
		mOutput("If the filename has no extension, it will be treated as a MiniD import-").newline;
		mOutput("style module name.  So \"a.b\" will look for a module named b in the a").newline;
		mOutput("directory.  The -I flag also affects the search paths used for this.").newline;
		mOutput.newline;
		mOutput("When passing a filename followed by args, all the args will be available").newline;
		mOutput("to the script by using the vararg expression.  The arguments will all be").newline;
		mOutput("strings.").newline;
		mOutput.newline;
		mOutput("In interactive mode, you will be given a >>> prompt.  When you hit enter,").newline;
		mOutput("you may be given a ... prompt.  That means you need to type more to make").newline;
		mOutput("the code complete.  Once you enter enough code to make it complete, the").newline;
		mOutput("code will be run.	If there is an error, the code buffer is cleared.").newline;
		mOutput("To end interactive mode, either use the function \"exit();\", or force").newline;
		mOutput("exit by hitting Ctrl-C.").newline;
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
					return;
				}

				inputFile = args[i];
				scriptArgs = args[i + 1 .. $];
				break _argLoop;
			}
		}

		if(ctx is null)
			ctx = NewContext();
		
		MDState state = ctx.mainThread;

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

			version(Windows)
			{
				mOutput("Use the \"exit();\" function to end, or hit Ctrl-C.").newline;
			}
			else
			{
				mOutput("Use the \"exit();\" function to end.").newline;
			}

			mOutput(Prompt1)();

			while(run)
			{
				char[] line = mInput.next();

				if(line.ptr is null)
					break;

				buffer ~= line;

				if(buffer.length > 0 && buffer[0] == '=')
				{
					MDValue val;

					try
					{
						val = eval(state, utf.toString32(buffer[1 .. $]));
						mOutput(" => ")(state.valueToString(val)).newline;
					}
					catch(MDCompileException e)
					{
						if(e.atEOF)
							mOutput(Prompt2)();
						else
						{
							mOutput.formatln("{}", e);
							mOutput.newline;
							mOutput(Prompt1)();
							buffer.length = 0;
						}
						
						continue;
					}
					catch(MDException e)
					{
						mOutput.formatln("Error: {}", e);
						mOutput.formatln("{}", ctx.getTracebackString());
						mOutput.newline;
					}
				}
				else
				{
					MDFuncDef def;

					try
						def = compileStatements(utf.toString32(buffer), "stdin");
					catch(MDCompileException e)
					{
						if(e.atEOF)
							mOutput(Prompt2)();
						else
						{
							mOutput.formatln("{}", e);
							mOutput.newline;
							mOutput(Prompt1)();
							buffer.length = 0;
						}

						continue;
					}
	
					try
					{
						scope closure = ctx.newClosure(def);
						state.easyCall(closure, 0, MDValue(ctx.globals.ns));
					}
					catch(MDException e)
					{
						mOutput.formatln("Error: {}", e);
						mOutput.formatln("{}", ctx.getTracebackString());
						mOutput.newline;
					}
				}

				mOutput(Prompt1)();
				buffer.length = 0;
			}
		}
	}
}
