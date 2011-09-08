module croctest;

import tango.core.tools.TraceExceptions;
import tango.io.Stdout;

import croc.api;
import croc.compiler;
import croc.ex_json;

import croc.addons.pcre;
import croc.addons.sdl;
import croc.addons.gl;
import croc.addons.net;

version(CrocAllAddons)
{
	version = CrocPcreAddon;
	version = CrocSdlAddon;
	version = CrocGlAddon;
	version = CrocNetAddon;
}

/*
Language changes:
- Trailing commas now allowed in table and array constructors
- Labeled control structures, breaks, and continues
*/

void main()
{
	scope(exit) Stdout.flush;

	CrocVM vm;
	auto t = openVM(&vm);
	loadStdlibs(t, CrocStdlib.ReallyAll);

	try
	{
		version(CrocPcreAddon) PcreLib.init(t);
		version(CrocSdlAddon) SdlLib.init(t);
		version(CrocGlAddon) GlLib.init(t);
		version(CrocNetAddon) NetLib.init(t);

		Compiler.setDefaultFlags(t, Compiler.All | Compiler.DocDecorators);

		importModule(t, "samples.simple");
		pushNull(t);
		lookup(t, "modules.runMain");
		swap(t, -3);
		rawCall(t, -3, 0);
	}
	catch(CrocException e)
	{
		catchException(t);
		Stdout.formatln("{}", e);

		dup(t);
		pushNull(t);
		methodCall(t, -2, "tracebackString", 1);
		Stdout.formatln("{}", getString(t, -1));

		pop(t, 2);

		if(e.info)
		{
			Stdout("D Traceback:");
			e.writeOut((char[]s) { Stdout(s); });
		}
	}
	catch(CrocHaltException e)
		Stdout.formatln("Thread halted");
	catch(Exception e)
	{
		Stdout("Bad error:").newline;
		e.writeOut((char[]s) { Stdout(s); });
		return;
	}

	closeVM(&vm);
}