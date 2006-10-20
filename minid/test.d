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

import std.stdio;

void main()
{
	MDGlobalState.initialize();
	MDState state = MDGlobalState().mainThread();
	baselib.init(state);
	stringlib.init(state);
	arraylib.init(state);
	tablelib.init(state);
	mathlib.init(state);
	charlib.init(state);

	MDClosure cl = new MDClosure(state, compileFile(`simple.md`));

	try
	{
		state.easyCall(cl, 0);
	}
	catch(MDException e)
	{
		writefln("error: ", e);
		writefln(state.getTracebackString());
	}
}
