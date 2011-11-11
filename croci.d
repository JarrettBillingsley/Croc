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

module croci;

import tango.io.Console;
import tango.io.device.Array;
import tango.io.Stdout;
import tango.io.stream.TextFile;
import tango.io.UnicodeFile;
import tango.text.Util;

import croc.api;
import croc.compiler;
import croc.ex_commandline;
import croc.ex_json;

version(CrocAllAddons)
{
	version = CrocSdlAddon;
	version = CrocGlAddon;
	version = CrocNetAddon;
	version = CrocPcreAddon;
	version = CrocDevilAddon;
}

import croc.addons.sdl;
import croc.addons.gl;
import croc.addons.net;
import croc.addons.pcre;
import croc.addons.devil;

const char[] ShortUsage =
"Usage:
    croci [flags] [filename [args]]

Flags:
    -v
        Print the name and version of the CLI and exit.

    -h, --help
        Print this message and exit.

    -I path
        Specifies an import path to search when importing modules.

    -d
        Load the debug library.

    --safe
        Only load safe libraries. Overrides -d (prevents the debug library
        from being loaded even if -d is specified).

    --docs=<on|off|default>
        Control whether documentation comments are extracted and attached to
        objects. The default is to enable them in interactive mode and disable
        them in file mode.
        
    --doctable outname filename
        This is a special mode which does not run any code. It just extracts
        documentation comments from the file given by 'filename', and saves
        the documentation table for the file into 'outname' as JSON. That
        table can then be further processed by another program. Any parameters
        after this flag are ignored.
        
        Unlike in file mode, filename must be an actual path, not just a
        module name.

        If outname is -, then the output JSON will be sent to stdout. If
        filename is -, then the source will be read from stdin. If filename
        is of the form -name, then stdin will be read, but the name
        following the dash will be used as the filename of the module.
";
/+ fff" +/

const char[] LongUsage =
"croci can be run in two modes: file mode or interactive mode.

If you pass a filename, croci will run in file mode by loading the file and
running any main() function defined in it. If the filename has no .croc or
.croco extension, it will be treated as a Croc import-style module name.
So \"a.b\" will look for a module named b in the a directory. The -I flag
also affects the search paths used for this.

When passing a filename followed by args, all the args will be passed as
arguments to its main() function. The arguments will all be strings.

If you don't pass a filename, it will run in interactive mode.

In interactive mode, you will be given a >>> prompt. When you hit enter,
you may be given a ... prompt. That means you need to type more to make
the code complete. Once you enter enough code to make it complete, the
code will be run. If there is an error, the code buffer is cleared.
To end interactive mode, use the \"exit()\" function.

The -docs flag controls whether or not documentation comments will be
extracted and attached to declarations, allowing for runtime reflection of the
documentation through the standard library. In \"default\" mode, they are
enabled in interactive mode and disabled in file mode. You can force them or
off as well.
";
/+ Stupid editor has issues with multiline strings. "+/

void printVersion()
{
	Stdout("Croc Command-Line interpreter").newline;
}

void printUsage(bool full)
{
	printVersion();
	Stdout(ShortUsage);

	if(full)
		Stdout.newline()(LongUsage);
}

struct Params
{
	bool justStop;
	bool debugEnabled;
	bool safe;
	bool failed;
	char[] docsEnabled = "default";
	char[] inputFile;
	char[][] args;
	char[] docOutfile;
}

Params parseArguments(CrocThread* t, char[][] args)
{
	Params ret;

	Params error(char[] format, ...)
	{
		Stdout("\nError: ");
		Stdout(Stdout.layout.convert(_arguments, _argptr, format)).newline;
		Stdout.newline;
		printUsage(false);
		ret.justStop = true;
		ret.failed = true;
		return ret;
	}

	for(int i = 1; i < args.length; i++)
	{
		switch(args[i])
		{
			case "-v":
				printVersion();
				ret.justStop = true;
				break;

			case "-h", "--help":
				printUsage(true);
				ret.justStop = true;
				break;

			case "-I":
				i++;

				if(i >= args.length)
					return error("-I must be followed by a path");

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
				
			case "--safe":
				ret.safe = true;
				continue;
				
			case "--doctable":
				i += 2;
				
				if(i >= args.length)
					return error("--doctable must be followed by two arguments");
				
				ret.docOutfile = args[i - 1];
				ret.inputFile = args[i];
				return ret;

			default:
				if(args[i].startsWith("--docs"))
				{
					auto pos = args[i].locate('=');
					
					if(pos == args[i].length)
						return error("Malfomed flag: '{}'", args[i]);

					auto mode = args[i][pos + 1 .. $];

					switch(mode)
					{
						case "on", "off", "default":
							ret.docsEnabled = mode;
							break;

						default:
							return error("Invalid mode '{}' (must be on, off, or default)", mode);
					}

					continue;
				}
				else if(args[i].startsWith("-"))
					return error("Unknown flag '{}'", args[i]);

				ret.inputFile = args[i];
				ret.args = args[i + 1 .. $];
				break;
		}

		break;
	}

	return ret;
}

bool doDocgen(CrocThread* t, ref Params params)
{
	if(!params.safe)
		loadUnsafeLibs(t, CrocUnsafeLib.All);

	try
	{
		bool failed = false;

		croctry(t,
		{
			char[] src;
			char[] name;

			if(params.inputFile.startsWith("-"))
			{
				if(params.inputFile.length == 1)
					name = "stdin";
				else
					name = params.inputFile[1 .. $];

				auto arr = new Array(0, 4096);
				arr.copy(Cin.stream);
				src = cast(char[])arr.slice();
			}
			else
			{
				scope file = new UnicodeFile!(char)(params.inputFile, Encoding.Unknown);
				src = file.read();
				name = params.inputFile;
			}

			scope c = new Compiler(t, Compiler.All | Compiler.DocTable);
			char[] modName = void;
			c.compileModule(src, name, modName);
		},
		(CrocException e, word crocEx)
		{
			Stdout.formatln("Error: {}", e);
			failed = true;
		});

		if(!failed)
		{
			pop(t);
			auto f = (params.docOutfile == "-") ? Stdout : new TextFileOutput(params.docOutfile);
			toJSON(t, -1, true, f);
			f.flush();
			f.newline();
		}
	}
	catch(Exception e)
	{
		Stdout.formatln("Oh noes!");
		e.writeOut((char[]s) { Stdout(s); });
		return false;
	}

	return true;
}

bool doNormal(CrocThread* t, ref Params params)
{
	if(!params.safe)
		loadUnsafeLibs(t, CrocUnsafeLib.All);

	version(CrocSdlAddon)  SdlLib.init(t);
	version(CrocPcreAddon) PcreLib.init(t);

	if(!params.safe)
	{
		version(CrocGlAddon)    GlLib.init(t);
		version(CrocNetAddon)   NetLib.init(t);
		version(CrocDevilAddon) DevilLib.init(t);

		if(params.debugEnabled)
			loadUnsafeLibs(t, CrocUnsafeLib.Debug);
	}

	try
	{
		if(params.inputFile)
		{
			if(params.docsEnabled == "on")
				Compiler.setDefaultFlags(t, Compiler.All | Compiler.DocDecorators);

			croctry(t,
			{
				foreach(arg; params.args)
					pushString(t, arg);

				if(params.inputFile.endsWith(".croc") || params.inputFile.endsWith(".croco"))
					runFile(t, params.inputFile, params.args.length);
				else
					runModule(t, params.inputFile, params.args.length);
			},
			(CrocException e, word crocEx)
			{
				Stdout.formatln("Error: {}", e);
				dup(t, crocEx);
				pushNull(t);
				methodCall(t, -2, "tracebackString", 1);
				Stdout.formatln("{}", getString(t, -1));
				pop(t);
			});
		}
		else
		{
			if(params.docsEnabled != "off")
				Compiler.setDefaultFlags(t, Compiler.All | Compiler.DocDecorators);

			printVersion();

			ConsoleCLI cli;
			cli.interactive(t);
		}
	}
	catch(Exception e)
	{
		Stdout.formatln("Oh noes!");
		e.writeOut((char[]s) { Stdout(s); });
		return false;
	}

	return true;
}

int main(char[][] args)
{
	CrocVM vm;
	auto t = openVM(&vm);
	auto params = parseArguments(t, args);

	if(params.justStop)
		return params.failed ? 1 : 0;

	bool success;

	if(params.docOutfile)
		success = doDocgen(t, params);
	else
		success = doNormal(t, params);

	if(success)
	{
		closeVM(&vm);
		return 0;
	}
	else
		return 1;
}