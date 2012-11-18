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
is used when an unencodable character is encountered. If the error behavior is \tt{"strict"}, a \tt{UnicodeException} is
thrown. If the error behavior is \tt{"ignore"}, the unencodable character is simply skipped. If the error behavior is
\tt{"replace"}, the unencodable character is skipped, and a codec-defined replacement character is encoded in its place.
Usually this will be a question mark character, but not necessarily.

For decoding, the input data may or may nor be well-formed; thus the error handling mechanism is used when malformed or
invalid input is encountered. If the error behavior is \tt{"strict"}, a \tt{UnicodeException} is thrown. If the error
behavior is \tt{"ignore"}, the invalid input is skipped. If the error behavior is \tt{"replace"}, the invalid input is
skipped, and the Unicode Replacement Character (U+00FFFD) is used in its place.
*/

module text

import exceptions:
	BoundsException,
	LookupException,
	NotImplementedException,
	ParamException,
	RangeException,
	TypeException,
	UnicodeException,
	ValueException

local textCodecs = {}

/**
Register a text codec of the given name. The codec can then be retrieved with \link{getCodec}.

\throws[exceptions.LookupException] if there is already a codec registered named \tt{name}.
*/
function registerCodec(name: string, codec: TextCodec)
{
	if(name in textCodecs)
		throw LookupException("Already a codec for '{}' registered".format(name))

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

\throws[exceptions.ParamException] if you don't pass at least one variadic argument.
\throws[exceptions.TypeException] if any of the variadic arguments are not strings.
*/
function aliasCodec(name: string, vararg)
{
	local c = getCodec(name)

	if(#vararg == 0)
		throw ParamException("Must have at least one variadic argument")

	for(i: 0 .. #vararg)
	{
		local rename = vararg[i]

		if(!isString(rename))
			throw TypeException("All variadic arguments must be strings")

		registerCodec(rename, c)
	}
}

/**
Gets the codec object that was registered with the given name.

\throws[exceptions.LookupException] if there was no codec registered with the given name.
*/
function getCodec(name: string)
{
	if(local ret = textCodecs[name])
		return ret

	throw LookupException("No codec registered for '{}'".format(name))
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
function charUTF8Length(c: char)
{
	local i = toInt(c)

	if(i < 0x80)
		return 1
	else if(i < 0x800)
		return 2
	else if(i < 0x10000)
		return 3
	else if(c <= 0x10FFFF)
		return 4
	else
		return 0
}

local UTF8StartCharLengths =
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

\throws[exceptions.RangeException] if \tt{firstByte} is not in the range \tt{[0 .. 255]}.
*/
function utf8SequenceLength(firstByte: int)
{
	if(firstByte < 0 || firstByte > 255)
		throw RangeException("{} is not in the range 0 to 255 inclusive".format(firstByte))

	return UTF8StartCharLengths[firstByte]
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
		throw NotImplementedException()

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

	\throws[exceptions.ValueException] if the given slice of data cannot be consumed in its entirety, such as if there
		is an incomplete character encoding at the end of the data. If you need to be able to decode data piecemeal,
		such as in a stream decoding situation, this is what \link{incrementalDecoder} is for.
	*/
	function decodeRange(src: memblock, lo: int, hi: int, errors: string = "strict")
		throw NotImplementedException()

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
		throw NotImplementedException()

	/**
	Returns a new instance of a class derived from \link{IncrementalDecoder} that allows you to decode a stream of text
	incrementally. See that class's docs for more info.
	*/
	function incrementalDecoder(errors: string = "strict")
		throw NotImplementedException()
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
		throw NotImplementedException()

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
		throw NotImplementedException()

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
		throw NotImplementedException()
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
		throw NotImplementedException()

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
		throw NotImplementedException()

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
		throw NotImplementedException()
}
`;






















// uword _toRawUnicode(CrocThread* t)
// {
// 	checkStringParam(t, 1);
// 	auto str = getStringObj(t, 1);
// 	auto bitSize = optIntParam(t, 2, 8);

// 	if(bitSize != 8 && bitSize != 16 && bitSize != 32)
// 		throwStdException(t, "ValueException", "Invalid encoding size of {} bits", bitSize);

// 	CrocMemblock* ret;
// 	uword mbLen = str.length * (cast(uword)bitSize / 8);

// 	if(optParam(t, 3, CrocValue.Type.Memblock))
// 	{
// 		ret = getMemblock(t, 3);
// 		lenai(t, 3, mbLen);
// 	}
// 	else
// 	{
// 		newMemblock(t, mbLen);
// 		ret = getMemblock(t, -1);
// 	}

// 	uword len = 0;
// 	auto src = str.toString();

// 	switch(bitSize)
// 	{
// 		case 8:
// 			(cast(char*)ret.data.ptr)[0 .. str.length] = src[];
// 			len = str.length;
// 			break;

// 		case 16:
// 			auto dest = (cast(wchar*)ret.data.ptr)[0 .. str.length];

// 			auto temp = allocArray!(dchar)(t, str.length);
// 			scope(exit) freeArray(t, temp);

// 			uint ate = 0;
// 			auto tempData = safeCode(t, "exceptions.UnicodeException", Utf_toString32(src, temp, &ate));
// 			len = 2 * safeCode(t, "exceptions.UnicodeException", Utf_toString16(temp, dest, &ate)).length;
// 			break;

// 		case 32:
// 			auto dest = (cast(dchar*)ret.data.ptr)[0 .. str.length];
// 			uint ate = 0;
// 			len = 4 *  safeCode(t, "exceptions.UnicodeException", Utf_toString32(src, dest, &ate)).length;
// 			break;

// 		default: assert(false);
// 	}

// 	push(t, CrocValue(ret));
// 	lenai(t, -1, len);
// 	return 1;
// }

// uword _fromRawUnicode(CrocThread* t)
// {
// 	checkParam(t, 1, CrocValue.Type.Memblock);
// 	auto mb = getMemblock(t, 1);
// 	auto bitSize = checkIntParam(t, 2);

// 	if(bitSize != 8 && bitSize != 16 && bitSize != 32)
// 		throwStdException(t, "ValueException", "Invalid encoding size of {} bits", bitSize);

// 	auto lo = optIntParam(t, 3, 0);
// 	auto hi = optIntParam(t, 4, mb.data.length);

// 	if(lo < 0)
// 		lo += mb.data.length;

// 	if(hi < 0)
// 		hi += mb.data.length;

// 	if(lo < 0 || lo > hi || hi > mb.data.length)
// 		throwStdException(t, "BoundsException", "Invalid memblock slice indices {} .. {} (memblock length: {})", lo, hi, mb.data.length);

// 	if(((lo - hi) % (bitSize / 8)) != 0)
// 		throwStdException(t, "ValueException", "Slice length ({}) is not an even multiple of character size ({})", lo - hi, bitSize / 8);

// 	switch(bitSize)
// 	{
// 		case 8:  pushFormat(t, "{}", (cast(char[])mb.data)[cast(uword)lo .. cast(uword)hi]); break;
// 		case 16: pushFormat(t, "{}", (cast(wchar[])mb.data)[cast(uword)lo .. cast(uword)hi]); break;
// 		case 32: pushFormat(t, "{}", (cast(dchar[])mb.data)[cast(uword)lo .. cast(uword)hi]); break;
// 		default: assert(false);
// 	}

// 	return 1;
// }

// uword _fromRawAscii(CrocThread* t)
// {
// 	checkParam(t, 1, CrocValue.Type.Memblock);
// 	auto mb = getMemblock(t, 1);
// 	auto lo = optIntParam(t, 2, 0);
// 	auto hi = optIntParam(t, 3, mb.data.length);

// 	if(lo < 0)
// 		lo += mb.data.length;

// 	if(hi < 0)
// 		hi += mb.data.length;

// 	if(lo < 0 || lo > hi || hi > mb.data.length)
// 		throwStdException(t, "BoundsException", "Invalid memblock slice indices {} .. {} (memblock length: {})", lo, hi, mb.data.length);

// 	auto src = (cast(char[])mb.data)[cast(uword)lo .. cast(uword)hi];
// 	auto dest = allocArray!(char)(t, src.length);

// 	scope(exit)
// 		freeArray(t, dest);

// 	foreach(i, char c; src)
// 	{
// 		if(c <= 0x7f)
// 			dest[i] = c;
// 		else
// 			dest[i] = '\u001a';
// 	}

// 	pushString(t, dest);
// 	return 1;
// }

// version(CrocBuiltinDocs) const Docs[] _globalFuncDocs =
// [
// 	{kind: "function", name: "fromRawUnicode",
// 	params: [Param("mb", "memblock"), Param("lo", "int", "0"), Param("hi", "int", "#mb")],
// 	docs:
// 	`Converts data stored in a memblock into a string. The given memblock must be of type \tt{u8}, \tt{u16}, or \tt{u32}.
// 	If it's \tt{u8}, it must contain UTF-8 data; if it's \tt{u16}, it must contain UTF-16 data; and if it's \tt{u32}, it
// 	must contain UTF-32 data. You can specify only a slice of the memblock to convert into a string with the \tt{lo}
// 	and \tt{hi} parameters; the default behavior is to convert the entire memblock. If the data is invalid Unicode,
// 	an exception will be thrown. Returns the converted string.

// 	\throws[exceptions.BoundsException] if the given slice indices are invalid.
// 	\throws[exceptions.ValueException] if the given memblock is not one of the three valid types.`},

// 	{kind: "function", name: "fromRawAscii",
// 	params: [Param("mb", "memblock"), Param("lo", "int", "0"), Param("hi", "int", "#mb")],
// 	docs:
// 	`Similar to \link{fromRawUnicode}, except converts a memblock containing ASCII data into a string. The memblock
// 	must be of type \tt{u8}. Any bytes above U+00007F are turned into the Unicode replacement character, U+00001A.
// 	Returns the converted string.

// 	\throws[exceptions.BoundsException] if the given slice indices are invalid.
// 	\throws[exceptions.ValueException] if the given memblock is not of type \tt{u8}.`},

// 	{kind: "function", name: "toRawUnicode",
// 	params: [Param("bits", "int", "8"), Param("mb", "memblock", "null")],
// 	docs:
// 	`Converts a string into a memblock containing Unicode-encoded data. The \tt{bits} parameter determines which
// 	encoding to use. It defaults to 8, which means the resulting memblock will be filled with a UTF-8 encoding of
// 	\tt{s}, and its type will be \tt{u8}. The other two valid values are 16, which will encode UTF-16 data in a memblock
// 	of type \tt{u16}, and 32, which will encode UTF-32 data in a memblock of type \tt{u32}.

// 	You may optionally pass a memblock as the second parameter to be used as the destination memblock. This way you
// 	can reuse a memblock as a conversion buffer to avoid memory allocations. The memblock's type will be set
// 	appropriately and its data will be replaced by the encoded string data.

// 	\returns the memblock containing the encoded string data, either a new memblock if \tt{mb} is \tt{null}, or \tt{mb}
// 	otherwise.

// 	\throws[exceptions.ValueException] if \tt{bits} is not one of the valid values.
// 	\throws[exceptions.UnicodeException] if, somehow, the Unicode transcoding fails (but this shouldn't happen unless something
// 	else is broken..)`},

// 	{kind: "function", name: "toRawAscii",
// 	params: [Param("mb", "memblock", "null")],
// 	docs:
// 	`Similar to \link{toRawUnicode}, except encodes \tt{s} as ASCII. \tt{s} must not contain any codepoints above U+00007F;
// 	that is, \tt{s.isAscii()} must return true for this method to work.

// 	Just like \link{toRawUnicode} you can pass a memblock as a destination buffer. Its type will be set to \tt{u8}.

// 	\returns the memblock containing the encoded string data, either a new memblock if \tt{mb} is \tt{null}, or \tt{mb}
// 	otherwise.

// 	\throws[exceptions.ValueException] if the given string is not an ASCII string.`},
// ];
