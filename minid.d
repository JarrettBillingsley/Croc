module minid;

import std.c.stdlib;
import std.conv;
import std.stdio;
import std.stream;
import std.string;
import std.utf;

void main()
{
	auto File f = new File(`simple.md`, FileMode.In);
	auto Compiler c = new Compiler();
	c.compile(`simple.md`, f);
}

class Compiler
{
	public this()
	{

	}

	public void compile(char[] name, Stream source)
	{
		auto Lexer l = new Lexer();
		Token* tokens = l.lex(name, source);

	}
}

int toInt(char[] s, int base)
{
	assert(base >= 2 && base <= 36);

	static char[] transTable =
	[
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 
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

char[] vformat(TypeInfo[] arguments, void* argptr)
{
	char[] s;
	
	void putc(dchar c)
	{
		std.utf.encode(s, c);
	}
	
	std.format.doFormat(&putc, arguments, argptr);
	
	return s;
}

struct Token
{
	public static enum Type
	{
		Break,
		Case,
		Catch,
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
		Ushr,
		UshrEq,
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
		"break",
		"case",
		"catch",
		"continue",
		"default",
		"do",
		"else",
		"false",
		"finally",
		"for",
		"foreach",
		"function",
		"if",
		"is",
		"local",
		"null",
		"return",
		"switch",
		"throw",
		"true",
		"try",
		"vararg",
		"while",

		"+",
		"+=",
		"++",
		"-",
		"-=",
		"--",
		"~",
		"~=",
		"*",
		"*=",
		"/",
		"/=",
		"%",
		"%=",
		"<",
		"<=",
		"<<",
		"<<=",
		">",
		">=",
		">>",
		">>=",
		">>>",
		">>>=",
		"&",
		"&=",
		"&&",
		"|",
		"|=",
		"||",
		"^",
		"^=",
		"=",
		"==",
		".",
		"..",
		"!",
		"!=",
		"(",
		")",
		"[",
		"]",
		"{",
		"}",
		":",
		",",
		";",
		"#",

		"Identifier",
		"Char Literal",
		"String Literal",
		"Int Literal",
		"Float Literal",
		"<EOF>"
	];
	
	public static Type[char[]] stringToType;

	static this()
	{
		stringToType["break"] = Type.Break;
		stringToType["case"] = Type.Case;
		stringToType["catch"] = Type.Catch;
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
				ret = "Integer Literal: " ~ std.string.toString(intValue);
				break;

			case Type.FloatLiteral:
				ret = "Float Literal: " ~ std.string.toString(floatValue);
				break;

			default:
				ret = tokenStrings[cast(uint)type];
				break;
		}
		
		return ret;
	}

	public static char[] toString(Type type)
	{
		return std.utf.toUTF8(tokenStrings[type]);
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

struct Location
{
	public uint line = 1;
	public uint column = 1;
	public char[] fileName;

	public static Location opCall(char[] fileName, uint line = 1, uint column = 1)
	{
		Location l;
		l.fileName = fileName;
		l.line = line;
		l.column = column;
		return l;
	}

	public char[] toString()
	{
		return std.string.format("%s(%d:%d)", fileName, line, column);
	}
}

class MDException : Exception
{
	public this(...)
	{
		char[] msg;

		void putc(dchar c)
		{
			std.utf.encode(msg, c);
		}

		std.format.doFormat(&putc, _arguments, _argptr);

		super(msg);
	}
}

class MDCompileException : MDException
{
	public this(Location loc, ...)
	{
		super(loc.toString(), ": ", vformat(_arguments, _argptr));
	}
}

class Lexer
{
	protected BufferedStream mSource;
	protected Location mLoc;
	protected char mCharacter;

	public this()
	{

	}

	public Token* lex(char[] name, Stream source)
	{
		if(!source.readable)
			throw new MDException(name ~ ": Source code stream is not readable");

		mLoc = Location(name);

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

	protected static bool isEOF(char c)
	{
		return (c == '\0') || (c == char.init);
	}

	protected static bool isEOL(char c)
	{
		return isNewline(c) || isEOF(c);
	}

	protected static bool isWhitespace(char c)
	{
		return (c == ' ') || (c == '\t') || (c == '\v') || (c == '\u000C') || isEOL(c);
	}
	
	protected static bool isNewline(char c)
	{
		return (c == '\r') || (c == '\n');
	}
	
	protected static bool isBinaryDigit(char c)
	{
		return (c == '0') || (c == '1');
	}
	
	protected static bool isOctalDigit(char c)
	{
		return (c >= '0') && (c <= '7');
	}

	protected static bool isHexDigit(char c)
	{
		return ((c >= '0') && (c <= '9')) || ((c >= 'a') && (c <= 'f')) || ((c >= 'A') && (c <= 'F'));
	}

	protected static bool isDecimalDigit(char c)
	{
		return (c >= '0') && (c <= '9');
	}
	
	protected static bool isAlpha(char c)
	{
		return ((c >= 'a') && (c <= 'z')) || ((c >= 'A') && (c <= 'Z'));
	}
	
	protected static ubyte hexDigitToInt(char c)
	{
		if(c >= '0' && c <= '9')	
			return c - '0';

		return std.ctype.tolower(c) - 'a' + 10;
	}

	protected void nextChar()
	{
		mCharacter = mSource.getc();
		mLoc.column++;
	}

	protected void nextLine()
	{
		while(isNewline(mCharacter) && !isEOF(mCharacter))
		{
			char old = mCharacter;

			nextChar();

			if(isNewline(mCharacter) && mCharacter != old)
				nextChar();

			mLoc.line++;
			mLoc.column = 1;
		}
	}
	
	protected bool readNumLiteral(bool prependPoint, out float fret, out int iret)
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
						
						if(!isBinaryDigit(mCharacter))
							throw new MDCompileException(mLoc, "Binary digit expected, not '%s'", mCharacter);

						while(isBinaryDigit(mCharacter) || mCharacter == '_')
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
						
						if(!isOctalDigit(mCharacter))
							throw new MDCompileException(mLoc, "Octal digit expected, not '%s'", mCharacter);

						while(isOctalDigit(mCharacter) || mCharacter == '_')
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
						
						if(!isHexDigit(mCharacter))
							throw new MDCompileException(mLoc, "Hexadecimal digit expected, not '%s'", mCharacter);

						while(isHexDigit(mCharacter) || mCharacter == '_')
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
			if(isDecimalDigit(mCharacter))
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
			if(isDecimalDigit(mCharacter))
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

				if(!isDecimalDigit(mCharacter))
					throw new MDCompileException(mLoc, "Exponent value expected in float literal '%s'", buf[0 .. i]);

				while(isDecimalDigit(mCharacter) || mCharacter == '_')
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
	
	protected char[] readEscapeSequence(Location beginning)
	{
		uint readHexDigits(uint num)
		{
			uint ret = 0;
			
			for(uint i = 0; i < num; i++)
			{
				if(isHexDigit(mCharacter) == false)
					throw new MDCompileException(mLoc, "Hexadecimal escape digits expected");
					
				ret <<= 8;
				ret |= hexDigitToInt(mCharacter);
			}

			return ret;
		}
		
		char[] ret;

		assert(mCharacter == '\\');
		
		nextChar();
		if(isEOF(mCharacter))
			throw new MDCompileException(beginning, "Unterminated string or character literal");

		switch(mCharacter)
		{
			case 'a': return "\a";
			case 'b': return "\b";
			case 'f': return "\f";
			case 'n': return "\n";
			case 'r': return "\r";
			case 't': return "\t";
			case 'v': return "\v";
			case '\\': return "\\";
			case '\"': return "\"";
			case '\'': return "\'";

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

				std.utf.encode(ret, cast(wchar)x);
				break;

			case 'U':
				nextChar();

				int x = readHexDigits(8);

				if(x == 0xFFFE || x == 0xFFFF)
					throw new MDCompileException(mLoc, "Unicode escape '\\u%04x' is illegal", x);

				if(std.utf.isValidDchar(cast(dchar)x) == false)
					throw new MDCompileException(mLoc, "Unicode escape '\\U%08x' too large", x);

				std.utf.encode(ret, cast(dchar)x);
				break;

			default:
				if(!isDecimalDigit(mCharacter))
					throw new MDCompileException(mLoc, "Invalid string escape sequence '\\%s'", mCharacter);

				// Decimal char
				int numch = 0;
				int c = 0;

				do
				{
					c = 10 * c + (mCharacter - '0');
					nextChar();
				} while(++numch < 3 && isDecimalDigit(mCharacter));

				if(c > 0x7F)
					throw new MDCompileException(mLoc, "Numeric escape sequence too large");

				ret ~= cast(char)c;
				break;
		}

		return ret;
	}
	
	protected char[] readStringLiteral(bool escape)
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
			if(isEOF(mCharacter))
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
	
	protected char[] readCharLiteral()
	{
		Location beginning = mLoc;
		char[] ret;

		nextChar();

		if(isEOF(mCharacter))
			throw new MDCompileException(beginning, "Unterminated character literal");

		switch(mCharacter)
		{
			case '\\':
				ret = readEscapeSequence(beginning);
				nextChar();
				break;

			default:
				ret ~= mCharacter;
				nextChar();
				break;
		}
		
		if(mCharacter != '\'')
			throw new MDCompileException(mLoc, "Unterminated character literal");

		return ret;
	}

	protected Token* nextToken()
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
						while(!isEOL(mCharacter))
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
								token.type = Token.Type.UshrEq;
							}
							else
								token.type = Token.Type.Ushr;
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
					else if(isDecimalDigit(mCharacter))
					{
						int dummy;
						bool b = readNumLiteral(true, token.floatValue, dummy);
						assert(b == false);

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
					token.stringValue = readCharLiteral();
					token.type = Token.Type.CharLiteral;
					return token;

				case '\0', char.init:
					token.type = Token.Type.EOF;
					return token;

				default:
					if(isWhitespace(mCharacter))
					{
						nextChar();
						continue;
					}
					else if(isDecimalDigit(mCharacter))
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
					else if(isAlpha(mCharacter) || mCharacter == '_')
					{
						char[] s;
						
						do
						{
							s ~= mCharacter;
							nextChar();
						}
						while(isAlpha(mCharacter) || isDecimalDigit(mCharacter) || mCharacter == '_');
						
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

class Chunk
{
	protected Statement[] mStatements;
	
	public this(Statement[] statements)
	{
		mStatements = statements;
	}

	public static Chunk parse(inout Token* t)
	{
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
			
		statements.length = i;
		
		return new Chunk(statements);
	}
}

abstract class Statement
{
	protected Location mLocation;

	public this(Location location)
	{
		mLocation = location;
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

			case Token.Type.Local, Token.Type.Function:
				return DeclarationStatement.parse(t);

			case Token.Type.LBrace:
				Statement s = CompoundStatement.parse(t);
				return s;
				
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
				
			case Token.Type.Semicolon:
				throw new MDCompileException(t.location, "Empty statements ( ';' ) are not allowed");
				
			default:
				throw new MDCompileException(t.location, "Statement expected, not '%s'", t.toString());
		}
	}
}

class ScopeStatement : Statement
{
	protected Statement mStatement;

	public this(Location location, Statement statement)
	{
		super(location);
		mStatement = statement;
	}
}

class ExpressionStatement : Statement
{
	protected Expression mExpr;
	
	public this(Location location, Expression expr)
	{
		super(location);
		mExpr = expr;
	}
	
	public static ExpressionStatement parse(inout Token* t)
	{
		return new ExpressionStatement(t.location, Expression.parse(t));
	}
}

class DeclarationStatement : Statement
{
	protected Declaration mDecl;

	public this(Location location, Declaration decl)
	{
		super(location);
		mDecl = decl;
	}

	public static DeclarationStatement parse(inout Token* t)
	{
		Location location = t.location;
		return new DeclarationStatement(location, Declaration.parse(t));
	}
}

abstract class Declaration
{
	protected Location mLocation;
	
	public this(Location location)
	{
		mLocation = location;
	}

	public static Declaration parse(inout Token* t)
	{
		Location location = t.location;

		if(t.type == Token.Type.Local)
		{
			t = t.nextToken;
			
			if(t.type == Token.Type.Function)
			{

			}
			else if(t.type == Token.Type.Ident)
			{
				
			}
			else
				throw new MDCompileException(location, "'function' or identifier expected after 'local'");
		}
		else if(t.type == Token.Type.Function)
		{

		}
		else
			throw new MDCompileException(location, "Declaration expected");
	}
}

class LocalDecl : Declaration
{
	protected Identifier[] mNames;
	protected Expression[] mInitializers;

	public this(Identifier[] names, Expression[] initializers, Location location)
	{
		super(location);

		mNames = names;
		mInitializers = initializers;
	}
	
	public static LocalDecl parse(inout Token* t)
	{
		return null;	
	}
}

class FuncDecl : Declaration
{
	protected Identifier[] mNames;
	protected bool mIsMethod;
	protected Identifier[] mParams;
	protected CompoundStatement mBody;

	public this(Identifier[] names, bool isMethod, Identifier[] params, CompoundStatement funcBody, Location location)
	{
		super(location);
		
		mNames = names;
		mIsMethod = isMethod;
		mParams = params;
		mBody = funcBody;
	}
}

class Identifier
{
	protected char[] mName;

	public this(char[] name)
	{
		mName = name;
	}

	public static Identifier parse(inout Token* t)
	{
		t.check(Token.Type.Ident);

		Identifier id = new Identifier(t.stringValue);
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
				ret = std.string.format("%s.%s", idents[i].toString(), ret);
				
		return ret;
	}
}

class CompoundStatement : Statement
{
	protected Statement[] mStatements;

	public this(Location location, Statement[] statements)
	{
		super(location);
		mStatements = statements;
	}
	
	public this(Location location, Statement statement)
	{
		super(location);
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
		t = t.nextToken;
		
		return new CompoundStatement(location, statements);
	}
}

class IfStatement : Statement
{
	protected Expression mCondition;
	protected Statement mIfBody;
	protected Statement mElseBody;

	public this(Location location, Expression condition, Statement ifBody, Statement elseBody)
	{
		super(location);

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

		if(t.type == Token.Type.Else)
		{
			t = t.nextToken;
			elseBody = Statement.parse(t);
		}

		return new IfStatement(location, condition, ifBody, elseBody);
	}
}

class WhileStatement : Statement
{
	protected Expression mCondition;
	protected Statement mBody;

	public this(Location location, Expression condition, Statement whileBody)
	{
		super(location);

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

		return new WhileStatement(location, condition, whileBody);
	}
}

class DoWhileStatement : Statement
{
	protected Statement mBody;
	protected Expression mCondition;

	public this(Location location, Statement doBody, Expression condition)
	{
		super(location);

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
		t = t.nextToken;

		return new DoWhileStatement(location, doBody, condition);
	}
}

class ForStatement : Statement
{
	protected Expression mInit;
	protected LocalDecl mInitDecl;
	protected Expression mCondition;
	protected Expression mIncrement;
	protected Statement mBody;

	public this(Location location, Expression init, LocalDecl initDecl, Expression condition, Expression increment, Statement forBody)
	{
		super(location);

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
				initDecl = LocalDecl.parse(t);
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

		return new ForStatement(location, init, initDecl, condition, increment, forBody);
	}
}

class ForeachStatement : Statement
{
	protected Identifier[] mIndices;
	protected Expression mContainer;
	protected Statement mBody;

	public this(Location location, Identifier[] indices, Expression container, Statement foreachBody)
	{
		super(location);

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

		Expression container = OpEqExp.parse(t);

		t.check(Token.Type.RParen);
		t = t.nextToken;
		
		Statement foreachBody = Statement.parse(t);

		return new ForeachStatement(location, indices, container, foreachBody);
	}
}

class SwitchStatement : Statement
{
	protected Expression mCondition;
	protected Statement[] mCases;
	protected Statement mDefault;

	public this(Location location, Expression condition, Statement[] cases, Statement caseDefault)
	{
		super(location);
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

		Statement[] cases = new Statement[10];
		int i = 0;

		void addCase(Statement c)
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

		Statement caseDefault;

		if(t.type == Token.Type.Default)
			caseDefault = DefaultStatement.parse(t);

		t.check(Token.Type.RBrace);
		t = t.nextToken;

		return new SwitchStatement(location, condition, cases, caseDefault);
	}
}

class CaseStatement : Statement
{
	protected Expression mCondition;
	protected Statement mBody;

	public this(Location location, Expression condition, Statement caseBody)
	{
		super(location);
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
			addCase(OpEqExp.parse(t));

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

		Statement caseBody = new CompoundStatement(location, statements);
		caseBody = new ScopeStatement(location, caseBody);

		CaseStatement ret;

		for(i = cases.length - 1; i >= 0; i--)
			ret = new CaseStatement(location, cases[i], caseBody);
		
		return ret;
	}
}

class DefaultStatement : Statement
{
	protected Statement mBody;

	public this(Location location, Statement defaultBody)
	{
		super(location);
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

		Statement defaultBody = new CompoundStatement(location, statements);
		defaultBody = new ScopeStatement(location, defaultBody);
		return new DefaultStatement(location, defaultBody);
	}
}

class ContinueStatement : Statement
{
	public this(Location location)
	{
		super(location);
	}

	public static ContinueStatement parse(inout Token* t)
	{
		Location location = t.location;
		t.check(Token.Type.Continue);
		t = t.nextToken;
		t.check(Token.Type.Semicolon);
		t = t.nextToken;
		return new ContinueStatement(location);
	}
}

class BreakStatement : Statement
{
	public this(Location location)
	{
		super(location);
	}

	public static BreakStatement parse(inout Token* t)
	{
		Location location = t.location;
		t.check(Token.Type.Break);
		t = t.nextToken;
		t.check(Token.Type.Semicolon);
		t = t.nextToken;
		return new BreakStatement(location);
	}
}

class ReturnStatement : Statement
{
	protected Expression[] mExprs;

	public this(Location location, Expression[] exprs)
	{
		super(location);
		mExprs = exprs;
	}

	public static ReturnStatement parse(inout Token* t)
	{
		Location location = t.location;
		t.check(Token.Type.Return);
		t = t.nextToken;
		
		if(t.type == Token.Type.Semicolon)
		{
			t = t.nextToken;
			return new ReturnStatement(location, null);
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
			t = t.nextToken;

			return new ReturnStatement(location, exprs);
		}
	}
}

class TryCatchStatement : Statement
{
	protected Statement mTryBody;
	protected Identifier mCatchVar;
	protected Statement mCatchBody;
	protected Statement mFinallyBody;
	
	public this(Location location, Statement tryBody, Identifier catchVar, Statement catchBody, Statement finallyBody)
	{
		super(location);
		
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
		tryBody = new ScopeStatement(tryBody.mLocation, tryBody);

		t.check(Token.Type.Catch);
		t = t.nextToken;
		t.check(Token.Type.LParen);
		t = t.nextToken;

		Identifier catchVar = Identifier.parse(t);

		t.check(Token.Type.RParen);

		Statement catchBody = CompoundStatement.parse(t);
		catchBody = new ScopeStatement(catchBody.mLocation, catchBody);

		Statement finallyBody;

		if(t.type == Token.Type.Finally)
		{
			t = t.nextToken;
			finallyBody = CompoundStatement.parse(t);
			finallyBody = new ScopeStatement(finallyBody.mLocation, finallyBody);
		}

		return new TryCatchStatement(location, tryBody, catchVar, catchBody, finallyBody);
	}
}

abstract class Expression
{
	protected Location mLocation;

	public this(Location location)
	{
		mLocation = location;
	}

	public static Expression parse(inout Token* t)
	{
		Expression exp = PrimaryExp.parse(t);
		
		if((cast(CallExp)exp) is null)
			exp = Assignment.parse(t, exp);

		t.check(Token.Type.Semicolon);
		t = t.nextToken;

		return exp;
	}
}

class Assignment : Expression
{
	protected Expression[] mLHS;
	protected Expression[] mRHS;
	
	public this(Location location, Expression[] lhs, Expression[] rhs)
	{
		super(location);
		
		mLHS = lhs;
		mRHS = rhs;
	}
	
	public static Assignment parse(inout Token* t, Expression firstLHS)
	{
		Location location = t.location;

		Expression[] lhs;
		Expression[] rhs;
		
		lhs ~= firstLHS;
		
		while(t.type == Token.Type.Comma)
		{
			t = t.nextToken;
			lhs ~= PrimaryExp.parse(t);
		}
		
		t.check(Token.Type.Assign);
		t = t.nextToken;
		
		rhs ~= OpEqExp.parse(t);
		
		while(t.type == Token.Type.Comma)
		{
			t = t.nextToken;
			rhs ~= OpEqExp.parse(t);
		}

		return new Assignment(location, lhs, rhs);
	}
}

abstract class BinaryExp : Expression
{
	protected Expression mOp1;
	protected Expression mOp2;
	
	public this(Location location, Expression left, Expression right)
	{
		super(location);
		mOp1 = left;
		mOp2 = right;
	}
}

abstract class OpEqExp : BinaryExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}

	public static Expression parse(inout Token* t)
	{
		Expression exp1;
		Expression exp2;

		exp1 = OrOrExp.parse(t);

		while(true)
		{
			Location location = t.location;

			switch(t.type)
			{
				case Token.Type.AddEq:
					t = t.nextToken;
					exp2 = OpEqExp.parse(t);
					exp1 = new AddEqExp(location, exp1, exp2);
					continue;

				case Token.Type.SubEq:
					t = t.nextToken;
					exp2 = OpEqExp.parse(t);
					exp1 = new SubEqExp(location, exp1, exp2);
					continue;
					
				case Token.Type.CatEq:
					t = t.nextToken;
					exp2 = OpEqExp.parse(t);
					exp1 = new CatEqExp(location, exp1, exp2);
					continue;

				case Token.Type.MulEq:
					t = t.nextToken;
					exp2 = OpEqExp.parse(t);
					exp1 = new MulEqExp(location, exp1, exp2);
					continue;

				case Token.Type.DivEq:
					t = t.nextToken;
					exp2 = OpEqExp.parse(t);
					exp1 = new DivEqExp(location, exp1, exp2);
					continue;

				case Token.Type.ModEq:
					t = t.nextToken;
					exp2 = OpEqExp.parse(t);
					exp1 = new ModEqExp(location, exp1, exp2);
					continue;
					
				case Token.Type.ShlEq:
					t = t.nextToken;
					exp2 = OpEqExp.parse(t);
					exp1 = new ShlEqExp(location, exp1, exp2);
					continue;
					
				case Token.Type.ShrEq:
					t = t.nextToken;
					exp2 = OpEqExp.parse(t);
					exp1 = new ShrEqExp(location, exp1, exp2);
					continue;
					
				case Token.Type.UshrEq:
					t = t.nextToken;
					exp2 = OpEqExp.parse(t);
					exp1 = new UshrEqExp(location, exp1, exp2);
					continue;
					
				case Token.Type.OrEq:
					t = t.nextToken;
					exp2 = OpEqExp.parse(t);
					exp1 = new OrEqExp(location, exp1, exp2);
					continue;
					
				case Token.Type.XorEq:
					t = t.nextToken;
					exp2 = OpEqExp.parse(t);
					exp1 = new XorEqExp(location, exp1, exp2);
					continue;
					
				case Token.Type.AndEq:
					t = t.nextToken;
					exp2 = OpEqExp.parse(t);
					exp1 = new AndEqExp(location, exp1, exp2);
					continue;

				default:
					break;
			}

			break;
		}

		return exp1;
	}
}

class AddEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class SubEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class CatEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class MulEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class DivEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class ModEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class ShlEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class ShrEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class UshrEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class OrEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class XorEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class AndEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class OrOrExp : BinaryExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
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
			exp1 = new OrOrExp(location, exp1, exp2);

			location = t.location;
		}
		
		return exp1;
	}
}

class AndAndExp : BinaryExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
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
			exp1 = new AndAndExp(location, exp1, exp2);

			location = t.location;
		}
		
		return exp1;
	}
}

class OrExp : BinaryExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
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
			exp1 = new OrExp(location, exp1, exp2);

			location = t.location;
		}
		
		return exp1;
	}
}

class XorExp : BinaryExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
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
			exp1 = new XorExp(location, exp1, exp2);

			location = t.location;
		}
		
		return exp1;
	}
}

class AndExp : BinaryExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public static Expression parse(inout Token* t)
	{
		Location location = t.location;
		
		Expression exp1;
		Expression exp2;
		
		exp1 = BaseEqualExp.parse(t);
		
		while(t.type == Token.Type.And)
		{
			t = t.nextToken;

			exp2 = BaseEqualExp.parse(t);
			exp1 = new AndExp(location, exp1, exp2);

			location = t.location;
		}
		
		return exp1;
	}
}

abstract class BaseEqualExp : BinaryExp
{
	protected bool mIsTrue;
	
	public this(bool isTrue, Location location, Expression left, Expression right)
	{
		super(location, left, right);
		
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
					exp1 = new EqualExp(isTrue, location, exp1, exp2);
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
					exp1 = new IsExp(isTrue, location, exp1, exp2);
					continue;
					
				default:
					break;
			}
			
			break;
		}
		
		return exp1;
	}
}

class EqualExp : BaseEqualExp
{
	public this(bool isTrue, Location location, Expression left, Expression right)
	{
		super(isTrue, location, left, right);
	}
}

class IsExp : BaseEqualExp
{
	public this(bool isTrue, Location location, Expression left, Expression right)
	{
		super(isTrue, location, left, right);
	}
}

class CmpExp : BinaryExp
{
	public static enum Type
	{
		Less,
		LessEq,
		Greater,
		GreaterEq
	}
	
	protected Type mType;

	public this(Token.Type type, Location location, Expression left, Expression right)
	{
		super(location, left, right);

		switch(type)
		{
			case Token.Type.LT: mType = Type.Less; break;
			case Token.Type.LE: mType = Type.LessEq; break;
			case Token.Type.GT: mType = Type.Greater; break;
			case Token.Type.GE: mType = Type.GreaterEq; break;
			default: throw new Exception("CmpExp.this() - Should never happen");
		}
	}

	public static Expression parse(inout Token* t)
	{
		Location location = t.location;
		
		Expression exp1;
		Expression exp2;
		
		exp1 = BaseShiftExp.parse(t);
		
		while(true)
		{
			Token.Type type = t.type;

			switch(type)
			{
				case Token.Type.LT, Token.Type.LE, Token.Type.GT, Token.Type.GE:
					t = t.nextToken;
					exp2 = BaseShiftExp.parse(t);
					exp1 = new CmpExp(type, location, exp1, exp2);
					continue;

				default:
					break;
			}
			
			break;
		}
		
		return exp1;
	}
}

class BaseShiftExp : BinaryExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public static Expression parse(inout Token* t)
	{
		Location location = t.location;
		
		Expression exp1;
		Expression exp2;
		
		exp1 = BaseAddExp.parse(t);
		
		while(true)
		{
			switch(t.type)
			{
				case Token.Type.Shl:
					t = t.nextToken;
					exp2 = BaseAddExp.parse(t);
					exp1 = new ShlExp(location, exp1, exp2);
					continue;
					
				case Token.Type.Shr:
					t = t.nextToken;
					exp2 = BaseAddExp.parse(t);
					exp1 = new ShrExp(location, exp1, exp2);
					continue;
					
				case Token.Type.Ushr:
					t = t.nextToken;
					exp2 = BaseAddExp.parse(t);
					exp1 = new UshrExp(location, exp1, exp2);
					continue;

				default:
					break;
			}
			
			break;
		}
		
		return exp1;
	}
}

class ShlExp : BaseShiftExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class ShrExp : BaseShiftExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class UshrExp : BaseShiftExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

abstract class BaseAddExp : BinaryExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public static Expression parse(inout Token* t)
	{
		Location location = t.location;
		
		Expression exp1;
		Expression exp2;
		
		exp1 = BaseMulExp.parse(t);
		
		while(true)
		{
			switch(t.type)
			{
				case Token.Type.Add:
					t = t.nextToken;
					exp2 = BaseMulExp.parse(t);
					exp1 = new AddExp(location, exp1, exp2);
					continue;
					
				case Token.Type.Sub:
					t = t.nextToken;
					exp2 = BaseMulExp.parse(t);
					exp1 = new SubExp(location, exp1, exp2);
					continue;
					
				case Token.Type.Cat:
					t = t.nextToken;
					exp2 = BaseMulExp.parse(t);
					exp1 = new CatExp(location, exp1, exp2);
					continue;

				default:
					break;
			}
			
			break;
		}
		
		return exp1;
	}
}

class AddExp : BaseAddExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class SubExp : BaseAddExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class CatExp : BaseAddExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

abstract class BaseMulExp : BinaryExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public static Expression parse(inout Token* t)
	{
		Location location = t.location;
		
		Expression exp1;
		Expression exp2;
		
		exp1 = UnaryExp.parse(t);

		while(true)
		{
			switch(t.type)
			{
				case Token.Type.Mul:
					t = t.nextToken;
					exp2 = UnaryExp.parse(t);
					exp1 = new MulExp(location, exp1, exp2);
					continue;
					
				case Token.Type.Div:
					t = t.nextToken;
					exp2 = UnaryExp.parse(t);
					exp1 = new DivExp(location, exp1, exp2);
					continue;
					
				case Token.Type.Mod:
					t = t.nextToken;
					exp2 = UnaryExp.parse(t);
					exp1 = new ModExp(location, exp1, exp2);
					continue;

				default:
					break;
			}
			
			break;
		}
		
		return exp1;
	}
}

class MulExp : BaseMulExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class DivExp : BaseMulExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

class ModExp : BaseMulExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
}

abstract class UnaryExp : Expression
{
	protected Expression mOp;
	
	public this(Location location, Expression operand)
	{
		super(location);
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
				exp = new AddEqExp(location, exp, new IntExp(location, 1));
				break;
				
			case Token.Type.Dec:
				t = t.nextToken;
				exp = UnaryExp.parse(t);
				exp = new SubEqExp(location, exp, new IntExp(location, 1));
				break;
				
			case Token.Type.Sub:
				t = t.nextToken;
				exp = UnaryExp.parse(t);
				exp = new NegExp(location, exp);
				break;
				
			case Token.Type.Not:
				t = t.nextToken;
				exp = UnaryExp.parse(t);
				exp = new NotExp(location, exp);
				break;
				
			case Token.Type.Cat:
				t = t.nextToken;
				exp = UnaryExp.parse(t);
				exp = new ComExp(location, exp);
				break;
				
			case Token.Type.Length:
				t = t.nextToken;
				exp = UnaryExp.parse(t);
				exp = new LengthExp(location, exp);
				break;

			default:
				exp = PrimaryExp.parse(t);
				break;
		}
		
		assert(exp !is null);

		return exp;
	}
}

class NegExp : UnaryExp
{
	public this(Location location, Expression operand)
	{
		super(location, operand);
	}
}

class NotExp : UnaryExp
{
	public this(Location location, Expression operand)
	{
		super(location, operand);
	}
}

class ComExp : UnaryExp
{
	public this(Location location, Expression operand)
	{
		super(location, operand);
	}
}

class LengthExp : UnaryExp
{
	public this(Location location, Expression operand)
	{
		super(location, operand);
	}
}

abstract class PostfixExp : UnaryExp
{
	public this(Location location, Expression operand)
	{
		super(location, operand);
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

					if(t.type != Token.Type.Ident)
						throw new MDCompileException(t.location, "Identifier expected after '.', not '%s'", t.toString());
					
					Location loc = t.location;
					exp = new DotExp(location, exp, new IdentExp(loc, Identifier.parse(t)));
					continue;
					
				case Token.Type.Colon:
					t = t.nextToken;

					if(t.type != Token.Type.Ident)
						throw new MDCompileException(t.location, "Identifier expected after ':', not '%s'", t.toString());
						
					

				case Token.Type.LParen:
					// exp = new CallExp(location, exp, parseArgumentList(t, Token.Type.RParen));
					continue;

				case Token.Type.LBracket:
					t = t.nextToken;

					Expression index = OpEqExp.parse(t);

					t.check(Token.Type.RBracket);
					t = t.nextToken;

					exp = new IndexExp(location, exp, index);
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

	public this(Location location, Expression operand, IdentExp ident)
	{
		super(location, operand);
		
		mIdent = ident;
	}
}

class CallExp : PostfixExp
{
	protected Expression[] mArgs;

	public this(Location location, Expression operand, Expression[] args)
	{
		super(location, operand);
		
		mArgs = args;
	}
}

class IndexExp : PostfixExp
{
	protected Expression mIndex;

	public this(Location location, Expression operand, Expression index)
	{
		super(location, operand);
		
		mIndex = index;
	}
}

class PrimaryExp : Expression
{
	public this(Location location)
	{
		super(location);
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
				
			case Token.Type.Dot:
				// .Identifier
				
			case Token.Type.Null:
				exp = NullExp.parse(t);
				break;
				
			case Token.Type.True, Token.Type.False:
				exp = BoolExp.parse(t);
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
				
			case Token.Type.LParen:
				t = t.nextToken;
				exp = Expression.parse(t);
				
				t.check(Token.Type.RParen);
				t = t.nextToken;
				break;
				
			case Token.Type.LBrace:
				// Table Ctor
				
			case Token.Type.LBracket:
				// Array Ctor

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
		return new IdentExp(t.location, Identifier.parse(t));
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
}

class StringExp : PrimaryExp
{
	protected char[] mValue;
	
	public this(Location location, char[] value)
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
}

class FuncLiteralExp : PrimaryExp
{
	public this(Location location)
	{
		super(location);
	}
	
	public static FuncLiteralExp parse(inout Token* t)
	{
		return new FuncLiteralExp(t.location);
	}
}

class TableCtorExp : PrimaryExp
{
	public this(Location location)
	{
		super(location);
	}
}

class ArrayCtorExp : PrimaryExp
{
	public this(Location location)
	{
		super(location);
	}
}