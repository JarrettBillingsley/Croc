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

		typeStrings[MDValue.Type.Null] = new MDString("null"d);
		typeStrings[MDValue.Type.Bool] = new MDString("bool"d);
		typeStrings[MDValue.Type.Int] = new MDString("int"d);
		typeStrings[MDValue.Type.Float] = new MDString("float"d);
		typeStrings[MDValue.Type.String] = new MDString("string"d);
		typeStrings[MDValue.Type.Table] = new MDString("table"d);
		typeStrings[MDValue.Type.Array] = new MDString("array"d);
		typeStrings[MDValue.Type.Function] = new MDString("function"d);
		typeStrings[MDValue.Type.UserData] = new MDString("userdata"d);
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
}

public void init(MDState s)
{
	BaseLib lib = new BaseLib();

	s.setGlobal("writefln",     new MDClosure(s, &lib.mdwritefln,   "writefln"));
	s.setGlobal("typeof",       new MDClosure(s, &lib.mdtypeof,     "typeof"));
	s.setGlobal("toString",     new MDClosure(s, &lib.mdtoString,   "toString"));
	s.setGlobal("setMetatable", new MDClosure(s, &lib.setMetatable, "setMetatable"));
}