module minid.baselib;

import minid.state;
import minid.types;

import std.stdio;

class BaseLib
{
	int mdwritefln(MDState s)
	{
		int numParams = s.numParams();

		for(int i = 0; i < numParams; i++)
			writef(s.getParam(i).toString());

		writefln();

		return 0;
	}

	static MDString[] typeStrings;
	
	static this()
	{
		typeStrings = new MDString[MDValue.Type.max + 1];

		for(uint i = MDValue.Type.min; i <= MDValue.Type.max; i++)
			typeStrings[i] = new MDString(MDValue.typeString(cast(MDValue.Type)i));
	}

	int mdtypeof(MDState s)
	{
		if(s.numParams < 1)
			throw new MDRuntimeException(s, "Parameter expected");

		s.push(typeStrings[s.getParam(0).type]);
		return 1;
	}

	int mdtoString(MDState s)
	{
		if(s.numParams < 1)
			throw new MDRuntimeException(s, "Parameter expected");
			
		s.push(s.getParam(0).toString());
		return 1;
	}
	
	int setMetatable(MDState s)
	{
		MDTable tab = s.getTableParam(0);

		if(s.numParams() == 1 || s.isNullParam(1))
			tab.metatable = null;
		else
			tab.metatable = s.getTableParam(1);
			
		return 0;
	}

	int mddelegate(MDState s)
	{
		MDClosure func = s.getClosureParam(0);

		if(s.numParams() == 1)
			throw new MDRuntimeException(s, "Need parameters to bind to delegate");

		MDValue[] params = s.getAllParams()[1 .. $];

		s.push(new MDDelegate(s, func, params));
		
		return 1;
	}
	
	int getTraceback(MDState s)
	{
		s.push(new MDString(s.getTracebackString()));
		
		return 1;
	}
}

public void init(MDState s)
{
	BaseLib lib = new BaseLib();

	s.setGlobal("writefln",     new MDClosure(s, &lib.mdwritefln,   "writefln"));
	s.setGlobal("typeof",       new MDClosure(s, &lib.mdtypeof,     "typeof"));
	s.setGlobal("toString",     new MDClosure(s, &lib.mdtoString,   "toString"));
	s.setGlobal("setMetatable", new MDClosure(s, &lib.setMetatable, "setMetatable"));
	s.setGlobal("delegate",     new MDClosure(s, &lib.mddelegate,   "delegate"));
	s.setGlobal("getTraceback", new MDClosure(s, &lib.getTraceback, "getTraceback"));
}