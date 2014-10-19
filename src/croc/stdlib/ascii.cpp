
#include <ctype.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{
// =====================================================================================================================
// Helpers

crocstr _checkAsciiString(CrocThread* t, word idx)
{
	croc_ex_checkStringParam(t, idx);
	auto obj = getStringObj(Thread::from(t), idx);

	if(obj->length != obj->cpLength)
		croc_eh_throwStd(t, "ValueError", "Parameter %" CROC_SSIZE_T_FORMAT " is not an ASCII string", idx);

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

// =====================================================================================================================
// Global funcs

const StdlibRegisterInfo _isAscii_info =
{
	Docstr(DFunc("isAscii") DParam("val", "string")
	R"(\returns a bool of whether \tt{val} is an ASCII string (that is, all its codepoints are below U+000080).)"),

	"isAscii", 1
};

word_t _isAscii(CrocThread* t)
{
	croc_ex_checkStringParam(t, 1);
	auto str = getStringObj(Thread::from(t), 1);

	// Take advantage of the fact that we're using UTF-8... ASCII strings will have a codepoint length
	// exactly equal to their data length
	croc_pushBool(t, str->length == str->cpLength);
	return 1;
}

const StdlibRegisterInfo _icompare_info =
{
	Docstr(DFunc("icompare") DParam("str1", "string") DParam("str2", "string")
	R"(Compares two ASCII strings in a case-insensitive manner.

	This function treats lower- and uppercase ASCII letters as comparing equal. For instance, "foo", "Foo", and "FOO"
	will all compare equal.

    \returns a negative \tt{int} if \tt{str1} compares before \tt{str2}, a positive \tt{int} if \tt{str1} compares after
	\tt{str2}, and 0 if they compare equal.

	\throws[ValueError] if either string is not ASCII.)"),

	"icompare", 2
};

word_t _icompare(CrocThread* t)
{
	auto s1 = _checkAsciiString(t, 1);
	auto s2 = _checkAsciiString(t, 2);
	croc_pushInt(t, _icmp(s1, s2));
	return 1;
}

const StdlibRegisterInfo _ifind_info =
{
	Docstr(DFunc("ifind") DParam("str", "string") DParam("sub", "string") DParamD("start", "int", "0")
	R"(Searches for an occurence of \tt{sub} in \tt{this}, but searches in a case-insensitive manner.

	The search starts from \tt{start} (which defaults to the first character) and goes right. If \tt{sub} is found, this
	function returns the integer index of the occurrence in the string, with 0 meaning the first character. Otherwise,
	if \tt{sub} cannot be found, \tt{#this} is returned.

	\tt{start} can be negative, in which case it's treated as an index from the end of the string.

	\throws[ValueError] if either \tt{str} or \tt{sub} are not ASCII.
	\throws[BoundsError] if \tt{start} is invalid.)"),

	"ifind", 3
};

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
	auto start = croc_ex_optIndexParam(t, 3, src.length, "start", 0);

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

const StdlibRegisterInfo _irfind_info =
{
	Docstr(DFunc("irfind") DParam("str", "string") DParam("sub", "string") DParamD("start", "int", "#str - 1")
	R"(Reverse case-insensitive find. Works similarly to \tt{ifind}, but the search starts with the character at
	\tt{start} (which defaults to the last character) and goes \em{left}.

	If \tt{sub} is found, this function returns the integer index of the occurrence in the string, with 0 meaning the
	first character. Otherwise, if \tt{sub} cannot be found, \tt{#this} is returned.

	\tt{start} can be negative, in which case it's treated as an index from the end of the string.

	\throws[ValueError] if either \tt{str} or \tt{sub} are not ASCII.
	\throws[BoundsError] if \tt{start} is invalid.)"),

	"irfind", 3
};

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
	auto start = croc_ex_optIndexParam(t, 3, src.length, "start", src.length - 1);

	// Search
	auto maxIdx = src.length - pat.length;
	auto firstChar = tolower(pat[0]);

	if(cast(uword)start > maxIdx)
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

const StdlibRegisterInfo _toLower_info =
{
	Docstr(DFunc("toLower") DParam("val", "string")
	R"(Converts a string to lowercase.

	\returns a new string with any uppercase letters converted to lowercase. Non-uppercase letters and non-letters are
	not affected.

	\throws[ValueError] if \tt{val} is not ASCII.)"),

	"toLower", 1
};

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

const StdlibRegisterInfo _toUpper_info =
{
	Docstr(DFunc("toUpper") DParam("val", "string")
	R"(Converts a string to uppercase.

	\returns a new string with any lowercase letters converted to uppercase. Non-lowercase letters and non-letters are
	not affected.

	\throws[ValueError] if \tt{val} is not ASCII.)"),

	"toUpper", 1
};

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

const StdlibRegisterInfo _istartsWith_info =
{
	Docstr(DFunc("istartsWith") DParam("str", "string") DParam("sub", "string")
	R"(Checks if \tt{str} begins with the substring \tt{other} in a case-insensitive manner.

	\returns a bool.

	\throws[ValueError] if either \tt{str} or \tt{sub} are not ASCII.)"),

	"istartsWith", 2
};

word_t _istartsWith(CrocThread* t)
{
	auto s1 = _checkAsciiString(t, 1);
	auto s2 = _checkAsciiString(t, 2);
	croc_pushBool(t, s1.length >= s2.length && _icmp(s1.slice(0, s2.length), s2) == 0);
	return 1;
}

const StdlibRegisterInfo _iendsWith_info =
{
	Docstr(DFunc("iendsWith") DParam("str", "string") DParam("sub", "string")
	R"(Checks if \tt{str} ends with the substring \tt{other} in a case-insensitive manner.

	\returns a bool.

	\throws[ValueError] if either \tt{str} or \tt{sub} are not ASCII.)"),

	"iendsWith", 2
};

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
		auto idx = croc_ex_optIndexParam(t, 2, str.length, "character", 0);\
		croc_pushBool(t, cast(bool)func(str[cast(uword)idx]));\
		return 1;\
	}

const StdlibRegisterInfo _isAlpha_info =
{
	Docstr(DFunc("isAlpha") DParam("c", "string") DParamD("idx", "int", "0")
	R"(These functions all work the same way: they classify a character in a string.

	\blist
		\li \tt{isAlpha} tests if the character is a lower- or upper-case letter.
		\li \tt{isAlnum} tests if the character is a lower- or upper-case letter or a digit (0-9).
		\li \tt{isLower} tests if the character is a lower-case letter.
		\li \tt{isUpper} tests if the character is an upper-case letter.
		\li \tt{isDigit} tests if the character is a digit (0-9).
		\li \tt{isHexDigit} tests if the character is a hexadecimal digit (0-9, a-f, A-F).
		\li \tt{isCtrl} tests if the character is a control character (less than ASCII 32, or ASCII 127).
		\li \tt{isPunct} tests if the character is a punctuation mark.
		\li \tt{isSpace} tests if the character is whitespace (space, \\t, \\f, \\v, \\r, or \\n).
		\li \tt{isGraph} tests if the character has a graphical representation (not a control character, and not space).
		\li \tt{isPrint} tests if the character is printable (same as isGraph, but includes space; inversion of isCtrl).
	\endlist

	\param[c] is the ASCII string to look in.
	\param[idx] is the index of the character in \tt{c} to text. Can be negative.

	\returns \tt{true} if \tt{c[idx]} is in that class of character; \tt{false} otherwise.

	\throws[ValueError] if \tt{c} is not ASCII, or if \tt{#c == 0}.
	\throws[BoundsError] if \tt{idx} is invalid.)"),

	"isAlpha", 2
};

MAKE_IS(_isAlpha, isalpha)

const StdlibRegisterInfo _isAlNum_info =
{
	Docstr(DFunc("isAlNum") DParam("c", "string") DParamD("idx", "int", "0")
	R"(ditto)"),

	"isAlNum", 2
};

MAKE_IS(_isAlNum, isalnum)

const StdlibRegisterInfo _isLower_info =
{
	Docstr(DFunc("isLower") DParam("c", "string") DParamD("idx", "int", "0")
	R"(ditto)"),

	"isLower", 2
};

MAKE_IS(_isLower, islower)

const StdlibRegisterInfo _isUpper_info =
{
	Docstr(DFunc("isUpper") DParam("c", "string") DParamD("idx", "int", "0")
	R"(ditto)"),

	"isUpper", 2
};

MAKE_IS(_isUpper, isupper)

const StdlibRegisterInfo _isDigit_info =
{
	Docstr(DFunc("isDigit") DParam("c", "string") DParamD("idx", "int", "0")
	R"(ditto)"),

	"isDigit", 2
};

MAKE_IS(_isDigit, isdigit)

const StdlibRegisterInfo _isHexDigit_info =
{
	Docstr(DFunc("isHexDigit") DParam("c", "string") DParamD("idx", "int", "0")
	R"(ditto)"),

	"isHexDigit", 2
};

MAKE_IS(_isHexDigit, isxdigit)

const StdlibRegisterInfo _isCtrl_info =
{
	Docstr(DFunc("isCtrl") DParam("c", "string") DParamD("idx", "int", "0")
	R"(ditto)"),

	"isCtrl", 2
};

MAKE_IS(_isCtrl, iscntrl)

const StdlibRegisterInfo _isPunct_info =
{
	Docstr(DFunc("isPunct") DParam("c", "string") DParamD("idx", "int", "0")
	R"(ditto)"),

	"isPunct", 2
};

MAKE_IS(_isPunct, ispunct)

const StdlibRegisterInfo _isSpace_info =
{
	Docstr(DFunc("isSpace") DParam("c", "string") DParamD("idx", "int", "0")
	R"(ditto)"),

	"isSpace", 2
};

MAKE_IS(_isSpace, isspace)

const StdlibRegisterInfo _isGraph_info =
{
	Docstr(DFunc("isGraph") DParam("c", "string") DParamD("idx", "int", "0")
	R"(ditto)"),

	"isGraph", 2
};

MAKE_IS(_isGraph, isgraph)

const StdlibRegisterInfo _isPrint_info =
{
	Docstr(DFunc("isPrint") DParam("c", "string") DParamD("idx", "int", "0")
	R"(ditto)"),

	"isPrint", 2
};

MAKE_IS(_isPrint, isprint)

const StdlibRegister _globalFuncs[] =
{
	_DListItem(_isAscii),
	_DListItem(_icompare),
	_DListItem(_ifind),
	_DListItem(_irfind),
	_DListItem(_toLower),
	_DListItem(_toUpper),
	_DListItem(_istartsWith),
	_DListItem(_iendsWith),
	_DListItem(_isAlpha),
	_DListItem(_isAlNum),
	_DListItem(_isLower),
	_DListItem(_isUpper),
	_DListItem(_isDigit),
	_DListItem(_isHexDigit),
	_DListItem(_isCtrl),
	_DListItem(_isPunct),
	_DListItem(_isSpace),
	_DListItem(_isGraph),
	_DListItem(_isPrint),
	_DListEnd
};

	word loader(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);
		return 0;
	}
	}

	void initAsciiLib(CrocThread* t)
	{
		registerModule(t, "ascii", &loader);
		croc_pushGlobal(t, "ascii");
#ifdef CROC_BUILTIN_DOCS
		CrocDoc doc;
		croc_ex_doc_init(t, &doc, __FILE__);
		croc_ex_doc_push(&doc,
		DModule("ascii")
		R"(This library provides string manipulation and character classification functions which are restricted to the
		ASCII subset of Unicode. Croc's strings are Unicode, but full Unicode implementations of the functions in this
		library would impose a very weighty dependency on a Unicode library such as ICU. As such, this library has been
		provided as a lightweight alternative, useful for quick programs and situations where perfect multilingual
		string support is not needed.

		Note that these functions (except for \link{isAscii}) will only work on ASCII strings. If passed strings which
		contain codepoints above U+00007F, they will throw an exception.)");
			docFields(&doc, _globalFuncs);
		croc_ex_doc_pop(&doc, -1);
		croc_ex_doc_finish(&doc);
#endif
		croc_popTop(t);
	}
}