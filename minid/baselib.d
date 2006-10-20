module minid.baselib;

import minid.state;
import minid.types;
import minid.compiler;

import std.stdio;
import std.stream;

class BaseLib
{
	int mdwritefln(MDState s)
	{
		int numParams = s.numParams();

		for(int i = 0; i < numParams; i++)
			writef("%s", s.getParam(i).toString());

		writefln();

		return 0;
	}
	
	int mdwritef(MDState s)
	{
		int numParams = s.numParams();

		for(int i = 0; i < numParams; i++)
			writef("%s", s.getParam(i).toString());

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
		s.push(typeStrings[s.getParam(0).type]);
		return 1;
	}

	int classof(MDState s)
	{
		s.push(s.getInstanceParam(0).getClass());
		return 1;
	}

	int mdtoString(MDState s)
	{
		s.push(s.getParam(0).toString());
		return 1;
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

	int isNull(MDState s)
	{
		s.push(s.getParam(0).isNull());
		return 1;
	}
	
	int isBool(MDState s)
	{
		s.push(s.getParam(0).isBool());
		return 1;
	}
	
	int isInt(MDState s)
	{
		s.push(s.getParam(0).isInt());
		return 1;
	}
	
	int isFloat(MDState s)
	{
		s.push(s.getParam(0).isFloat());
		return 1;
	}
	
	int isChar(MDState s)
	{
		s.push(s.getParam(0).isChar());
		return 1;
	}
	
	int isString(MDState s)
	{
		s.push(s.getParam(0).isString());
		return 1;
	}
	
	int isTable(MDState s)
	{
		s.push(s.getParam(0).isTable());
		return 1;
	}
	
	int isArray(MDState s)
	{
		s.push(s.getParam(0).isArray());
		return 1;
	}
	
	int isFunction(MDState s)
	{
		s.push(s.getParam(0).isFunction());
		return 1;
	}
	
	int isUserdata(MDState s)
	{
		s.push(s.getParam(0).isUserdata());
		return 1;
	}
	
	int isClass(MDState s)
	{
		s.push(s.getParam(0).isClass());
		return 1;
	}
	
	int isInstance(MDState s)
	{
		s.push(s.getParam(0).isInstance());
		return 1;
	}

	int isDelegate(MDState s)
	{
		s.push(s.getParam(0).isDelegate());
		return 1;
	}
	
	int mdassert(MDState s)
	{
		MDValue condition = s.getParam(0);
		
		if(condition.isFalse())
		{
			if(s.numParams() == 1)
				throw new MDRuntimeException(s, "Assertion Failed!");
			else
				throw new MDRuntimeException(s, "Assertion Failed: %s", s.getParam(1).toString());
		}
		
		return 0;
	}
}

public void init(MDState s)
{
	BaseLib lib = new BaseLib();

	s.setGlobal("writefln",     new MDClosure(s, &lib.mdwritefln,   "writefln"));
	s.setGlobal("writef",       new MDClosure(s, &lib.mdwritef,     "writef"));
	s.setGlobal("typeof",       new MDClosure(s, &lib.mdtypeof,     "typeof"));
	s.setGlobal("classof",      new MDClosure(s, &lib.classof,      "classof"));
	s.setGlobal("toString",     new MDClosure(s, &lib.mdtoString,   "toString"));
	s.setGlobal("delegate",     new MDClosure(s, &lib.mddelegate,   "delegate"));
	s.setGlobal("getTraceback", new MDClosure(s, &lib.getTraceback, "getTraceback"));
	s.setGlobal("isNull",       new MDClosure(s, &lib.isNull,       "isNull"));
	s.setGlobal("isBool",       new MDClosure(s, &lib.isBool,       "isBool"));
	s.setGlobal("isInt",        new MDClosure(s, &lib.isInt,        "isInt"));
	s.setGlobal("isFloat",      new MDClosure(s, &lib.isFloat,      "isFloat"));
	s.setGlobal("isChar",       new MDClosure(s, &lib.isChar,       "isChar"));
	s.setGlobal("isString",     new MDClosure(s, &lib.isString,     "isString"));
	s.setGlobal("isTable",      new MDClosure(s, &lib.isTable,      "isTable"));
	s.setGlobal("isArray",      new MDClosure(s, &lib.isArray,      "isArray"));
	s.setGlobal("isFunction",   new MDClosure(s, &lib.isFunction,   "isFunction"));
	s.setGlobal("isUserdata",   new MDClosure(s, &lib.isUserdata,   "isUserdata"));
	s.setGlobal("isClass",      new MDClosure(s, &lib.isClass,      "isClass"));
	s.setGlobal("isInstance",   new MDClosure(s, &lib.isInstance,   "isInstance"));
	s.setGlobal("isDelegate",   new MDClosure(s, &lib.isDelegate,   "isDelegate"));
	s.setGlobal("assert",       new MDClosure(s, &lib.mdassert,     "assert"));
}