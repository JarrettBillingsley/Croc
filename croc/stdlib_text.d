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

// =====================================================================================================================
// Public
// =====================================================================================================================

public:

void initTextLib(CrocThread* t)
{
	importModuleFromStringNoNS(t, "text", textSource, "text.croc");
	initAsciiCodec(t);
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
*/

module text

import exceptions:
	BoundsException,
	LookupException,
	NotImplementedException,
	ParamException,
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
Gets an alphabetically sorted list of all available codecs (including aliases).
*/
function getAllCodecs() =
	hash.keys(textCodecs).sort()

/**
Returns whether or not a codec of the given name has been registered.
*/
function hasCodec(name: string) =
	name in textCodecs

class TextCodec
{
	/**
	The name of the text encoding that this codec implements.
	*/
	name = ""

	/**
	Takes a string to encode, a memblock into which the encoded data is placed, and an index into the memblock where
	encoding should begin. The length of the memblock will be set to exactly long enough to contain the encoded data.
	The same memblock is returned.
	*/
	function encodeInto(str: string, dest: memblock, start: int, errors: string = "strict")
		throw NotImplementedException()

	/**
	Same as calling \link{encodeInto} with a new, empty memblock and a starting index of 0.
	*/
	function encode(str: string, errors: string = "strict") =
		:encodeInto(str, memblock.new(0), 0, errors)

	/**
	Takes a memblock and a range of characters to decode. Decodes the given range into a string, which is returned. If
	the given range is not consumed in its entirety, it is an error. If you need that behavior -- and about the only
	time that you would is in a "stream decoding" situation -- that's what \link{incrementalDecoder} is for.
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
	incrementally -- that is, when the end of a string is reached, the encoder preserves any state that it needs so that
	another string can be encoded after it and treated as a continuation.
	*/
	function incrementalEncoder(errors: string = "strict")
		throw NotImplementedException()

	/**
	Returns a new instance of a class derived from \link{IncrementalDecoder} that allows you to decode a stream of text
	incrementally -- that is, when the end of the memblock range is reached, the decoder preserves any state that it
	needs so that another piece of memblock can be decoded after it and treated as a continuation.
	*/
	function incrementalDecoder(errors: string = "strict")
		throw NotImplementedException()
}

class IncrementalEncoder
{
	/**
	The error behavior of an incremental encoder is specified only once, when it's first constructed.
	*/
	this(errors: string = "strict")
		throw NotImplementedException()

	/**
	Like \link{TextCodec.encodeInto}, but works a bit differently. The \tt{final} parameter tells the function whether
	or not this is the last piece of string to be encoded. This way the encoder can throw an error if there's
	insufficient input or whatever.

	Returns three things: \tt{dest}, the number of characters consumed from \tt{str}, and the index in \tt{dest} after
	the last encoded character (that is, you could then pass that index as the \tt{start} of another call to this
	function).
	*/
	function encodeInto(str: string, dest: memblock, start: int, final: bool = false)
		throw NotImplementedException()

	/**
	Same as caling \link{encodeInto} with a new, empty memblock and a starting index of 0.
	*/
	function encode(str: string, final: bool = false) =
		:encodeInto(str, memblock.new(0), 0, final)

	/**
	Resets any internal state to its initial state so that this encoder object can be used to encode a new string.
	*/
	function reset()
		throw NotImplementedException()
}

class IncrementalDecoder
{
	/**
	The error behacior of an incremental decoder is specified only once, when it's first constructed.
	*/
	this(errors: string = "strict")
		throw NotImplementedException()

	/**
	Like \link{TextCodec.decodeRange}, but works a bit differently. The \tt{final} parameter tells the function whether
	or not this is the last piece of data to be decoded. This way the decoder can throw an error if there's insufficient
	input or whatever.

	Returns two things: a string representing the portion of \tt{src} that was decoded, and the index in \tt{src} after
	the last decoded byte (that is, you could then pass that index as the \tt{lo} of another call to this function).
	*/
	function decodeRange(src: memblock, lo: int, hi: int, final: bool = false)
		throw NotImplementedException()

	/**
	Same as calling \link{decodeRange} with a slice of the entire memblock.
	*/
	function decode(src: memblock, final: bool = false) =
		:decodeRange(src, 0, #src, final)

	/**
	Resets any internal state to its initial state so that this decoder object can be used to decode a new string.
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
