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

import ctype = std.ctype;
import std.uni;

class CharLib
{
	this(MDNamespace namespace)
	{
		namespace.addList
		(
			"toLower",     new MDClosure(namespace, &toLower,     "char.toLower"),
			"toUpper",     new MDClosure(namespace, &toUpper,     "char.toUpper"),
			"isAlpha",     new MDClosure(namespace, &isAlpha,     "char.isAlpha"),
			"isAlNum",     new MDClosure(namespace, &isAlNum,     "char.isAlNum"),
			"isLower",     new MDClosure(namespace, &isLower,     "char.isLower"),
			"isUpper",     new MDClosure(namespace, &isUpper,     "char.isUpper"),
			"isDigit",     new MDClosure(namespace, &isDigit,     "char.isDigit"),
			"isCtrl",      new MDClosure(namespace, &isCtrl,      "char.isCtrl"),
			"isPunct",     new MDClosure(namespace, &isPunct,     "char.isPunct"),
			"isSpace",     new MDClosure(namespace, &isSpace,     "char.isSpace"),
			"isHexDigit",  new MDClosure(namespace, &isHexDigit,  "char.isHexDigit"),
			"isAscii",     new MDClosure(namespace, &isAscii,     "char.isAscii")
		);
	}

	int toLower(MDState s)
	{
		s.push(s.safeCode(toUniLower(s.getContext().asChar())));
		return 1;
	}

	int toUpper(MDState s)
	{
		s.push(s.safeCode(toUniUpper(s.getContext().asChar())));
		return 1;
	}
	
	int isAlpha(MDState s)
	{
		s.push(cast(bool)isUniAlpha(s.getContext().asChar()));
		return 1;
	}

	int isAlNum(MDState s)
	{
		dchar c = s.getContext().asChar();
		s.push(cast(bool)(ctype.isdigit(c) || isUniAlpha(c)));
		return 1;
	}
	
	int isLower(MDState s)
	{
		s.push(cast(bool)isUniLower(s.getContext().asChar()));
		return 1;
	}
	
	int isUpper(MDState s)
	{
		s.push(cast(bool)isUniUpper(s.getContext().asChar()));
		return 1;
	}

	int isDigit(MDState s)
	{
		s.push(cast(bool)ctype.isdigit(s.getContext().asChar()));
		return 1;
	}

	int isCtrl(MDState s)
	{
		s.push(cast(bool)ctype.iscntrl(s.getContext().asChar()));
		return 1;
	}
	
	int isPunct(MDState s)
	{
		s.push(cast(bool)ctype.ispunct(s.getContext().asChar()));
		return 1;
	}
	
	int isSpace(MDState s)
	{
		s.push(cast(bool)ctype.isspace(s.getContext().asChar()));
		return 1;
	}
	
	int isHexDigit(MDState s)
	{
		s.push(cast(bool)ctype.isxdigit(s.getContext().asChar()));
		return 1;
	}
	
	int isAscii(MDState s)
	{
		s.push(cast(bool)ctype.isascii(s.getContext().asChar()));
		return 1;
	}
}

public void init()
{
	MDNamespace namespace = new MDNamespace("char"d, MDGlobalState().globals);
	new CharLib(namespace);
	MDGlobalState().setMetatable(MDValue.Type.Char, namespace);
}