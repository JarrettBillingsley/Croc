module minid.charlib;

import minid.state;
import minid.types;

import ctype = std.ctype;
import std.uni;

class CharLib
{
	int toLower(MDState s)
	{
		s.push(toUniLower(s.getCharParam(0)));
		return 1;
	}
	
	int toUpper(MDState s)
	{
		s.push(toUniUpper(s.getCharParam(0)));
		return 1;
	}
	
	int isAlpha(MDState s)
	{
		s.push(cast(bool)isUniAlpha(s.getCharParam(0)));
		return 1;
	}

	int isAlNum(MDState s)
	{
		dchar c = s.getCharParam(0);
		s.push(cast(bool)(ctype.isdigit(c) || isUniAlpha(c)));
		return 1;
	}
	
	int isLower(MDState s)
	{
		s.push(cast(bool)isUniLower(s.getCharParam(0)));
		return 1;
	}
	
	int isUpper(MDState s)
	{
		s.push(cast(bool)isUniUpper(s.getCharParam(0)));
		return 1;
	}

	int isDigit(MDState s)
	{
		s.push(cast(bool)ctype.isdigit(s.getCharParam(0)));
		return 1;
	}

	int isCtrl(MDState s)
	{
		s.push(cast(bool)ctype.iscntrl(s.getCharParam(0)));
		return 1;
	}
	
	int isPunct(MDState s)
	{
		s.push(cast(bool)ctype.ispunct(s.getCharParam(0)));
		return 1;
	}
	
	int isSpace(MDState s)
	{
		s.push(cast(bool)ctype.isspace(s.getCharParam(0)));
		return 1;
	}
	
	int isHexDigit(MDState s)
	{
		s.push(cast(bool)ctype.isxdigit(s.getCharParam(0)));
		return 1;
	}
	
	int isAscii(MDState s)
	{
		s.push(cast(bool)ctype.isascii(s.getCharParam(0)));
		return 1;
	}
}

public void init(MDState s)
{
	CharLib lib = new CharLib();
	
	MDTable charLib = MDTable.create
	(
		"toLower",     new MDClosure(s, &lib.toLower,     "char.toLower"),
		"toUpper",     new MDClosure(s, &lib.toUpper,     "char.toUpper"),
		"isAlpha",     new MDClosure(s, &lib.isAlpha,     "char.isAlpha"),
		"isAlNum",     new MDClosure(s, &lib.isAlNum,     "char.isAlNum"),
		"isLower",     new MDClosure(s, &lib.isLower,     "char.isLower"),
		"isUpper",     new MDClosure(s, &lib.isUpper,     "char.isUpper"),
		"isDigit",     new MDClosure(s, &lib.isDigit,     "char.isDigit"),
		"isCtrl",      new MDClosure(s, &lib.isCtrl,      "char.isCtrl"),
		"isPunct",     new MDClosure(s, &lib.isPunct,     "char.isPunct"),
		"isSpace",     new MDClosure(s, &lib.isSpace,     "char.isSpace"),
		"isHexDigit",  new MDClosure(s, &lib.isHexDigit,  "char.isHexDigit"),
		"isAscii",     new MDClosure(s, &lib.isAscii,     "char.isAscii")
	);

	s.setGlobal("char", charLib);
	MDGlobalState().setMetatable(MDValue.Type.Char, charLib);
}