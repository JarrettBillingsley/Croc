/******************************************************************************
This module holds the underlying implementation of the MiniD format() function.
There is no public interface.

License:
Copyright (c) 2011 Jarrett Billingsley

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

module minid.ex_format;

import Integer = tango.text.convert.Integer;
import tango.stdc.ctype;
import tango.stdc.stdlib;
import tango.text.Util;

import minid.interpreter;
import minid.stackmanip;
import minid.types;

package void formatImpl(MDThread* t, uword numParams, uint delegate(char[]) sink)
{
	return formatImpl(t, 1, numParams, sink);
}

package void formatImpl(MDThread* t, uword startIndex, uword numParams, uint delegate(char[]) sink)
{
	auto formatter = t.vm.formatter;

	void output(char[] fmt, uword param, bool isRaw)
	{
		auto tmp = (cast(char*)alloca(fmt.length + 1))[0 .. fmt.length + 1];
		tmp[0] = '{';
		tmp[1 .. $] = fmt[];

		switch(type(t, param))
		{
			case MDValue.Type.Int:   formatter.convert(sink, tmp, getInt(t, param));   break;
			case MDValue.Type.Float: formatter.convert(sink, tmp, getFloat(t, param)); break;
			case MDValue.Type.Char:  formatter.convert(sink, tmp, getChar(t, param));  break;

			default:
				pushToString(t, param, isRaw);
				formatter.convert(sink, tmp, getString(t, -1));
				pop(t);
				break;
		}
	}

	auto formatStr = getString(t, startIndex);
	uword autoIndex = startIndex + 1;
	uword begin = 0;

	while(begin < formatStr.length)
	{
		// output anything outside the {}
		auto fmtBegin = formatStr.locate('{', begin);

		if(fmtBegin > begin)
		{
			formatter.convert(sink, "{}", formatStr[begin .. fmtBegin]);
			begin = fmtBegin;
		}

		// did we run out of string?
		if(fmtBegin == formatStr.length)
			break;
			
		// Check if it's an escaped {
		if(formatStr[fmtBegin + 1] == '{')
		{
			begin = fmtBegin + 2;
			formatter.convert(sink, "{}", "{");
			continue;
		}

		// find the end of the {}
		auto fmtEnd = formatStr.locate('}', fmtBegin + 1);

		// onoz, unmatched {}
		if(fmtEnd == formatStr.length)
		{
			formatter.convert(sink, "{{missing or misplaced '}'}{}", formatStr[fmtBegin .. $]);
			break;
		}

		// chop off opening { on format spec but leave closing }
		// this means fmtSpec.length will always be >= 1
		auto fmtSpec = formatStr[fmtBegin + 1 .. fmtEnd + 1];
		bool isRaw = false;

		// check for {r and remove it if there
		if(fmtSpec[0] == 'r')
		{
			isRaw = true;
			fmtSpec = fmtSpec[1 .. $];
		}

		// check for parameter index and remove it if there
		auto index = autoIndex;

		if(isdigit(fmtSpec[0]))
		{
			uword j = 0;

			for(; j < fmtSpec.length && isdigit(fmtSpec[j]); j++)
			{}

			index = Integer.atoi(fmtSpec[0 .. j]) + startIndex + 1;
			fmtSpec = fmtSpec[j .. $];
		}
		else
			autoIndex++;

		// output it (or see if it's an invalid index)
		if(index > numParams)
			formatter.convert(sink, "{{invalid index}");
		else
			output(fmtSpec, index, isRaw);

		begin = fmtEnd + 1;
	}
}