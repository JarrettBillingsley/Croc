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

module mdcl;

import minid.compiler;
import minid.minid;
import minid.types;

import tango.io.Stdout;
import tango.io.Console;
import utf = tango.text.convert.Utf;

void printVersion()
{
	Stdout("MiniD Command-Line interpreter beta").newline;
}

void printUsage()
{
	printVersion();
	Stdout("Usage:").newline;
	Stdout("\tmdcl [flags] [filename [args]]").newline;
	Stdout.newline;
	Stdout("Flags:").newline;
	Stdout("\t-i      Enter interactive mode, after executing any script file.").newline;
	Stdout("\t-v      Print the version of the CLI.").newline;
	Stdout("\t-h      Print this message and end.").newline;
	Stdout("\t-I path Specifies an import path to search when importing modules.").newline;
	Stdout.newline;
	Stdout("If mdcl is called without any arguments, it will be as if you passed it").newline;
	Stdout("the -v and -i arguments (it will print the version and enter interactive").newline;
	Stdout("mode).").newline;
	Stdout.newline;
	Stdout("If the filename has no extension, it will be treated as a MiniD import-").newline;
	Stdout("style module name.  So \"a.b\" will look for a module named b in the a").newline;
	Stdout("directory.  The -I flag also affects the search paths used for this.").newline;
	Stdout.newline;
	Stdout("When passing a filename followed by args, all the args will be available").newline;
	Stdout("to the script by using the vararg expression.  The arguments will all be").newline;
	Stdout("strings.").newline;
	Stdout.newline;
	Stdout("In interactive mode, you will be given a >>> prompt.  When you hit enter,").newline;
	Stdout("you may be given a ... prompt.  That means you need to type more to make").newline;
	Stdout("the code complete.  Once you enter enough code to make it complete, the").newline;
	Stdout("code will be run.  If there is an error, the code buffer is cleared.").newline;


	version(Windows)
	{
		Stdout("To end interactive mode, either use the function \"exit();\", or force").newline;
		Stdout("exit by hitting Ctrl-C.").newline;
	}
	else
	{
		Stdout("To end interactive mode, use the function \"exit();\".").newline;
	}
}

const char[] Prompt1 = ">>> ";
const char[] Prompt2 = "... ";

void main(char[][] args)
{
	bool printedVersion = false;
	bool interactive = false;
	char[] inputFile;
	char[][] scriptArgs;
	char[][] importPaths;

	if(args.length == 1)
	{
		printVersion();
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
				printUsage();
				return;
				
			case "-I":
				i++;
				
				if(i >= args.length)
				{
					Stdout("-I must be followed by a path").newline;
					printUsage();
					return;
				}
				
				importPaths ~= args[i];
				break;

			default:
				if(args[i][0] == '-')
				{
					Stdout("Invalid flag '%s'", args[i]).newline;
					printUsage();
					return;
				}

				inputFile = args[i];
				scriptArgs = args[i + 1 .. $];
				break _argLoop;
		}
	}

	MDState state = MDInitialize();

	foreach(path; importPaths)
		MDGlobalState().addImportPath(path);

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
				if(MDGlobalState().loadModuleFromFile(state, utf.toUtf32(inputFile), params) is null)
					Stdout.formatln("Error: could not find module '{}'", inputFile);
			}
			catch(MDException e)
			{
				Stdout.formatln("Error: {}", e);
				Stdout.formatln("{}", MDState.getTracebackString());
			}
		}
		else
		{
			try
				MDGlobalState().initializeModule(state, def, params);
			catch(MDException e)
			{
				Stdout.formatln("Error: {}", e);
				Stdout.formatln("{}", MDState.getTracebackString());
			}
		}
	}

	if(interactive)
	{
		char[] buffer;
		bool run = true;

		MDGlobalState().globals["exit"d] = MDGlobalState().newClosure
		(
			(MDState s, uint numParams)
			{
				run = false;
				return 0;
			}, "exit"
		);

		version(Windows)
		{
			Stdout("Use the \"exit();\" function to end, or hit Ctrl-C.").newline;
		}
		else
		{
			Stdout("Use the \"exit();\" function to end.").newline;
		}
		
		Stdout(Prompt1)();

		while(run)
		{
			char[] line;
			
			if(Cin.readln(line) == false)
				break;

			buffer ~= line;

			bool atEOF = false;
			MDFuncDef def;

			try
				def = compileStatements(utf.toUtf32(buffer), "stdin", atEOF);
			catch(MDCompileException e)
			{
				if(atEOF)
				{
					Stdout(Prompt2)();
				}
				else
				{
					Stdout.formatln("{}", e);
					Stdout.newline;
					Stdout(Prompt1)();
					buffer.length = 0;
				}

				continue;
			}

			try
			{
				scope closure = MDGlobalState().newClosure(def);
				state.easyCall(closure, 0, MDValue(MDGlobalState().globals.ns));
			}
			catch(MDException e)
			{
				Stdout.formatln("Error: {}", e);
				Stdout.formatln("{}", MDState.getTracebackString());
				Stdout.newline;
			}

			Stdout(Prompt1)();
			buffer.length = 0;
		}
	}
}