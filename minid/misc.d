/******************************************************************************
This holds miscellaneous functionality used in the internal library and also
as part of the extended API.  There are no public functions in here yet.

License:
Copyright (c) 2008 Jarrett Billingsley

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

import Integer = tango.text.convert.Integer;
import tango.stdc.ctype;
import tango.text.convert.Utf;
import tango.io.Print;

import minid.alloc;
import minid.interpreter;
import minid.types;
import minid.utils;

package void formatImpl(MDThread* t, uword numParams, uint delegate(dchar[]) sink)
{
	void outputInvalid(dchar[] fmt)
	{
		t.vm.formatter.convert(sink, fmt, "{invalid index}");
	}

	void output(dchar[] fmt, uword param, bool isRaw)
	{
		switch(type(t, param))
		{
			case MDValue.Type.Null:   t.vm.formatter.convert(sink, fmt, "null"); return;
			case MDValue.Type.Bool:   t.vm.formatter.convert(sink, fmt, getBool(t, param)); return;
			case MDValue.Type.Int:    t.vm.formatter.convert(sink, fmt, getInt(t, param)); return;
			case MDValue.Type.Float:  t.vm.formatter.convert(sink, fmt, getFloat(t, param)); return;
			case MDValue.Type.Char:   t.vm.formatter.convert(sink, fmt, getChar(t, param)); return;
			case MDValue.Type.String: t.vm.formatter.convert(sink, fmt, getString(t, param)); return;

			default:
				pushToString(t, param, isRaw);
				t.vm.formatter.convert(sink, fmt, getString(t, -1));
				pop(t);
				return;
		}
	}

	if(numParams > 64)
		throwException(t, "Too many parameters to format");

	bool[64] used;

	for(uword paramIndex = 1; paramIndex <= numParams; paramIndex++)
	{
		if(used[paramIndex])
			continue;

  		if(!isString(t, paramIndex))
  		{
			output("{}", paramIndex, false);
			continue;
		}

		auto formatStr = getString(t, paramIndex);
		auto formatStrIndex = paramIndex;
		auto autoIndex = paramIndex + 1;

		for(uword i = 0; i < formatStr.length; i++)
		{
			auto c = formatStr[i];

			void nextChar()
			{
				i++;

				if(i >= formatStr.length)
					c = dchar.init;
				else
					c = formatStr[i];
			}

			dchar[32] format = void;
			uword iFormat = 0;

			void addChar(dchar c)
			{
				if(iFormat >= format.length)
					throwException(t, "Format specifier too long in parameter {}", formatStrIndex);

				format[iFormat++] = c;
			}

			// TODO: make this a little more efficient; output all the data between format specifiers as a chunk
			if(c != '{')
			{
				dchar[1] buf = void;
				buf[0] = c;
				sink(buf);
				continue;
			}

			nextChar();

			if(c == '{')
			{
				sink("{");
				continue;
			}

			if(c == dchar.init)
			{
				sink("{missing or misplaced '}'}{");
				break;
			}

			addChar('{');

			bool isRaw = false;

			if(c == 'r')
			{
				isRaw = true;
				nextChar();
			}

			auto index = autoIndex;

			if(isdigit(c))
			{
				auto begin = i;

				while(isdigit(c))
					nextChar();

				auto offset = Integer.atoi(formatStr[begin .. begin + i]);
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
					throwException(t, "Format width must have at least one digit in parameter {}", formatStrIndex);

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

				while(i < formatStr.length && c != '}')
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

			if(index < used.length)
				used[index] = true;

			if(index > numParams)
				outputInvalid(format[0 .. iFormat]);
			else
				output(format[0 .. iFormat], index, isRaw);
		}
	}
}

/+
// Expects root to be at the top of the stack
package void toJSONImpl(T)(MDThread* t, bool pretty, Print!(T) printer)
{
	auto root = stackSize(t) - 1;
	auto cycles = newTable(t);

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

	void delegate() outputTable;
	void delegate() outputArray;
	void delegate() outputValue;

	void _outputTable()
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
}+/