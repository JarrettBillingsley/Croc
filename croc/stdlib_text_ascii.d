/******************************************************************************

License:
Copyright (c) 2012 Jarrett Billingsley

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

module croc.stdlib_text_ascii;

import tango.math.Math;
import tango.stdc.string;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.stdlib_text_codec;
import croc.types;
import croc.utf;

// =====================================================================================================================
// Package
// =====================================================================================================================

package:

void initAsciiCodec(CrocThread* t)
{
	registerCodec(t, _asciiCodec);
	pop(t);
}

// Rest of this has to be package as well since templated functions can't access private alias params..

RegisterCodec _asciiCodec =
{
	"AsciiCodec", "ascii", [],
	&_encodeInto!(_asciiEncodeInternal),
	&_decodeRange!(_asciiDecodeInternal),
	null,
	null
};

void _asciiEncodeInternal(CrocThread* t, word destSlot, uword start, char[] str, uword strlen, char[] errors)
{
	// Gonna need at most str.length characters, if all goes well
	lenai(t, destSlot, max(len(t, destSlot), start + str.length));

	auto destBase = getMemblockData(t, destSlot).ptr;
	auto dest = destBase + start;
	auto src = str.ptr;

	if(str.length == strlen)
	{
		// It's definitely ASCII, just shortcut copying it over.
		memcpy(dest, src, strlen * char.sizeof);
		return;
	}

	auto end = src + str.length;

	// At least one of the characters is outside ASCII range, just let the slower loop figure out what to do
	while(src < end)
	{
		if(*src < 0x80)
			*dest++ = *src++;
		else
		{
			auto c = fastDecodeUTF8Char(src);

			if(errors == "strict")
				throwStdException(t, "UnicodeException", "Character U+{:X6} cannot be encoded as ASCII", cast(uint)c);
			else if(errors == "ignore")
				continue;
  			else if(errors == "replace")
				*(dest++) = '?';
			else
				throwStdException(t, "ValueException", "Invalid error handling type '{}'", errors);
		}
	}

	// "ignore" may have resulted in fewer characters being encoded than we allocated for
	lenai(t, destSlot, dest - destBase);
}

void _asciiDecodeInternal(CrocThread* t, ref StrBuffer s, ubyte[] mb, char[] errors)
{
	auto src = mb.ptr;
	auto end = mb.ptr + mb.length;

	while(src < end)
	{
		if(*src < 0x80)
			s.addChar(cast(dchar)*src++);
		else
		{
			auto c = *src++;

			if(errors == "strict")
				throwStdException(t, "UnicodeException", "Character 0x{:X2} is invalid ASCII (above 0x7F)", c);
			else if(errors == "ignore")
				continue;
			else if(errors == "replace")
				s.addChar('\uFFFD');
			else
				throwStdException(t, "ValueException", "Invalid error handling type '{}'", errors);
		}
	}
}
