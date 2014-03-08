
#include <stdlib.h>
#include <string.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"
#include "croc/util/utf.hpp"

namespace croc
{
	namespace
	{
#include "croc/stdlib/text.croc.hpp"

	enum class Errors
	{
		Strict,
		Replace,
		Ignore
	};

	Errors checkErrorsParam(CrocThread* t, word_t idx)
	{
		auto str = croc_ex_optStringParam(t, idx, "strict");

		if(strcmp(str, "strict") == 0)
			return Errors::Strict;
		else if(strcmp(str, "replace") == 0)
			return Errors::Replace;
		else if(strcmp(str, "ignore") == 0)
			return Errors::Ignore;
		else
			croc_eh_throwStd(t, "ValueError", "Invalid error behavior string");

		return Errors::Strict; // dummy
	}

	// Shared global, but only ever read after init and always has the same value, so whatev
	bool isLittleEndian;

	bool shouldSwap(CrocThread* t, word_t idx)
	{
		// this function is only ever used internally so we can be a little unsafe here
		switch(croc_ex_optStringParam(t, idx, "n")[0])
		{
			case 'n': return false;
			case 's': return true;
			case 'b': return isLittleEndian;
			case 'l': return !isLittleEndian;
		}

		assert(false);
		return false; // dummy
	}

	custring checkUStrParam(CrocThread* t, word_t slot)
	{
		custring ret;
		ret.ptr = cast(const uchar*)croc_ex_checkStringParamn(t, slot, &ret.length);
		return ret;
	}

#define ENCODE_INTO_HEADER\
	auto str = checkUStrParam(t, 1);\
	auto strCPLen = cast(uword)croc_len(t, 1);\
	croc_ex_checkParam(t, 2, CrocType_Memblock);\
	auto destlen = croc_len(t, 2);\
	auto start = croc_ex_checkIntParam(t, 3);\
	auto errors = checkErrorsParam(t, 4);\
	if(start < 0) start += destlen;\
	if(start < 0 || start > destlen)\
		croc_eh_throwStd(t, "BoundsError",\
			"Invalid start index %" CROC_INTEGER_FORMAT " for memblock of length %" CROC_INTEGER_FORMAT,\
			start, destlen);

#define DECODE_RANGE_HEADER\
	croc_ex_checkParam(t, 1, CrocType_Memblock);\
	DArray<uint8_t> data;\
	data.ptr = cast(uint8_t*)croc_memblock_getDatan(t, 1, &data.length);\
	auto lo = croc_ex_checkIntParam(t, 2);\
	auto hi = croc_ex_checkIntParam(t, 3);\
	auto errors = checkErrorsParam(t, 4);\
	if(lo < 0) lo += data.length;\
	if(hi < 0) hi += data.length;\
	if(lo < 0 || lo > hi || hi > data.length)\
		croc_eh_throwStd(t, "BoundsError",\
			"Invalid slice indices(%" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT ") for memblock of length %u",\
			lo, hi, data.length);\
	auto mb = data.slice(cast(uword)lo, cast(uword)hi);

	word_t _asciiEncodeInternal(CrocThread* t)
	{
		ENCODE_INTO_HEADER

		// Gonna need at most str.length characters, if all goes well
		croc_lenai(t, 2, start + str.length);
		auto destBase = croc_memblock_getData(t, 2);
		auto dest = destBase + start;
		auto src = str.ptr;

		if(str.length == strCPLen)
		{
			// It's definitely ASCII, just shortcut copying it over.
			memcpy(dest, src, strCPLen * sizeof(char));
			croc_dup(t, 2);
			return 1;
		}

		auto end = src + str.length;
		auto last = src;

		// At least one of the characters is outside ASCII range, just let the slower loop figure out what to do
		while(src < end)
		{
			if(*src < 0x80)
				src++;
			else
			{
				if(src != last)
				{
					memcpy(dest, last, (src - last) * sizeof(char));
					dest += src - last;
				}

				auto c = fastDecodeUtf8Char(src);
				last = src;

				if(errors == Errors::Strict)
					croc_eh_throwStd(t, "UnicodeError", "Character U+%6X cannot be encoded as ASCII", cast(dchar)c);
				else if(errors == Errors::Ignore)
					continue;
	  			else // replace
					*(dest++) = '?';
			}
		}

		if(src != last)
		{
			memcpy(dest, last, (src - last) * sizeof(char));
			dest += src - last;
		}

		// "ignore" may have resulted in fewer characters being encoded than we allocated for
		croc_lenai(t, 2, dest - destBase);
		croc_dup(t, 2);
		return 1;
	}

	word_t _asciiDecodeInternal(CrocThread* t)
	{
		DECODE_RANGE_HEADER

		auto src = mb.ptr;
		auto end = mb.ptr + mb.length;
		auto last = src;

		CrocStrBuffer s;
		croc_ex_buffer_init(t, &s);

		while(src < end)
		{
			if(*src < 0x80)
				src++;
			else
			{
				if(src != last)
					croc_ex_buffer_addStringn(&s, cast(const char*)last, src - last);

				auto c = *src++;
				last = src;

				if(errors == Errors::Strict)
					croc_eh_throwStd(t, "UnicodeError", "Character 0x%2X is invalid ASCII (above 0x7F)", c);
				else if(errors == Errors::Ignore)
					continue;
				else // replace
					croc_ex_buffer_addChar(&s, 0xFFFD);
			}
		}

		if(src != last)
			croc_ex_buffer_addStringn(&s, cast(const char*)last, src - last);

		croc_ex_buffer_finish(&s);
		return 1;
	}

	word_t _latin1EncodeInternal(CrocThread* t)
	{
		ENCODE_INTO_HEADER

		// Gonna need at most str.length characters, if all goes well
		croc_lenai(t, 2, start + str.length);

		auto destBase = croc_memblock_getData(t, 2);
		auto dest = destBase + start;
		auto src = str.ptr;

		if(str.length == strCPLen)
		{
			// It's plain ASCII, just shortcut copying it over.
			memcpy(dest, src, strCPLen * sizeof(char));
			croc_dup(t, 2);
			return 1;
		}

		auto end = src + str.length;
		auto last = src;

		while(src < end)
		{
			if(*src < 0x80)
				src++;
			else
			{
				if(src != last)
				{
					memcpy(dest, last, (src - last) * sizeof(char));
					dest += src - last;
				}

				auto c = fastDecodeUtf8Char(src);
				last = src;

				if(c <= 0xFF)
					*dest++ = c;
				else if(errors == Errors::Strict)
					croc_eh_throwStd(t, "UnicodeError", "Character U+%6X cannot be encoded as ASCII", cast(dchar)c);
				else if(errors == Errors::Ignore)
					continue;
	  			else // replace
					*(dest++) = '?';
			}
		}

		if(src != last)
		{
			memcpy(dest, last, (src - last) * sizeof(char));
			dest += src - last;
		}

		// "ignore" may have resulted in fewer characters being encoded than we allocated for
		croc_lenai(t, 2, dest - destBase);
		croc_dup(t, 2);
		return 1;
	}

	word_t _latin1DecodeInternal(CrocThread* t)
	{
		DECODE_RANGE_HEADER
		(void)errors;
		auto src = mb.ptr;
		auto end = mb.ptr + mb.length;
		auto last = src;

		CrocStrBuffer s;
		croc_ex_buffer_init(t, &s);

		while(src < end)
		{
			if(*src < 0x80)
				src++;
			else
			{
				if(src != last)
					croc_ex_buffer_addStringn(&s, cast(const char*)last, src - last);

				croc_ex_buffer_addChar(&s, cast(crocchar_t)*src++);
				last = src;
			}
		}

		if(src != last)
			croc_ex_buffer_addStringn(&s, cast(const char*)last, src - last);

		croc_ex_buffer_finish(&s);
		return 1;
	}

	word_t _utf8EncodeInternal(CrocThread* t)
	{
		ENCODE_INTO_HEADER
		(void)strCPLen;
		(void)errors;
		croc_lenai(t, 2, start + str.length);
		auto dest = croc_memblock_getData(t, 2) + start;
		memcpy(dest, str.ptr, str.length);
		croc_dup(t, 2);
		return 1;
	}

	word_t _utf8DecodeInternal(CrocThread* t)
	{
		DECODE_RANGE_HEADER

		auto src = cast(const uchar*)mb.ptr;
		auto end = cast(const uchar*)mb.ptr + mb.length;
		auto last = src;

		CrocStrBuffer s;
		croc_ex_buffer_init(t, &s);

		while(src < end)
		{
			if(*src < 0x80)
			{
				src++;
				continue;
			}

			if(src != last)
			{
				croc_ex_buffer_addStringn(&s, cast(const char*)last, src - last);
				last = src;
			}

			crocchar_t c;
			auto ok = decodeUtf8Char(src, end, c);

			if(ok == UtfError_OK)
			{
				croc_ex_buffer_addChar(&s, c);
				last = src;
			}
			else if(ok == UtfError_Truncated)
			{
				// incomplete character encoding.. stop it here
				break;
			}
			else
			{
				// Either a correctly-encoded invalid character or a bad encoding -- skip it either way
				skipBadUtf8Char(src, end);
				last = src;

				if(errors == Errors::Strict)
					croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8");
				else if(errors == Errors::Ignore)
					continue;
				else // replace
					croc_ex_buffer_addChar(&s, 0xFFFD);
			}
		}

		if(src != last)
			croc_ex_buffer_addStringn(&s, cast(const char*)last, src - last);

		croc_ex_buffer_finish(&s);
		croc_pushInt(t, cast(uchar*)src - cast(uchar*)mb.ptr); // how many bytes were consumed
		return 2;
	}

	word_t _utf16EncodeInternal(CrocThread* t)
	{
		ENCODE_INTO_HEADER
		(void)errors;

		auto toUtf16 = shouldSwap(t, 5) ? & Utf8ToUtf16<true> : Utf8ToUtf16<false>;

		// this initial sizing might not be enough.. but it's probably enough for most text. only trans-BMP chars will
		// need more room
		croc_lenai(t, 2, max(croc_len(t, 2), start + strCPLen * sizeof(wchar)));
		auto dest = wstring::n(cast(wchar*)(croc_memblock_getData(t, 2) + start), strCPLen);

		custring remaining;
		auto encoded = (*toUtf16)(str, dest, remaining);

		if(remaining.length > 0)
		{
			// Didn't have enough room.. let's allocate a little more aggressively this time
			start += encoded.length * sizeof(wchar);
			strCPLen = fastUtf8CPLength(remaining);
			croc_lenai(t, 2, start + strCPLen * sizeof(wchar) * 2);
			dest = wstring::n(cast(wchar*)(croc_memblock_getData(t, 2) + start), strCPLen);
			encoded = (*toUtf16)(remaining, dest, remaining);
			assert(remaining.length == 0);
		}

		croc_lenai(t, 2, start + encoded.length * sizeof(wchar));
		croc_dup(t, 2);
		return 1;
	}

	word_t _utf16DecodeInternal(CrocThread* t)
	{
		DECODE_RANGE_HEADER
		auto swap = shouldSwap(t, 5);
		auto toUtf8 = swap ? &Utf16ToUtf8BS : &Utf16ToUtf8;
		auto skipBadChar = swap ? &skipBadUtf16Char<true> : &skipBadUtf16Char<false>;

		mb = mb.slice(0, mb.length & ~1); // round down to lower even length, if it's an odd-sized slice

		auto src = cast(const wchar*)mb.ptr;
		auto end = src + (mb.length / 2);

		CrocStrBuffer s;
		croc_ex_buffer_init(t, &s);
		uchar buf[256];
		cwstring remaining;
		ustring output;

		while(src < end)
		{
			auto ok = (*toUtf8)(cwstring::n(src, end - src), ustring::n(buf, 256), remaining, output);

			if(ok == UtfError_OK)
			{
				croc_ex_buffer_addStringn(&s, cast(const char*)output.ptr, output.length);

				if(remaining.length)
					src = remaining.ptr;
				else
					src = end;
			}
			else if(ok == UtfError_Truncated)
			{
				// incomplete character encoding.. stop it here
				break;
			}
			else
			{
				// Either a correctly-encoded invalid character or a bad encoding -- skip it either way
				(*skipBadChar)(src, end);

				if(errors == Errors::Strict)
					croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-16");
				else if(errors == Errors::Ignore)
					continue;
				else // replace
					croc_ex_buffer_addChar(&s, 0xFFFD);
			}
		}

		croc_ex_buffer_finish(&s);
		croc_pushInt(t, cast(uchar*)src - cast(uchar*)mb.ptr); // how many bytes were consumed
		return 2;
	}

	word_t _utf32EncodeInternal(CrocThread* t)
	{
		ENCODE_INTO_HEADER
		(void)errors;
		auto toUtf32 = shouldSwap(t, 5) ? &Utf8ToUtf32<true> : &Utf8ToUtf32<false>;
		croc_lenai(t, 2, start + strCPLen * sizeof(dchar));
		auto dest = dstring::n(cast(dchar*)(croc_memblock_getData(t, 2) + start), strCPLen);
		custring remaining;
		toUtf32(str, dest, remaining);
		assert(remaining.length == 0);
		croc_dup(t, 2);
		return 1;
	}

	word_t _utf32DecodeInternal(CrocThread* t)
	{
		DECODE_RANGE_HEADER
		auto swap = shouldSwap(t, 5);
		auto toUtf8 = swap ? &Utf32ToUtf8BS : Utf32ToUtf8;
		auto skipBadChar = swap ? &skipBadUtf32Char<true> : &skipBadUtf32Char<false>;
		mb = mb.slice(0, mb.length & ~3); // round down to lower multiple-of-4 length

		auto src = cast(const dchar*)mb.ptr;
		auto end = src + (mb.length / 4);

		CrocStrBuffer s;
		croc_ex_buffer_init(t, &s);
		uchar buf[256];
		cdstring remaining;
		ustring output;

		while(src < end)
		{
			auto ok = (*toUtf8)(cdstring::n(src, end - src), ustring::n(buf, 256), remaining, output);

			if(ok == UtfError_OK)
			{
				croc_ex_buffer_addStringn(&s, cast(const char*)output.ptr, output.length);

				if(remaining.length)
					src = remaining.ptr;
				else
					src = end;
			}
			else if(ok == UtfError_Truncated)
			{
				// incomplete character encoding.. stop it here
				break;
			}
			else
			{
				// Either a correctly-encoded invalid character or a bad encoding -- skip it either way
				(*skipBadChar)(src, end);

				if(errors == Errors::Strict)
					croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-32");
				else if(errors == Errors::Ignore)
					continue;
				else // replace
					croc_ex_buffer_addChar(&s, 0xFFFD);
			}
		}

		croc_ex_buffer_finish(&s);
		croc_pushInt(t, cast(uchar*)src - cast(uchar*)mb.ptr); // how many bytes were consumed
		return 2;
	}

	const CrocRegisterFunc _globalFuncs[] =
	{
		{"asciiEncodeInternal",  4, &_asciiEncodeInternal },
		{"asciiDecodeInternal",  4, &_asciiDecodeInternal },
		{"latin1EncodeInternal", 4, &_latin1EncodeInternal},
		{"latin1DecodeInternal", 4, &_latin1DecodeInternal},
		{"utf8EncodeInternal",   4, &_utf8EncodeInternal  },
		{"utf8DecodeInternal",   4, &_utf8DecodeInternal  },
		{"utf16EncodeInternal",  5, &_utf16EncodeInternal },
		{"utf16DecodeInternal",  5, &_utf16DecodeInternal },
		{"utf32EncodeInternal",  5, &_utf32EncodeInternal },
		{"utf32DecodeInternal",  5, &_utf32DecodeInternal },
		{nullptr, 0, nullptr}
	};
	}

	void initTextLib(CrocThread* t)
	{
		uint8_t test[2] = {1, 0};
		isLittleEndian = *(cast(uint16_t*)test) == 1;

		croc_table_new(t, 0);
			croc_ex_registerFields(t, _globalFuncs);
		croc_newGlobal(t, "_texttmp");

		croc_ex_importFromString(t, "text", text_croc_text, "text.croc");

		croc_pushGlobal(t, "_G");
		croc_pushString(t, "_texttmp");
		croc_removeKey(t, -2);
		croc_popTop(t);
	}
}