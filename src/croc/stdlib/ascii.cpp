
#include <ctype.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
	// ===================================================================================================================================
	// Helpers

	crocstr _checkAsciiString(CrocThread* t, word idx)
	{
		croc_ex_checkStringParam(t, idx);
		auto obj = getStringObj(Thread::from(t), idx);

		if(obj->length != obj->cpLength)
			croc_eh_throwStd(t, "ValueError", "Parameter %d is not an ASCII string", idx);

		return obj->toDArray();
	}

	int _icmp(crocstr s1, crocstr s2)
	{
		auto len = min(s1.length, s2.length);
		auto a = s1.slice(0, len);
		auto b = s2.slice(0, len);
		uword i = 0;

		for(auto c: a)
		{
			auto cmp = Compare3(tolower(c), tolower(b[i++]));

			if(cmp != 0)
				return cmp;
		}

		return Compare3(s1.length, s2.length);
	}

	// ===================================================================================================================================
	// Helpers

	word_t _isAscii(CrocThread* t)
	{
		croc_ex_checkStringParam(t, 1);
		auto str = getStringObj(Thread::from(t), 1);

		// Take advantage of the fact that we're using UTF-8... ASCII strings will have a codepoint length
		// exactly equal to their data length
		croc_pushBool(t, str->length == str->cpLength);
		return 1;
	}

	word_t _icompare(CrocThread* t)
	{
		auto s1 = _checkAsciiString(t, 1);
		auto s2 = _checkAsciiString(t, 2);
		croc_pushInt(t, _icmp(s1, s2));
		return 1;
	}

	word_t _ifind(CrocThread* t)
	{
		// Source (search) string
		auto src = _checkAsciiString(t, 1);

		// Pattern (searched) string/char
		auto pat = _checkAsciiString(t, 2);

		if(src.length < pat.length)
		{
			croc_pushInt(t, src.length);
			return 1;
		}

		// Start index
		auto start = croc_ex_optIntParam(t, 3, 0);

		if(start < 0)
			start += src.length;

		if(start < 0 || start >= src.length)
			croc_eh_throwStd(t, "BoundsError", "Invalid start index %" CROC_INTEGER_FORMAT, start);

		// Search
		auto maxIdx = src.length - pat.length;
		auto firstChar = tolower(pat[0]);

		for(auto i = cast(uword)start; i < maxIdx; i++)
		{
			auto ch = tolower(src[i]);

			if(ch == firstChar && _icmp(src.slice(i, i + pat.length), pat) == 0)
			{
				croc_pushInt(t, i);
				return 1;
			}
		}

		croc_pushInt(t, src.length);
		return 1;
	}

	word_t _irfind(CrocThread* t)
	{
		// Source (search) string
		auto src = _checkAsciiString(t, 1);

		// Pattern (searched) string/char
		auto pat = _checkAsciiString(t, 2);

		if(src.length < pat.length)
		{
			croc_pushInt(t, src.length);
			return 1;
		}

		// Start index
		auto start = croc_ex_optIntParam(t, 3, src.length - 1);

		if(start < 0)
			start += src.length;

		if(start < 0 || start >= src.length)
			croc_eh_throwStd(t, "BoundsError", "Invalid start index: %" CROC_INTEGER_FORMAT, start);

		// Search
		auto maxIdx = src.length - pat.length;
		auto firstChar = tolower(pat[0]);

		if(start > maxIdx)
			start = maxIdx;

		for(auto i = cast(uword)start; ; i--)
		{
			auto ch = tolower(src[i]);

			if(ch == firstChar && _icmp(src.slice(i, i + pat.length), pat) == 0)
			{
				croc_pushInt(t, i);
				return 1;
			}

			if(i == 0)
				break;
		}

		croc_pushInt(t, src.length);
		return 1;
	}

	word_t _toLower(CrocThread* t)
	{
		auto src = _checkAsciiString(t, 1);
		CrocStrBuffer buf;
		croc_ex_buffer_init(t, &buf);
		auto dest = croc_ex_buffer_prepare(&buf, src.length);

		for(auto c: src)
			*dest++ = tolower(c);

		croc_ex_buffer_addPrepared(&buf);
		croc_ex_buffer_finish(&buf);
		return 1;
	}

	word_t _toUpper(CrocThread* t)
	{
		auto src = _checkAsciiString(t, 1);
		CrocStrBuffer buf;
		croc_ex_buffer_init(t, &buf);
		auto dest = croc_ex_buffer_prepare(&buf, src.length);

		for(auto c: src)
			*dest++ = toupper(c);

		croc_ex_buffer_addPrepared(&buf);
		croc_ex_buffer_finish(&buf);
		return 1;
	}

	word_t _istartsWith(CrocThread* t)
	{
		auto s1 = _checkAsciiString(t, 1);
		auto s2 = _checkAsciiString(t, 2);
		croc_pushBool(t, s1.length >= s2.length && _icmp(s1.slice(0, s2.length), s2) == 0);
		return 1;
	}

	word_t _iendsWith(CrocThread* t)
	{
		auto s1 = _checkAsciiString(t, 1);
		auto s2 = _checkAsciiString(t, 2);
		croc_pushBool(t, s1.length >= s2.length && _icmp(s1.slice(s1.length - s2.length, s1.length), s2) == 0);
		return 1;
	}

#define MAKE_IS(name, func)\
	word_t name(CrocThread* t)\
	{\
		auto str = _checkAsciiString(t, 1);\
		auto idx = croc_ex_optIntParam(t, 2, 0);\
\
		if(str.length == 0)\
			croc_eh_throwStd(t, "ValueError", "String must be at least one character long");\
\
		if(idx < 0)\
			idx += str.length;\
\
		if(idx < 0 || idx >= str.length)\
			croc_eh_throwStd(t, "BoundsError", "Invalid index %" CROC_INTEGER_FORMAT " for string of length %u",\
				idx, str.length);\
\
		croc_pushBool(t, cast(bool)func(str[cast(uword)idx]));\
		return 1;\
	}

	MAKE_IS(_isAlpha,    isalpha)
	MAKE_IS(_isAlNum,    isalnum)
	MAKE_IS(_isLower,    islower)
	MAKE_IS(_isUpper,    isupper)
	MAKE_IS(_isDigit,    isdigit)
	MAKE_IS(_isHexDigit, isxdigit)
	MAKE_IS(_isCtrl,     iscntrl)
	MAKE_IS(_isPunct,    ispunct)
	MAKE_IS(_isSpace,    isspace)

	const CrocRegisterFunc _globalFuncs[] =
	{
		{"isAscii",      1, &_isAscii    },
		{"icompare",     2, &_icompare   },
		{"ifind",        3, &_ifind      },
		{"irfind",       3, &_irfind     },
		{"toLower",      1, &_toLower    },
		{"toUpper",      1, &_toUpper    },
		{"istartsWith",  2, &_istartsWith},
		{"iendsWith",    2, &_iendsWith  },
		{"isAlpha",      2, &_isAlpha    },
		{"isAlNum",      2, &_isAlNum    },
		{"isLower",      2, &_isLower    },
		{"isUpper",      2, &_isUpper    },
		{"isDigit",      2, &_isDigit    },
		{"isHexDigit",   2, &_isHexDigit },
		{"isCtrl",       2, &_isCtrl     },
		{"isPunct",      2, &_isPunct    },
		{"isSpace",      2, &_isSpace    },
		{nullptr, 0, nullptr}
	};

	word loader(CrocThread* t)
	{
		croc_ex_registerGlobals(t, _globalFuncs);
		return 0;
	}
	}

	void initAsciiLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "ascii", &loader);
		croc_ex_import(t, "ascii");
	}
}