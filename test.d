module test;

import tango.core.stacktrace.TraceExceptions;
import tango.io.Stdout;

import tango.io.device.Array;

import minid.api;
import minid.bind;
import minid.vector;

import minid.serialization;

// import minid.addons.pcre;
// import minid.addons.sdl;
// import minid.addons.gl;
// import minid.addons.net;

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
// 		NetLib.init(t);

		// Serialize!
// 		auto intrans = newTable(t);
// 		pushGlobal(t, "writeln");
// 		pushInt(t, 1);
// 		idxa(t, intrans);
// 
// 		loadString(t,
// 		`
// 		local a = [1, 2, 3]
// 		local b = [a, weakref(a), weakref([10])]
// 
// 		gc.collect()
// 		dumpVal$ b
// 
// 		return b
// 		`);
// 
// 		pushNull(t);
// 		rawCall(t, -2, 1);
// 		auto data = new Array(256, 256);
// 		serializeGraph(t, -1, intrans, data);
// 		pop(t, 2);
// 
// 		// Deserialize!
// 		intrans = newTable(t);
// 		pushInt(t, 1);
// 		pushGlobal(t, "writeln");
// 		idxa(t, intrans);
// 		deserializeGraph(t, intrans, data);
// 
// 		loadString(t,
// 		`
// 		local b = vararg[0]
// 
// 		dumpVal$ b
// 		writeln$ b[0] is deref(b[1])
// 		`);
// 		pushNull(t);
// 		rotate(t, 3, 2);
// 		rawCall(t, -3, 0);

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
		{
			Stdout("D Traceback:");
			e.writeOut((char[]s) { Stdout(s); });
		}
	}
	catch(MDHaltException e)
		Stdout.formatln("Thread halted");
	catch(Exception e)
	{
		Stdout("Bad error:").newline;
		e.writeOut((char[]s) { Stdout(s); });
		return;
	}

	closeVM(&vm);
}