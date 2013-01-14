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

module croc.stdlib_text_utf32;

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

void initUtf32Codec(CrocThread* t)
{
	ubyte[2] test = void;
	test[0] = 1;
	test[1] = 0;
	isLittleEndian = *(cast(ushort*)test.ptr) == 1;

	pushGlobal(t, "text");
	loadString(t, _code, true, "text_utf32.croc");
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
	{ "utf32EncodeInternal", &_utf32EncodeInternal, maxParams: 5 },
	{ "utf32DecodeInternal", &_utf32DecodeInternal, maxParams: 5 }
];

uword _utf32EncodeInternal(CrocThread* t)
{
	mixin(encodeIntoHeader);

	auto byteOrder = optCharParam(t, 5, 'n');
	auto toUtf32 = &Utf8ToUtf32!(false);

	if(byteOrder == 's' || (byteOrder == 'b' && isLittleEndian) || (byteOrder == 'l' && !isLittleEndian))
		toUtf32 = &Utf8ToUtf32BS;

	lenai(t, 2, start + strlen * dchar.sizeof);
	auto dest = (cast(dchar*)(getMemblockData(t, 2).ptr + start))[0 .. strlen];

	char[] remaining = void;
	toUtf32(str, dest, remaining);
	assert(remaining.length == 0);
	dup(t, 2);
	return 1;
}

uword _utf32DecodeInternal(CrocThread* t)
{
	mixin(decodeRangeHeader);

	auto byteOrder = optCharParam(t, 5, 'n');
	auto toUtf8 = &Utf32ToUtf8;
	auto skipBadChar = &skipBadUtf32Char!(false);

	if(byteOrder == 's' || (byteOrder == 'b' && isLittleEndian) || (byteOrder == 'l' && !isLittleEndian))
	{
		toUtf8 = &Utf32ToUtf8BS;
		skipBadChar = &skipBadUtf32CharBS;
	}

	mb = mb[0 .. $ & ~3]; // round down to lower multiple-of-4 length

	auto src = cast(dchar*)mb.ptr;
	auto end = src + (mb.length / 4);

	auto s = StrBuffer(t);
	char[256] buf = void;
	dchar[] remaining = void;
	char[] output = void;

	while(src < end)
	{
		auto ok = toUtf8(src[0 .. end - src], buf, remaining, output);

		if(ok == UtfError.OK)
		{
			s.addString(output);

			if(remaining.length)
				src = remaining.ptr;
			else
				src = end;
		}
		else if(ok == UtfError.Truncated)
		{
			// incomplete character encoding.. stop it here
			break;
		}
		else
		{
			// Either a correctly-encoded invalid character or a bad encoding -- skip it either way
			skipBadChar(src, end);

			if(errors == "strict")
				throwStdException(t, "UnicodeException", "Invalid UTF-32");
			else if(errors == "ignore")
				continue;
			else if(errors == "replace")
				s.addChar('\uFFFD');
			else
				throwStdException(t, "ValueException", "Invalid error handling type '{}'", errors);
		}
	}

	s.finish();
	pushInt(t, cast(char*)src - cast(char*)mb.ptr); // how many bytes were consumed
	return 2;
}

const char[] _code =
`
local _internal = vararg
local _encodeInto, _decodeRange = _internal.utf32EncodeInternal, _internal.utf32DecodeInternal
import exceptions: ValueException, StateException

// =====================================================================================================================
// UTF-32 (BOM + native on encoding, BOM + either on decoding)

local class Utf32IncrementalEncoder : IncrementalEncoder
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

			if(start + #BOM_UTF32 > #dest)
				#dest = start + #BOM_UTF32

			dest.copy(start, BOM_UTF32, 0, #BOM_UTF32)
			_encodeInto(str, dest, start + #BOM_UTF32, :_errors)
		}
	}

	function reset()
	{
		:_first = true
	}
}

local class Utf32IncrementalDecoder : BufferedIncrementalDecoder
{
	_first = true
	_order = 'n'

	function bufferedDecode_(src: memblock, lo: int, hi: int, errors: string = "strict", final: bool = false)
	{
		local prefix = 0

		if(:_first)
		{
			if(hi - lo < #BOM_UTF32)
				return "", 0

			:_first = false

			if(BOM_UTF32.compare(0, src, lo, #BOM_UTF32) == 0)
			{
				lo += #BOM_UTF32
				prefix = #BOM_UTF32
			}
			else if(BOM_UTF32_BS.compare(0, src, lo, #BOM_UTF32_BS) == 0)
			{
				lo += #BOM_UTF32_BS
				prefix = #BOM_UTF32_BS
				:_order = 's'
			}
			else
				throw UnicodeException("UTF-32 encoded text has no BOM")
		}

		local ret, eaten = _decodeRange(src, lo, hi, errors, :_order)
		return ret, prefix + eaten
	}

	function reset()
	{
		super.reset()
		:_first = true
		:_order = 'n'
	}
}

class Utf32Codec : TextCodec
{
	name = "utf-32"

	function encodeInto(str: string, dest: memblock, start: int, errors: string = "strict")
	{
		if(start + #BOM_UTF32 > #dest)
			#dest = start + #BOM_UTF32

		dest.copy(start, BOM_UTF32, 0, #BOM_UTF32)
		_encodeInto(str, dest, start + #BOM_UTF32, errors)
	}

	function decodeRange(src: memblock, lo: int, hi: int, errors: string = "strict")
	{
		if(hi - lo < #BOM_UTF32)
			throw UnicodeException("UTF-32 encoded text is too short to have a BOM")

		local ret, eaten

		if(BOM_UTF32.compare(0, src, lo, #BOM_UTF32) == 0)
			ret, eaten = _decodeRange(src, lo + #BOM_UTF32, hi, errors)
		else if(BOM_UTF32_BS.compare(0, src, lo, #BOM_UTF32_BS) == 0)
			ret, eaten = _decodeRange(src, lo + #BOM_UTF32_BS, hi, errors, 's')
		else
			throw UnicodeException("UTF-32 encoded text has no BOM")

		eaten += #BOM_UTF32

		if(eaten < (hi - lo))
			throw ValueException("Incomplete text at end of data")

		return ret
	}

	function incrementalEncoder(errors: string = "strict") =
		Utf32IncrementalEncoder(errors)

	function incrementalDecoder(errors: string = "strict") =
		Utf32IncrementalDecoder(errors)
}

registerCodec("utf-32", Utf32Codec())
aliasCodec("utf-32", "utf32")

// =====================================================================================================================
// UTF-32 Little Endian (no BOM on either encoding or decoding)

local class Utf32LEIncrementalEncoder : IncrementalEncoder
{
	_errors

	this(errors: string = "strict")
		:_errors = errors

	function encodeInto(str: string, dest: memblock, start: int, final: bool = false) =
		_encodeInto(str, dest, start, :_errors, 'l')

	function reset() {}
}

local class Utf32LEIncrementalDecoder : BufferedIncrementalDecoder
{
	function bufferedDecode_(src: memblock, lo: int, hi: int, errors: string = "strict", final: bool = false)
		return _decodeRange(src, lo, hi, errors, 'l')
}

class Utf32LECodec : TextCodec
{
	name = "utf-32-le"

	function encodeInto(str: string, dest: memblock, start: int, errors: string = "strict") =
		_encodeInto(str, dest, start, errors, 'l')

	function decodeRange(src: memblock, lo: int, hi: int, errors: string = "strict")
	{
		local ret, eaten = _decodeRange(src, lo, hi, errors, 'l')

		if(eaten < (hi - lo))
			throw ValueException("Incomplete text at end of data")

		return ret
	}

	function incrementalEncoder(errors: string = "strict") =
		Utf32LEIncrementalEncoder(errors)

	function incrementalDecoder(errors: string = "strict") =
		Utf32LEIncrementalDecoder(errors)
}

registerCodec("utf-32-le", Utf32LECodec())
aliasCodec("utf-32-le", "utf32le")

// =====================================================================================================================
// UTF-32 Big Endian (no BOM on either encoding or decoding)

local class Utf32BEIncrementalEncoder : IncrementalEncoder
{
	_errors

	this(errors: string = "strict")
		:_errors = errors

	function encodeInto(str: string, dest: memblock, start: int, final: bool = false) =
		_encodeInto(str, dest, start, :_errors, 'b')

	function reset() {}
}

local class Utf32BEIncrementalDecoder : BufferedIncrementalDecoder
{
	function bufferedDecode_(src: memblock, lo: int, hi: int, errors: string = "strict", final: bool = false)
		return _decodeRange(src, lo, hi, errors, 'b')
}

class Utf32BECodec : TextCodec
{
	name = "utf-32-be"

	function encodeInto(str: string, dest: memblock, start: int, errors: string = "strict") =
		_encodeInto(str, dest, start, errors, 'b')

	function decodeRange(src: memblock, lo: int, hi: int, errors: string = "strict")
	{
		local ret, eaten = _decodeRange(src, lo, hi, errors, 'b')

		if(eaten < (hi - lo))
			throw ValueException("Incomplete text at end of data")

		return ret
	}

	function incrementalEncoder(errors: string = "strict") =
		Utf32BEIncrementalEncoder(errors)

	function incrementalDecoder(errors: string = "strict") =
		Utf32BEIncrementalDecoder(errors)
}

registerCodec("utf-32-be", Utf32BECodec())
aliasCodec("utf-32-be", "utf32be")
`;