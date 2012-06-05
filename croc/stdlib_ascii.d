/******************************************************************************
This module contains the 'ascii' standard library.

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

module croc.stdlib_ascii;

import tango.math.Math;
import tango.stdc.ctype;

alias tango.stdc.ctype.tolower ctolower;
alias tango.stdc.ctype.toupper ctoupper;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.stdlib_utils;
import croc.types;
import croc.utils;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initAsciiLib(CrocThread* t)
{
	makeModule(t, "ascii", function uword(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);
		return 0;
	});

	importModule(t, "ascii");

	version(CrocBuiltinDocs)
	{
		scope doc = new CrocDoc(t, __FILE__);
		doc.push(Docs("module", "ascii",
		`This library provides string manipulation and character classification functions which are restricted to
		the ASCII subset of Unicode. Croc's strings are Unicode, but full Unicode implementations of the functions in
		this library would impose a very weighty dependency on a Unicode library such as ICU. As such, this library
		has been provided as a lightweight alternative, useful for quick programs and situations where perfect
		multilingual string support is not needed.

		Note that these functions (except for \link{isAscii}) will only work on ASCII strings. If passed strings or
		characters which contain codepoints above U+0007F, they will throw an exception.`));

		docFields(t, doc, _globalFuncDocs);
		doc.pop(-1);
	}

	pop(t);
}


// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

// ===================================================================================================================================
// Global funcs

const RegisterFunc[] _globalFuncs =
[
	{"isAscii",      &_isAscii,      maxParams: 1},
	{"icompare",     &_icompare,     maxParams: 2},
	{"ifind",        &_ifind,        maxParams: 3},
	{"irfind",       &_irfind,       maxParams: 3},
	{"toLower",      &_toLower,      maxParams: 1},
	{"toUpper",      &_toUpper,      maxParams: 1},
	{"istartsWith",  &_istartsWith,  maxParams: 2},
	{"iendsWith",    &_iendsWith,    maxParams: 2}
];

uword _isAscii(CrocThread* t)
{
	checkAnyParam(t, 1);

	if(isString(t, 1))
	{
		auto str = getStringObj(t, 1);
		// Take advantage of the fact that we're using UTF-8... ASCII strings will have a codepoint length
		// exactly equal to their data length
		pushBool(t, str.length == str.cpLength);
	}
	else if(isChar(t, 1))
		pushBool(t, getChar(t, 1) <= 0x7F);
	else
		paramTypeError(t, 1, "char|string");

	return 1;
}

uword _icompare(CrocThread* t)
{
	auto s1 = _checkAsciiString(t, 1);
	auto s2 = _checkAsciiString(t, 2);
	pushInt(t, _icmp(s1, s2));
	return 1;
}

uword _ifind(CrocThread* t)
{
	// Source (search) string
	auto src = _checkAsciiString(t, 1);

	// Pattern (searched) string/char
	checkAnyParam(t, 2);

	char[1] buf = void;
	char[] pat;

	if(isString(t, 2))
		pat = _checkAsciiString(t, 2);
	else if(isChar(t, 2))
	{
		buf[0] = _checkAsciiChar(t, 2);
		pat = buf[];
	}
	else
		paramTypeError(t, 2, "char|string");

	// Start index
	auto start = optIntParam(t, 3, 0);

	if(start < 0)
	{
		start += src.length;

		if(start < 0)
			throwStdException(t, "BoundsException", "Invalid start index {}", start);
	}

	if(start > (src.length - pat.length))
	{
		pushInt(t, src.length);
		return 1;
	}

	// Search
	auto maxIdx = src.length - pat.length;
	auto firstChar = ctolower(pat[0]);

	for(auto i = cast(uword)start; i < maxIdx; i++)
	{
		auto ch = ctolower(src[i]);

		if(ch == firstChar && _icmp(src[i .. i + pat.length], pat) == 0)
		{
			pushInt(t, i);
			return 1;
		}
	}

	pushInt(t, src.length);
	return 1;
}

uword _irfind(CrocThread* t)
{
	// Source (search) string
	auto src = _checkAsciiString(t, 1);

	// Pattern (searched) string/char
	checkAnyParam(t, 2);

	char[1] buf = void;
	char[] pat;

	if(isString(t, 2))
		pat = _checkAsciiString(t, 2);
	else if(isChar(t, 2))
	{
		buf[0] = _checkAsciiChar(t, 2);
		pat = buf[];
	}
	else
		paramTypeError(t, 2, "char|string");

	// Start index
	auto start = optIntParam(t, 3, src.length);
	
	if(start > src.length)
		throwStdException(t, "BoundsException", "Invalid start index: {}", start);

	if(start < 0)
	{
		start += src.length;

		if(start < 0)
			throwStdException(t, "BoundsException", "Invalid start index {}", start);
	}

	if(start == 0)
	{
		pushInt(t, src.length);
		return 1;
	}

	// Search
	auto maxIdx = src.length - pat.length;
	auto firstChar = ctolower(pat[0]);
	
	if(start > maxIdx)
		start = maxIdx;

	for(auto i = cast(uword)start; ; i--)
	{
		auto ch = ctolower(src[i]);

		if(ch == firstChar && _icmp(src[i .. i + pat.length], pat) == 0)
		{
			pushInt(t, i);
			return 1;
		}

		if(i == 0)
			break;
	}

	pushInt(t, src.length);
	return 1;
}

uword _toLower(CrocThread* t)
{
	checkAnyParam(t, 1);
	
	if(isString(t, 1))
	{
		auto src = _checkAsciiString(t, 1);
		auto buf = StrBuffer(t);

		foreach(c; src)
			buf.addChar(ctolower(c));

		buf.finish();
	}
	else if(isChar(t, 1))
		pushChar(t, ctolower(_checkAsciiChar(t, 1)));
	else
		paramTypeError(t, 1, "char|string");

	return 1;
}

uword _toUpper(CrocThread* t)
{
	checkAnyParam(t, 1);
	
	if(isString(t, 1))
	{
		auto src = _checkAsciiString(t, 1);
		auto buf = StrBuffer(t);
		
		foreach(c; src)
			buf.addChar(ctoupper(c));

		buf.finish();
	}
	else if(isChar(t, 1))
		pushChar(t, ctoupper(_checkAsciiChar(t, 1)));
	else
		paramTypeError(t, 1, "char|string");

	return 1;
}

uword _istartsWith(CrocThread* t)
{
	auto s1 = _checkAsciiString(t, 1);
	auto s2 = _checkAsciiString(t, 2);

	if(s2.length > s1.length)
	{
		pushBool(t, false);
		return 1;
	}

	pushBool(t, _icmp(s1[0 .. s2.length], s2) == 0);
	return 1;
}

uword _iendsWith(CrocThread* t)
{
	auto s1 = _checkAsciiString(t, 1);
	auto s2 = _checkAsciiString(t, 2);

	if(s2.length > s1.length)
	{
		pushBool(t, false);
		return 1;
	}

	pushBool(t, _icmp(s1[$ - s2.length .. $], s2) == 0);
	return 1;
}

// ===================================================================================================================================
// Helpers

char[] _checkAsciiString(CrocThread* t, word idx)
{
	auto ret = checkStringParam(t, idx);
	auto obj = getStringObj(t, idx);

	if(obj.length != obj.cpLength)
		throwStdException(t, "ValueException", "Parameter {} is not an ASCII string", idx);
	
	return ret;
}

char _checkAsciiChar(CrocThread* t, word idx)
{
	auto ret = checkCharParam(t, idx);
	
	if(ret > 0x7F)
		throwStdException(t, "ValueException", "Parameter {} is not an ASCII character", idx);
		
	return ret;
}

int _icmp(char[] s1, char[] s2)
{
	auto len = min(s1.length, s2.length);
	auto a = s1[0 .. len];
	auto b = s2[0 .. len];

	foreach(i, c; a)
	{
		auto cmp = Compare3(ctolower(c), ctolower(b[i]));

		if(cmp != 0)
			return cmp;
	}

	return Compare3(s1.length, s2.length);
}

version(CrocBuiltinDocs)
{
	const Docs[] _globalFuncDocs =
	[
		{kind: "function", name: "isAscii", docs:
		`Checks to see if the given \tt{char} or \tt{string} is ASCII.

		If \tt{val} is a \tt{char}, it is ASCII if it's below codepoint U+00080.

		If \tt{val} is a \tt{string}, it is ASCII if all of its characters are below codepoint U+00080.`,
		params: [Param("val", "char|string")]},

		{kind: "function", name: "icompare", docs:
		`Compares two ASCII strings in a case-insensitive manner.

		This function treats lower- and uppercase ASCII letters as comparing equal. For instance, "foo", "Foo", and "FOO" will
		all compare equal.

		\throws[exceptions.ValueException] if either string is not ASCII.`,
		params: [Param("str1", "string"), Param("str2", "string")]},

		{kind: "function", name: "ifind", docs:
		`The same as \link{find}, but case-insensitive.`,
		params: [Param("sub", "string|char"), Param("start", "int", "0")]},

		{kind: "function", name: "irfind", docs:
		`The same as \link{rfind}, but case-insensitive.`,
		params: [Param("sub", "string|char"), Param("start", "int", "#s")]},

		{kind: "function", name: "toLower", docs:
		`\returns a new string with any uppercase letters converted to lowercase. Non-uppercase letters and non-letters are not
		affected.`},

		{kind: "function", name: "toUpper", docs:
		`\returns a new string with any lowercase letters converted to uppercase. Non-lowercase letters and non-letters are not
		affected.`},

		{kind: "function", name: "istartsWith", docs:
		`\returns a bool of whether or not \tt{s} starts with the substring \tt{other}. This is case-insensitive.`,
		params: [Param("other", "string")]},

		{kind: "function", name: "iendsWith", docs:
		`\returns a bool of whether or not \tt{s} ends with the substring \tt{other}. This is case-insensitive.`,
		params: [Param("other", "string")]}
	];
}