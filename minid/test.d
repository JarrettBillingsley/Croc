module minid.test;

import minid.minid;
import minid.types;

import std.stdio;
import std.stream;
import std.string;

void main()
{
	MDState s = MDInitialize();
	MDFileLoader().addPath(`imports`);

	try
	{
		MDGlobalState().importModule(`regexptest`);
		//compileModule(`simple.md`);
	}
	catch(MDException e)
	{
		writefln("Error: ", e);
		writefln(s.getTracebackString());
	}
	catch(Object e)
	{
		writefln("Bad error: ", e);
		writefln(s.getTracebackString());
	}
}