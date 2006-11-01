module minid.baselib;

import minid.state;
import minid.types;
import minid.compiler;

import std.stdio;
import std.stream;
import std.format;

void specialFormat(void delegate(dchar) putc, ...)
{
	doFormat(putc, _arguments, _argptr);
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

	for(int paramIndex = 0; paramIndex < params.length; paramIndex++)
	{
		if(params[paramIndex].isString())
		{
			MDString formatStr = params[paramIndex].asString();
			int formatStrIndex = paramIndex;

			int getIntParam(int index)
			{
				if(index >= params.length)
					throw new MDRuntimeException(s, "Not enough parameters to format parameter ", formatStrIndex);

				if(params[index].isInt() == false)
					throw new MDRuntimeException(s, "Expected 'int' but got '%s' for parameter ", params[index].typeString(), formatStrIndex);

				return params[index].asInt();
			}

			float getFloatParam(int index)
			{
				if(index >= params.length)
					throw new MDRuntimeException(s, "Not enough parameters to format parameter ", formatStrIndex);

				if(params[index].isFloat() == false)
					throw new MDRuntimeException(s, "Expected 'float' but got '%s' for parameter ", params[index].typeString(), formatStrIndex);

				return params[index].asFloat();
			}

			dchar getCharParam(int index)
			{
				if(index >= params.length)
					throw new MDRuntimeException(s, "Not enough parameters to format parameter ", formatStrIndex);

				if(params[index].isChar() == false)
					throw new MDRuntimeException(s, "Expected 'char' but got '%s' for parameter ", params[index].typeString(), formatStrIndex);

				return params[index].asChar();
			}

			MDValue getParam(int index)
			{
				if(index >= params.length)
					throw new MDRuntimeException(s, "Not enough parameters to format parameter ", formatStrIndex);

				return params[index];
			}

			for(int i = 0; i < formatStr.length; i++)
			{
				dchar[20] formatting;
				int formattingLength = 0;

				void addFormatChar(dchar c)
				{
					if(formattingLength >= formatting.length)
						throw new MDRuntimeException(s, "Format specifier too long in parameter ", formatStrIndex);

					formatting[formattingLength] = c;
					formattingLength++;
				}

				dchar c = formatStr[i];

				void nextChar()
				{
					i++;

					if(i >= formatStr.length)
						throw new MDRuntimeException(s, "Unterminated format specifier in parameter ", formatStrIndex);

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
						throw new MDRuntimeException(s, "Variable length (*) formatting specifiers are unsupported in parameter ", formatStrIndex);
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
							throw new MDRuntimeException(s, "Variable length (*) formatting specifiers are unsupported in parameter ", formatStrIndex);
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
							char[] val = getParam(paramIndex).toString();
							specialFormat(&outputChar, formatting[0 .. formattingLength], val);
							break;

						case 'c':
							dchar val = getCharParam(paramIndex);
							specialFormat(&outputChar, formatting[0 .. formattingLength], val);
							break;

						default:
							throw new MDRuntimeException(s, "Unsupported format specifier '%c' in parameter ", c, formatStrIndex);
					}
				}
				else
					outputChar(c);
			}
		}
		else
			outputString(utf.toUTF32(s.getParam(paramIndex).toString()));
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
			writef("%s", s.getParam(i).toString());
			
		writefln();
		return 0;
	}
	
	int write(MDState s)
	{
		int numParams = s.numParams();
		
		for(int i = 0; i < numParams; i++)
			writef("%s", s.getParam(i).toString());

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

	s.setGlobal("writefln"d,     new MDClosure(s, &lib.mdwritefln,   "writefln"));
	s.setGlobal("writef"d,       new MDClosure(s, &lib.mdwritef,     "writef"));
	s.setGlobal("writeln"d,      new MDClosure(s, &lib.writeln,      "writeln"));
	s.setGlobal("write"d,        new MDClosure(s, &lib.write,        "write"));
	s.setGlobal("format"d,       new MDClosure(s, &lib.mdformat,     "format"));
	s.setGlobal("typeof"d,       new MDClosure(s, &lib.mdtypeof,     "typeof"));
	s.setGlobal("classof"d,      new MDClosure(s, &lib.classof,      "classof"));
	s.setGlobal("toString"d,     new MDClosure(s, &lib.mdtoString,   "toString"));
	s.setGlobal("delegate"d,     new MDClosure(s, &lib.mddelegate,   "delegate"));
	s.setGlobal("getTraceback"d, new MDClosure(s, &lib.getTraceback, "getTraceback"));
	s.setGlobal("isNull"d,       new MDClosure(s, &lib.isNull,       "isNull"));
	s.setGlobal("isBool"d,       new MDClosure(s, &lib.isBool,       "isBool"));
	s.setGlobal("isInt"d,        new MDClosure(s, &lib.isInt,        "isInt"));
	s.setGlobal("isFloat"d,      new MDClosure(s, &lib.isFloat,      "isFloat"));
	s.setGlobal("isChar"d,       new MDClosure(s, &lib.isChar,       "isChar"));
	s.setGlobal("isString"d,     new MDClosure(s, &lib.isString,     "isString"));
	s.setGlobal("isTable"d,      new MDClosure(s, &lib.isTable,      "isTable"));
	s.setGlobal("isArray"d,      new MDClosure(s, &lib.isArray,      "isArray"));
	s.setGlobal("isFunction"d,   new MDClosure(s, &lib.isFunction,   "isFunction"));
	s.setGlobal("isUserdata"d,   new MDClosure(s, &lib.isUserdata,   "isUserdata"));
	s.setGlobal("isClass"d,      new MDClosure(s, &lib.isClass,      "isClass"));
	s.setGlobal("isInstance"d,   new MDClosure(s, &lib.isInstance,   "isInstance"));
	s.setGlobal("isDelegate"d,   new MDClosure(s, &lib.isDelegate,   "isDelegate"));
	s.setGlobal("assert"d,       new MDClosure(s, &lib.mdassert,     "assert"));
}