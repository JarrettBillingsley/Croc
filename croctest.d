module croctest;

import tango.core.tools.TraceExceptions;
import tango.io.Stdout;

import croc.api;
import croc.compiler;

import croc.addons.pcre;
import croc.addons.sdl;
import croc.addons.gl;
import croc.addons.net;
import croc.addons.devil;

version(CrocAllAddons)
{
	version = CrocPcreAddon;
	version = CrocSdlAddon;
	version = CrocGlAddon;
	version = CrocNetAddon;
	version = CrocDevilAddon;
}

import tango.stdc.stdlib;
void main()
{
	scope(exit) Stdout.flush;

	CrocVM vm;
	auto t = openVM(&vm);
	Stdout.formatln("here we go...").flush;
// 	gc(t);
// 	exit(0);
	loadStdlibs(t, CrocStdlib.Array);
	Stdout.formatln("whew").flush;

	try
	{
		version(CrocPcreAddon) PcreLib.init(t);
		version(CrocSdlAddon) SdlLib.init(t);
		version(CrocGlAddon) GlLib.init(t);
		version(CrocNetAddon) NetLib.init(t);
		version(CrocDevilAddon) DevilLib.init(t);

		Compiler.setDefaultFlags(t, Compiler.All | Compiler.DocDecorators);
		runModule(t, "samples.simple");
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
			Stdout("D Traceback: ");
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

// 	closeVM(&vm);
}