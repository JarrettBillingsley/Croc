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

module croc.stdlib_text_utf8;

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

void initUtf8Codec(CrocThread* t)
{
	pushGlobal(t, "text");
	loadString(t, _code, true, "text_utf8.croc");
	pushNull(t);
	newTable(t);
		registerFields(t, _funcs);

	rawCall(t, -3, 0);
}

// =====================================================================================================================
// Private
// =====================================================================================================================

private:

const RegisterFunc[] _funcs =
[
	{ "utf8EncodeInternal", &_utf8EncodeInternal, maxParams: 4 },
	{ "utf8DecodeInternal", &_utf8DecodeInternal, maxParams: 4 }
];

uword _utf8EncodeInternal(CrocThread* t)
{
	mixin(encodeIntoHeader);
	lenai(t, 2, max(len(t, 2), start + str.length));
	auto dest = getMemblockData(t, 2).ptr + start;
	memcpy(dest, str.ptr, str.length);
	dup(t, 2);
	return 1;
}

uword _utf8DecodeInternal(CrocThread* t)
{
	mixin(decodeRangeHeader);

	auto src = cast(char*)mb.ptr;
	auto end = cast(char*)mb.ptr + mb.length;
	auto last = src;

	auto s = StrBuffer(t);

	while(src < end)
	{
		if(*src < 0x80)
			src++;
		else
		{
			if(src !is last)
			{
				s.addString(cast(char[])last[0 .. src - last]);
				last = src;
			}

			dchar c = void;
			auto ok = decodeUtf8Char(src, end, c);

			if(ok == UtfError.OK)
			{
				s.addChar(c);
				last = src;
			}
			else if(ok == UtfError.Truncated)
			{
				// incomplete character encoding.. stop it here
				break;
			}
			else
			{
				// Either a correctly-encoded invalid character or a bad encoding -- skip it either way
				auto len = utf8SequenceLength(*src);

				if(len == 0)
					src++;
				else
					src += len;

				last = src;

				if(errors == "strict")
					throwStdException(t, "UnicodeException", "Invalid UTF-8");
				else if(errors == "ignore")
					continue;
				else if(errors == "replace")
					s.addChar('\uFFFD');
				else
					throwStdException(t, "ValueException", "Invalid error handling type '{}'", errors);
			}
		}
	}

	if(src !is last)
		s.addString(cast(char[])last[0 .. src - last]);

	s.finish();
	pushInt(t, src - cast(char*)mb.ptr); // how many characters we consumed
	return 2;
}

const char[] _code =
`
local _internal = vararg
local _encodeInto, _decodeRange = _internal.utf8EncodeInternal, _internal.utf8DecodeInternal
import exceptions: ValueException, StateException

// =====================================================================================================================
// "Raw" UTF-8

local class Utf8IncrementalEncoder : IncrementalEncoder
{
	_errors

	this(errors: string = "strict")
		:_errors = errors

	function encodeInto(str: string, dest: memblock, start: int, final: bool = false) =
		_encodeInto(str, dest, start, :_errors)

	function reset() {}
}

local class Utf8IncrementalDecoder : BufferedIncrementalDecoder
{
	this(errors: string)
		super(errors)

	function bufferedDecode_(src: memblock, lo: int, hi: int, errors: string = "strict", final: bool = false)
	{
		local ret, eaten = _decodeRange(src, lo, hi, errors)
		local needed = 0

		if(eaten < (hi - lo))
		{
			needed = utf8SequenceLength(src[lo + eaten])
			assert(needed != 0) // should be a legal start char, if the decoder is working..
		}

		return ret, eaten, needed
	}
}

class Utf8Codec : TextCodec
{
	name = "utf-8"

	function decodeRange(src: memblock, lo: int, hi: int, errors: string = "strict")
	{
		local ret, eaten = _decodeRange(src, lo, hi, errors)

		if(eaten < (hi - lo))
			throw ValueException("Incomplete text at end of data")

		return ret;
	}

	function incrementalEncoder(errors: string = "strict") =
		Utf8IncrementalEncoder(errors)

	function incrementalDecoder(errors: string = "strict") =
		Utf8IncrementalDecoder(errors)
}

object.addMethod(Utf8Codec, "encodeInto", _encodeInto)

registerCodec("utf-8", Utf8Codec())
aliasCodec("utf-8", "utf8")

// =====================================================================================================================
// UTF-8 with a signature

`;