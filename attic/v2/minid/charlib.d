/******************************************************************************
License:
Copyright (c) 2007 Jarrett Billingsley

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

module minid.charlib;

import minid.types;

import tango.stdc.ctype;
import Uni = tango.text.Unicode;

final class CharLib
{
static:
	public void init(MDContext context)
	{
		auto methods = new MDNamespace("char"d, context.globals.ns);

		methods.addList
		(
			"toLower"d,    new MDClosure(methods, &toLower,     "char.toLower"),
			"toUpper"d,    new MDClosure(methods, &toUpper,     "char.toUpper"),
			"isAlpha"d,    new MDClosure(methods, &isAlpha,     "char.isAlpha"),
			"isAlNum"d,    new MDClosure(methods, &isAlNum,     "char.isAlNum"),
			"isLower"d,    new MDClosure(methods, &isLower,     "char.isLower"),
			"isUpper"d,    new MDClosure(methods, &isUpper,     "char.isUpper"),
			"isDigit"d,    new MDClosure(methods, &isDigit,     "char.isDigit"),
			"isCtrl"d,     new MDClosure(methods, &isCtrl,      "char.isCtrl"),
			"isPunct"d,    new MDClosure(methods, &isPunct,     "char.isPunct"),
			"isSpace"d,    new MDClosure(methods, &isSpace,     "char.isSpace"),
			"isHexDigit"d, new MDClosure(methods, &isHexDigit,  "char.isHexDigit"),
			"isAscii"d,    new MDClosure(methods, &isAscii,     "char.isAscii"),
			"isValid"d,    new MDClosure(methods, &isValid,     "char.isValid")
		);

		context.setMetatable(MDValue.Type.Char, methods);
	}

	int toLower(MDState s, uint numParams)
	{
		dchar[1] buf;
		s.push(s.safeCode(Uni.toLower([s.getContext!(dchar)], buf)[0]));
		return 1;
	}

	int toUpper(MDState s, uint numParams)
	{
		dchar[1] buf;
		s.push(s.safeCode(Uni.toUpper([s.getContext!(dchar)], buf)[0]));
		return 1;
	}

	int isAlpha(MDState s, uint numParams)
	{
		s.push(Uni.isLetter(s.getContext!(dchar)));
		return 1;
	}

	int isAlNum(MDState s, uint numParams)
	{
		s.push(Uni.isLetterOrDigit(s.getContext!(dchar)));
		return 1;
	}
	
	int isLower(MDState s, uint numParams)
	{
		s.push(Uni.isLower(s.getContext!(dchar)));
		return 1;
	}

	int isUpper(MDState s, uint numParams)
	{
		s.push(Uni.isUpper(s.getContext!(dchar)));
		return 1;
	}

	int isDigit(MDState s, uint numParams)
	{
		s.push(Uni.isDigit(s.getContext!(dchar)));
		return 1;
	}

	int isCtrl(MDState s, uint numParams)
	{
		s.push(cast(bool)iscntrl(s.getContext!(dchar)));
		return 1;
	}
	
	int isPunct(MDState s, uint numParams)
	{
		s.push(cast(bool)ispunct(s.getContext!(dchar)));
		return 1;
	}
	
	int isSpace(MDState s, uint numParams)
	{
		s.push(cast(bool)isspace(s.getContext!(dchar)));
		return 1;
	}
	
	int isHexDigit(MDState s, uint numParams)
	{
		s.push(cast(bool)isxdigit(s.getContext!(dchar)));
		return 1;
	}
	
	int isAscii(MDState s, uint numParams)
	{
		s.push(s.getContext!(dchar) <= 0x7f);
		return 1;
	}
	
	int isValid(MDState s, uint numParams)
	{
		auto c = s.getContext!(dchar);
		s.push(c < 0xD800 || (c > 0xDFFF && c <= 0x10FFFF));
		return 1;
	}
}