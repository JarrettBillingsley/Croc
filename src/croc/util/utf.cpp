#include "croc/base/darray.hpp"
#include "croc/base/sanity.hpp"

#include "croc/util/utf.hpp"

namespace croc
{
	namespace
	{
	const uint8_t Utf8CharLengths[256] =
	{
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
	};

	const size_t   Utf8InvalidTailBits[4] =  {1,1,0,1}; // 2-bit index
	const uint32_t Utf8MagicSubtraction[5] = {0, 0x00000000, 0x00003080, 0x000E2080, 0x03C82080}; // index is 1..4
	const uint32_t Utf8OverlongMinimum[5] =  {0, 0x00000000, 0x00000080, 0x00000800, 0x00010000}; // index is 1..4
	}

	#define IN_RANGE(c, lo, hi) ((uint32_t)((c) - (lo)) < ((hi) - (lo) + 1))
	#define IS_SURROGATE(c)     IN_RANGE(c, 0xd800, 0xdfff)
	#define IS_NONCHARACTER(c)  IN_RANGE(c, 0xfdd0, 0xfdef)
	#define IS_RESERVED(c)      (((c) & 0xfffe) == 0xfffe)
	#define IS_OUT_OF_RANGE(c)  ((c) > 0x10ffff)
	#define IS_INVALID_BMP(c)   (IS_SURROGATE(c) || IS_NONCHARACTER(c) || IS_RESERVED(c) || IS_OUT_OF_RANGE(c))

	/**
	Returns whether or not a given codepoint is valid Unicode.
	*/
	bool isValidChar(dchar c)
	{
		return !IS_INVALID_BMP(c);
	}

	/**
	Returns the number of bytes needed to encode the given codepoint in UTF-8, or 0 if the codepoint is out of the valid
	range of Unicode.
	*/
	size_t charUtf8Length(dchar c)
	{
		if(c < 0x80)
			return 1;
		else if(c < 0x800)
			return 2;
		else if(c < 0x10000)
			return 3;
		else if(!IS_OUT_OF_RANGE(c))
			return 4;
		else
			return 0;
	}

	/**
	Given the value of an initial UTF-8 code unit, returns how many bytes long this character is, or 0 if this is an invalid
	initial code unit.
	*/
	size_t utf8SequenceLength(uchar firstByte)
	{
		return Utf8CharLengths[firstByte];
	}

	/**
	Attempts to decode a single codepoint from the given UTF-8 encoded text.

	If the encoding is invalid, returns UtfError_BadEncoding. s will be unchanged.

	If decoding completed successfully, returns UtfError_OK. s will be pointing to the next code unit in the string, and
	out will be set to the decoded codepoint.

	Overlong encodings (characters which were encoded with more bytes than necessary) are treated as "bad encoding" rather
	than "bad character".

	This code (and the accompanying tables) borrowed, in a slightly modified form, from
	http://floodyberry.wordpress.com/2007/04/14/utf-8-conversion-tricks/ ; thanks Andrew!

	Params:
		s = pointer to the codepoint to be decoded. Will be advanced by this function.
		end = pointer to the end of the string.
		out = the decoded character.

	Returns:
		One of the members of UtfError. If it is UtfError_BadChar, out will be set to the (invalid) character that was
		decoded.
	*/
	UtfError decodeUtf8Char(const uchar*& s, const uchar* end, dchar& out)
	{
		dchar c = *s;

		if(c < 0x80)
		{
			s++;
			out = c;
			return UtfError_OK;
		}

		size_t len = Utf8CharLengths[cast(uchar)c];

		if(len == 0)
			return UtfError_BadEncoding;
		else if((s + len) > end)
			return UtfError_Truncated;

		size_t mask = 0;

		for(size_t i = 1; i < len; i++)
		{
			// This looks wrong, but it's not! The "continuation" bits are removed by the UTF8MagicSubtraction step.
			c = (c << 6) + s[i];
			mask = (mask << 1) | Utf8InvalidTailBits[s[i] >> 6];
		}

		if(mask)
			return UtfError_BadEncoding;

		c -= Utf8MagicSubtraction[len];

		if(c < Utf8OverlongMinimum[len])
			return UtfError_BadEncoding;
		else if(IS_INVALID_BMP(c))
		{
			out = c;
			return UtfError_BadChar;
		}

		s += len;
		out = c;
		return UtfError_OK;
	}

	/**
	Same as above, but for UTF-16 encoded text.
	*/
	template<bool swap = false>
	UtfError decodeUtf16Char(const wchar*& s, const wchar* end, dchar& out)
	{
		dchar c = *s;

		if(swap)
			c = ((c & 0xFF) << 8) | (c >> 8);

		// Single-codeunit character?
		if(c <= 0xD7FF || c >= 0xE000)
		{
			if(IS_NONCHARACTER(c) || IS_RESERVED(c))
			{
				out = c;
				return UtfError_BadChar;
			}

			s++;
			out = c;
			return UtfError_OK;
		}

		// First code unit must be a leading surrogate, and there better be another code unit after this
		if(!IN_RANGE(c, 0xD800, 0xDBFF))
			return UtfError_BadEncoding;
		else if((s + 2) > end)
			return UtfError_Truncated;

		dchar c2 = s[1];

		if(swap)
			c2 = ((c2 & 0xFF) << 8) | (c2 >> 8);

		// Second code unit must be a trailing surrogate
		if(!IN_RANGE(c2, 0xDC00, 0xDFFF))
			return UtfError_BadEncoding;

		c = 0x10000 + (((c & 0x3FF) << 10) | (c2 & 0x3FF));

		if(IS_RESERVED(c) || IS_OUT_OF_RANGE(c))
		{
			out = c;
			return UtfError_BadChar;
		}

		s += 2;
		out = c;
		return UtfError_OK;
	}

	template UtfError decodeUtf16Char<true>(const wchar*& s, const wchar* end, dchar& out);
	template UtfError decodeUtf16Char<false>(const wchar*& s, const wchar* end, dchar& out);

	/**
	Same as above, but byteswaps the code units when reading them.
	*/
	#define decodeUtf16CharBS decodeUtf16Char<true>

	/**
	Same as above, but for UTF-32 encoded text.
	*/
	template<bool swap = false>
	UtfError decodeUtf32Char(const dchar*& s, const dchar* end, dchar& out)
	{
		(void)end;
		dchar c = *s;

		if(swap)
			c = ((c & 0xFF) << 24) | ((c & 0xFF00) << 8) | ((c & 0xFF0000) >> 8) | (c >> 24);

		out = c;

		if(IS_INVALID_BMP(c))
			return UtfError_BadChar;
		else
		{
			s++;
			return UtfError_OK;
		}
	}

	template UtfError decodeUtf32Char<true>(const dchar*& s, const dchar* end, dchar& out);
	template UtfError decodeUtf32Char<false>(const dchar*& s, const dchar* end, dchar& out);

	/**
	Same as above, but byteswaps the code units when reading them.
	*/
	#define decodeUtf32CharBS decodeUtf32Char<true>

	/**
	Skips over a bad UTF-8 codepoint by advancing the given string pointer over it. Note that depending on the nature of the
	invalid incoding, subsequent decoding may fail anyway.

	Params:
		s = pointer to the codepoint to be skipped. Will be advanced by this function, though never past end.
		end = pointer to the end of the string.
	*/
	void skipBadUtf8Char(const uchar*& s, const uchar* end)
	{
		size_t len = Utf8CharLengths[*s];

		if(len == 0)
			s++;
		else if((s + len) > end)
			s = end;
		else
			s += len;
	}

	/**
	Same as above, but for UTF-16 encoded text.
	*/
	template<bool swap = false>
	void skipBadUtf16Char(const wchar*& s, const wchar* end)
	{
		dchar c = *s;

		if(swap)
			c = ((c & 0xFF) << 8) | (c >> 8);

		if(c <= 0xDBFF || c >= 0xE000)
			s++;
		else if((s + 2) > end)
			s = end;
		else
			s += 2;
	}

	template void skipBadUtf16Char<true>(const wchar*& s, const wchar* end);
	template void skipBadUtf16Char<false>(const wchar*& s, const wchar* end);

	/**
	Same as above, but byteswaps the code units when reading them.
	*/
	#define skipBadUtf16CharBS skipBadUtf16Char<true>

	/**
	Same as above, but for UTF-32 encoded text.
	*/
	template<bool swap = false>
	void skipBadUtf32Char(const dchar*& s, const dchar* end)
	{
		if(s < end)
			s++;
	}

	template void skipBadUtf32Char<true>(const dchar*& s, const dchar* end);
	template void skipBadUtf32Char<false>(const dchar*& s, const dchar* end);

	/**
	Same as above, but byteswaps the code units when reading them.
	*/
	#define skipBadUtf32CharBS skipBadUtf32Char<true>

	/**
	Verifies whether or not the given string is valid encoded UTF-8.

	Params:
		str = The string to be checked for validity.
		cpLen = Set to the length of the string, in codepoints, if this function returns true.

	Returns:
		true if the given string is valid UTF-8, false, otherwise.
	*/
	bool verifyUtf8(custring str, size_t& cpLen)
	{
		cpLen = 0;
		dchar c;
		auto s = str.ptr;
		auto end = s + str.length;

		while(s < end)
		{
			cpLen++;

			if(*s < 0x80)
				s++;
			else
			{
				auto ok = decodeUtf8Char(s, end, c);

				if(ok != UtfError_OK)
					return ok;
			}
		}

		return UtfError_OK;
	}

	#define UTF16_NEXT_CHAR decodeUtf16Char<false>(src, end, c)
	#define UTF16_NEXT_CHAR_BS decodeUtf16Char<true>(src, end, c)
	#define UTF32_NEXT_CHAR decodeUtf32Char<false>(src, end, c)
	#define UTF32_NEXT_CHAR_BS decodeUtf32Char<true>(src, end, c)

	/**
	Attempts to transcode UTF-16 or UTF-32 encoded text to UTF-8.

	This function expects you to provide it with an output buffer that you have allocated. This buffer is not required to
	be large enough to hold the entire output.

	If the entire input was successfully transcoded, returns UtfError_OK, remaining will be set to an empty string, and
	output will be set to the slice of buf that contains the output UTF-8.

	If only some of the input was successfully transcoded (because the output buffer was not big enough), returns
	UtfError_OK, remaining will be set to the slice of str that has yet to be transcoded, and output will be set to the
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
		One of the members of UtfError.

	Examples:
		Suppose you want to convert some UTF-32 text to UTF-8 and output it to a file as you go. You can do this in multiple
		calls as follows (using Utf32ToUtf8, an alias for the dchar instantiation of this templated function):

	-----
	dchar[] input = whatever(); // The source text
	char[512] buffer = void;    // Intermediate buffer
	char[] output = void;

	while(input.length > 0)
	{
		if(Utf32ToUtf8(input, buffer, input, output) == UtfError_OK)
			outputUTF8ToFile(output);
		else
			throw SomeException("Invalid UTF32");
	}
	-----
	*/
	#define MAKE_TO_UTF8(name, type, NEXTCHAR)\
		UtfError name(DArray<const type> str, ustring buf, DArray<const type>& remaining, ustring& output)\
		{\
			auto src = str.ptr;\
			auto end = src + str.length;\
			auto dest = buf.ptr;\
			auto destEnd = dest + buf.length;\
			auto destEndM2 = destEnd - 2;\
			auto destEndM3 = destEnd - 3;\
			auto destEndM4 = destEnd - 4;\
	\
			while(src < end && dest < destEnd)\
			{\
				auto srcSave = src;\
				dchar c;\
	\
				UtfError ok = NEXTCHAR;\
	\
				if(ok != UtfError_OK)\
				{\
					remaining = str.slice(srcSave - str.ptr, str.length);\
					output = ustring();\
					return ok;\
				}\
	\
				if(c < 0x80)\
				{\
					*dest++ = c;\
					continue;\
				}\
				if(c < 0x800)\
				{\
					if(dest <= destEndM2)\
					{\
						*dest++ = cast(char)(0xC0 | (c >> 6));\
						*dest++ = cast(char)(0x80 | (c & 0x3F));\
						continue;\
					}\
				}\
				else if(c < 0x10000)\
				{\
					if(dest <= destEndM3)\
					{\
						*dest++ = cast(char)(0xE0 | (c >> 12));\
						*dest++ = cast(char)(0x80 | ((c >> 6) & 0x3F));\
						*dest++ = cast(char)(0x80 | (c & 0x3F));\
						continue;\
					}\
				}\
				else\
				{\
					if(dest <= destEndM4)\
					{\
						*dest++ = cast(char)(0xF0 | (c >> 18));\
						*dest++ = cast(char)(0x80 | ((c >> 12) & 0x3F));\
						*dest++ = cast(char)(0x80 | ((c >> 6) & 0x3F));\
						*dest++ = cast(char)(0x80 | (c & 0x3F));\
						continue;\
					}\
				}\
	\
				src = srcSave;\
				break;\
			}\
	\
			remaining = str.slice(src - str.ptr, str.length);\
			output = buf.slice(0, dest - buf.ptr);\
			return UtfError_OK;\
		}\

	MAKE_TO_UTF8(Utf16ToUtf8, wchar, UTF16_NEXT_CHAR)
	MAKE_TO_UTF8(Utf32ToUtf8, dchar, UTF32_NEXT_CHAR)
	MAKE_TO_UTF8(Utf16ToUtf8BS, wchar, UTF16_NEXT_CHAR_BS)
	MAKE_TO_UTF8(Utf32ToUtf8BS, dchar, UTF32_NEXT_CHAR_BS)

	#undef MAKE_TO_UTF8
	#undef UTF16_NEXT_CHAR
	#undef UTF16_NEXT_CHAR_BS
	#undef UTF32_NEXT_CHAR
	#undef UTF32_NEXT_CHAR_BS

	/**
	Encodes a single Unicode codepoint into UTF-8. Useful as a shortcut for when you just need to convert a character to its
	UTF-8 representation.

	Params:
		buf = The output buffer. Should be at least four bytes long.
		c = The character to encode.
		ret = Will be set to the slice of buf that contains the output UTF-8.

	Returns:
		One of the members of UtfError. If buf is too small to hold the encoded character, returns UtfError_Truncated.
	*/
	UtfError encodeUtf8Char(ustring buf, dchar c, ustring& ret)
	{
		auto str = cdstring::n(&c, 1);
		cdstring remaining;

		auto ok = Utf32ToUtf8(str, buf, remaining, ret);

		if(ok == UtfError_OK)
			return remaining.length == 0 ? UtfError_OK : UtfError_Truncated;
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
		dchar c = fastDecodeUtf8Char(ptr);
		// do something with c
	}
	-----
	*/
	dchar fastDecodeUtf8Char(const uchar*& s)
	{
		dchar c = *s;

		if(c < 0x80)
		{
			s++;
			return c;
		}

		size_t len = Utf8CharLengths[cast(unsigned char)c];

		for(size_t i = 1; i < len; i++)
			c = (c << 6) + s[i];

		s += len;
		c -= Utf8MagicSubtraction[len];
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
	dchar fastReverseUtf8Char(const uchar*& s)
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

		assert(len == Utf8CharLengths[*s]);
		return c - Utf8MagicSubtraction[len];
	}

	/**
	Assuming that s points into well-formed UTF-8, moves s backwards, if necessary, to place it at the beginning of a
	multibyte character. If s is already pointing to the beginning of a character, it is left unchanged.
	*/
	void fastAlignUtf8(const uchar*& s)
	{
		while((*s & 0xC0) == 0x80)
			s--;
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
		auto output = Utf8ToUtf16(input, buffer, input);
		outputUTF8ToFile(output);
	}
	-----

	*/
	template<bool swap = false>
	wstring Utf8ToUtf16(custring str, wstring buf, custring& remaining)
	{
		auto src = str.ptr;
		auto end = src + str.length;
		wchar* dest = buf.ptr;
		wchar* destEnd = dest + buf.length;

		while(src < end && dest < destEnd)
		{
			if(*src < 0x80)
			{
				if(swap)
					*dest++ = cast(wchar)(*src++ << 8);
				else
					*dest++ = *(src++);
			}
			else
			{
				auto srcSave = src;
				auto c = fastDecodeUtf8Char(src);

				if(c < 0x10000)
				{
					if(swap)
						*dest++ = cast(wchar)(((c & 0xFF) << 8) | (c >> 8));
					else
						*dest++ = c;
				}
				else if(dest < destEnd - 1)
				{
					c -= 0x10000;

					if(swap)
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

		remaining = str.slice(src - str.ptr, str.length);
		return buf.slice(0, dest - buf.ptr);
	}

	template wstring Utf8ToUtf16<true>(custring str, wstring buf, custring& remaining);
	template wstring Utf8ToUtf16<false>(custring str, wstring buf, custring& remaining);

	/**
	Same as above, but byte-swaps the output.
	*/
	#define Utf8ToUtf16BS Utf8ToUtf16<true>

	/**
	Same as above, but for transcoding to UTF-32 instead.
	*/
	template<bool swap = false>
	dstring Utf8ToUtf32(custring str, dstring buf, custring& remaining)
	{
		auto src = str.ptr;
		auto end = src + str.length;
		dchar* dest = buf.ptr;
		dchar* destEnd = dest + buf.length;

		while(src < end && dest < destEnd)
		{
			if(swap)
			{
				if(*src < 0x80)
					*dest++ = *(src++) << 24;
				else
				{
					auto c = fastDecodeUtf8Char(src);
					*dest++ = ((c & 0xFF) << 24) | ((c & 0xFF00) << 8) | ((c & 0xFF0000) >> 8) | (c >> 24);
				}
			}
			else
			{
				if(*src < 0x80)
					*dest++ = *(src++);
				else
					*dest++ = fastDecodeUtf8Char(src);
			}
		}

		remaining = str.slice(src - str.ptr, str.length);
		return buf.slice(0, dest - buf.ptr);
	}

	template dstring Utf8ToUtf32<true>(custring str, dstring buf, custring& remaining);
	template dstring Utf8ToUtf32<false>(custring str, dstring buf, custring& remaining);

	/**
	Same as above, but byte-swaps the output.
	*/
	#define Utf8ToUtf32BS Utf8ToUtf32<true>

	/**
	Given a valid UTF-8 string and two codepoint indices, returns a slice of the string.

	This is a linear time operation, as indexing and slicing by codepoint index rather than by byte index requires a linear
	traversal of the string.
	*/
	custring utf8Slice(custring str, size_t lo, size_t hi)
	{
		if(lo == hi)
			return custring();

		auto s = str.ptr;

		for(size_t i = 0; i < lo; i++)
			s += Utf8CharLengths[*s];

		size_t realLo = cast(size_t)(s - str.ptr);

		for(size_t i = lo; i < hi; i++)
			s += Utf8CharLengths[*s];

		return str.slice(realLo, cast(size_t)(s - str.ptr));
	}

	/**
	Given a valid UTF-8 string and a codepoint index, returns the codepoint at that index.

	This is a linear time operation, as indexing and slicing by codepoint index rather than by byte index requires a linear
	traversal of the string.
	*/
	dchar utf8CharAt(custring str, size_t idx)
	{
		auto s = str.ptr;

		for(size_t i = 0; i < idx; i++)
			s += Utf8CharLengths[*s];

		return fastDecodeUtf8Char(s);
	}

	/**
	Given a valid UTF-8 string and a codepoint index, returns the equivalent byte index.

	This is a linear time operation, as indexing and slicing by codepoint index rather than by byte index requires a linear
	traversal of the string.
	*/
	size_t utf8CPIdxToByte(custring str, size_t fake)
	{
		auto s = str.ptr;

		for(size_t i = 0; i < fake; i++)
			s += Utf8CharLengths[*s];

		return s - str.ptr;
	}

	/**
	Given a valid UTF-8 string and a byte index, returns the equivalent codepoint index.

	Note that the given byte index must be pointing to the beginning of a codepoint for this function to work properly.

	This is a linear time operation, as indexing and slicing by codepoint index rather than by byte index requires a linear
	traversal of the string.
	*/
	size_t utf8ByteIdxToCP(custring str, size_t fake)
	{
		auto fakeEnd = str.ptr + fake;
		size_t ret = 0;

		for(auto s = str.ptr; s < fakeEnd; ret++)
			s += Utf8CharLengths[*s];

		return ret;
	}

	/**
	Given a valid UTF-8 string, count how many codepoints there are in it.

	This is a linear time operation, as indexing and slicing by codepoint index rather than by byte index requires a linear
	traversal of the string.
	*/
	size_t fastUtf8CPLength(custring str)
	{
		return utf8ByteIdxToCP(str, str.length);
	}

	/**
	Given a valid UTF-16 string, get how many bytes it would take to encode it as UTF-8.
	*/
	size_t fastUtf16GetUtf8Size(cwstring str)
	{
		size_t ret = 0;

		for(auto p = str.ptr, e = p + str.length; p < e; )
		{
			dchar ch;
			auto ok = decodeUtf16Char(p, e, ch);
			assert(ok == UtfError_OK);
#ifdef NDEBUG
			(void)ok
#endif
			if(ch < 0x80)
				ret++;
			else if(ch < 0x800)
				ret += 2;
			else if(ch < 0x10000)
				ret += 3;
			else
				ret += 4;
		}

		return ret;
	}

	/**
	Given a valid UTF-32 string, get how many bytes it would take to encode it as UTF-8.
	*/
	size_t fastUtf32GetUtf8Size(cdstring str)
	{
		size_t ret = 0;

		for(auto ch: str)
		{
			if(ch < 0x80)
				ret++;
			else if(ch < 0x800)
				ret += 2;
			else if(ch < 0x10000)
				ret += 3;
			else
				ret += 4;
		}

		return ret;
	}

	/**
	Given a valid UTF-8 string, count how many UTF-16 code units it would take to encode it.
	*/
	size_t fastUtf8GetUtf16Size(custring str)
	{
		size_t ret = 0;

		for(auto p = str.ptr, e = p + str.length; p < e; )
		{
			auto ch = fastDecodeUtf8Char(p);

			if(ch < 0x10000)
				ret++;
			else
				ret += 2;
		}

		return ret;
	}
}