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
		MDFileLoader().addPath(`imports`);

		MDGlobalState().importModule("simple");
	}
	catch(MDException e)
	{
		writefln("Error: ", e);
		writefln(MDState.getTracebackString());
	}
	catch(Object e)
	{
		writefln("Bad error: ", e);
		writefln(MDState.getTracebackString());
	}
}