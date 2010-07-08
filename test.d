module test;

import std.stdio;
import std.file;

import minid.api;
// import minid.bind;
// import minid.vector;

// import minid.serialization;

// import minid.addons.pcre;
// import minid.addons.sdl;
// import minid.addons.gl;
// import minid.addons.net;

void main()
{
	scope(exit) stdout.flush();

	MDVM vm;
	auto t = openVM(&vm);
// 	loadStdlibs(t, MDStdlib.ReallyAll);

	try
	{
// 		PcreLib.init(t);
// 		SdlLib.init(t);
// 		GlLib.init(t);
// 		NetLib.init(t);

// 		SerializationLib.init(t);

		importModule(t, "samples.factorial");
		pushNull(t);
		lookup(t, "modules.runMain");
		swap(t, -3);
		rawCall(t, -3, 0);
	}
	catch(MDException e)
	{
		catchException(t);
		writefln("Error: %s", e);

		getTraceback(t);
		writefln("%s", getString(t, -1));

		pop(t, 2);

		if(e.info)
		{
			write("D Traceback:");
			writeln(e);
		}
	}
	catch(MDHaltException e)
		writeln("Thread halted");
	catch(Exception e)
	{
		writeln("Bad error:");
		writeln(e);
		return;
	}

	closeVM(&vm);
}