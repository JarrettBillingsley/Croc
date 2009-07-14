module test;

import tango.core.stacktrace.TraceExceptions;
import tango.io.Stdout;

import tango.io.device.Array;
import tango.io.device.File;

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
			loadString(t,
			`
			return {
				[writeln] = 1,
				[writefln] = 2,
				[Vector] = 3,
				[StringBuffer] = 4
			}`);
			pushNull(t);
			rawCall(t, -2, 1);
			auto trans = stackSize(t) - 1;

			loadString(t,
			`
			class A
			{
				this(x, y)
					:x, :y = x, y

				function toString() = format("<x = {} y = {}>", :x, :y)
			}

			class B
			{
				this(x, y)
					:x, :y = x, y

				function toString() = format("<x = {} y = {}>", :x, :y)

				function opSerialize(s, f)
				{
					f(:x)
					f(:y)
					s.writeChars("lol")
				}

				function opDeserialize(s, f)
				{
					:x = f()
					:y = f()
					writeln$ s.readChars(3)
				}
			}

			return [A(3, 5), B(5, 10), StringBuffer("ohai"), Vector.fromArray$ "i16", [1, 2, 3]]
			`);

			pushNull(t);
			rawCall(t, -2, 1);
			auto data = new File("temp.dat", File.WriteCreate);//new Array(256, 256);
			serializeGraph(t, -1, trans, data);
			pop(t);
			data.close();

			data = new File("temp.dat", File.ReadExisting);

			// Deserialize!
			loadString(t, "return {[v] = k for k, v in vararg[0]}");
			pushNull(t);
			rotate(t, 3, 2);
			rawCall(t, -3, 1);
			trans = stackSize(t) - 1;

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