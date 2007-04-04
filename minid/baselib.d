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
					val = v;
					break;

				case 'e', 'E', 'f', 'F', 'g', 'G', 'a', 'A':
					float f;
					input.readf(fmt, &f);
					val = f;
					break;

				case 's':
					char[] v;
					input.readf(fmt, &v);
					val = v;
					break;

				case 'c':
					char v;
					input.readf(fmt, &v);
					val = cast(dchar)v;
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
			MDString formatStr = params[paramIndex].as!(MDString);
			int formatStrIndex = paramIndex;

			int getIntParam(int index)
			{
				if(index >= params.length)
					s.throwRuntimeException("Not enough parameters to format parameter ", formatStrIndex);

				if(params[index].isInt() == false)
					s.throwRuntimeException("Expected 'int' but got '%s' for parameter ", params[index].typeString(), formatStrIndex);

				return params[index].as!(int);
			}

			float getFloatParam(int index)
			{
				if(index >= params.length)
					s.throwRuntimeException("Not enough parameters to format parameter ", formatStrIndex);

				if(params[index].isFloat() == false)
					s.throwRuntimeException("Expected 'float' but got '%s' for parameter ", params[index].typeString(), formatStrIndex);

				return params[index].as!(float);
			}

			dchar getCharParam(int index)
			{
				if(index >= params.length)
					s.throwRuntimeException("Not enough parameters to format parameter ", formatStrIndex);

				if(params[index].isChar() == false)
					s.throwRuntimeException("Expected 'char' but got '%s' for parameter ", params[index].typeString(), formatStrIndex);

				return params[index].as!(dchar);
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
	int mdwritefln(MDState s, uint numParams)
	{
		writefln("%s", baseFormat(s, s.getAllParams()));
		return 0;
	}

	int mdwritef(MDState s, uint numParams)
	{
		writef("%s", baseFormat(s, s.getAllParams()));
		return 0;
	}
	
	int writeln(MDState s, uint numParams)
	{
		for(uint i = 0; i < numParams; i++)
			writef("%s", s.valueToString(s.getParam(i)).mData);

		writefln();
		return 0;
	}
	
	int write(MDState s, uint numParams)
	{
		for(uint i = 0; i < numParams; i++)
			writef("%s", s.valueToString(s.getParam(i)).mData);

		return 0;
	}

	int readf(MDState s, uint numParams)
	{
		MDValue[] ret = s.safeCode(baseUnFormat(s, s.getParam!(dchar[])(0), din));
		
		foreach(inout v; ret)
			s.push(v);
			
		return ret.length;
	}

	int mdformat(MDState s, uint numParams)
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

	int mdtypeof(MDState s, uint numParams)
	{
		s.push(typeStrings[s.getParam(0u).type]);
		return 1;
	}

	int classof(MDState s, uint numParams)
	{
		s.push(s.getParam!(MDInstance)(0).getClass());
		return 1;
	}

	int mdtoString(MDState s, uint numParams)
	{
		s.push(s.valueToString(s.getParam(0u)));
		return 1;
	}

	int getTraceback(MDState s, uint numParams)
	{
		s.push(new MDString(s.getTracebackString()));
		return 1;
	}
	
	int isParam(char[] type)(MDState s, uint numParams)
	{
		s.push(s.isParam!(type)(0));
		return 1;
	}

	int mdassert(MDState s, uint numParams)
	{
		MDValue condition = s.getParam(0u);
		
		if(condition.isFalse())
		{
			if(numParams == 1)
				s.throwRuntimeException("Assertion Failed!");
			else
				s.throwRuntimeException("Assertion Failed: %s", s.getParam(1u).toString());
		}
		
		return 0;
	}
	
	int toInt(MDState s, uint numParams)
	{
		MDValue val = s.getParam(0u);

		switch(val.type)
		{
			case MDValue.Type.Bool:
				s.push(cast(int)val.as!(bool));
				break;

			case MDValue.Type.Int:
				s.push(val.as!(int));
				break;

			case MDValue.Type.Float:
				s.push(cast(int)val.as!(float));
				break;

			case MDValue.Type.Char:
				s.push(cast(int)val.as!(dchar));
				break;
				
			case MDValue.Type.String:
				s.push(s.safeCode(minid.utils.toInt(val.as!(dchar[]), 10)));
				break;
				
			default:
				s.throwRuntimeException("Cannot convert type '%s' to int", val.typeString());
		}

		return 1;
	}
	
	int toFloat(MDState s, uint numParams)
	{
		MDValue val = s.getParam(0u);

		switch(val.type)
		{
			case MDValue.Type.Bool:
				s.push(cast(float)val.as!(bool));
				break;

			case MDValue.Type.Int:
				s.push(cast(float)val.as!(int));
				break;

			case MDValue.Type.Float:
				s.push(val.as!(float));
				break;

			case MDValue.Type.Char:
				s.push(cast(float)val.as!(dchar));
				break;

			case MDValue.Type.String:
				s.push(s.safeCode(std.conv.toFloat(val.as!(char[]))));
				break;

			default:
				s.throwRuntimeException("Cannot convert type '%s' to float", val.typeString());
		}

		return 1;
	}
	
	int toChar(MDState s, uint numParams)
	{
		s.push(cast(dchar)s.getParam!(int)(0));
		return 1;
	}

	int namespaceIterator(MDState s, uint numParams)
	{
		MDNamespace namespace = s.getUpvalue!(MDNamespace)(0);
		MDArray keys = s.getUpvalue!(MDArray)(1);
		int index = s.getUpvalue!(int)(2);

		index++;
		s.setUpvalue(2u, index);

		if(index >= keys.length)
			return 0;

		s.push(keys[index]);
		s.push(namespace[keys[index].as!(MDString)]);

		return 2;
	}

	MDClosure makeNamespaceIterator(MDNamespace ns)
	{
		MDValue[3] upvalues;

		upvalues[0] = ns;
		upvalues[1] = ns.keys;
		upvalues[2] = -1;

		return MDGlobalState().newClosure(&namespaceIterator, "namespaceIterator", upvalues);
	}

	int namespaceApply(MDState s, uint numParams)
	{
		s.push(makeNamespaceIterator(s.getContext!(MDNamespace)));

		return 1;
	}
	
	int fieldsOf(MDState s, uint numParams)
	{
		if(s.isParam!("class")(0))
			s.push(makeNamespaceIterator(s.getParam!(MDClass)(0).fields));
		else if(s.isParam!("instance")(0))
			s.push(makeNamespaceIterator(s.getParam!(MDInstance)(0).fields));
		else
			s.throwRuntimeException("Expected class or instance, not '%s'", s.getParam(0u).typeString());
	
		return 1;
	}
	
	int methodsOf(MDState s, uint numParams)
	{
		if(s.isParam!("class")(0))
			s.push(makeNamespaceIterator(s.getParam!(MDClass)(0).methods));
		else if(s.isParam!("instance")(0))
			s.push(makeNamespaceIterator(s.getParam!(MDInstance)(0).methods));
		else
			s.throwRuntimeException("Expected class or instance, not '%s'", s.getParam(0u).typeString());

		return 1;
	}
	
	int threadState(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDState).stateString());
		return 1;
	}
	
	int isInitial(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDState).state() == MDState.State.Initial);
		return 1;
	}
	
	int isRunning(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDState).state() == MDState.State.Running);
		return 1;
	}

	int isWaiting(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDState).state() == MDState.State.Waiting);
		return 1;
	}

	int isSuspended(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDState).state() == MDState.State.Suspended);
		return 1;
	}

	int isDead(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDState).state() == MDState.State.Dead);
		return 1;
	}
	
	MDClosure threadIteratorClosure;
	
	int threadIterator(MDState s, uint numParams)
	{
		MDState thread = s.getContext!(MDState);
		int index = s.getParam!(int)(0);
		index++;

		s.push(index);
		uint numRets = s.call(s.push(thread), 0, -1) + 1;

		if(thread.state == MDState.State.Dead)
			return 0;

		return numRets;
	}

	int threadApply(MDState s, uint numParams)
	{
		MDState thread = s.getContext!(MDState);
		MDValue init = s.getParam(0u);

		if(thread.state != MDState.State.Initial)
			s.throwRuntimeException("Iterated coroutine must be in the initial state");

		uint funcReg = s.push(thread);
		s.push(thread);
		s.push(init);
		s.call(funcReg, 2, 0);
		
		s.push(threadIteratorClosure);
		s.push(thread);
		s.push(0);
		return 3;
	}
	
	int currentThread(MDState s, uint numParams)
	{
		if(s is MDGlobalState().mainThread)
			s.pushNull();
		else
			s.push(s);

		return 1;
	}

	int curryClosure(MDState s, uint numParams)
	{
		uint funcReg = s.push(s.getUpvalue!(MDClosure)(0));
		s.push(s.getContext());
		s.push(s.getUpvalue(1u));

		for(uint i = 0; i < numParams; i++)
			s.push(s.getParam(i));

		return s.call(funcReg, numParams + 2, -1);
	}
	
	int curry(MDState s, uint numParams)
	{
		MDValue[2] upvalues;
		upvalues[0] = s.getParam!(MDClosure)(0);
		upvalues[1] = s.getParam(1u);
		
		s.push(new MDClosure(upvalues[0].as!(MDClosure).environment, &curryClosure, "curryClosure", upvalues));
		return 1;
	}
}

public void init()
{
	with(MDGlobalState())
	{
		BaseLib lib = new BaseLib();

		setGlobal("assert"d,        newClosure(&lib.mdassert,              "assert"));
		setGlobal("getTraceback"d,  newClosure(&lib.getTraceback,          "getTraceback"));
		setGlobal("typeof"d,        newClosure(&lib.mdtypeof,              "typeof"));
		setGlobal("classof"d,       newClosure(&lib.classof,               "classof"));
		setGlobal("fieldsOf"d,      newClosure(&lib.fieldsOf,              "fieldsOf"));
		setGlobal("methodsOf"d,     newClosure(&lib.methodsOf,             "methodsOf"));
		setGlobal("toString"d,      newClosure(&lib.mdtoString,            "toString"));
		setGlobal("toInt"d,         newClosure(&lib.toInt,                 "toInt"));
		setGlobal("toFloat"d,       newClosure(&lib.toFloat,               "toFloat"));
		setGlobal("toChar"d,        newClosure(&lib.toChar,                "toChar"));
		setGlobal("format"d,        newClosure(&lib.mdformat,              "format"));
		setGlobal("writefln"d,      newClosure(&lib.mdwritefln,            "writefln"));
		setGlobal("writef"d,        newClosure(&lib.mdwritef,              "writef"));
		setGlobal("writeln"d,       newClosure(&lib.writeln,               "writeln"));
		setGlobal("write"d,         newClosure(&lib.write,                 "write"));
		setGlobal("readf"d,         newClosure(&lib.readf,                 "readf"));
		setGlobal("isNull"d,        newClosure(&lib.isParam!("null"),      "isNull"));
		setGlobal("isBool"d,        newClosure(&lib.isParam!("bool"),      "isBool"));
		setGlobal("isInt"d,         newClosure(&lib.isParam!("int"),       "isInt"));
		setGlobal("isFloat"d,       newClosure(&lib.isParam!("float"),     "isFloat"));
		setGlobal("isChar"d,        newClosure(&lib.isParam!("char"),      "isChar"));
		setGlobal("isString"d,      newClosure(&lib.isParam!("string"),    "isString"));
		setGlobal("isTable"d,       newClosure(&lib.isParam!("table"),     "isTable"));
		setGlobal("isArray"d,       newClosure(&lib.isParam!("array"),     "isArray"));
		setGlobal("isFunction"d,    newClosure(&lib.isParam!("function"),  "isFunction"));
		setGlobal("isClass"d,       newClosure(&lib.isParam!("class"),     "isClass"));
		setGlobal("isInstance"d,    newClosure(&lib.isParam!("instance"),  "isInstance"));
		setGlobal("isNamespace"d,   newClosure(&lib.isParam!("namespace"), "isNamespace"));
		setGlobal("isThread"d,      newClosure(&lib.isParam!("thread"),    "isThread"));
		setGlobal("currentThread"d, newClosure(&lib.currentThread,         "currentThread"));
		setGlobal("curry"d,         newClosure(&lib.curry,                 "curry"));

		MDNamespace namespace = MDNamespace.create
		(
			"namespace"d, globals,
			"opApply"d,             newClosure(&lib.namespaceApply,        "namespace.opApply")
		);

		setMetatable(MDValue.Type.Namespace, namespace);

		MDNamespace thread = MDNamespace.create
		(
			"thread"d, globals,
			"state"d,               newClosure(&lib.threadState,           "thread.state"),
			"isInitial"d,           newClosure(&lib.isInitial,             "thread.isInitial"),
			"isRunning"d,           newClosure(&lib.isRunning,             "thread.isRunning"),
			"isWaiting"d,           newClosure(&lib.isWaiting,             "thread.isWaiting"),
			"isSuspended"d,         newClosure(&lib.isSuspended,           "thread.isSuspended"),
			"isDead"d,              newClosure(&lib.isDead,                "thread.isDead"),
			"opApply"d,             newClosure(&lib.threadApply,           "thread.opApply")
		);

		lib.threadIteratorClosure = new MDClosure(thread, &lib.threadIterator, "thread.iterator");

		setMetatable(MDValue.Type.Thread, thread);
	}
}