module test;

import minid.minid;
import minid.types;

import std.stdio;
import std.stream;
import std.string;

void main()
{
	MDState s;

	try
	{
		s = MDInitialize();
		MDFileLoader().addPath(`samples`);

		MDGlobalState().importModule("simple");
		//compileModule(`samples\simple.md`);
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