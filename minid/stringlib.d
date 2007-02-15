module minid.stringlib;

import minid.types;
import minid.utils;

alias minid.utils.toInt toInt;

import string = std.string;
import std.conv;
import std.uni;

//import std.stdio;

class StringLib
{
	this(MDNamespace namespace)
	{
		iteratorClosure = new MDClosure(namespace, &iterator, "string.iterator");
		iteratorReverseClosure = new MDClosure(namespace, &iteratorReverse, "string.iteratorReverse");
		
		namespace.addList
		(
			"toInt",      new MDClosure(namespace, &toInt,      "string.toInt"),
			"toFloat",    new MDClosure(namespace, &toFloat,    "string.toFloat"),
			"compare",    new MDClosure(namespace, &compare,    "string.compare"),
			"icompare",   new MDClosure(namespace, &icompare,   "string.icompare"),
			"find",       new MDClosure(namespace, &find,       "string.find"),
			"ifind",      new MDClosure(namespace, &ifind,      "string.ifind"),
			"rfind",      new MDClosure(namespace, &rfind,      "string.rfind"),
			"irfind",     new MDClosure(namespace, &irfind,     "string.irfind"),
			"toLower",    new MDClosure(namespace, &toLower,    "string.toLower"),
			"toUpper",    new MDClosure(namespace, &toUpper,    "string.toUpper"),
			"repeat",     new MDClosure(namespace, &repeat,     "string.repeat"),
			"join",       new MDClosure(namespace, &join,       "string.join"),
			"split",      new MDClosure(namespace, &split,      "string.split"),
			"splitLines", new MDClosure(namespace, &splitLines, "string.splitLines"),
			"strip",      new MDClosure(namespace, &strip,      "string.strip"),
			"lstrip",     new MDClosure(namespace, &lstrip,     "string.lstrip"),
			"rstrip",     new MDClosure(namespace, &rstrip,     "string.rstrip"),
			"replace",    new MDClosure(namespace, &replace,    "string.replace"),
			"opApply",    new MDClosure(namespace, &apply,      "string.opApply")
		);
	}

	int toInt(MDState s)
	{
		dchar[] src = s.getStringParam(0).asUTF32();
		
		int base = 10;

		if(s.numParams() > 1)
			base = s.getIntParam(1);

		s.push(s.safeCode(.toInt(src, base)));
		return 1;
	}
	
	int toFloat(MDState s)
	{
		s.push(s.safeCode(std.conv.toFloat(s.getStringParam(0).asUTF8())));
		return 1;
	}
	
	int compare(MDState s)
	{
		char[] src1 = s.getStringParam(0).asUTF8();
		char[] src2 = s.getStringParam(1).asUTF8();

		s.push(s.safeCode(string.cmp(src1, src2)));
		return 1;
	}
	
	int icompare(MDState s)
	{
		char[] src1 = s.getStringParam(0).asUTF8();
		char[] src2 = s.getStringParam(1).asUTF8();

		s.push(s.safeCode(string.icmp(src1, src2)));
		return 1;
	}
	
	int find(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();

		if(s.isParam!("string")(1))
			s.push(s.safeCode(string.find(src, s.getStringParam(1).asUTF8())));
		else if(s.isParam!("char")(1))
			s.push(s.safeCode(string.find(src, s.getCharParam(1))));
		else
			s.throwRuntimeException("Second parameter must be string or int");

		return 1;
	}
	
	int ifind(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();

		if(s.isParam!("string")(1))
			s.push(s.safeCode(string.ifind(src, s.getStringParam(1).asUTF8())));
		else if(s.isParam!("char")(1))
			s.push(s.safeCode(string.ifind(src, s.getCharParam(1))));
		else
			s.throwRuntimeException("Second parameter must be string or int");

		return 1;
	}
	
	int rfind(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		
		if(s.isParam!("string")(1))
			s.push(s.safeCode(string.rfind(src, s.getStringParam(1).asUTF8())));
		else if(s.isParam!("char")(1))
			s.push(s.safeCode(string.rfind(src, s.getCharParam(1))));
		else
			s.throwRuntimeException("Second parameter must be string or int");

		return 1;
	}

	int irfind(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();

		if(s.isParam!("string")(1))
			s.push(s.safeCode(string.irfind(src, s.getStringParam(1).asUTF8())));
		else if(s.isParam!("char")(1))
			s.push(s.safeCode(string.irfind(src, s.getCharParam(1))));
		else
			s.throwRuntimeException("Second parameter must be string or int");

		return 1;
	}

	int toLower(MDState s)
	{
		MDString src = s.getStringParam(0);

		dchar[] dest = new dchar[src.length];

		s.safeCode
		({
			for(int i = 0; i < src.length; i++)
				dest[i] = toUniLower(src[i]);
		}());

		s.push(new MDString(dest));
		return 1;
	}
	
	int toUpper(MDState s)
	{
		MDString src = s.getStringParam(0);

		dchar[] dest = new dchar[src.length];
		
		s.safeCode
		({
			for(int i = 0; i < src.length; i++)
				dest[i] = toUniUpper(src[i]);
		}());

		s.push(new MDString(dest));
		return 1;
	}
	
	int repeat(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		int numTimes = s.getIntParam(1);
		
		if(numTimes < 1)
			s.throwRuntimeException("Invalid number of repetitions: ", numTimes);

		s.push(s.safeCode(string.repeat(src, numTimes)));
		return 1;
	}
	
	int join(MDState s)
	{
		MDArray array = s.getArrayParam(0);
		char[] sep = s.getStringParam(1).asUTF8();
		
		char[][] strings = new char[][array.length];
		
		foreach(uint i, MDValue val; array)
		{
			if(val.isString() == false)
				s.throwRuntimeException("Array element ", i, " is not a string");
				
			strings[i] = val.asString.asUTF8();
		}

		s.push(s.safeCode(string.join(strings, sep)));
		return 1;
	}
	
	int split(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();

		char[][] ret;

		if(s.numParams() > 1)
		{
			char[] delim = s.getStringParam(1).asUTF8();
			s.safeCode(ret = string.split(src, delim));
		}
		else
			s.safeCode(ret = string.split(src));

		MDArray array = new MDArray(ret.length);

		for(uint i = 0; i < ret.length; i++)
			array[i] = new MDString(ret[i]);

		s.push(array);
		return 1;
	}

	int splitLines(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		char[][] ret;

		s.safeCode(ret = string.splitlines(src));

		MDArray array = new MDArray(ret.length);

		for(uint i = 0; i < ret.length; i++)
			array[i] = new MDString(ret[i]);

		s.push(array);
		return 1;
	}
	
	int strip(MDState s)
	{
		s.push(s.safeCode(string.strip(s.getStringParam(0).asUTF8())));
		return 1;
	}

	int lstrip(MDState s)
	{
		s.push(s.safeCode(string.stripl(s.getStringParam(0).asUTF8())));
		return 1;
	}

	int rstrip(MDState s)
	{
		s.push(s.safeCode(string.stripr(s.getStringParam(0).asUTF8())));
		return 1;
	}

	int replace(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		char[] from = s.getStringParam(1).asUTF8();
		char[] to = s.getStringParam(2).asUTF8();

		s.push(s.safeCode(string.replace(src, from, to)));
		return 1;
	}

	int iterator(MDState s)
	{
		MDString string = s.getStringParam(0);
		int index = s.getIntParam(1);

		index++;

		if(index >= string.length)
			return 0;
			
		s.push(index);
		s.push(string[index]);

		return 2;
	}
	
	int iteratorReverse(MDState s)
	{
		MDString string = s.getStringParam(0);
		int index = s.getIntParam(1);

		index--;

		if(index < 0)
			return 0;

		s.push(index);
		s.push(string[index]);
		
		return 2;
	}
	
	MDClosure iteratorClosure;
	MDClosure iteratorReverseClosure;
	
	int apply(MDState s)
	{
		MDString string = s.getStringParam(0);

		if(s.numParams() > 1 && s.isParam!("string")(1) && s.getStringParam(1) == "reverse"d)
		{
			s.push(iteratorReverseClosure);
			s.push(string);
			s.push(cast(int)string.length);
		}
		else
		{
			s.push(iteratorClosure);
			s.push(string);
			s.push(-1);
		}

		return 3;
	}
}

public void init()
{
	MDNamespace namespace = new MDNamespace("string"d);
	new StringLib(namespace);
	MDGlobalState().setGlobal("string"d, namespace);
	MDGlobalState().setMetatable(MDValue.Type.String, namespace);
}