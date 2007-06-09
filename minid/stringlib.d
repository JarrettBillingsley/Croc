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

import Integer = tango.text.convert.Integer;
import Float = tango.text.convert.Float;
import tango.text.Ascii;
import tango.core.Array;
import tango.text.Util;
import UniChar;

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

		MDGlobalState().globals["string"d] = MDNamespace.create
		(
			"string"d, MDGlobalState().globals.ns,
			"join"d,       new MDClosure(namespace, &join,       "string.join")
		);
	}

	int toInt(MDState s, uint numParams)
	{
		dchar[] src = s.getContext!(dchar[]);

		int base = 10;

		if(numParams > 0)
			base = s.getParam!(int)(0);

		s.push(s.safeCode(Integer.toInt(src, base)));
		return 1;
	}

	int toFloat(MDState s, uint numParams)
	{
		s.push(s.safeCode(Float.toFloat(s.getContext!(dchar[]))));
		return 1;
	}
	
	int compare(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDString).opCmp(s.getParam!(MDString)(0)));
		return 1;
	}

	int icompare(MDState s, uint numParams)
	{
		s.push(.icompare(s.getContext!(char[]), s.getParam!(char[])(0)));
		return 1;
	}
	
	int find(MDState s, uint numParams)
	{
		dchar[] src = s.getContext!(dchar[]);
		uint result;

		if(s.isParam!("string")(0))
			result = locatePattern(src, s.getParam!(dchar[])(0));
		else if(s.isParam!("char")(0))
			result = locate(src, s.getParam!(dchar)(0));
		else
			s.throwRuntimeException("Second parameter must be string or char");

		if(result == src.length)
			s.push(-1);
		else
			s.push(result);

		return 1;
	}
	
	int ifind(MDState s, uint numParams)
	{
		dchar[] src = toLowerD(s.getContext!(dchar[]));
		uint result;

		if(s.isParam!("string")(0))
			result = locatePattern(src, toLowerD(s.getParam!(dchar[])(0)));
		else if(s.isParam!("char")(0))
			result = locate(src, toUniLower(s.getParam!(dchar)(0)));
		else
			s.throwRuntimeException("Second parameter must be string or int");
			
		if(result == src.length)
			s.push(-1);
		else
			s.push(result);

		return 1;
	}
	
	int rfind(MDState s, uint numParams)
	{
		dchar[] src = s.getContext!(dchar[]);
		uint result;

		if(s.isParam!("string")(0))
			result = locatePatternPrior(src, s.getParam!(dchar[])(0));
		else if(s.isParam!("char")(0))
			result = locatePrior(src, s.getParam!(dchar)(0));
		else
			s.throwRuntimeException("Second parameter must be string or int");

		if(result == src.length)
			s.push(-1);
		else
			s.push(result);

		return 1;
	}

	int irfind(MDState s, uint numParams)
	{
		dchar[] src = toLowerD(s.getContext!(dchar[]));
		uint result;

		if(s.isParam!("string")(0))
			result = locatePatternPrior(src, toLowerD(s.getParam!(dchar[])(0)));
		else if(s.isParam!("char")(0))
			result = locatePrior(src, toUniLower(s.getParam!(dchar)(0)));
		else
			s.throwRuntimeException("Second parameter must be string or int");
			
		if(result == src.length)
			s.push(-1);
		else
			s.push(result);

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
			s.throwRuntimeException("Invalid number of repetitions: {}", numTimes);

		s.push(.repeat(src, numTimes));
		return 1;
	}
	
	int join(MDState s, uint numParams)
	{
		MDArray array = s.getParam!(MDArray)(0);
		dchar[] sep = s.getParam!(dchar[])(1);
		
		dchar[][] strings = new dchar[][array.length];
		
		foreach(uint i, MDValue val; array)
		{
			if(val.isString() == false)
				s.throwRuntimeException("Array element {} is not a string", i);
				
			strings[i] = val.as!(dchar[]);
		}

		s.push(.join(strings, sep));
		return 1;
	}
	
	int split(MDState s, uint numParams)
	{
		dchar[] src = s.getContext!(dchar[]);
		dchar[][] ret;

		if(numParams > 0)
			ret = .split(src, s.getParam!(dchar[])(0));
		else
		{
			ret = src.delimit(" \t\v\r\n\f\u2028\u2029"d);
			uint num = ret.removeIf((dchar[] elem) { return elem.length == 0; });
			ret = ret[0 .. num];
		}

		s.push(MDArray.fromArray(ret));
		return 1;
	}

	int splitLines(MDState s, uint numParams)
	{
		s.push(MDArray.fromArray(.splitLines(s.getContext!(dchar[]))));
		return 1;
	}
	
	int strip(MDState s, uint numParams)
	{
		s.push(trim(s.getContext!(dchar[])));
		return 1;
	}

	int lstrip(MDState s, uint numParams)
	{
		dchar[] str = s.getContext!(dchar[]);
		size_t i;

		for(i = 0; i < str.length && isSpace(str[i]); i++){}

		s.push(str[i .. $]);
		return 1;
	}

	int rstrip(MDState s, uint numParams)
	{
		dchar[] str = s.getContext!(dchar[]);
		int i;

		for(i = str.length - 1; i >= 0 && isSpace(str[i]); i--){}

		s.push(str[0 .. i + 1]);
		return 1;
	}

	int replace(MDState s, uint numParams)
	{
		s.push(.substitute(s.getContext!(dchar[]), s.getParam!(dchar[])(0), s.getParam!(dchar[])(1)));
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
	MDNamespace namespace = new MDNamespace("string"d, MDGlobalState().globals.ns);
	new StringLib(namespace);
	MDGlobalState().setMetatable(MDValue.Type.String, namespace);
}