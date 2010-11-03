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

module mdcl;

import tango.io.Stdout;
import tango.io.Console;

import minid.api;
import minid.commandline;

version = MdclAllAddons;

version(MdclAllAddons)
{
	version = MdclSdlAddon;
	version = MdclGlAddon;
	version = MdclNetAddon;
	version = MdclPcreAddon;
}

version(MdclSdlAddon)  import minid.addons.sdl;
version(MdclGlAddon)   import minid.addons.gl;
version(MdclNetAddon)  import minid.addons.net;
version(MdclPcreAddon) import minid.addons.pcre;

const char[] Usage =
"Usage:
\tmdcl [flags] [filename [args]]

Flags:
    -v        Print the version of the CLI and exit.
    -h        Print this message and exit.
    -I path   Specifies an import path to search when importing modules.
    -d        Load the debug library.

mdcl can be run in two modes: file mode or interactive mode.

If you pass a filename, mdcl will run in file mode by loading the file and
running any main() function defined in it.  If the filename has no extension,
it will be treated as a MiniD import-style module name.  So \"a.b\" will look
for a module named b in the a directory.  The -I flag also affects the search
paths used for this.

When passing a filename followed by args, all the args will be passed as
arguments to its main() function.  The arguments will all be strings.

If you don't pass a filename, it will run in interactive mode.


In interactive mode, you will be given a >>> prompt.  When you hit enter,
you may be given a ... prompt.  That means you need to type more to make
the code complete.  Once you enter enough code to make it complete, the
code will be run.  If there is an error, the code buffer is cleared.
To end interactive mode, use the \"exit()\" function.
";
/+ Stupid editor has issues with multiline strings. "+/

void printVersion()
{
	Stdout("MiniD Command-Line interpreter 2.0").newline;
}

void printUsage()
{
	printVersion();
	Stdout(Usage);
}

struct Params
{
	bool justStop;
	bool debugEnabled;
	char[] inputFile;
	char[][] args;
}

Params parseArguments(MDThread* t, char[][] args)
{
	Params ret;

	for(int i = 1; i < args.length; i++)
	{
		switch(args[i])
		{
			case "-v":
				printVersion();
				ret.justStop = true;
				break;

			case "-h":
				printUsage();
				ret.justStop = true;
				break;

			case "-I":
				i++;

				if(i >= args.length)
				{
					Stdout("-I must be followed by a path").newline;
					printUsage();
					ret.justStop = true;
					break;
				}

				pushGlobal(t, "modules");
				field(t, -1, "path");
				pushChar(t, ';');
				pushString(t, args[i]);
				cateq(t, -3, 2);
				fielda(t, -2, "path");
				pop(t);
				continue;

			case "-d":
				ret.debugEnabled = true;
				continue;

			default:
				if(args[i].startsWith("-"))
				{
					Stdout.formatln("Unknown flag '{}'", args[i]);
					printUsage();
					ret.justStop = true;
					break;
				}

				ret.inputFile = args[i];
				ret.args = args[i + 1 .. $];
				break;
		}

		break;
	}

	return ret;
}

void main(char[][] args)
{
	MDVM vm;
	auto t = openVM(&vm);
	loadStdlibs(t, MDStdlib.All);

	version(MdclSdlAddon)  SdlLib.init(t);
	version(MdclGlAddon)   GlLib.init(t);
	version(MdclNetAddon)  NetLib.init(t);
	version(MdclPcreAddon) PcreLib.init(t);

	auto params = parseArguments(t, args);

	if(params.justStop)
		return;

	if(params.debugEnabled)
		loadStdlibs(t, MDStdlib.Debug);

	try
	{
		if(params.inputFile)
		{
			mdtry(t,
			{
				foreach(arg; params.args)
					pushString(t, arg);

				runFile(t, params.inputFile, params.args.length);
			},
			(MDException e, word mdEx)
			{
				Stdout.formatln("Error: {}", e);
				getTraceback(t);
				Stdout.formatln("{}", getString(t, -1));
				pop(t);
			});
		}
		else
		{
			printVersion();

			ConsoleCLI cli;
			cli.interactive(t);
		}
	}
	catch(Exception e)
	{
		Stdout.formatln("Oh noes!");
		e.writeOut((char[]s) { Stdout(s); });
		return;
	}

	closeVM(&vm);
}