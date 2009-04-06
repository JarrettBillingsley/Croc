module test;

import tango.io.Stdout;
debug import tango.stdc.stdarg; // To make tango-user-base-debug.lib link correctly

import minid.api;
import minid.bind;
import minid.vector;

// import minid.addons.pcre;
// import minid.addons.sdl;
// import minid.addons.gl;

void main()
{
	scope(exit) Stdout.flush;

	MDVM vm;
	auto t = openVM(&vm);
	loadStdlibs(t, MDStdlib.ReallyAll);

	try
	{
// 		PcreLib.init(t);
// 		SdlLib.init(t);
// 		GlLib.init(t);

		importModule(t, "samples.simple");
		pushNull(t);
		lookup(t, "modules.runMain");
		swap(t, -3);
		rawCall(t, -3, 0);
	}
	catch(MDException e)
	{
		catchException(t);
		Stdout.formatln("Error: {}", e);

		getTraceback(t);
		Stdout.formatln("{}", getString(t, -1));

		pop(t, 2);

		if(e.info)
			Stdout.formatln("D Traceback:\n{}", e.info);
	}
	catch(MDHaltException e)
		Stdout.formatln("Thread halted");
	catch(Exception e)
	{
		Stdout.formatln("Bad error ({}, {}): {}", e.file, e.line, e);

		if(e.info)
			Stdout.formatln("D Traceback:\n{}", e.info);

		return;
	}

	closeVM(&vm);
}
