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
	iolib.init(state);

	MDClosure cl = new MDClosure(state, compileFile(`simple.md`));
	
	state.setGlobal("intToChar"d, new MDClosure(state, delegate int(MDState s)
	{
		s.push(cast(dchar)s.getIntParam(0));
		return 1;
	}, "intToChar"));

	/*MDClass testClass = new MDClass(state, "Test", null);
	
	int testMethod1(MDState s)
	{
		MDInstance _this = s.getInstanceParam(0);

		writefln("testMethod1 hi");
		writefln("x: ", _this["x"].asInt, " y: ", _this["y"].asInt);
		return 0;
	}

	int testMethod2(MDState s)
	{
		int x = s.getIntParam(1);

		writefln("testMethod2 got ", x);
		return 0;
	}

	testClass["testMethod1"] = new MDClosure(state, &testMethod1, "testMethod1");
	testClass["testMethod2"] = new MDClosure(state, &testMethod2, "testMethod2");
	
	MDValue val;
	val.value = 0;
	testClass["x"] = &val;
	testClass["y"] = &val;

	state.setGlobal("Test"d, testClass);*/

	try
	{
		state.easyCall(cl, 0u);
	}
	catch(MDException e)
	{
		writefln("error: ", e);
		writefln(state.getTracebackString());
	}
}
