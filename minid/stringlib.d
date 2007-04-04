/******************************************************************************
License:
Copyright (c) 2007 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

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
			"toInt"d,      new MDClosure(namespace, &toInt,      "string.toInt"),
			"toFloat"d,    new MDClosure(namespace, &toFloat,    "string.toFloat"),
			"compare"d,    new MDClosure(namespace, &compare,    "string.compare"),
			"icompare"d,   new MDClosure(namespace, &icompare,   "string.icompare"),
			"find"d,       new MDClosure(namespace, &find,       "string.find"),
			"ifind"d,      new MDClosure(namespace, &ifind,      "string.ifind"),
			"rfind"d,      new MDClosure(namespace, &rfind,      "string.rfind"),
			"irfind"d,     new MDClosure(namespace, &irfind,     "string.irfind"),
			"toLower"d,    new MDClosure(namespace, &toLower,    "string.toLower"),
			"toUpper"d,    new MDClosure(namespace, &toUpper,    "string.toUpper"),
			"repeat"d,     new MDClosure(namespace, &repeat,     "string.repeat"),
			"split"d,      new MDClosure(namespace, &split,      "string.split"),
			"splitLines"d, new MDClosure(namespace, &splitLines, "string.splitLines"),
			"strip"d,      new MDClosure(namespace, &strip,      "string.strip"),
			"lstrip"d,     new MDClosure(namespace, &lstrip,     "string.lstrip"),
			"rstrip"d,     new MDClosure(namespace, &rstrip,     "string.rstrip"),
			"replace"d,    new MDClosure(namespace, &replace,    "string.replace"),
			"opApply"d,    new MDClosure(namespace, &apply,      "string.opApply")
		);

		MDGlobalState().setGlobal("string"d, MDNamespace.create
		(
			"string"d, MDGlobalState().globals,
			"join"d,       new MDClosure(namespace, &join,       "string.join")
		));
	}

	int toInt(MDState s, uint numParams)
	{
		dchar[] src = s.getContext!(dchar[]);

		int base = 10;

		if(numParams > 0)
			base = s.getParam!(int)(0);

		s.push(s.safeCode(.toInt(src, base)));
		return 1;
	}
	
	int toFloat(MDState s, uint numParams)
	{
		s.push(s.safeCode(std.conv.toFloat(s.getContext!(char[]))));
		return 1;
	}
	
	int compare(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDString).opCmp(s.getParam!(MDString)(0)));
		return 1;
	}

	int icompare(MDState s, uint numParams)
	{
		char[] src1 = s.getContext!(char[]);
		char[] src2 = s.getParam!(char[])(0);

		s.push(s.safeCode(string.icmp(src1, src2)));
		return 1;
	}
	
	int find(MDState s, uint numParams)
	{
		char[] src = s.getContext!(char[]);

		if(s.isParam!("string")(0))
			s.push(s.safeCode(string.find(src, s.getParam!(char[])(0))));
		else if(s.isParam!("char")(0))
			s.push(s.safeCode(string.find(src, s.getParam!(dchar)(0))));
		else
			s.throwRuntimeException("Second parameter must be string or int");

		return 1;
	}
	
	int ifind(MDState s, uint numParams)
	{
		char[] src = s.getContext!(char[]);

		if(s.isParam!("string")(0))
			s.push(s.safeCode(string.ifind(src, s.getParam!(char[])(0))));
		else if(s.isParam!("char")(0))
			s.push(s.safeCode(string.ifind(src, s.getParam!(dchar)(0))));
		else
			s.throwRuntimeException("Second parameter must be string or int");

		return 1;
	}
	
	int rfind(MDState s, uint numParams)
	{
		char[] src = s.getContext!(char[]);
		
		if(s.isParam!("string")(0))
			s.push(s.safeCode(string.rfind(src, s.getParam!(char[])(0))));
		else if(s.isParam!("char")(0))
			s.push(s.safeCode(string.rfind(src, s.getParam!(dchar)(0))));
		else
			s.throwRuntimeException("Second parameter must be string or int");

		return 1;
	}

	int irfind(MDState s, uint numParams)
	{
		char[] src = s.getContext!(char[]);

		if(s.isParam!("string")(0))
			s.push(s.safeCode(string.irfind(src, s.getParam!(char[])(0))));
		else if(s.isParam!("char")(0))
			s.push(s.safeCode(string.irfind(src, s.getParam!(dchar)(0))));
		else
			s.throwRuntimeException("Second parameter must be string or int");

		return 1;
	}

	int toLower(MDState s, uint numParams)
	{
		MDString src = s.getContext!(MDString);

		dchar[] dest = toLowerD(src.mData);
		
		if(dest is src.mData)
			s.push(src);
		else
			s.push(new MDString(dest));

		return 1;
	}
	
	int toUpper(MDState s, uint numParams)
	{
		MDString src = s.getContext!(MDString);

		dchar[] dest = toUpperD(src.mData);
		
		if(dest is src.mData)
			s.push(src);
		else
			s.push(new MDString(dest));

		return 1;
	}
	
	int repeat(MDState s, uint numParams)
	{
		char[] src = s.getContext!(char[]);
		int numTimes = s.getParam!(int)(0);
		
		if(numTimes < 0)
			s.throwRuntimeException("Invalid number of repetitions: ", numTimes);

		s.push(s.safeCode(string.repeat(src, numTimes)));
		return 1;
	}
	
	int join(MDState s, uint numParams)
	{
		MDArray array = s.getParam!(MDArray)(0);
		char[] sep = s.getParam!(char[])(1);
		
		char[][] strings = new char[][array.length];
		
		foreach(uint i, MDValue val; array)
		{
			if(val.isString() == false)
				s.throwRuntimeException("Array element ", i, " is not a string");
				
			strings[i] = val.as!(char[]);
		}

		s.push(s.safeCode(string.join(strings, sep)));
		return 1;
	}
	
	int split(MDState s, uint numParams)
	{
		char[] src = s.getContext!(char[]);

		char[][] ret;

		if(numParams > 0)
		{
			char[] delim = s.getParam!(char[])(0);
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

	int splitLines(MDState s, uint numParams)
	{
		char[] src = s.getContext!(char[]);
		char[][] ret;

		s.safeCode(ret = string.splitlines(src));

		MDArray array = new MDArray(ret.length);

		for(uint i = 0; i < ret.length; i++)
			array[i] = new MDString(ret[i]);

		s.push(array);
		return 1;
	}
	
	int strip(MDState s, uint numParams)
	{
		s.push(s.safeCode(string.strip(s.getContext!(char[]))));
		return 1;
	}

	int lstrip(MDState s, uint numParams)
	{
		s.push(s.safeCode(string.stripl(s.getContext!(char[]))));
		return 1;
	}

	int rstrip(MDState s, uint numParams)
	{
		s.push(s.safeCode(string.stripr(s.getContext!(char[]))));
		return 1;
	}

	int replace(MDState s, uint numParams)
	{
		char[] src = s.getContext!(char[]);
		char[] from = s.getParam!(char[])(0);
		char[] to = s.getParam!(char[])(1);

		s.push(s.safeCode(string.replace(src, from, to)));
		return 1;
	}

	int iterator(MDState s, uint numParams)
	{
		MDString string = s.getContext!(MDString);
		int index = s.getParam!(int)(0);

		index++;

		if(index >= string.length)
			return 0;
			
		s.push(index);
		s.push(string[index]);

		return 2;
	}
	
	int iteratorReverse(MDState s, uint numParams)
	{
		MDString string = s.getContext!(MDString);
		int index = s.getParam!(int)(0);

		index--;

		if(index < 0)
			return 0;

		s.push(index);
		s.push(string[index]);
		
		return 2;
	}
	
	MDClosure iteratorClosure;
	MDClosure iteratorReverseClosure;
	
	int apply(MDState s, uint numParams)
	{
		MDString string = s.getContext!(MDString);

		if(s.isParam!("string")(0) && s.getParam!(MDString)(0) == "reverse"d)
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
	MDNamespace namespace = new MDNamespace("string"d, MDGlobalState().globals);
	new StringLib(namespace);
	MDGlobalState().setMetatable(MDValue.Type.String, namespace);
}