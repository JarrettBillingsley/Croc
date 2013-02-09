module croctest;

import tango.core.tools.TraceExceptions;
import tango.io.Stdout;

import croc.api;
import croc.compiler;

/*
	SdlSurface   (1 pointer. C pointers could just be cast to integers in D and use nativeobjs in C)
*/

void main()
{
	scope(exit) Stdout.flush;

	CrocVM vm;
	CrocThread* t;
	bool shouldClose = true;

	try
	{
		t = openVM(&vm);
		loadUnsafeLibs(t, CrocUnsafeLib.ReallyAll);
		loadAvailableAddons(t);
		Compiler.setDefaultFlags(t, Compiler.All | Compiler.DocDecorators);
		runModule(t, "samples.simple");
	}
	catch(CrocException e)
	{
		if(t is null)
		{
			// in case, while fucking around, we manage to throw an exception from openVM
			shouldClose = false;
			t = mainThread(&vm);
		}

		catchException(t);
		Stdout.formatln("{}", e);

		dup(t);
		pushNull(t);
		methodCall(t, -2, "tracebackString", 1);
		Stdout.formatln("{}", getString(t, -1));

		pop(t, 2);

		// if(e.info)
		// {
		// 	Stdout("\nD Traceback: ").newline;
		// 	e.info.writeOut((char[]s) { Stdout(s); });
		// }
	}
	catch(CrocHaltException e)
		Stdout.formatln("Thread halted");
	catch(Exception e)
	{
		Stdout("Bad error:").newline;
		e.writeOut((char[]s) { Stdout(s); });
		return;
	}

	if(shouldClose)
		closeVM(&vm);
}
