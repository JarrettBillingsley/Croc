module minid.baselib;

import minid.types;
import minid.compiler;

import std.stdio;
import std.stream;
import std.format;

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
			MDString val = s.valueToString(s.getParam(paramIndex));
			outputString(val.mData);
		}
	}

	return output;
}

class BaseLib
{
	int mdwritefln(MDState s)
	{
		writefln(baseFormat(s, s.getAllParams()));
		return 0;
	}
	
	int mdwritef(MDState s)
	{
		writef(baseFormat(s, s.getAllParams()));
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

		if(s.numParams() == 1)
			s.throwRuntimeException("Need parameters to bind to delegate");

		MDValue[] params = s.getParams(1, -1);

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
}

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
		setGlobal("toString"d,     newClosure(&lib.mdtoString,   "toString"));
		setGlobal("format"d,       newClosure(&lib.mdformat,     "format"));
		setGlobal("writefln"d,     newClosure(&lib.mdwritefln,   "writefln"));
		setGlobal("writef"d,       newClosure(&lib.mdwritef,     "writef"));
		setGlobal("writeln"d,      newClosure(&lib.writeln,      "writeln"));
		setGlobal("write"d,        newClosure(&lib.write,        "write"));
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
	}
}