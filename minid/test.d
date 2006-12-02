module minid.test;

import minid.state;
import minid.types;
import minid.compiler;
import baselib = minid.baselib;
import stringlib = minid.stringlib;
import arraylib = minid.arraylib;
import tablelib = minid.tablelib;
import mathlib = minid.mathlib;
import charlib = minid.charlib;
import iolib = minid.iolib;
import std.stdio;
import std.stream;

void main()
{
	MDState state = MDGlobalState().mainThread();
	baselib.init(state);
	stringlib.init(state);
	arraylib.init(state);
	tablelib.init(state);
	mathlib.init(state);
	charlib.init(state);
	iolib.init(state);
	
	MDClosure cl = new MDClosure(state, compileFile(`simple.md`));

	try
	{
		state.easyCall(cl, 0);
		
		MDClosure func = state.getGlobal("foo"d).asFunction();
		
		uint firstReturn = state.numParams();
		uint numReturns = state.easyCall(func, -1);
		
		for(int i = firstReturn; i < firstReturn + numReturns; i++)
			writefln("value ", i - firstReturn, ": ", state.getParam(i).toString());
	}
	catch(MDException e)
	{
		writefln("error: ", e);
		writefln(state.getTracebackString());
	}
	catch(Object e)
	{
		writefln("bad error: ", e);
		writefln(state.getTracebackString());
	}
}
