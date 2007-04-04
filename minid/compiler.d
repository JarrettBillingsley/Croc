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

module minid.compiler;

import std.c.stdlib;
import std.conv;
import std.stdio;
import std.stream;
import path = std.path;
import string = std.string;
import utf = std.utf;
import std.cstream;

import minid.types;
import minid.opcodes;
import minid.utils;

alias minid.utils.toInt toInt;

//debug = REGPUSHPOP;
//debug = VARACTIVATE;
//debug = WRITECODE;

public MDModuleDef compileModule(char[] filename)
{
	scope f = new BufferedFile(filename, FileMode.In);
	return compileModule(f, path.getBaseName(filename));
}

public MDModuleDef compileModule(Stream source, char[] name)
{
	Token* tokens = Lexer.lex(name, source);
	Module mod = Module.parse(tokens);

	return mod.codeGen();
}

public MDFuncDef compileStatement(Stream source, char[] name, out bool atEOF)
{
	Token* tokens = Lexer.lex(name, source);
	Statement s;
	FuncState fs;

	try
		s = Statement.parse(tokens);
	catch(Object o)
	{
		if(tokens.type == Token.Type.EOF)
			atEOF = true;

		throw o;
	}

	fs = new FuncState(Location(utf.toUTF32(name), 1, 1), utf.toUTF32(name));
	s = s.fold();
	s.codeGen(fs);
	fs.codeI(s.mEndLocation.line, Op.Ret, 0, 1);

	return fs.toFuncDef();
}

struct Token
{
	public static enum Type
	{
		As,
		Break,
		Case,
		Catch,
		Class,
		Continue,
		Coroutine,
		Default,
		Do,
		Else,
		False,
		Finally,
		For,
		Foreach,
		Function,
		Global,
		If,
		Import,
		In,
		Is,
		Local,
		Module,
		Null,
		Return,
		Switch,
		This,
		Throw,
		True,
		Try,
		Vararg,
		While,
		With,
		Yield,

		Add,
		AddEq,
		Inc,
		Sub,
		SubEq,
		Dec,
		Cat,
		CatEq,
		Mul,
		MulEq,
		DefaultEq,
		Div,
		DivEq,
		Mod,
		ModEq,
		LT,
		LE,
		Shl,
		ShlEq,
		GT,
		GE,
		Shr,
		ShrEq,
		UShr,
		UShrEq,
		And,
		AndEq,
		AndAnd,
		Or,
		OrEq,
		OrOr,
		Xor,
		XorEq,
		Assign,
		EQ,
		Dot,
		DotDot,
		Not,
		NE,
		LParen,
		RParen,
		LBracket,
		RBracket,
		LBrace,
		RBrace,
		Colon,
		Comma,
		Semicolon,
		Length,

		Ident,
		CharLiteral,
		StringLiteral,
		IntLiteral,
		FloatLiteral,
		EOF
	}

	public static const dchar[][] tokenStrings =
	[
		Type.As: "as",
		Type.Break: "break",
		Type.Case: "case",
		Type.Catch: "catch",
		Type.Class: "class",
		Type.Continue: "continue",
		Type.Coroutine: "coroutine",
		Type.Default: "default",
		Type.Do: "do",
		Type.Else: "else",
		Type.False: "false",
		Type.Finally: "finally",
		Type.For: "for",
		Type.Foreach: "foreach",
		Type.Function: "function",
		Type.Global: "global",
		Type.If: "if",
		Type.Import: "import",
		Type.In: "in",
		Type.Is: "is",
		Type.Local: "local",
		Type.Module: "module",
		Type.Null: "null",
		Type.Return: "return",
		Type.Switch: "switch",
		Type.This: "this",
		Type.Throw: "throw",
		Type.True: "true",
		Type.Try: "try",
		Type.Vararg: "vararg",
		Type.While: "while",
		Type.With: "with",
		Type.Yield: "yield",

		Type.Add: "+",
		Type.AddEq: "+=",
		Type.Inc: "++",
		Type.Sub: "-",
		Type.SubEq: "-=",
		Type.Dec: "--",
		Type.Cat: "~",
		Type.CatEq: "~=",
		Type.Mul: "*",
		Type.MulEq: "*=",
		Type.DefaultEq: "?=",
		Type.Div: "/",
		Type.DivEq: "/=",
		Type.Mod: "%",
		Type.ModEq: "%=",
		Type.LT: "<",
		Type.LE: "<=",
		Type.Shl: "<<",
		Type.ShlEq: "<<=",
		Type.GT: ">",
		Type.GE: ">=",
		Type.Shr: ">>",
		Type.ShrEq: ">>=",
		Type.UShr: ">>>",
		Type.UShrEq: ">>>=",
		Type.And: "&",
		Type.AndEq: "&=",
		Type.AndAnd: "&&",
		Type.Or: "|",
		Type.OrEq: "|=",
		Type.OrOr: "||",
		Type.Xor: "^",
		Type.XorEq: "^=",
		Type.Assign: "=",
		Type.EQ: "==",
		Type.Dot: ".",
		Type.DotDot: "..",
		Type.Not: "!",
		Type.NE: "!=",
		Type.LParen: "(",
		Type.RParen: ")",
		Type.LBracket: "[",
		Type.RBracket: "]",
		Type.LBrace: "{",
		Type.RBrace: "}",
		Type.Colon: ":",
		Type.Comma: ",",
		Type.Semicolon: ";",
		Type.Length: "#",

		Type.Ident: "Identifier",
		Type.CharLiteral: "Char Literal",
		Type.StringLiteral: "String Literal",
		Type.IntLiteral: "Int Literal",
		Type.FloatLiteral: "Float Literal",
		Type.EOF: "<EOF>"
	];

	public static Type[dchar[]] stringToType;

	static this()
	{
		stringToType["as"] = Type.As;
		stringToType["break"] = Type.Break;
		stringToType["case"] = Type.Case;
		stringToType["catch"] = Type.Catch;
		stringToType["class"] = Type.Class;
		stringToType["continue"] = Type.Continue;
		stringToType["coroutine"] = Type.Coroutine;
		stringToType["default"] = Type.Default;
		stringToType["do"] = Type.Do;
		stringToType["else"] = Type.Else;
		stringToType["false"] = Type.False;
		stringToType["finally"] = Type.Finally;
		stringToType["for"] = Type.For;
		stringToType["foreach"] = Type.Foreach;
		stringToType["function"] = Type.Function;
		stringToType["global"] = Type.Global;
		stringToType["if"] = Type.If;
		stringToType["import"] = Type.Import;
		stringToType["in"] = Type.In;
		stringToType["is"] = Type.Is;
		stringToType["local"] = Type.Local;
		stringToType["module"] = Type.Module;
		stringToType["null"] = Type.Null;
		stringToType["return"] = Type.Return;
		stringToType["switch"] = Type.Switch;
		stringToType["this"] = Type.This;
		stringToType["throw"] = Type.Throw;
		stringToType["true"] = Type.True;
		stringToType["try"] = Type.Try;
		stringToType["vararg"] = Type.Vararg;
		stringToType["while"] = Type.While;
		stringToType["with"] = Type.With;
		stringToType["yield"] = Type.Yield;
		stringToType["("] = Type.LParen;
		stringToType[")"] = Type.RParen;
		stringToType["["] = Type.LBracket;
		stringToType["]"] = Type.RBracket;
		stringToType["{"] = Type.LBrace;
		stringToType["}"] = Type.RBrace;
		stringToType[":"] = Type.Colon;
		stringToType[","] = Type.Comma;
		stringToType[";"] = Type.Semicolon;
		stringToType["#"] = Type.Length;

		stringToType.rehash;
	}

	public char[] toString()
	{
		char[] ret;

		switch(type)
		{
			case Type.Ident:
				ret = "Identifier: " ~ utf.toUTF8(stringValue);
				break;

			case Type.CharLiteral:
				ret = "Character Literal";
				break;

			case Type.StringLiteral:
				ret = "String Literal";
				break;

			case Type.IntLiteral:
				ret = "Integer Literal: " ~ string.toString(intValue);
				break;

			case Type.FloatLiteral:
				ret = "Float Literal: " ~ string.toString(floatValue);
				break;

			default:
				ret = utf.toUTF8(tokenStrings[cast(uint)type]);
				break;
		}

		return ret;
	}

	public static char[] toString(Type type)
	{
		return utf.toUTF8(tokenStrings[type]);
	}

	public void check(Type t)
	{
		if(type != t)
			throw new MDCompileException(location, "'%s' expected; found '%s' instead", tokenStrings[t], tokenStrings[type]);
	}
	
	public bool isOpAssign()
	{
		switch(type)
		{
			case Token.Type.AddEq,
				Token.Type.SubEq,
				Token.Type.CatEq,
				Token.Type.MulEq,
				Token.Type.DivEq,
				Token.Type.ModEq,
				Token.Type.ShlEq,
				Token.Type.ShrEq,
				Token.Type.UShrEq,
				Token.Type.OrEq,
				Token.Type.XorEq,
				Token.Type.AndEq,
				Token.Type.DefaultEq:
				return true;
			
			default:
				return false;
		}
	}

	public Type type;

	union
	{
		public bool boolValue;
		public dchar[] stringValue;
		public int intValue;
		public float floatValue;
	}

	public Location location;

	public Token* nextToken;
}

class Lexer
{
	protected static BufferedStream mSource;
	protected static Location mLoc;
	protected static dchar mCharacter;
	protected static dchar mLookaheadCharacter;
	protected static bool mHaveLookahead = false;
	
	enum Encoding
	{
		UTF8,
		UTF16LE,
		UTF16BE,
		UTF32LE,
		UTF32BE
	}
	
	protected static Encoding mEncoding;

	public static Token* lex(char[] name, Stream source)
	{
		if(!source.readable)
			throw new MDException("%s", name, ": Source code stream is not readable");

		mLoc = Location(utf.toUTF32(name), 1, 0);

		mSource = new BufferedStream(source);

		char firstChar = mSource.getc();
		
		if(mSource.eof() == false)
		{
			switch(firstChar)
			{
				case 0xEF:
					char c = mSource.getc();
					
					if(c != 0xBB)
						throw new MDCompileException(mLoc, "Invalid input source text encoding");
						
					c = mSource.getc();
					
					if(c != 0xBF)
						throw new MDCompileException(mLoc, "Invalid input source text encoding");
						
					mEncoding = Encoding.UTF8;
					nextChar();
					break;
					
				case 0xFE:
					char c = mSource.getc();
					
					if(c != 0xFF)
						throw new MDCompileException(mLoc, "Invalid input source text encoding");
						
					mEncoding = Encoding.UTF16BE;
					nextChar();
					break;
					
				case 0xFF:
					char c = mSource.getc();
					
					if(c != 0xFE)
						throw new MDCompileException(mLoc, "Invalid input source text encoding");
	
					c = mSource.getc();
	
					if(c == 0)
					{
						c = mSource.getc();
						
						if(c != 0)
							throw new MDCompileException(mLoc, "Invalid input source text encoding");

						mEncoding = Encoding.UTF32LE;
						nextChar();
						break;
					}
					else if(c == char.init)
					{
						// end of file?
						mCharacter = dchar.init;
						mEncoding = Encoding.UTF16LE;
						break;
					}
					else
					{
						mEncoding = Encoding.UTF16LE;
						mCharacter = readRestOfUTF16LEChar(c);
						break;
					}
					break;
					
				case 0:
					char c = mSource.getc();
					
					if(c != 0)
						throw new MDCompileException(mLoc, "Invalid input source text encoding");
						
					c = mSource.getc();
	
					if(c != 0xFE)
						throw new MDCompileException(mLoc, "Invalid input source text encoding");
						
					c = mSource.getc();
	
					if(c != 0xFF)
						throw new MDCompileException(mLoc, "Invalid input source text encoding");
						
					mEncoding = Encoding.UTF32BE;
					nextChar();
					break;
	
				default:
					// If we default to UTF-8, the first character could be the beginning of a multi-byte, so..
					//if(firstChar > 0x7f)
					//	throw new MDCompileException(mLoc, "Invalid input source text encoding");
	
					mEncoding = Encoding.UTF8;
					mCharacter = firstChar;
					break;
			}
		}
		else
		{
			mEncoding = Encoding.UTF8;
			mCharacter = 0;
		}
		
		if(mCharacter == '#')
		{
			nextChar();
			
			if(mCharacter != '!')
				throw new MDCompileException(mLoc, "Script line must start with \"#!\"");
			
			while(!isEOL())
				nextChar();
		}

		Token* firstToken = nextToken();
		Token* t = firstToken;

		while(t.type != Token.Type.EOF)
		{
			Token* next = nextToken();

			t.nextToken = next;
			t = t.nextToken;
		}

		return firstToken;
	}

	protected static bool isEOF()
	{
		return (mCharacter == '\0') || (mCharacter == dchar.init);
	}

	protected static bool isEOL()
	{
		return isNewline() || isEOF();
	}

	protected static bool isWhitespace()
	{
		return (mCharacter == ' ') || (mCharacter == '\t') || (mCharacter == '\v') || (mCharacter == '\u000C') || isEOL();
	}

	protected static bool isNewline()
	{
		return (mCharacter == '\r') || (mCharacter == '\n');
	}

	protected static bool isBinaryDigit()
	{
		return (mCharacter == '0') || (mCharacter == '1');
	}

	protected static bool isOctalDigit()
	{
		return (mCharacter >= '0') && (mCharacter <= '7');
	}

	protected static bool isHexDigit()
	{
		return ((mCharacter >= '0') && (mCharacter <= '9')) ||
			((mCharacter >= 'a') && (mCharacter <= 'f')) ||
			((mCharacter >= 'A') && (mCharacter <= 'F'));
	}

	protected static bool isDecimalDigit()
	{
		return (mCharacter >= '0') && (mCharacter <= '9');
	}

	protected static bool isAlpha()
	{
		return ((mCharacter >= 'a') && (mCharacter <= 'z')) || ((mCharacter >= 'A') && (mCharacter <= 'Z'));
	}

	protected static ubyte hexDigitToInt(dchar c)
	{
		assert((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'), "hexDigitToInt");

		if(c >= '0' && c <= '9')
			return c - '0';

		return std.ctype.tolower(cast(char)c) - 'a' + 10;
	}
	
	protected static dchar readRestOfUTF16LEChar(char loChar)
	{
		char hiChar = mSource.getc();

		if(hiChar == char.init)
			throw new MDCompileException(mLoc, "Unfinished UTF-16 character");

		wchar c = loChar | (hiChar << 8);

		if(c & ~0x7F)
		{
			if(c >= 0xD800 && c <= 0xDBFF)
			{
				wchar c2 = mSource.getcw();

				if(c2 < 0xDC00 || c2 > 0xDFFF)
					throw new MDCompileException(mLoc, "Surrogate UTF-16 low value out of range");

				return ((c - 0xD7C0) << 10) + (c2 - 0xDC00);
			}
			else if(c >= 0xDC00 && c <= 0xDFFF)
				throw new MDCompileException(mLoc, "Unpaired surrogate UTF-16 value");
			else if(c == 0xFFFE || c == 0xFFFF)
				throw new MDCompileException(mLoc, "Illegal UTF-16 value");
			else
				return c;
		}
		else
			return c;
	}
	
	protected static dchar readChar()
	{
		switch(mEncoding)
		{
			case Encoding.UTF8:
				char c = mSource.getc();

				if(c == char.init)
					return dchar.init;

				if(c & 0x80)
				{
					uint n;

					for(n = 1; ; n++)
					{
						if(n > 4)
							throw new MDCompileException(mLoc, "Invalid UTF-8 character");

						if(((c << n) & 0x80) == 0)
						{
							if(n == 1)
								throw new MDCompileException(mLoc, "Invalid UTF-8 character");

							break;
						}
					}

					dchar dc = cast(dchar)(c & ((1 << (7 - n)) - 1));

					char c2 = mSource.getc();

					if ((c & 0xFE) == 0xC0 ||
						(c == 0xE0 && (c2 & 0xE0) == 0x80) ||
						(c == 0xF0 && (c2 & 0xF0) == 0x80) ||
						(c == 0xF8 && (c2 & 0xF8) == 0x80) ||
						(c == 0xFC && (c2 & 0xFC) == 0x80))
						throw new MDCompileException(mLoc, "Invalid UTF-8 character");

					c = c2;
					if((c & 0xC0) != 0x80)
						throw new MDCompileException(mLoc, "Invalid UTF-8 character");

					dc = (dc << 6) | (c & 0x3F);

					for(uint i = 2; i != n; i++)
					{
						c = mSource.getc();

						if((c & 0xC0) != 0x80)
							throw new MDCompileException(mLoc, "Invalid UTF-8 character");

						dc = (dc << 6) | (c & 0x3F);
					}

					if(!utf.isValidDchar(dc))
						throw new MDCompileException(mLoc, "Invalid UTF-8 character");

					return dc;
				}
				else
					return c;

			case Encoding.UTF16LE:
				char hiChar = mSource.getc();

				if(hiChar == char.init)
					return dchar.init;

				return readRestOfUTF16LEChar(hiChar);

			default:
				assert(false, "unimplemented encoding");
		}
	}
	
	protected static dchar lookaheadChar()
	{
		assert(mHaveLookahead == false, "looking ahead too far");

		mLookaheadCharacter = readChar();
		mHaveLookahead = true;
		return mLookaheadCharacter;
	}

	protected static void nextChar()
	{
		mLoc.column++;
		
		if(mHaveLookahead)
		{
			mCharacter = mLookaheadCharacter;
			mHaveLookahead = false;
		}
		else
		{
			mCharacter = readChar();
		}
	}

	protected static void nextLine()
	{
		while(isNewline() && !isEOF())
		{
			dchar old = mCharacter;

			nextChar();

			if(isNewline() && mCharacter != old)
				nextChar();

			mLoc.line++;
			mLoc.column = 1;
		}
	}

	protected static bool readNumLiteral(bool prependPoint, out float fret, out int iret)
	{
		Location beginning = mLoc;
		dchar[100] buf;
		uint i = 0;

		void add(dchar c)
		{
			buf[i] = c;
			i++;
		}

		bool hasPoint = false;

		if(prependPoint)
		{
			hasPoint = true;
			add('.');
		}
		else
		{
			if(mCharacter == '0')
			{
				nextChar();

				switch(mCharacter)
				{
					case 'b':
						nextChar();

						if(!isBinaryDigit())
							throw new MDCompileException(mLoc, "Binary digit expected, not '%s'", mCharacter);

						while(isBinaryDigit() || mCharacter == '_')
						{
							if(mCharacter != '_')
								add(mCharacter);

							nextChar();
						}

						try
						{
							iret = toInt(buf[0 .. i], 2);
						}
						catch(ConvError e)
						{
							throw new MDCompileException(beginning, "Malformed binary int literal");
						}

						return true;

					case 'c':
						nextChar();

						if(!isOctalDigit())
							throw new MDCompileException(mLoc, "Octal digit expected, not '%s'", mCharacter);

						while(isOctalDigit() || mCharacter == '_')
						{
							if(mCharacter != '_')
								add(mCharacter);

							nextChar();
						}

						try
						{
							iret = toInt(buf[0 .. i], 8);
						}
						catch(ConvError e)
						{
							throw new MDCompileException(beginning, "Malformed octal int literal");
						}

						return true;

					case 'x':
						nextChar();

						if(!isHexDigit())
							throw new MDCompileException(mLoc, "Hexadecimal digit expected, not '%s'", mCharacter);

						while(isHexDigit() || mCharacter == '_')
						{
							if(mCharacter != '_')
								add(mCharacter);

							nextChar();
						}

						try
						{
							iret = toInt(buf[0 .. i], 16);
						}
						catch(ConvError e)
						{
							throw new MDCompileException(beginning, "Malformed hexadecimal int literal");
						}

						return true;

					default:
						add('0');
						break;
				}
			}
		}

		while(hasPoint == false)
		{
			if(isDecimalDigit())
			{
				add(mCharacter);
				nextChar();
			}
			else if(mCharacter == '.')
			{
				if(lookaheadChar() == '.')
				{
					// next token is probably a ..
					break;
				}
				else
				{
					hasPoint = true;
					add(mCharacter);
					nextChar();
				}
			}
			else if(mCharacter == '_')
			{
				nextChar();
				continue;
			}
			else
				// this will still handle exponents on literals without a decimal point
				break;
		}

		if(hasPoint)
		{
			if(isDecimalDigit())
			{
				add(mCharacter);
				nextChar();
			}
			else
				throw new MDCompileException(mLoc, "Floating point literal '%s' must have at least one digit after decimal point", buf[0 .. i]);
		}
		
		bool hasExponent = false;

		while(true)
		{
			if(isDecimalDigit())
			{
				add(mCharacter);
				nextChar();
			}
			else if(mCharacter == 'e' || mCharacter == 'E')
			{
				hasExponent = true;

				add(mCharacter);

				nextChar();

				if(mCharacter == '-' || mCharacter == '+')
				{
					add(mCharacter);
					nextChar();
				}

				if(!isDecimalDigit())
					throw new MDCompileException(mLoc, "Exponent value expected in float literal '%s'", buf[0 .. i]);

				while(isDecimalDigit() || mCharacter == '_')
				{
					if(mCharacter != '_')
						add(mCharacter);

					nextChar();
				}

				break;
			}
			else if(mCharacter == '_')
				continue;
			else
				break;
		}

		if(hasPoint == false && hasExponent == false)
		{
			try
			{
				iret = toInt(buf[0 .. i], 10);
			}
			catch(ConvError e)
			{
				throw new MDCompileException(beginning, "Malformed int literal '%s'", buf[0 .. i]);
			}

			return true;
		}
		else
		{
			try
			{
				fret = std.conv.toFloat(utf.toUTF8(buf[0 .. i]));
			}
			catch(ConvError e)
			{
				throw new MDCompileException(beginning, "Malformed float literal '%s'", buf[0 .. i]);
			}

			return false;
		}
	}

	protected static dchar readEscapeSequence(Location beginning)
	{
		uint readHexDigits(uint num)
		{
			uint ret = 0;

			for(uint i = 0; i < num; i++)
			{
				if(isHexDigit() == false)
					throw new MDCompileException(mLoc, "Hexadecimal escape digits expected");

				ret <<= 4;
				ret |= hexDigitToInt(mCharacter);
				nextChar();
			}

			return ret;
		}

		dchar ret;

		assert(mCharacter == '\\', "escape seq - must start on backslash");

		nextChar();
		if(isEOF())
			throw new MDCompileException(beginning, "Unterminated string or character literal");

		switch(mCharacter)
		{
			case 'a':  nextChar(); return '\a';
			case 'b':  nextChar(); return '\b';
			case 'f':  nextChar(); return '\f';
			case 'n':  nextChar(); return '\n';
			case 'r':  nextChar(); return '\r';
			case 't':  nextChar(); return '\t';
			case 'v':  nextChar(); return '\v';
			case '\\': nextChar(); return '\\';
			case '\"': nextChar(); return '\"';
			case '\'': nextChar(); return '\'';

			case 'x':
				nextChar();

				int x = readHexDigits(2);

				if(x > 0x7F)
					throw new MDCompileException(mLoc, "Hexadecimal escape sequence too large");

				ret = cast(dchar)x;
				break;

			case 'u':
				nextChar();

				int x = readHexDigits(4);

				if(x == 0xFFFE || x == 0xFFFF)
					throw new MDCompileException(mLoc, "Unicode escape '\\u%04x' is illegal", x);

				ret = cast(dchar)x;
				break;

			case 'U':
				nextChar();

				int x = readHexDigits(8);

				if(x == 0xFFFE || x == 0xFFFF)
					throw new MDCompileException(mLoc, "Unicode escape '\\u%04x' is illegal", x);

				if(utf.isValidDchar(cast(dchar)x) == false)
					throw new MDCompileException(mLoc, "Unicode escape '\\U%08x' too large", x);

				ret = cast(dchar)x;
				break;

			default:
				if(!isDecimalDigit())
					throw new MDCompileException(mLoc, "Invalid string escape sequence '\\%s'", mCharacter);

				// Decimal char
				int numch = 0;
				int c = 0;

				do
				{
					c = 10 * c + (mCharacter - '0');
					nextChar();
				} while(++numch < 3 && isDecimalDigit());

				if(c > 0x7F)
					throw new MDCompileException(mLoc, "Numeric escape sequence too large");

				ret = cast(dchar)c;
				break;
		}

		return ret;
	}

	protected static dchar[] readStringLiteral(bool escape)
	{
		Location beginning = mLoc;
		uint i = 0;
		dchar[] buf = new dchar[100];

		void add(dchar c)
		{
			if(i >= buf.length)
				buf.length = cast(uint)(buf.length * 1.5);

			buf[i] = c;
			i++;
		}

		dchar delimiter = mCharacter;

		// Skip opening quote
		nextChar();

		while(mCharacter != delimiter)
		{
			if(isEOF())
				throw new MDCompileException(beginning, "Unterminated string literal");

			switch(mCharacter)
			{
				case '\r', '\n':
					add('\n');
					nextLine();
					break;

				case '\\':
					if(escape == false)
						goto default;

					add(readEscapeSequence(beginning));
					continue;

				default:
					add(mCharacter);
					nextChar();
					break;
			}
		}

		// Skip end quote
		nextChar();

		return buf[0 .. i];
	}

	protected static dchar readCharLiteral()
	{
		Location beginning = mLoc;
		dchar ret;

		assert(mCharacter == '\'', "char literal must start with single quote");
		nextChar();

		if(isEOF())
			throw new MDCompileException(beginning, "Unterminated character literal");

		switch(mCharacter)
		{
			case '\\':
				ret = readEscapeSequence(beginning);
				break;

			default:
				ret = mCharacter;
				nextChar();
				break;
		}

		if(mCharacter != '\'')
			throw new MDCompileException(beginning, "Unterminated character literal");

		nextChar();

		return ret;
	}

	protected static Token* nextToken()
	{
		Token* token = new Token;

		Location tokenLoc;

		scope(exit)
			token.location = tokenLoc;

		while(true)
		{
			tokenLoc = mLoc;

			switch(mCharacter)
			{
				case '\r', '\n':
					nextLine();
					continue;

				case '+':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						token.type = Token.Type.AddEq;
					}
					else if(mCharacter == '+')
					{
						nextChar();
						token.type = Token.Type.Inc;
					}
					else
						token.type = Token.Type.Add;

					return token;

				case '-':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						token.type = Token.Type.SubEq;
					}
					else if(mCharacter == '-')
					{
						nextChar();
						token.type = Token.Type.Dec;
					}
					else
						token.type = Token.Type.Sub;

					return token;

				case '~':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						token.type = Token.Type.CatEq;
					}
					else
						token.type = Token.Type.Cat;

					return token;

				case '*':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						token.type = Token.Type.MulEq;
					}
					else
						token.type = Token.Type.Mul;

					return token;

				case '/':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						token.type = Token.Type.DivEq;
						return token;
					}
					else if(mCharacter == '/')
					{
						while(!isEOL())
							nextChar();
					}
					else if(mCharacter == '*')
					{
						nextChar();

						_commentLoop: while(true)
						{
							switch(mCharacter)
							{
								case '*':
									nextChar();

									if(mCharacter == '/')
									{
										nextChar();
										break _commentLoop;
									}
									continue;

								case '\r', '\n':
									nextLine();
									continue;

								case '\0', dchar.init:
									throw new MDCompileException(tokenLoc, "Unterminated /* */ comment");

								default:
									break;
							}

							nextChar();
						}
					}
					else if(mCharacter == '+')
					{
						nextChar();
						
						uint nesting = 1;

						_commentLoop2: while(true)
						{
							switch(mCharacter)
							{
								case '/':
									nextChar();
									
									if(mCharacter == '+')
									{
										nextChar();
										nesting++;
									}

									continue;
									
								case '+':
									nextChar();

									if(mCharacter == '/')
									{
										nextChar();
										nesting--;
										
										if(nesting == 0)
											break _commentLoop2;
									}
									continue;

								case '\r', '\n':
									nextLine();
									continue;

								case '\0', dchar.init:
									throw new MDCompileException(tokenLoc, "Unterminated /+ +/ comment");

								default:
									break;
							}
							
							nextChar();
						}
					}
					else
					{
						token.type = Token.Type.Div;
						return token;
					}

					break;

				case '%':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						token.type = Token.Type.ModEq;
					}
					else
						token.type = Token.Type.Mod;

					return token;

				case '<':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						token.type = Token.Type.LE;
					}
					else if(mCharacter == '<')
					{
						nextChar();

						if(mCharacter == '=')
						{
							nextChar();
							token.type = Token.Type.ShlEq;
						}
						else
							token.type = Token.Type.Shl;
					}
					else
						token.type = Token.Type.LT;

					return token;

				case '>':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						token.type = Token.Type.GE;
					}
					else if(mCharacter == '>')
					{
						nextChar();

						if(mCharacter == '=')
						{
							nextChar();
							token.type = Token.Type.ShrEq;
						}
						else if(mCharacter == '>')
						{
							nextChar();

							if(mCharacter == '=')
							{
								nextChar();
								token.type = Token.Type.UShrEq;
							}
							else
								token.type = Token.Type.UShr;
						}
						else
							token.type = Token.Type.Shr;
					}
					else
						token.type = Token.Type.GT;

					return token;

				case '&':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						token.type = Token.Type.AndEq;
					}
					else if(mCharacter == '&')
					{
						nextChar();
						token.type = Token.Type.AndAnd;
					}
					else
						token.type = Token.Type.And;

					return token;

				case '|':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						token.type = Token.Type.OrEq;
					}
					else if(mCharacter == '|')
					{
						nextChar();
						token.type = Token.Type.OrOr;
					}
					else
						token.type = Token.Type.Or;

					return token;

				case '^':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						token.type = Token.Type.XorEq;
					}
					else
						token.type = Token.Type.Xor;

					return token;

				case '=':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						token.type = Token.Type.EQ;
					}
					else
						token.type = Token.Type.Assign;

					return token;

				case '.':
					nextChar();

					if(isDecimalDigit())
					{
						int dummy;
						bool b = readNumLiteral(true, token.floatValue, dummy);
						assert(b == false, "literal must be float");

						token.type = Token.Type.FloatLiteral;
					}
					else
					{
						if(mCharacter == '.')
						{
							nextChar();
							token.type = Token.Type.DotDot;
						}
						else
							token.type = Token.Type.Dot;
					}

					return token;

				case '!':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						token.type = Token.Type.NE;
					}
					else
						token.type = Token.Type.Not;

					return token;
					
				case '?':
					nextChar();
					
					if(mCharacter != '=')
						throw new MDCompileException(tokenLoc, "'?' expected to be followed by '='");
					
					nextChar();

					token.type = Token.Type.DefaultEq;
					return token;

				case '\"':
					token.stringValue = readStringLiteral(true);
					token.type = Token.Type.StringLiteral;
					return token;

				case '`':
					token.stringValue = readStringLiteral(false);
					token.type = Token.Type.StringLiteral;
					return token;

				case '@':
					nextChar();

					if(mCharacter != '\"')
						throw new MDCompileException(tokenLoc, "'@' expected to be followed by '\"'");

					token.stringValue = readStringLiteral(false);
					token.type = Token.Type.StringLiteral;
					return token;

				case '\'':
					token.intValue = readCharLiteral();
					token.type = Token.Type.CharLiteral;
					return token;

				case '\0', dchar.init:
					token.type = Token.Type.EOF;
					return token;

				default:
					if(isWhitespace())
					{
						nextChar();
						continue;
					}
					else if(isDecimalDigit())
					{
						float fval;
						int ival;

						bool type = readNumLiteral(false, fval, ival);

						if(type == false)
						{
							token.floatValue = fval;
							token.type = Token.Type.FloatLiteral;
							return token;
						}
						else
						{
							token.intValue = ival;
							token.type = Token.Type.IntLiteral;
							return token;
						}
					}
					else if(isAlpha() || mCharacter == '_')
					{
						dchar[] s;

						do
						{
							s ~= mCharacter;
							nextChar();
						}
						while(isAlpha() || isDecimalDigit() || mCharacter == '_');

						if(s.length >= 2 && s[0 .. 2] == "__")
							throw new MDCompileException(tokenLoc, "'", s, "': Identifiers starting with two underscores are reserved");

						Token.Type* t = (s in Token.stringToType);

						if(t is null)
						{
							token.type = Token.Type.Ident;
							token.stringValue = s;
							return token;
						}
						else
						{
							token.type = *t;
							return token;
						}
					}
					else
					{
						dchar[] s;
						s ~= mCharacter;

						nextChar();

						Token.Type* t = (s in Token.stringToType);

						if(t is null)
							throw new MDCompileException(tokenLoc, "Invalid token '%s'", s);
						else
							token.type = *t;

						return token;
					}
			}
		}
	}
}

struct InstRef
{
	InstRef* trueList;
	InstRef* falseList;
	uint pc;
}

enum ExpType
{
	Null,
	True,
	False,
	Const,
	Var,
	NewGlobal,
	Indexed,
	Sliced,
	Vararg,
	Closure,
	Call,
	Yield,
	NeedsDest,
	Src
}

struct Exp
{
	ExpType type;

	uint index;
	uint index2;
	uint index3;

	bool isTempReg;
	bool isTempReg2;
	bool isTempReg3;
	
	char[] toString()
	{
		char[] typename;
		
		switch(type)
		{
			case ExpType.Null: typename = "Null"; break;
			case ExpType.True: typename = "True"; break;
			case ExpType.False: typename = "False"; break;
			case ExpType.Const: typename = "Const"; break;
			case ExpType.Var: typename = "Var"; break;
			case ExpType.NewGlobal: typename = "NewGlobal"; break;
			case ExpType.Indexed: typename = "Indexed"; break;
			case ExpType.Sliced: typename = "Sliced"; break;
			case ExpType.Vararg: typename = "Vararg"; break;
			case ExpType.Closure: typename = "Closure"; break;
			case ExpType.Call: typename = "Call"; break;
			case ExpType.Yield: typename = "Yield"; break;
			case ExpType.NeedsDest: typename = "NeedsDest"; break;
			case ExpType.Src: typename = "Src"; break;
		}
		
		return string.format("%s (%d, %d, %d) : (%s, %s, %s)", typename, index, index2, index3, isTempReg, isTempReg2, isTempReg3);
	}
}

class FuncState
{
	struct Scope
	{
		protected Scope* enclosing;
		protected Scope* breakScope;
		protected Scope* continueScope;
		protected InstRef* breaks;
		protected InstRef* continues;
		protected uint varStart = 0;
		protected uint regStart = 0;
		protected bool hasUpval = false;
	}

	protected FuncState mParent;
	protected Scope* mScope;
	protected int mFreeReg = 0;
	protected Exp[] mExpStack;
	protected int mExpSP = 0;

	protected bool mIsVararg;
	protected FuncState[] mInnerFuncs;
	protected Location mLocation;
	protected MDValue[] mConstants;
	protected uint mNumParams;
	protected uint mStackSize;
	protected Instruction[] mCode;
	protected uint[] mLineInfo;
	protected dchar[] mGuessedName;

	struct LocVarDesc
	{
		dchar[] name;
		Location location;
		uint reg;
		bool isActive;
	}

	protected LocVarDesc[] mLocVars;

	struct UpvalDesc
	{
		bool isUpvalue;
		uint index;
		dchar[] name;
	}

	protected UpvalDesc[] mUpvals;

	struct SwitchDesc
	{
		bool isString;
		uint switchPC;

		union
		{
			int[int] intOffsets;
			int[dchar[]] stringOffsets;
		}

		int defaultOffset = -1;

		SwitchDesc* prev;
	}

	// Switches are kept on this switch stack while being built..
	protected SwitchDesc* mSwitch;
	// ..and are then transfered to this array when they are done.
	protected SwitchDesc*[] mSwitchTables;

	public this(Location location, dchar[] guessedName, FuncState parent = null)
	{
		mLocation = location;
		mGuessedName = guessedName;

		mParent = parent;
		mScope = new Scope;
		mExpStack = new Exp[10];

		if(parent !is null)
			parent.mInnerFuncs ~= this;
		else
		{
			mNumParams = 1;
			insertLocal(new Identifier("this", mLocation));
			activateLocals(1);
		}
	}

	public uint tagLocal(uint val)
	{
		if(val > MaxRegisters)
			throw new MDCompileException(mLocation, "Too many locals");

		return (val & ~Instruction.locMask) | Instruction.locLocal;
	}
	
	public uint tagConst(uint val)
	{
		if(val > MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants");
			
		return (val & ~Instruction.locMask) | Instruction.locConst;
	}
	
	public uint tagUpval(uint val)
	{
		if(val > MaxUpvalues)
			throw new MDCompileException(mLocation, "Too many upvalues");

		return (val & ~Instruction.locMask) | Instruction.locUpval;
	}
	
	public uint tagGlobal(uint val)
	{
		if(val > MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants");
			
		return (val & ~Instruction.locMask) | Instruction.locGlobal;
	}
	
	public bool isLocalTag(uint val)
	{
		return ((val & Instruction.locMask) == Instruction.locLocal);
	}
	
	public bool isConstTag(uint val)
	{
		return ((val & Instruction.locMask) == Instruction.locConst);
	}
	
	public bool isUpvalTag(uint val)
	{
		return ((val & Instruction.locMask) == Instruction.locUpval);
	}
	
	public bool isGlobalTag(uint val)
	{
		return ((val & Instruction.locMask) == Instruction.locGlobal);
	}

	public void pushScope()
	{
		Scope* s = new Scope;

		s.breakScope = mScope.breakScope;
		s.continueScope = mScope.continueScope;
		s.varStart = mLocVars.length;
		s.regStart = mFreeReg;

		s.enclosing = mScope;
		mScope = s;
	}

	public void popScope(uint line)
	{
		Scope* s = mScope;
		assert(s !is null, "scope underflow");

		mScope = mScope.enclosing;

		if(s.hasUpval)
			codeClose(line, s.regStart);

		deactivateLocals(s.varStart, s.regStart);

		delete s;
	}
	
	public bool scopeHasUpval()
	{
		return mScope.hasUpval;
	}

	public void beginStringSwitch(uint line, uint srcReg)
	{
		SwitchDesc* sd = new SwitchDesc;
		sd.switchPC = codeR(line, Op.SwitchString, 0, srcReg, 0);
		sd.isString = true;

		sd.prev = mSwitch;
		mSwitch = sd;
	}

	public void beginIntSwitch(uint line, uint srcReg)
	{
		SwitchDesc* sd = new SwitchDesc;
		sd.switchPC = codeR(line, Op.SwitchInt, 0, srcReg, 0);
		sd.isString = false;

		sd.prev = mSwitch;
		mSwitch = sd;
	}

	public void endSwitch()
	{
		SwitchDesc* desc = mSwitch;
		assert(desc, "endSwitch - no switch to end");
		mSwitch = mSwitch.prev;

		mSwitchTables ~= desc;
		mCode[desc.switchPC].rt = mSwitchTables.length - 1;
	}

	public void addCase(Expression exp)
	{
		assert(mSwitch !is null, "adding case outside of a switch");

		IntExp intExp = cast(IntExp)exp;

		if(intExp)
		{
			if(mSwitch.isString == true)
				throw new MDCompileException(exp.mLocation, "Case value must be a string literal");

			int* oldOffset = (intExp.mValue in mSwitch.intOffsets);

			if(oldOffset !is null)
				throw new MDCompileException(exp.mLocation, "Duplicate case value '%s'", intExp.mValue);

			mSwitch.intOffsets[intExp.mValue] = mCode.length - mSwitch.switchPC - 1;

			return;
		}

		StringExp stringExp = cast(StringExp)exp;

		assert(stringExp, "added case is neither int nor string");

		if(mSwitch.isString == false)
			throw new MDCompileException(exp.mLocation, "Case value must be an integer literal");

		int* oldOffset = (stringExp.mValue in mSwitch.stringOffsets);

		if(oldOffset !is null)
			throw new MDCompileException(exp.mLocation, "Duplicate case value '%s'", stringExp.mValue);

		mSwitch.stringOffsets[stringExp.mValue] = mCode.length - mSwitch.switchPC - 1;
	}

	public void addDefault()
	{
		assert(mSwitch !is null, "adding default outside of a switch");
		assert(mSwitch.defaultOffset == -1, "tried to add a second default");

		mSwitch.defaultOffset = mCode.length - mSwitch.switchPC - 1;
	}

	public void setBreakable()
	{
		mScope.breakScope = mScope;
	}

	public void setContinuable()
	{
		mScope.continueScope = mScope;
	}

	protected int searchLocal(dchar[] name, out uint reg)
	{
		for(int i = mLocVars.length - 1; i >= 0; i--)
		{
			if(mLocVars[i].isActive && mLocVars[i].name == name)
			{
				reg = mLocVars[i].reg;
				return i;
			}
		}

		return -1;
	}

	public uint insertLocal(Identifier ident)
	{
		uint dummy;
		int index = searchLocal(ident.mName, dummy);
		
		if(index != -1)
		{
			throw new MDCompileException(ident.mLocation, "Local '%s' conflicts with previous definition at %s",
				ident.mName, mLocVars[index].location.toString());
		}

		mLocVars.length = mLocVars.length + 1;

		with(mLocVars[$ - 1])
		{
			name = ident.mName;
			location = ident.mLocation;
			reg = pushRegister();
			isActive = false;
		}

		return mLocVars[$ - 1].reg;
	}

	public void activateLocals(uint num)
	{
		for(int i = mLocVars.length - 1; i >= cast(int)(mLocVars.length - num); i--)
		{
			debug(VARACTIVATE) writefln("activating %s %s reg %s", mLocVars[i].name, mLocVars[i].location.toString(), mLocVars[i].reg);
			mLocVars[i].isActive = true;
		}
	}

	public void deactivateLocals(int varStart, int regTo)
	{
		for(int i = mLocVars.length - 1; i >= varStart; i--)
		{
			if(mLocVars[i].reg >= regTo && mLocVars[i].isActive)
			{
				debug(VARACTIVATE) writefln("deactivating %s %s reg %s", mLocVars[i].name, mLocVars[i].location.toString(), mLocVars[i].reg);
				popRegister(mLocVars[i].reg);
				mLocVars[i].isActive = false;
			}
		}
	}

	public uint nextRegister()
	{
		return mFreeReg;
	}

	public uint pushRegister()
	{
		debug(REGPUSHPOP) writefln("push ", mFreeReg);
		mFreeReg++;

		if(mFreeReg > MaxRegisters)
			throw new MDCompileException(mLocation, "Too many registers");

		if(mFreeReg > mStackSize)
			mStackSize = mFreeReg;

		return mFreeReg - 1;
	}

	public void popRegister(uint r)
	{
		mFreeReg--;
		debug(REGPUSHPOP) writefln("pop ", mFreeReg, ", ", r);

		assert(mFreeReg >= 0, "temp reg underflow");
		assert(mFreeReg == r, "reg not freed in order");
	}
	
	protected void printExpStack()
	{
		writefln("Expression Stack");
		writefln("----------------");

		for(int i = 0; i < mExpSP; i++)
			writefln(i, ": ", mExpStack[i].toString());
			
		writefln();
	}

	protected Exp* pushExp()
	{
		if(mExpSP >= mExpStack.length)
			mExpStack.length = mExpStack.length * 2;

		Exp* ret = &mExpStack[mExpSP];
		mExpSP++;

		ret.isTempReg = false;
		ret.isTempReg2 = false;
		ret.isTempReg3 = false;

		return ret;
	}

	protected Exp* popExp()
	{
		mExpSP--;

		assert(mExpSP >= 0, "exp stack underflow");

		return &mExpStack[mExpSP];
	}
	
	public void dup()
	{
		Exp* src = &mExpStack[mExpSP - 1];
		Exp* e = pushExp();
		*e = *src;
	}

	public void pushNull()
	{
		Exp* e = pushExp();
		e.type = ExpType.Null;
	}

	public void pushBool(bool value)
	{
		Exp* e = pushExp();

		if(value == true)
			e.type = ExpType.True;
		else
			e.type = ExpType.False;
	}

	public void pushInt(int value)
	{
		pushConst(codeIntConst(value));
	}

	public void pushFloat(float value)
	{
		pushConst(codeFloatConst(value));
	}

	public void pushString(dchar[] value)
	{
		pushConst(codeStringConst(value));
	}
	
	public void pushChar(dchar value)
	{
		pushConst(codeCharConst(value));
	}

	public void pushConst(uint index)
	{
		Exp* e = pushExp();
		e.type = ExpType.Const;
		e.index = tagConst(index);
	}
	
	public void pushNewGlobal(Identifier name)
	{
		Exp* e = pushExp();
		e.type = ExpType.NewGlobal;
		e.index = tagConst(codeStringConst(name.mName));
	}
	
	public void pushThis()
	{
		Exp* e = pushExp();
		e.type = ExpType.Var;
		e.index = tagLocal(0);
	}

	public void pushVar(Identifier name)
	{
		Exp* e = pushExp();

		const Local = 0;
		const Upvalue = 1;
		const Global = 2;

		uint varType = Local;

		uint searchVar(FuncState s, bool isOriginal = true)
		{
			uint findUpval()
			{
				for(int i = 0; i < s.mUpvals.length; i++)
				{
					if(s.mUpvals[i].name == name.mName)
					{
						if((s.mUpvals[i].isUpvalue && varType == Upvalue) || (!s.mUpvals[i].isUpvalue && varType == Local))
							return i;
					}
				}

				UpvalDesc ud;

				ud.name = name.mName;
				ud.isUpvalue = (varType == Upvalue);
				ud.index = e.index;

				s.mUpvals ~= ud;

				if(mUpvals.length > MaxUpvalues)
					throw new MDCompileException(mLocation, "Too many upvalues in function");

				return s.mUpvals.length - 1;
			}

			if(s is null)
			{
				varType = Global;
				return Global;
			}

			uint reg;
			int index = s.searchLocal(name.mName, reg);

			if(index == -1)
			{
				if(searchVar(s.mParent, false) == Global)
					return Global;

				e.index = tagUpval(findUpval());
				varType = Upvalue;
				return Upvalue;
			}
			else
			{
				varType = Local;
				e.index = tagLocal(reg);

				if(isOriginal == false)
				{
					for(Scope* sc = s.mScope; sc !is null; sc = sc.enclosing)
					{
						if(sc.regStart <= reg)
						{
							sc.hasUpval = true;
							break;
						}
					}
				}

				return Local;
			}
		}

		if(searchVar(this) == Global)
			e.index = tagGlobal(codeStringConst(name.mName));
			
		e.type = ExpType.Var;
	}
	
	public void pushVararg()
	{
		Exp* e = pushExp();
		e.type = ExpType.Vararg;
	}

	public void pushTempReg(uint idx)
	{
		Exp* e = pushExp();

		e.type = ExpType.Src;
		e.index = idx;
		e.isTempReg = true;
	}

	public void pushClosure(FuncState fs)
	{
		Exp* e = pushExp();

		int index = -1;

		foreach(uint i, FuncState child; mInnerFuncs)
		{
			if(fs is child)
			{
				index = i;
				break;
			}
		}

		assert(index != -1, "fs is not a child proto");

		e.type = ExpType.Closure;
		e.index = index;
	}

	public void freeExpTempRegs(Exp* e)
	{
		if(e.isTempReg3)
		{
			popRegister(e.index3);
			e.isTempReg3 = false;
		}
			
		if(e.isTempReg2)
		{
			popRegister(e.index2);
			e.isTempReg2 = false;
		}
			
		if(e.isTempReg)
		{
			popRegister(e.index);
			e.isTempReg = false;
		}
	}
	
	public void popToNothing()
	{
		if(mExpSP == 0)
			return;

		Exp* src = popExp();

		if(src.type == ExpType.Call || src.type == ExpType.Yield)
			mCode[src.index].rt = 1;

		freeExpTempRegs(src);
	}

	public void popAssign(uint line)
	{
		Exp* src = popExp();
		Exp* dest = popExp();

		switch(dest.type)
		{
			case ExpType.Var:
				moveTo(line, dest.index, src);
				break;

			case ExpType.NewGlobal:
				toSource(line, src);
				
				codeR(line, Op.NewGlobal, 0, src.index, dest.index);
				
				freeExpTempRegs(src);
				freeExpTempRegs(dest);
				break;

			case ExpType.Indexed:
				toSource(line, src);

				codeR(line, Op.IndexAssign, dest.index, dest.index2, src.index);

				freeExpTempRegs(src);
				freeExpTempRegs(dest);
				break;
				
			case ExpType.Sliced:
				toSource(line, src);
				
				codeR(line, Op.SliceAssign, dest.index, src.index, 0);
				
				freeExpTempRegs(src);
				freeExpTempRegs(dest);
				break;
		}
	}

	public void popMoveTo(uint line, uint dest)
	{
		Exp* src = popExp();
		moveTo(line, dest, src);
	}

	public void moveTo(uint line, uint dest, Exp* src)
	{
		switch(src.type)
		{
			case ExpType.Null:
				codeR(line, Op.LoadNull, dest, 0, 0);
				break;

			case ExpType.True:
				codeR(line, Op.LoadBool, dest, 1, 0);
				break;

			case ExpType.False:
				codeR(line, Op.LoadBool, dest, 0, 0);
				break;

			case ExpType.Const:
				codeR(line, Op.Move, dest, src.index, 0);
				break;

			case ExpType.Var:
				if(dest != src.index)
					codeR(line, Op.Move, dest, src.index, 0);
				break;

			case ExpType.Indexed:
				codeR(line, Op.Index, dest, src.index, src.index2);
				freeExpTempRegs(src);
				break;
				
			case ExpType.Sliced:
				codeR(line, Op.Slice, dest, src.index, 0);
				freeExpTempRegs(src);
				break;

			case ExpType.Vararg:
				if(isLocalTag(dest))
					codeI(line, Op.Vararg, dest, 2);
				else
				{
					assert(!isConstTag(dest), "moveTo vararg dest is const");
					uint tempReg = pushRegister();
					codeI(line, Op.Vararg, tempReg, 2);
					codeR(line, Op.Move, dest, tempReg, 0);
					popRegister(tempReg);
				}
				break;

			case ExpType.Closure:
				codeI(line, Op.Closure, dest, src.index);

				foreach(inout UpvalDesc ud; mInnerFuncs[src.index].mUpvals)
				{
					if(ud.isUpvalue)
						codeR(line, Op.Move, 1, ud.index, 0);
					else
						codeR(line, Op.Move, 0, ud.index, 0);
				}

				break;

			case ExpType.Call, ExpType.Yield:
				mCode[src.index].rt = 2;

				if(dest != src.index2)
					codeR(line, Op.Move, dest, src.index2, 0);

				freeExpTempRegs(src);
				break;

			case ExpType.NeedsDest:
				mCode[src.index].rd = dest;
				break;

			case ExpType.Src:
				if(dest != src.index)
					codeR(line, Op.Move, dest, src.index, 0);

				freeExpTempRegs(src);
				break;

			default:
				assert(false, "moveTo switch");
		}
	}

	public void popToRegisters(uint line, uint reg, int num)
	{
		Exp* src = popExp();

		switch(src.type)
		{
			case ExpType.Vararg:
				codeI(line, Op.Vararg, reg, num + 1);
				break;

			case ExpType.Call, ExpType.Yield:
				assert(src.index2 == reg, "pop to regs - trying to pop func call or yield to different reg");
				mCode[src.index].rt = num + 1;
				freeExpTempRegs(src);
				break;

			default:
				assert(false, "pop to regs switch");
		}
	}

	public void pushBinOp(uint line, Op type, uint rs, uint rt)
	{
		Exp* dest = pushExp();
		dest.type = ExpType.NeedsDest;
		dest.index = codeR(line, type, 0, rs, rt);
	}
	
	public void popReflexOp(uint line, Op type, uint rd, uint rs)
	{
		Exp* dest = pushExp();
		dest.type = ExpType.NeedsDest;
		dest.index = codeR(line, type, rd, rs, 0);

		popAssign(line);
	}

	public void popUnOp(uint line, Op type)
	{
		Exp* src = popExp();

		toSource(line, src);

		uint pc = codeR(line, type, 0, src.index, 0);

		freeExpTempRegs(src);

		Exp* dest = pushExp();
		dest.type = ExpType.NeedsDest;
		dest.index = pc;
	}

	public void pushCall(uint line, uint firstReg, uint numRegs)
	{
		Exp* e = pushExp();
		e.type = ExpType.Call;
		e.index = codeR(line, Op.Call, firstReg, numRegs, 0);
		e.index2 = firstReg;
		e.isTempReg2 = true;
	}
	
	public void pushYield(uint line, uint firstReg, uint numRegs)
	{
		Exp* e = pushExp();
		e.type = ExpType.Yield;
		e.index = codeR(line, Op.Yield, firstReg, numRegs, 0);
		e.index2 = firstReg;
	}
	
	public void makeTailcall()
	{
		assert(mCode[$ - 1].opcode == Op.Call, "need call to make tailcall");
		mCode[$ - 1].opcode = Op.Tailcall;
	}

	public void popMoveFromReg(uint line, uint srcReg)
	{
		codeMoveFromReg(line, popExp(), srcReg);
	}

	public void codeMoveFromReg(uint line, Exp* dest, uint srcReg)
	{
		switch(dest.type)
		{
			case ExpType.Var:
				if(dest.index != srcReg)
					codeR(line, Op.Move, dest.index, srcReg, 0);
				break;
				
			case ExpType.NewGlobal:
				codeR(line, Op.NewGlobal, 0, srcReg, dest.index);
				break;

			case ExpType.Indexed:
				codeR(line, Op.IndexAssign, dest.index, dest.index2, srcReg);
				freeExpTempRegs(dest);
				break;
				
			case ExpType.Sliced:
				codeR(line, Op.SliceAssign, dest.index, srcReg, 0);
				freeExpTempRegs(dest);
				break;

			default:
				assert(false);
		}
	}

	public void popField(uint line, Identifier field)
	{
		pushString(field.mName);
		popIndex(line);
	}

	public void popIndex(uint line)
	{
		assert(mExpSP > 1, "pop index from nothing");

		Exp* index = popExp();
		Exp* e = &mExpStack[mExpSP - 1];

		toSource(line, e);
		toSource(line, index);

		e.index2 = index.index;
		e.isTempReg2 = index.isTempReg;
		e.type = ExpType.Indexed;
	}

	public void pushSlice(uint line, uint reg)
	{
		Exp* e = pushExp();
		e.index = pushRegister();
		
		assert(e.index == reg, "push slice reg wrong");

		e.isTempReg = true;
		e.index2 = pushRegister();
		e.isTempReg2 = true;
		e.index3 = pushRegister();
		e.isTempReg3 = true;
		e.type = ExpType.Sliced;
	}

	public void popSource(uint line, out Exp n)
	{
		n = *popExp();
		toSource(line, &n);
	}
	
	public void pushSource(uint line)
	{
		dup();
		topToSource(line, false);
	}

	public void topToSource(uint line, bool cleanup = true)
	{
		toSource(line, &mExpStack[mExpSP - 1], cleanup);
	}

	protected void toSource(uint line, Exp* e, bool cleanup = true)
	{
		Exp temp;
		temp.type = ExpType.Src;

		switch(e.type)
		{
			case ExpType.Null:
				temp.index = tagConst(codeNullConst());
				break;

			case ExpType.True:
				temp.index = tagConst(codeBoolConst(true));
				break;

			case ExpType.False:
				temp.index = tagConst(codeBoolConst(false));
				break;

			case ExpType.Const:
				temp.index = e.index;
				break;

			case ExpType.Var:
				temp.index = e.index;
				break;

			case ExpType.Indexed:
				if(cleanup)
					freeExpTempRegs(e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op.Index, temp.index, e.index, e.index2);
				break;
				
			case ExpType.Sliced:
				if(cleanup)
					freeExpTempRegs(e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op.Slice, temp.index, e.index, 0);
				break;

			case ExpType.NeedsDest:
				temp.index = pushRegister();
				mCode[e.index].rd = temp.index;
				temp.isTempReg = true;
				break;

			case ExpType.Call, ExpType.Yield:
				mCode[e.index].rt = 2;
				temp.index = e.index2;
				temp.isTempReg = e.isTempReg2;
				break;

			case ExpType.Closure:
				temp.index = pushRegister();
				codeI(line, Op.Closure, temp.index, e.index);

				foreach(inout UpvalDesc ud; mInnerFuncs[e.index].mUpvals)
				{
					if(ud.isUpvalue)
						codeR(line, Op.Move, 1, ud.index, 0);
					else
						codeR(line, Op.Move, 0, ud.index, 0);
				}

				temp.isTempReg = true;
				break;

			case ExpType.Src:
				temp = *e;
				break;

			case ExpType.Vararg:
				temp.index = pushRegister();
				codeI(line, Op.Vararg, temp.index, 2);
				temp.isTempReg = true;
				break;

			default:
				assert(false, "toSource switch");
		}

		*e = temp;
	}

	public void codeClose(uint line)
	{
		if(mScope.hasUpval)
			codeI(line, Op.Close, mScope.regStart, 0);
	}

	public void codeClose(uint line, uint reg)
	{
		codeI(line, Op.Close, reg, 0);
	}

	public void patchJumpToHere(InstRef* src)
	{
		mCode[src.pc].imm = mCode.length - src.pc - 1;
	}

	public void patchJumpTo(InstRef* src, InstRef* dest)
	{
		mCode[src.pc].imm = dest.pc - src.pc - 1;
	}

	public InstRef* getLabel()
	{
		InstRef* l = new InstRef;
		l.pc = mCode.length;
		return l;
	}

	public void invertJump(InstRef* i)
	{
		mCode[i.pc].rd = !mCode[i.pc].rd;
	}

	public void patchContinues(InstRef* dest)
	{
		for(InstRef* c = mScope.continues; c !is null; )
		{
			patchJumpTo(c, dest);

			InstRef* next = c.trueList;
			delete c;
			c = next;
		}
	}

	public void patchBreaksToHere()
	{
		for(InstRef* c = mScope.breaks; c !is null; )
		{
			patchJumpToHere(c);

			InstRef* next = c.trueList;
			delete c;
			c = next;
		}
	}

	public void patchContinuesToHere()
	{
		for(InstRef* c = mScope.continues; c !is null; )
		{
			patchJumpToHere(c);

			InstRef* next = c.trueList;
			delete c;
			c = next;
		}
	}

	public void patchTrueTo(InstRef* i, InstRef* dest)
	{
		for(InstRef* t = i.trueList; t !is null; )
		{
			patchJumpTo(t, dest);

			InstRef* next = t.trueList;
			delete t;
			t = next;
		}

		i.trueList = null;
	}

	public void patchTrueToHere(InstRef* i)
	{
		for(InstRef* t = i.trueList; t !is null; )
		{
			patchJumpToHere(t);

			InstRef* next = t.trueList;
			delete t;
			t = next;
		}

		i.trueList = null;
	}

	public void patchFalseToHere(InstRef* i)
	{
		for(InstRef* f = i.falseList; f !is null; )
		{
			patchJumpToHere(f);

			InstRef* next = f.falseList;
			delete f;
			f = next;
		}

		i.falseList = null;
	}

	public void codeJump(uint line, InstRef* dest)
	{
		codeJ(line, Op.Jmp, true, dest.pc - mCode.length - 1);
	}

	public InstRef* makeJump(uint line, Op type = Op.Jmp, bool isTrue = true)
	{
		InstRef* i = new InstRef;
		i.pc = codeJ(line, type, isTrue, 0);
		return i;
	}

	public InstRef* codeCatch(uint line, out uint checkReg)
	{
		InstRef* i = new InstRef;
		i.pc = codeI(line, Op.PushCatch, mFreeReg, 0);
		checkReg = mFreeReg;
		return i;
	}

	public InstRef* codeFinally(uint line)
	{
		InstRef* i = new InstRef;
		i.pc = codeI(line, Op.PushFinally, 0, 0);
		return i;
	}

	public void codeContinue(Location location)
	{
		if(mScope.continueScope is null)
			throw new MDCompileException(location, "No continuable control structure");

		if(mScope.continueScope.hasUpval)
			codeClose(location.line, mScope.continueScope.regStart);

		InstRef* i = new InstRef;
		i.pc = codeJ(location.line, Op.Jmp, 1, 0);
		i.trueList = mScope.continueScope.continues;
		mScope.continueScope.continues = i;
	}

	public void codeBreak(Location location)
	{
		if(mScope.breakScope is null)
			throw new MDCompileException(location, "No breakable control structure");

		if(mScope.breakScope.hasUpval)
			codeClose(location.line, mScope.breakScope.regStart);

		InstRef* i = new InstRef;
		i.pc = codeJ(location.line, Op.Jmp, 1, 0);
		i.trueList = mScope.breakScope.breaks;
		mScope.breakScope.breaks = i;
	}
	
	public int codeStringConst(dchar[] c)
	{
		foreach(uint i, MDValue v; mConstants)
			if(v.isString() && v.as!(MDString)() == c)
				return i;

		MDValue v = c;
		mConstants ~= v;

		if(mConstants.length > MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}
	
	public int codeBoolConst(bool b)
	{
		foreach(uint i, MDValue v; mConstants)
			if(v.isBool() && v.as!(bool)() == b)
				return i;

		MDValue v = b;
		mConstants ~= v;

		if(mConstants.length > MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}

	public int codeIntConst(int x)
	{
		foreach(uint i, MDValue v; mConstants)
			if(v.isInt() && v.as!(int)() == x)
				return i;

		MDValue v = x;
		mConstants ~= v;

		if(mConstants.length > MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}
	
	public int codeCharConst(dchar x)
	{
		foreach(uint i, MDValue v; mConstants)
			if(v.isChar() && v.as!(dchar)() == x)
				return i;

		MDValue v = x;
		mConstants ~= v;

		if(mConstants.length > MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}

	public int codeFloatConst(float x)
	{
		foreach(uint i, MDValue v; mConstants)
			if(v.isFloat() && v.as!(float)() == x)
				return i;

		MDValue v = x;
		mConstants ~= v;

		if(mConstants.length > MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}

	public int codeNullConst()
	{
		foreach(uint i, MDValue v; mConstants)
			if(v.isNull())
				return i;

		MDValue v;
		v.setNull();

		mConstants ~= v;

		if(mConstants.length > MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}

	public void codeNulls(uint line, uint reg, uint num)
	{
		codeI(line, Op.LoadNulls, reg, num);
	}

	public uint codeR(uint line, Op opcode, ushort dest, ushort src1, ushort src2)
	{
		Instruction i;
		i.opcode = opcode;
		i.rd = dest;
		i.rs = src1;
		i.rt = src2;

		debug(WRITECODE) writefln(i.toString());

		mLineInfo ~= line;
		mCode ~= i;
		return mCode.length - 1;
	}

	public uint codeI(uint line, Op opcode, ushort dest, uint imm)
	{
		Instruction i;
		i.opcode = opcode;
		i.rd = dest;
		i.uimm = imm;

		debug(WRITECODE) writefln(i.toString());

		mLineInfo ~= line;
		mCode ~= i;
		return mCode.length - 1;
	}

	public uint codeJ(uint line, Op opcode, ushort dest, int offs)
	{
		Instruction i;
		i.opcode = opcode;
		i.rd = dest;
		i.imm = offs;
		
		debug(WRITECODE) writefln(i.toString());

		mLineInfo ~= line;
		mCode ~= i;
		return mCode.length - 1;
	}

	public void showMe(uint tab = 0)
	{
		writefln(string.repeat("\t", tab), "Function at ", mLocation.toString(), " (guessed name: %s)", mGuessedName);
		writefln(string.repeat("\t", tab), "Num params: ", mNumParams, " Vararg: ", mIsVararg, " Stack size: ", mStackSize);

		foreach(uint i, FuncState s; mInnerFuncs)
		{
			writefln(string.repeat("\t", tab + 1), "Inner Func ", i);
			s.showMe(tab + 1);
		}
		
		foreach(uint i, inout SwitchDesc* t; mSwitchTables)
		{
			writef(string.repeat("\t", tab + 1), "Switch Table ", i);

			if(t.isString)
			{
				writefln(" - String");

				foreach(dchar[] index; t.stringOffsets.keys.sort)
					writefln(string.repeat("\t", tab + 2), "\"%s\" => %s", index, t.stringOffsets[index]);
			}
			else
			{
				writefln(" - Int");

				foreach(int index; t.intOffsets.keys.sort)
					writefln(string.repeat("\t", tab + 2), "%s => %s", index, t.intOffsets[index]);
			}

			writefln(string.repeat("\t", tab + 2), "Default: ", t.defaultOffset);
		}

		foreach(v; mLocVars)
			writefln(string.repeat("\t", tab + 1), "Local ", v.name, "(at %s, reg %s)", v.location.toString(), v.reg);

		foreach(i, u; mUpvals)
			writefln(string.repeat("\t", tab + 1), "Upvalue %s: %s : %s (%s)", i, u.name, u.index, u.isUpvalue ? "upval" : "local");

		foreach(i, c; mConstants)
		{
			switch(c.type)
			{
				case MDValue.Type.Null:
					writefln(string.repeat("\t", tab + 1), "Const %s: null", i);
					break;

				case MDValue.Type.Int:
					writefln(string.repeat("\t", tab + 1), "Const %s: %s", i, c.as!(int)());
					break;

				case MDValue.Type.Float:
					writefln(string.repeat("\t", tab + 1), "Const %s: %sf", i, c.as!(float)());
					break;

				case MDValue.Type.Char:
					writefln(string.repeat("\t", tab + 1), "Const %s: '%s'", i, c.as!(dchar)());
					break;

				case MDValue.Type.String:
					writefln(string.repeat("\t", tab + 1), "Const %s: \"%s\"", i, c.as!(dchar[])());
					break;

				default:
					assert(false);
			}
		}

		foreach(i, inst; cast(Instruction[])mCode)
			writefln(string.repeat("\t", tab + 1), "[%3s:%4s] ", i, mLineInfo[i], inst.toString());
	}

	protected MDFuncDef toFuncDef()
	{
		MDFuncDef ret = new MDFuncDef();

		ret.mIsVararg = mIsVararg;
		ret.mLocation = mLocation;
		ret.mGuessedName = mGuessedName;

		ret.mInnerFuncs.length = mInnerFuncs.length;

		for(int i = 0; i < mInnerFuncs.length; i++)
			ret.mInnerFuncs[i] = mInnerFuncs[i].toFuncDef();
			
		ret.mConstants = mConstants;
		ret.mNumParams = mNumParams;
		ret.mNumUpvals = mUpvals.length;
		ret.mStackSize = mStackSize;
		ret.mCode = mCode;
		ret.mLineInfo = mLineInfo;

		ret.mLocVarDescs.length = mLocVars.length;

		for(int i = 0; i < mLocVars.length; i++)
		{
			with(mLocVars[i])
			{
				ret.mLocVarDescs[i].name = name;
				ret.mLocVarDescs[i].location = location;
				ret.mLocVarDescs[i].reg = reg;
			}
		}
		
		ret.mUpvalNames.length = mUpvals.length;
		
		for(int i = 0; i < mUpvals.length; i++)
			ret.mUpvalNames[i] = mUpvals[i].name;

		ret.mSwitchTables.length = mSwitchTables.length;

		for(int i = 0; i < mSwitchTables.length; i++)
		{
			with(*mSwitchTables[i])
			{
				ret.mSwitchTables[i].isString = isString;

				if(isString)
					ret.mSwitchTables[i].stringOffsets = stringOffsets;
				else
					ret.mSwitchTables[i].intOffsets = intOffsets;

				ret.mSwitchTables[i].defaultOffset = defaultOffset;
			}
		}

		return ret;
	}
}

class ClassDef
{
	protected Location mLocation;
	protected Location mEndLocation;
	protected Identifier mName;
	protected Expression mBaseClass;
	protected FuncDef[] mMethods;

	struct Field
	{
		dchar[] name;
		Expression initializer;
	}

	protected Field[] mFields;

	public this(Identifier name, Expression baseClass, FuncDef[] methods, Field[] fields, Location location, Location endLocation)
	{
		mName = name;
		mBaseClass = baseClass;
		mMethods = methods;
		mFields = fields;
		mLocation = location;
		mEndLocation = endLocation;

		if(mName is null)
			mName = new Identifier("<literal at " ~ utf.toUTF32(mLocation.toString()) ~ ">", mLocation);
	}

	public static void parseBody(Location location, inout Token* t, out FuncDef[] methods, out Field[] fields, out Location endLocation)
	{
		t.check(Token.Type.LBrace);
		t = t.nextToken;
		
		methods = new FuncDef[10];
		int iMethod = 0;

		void addMethod(FuncDef m)
		{
			if(iMethod >= methods.length)
				methods.length = methods.length * 2;

			methods[iMethod] = m;
			iMethod++;
		}

		fields = new Field[10];
		int iField = 0;

		void addField(dchar[] name, Expression v)
		{
			if(iField >= fields.length)
				fields.length = fields.length * 2;

			fields[iField].name = name;
			fields[iField].initializer = v;

			iField++;
		}

		while(t.type != Token.Type.RBrace)
		{
			switch(t.type)
			{
				case Token.Type.Function:
					addMethod(FuncDef.parseSimple(t));
					break;
					
				case Token.Type.Ident:
					Identifier id = Identifier.parse(t);

					Expression v;

					if(t.type == Token.Type.Assign)
					{
						t = t.nextToken;
						v = Expression.parse(t);
					}
					else
						v = new NullExp(id.mLocation);

					dchar[] name = id.mName;

					t.check(Token.Type.Semicolon);
					t = t.nextToken;
					
					addField(name, v);
					break;

				case Token.Type.EOF:
					throw new MDCompileException(t.location, "Class at ", location.toString(), " is missing its closing brace");

				default:
					break;
			}
		}

		methods.length = iMethod;
		fields.length = iField;

		if(t.type != Token.Type.RBrace)
			throw new MDCompileException(t.location, "Class at ", location.toString(), " is missing its closing brace");
			
		endLocation = t.location;

		t = t.nextToken;
	}

	public static Expression parseBaseClass(inout Token* t)
	{
		Expression baseClass;

		if(t.type == Token.Type.Colon)
		{
			t = t.nextToken;
			baseClass = Expression.parse(t);
		}
		else
			baseClass = new NullExp(t.location);

		return baseClass;
	}
	
	public void codeGen(FuncState s)
	{
		mBaseClass.codeGen(s);
		Exp base;
		s.popSource(mLocation.line, base);
		s.freeExpTempRegs(&base);

		uint destReg = s.pushRegister();
		uint nameConst = s.tagConst(s.codeStringConst(mName.mName));
		s.codeR(mLocation.line, Op.Class, destReg, nameConst, base.index);

		foreach(Field field; mFields)
		{
			uint index = s.tagConst(s.codeStringConst(field.name));

			field.initializer.codeGen(s);
			Exp val;
			s.popSource(field.initializer.mEndLocation.line, val);

			s.codeR(field.initializer.mEndLocation.line, Op.IndexAssign, destReg, index, val.index);

			s.freeExpTempRegs(&val);
		}

		foreach(FuncDef method; mMethods)
		{
			uint index = s.tagConst(s.codeStringConst(method.mName.mName));

			method.codeGen(s);
			Exp val;
			s.popSource(method.mEndLocation.line, val);

			s.codeR(method.mEndLocation.line, Op.IndexAssign, destReg, index, val.index);

			s.freeExpTempRegs(&val);
		}

		s.pushTempReg(destReg);
	}

	public ClassDef fold()
	{
		mBaseClass = mBaseClass.fold();
		
		foreach(inout field; mFields)
			field.initializer = field.initializer.fold();
			
		foreach(inout method; mMethods)
			method = method.fold();
		
		return this;
	}
}

class FuncDef
{
	protected Location mLocation;
	protected Location mEndLocation;
	protected Identifier[] mParams;
	protected bool mIsVararg;
	protected Statement mBody;
	protected Identifier mName;

	public this(Location location, Location endLocation, Identifier[] params, bool isVararg, Statement funcBody, Identifier name)
	{
		mLocation = location;
		mEndLocation = endLocation;
		mParams = params;
		mIsVararg = isVararg;
		mBody = funcBody;
		mName = name;
	}

	public static FuncDef parseSimple(inout Token* t)
	{
		Location location = t.location;
		
		t.check(Token.Type.Function);
		t = t.nextToken;

		Identifier name = Identifier.parse(t);

		bool isVararg;
		Identifier[] params = parseParams(t, isVararg);

		CompoundStatement funcBody = CompoundStatement.parse(t);

		return new FuncDef(location, funcBody.mEndLocation, params, isVararg, funcBody, name);
	}
	
	public static FuncDef parseLiteral(inout Token* t)
	{
		Location location = t.location;
		
		t.check(Token.Type.Function);
		t = t.nextToken;

		Identifier name;
		
		if(t.type == Token.Type.Ident)
			name = Identifier.parse(t);
		else
			name = new Identifier("<literal at " ~ utf.toUTF32(location.toString()) ~ ">", location);

		bool isVararg;
		Identifier[] params = parseParams(t, isVararg);

		Statement funcBody;
		
		if(t.type == Token.Type.LBrace)
			funcBody = CompoundStatement.parse(t);
		else
			funcBody = new ReturnStatement(Expression.parse(t));

		return new FuncDef(location, funcBody.mEndLocation, params, isVararg, funcBody, name);
	}

	public static Identifier[] parseParams(inout Token* t, out bool isVararg)
	{
		Identifier[] ret;
		
		ret ~= new Identifier("this", t.location);

		t.check(Token.Type.LParen);
		t = t.nextToken;
			
		if(t.type == Token.Type.Vararg)
		{
			isVararg = true;
			t = t.nextToken;
		}
		else if(t.type != Token.Type.RParen)
		{
			while(true)
			{
				if(t.type == Token.Type.Vararg)
				{
					isVararg = true;
					t = t.nextToken;
					break;
				}

				ret ~= Identifier.parse(t);

				if(t.type == Token.Type.RParen)
					break;

				t.check(Token.Type.Comma);
				t = t.nextToken;
			}
		}
		
		t.check(Token.Type.RParen);
		t = t.nextToken;
		
		return ret;
	}

	public void codeGen(FuncState s)
	{
		FuncState fs = new FuncState(mLocation, mName.mName, s);

		fs.mIsVararg = mIsVararg;
		fs.mNumParams = mParams.length;

		foreach(Identifier p; mParams)
			fs.insertLocal(p);

		fs.activateLocals(mParams.length);

		mBody.codeGen(fs);
		fs.codeI(mBody.mEndLocation.line, Op.Ret, 0, 1);
		
		fs.popScope(mBody.mEndLocation.line);

		s.pushClosure(fs);
	}

	public FuncDef fold()
	{
		mBody = mBody.fold();
		return this;
	}
}

class Module
{
	protected Location mLocation;
	protected Location mEndLocation;
	protected ModuleDeclaration mModDecl;
	protected dchar[][][] mImports;
	protected Statement[] mStatements;

	public this(Location location, Location endLocation, ModuleDeclaration modDecl, dchar[][][] imports, Statement[] statements)
	{
		mLocation = location;
		mEndLocation = endLocation;
		mModDecl = modDecl;
		mImports = imports;
		mStatements = statements;
	}

	public static Module parse(inout Token* t)
	{
		Location location = t.location;
		ModuleDeclaration modDecl = ModuleDeclaration.parse(t);

		Statement[] statements = new Statement[32];
		uint i = 0;

		bool[dchar[][]] imports;

		void add(Statement s)
		{
			if(i >= statements.length)
				statements.length = statements.length * 2;

			statements[i] = s;
			i++;
		}

		void addImport(ImportStatement imp)
		{
			imports[Identifier.toStringArray(imp.mNames)] = true;
		}

		while(t.type != Token.Type.EOF)
		{
			if(t.type == Token.Type.Import)
				addImport(ImportStatement.parse(t));
			else
				add(Statement.parse(t));
		}

		t.check(Token.Type.EOF);

		statements.length = i;

		return new Module(location, t.location, modDecl, imports.keys.sort, statements);
	}

	public MDModuleDef codeGen()
	{
		MDModuleDef def = new MDModuleDef();

		def.mName.length = mModDecl.mNames.length;

		foreach(i, ident; mModDecl.mNames)
			def.mName[i] = ident.mName;

		def.mImports = mImports;

		FuncState fs = new FuncState(mLocation, "module " ~ Identifier.toLongString(mModDecl.mNames));
		fs.mIsVararg = true;

		try
		{
			foreach(inout s; mStatements)
			{
				s = s.fold();
				s.codeGen(fs);
			}

			fs.codeI(mEndLocation.line, Op.Ret, 0, 1);
		}
		finally
		{
			//showMe(); fs.showMe(); fflush(stdout);
			//fs.printExpStack();
		}

		assert(fs.mExpSP == 0, "module - not all expressions have been popped");

		def.mFunc = fs.toFuncDef();

		return def;
	}
	
	public void showMe()
	{
		writefln("module %s", Identifier.toLongString(mModDecl.mNames));

		foreach(name; mImports)
			writefln("import %s", djoin(name, '.'));
	}
}

class ModuleDeclaration
{
	protected Identifier[] mNames;
	
	public this(Identifier[] names)
	{
		mNames = names;
	}

	public static ModuleDeclaration parse(inout Token* t)
	{
		t.check(Token.Type.Module);
		t = t.nextToken;
		
		Identifier[] names;
		names ~= Identifier.parse(t);
		
		while(t.type == Token.Type.Dot)
		{
			t = t.nextToken;
			names ~= Identifier.parse(t);
		}
		
		t.check(Token.Type.Semicolon);
		t = t.nextToken;
		
		return new ModuleDeclaration(names);
	}
}

abstract class Statement
{
	protected Location mLocation;
	protected Location mEndLocation;

	public this(Location location, Location endLocation)
	{
		mLocation = location;
		mEndLocation = endLocation;
	}

	public static Statement parse(inout Token* t)
	{
		Location location = t.location;

		switch(t.type)
		{
			case
				Token.Type.CharLiteral,
				Token.Type.Dec,
				Token.Type.Dot,
				Token.Type.False,
				Token.Type.FloatLiteral,
				Token.Type.Ident,
				Token.Type.Inc,
				Token.Type.IntLiteral,
				Token.Type.LParen,
				Token.Type.Null,
				Token.Type.StringLiteral,
				Token.Type.Sub,
				Token.Type.This,
				Token.Type.True,
				Token.Type.Yield:

				return ExpressionStatement.parse(t);

			case Token.Type.Local, Token.Type.Global, Token.Type.Function, Token.Type.Class:
				return DeclarationStatement.parse(t);
				
			case Token.Type.LBrace:
				CompoundStatement s = CompoundStatement.parse(t);
				return new ScopeStatement(s.mLocation, s.mEndLocation, s);

			case Token.Type.If:
				return IfStatement.parse(t);

			case Token.Type.While:
				return WhileStatement.parse(t);

			case Token.Type.Do:
				return DoWhileStatement.parse(t);

			case Token.Type.For:
				return ForStatement.parse(t);

			case Token.Type.Foreach:
				return ForeachStatement.parse(t);

			case Token.Type.Switch:
				return SwitchStatement.parse(t);

			case Token.Type.Case:
				return CaseStatement.parse(t);

			case Token.Type.Default:
				return DefaultStatement.parse(t);

			case Token.Type.Continue:
				return ContinueStatement.parse(t);

			case Token.Type.Break:
				return BreakStatement.parse(t);

			case Token.Type.Return:
				return ReturnStatement.parse(t);

			case Token.Type.Try:
				return TryCatchStatement.parse(t);

			case Token.Type.Throw:
				return ThrowStatement.parse(t);

			case Token.Type.Semicolon:
				throw new MDCompileException(t.location, "Empty statements ( ';' ) are not allowed");

			default:
				throw new MDCompileException(t.location, "Statement expected, not '%s'", t.toString());
		}
	}

	public void codeGen(FuncState s)
	{
		assert(false, "no codegen routine");
	}
	
	public Statement fold()
	{
		return this;
	}
}

class ImportStatement : Statement
{
	protected Identifier[] mNames;

	public this(Location location, Location endLocation, Identifier[] names)
	{
		super(location, endLocation);

		mNames = names;
	}

	public static ImportStatement parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Import);
		t = t.nextToken;
		
		Identifier[] names;
		names ~= Identifier.parse(t);

		while(t.type == Token.Type.Dot)
		{
			t = t.nextToken;
			names ~= Identifier.parse(t);
		}

		t.check(Token.Type.Semicolon);
		Location endLocation = t.location;
		t = t.nextToken;

		return new ImportStatement(location, endLocation, names);
	}
	
	public char[] toString()
	{
		return "import " ~ utf.toUTF8(Identifier.toLongString(mNames)) ~ ";";
	}
}

class ScopeStatement : Statement
{
	protected Statement mStatement;

	public this(Location location, Location endLocation, Statement statement)
	{
		super(location, endLocation);
		mStatement = statement;
	}

	public override void codeGen(FuncState s)
	{
		s.pushScope();
		mStatement.codeGen(s);
		s.popScope(mEndLocation.line);
	}
	
	public override Statement fold()
	{
		mStatement = mStatement.fold();
		return this;
	}
}

class ExpressionStatement : Statement
{
	protected Expression mExpr;

	public this(Location location, Location endLocation, Expression expr)
	{
		super(location, endLocation);
		mExpr = expr;
	}

	public static ExpressionStatement parse(inout Token* t)
	{
		Location location = t.location;
		Expression exp = Expression.parseStatement(t);

		t.check(Token.Type.Semicolon);
		Location endLocation = t.location;
		t = t.nextToken;

		return new ExpressionStatement(location, endLocation, exp);
	}

	public override void codeGen(FuncState s)
	{
		int freeRegCheck = s.mFreeReg;

		mExpr.codeGen(s);
		s.popToNothing();

		assert(s.mFreeReg == freeRegCheck, "not all regs freed");
	}
	
	public override Statement fold()
	{
		mExpr = mExpr.fold();
		return this;
	}
}

class DeclarationStatement : Statement
{
	protected Declaration mDecl;

	public this(Location location, Location endLocation, Declaration decl)
	{
		super(location, endLocation);
		mDecl = decl;
	}

	public static DeclarationStatement parse(inout Token* t)
	{
		Location location = t.location;
		Declaration decl = Declaration.parse(t);
		return new DeclarationStatement(location, decl.mEndLocation, decl);
	}

	public override void codeGen(FuncState s)
	{
		mDecl.codeGen(s);
	}
	
	public override Statement fold()
	{
		mDecl = mDecl.fold();
		return this;
	}
}

abstract class Declaration
{
	enum Protection
	{
		Local,
		Global
	}

	protected Location mLocation;
	protected Location mEndLocation;
	protected Protection mProtection;

	public this(Location location, Location endLocation, Protection protection)
	{
		mLocation = location;
		mEndLocation = endLocation;
		mProtection = protection;
	}

	public static Declaration parse(inout Token* t)
	{
		Location location = t.location;

		if(t.type == Token.Type.Local || t.type == Token.Type.Global)
		{
			if(t.nextToken.type == Token.Type.Ident)
			{
				VarDecl ret = VarDecl.parse(t);
				
				t.check(Token.Type.Semicolon);
				t = t.nextToken;

				return ret;
			}
			else if(t.nextToken.type == Token.Type.Function)
            	return FuncDecl.parse(t);
			else if(t.nextToken.type == Token.Type.Class)
				return ClassDecl.parse(t);
			else
				throw new MDCompileException(location, "Illegal token '%s' after '%s'", t.nextToken.toString(), t.toString());
		}
		else if(t.type == Token.Type.Function)
			return FuncDecl.parse(t);
		else if(t.type == Token.Type.Class)
			return ClassDecl.parse(t);
		else
			throw new MDCompileException(location, "Declaration expected");
	}

	public void codeGen(FuncState s)
	{
		assert(false, "no declaration codegen routine");
	}
	
	public Declaration fold()
	{
		return this;
	}
}

class ClassDecl : Declaration
{
	protected ClassDef mDef;

	public this(Location location, Protection protection, ClassDef def)
	{
		super(location, def.mEndLocation, protection);

		mDef = def;
	}

	public static ClassDecl parse(inout Token* t)
	{
		Location location = t.location;

		Protection protection = Protection.Local;

		if(t.type == Token.Type.Global)
		{
			protection = Protection.Global;
			t = t.nextToken;
		}
		else if(t.type == Token.Type.Local)
			t = t.nextToken;

		t.check(Token.Type.Class);
		t = t.nextToken;

		Identifier name = Identifier.parse(t);
		Expression baseClass = ClassDef.parseBaseClass(t);

		FuncDef[] methods;
		ClassDef.Field[] fields;
		Location endLocation;

		ClassDef.parseBody(location, t, methods, fields, endLocation);

		ClassDef def = new ClassDef(name, baseClass, methods, fields, location, endLocation);
		
		return new ClassDecl(location, protection, def);
	}

	public override void codeGen(FuncState s)
	{
		if(mProtection == Protection.Local)
		{
			s.insertLocal(mDef.mName);
			s.activateLocals(1);
			s.pushVar(mDef.mName);
		}
		else
		{
			assert(mProtection == Protection.Global);
			s.pushNewGlobal(mDef.mName);
		}

		mDef.codeGen(s);
		s.popAssign(mEndLocation.line);
	}
	
	public override Declaration fold()
	{
		mDef = mDef.fold();
		return this;
	}
}

class VarDecl : Declaration
{
	protected Identifier[] mNames;
	protected Expression mInitializer;

	public this(Location location, Location endLocation, Protection protection, Identifier[] names, Expression initializer)
	{
		super(location, endLocation, protection);

		mNames = names;
		mInitializer = initializer;
	}

	public static VarDecl parse(inout Token* t)
	{
		Location location = t.location;
		
		Protection protection = Protection.Local;

		if(t.type == Token.Type.Global)
		{
			protection = Protection.Global;
			t = t.nextToken;
		}
		else
		{
			t.check(Token.Type.Local);
			t = t.nextToken;
		}

		Identifier[] names;
		names ~= Identifier.parse(t);

		while(t.type == Token.Type.Comma)
		{
			t = t.nextToken;
			names ~= Identifier.parse(t);
		}
		
		Location endLocation = names[$ - 1].mLocation;

		Expression initializer;

		if(t.type == Token.Type.Assign)
		{
			t = t.nextToken;
			initializer = Expression.parse(t);
			endLocation = initializer.mEndLocation;
		}

		return new VarDecl(location, endLocation, protection, names, initializer);
	}

	public override void codeGen(FuncState s)
	{
		// Check for name conflicts within the definition
		foreach(uint i, Identifier n; mNames)
		{
			foreach(Identifier n2; mNames[0 .. i])
			{
				if(n.mName == n2.mName)
				{
					throw new MDCompileException(n.mLocation, "Variable '%s' conflicts with previous definition at %s",
						n.mName, n2.mLocation.toString());
				}
			}
		}

		if(mProtection == Protection.Global)
		{
			if(mInitializer)
			{
				if(mNames.length == 1)
				{
					s.pushNewGlobal(mNames[0]);
					mInitializer.codeGen(s);
					s.popAssign(mInitializer.mEndLocation.line);
				}
				else
				{
					mInitializer.checkMultRet();
					
					foreach(Identifier n; mNames)
						s.pushNewGlobal(n);

					uint reg = s.nextRegister();
					mInitializer.codeGen(s);
					s.popToRegisters(mEndLocation.line, reg, mNames.length);

					for(int r = reg + mNames.length; r >= reg; r--)
						s.popMoveFromReg(mEndLocation.line, r);
				}
			}
			else
			{
				foreach(Identifier n; mNames)
				{
					s.pushNewGlobal(n);
					s.pushNull();
					s.popAssign(n.mLocation.line);
				}
			}
		}
		else
		{
			assert(mProtection == Protection.Local);

			if(mInitializer)
			{
				if(mNames.length == 1)
				{
					uint destReg = s.nextRegister();
					mInitializer.codeGen(s);
					s.popMoveTo(mLocation.line, destReg);
					s.insertLocal(mNames[0]);
				}
				else
				{
					uint destReg = s.nextRegister();
					mInitializer.checkMultRet();
					mInitializer.codeGen(s);
					s.popToRegisters(mLocation.line, destReg, mNames.length);
					s.insertLocal(mNames[0]);
	
					foreach(Identifier n; mNames[1 .. $])
						s.insertLocal(n);
				}
			}
			else
			{
				uint reg = s.nextRegister();
	
				foreach(Identifier n; mNames)
					s.insertLocal(n);
	
				s.codeNulls(mLocation.line, reg, mNames.length);
			}

			s.activateLocals(mNames.length);
		}
	}

	public override VarDecl fold()
	{
		if(mInitializer)
			mInitializer = mInitializer.fold();
	
		return this;
	}
}

class FuncDecl : Declaration
{
	protected FuncDef mDef;

	public this(Location location, Protection protection, FuncDef def)
	{
		super(location, def.mEndLocation, protection);

		mDef = def;
	}

	public static FuncDecl parse(inout Token* t, bool simple = false)
	{
		Location location = t.location;
		Protection protection = Protection.Local;
		
		if(t.type == Token.Type.Global)
		{
			protection = Protection.Global;
			t = t.nextToken;
		}
		else if(t.type == Token.Type.Local)
			t = t.nextToken;

		FuncDef def = FuncDef.parseSimple(t);

		return new FuncDecl(location, protection, def);
	}

	public override void codeGen(FuncState s)
	{
		if(mProtection == Protection.Local)
		{
			s.insertLocal(mDef.mName);
			s.activateLocals(1);
			s.pushVar(mDef.mName);
		}
		else
		{
			assert(mProtection == Protection.Global);
			s.pushNewGlobal(mDef.mName);
		}

		mDef.codeGen(s);
		s.popAssign(mEndLocation.line);
	}
	
	public override Declaration fold()
	{
		mDef = mDef.fold();
		return this;
	}
}

class Identifier
{
	protected dchar[] mName;
	protected Location mLocation;

	public this(dchar[] name, Location location)
	{
		mName = name;
		mLocation = location;
	}
	
	public int opCmp(Object o)
	{
		Identifier other = cast(Identifier)o;
		assert(other);
		
		return typeid(typeof(mName)).compare(&mName, &other.mName);	
	}

	public static Identifier parse(inout Token* t)
	{
		t.check(Token.Type.Ident);

		Identifier id = new Identifier(t.stringValue, t.location);
		t = t.nextToken;

		return id;
	}

	public static dchar[] toLongString(Identifier[] idents)
	{
		return djoin((uint index)
		{
			if(index >= idents.length)
				return cast(dchar[])null;
			else
				return idents[index].mName;
		}, ".");
	}
	
	public static dchar[][] toStringArray(Identifier[] idents)
	{
		dchar[][] ret = new dchar[][idents.length];
		
		foreach(i, ident; idents)
			ret[i] = ident.mName;
			
		return ret;
	}

	public char[] toString()
	{
		return utf.toUTF8(mName);
	}
}

class CompoundStatement : Statement
{
	protected Statement[] mStatements;

	public this(Location location, Location endLocation, Statement[] statements)
	{
		super(location, endLocation);
		mStatements = statements;
	}

	public static CompoundStatement parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.LBrace);
		t = t.nextToken;

		Statement[] statements = new Statement[10];
		int i = 0;

		void addStatement(Statement s)
		{
			if(i >= statements.length)
				statements.length = statements.length * 2;

			statements[i] = s;
			i++;
		}

		while(t.type != Token.Type.RBrace)
			addStatement(Statement.parse(t));

		statements.length = i;

		t.check(Token.Type.RBrace);
		Location endLocation = t.location;
		t = t.nextToken;

		return new CompoundStatement(location, endLocation, statements);
	}

	public override void codeGen(FuncState s)
	{
		foreach(Statement st; mStatements)
			st.codeGen(s);
	}
	
	public override CompoundStatement fold()
	{
		foreach(inout statement; mStatements)
			statement = statement.fold();
			
		return this;
	}
}

class IfStatement : Statement
{
	protected Expression mCondition;
	protected Statement mIfBody;
	protected Statement mElseBody;

	public this(Location location, Location endLocation, Expression condition, Statement ifBody, Statement elseBody)
	{
		super(location, endLocation);

		mCondition = condition;
		mIfBody = ifBody;
		mElseBody = elseBody;
	}

	public static IfStatement parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.If);
		t = t.nextToken;
		t.check(Token.Type.LParen);
		t = t.nextToken;

		Expression condition = Expression.parse(t);

		t.check(Token.Type.RParen);
		t = t.nextToken;

		Statement ifBody = Statement.parse(t);

		Statement elseBody;
		
		Location endLocation = ifBody.mEndLocation;

		if(t.type == Token.Type.Else)
		{
			t = t.nextToken;
			elseBody = Statement.parse(t);
			endLocation = elseBody.mEndLocation;
		}

		return new IfStatement(location, endLocation, condition, ifBody, elseBody);
	}

	public override void codeGen(FuncState s)
	{
		InstRef* i = mCondition.codeCondition(s);
		s.invertJump(i);

		s.pushScope();

		s.patchTrueToHere(i);
		mIfBody.codeGen(s);

		if(mElseBody)
		{
			s.popScope(mIfBody.mEndLocation.line);

			InstRef* j = s.makeJump(mElseBody.mLocation.line);
			s.patchFalseToHere(i);
			s.patchJumpToHere(i);

			s.pushScope();
				mElseBody.codeGen(s);
			s.popScope(mEndLocation.line);

			s.patchJumpToHere(j);
			delete j;
		}
		else
		{
			s.popScope(mIfBody.mEndLocation.line);
			s.patchFalseToHere(i);
			s.patchJumpToHere(i);
		}

		delete i;
	}
	
	public override Statement fold()
	{
		mCondition = mCondition.fold();
		mIfBody = mIfBody.fold();
		
		if(mElseBody)
			mElseBody = mElseBody.fold();
			
		if(mCondition.isConstant)
		{
			if(mCondition.isTrue)
				return mIfBody;
			else
			{
				if(mElseBody)
					return mElseBody;
				else
					return new CompoundStatement(mLocation, mEndLocation, null);
			}
		}
		
		return this;
	}
}

class WhileStatement : Statement
{
	protected Expression mCondition;
	protected Statement mBody;

	public this(Location location, Location endLocation, Expression condition, Statement whileBody)
	{
		super(location, endLocation);

		mCondition = condition;
		mBody = whileBody;
	}

	public static WhileStatement parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.While);
		t = t.nextToken;
		t.check(Token.Type.LParen);
		t = t.nextToken;

		Expression condition = Expression.parse(t);

		t.check(Token.Type.RParen);
		t = t.nextToken;

		Statement whileBody = Statement.parse(t);

		return new WhileStatement(location, whileBody.mEndLocation, condition, whileBody);
	}

	public override void codeGen(FuncState s)
	{
		InstRef* beginLoop = s.getLabel();
		
		if(mCondition.isConstant && mCondition.isTrue)
		{
			s.pushScope();
				s.setBreakable();
				s.setContinuable();
				mBody.codeGen(s);
				s.patchContinues(beginLoop);
				s.codeJump(mEndLocation.line, beginLoop);
				s.patchBreaksToHere();
			s.popScope(mEndLocation.line);
		}
		else
		{
			InstRef* cond = mCondition.codeCondition(s);
			s.invertJump(cond);
	
			s.pushScope();
				s.patchTrueToHere(cond);
				s.setBreakable();
				s.setContinuable();
				mBody.codeGen(s);
				s.patchContinues(beginLoop);
				s.codeJump(mEndLocation.line, beginLoop);
				s.patchBreaksToHere();
			s.popScope(mEndLocation.line);

			s.patchFalseToHere(cond);
			s.patchJumpToHere(cond);

			delete cond;
		}

		delete beginLoop;
	}
	
	public override Statement fold()
	{
		mCondition = mCondition.fold();
		mBody = mBody.fold();
		
		if(mCondition.isConstant)
		{
			if(!mCondition.isTrue)
				return new CompoundStatement(mLocation, mEndLocation, null);
		}
		
		return this;
	}
}

class DoWhileStatement : Statement
{
	protected Statement mBody;
	protected Expression mCondition;

	public this(Location location, Location endLocation, Statement doBody, Expression condition)
	{
		super(location, endLocation);

		mBody = doBody;
		mCondition = condition;
	}

	public static DoWhileStatement parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Do);
		t = t.nextToken;

		Statement doBody = Statement.parse(t);

		t.check(Token.Type.While);
		t = t.nextToken;
		t.check(Token.Type.LParen);
		t = t.nextToken;

		Expression condition = Expression.parse(t);

		t.check(Token.Type.RParen);
		Location endLocation = t.location;
		t = t.nextToken;

		return new DoWhileStatement(location, endLocation, doBody, condition);
	}

	public override void codeGen(FuncState s)
	{
		InstRef* beginLoop = s.getLabel();

		if(mCondition.isConstant && mCondition.isTrue)
		{
			s.pushScope();
				s.setBreakable();
				s.setContinuable();
				mBody.codeGen(s);
				s.patchContinuesToHere();
				s.codeJump(mEndLocation.line, beginLoop);
				s.patchBreaksToHere();
			s.popScope(mEndLocation.line);
		}
		else
		{
			s.pushScope();
				s.setBreakable();
				s.setContinuable();
				mBody.codeGen(s);
				s.patchContinuesToHere();
				InstRef* cond = mCondition.codeCondition(s);
				s.invertJump(cond);
				s.patchTrueToHere(cond);
				s.codeJump(mEndLocation.line, beginLoop);
				s.patchBreaksToHere();
			s.popScope(mEndLocation.line);

			s.patchFalseToHere(cond);
			s.patchJumpToHere(cond);
	
			delete cond;
		}

		delete beginLoop;
	}
	
	public override Statement fold()
	{
		mBody = mBody.fold();
		mCondition = mCondition.fold();

		if(mCondition.isConstant)
		{
			if(!mCondition.isTrue)
				return mBody;
		}
		
		return this;
	}
}

class ForStatement : Statement
{
	protected Expression mInit;
	protected VarDecl mInitDecl;
	protected Expression mCondition;
	protected Expression mIncrement;
	protected Statement mBody;

	public this(Location location, Location endLocation, Expression init, VarDecl initDecl, Expression cond, Expression inc, Statement forBody)
	{
		super(location, endLocation);

		mInit = init;
		mInitDecl = initDecl;
		mCondition = cond;
		mIncrement = inc;
		mBody = forBody;
	}

	public static ForStatement parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.For);
		t = t.nextToken;
		t.check(Token.Type.LParen);
		t = t.nextToken;

		Expression init;
		VarDecl initDecl;

		if(t.type == Token.Type.Semicolon)
			t = t.nextToken;
		else
		{
			if(t.type == Token.Type.Local)
				initDecl = VarDecl.parse(t);
			else
				init = Expression.parseStatement(t);

			t.check(Token.Type.Semicolon);
			t = t.nextToken;
		}

		Expression condition;

		if(t.type == Token.Type.Semicolon)
			t = t.nextToken;
		else
		{
			condition = Expression.parse(t);
			t.check(Token.Type.Semicolon);
			t = t.nextToken;
		}

		Expression increment;

		if(t.type == Token.Type.RParen)
			t = t.nextToken;
		else
		{
			increment = Expression.parseStatement(t);
			t.check(Token.Type.RParen);
			t = t.nextToken;
		}

		Statement forBody = Statement.parse(t);

		return new ForStatement(location, forBody.mEndLocation, init, initDecl, condition, increment, forBody);
	}

	public override void codeGen(FuncState s)
	{
		s.pushScope();
			s.setBreakable();
			
			s.pushScope();
				s.setContinuable();

				if(mInitDecl)
					mInitDecl.codeGen(s);
				else if(mInit)
				{
					mInit.codeGen(s);
					s.popToNothing();
				}
	
				InstRef* beginLoop = s.getLabel();
	
				InstRef* cond;
				
				if(mCondition)
				{
					cond = mCondition.codeCondition(s);
					s.invertJump(cond);
					s.patchTrueToHere(cond);
				}
	
				mBody.codeGen(s);
	
				s.patchContinuesToHere();
				
				if(s.scopeHasUpval())
					s.codeClose(mIncrement.mLocation.line);

				if(mIncrement)
				{
					mIncrement.codeGen(s);
					s.popToNothing();
				}
			s.popScope(mEndLocation.line);

			s.codeJump(mEndLocation.line, beginLoop);
			delete beginLoop;

			s.patchBreaksToHere();
		s.popScope(mEndLocation.line);

		if(mCondition)
		{
			s.patchFalseToHere(cond);
			s.patchJumpToHere(cond);
			delete cond;
		}
	}
	
	public override Statement fold()
	{
		if(mInit)
			mInit = mInit.fold();

		if(mInitDecl)
			mInitDecl = mInitDecl.fold();

		if(mCondition)
			mCondition = mCondition.fold();

		if(mIncrement)
			mIncrement = mIncrement.fold();

		mBody = mBody.fold();

		if(mCondition && mCondition.isConstant)
		{
			if(mCondition.isTrue)
				mCondition = null;
			else if(mInit)
				return new ScopeStatement(mLocation, mEndLocation, new ExpressionStatement(mLocation, mEndLocation, mInit));
			else if(mInitDecl)
				return new ScopeStatement(mLocation, mEndLocation, new DeclarationStatement(mLocation, mEndLocation, mInitDecl));
			else
				return new CompoundStatement(mLocation, mEndLocation, null);
		}

		return this;
	}
}

class ForeachStatement : Statement
{
	protected Identifier[] mIndices;
	protected Expression[] mContainer;
	protected Statement mBody;

	public this(Location location, Location endLocation, Identifier[] indices, Expression[] container, Statement foreachBody)
	{
		super(location, endLocation);

		mIndices = indices;
		mContainer = container;
		mBody = foreachBody;
	}
	
	private static Identifier dummyIndex(Location l)
	{
		static uint counter = 0;
		return new Identifier("__dummy"d ~ utf.toUTF32(string.toString(counter++)), l);
	}

	public static ForeachStatement parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Foreach);
		t = t.nextToken;
		t.check(Token.Type.LParen);
		t = t.nextToken;

		Identifier[] indices;

		if(t.type == Token.Type.Local)
		{
			derr.writefln("Warning ", t.location.toString(), ": 'local' in foreach indices will soon be illegal");
			t = t.nextToken;
		}

		indices ~= Identifier.parse(t);

		while(t.type == Token.Type.Comma)
		{
			t = t.nextToken;

			if(t.type == Token.Type.Local)
			{
				derr.writefln("Warning ", t.location.toString(), ": 'local' in foreach indices will soon be illegal");
				t = t.nextToken;
			}

			indices ~= Identifier.parse(t);
		}
		
		if(indices.length == 1)
			indices = dummyIndex(indices[0].mLocation) ~ indices;

		t.check(Token.Type.Semicolon);
		t = t.nextToken;

		Expression[] container;
		container ~= Expression.parse(t);

		while(t.type == Token.Type.Comma)
		{
			t = t.nextToken;
			container ~= Expression.parse(t);
		}

		if(container.length > 3)
			throw new MDCompileException(location, "'foreach' may have a maximum of three container expressions");

		t.check(Token.Type.RParen);
		t = t.nextToken;

		Statement foreachBody = Statement.parse(t);

		return new ForeachStatement(location, foreachBody.mEndLocation, indices, container, foreachBody);
	}

	public override void codeGen(FuncState s)
	{
		s.pushScope();
			s.setBreakable();
			s.setContinuable();

			uint baseReg = s.nextRegister();
			uint generator;
			uint invState;
			uint control;

			if(mContainer.length == 3)
			{
				generator = s.nextRegister();
				mContainer[0].codeGen(s);
				s.popMoveTo(mContainer[0].mLocation.line, generator);
				s.pushRegister();
				
				invState = s.nextRegister();
				mContainer[1].codeGen(s);
				s.popMoveTo(mContainer[1].mLocation.line, invState);
				s.pushRegister();
				
				control = s.nextRegister();
				mContainer[2].codeGen(s);
				s.popMoveTo(mContainer[2].mLocation.line, control);
				s.pushRegister();
			}
			else if(mContainer.length == 2)
			{
				generator = s.nextRegister();
				mContainer[0].codeGen(s);
				s.popMoveTo(mContainer[0].mLocation.line, generator);
				s.pushRegister();

				invState = s.nextRegister();
				mContainer[1].codeGen(s);

				if(mContainer[1].isMultRet())
				{
					s.popToRegisters(mContainer[1].mLocation.line, invState, 2);
					s.pushRegister();
					control = s.pushRegister();
				}
				else
				{
					s.popMoveTo(mContainer[1].mLocation.line, invState);
					s.pushRegister();
					control = s.pushRegister();
					s.codeNulls(mContainer[1].mLocation.line, control, 1);
				}
			}
			else
			{
				generator = s.nextRegister();
				mContainer[0].codeGen(s);

				if(mContainer[0].isMultRet())
				{
					s.popToRegisters(mContainer[0].mLocation.line, generator, 3);
					s.pushRegister();
					invState = s.pushRegister();
					control = s.pushRegister();
				}
				else
				{
					s.popMoveTo(mContainer[0].mLocation.line, generator);
					s.pushRegister();
					invState = s.pushRegister();
					control = s.pushRegister();
					s.codeNulls(mContainer[0].mLocation.line, invState, 2);
				}
			}

			InstRef* beginJump = s.makeJump(mLocation.line);
			InstRef* beginLoop = s.getLabel();

			s.pushScope();
				foreach(Identifier i; mIndices)
					s.insertLocal(i);
					
				s.activateLocals(mIndices.length);
				mBody.codeGen(s);
			s.popScope(mEndLocation.line);

			s.patchJumpToHere(beginJump);
			delete beginJump;

			s.codeI(mEndLocation.line, Op.Foreach, baseReg, mIndices.length);
			InstRef* gotoBegin = s.makeJump(mEndLocation.line, Op.Je);

			s.patchJumpTo(gotoBegin, beginLoop);
			delete beginLoop;
			delete gotoBegin;

			s.popRegister(control);
			s.popRegister(invState);
			s.popRegister(generator);
		s.popScope(mEndLocation.line);
	}
	
	public override Statement fold()
	{
		foreach(inout c; mContainer)
			c = c.fold();
			
		mBody = mBody.fold();

		return this;
	}
}

class SwitchStatement : Statement
{
	protected Expression mCondition;
	protected CaseStatement[] mCases;
	protected DefaultStatement mDefault;

	public this(Location location, Location endLocation, Expression condition, CaseStatement[] cases, DefaultStatement caseDefault)
	{
		super(location, endLocation);
		mCondition = condition;
		mCases = cases;
		mDefault = caseDefault;
	}

	public static SwitchStatement parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Switch);
		t = t.nextToken;
		t.check(Token.Type.LParen);
		t = t.nextToken;

		Expression condition = Expression.parse(t);

		t.check(Token.Type.RParen);
		t = t.nextToken;
		t.check(Token.Type.LBrace);
		t = t.nextToken;

		CaseStatement[] cases = new CaseStatement[10];
		int i = 0;

		void addCase(CaseStatement c)
		{
			if(i >= cases.length)
				cases.length = cases.length * 2;

			cases[i] = c;
			i++;
		}

		while(true)
		{
			if(t.type == Token.Type.Case)
				addCase(CaseStatement.parse(t));
			else
				break;
		}

		cases.length = i;

		if(cases.length == 0)
			throw new MDCompileException(location, "Switch statement must have at least one case statement");

		DefaultStatement caseDefault;

		if(t.type == Token.Type.Default)
			caseDefault = DefaultStatement.parse(t);

		t.check(Token.Type.RBrace);
		Location endLocation = t.location;
		t = t.nextToken;

		return new SwitchStatement(location, endLocation, condition, cases, caseDefault);
	}

	public override void codeGen(FuncState s)
	{
		s.pushScope();
			s.setBreakable();

			mCondition.codeGen(s);
			Exp src;
			s.popSource(mLocation.line, src);

			if(cast(IntExp)mCases[0].mCondition)
				s.beginIntSwitch(mLocation.line, src.index);
			else
				s.beginStringSwitch(mLocation.line, src.index);

			s.freeExpTempRegs(&src);

			foreach(CaseStatement c; mCases)
				c.codeGen(s);

			if(mDefault)
				mDefault.codeGen(s);

			s.endSwitch();

			s.patchBreaksToHere();
		s.popScope(mEndLocation.line);
	}
	
	public override Statement fold()
	{
		mCondition = mCondition.fold();
		
		foreach(inout c; mCases)
			c = c.fold();
			
		if(mDefault)
			mDefault = mDefault.fold();

		return this;
	}
}

class CaseStatement : Statement
{
	protected Expression mCondition;
	protected Statement mBody;

	public this(Location location, Location endLocation, Expression condition, Statement caseBody)
	{
		super(location, endLocation);
		mCondition = condition;
		mBody = caseBody;
	}

	public static CaseStatement parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Case);
		t = t.nextToken;

		Expression[] cases = new Expression[10];
		int i = 0;

		void addCase(Expression c)
		{
			if(i >= cases.length)
				cases.length = cases.length * 2;

			cases[i] = c;
			i++;
		}
		
		addCase(Expression.parse(t));
		
		while(t.type == Token.Type.Comma)
		{
			t = t.nextToken;
			addCase(Expression.parse(t));
		}

		cases.length = i;

		t.check(Token.Type.Colon);
		t = t.nextToken;

		Statement[] statements = new Statement[10];
		i = 0;

		void addStatement(Statement s)
		{
			if(i >= statements.length)
				statements.length = statements.length * 2;

			statements[i] = s;
			i++;
		}

		while(t.type != Token.Type.Case && t.type != Token.Type.Default && t.type != Token.Type.RBrace)
			addStatement(Statement.parse(t));

		statements.length = i;

		Location endLocation = t.location;

		Statement ret = new CompoundStatement(location, endLocation, statements);
		ret = new ScopeStatement(location, endLocation, ret);

		for(i = cases.length - 1; i >= 0; i--)
			ret = new CaseStatement(location, endLocation, cases[i], ret);

		return cast(CaseStatement)ret;
	}

	public override void codeGen(FuncState s)
	{
		if(!mCondition.isConstant)
			throw new MDCompileException(mLocation, "Case value is not constant");

		s.addCase(mCondition);
		mBody.codeGen(s);
	}

	public override CaseStatement fold()
	{
		mCondition = mCondition.fold();
		mBody = mBody.fold();
		return this;
	}
}

class DefaultStatement : Statement
{
	protected Statement mBody;

	public this(Location location, Location endLocation, Statement defaultBody)
	{
		super(location, endLocation);
		mBody = defaultBody;
	}

	public static DefaultStatement parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Default);
		t = t.nextToken;
		t.check(Token.Type.Colon);
		t = t.nextToken;

		Statement[] statements = new Statement[10];
		int i = 0;

		void addStatement(Statement s)
		{
			if(i >= statements.length)
				statements.length = statements.length * 2;

			statements[i] = s;
			i++;
		}

		while(t.type != Token.Type.Case && t.type != Token.Type.Default && t.type != Token.Type.RBrace)
			addStatement(Statement.parse(t));

		statements.length = i;
		
		Location endLocation = t.location;

		Statement defaultBody = new CompoundStatement(location, endLocation, statements);
		defaultBody = new ScopeStatement(location, endLocation, defaultBody);
		return new DefaultStatement(location, endLocation, defaultBody);
	}

	public override void codeGen(FuncState s)
	{
		s.addDefault();
		mBody.codeGen(s);
	}

	public override DefaultStatement fold()
	{
		mBody = mBody.fold();
		return this;
	}
}

class ContinueStatement : Statement
{
	public this(Location location, Location endLocation)
	{
		super(location, endLocation);
	}

	public static ContinueStatement parse(inout Token* t)
	{
		Location location = t.location;
		t.check(Token.Type.Continue);
		t = t.nextToken;
		t.check(Token.Type.Semicolon);
		Location endLocation = t.location;
		t = t.nextToken;
		return new ContinueStatement(location, endLocation);
	}

	public override void codeGen(FuncState s)
	{
		s.codeContinue(mLocation);
	}
}

class BreakStatement : Statement
{
	public this(Location location, Location endLocation)
	{
		super(location, endLocation);
	}

	public static BreakStatement parse(inout Token* t)
	{
		Location location = t.location;
		t.check(Token.Type.Break);
		t = t.nextToken;
		t.check(Token.Type.Semicolon);
		Location endLocation = t.location;
		t = t.nextToken;
		return new BreakStatement(location, endLocation);
	}

	public override void codeGen(FuncState s)
	{
		s.codeBreak(mLocation);
	}
}

class ReturnStatement : Statement
{
	protected Expression[] mExprs;

	public this(Location location, Location endLocation, Expression[] exprs)
	{
		super(location, endLocation);
		mExprs = exprs;
	}
	
	public this(Expression value)
	{
		super(value.mLocation, value.mEndLocation);
		mExprs ~= value;	
	}

	public static ReturnStatement parse(inout Token* t)
	{
		Location location = t.location;
		t.check(Token.Type.Return);
		t = t.nextToken;

		if(t.type == Token.Type.Semicolon)
		{
			Location endLocation = t.location;
			t = t.nextToken;
			return new ReturnStatement(location, endLocation, null);
		}
		else
		{
			Expression[] exprs = new Expression[10];
			int i = 0;

			void add(Expression s)
			{
				if(i >= exprs.length)
					exprs.length = exprs.length * 2;

				exprs[i] = s;
				i++;
			}

			add(Expression.parse(t));

			while(t.type == Token.Type.Comma)
			{
				t = t.nextToken;
				add(Expression.parse(t));
			}

			exprs.length = i;

			t.check(Token.Type.Semicolon);
			Location endLocation = t.location;
			t = t.nextToken;

			return new ReturnStatement(location, endLocation, exprs);
		}
	}

	public override void codeGen(FuncState s)
	{
		if(mExprs.length == 0)
			s.codeI(mLocation.line, Op.Ret, 0, 1);
		else
		{
			uint firstReg = s.nextRegister();

			if(mExprs.length == 1 && cast(CallExp)mExprs[0])
			{
				mExprs[0].codeGen(s);
				s.popToRegisters(mEndLocation.line, firstReg, -1);
				s.makeTailcall();
			}
			else
			{

				Expression.codeGenListToNextReg(s, mExprs);

				if(mExprs[$ - 1].isMultRet())
					s.codeI(mEndLocation.line, Op.Ret, firstReg, 0);
				else
					s.codeI(mEndLocation.line, Op.Ret, firstReg, mExprs.length + 1);
			}
		}
	}
	
	public override Statement fold()
	{
		foreach(inout exp; mExprs)
			exp = exp.fold();
			
		return this;
	}
}

class TryCatchStatement : Statement
{
	protected Statement mTryBody;
	protected Identifier mCatchVar;
	protected Statement mCatchBody;
	protected Statement mFinallyBody;

	public this(Location location, Location endLocation, Statement tryBody, Identifier catchVar, Statement catchBody, Statement finallyBody)
	{
		super(location, endLocation);

		mTryBody = tryBody;
		mCatchVar = catchVar;
		mCatchBody = catchBody;
		mFinallyBody = finallyBody;
	}

	public static TryCatchStatement parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Try);
		t = t.nextToken;

		Statement tryBody = Statement.parse(t);
		tryBody = new ScopeStatement(tryBody.mLocation, tryBody.mEndLocation, tryBody);

		Identifier catchVar;
		Statement catchBody;
		
		Location endLocation;

		if(t.type == Token.Type.Catch)
		{
			t = t.nextToken;
			t.check(Token.Type.LParen);
			t = t.nextToken;

			catchVar = Identifier.parse(t);

			t.check(Token.Type.RParen);
			t = t.nextToken;

			catchBody = Statement.parse(t);
			catchBody = new ScopeStatement(catchBody.mLocation, catchBody.mEndLocation, catchBody);
			
			endLocation = catchBody.mEndLocation;
		}

		Statement finallyBody;

		if(t.type == Token.Type.Finally)
		{
			t = t.nextToken;
			finallyBody = Statement.parse(t);
			finallyBody = new ScopeStatement(finallyBody.mLocation, finallyBody.mEndLocation, finallyBody);
			
			endLocation = finallyBody.mEndLocation;
		}

		if(catchBody is null && finallyBody is null)
			throw new MDCompileException(location, "Try statement must be followed by a catch, finally, or both");

		return new TryCatchStatement(location, endLocation, tryBody, catchVar, catchBody, finallyBody);
	}

	public override void codeGen(FuncState s)
	{
		if(mFinallyBody)
		{
			InstRef* pushFinally = s.codeFinally(mLocation.line);

			if(mCatchBody)
			{
				uint checkReg1;
				InstRef* pushCatch = s.codeCatch(mLocation.line, checkReg1);

				mTryBody.codeGen(s);

				s.codeI(mTryBody.mEndLocation.line, Op.PopCatch, 0, 0);
				s.codeI(mTryBody.mEndLocation.line, Op.PopFinally, 0, 0);
				InstRef* jumpOverCatch = s.makeJump(mTryBody.mEndLocation.line);
				s.patchJumpToHere(pushCatch);
				delete pushCatch;

				s.pushScope();
					uint checkReg2 = s.insertLocal(mCatchVar);

					assert(checkReg1 == checkReg2, "catch var register is not right");

					s.activateLocals(1);
					mCatchBody.codeGen(s);
				s.popScope(mCatchBody.mEndLocation.line);

				s.codeI(mCatchBody.mEndLocation.line, Op.PopFinally, 0, 0);
				s.patchJumpToHere(jumpOverCatch);
				delete jumpOverCatch;

				s.patchJumpToHere(pushFinally);
				delete pushFinally;

				mFinallyBody.codeGen(s);

				s.codeI(mFinallyBody.mEndLocation.line, Op.EndFinal, 0, 0);
			}
			else
			{
				mTryBody.codeGen(s);
				s.codeI(mTryBody.mEndLocation.line, Op.PopFinally, 0, 0);

				s.patchJumpToHere(pushFinally);
				delete pushFinally;

				mFinallyBody.codeGen(s);
				s.codeI(mFinallyBody.mEndLocation.line, Op.EndFinal, 0, 0);
			}
		}
		else
		{
			assert(mCatchBody);

			uint checkReg1;
			InstRef* pushCatch = s.codeCatch(mLocation.line, checkReg1);

			mTryBody.codeGen(s);

			s.codeI(mTryBody.mEndLocation.line, Op.PopCatch, 0, 0);
			InstRef* jumpOverCatch = s.makeJump(mTryBody.mEndLocation.line);
			s.patchJumpToHere(pushCatch);
			delete pushCatch;

			s.pushScope();
				uint checkReg2 = s.insertLocal(mCatchVar);

				assert(checkReg1 == checkReg2, "catch var register is not right");

				s.activateLocals(1);
				mCatchBody.codeGen(s);
			s.popScope(mCatchBody.mEndLocation.line);

			s.patchJumpToHere(jumpOverCatch);
			delete jumpOverCatch;
		}
	}

	public override Statement fold()
	{
		mTryBody = mTryBody.fold();

		if(mCatchBody)
			mCatchBody = mCatchBody.fold();
			
		if(mFinallyBody)
			mFinallyBody = mFinallyBody.fold();
			
		return this;
	}
}

class ThrowStatement : Statement
{
	protected Expression mExp;

	public this(Location location, Location endLocation, Expression exp)
	{
		super(location, endLocation);

		mExp = exp;
	}

	public static ThrowStatement parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Throw);
		t = t.nextToken;

		Expression exp = Expression.parse(t);

		t.check(Token.Type.Semicolon);
		Location endLocation = t.location;
		t = t.nextToken;

		return new ThrowStatement(location, endLocation, exp);
	}

	public override void codeGen(FuncState s)
	{
		mExp.codeGen(s);

		Exp src;
		s.popSource(mLocation.line, src);

		s.codeR(mEndLocation.line, Op.Throw, 0, src.index, 0);

		s.freeExpTempRegs(&src);
	}
	
	public override Statement fold()
	{
		mExp = mExp.fold();
		return this;	
	}
}

abstract class Expression
{
	protected Location mLocation;
	protected Location mEndLocation;

	public this(Location location, Location endLocation)
	{
		mLocation = location;
		mEndLocation = endLocation;
	}

	public static Expression parse(inout Token* t)
	{
		return BinaryExp.parse(t);
	}
	
	public static Expression parseStatement(inout Token* t)
	{
		Location location = t.location;
		Expression exp;

		if(t.type == Token.Type.Inc)
		{
			t = t.nextToken;
			exp = PrimaryExp.parse(t);
			exp = new OpEqExp(location, location, Op.AddEq, exp, new IntExp(location, 1));
		}
		else if(t.type == Token.Type.Dec)
		{
			t = t.nextToken;
			exp = PrimaryExp.parse(t);
			exp = new OpEqExp(location, location, Op.SubEq, exp, new IntExp(location, 1));
		}
		else
		{
			if(t.type != Token.Type.Ident && t.type != Token.Type.This && t.type != Token.Type.LParen && t.type != Token.Type.Yield)
				throw new MDCompileException(t.location,
					"Expression statements may not begin with '%s'", t.toString());
			else
			{
				exp = PrimaryExp.parse(t);

				if(t.isOpAssign())
					exp = OpEqExp.parse(t, exp);
				else if(t.type == Token.Type.Assign || t.type == Token.Type.Comma)
					exp = Assignment.parse(t, exp);
				else if(t.type == Token.Type.Inc)
				{
					t = t.nextToken;
					exp = new OpEqExp(location, location, Op.AddEq, exp, new IntExp(location, 1));
				}
				else if(t.type == Token.Type.Dec)
				{
					t = t.nextToken;
					exp = new OpEqExp(location, location, Op.SubEq, exp, new IntExp(location, 1));
				}
			}
		}

		exp.checkToNothing();

		return exp;
	}

	public static void codeGenListToNextReg(FuncState s, Expression[] exprs)
	{
		if(exprs.length == 0)
			return;
		else if(exprs.length == 1)
		{
			uint firstReg = s.nextRegister();
			exprs[0].codeGen(s);

			if(exprs[0].isMultRet())
				s.popToRegisters(exprs[0].mEndLocation.line, firstReg, -1);
			else
				s.popMoveTo(exprs[0].mEndLocation.line, firstReg);
		}
		else
		{
			uint firstReg = s.nextRegister();
			exprs[0].codeGen(s);
			s.popMoveTo(exprs[0].mEndLocation.line, firstReg);
			s.pushRegister();

			uint lastReg = firstReg;

			foreach(uint i, Expression e; exprs[1 .. $])
			{
				lastReg = s.nextRegister();
				e.codeGen(s);

				// has to be -2 because i _is not the index in the array_ but the _index in the slice_
				if(i == exprs.length - 2 && e.isMultRet())
					s.popToRegisters(e.mEndLocation.line, lastReg, -1);
				else
					s.popMoveTo(e.mEndLocation.line, lastReg);

				s.pushRegister();
			}

			for(int i = lastReg; i >= cast(int)firstReg; i--)
				s.popRegister(i);
		}
	}

	public void codeGen(FuncState s)
	{
		assert(false, "unimplemented codeGen");
	}

	public InstRef* codeCondition(FuncState s)
	{
		assert(false, "unimplemented codeCondition");
	}

	public void checkToNothing()
	{
		throw new MDCompileException(mLocation, "Expression cannot exist on its own");
	}

	public void checkMultRet()
	{
		if(isMultRet() == false)
			throw new MDCompileException(mLocation, "Expression cannot be the source of a multi-target assignment");
	}

	public bool isMultRet()
	{
		return false;
	}
	
	public bool isConstant()
	{
		return false;
	}
	
	public bool isTrue()
	{
		return false;
	}
	
	public Expression fold()
	{
		return this;
	}
}

class Assignment : Expression
{
	protected Expression[] mLHS;
	protected Expression mRHS;

	public this(Location location, Location endLocation, Expression[] lhs, Expression rhs)
	{
		super(location, endLocation);

		mLHS = lhs;
		mRHS = rhs;
	}

	public static Assignment parse(inout Token* t, Expression firstLHS)
	{
		Location location = t.location;

		Expression[] lhs;
		Expression rhs;

		lhs ~= firstLHS;

		while(t.type == Token.Type.Comma)
		{
			t = t.nextToken;
			lhs ~= PrimaryExp.parse(t);
		}

		t.check(Token.Type.Assign);
		t = t.nextToken;

		rhs = OrOrExp.parse(t);

		foreach(exp; lhs)
			if(cast(ThisExp)exp)
				throw new MDCompileException(exp.mLocation, "'this' cannot be the target of an assignment");

		return new Assignment(location, rhs.mEndLocation, lhs, rhs);
	}

	public override void codeGen(FuncState s)
	{
		if(mLHS.length == 1)
		{
			mLHS[0].codeGen(s);
			mRHS.codeGen(s);
			s.popAssign(mEndLocation.line);
		}
		else
		{
			//TODO: Have to do conflict checking (local a, b; a[b], a = foo())!
			mRHS.checkMultRet();

			foreach(Expression dest; mLHS)
				dest.codeGen(s);

			uint RHSReg = s.nextRegister();
			mRHS.codeGen(s);
			s.popToRegisters(mEndLocation.line, RHSReg, mLHS.length);

			for(int reg = RHSReg + mLHS.length - 1; reg >= RHSReg; reg--)
				s.popMoveFromReg(mEndLocation.line, reg);
		}
	}

	public override InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(mLocation, "Assignments cannot be used as a condition");
	}

	public override void checkToNothing()
	{
		// OK
	}

	public override Expression fold()
	{
		foreach(inout exp; mLHS)
			exp = exp.fold();
			
		mRHS = mRHS.fold();
		return this;
	}
}

class OpEqExp : Expression
{
	protected Expression mLHS;
	protected Expression mRHS;
	protected Op mType;

	public this(Location location, Location endLocation, Op type, Expression left, Expression right)
	{
		super(location, endLocation);
		
		mLHS = left;
		mRHS = right;
		mType = type;
	}

	public static Expression parse(inout Token* t, Expression exp1)
	{
		Expression exp2;

		Location location = t.location;
		Op type;

		switch(t.type)
		{
			case Token.Type.AddEq:     type = Op.AddEq;  goto _commonParse;
			case Token.Type.SubEq:     type = Op.SubEq;  goto _commonParse;
			case Token.Type.CatEq:     type = Op.CatEq;  goto _commonParse;
			case Token.Type.MulEq:     type = Op.MulEq;  goto _commonParse;
			case Token.Type.DivEq:     type = Op.DivEq;  goto _commonParse;
			case Token.Type.ModEq:     type = Op.ModEq;  goto _commonParse;
			case Token.Type.ShlEq:     type = Op.ShlEq;  goto _commonParse;
			case Token.Type.ShrEq:     type = Op.ShrEq;  goto _commonParse;
			case Token.Type.UShrEq:    type = Op.UShrEq; goto _commonParse;
			case Token.Type.OrEq:      type = Op.OrEq;   goto _commonParse;
			case Token.Type.XorEq:     type = Op.XorEq;  goto _commonParse;
			case Token.Type.AndEq:     type = Op.AndEq;  goto _commonParse;
			case Token.Type.DefaultEq: type = Op.Move;

			_commonParse:
				t = t.nextToken;
				exp2 = OrOrExp.parse(t);
				exp1 = new OpEqExp(location, exp2.mEndLocation, type, exp1, exp2);
				break;

			default:
				assert(false, "OpEqExp parse switch");
				break;
		}

		return exp1;
	}

	public override void codeGen(FuncState s)
	{
		if(mType == Op.Move)
		{
			Statement ifBody = new ExpressionStatement(mLocation, mEndLocation, new Assignment(mLocation, mEndLocation, [mLHS], mRHS));
			Expression condition = new EqualExp(true, mLocation, mEndLocation, Op.Is, mLHS, new NullExp(mLocation));
			Statement ifStatement = new IfStatement(mLocation, mEndLocation, condition, ifBody, null);
			ifStatement.codeGen(s);
		}
		else
		{
			mLHS.codeGen(s);
			s.pushSource(mLHS.mEndLocation.line);
	
			Exp src1;
			s.popSource(mLHS.mEndLocation.line, src1);
			mRHS.codeGen(s);
			Exp src2;
			s.popSource(mEndLocation.line, src2);
	
			s.freeExpTempRegs(&src2);
			s.freeExpTempRegs(&src1);
	
			s.popReflexOp(mEndLocation.line, mType, src1.index, src2.index);
		}
	}

	public override InstRef* codeCondition(FuncState s)
	{
		switch(mType)
		{
			case Op.AddEq:  throw new MDCompileException(mLocation, "'+=' cannot be used as a condition");
			case Op.SubEq:  throw new MDCompileException(mLocation, "'-=' cannot be used as a condition");
			case Op.CatEq:  throw new MDCompileException(mLocation, "'~=' cannot be used as a condition");
			case Op.MulEq:  throw new MDCompileException(mLocation, "'*=' cannot be used as a condition");
			case Op.DivEq:  throw new MDCompileException(mLocation, "'/=' cannot be used as a condition");
			case Op.ModEq:  throw new MDCompileException(mLocation, "'%=' cannot be used as a condition");
			case Op.ShlEq:  throw new MDCompileException(mLocation, "'<<=' cannot be used as a condition");
			case Op.ShrEq:  throw new MDCompileException(mLocation, "'>>=' cannot be used as a condition");
			case Op.UShrEq: throw new MDCompileException(mLocation, "'>>>=' cannot be used as a condition");
			case Op.OrEq:   throw new MDCompileException(mLocation, "'|=' cannot be used as a condition");
			case Op.XorEq:  throw new MDCompileException(mLocation, "'^=' cannot be used as a condition");
			case Op.AndEq:  throw new MDCompileException(mLocation, "'&=' cannot be used as a condition");
			case Op.Move:   throw new MDCompileException(mLocation, "'?=' cannot be used as a condition");
		}
	}

	public override void checkToNothing()
	{
		// OK
	}
	
	public override Expression fold()
	{
		mLHS = mLHS.fold();
		mRHS = mRHS.fold();

		return this;
	}
}

abstract class BinaryExp : Expression
{
	protected Expression mOp1;
	protected Expression mOp2;
	protected Op mType;

	public this(Location location, Location endLocation, Op type, Expression left, Expression right)
	{
		super(location, endLocation);
		mType = type;
		mOp1 = left;
		mOp2 = right;
	}

	public override void codeGen(FuncState s)
	{
		mOp1.codeGen(s);
		Exp src1;
		s.popSource(mOp1.mEndLocation.line, src1);
		mOp2.codeGen(s);
		Exp src2;
		s.popSource(mEndLocation.line, src2);

		s.freeExpTempRegs(&src2);
		s.freeExpTempRegs(&src1);

		s.pushBinOp(mEndLocation.line, mType, src1.index, src2.index);
	}
	
	public static Expression parse(inout Token* t)
	{
		return OrOrExp.parse(t);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		uint temp = s.pushRegister();
		codeGen(s);
		s.popMoveTo(mEndLocation.line, temp);
		s.codeR(mEndLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* ret = s.makeJump(mEndLocation.line, Op.Je);
		s.popRegister(temp);
		return ret;
	}
}

class OrOrExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, Op.Or, left, right);
	}

	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		Expression exp1;
		Expression exp2;

		exp1 = AndAndExp.parse(t);

		while(t.type == Token.Type.OrOr)
		{
			t = t.nextToken;

			exp2 = AndAndExp.parse(t);
			exp1 = new OrOrExp(location, exp2.mEndLocation, exp1, exp2);

			location = t.location;
		}

		return exp1;
	}

	public override void codeGen(FuncState s)
	{
		uint temp = s.pushRegister();
		mOp1.codeGen(s);
		s.popMoveTo(mOp1.mEndLocation.line, temp);
		s.codeR(mOp1.mEndLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* i = s.makeJump(mOp1.mEndLocation.line, Op.Je);
		mOp2.codeGen(s);
		s.popMoveTo(mEndLocation.line, temp);
		s.patchJumpToHere(i);
		delete i;
		s.pushTempReg(temp);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		InstRef* left = mOp1.codeCondition(s);
		s.patchFalseToHere(left);
		InstRef* right = mOp2.codeCondition(s);

		InstRef* t;

		for(t = right; t.trueList !is null; t = t.trueList)
		{}

		t.trueList = left;

		return right;
	}

	public override void checkToNothing()
	{
		// OK
	}
	
	public override Expression fold()
	{
		mOp1 = mOp1.fold();
		mOp2 = mOp2.fold();
		
		if(mOp1.isConstant)
		{
			if(mOp1.isTrue())
				return mOp1;
			else
				return mOp2;
		}

		return this;
	}
}

class AndAndExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, Op.And, left, right);
	}

	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		Expression exp1;
		Expression exp2;

		exp1 = OrExp.parse(t);

		while(t.type == Token.Type.AndAnd)
		{
			t = t.nextToken;

			exp2 = OrExp.parse(t);
			exp1 = new AndAndExp(location, exp2.mEndLocation, exp1, exp2);

			location = t.location;
		}

		return exp1;
	}

	public override void codeGen(FuncState s)
	{
		uint temp = s.pushRegister();
		mOp1.codeGen(s);
		s.popMoveTo(mOp1.mEndLocation.line, temp);
		s.codeR(mOp1.mEndLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* i = s.makeJump(mOp1.mEndLocation.line, Op.Je, false);
		mOp2.codeGen(s);
		s.popMoveTo(mEndLocation.line, temp);
		s.patchJumpToHere(i);
		delete i;
		s.pushTempReg(temp);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		InstRef* left = mOp1.codeCondition(s);
		s.invertJump(left);
		s.patchTrueToHere(left);
		InstRef* right = mOp2.codeCondition(s);

		InstRef* f;

		for(f = right; f.falseList !is null; f = f.falseList)
		{}

		f.falseList = left;

		return right;
	}

	public override void checkToNothing()
	{
		// OK
	}
	
	public override Expression fold()
	{
		mOp1 = mOp1.fold();
		mOp2 = mOp2.fold();
		
		if(mOp1.isConstant)
		{
			if(mOp1.isTrue())
				return mOp2;
			else
				return mOp1;
		}

		return this;
	}
}

class OrExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, Op.Or, left, right);
	}

	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		Expression exp1;
		Expression exp2;

		exp1 = XorExp.parse(t);

		while(t.type == Token.Type.Or)
		{
			t = t.nextToken;

			exp2 = XorExp.parse(t);
			exp1 = new OrExp(location, exp2.mEndLocation, exp1, exp2);

			location = t.location;
		}

		return exp1;
	}
	
	public override Expression fold()
	{
		mOp1 = mOp1.fold();
		mOp2 = mOp2.fold();
		
		if(mOp1.isConstant && mOp2.isConstant)
		{
			IntExp e1 = cast(IntExp)mOp1;
			IntExp e2 = cast(IntExp)mOp2;
			
			if(e1 is null || e2 is null)
				throw new MDCompileException(mLocation, "Bitwise Or must be performed on integers");
				
			return new IntExp(mLocation, e1.mValue | e2.mValue);
		}

		return this;
	}
}

class XorExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, Op.Xor, left, right);
	}

	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		Expression exp1;
		Expression exp2;

		exp1 = AndExp.parse(t);

		while(t.type == Token.Type.Xor)
		{
			t = t.nextToken;

			exp2 = AndExp.parse(t);
			exp1 = new XorExp(location, exp2.mEndLocation, exp1, exp2);

			location = t.location;
		}

		return exp1;
	}
	
	public override Expression fold()
	{
		mOp1 = mOp1.fold();
		mOp2 = mOp2.fold();
		
		if(mOp1.isConstant && mOp2.isConstant)
		{
			IntExp e1 = cast(IntExp)mOp1;
			IntExp e2 = cast(IntExp)mOp2;
			
			if(e1 is null || e2 is null)
				throw new MDCompileException(mLocation, "Bitwise Xor must be performed on integers");

			return new IntExp(mLocation, e1.mValue ^ e2.mValue);
		}

		return this;
	}
}

class AndExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, Op.And, left, right);
	}

	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		Expression exp1;
		Expression exp2;

		exp1 = EqualExp.parse(t);

		while(t.type == Token.Type.And)
		{
			t = t.nextToken;

			exp2 = EqualExp.parse(t);
			exp1 = new AndExp(location, exp2.mEndLocation, exp1, exp2);

			location = t.location;
		}

		return exp1;
	}
	
	public override Expression fold()
	{
		mOp1 = mOp1.fold();
		mOp2 = mOp2.fold();
		
		if(mOp1.isConstant && mOp2.isConstant)
		{
			IntExp e1 = cast(IntExp)mOp1;
			IntExp e2 = cast(IntExp)mOp2;
			
			if(e1 is null || e2 is null)
				throw new MDCompileException(mLocation, "Bitwise And must be performed on integers");

			return new IntExp(mLocation, e1.mValue & e2.mValue);
		}

		return this;
	}
}

class EqualExp : BinaryExp
{
	protected bool mIsTrue;

	public this(bool isTrue, Location location, Location endLocation, Op type, Expression left, Expression right)
	{
		super(location, endLocation, type, left, right);

		mIsTrue = isTrue;
	}

	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		Expression exp1;
		Expression exp2;

		exp1 = CmpExp.parse(t);

		while(true)
		{
			bool isTrue = false;

			switch(t.type)
			{
				case Token.Type.EQ, Token.Type.NE:
					isTrue = (t.type == Token.Type.EQ);
					t = t.nextToken;
					exp2 = CmpExp.parse(t);
					exp1 = new EqualExp(isTrue, location, exp2.mEndLocation, Op.Cmp, exp1, exp2);
					continue;

				case Token.Type.Not:
					if(t.nextToken.type != Token.Type.Is)
						break;

					t = t.nextToken.nextToken;
					goto _doIs;

				case Token.Type.Is:
					isTrue = true;
					t = t.nextToken;

				_doIs:
					exp2 = CmpExp.parse(t);
					exp1 = new EqualExp(isTrue, location, exp2.mEndLocation, Op.Is, exp1, exp2);
					continue;

				default:
					break;
			}

			break;
		}

		return exp1;
	}

	public override void codeGen(FuncState s)
	{
		uint temp = s.pushRegister();
		InstRef* i = codeCondition(s);
		s.pushBool(false);
		s.popMoveTo(mEndLocation.line, temp);
		InstRef* j = s.makeJump(mEndLocation.line, Op.Jmp);
		s.patchJumpToHere(i);
		delete i;
		s.pushBool(true);
		s.popMoveTo(mEndLocation.line, temp);
		s.patchJumpToHere(j);
		delete j;
		s.pushTempReg(temp);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		mOp1.codeGen(s);
		Exp src1;
		s.popSource(mOp1.mEndLocation.line, src1);
		mOp2.codeGen(s);
		Exp src2;
		s.popSource(mEndLocation.line, src2);

		s.freeExpTempRegs(&src2);
		s.freeExpTempRegs(&src1);

		s.codeR(mEndLocation.line, mType, 0, src1.index, src2.index);

		return s.makeJump(mEndLocation.line, Op.Je, mIsTrue);
	}
	
	public override Expression fold()
	{
		mOp1 = mOp1.fold();
		mOp2 = mOp2.fold();
		
		if(mOp1.isConstant && mOp2.isConstant)
		{
			if(cast(NullExp)mOp1 && cast(NullExp)mOp2)
				return new BoolExp(mLocation, mIsTrue ? true : false);

			BoolExp b1 = cast(BoolExp)mOp1;
			BoolExp b2 = cast(BoolExp)mOp2;

			if(b1 && b2)
				return new BoolExp(mLocation, mIsTrue ? b1.mValue == b2.mValue : b1.mValue != b2.mValue);

			IntExp i1 = cast(IntExp)mOp1;
			IntExp i2 = cast(IntExp)mOp2;

			if(i1 && i2)
				return new BoolExp(mLocation, mIsTrue ? i1.mValue == i2.mValue : i1.mValue != i2.mValue);

			FloatExp f1 = cast(FloatExp)mOp1;
			FloatExp f2 = cast(FloatExp)mOp2;

			if(f1 && f2)
				return new BoolExp(mLocation, mIsTrue ? f1.mValue == f2.mValue : f1.mValue != f2.mValue);

			if(i1 && f2)
				return new BoolExp(mLocation, mIsTrue ? i1.mValue == f2.mValue : i1.mValue != f2.mValue);

			if(f1 && i2)
				return new BoolExp(mLocation, mIsTrue ? f1.mValue == i2.mValue : f1.mValue != i2.mValue);

			CharExp c1 = cast(CharExp)mOp1;
			CharExp c2 = cast(CharExp)mOp2;

			if(c1 && c2)
				return new BoolExp(mLocation, mIsTrue ? c1.mValue == c2.mValue : c1.mValue != c2.mValue);
				
			StringExp s1 = cast(StringExp)mOp1;
			StringExp s2 = cast(StringExp)mOp2;
			
			if(s1 && s2)
				return new BoolExp(mLocation, mIsTrue ? s1.mValue == s2.mValue : s1.mValue != s2.mValue);
				
			throw new MDCompileException(mLocation, "Cannot compare different types");
		}

		return this;
	}
}

class CmpExp : BinaryExp
{
	protected Token.Type mCmpType;

	public this(Token.Type type, Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, Op.Cmp, left, right);

		mCmpType = type;

		assert(mCmpType == Token.Type.LT || mCmpType == Token.Type.LE ||
			mCmpType == Token.Type.GT || mCmpType == Token.Type.GE, "invalid cmp type");
	}

	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		Expression exp1;
		Expression exp2;

		exp1 = ShiftExp.parse(t);

		while(true)
		{
			Token.Type type = t.type;

			switch(type)
			{
				case Token.Type.LT, Token.Type.LE, Token.Type.GT, Token.Type.GE:
					t = t.nextToken;
					exp2 = ShiftExp.parse(t);
					exp1 = new CmpExp(type, location, exp2.mEndLocation, exp1, exp2);
					continue;
					
				case Token.Type.As:
					t = t.nextToken;
					exp2 = ShiftExp.parse(t);
					exp1 = new AsExp(location, exp2.mEndLocation, exp1, exp2);
					continue;
					
				case Token.Type.In:
					t = t.nextToken;
					exp2 = ShiftExp.parse(t);
					exp1 = new InExp(location, exp2.mEndLocation, exp1, exp2);
					continue;
					
				case Token.Type.Not:
					if(t.nextToken.type != Token.Type.In)
						break;

					t = t.nextToken.nextToken;
					exp2 = ShiftExp.parse(t);
					exp1 = new NotInExp(location, exp2.mEndLocation, exp1, exp2);
					continue;

				default:
					break;
			}

			break;
		}

		return exp1;
	}

	public override void codeGen(FuncState s)
	{
		uint temp = s.pushRegister();
		InstRef* i = codeCondition(s);
		s.pushBool(false);
		s.popMoveTo(mEndLocation.line, temp);
		InstRef* j = s.makeJump(mEndLocation.line, Op.Jmp);
		s.patchJumpToHere(i);
		delete i;
		s.pushBool(true);
		s.popMoveTo(mEndLocation.line, temp);
		s.patchJumpToHere(j);
		delete j;
		s.pushTempReg(temp);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		mOp1.codeGen(s);
		Exp src1;
		s.popSource(mOp1.mEndLocation.line, src1);
		mOp2.codeGen(s);
		Exp src2;
		s.popSource(mEndLocation.line, src2);

		s.freeExpTempRegs(&src2);
		s.freeExpTempRegs(&src1);

		s.codeR(mEndLocation.line, Op.Cmp, 0, src1.index, src2.index);

		switch(mCmpType)
		{
			case Token.Type.LT: return s.makeJump(mEndLocation.line, Op.Jlt, true);
			case Token.Type.LE: return s.makeJump(mEndLocation.line, Op.Jle, true);
			case Token.Type.GT: return s.makeJump(mEndLocation.line, Op.Jle, false);
			case Token.Type.GE: return s.makeJump(mEndLocation.line, Op.Jlt, false);
			default: assert(false);
		}
	}
	
	public override Expression fold()
	{
		mOp1 = mOp1.fold();
		mOp2 = mOp2.fold();
		
		if(mOp1.isConstant && mOp2.isConstant)
		{
			int cmpVal = 0;

			if(cast(NullExp)mOp1 && cast(NullExp)mOp2)
			{
				cmpVal = 0;
				goto _done;
			}

			IntExp i1 = cast(IntExp)mOp1;
			IntExp i2 = cast(IntExp)mOp2;

			if(i1 && i2)
			{
				cmpVal = i1.mValue - i2.mValue;
				goto _done;
			}

			FloatExp f1 = cast(FloatExp)mOp1;
			FloatExp f2 = cast(FloatExp)mOp2;

			if(f1 && f2)
			{
				if(f1.mValue < f2.mValue)
					cmpVal = -1;
				else if(f1.mValue > f2.mValue)
					cmpVal = 1;
				else
					cmpVal = 0;
					
				goto _done;
			}

			if(i1 && f2)
			{
				if(i1.mValue < f2.mValue)
					cmpVal = -1;
				else if(i1.mValue > f2.mValue)
					cmpVal = 1;
				else
					cmpVal = 0;
					
				goto _done;
			}

			if(f1 && i2)
			{
				if(f1.mValue < i2.mValue)
					cmpVal = -1;
				else if(f1.mValue > i2.mValue)
					cmpVal = 1;
				else
					cmpVal = 0;
					
				goto _done;
			}

			CharExp c1 = cast(CharExp)mOp1;
			CharExp c2 = cast(CharExp)mOp2;

			if(c1 && c2)
			{
				cmpVal = c1.mValue - c2.mValue;
				goto _done;
			}

			StringExp s1 = cast(StringExp)mOp1;
			StringExp s2 = cast(StringExp)mOp2;

			if(s1 && s2)
			{
				cmpVal = dcmp(s1.mValue, s2.mValue);
				goto _done;
			}
				
			throw new MDCompileException(mLocation, "Invalid compile-time comparison");
			
			_done:
			
			switch(mCmpType)
			{
				case Token.Type.LT: return new BoolExp(mLocation, cmpVal < 0);
				case Token.Type.LE: return new BoolExp(mLocation, cmpVal <= 0);
				case Token.Type.GT: return new BoolExp(mLocation, cmpVal > 0);
				case Token.Type.GE: return new BoolExp(mLocation, cmpVal >= 0);
				default: assert(false, "CmpExp fold");
			}
		}

		return this;
	}
}

class AsExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		if(left.isConstant() || right.isConstant())
			throw new MDCompileException(location, "Neither argument of an 'as' expression may be a constant");
			
		super(location, endLocation, Op.As, left, right);
	}
}

class InExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, Op.In, left, right);
	}
}

class NotInExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, Op.NotIn, left, right);
	}
}

class ShiftExp : BinaryExp
{
	public this(Location location, Location endLocation, Token.Type type, Expression left, Expression right)
	{
		Op t;

		switch(type)
		{
			case Token.Type.Shl: t = Op.Shl; break;
			case Token.Type.Shr: t = Op.Shr; break;
			case Token.Type.UShr: t = Op.UShr; break;
			default: assert(false, "ShiftExp ctor type switch");
		}

		super(location, endLocation, t, left, right);
	}

	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		Expression exp1;
		Expression exp2;

		exp1 = AddExp.parse(t);

		while(true)
		{
			Token.Type type = t.type;

			switch(t.type)
			{
				case Token.Type.Shl, Token.Type.Shr, Token.Type.UShr:
					t = t.nextToken;
					exp2 = AddExp.parse(t);
					exp1 = new ShiftExp(location, exp2.mEndLocation, type, exp1, exp2);
					continue;

				default:
					break;
			}

			break;
		}

		return exp1;
	}
	
	public override Expression fold()
	{
		mOp1 = mOp1.fold();
		mOp2 = mOp2.fold();
		
		if(mOp1.isConstant && mOp2.isConstant)
		{
			IntExp e1 = cast(IntExp)mOp1;
			IntExp e2 = cast(IntExp)mOp2;
			
			if(e1 is null || e2 is null)
				throw new MDCompileException(mLocation, "Bitshifting must be performed on integers");
				
			switch(mType)
			{
				case Op.Shl: return new IntExp(mLocation, e1.mValue << e2.mValue);
				case Op.Shr: return new IntExp(mLocation, e1.mValue >> e2.mValue);
				case Op.UShr: return new IntExp(mLocation, e1.mValue >>> e2.mValue);
				default: assert(false, "ShiftExp fold");
			}
		}

		return this;
	}
}

class AddExp : BinaryExp
{
	public this(Location location, Location endLocation, Token.Type type, Expression left, Expression right)
	{
		Op t;

		switch(type)
		{
			case Token.Type.Add: t = Op.Add; break;
			case Token.Type.Sub: t = Op.Sub; break;
			default: assert(false, "BaseAddExp ctor type switch");
		}

		super(location, endLocation, t, left, right);
	}

	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		Expression exp1;
		Expression exp2;

		exp1 = MulExp.parse(t);

		while(true)
		{
			Token.Type type = t.type;

			switch(t.type)
			{
				case Token.Type.Add, Token.Type.Sub:
					t = t.nextToken;
					exp2 = MulExp.parse(t);
					exp1 = new AddExp(location, exp2.mEndLocation, type, exp1, exp2);
					continue;
					
				case Token.Type.Cat:
					t = t.nextToken;
					exp2 = MulExp.parse(t);
					exp1 = new CatExp(location, exp2.mEndLocation, type, exp1, exp2);
					continue;

				default:
					break;
			}

			break;
		}

		return exp1;
	}
	
	public override Expression fold()
	{
		mOp1 = mOp1.fold();
		mOp2 = mOp2.fold();

		if(mOp1.isConstant && mOp2.isConstant)
		{
			IntExp i1 = cast(IntExp)mOp1;
			IntExp i2 = cast(IntExp)mOp2;
			
			if(i1 && i2)
			{
				if(mType == Op.Add)
					return new IntExp(mLocation, i1.mValue + i2.mValue);
				else
				{
					assert(mType == Op.Sub, "AddExp fold 1");
					return new IntExp(mLocation, i1.mValue - i2.mValue);
				}
			}

			FloatExp f1 = cast(FloatExp)mOp1;
			FloatExp f2 = cast(FloatExp)mOp2;
			
			if((f1 && f2) || (f1 && i2) || (i1 && f2))
			{
				float val1;
				float val2;
				
				if(i1)
					val1 = cast(float)i1.mValue;
				else
					val1 = f1.mValue;
					
				if(i2)
					val2 = cast(float)i2.mValue;
				else
					val2 = f2.mValue;
					
				if(mType == Op.Add)
					return new FloatExp(mLocation, val1 + val2);
				else
				{
					assert(mType == Op.Sub, "AddExp fold 2");
					return new FloatExp(mLocation, val1 - val2);
				}
			}
				
			throw new MDCompileException(mLocation, "Addition and Subtraction must be performed on numbers");
		}

		return this;
	}
}

class CatExp : BinaryExp
{
	protected Expression[] mOps;
	protected bool mCollapsed = false;

	public this(Location location, Location endLocation, Token.Type type, Expression left, Expression right)
	{
		super(location, endLocation, Op.Cat, left, right);
	}

	public override void codeGen(FuncState s)
	{
		assert(mCollapsed is true, "CatExp codeGen not collapsed");
		assert(mOps.length >= 2, "CatExp codeGen not enough ops");

		uint firstReg = s.nextRegister();

		Expression.codeGenListToNextReg(s, mOps);

		if(mOps[$ - 1].isMultRet())
			s.pushBinOp(mEndLocation.line, Op.Cat, firstReg, 0);
		else
			s.pushBinOp(mEndLocation.line, Op.Cat, firstReg, mOps.length + 1);
	}
	
	public override Expression fold()
	{
		mOp1 = mOp1.fold();
		mOp2 = mOp2.fold();

		assert(mCollapsed is false, "repeated CatExp fold");
		mCollapsed = true;
		
		CatExp l = cast(CatExp)mOp1;
		CatExp r = cast(CatExp)mOp2;
		
		if(l)
			mOps = l.mOps ~ mOps;
		else
			mOps = mOp1 ~ mOps;

		mOps ~= mOp2;

		mEndLocation = mOps[$ - 1].mEndLocation;
		
		for(int i = 0; i < mOps.length - 1; i++)
		{
			if(mOps[i].isConstant && mOps[i + 1].isConstant)
			{
				StringExp s1 = cast(StringExp)mOps[i];
				StringExp s2 = cast(StringExp)mOps[i + 1];

				if(s1 && s2)
				{
					mOps[i] = new StringExp(mLocation, s1.mValue ~ s2.mValue);
					mOps = mOps[0 .. i + 1] ~ mOps[i + 2 .. $];
					i--;
					continue;
				}

				CharExp c1 = cast(CharExp)mOps[i];
				CharExp c2 = cast(CharExp)mOps[i + 1];

				if(c1 && c2)
				{
					dchar[] s = new dchar[2];
					s[0] = c1.mValue;
					s[1] = c2.mValue;
	
					mOps[i] = new StringExp(mLocation, s);
					mOps = mOps[0 .. i + 1] ~ mOps[i + 2 .. $];
					i--;
					continue;
				}

				if(s1 && c2)
				{
					mOps[i] = new StringExp(mLocation, s1.mValue ~ c2.mValue);
					mOps = mOps[0 .. i + 1] ~ mOps[i + 2 .. $];
					i--;
					continue;
				}
	
				if(c1 && s2)
				{
					mOps[i] = new StringExp(mLocation, c1.mValue ~ s2.mValue);
					mOps = mOps[0 .. i + 1] ~ mOps[i + 2 .. $];
					i--;
					continue;
				}
			}
		}

		if(mOps.length == 1)
			return mOps[0];

		return this;
	}
}

class MulExp : BinaryExp
{
	public this(Location location, Location endLocation, Token.Type type, Expression left, Expression right)
	{
		Op t;

		switch(type)
		{
			case Token.Type.Mul: t = Op.Mul; break;
			case Token.Type.Div: t = Op.Div; break;
			case Token.Type.Mod: t = Op.Mod; break;
			default: assert(false, "BaseMulExp ctor type switch");
		}

		super(location, endLocation, t, left, right);
	}

	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		Expression exp1;
		Expression exp2;

		exp1 = UnaryExp.parse(t);

		while(true)
		{
			Token.Type type = t.type;

			switch(t.type)
			{
				case Token.Type.Mul, Token.Type.Div, Token.Type.Mod:
					t = t.nextToken;
					exp2 = UnaryExp.parse(t);
					exp1 = new MulExp(location, exp2.mEndLocation, type, exp1, exp2);
					continue;

				default:
					break;
			}

			break;
		}

		return exp1;
	}
	
	public override Expression fold()
	{
		mOp1 = mOp1.fold();
		mOp2 = mOp2.fold();

		if(mOp1.isConstant && mOp2.isConstant)
		{
			IntExp i1 = cast(IntExp)mOp1;
			IntExp i2 = cast(IntExp)mOp2;
			
			if(i1 && i2)
			{
				switch(mType)
				{
					case Op.Mul: return new IntExp(mLocation, i1.mValue * i2.mValue);
					case Op.Mod: return new IntExp(mLocation, i1.mValue % i2.mValue);
					case Op.Div:
						if(i2.mValue == 0)
							throw new MDCompileException(mLocation, "Division by 0");

						return new IntExp(mLocation, i1.mValue / i2.mValue);
						
					default: assert(false, "MulExp fold 1");
				}
			}

			FloatExp f1 = cast(FloatExp)mOp1;
			FloatExp f2 = cast(FloatExp)mOp2;
			
			if((f1 && f2) || (f1 && i2) || (i1 && f2))
			{
				float val1;
				float val2;
				
				if(i1)
					val1 = cast(float)i1.mValue;
				else
					val1 = f1.mValue;
					
				if(i2)
					val2 = cast(float)i2.mValue;
				else
					val2 = f2.mValue;
					
				switch(mType)
				{
					case Op.Mul: return new FloatExp(mLocation, val1 * val2);
					case Op.Mod: return new FloatExp(mLocation, val1 % val2);
					case Op.Div:
						if(val2 == 0.0)
							throw new MDCompileException(mLocation, "Division by 0");

						return new FloatExp(mLocation, val1 / val2);

					default: assert(false, "MulExp fold 2");
				}
			}
				
			throw new MDCompileException(mLocation, "Multiplication, Division, and Modulo must be performed on numbers");
		}

		return this;
	}
}

abstract class UnaryExp : Expression
{
	protected Expression mOp;

	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation);
		mOp = operand;
	}

	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		Expression exp;

		switch(t.type)
		{
			case Token.Type.Sub:
				t = t.nextToken;
				exp = UnaryExp.parse(t);
				exp = new NegExp(location, exp.mEndLocation, exp);
				break;

			case Token.Type.Not:
				t = t.nextToken;
				exp = UnaryExp.parse(t);
				exp = new NotExp(location, exp.mEndLocation, exp);
				break;

			case Token.Type.Cat:
				t = t.nextToken;
				exp = UnaryExp.parse(t);
				exp = new ComExp(location, exp.mEndLocation, exp);
				break;

			case Token.Type.Length:
				t = t.nextToken;
				exp = UnaryExp.parse(t);
				exp = new LengthExp(location, exp.mEndLocation, exp);
				break;
				
			case Token.Type.Coroutine:
				t = t.nextToken;
				exp = UnaryExp.parse(t);
				exp = new CoroutineExp(location, exp.mEndLocation, exp);
				break;

			default:
				exp = PrimaryExp.parse(t);
				break;
		}

		assert(exp !is null);

		return exp;
	}

	public override InstRef* codeCondition(FuncState s)
	{
		uint temp = s.nextRegister();
		codeGen(s);
		s.popMoveTo(mEndLocation.line, temp);
		s.codeR(mEndLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* ret = s.makeJump(mEndLocation.line, Op.Je);
		return ret;
	}
}

class NegExp : UnaryExp
{
	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation, operand);
	}

	public override void codeGen(FuncState s)
	{
		mOp.codeGen(s);
		s.popUnOp(mEndLocation.line, Op.Neg);
	}

	public override Expression fold()
	{
		mOp = mOp.fold();
		
		if(mOp.isConstant)
		{
			IntExp intExp = cast(IntExp)mOp;

			if(intExp)
			{
				intExp.mValue = -intExp.mValue;
				return intExp;
			}

			FloatExp floatExp = cast(FloatExp)mOp;

			if(floatExp)
			{
				floatExp.mValue = -floatExp.mValue;
				return floatExp;
			}
			
			throw new MDCompileException(mLocation, "Negation must be performed on numbers");
		}

		return this;
	}
}

class NotExp : UnaryExp
{
	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation, operand);
	}

	public override void codeGen(FuncState s)
	{
		mOp.codeGen(s);
		s.popUnOp(mEndLocation.line, Op.Not);
	}

	public override Expression fold()
	{
		mOp = mOp.fold();
		
		if(mOp.isConstant)
			return new BoolExp(mLocation, !mOp.isTrue);

		CmpExp cmpExp = cast(CmpExp)mOp;

		if(cmpExp)
		{
			switch(cmpExp.mCmpType)
			{
				case Token.Type.LT: cmpExp.mCmpType = Token.Type.GE; break;
				case Token.Type.LE: cmpExp.mCmpType = Token.Type.GT; break;
				case Token.Type.GT: cmpExp.mCmpType = Token.Type.LE; break;
				case Token.Type.GE: cmpExp.mCmpType = Token.Type.LT; break;
			}

			return cmpExp;
		}

		EqualExp equalExp = cast(EqualExp)mOp;

		if(equalExp)
		{
			equalExp.mIsTrue = !equalExp.mIsTrue;
			return equalExp;
		}

		return this;
	}
}

class ComExp : UnaryExp
{
	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation, operand);
	}

	public override void codeGen(FuncState s)
	{
		mOp.codeGen(s);
		s.popUnOp(mEndLocation.line, Op.Com);
	}
	
	public override Expression fold()
	{
		mOp = mOp.fold();
		
		if(mOp.isConstant)
		{
			IntExp intExp = cast(IntExp)mOp;

			if(intExp)
			{
				intExp.mValue = ~intExp.mValue;
				return intExp;
			}
			
			throw new MDCompileException(mLocation, "Bitwise complement must be performed on integers");
		}
		
		return this;
	}
}

class LengthExp : UnaryExp
{
	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation, operand);
	}

	public override void codeGen(FuncState s)
	{
		mOp.codeGen(s);
		s.popUnOp(mEndLocation.line, Op.Length);
	}
	
	public override Expression fold()
	{
		mOp = mOp.fold();
		
		if(mOp.isConstant)
		{
			StringExp stringExp = cast(StringExp)mOp;
			
			if(stringExp)
				return new IntExp(mLocation, stringExp.mValue.length);

			throw new MDCompileException(mLocation, "Length must be performed on a string");
		}
		
		return this;
	}
}

class CoroutineExp : UnaryExp
{
	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation, operand);
	}
	
	public override void codeGen(FuncState s)
	{
		mOp.codeGen(s);
		s.popUnOp(mEndLocation.line, Op.Coroutine);
	}
	
	public override Expression fold()
	{
		mOp = mOp.fold();		
		return this;
	}
}

abstract class PostfixExp : UnaryExp
{
	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation, operand);
	}

	public static Expression parse(inout Token* t, Expression exp)
	{
		while(true)
		{
			Location location = t.location;

			switch(t.type)
			{
				case Token.Type.Dot:
					t = t.nextToken;

					t.check(Token.Type.Ident);

					Location loc = t.location;
					
					IdentExp ie = new IdentExp(loc, Identifier.parse(t));

					exp = new DotExp(location, ie.mEndLocation, exp, ie);
					continue;

				case Token.Type.LParen:
					t = t.nextToken;

					Expression context;
					Expression[] args = new Expression[5];
					uint i = 0;

					void add(Expression arg)
					{
						if(i >= args.length)
							args.length = args.length * 2;

						args[i] = arg;
						i++;
					}
					
					if(t.type == Token.Type.With)
					{
						t = t.nextToken;
						context = Expression.parse(t);
						
						while(t.type == Token.Type.Comma)
						{
							t = t.nextToken;
							add(Expression.parse(t));
						}
					}
					else if(t.type != Token.Type.RParen)
					{
						while(true)
						{
							add(Expression.parse(t));

							if(t.type == Token.Type.RParen)
								break;

							t.check(Token.Type.Comma);
							t = t.nextToken;
						}
					}

					args.length = i;

					t.check(Token.Type.RParen);
					Location endLocation = t.location;
					t = t.nextToken;

					exp = new CallExp(location, endLocation, exp, context, args);
					continue;

				case Token.Type.LBracket:
					t = t.nextToken;

					Expression loIndex;
					Expression hiIndex;
					
					Location endLocation;

					if(t.type == Token.Type.DotDot)
					{
						loIndex = new NullExp(t.location);
						t = t.nextToken;

						if(t.type == Token.Type.RBracket)
						{
							// a[ .. ]
							hiIndex = new NullExp(t.location);
							endLocation = t.location;
							t = t.nextToken;
						}
						else
						{
							// a[ .. 0]
							hiIndex = Expression.parse(t);
							t.check(Token.Type.RBracket);
							endLocation = t.location;
							t = t.nextToken;
						}

						exp = new SliceExp(location, endLocation, exp, loIndex, hiIndex);
					}
					else
					{
						loIndex = Expression.parse(t);

						if(t.type == Token.Type.DotDot)
						{
							t = t.nextToken;

							if(t.type == Token.Type.RBracket)
							{
								// a[0 .. ]
								hiIndex = new NullExp(t.location);
								endLocation = t.location;
								t = t.nextToken;
							}
							else
							{
								// a[0 .. 0]
								hiIndex = Expression.parse(t);
								t.check(Token.Type.RBracket);
								endLocation = t.location;
								t = t.nextToken;
							}
							
							exp = new SliceExp(location, endLocation, exp, loIndex, hiIndex);
						}
						else
						{
							// a[0]
							t.check(Token.Type.RBracket);
							endLocation = t.location;
							t = t.nextToken;
							
							exp = new IndexExp(location, endLocation, exp, loIndex);
						}
					}
					continue;

				default:
					return exp;
			}
		}
	}
}

class DotExp : PostfixExp
{
	protected IdentExp mIdent;

	public this(Location location, Location endLocation, Expression operand, IdentExp ident)
	{
		super(location, endLocation, operand);

		mIdent = ident;
	}

	public override void codeGen(FuncState s)
	{
		mOp.codeGen(s);
		
		s.topToSource(mEndLocation.line);
		s.popField(mEndLocation.line, mIdent.mIdent);
	}
	
	public override Expression fold()
	{
		mOp = mOp.fold();
		return this;
	}
}

class CallExp : PostfixExp
{
	protected Expression mContext;
	protected Expression[] mArgs;

	public this(Location location, Location endLocation, Expression operand, Expression context, Expression[] args)
	{
		super(location, endLocation, operand);

		mContext = context;
		mArgs = args;
	}

	public override void codeGen(FuncState s)
	{
		DotExp dotExp = cast(DotExp)mOp;

		if(dotExp !is null && mContext is null)
		{
			Identifier methodName = dotExp.mIdent.mIdent;

			uint funcReg = s.nextRegister();
			dotExp.mOp.codeGen(s);
			
			Exp src;
			s.popSource(mOp.mEndLocation.line, src);
			s.freeExpTempRegs(&src);
			assert(s.nextRegister() == funcReg);
			//assert(src.index < funcReg + 2);

			s.pushRegister();
			uint thisReg = s.pushRegister();

			Expression.codeGenListToNextReg(s, mArgs);
			
			s.codeR(mOp.mEndLocation.line, Op.Method, funcReg, src.index, s.codeStringConst(methodName.mName));
			s.popRegister(thisReg);

			if(mArgs.length == 0)
				s.pushCall(mEndLocation.line, funcReg, 2);
			else if(mArgs[$ - 1].isMultRet())
				s.pushCall(mEndLocation.line, funcReg, 0);
			else
				s.pushCall(mEndLocation.line, funcReg, mArgs.length + 2);
		}
		else
		{
			uint funcReg = s.nextRegister();
			mOp.codeGen(s);
			
			Exp src;
			s.popSource(mOp.mEndLocation.line, src);
			s.freeExpTempRegs(&src);
			assert(s.nextRegister() == funcReg);

			s.pushRegister();
			uint thisReg = s.pushRegister();
			
			if(mContext)
			{
				mContext.codeGen(s);
				s.popMoveTo(mOp.mEndLocation.line, thisReg);
			}

			Expression.codeGenListToNextReg(s, mArgs);

			s.codeR(mOp.mEndLocation.line, Op.Precall, funcReg, src.index, (mContext is null) ? 1 : 0);
			s.popRegister(thisReg);

			if(mArgs.length == 0)
				s.pushCall(mEndLocation.line, funcReg, 2);
			else if(mArgs[$ - 1].isMultRet())
				s.pushCall(mEndLocation.line, funcReg, 0);
			else
				s.pushCall(mEndLocation.line, funcReg, mArgs.length + 2);
		}
	}

	public void checkToNothing()
	{
		// OK
	}

	public bool isMultRet()
	{
		return true;
	}
	
	public override Expression fold()
	{
		mOp = mOp.fold();

		foreach(inout arg; mArgs)
			arg = arg.fold();
			
		return this;
	}
}

class IndexExp : PostfixExp
{
	protected Expression mIndex;

	public this(Location location, Location endLocation, Expression operand, Expression index)
	{
		super(location, endLocation, operand);

		mIndex = index;
	}

	public override void codeGen(FuncState s)
	{
		mOp.codeGen(s);
		
		s.topToSource(mEndLocation.line);

		mIndex.codeGen(s);
		s.popIndex(mEndLocation.line);
	}
	
	public override Expression fold()
	{
		mOp = mOp.fold();
		mIndex = mIndex.fold();
		
		if(mOp.isConstant && mIndex.isConstant)
		{
			StringExp str = cast(StringExp)mOp;
			IntExp idx = cast(IntExp)mIndex;

			if(str is null || idx is null)
				throw new MDCompileException(mLocation, "Can only index strings with integers at compile time");

			if(idx.mValue < 0)
				idx.mValue += str.mValue.length;

			if(idx.mValue < 0 || idx.mValue >= str.mValue.length)
				throw new MDCompileException(mLocation, "Invalid string index");

			return new CharExp(mLocation, str.mValue[idx.mValue]);
		}

		return this;
	}
}

class SliceExp : PostfixExp
{
	protected Expression mLoIndex;
	protected Expression mHiIndex;
	
	public this(Location location, Location endLocation, Expression operand, Expression loIndex, Expression hiIndex)
	{
		super(location, endLocation, operand);
		
		mLoIndex = loIndex;
		mHiIndex = hiIndex;
	}
	
	public override void codeGen(FuncState s)
	{
		uint reg = s.nextRegister();
		Expression.codeGenListToNextReg(s, [mOp, mLoIndex, mHiIndex]);

		s.pushSlice(mEndLocation.line, reg);
	}
	
	public override Expression fold()
	{
		mOp = mOp.fold();
		mLoIndex = mLoIndex.fold();
		mHiIndex = mHiIndex.fold();

		if(mOp.isConstant && mLoIndex.isConstant && mHiIndex.isConstant)
		{
			StringExp str = cast(StringExp)mOp;
			IntExp lo = cast(IntExp)mLoIndex;
			IntExp hi = cast(IntExp)mHiIndex;

			if(str is null || lo is null || hi is null)
				throw new MDCompileException(mLocation, "Can only slice strings with integers at compile time");

			int l = lo.mValue;
			int h = hi.mValue;

			if(l < 0)
				l += str.mValue.length;

			if(h < 0)
				h += str.mValue.length;

			if(l < 0 || l >= str.mValue.length || h < 0 || h >= str.mValue.length || l > h)
				throw new MDCompileException(mLocation, "Invalid slice indices");

			return new StringExp(mLocation, str.mValue[l .. h]);
		}

		return this;
	}
}

class PrimaryExp : Expression
{
	public this(Location location)
	{
		super(location, location);
	}
	
	public this(Location location, Location endLocation)
	{
		super(location, endLocation);
	}

	public static Expression parse(inout Token* t)
	{
		Expression exp;
		Location location = t.location;

		switch(t.type)
		{
			case Token.Type.Ident:
				exp = IdentExp.parse(t);
				break;
				
			case Token.Type.This:
				exp = ThisExp.parse(t);
				break;
				
			case Token.Type.Null:
				exp = NullExp.parse(t);
				break;

			case Token.Type.True, Token.Type.False:
				exp = BoolExp.parse(t);
				break;

			case Token.Type.Vararg:
				exp = VarargExp.parse(t);
				break;
				
			case Token.Type.CharLiteral:
				exp = CharExp.parse(t);
				break;

			case Token.Type.IntLiteral:
				exp = IntExp.parse(t);
				break;

			case Token.Type.FloatLiteral:
				exp = FloatExp.parse(t);
				break;

			case Token.Type.StringLiteral:
				exp = StringExp.parse(t);
				break;

			case Token.Type.Function:
				exp = FuncLiteralExp.parse(t);
				break;
				
			case Token.Type.Class:
				exp = ClassLiteralExp.parse(t);
				break;

			case Token.Type.LParen:
				exp = ParenExp.parse(t);
				break;
				
			case Token.Type.LBrace:
				exp = TableCtorExp.parse(t);
				break;

			case Token.Type.LBracket:
				exp = ArrayCtorExp.parse(t);
				break;
				
			case Token.Type.Yield:
				exp = YieldExp.parse(t);
				break;

			default:
				throw new MDCompileException(location, "Expression expected, not '%s'", t.toString());
		}

		return PostfixExp.parse(t, exp);
	}
}

class IdentExp : PrimaryExp
{
	protected Identifier mIdent;

	public this(Location location, Identifier ident)
	{
		super(location);

		mIdent = ident;
	}

	public static IdentExp parse(inout Token* t)
	{
		Location location = t.location;
		return new IdentExp(location, Identifier.parse(t));
	}

	public override void codeGen(FuncState s)
	{
		s.pushVar(mIdent);
	}

	public InstRef* codeCondition(FuncState s)
	{
		codeGen(s);
		Exp reg;
		s.popSource(mEndLocation.line, reg);
		s.codeR(mEndLocation.line, Op.IsTrue, 0, reg.index, 0);
		InstRef* ret = s.makeJump(mEndLocation.line, Op.Je);

		s.freeExpTempRegs(&reg);

		return ret;
	}

	char[] toString()
	{
		return "Ident " ~ utf.toUTF8(mIdent.mName);	
	}
}

class ThisExp : PrimaryExp
{
	public this(Location location)
	{
		super(location);
	}

	public static ThisExp parse(inout Token* t)
	{
		Location location = t.location;
		t.check(Token.Type.This);
		t = t.nextToken;
		return new ThisExp(location);
	}

	public override void codeGen(FuncState s)
	{
		s.pushThis();
	}

	public InstRef* codeCondition(FuncState s)
	{
		codeGen(s);
		Exp reg;
		s.popSource(mEndLocation.line, reg);
		s.codeR(mEndLocation.line, Op.IsTrue, 0, reg.index, 0);
		InstRef* ret = s.makeJump(mEndLocation.line, Op.Je);

		s.freeExpTempRegs(&reg);

		return ret;
	}

	char[] toString()
	{
		return "this";
	}
}

class NullExp : PrimaryExp
{
	public this(Location location)
	{
		super(location);
	}

	public static NullExp parse(inout Token* t)
	{
		t.check(Token.Type.Null);

		scope(success)
			t = t.nextToken;

		return new NullExp(t.location);
	}

	public override void codeGen(FuncState s)
	{
		s.pushNull();
	}

	public InstRef* codeCondition(FuncState s)
	{
		return s.makeJump(mEndLocation.line, Op.Jmp);
	}
	
	public override bool isConstant()
	{
		return true;
	}

	public override bool isTrue()
	{
		return false;
	}
}

class BoolExp : PrimaryExp
{
	protected bool mValue;

	public this(Location location, bool value)
	{
		super(location);

		mValue = value;
	}

	public static BoolExp parse(inout Token* t)
	{
		scope(success)
			t = t.nextToken;

		if(t.type == Token.Type.True)
			return new BoolExp(t.location, true);
		else if(t.type == Token.Type.False)
			return new BoolExp(t.location, false);
		else
			throw new MDCompileException(t.location, "'true' or 'false' expected, not '%s'", t.toString());
	}

	public override void codeGen(FuncState s)
	{
		s.pushBool(mValue);
	}

	public InstRef* codeCondition(FuncState s)
	{
		return s.makeJump(mEndLocation.line, Op.Jmp, mValue);
	}
	
	public override bool isConstant()
	{
		return true;
	}
	
	public override bool isTrue()
	{
		return mValue;
	}
}

class VarargExp : PrimaryExp
{
	public this(Location location)
	{
		super(location);
	}

	public static VarargExp parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Vararg);
		t = t.nextToken;

		return new VarargExp(location);
	}

	public override void codeGen(FuncState s)
	{
		if(s.mIsVararg == false)
			throw new MDCompileException(mLocation, "'vararg' cannot be used in a non-variadic function");

		s.pushVararg();
	}

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(mLocation, "Cannot use 'vararg' as a condition");
	}

	public bool isMultRet()
	{
		return true;
	}
}

class CharExp : PrimaryExp
{
	protected dchar mValue;

	public this(Location location, dchar value)
	{
		super(location);

		mValue = value;
	}

	public static CharExp parse(inout Token* t)
	{
		scope(success)
			t = t.nextToken;

		if(t.type == Token.Type.CharLiteral)
			return new CharExp(t.location, t.intValue);
		else
			throw new MDCompileException(t.location, "Character literal expected, not '%s'", t.toString());
	}

	public override void codeGen(FuncState s)
	{
		s.pushChar(mValue);
	}

	public InstRef* codeCondition(FuncState s)
	{
		uint temp = s.pushRegister();
		codeGen(s);
		s.popMoveTo(mEndLocation.line, temp);
		s.codeR(mEndLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* ret = s.makeJump(mEndLocation.line, Op.Je);
		s.popRegister(temp);
		return ret;
	}
	
	public override bool isConstant()
	{
		return true;
	}
}

class IntExp : PrimaryExp
{
	protected int mValue;

	public this(Location location, int value)
	{
		super(location);

		mValue = value;
	}

	public static IntExp parse(inout Token* t)
	{
		scope(success)
			t = t.nextToken;

		if(t.type == Token.Type.IntLiteral)
			return new IntExp(t.location, t.intValue);
		else
			throw new MDCompileException(t.location, "Integer literal expected, not '%s'", t.toString());
	}

	public override void codeGen(FuncState s)
	{
		s.pushInt(mValue);
	}

	public InstRef* codeCondition(FuncState s)
	{
		uint temp = s.pushRegister();
		codeGen(s);
		s.popMoveTo(mEndLocation.line, temp);
		s.codeR(mEndLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* ret = s.makeJump(mEndLocation.line, Op.Je);
		s.popRegister(temp);
		return ret;
	}
	
	public override bool isConstant()
	{
		return true;
	}
	
	public override bool isTrue()
	{
		return (mValue != 0);
	}
}

class FloatExp : PrimaryExp
{
	protected float mValue;

	public this(Location location, float value)
	{
		super(location);

		mValue = value;
	}

	public static FloatExp parse(inout Token* t)
	{
		t.check(Token.Type.FloatLiteral);

		scope(success)
			t = t.nextToken;

		return new FloatExp(t.location, t.floatValue);
	}

	public override void codeGen(FuncState s)
	{
		s.pushFloat(mValue);
	}

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(mLocation, "Cannot use a float literal as a condition");
	}
	
	public override bool isConstant()
	{
		return true;
	}
	
	public override bool isTrue()
	{
		return (mValue != 0.0);
	}
}

class StringExp : PrimaryExp
{
	protected dchar[] mValue;

	public this(Location location, dchar[] value)
	{
		super(location);

		mValue = value;
	}

	public static StringExp parse(inout Token* t)
	{
		t.check(Token.Type.StringLiteral);

		scope(success)
			t = t.nextToken;

		return new StringExp(t.location, t.stringValue);
	}

	public override void codeGen(FuncState s)
	{
		s.pushString(mValue);
	}

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(mLocation, "Cannot use a string literal as a condition");
	}
	
	public override bool isConstant()
	{
		return true;
	}
	
	public override bool isTrue()
	{
		return true;
	}
}

class FuncLiteralExp : PrimaryExp
{
	protected FuncDef mDef;

	public this(Location location, Location endLocation, FuncDef def)
	{
		super(location, endLocation);

		mDef = def;
	}

	public static FuncLiteralExp parse(inout Token* t)
	{
		Location location = t.location;
		FuncDef def = FuncDef.parseLiteral(t);

		return new FuncLiteralExp(location, def.mEndLocation, def);
	}

	public override void codeGen(FuncState s)
	{
		mDef.codeGen(s);
	}

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(mLocation, "Cannot use a function literal as a condition");
	}
	
	public override FuncLiteralExp fold()
	{
		mDef = mDef.fold();
		return this;
	}
}

class ClassLiteralExp : PrimaryExp
{
	protected ClassDef mDef;

	public this(Location location, Location endLocation, Identifier name, Expression baseClass, FuncDef[] methods, ClassDef.Field[] fields)
	{
		super(location, endLocation);

		mDef = new ClassDef(name, baseClass, methods, fields, location, endLocation);
	}
	
	public static ClassLiteralExp parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Class);
		t = t.nextToken;
		
		Identifier name;
		
		if(t.type == Token.Type.Ident)
			name = Identifier.parse(t);

		Expression baseClass = ClassDef.parseBaseClass(t);

		FuncDef[] methods;
		ClassDef.Field[] fields;
		Location endLocation;
		
		ClassDef.parseBody(location, t, methods, fields, endLocation);

		return new ClassLiteralExp(location, endLocation, name, baseClass, methods, fields);
	}
	
	public override void codeGen(FuncState s)
	{
		mDef.codeGen(s);
	}
	
	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(mLocation, "Cannot use a class literal as a condition");
	}
	
	public override Expression fold()
	{
		mDef = mDef.fold();
		return this;
	}
}

class ParenExp : PrimaryExp
{
	protected Expression mExp;
	
	public this(Location location, Location endLocation, Expression exp)
	{
		super(location, endLocation);
		mExp = exp;
	}
	
	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.LParen);
		t = t.nextToken;
		Expression exp = Expression.parse(t);
		t.check(Token.Type.RParen);
		Location endLocation = t.location;
		t = t.nextToken;

		if(exp.isMultRet())
			return new ParenExp(location, endLocation, exp);
		else
			return exp;
	}
	
	public override void codeGen(FuncState s)
	{
		assert(mExp.isMultRet(), "ParenExp codeGen not multret");

		uint reg = s.nextRegister();
		mExp.codeGen(s);
		s.popMoveTo(mLocation.line, reg);
		uint checkReg = s.pushRegister();

		assert(reg == checkReg, "ParenExp codeGen wrong regs");

		s.pushTempReg(reg);
	}
}

class TableCtorExp : PrimaryExp
{
	protected Expression[2][] mFields;

	public this(Location location, Location endLocation, Expression[2][] fields)
	{
		super(location, endLocation);
		
		if(fields.length > 0)
			mEndLocation = fields[$ - 1][1].mEndLocation;

		mFields = fields;
	}

	public static TableCtorExp parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.LBrace);
		t = t.nextToken;

		Expression[2][] fields = new Expression[2][2];
		uint i = 0;

		void addPair(Expression k, Expression v)
		{
			if(i >= fields.length)
				fields.length = fields.length * 2;

			fields[i][0] = k;
			fields[i][1] = v;
			i++;
		}

		if(t.type != Token.Type.RBrace)
		{
			int index = 0;

			bool lastWasFunc = false;

			void parseField()
			{
				Expression k;
				Expression v;

				lastWasFunc = false;
				
				switch(t.type)
				{
					case Token.Type.LBracket:
						t = t.nextToken;
						k = Expression.parse(t);
	
						t.check(Token.Type.RBracket);
						t = t.nextToken;
						t.check(Token.Type.Assign);
						t = t.nextToken;
	
						v = Expression.parse(t);
						break;

					case Token.Type.Function:
						FuncDef fd = FuncDef.parseSimple(t);
						k = new StringExp(fd.mLocation, fd.mName.mName);
						v = new FuncLiteralExp(fd.mLocation, fd.mEndLocation, fd);
						lastWasFunc = true;
						break;

					default:
						Identifier id = Identifier.parse(t);
	
						t.check(Token.Type.Assign);
						t = t.nextToken;
	
						k = new StringExp(id.mLocation, id.mName);
						v = Expression.parse(t);
						break;
				}

				addPair(k, v);
			}

			parseField();

			while(t.type != Token.Type.RBrace)
			{
				if(lastWasFunc)
				{
					if(t.type == Token.Type.Comma)
						t = t.nextToken;
				}
				else
				{
					t.check(Token.Type.Comma);
					t = t.nextToken;
				}

				parseField();
			}
		}

		fields.length = i;

		t.check(Token.Type.RBrace);
		Location endLocation = t.location;
		t = t.nextToken;

		return new TableCtorExp(location, endLocation, fields);
	}

	public override void codeGen(FuncState s)
	{
		uint destReg = s.pushRegister();
		s.codeI(mLocation.line, Op.NewTable, destReg, 0);

		foreach(Expression[2] field; mFields)
		{
			field[0].codeGen(s);
			Exp idx;
			s.popSource(field[0].mEndLocation.line, idx);

			field[1].codeGen(s);
			Exp val;
			s.popSource(field[1].mEndLocation.line, val);

			s.codeR(field[1].mEndLocation.line, Op.IndexAssign, destReg, idx.index, val.index);

			s.freeExpTempRegs(&val);
			s.freeExpTempRegs(&idx);
		}

		s.pushTempReg(destReg);
	}

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(mLocation, "Cannot use a table constructor as a condition");
	}
	
	public override Expression fold()
	{
		foreach(inout field; mFields)
		{
			field[0] = field[0].fold();
			field[1] = field[1].fold();
		}

		return this;
	}
}

class ArrayCtorExp : PrimaryExp
{
	protected Expression[] mFields;

	protected const uint maxFields = Instruction.arraySetFields * Instruction.rtMax;

	public this(Location location, Location endLocation, Expression[] fields)
	{
		super(location, endLocation);
		
		if(fields.length > 0)
			mEndLocation = fields[$ - 1].mEndLocation;

		mFields = fields;
	}

	public static ArrayCtorExp parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.LBracket);
		t = t.nextToken;

		Expression[] fields = new Expression[2];
		uint i = 0;

		void add(Expression v)
		{
			if(i >= fields.length)
				fields.length = fields.length * 2;

			fields[i] = v;
			i++;
		}

		if(t.type != Token.Type.RBracket)
		{
			add(Expression.parse(t));

			while(t.type != Token.Type.RBracket)
			{
				t.check(Token.Type.Comma);
				t = t.nextToken;

				add(Expression.parse(t));
			}
		}

		fields.length = i;

		t.check(Token.Type.RBracket);
		Location endLocation = t.location;
		t = t.nextToken;

		return new ArrayCtorExp(location, endLocation, fields);
	}

	public override void codeGen(FuncState s)
	{
		if(mFields.length > maxFields)
			throw new MDCompileException(mLocation, "Array constructor has too many fields (more than %s)", maxFields);

		uint min(uint a, uint b)
		{
			return (a > b) ? b : a;
		}

		uint destReg = s.pushRegister();

		if(mFields.length > 0 && mFields[$ - 1].isMultRet())
			s.codeI(mLocation.line, Op.NewArray, destReg, mFields.length - 1);
		else
			s.codeI(mLocation.line, Op.NewArray, destReg, mFields.length);

		if(mFields.length > 0)
		{
			int index = 0;
			int fieldsLeft = mFields.length;
			uint block = 0;

			while(fieldsLeft > 0)
			{
				uint numToDo = min(fieldsLeft, Instruction.arraySetFields);

				Expression.codeGenListToNextReg(s, mFields[index .. index + numToDo]);

				fieldsLeft -= numToDo;

				if(fieldsLeft == 0 && mFields[$ - 1].isMultRet())
					s.codeR(mEndLocation.line, Op.SetArray, destReg, 0, block);
				else
					s.codeR(mFields[index + numToDo - 1].mEndLocation.line, Op.SetArray, destReg, numToDo + 1, block);

				index += numToDo;
				block++;
			}
		}

		s.pushTempReg(destReg);
	}

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(mLocation, "Cannot use an array constructor as a condition");
	}
	
	public override Expression fold()
	{
		foreach(inout field; mFields)
			field = field.fold();
			
		return this;
	}
}

class YieldExp : PrimaryExp
{
	protected Expression[] mArgs;

	public this(Location location, Location endLocation, Expression[] args)
	{
		super(location, endLocation);
		mArgs = args;
	}
	
	public static YieldExp parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Yield);
		t = t.nextToken;
		t.check(Token.Type.LParen);
		t = t.nextToken;
		
		Expression[] args = new Expression[5];
		uint i = 0;

		void add(Expression arg)
		{
			if(i >= args.length)
				args.length = args.length * 2;

			args[i] = arg;
			i++;
		}

		if(t.type != Token.Type.RParen)
		{
			while(true)
			{
				add(Expression.parse(t));

				if(t.type == Token.Type.RParen)
					break;

				t.check(Token.Type.Comma);
				t = t.nextToken;
			}
		}

		args.length = i;

		t.check(Token.Type.RParen);
		Location endLocation = t.location;
		t = t.nextToken;

		return new YieldExp(location, endLocation, args);
	}

	public override void codeGen(FuncState s)
	{
		uint firstReg = s.nextRegister();

		Expression.codeGenListToNextReg(s, mArgs);

		if(mArgs.length == 0)
			s.pushYield(mEndLocation.line, firstReg, 1);
		else if(mArgs[$ - 1].isMultRet())
			s.pushYield(mEndLocation.line, firstReg, 0);
		else
			s.pushYield(mEndLocation.line, firstReg, mArgs.length + 1);
	}

	public void checkToNothing()
	{
		// OK
	}

	public bool isMultRet()
	{
		return true;
	}
	
	public override Expression fold()
	{
		foreach(inout arg; mArgs)
			arg = arg.fold();

		return this;
	}
}
