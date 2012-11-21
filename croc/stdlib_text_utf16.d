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

module croc.stdlib_text_utf16;

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

void initUtf16Codec(CrocThread* t)
{
	ubyte[2] test = void;
	test[0] = 1;
	test[1] = 0;
	isLittleEndian = *(cast(ushort*)test.ptr) == 1;

	pushGlobal(t, "text");
	loadString(t, _code, true, "text_utf16.croc");
	pushNull(t);
	newTable(t);
		registerFields(t, _funcs);

	rawCall(t, -3, 0);
}

// =====================================================================================================================
// Private
// =====================================================================================================================

private:

// Shared global, but only ever read, so whatev
bool isLittleEndian;

const RegisterFunc[] _funcs =
[
	{ "utf16EncodeInternal", &_utf16EncodeInternal, maxParams: 5 },
	{ "utf16DecodeInternal", &_utf16DecodeInternal, maxParams: 5 }
];

uword _utf16EncodeInternal(CrocThread* t)
{
	mixin(encodeIntoHeader);

	auto byteOrder = optCharParam(t, 5, 'n');
	auto toUtf16 = &Utf8ToUtf16;

	if((byteOrder == 'b' && isLittleEndian) || (byteOrder == 'l' && !isLittleEndian))
		toUtf16 = &Utf8ToUtf16BS;

	// this initial sizing might not be enough.. but it's probably enough for most text. only trans-BMP chars will
	// need more room
	lenai(t, 2, max(len(t, 2), start + strlen * wchar.sizeof));
	auto dest = (cast(wchar*)(getMemblockData(t, 2).ptr + start))[0 .. strlen];

	char[] remaining = void;
	auto encoded = toUtf16(str, dest, remaining);

	if(remaining.length > 0)
	{
		// Didn't have enough room.. let's allocate a little more aggressively this time
		start += encoded.length * wchar.sizeof;
		strlen = fastUtf8CPLength(remaining);
		lenai(t, 2, start + strlen * wchar.sizeof * 2);
		dest = (cast(wchar*)(getMemblockData(t, 2).ptr + start))[0 .. strlen];
		encoded = toUtf16(remaining, dest, remaining);
		assert(remaining.length == 0);
		lenai(t, 2, start + encoded.length * wchar.sizeof);
	}

	dup(t, 2);
	return 1;
}

uword _utf16DecodeInternal(CrocThread* t)
{
	mixin(decodeRangeHeader);

	auto byteOrder = optCharParam(t, 5, 'n');
	auto toUtf8 = &Utf16ToUtf8;

	if((byteOrder == 'b' && isLittleEndian) || (byteOrder == 'l' && !isLittleEndian))
		toUtf8 = &Utf16ToUtf8BS;

	auto src = cast(ushort*)mb.ptr;
	auto end = cast(ushort*)(mb.ptr + (mb.length & ~1)); // round down to lower even number, if it's an odd-size slice
	auto last = src;

	auto s = StrBuffer(t);

	while(src < end)
	{

		// if(*src < 0x80)
		// 	src++;
		// else
		// {
		// 	if(src !is last)
		// 	{
		// 		s.addString(cast(char[])last[0 .. src - last]);
		// 		last = src;
		// 	}

		// 	dchar c = void;
		// 	auto ok = decodeUtf8Char(src, end, c);

		// 	if(ok == UtfError.OK)
		// 	{
		// 		s.addChar(c);
		// 		last = src;
		// 	}
		// 	else if(ok == UtfError.Truncated)
		// 	{
		// 		// incomplete character encoding.. stop it here
		// 		break;
		// 	}
		// 	else
		// 	{
		// 		// Either a correctly-encoded invalid character or a bad encoding -- skip it either way
		// 		auto len = utf8SequenceLength(*src);

		// 		if(len == 0)
		// 			src++;
		// 		else
		// 			src += len;

		// 		last = src;

		// 		if(errors == "strict")
		// 			throwStdException(t, "UnicodeException", "Invalid UTF-8");
		// 		else if(errors == "ignore")
		// 			continue;
		// 		else if(errors == "replace")
		// 			s.addChar('\uFFFD');
		// 		else
		// 			throwStdException(t, "ValueException", "Invalid error handling type '{}'", errors);
		// 	}
		// }
	}

	if(src !is last)
		s.addString(cast(char[])last[0 .. src - last]);

	s.finish();
	pushInt(t, cast(char*)src - cast(char*)mb.ptr); // how many characters we consumed
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

		return ret
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

local class Utf8SigIncrementalEncoder : IncrementalEncoder
{
	_errors
	_first = true

	this(errors: string = "strict")
		:_errors = errors

	function encodeInto(str: string, dest: memblock, start: int, final: bool = false)
	{
		if(!:_first)
			_encodeInto(str, dest, start, :_errors)
		else
		{
			:_first = false
			_encodeInto(BOM_UTF8_STR ~ str, dest, start, :_errors)
		}
	}

	function reset()
	{
		:_first = true
	}
}

local class Utf8SigIncrementalDecoder : BufferedIncrementalDecoder
{
	_first = true

	function bufferedDecode_(src: memblock, lo: int, hi: int, errors: string = "strict", final: bool = false)
	{
		local prefix = 0

		if(:_first)
		{
			local sliceLen = hi - lo

			if(sliceLen < 3)
			{
				if(BOM_UTF8.compare(0, src, lo, sliceLen) == 0)
					return "", 0, 3 - sliceLen
				else
					:_first = false
			}
			else
			{
				:_first = false

				if(BOM_UTF8.compare(0, src, lo, 3) == 0)
				{
					lo += 3
					prefix = 3
				}
			}
		}

		local ret, eaten = _decodeRange(src, lo, hi, errors)
		local needed = 0

		if(eaten < (hi - lo))
		{
			needed = utf8SequenceLength(src[lo + eaten])
			assert(needed != 0) // should be a legal start char, if the decoder is working..
		}

		return ret, prefix + eaten, needed
	}

	function reset()
	{
		super.reset()
		:_first = true
	}
}

class Utf8SigCodec : TextCodec
{
	name = "utf-8-sig"

	function encodeInto(str: string, dest: memblock, start: int, errors: string = "strict") =
		_encodeInto(BOM_UTF8_STR ~ str, dest, start, errors)

	function decodeRange(src: memblock, lo: int, hi: int, errors: string = "strict")
	{
		if((hi - lo) >= 3 && BOM_UTF8.compare(0, src, lo, 3) == 0)
			lo += 3

		local ret, eaten = _decodeRange(src, lo, hi, errors)

		if(eaten < (hi - lo))
			throw ValueException("Incomplete text at end of data")

		return ret
	}

	function incrementalEncoder(errors: string = "strict") =
		Utf8SigIncrementalEncoder(errors)

	function incrementalDecoder(errors: string = "strict") =
		Utf8SigIncrementalDecoder(errors)
}

registerCodec("utf-8-sig", Utf8SigCodec())
aliasCodec("utf-8-sig", "utf8-sig")

`;