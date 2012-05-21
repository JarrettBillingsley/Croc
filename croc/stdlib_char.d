/******************************************************************************
This module contains the 'char' standard library.

License:
Copyright (c) 2008 Jarrett Billingsley

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

module croc.stdlib_char;

import tango.stdc.ctype;
import Uni = tango.text.Unicode;
import Utf = tango.text.convert.Utf;

import croc.api_interpreter;
import croc.ex;
import croc.stdlib_utils;
import croc.types;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initCharLib(CrocThread* t)
{
	newNamespace(t, "char");
		registerFields(t, _methodFuncs);

	version(CrocBuiltinDocs)
	{
		scope doc = new CrocDoc(t, __FILE__);
		doc.push(Docs("module", "Character Library",
		`The character library provides functionality for classifying and transforming individual
		characters. These functions are all accessed as methods of character values.`));

		docFields(t, doc, _methodFuncDocs);
		doc.pop(-1);
	}

	setTypeMT(t, CrocValue.Type.Char);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

const RegisterFunc[] _methodFuncs =
[
	{"toLower",    &_toLower,    maxParams: 0},
	{"toUpper",    &_toUpper,    maxParams: 0},
	{"isAlpha",    &_isAlpha,    maxParams: 0},
	{"isAlNum",    &_isAlNum,    maxParams: 0},
	{"isLower",    &_isLower,    maxParams: 0},
	{"isUpper",    &_isUpper,    maxParams: 0},
	{"isDigit",    &_isDigit,    maxParams: 0},
	{"isCtrl",     &_isCtrl,     maxParams: 0},
	{"isPunct",    &_isPunct,    maxParams: 0},
	{"isSpace",    &_isSpace,    maxParams: 0},
	{"isHexDigit", &_isHexDigit, maxParams: 0},
	{"isAscii",    &_isAscii,    maxParams: 0},
	{"isValid",    &_isValid,    maxParams: 0}
];

uword _toLower(CrocThread* t)
{
	dchar[4] outbuf = void;
	dchar c = checkCharParam(t, 0);
	pushChar(t, safeCode(t, Uni.toLower((&c)[0 .. 1], outbuf)[0]));
	return 1;
}

uword _toUpper(CrocThread* t)
{
	dchar[4] outbuf = void;
	dchar c = checkCharParam(t, 0);
	pushChar(t, safeCode(t, Uni.toUpper((&c)[0 .. 1], outbuf)[0]));
	return 1;
}

uword _isAlpha(CrocThread* t)
{
	pushBool(t, Uni.isLetter(checkCharParam(t, 0)));
	return 1;
}

uword _isAlNum(CrocThread* t)
{
	pushBool(t, Uni.isLetterOrDigit(checkCharParam(t, 0)));
	return 1;
}

uword _isLower(CrocThread* t)
{
	pushBool(t, Uni.isLower(checkCharParam(t, 0)));
	return 1;
}

uword _isUpper(CrocThread* t)
{
	pushBool(t, Uni.isUpper(checkCharParam(t, 0)));
	return 1;
}

uword _isDigit(CrocThread* t)
{
	pushBool(t, Uni.isDigit(checkCharParam(t, 0)));
	return 1;
}

uword _isCtrl(CrocThread* t)
{
	pushBool(t, cast(bool)iscntrl(checkCharParam(t, 0)));
	return 1;
}

uword _isPunct(CrocThread* t)
{
	pushBool(t, cast(bool)ispunct(checkCharParam(t, 0)));
	return 1;
}

uword _isSpace(CrocThread* t)
{
	pushBool(t, cast(bool)isspace(checkCharParam(t, 0)));
	return 1;
}

uword _isHexDigit(CrocThread* t)
{
	pushBool(t, cast(bool)isxdigit(checkCharParam(t, 0)));
	return 1;
}

uword _isAscii(CrocThread* t)
{
	pushBool(t, checkCharParam(t, 0) <= 0x7f);
	return 1;
}

uword _isValid(CrocThread* t)
{
	pushBool(t, Utf.isValid(checkCharParam(t, 0)));
	return 1;
}

version(CrocBuiltinDocs)
{
	const Docs[] _methodFuncDocs =
	[
		{kind: "function", name: "c.toUpper", docs:
		`\returns : If c is a lowercase letter, returns the uppercase version of the letter. Otherwise, just
		returns the character itself.`,
		params: []},

		{kind: "function", name: "c.isAlpha", docs:
		`\returns \tt{true} if c is an alphabetic character; \tt{false} otherwise.`,
		params: []},

		{kind: "function", name: "c.isAlNum", docs:
		`\returns \tt{true} if c is an alphanumeric character; \tt{false} otherwise.`,
		params: []},

		{kind: "function", name: "c.isLower", docs:
		`\returns \tt{true} if c is a lowercase alphabetic character; \tt{false} otherwise.`,
		params: []},

		{kind: "function", name: "c.isUpper", docs:
		`\returns \tt{true} if c is an uppercase alphabetic character; \tt{false} otherwise.`,
		params: []},

		{kind: "function", name: "c.isDigit", docs:
		`\returns \tt{true} if c is a decimal digit (0 - 9); \tt{false} otherwise.`,
		params: []},

		{kind: "function", name: "c.isCtrl", docs:
		`\returns \tt{true} if c is a control character (characters 0x0 to 0x1f and character 0x7f); \tt{false} otherwise.`,
		params: []},

		{kind: "function", name: "c.isPunct", docs:
		`Returns \tt{true} if c is a punctuation character; \tt{false} otherwise.`,
		params: []},

		{kind: "function", name: "c.isSpace", docs:
		`Returns \tt{true} if c is a whitespace character; \tt{false} otherwise.`,
		params: []},

		{kind: "function", name: "c.isHexDigit", docs:
		`Returns \tt{true} if c is a hexadecimal digit (0 - 9, A - F, a - f); \tt{false} otherwise.`,
		params: []},

		{kind: "function", name: "c.isAscii", docs:
		`Returns \tt{true} if c is an ASCII character (<= 0x7f); \tt{false} otherwise.`,
		params: []},

		{kind: "function", name: "c.isValid", docs:
		`Returns \tt{true} if c is a valid Unicode character; \tt{false} otherwise.`,
		params: []}
	];
}