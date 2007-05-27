module test;

import std.stdio;
import std.stream;
import std.string;
import std.traits;

import minid.minid;

void main()
{
	try
	{
		MDState s = MDInitialize();
		MDGlobalState().addImportPath(`samples`);

		MDGlobalState().importModule("arrays");
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