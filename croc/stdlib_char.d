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

struct CharLib
{
static:
	public void init(CrocThread* t)
	{
		version(CrocBuiltinDocs)
		{
			scope doc = new CrocDoc(t, __FILE__);
			doc.push(Docs("module", "Character Library",
			"The character library provides functionality for classifying and transforming individual
			characters. These functions are all accessed as methods of character values."));
		}

		newNamespace(t, "char");
			mixin(RegisterField!(0, "toLower"));
			mixin(RegisterField!(0, "toUpper"));
			mixin(RegisterField!(0, "isAlpha"));
			mixin(RegisterField!(0, "isAlNum"));
			mixin(RegisterField!(0, "isLower"));
			mixin(RegisterField!(0, "isUpper"));
			mixin(RegisterField!(0, "isDigit"));
			mixin(RegisterField!(0, "isCtrl"));
			mixin(RegisterField!(0, "isPunct"));
			mixin(RegisterField!(0, "isSpace"));
			mixin(RegisterField!(0, "isHexDigit"));
			mixin(RegisterField!(0, "isAscii"));
			mixin(RegisterField!(0, "isValid"));

			version(CrocBuiltinDocs)
				doc.pop(-1);

		setTypeMT(t, CrocValue.Type.Char);
	}

	version(CrocBuiltinDocs) Docs toLower_docs = {kind: "function", name: "c.toLower", docs:
	"If c is an uppercase letter, returns the lowercase version of the letter. Otherwise, just
	returns the character itself.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword toLower(CrocThread* t)
	{
		dchar[4] outbuf = void;
		dchar c = checkCharParam(t, 0);
		pushChar(t, safeCode(t, Uni.toLower((&c)[0 .. 1], outbuf)[0]));
		return 1;
	}

	version(CrocBuiltinDocs) Docs toUpper_docs = {kind: "function", name: "c.toUpper", docs:
	"If c is a lowercase letter, returns the uppercase version of the letter. Otherwise, just
	returns the character itself.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword toUpper(CrocThread* t)
	{
		dchar[4] outbuf = void;
		dchar c = checkCharParam(t, 0);
		pushChar(t, safeCode(t, Uni.toUpper((&c)[0 .. 1], outbuf)[0]));
		return 1;
	}

	version(CrocBuiltinDocs) Docs isAlpha_docs = {kind: "function", name: "c.isAlpha", docs:
	"Returns `true` if c is an alphabetic character; `false` otherwise.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword isAlpha(CrocThread* t)
	{
		pushBool(t, Uni.isLetter(checkCharParam(t, 0)));
		return 1;
	}

	version(CrocBuiltinDocs) Docs isAlNum_docs = {kind: "function", name: "c.isAlNum", docs:
	"Returns `true` if c is an alphanumeric character; `false` otherwise.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword isAlNum(CrocThread* t)
	{
		pushBool(t, Uni.isLetterOrDigit(checkCharParam(t, 0)));
		return 1;
	}

	version(CrocBuiltinDocs) Docs isLower_docs = {kind: "function", name: "c.isLower", docs:
	"Returns `true` if c is a lowercase alphabetic character; `false` otherwise.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword isLower(CrocThread* t)
	{
		pushBool(t, Uni.isLower(checkCharParam(t, 0)));
		return 1;
	}

	version(CrocBuiltinDocs) Docs isUpper_docs = {kind: "function", name: "c.isUpper", docs:
	"Returns `true` if c is an uppercase alphabetic character; `false` otherwise.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword isUpper(CrocThread* t)
	{
		pushBool(t, Uni.isUpper(checkCharParam(t, 0)));
		return 1;
	}

	version(CrocBuiltinDocs) Docs isDigit_docs = {kind: "function", name: "c.isDigit", docs:
	"Returns `true` if c is a decimal digit (0 - 9); `false` otherwise.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword isDigit(CrocThread* t)
	{
		pushBool(t, Uni.isDigit(checkCharParam(t, 0)));
		return 1;
	}

	version(CrocBuiltinDocs) Docs isCtrl_docs = {kind: "function", name: "c.isCtrl", docs:
	"Returns `true` if c is a control character (characters 0x0 to 0x1f and character 0x7f); `false` otherwise.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword isCtrl(CrocThread* t)
	{
		pushBool(t, cast(bool)iscntrl(checkCharParam(t, 0)));
		return 1;
	}

	version(CrocBuiltinDocs) Docs isPunct_docs = {kind: "function", name: "c.isPunct", docs:
	"Returns `true` if c is a punctuation character; `false` otherwise.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword isPunct(CrocThread* t)
	{
		pushBool(t, cast(bool)ispunct(checkCharParam(t, 0)));
		return 1;
	}

	version(CrocBuiltinDocs) Docs isSpace_docs = {kind: "function", name: "c.isSpace", docs:
	"Returns `true` if c is a whitespace character; `false` otherwise.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword isSpace(CrocThread* t)
	{
		pushBool(t, cast(bool)isspace(checkCharParam(t, 0)));
		return 1;
	}

	version(CrocBuiltinDocs) Docs isHexDigit_docs = {kind: "function", name: "c.isHexDigit", docs:
	"Returns `true` if c is a hexadecimal digit (0 - 9, A - F, a - f); `false` otherwise.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword isHexDigit(CrocThread* t)
	{
		pushBool(t, cast(bool)isxdigit(checkCharParam(t, 0)));
		return 1;
	}

	version(CrocBuiltinDocs) Docs isAscii_docs = {kind: "function", name: "c.isAscii", docs:
	"Returns `true` if c is an ASCII character (<= 0x7f); `false` otherwise.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword isAscii(CrocThread* t)
	{
		pushBool(t, checkCharParam(t, 0) <= 0x7f);
		return 1;
	}

	version(CrocBuiltinDocs) Docs isValid_docs = {kind: "function", name: "c.isValid", docs:
	"Returns `true` if c is a valid Unicode character; `false` otherwise.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword isValid(CrocThread* t)
	{
		pushBool(t, Utf.isValid(checkCharParam(t, 0)));
		return 1;
	}
}