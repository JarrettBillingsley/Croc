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

		version(all)
		{
			// Serialize!
			auto trans = newTable(t);
			pushGlobal(t, "writeln");
			pushInt(t, 1);
			idxa(t, trans);
			pushGlobal(t, "writefln");
			pushInt(t, 2);
			idxa(t, trans);
			pushGlobal(t, "Vector");
			pushInt(t, 3);
			idxa(t, trans);

			loadString(t,
			`
			class A
			{
				this(x, y)
					:x, :y = x, y

				function toString() = format("<x = {} y = {}>", :x, :y)
			}

			return [A(3, 5), Vector.fromArray$ "i16", [1, 2, 3]]
			`);

			pushNull(t);
			rawCall(t, -2, 1);
			auto data = new Array(256, 256);
			serializeGraph(t, -1, trans, data);
			pop(t, 2);

			// Deserialize!
			trans = newTable(t);
			pushInt(t, 1);
			pushGlobal(t, "writeln");
			idxa(t, trans);
			pushInt(t, 2);
			pushGlobal(t, "writefln");
			idxa(t, trans);
			pushInt(t, 3);
			pushGlobal(t, "Vector");
			idxa(t, trans);

			deserializeGraph(t, trans, data);

			loadString(t,
			`
			local objs = vararg[0]
			dumpVal$ objs
			`);
			pushNull(t);
			rotate(t, 3, 2);
			rawCall(t, -3, 0);
		}
		else
		{
			importModule(t, "samples.simple");
			pushNull(t);
			lookup(t, "modules.runMain");
			swap(t, -3);
			rawCall(t, -3, 0);
		}
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