/******************************************************************************
This holds miscellaneous functionality used in the internal library and also
as part of the extended API.  This is where

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

module minid.misc;

import minid.types;
import minid.utils;

import tango.io.Print;
import tango.stdc.ctype;
import tango.text.convert.Layout;
import tango.core.Vararg;

template Formatter(T)
{
	package Layout!(T) Formatter;
}

alias Formatter!(char) FormatterC;
alias Formatter!(wchar) FormatterW;
alias Formatter!(dchar) FormatterD;

static this()
{
	FormatterC = new Layout!(char);
	FormatterW = new Layout!(wchar);
	FormatterD = new Layout!(dchar);
}

package void formatImpl(MDState s, MDValue[] params, uint delegate(dchar[]) sink)
{
	void output(dchar[] fmt, MDValue* param, bool isRaw)
	{
		if(param is null)
			FormatterD.convert(sink, fmt, "{invalid index}");
		else
		{
			switch(param.type)
			{
				case MDValue.Type.Null:
					FormatterD.convert(sink, fmt, "null");
					break;

				case MDValue.Type.Bool:
					FormatterD.convert(sink, fmt, param.as!(bool) ? "true" : "false");
					break;

				case MDValue.Type.Int:
					FormatterD.convert(sink, fmt, param.as!(int));
					break;

				case MDValue.Type.Float:
					FormatterD.convert(sink, fmt, param.as!(mdfloat));
					break;

				case MDValue.Type.Char:
					FormatterD.convert(sink, fmt, param.as!(dchar));
					break;

				case MDValue.Type.String:
					FormatterD.convert(sink, fmt, param.as!(dchar[]));
					break;

				default:
					if(isRaw)
						FormatterD.convert(sink, fmt, param.toUtf8());
					else
						FormatterD.convert(sink, fmt, s.valueToString(*param).asUTF32());
					break;
			}
		}
	}
	
	if(params.length > 64)
		s.throwRuntimeException("Too many parameters to format");

	bool[64] used;

	for(int paramIndex = 0; paramIndex < params.length; paramIndex++)
	{
		if(used[paramIndex])
			continue;

  		if(!params[paramIndex].isString())
			output("{}", &params[paramIndex], false);
		else
		{
			MDString formatStr = params[paramIndex].as!(MDString);
			int formatStrIndex = paramIndex;
			int autoIndex = paramIndex + 1;

			MDValue* getParam(int index)
			{
				if(index >= params.length)
					return null;

				return &params[index];
			}

			for(int i = 0; i < formatStr.length; i++)
			{
				dchar c = formatStr[i];

				void nextChar()
				{
					i++;

					if(i >= formatStr.length)
						c = dchar.init;
					else
						c = formatStr[i];
				}

				dchar[20] format = void;
				int iFormat = 0;

				void addChar(dchar c)
				{
					if(iFormat >= format.length)
						s.throwRuntimeException("Format specifier too long in parameter {}", formatStrIndex);

					format[iFormat++] = c;
				}

				if(c != '{')
					sink([c]);
				else
				{
					nextChar();

					if(c == '{')
					{
						sink("{");
						continue;
					}
					
					addChar('{');
					
					bool isRaw = false;

					if(c == 'r')
					{
						isRaw = true;
						nextChar();
					}
					
					int index = autoIndex;

					if(c == '-' || isdigit(c))
					{
						int begin = i;

						if(!isdigit(c))
							s.throwRuntimeException("Format index must have at least one digit in parameter {}", formatStrIndex);

						while(isdigit(c))
							nextChar();

						int offset = Integer.atoi(formatStr.sliceData(begin, i));
						
						index = formatStrIndex + offset + 1;
					}
					else
						autoIndex++;
					
					if(c == ',')
					{
						addChar(',');
						nextChar();
						
						if(c == '-')
						{
							addChar('-');
							nextChar();
						}
						
						if(!isdigit(c))
							s.throwRuntimeException("Format width must have at least one digit in parameter {}", formatStrIndex);

						while(isdigit(c))
						{
							addChar(c);
							nextChar();
						}
					}
					
					if(c == ':')
					{
						addChar(':');
						nextChar();

						while(c != '}')
						{
							addChar(c);
							nextChar();
						}
					}
					
					if(c != '}')
					{
						sink("{missing or misplaced '}'}");
						sink(format[0 .. iFormat]);
						i--;
						continue;
					}

					addChar('}');
					used[index] = true;

					output(format[0 .. iFormat], getParam(index), isRaw);
				}
			}
		}
	}
}

package void toJSONImpl(T)(MDState s, MDValue root, bool pretty, Print!(T) printer)
{
	void throwByState(char[] fmt, ...)
	{
		s.throwRuntimeException(fmt, _arguments, _argptr);
	}
	
	void throwNormal(char[] fmt, ...)
	{
		throw new MDException(fmt, _arguments, _argptr);
	}
	
	void delegate(char[], ...) exception = s is null ? &throwNormal : &throwByState;

	bool[MDValue] cycles;

	int indent = 0;

	void newline(int dir = 0)
	{
		printer.newline;

		if(dir > 0)
			indent++;
		else if(dir < 0)
			indent--;

		for(int i = indent; i > 0; i--)
			printer.print("\t");
	}

	void delegate(MDTable) outputTable;
	void delegate(MDArray) outputArray;
	void delegate(ref MDValue) outputValue;

	void _outputTable(MDTable t)
	{
		printer.print("{");

		if(pretty)
			newline(1);

		bool first = true;

		foreach(k, ref v; t)
		{
			if(!k.isString())
				exception("All keys in a JSON table must be strings");

			if(first)
				first = false;
			else
			{
				printer.print(",");

				if(pretty)
					newline();
			}

			outputValue(k);

			if(pretty)
				printer.print(": ");
			else
				printer.print(":");

			outputValue(v);
		}

		if(pretty)
			newline(-1);

		printer.print("}");
	}

	void _outputArray(MDArray a)
	{
		printer.print("[");

		bool first = true;

		foreach(ref v; a)
		{
			if(first)
				first = false;
			else
			{
				if(pretty)
					printer.print(", ");
				else
					printer.print(",");
			}

			outputValue(v);
		}

		printer.print("]");
	}

	void _outputValue(ref MDValue v)
	{
		switch(v.type)
		{
			case MDValue.Type.Null:
				printer.print("null");
				break;

			case MDValue.Type.Bool:
				printer.print(v.isFalse() ? "false" : "true");
				break;

			case MDValue.Type.Int:
				printer.format("{}", v.as!(int));
				break;

			case MDValue.Type.Float:
				printer.format("{}", v.as!(double));
				break;

			case MDValue.Type.Char:
				printer.print("\"");
				printer.print(v.as!(dchar));
				printer.print("\"");
				break;

			case MDValue.Type.String:
				printer.print('"');

				foreach(c; v.as!(MDString).mData)
				{
					switch(c)
					{
						case '\b': printer.print("\\b"); break;
						case '\f': printer.print("\\f"); break;
						case '\n': printer.print("\\n"); break;
						case '\r': printer.print("\\r"); break;
						case '\t': printer.print("\\t"); break;

						case '"', '\\', '/':
							printer.print("\\");
							printer.print(c);
							break;

						default:
							if(c > 0x7f)
								printer.format("\\u{:x4}", cast(int)c);
							else
								printer.print(c);

							break;
					}
				}

				printer.print('"');
				break;

			case MDValue.Type.Table:
				if(v in cycles)
					exception("Table is cyclically referenced");

				cycles[v] = true;

				scope(exit)
					cycles.remove(v);

				outputTable(v.as!(MDTable));
				break;

			case MDValue.Type.Array:
				if(v in cycles)
					exception("Array is cyclically referenced");

				cycles[v] = true;

				scope(exit)
					cycles.remove(v);

				outputArray(v.as!(MDArray));
				break;

			default:
				exception("Type '{}' is not a valid type for conversion to JSON", v.typeString());
		}
	}

	outputTable = &_outputTable;
	outputArray = &_outputArray;
	outputValue = &_outputValue;

	if(root.isArray())
		outputArray(root.as!(MDArray));
	else if(root.isTable())
		outputTable(root.as!(MDTable));
	else
		exception("Root element must be either a table or an array, not a '{}'", root.typeString());

	printer.flush();
}

/*
package MDValue[] unformatImpl(MDState s, dchar[] formatStr, Stream input)
{
	MDValue[] output;

	void outputValue(ref MDValue val)
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
			
			char[] fmt = utf.toUtf8(formatStr[begin .. i + 1]);
			MDValue val;

			switch(c)
			{
				case 'd', 'i', 'b', 'o', 'x', 'X':
					int v;
					input.readf(fmt, &v);
					val = v;
					break;

				case 'e', 'E', 'f', 'F', 'g', 'G', 'a', 'A':
					mdfloat f;
					input.readf(fmt, &f);
					val = f;
					break;

				case 'r', 's':
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
*/