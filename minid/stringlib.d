module minid.stringlib;

import minid.state;
import minid.types;

import string = std.string;
import std.conv;

//import std.stdio;

int toIntEx(char[] s, int base)
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
		throw new ConvError(s);

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
				throw new ConvOverflowError(s);
		}
		else if(c == '-' && i == 0)
		{
			sign = -1;

			if(length == 1)
				throw new ConvError(s);
		}
		else if(c == '+' && i == 0)
		{
			if(length == 1)
				throw new ConvError(s);
		}
		else
			throw new ConvError(s);
	}
	
	if(sign == -1)
	{
		if(cast(uint)v > 0x80000000)
			throw new ConvOverflowError(s);

		v = -v;
	}
	else
	{
		if(cast(uint)v > 0x7FFFFFFF)
			throw new ConvOverflowError(s);
	}

	return v;
}

class StringLib
{
	int toInt(MDState s)
	{
		char[] src = s.getStringParam(0);
		
		int base = 10;

		if(s.numParams() > 1)
			base = s.getIntParam(1);

		int dest;
	
		try
		{
			dest = toIntEx(src, base);
		}
		catch(MDException e)
		{
			throw e;
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
		char[] src = s.getStringParam(0);
		
		float dest;
	
		try
		{
			dest = std.conv.toFloat(utf.toUTF8(src));
		}
		catch(MDException e)
		{
			throw e;
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
		char[] src1 = s.getStringParam(0);
		char[] src2 = s.getStringParam(1);
		
		int ret;
		
		try
		{
			ret = string.cmp(src1, src2);
		}
		catch(MDException e)
		{
			throw e;
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
		char[] src1 = s.getStringParam(0);
		char[] src2 = s.getStringParam(1);
		
		int ret;
		
		try
		{
			ret = string.icmp(src1, src2);
		}
		catch(MDException e)
		{
			throw e;
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
		char[] src = s.getStringParam(0);
		
		int ret;

		if(s.isStringParam(1))
		{
			try
			{
				ret = string.find(src, s.getStringParam(1));
			}
			catch(MDException e)
			{
				throw e;
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		else if(s.isIntParam(1))
		{
			try
			{
				ret = string.find(src, cast(dchar)s.getIntParam(1));
			}
			catch(MDException e)
			{
				throw e;
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
		char[] src = s.getStringParam(0);
		
		int ret;

		if(s.isStringParam(1))
		{
			try
			{
				ret = string.ifind(src, s.getStringParam(1));
			}
			catch(MDException e)
			{
				throw e;
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		else if(s.isIntParam(1))
		{
			try
			{
				ret = string.ifind(src, cast(dchar)s.getIntParam(1));
			}
			catch(MDException e)
			{
				throw e;
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
		char[] src = s.getStringParam(0);
		
		int ret;

		if(s.isStringParam(1))
		{
			try
			{
				ret = string.rfind(src, s.getStringParam(1));
			}
			catch(MDException e)
			{
				throw e;
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		else if(s.isIntParam(1))
		{
			try
			{
				ret = string.rfind(src, cast(dchar)s.getIntParam(1));
			}
			catch(MDException e)
			{
				throw e;
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
		char[] src = s.getStringParam(0);
		
		int ret;

		if(s.isStringParam(1))
		{
			try
			{
				ret = string.irfind(src, s.getStringParam(1));
			}
			catch(MDException e)
			{
				throw e;
			}
			catch(Exception e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
		}
		else if(s.isIntParam(1))
		{
			try
			{
				ret = string.irfind(src, cast(dchar)s.getIntParam(1));
			}
			catch(MDException e)
			{
				throw e;
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
	
	int charAt(MDState s)
	{
		dchar[] src = s.getDStringParam(0);
		int index = s.getIntParam(1);
		
		if(index < 0 || index >= src.length)
			throw new MDRuntimeException(s, "Invalid character index: ", index);

		s.push(cast(int)src[index]);
		
		return 1;
	}
	
	int toLower(MDState s)
	{
		char[] src = s.getStringParam(0);
		
		char[] ret;
		
		try
		{
			ret = string.tolower(src);
		}
		catch(MDException e)
		{
			throw e;
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}
		
		s.push(ret);
		
		return 1;
	}
	
	int toUpper(MDState s)
	{
		char[] src = s.getStringParam(0);
		
		char[] ret;
		
		try
		{
			ret = string.toupper(src);
		}
		catch(MDException e)
		{
			throw e;
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(ret);
		
		return 1;
	}
	
	int repeat(MDState s)
	{
		char[] src = s.getStringParam(0);
		int numTimes = s.getIntParam(1);
		
		if(numTimes < 1)
			throw new MDRuntimeException(s, "Invalid number of repetitions: ", numTimes);

		char[] ret;
		
		try
		{
			ret = string.repeat(src, numTimes);
		}
		catch(MDException e)
		{
			throw e;
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
		char[] sep = s.getStringParam(1);
		
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
		catch(MDException e)
		{
			throw e;
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
		char[] src = s.getStringParam(0);

		char[][] ret;

		if(s.numParams() > 1)
		{
			char[] delim = s.getStringParam(1);

			try
			{
				ret = string.split(src, delim);
			}
			catch(MDException e)
			{
				throw e;
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
			catch(MDException e)
			{
				throw e;
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
		char[] src = s.getStringParam(0);

		char[][] ret;

		try
		{
			ret = string.splitlines(src);
		}
		catch(MDException e)
		{
			throw e;
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
		char[] src = s.getStringParam(0);

		char[] ret;

		try
		{
			ret = string.strip(src);
		}
		catch(MDException e)
		{
			throw e;
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
		char[] src = s.getStringParam(0);

		char[] ret;

		try
		{
			ret = string.stripl(src);
		}
		catch(MDException e)
		{
			throw e;
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
		char[] src = s.getStringParam(0);

		char[] ret;

		try
		{
			ret = string.stripr(src);
		}
		catch(MDException e)
		{
			throw e;
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(ret);

		return 1;
	}
	
	int slice(MDState s)
	{
		MDString str = s.getStringObjParam(0);
		
		int lo;
		int hi;
		
		if(s.numParams() == 1)
		{
			lo = 0;
			hi = str.length;
		}
		else if(s.numParams() == 2)
		{
			lo = s.getIntParam(1);
			hi = str.length;
		}
		else
		{
			lo = s.getIntParam(1);
			hi = s.getIntParam(2);
		}
		
		if(lo < 0)
			lo = str.length + lo + 1;
			
		if(hi < 0)
			hi = str.length + hi + 1;
			
		if(lo > hi || lo < 0 || lo > str.length || hi < 0 || hi > str.length)
			throw new MDRuntimeException(s, "Invalid slice indices [", lo, " .. ", hi, "] (string length = ", str.length, ")");

		s.push(str[lo .. hi]);
		
		return 1;
	}

	//TODO: int format(MDState s)
}

public void init(MDState s)
{
	StringLib lib = new StringLib();

	MDTable stringTable = MDTable.create
	(
		"toInt",      new MDClosure(s, &lib.toInt,      "string.toInt"),
		"toFloat",    new MDClosure(s, &lib.toFloat,    "string.toFloat"),
		"compare",    new MDClosure(s, &lib.compare,    "string.compare"),
		"icompare",   new MDClosure(s, &lib.icompare,   "string.icompare"),
		"charAt",     new MDClosure(s, &lib.charAt,     "string.charAt"),
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
		"slice",      new MDClosure(s, &lib.slice,      "string.slice")
	);

	stringTable["opIndex"d] = stringTable["charAt"];

	s.setGlobal("string", stringTable);
	MDGlobalState().setMetatable(MDValue.Type.String, stringTable);
}