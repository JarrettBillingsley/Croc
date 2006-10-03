module minid.compiler;

import std.c.stdlib;
import std.conv;
import std.stdio;
import std.stream;
import path = std.path;
import string = std.string;
import utf = std.utf;
import std.asserterror;
import std.perf;

import minid.types;
import minid.opcodes;

/*
metamethods become per-type for ALL types, including tables and userdata.  
there are default metamethods implemented for all types, such as:
	opLength
	opToString
	opTypeString

There is a base class, Object, from which all classes derive.  It has default
implementations for the above methods.

Generally, indexing becomes:
	for arrays: index must be an int, if not, tries metatable
	for tables: tries to index; if not found, tries metatable
	for classes: tries to index; if not found, tries superclass
	for class instances: tries to index; if not found, tries class

Keep :.  That enables things like:

class Foo
{
	method m()
	{
		writefln(this.x);
	}
	
	x = 0;
}

local f = Foo();
f.x = 5;
f:m(); // writes 5

local g = Foo();
g.x = 2;
Foo.m(g); // writes 2

I.e. something like an unbound delegate (pointer-to-member).

New keywords:
'method' - Like declaring a "obj:method()" function - just inserts an implicit "this"
'as' - Attempts to cast a class instance (inst as Class)
'class' - Duh
*/

//debug = REGPUSHPOP;
//debug = VARACTIVATE;

public MDFuncDef compileFile(char[] filename)
{
	auto File f = new File(filename, FileMode.In);
	return compile(path.getBaseName(filename), f);
}

public MDFuncDef compile(char[] name, Stream source)
{
	Token* tokens = Lexer.lex(name, source);
	Chunk ck = Chunk.parse(tokens);
	return ck.codeGen();
}

int toInt(char[] s, int base)
{
	assert(base >= 2 && base <= 36, "toInt - invalid base");

	static char[] transTable =
	[
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 0, 0, 0, 0, 0, 0,
		0, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72,
		73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 0, 0, 0, 0, 0,
		0, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72,
		73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	];

    int length = s.length;

	if(!length)
		throw new ConvError(s);

	int sign = 0;
	int v = 0;

	char maxDigit = '0' + base - 1;

	for(int i = 0; i < length; i++)
	{
		char c = transTable[s[i]];

		if(c >= '0' && c <= maxDigit)
		{
			uint v1 = v;
			v = v * base + (c - '0');

			if(cast(uint)v < v1)
				throw new ConvOverflowError(s);
		}
		else if(c == '-' && i == 0)
		{
			sign = -1;

			if(length == 1)
				throw new ConvError(s);
		}
		else if(c == '+' && i == 0)
		{
			if(length == 1)
				throw new ConvError(s);
		}
		else
			throw new ConvError(s);
	}

	if(sign == -1)
	{
		if(cast(uint)v > 0x80000000)
			throw new ConvOverflowError(s);

		v = -v;
	}
	else
	{
		if(cast(uint)v > 0x7FFFFFFF)
			throw new ConvOverflowError(s);
	}

	return v;
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
		Default,
		Do,
		Else,
		False,
		Finally,
		For,
		Foreach,
		Function,
		If,
		Is,
		Local,
		Method,
		Null,
		Return,
		Switch,
		Throw,
		True,
		Try,
		Vararg,
		While,

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

	public static const char[][] tokenStrings =
	[
		Type.As: "as",
		Type.Break: "break",
		Type.Case: "case",
		Type.Catch: "catch",
		Type.Class: "class",
		Type.Continue: "continue",
		Type.Default: "default",
		Type.Do: "do",
		Type.Else: "else",
		Type.False: "false",
		Type.Finally: "finally",
		Type.For: "for",
		Type.Foreach: "foreach",
		Type.Function: "function",
		Type.If: "if",
		Type.Is: "is",
		Type.Local: "local",
		Type.Method: "method",
		Type.Null: "null",
		Type.Return: "return",
		Type.Switch: "switch",
		Type.Throw: "throw",
		Type.True: "true",
		Type.Try: "try",
		Type.Vararg: "vararg",
		Type.While: "while",

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

	public static Type[char[]] stringToType;

	static this()
	{
		stringToType["as"] = Type.As;
		stringToType["break"] = Type.Break;
		stringToType["case"] = Type.Case;
		stringToType["catch"] = Type.Catch;
		stringToType["class"] = Type.Class;
		stringToType["continue"] = Type.Continue;
		stringToType["default"] = Type.Default;
		stringToType["do"] = Type.Do;
		stringToType["else"] = Type.Else;
		stringToType["false"] = Type.False;
		stringToType["finally"] = Type.Finally;
		stringToType["for"] = Type.For;
		stringToType["foreach"] = Type.Foreach;
		stringToType["function"] = Type.Function;
		stringToType["if"] = Type.If;
		stringToType["is"] = Type.Is;
		stringToType["local"] = Type.Local;
		stringToType["method"] = Type.Method;
		stringToType["null"] = Type.Null;
		stringToType["return"] = Type.Return;
		stringToType["switch"] = Type.Switch;
		stringToType["throw"] = Type.Throw;
		stringToType["true"] = Type.True;
		stringToType["try"] = Type.Try;
		stringToType["vararg"] = Type.Vararg;
		stringToType["while"] = Type.While;
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
				ret = "Identifier: " ~ stringValue;
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
				ret = tokenStrings[cast(uint)type];
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

	public Type type;

	union
	{
		public bool boolValue;
		public char[] stringValue;
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
	protected static char mCharacter;

	public static Token* lex(char[] name, Stream source)
	{
		if(!source.readable)
			throw new MDException("%s", name, ": Source code stream is not readable");

		mLoc = Location(utf.toUTF32(name), 1, 0);

		mSource = new BufferedStream(source);

		nextChar();

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
		return (mCharacter == '\0') || (mCharacter == char.init);
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

	protected static ubyte hexDigitToInt(char c)
	{
		if(c >= '0' && c <= '9')
			return c - '0';

		return std.ctype.tolower(c) - 'a' + 10;
	}

	protected static void nextChar()
	{
		mCharacter = mSource.getc();
		mLoc.column++;
	}

	protected static void nextLine()
	{
		while(isNewline() && !isEOF())
		{
			char old = mCharacter;

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
		char[100] buf;
		uint i = 0;

		void add(char c)
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
				hasPoint = true;

				add(mCharacter);
				nextChar();
			}
			else if(mCharacter == '_')
				continue;
			else
				// this will still handle exponents on literals without a decimal point
				break;
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
				iret = std.conv.toInt(buf[0 .. i]);
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
				fret = std.conv.toFloat(buf[0 .. i]);
			}
			catch(ConvError e)
			{
				throw new MDCompileException(beginning, "Malformed float literal '%s'", buf[0 .. i]);
			}

			return false;
		}
	}

	protected static char[] readEscapeSequence(Location beginning)
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

		char[] ret;

		assert(mCharacter == '\\', "escape seq - must start on backslash");

		nextChar();
		if(isEOF())
			throw new MDCompileException(beginning, "Unterminated string or character literal");

		switch(mCharacter)
		{
			case 'a':  nextChar(); return "\a";
			case 'b':  nextChar(); return "\b";
			case 'f':  nextChar(); return "\f";
			case 'n':  nextChar(); return "\n";
			case 'r':  nextChar(); return "\r";
			case 't':  nextChar(); return "\t";
			case 'v':  nextChar(); return "\v";
			case '\\': nextChar(); return "\\";
			case '\"': nextChar(); return "\"";
			case '\'': nextChar(); return "\'";

			case 'x':
				nextChar();

				int x = readHexDigits(2);

				if(x > 0x7F)
					throw new MDCompileException(mLoc, "Hexadecimal escape sequence too large");

				ret ~= cast(char)x;
				break;

			case 'u':
				nextChar();

				int x = readHexDigits(4);

				if(x == 0xFFFE || x == 0xFFFF)
					throw new MDCompileException(mLoc, "Unicode escape '\\u%04x' is illegal", x);

				utf.encode(ret, cast(wchar)x);
				break;

			case 'U':
				nextChar();

				int x = readHexDigits(8);

				if(x == 0xFFFE || x == 0xFFFF)
					throw new MDCompileException(mLoc, "Unicode escape '\\u%04x' is illegal", x);

				if(utf.isValidDchar(cast(dchar)x) == false)
					throw new MDCompileException(mLoc, "Unicode escape '\\U%08x' too large", x);

				utf.encode(ret, cast(dchar)x);
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

				ret ~= cast(char)c;
				break;
		}

		return ret;
	}

	protected static char[] readStringLiteral(bool escape)
	{
		Location beginning = mLoc;
		uint i = 0;
		char[] buf = new char[100];

		void add(char c)
		{
			if(i >= buf.length)
				buf.length = cast(uint)(buf.length * 1.5);

			buf[i] = c;
			i++;
		}

		char delimiter = mCharacter;

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

					char[] esc = readEscapeSequence(beginning);

					foreach(char c; esc)
						add(c);

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

	protected static int readCharLiteral()
	{
		Location beginning = mLoc;
		char[] ret;

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
				ret ~= mCharacter;
				nextChar();
				break;
		}

		if(mCharacter != '\'')
			throw new MDCompileException(beginning, "Unterminated character literal");

		nextChar();

		return cast(int)(utf.toUTF32(ret)[0]);
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

								case '\0', char.init:
									throw new MDCompileException(tokenLoc, "Unterminated /* */ comment");

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

					if(mCharacter == '.')
					{
						nextChar();
						token.type = Token.Type.DotDot;
					}
					else if(isDecimalDigit())
					{
						int dummy;
						bool b = readNumLiteral(true, token.floatValue, dummy);
						assert(b == false, "literal must be float");

						token.type = Token.Type.FloatLiteral;
					}
					else
						token.type = Token.Type.Dot;

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

				case '\0', char.init:
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
						char[] s;

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
						char[] s;
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

class CodeWriter
{
	protected Stream mOutput;
	protected uint mTabs = 0;

	public this(Stream output)
	{
		mOutput = output;

		assert(mOutput.writeable, "codewriter - output stream not writeable");
	}

	protected void writeChar(char c)
	{
		mOutput.write(c);
	}

	protected void newLine()
	{
		writeChar('\r');
		writeChar('\n');

		for(uint i = 0; i < mTabs; i++)
			writeChar('\t');
	}

	protected void incIndent()
	{
		mTabs++;
	}

	protected void decIndent()
	{
		mTabs--;
	}

	public void write(char[] s)
	{
		foreach(char c; s)
		{
			switch(c)
			{
				case '{':
					newLine();
					writeChar('{');
					incIndent();
					newLine();
					break;

				case '}':
					decIndent();
					newLine();
					writeChar('}');
					newLine();
					newLine();
					break;

				case ';':
					writeChar(';');
					newLine();
					break;

				default:
					writeChar(c);
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
	Void,
	Null,
	True,
	False,
	ConstInt,
	ConstFloat,
	ConstIndex,
	Local,
	Upvalue,
	Global,
	Indexed,
	Vararg,
	Closure,
	Class,
	Call,
	NeedsDest,
	Src
}

struct Exp
{
	ExpType type;
	uint index;
	uint index2;

	bool isTempReg;
	bool isTempReg2;
	
	//uint attrs;

	union
	{
		int intValue;
		float floatValue;
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
	protected ClassDef[] mClasses;
	protected Location mLocation;
	protected MDValue[] mConstants;
	protected uint mNumParams;
	protected uint mStackSize;
	protected Instruction[] mCode;
	protected uint[] mLineInfo;
	protected dchar[] mGuessedName;

	struct LocVarDesc
	{
		char[] name;
		Location location;
		uint reg;
		bool isActive;
	}

	protected LocVarDesc[] mLocVars;

	struct UpvalDesc
	{
		ExpType type;
		uint index;
		char[] name;
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
			codeClose(line, s.varStart);

		deactivateLocals(s.varStart, s.regStart);

		delete s;
	}

	public void beginStringSwitch(uint line, uint srcReg)
	{
		SwitchDesc* sd = new SwitchDesc;
		sd.switchPC = codeI(line, Op.SwitchString, srcReg, 0);
		sd.isString = true;

		sd.prev = mSwitch;
		mSwitch = sd;
	}

	public void beginIntSwitch(uint line, uint srcReg)
	{
		SwitchDesc* sd = new SwitchDesc;
		sd.switchPC = codeI(line, Op.SwitchInt, srcReg, 0);
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
		mCode[desc.switchPC].imm = mSwitchTables.length - 1;
	}

	public void addCase(Expression exp)
	{
		assert(mSwitch !is null, "adding case outside of a switch");

		IntExp intExp = cast(IntExp)exp;

		if(intExp)
		{
			if(mSwitch.isString == true)
				throw new MDCompileException(exp.mLocation, "Case value must be a  literal");

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

	protected int searchLocal(char[] name, out uint reg)
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

	protected Exp* pushExp()
	{
		if(mExpSP >= mExpStack.length)
			mExpStack.length = mExpStack.length * 2;

		Exp* ret = &mExpStack[mExpSP];
		mExpSP++;

		ret.isTempReg = false;
		ret.isTempReg2 = false;

		return ret;
	}

	protected Exp* popExp()
	{
		mExpSP--;

		assert(mExpSP >= 0, "exp stack underflow");

		return &mExpStack[mExpSP];
	}

	public void pushVoid()
	{
		Exp* e = pushExp();
		e.type = ExpType.Void;
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
		Exp* e = pushExp();

		e.type = ExpType.ConstInt;
		e.intValue = value;
	}

	public void pushFloat(float value)
	{
		Exp* e = pushExp();

		e.type = ExpType.ConstFloat;
		e.floatValue = value;
	}

	public void pushString(dchar[] value)
	{
		pushConst(codeStringConst(value));
	}

	public void pushConst(uint index)
	{
		Exp* e = pushExp();

		e.type = ExpType.ConstIndex;
		e.index = index;
	}

	public void pushVar(Identifier name)
	{
		Exp* e = pushExp();

		ExpType searchVar(FuncState s, bool isOriginal = true)
		{
			uint findUpval()
			{
				for(int i = 0; i < s.mUpvals.length; i++)
					if(s.mUpvals[i].name == name.mName && s.mUpvals[i].type == e.type)
						return i;

				UpvalDesc ud;

				ud.name = name.mName;
				ud.type = e.type;
				ud.index = e.index;

				s.mUpvals ~= ud;

				if(mUpvals.length > MaxUpvalues)
					throw new MDCompileException(mLocation, "Too many upvalues in function");

				return s.mUpvals.length - 1;
			}

			if(s is null)
			{
				e.type = ExpType.Global;
				return ExpType.Global;
			}

			uint reg;
			int index = s.searchLocal(name.mName, reg);

			if(index == -1)
			{
				if(searchVar(s.mParent, false) == ExpType.Global)
					return ExpType.Global;

				e.index = findUpval();
				e.type = ExpType.Upvalue;
				return ExpType.Upvalue;
			}
			else
			{
				e.type = ExpType.Local;
				e.index = reg;

				if(isOriginal == false)
				{
					for(Scope* sc = s.mScope; sc !is null; sc = sc.enclosing)
					{
						if(sc.varStart <= index)
						{
							sc.hasUpval = true;
							break;
						}
					}
				}

				return ExpType.Local;
			}
		}

		if(searchVar(this) == ExpType.Global)
			e.index = codeStringConst(utf.toUTF32(name.mName));
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
	
	public void pushClass(ClassDef c)
	{
		mClasses ~= c;

		Exp baseClass = *popSource(c.mLocation.line);
		Exp* e = pushExp();

		e.type = ExpType.Class;
		e.index = baseClass.index;
		e.isTempReg = baseClass.isTempReg;
		e.index2 = mClasses.length - 1;
	}

	public void freeExpTempRegs(Exp* e)
	{
		if(e.isTempReg2)
			popRegister(e.index2);

		if(e.isTempReg)
			popRegister(e.index);

		e.isTempReg = false;
		e.isTempReg2 = false;
	}

	public void popToNothing()
	{
		if(mExpSP == 0)
			return;

		Exp* src = popExp();

		if(src.type == ExpType.Call)
			mCode[src.index].rs2 = 1;

		freeExpTempRegs(src);
	}

	public void popAssign(uint line)
	{
		Exp* dest = popExp();

		switch(dest.type)
		{
			case ExpType.Local:
				popToRegister(line, dest.index);
				break;

			case ExpType.Upvalue:
				Exp* src = popSource(line);

				codeI(line, Op.SetUpvalue, src.index, dest.index);

				freeExpTempRegs(src);
				delete src;
				break;

			case ExpType.Global:
				Exp* src = popSource(line);

				codeI(line, Op.SetGlobal, src.index, dest.index);

				freeExpTempRegs(src);
				delete src;
				break;

			case ExpType.Indexed:
				Exp* src = popSource(line);

				codeR(line, Op.IndexAssign, dest.index, dest.index2, src.index);

				freeExpTempRegs(src);
				delete src;
				break;
		}

		freeExpTempRegs(dest);
	}

	public void popToRegister(uint line, uint reg)
	{
		Exp* src = popExp();

		assert(src.type != ExpType.Void, "pop void to reg");

		switch(src.type)
		{
			case ExpType.Null:
				codeR(line, Op.LoadNull, reg, 0, 0);
				break;

			case ExpType.True:
				codeR(line, Op.LoadBool, reg, 1, 0);
				break;

			case ExpType.False:
				codeR(line, Op.LoadBool, reg, 0, 0);
				break;

			case ExpType.ConstInt:
				codeI(line, Op.LoadConst, reg, codeIntConst(src.intValue));
				break;

			case ExpType.ConstFloat:
				codeI(line, Op.LoadConst, reg, codeFloatConst(src.floatValue));
				break;

			case ExpType.ConstIndex:
				codeI(line, Op.LoadConst, reg, src.index);
				break;

			case ExpType.Local:
				if(reg != src.index)
					codeR(line, Op.Move, reg, src.index, 0);
				break;

			case ExpType.Upvalue:
				codeI(line, Op.GetUpvalue, reg, src.index);
				break;

			case ExpType.Global:
				codeI(line, Op.GetGlobal, reg, src.index);
				break;

			case ExpType.Indexed:
				codeR(line, Op.Index, reg, src.index, src.index2);
				freeExpTempRegs(src);
				break;

			case ExpType.Vararg:
				codeI(line, Op.Vararg, reg, 2);
				break;

			case ExpType.Closure:
				codeI(line, Op.Closure, reg, src.index);

				foreach(inout UpvalDesc ud; mInnerFuncs[src.index].mUpvals)
				{
					if(ud.type == ExpType.Local)
						codeR(line, Op.Move, 0, ud.index, 0);
					else
						codeI(line, Op.GetUpvalue, 0, ud.index);
				}

				break;
				
			case ExpType.Class:
				codeR(line, Op.Class, reg, src.index2, src.index);
				freeExpTempRegs(src);
				break;

			case ExpType.Call:
				mCode[src.index].rs2 = 2;

				if(reg != src.index2)
					codeR(line, Op.Move, reg, src.index2, 0);

				freeExpTempRegs(src);
				break;

			case ExpType.NeedsDest:
				mCode[src.index].rd = reg;
				break;

			case ExpType.Src:
				if(reg != src.index)
					codeR(line, Op.Move, reg, src.index, 0);

				freeExpTempRegs(src);
				break;

			default:
				assert(false, "pop to reg switch");
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

			case ExpType.Call:
				assert(src.index2 == reg, "pop to regs - trying to pop func call to different reg");
				mCode[src.index].rs2 = num + 1;
				freeExpTempRegs(src);
				break;

			default:
				assert(false, "pop to regs switch");
		}
	}

	public void pushBinOp(uint line, Op type, uint rs1, uint rs2)
	{
		uint pc = codeR(line, type, 0, rs1, rs2);

		Exp* dest = pushExp();
		dest.type = ExpType.NeedsDest;
		dest.index = pc;
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
		e.index = codeR(line, Op.Call, firstReg, numRegs, 0);
		e.type = ExpType.Call;
		e.index2 = firstReg;
		e.isTempReg2 = true;
	}
	
	public void popMoveFromReg(uint line, uint srcReg)
	{
		codeMoveFromReg(line, popExp(), srcReg);
	}

	public void codeMoveFromReg(uint line, Exp* dest, uint srcReg)
	{
		switch(dest.type)
		{
			case ExpType.Local:
				if(dest.index != srcReg)
					codeR(line, Op.Move, dest.index, srcReg, 0);
				break;

			case ExpType.Global:
				codeI(line, Op.SetGlobal, srcReg, dest.index);
				break;

			case ExpType.Upvalue:
				codeI(line, Op.SetUpvalue, srcReg, dest.index);
				break;

			case ExpType.Indexed:
				codeR(line, Op.IndexAssign, dest.index, dest.index2, srcReg);
				freeExpTempRegs(dest);
				break;

			default:
				assert(false);
		}
	}

	public void popField(uint line, Identifier field)
	{
		pushString(utf.toUTF32(field.mName));
		popIndex(line);
	}

	public void popIndex(uint line)
	{
		assert(mExpSP > 1, "pop index from nothing");

		Exp* index = popExp();
		Exp* e = &mExpStack[mExpSP - 1];

		switch(e.type)
		{
			case ExpType.Local:
				// index just stays the same; type and index2 are written to
				break;

			case ExpType.Global:
				uint destReg = pushRegister();
				codeI(line, Op.GetGlobal, destReg, e.index);
				e.index = destReg;
				e.isTempReg = true;
				break;

			case ExpType.Upvalue:
				uint destReg = pushRegister();
				codeI(line, Op.GetUpvalue, destReg, e.index);
				e.index = destReg;
				e.isTempReg = true;
				break;

			case ExpType.Indexed:
				if(e.isTempReg)
					popRegister(e.index);

				uint destReg = pushRegister();
				codeR(line, Op.Index, destReg, e.index, e.index2);
				e.index = destReg;
				e.isTempReg = true;
				break;

			default:
				assert(false);
		}

		toSource(line, index);
		e.index2 = index.index;
		e.isTempReg2 = index.isTempReg;
		e.type = ExpType.Indexed;
	}

	public Exp* popSource(uint line)
	{
		toSource(line, &mExpStack[mExpSP - 1]);
		Exp* n = new Exp;
		*n = *popExp();

		return n;
	}

	protected void toSource(uint line, Exp* e)
	{
		Exp temp = *e;
		temp.type = ExpType.Src;

		void doConst(uint index)
		{
			if(index > Instruction.constMax)
				throw new MDCompileException(mLocation, "Too many constants");

			temp.index = index | Instruction.constBit;
		}

		switch(e.type)
		{
			case ExpType.Null:
				doConst(codeNullConst());
				break;

			case ExpType.True:
				doConst(codeIntConst(1));
				break;

			case ExpType.False:
				doConst(codeIntConst(0));
				break;

			case ExpType.ConstInt:
				doConst(codeIntConst(e.intValue));
				break;

			case ExpType.ConstFloat:
				doConst(codeFloatConst(e.floatValue));
				break;

			case ExpType.ConstIndex:
				doConst(e.index);
				break;

			case ExpType.Local:
				temp.index = e.index;
				break;

			case ExpType.Upvalue:
				temp.index = pushRegister();
				codeI(line, Op.GetUpvalue, temp.index, e.index);
				temp.isTempReg = true;
				break;

			case ExpType.Global:
				temp.index = pushRegister();
				codeI(line, Op.GetGlobal, temp.index, e.index);
				temp.isTempReg = true;
				break;

			case ExpType.Indexed:
				codeR(line, Op.Index, e.index, e.index, e.index2);
				break;

			case ExpType.NeedsDest:
				temp.index = pushRegister();
				mCode[e.index].rd = temp.index;
				temp.isTempReg = true;
				break;

			case ExpType.Call:
				mCode[e.index].rs2 = 2;
				temp.index = e.index2;
				break;

			case ExpType.Closure:
				temp.index = pushRegister();
				codeI(line, Op.Closure, temp.index, e.index);

				foreach(inout UpvalDesc ud; mInnerFuncs[e.index].mUpvals)
				{
					if(ud.type == ExpType.Local)
						codeR(line, Op.Move, 0, ud.index, 0);
					else
						codeI(line, Op.GetUpvalue, 0, ud.index);
				}

				temp.isTempReg = true;
				break;

			case ExpType.Class:
				if(e.isTempReg)
					codeR(line, Op.Class, temp.index, e.index2, e.index);
				else
				{
					temp.index = pushRegister();
					temp.isTempReg = true;
					codeR(line, Op.Class, temp.index, e.index2, e.index);
				}
				break;

			case ExpType.Src:
				break;

			case ExpType.Vararg:
				temp.index = pushRegister();
				codeI(line, Op.Vararg, temp.index, 2);
				temp.isTempReg = true;
				break;

			case ExpType.Void:
			default:
				assert(false, "toSource switch");
		}

		*e = temp;
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
			codeClose(location.line, mScope.continueScope.varStart);

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
			codeClose(location.line, mScope.breakScope.varStart);

		InstRef* i = new InstRef;
		i.pc = codeJ(location.line, Op.Jmp, 1, 0);
		i.trueList = mScope.breakScope.breaks;
		mScope.breakScope.breaks = i;
	}

	public int codeStringConst(dchar[] c)
	{
		foreach(uint i, MDValue v; mConstants)
			if(v.isString() && v.asString() == c)
				return i;

		MDValue v;
		v.value = new MDString(c);

		mConstants ~= v;

		if(mConstants.length > MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}

	public int codeIntConst(int x)
	{
		foreach(uint i, MDValue v; mConstants)
			if(v.isInt() && v.asInt() == x)
				return i;

		MDValue v;
		v.value = x;

		mConstants ~= v;

		if(mConstants.length > MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}

	public int codeFloatConst(float x)
	{
		foreach(uint i, MDValue v; mConstants)
			if(v.isFloat() && v.asFloat() == x)
				return i;

		MDValue v;
		v.value = x;

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

	public void codeNull(uint line, uint reg, uint num)
	{
		codeI(line, Op.LoadNull, reg, num);
	}

	public uint codeR(uint line, Op opcode, ushort dest, ushort src1, ushort src2, uint attrs = 0)
	{
		Instruction i;
		i.opcode = opcode;
		//i.attrs = attrs;
		i.rd = dest;
		i.rs1 = src1;
		i.rs2 = src2;

		mLineInfo ~= line;
		mCode ~= i;
		return mCode.length - 1;
	}

	public uint codeI(uint line, Op opcode, ushort dest, uint imm, uint attrs = 0)
	{
		Instruction i;
		i.opcode = opcode;
		//i.attrs = attrs;
		i.rd = dest;
		i.uimm = imm;

		mLineInfo ~= line;
		mCode ~= i;
		return mCode.length - 1;
	}

	public uint codeJ(uint line, Op opcode, ushort dest, int offs, uint attrs = 0)
	{
		Instruction i;
		i.opcode = opcode;
		//i.attrs = attrs;
		i.rd = dest;
		i.imm = offs;

		mLineInfo ~= line;
		mCode ~= i;
		return mCode.length - 1;
	}

	public void showMe(uint tab = 0)
	{
		writefln(string.repeat("\t", tab), "Function at ", mLocation.toString(), " (guessed name: %s)", mGuessedName);

		foreach(uint i, FuncState s; mInnerFuncs)
		{
			writefln(string.repeat("\t", tab + 1), "Inner Func ", i);
			s.showMe(tab + 1);
		}
		
		foreach(uint i, ClassDef c; mClasses)
		{
			writefln(string.repeat("\t", tab + 1), "Class ", i);
			
			c.showMe(tab + 1);
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
			writefln(string.repeat("\t", tab + 1), "Upvalue %s: %s : %s (%s)", i, u.name, u.index, (u.type == ExpType.Local) ? "local" : "upval");

		foreach(i, c; mConstants)
		{
			switch(c.type)
			{
				case MDValue.Type.Null:
					writefln(string.repeat("\t", tab + 1), "Const %s: null", i);
					break;

				case MDValue.Type.Int:
					writefln(string.repeat("\t", tab + 1), "Const %s: %s", i, c.asInt());
					break;

				case MDValue.Type.Float:
					writefln(string.repeat("\t", tab + 1), "Const %s: %sf", i, c.asFloat());
					break;

				case MDValue.Type.String:
					writefln(string.repeat("\t", tab + 1), "Const %s: \"%s\"", i, c.asString());
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
				ret.mLocVarDescs[i].name = utf.toUTF32(name);
				ret.mLocVarDescs[i].location = location;
				ret.mLocVarDescs[i].reg = reg;
			}
		}

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
	protected MethodDecl[] mMethods;

	struct Field
	{
		dchar[] name;
		Expression initializer;
	}

	protected Field[] mFields;

	public this(Identifier name, Expression baseClass, MethodDecl[] methods, Field[] fields, Location location, Location endLocation)
	{
		mName = name;
		mBaseClass = baseClass;
		mMethods = methods;
		mFields = fields;
		mLocation = location;
		mEndLocation = endLocation;
	}

	public static void parseBody(Location location, inout Token* t, out MethodDecl[] methods, out Field[] fields, out Location endLocation)
	{
		t.check(Token.Type.LBrace);
		t = t.nextToken;
		
		methods = new MethodDecl[10];
		int iMethod = 0;

		void addMethod(MethodDecl m)
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
				case Token.Type.Method:
					addMethod(MethodDecl.parse(t));
					break;
					
				case Token.Type.Ident:
					Identifier id = Identifier.parse(t);

					Expression v;

					if(t.type == Token.Type.Assign)
					{
						t = t.nextToken;
						v = OpEqExp.parse(t);
					}
					else
						v = new NullExp(id.mLocation);

					dchar[] name = utf.toUTF32(id.mName);

					t.check(Token.Type.Semicolon);
					t = t.nextToken;
					
					addField(name, v);
					break;
					
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
			baseClass = OpEqExp.parse(t);
		}
		else
			baseClass = new NullExp(t.location);

		return baseClass;
	}
	
	public void codeGen(FuncState s)
	{
		/*mBaseClass.codeGen(s);
		Exp* base = s.popSource(mLocation.line);
		s.freeExpTempRegs(base);

		uint destReg = s.pushRegister();
		uint nameConst = s.codeStringConst(mName.mName);
		s.codeR(mLocation.line, Op.Class, destReg, nameConst, base.index);

		delete base;

		foreach(Field field; mFields)
		{
			uint index = s.pushStringConst(field.name);

			field.initializer.codeGen(s);
			Exp* val = s.popSource(field.initializer.mEndLocation.line);

			s.codeR(field.initializer.mEndLocation.line, Op.IndexAssign, destReg, index, val.index);

			s.freeExpTempRegs(val);

			delete val;
		}
		
		foreach(MethodDecl method; mMethods)
		{
			uint index = s.pushStringConst(method.name);

			field.initializer.codeGen(s);
			Exp* val = s.popSource(field.initializer.mEndLocation.line);

			s.codeR(field.initializer.mEndLocation.line, Op.IndexAssign, destReg, index, val.index);

			s.freeExpTempRegs(val);

			delete val;
		}

		s.pushTempReg(destReg);*/
	}

	public void showMe(uint tab = 0)
	{
		/*char[] guessedName;
		
		if(mName is null)
			guessedName = "class literal at " ~ mLocation.toString();
		else
			guessedName = mName.mName;

		writefln(string.repeat("\t", tab), "Class at ", mLocation.toString(), " (guessed name: %s)", guessedName);

		foreach(f; mFields)
			writefln(string.repeat("\t", tab + 1), "Field: ", f.name, " = ", f.defaultValue.toString());

		foreach(uint i, FuncState m; mMethodStates)
		{
			writefln(string.repeat("\t", tab + 1), "Method ", i);
			m.showMe(tab + 1);
		}*/
	}
	
	/*public MDClassDef toClassDef()
	{
		MDClassDef cd = new MDClassDef();
		
		cd.mLocation = mLocation;
		
		if(mName is null)
			cd.mGuessedName = "class literal at "d ~ utf.toUTF32(mLocation.toString());
		else
			cd.mGuessedName = utf.toUTF32(mName.mName);

		cd.mMethods.length = mMethods.length;

		foreach(uint i, MethodDecl m; mMethods)
		{
			cd.mMethods[i].name = utf.toUTF32(m.mName.mName);
			cd.mMethods[i].func = mMethodStates[i].toFuncDef();
		}

		cd.mFields.length = mFields.length;
		
		for(int i = 0; i < mFields.length; i++)
		{
			cd.mFields[i].name = mFields[i].name;
			cd.mFields[i].defaultValue = mFields[i].defaultValue;
		}
		
		return cd;
	}*/
}

class Chunk
{
	protected Location mLocation;
	protected Location mEndLocation;
	protected Statement[] mStatements;

	public this(Location location, Location endLocation, Statement[] statements)
	{
		mLocation = location;
		mEndLocation = endLocation;
		mStatements = statements;
	}

	public static Chunk parse(inout Token* t)
	{
		Location location = t.location;
		Statement[] statements = new Statement[10];
		uint i = 0;

		void add(Statement s)
		{
			if(i >= statements.length)
				statements.length = statements.length * 2;

			statements[i] = s;
			i++;
		}

		while(t.type != Token.Type.EOF)
			add(Statement.parse(t));

		t.check(Token.Type.EOF);

		statements.length = i;

		return new Chunk(location, t.location, statements);
	}
	
	public MDFuncDef codeGen()
	{
		FuncState fs = new FuncState(mLocation, "chunk " ~ mLocation.fileName);
		fs.mIsVararg = true;

		foreach(Statement s; mStatements)
			s.codeGen(fs);

		fs.codeI(mEndLocation.line, Op.Ret, 0, 1);

		assert(fs.mExpSP == 0, "chunk - not all expressions have been popped");

		fs.showMe();

		//auto File o = new File(`testoutput.txt`, FileMode.OutNew);
		//CodeWriter cw = new CodeWriter(o);
		//ck.writeCode(cw);

		return fs.toFuncDef();
	}

	void writeCode(CodeWriter cw)
	{
		foreach(Statement s; mStatements)
			s.writeCode(cw);
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
				Token.Type.True:

				return ExpressionStatement.parse(t);

			case Token.Type.Local, Token.Type.Function, Token.Type.Method, Token.Type.Class:
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

	public void writeCode(CodeWriter cw)
	{
		cw.write("<unimplemented>");
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

	public override void writeCode(CodeWriter cw)
	{
		mStatement.writeCode(cw);
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
		Expression exp = Expression.parse(t);
		exp.checkToNothing();

		t.check(Token.Type.Semicolon);
		Location endLocation = t.location;
		t = t.nextToken;

		return new ExpressionStatement(location, endLocation, exp);
	}

	public override void codeGen(FuncState s)
	{
		int freeRegCheck = s.mFreeReg;

		mExpr.checkToNothing();
		mExpr.codeGen(s);
		s.popToNothing();

		assert(s.mFreeReg == freeRegCheck, "not all regs freed");
	}

	public override void writeCode(CodeWriter cw)
	{
		mExpr.writeCode(cw);
		cw.write(";");
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

	public override void writeCode(CodeWriter cw)
	{
		mDecl.writeCode(cw);

		if(cast(LocalDecl)mDecl)
			cw.write(";");
	}
}

abstract class Declaration
{
	protected Location mLocation;
	protected Location mEndLocation;

	public this(Location location, Location endLocation)
	{
		mLocation = location;
		mEndLocation = endLocation;
	}

	public static Declaration parse(inout Token* t)
	{
		Location location = t.location;

		if(t.type == Token.Type.Local)
		{
			t = t.nextToken;

			if(t.type == Token.Type.Function)
				return LocalFuncDecl.parse(t);
			else if(t.type == Token.Type.Ident)
			{
				LocalDecl ret = LocalDecl.parse(t);
				
				t.check(Token.Type.Semicolon);
				t = t.nextToken;

				return ret;
			}
			else
				throw new MDCompileException(location, "'function' or identifier expected after 'local'");
		}
		else if(t.type == Token.Type.Function)
			return FuncDecl.parse(t);
		else if(t.type == Token.Type.Class)
			return ClassDecl.parse(t);
		else
			throw new MDCompileException(location, "Declaration expected");
	}
	
	public static Identifier[] parseParams(inout Token* t, out bool isVararg, bool isMethod = false)
	{
		Identifier[] ret;
		
		if(isMethod)
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
		assert(false, "no codegen routine");
	}

	public void writeCode(CodeWriter cw)
	{
		cw.write("<unimplemented>");
	}
}

class ClassDecl : Declaration
{
	protected ClassDef mDef;

	public this(Identifier name, Expression baseClass, MethodDecl[] methods, ClassDef.Field[] fields, Location location, Location endLocation)
	{
		super(location, endLocation);

		mDef = new ClassDef(name, baseClass, methods, fields, location, endLocation);
	}

	public static ClassDecl parse(inout Token* t)
	{
		Location location = t.location;
		
		t.check(Token.Type.Class);
		t = t.nextToken;

		Identifier name = Identifier.parse(t);
		
		Expression baseClass = ClassDef.parseBaseClass(t);

		MethodDecl[] methods;
		ClassDef.Field[] fields;
		Location endLocation;

		ClassDef.parseBody(location, t, methods, fields, endLocation);
		
		return new ClassDecl(name, baseClass, methods, fields, location, endLocation);
	}

	public override void codeGen(FuncState s)
	{
		mDef.codeGen(s);
		s.pushVar(mDef.mName);
		s.popAssign(mLocation.line);
	}
}

class LocalDecl : Declaration
{
	protected Identifier[] mNames;
	protected Expression mInitializer;

	public this(Identifier[] names, Expression initializer, Location location, Location endLocation)
	{
		super(location, endLocation);

		mNames = names;
		mInitializer = initializer;
	}

	public static LocalDecl parse(inout Token* t)
	{
		// Special: starts on the first identifier
		Location location = t.location;
		
		Location endLocation = t.location;

		Identifier[] names;
		names ~= Identifier.parse(t);

		while(t.type == Token.Type.Comma)
		{
			t = t.nextToken;
			endLocation = t.location;
			names ~= Identifier.parse(t);
		}

		Expression initializer;

		if(t.type == Token.Type.Assign)
		{
			t = t.nextToken;
			initializer = OpEqExp.parse(t);
			endLocation = initializer.mEndLocation;
		}

		return new LocalDecl(names, initializer, location, endLocation);
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
					throw new MDCompileException(n.mLocation, "Local '%s' conflicts with previous definition at %s",
						n.mName, n2.mLocation.toString());
				}
			}
		}

		if(mInitializer)
		{
			if(mNames.length == 1)
			{
				uint destReg = s.nextRegister();
				mInitializer.codeGen(s);
				s.popToRegister(mLocation.line, destReg);
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

			s.codeNull(mLocation.line, reg, mNames.length);
		}

		s.activateLocals(mNames.length);
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("local ");

		foreach(uint i, Identifier n; mNames)
		{
			n.writeCode(cw);

			if(i != mNames.length - 1)
				cw.write(", ");
		}

		if(mInitializer)
		{
			cw.write(" = ");
			mInitializer.writeCode(cw);
		}
	}
}

class LocalFuncDecl : Declaration
{
	protected Identifier mName;
	protected FuncLiteralExp mFunc;

	public this(Identifier name, Identifier[] params, bool isVararg, CompoundStatement funcBody, Location location, Location endLocation)
	{
		super(location, endLocation);

		mName = name;
		mFunc = new FuncLiteralExp(mLocation, params, isVararg, funcBody, utf.toUTF32(mName.mName));
	}

	public static LocalFuncDecl parse(inout Token* t)
	{
		// Special: starts on the "function" token
		Location location = t.location;

		t.check(Token.Type.Function);
		t = t.nextToken;

		Identifier name = Identifier.parse(t);

		bool isVararg;
		Identifier[] params = Declaration.parseParams(t, isVararg);

		CompoundStatement funcBody = CompoundStatement.parse(t);

		return new LocalFuncDecl(name, params, isVararg, funcBody, location, funcBody.mEndLocation);
	}

	public override void codeGen(FuncState s)
	{
		s.insertLocal(mName);
		s.activateLocals(1);

		mFunc.codeGen(s);

		s.pushVar(mName);
		s.popAssign(mEndLocation.line);
	}

	public override void writeCode(CodeWriter cw)
	{
		/*cw.write("local function ");
		mName.writeCode(cw);
		cw.write("(");

		foreach(uint i, Identifier p; mParams)
		{
			p.writeCode(cw);

			if(i != mParams.length - 1)
				cw.write(", ");
		}

		if(mIsVararg)
		{
			if(mParams.length > 0)
				cw.write(", ");

			cw.write("vararg");
		}

		cw.write(")");

		mBody.writeCode(cw);*/
	}
}

class FuncDecl : Declaration
{
	protected Identifier[] mNames;
	protected FuncLiteralExp mFunc;

	public this(Identifier[] names, bool isVararg, Identifier[] params, CompoundStatement funcBody, Location location, Location endLocation)
	{
		super(location, endLocation);

		mNames = names;

		dchar[] guessedName = utf.toUTF32(mNames[0].mName);

		foreach(Identifier n; mNames[1 .. $])
			guessedName ~= "."d ~ utf.toUTF32(n.mName);
			
		mFunc = new FuncLiteralExp(mLocation, params, isVararg, funcBody, guessedName);
	}

	public static FuncDecl parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Function);
		t = t.nextToken;

		Identifier[] names;
		names ~= Identifier.parse(t);

		while(t.type == Token.Type.Dot)
		{
			t = t.nextToken;
			names ~= Identifier.parse(t);
		}

		bool isVararg;
		Identifier[] params = Declaration.parseParams(t, isVararg);

		CompoundStatement funcBody = CompoundStatement.parse(t);

		return new FuncDecl(names, isVararg, params, funcBody, location, funcBody.mEndLocation);
	}

	public override void codeGen(FuncState s)
	{
		mFunc.codeGen(s);
		s.pushVar(mNames[0]);

		foreach(Identifier n; mNames[1 .. $])
			s.popField(mLocation.line, n);

		s.popAssign(mLocation.line);
	}

	public override void writeCode(CodeWriter cw)
	{
		/*cw.write("function ");

		foreach(uint i, Identifier n; mNames[0 .. $ - 1])
		{
			n.writeCode(cw);

			if(i != mNames.length - 2)
				cw.write(".");
		}

		if(mNames.length > 1)
			cw.write(".");

		mNames[$ - 1].writeCode(cw);

		cw.write("(");

		foreach(uint i, Identifier p; mParams)
		{
			p.writeCode(cw);

			if(i != mParams.length - 1)
				cw.write(", ");
		}

		if(mIsVararg)
		{
			if(mParams.length > 0)
				cw.write(", ");

			cw.write("vararg");
		}

		cw.write(")");

		mBody.writeCode(cw);*/
	}
}

class MethodDecl : Declaration
{
	protected Identifier mName;
	protected FuncLiteralExp mFunc;

	public this(Identifier name, Identifier[] params, bool isVararg, CompoundStatement funcBody, Location location, Location endLocation)
	{
		super(location, endLocation);

		mName = name;
		mFunc = new FuncLiteralExp(location, params, isVararg, funcBody, utf.toUTF32(name.mName));
	}

	public static MethodDecl parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Method);
		t = t.nextToken;

		Identifier name = Identifier.parse(t);

		bool isVararg;
		Identifier[] params;
		
		params ~= new Identifier("this", t.location);
		params ~= Declaration.parseParams(t, isVararg);

		CompoundStatement funcBody = CompoundStatement.parse(t);

		return new MethodDecl(name, params, isVararg, funcBody, location, funcBody.mEndLocation);
	}

	public FuncState codeGenNoPush(FuncState s)
	{
		mFunc.codeGen(s);
		Exp* e = s.popExp();
		return s.mInnerFuncs[e.index];
	}

	public override void writeCode(CodeWriter cw)
	{
		/*cw.write("local function ");
		mName.writeCode(cw);
		cw.write("(");

		foreach(uint i, Identifier p; mParams)
		{
			p.writeCode(cw);

			if(i != mParams.length - 1)
				cw.write(", ");
		}

		if(mIsVararg)
		{
			if(mParams.length > 0)
				cw.write(", ");

			cw.write("vararg");
		}

		cw.write(")");

		mBody.writeCode(cw);*/
	}
}

class Identifier
{
	protected char[] mName;
	protected Location mLocation;

	public this(char[] name, Location location)
	{
		mName = name;
		mLocation = location;
	}

	public static Identifier parse(inout Token* t)
	{
		t.check(Token.Type.Ident);

		Identifier id = new Identifier(t.stringValue, t.location);
		t = t.nextToken;

		return id;
	}

	public char[] toString()
	{
		return mName;
	}

	public static char[] toLongString(Identifier[] idents)
	{
		char[] ret = idents[$ - 1].toString();

		if(idents.length > 1)
			for(int i = idents.length - 2; i >= 0; i--)
				ret = string.format("%s.%s", idents[i].toString(), ret);

		return ret;
	}

	public void writeCode(CodeWriter cw)
	{
		cw.write(mName);
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

	public this(Location location, Location endLocation, Statement statement)
	{
		super(location, endLocation);
		mStatements.length = 1;
		mStatements[0] = statement;
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

	public override void writeCode(CodeWriter cw)
	{
		cw.write("{");

		foreach(Statement s; mStatements)
			s.writeCode(cw);

		cw.write("}");
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

		Expression condition = OpEqExp.parse(t);

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

	public override void writeCode(CodeWriter cw)
	{
		cw.write("if(");
		mCondition.writeCode(cw);
		cw.write(")");
		mIfBody.writeCode(cw);

		if(mElseBody)
		{
			cw.write("else ");
			mElseBody.writeCode(cw);
		}
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

		Expression condition = OpEqExp.parse(t);

		t.check(Token.Type.RParen);
		t = t.nextToken;

		Statement whileBody = Statement.parse(t);

		return new WhileStatement(location, whileBody.mEndLocation, condition, whileBody);
	}

	public override void codeGen(FuncState s)
	{
		InstRef* beginLoop = s.getLabel();

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
		delete beginLoop;
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("while(");
		mCondition.writeCode(cw);
		cw.write(")");
		mBody.writeCode(cw);
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

		Expression condition = OpEqExp.parse(t);

		t.check(Token.Type.RParen);
		Location endLocation = t.location;
		t = t.nextToken;

		return new DoWhileStatement(location, endLocation, doBody, condition);
	}

	public override void codeGen(FuncState s)
	{
		InstRef* beginLoop = s.getLabel();

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
		delete beginLoop;
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("do ");
		mBody.writeCode(cw);
		cw.write("while(");
		mCondition.writeCode(cw);
		cw.write(")");
	}
}

class ForStatement : Statement
{
	protected Expression mInit;
	protected LocalDecl mInitDecl;
	protected Expression mCondition;
	protected Expression mIncrement;
	protected Statement mBody;

	public this(Location location, Location endLocation, Expression init, LocalDecl initDecl, Expression condition, Expression increment, Statement forBody)
	{
		super(location, endLocation);

		mInit = init;
		mInitDecl = initDecl;
		mCondition = condition;
		mIncrement = increment;
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
		LocalDecl initDecl;

		if(t.type == Token.Type.Semicolon)
			t = t.nextToken;
		else
		{
			if(t.type == Token.Type.Local)
			{
				// Have to appease the LocalDecl.parse
				t = t.nextToken;
				initDecl = LocalDecl.parse(t);
			}
			else
				init = Expression.parse(t);

			t.check(Token.Type.Semicolon);
			t = t.nextToken;
		}

		Expression condition;

		if(t.type == Token.Type.Semicolon)
			t = t.nextToken;
		else
		{
			condition = OpEqExp.parse(t);
			t.check(Token.Type.Semicolon);
			t = t.nextToken;
		}

		Expression increment;

		if(t.type == Token.Type.RParen)
			t = t.nextToken;
		else
		{
			increment = Expression.parse(t);
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
			s.setContinuable();

			if(mInitDecl)
				mInitDecl.codeGen(s);
			else
			{
				mInit.checkToNothing();
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

			if(mIncrement)
			{
				mIncrement.checkToNothing();
				mIncrement.codeGen(s);
				s.popToNothing();
			}

			s.codeJump(mEndLocation.line, beginLoop);

			s.patchBreaksToHere();

			delete beginLoop;
		s.popScope(mEndLocation.line);

		if(mCondition)
		{
			s.patchFalseToHere(cond);
			s.patchJumpToHere(cond);
			delete cond;
		}
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("for(");

		if(mInit)
			mInit.writeCode(cw);
		else if(mInitDecl)
			mInitDecl.writeCode(cw);

		cw.write(";");

		if(mCondition)
			mCondition.writeCode(cw);

		cw.write(";");

		if(mIncrement)
			mIncrement.writeCode(cw);

		cw.write(")");

		mBody.writeCode(cw);
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

	public static ForeachStatement parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Foreach);
		t = t.nextToken;
		t.check(Token.Type.LParen);
		t = t.nextToken;

		Identifier[] indices;

		t.check(Token.Type.Local);
		t = t.nextToken;

		indices ~= Identifier.parse(t);

		while(t.type == Token.Type.Comma)
		{
			t = t.nextToken;

			t.check(Token.Type.Local);
			t = t.nextToken;

			indices ~= Identifier.parse(t);
		}

		t.check(Token.Type.Semicolon);
		t = t.nextToken;

		Expression[] container;
		container ~= OpEqExp.parse(t);

		while(t.type == Token.Type.Comma)
		{
			t = t.nextToken;
			container ~= OpEqExp.parse(t);
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

			if(mContainer.length == 3)
			{
				foreach(uint i, Expression c; mContainer)
				{
					c.codeGen(s);
					s.popToRegister(c.mLocation.line, i + baseReg);
				}
			}
			else
			{
				for(uint i = 0; i < mContainer.length - 1; i++)
				{
					mContainer[i].codeGen(s);
					s.popToRegister(mContainer[i].mLocation.line, i + baseReg);
				}

				mContainer[$ - 1].codeGen(s);

				if(mContainer[$ - 1].isMultRet())
					s.popToRegisters(mContainer[$ - 1].mLocation.line, baseReg + mContainer.length - 1, 3 - mContainer.length + 1);
				else
				{
					s.popToRegister(mContainer[$ - 1].mLocation.line, baseReg + mContainer.length - 1);
					s.codeNull(mContainer[$ - 1].mLocation.line, baseReg + mContainer.length, 3 - mContainer.length);
				}
			}

			uint generator = s.pushRegister();
			uint invState = s.pushRegister();
			uint control = s.pushRegister();

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

	public override void writeCode(CodeWriter cw)
	{
		cw.write("foreach(");

		foreach(uint i, Identifier index; mIndices)
		{
			cw.write("local ");
			index.writeCode(cw);

			if(i != mIndices.length - 1)
				cw.write(", ");
		}

		cw.write(";");
		mContainer[0].writeCode(cw);

		foreach(Expression c; mContainer[1 .. $])
		{
			cw.write(", ");
			c.writeCode(cw);
		}

		cw.write(")");
		mBody.writeCode(cw);
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

		Expression condition = OpEqExp.parse(t);

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
			Exp* src = s.popSource(mLocation.line);

			if(cast(IntExp)mCases[0].mCondition)
				s.beginIntSwitch(mLocation.line, src.index);
			else
				s.beginStringSwitch(mLocation.line, src.index);

			s.freeExpTempRegs(src);
			delete src;

			foreach(CaseStatement c; mCases)
				c.codeGen(s);

			if(mDefault)
				mDefault.codeGen(s);

			s.endSwitch();

			s.patchBreaksToHere();
		s.popScope(mEndLocation.line);
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("switch(");
		mCondition.writeCode(cw);
		cw.write("){");

		foreach(CaseStatement c; mCases)
			c.writeCode(cw);

		if(mDefault)
			mDefault.writeCode(cw);

		cw.write("}");
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

		while(true)
		{
			switch(t.type)
			{
				case Token.Type.IntLiteral, Token.Type.CharLiteral:
					addCase(new IntExp(t.location, t.intValue));
					t = t.nextToken;
					break;

				case Token.Type.StringLiteral:
					addCase(new StringExp(t.location, utf.toUTF32(t.stringValue)));
					t = t.nextToken;
					break;

				default:
					throw new MDCompileException(t.location,
						"Case value can only be an integer or string literal, not '%s'", t.toString());
			}

			if(t.type != Token.Type.Comma)
				break;

			t = t.nextToken;
		}

		cases.length = i;

		// OpEqExp.parse() should catch this, but just to be safe
		assert(cases.length > 0);

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
		
		Location endLocation = statements[$ - 1].mEndLocation;

		Statement ret = new CompoundStatement(location, endLocation, statements);
		ret = new ScopeStatement(location, endLocation, ret);

		for(i = cases.length - 1; i >= 0; i--)
			ret = new CaseStatement(location, endLocation, cases[i], ret);

		assert(cast(CaseStatement)ret !is null);

		return cast(CaseStatement)ret;
	}

	public override void codeGen(FuncState s)
	{
		s.addCase(mCondition);
		mBody.codeGen(s);
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("case ");
		mCondition.writeCode(cw);
		cw.write(":");
		mBody.writeCode(cw);
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
		
		Location endLocation = statements[$ - 1].mEndLocation;

		Statement defaultBody = new CompoundStatement(location, endLocation, statements);
		defaultBody = new ScopeStatement(location, endLocation, defaultBody);
		return new DefaultStatement(location, endLocation, defaultBody);
	}

	public override void codeGen(FuncState s)
	{
		s.addDefault();
		mBody.codeGen(s);
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("default:");
		mBody.writeCode(cw);
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

	public override void writeCode(CodeWriter cw)
	{
		cw.write("continue;");
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

	public override void writeCode(CodeWriter cw)
	{
		cw.write("break;");
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

			add(OpEqExp.parse(t));

			while(t.type == Token.Type.Comma)
			{
				t = t.nextToken;
				add(OpEqExp.parse(t));
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

			Expression.codeGenListToNextReg(s, mExprs);

			if(mExprs[$ - 1].isMultRet())
				s.codeI(mEndLocation.line, Op.Ret, firstReg, 0);
			else
				s.codeI(mEndLocation.line, Op.Ret, firstReg, mExprs.length + 1);
		}
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("return ");

		foreach(uint i, Expression e; mExprs)
		{
			e.writeCode(cw);

			if(i != mExprs.length - 1)
				cw.write(", ");
		}

		cw.write(";");
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

		Statement tryBody = CompoundStatement.parse(t);
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

			catchBody = CompoundStatement.parse(t);
			catchBody = new ScopeStatement(catchBody.mLocation, catchBody.mEndLocation, catchBody);
			
			endLocation = catchBody.mEndLocation;
		}

		Statement finallyBody;

		if(t.type == Token.Type.Finally)
		{
			t = t.nextToken;
			finallyBody = CompoundStatement.parse(t);
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

	public override void writeCode(CodeWriter cw)
	{
		cw.write("try");
		mTryBody.writeCode(cw);

		if(mCatchBody)
		{
			cw.write("catch(");
			mCatchVar.writeCode(cw);
			cw.write(")");
			mCatchBody.writeCode(cw);
		}

		if(mFinallyBody)
		{
			cw.write("finally");
			mFinallyBody.writeCode(cw);
		}
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

		Expression exp = OpEqExp.parse(t);

		t.check(Token.Type.Semicolon);
		Location endLocation = t.location;
		t = t.nextToken;

		return new ThrowStatement(location, endLocation, exp);
	}

	public override void codeGen(FuncState s)
	{
		mExp.codeGen(s);

		Exp* src = s.popSource(mLocation.line);

		s.codeR(mEndLocation.line, Op.Throw, 0, src.index, 0);

		s.freeExpTempRegs(src);
		delete src;
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("throw ");
		mExp.writeCode(cw);
		cw.write(";");
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
		Expression exp;

		if(t.type == Token.Type.Ident)
		{
			exp = PrimaryExp.parse(t);

			if(t.type == Token.Type.Assign || t.type == Token.Type.Comma)
				exp = Assignment.parse(t, exp);
			else
				exp = OpEqExp.parse(t, exp);
		}
		else
			exp = OpEqExp.parse(t);

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
				s.popToRegister(exprs[0].mEndLocation.line, firstReg);
		}
		else
		{
			uint firstReg = s.nextRegister();
			exprs[0].codeGen(s);
			s.popToRegister(exprs[0].mEndLocation.line, firstReg);
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
					s.popToRegister(e.mEndLocation.line, lastReg);

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

	public void writeCode(CodeWriter cw)
	{
		cw.write("<unimplemented>");
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

		return new Assignment(location, rhs.mEndLocation, lhs, rhs);
	}

	public override void codeGen(FuncState s)
	{
		if(mLHS.length == 1)
		{
			mRHS.codeGen(s);
			mLHS[0].codeGen(s);
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

		// to appease popToNothing
		s.pushVoid();
	}

	public override InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(mLocation, "Assignments cannot be used as a condition");
	}

	public override void checkToNothing()
	{
		// OK
	}

	public override void writeCode(CodeWriter cw)
	{
		foreach(uint i, Expression e; mLHS)
		{
			e.writeCode(cw);

			if(i != mLHS.length - 1)
				cw.write(", ");
		}

		cw.write(" = ");

		mRHS.writeCode(cw);
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
		Exp* src1 = s.popSource(mOp1.mEndLocation.line);
		mOp2.codeGen(s);
		Exp* src2 = s.popSource(mEndLocation.line);

		s.freeExpTempRegs(src2);
		s.freeExpTempRegs(src1);

		s.pushBinOp(mEndLocation.line, mType, src1.index, src2.index);

		delete src1;
		delete src2;
	}

	public override InstRef* codeCondition(FuncState s)
	{
		uint temp = s.pushRegister();
		codeGen(s);
		s.popToRegister(mEndLocation.line, temp);
		s.codeR(mEndLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* ret = s.makeJump(mEndLocation.line, Op.Je);
		s.popRegister(temp);
		return ret;
	}
}

class OpEqExp : BinaryExp
{
	protected Op mType;

	public this(Location location, Location endLocation, Op type, Expression left, Expression right)
	{
		super(location, endLocation, type, left, right);
	}

	public static Expression parse(inout Token* t, Expression exp1 = null)
	{
		if(exp1 is null)
			exp1 = OrOrExp.parse(t);

		Expression exp2;

		while(true)
		{
			Location location = t.location;

			Op type;
			switch(t.type)
			{
				case Token.Type.AddEq:  type = Op.Add;  goto _commonParse;
				case Token.Type.SubEq:  type = Op.Sub;  goto _commonParse;
				case Token.Type.CatEq:  type = Op.Cat;  goto _commonParse;
				case Token.Type.MulEq:  type = Op.Mul;  goto _commonParse;
				case Token.Type.DivEq:  type = Op.Div;  goto _commonParse;
				case Token.Type.ModEq:  type = Op.Mod;  goto _commonParse;
				case Token.Type.ShlEq:  type = Op.Shl;  goto _commonParse;
				case Token.Type.ShrEq:  type = Op.Shr;  goto _commonParse;
				case Token.Type.UShrEq: type = Op.UShr; goto _commonParse;
				case Token.Type.OrEq:   type = Op.Or;   goto _commonParse;
				case Token.Type.XorEq:  type = Op.Xor;  goto _commonParse;
				case Token.Type.AndEq:  type = Op.And;

				_commonParse:
					t = t.nextToken;
					exp2 = OpEqExp.parse(t);
					exp1 = new OpEqExp(location, exp2.mEndLocation, type, exp1, exp2);
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
		super.codeGen(s);
		mOp1.codeGen(s);
		s.popAssign(mEndLocation.line);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		switch(mType)
		{
			case Op.Add:  throw new MDCompileException(mLocation, "'+=' cannot be used as a condition");
			case Op.Sub:  throw new MDCompileException(mLocation, "'-=' cannot be used as a condition");
			case Op.Cat:  throw new MDCompileException(mLocation, "'~=' cannot be used as a condition");
			case Op.Mul:  throw new MDCompileException(mLocation, "'*=' cannot be used as a condition");
			case Op.Div:  throw new MDCompileException(mLocation, "'/=' cannot be used as a condition");
			case Op.Mod:  throw new MDCompileException(mLocation, "'%=' cannot be used as a condition");
			case Op.Shl:  throw new MDCompileException(mLocation, "'<<=' cannot be used as a condition");
			case Op.Shr:  throw new MDCompileException(mLocation, "'>>=' cannot be used as a condition");
			case Op.UShr: throw new MDCompileException(mLocation, "'>>>=' cannot be used as a condition");
			case Op.Or:   throw new MDCompileException(mLocation, "'|=' cannot be used as a condition");
			case Op.Xor:  throw new MDCompileException(mLocation, "'^=' cannot be used as a condition");
			case Op.And:  throw new MDCompileException(mLocation, "'&=' cannot be used as a condition");
		}
	}

	public override void checkToNothing()
	{
		// OK
	}

	public override void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);

		switch(mType)
		{
			case Op.Add:  cw.write(" += "); break;
			case Op.Sub:  cw.write(" -= "); break;
			case Op.Cat:  cw.write(" ~= "); break;
			case Op.Mul:  cw.write(" *= "); break;
			case Op.Div:  cw.write(" /= "); break;
			case Op.Mod:  cw.write(" %= "); break;
			case Op.Shl:  cw.write(" <<= "); break;
			case Op.Shr:  cw.write(" >>= "); break;
			case Op.UShr: cw.write(" >>>= "); break;
			case Op.Or:   cw.write(" |= "); break;
			case Op.Xor:  cw.write(" ^= "); break;
			case Op.And:  cw.write(" &= "); break;
		}

		mOp2.writeCode(cw);
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
		s.popToRegister(mOp1.mEndLocation.line, temp);
		s.codeR(mOp1.mEndLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* i = s.makeJump(mOp1.mEndLocation.line, Op.Je);
		mOp2.codeGen(s);
		s.popToRegister(mEndLocation.line, temp);
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

	public override void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" || ");
		mOp2.writeCode(cw);
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
		s.popToRegister(mOp1.mEndLocation.line, temp);
		s.codeR(mOp1.mEndLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* i = s.makeJump(mOp1.mEndLocation.line, Op.Je, false);
		mOp2.codeGen(s);
		s.popToRegister(mEndLocation.line, temp);
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

	public override void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" && ");
		mOp2.writeCode(cw);
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

	public override void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" | ");
		mOp2.writeCode(cw);
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

	public override void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" ^ ");
		mOp2.writeCode(cw);
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

	public override void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" & ");
		mOp2.writeCode(cw);
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
		s.popToRegister(mEndLocation.line, temp);
		InstRef* j = s.makeJump(mEndLocation.line, Op.Jmp);
		s.patchJumpToHere(i);
		delete i;
		s.pushBool(true);
		s.popToRegister(mEndLocation.line, temp);
		s.patchJumpToHere(j);
		delete j;
		s.pushTempReg(temp);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		mOp1.codeGen(s);
		Exp* src1 = s.popSource(mOp1.mEndLocation.line);
		mOp2.codeGen(s);
		Exp* src2 = s.popSource(mEndLocation.line);

		s.freeExpTempRegs(src2);
		s.freeExpTempRegs(src1);

		s.codeR(mEndLocation.line, mType, 0, src1.index, src2.index);

		delete src1;
		delete src2;

		return s.makeJump(mEndLocation.line, Op.Je, mIsTrue);
	}

	public override void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);

		switch(mType)
		{
			case Op.Cmp: if(mIsTrue) cw.write(" == "); else cw.write(" != "); break;
			case Op.Is:  if(mIsTrue) cw.write(" is "); else cw.write(" !is "); break;
		}

		mOp2.writeCode(cw);
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
		s.popToRegister(mEndLocation.line, temp);
		InstRef* j = s.makeJump(mEndLocation.line, Op.Jmp);
		s.patchJumpToHere(i);
		delete i;
		s.pushBool(true);
		s.popToRegister(mEndLocation.line, temp);
		s.patchJumpToHere(j);
		delete j;
		s.pushTempReg(temp);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		mOp1.codeGen(s);
		Exp* src1 = s.popSource(mOp1.mEndLocation.line);
		mOp2.codeGen(s);
		Exp* src2 = s.popSource(mEndLocation.line);

		s.freeExpTempRegs(src2);
		s.freeExpTempRegs(src1);

		s.codeR(mEndLocation.line, Op.Cmp, 0, src1.index, src2.index);

		delete src1;
		delete src2;

		switch(mCmpType)
		{
			case Token.Type.LT: return s.makeJump(mEndLocation.line, Op.Jlt, true);
			case Token.Type.LE: return s.makeJump(mEndLocation.line, Op.Jle, true);
			case Token.Type.GT: return s.makeJump(mEndLocation.line, Op.Jle, false);
			case Token.Type.GE: return s.makeJump(mEndLocation.line, Op.Jlt, false);
			default: assert(false);
		}
	}

	public override void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);

		switch(mCmpType)
		{
			case Token.Type.LT: cw.write(" < "); break;
			case Token.Type.LE: cw.write(" <= "); break;
			case Token.Type.GT: cw.write(" > "); break;
			case Token.Type.GE: cw.write(" >= "); break;
		}

		mOp2.writeCode(cw);
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
	
	public override void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);

		cw.write(" as ");

		mOp2.writeCode(cw);
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
			default: assert(false, "BaseShiftExp ctor type switch");
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

	public override void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);

		switch(mType)
		{
			case Op.Shl: cw.write(" << "); break;
			case Op.Shr: cw.write(" >> "); break;
			case Op.UShr: cw.write(" >>> "); break;
		}

		mOp2.writeCode(cw);
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
			case Token.Type.Cat: t = Op.Cat; break;
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
				case Token.Type.Add, Token.Type.Sub, Token.Type.Cat:
					t = t.nextToken;
					exp2 = MulExp.parse(t);
					exp1 = new AddExp(location, exp2.mEndLocation, type, exp1, exp2);
					continue;

				default:
					break;
			}

			break;
		}

		return exp1;
	}

	public override void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);

		switch(mType)
		{
			case Op.Add: cw.write(" + "); break;
			case Op.Sub: cw.write(" - "); break;
			case Op.Cat: cw.write(" ~ "); break;
		}

		mOp2.writeCode(cw);
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

	public override void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);

		switch(mType)
		{
			case Op.Mul: cw.write(" * "); break;
			case Op.Div: cw.write(" / "); break;
			case Op.Mod: cw.write(" % "); break;
		}

		mOp2.writeCode(cw);
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
			case Token.Type.Inc:
				t = t.nextToken;
				exp = UnaryExp.parse(t);
				exp = new OpEqExp(location, location, Op.Add, exp, new IntExp(location, 1));
				break;

			case Token.Type.Dec:
				t = t.nextToken;
				exp = UnaryExp.parse(t);
				exp = new OpEqExp(location, location, Op.Sub, exp, new IntExp(location, 1));
				break;

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
		s.popToRegister(mEndLocation.line, temp);
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
		IntExp intExp = cast(IntExp)mOp;

		if(intExp)
		{
			intExp.mValue = -intExp.mValue;
			intExp.codeGen(s);
			return;
		}

		FloatExp floatExp = cast(FloatExp)mOp;

		if(floatExp)
		{
			floatExp.mValue = -floatExp.mValue;
			floatExp.codeGen(s);
			return;
		}

		mOp.codeGen(s);
		s.popUnOp(mEndLocation.line, Op.Neg);
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("-");
		mOp.writeCode(cw);
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
		BoolExp boolExp = cast(BoolExp)mOp;

		if(boolExp)
		{
			boolExp.mValue = !boolExp.mValue;
			boolExp.codeGen(s);
			return;
		}

		NullExp nullExp = cast(NullExp)mOp;

		if(nullExp)
		{
			BoolExp e = new BoolExp(nullExp.mLocation, true);
			e.codeGen(s);
			return;
		}

		mOp.codeGen(s);
		s.popUnOp(mEndLocation.line, Op.Not);
	}

	public override InstRef* codeCondition(FuncState s)
	{
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

			return cmpExp.codeCondition(s);
		}

		EqualExp equalExp = cast(EqualExp)mOp;

		if(equalExp)
		{
			equalExp.mIsTrue = !equalExp.mIsTrue;
			return equalExp.codeCondition(s);
		}

		return super.codeCondition(s);
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("!");
		mOp.writeCode(cw);
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
		IntExp intExp = cast(IntExp)mOp;

		if(intExp)
		{
			intExp.mValue = ~intExp.mValue;
			intExp.codeGen(s);
			return;
		}

		mOp.codeGen(s);
		s.popUnOp(mEndLocation.line, Op.Com);
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("~");
		mOp.writeCode(cw);
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
		StringExp stringExp = cast(StringExp)mOp;

		if(stringExp)
		{
			IntExp intExp = new IntExp(stringExp.mLocation, stringExp.mValue.length);
			intExp.codeGen(s);
			return;
		}

		mOp.codeGen(s);
		s.popUnOp(mEndLocation.line, Op.Length);
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("#");
		mOp.writeCode(cw);
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

			Identifier methodName;

			switch(t.type)
			{
				case Token.Type.Dot:
					t = t.nextToken;

					t.check(Token.Type.Ident);

					Location loc = t.location;
					
					IdentExp ie = new IdentExp(loc, Identifier.parse(t));

					exp = new DotExp(location, ie.mEndLocation, exp, ie);
					continue;

				case Token.Type.Colon:
					t = t.nextToken;

					t.check(Token.Type.Ident);

					methodName = Identifier.parse(t);

					t.check(Token.Type.LParen);

					// fall through
				case Token.Type.LParen:
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
							add(OpEqExp.parse(t));

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

					exp = new CallExp(location, endLocation, exp, args, methodName);
					continue;

				case Token.Type.LBracket:
					t = t.nextToken;

					Expression index = OpEqExp.parse(t);

					t.check(Token.Type.RBracket);
					Location endLocation = t.location;
					t = t.nextToken;

					exp = new IndexExp(location, endLocation, exp, index);
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
		s.popField(mEndLocation.line, mIdent.mIdent);
	}

	public InstRef* codeCondition(FuncState s)
	{
		uint temp = s.pushRegister();
		codeGen(s);
		s.popToRegister(mEndLocation.line, temp);
		s.codeR(mEndLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* ret = s.makeJump(mEndLocation.line, Op.Je);
		s.popRegister(temp);
		return ret;
	}

	public override void writeCode(CodeWriter cw)
	{
		mOp.writeCode(cw);
		cw.write(".");
		mIdent.writeCode(cw);
	}
}

class CallExp : PostfixExp
{
	protected Expression[] mArgs;
	protected Identifier mMethodName;

	public this(Location location, Location endLocation, Expression operand, Expression[] args, Identifier methodName)
	{
		super(location, endLocation, operand);

		mArgs = args;
		mMethodName = methodName;
	}

	public override void codeGen(FuncState s)
	{
		/*
		regular:
			1. evaluate function exp, put in reg 1
			2. evaluate args, put in regs 2..
			3. call reg 1, num params + 1

		method:
			1. evaluate function exp
			2. method reg 1, function exp, stringConst(methodname)
			3. evaluate args, put in regs 3..
			4. call reg 1, num params + 2
		*/

		if(mMethodName)
		{
			uint funcReg = s.nextRegister();
			mOp.codeGen(s);
			
			Exp* src = s.popSource(mOp.mEndLocation.line);
			s.freeExpTempRegs(src);

			assert(s.nextRegister() == funcReg);
			s.pushRegister();

			s.pushString(utf.toUTF32(mMethodName.mName));
			Exp* method = s.popSource(mOp.mEndLocation.line);

			s.codeR(mOp.mEndLocation.line, Op.Method, funcReg, src.index, method.index);

			s.freeExpTempRegs(method);

			uint thisReg = s.pushRegister();

			Expression.codeGenListToNextReg(s, mArgs);

			s.popRegister(thisReg);

			if(mArgs.length == 0)
				s.pushCall(mEndLocation.line, funcReg, 2);
			else if(mArgs[$ - 1].isMultRet())
				s.pushCall(mEndLocation.line, funcReg, 0);
			else
				s.pushCall(mEndLocation.line, funcReg, mArgs.length + 2);

			delete src;
			delete method;
		}
		else
		{
			uint funcReg = s.nextRegister();
			mOp.codeGen(s);

			s.popToRegister(mOp.mEndLocation.line, funcReg);
			s.pushRegister();

			assert(s.nextRegister() == funcReg + 1);

			Expression.codeGenListToNextReg(s, mArgs);

			if(mArgs.length == 0)
				s.pushCall(mEndLocation.line, funcReg, 1);
			else if(mArgs[$ - 1].isMultRet())
				s.pushCall(mEndLocation.line, funcReg, 0);
			else
				s.pushCall(mEndLocation.line, funcReg, mArgs.length + 1);
		}
	}

	public InstRef* codeCondition(FuncState s)
	{
		uint temp = s.pushRegister();
		codeGen(s);
		s.popToRegister(mEndLocation.line, temp);
		s.codeR(mEndLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* ret = s.makeJump(mEndLocation.line, Op.Je);
		s.popRegister(temp);
		return ret;
	}

	public void checkToNothing()
	{
		// OK
	}

	public bool isMultRet()
	{
		return true;
	}

	public override void writeCode(CodeWriter cw)
	{
		mOp.writeCode(cw);

		if(mMethodName)
		{
			cw.write(":");
			mMethodName.writeCode(cw);
		}

		cw.write("(");

		foreach(uint i, Expression e; mArgs)
		{
			e.writeCode(cw);

			if(i != mArgs.length - 1)
				cw.write(", ");
		}

		cw.write(")");
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
		mIndex.codeGen(s);
		s.popIndex(mEndLocation.line);
	}

	public InstRef* codeCondition(FuncState s)
	{
		uint temp = s.pushRegister();
		codeGen(s);
		s.popToRegister(mEndLocation.line, temp);
		s.codeR(mEndLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* ret = s.makeJump(mEndLocation.line, Op.Je);
		s.popRegister(temp);
		return ret;
	}

	public override void writeCode(CodeWriter cw)
	{
		mOp.writeCode(cw);
		cw.write("[");
		mIndex.writeCode(cw);
		cw.write("]");
	}
}

class PrimaryExp : Expression
{
	public this(Location location)
	{
		super(location, location);
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

			case Token.Type.Null:
				exp = NullExp.parse(t);
				break;

			case Token.Type.True, Token.Type.False:
				exp = BoolExp.parse(t);
				break;

			case Token.Type.Vararg:
				exp = VarargExp.parse(t);
				break;

			case Token.Type.CharLiteral, Token.Type.IntLiteral:
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
				t = t.nextToken;
				exp = OpEqExp.parse(t);

				t.check(Token.Type.RParen);
				t = t.nextToken;
				break;
				
			case Token.Type.LBrace:
				exp = TableCtorExp.parse(t);
				break;

			case Token.Type.LBracket:
				exp = ArrayCtorExp.parse(t);
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
		Exp* reg = s.popSource(mEndLocation.line);
		s.codeR(mEndLocation.line, Op.IsTrue, 0, reg.index, 0);
		InstRef* ret = s.makeJump(mEndLocation.line, Op.Je);

		s.freeExpTempRegs(reg);
		delete reg;

		return ret;
	}

	public override void writeCode(CodeWriter cw)
	{
		mIdent.writeCode(cw);
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

	public override void writeCode(CodeWriter cw)
	{
		cw.write("null");
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

	public override void writeCode(CodeWriter cw)
	{
		if(mValue)
			cw.write("true");
		else
			cw.write("false");
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

	public override void writeCode(CodeWriter cw)
	{
		cw.write("vararg");
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

		if(t.type == Token.Type.IntLiteral || t.type == Token.Type.CharLiteral)
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
		s.popToRegister(mEndLocation.line, temp);
		s.codeR(mEndLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* ret = s.makeJump(mEndLocation.line, Op.Je);
		s.popRegister(temp);
		return ret;
	}
	
	public override bool isConstant()
	{
		return true;
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write(string.toString(mValue));
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

	public override void writeCode(CodeWriter cw)
	{
		cw.write(string.toString(mValue));
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

		return new StringExp(t.location, utf.toUTF32(t.stringValue));
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

	public override void writeCode(CodeWriter cw)
	{
		//TODO: Need to escape string

		cw.write("\"");
		cw.write(utf.toUTF8(mValue));
		cw.write("\"");
	}
}

class FuncLiteralExp : PrimaryExp
{
	protected Identifier[] mParams;
	protected bool mIsVararg;
	protected CompoundStatement mBody;
	protected dchar[] mGuessedName;

	public this(Location location, Identifier[] params, bool isVararg, CompoundStatement funcBody, dchar[] guessedName = null)
	{
		super(location);

		mParams = params;
		mIsVararg = isVararg;
		mBody = funcBody;
		mGuessedName = guessedName;
	}

	public static FuncLiteralExp parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Function);
		t = t.nextToken;

		bool isVararg;
		Identifier[] params = Declaration.parseParams(t, isVararg);

		CompoundStatement funcBody = CompoundStatement.parse(t);

		return new FuncLiteralExp(location, params, isVararg, funcBody);
	}

	public override void codeGen(FuncState s)
	{
		FuncState fs;

		if(mGuessedName.length == 0)
			fs = new FuncState(mLocation, "function literal at "d ~ utf.toUTF32(mLocation.toString()), s);
		else
			fs = new FuncState(mLocation, mGuessedName, s);

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

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(mLocation, "Cannot use a function literal as a condition");
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("function(");

		foreach(uint i, Identifier p; mParams)
		{
			p.writeCode(cw);

			if(i != mParams.length - 1)
				cw.write(", ");
		}

		cw.write(")");

		mBody.writeCode(cw);
	}
}

class ClassLiteralExp : PrimaryExp
{
	protected ClassDef mDef;

	public this(Expression baseClass, MethodDecl[] methods, ClassDef.Field[] fields, Location location, Location endLocation)
	{
		super(location);

		mDef = new ClassDef(null, baseClass, methods, fields, location, endLocation);
	}
	
	public static ClassLiteralExp parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Class);
		t = t.nextToken;

		Expression baseClass = ClassDef.parseBaseClass(t);

		MethodDecl[] methods;
		ClassDef.Field[] fields;
		Location endLocation;
		
		ClassDef.parseBody(location, t, methods, fields, endLocation);

		return new ClassLiteralExp(baseClass, methods, fields, location, endLocation);
	}
	
	public override void codeGen(FuncState s)
	{
		mDef.codeGen(s);
	}
	
	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(mLocation, "Cannot use a class literal as a condition");
	}
}

class TableCtorExp : PrimaryExp
{
	protected Expression[2][] mFields;

	public this(Location location, Expression[2][] fields)
	{
		super(location);
		
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

				if(t.type == Token.Type.LBracket)
				{
					t = t.nextToken;
					k = OpEqExp.parse(t);

					t.check(Token.Type.RBracket);
					t = t.nextToken;
					t.check(Token.Type.Assign);
					t = t.nextToken;

					v = OpEqExp.parse(t);
				}
				else if(t.type == Token.Type.Function)
				{
					// Take advantage of the fact that LocalFuncDecl.parse() starts on the 'function' token
					auto LocalFuncDecl fd = LocalFuncDecl.parse(t);
					k = new StringExp(fd.mLocation, utf.toUTF32(fd.mName.mName));
					v = fd.mFunc;
					lastWasFunc = true;
				}
				else
				{
					Identifier id = Identifier.parse(t);

					t.check(Token.Type.Assign);
					t = t.nextToken;

					k = new StringExp(id.mLocation, utf.toUTF32(id.mName));
					v = OpEqExp.parse(t);
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
		t = t.nextToken;

		return new TableCtorExp(location, fields);
	}

	public override void codeGen(FuncState s)
	{
		uint destReg = s.pushRegister();
		s.codeI(mLocation.line, Op.NewTable, destReg, 0);

		foreach(Expression[2] field; mFields)
		{
			field[0].codeGen(s);
			Exp* idx = s.popSource(field[0].mEndLocation.line);

			field[1].codeGen(s);
			Exp* val = s.popSource(field[1].mEndLocation.line);

			s.codeR(field[1].mEndLocation.line, Op.IndexAssign, destReg, idx.index, val.index);

			s.freeExpTempRegs(val);
			s.freeExpTempRegs(idx);

			delete idx;
			delete val;
		}

		s.pushTempReg(destReg);
	}

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(mLocation, "Cannot use a table constructor as a condition");
	}

	public override void writeCode(CodeWriter cw)
	{
		cw.write("{");

		foreach(uint i, Expression[2] field; mFields)
		{
			cw.write("(");
			field[0].writeCode(cw);
			cw.write(") = ");
			field[1].writeCode(cw);

			if(i != mFields.length - 1)
				cw.write(", ");
		}

		cw.write("}");
	}
}

class ArrayCtorExp : PrimaryExp
{
	protected Expression[] mFields;

	protected const uint maxFields = Instruction.arraySetFields * Instruction.rs2Max;

	public this(Location location, Expression[] fields)
	{
		super(location);
		
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
			add(OpEqExp.parse(t));

			while(t.type != Token.Type.RBracket)
			{
				t.check(Token.Type.Comma);
				t = t.nextToken;

				add(OpEqExp.parse(t));
			}
		}

		fields.length = i;

		t.check(Token.Type.RBracket);
		t = t.nextToken;

		return new ArrayCtorExp(location, fields);
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

	public override void writeCode(CodeWriter cw)
	{
		cw.write("[");

		foreach(uint i, Expression field; mFields)
		{
			field.writeCode(cw);

			if(i != mFields.length - 1)
				cw.write(", ");
		}

		cw.write("]");
	}
}
