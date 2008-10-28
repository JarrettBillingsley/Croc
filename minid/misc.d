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
import tango.io.Print;
import tango.stdc.ctype;
import tango.stdc.stdlib;
import tango.text.convert.Utf;
import tango.text.Util;

import minid.alloc;
import minid.interpreter;
import minid.types;
import minid.utils;

package void formatImpl(MDThread* t, uword numParams, uint delegate(char[]) sink)
{
	void output(char[] fmt, uword param, bool isRaw)
	{
		pushToString(t, param, isRaw);

		if(fmt[1] == 'r' || isdigit(fmt[1]))
		{
			auto begin = 2;

			for(; begin < fmt.length; begin++)
				if(fmt[begin] != 'r' && !isdigit(fmt[begin]))
					break;

			auto tmp = (cast(char*) alloca(fmt.length - begin + 1))[0 .. fmt.length - begin + 1];
			tmp[0] = '{';
			tmp[1 .. $] = fmt[begin .. $];
			t.vm.formatter.convert(sink, tmp, getString(t, -1));
		}
		else
			t.vm.formatter.convert(sink, fmt, getString(t, -1));

		pop(t);
	}

	if(numParams > 64)
		throwException(t, "Too many parameters to format (maximum of 64)");

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
		uword begin = 0;

		while(begin < formatStr.length)
		{
			auto fmtBegin = formatStr.locate('{', begin);

			t.vm.formatter.convert(sink, "{}", formatStr[begin .. fmtBegin]);
			begin = fmtBegin;

			if(fmtBegin == formatStr.length)
				break;

			auto fmtEnd = formatStr.locate('}', fmtBegin + 1);

			if(fmtEnd == formatStr.length)
			{
				t.vm.formatter.convert(sink, "{{missing or misplaced '}'}{}", formatStr[fmtBegin .. $]);
				break;
			}

			fmtEnd++;

			auto fmtSpec = formatStr[fmtBegin .. fmtEnd];
			
			bool isRaw = false;

			if(fmtSpec[1] == 'r')
				isRaw = true;

			auto index = autoIndex;

			if(fmtSpec.length > 2 && (isRaw ? isdigit(fmtSpec[2]) : isdigit(fmtSpec[1])))
			{
				uword j = 2;

				for(; j < fmtSpec.length && isdigit(fmtSpec[j]); j++)
				{}

				auto offset = Integer.atoi(fmtSpec[2 .. j]);
				index = formatStrIndex + offset + 1;
			}
			else
				autoIndex++;

			if(index > numParams)
				t.vm.formatter.convert(sink, "{}", "{invalid index}");
			else
			{
				used[index] = true;
				output(fmtSpec, index, isRaw);
			}

			begin = fmtEnd;
		}
	}
}

// Expects root to be at the top of the stack
package void toJSONImpl(T)(MDThread* t, word root, bool pretty, Print!(T) printer)
{
	root = absIndex(t, root);
	auto cycles = newTable(t);

	word indent = 0;

	void newline(word dir = 0)
	{
		printer.newline;

		if(dir > 0)
			indent++;
		else if(dir < 0)
			indent--;

		for(word i = indent; i > 0; i--)
			printer.print("\t");
	}

	void delegate(word) outputValue;

	void outputTable(word tab)
	{
		printer.print("{");

		if(pretty)
			newline(1);

		bool first = true;
		dup(t, tab);

		foreach(word k, word v; foreachLoop(t, 1))
		{
			if(!isString(t, k))
				throwException(t, "All keys in a JSON table must be strings");

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

	void outputArray(word arr)
	{
		printer.print("[");

		auto l = len(t, arr);

		for(word i = 0; i < l; i++)
		{
			if(i > 0)
			{
				if(pretty)
					printer.print(", ");
				else
					printer.print(",");
			}

			outputValue(idxi(t, arr, i));
			pop(t);
		}

		printer.print("]");
	}
	
	void outputChar(dchar c)
	{
		switch(c)
		{
			case '\b': printer.print("\\b"); return;
			case '\f': printer.print("\\f"); return;
			case '\n': printer.print("\\n"); return;
			case '\r': printer.print("\\r"); return;
			case '\t': printer.print("\\t"); return;

			case '"', '\\', '/':
				printer.print("\\");
				printer.print(c);
				return;

			default:
				if(c > 0x7f)
					printer.format("\\u{:x4}", cast(int)c);
				else
					printer.print(c);

				return;
		}
	}

	void _outputValue(word idx)
	{
		switch(type(t, idx))
		{
			case MDValue.Type.Null:
				printer.print("null");
				break;

			case MDValue.Type.Bool:
				printer.print(getBool(t, idx) ? "true" : "false");
				break;

			case MDValue.Type.Int:
				printer.format("{}", getInt(t, idx));
				break;

			case MDValue.Type.Float:
				printer.format("{}", getFloat(t, idx));
				break;

			case MDValue.Type.Char:
				printer.print('"');
				outputChar(getChar(t, idx));
				printer.print('"');
				break;

			case MDValue.Type.String:
				printer.print('"');

				foreach(dchar c; getString(t, idx))
					outputChar(c);

				printer.print('"');
				break;

			case MDValue.Type.Table:
				if(opin(t, idx, cycles))
					throwException(t, "Table is cyclically referenced");

				dup(t, idx);
				pushBool(t, true);
				idxa(t, cycles);

				scope(exit)
				{
					dup(t, idx);
					pushNull(t);
					idxa(t, cycles);
				}

				outputTable(idx);
				break;

			case MDValue.Type.Array:
				if(opin(t, idx, cycles))
					throwException(t, "Array is cyclically referenced");

				dup(t, idx);
				pushBool(t, true);
				idxa(t, cycles);

				scope(exit)
				{
					dup(t, idx);
					pushNull(t);
					idxa(t, cycles);
				}

				outputArray(idx);
				break;

			default:
				pushTypeString(t, idx);
				throwException(t, "Type '{}' is not a valid type for conversion to JSON", getString(t, -1));
		}
	}

	outputValue = &_outputValue;

	if(isArray(t, root))
		outputArray(root);
	else if(isTable(t, root))
		outputTable(root);
	else
	{
		pushTypeString(t, root);
		throwException(t, "Root element must be either a table or an array, not a '{}'", getString(t, -1));
	}

	printer.flush();
	pop(t);
}