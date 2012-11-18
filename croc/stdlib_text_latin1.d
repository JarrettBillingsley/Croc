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

module croc.stdlib_text_latin1;

import tango.math.Math;
import tango.stdc.string;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_library;
import croc.stdlib_text_codec;
import croc.types;
import croc.utf;

// =====================================================================================================================
// Package
// =====================================================================================================================

package:

void initLatin1Codec(CrocThread* t)
{
	pushGlobal(t, "text");
	loadString(t, _code, true, "text_latin1.croc");
	pushNull(t);
	newTable(t);
		registerFields(t, _funcs);

	rawCall(t, -3, 0);
}

// Rest of this has to be package as well since templated functions can't access private alias params..

const RegisterFunc[] _funcs =
[
	{ "latin1EncodeInternal", &_encodeInto!(_latin1EncodeInternal),  maxParams: 4 },
	{ "latin1DecodeInternal", &_decodeRange!(_latin1DecodeInternal), maxParams: 4 }
];

void _latin1EncodeInternal(CrocThread* t, word destSlot, uword start, char[] str, uword strlen, char[] errors)
{
	// Gonna need at most str.length characters, if all goes well
	lenai(t, destSlot, max(len(t, destSlot), start + str.length));

	auto destBase = getMemblockData(t, destSlot).ptr;
	auto dest = destBase + start;
	auto src = str.ptr;

	if(str.length == strlen)
	{
		// It's plain ASCII, just shortcut copying it over.
		memcpy(dest, src, strlen * char.sizeof);
		return;
	}

	auto end = src + str.length;

	while(src < end)
	{
		if(*src < 0x80)
			*dest++ = *src++;
		else
		{
			auto c = fastDecodeUTF8Char(src);

			if(c <= 0xFF)
				*dest++ = c;
			else if(errors == "strict")
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

void _latin1DecodeInternal(CrocThread* t, ref StrBuffer s, ubyte[] mb, char[] errors)
{
	auto src = mb.ptr;
	auto end = mb.ptr + mb.length;
	auto last = src;

	while(src < end)
	{
		if(*src < 0x80)
			src++;
		else
		{
			if(src !is last)
				s.addString(cast(char[])last[0 .. src - last]);

			s.addChar(cast(dchar)*src++);
			last = src;
		}
	}

	if(src !is last)
		s.addString(cast(char[])last[0 .. src - last]);
}

const char[] _code =
`
local _internal = vararg
local _encodeInto, _decodeRange = _internal.latin1EncodeInternal, _internal.latin1DecodeInternal

local class Latin1IncrementalEncoder : IncrementalEncoder
{
	_errors

	this(errors: string = "strict")
		:_errors = errors

	function encodeInto(str: string, dest: memblock, start: int, final: bool = false) =
		_encodeInto(str, dest, start, :_errors)

	function reset() {}
}

local class Latin1IncrementalDecoder : IncrementalDecoder
{
	_errors

	this(errors: string = "strict")
		:_errors = errors

	function decodeRange(src: memblock, lo: int, hi: int, final: bool = false) =
		_decodeRange(src, lo, hi, :_errors)

	function reset() {}
}

class Latin1Codec : TextCodec
{
	name = "latin1"

	function incrementalEncoder(errors: string = "strict") =
		Latin1IncrementalEncoder(errors)

	function incrementalDecoder(errors: string = "strict") =
		Latin1IncrementalDecoder(errors)
}

object.addMethod(Latin1Codec, "encodeInto", _encodeInto)
object.addMethod(Latin1Codec, "decodeRange", _decodeRange)

registerCodec("latin1", Latin1Codec())
aliasCodec("latin1", "latin-1", "iso8859-1", "cp819")
`;