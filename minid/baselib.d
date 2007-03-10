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

module minid.baselib;

import minid.types;
import minid.compiler;
import minid.utils;

import std.stdio;
import std.stream;
import std.format;
import std.conv;
import std.cstream;
import std.stream;

MDValue[] baseUnFormat(MDState s, dchar[] formatStr, Stream input)
{
	MDValue[] output;

	void outputValue(inout MDValue val)
	{
		output ~= val;
	}

	int begin = 0;

	for(int i = 0; i < formatStr.length; i++)
	{
		dchar c = formatStr[i];

		void nextChar()
		{
			i++;

			if(i >= formatStr.length)
				s.throwRuntimeException("Unterminated format specifier");

			c = formatStr[i];
		}

		if(c == '%')
		{
			nextChar();

			if(c == '%')
				continue;

			while(true)
			{
				switch(c)
				{
					case '-', '+', '#', '0', ' ':
						nextChar();
						continue;

					default:
						break;
				}

				break;
			}

			if(c == '*')
				s.throwRuntimeException("Variable length (*) formatting specifiers are unsupported");
			else if(std.ctype.isdigit(c))
			{
				do
					nextChar();
				while(std.ctype.isdigit(c))
			}

			if(c == '.')
			{
				nextChar();

				if(c == '*')
					s.throwRuntimeException("Variable length (*) formatting specifiers are unsupported");
				else if(std.ctype.isdigit(c))
				{
					do
						nextChar();
					while(std.ctype.isdigit(c))
				}
			}
			
			char[] fmt = utf.toUTF8(formatStr[begin .. i + 1]);
			MDValue val;

			switch(c)
			{
				case 'd', 'i', 'b', 'o', 'x', 'X':
					int v;
					input.readf(fmt, &v);
					val.value = v;
					break;

				case 'e', 'E', 'f', 'F', 'g', 'G', 'a', 'A':
					float f;
					input.readf(fmt, &f);
					val.value = f;
					break;

				case 's':
					char[] v;
					input.readf(fmt, &v);
					val.value = v;
					break;

				case 'c':
					char v;
					input.readf(fmt, &v);
					val.value = cast(dchar)v;
					break;

				default:
					// unsupported: %p
					s.throwRuntimeException("Unsupported format specifier '%c'", c);
			}
			
			outputValue(val);
			begin = i + 1;
		}
	}

	return output;
}

dchar[] baseFormat(MDState s, MDValue[] params)
{
	dchar[] output;

	void outputChar(dchar c)
	{
		output ~= c;
	}

	void outputString(dchar[] s)
	{
		output ~= s;
	}

	void specialFormat(void delegate(dchar) putc, ...)
	{
		doFormat(putc, _arguments, _argptr);
	}

	for(int paramIndex = 0; paramIndex < params.length; paramIndex++)
	{
		if(params[paramIndex].isString())
		{
			MDString formatStr = params[paramIndex].asString();
			int formatStrIndex = paramIndex;

			int getIntParam(int index)
			{
				if(index >= params.length)
					s.throwRuntimeException("Not enough parameters to format parameter ", formatStrIndex);

				if(params[index].isInt() == false)
					s.throwRuntimeException("Expected 'int' but got '%s' for parameter ", params[index].typeString(), formatStrIndex);

				return params[index].asInt();
			}

			float getFloatParam(int index)
			{
				if(index >= params.length)
					s.throwRuntimeException("Not enough parameters to format parameter ", formatStrIndex);

				if(params[index].isFloat() == false)
					s.throwRuntimeException("Expected 'float' but got '%s' for parameter ", params[index].typeString(), formatStrIndex);

				return params[index].asFloat();
			}

			dchar getCharParam(int index)
			{
				if(index >= params.length)
					s.throwRuntimeException("Not enough parameters to format parameter ", formatStrIndex);

				if(params[index].isChar() == false)
					s.throwRuntimeException("Expected 'char' but got '%s' for parameter ", params[index].typeString(), formatStrIndex);

				return params[index].asChar();
			}

			MDValue getParam(int index)
			{
				if(index >= params.length)
					s.throwRuntimeException("Not enough parameters to format parameter ", formatStrIndex);

				return params[index];
			}

			for(int i = 0; i < formatStr.length; i++)
			{
				dchar[20] formatting;
				int formattingLength = 0;

				void addFormatChar(dchar c)
				{
					if(formattingLength >= formatting.length)
						s.throwRuntimeException("Format specifier too long in parameter ", formatStrIndex);

					formatting[formattingLength] = c;
					formattingLength++;
				}

				dchar c = formatStr[i];

				void nextChar()
				{
					i++;

					if(i >= formatStr.length)
						s.throwRuntimeException("Unterminated format specifier in parameter ", formatStrIndex);

					c = formatStr[i];
				}

				if(c == '%')
				{
					nextChar();

					if(c == '%')
					{
						outputChar('%');
						continue;
					}
					else
						addFormatChar('%');

					while(true)
					{
						switch(c)
						{
							case '-', '+', '#', '0', ' ':
								addFormatChar(c);
								nextChar();
								continue;

							default:
								break;
						}

						break;
					}

					if(c == '*')
						s.throwRuntimeException("Variable length (*) formatting specifiers are unsupported in parameter ", formatStrIndex);
					else if(std.ctype.isdigit(c))
					{
						addFormatChar(c);
						nextChar();

						while(true)
						{
							if(std.ctype.isdigit(c))
							{
								addFormatChar(c);
								nextChar();
								continue;
							}

							break;
						}
					}

					if(c == '.')
					{
						addFormatChar('.');
						nextChar();

						if(c == '*')
							s.throwRuntimeException("Variable length (*) formatting specifiers are unsupported in parameter ", formatStrIndex);
						else if(std.ctype.isdigit(c))
						{
							addFormatChar(c);
							nextChar();

							while(true)
							{
								if(std.ctype.isdigit(c))
								{
									addFormatChar(c);
									nextChar();
									continue;
								}

								break;
							}
						}
					}

					paramIndex++;

					addFormatChar(c);

					switch(c)
					{
						case 'd', 'i', 'b', 'o', 'x', 'X':
							int val = getIntParam(paramIndex);
							specialFormat(&outputChar, formatting[0 .. formattingLength], val);
							break;

						case 'e', 'E', 'f', 'F', 'g', 'G', 'a', 'A':
							float val;

							if(s.isParam!("int")(paramIndex))
								val = getIntParam(paramIndex);
							else
								val = getFloatParam(paramIndex);

							specialFormat(&outputChar, formatting[0 .. formattingLength], val);
							break;

						case 's':
							MDString val = s.valueToString(getParam(paramIndex));
							specialFormat(&outputChar, formatting[0 .. formattingLength], val.mData);
							break;

						case 'c':
							dchar val = getCharParam(paramIndex);
							specialFormat(&outputChar, formatting[0 .. formattingLength], val);
							break;

						default:
							// unsupported: %p
							s.throwRuntimeException("Unsupported format specifier '%c' in parameter ", c, formatStrIndex);
					}
				}
				else
					outputChar(c);
			}
		}
		else
		{
			MDString val = s.valueToString(params[paramIndex]);
			outputString(val.mData);
		}
	}

	return output;
}

class BaseLib
{
	int mdwritefln(MDState s)
	{
		writefln("%s", baseFormat(s, s.getAllParams()));
		return 0;
	}

	int mdwritef(MDState s)
	{
		writef("%s", baseFormat(s, s.getAllParams()));
		return 0;
	}
	
	int writeln(MDState s)
	{
		int numParams = s.numParams();

		for(int i = 0; i < numParams; i++)
		{
			MDString str = s.valueToString(s.getParam(i));
			writef("%s", str.mData);
		}

		writefln();
		return 0;
	}
	
	int write(MDState s)
	{
		int numParams = s.numParams();
		
		for(int i = 0; i < numParams; i++)
		{
			MDString str = s.valueToString(s.getParam(i));
			writef("%s", str.mData);
		}

		return 0;
	}
	
	int readf(MDState s)
	{
		MDValue[] ret = s.safeCode(baseUnFormat(s, s.getStringParam(0).asUTF32(), din));
		
		foreach(inout v; ret)
			s.push(v);
			
		return ret.length;
	}

	int mdformat(MDState s)
	{
		s.push(baseFormat(s, s.getAllParams()));
		return 1;
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
		s.push(s.valueToString(s.getParam(0)));
		return 1;
	}

	int mddelegate(MDState s)
	{
		MDClosure func = s.getClosureParam(0);

		MDValue[] params;
		
		if(s.numParams() == 1)
			params ~= MDValue(func.environment);
		else
			params = s.getParams(1, -1);

		s.push(new MDDelegate(func, params));

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
	
	int isNamespace(MDState s)
	{
		s.push(s.getParam(0).isNamespace());
		return 1;
	}
	
	int mdassert(MDState s)
	{
		MDValue condition = s.getParam(0);
		
		if(condition.isFalse())
		{
			if(s.numParams() == 1)
				s.throwRuntimeException("Assertion Failed!");
			else
				s.throwRuntimeException("Assertion Failed: %s", s.getParam(1).toString());
		}
		
		return 0;
	}
	
	int toInt(MDState s)
	{
		MDValue val = s.getParam(0);

		switch(val.type)
		{
			case MDValue.Type.Bool:
				s.push(cast(int)val.asBool());
				break;

			case MDValue.Type.Int:
				s.push(val.asInt());
				break;

			case MDValue.Type.Float:
				s.push(cast(int)val.asFloat());
				break;

			case MDValue.Type.Char:
				s.push(cast(int)val.asChar());
				break;
				
			case MDValue.Type.String:
				s.push(s.safeCode(minid.utils.toInt(val.asString.asUTF32, 10)));
				break;
				
			default:
				s.throwRuntimeException("Cannot convert type '%s' to int", val.typeString());
		}

		return 1;
	}
	
	int toFloat(MDState s)
	{
		MDValue val = s.getParam(0);

		switch(val.type)
		{
			case MDValue.Type.Bool:
				s.push(cast(float)val.asBool());
				break;

			case MDValue.Type.Int:
				s.push(cast(float)val.asInt());
				break;

			case MDValue.Type.Float:
				s.push(val.asFloat());
				break;

			case MDValue.Type.Char:
				s.push(cast(float)val.asChar());
				break;
				
			case MDValue.Type.String:
				s.push(s.safeCode(std.conv.toFloat(val.asString.asUTF8)));
				break;

			default:
				s.throwRuntimeException("Cannot convert type '%s' to float", val.typeString());
		}

		return 1;
	}
	
	int toChar(MDState s)
	{
		s.push(cast(dchar)s.getIntParam(0));
		return 1;
	}

	int namespaceIterator(MDState s)
	{
		MDNamespace namespace = s.getUpvalue(0).asNamespace();
		MDArray keys = s.getUpvalue(1).asArray();
		int index = s.getUpvalue(2).asInt();

		index++;
		s.setUpvalue(2u, index);

		if(index >= keys.length)
			return 0;

		s.push(keys[index]);
		s.push(namespace[keys[index].asString()]);

		return 2;
	}

	MDClosure makeNamespaceIterator(MDNamespace ns)
	{
		MDValue[3] upvalues;

		upvalues[0].value = ns;
		upvalues[1].value = ns.keys;
		upvalues[2].value = -1;

		return MDGlobalState().newClosure(&namespaceIterator, "namespaceIterator", upvalues);
	}

	int namespaceApply(MDState s)
	{
		s.push(makeNamespaceIterator(s.getContext().asNamespace()));

		return 1;
	}
	
	int fieldsOf(MDState s)
	{
		if(s.isParam!("class")(0))
			s.push(makeNamespaceIterator(s.getClassParam(0).fields));
		else if(s.isParam!("instance")(0))
			s.push(makeNamespaceIterator(s.getInstanceParam(0).fields));
		else
			s.throwRuntimeException("Expected class or instance, not '%s'", s.getParam(0).typeString());
	
		return 1;
	}
	
	int methodsOf(MDState s)
	{
		if(s.isParam!("class")(0))
			s.push(makeNamespaceIterator(s.getClassParam(0).methods));
		else if(s.isParam!("instance")(0))
			s.push(makeNamespaceIterator(s.getInstanceParam(0).methods));
		else
			s.throwRuntimeException("Expected class or instance, not '%s'", s.getParam(0).typeString());

		return 1;
	}
	
	int timeGetTime(MDState s)
	{
		s.push(.timeGetTime());
		return 1;
	}
}

pragma(lib, "winmm.lib");
extern(Windows) uint timeGetTime();

public void init()
{
	with(MDGlobalState())
	{
		BaseLib lib = new BaseLib();

		setGlobal("assert"d,       newClosure(&lib.mdassert,     "assert"));
		setGlobal("getTraceback"d, newClosure(&lib.getTraceback, "getTraceback"));
		setGlobal("delegate"d,     newClosure(&lib.mddelegate,   "delegate"));
		setGlobal("typeof"d,       newClosure(&lib.mdtypeof,     "typeof"));
		setGlobal("classof"d,      newClosure(&lib.classof,      "classof"));
		setGlobal("fieldsOf"d,     newClosure(&lib.fieldsOf,     "fieldsOf"));
		setGlobal("methodsOf"d,    newClosure(&lib.methodsOf,    "methodsOf"));
		setGlobal("toString"d,     newClosure(&lib.mdtoString,   "toString"));
		setGlobal("toInt"d,        newClosure(&lib.toInt,        "toInt"));
		setGlobal("toFloat"d,      newClosure(&lib.toFloat,      "toFloat"));
		setGlobal("toChar"d,       newClosure(&lib.toChar,       "toChar"));
		setGlobal("format"d,       newClosure(&lib.mdformat,     "format"));
		setGlobal("writefln"d,     newClosure(&lib.mdwritefln,   "writefln"));
		setGlobal("writef"d,       newClosure(&lib.mdwritef,     "writef"));
		setGlobal("writeln"d,      newClosure(&lib.writeln,      "writeln"));
		setGlobal("write"d,        newClosure(&lib.write,        "write"));
		setGlobal("readf"d,        newClosure(&lib.readf,        "readf"));
		setGlobal("isNull"d,       newClosure(&lib.isNull,       "isNull"));
		setGlobal("isBool"d,       newClosure(&lib.isBool,       "isBool"));
		setGlobal("isInt"d,        newClosure(&lib.isInt,        "isInt"));
		setGlobal("isFloat"d,      newClosure(&lib.isFloat,      "isFloat"));
		setGlobal("isChar"d,       newClosure(&lib.isChar,       "isChar"));
		setGlobal("isString"d,     newClosure(&lib.isString,     "isString"));
		setGlobal("isTable"d,      newClosure(&lib.isTable,      "isTable"));
		setGlobal("isArray"d,      newClosure(&lib.isArray,      "isArray"));
		setGlobal("isFunction"d,   newClosure(&lib.isFunction,   "isFunction"));
		setGlobal("isUserdata"d,   newClosure(&lib.isUserdata,   "isUserdata"));
		setGlobal("isClass"d,      newClosure(&lib.isClass,      "isClass"));
		setGlobal("isInstance"d,   newClosure(&lib.isInstance,   "isInstance"));
		setGlobal("isDelegate"d,   newClosure(&lib.isDelegate,   "isDelegate"));
		setGlobal("isNamespace"d,  newClosure(&lib.isNamespace,  "isNamespace"));
		
		setGlobal("timeGetTime"d,  newClosure(&lib.timeGetTime,  "timeGetTime"));

		MDNamespace namespace = MDNamespace.create(
			"namespace"d, globals,
			"opApply"d, newClosure(&lib.namespaceApply, "namespace.opApply")
		);
		
		setMetatable(MDValue.Type.Namespace, namespace);
	}
}