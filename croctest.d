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

import croc.ex_doccomments;

uword processComment_wrap(CrocThread* t)
{
	auto str = checkStringParam(t, 1);
	
	newTable(t);
	pushString(t, "dumb.croc"); fielda(t, -2, "file");
	pushInt(t, 1);              fielda(t, -2, "line");
	pushString(t, "function");  fielda(t, -2, "kind");
	pushString(t, "f");         fielda(t, -2, "name");

		newTable(t);
		pushString(t, "dumb.croc"); fielda(t, -2, "file");
		pushInt(t, 1);              fielda(t, -2, "line");
		pushString(t, "parameter"); fielda(t, -2, "kind");
		pushString(t, "x");         fielda(t, -2, "name");
	newArrayFromStack(t, 1);
	fielda(t, -2, "params");

	processComment(t, str);

	return 1;
}

version(CrocAllAddons)
{
	version = CrocPcreAddon;
	version = CrocSdlAddon;
	version = CrocGlAddon;
	version = CrocNetAddon;
	version = CrocDevilAddon;
}

void main()
{
	scope(exit) Stdout.flush;

	CrocVM vm;
	CrocThread* t;

	try
	{
		t = openVM(&vm);
		loadUnsafeLibs(t, CrocUnsafeLib.ReallyAll);

		version(CrocPcreAddon) PcreLib.init(t);
		version(CrocSdlAddon) SdlLib.init(t);
		version(CrocGlAddon) GlLib.init(t);
		version(CrocNetAddon) NetLib.init(t);
		version(CrocDevilAddon) DevilLib.init(t);
		
		newFunction(t, &processComment_wrap, "processComment");
		newGlobal(t, "processComment");

		Compiler.setDefaultFlags(t, Compiler.All | Compiler.DocDecorators);
		runModule(t, "samples.simple");
	}
	catch(CrocException e)
	{
		t = t ? t : mainThread(&vm); // in case, while fucking around, we manage to throw an exception from openVM
		catchException(t);
		Stdout.formatln("{}", e);

		dup(t);
		pushNull(t);
		methodCall(t, -2, "tracebackString", 1);
		Stdout.formatln("{}", getString(t, -1));

		pop(t, 2);

		if(e.info)
		{
			Stdout("\nD Traceback: ").newline;
			e.info.writeOut((char[]s) { Stdout(s); });
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