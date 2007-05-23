module test;

import minid.minid;
import minid.types;

import std.stdio;
import std.stream;
import std.string;
import std.traits;

void main()
{
	try
	{
		MDState s = MDInitialize();
		MDFileLoader().addPath(`samples`);

		MDGlobalState().importModule("tests.interpreter");
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