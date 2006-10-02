module minid.test;

import minid.state;
import minid.types;
import minid.compiler;
import baselib = minid.baselib;
import stringlib = minid.stringlib;
import arraylib = minid.arraylib;
import tablelib = minid.tablelib;

import std.stdio;

void main()
{
	MDGlobalState.initialize();
	MDState state = MDGlobalState().mainThread();
	baselib.init(state);
	stringlib.init(state);
	arraylib.init(state);
	tablelib.init(state);

	MDClosure cl = new MDClosure(state, compileFile(`simple.md`));

	try
	{
		state.easyCall(cl, 0);
	}
	catch
	{
		writefln("error: ", state.getDebugLocation().toString());
	}
}
