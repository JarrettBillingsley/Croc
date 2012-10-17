#include <stdio.h>
#include <stdlib.h>

#include "croc/base/darray.hpp"

using namespace croc;

// #include "croc/base/alloc.hpp"
// #include "croc/base/sanity.hpp"

// using namespace croc;

// void* DefaultMemFunc(void* ctx, void* p, size_t oldSize, size_t newSize)
// {
// 	if(newSize == 0)
// 	{
// 		free(p);
// 		return NULL;
// 	}
// 	else
// 	{
// 		void* ret = cast(void*)realloc(p, newSize);

// 		// if(ret == null)
// 		// 	onOutOfMemoryError();

// 		return ret;
// 	}
// }

#include <stdint.h>

const uint8_t UTF8CharLengths[256] =
{
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
	2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
	3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,
	4,4,4,4,4,4,4,4,5,5,5,5,6,6,1,1
};

const size_t   UTF8InvalidTailBits[4] =  {1,1,0,1}; // 2-bit index
const size_t   UTF8InvalidOffset[8] =    {0,3,2,2,1,1,1,1}; // 3-bit index
const uint32_t UTF8MagicSubtraction[5] = {0, 0x00000000, 0x00003080, 0x000E2080, 0x03C82080}; // index is 1..4
const uint32_t UTF8OverlongMinimum[5] =  {0, 0x00000000, 0x00000080, 0x00000800, 0x00010000}; // index is 1..4

#define IN_RANGE(c, lo, hi) ((uint32_t)((c) - (lo)) < ((hi) - (lo) + 1))
#define IS_SURROGATE(c)     IN_RANGE(c, 0xd800, 0xdfff)
#define IS_NONCHARACTER(c)  IN_RANGE(c, 0xfdd0, 0xfdef)
#define IS_RESERVED(c)      (((c) & 0xfffe) == 0xfffe)
#define IS_OUT_OF_RANGE(c)  ((c) > 0x10ffff)
#define IS_INVALID_BMP(c)   (IS_SURROGATE(c) || IS_NONCHARACTER(c) || IS_RESERVED(c) || IS_OUT_OF_RANGE(c))

// This code (and the accompanying tables) borrowed, in a slightly modified form, from
// http://floodyberry.wordpress.com/2007/04/14/utf-8-conversion-tricks/
// Thanks Andrew!
bool decodeUTF8Char(const char*& s, const char* end, uint32_t& out)
{
	uint32_t c = *s;

	if(c < 0x80)
	{
		s++;
		out = c;
		return true;
	}

	size_t len = UTF8CharLengths[c];

	if(len == 1 || len > 4 || (s + len > end))
		return false;

	c &= 0x7F >> len;
	size_t mask = 0;

	for(size_t i = 1; i < len; i++)
	{
		// This looks wrong, but it's not! The "continuation" bits are removed by the UTF8MagicSubtraction step.
		c = (c << 6) + s[i];
		mask = (mask << 1) | UTF8InvalidTailBits[s[i] >> 6];
	}

	if(mask)
	{
		s += UTF8InvalidOffset[mask];
		return false;
	}

	c -= UTF8MagicSubtraction[len];

	if(c < UTF8OverlongMinimum[len] || IS_INVALID_BMP(c))
		return false;

	s += len;
	out = c;
	return true;
}

bool decodeUTF16Char(const uint16_t*& s, const uint16_t* end, uint32_t&out)
{
	uint32_t c = *s;

	// Single-codeunit character?
	if(c <= 0xD7FF || c >= 0xE000)
	{
		if(IS_NONCHARACTER(c) || IS_RESERVED(c))
			return false;

		s++;
		out = c;
		return true;
	}

	// First code unit must be a leading surrogate, and there better be another code unit after this
	if(!IN_RANGE(c, 0xD800, 0xDBFF) || s + 1 >= end)
		return false;

	uint16_t c2 = s[1];

	// Second code unit must be a trailing surrogate
	if(!IN_RANGE(c2, 0xDC00, 0xDFFF))
		return false;

	c = 0x10000 + (((c & 0x3FF) << 10) | (c2 & 0x3FF));

	if(IS_RESERVED(c) || IS_OUT_OF_RANGE(c))
		return false;

	s += 2;
	out = c;
	return true;
}

bool verifyUTF8(DArray<const char> str, size_t& cpLen)
{
	cpLen = 0;
	const char* s = str.ptr;
	const char* end = s + str.length;
	uint32_t c;

	while(s < end)
	{
		cpLen++;

		if(*s < 0x80)
			s++;
		else if(!decodeUTF8Char(s, end, c))
			return false;
	}

	return true;
}

#define UTF16_NEXT_CHAR\
	if(!decodeUTF16Char(src, srcEnd, c))\
	{\
		success = false;\
		return DArray<char>();\
	}

#define UTF32_NEXT_CHAR\
	c = *src++;\
\
	if(IS_INVALID_BMP(c))\
	{\
		src = srcSave;\
		success = false;\
		return DArray<char>();\
	}

#define MAKE_TO_UTF8(name, type, NEXTCHAR)\
	DArray<char> name(DArray<const type> str, DArray<char> buf, size_t& idx, bool& success)\
	{\
		const type* src = str.ptr + idx;\
		const type* srcEnd = str.ptr + str.length;\
		char* dest = buf.ptr;\
		char* destEnd = dest + buf.length;\
		char* destEndM2 = destEnd - 2;\
		char* destEndM3 = destEnd - 3;\
		char* destEndM4 = destEnd - 4;\
\
		while(src < srcEnd && dest < destEnd)\
		{\
			while(src < srcEnd && dest < destEnd && *src < 0x80)\
				*dest++ = *src++;\
\
			if(src < srcEnd && dest < destEnd)\
			{\
				const type* srcSave = src;\
				uint32_t c;\
\
				NEXTCHAR\
\
				if(c < 0x800)\
				{\
					if(dest <= destEndM2)\
					{\
						*dest++ = 0xC0 | (c >> 6);\
						*dest++ = 0x80 | (c & 0x3F);\
						continue;\
					}\
				}\
				else if(c < 0x10000)\
				{\
					if(dest <= destEndM3)\
					{\
						*dest++ = 0xE0 | (c >> 12);\
						*dest++ = 0x80 | ((c >> 6) &  0x3F);\
						*dest++ = 0x80 | (c & 0x3F);\
						continue;\
					}\
				}\
				else\
				{\
					if(dest <= destEndM4)\
					{\
						*dest++ = 0xF0 | (c >> 18);\
						*dest++ = 0x80 | ((c >> 12) &  0x3F);\
						*dest++ = 0x80 | ((c >> 6) & 0x3F);\
						*dest++ = 0x80 | (c & 0x3F);\
						continue;\
					}\
				}\
\
				src = srcSave;\
				break;\
			}\
		}\
\
		idx = src - str.ptr;\
		success = true;\
		return buf.slice(0, dest - buf.ptr);\
	}

MAKE_TO_UTF8(UTF16ToUTF8, uint16_t, UTF16_NEXT_CHAR)
MAKE_TO_UTF8(UTF32ToUTF8, uint32_t, UTF32_NEXT_CHAR)

#undef MAKE_TO_UTF8
#undef UTF16_NEXT_CHAR
#undef UTF32_NEXT_CHAR

// =====================================================================================================================
// The functions from here on all assume the input string is well-formed -- which is the case with Croc's strings

uint32_t fastDecodeUTF8Char(const char*& s)
{
	uint32_t c = *s;

	if(c < 0x80)
	{
		s++;
		return c;
	}

	size_t len = UTF8CharLengths[c];

	c &= 0x7F >> len;

	for(size_t i = 1; i < len; i++)
		c = (c << 6) | (s[i] & 0x3F);

	s += len;
	return c;
}

DArray<uint16_t> UTF8ToUTF16(DArray<const char> str, DArray<uint16_t> buf)
{
	assert(buf.length >= 2 * str.length);
	const char* src = str.ptr;
	const char* end = src + str.length;
	uint16_t* dest = buf.ptr;

	while(src < end)
	{
		while(src < end && *src < 0x80)
			*dest++ = *src++;

		if(src < end)
		{
			uint32_t c = fastDecodeUTF8Char(src);

			if(c < 0x10000)
				*dest++ = c;
			else
			{
				c -= 0x10000;
				*dest++ = 0xD800 | (c >> 10);
				*dest++ = 0xDC00 | (c & 0x3FF);
			}
		}
	}

	return buf.slice(0, dest - buf.ptr);
}

DArray<uint32_t> UTF8ToUTF32(DArray<const char> str, DArray<uint32_t> buf)
{
	assert(buf.length >= str.length);
	const char* src = str.ptr;
	const char* end = src + str.length;
	uint32_t* dest = buf.ptr;

	while(src < end)
	{
		while(src < end && *src < 0x80)
			*dest++ = *src++;

		if(src < end)
			*dest++ = fastDecodeUTF8Char(src);
	}

	return buf.slice(0, dest - buf.ptr);
}

DArray<const char> UTF8Slice(DArray<const char> str, size_t lo, size_t hi)
{
	if(lo == hi)
		return DArray<const char>();

	const char* s = str.ptr;
	size_t realLo = 0;

	for( ; realLo < lo; realLo++)
		s += UTF8CharLengths[*s];

	size_t realHi = realLo;

	for( ; realHi < hi; realHi++)
		s += UTF8CharLengths[*s];

	return str.slice(realLo, realHi);
}

uint32_t UTF8CharAt(DArray<const char> str, size_t idx)
{
	const char* s = str.ptr;

	for(size_t i = 0; i < idx; i++)
		s += UTF8CharLengths[*s];

	return fastDecodeUTF8Char(s);
}

size_t UTF8CPIdxToByte(DArray<const char> str, size_t fake)
{
	const char* s = str.ptr;

	for(size_t i = 0; i < fake; i++)
		s += UTF8CharLengths[*s];

	return s - str.ptr;
}

size_t UTF8ByteIdxToCP(DArray<const char> str, size_t fake)
{
	const char* fakeEnd = str.ptr + fake;
	size_t ret = 0;

	for(const char* s = str.ptr; s < fakeEnd; ret++)
		s += UTF8CharLengths[*s];

	return ret;
}

int main()
{
	// Allocator a;
	// a.memFunc = &DefaultMemFunc;



	return 0;
}