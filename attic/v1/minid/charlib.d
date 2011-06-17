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

class CharLib
{
	private static CharLib lib;
	
	static this()
	{
		lib = new CharLib();
	}
	
	private this()
	{
		
	}

	public static void init(MDContext context)
	{
		MDNamespace namespace = new MDNamespace("char"d, context.globals.ns);
		
		namespace.addList
		(
			"toLower"d,    new MDClosure(namespace, &lib.toLower,     "char.toLower"),
			"toUpper"d,    new MDClosure(namespace, &lib.toUpper,     "char.toUpper"),
			"isAlpha"d,    new MDClosure(namespace, &lib.isAlpha,     "char.isAlpha"),
			"isAlNum"d,    new MDClosure(namespace, &lib.isAlNum,     "char.isAlNum"),
			"isLower"d,    new MDClosure(namespace, &lib.isLower,     "char.isLower"),
			"isUpper"d,    new MDClosure(namespace, &lib.isUpper,     "char.isUpper"),
			"isDigit"d,    new MDClosure(namespace, &lib.isDigit,     "char.isDigit"),
			"isCtrl"d,     new MDClosure(namespace, &lib.isCtrl,      "char.isCtrl"),
			"isPunct"d,    new MDClosure(namespace, &lib.isPunct,     "char.isPunct"),
			"isSpace"d,    new MDClosure(namespace, &lib.isSpace,     "char.isSpace"),
			"isHexDigit"d, new MDClosure(namespace, &lib.isHexDigit,  "char.isHexDigit"),
			"isAscii"d,    new MDClosure(namespace, &lib.isAscii,     "char.isAscii")
		);
		
		context.setMetatable(MDValue.Type.Char, namespace);
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
}

public void init()
{

}