/******************************************************************************
This module holds low-level Unicode manipulation routines for transcoding and
such.

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

module croc.utf;

private const ubyte[256] UTF8CharLengths =
[
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
	2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
	3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,
	4,4,4,4,4,4,4,4,0,0,0,0,0,0,0,0
];

private const size_t UTF8InvalidTailBits[4]  = [1,1,0,1]; // 2-bit index
private const uint   UTF8MagicSubtraction[5] = [0, 0x00000000, 0x00003080, 0x000E2080, 0x03C82080]; // index is 1..4
private const uint   UTF8OverlongMinimum[5]  = [0, 0x00000000, 0x00000080, 0x00000800, 0x00010000]; // index is 1..4

private template IN_RANGE(char[] c, char[] lo, char[] hi)
{
	const IN_RANGE = "cast(uint)(" ~ c ~ " - " ~ lo ~ ") < (" ~ hi ~ " - " ~ lo ~ " + 1)";
}

private template IS_SURROGATE(char[] c)     { const IS_SURROGATE = IN_RANGE!("c", "0xd800", "0xdfff"); }
private template IS_NONCHARACTER(char[] c)  { const IS_NONCHARACTER = IN_RANGE!("c", "0xfdd0", "0xfdef"); }
private template IS_RESERVED(char[] c)      { const IS_RESERVED = "(" ~ c ~ " & 0xfffe) == 0xfffe"; }
private template IS_OUT_OF_RANGE(char[] c)  { const IS_OUT_OF_RANGE = c ~ " > 0x10ffff"; }
private template IS_INVALID_BMP(char[] c)
{
	const IS_INVALID_BMP =
		IS_SURROGATE!(c) ~ " || " ~
		IS_NONCHARACTER!(c) ~ " || " ~
		IS_RESERVED!(c) ~ " || " ~
		IS_OUT_OF_RANGE!(c);
}

/**
Returns whether or not a given codepoint is valid Unicode.
*/
bool isValidChar(dchar c)
{
	return !mixin(IS_INVALID_BMP!("c"));
}

/**
Returns the number of bytes needed to encode the given codepoint in UTF-8, or 0 if the codepoint is out of the valid
range of Unicode.
*/
size_t charUTF8Length(dchar c)
{
	if(c < 0x80)
		return 1;
	else if(c < 0x800)
		return 2;
	else if(c < 0x10000)
		return 3;
	else if(!mixin(IS_OUT_OF_RANGE!("c")))
		return 4;
	else
		return 0;
}

/**
Given the value of an initial UTF-8 code unit, returns how many bytes long this character is, or 0 if this is an invalid
initial code unit.
*/
size_t utf8SequenceLength(ubyte firstByte)
{
	return UTF8CharLengths[firstByte];
}

/**
Enumeration of possible return values from certain UTF decoding functions.
*/
enum UTFError
{
	OK = 0,          /// Success.
	BadEncoding = 1, /// The data is incorrectly encoded. It may or may not be possible to progress past this.
	BadChar = 2,     /// The data was encoded properly, but encodes an invalid character.
	Truncated = 3,   /// The end of the data comes before the character can be completely decoded.
}

/**
Attempts to decode a single codepoint from the given UTF-8 encoded text.

If the encoding is invalid, returns false. s will be unchanged.

If decoding completed successfully, returns UTFError.OK. s will be pointing to the next code unit in the string, and
outch will be set to the decoded codepoint.

Overlong encodings (characters which were encoded with more bytes than necessary) are treated as "bad encoding" rather
than "bad character".

This code (and the accompanying tables) borrowed, in a slightly modified form, from
http://floodyberry.wordpress.com/2007/04/14/utf-8-conversion-tricks/ ; thanks Andrew!

Params:
	s = pointer to the codepoint to be decoded. Will be advanced by this function.
	end = pointer to the end of the string.
	outch = the decoded character.

Returns:
	One of the members of UTFError. If it is UTFError.BadChar, outch will be set to the (invalid) character that was
	decoded.
*/
UTFError decodeUTF8Char(ref char* s, char* end, ref dchar outch)
{
	dchar c = *s;

	if(c < 0x80)
	{
		s++;
		outch = c;
		return UTFError.OK;
	}

	size_t len = UTF8CharLengths[c];

	if(len == 0)
		return UTFError.BadEncoding;
	else if((s + len) > end)
		return UTFError.Truncated;

	size_t mask = 0;

	for(size_t i = 1; i < len; i++)
	{
		// This looks wrong, but it's not! The "continuation" bits are removed by the UTF8MagicSubtraction step.
		c = (c << 6) + s[i];
		mask = (mask << 1) | UTF8InvalidTailBits[s[i] >> 6];
	}

	if(mask)
		return UTFError.BadEncoding;

	c -= UTF8MagicSubtraction[len];

	if(c < UTF8OverlongMinimum[len])
		return UTFError.BadEncoding;
	else if(mixin(IS_INVALID_BMP!("c")))
	{
		outch = c;
		return UTFError.BadChar;
	}

	s += len;
	outch = c;
	return UTFError.OK;
}

/**
Same as above, but for UTF-16 encoded text.
*/
UTFError decodeUTF16Char(bool swap = false)(ref wchar* s, wchar* end, ref dchar outch)
{
	dchar c = *s;

	static if(swap)
		c = ((c & 0xFF) << 8) | (c >> 8);

	// Single-codeunit character?
	if(c <= 0xD7FF || c >= 0xE000)
	{
		if(mixin(IS_NONCHARACTER!("c")) || mixin(IS_RESERVED!("c")))
		{
			outch = c;
			return UTFError.BadChar;
		}

		s++;
		outch = c;
		return UTFError.OK;
	}

	// First code unit must be a leading surrogate, and there better be another code unit after this
	if(!mixin(IN_RANGE!("c", "0xD800", "0xDBFF")))
		return  UTFError.BadEncoding;
	else if((s + 2) > end)
		return UTFError.Truncated;

	dchar c2 = s[1];

	static if(swap)
		c2 = ((c2 & 0xFF) << 8) | (c2 >> 8);

	// Second code unit must be a trailing surrogate
	if(!mixin(IN_RANGE!("c2", "0xDC00", "0xDFFF")))
		return UTFError.BadEncoding;

	c = 0x10000 + (((c & 0x3FF) << 10) | (c2 & 0x3FF));

	if(mixin(IS_RESERVED!("c")) || mixin(IS_OUT_OF_RANGE!("c")))
	{
		outch = c;
		return UTFError.BadChar;
	}

	s += 2;
	outch = c;
	return UTFError.OK;
}

/**
Same as above, but byteswaps the code units when reading them.
*/
alias decodeUTF16Char!(true) decodeUTF16CharBS;

/**
Same as above, but for UTF-32 encoded text.
*/
UTFError decodeUTF32Char(bool swap = false)(ref dchar* s, dchar* end, ref dchar outch)
{
	dchar c = *s;

	static if(swap)
		c = ((c & 0xFF) << 24) | ((c & 0xFF00) << 8) | ((c & 0xFF0000) >> 8) | (c >> 24);

	outch = c;

	if(mixin(IS_INVALID_BMP!("c")))
		return UTFError.BadChar;
	else
	{
		s++;
		return UTFError.OK;
	}
}

/**
Same as above, but byteswaps the code units when reading them.
*/
alias decodeUTF32Char!(true) decodeUTF32CharBS;

/**
Verifies whether or not the given string is valid encoded UTF-8.

Params:
	str = The string to be checked for validity.
	cpLen = Set to the length of the string, in codepoints, if this function returns true.

Returns:
	true if the given string is valid UTF-8, false, otherwise.
*/
UTFError verifyUTF8(char[] str, ref size_t cpLen)
{
	cpLen = 0;
	dchar c = void;
	auto s = str.ptr;
	auto end = s + str.length;

	while(s < end)
	{
		cpLen++;

		if(*s < 0x80)
			s++;
		else
		{
			auto ok = decodeUTF8Char(s, end, c);

			if(ok != UTFError.OK)
				return ok;
		}
	}

	return UTFError.OK;
}

/**
Attempts to transcode UTF-16 or UTF-32 encoded text to UTF-8.

This function is templated but the only two valid type parameters are wchar and dchar.

This function expects you to provide it with an output buffer that you have allocated. This buffer is not required to
be large enough to hold the entire output.

If the entire input was successfully transcoded, returns UTFError.OK, remaining will be set to an empty string, and
output will be set to the slice of buf that contains the output UTF-8.

If only some of the input was successfully transcoded (because the output buffer was not big enough), returns
UTFError.OK, remaining will be set to the slice of str that has yet to be transcoded, and output will be set to the
slice of buf that contains what UTF-8 was transcoded so far.

If the input string's encoding is invalid, returns the error code, remaining will be set to the slice of str beginning
with the invalid code unit, and output will be set to an empty string.

Params:
	str = The string to be transcoded into UTF-8.
	buf = The output UTF-8 buffer.
	remaining = If successful but ran out of room, set to the slice of str that has yet to be transcoded. If failed, set
		to the slice of str starting with the first invalid code unit.
	output = If successful, set to a slice of buf which contains the encoded UTF-8.

Returns:
	One of the members of UTFError.

Examples:
	Suppose you want to convert some UTF-32 text to UTF-8 and output it to a file as you go. You can do this in multiple
	calls as follows (using UTF32ToUTF8, an alias for the dchar instantiation of this templated function):

-----
dchar[] input = whatever(); // The source text
char[512] buffer = void;    // Intermediate buffer
char[] output = void;

while(input.length > 0)
{
	if(UTF32ToUTF8(input, buffer, input, output) == UTFError.OK)
		outputUTF8ToFile(output);
	else
		throw SomeException("Invalid UTF32");
}
-----
*/
UTFError _toUTF8(T, bool swap)(T[] str, char[] buf, ref T[] remaining, ref char[] output)
{
	auto src = str.ptr;
	auto end = src + str.length;
	auto dest = buf.ptr;
	auto destEnd = dest + buf.length;
	auto destEndM2 = destEnd - 2;
	auto destEndM3 = destEnd - 3;
	auto destEndM4 = destEnd - 4;

	while(src < end && dest < destEnd)
	{
		if(*src < 0x80)
			*dest++ = *src++;
		else
		{
			auto srcSave = src;
			dchar c = void;

			static if(is(T == wchar))
			{
				static if(swap)
					UTFError ok = decodeUTF16CharBS(src, end, c);
				else
					UTFError ok = decodeUTF16Char(src, end, c);
			}
			else static if(is(T == dchar))
			{
				static if(swap)
					UTFError ok = decodeUTF32CharBS(src, end, c);
				else
					UTFError ok = decodeUTF32Char(src, end, c);
			}
			else
				static assert(false);

			if(ok != UTFError.OK)
			{
				remaining = str[srcSave - str.ptr .. $];
				output = null;
				return ok;
			}

			if(c < 0x800)
			{
				if(dest <= destEndM2)
				{
					*dest++ = cast(char)(0xC0 | (c >> 6));
					*dest++ = cast(char)(0x80 | (c & 0x3F));
					continue;
				}
			}
			else if(c < 0x10000)
			{
				if(dest <= destEndM3)
				{
					*dest++ = cast(char)(0xE0 | (c >> 12));
					*dest++ = cast(char)(0x80 | ((c >> 6) & 0x3F));
					*dest++ = cast(char)(0x80 | (c & 0x3F));
					continue;
				}
			}
			else
			{
				if(dest <= destEndM4)
				{
					*dest++ = cast(char)(0xF0 | (c >> 18));
					*dest++ = cast(char)(0x80 | ((c >> 12) & 0x3F));
					*dest++ = cast(char)(0x80 | ((c >> 6) & 0x3F));
					*dest++ = cast(char)(0x80 | (c & 0x3F));
					continue;
				}
			}

			src = srcSave;
			break;
		}
	}

	remaining = str[src - str.ptr .. $];
	output = buf[0 .. dest - buf.ptr];
	return UTFError.OK;
}

/**
Convenience alias for the UTF-16 to UTF-8 function.
*/
alias _toUTF8!(wchar, false) UTF16ToUTF8;

/**
Convenience alias for the UTF-32 to UTF-8 function.
*/
alias _toUTF8!(dchar, false) UTF32ToUTF8;

/**
Convenience alias for the byte-swapped UTF-16 to UTF-8 function.
*/
alias _toUTF8!(wchar, true) UTF16ToUTF8BS;

/**
Convenience alias for the byte-swapped UTF-32 to UTF-8 function.
*/
alias _toUTF8!(dchar, true) UTF32ToUTF8BS;

/**
Encodes a single Unicode codepoint into UTF-8. Useful as a shortcut for when you just need to convert a character to its
UTF-8 representation.

Params:
	buf = The output buffer. Should be at least four bytes long.
	c = The character to encode.
	ret = Will be set to the slice of buf that contains the output UTF-8.

Returns:
	One of the members of UTFError. If buf is too small to hold the encoded character, returns UTFError.Truncated.
*/
UTFError encodeUTF8Char(char[] buf, dchar c, ref char[] ret)
{
	dchar[] remaining = void;

	auto ok = UTF32ToUTF8((&c)[0 .. 1], buf, remaining, ret);

	if(ok == UTFError.OK)
		return remaining.length == 0 ? UTFError.OK : UTFError.Truncated;
	else
		return ok;
}

// =====================================================================================================================
// The functions from here on all assume the input string is well-formed -- which is the case with Croc's strings

/**
Assuming the given UTF-8 is well-formed, decodes a single codepoint and advances the string pointer.

Params:
	s = Pointer to the codepoint to be decoded. There are no checks done to ensure that this actually points into a
		string! Will be advanced to the next character after decoding.

Returns:
	The decoded codepoint.

Examples:
	You can use this to quickly iterate over the characters of a string that you know to be valid UTF-8:

-----
char[] str = something();
char* ptr = str.ptr;
char* end = ptr + str.length;

while(ptr < end)
{
	dchar c = fastDecodeUTF8Char(ptr);
	// do something with c
}
-----
*/
dchar fastDecodeUTF8Char(ref char* s)
{
	dchar c = *s;

	if(c < 0x80)
	{
		s++;
		return c;
	}

	size_t len = UTF8CharLengths[c];

	for(size_t i = 1; i < len; i++)
		c = (c << 6) + s[i];

	s += len;
	c -= UTF8MagicSubtraction[len];
	return c;
}

/**
Assuming the given UTF-8 is well-formed, decodes a single codepoint from $(B before) the current pointer, and moves the
pointer to point to it.

Params:
	s = Pointer to the byte after the codepoint to be decoded. There are no checks done to ensure that this actually
		points into a string! Will be moved back to the beginning of the decoded character after decoding.

Returns:
	The decoded codepoint.

Examples:
	You can use this to quickly iterate backwards over the characters of a string that you know to be valid UTF-8:

-----
char[] str = something();
char* begin = str.ptr;
char* ptr = begin + str.length;

while(ptr > begin)
{
	dchar c = fastReverseUTF8Char(ptr);
	// do something with c
}
-----
*/
dchar fastReverseUTF8Char(ref char* s)
{
	dchar c = *(--s);

	if(c < 0x80)
		return c;

	size_t len = 1;

	while(*s & 0x80)
	{
		s--;
		c += *s << (6 * len);
		len++;

		if((*s & 0xC0) == 0xC0)
			break;
	}

	assert(len == UTF8CharLengths[*s]);
	return c - UTF8MagicSubtraction[len];
}

/**
Assuming the given UTF-8 is well-formed, transcodes it into UTF-16.

This function expects you to provide it with an output buffer that you have allocated. This buffer is not required to
be large enough to hold the entire output.

If the entire input was successfully transcoded, remaining will be set to an empty string, and the return value will be
a slice of buf that contains the output UTF-16.

If only some of the input was successfully transcoded (because the output buffer was not big enough), remaining will be
set to the slice of str that has yet to be transcoded, and the return value will be a slice of buf that contains what
UTF-16 was transcoded so far.

Params:
	str = The string to be transcoded into UTF-16.
	buf = The output UTF-16 buffer.
	remaining = Set to the slice of str that has yet to be transcoded, or an empty string if transcoding completed.

Returns:
	A slice of buf which contains the encoded UTF-16.

Examples:
	Suppose you want to convert some UTF-8 text to UTF-16 and output it to a file as you go. You can do this in multiple
	calls as follows:

-----
char[] input = whatever(); // The source text; must be valid UTF-8
wchar[256] buffer = void;  // Intermediate buffer

while(input.length > 0)
{
	auto output = UTF8ToUTF16(input, buffer, input);
	outputUTF8ToFile(output);
}
-----

*/
wchar[] UTF8ToUTF16(bool swap = false)(char[] str, wchar[] buf, ref char[] remaining)
{
	auto src = str.ptr;
	auto end = src + str.length;
	wchar* dest = buf.ptr;
	wchar* destEnd = dest + buf.length;

	while(src < end && dest < destEnd)
	{
		if(*src < 0x80)
			*dest++ = *src++;
		else
		{
			auto srcSave = src;
			auto c = fastDecodeUTF8Char(src);

			if(c < 0x10000)
			{
				static if(swap)
					*dest++ = cast(wchar)(((c & 0xFF) << 8) | (c >> 8));
				else
					*dest++ = c;
			}
			else if(dest < destEnd - 1)
			{
				c -= 0x10000;

				static if(swap)
				{
					*dest++ = cast(wchar)(0x00D8 | ((c & 0x3FC00) >> 2) | (c >> 18));
					*dest++ = cast(wchar)(0x00DC | ((c & 0xFF) << 8) | ((c >> 8) & 0x3));
				}
				else
				{
					*dest++ = cast(wchar)(0xD800 | (c >> 10));
					*dest++ = cast(wchar)(0xDC00 | (c & 0x3FF));
				}
			}
			else
			{
				src = srcSave;
				break;
			}
		}
	}

	remaining = str[src - str.ptr .. $];
	return buf[0 .. dest - buf.ptr];
}

/**
Same as above, but byte-swaps the output.
*/
alias UTF8ToUTF16!(true) UTF8ToUTF16BS;

/**
Same as above, but for transcoding to UTF-32 instead.
*/
dchar[] UTF8ToUTF32(bool swap = false)(char[] str, dchar[] buf, ref char[] remaining)
{
	auto src = str.ptr;
	auto end = src + str.length;
	dchar* dest = buf.ptr;
	dchar* destEnd = dest + buf.length;

	while(src < end && dest < destEnd)
	{
		static if(swap)
		{
			if(*src < 0x80)
				*dest++ = (*src++) << 24;
			else
			{
				auto c = fastDecodeUTF8Char(src);
				*dest++ = ((c & 0xFF) << 24) | ((c & 0xFF00) << 8) | ((c & 0xFF0000) >> 8) | (c >> 24);
			}
		}
		else
		{
			if(*src < 0x80)
				*dest++ = *src++;
			else
				*dest++ = fastDecodeUTF8Char(src);
		}
	}

	remaining = str[src - str.ptr .. $];
	return buf[0 .. dest - buf.ptr];
}

/**
Same as above, but byte-swaps the output.
*/
alias UTF8ToUTF32!(true) UTF8ToUTF32BS;

/**
Given a valid UTF-8 string and two codepoint indices, returns a slice of the string.

This is a linear time operation, as indexing and slicing by codepoint index rather than by byte index requires a linear
traversal of the string.
*/
char[] UTF8Slice(char[] str, size_t lo, size_t hi)
{
	if(lo == hi)
		return null;

	auto s = str.ptr;
	size_t realLo = 0;

	for( ; realLo < lo; realLo++)
		s += UTF8CharLengths[*s];

	size_t realHi = realLo;

	for( ; realHi < hi; realHi++)
		s += UTF8CharLengths[*s];

	return str[realLo .. realHi];
}

/**
Given a valid UTF-8 string and a codepoint index, returns the codepoint at that index.

This is a linear time operation, as indexing and slicing by codepoint index rather than by byte index requires a linear
traversal of the string.
*/
dchar UTF8CharAt(char[] str, size_t idx)
{
	auto s = str.ptr;

	for(size_t i = 0; i < idx; i++)
		s += UTF8CharLengths[*s];

	return fastDecodeUTF8Char(s);
}

/**
Given a valid UTF-8 string and a codepoint index, returns the equivalent byte index.

This is a linear time operation, as indexing and slicing by codepoint index rather than by byte index requires a linear
traversal of the string.
*/
size_t UTF8CPIdxToByte(char[] str, size_t fake)
{
	auto s = str.ptr;

	for(size_t i = 0; i < fake; i++)
		s += UTF8CharLengths[*s];

	return s - str.ptr;
}

/**
Given a valid UTF-8 string and a byte index, returns the equivalent codepoint index.

Note that the given byte index must be pointing to the beginning of a codepoint for this function to work properly.

This is a linear time operation, as indexing and slicing by codepoint index rather than by byte index requires a linear
traversal of the string.
*/
size_t UTF8ByteIdxToCP(char[] str, size_t fake)
{
	auto fakeEnd = str.ptr + fake;
	size_t ret = 0;

	for(auto s = str.ptr; s < fakeEnd; ret++)
		s += UTF8CharLengths[*s];

	return ret;
}