/******************************************************************************
This module contains the 'text' standard library.

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

module croc.stdlib_text;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.types;

import croc.stdlib_text_ascii;
import croc.stdlib_text_latin1;
import croc.stdlib_text_utf8;
import croc.stdlib_text_utf16;
import croc.stdlib_text_utf32;

// =====================================================================================================================
// Public
// =====================================================================================================================

public:

void initTextLib(CrocThread* t)
{
	importModuleFromStringNoNS(t, "text", textSource, "text.croc");
	initAsciiCodec(t);
	initLatin1Codec(t);
	initUtf8Codec(t);
	initUtf16Codec(t);
	initUtf32Codec(t);
}

// =====================================================================================================================
// Private
// =====================================================================================================================

private:

const char[] textSource =
`/**
This library contains utilities for performing text encoding and formatting.

Note that this is somewhat different from the purpose of the \tt{string} library, which concerns itself with
simple algorithmic operations on string objects. This module instead deals with the more "linguistic" aspects of
handling text, including encoding strings into and decoding strings from raw character encodings, and formatting
program objects into human-readable forms.

This module exposes flexible interfaces, and the hope is that more text encodings and formatting options will be
made available by second- and third-party libraries.

\b{Error Handling}

The text codecs' encoding and decoding functions all take an optional argument to control the behavior of encoding and
decoding when erroneous input is encountered. There are three error behaviors: \tt{"strict"}, \tt{"ignore"}, and
\tt{"replace"}. The default behavior is \tt{"strict"}.

For encoding, the input text is always well-formed, since Croc strings are always valid sequences of Unicode codepoints.
However, many text encodings only support a subset of all available Unicode codepoints, so the error handling mechanism
is used when an unencodable character is encountered. If the error behavior is \tt{"strict"}, a \tt{UnicodeError} is
thrown. If the error behavior is \tt{"ignore"}, the unencodable character is simply skipped. If the error behavior is
\tt{"replace"}, the unencodable character is skipped, and a codec-defined replacement character is encoded in its place.
Usually this will be a question mark character, but not necessarily.

For decoding, the input data may or may nor be well-formed; thus the error handling mechanism is used when malformed or
invalid input is encountered. If the error behavior is \tt{"strict"}, a \tt{UnicodeError} is thrown. If the error
behavior is \tt{"ignore"}, the invalid input is skipped. If the error behavior is \tt{"replace"}, the invalid input is
skipped, and the Unicode Replacement Character (U+00FFFD) is used in its place.
*/

module text

local textCodecs = {}

/**
Register a text codec of the given name. The codec can then be retrieved with \link{getCodec}.

\throws[exceptions.LookupError] if there is already a codec registered named \tt{name}.
*/
function registerCodec(name: string, codec: TextCodec)
{
	if(name in textCodecs)
		throw LookupError("Already a codec for '{}' registered".format(name))

	textCodecs[name] = codec
}

/**
Re-registers an already-registered codec with one or more alternate names.

For instance, if you wanted the codec "foobar" to be accessible also as "foo-bar" or "FOOBAR", you could use:

\code
aliasCodec("foobar", "foo-bar", "FOOBAR")
\endcode

Then \tt{getCodec("foo-bar")} and \tt{getCodec("FOOBAR")} would give the same codec as \tt{getCodec("foobar")}.

\param[name] is the name of the codec to alias. It must have been previously registered with \link{registerCodec}.
\param[vararg] is one or more strings that will be registered as aliases to the given codec.

\throws[exceptions.ParamError] if you don't pass at least one variadic argument.
\throws[exceptions.TypeError] if any of the variadic arguments are not strings.
*/
function aliasCodec(name: string, vararg)
{
	local c = getCodec(name)

	if(#vararg == 0)
		throw ParamError("Must have at least one variadic argument")

	for(i: 0 .. #vararg)
	{
		local rename = vararg[i]

		if(!isString(rename))
			throw TypeError("All variadic arguments must be strings")

		registerCodec(rename, c)
	}
}

/**
Gets the codec object that was registered with the given name.

\throws[exceptions.LookupError] if there was no codec registered with the given name.
*/
function getCodec(name: string)
{
	if(local ret = textCodecs[name])
		return ret

	throw LookupError("No codec registered for '{}'".format(name))
}

/**
Gets an alphabetically sorted array of the names of all available codecs (including aliases).
*/
function getAllCodecNames() =
	hash.keys(textCodecs).sort()

/**
Gets an alphabetically sorted array of arrays. Each sub-array has the name of the codec as the first element and the
codec itself as the second.
*/
function getAllCodecs() =
	[[k, v] foreach k, v; textCodecs].sort(\a, b -> a[0] <=> b[0])

/**
Returns whether or not a codec of the given name has been registered.
*/
function hasCodec(name: string) =
	name in textCodecs

/**
Returns the number of bytes needed to encode the given codepoint in UTF-8, or 0 if the codepoint is out of the valid
range of Unicode.
*/
function charUtf8Length(c: string)
{
	if(#c != 1)
		throw ValueError("One-character string expected")

	local i = c.ord(0)

	if(i < 0x80)
		return 1
	else if(i < 0x800)
		return 2
	else if(i < 0x10000)
		return 3
	else if(i <= 0x10FFFF)
		return 4
	else
		return 0
}

local Utf8StartCharLengths =
[
	1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
	1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
	1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
	1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
	1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
	1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
	1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
	1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
	0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
	0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
	0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
	0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
	2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2
	2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2
	3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3
	4 4 4 4 4 4 4 4 0 0 0 0 0 0 0 0
];

/**
Given the value of an initial UTF-8 code unit, returns how many bytes long this character is, or 0 if this is an invalid
initial code unit.

\throws[exceptions.RangeError] if \tt{firstByte} is not in the range \tt{[0 .. 255]}.
*/
function utf8SequenceLength(firstByte: int)
{
	if(firstByte < 0 || firstByte > 255)
		throw RangeError("{} is not in the range 0 to 255 inclusive".format(firstByte))

	return Utf8StartCharLengths[firstByte]
}

/**
UTF-8 "BOM", not so much a byte-order mark as it is a UTF-8 tag. Sometimes appears at the beginning of UTF-8 encoded
text.
*/
global BOM_UTF8 = memblock.fromArray([0xEF 0xBB 0xBF])

/**
A string representation of the above.
*/
global BOM_UTF8_STR = "\uFEFF"

/**
Little-endian UTF-16 BOM.
*/
global BOM_UTF16_LE = memblock.fromArray([0xFF 0xFE])

/**
Big-endian UTF-16 BOM.
*/
global BOM_UTF16_BE = memblock.fromArray([0xFE 0xFF])

/**
Little-endian UTF-32 BOM.
*/
global BOM_UTF32_LE = memblock.fromArray([0xFF 0xFE 0x00 0x00])

/**
Big-endian UTF-32 BOM.
*/
global BOM_UTF32_BE = memblock.fromArray([0x00 0x00 0xFE 0xFF])

/**
Native and byte-swapped UTF-16 and UTF-32 BOMs. These are just aliases for the above globals, and which is "native" and
which is "byte-swapped" is determined automatically for you.
*/
global BOM_UTF16, BOM_UTF16_BS

/// ditto
global BOM_UTF32, BOM_UTF32_BS

if(BOM_UTF16_LE.readUInt16(0) == 0xFEFF)
{
	BOM_UTF16 = BOM_UTF16_LE
	BOM_UTF32 = BOM_UTF32_LE
	BOM_UTF16_BS = BOM_UTF16_BE
	BOM_UTF32_BS = BOM_UTF32_BE
}
else
{
	BOM_UTF16 = BOM_UTF16_BE
	BOM_UTF32 = BOM_UTF32_BE
	BOM_UTF16_BS = BOM_UTF16_LE
	BOM_UTF32_BS = BOM_UTF32_LE
}

/**
The base class for all text codecs which are registered with this module. This class defines an interface which all
codecs must implement.
*/
class TextCodec
{
	/**
	The name of the text encoding that this codec implements.
	*/
	name = ""

	/**
	Encodes a string object into a string encoding, placing the encoded data into a memblock.

	\param[str] is the string to be encoded.
	\param[dest] is the memblock that will hold the encoded data. The memblock will be resized so that the end of the
		memblock coincides with the end of the encoded data. The beginning of the encoded data is specified by..
	\param[start] ..this parameter. This is the byte offset into \tt{dest} where the first byte of encoded data will be
		placed. This can be equal to \tt{#dest}, which means the encoded data will be appended to the end of \tt{dest}.
	\param[errors] controls the error handling behavior of the encoder; see this module's docs for more info.

	\returns \tt{dest}.
	*/
	function encodeInto(str: string, dest: memblock, start: int, errors: string = "strict")
		throw NotImplementedError()

	/**
	Same as calling \link{encodeInto} with a new, empty memblock and a starting index of 0.
	*/
	function encode(str: string, errors: string = "strict") =
		:encodeInto(str, memblock.new(0), 0, errors)

	/**
	Decodes an encoded string from a memblock into a string.

	\param[src] is the memblock that holds the encoded string data.
	\param[lo] and
	\param[hi] are slice indices into \tt{src}; this slice is the data to be decoded.
	\param[errors] controls the error handling behavior of the decoder; see this module's docs for more info.

	\returns the decoded text as a string.

	\throws[exceptions.ValueError] if the given slice of data cannot be consumed in its entirety, such as if there
		is an incomplete character encoding at the end of the data. If you need to be able to decode data piecemeal,
		such as in a stream decoding situation, this is what \link{incrementalDecoder} is for.
	*/
	function decodeRange(src: memblock, lo: int, hi: int, errors: string = "strict")
		throw NotImplementedError()

	/**
	Same as calling \link{decodeRange} with a slice of the entire memblock.
	*/
	function decode(src: memblock, errors: string = "strict") =
		:decodeRange(src, 0, #src, errors)

	/**
	Returns a new instance of a class derived from \link{IncrementalEncoder} that allows you to encode a stream of text
	incrementally. See that class's docs for more info.
	*/
	function incrementalEncoder(errors: string = "strict")
		throw NotImplementedError()

	/**
	Returns a new instance of a class derived from \link{IncrementalDecoder} that allows you to decode a stream of text
	incrementally. See that class's docs for more info.
	*/
	function incrementalDecoder(errors: string = "strict")
		throw NotImplementedError()
}

/**
The base class for incremental text encoders, which are returned from \link{TextCodec.incrementalEncoder} methods.

An incremental encoder does the same thing as \link{TextCodec.encodeInto} except its operation can be split up over
multiple calls instead of being done all at once. This way large pieces of data can be encoded without having to have
either the source or the output entirely in memory.
*/
class IncrementalEncoder
{
	/**
	Instead of specifying the error behavior on each call, incremental encoders have it specified once in the
	constructor.
	*/
	this(errors: string = "strict")
		throw NotImplementedError()

	/**
	Similar to \link{TextCodec.encodeInto}.

	The \tt{final} parameter tells the function whether or not this is the last piece of string to be encoded. This way
	the encoder can throw an error if there's insufficient input or whatever. Also, if the \tt{final} parameter is true,
	the encoder is expected to be reset to its initial state after this method returns.

	\param[str] same as in \link{TextCodec.encodeInto}.
	\param[dest] same as in \link{TextCodec.encodeInto}.
	\param[start] same as in \link{TextCodec.encodeInto}.
	\param[final] is explained above.

	\returns \tt{dest}.
	*/
	function encodeInto(str: string, dest: memblock, start: int, final: bool = false)
		throw NotImplementedError()

	/**
	Same as caling \link{encodeInto} with a new, empty memblock and a starting index of 0.
	*/
	function encode(str: string, final: bool = false) =
		:encodeInto(str, memblock.new(0), 0, final)

	/**
	Resets any internal state to its initial state so that this encoder object can be used to encode a new string. This
	will be called automatically by \link{encodeInto} if its \tt{final} param was \tt{true}.
	*/
	function reset()
		throw NotImplementedError()
}

/**
The base class for incremental text decoders, which are returned from \link{TextCodec.incrementalDecoder} methods.

An incremental decoder does the same thing as \link{TextCodec.decodeRange} except its operation can be split up over
multiple calls instead of being done all at once. This way large pieces of data can be decoded without having to have
either the source or the output entirely in memory.
*/
class IncrementalDecoder
{
	/**
	Instead of specifying the error behavior on each call, incremental decoders have it specified once in the
	constructor.
	*/
	this(errors: string = "strict")
		throw NotImplementedError()

	/**
	Similar to \link{TextCodec.decodeRange}.

	The \tt{final} parameter tells the function whether or not this is the last piece of string to be decoded. This way
	the decoder can throw an error if there's insufficient input or whatever. Also, if the \tt{final} parameter is true,
	the decoder is expected to be reset to its initial state after this method returns.

	If the given slice of data ends with an incomplete character encoding, it is the decoder's responsibility to keep
	this data around for the next call to this method. Then it can resume decoding by using the stored data as the
	beginning of the next character.

	\param[src] same as in \link{TextCodec.decodeRange}.
	\param[lo] same as in \link{TextCodec.decodeRange}.
	\param[hi] same as in \link{TextCodec.decodeRange}.
	\param[final] is explained above.

	\returns as much of the data as could be decoded as a string.
	*/
	function decodeRange(src: memblock, lo: int, hi: int, final: bool = false)
		throw NotImplementedError()

	/**
	Same as calling \link{decodeRange} with a slice of the entire memblock.
	*/
	function decode(src: memblock, final: bool = false) =
		:decodeRange(src, 0, #src, final)

	/**
	Resets any internal state to its initial state so that this encoder object can be used to encode a new string. This
	will be called automatically by \link{decodeRange} if its \tt{final} param was \tt{true}.
	*/
	function reset()
		throw NotImplementedError()
}

/**
A base class for incremental decoders which share a common behavior: needing to save partial character encodings from
the end of a data block for use in the next call.

Subclasses need only implement the \link{_bufferedDecode} method.
*/
class BufferedIncrementalDecoder : IncrementalDecoder
{
	_errors
	_scratch

	this(errors: string = "strict")
	{
		:_errors = errors
		:_scratch = memblock.new(0)
	}

	/**
	Subclasses just implement this method. Note that it takes both an \tt{errors} parameter \em{and} a \tt{final}
	parameter.

	This method should return two values. The first is the decoded string (or the empty string if there was not enough
	data to decode anything). The second is the number of bytes of the given slice that were consumed during decoding.

	When this method is given a memblock slice, it's possible that there is incomplete encoded data at the end of the
	slice. For instance, in a multibyte character encoding scheme (like UTF-8), there might only be the first byte of a
	four-byte character at the end of the slice. Suppose the slice is 16 bytes long. In this case, this method would
	return the decoded version of the first 15 bytes, then the number 15 (to indicate that only 15 of 16 bytes were
	decoded).

	With this information, this class can save that 1 byte into an internal buffer, and then on the next call to
	\link{decodeRange}, it will concatenate that byte to the front of the new input slice, and call this method with
	the concatenated data.

	If all the bytes were decoded from the given slice, then this method should return \tt{hi - lo} as the number of
	bytes consumed.

	\returns two values: the decoded string (or an empty string if nothing was decoded) and the number of bytes consumed
		from the given slice of the memblock.
	*/
	function _bufferedDecode(src: memblock, lo: int, hi: int, errors: string = "strict", final: bool = false)
		throw NotImplementedError()

	function decodeRange(src: memblock, lo: int, hi: int, final: bool = false)
	{
		if(#:_scratch > 0)
		{
			local m = memblock.new(#:_scratch + (hi - lo))
			m.copy(0, :_scratch, 0, #:_scratch)
			m.copy(#:_scratch, src, lo, hi - lo)
			src = m
			lo = 0
			hi = #src
		}

		writeln("bout to call it weeee")
		local ret, eaten = :_bufferedDecode(src, lo, hi, :_errors, final)
		local sliceLen = hi - lo

		if(eaten < sliceLen)
		{
			if(final)
				throw ValueError("Incomplete text at end of data")

			#:_scratch = sliceLen - eaten
			:_scratch.copy(0, src, lo + eaten, #:_scratch)
		}
		else
			#:_scratch = 0

		return ret
	}

	function reset()
	{
		#:_scratch = 0
	}
}
`;
