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
	compile(`simple.md`, f);
}

public void compile(char[] name, Stream source)
{
	auto Lexer l = new Lexer();
	Token* tokens = l.lex(name, source);
	Chunk ck = Chunk.parse(tokens);
	ck.semantic();

	//auto File o = new File(`testoutput.txt`, FileMode.OutNew);
	//CodeWriter cw = new CodeWriter(o);
	//ck.writeCode(cw);
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
			throw new MDException("%s", name, ": Source code stream is not readable");

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

class CodeWriter
{
	protected Stream mOutput;
	protected uint mTabs = 0;

	public this(Stream output)
	{
		mOutput = output;

		assert(mOutput.writeable);
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

class FuncState
{
	protected Scope mParent;
	protected Scope mScope;
	protected bool mIsVararg;
	protected FuncState[] mFuncs;

	public this(Scope parent = null)
	{
		mParent = parent;
		mScope = new Scope(this);
		
		if(parent !is null)
			parent.mParent.mFuncs ~= this;
	}
}

class Scope
{
	protected FuncState mParent;
	protected Scope mEnclosing;
	protected Statement mBreakStat;
	protected Statement mContinueStat;
	protected int[char[]] mLocalTable;
	protected char[][] mLocalNames;
	protected Location[] mLocalLocations;
	protected Scope[] mEnclosed;

	public this(FuncState parent)
	{
		mParent = parent;

		if(parent.mParent !is null)
			mEnclosing = parent.mParent;
	}

	public this(Scope enclosing)
	{
		if(enclosing !is null)
		{
			mEnclosing = enclosing;
			mParent = enclosing.mParent;
			enclosing.mEnclosed ~= this;
		}
	}

	public int searchLocal(Identifier ident, out Scope owner)
	{
		assert(ident !is null);
		
		for(Scope s = this; s !is null; s = s.mEnclosing)
		{
			int* index = (ident.mName in s.mLocalTable);

			if(index is null)
				continue;

			owner = s;
			return *index;
		}
		
		return -1;
	}
	
	public int searchLocal(Identifier ident)
	{
		Scope owner;
		return searchLocal(ident, owner);
	}
	
	public int insertLocal(Identifier ident)
	{
		int* i = (ident.mName in mLocalTable);

		if(i !is null)
			throw new MDCompileException(ident.mLocation, "Local '%s' conflicts with previous definition at %s", ident.mName, mLocalLocations[*i].toString());

		mLocalNames ~= ident.mName;
		mLocalLocations ~= ident.mLocation;
		mLocalTable[ident.mName] = mLocalNames.length - 1;

		return mLocalNames.length - 1;
	}

	public Scope push(FuncState s)
	{
		Scope sc = new Scope(s);
		s.mScope = sc;

		return sc;
	}

	public Scope push(Scope s)
	{
		return new Scope(s);
	}
	
	public Scope push()
	{
		return new Scope(this);
	}
	
	public Scope pop()
	{
		return mEnclosing;
	}
	
	/*public void showChildren(uint tab = 0)
	{
		if(mTable !is null)
		{
			foreach(Symbol s; mTable.mTable)
			{
				writefln(std.string.repeat("\t", tab), s);

				s.showChildren(tab + 1);
	
				if(cast(FuncDecl)s)
					(cast(FuncDecl)s).showOverloads(tab);
			}
		}

		if(mEnclosed.length > 0)
		{
			//writefln(std.string.repeat("\t", tab), "showing children: ", mEnclosed.length);
			foreach(Scope s; mEnclosed)
				s.showChildren(tab + 1);

			//writefln(std.string.repeat("\t", tab), "done showing children");
		}
	}*/
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
			
		t.check(Token.Type.EOF);
			
		statements.length = i;
		
		return new Chunk(statements);
	}
	
	public void semantic()
	{
		FuncState fs = new FuncState();
		
		foreach(Statement s; mStatements)
			s.semantic(fs.mScope);
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
	protected Scope mScope;

	public this(Location location)
	{
		mLocation = location;
	}
	
	public static Statement parse(inout Token* t, bool createBraceScope = true)
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
				
				if(createBraceScope)
					s = new ScopeStatement(s.mLocation, s);
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
				
			case Token.Type.Throw:
				return ThrowStatement.parse(t);
				
			case Token.Type.Semicolon:
				throw new MDCompileException(t.location, "Empty statements ( ';' ) are not allowed");
				
			default:
				throw new MDCompileException(t.location, "Statement expected, not '%s'", t.toString());
		}
	}
	
	public void semantic(Scope s)
	{
		assert(false, "no semantic routine");
	}
	
	public void writeCode(CodeWriter cw)
	{
		cw.write("<unimplemented>");
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
	
	public override void semantic(Scope s)
	{
		mScope = s.push();
		mStatement.semantic(mScope);
		mScope.pop();
	}
	
	public void writeCode(CodeWriter cw)
	{
		mStatement.writeCode(cw);
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
		Location location = t.location;
		Expression exp = Expression.parse(t);

		t.check(Token.Type.Semicolon);
		t = t.nextToken;
		
		return new ExpressionStatement(location, exp);
	}
	
	public override void semantic(Scope s)
	{

	}
	
	public void writeCode(CodeWriter cw)
	{
		mExpr.writeCode(cw);
		cw.write(";");
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
	
	public override void semantic(Scope s)
	{
		mDecl.semantic(s);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mDecl.writeCode(cw);

		if(cast(LocalDecl)mDecl)
			cw.write(";");
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
				return LocalFuncDecl.parse(t);
			else if(t.type == Token.Type.Ident)
			{
				scope(success)
				{
					t.check(Token.Type.Semicolon);
					t = t.nextToken;
				}
				return LocalDecl.parse(t);
			}
			else
				throw new MDCompileException(location, "'function' or identifier expected after 'local'");
		}
		else if(t.type == Token.Type.Function)
			return FuncDecl.parse(t);
		else
			throw new MDCompileException(location, "Declaration expected");
	}
	
	public void semantic(Scope s)
	{
		assert(false, "no semantic routine");
	}
	
	public void writeCode(CodeWriter cw)
	{
		cw.write("<unimplemented>");
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
		// Special: starts on the first identifier
		Location location = t.location;
		
		Identifier[] names;
		names ~= Identifier.parse(t);

		while(t.type == Token.Type.Comma)
		{
			t = t.nextToken;
			names ~= Identifier.parse(t);
		}

		Expression[] initializers;

		if(t.type == Token.Type.Assign)
		{
			t = t.nextToken;

			initializers ~= OpEqExp.parse(t);
			
			while(t.type == Token.Type.Comma)
			{
				t = t.nextToken;
				initializers ~= OpEqExp.parse(t);
			}
		}

		return new LocalDecl(names, initializers, location);
	}
	
	public override void semantic(Scope s)
	{
		foreach(Identifier n; mNames)
			s.insertLocal(n);
	}

	public void writeCode(CodeWriter cw)
	{
		cw.write("local ");

		foreach(uint i, Identifier n; mNames)
		{
			n.writeCode(cw);
			
			if(i != mNames.length - 1)
				cw.write(", ");
		}
		
		cw.write(" = ");
		
		foreach(uint i, Expression e; mInitializers)
		{
			e.writeCode(cw);
			
			if(i != mInitializers.length - 1)
				cw.write(", ");
		}
	}
}

class LocalFuncDecl : Declaration
{
	protected Identifier mName;
	protected Identifier[] mParams;
	protected bool mIsVararg;
	protected CompoundStatement mBody;
	
	public this(Identifier name, Identifier[] params, bool isVararg, CompoundStatement funcBody, Location location)
	{
		super(location);

		mName = name;
		mParams = params;
		mIsVararg = isVararg;
		mBody = funcBody;
	}
	
	public static LocalFuncDecl parse(inout Token* t)
	{
		// Special: starts on the "function" token
		
		Location location = t.location;
		
		t.check(Token.Type.Function);
		t = t.nextToken;
		
		Identifier name = Identifier.parse(t);
		
		t.check(Token.Type.LParen);
		t = t.nextToken;
		
		Identifier[] params;
		bool isVararg = false;

		if(t.type == Token.Type.Vararg)
		{
			isVararg = true;
			t = t.nextToken;
		}
		else if(t.type != Token.Type.RParen)
		{
			while(true)
			{
				params ~= Identifier.parse(t);
				
				if(t.type == Token.Type.RParen)
					break;
				else if(t.type == Token.Type.Vararg)
				{
					isVararg = true;
					break;
				}
					
				t.check(Token.Type.Comma);
				t = t.nextToken;
			}
		}

		t.check(Token.Type.RParen);
		t = t.nextToken;
		
		CompoundStatement funcBody = CompoundStatement.parse(t);
		
		return new LocalFuncDecl(name, params, isVararg, funcBody, location);
	}
	
	public override void semantic(Scope s)
	{
		s.insertLocal(mName);

		FuncState fs = new FuncState(s);
		s = fs.mScope;
		
		foreach(Identifier p; mParams)
			s.insertLocal(p);
			
		mBody.semantic(s);
	}

	public void writeCode(CodeWriter cw)
	{
		cw.write("local function ");
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
		
		mBody.writeCode(cw);
	}
}

class FuncDecl : Declaration
{
	protected Identifier[] mNames;
	protected bool mIsMethod;
	protected bool mIsVararg;
	protected Identifier[] mParams;
	protected CompoundStatement mBody;

	public this(Identifier[] names, bool isMethod, bool isVararg, Identifier[] params, CompoundStatement funcBody, Location location)
	{
		super(location);
		
		mNames = names;
		mIsMethod = isMethod;
		mIsVararg = isVararg;
		mParams = params;
		mBody = funcBody;
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
		
		bool isMethod = (t.type == Token.Type.Colon);
		
		if(t.type == Token.Type.Colon)
		{
			t = t.nextToken;
			names ~= Identifier.parse(t);
		}
		
		t.check(Token.Type.LParen);
		t = t.nextToken;

		Identifier[] params;
		bool isVararg = false;

		if(t.type == Token.Type.Vararg)
		{
			isVararg = true;
			t = t.nextToken;
		}
		else if(t.type != Token.Type.RParen)
		{
			while(true)
			{
				params ~= Identifier.parse(t);
				
				if(t.type == Token.Type.RParen)
					break;
				else if(t.type == Token.Type.Vararg)
				{
					isVararg = true;
					break;
				}
					
				t.check(Token.Type.Comma);
				t = t.nextToken;
			}
		}

		t.check(Token.Type.RParen);
		t = t.nextToken;
		
		CompoundStatement funcBody = CompoundStatement.parse(t);
		
		return new FuncDecl(names, isMethod, isVararg, params, funcBody, location);
	}

	public override void semantic(Scope s)
	{
		FuncState fs = new FuncState(s);
		s = fs.mScope;

		foreach(Identifier p; mParams)
			s.insertLocal(p);
			
		mBody.semantic(s);
	}

	public void writeCode(CodeWriter cw)
	{
		cw.write("function ");

		foreach(uint i, Identifier n; mNames[0 .. $ - 1])
		{
			n.writeCode(cw);

			if(i != mNames.length - 2)
				cw.write(".");
		}

		if(mIsMethod)
			cw.write(":");
		else if(mNames.length > 1)
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
		
		mBody.writeCode(cw);
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
				ret = std.string.format("%s.%s", idents[i].toString(), ret);
				
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
	
	public override void semantic(Scope s)
	{
		foreach(Statement st; mStatements)
			st.semantic(s);
	}
	
	public void writeCode(CodeWriter cw)
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
	
	public override void semantic(Scope s)
	{
		//mCondition.semantic(s);
		s = s.push();
		mIfBody.semantic(s);
		s = s.pop();
		
		if(mElseBody)
		{
			s = s.push();
			mElseBody.semantic(s);
			s = s.pop();
		}
	}
	
	public void writeCode(CodeWriter cw)
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
	
	public override void semantic(Scope s)
	{
		s = s.push();
		s.mBreakStat = this;
		s.mContinueStat = this;
		mBody.semantic(s);
		s.pop();
	}
	
	public void writeCode(CodeWriter cw)
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
	
	public override void semantic(Scope s)
	{
		s = s.push();
		s.mBreakStat = this;
		s.mContinueStat = this;
		mBody.semantic(s);
		//mCondition.semantic(s);
		s.pop();
	}

	public void writeCode(CodeWriter cw)
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

		return new ForStatement(location, init, initDecl, condition, increment, forBody);
	}
	
	public override void semantic(Scope s)
	{
		s = s.push();
		s.mBreakStat = this;
		s.mContinueStat = this;
		
		if(mInitDecl)
			mInitDecl.semantic(s);

		//mCondition && mCondition.semantic(s);
		//mIncrement && mIncrement.semantic(s);
		
		mBody.semantic(s);

		s.pop();
	}
	
	public void writeCode(CodeWriter cw)
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

	public this(Location location, Identifier[] indices, Expression[] container, Statement foreachBody)
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

		Expression[] container;
		container ~= OpEqExp.parse(t);
		
		while(t.type == Token.Type.Comma)
		{
			t = t.nextToken;
			container ~= OpEqExp.parse(t);
		}

		t.check(Token.Type.RParen);
		t = t.nextToken;
		
		Statement foreachBody = Statement.parse(t);

		return new ForeachStatement(location, indices, container, foreachBody);
	}
	
	public override void semantic(Scope s)
	{
		s = s.push();
		s.mBreakStat = this;
		s.mContinueStat = this;
		
		foreach(Identifier i; mIndices)
			s.insertLocal(i);
			
		//foreach(Expression c; mContainer) c.semantic(s);
		
		mBody.semantic(s);

		s.pop();
	}
	
	public void writeCode(CodeWriter cw)
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
	
	public override void semantic(Scope s)
	{
		s = s.push();
		s.mBreakStat = this;

		foreach(Statement c; mCases)
			c.semantic(s);
			
		if(mDefault)
			mDefault.semantic(s);
			
		s.pop();
	}
	
	public void writeCode(CodeWriter cw)
	{
		cw.write("switch(");
		mCondition.writeCode(cw);
		cw.write("){");
		
		foreach(Statement c; mCases)
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
	
	public override void semantic(Scope s)
	{
		mBody.semantic(s);
	}
	
	public void writeCode(CodeWriter cw)
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
	
	public override void semantic(Scope s)
	{
		mBody.semantic(s);
	}
	
	public void writeCode(CodeWriter cw)
	{
		cw.write("default:");
		mBody.writeCode(cw);
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
	
	public override void semantic(Scope s)
	{

	}
	
	public void writeCode(CodeWriter cw)
	{
		cw.write("continue;");
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
	
	public override void semantic(Scope s)
	{
		
	}

	public void writeCode(CodeWriter cw)
	{
		cw.write("break;");
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
	
	public override void semantic(Scope s)
	{
		
	}
	
	public void writeCode(CodeWriter cw)
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
		
		Identifier catchVar;
		Statement catchBody;

		if(t.type == Token.Type.Catch)
		{
			t = t.nextToken;
			t.check(Token.Type.LParen);
			t = t.nextToken;

			catchVar = Identifier.parse(t);

			t.check(Token.Type.RParen);
			t = t.nextToken;

			catchBody = CompoundStatement.parse(t);
			catchBody = new ScopeStatement(catchBody.mLocation, catchBody);
		}

		Statement finallyBody;

		if(t.type == Token.Type.Finally)
		{
			t = t.nextToken;
			finallyBody = CompoundStatement.parse(t);
			finallyBody = new ScopeStatement(finallyBody.mLocation, finallyBody);
		}
		
		if(catchBody is null && finallyBody is null)
			throw new MDCompileException(location, "Try statement must be followed by a catch, finally, or both");

		return new TryCatchStatement(location, tryBody, catchVar, catchBody, finallyBody);
	}
	
	public override void semantic(Scope s)
	{
		mTryBody.semantic(s);

		if(mCatchBody)
		{
			s = s.push();
			s.insertLocal(mCatchVar);
			mCatchBody.semantic(s);
			s = s.pop();
		}

		if(mFinallyBody)
			mFinallyBody.semantic(s);
	}
	
	public void writeCode(CodeWriter cw)
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
	
	public this(Location location, Expression exp)
	{
		super(location);
		
		mExp = exp;
	}
	
	public static ThrowStatement parse(inout Token* t)
	{
		Location location = t.location;
		
		t.check(Token.Type.Throw);
		t = t.nextToken;
		
		Expression exp = OpEqExp.parse(t);
		
		t.check(Token.Type.Semicolon);
		t = t.nextToken;

		return new ThrowStatement(location, exp);
	}
	
	public override void semantic(Scope s)
	{
		
	}
	
	public void writeCode(CodeWriter cw)
	{
		cw.write("throw ");
		mExp.writeCode(cw);
		cw.write(";");
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
	
	public void writeCode(CodeWriter cw)
	{
		cw.write("<unimplemented>");
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
	
	public void writeCode(CodeWriter cw)
	{
		foreach(uint i, Expression e; mLHS)
		{
			e.writeCode(cw);
			
			if(i != mLHS.length - 1)
				cw.write(", ");
		}
		
		cw.write(" = ");
		
		foreach(uint i, Expression e; mRHS)
		{
			e.writeCode(cw);
			
			if(i != mRHS.length - 1)
				cw.write(", ");
		}
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

	public static Expression parse(inout Token* t, Expression exp1 = null)
	{
		if(exp1 is null)
			exp1 = OrOrExp.parse(t);

		Expression exp2;

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
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" += ");
		mOp2.writeCode(cw);
	}
}

class SubEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" -= ");
		mOp2.writeCode(cw);
	}
}

class CatEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" ~= ");
		mOp2.writeCode(cw);
	}
}

class MulEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" *= ");
		mOp2.writeCode(cw);
	}
}

class DivEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" /= ");
		mOp2.writeCode(cw);
	}
}

class ModEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" %= ");
		mOp2.writeCode(cw);
	}
}

class ShlEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" <<= ");
		mOp2.writeCode(cw);
	}
}

class ShrEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" >>= ");
		mOp2.writeCode(cw);
	}
}

class UshrEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" >>>= ");
		mOp2.writeCode(cw);
	}
}

class OrEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" |= ");
		mOp2.writeCode(cw);
	}
}

class XorEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" ^= ");
		mOp2.writeCode(cw);
	}
}

class AndEqExp : OpEqExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}

	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" &= ");
		mOp2.writeCode(cw);
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
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" || ");
		mOp2.writeCode(cw);
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
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" && ");
		mOp2.writeCode(cw);
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
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" | ");
		mOp2.writeCode(cw);
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
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" ^ ");
		mOp2.writeCode(cw);
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
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" & ");
		mOp2.writeCode(cw);
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
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		
		if(mIsTrue)
			cw.write(" == ");
		else
			cw.write(" != ");

		mOp2.writeCode(cw);
	}
}

class IsExp : BaseEqualExp
{
	public this(bool isTrue, Location location, Expression left, Expression right)
	{
		super(isTrue, location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		
		if(mIsTrue)
			cw.write(" is ");
		else
			cw.write(" !is ");

		mOp2.writeCode(cw);
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
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		
		switch(mType)
		{
			case Type.Less:			cw.write(" < "); break;
			case Type.Greater:		cw.write(" > "); break;
			case Type.LessEq:		cw.write(" <= "); break;
			case Type.GreaterEq:	cw.write(" >= "); break;
		}

		mOp2.writeCode(cw);
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

	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" << ");
		mOp2.writeCode(cw);
	}
}

class ShrExp : BaseShiftExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" >> ");
		mOp2.writeCode(cw);
	}
}

class UshrExp : BaseShiftExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" >>> ");
		mOp2.writeCode(cw);
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
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" + ");
		mOp2.writeCode(cw);
	}
}

class SubExp : BaseAddExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" - ");
		mOp2.writeCode(cw);
	}
}

class CatExp : BaseAddExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" ~ ");
		mOp2.writeCode(cw);
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
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" * ");
		mOp2.writeCode(cw);
	}
}

class DivExp : BaseMulExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" / ");
		mOp2.writeCode(cw);
	}
}

class ModExp : BaseMulExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public void writeCode(CodeWriter cw)
	{
		mOp1.writeCode(cw);
		cw.write(" % ");
		mOp2.writeCode(cw);
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
	
	public void writeCode(CodeWriter cw)
	{
		cw.write("-");
		mOp.writeCode(cw);
	}
}

class NotExp : UnaryExp
{
	public this(Location location, Expression operand)
	{
		super(location, operand);
	}
	
	public void writeCode(CodeWriter cw)
	{
		cw.write("!");
		mOp.writeCode(cw);
	}
}

class ComExp : UnaryExp
{
	public this(Location location, Expression operand)
	{
		super(location, operand);
	}
	
	public void writeCode(CodeWriter cw)
	{
		cw.write("~");
		mOp.writeCode(cw);
	}
}

class LengthExp : UnaryExp
{
	public this(Location location, Expression operand)
	{
		super(location, operand);
	}
	
	public void writeCode(CodeWriter cw)
	{
		cw.write("#");
		mOp.writeCode(cw);
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
			
			Identifier methodName;
			
			switch(t.type)
			{
				case Token.Type.Dot:
					t = t.nextToken;

					t.check(Token.Type.Ident);
					
					Location loc = t.location;
					exp = new DotExp(location, exp, new IdentExp(loc, Identifier.parse(t)));
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
					t = t.nextToken;

					exp = new CallExp(location, exp, args, methodName);
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
	
	public void writeCode(CodeWriter cw)
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

	public this(Location location, Expression operand, Expression[] args, Identifier methodName)
	{
		super(location, operand);
		
		mArgs = args;
		mMethodName = methodName;
	}
	
	public void writeCode(CodeWriter cw)
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

	public this(Location location, Expression operand, Expression index)
	{
		super(location, operand);
		
		mIndex = index;
	}
	
	public void writeCode(CodeWriter cw)
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
	
	public void writeCode(CodeWriter cw)
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
	
	public void writeCode(CodeWriter cw)
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
	
	public void writeCode(CodeWriter cw)
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
	
	public void writeCode(CodeWriter cw)
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
	
	public void writeCode(CodeWriter cw)
	{
		cw.write(std.string.toString(mValue));
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
	
	public void writeCode(CodeWriter cw)
	{
		cw.write(std.string.toString(mValue));
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
	
	public void writeCode(CodeWriter cw)
	{
		// Need to escape string
		
		cw.write("\"");
		cw.write(mValue);
		cw.write("\"");
	}
}

class FuncLiteralExp : PrimaryExp
{
	protected Identifier[] mParams;
	protected Statement mBody;

	public this(Location location, Identifier[] params, Statement funcBody)
	{
		super(location);
		
		mParams = params;
		mBody = funcBody;
	}
	
	public static FuncLiteralExp parse(inout Token* t)
	{
		Location location = t.location;
		
		t.check(Token.Type.Function);
		t = t.nextToken;
		t.check(Token.Type.LParen);
		t = t.nextToken;
		
		Identifier[] params;
		
		if(t.type != Token.Type.RParen)
		{
			while(true)
			{
				params ~= Identifier.parse(t);
				
				if(t.type == Token.Type.RParen)
					break;
					
				t.check(Token.Type.Comma);
				t = t.nextToken;
			}
		}

		t.check(Token.Type.RParen);
		t = t.nextToken;
		
		Statement funcBody = CompoundStatement.parse(t);

		return new FuncLiteralExp(t.location, params, funcBody);
	}
	
	public void writeCode(CodeWriter cw)
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

class TableCtorExp : PrimaryExp
{
	protected Expression[2][] mFields;

	public this(Location location, Expression[2][] fields)
	{
		super(location);
		
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

			void parseField()
			{
				Expression k;
				Expression v;

				if(t.type == Token.Type.LParen)
				{
					t = t.nextToken;
					k = OpEqExp.parse(t);
					
					t.check(Token.Type.RParen);
					t = t.nextToken;
					t.check(Token.Type.Assign);
					t = t.nextToken;
					
					v = OpEqExp.parse(t);
				}
				else
				{
					if(t.type == Token.Type.Function)
					{
						// Take advantage of the fact that LocalFuncDecl.parse() starts on the 'function' token
						auto LocalFuncDecl fd = LocalFuncDecl.parse(t);
						k = new StringExp(fd.mLocation, fd.mName.mName);
						v = new FuncLiteralExp(fd.mLocation, fd.mParams, fd.mBody);
					}
					else
					{
						Expression exp = OpEqExp.parse(t);
						IdentExp id = cast(IdentExp)exp;
	
						if(id !is null)
						{
							k = new StringExp(id.mLocation, id.mIdent.mName);
							
							t.check(Token.Type.Assign);
							t = t.nextToken;
							v = OpEqExp.parse(t);
						}
						else
						{
							k = new IntExp(exp.mLocation, index);
							index++;
							
							v = exp;
						}
					}
				}
				
				addPair(k, v);
			}

			parseField();
			
			while(t.type != Token.Type.RBrace)
			{
				if(t.type == Token.Type.Comma)
					t = t.nextToken;

				parseField();
			}
		}
		
		fields.length = i;

		t.check(Token.Type.RBrace);
		t = t.nextToken;
		
		return new TableCtorExp(location, fields);
	}
	
	public void writeCode(CodeWriter cw)
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

	public this(Location location, Expression[] fields)
	{
		super(location);

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
	
	public void writeCode(CodeWriter cw)
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