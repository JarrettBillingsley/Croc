module minid.stringlib;

import minid.state;
import minid.types;

import string = std.string;
import std.conv;
import std.uni;

//import std.stdio;

int toIntEx(dchar[] s, int base)
{
	assert(base >= 2 && base <= 36, "toInt - invalid base");

	static char[] transTable =
	[
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 0, 0, 0, 0, 0, 0,
		0, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72,
		73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 0, 0, 0, 0, 0,
		0, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72,
		73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	];

    int length = s.length;

	if(!length)
		throw new ConvError(utf.toUTF8(s));

	int sign = 0;
	int v = 0;

	char maxDigit = '0' + base - 1;

	for(int i = 0; i < length; i++)
	{
		char c = transTable[s[i]];

		if(c >= '0' && c <= maxDigit)
		{
			uint v1 = v;
			v = v * base + (c - '0');

			if(cast(uint)v < v1)
				throw new ConvOverflowError(utf.toUTF8(s));
		}
		else if(c == '-' && i == 0)
		{
			sign = -1;

			if(length == 1)
				throw new ConvError(utf.toUTF8(s));
		}
		else if(c == '+' && i == 0)
		{
			if(length == 1)
				throw new ConvError(utf.toUTF8(s));
		}
		else
			throw new ConvError(utf.toUTF8(s));
	}

	if(sign == -1)
	{
		if(cast(uint)v > 0x80000000)
			throw new ConvOverflowError(utf.toUTF8(s));

		v = -v;
	}
	else
	{
		if(cast(uint)v > 0x7FFFFFFF)
			throw new ConvOverflowError(utf.toUTF8(s));
	}

	return v;
}

class StringLib
{
	int toInt(MDState s)
	{
		dchar[] src = s.getStringParam(0).asUTF32();
		
		int base = 10;

		if(s.numParams() > 1)
			base = s.getIntParam(1);

		int dest;
	
		try
		{
			dest = toIntEx(src, base);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(dest);
		
		return 1;
	}
	
	int toFloat(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		
		float dest;
	
		try
		{
			dest = std.conv.toFloat(utf.toUTF8(src));
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(dest);

		return 1;
	}
	
	int compare(MDState s)
	{
		char[] src1 = s.getStringParam(0).asUTF8();
		char[] src2 = s.getStringParam(1).asUTF8();
		
		int ret;

		try
		{
			ret = string.cmp(src1, src2);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(ret);

		return 1;
	}
	
	int icompare(MDState s)
	{
		char[] src1 = s.getStringParam(0).asUTF8();
		char[] src2 = s.getStringParam(1).asUTF8();
		
		int ret;
		
		try
		{
			ret = string.icmp(src1, src2);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(ret);

		return 1;
	}
	
	int find(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		
		int ret;

		if(s.isParam!("string")(1))
		{
			try
			{
				ret = string.find(src, s.getStringParam(1).asUTF8());
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		else if(s.isParam!("char")(1))
		{
			try
			{
				ret = string.find(src, s.getCharParam(1));
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		else
			throw new MDRuntimeException(s, "Second parameter must be string or int");

		s.push(ret);

		return 1;
	}
	
	int ifind(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		
		int ret;

		if(s.isParam!("string")(1))
		{
			try
			{
				ret = string.ifind(src, s.getStringParam(1).asUTF8());
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		else if(s.isParam!("char")(1))
		{
			try
			{
				ret = string.ifind(src, s.getCharParam(1));
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		else
			throw new MDRuntimeException(s, "Second parameter must be string or int");

		s.push(ret);

		return 1;
	}
	
	int rfind(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		
		int ret;

		if(s.isParam!("string")(1))
		{
			try
			{
				ret = string.rfind(src, s.getStringParam(1).asUTF8());
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		else if(s.isParam!("char")(1))
		{
			try
			{
				ret = string.rfind(src, s.getCharParam(1));
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		else
			throw new MDRuntimeException(s, "Second parameter must be string or int");

		s.push(ret);

		return 1;
	}
	
	int irfind(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		
		int ret;

		if(s.isParam!("string")(1))
		{
			try
			{
				ret = string.irfind(src, s.getStringParam(1).asUTF8());
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		else if(s.isParam!("char")(1))
		{
			try
			{
				ret = string.irfind(src, s.getCharParam(1));
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		else
			throw new MDRuntimeException(s, "Second parameter must be string or int");

		s.push(ret);

		return 1;
	}
	
	int toLower(MDState s)
	{
		MDString src = s.getStringParam(0);
		
		dchar[] dest = new dchar[src.length];
		
		try
		{
			for(int i = 0; i < src.length; i++)
				dest[i] = toUniLower(src[i]);
		}
		catch(MDException e)
		{
			throw e;
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}
		
		s.push(new MDString(dest));
		
		return 1;
	}
	
	int toUpper(MDState s)
	{
		MDString src = s.getStringParam(0);
		
		dchar[] dest = new dchar[src.length];
		
		try
		{
			for(int i = 0; i < src.length; i++)
				dest[i] = toUniUpper(src[i]);
		}
		catch(MDException e)
		{
			throw e;
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}
		
		s.push(new MDString(dest));
		
		return 1;
	}
	
	int repeat(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		int numTimes = s.getIntParam(1);
		
		if(numTimes < 1)
			throw new MDRuntimeException(s, "Invalid number of repetitions: ", numTimes);

		char[] ret;
		
		try
		{
			ret = string.repeat(src, numTimes);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(ret);
		
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
				throw new MDRuntimeException(s, "Array element ", i, " is not a string");
				
			strings[i] = val.asString.asUTF8();
		}

		char[] ret;

		try
		{
			ret = string.join(strings, sep);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(ret);
		
		return 1;
	}
	
	int split(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();

		char[][] ret;

		if(s.numParams() > 1)
		{
			char[] delim = s.getStringParam(1).asUTF8();

			try
			{
				ret = string.split(src, delim);
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		else
		{
			try
			{
				ret = string.split(src);
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		
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

		try
		{
			ret = string.splitlines(src);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		MDArray array = new MDArray(ret.length);
		
		for(uint i = 0; i < ret.length; i++)
			array[i] = new MDString(ret[i]);
			
		s.push(array);
		
		return 1;
	}
	
	int strip(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		char[] ret;

		try
		{
			ret = string.strip(src);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(ret);

		return 1;
	}
	
	int lstrip(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		char[] ret;

		try
		{
			ret = string.stripl(src);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(ret);
		
		return 1;
	}
	
	int rstrip(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		char[] ret;

		try
		{
			ret = string.stripr(src);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(ret);

		return 1;
	}

	int fromChar(MDState s)
	{
		dchar c;
		
		if(s.isParam!("int")(0))
			c = s.getIntParam(0);
		else
			c = s.getCharParam(0);

		if(!utf.isValidDchar(c))
			throw new MDRuntimeException(s, "Invalid character: U+%x", cast(int)c);
			
		dchar[] str = new dchar[1];
		str[0] = c;

		return s.push(new MDString(str));
	}
	
	int replace(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		char[] from = s.getStringParam(1).asUTF8();
		char[] to = s.getStringParam(2).asUTF8();
		
		char[] ret;
		
		try
		{
			ret = string.replace(src, from, to);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(ret);
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

public void init(MDState s)
{
	StringLib lib = new StringLib();
	
	lib.iteratorClosure = new MDClosure(s, &lib.iterator, "string.iterator");
	lib.iteratorReverseClosure = new MDClosure(s, &lib.iteratorReverse, "string.iteratorReverse");

	MDTable stringTable = MDTable.create
	(
		"toInt",      new MDClosure(s, &lib.toInt,      "string.toInt"),
		"toFloat",    new MDClosure(s, &lib.toFloat,    "string.toFloat"),
		"compare",    new MDClosure(s, &lib.compare,    "string.compare"),
		"icompare",   new MDClosure(s, &lib.icompare,   "string.icompare"),
		"find",       new MDClosure(s, &lib.find,       "string.find"),
		"ifind",      new MDClosure(s, &lib.ifind,      "string.ifind"),
		"rfind",      new MDClosure(s, &lib.rfind,      "string.rfind"),
		"irfind",     new MDClosure(s, &lib.irfind,     "string.irfind"),
		"toLower",    new MDClosure(s, &lib.toLower,    "string.toLower"),
		"toUpper",    new MDClosure(s, &lib.toUpper,    "string.toUpper"),
		"repeat",     new MDClosure(s, &lib.repeat,     "string.repeat"),
		"join",       new MDClosure(s, &lib.join,       "string.join"),
		"split",      new MDClosure(s, &lib.split,      "string.split"),
		"splitLines", new MDClosure(s, &lib.splitLines, "string.splitLines"),
		"strip",      new MDClosure(s, &lib.strip,      "string.strip"),
		"lstrip",     new MDClosure(s, &lib.lstrip,     "string.lstrip"),
		"rstrip",     new MDClosure(s, &lib.rstrip,     "string.rstrip"),
		"fromChar",   new MDClosure(s, &lib.fromChar,   "string.fromChar"),
		"replace",    new MDClosure(s, &lib.replace,    "string.replace"),
		"opApply",    new MDClosure(s, &lib.apply,      "string.opApply")
	);

	s.setGlobal("string"d, stringTable);
	MDGlobalState().setMetatable(MDValue.Type.String, stringTable);
}