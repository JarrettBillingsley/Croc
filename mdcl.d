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

import std.cstream;
import std.path;
import std.stdio;
import std.stream;

void printVersion()
{
	writefln("MiniD Command-Line interpreter beta");
}

void printUsage()
{
	printVersion();
	writefln("Usage:");
	writefln("\tmdcl [flags] [filename [args]]");
	writefln();
	writefln("Flags:");
	writefln("\t-i      Enter interactive mode, after executing any script file.");
	writefln("\t-v      Print the version of the CLI.");
	writefln("\t-h      Print this message and end.");
	writefln("\t-I path Specifies an import path to search when importing modules.");
	writefln();
	writefln("If mdcl is called without any arguments, it will be as if you passed it");
	writefln("the -v and -i arguments (it will print the version and enter interactive");
	writefln("mode).");
	writefln();
	writefln("If the filename has no extension, it will be treated as a MiniD import-");
	writefln("style module name.  So \"a.b\" will look for a module named b in the a");
	writefln("directory.  The -I flag also affects the search paths used for this.");
	writefln();
	writefln("When passing a filename followed by args, all the args will be available");
	writefln("to the script by using the vararg expression.  The arguments will all be");
	writefln("strings.");
	writefln();
	writefln("In interactive mode, you will be given a >>> prompt.  When you hit enter,");
	writefln("you may be given a ... prompt.  That means you need to type more to make");
	writefln("the code complete.  Once you enter enough code to make it complete, the");
	writefln("code will be run.  If there is an error, the code buffer is cleared.");
	writefln("To end interactive mode, either use the function \"exit();\", or type");
	
	version(Windows)
	{
		writefln("the end-of-file character (Ctrl-Z) and hit enter to end, or force exit");
		writefln("by hitting Ctrl-C.");
	}
	else
		writefln("the end-of-file character (Ctrl-D) and hit enter to end.");
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
					writefln("-I must be followed by a path");
					printUsage();
					return;
				}
				
				importPaths ~= args[i];
				break;

			default:
				if(args[i][0] == '-')
				{
					writefln("Invalid flag '%s'", args[i]);
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
				if(MDGlobalState().loadModuleFromFile(state, utf.toUTF32(inputFile), params) is null)
					writefln("Error: could not find module '%s'", inputFile);
			}
			catch(MDException e)
			{
				writefln("Error: ", e);
				writefln(MDState.getTracebackString());
			}
		}
		else
		{
			try
				MDGlobalState().initializeModule(state, def, params);
			catch(MDException e)
			{
				writefln("Error: ", e);
				writefln(MDState.getTracebackString());
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
			writefln("Type EOF (Ctrl-Z) and hit enter to end, or use the \"exit();\" function.");
		else
			writefln("Type EOF (Ctrl-D) and hit enter to end, or use the \"exit();\" function.");
			
		writef(Prompt1);

		while(run)
		{
			char[] line = din.readLine();

			if(din.eof())
				break;

			buffer ~= line;

			scope MemoryStream s = new MemoryStream(buffer);

			bool atEOF = false;
			MDFuncDef def;

			try
				def = compileStatements(s, "stdin", atEOF);
			catch(MDCompileException e)
			{
				if(atEOF)
				{
					writef(Prompt2);
				}
				else
				{
					writefln(e);
					writefln();
					writef(Prompt1);
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
				writefln("Error: ", e);
				writefln(MDState.getTracebackString());
				writefln();
			}

			writef(Prompt1);
			buffer.length = 0;
		}
	}
}