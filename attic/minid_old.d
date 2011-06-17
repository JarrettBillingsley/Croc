module minid;

import std.c.stdlib;
import std.conv;
import std.perf;
import std.stdio;
import std.stream;
import std.string;
import std.utf;

/*
Calling a closure (of any type):
	ocall ox, 0

Calling methods with "this":
	ocall ox, index
	
Downcalling dynamic closures:
	ecall index

Calling static functions / Sidecalling dynamic closures:
	rcall index

Referencing static functions / Sidereferencing dynamic closures:
	rfuncref index

Downreferencing dynamic closures:
	efuncref index

Downclosing a function:
	eclose index

Sideclosing a function
	rclose index

Closing/referencing methods with "this" (delegation):
	oclose ox, index

Create closures at a static function level.
*/

/*
the minid module:

class Object
{
	int opCmp(Object other);
	bool opEquals(Object other);
	int getHash();
	char[] toString();
}

// Cut down on duplication of effort with RTTI!
// But that involves either subverting the typesafe compiler or adding in a new "feature" to allow an "any" type.
// How about instead of converting arrays to __Arrays right away, save that for the codegen, or somewhere between
// semantic and codegen?  That would work.

class __Array : Object
{
	this(TypeInfo ti, int length);

	int opCmp(__Array other);
	bool opEquals(__Array other);
	int getHash();
	char[] toString();

	// These return an "int", but the return type is really dictated by the compiler.
	int opIndex(int index);

	// These all take "ints", but again, it's type-dependent.
	int opIndexAssign(int value, int index);

	__Array opSlice();
	__Array opSlice(int lo, int hi);
	__Array opSliceAssign(int value);
	__Array opSliceAssign(int value, int lo, int hi);
	__IntArray dup();
	void sort();
	void reverse();
	
	namespace length
	{
		int opGet();
		int opSet(int l);
	}
	
	__IntArray opCat(__IntArray other);
	__IntArray opCatEq(__IntArray other);
}
*/

void main()
{
	BufferedFile f = new BufferedFile(`testscript.txt`, FileMode.In);

	auto Compiler c = new Compiler();

	c.compile(`testscript.txt`, f);
	
	f.close();
	delete f;
}

class Compiler
{
	public this()
	{

	}

	public void compile(char[] name, Stream source)
	{
		auto Lexer l = new Lexer();
		auto HighPerformanceCounter hpc = new HighPerformanceCounter();
		hpc.start();
		Token* tokens = l.lex(name, source);
		Module m = Module.parse(tokens);
		m.semantic();
		hpc.stop();
		writefln("Took ", hpc.microseconds() / 1000.0, "ms\n");
		m.showChildren();
		//writefln(m);
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

struct Token
{
	public static enum Type
	{
		Assert,
		Bool,
		Break,
		Case,
		Cast,
		Char,
		Class,
		Closure,
		Continue,
		Def,
		Default,
		Delete,
		Do,
		Else,
		False,
		Float,
		For,
		Foreach,
		Function,
		If,
		Import,
		Int,
		Main,
		Module,
		Namespace,
		New,
		Null,
		Return,
		Super,
		Switch,
		This,
		True,
		Vararg,
		Void,
		While,

		Add,
		AddEq,
		Sub,
		SubEq,
		Mul,
		MulEq,
		Div,
		DivEq,
		Mod,
		ModEq,
		Pow,
		PowEq,
		Cat,
		CatEq,
		Assign,

		AndAnd,
		OrOr,

		Inc,
		Dec,

		LT,
		LE,
		GT,
		GE,
		EQ,
		NE,
		Is,

		Not,

		LParen,
		RParen,
		LBracket,
		RBracket,
		LBrace,
		RBrace,

		Colon,
		Comma,
		Semicolon,

		Dot,
		DotDot,

		Ident,
		BoolLiteral,
		StringLiteral,
		CharLiteral,
		IntLiteral,
		FloatLiteral,
		EOF
	}

	public static const char[][] tokenStrings =
	[
		"assert",
		"bool",
		"break",
		"case",
		"cast",
		"char",
		"class",
		"closure",
		"continue",
		"def",
		"default",
		"delete",
		"do",
		"else",
		"false",
		"float",
		"for",
		"foreach",
		"function",
		"if",
		"import",
		"int",
		"main",
		"module",
		"namespace"
		"new",
		"null",
		"return",
		"super",
		"switch",
		"this",
		"true",
		"vararg",
		"void",
		"while",

		"+",
		"+=",
		"-",
		"-=",
		"*",
		"*=",
		"/",
		"/=",
		"%",
		"%=",
		"^",
		"^=",
		"~",
		"~=",
		"=",

		"&&",
		"||",

		"++",
		"--",

		"<",
		"<=",
		">",
		">=",
		"==",
		"!=",
		"is",

		"!",

		"(",
		")",
		"[",
		"]",
		"{",
		"}",

		":",
		",",
		";",

		".",
		"..",
		
		"Identifier",
		"Bool Literal",
		"String Literal",
		"Char Literal",
		"Int Literal",
		"Float Literal",
		"<EOF>"
	];
	
	public static Type[char[]] stringToType;
	
	static this()
	{
		stringToType["assert"] = Type.Assert;
		stringToType["bool"] = Type.Bool;
		stringToType["break"] = Type.Break;
		stringToType["case"] = Type.Case;
		stringToType["cast"] = Type.Cast;
		stringToType["char"] = Type.Char;
		stringToType["class"] = Type.Class;
		stringToType["closure"] = Type.Closure;
		stringToType["continue"] = Type.Continue;
		stringToType["def"] = Type.Def;
		stringToType["default"] = Type.Default;
		stringToType["delete"] = Type.Delete;
		stringToType["do"] = Type.Do;
		stringToType["else"] = Type.Else;
		stringToType["false"] = Type.False;
		stringToType["float"] = Type.Float;
		stringToType["for"] = Type.For;
		stringToType["foreach"] = Type.Foreach;
		stringToType["function"] = Type.Function;
		stringToType["if"] = Type.If;
		stringToType["is"] = Type.Is;
		stringToType["import"] = Type.Import;
		stringToType["int"] = Type.Int;
		stringToType["main"] = Type.Main;
		stringToType["module"] = Type.Module;
		stringToType["namespace"] = Type.Namespace;
		stringToType["new"] = Type.New;
		stringToType["null"] = Type.Null;
		stringToType["return"] = Type.Return;
		stringToType["super"] = Type.Super;
		stringToType["switch"] = Type.Switch;
		stringToType["this"] = Type.This;
		stringToType["true"] = Type.True;
		stringToType["vararg"] = Type.Vararg;
		stringToType["void"] = Type.Void;
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

		stringToType.rehash;
	}
	
	public char[] toString()
	{
		char[] ret;

		switch(type)
		{
			case Type.Ident:
				ret ~= "Ident: " ~ stringValue;
				break;
				
			case Type.BoolLiteral:
				ret ~= (boolValue ? "true" : "false");

			case Type.StringLiteral:
				ret ~= '"' ~ stringValue ~ '"';
				break;
				
			case Type.CharLiteral:
				ret ~= "'" ~ stringValue ~ "'";

			case Type.IntLiteral:
				ret ~= "Int: " ~ std.string.toString(intValue);
				break;

			case Type.FloatLiteral:
				ret ~= "Float: " ~ std.string.toString(floatValue);
				break;

			default:
				ret ~= tokenStrings[cast(uint)type];
				break;
		}
		
		return ret;
	}
	
	public static char[] toString(Type type)
	{
		return tokenStrings[type];
	}
	
	public void check(Type t)
	{
		if(type != t)
			throw new MDCompileException("'" ~ tokenStrings[t] ~ "' expected; found '" ~ tokenStrings[type] ~ "' instead", location);
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
		return fileName ~ "(" ~ .toString(line) ~ ":" ~ .toString(column) ~ ")";
	}
}

class MDException : Exception
{
	public this(char[] msg)
	{
		super(msg);
	}
}

class MDCompileException : MDException
{
	public this(char[] msg, Location loc)
	{
		super(loc.toString() ~ ": " ~ msg);
	}
}

class MDSymbolConflictException : MDCompileException
{
	public this(Symbol sym1, Symbol sym2)
	{
		super("'" ~ sym1.toPrettyString() ~ "' conflicts with '" ~ sym2.toPrettyString() ~ "'(" ~ sym2.mLocation.toString() ~ ")", sym1.mLocation);
	}
}

class MDShadowingException : MDCompileException
{
	public this(Symbol sym1, Symbol sym2)
	{
		super("'" ~ sym1.toPrettyString() ~ "' shadows '" ~ sym2.toPrettyString() ~ "'(" ~ sym2.mLocation.toString() ~ ")", sym1.mLocation);	
	}
}

class MDTypeConvException : MDCompileException
{
	public this(Expression from, Expression to)
	{
		super("Cannot implicitly convert expression '" ~ from.toString() ~ "' of type '" ~ from.mSemType.toString() ~ "' to type '" ~ to.mSemType.toString() ~ "'", from.mLocation);
	}
}

class Lexer
{
	protected Stream mSource;
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

		mSource = source;

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
							throw new MDCompileException("Binary digit expected, not '" ~ mCharacter ~ "'", mLoc);

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
							throw new MDCompileException("Malformed binary int literal", beginning);
						}
						
						return true;

					case 'c':
						nextChar();
						
						if(!isOctalDigit(mCharacter))
							throw new MDCompileException("Octal digit expected, not '" ~ mCharacter ~ "'", mLoc);

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
							throw new MDCompileException("Malformed octal int literal", beginning);
						}
						
						return true;

					case 'x':
						nextChar();
						
						if(!isHexDigit(mCharacter))
							throw new MDCompileException("Hexadecimal digit expected, not '" ~ mCharacter ~ "'", mLoc);

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
							throw new MDCompileException("Malformed hexadecimal int literal", beginning);
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
					throw new MDCompileException("Exponent value expected in float literal", mLoc);

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
				throw new MDCompileException("Malformed int literal '" ~ buf[0 .. i] ~ "'", beginning);
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
				throw new MDCompileException("Malformed float literal '" ~ buf[0 .. i] ~ "'", beginning);
			}

			return false;
		}
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
			switch(mCharacter)
			{
				int c;

				case char.init, '\0':
					throw new MDCompileException("Unterminated string literal", beginning);
					
				case '\r', '\n':
					add('\n');
					nextLine();

				case '\\':
					if(escape == false)
						goto default;

					nextChar();

					switch(mCharacter)
					{
						case 'a': c = '\a'; break;
						case 'b': c = '\b'; break;
						case 'f': c = '\f'; break;
						case 'n': c = '\n'; break;
						case 'r': c = '\r'; break;
						case 't': c = '\t'; break;
						case 'v': c = '\v'; break;

						case char.init, '\0':
							// will raise an error next loop
							continue;
							
						case '\\', '\"', '\'':
							add(mCharacter);
							nextChar();
							continue;

						default:
							if(!isDecimalDigit(mCharacter))
								throw new MDCompileException("Invalid string escape sequence '\\" ~ mCharacter ~ "'", mLoc);

							// Decimal char
							int numch = 0;
							c = 0;

							do
							{
								c = 10 * c + (mCharacter - '0');
								nextChar();
							} while(++numch < 3 && isDecimalDigit(mCharacter));

							if(c > 127)
								throw new MDCompileException("Numeric escape sequence too large", mLoc);

							add(cast(char)c);

							continue;
					}

					add(cast(char)c);
					nextChar();
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

		nextChar();
		
		char c;

		switch(mCharacter)
		{
			case char.init, '\0':
				throw new MDCompileException("Unterminated character literal", beginning);

			case '\\':
				nextChar();

				switch(mCharacter)
				{
					case 'a': c = '\a'; nextChar(); break;
					case 'b': c = '\b'; nextChar(); break;
					case 'f': c = '\f'; nextChar(); break;
					case 'n': c = '\n'; nextChar(); break;
					case 'r': c = '\r'; nextChar(); break;
					case 't': c = '\t'; nextChar(); break;
					case 'v': c = '\v'; nextChar(); break;

					case char.init, '\0':
						throw new MDCompileException("Unterminated character literal", beginning);

					case '\\', '\"', '\'':
						c = mCharacter;
						nextChar();
						break;

					default:
						if(!isDecimalDigit(mCharacter))
							throw new MDCompileException("Invalid escape sequence '\\" ~ mCharacter ~ "'", mLoc);

						// Decimal char
						int numch = 0;
						c = 0;

						do
						{
							c = 10 * c + (mCharacter - '0');
							nextChar();
						} while(++numch < 3 && isDecimalDigit(mCharacter));

						if(c > 127)
							throw new MDCompileException("Numeric escape sequence too large", mLoc);
						break;
				}
				break;

			default:
				c = mCharacter;
				nextChar();
				break;
		}
		
		if(mCharacter != '\'')
			throw new MDCompileException("Unterminated character literal", mLoc);
			
		char[] ret;
		ret ~= c;
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

				case '=':
					nextChar();

					if(mCharacter != '=')
						token.type = Token.Type.Assign;
					else
					{
						nextChar();
						token.type = Token.Type.EQ;
					}
					
					return token;
					
				case '<':
					nextChar();

					if(mCharacter != '=')
						token.type = Token.Type.LT;
					else
					{
						nextChar();
						token.type = Token.Type.LE;
					}
					
					return token;
					
				case '>':
					nextChar();

					if(mCharacter != '=')
						token.type = Token.Type.GT;
					else
					{
						nextChar();
						token.type = Token.Type.GE;
					}
					
					return token;
					
				case '!':
					nextChar();

					if(mCharacter != '=')
						token.type = Token.Type.Not;
					else
					{
						nextChar();
						token.type = Token.Type.NE;
					}

					return token;
					
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
					
				case '*':
					nextChar();

					if(mCharacter != '=')
						token.type = Token.Type.Mul;
					else
					{
						nextChar();
						token.type = Token.Type.MulEq;
					}
					
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
									throw new MDCompileException("Unterminated /* */ comment", tokenLoc);

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

					if(mCharacter != '=')
						token.type = Token.Type.Mod;
					else
					{
						nextChar();
						token.type = Token.Type.ModEq;
					}
					
					return token;
					
				case '^':
					nextChar();

					if(mCharacter != '=')
						token.type = Token.Type.Pow;
					else
					{
						nextChar();
						token.type = Token.Type.PowEq;
					}
					
					return token;
					
				case '~':
					nextChar();

					if(mCharacter != '=')
						token.type = Token.Type.Cat;
					else
					{
						nextChar();
						token.type = Token.Type.CatEq;
					}
					
					return token;
					
				case '.':
					nextChar();
					
					if(mCharacter == '.')
					{
						nextChar();
						
						token.type = Token.Type.DotDot;
						return token;
					}
					else if(isDecimalDigit(mCharacter))
					{
						int dummy;
						assert(readNumLiteral(true, token.floatValue, dummy) == false);
						token.type = Token.Type.FloatLiteral;
						return token;
					}
					else
					{
						token.type = Token.Type.Dot;
						return token;
					}
					
				case '&':
					nextChar();
					
					if(mCharacter != '&')
						throw new MDCompileException("Token '&&' expected", tokenLoc);
						
					nextChar();
					
					token.type = Token.Type.AndAnd;
					return token;
					
				case '|':
					nextChar();

					if(mCharacter != '|')
						throw new MDCompileException("Token '||' expected", tokenLoc);
						
					nextChar();
					
					token.type = Token.Type.OrOr;
					return token;
					
				case '\"':
					token.stringValue = readStringLiteral(true);
					token.type = Token.Type.StringLiteral;
					return token;
					
				case '`':
					token.stringValue = readStringLiteral(false);
					token.type = Token.Type.StringLiteral;
					return token;
					
				case '\'':
					token.stringValue = readCharLiteral();
					token.type = Token.Type.CharLiteral;
					return token;
					
				case 'r':
					nextChar();
					
					if(mCharacter == '\"')
					{
						token.stringValue = readStringLiteral(true);
						token.type = Token.Type.StringLiteral;
						return token;
					}
					else
					{
						char[] s = "r";
						
						do
						{
							s ~= mCharacter;
							nextChar();
						}
						while(isAlpha(mCharacter) || isDecimalDigit(mCharacter) || mCharacter == '_');
						
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
							throw new MDCompileException("'" ~ s ~ "': Identifiers starting with two underscores are reserved", tokenLoc);
						
						Token.Type* t = (s in Token.stringToType);

						if(t is null)
						{
							token.type = Token.Type.Ident;
							token.stringValue = s;
							return token;
						}
						else
						{
							if(*t == Token.Type.True || *t == Token.Type.False)
							{
								token.type = Token.Type.BoolLiteral;
								token.boolValue = (*t == Token.Type.True);
							}
							else
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
							throw new MDCompileException("Invalid token '" ~ s ~ "'", tokenLoc);
						else
						{
							token.type = *t;
							return token;
						}
					}
			}
		}
	}
}

/*
Named symbols include:
	modules
	classes
	functions
	variables
	properties
	
Many symbols introduce scope.  All but variables in the above list.
Other constructs introduce scope as well, including:
	block
	if
	while
	do-while
	for
	foreach
	case
	default
*/

class Scope
{
	protected Symbol mParent;
	protected Module mModule;
	protected Scope mEnclosing;
	protected FuncDecl mFunc;
	protected ForeachStatement mForeach;
	protected Statement mBreakableStat;
	protected Statement mContinuableStat;
	protected SymbolTable mTable;
	protected Scope[] mEnclosed;
	protected Scope[] mImports;

	public static Scope createGlobal(Module owner)
	{
		Scope s = new Scope(owner);
		s.mModule = owner;
		owner.mChild = s;

		return s;
	}

	public this(Symbol parent)
	{
		mParent = parent;

		if(parent.mParent !is null)
		{
			mEnclosing = parent.mParent;
			mModule = parent.mParent.mModule;
			mFunc = parent.mParent.mFunc;
		}
	}
	
	public this(Scope parent)
	{
		if(parent !is null)
		{
			mEnclosing = parent;
			mParent = parent.mParent;
			mModule = parent.mModule;
			mFunc = parent.mFunc;
			parent.mEnclosed ~= this;
		}
	}

	public Symbol search(Identifier ident, out Symbol owner)
	{
		assert(ident !is null);
		
		for(Scope s = this; s !is null; s = s.mEnclosing)
		{
			if(s.mTable is null)
				continue;

			Symbol sym = s.mTable.lookup(ident);

			if(sym is null)
			{
				foreach(Scope imp; s.mImports)
				{
					Symbol sym2 = imp.search(ident);

					if(sym is null)
						sym = sym2;
					else if(sym2 !is null && sym !is sym2)
						throw new MDSymbolConflictException(sym, sym2);
				}
			}

			if(sym is null)
				continue;

			owner = s.mParent;
			return sym;
		}
		
		return null;
	}
	
	public void importScope(Scope s)
	{
		if(s is this)
			return;
			
		foreach(Scope imp; mImports)
			if(imp is s)
				return;
				
		mImports ~= s;
	}
	
	public Symbol search(Identifier ident)
	{
		Symbol owner;
		return search(ident, owner);
	}
	
	public Symbol insert(Symbol s)
	{
		if(mTable is null)
			mTable = new SymbolTable();

		return mTable.insert(s);
	}

	public Scope push(Symbol s)
	{
		Scope sc = new Scope(s);
		s.mChild = sc;

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
	
	public void showChildren(uint tab = 0)
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
	}
}

class Symbol
{
	protected Scope mParent;
	protected Scope mChild;
	protected Identifier mIdent;
	protected Location mLocation;
	
	public this(Identifier ident, Location location)
	{
		mIdent = ident;
		mLocation = location;
	}
	
	public this()
	{

	}
	
	public Scope parent()
	{
		return mParent;
	}
	
	public Symbol search(Identifier ident)
	{
		return null;
	}
	
	public char[] toString()
	{
		if(mIdent !is null)
			return mIdent.toString();
		else
			return "__anonymous";
	}
	
	public char[] toName()
	{
		if(mIdent !is null)
			return mIdent.toString();
		else
			return "__anonymous";
	}

	public char[] toPrettyString()
	{
		if(mParent is null)
			return toName();

		char[] ret = toName();

		Symbol old;

		for(Scope s = mParent; s !is null; s = s.mEnclosing)
		{
			if(s.mParent !is old)
			{
				ret = s.mParent.toName() ~ "." ~ ret;
				old = s.mParent;
			}
		}

		return ret;
	}

	protected void semantic1(Scope sc)
	{
		throw new MDException("No semantic routine");
	}

	protected void semantic2(Scope sc)
	{

	}

	protected void semantic3(Scope sc)
	{

	}
	
	protected bool isAnonymous()
	{
		return (mIdent is null);
	}

	protected bool addAsMember(Scope owner)
	{
		mParent = owner;

		if(isAnonymous())
			return false;

		if(owner.insert(this) is null)
		{
			// The insert failed (it already exists in the table)
			
			// Let's try overloading it
			Symbol sym = owner.mTable.lookup(mIdent);

			if(sym.overloadInsert(this) == false)
				throw new MDSymbolConflictException(this, sym);
		}

		return true;
	}

	protected bool overloadInsert(Symbol sym)
	{
		return false;
	}
	
	public void showChildren(uint tab = 0)
	{
		//writefln(std.string.repeat("\t", tab), this);

		if(mChild is null)
			return;
			
		mChild.showChildren(tab);
	}
}

class SymbolTable
{
	protected Symbol[char[]] mTable;

	// Look up symbol.  Returns null if doesn't exist.
	public Symbol lookup(Identifier ident)
	{
		Symbol* test = (ident.mName in mTable);
		
		if(test is null)
			return null;
		else
			return *test;
	}

	// If symbol is there, return null; otherwise, add it and return it.
	public Symbol insert(Symbol sym)
	{
		Symbol* test = (sym.mIdent.mName in mTable);
		
		if(test !is null)
			return null;
			
		mTable[sym.mIdent.mName] = sym;
		
		return sym;
	}
	
	// Lookup symbol.  If it's already there, return it.  Otherwise, add it and return it.
	public Symbol update(Symbol sym)
	{
		Symbol* test = (sym.mIdent.mName in mTable);
		
		if(test !is null)
			return *test;
			
		mTable[sym.mIdent.mName] = sym;
		
		return sym;
	}
}

class Module : Symbol
{
	protected ModuleDecl mModuleDecl;
	protected ImportDecl[] mImports;
	protected Symbol[] mDecls;
	protected MainDecl mMain;
	protected bool mSemanticDone;

	public this(ModuleDecl moduleDecl, ImportDecl[] imports, Symbol[] decls, MainDecl moduleMain)
	{
		assert(moduleDecl !is null, "There should always be a module declaration..");

		super(moduleDecl.mIdent, moduleDecl.mLocation);

		mModuleDecl = moduleDecl;
		mImports = imports;
		mDecls = decls;
		mMain = moduleMain;
		
		mImports ~= ImportDecl.minidInstance;
	}

	public static Module parse(inout Token* t)
	{
		ModuleDecl moduleDecl = ModuleDecl.parse(t);
		
		ImportDecl[] imports;
		Symbol[] decls;
		MainDecl moduleMain;

		// Parse declarations
		while(t.type != Token.Type.EOF)
		{
			Location location = t.location;

			switch(t.type)
			{
				case Token.Type.Import:
					imports ~= ImportDecl.parse(t);
					break;

				case Token.Type.Main:
					if(moduleMain !is null)
						throw new MDCompileException("Duplicate main declaration (other is at " ~ moduleMain.mLocation.toString() ~ ")", location);

					moduleMain = MainDecl.parse(t);
					break;
					
				case Token.Type.Class:
					decls ~= ClassDecl.parse(t);
					break;
					
				case Token.Type.Namespace:
					decls ~= NamespaceDecl.parse(t, true);
					break;

				default:
					decls ~= SimpleDecl.parse(t);
					break;
			}
		}

		return new Module(moduleDecl, imports, decls, moduleMain);
	}

	public char[] toString()
	{
		return mModuleDecl.toString();
	}
	
	public char[] toName()
	{
		if(mModuleDecl)
			return mModuleDecl.toName();
			
		return "";
	}
	
	// Dummy
	protected override void semantic1(Scope sc)
	{

	}

	protected void semantic()
	{
		if(mSemanticDone)
			return;
			
		mSemanticDone = true;

		Scope s = Scope.createGlobal(this);

		foreach(ImportDecl imp; mImports)
			imp.addAsMember(s);

		foreach(Symbol sym; mDecls)
			sym.semantic1(s);

		if(mMain)
			mMain.semantic1(s);
			
		foreach(Symbol sym; mDecls)
			sym.semantic2(s);
			
		if(mMain)
			mMain.semantic2(s);
	}
}

class ModuleDecl : Symbol
{
	protected Identifier[] mPackages;

	public this(Identifier[] packages, Identifier name)
	{
		Location location;
		super(name, location);
		mPackages = packages;
	}
	
	public static ModuleDecl parse(inout Token* t)
	{
		t.check(Token.Type.Module);
		t = t.nextToken;

		Identifier[] names;

		while(true)
		{
			t.check(Token.Type.Ident);

			names ~= Identifier.parse(t);
			names[$ - 1].mName = std.string.tolower(names[$ - 1].mName);

			if(t.type == Token.Type.Dot)
				t = t.nextToken;
			else
				break;
		}
		
		t.check(Token.Type.Semicolon);
		t = t.nextToken;

		return new ModuleDecl(names[0 .. $ - 1], names[$ - 1]);
	}
	
	public char[] toString()
	{
		return std.string.format("module %s", toName());
	}
	
	public char[] toName()
	{
		char[] ret;

		foreach(Identifier p; mPackages)
			ret = std.string.format("%s%s.", ret, p);
			
		ret ~= mIdent.toString();
			
		return ret;
	}
}

class ImportDecl : Symbol
{
	protected Identifier[] mPackages;
	
	protected static ImportDecl minidInstance;
	
	static this()
	{
		minidInstance = new ImportDecl(null, new Identifier("minid"), Location(""));
	}

	public this(Identifier[] packages, Identifier name, Location location)
	{
		super(name, location);
		mPackages = packages;
	}

	public static ImportDecl parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Import);
		t = t.nextToken;

		Identifier[] names;

		while(true)
		{
			t.check(Token.Type.Ident);

			names ~= Identifier.parse(t);
			names[$ - 1].mName = std.string.tolower(names[$ - 1].mName);

			if(t.type == Token.Type.Dot)
				t = t.nextToken;
			else
				break;
		}
		
		t.check(Token.Type.Semicolon);
		t = t.nextToken;

		return new ImportDecl(names[0 .. $ - 1], names[$ - 1], location);
	}

	public char[] toString()
	{
		char[] ret;

		foreach(Identifier p; mPackages)
			ret = std.string.format("%s%s.", ret, p);

		return std.string.format("import %s%s", ret, mIdent);
	}
}

class NamespaceDecl : Symbol
{
	protected Symbol[] mDecls;

	public this(Identifier name, Symbol[] decls, Location location)
	{
		super(name, location);
		
		mDecls = decls;
	}
	
	public static NamespaceDecl parse(inout Token* t, bool allowClasses)
	{
		Location location = t.location;
		
		t.check(Token.Type.Namespace);
		t = t.nextToken;
		
		Identifier name = Identifier.parse(t);
		
		t.check(Token.Type.LBrace);
		t = t.nextToken;
		
		Symbol[] decls;
		
		while(t.type != Token.Type.RBrace)
		{
			switch(t.type)
			{
				case Token.Type.Def:
					decls ~= SimpleDecl.parse(t);
					break;
					
				case Token.Type.Namespace:
					decls ~= NamespaceDecl.parse(t, allowClasses);
					break;
					
				case Token.Type.Class:
					if(allowClasses)
						decls ~= ClassDecl.parse(t);
					else
						throw new MDCompileException("Cannot declare a class inside a class", t.location);
					break;
					
				default:
					throw new MDCompileException("Declaration expected for namespace '" ~ name.toString() ~ "', not '" ~ t.toString() ~ "'", t.location);
			}
		}
		
		if(t.type != Token.Type.RBrace)
			throw new MDCompileException("'}' Expected after declaration of namespace '" ~ name.toString() ~ "'", t.location);
			
		t = t.nextToken;
		
		return new NamespaceDecl(name, decls, location);
	}
	
	protected override void semantic1(Scope sc)
	{
		addAsMember(sc);

		sc = sc.push(this);

		foreach(Symbol decl; mDecls)
			decl.semantic1(sc);
			
		sc.pop();
	}
	
	protected override void semantic2(Scope sc)
	{
		foreach(Symbol decl; mDecls)
			decl.semantic2(mChild);
	}

	public char[] toString()
	{
		return "namespace " ~ mIdent.toString();
	}
}

class ClassDecl : Symbol
{
	protected Identifier[] mBaseClassName;
	protected ClassDecl mBaseClassDecl;
	protected CtorDecl[] mCtors;
	protected DtorDecl mDtor;
	protected FuncDecl[] mMethods;
	protected VarDecl[] mFields;
	protected NamespaceDecl[] mNamespaces;
	protected static Identifier[] objectNameInst;

	static this()
	{
		objectNameInst = new Identifier[2];
		objectNameInst[0] = new Identifier("minid");
		objectNameInst[1] = new Identifier("Object");
	}
	
	protected static DtorDecl defaultDtor(ClassDecl owner)
	{
		// ~this() { }
		Statement[] s;
		return new DtorDecl(new CompoundStatement(owner.mLocation, s), owner.mLocation);
	}
	
	protected static CtorDecl defaultCtor(ClassDecl owner)
	{
		// this() { super(); }
		Statement s = new ExpressionStatement(owner.mLocation, new CallExp(owner.mLocation, new SuperExp(owner.mLocation), null));
		return new CtorDecl(null, new CompoundStatement(owner.mLocation, s), owner.mLocation);
	}

	public this(Identifier name, Identifier[] baseClassName, CtorDecl[] ctors, DtorDecl dtor, FuncDecl[] methods, VarDecl[] fields, NamespaceDecl[] namespaces, Location location)
	{
		super(name, location);

		mBaseClassName = baseClassName;

		if(mBaseClassName.length == 0)
			mBaseClassName = objectNameInst;

		mCtors = ctors;
		mDtor = dtor;
		mMethods = methods;
		mFields = fields;
		mNamespaces = namespaces;
		
		if(mCtors.length == 0)
			mCtors ~= defaultCtor(this);

		if(mDtor is null)
			mDtor = defaultDtor(this);
	}

	public static ClassDecl parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Class);
		t = t.nextToken;
		
		t.check(Token.Type.Ident);
		Identifier name = Identifier.parse(t);
		
		Identifier[] baseClassName;
		
		if(t.type == Token.Type.Colon)
		{
			t = t.nextToken;

			while(true)
			{
				t.check(Token.Type.Ident);

				baseClassName ~= Identifier.parse(t);

				if(t.type != Token.Type.Dot)
					break;
					
				t = t.nextToken;
			}
		}
		
		t.check(Token.Type.LBrace);
		t = t.nextToken;

		FuncDecl[] methods;
		VarDecl[] fields;
		NamespaceDecl[] namespaces;
		CtorDecl[] ctors;
		DtorDecl dtor;

		while(t.type != Token.Type.RBrace)
		{
			Location location2 = t.location;

			switch(t.type)
			{
				case Token.Type.This:
					t = t.nextToken;
					Parameter[] params = Parameter.parseParams(t);
					CompoundStatement funcBody = CompoundStatement.parse(t);
					ctors ~= new CtorDecl(params, funcBody, location2);
					break;
					
				case Token.Type.Cat:
					t = t.nextToken;
					t.check(Token.Type.This);
					t = t.nextToken;
					t.check(Token.Type.LParen);
					t = t.nextToken;
					t.check(Token.Type.RParen);
					t = t.nextToken;
					CompoundStatement funcBody = CompoundStatement.parse(t);
					
					if(dtor !is null)
						throw new MDCompileException("Multiple destructors in class '" ~ name.toString() ~ "'", location2);
						
					dtor = new DtorDecl(funcBody, location2);
					break;
					
				case Token.Type.Def:
					SimpleDecl decl = SimpleDecl.parse(t);
					
					if(cast(FuncDecl)decl)
						methods ~= cast(FuncDecl)decl;
					else if(cast(VarDecl)decl)
						fields ~= cast(VarDecl)decl;
					else
						assert(false, "Umm, can any other kind of declaration exist in a class?");
					break;
					
				case Token.Type.Namespace:
					namespaces ~= NamespaceDecl.parse(t, false);
					break;
					
				default:
					throw new MDCompileException("Declaration expected for class '" ~ name.toString() ~ "', not '" ~ t.toString() ~ "'", location2);
			}
		}

		if(t.type != Token.Type.RBrace)
			throw new MDCompileException("'}' Expected after declaration of class '" ~ name.toString() ~ "'", t.location);

		t = t.nextToken;

		return new ClassDecl(name, baseClassName, ctors, dtor, methods, fields, namespaces, location);
	}
	
	protected override void semantic1(Scope sc)
	{
		addAsMember(sc);

		sc = sc.push(this);

		foreach(CtorDecl decl; mCtors)
			decl.semantic1(sc);

		foreach(FuncDecl decl; mMethods)
			decl.semantic1(sc);
			
		foreach(VarDecl decl; mFields)
			decl.semantic1(sc);

		foreach(NamespaceDecl decl; mNamespaces)
			decl.semantic1(sc);
			
		mDtor.semantic1(sc);

		sc.pop();
	}
	
	protected override void semantic2(Scope sc)
	{
		Symbol sym = sc.search(mBaseClassName[0]);
		
		if(mBaseClassName.length > 1)
			foreach(Identifier namePiece; mBaseClassName[1 .. $])
				sym = sym.search(namePiece);

		mBaseClassDecl = cast(ClassDecl)sym;
		
		if(mBaseClassDecl is null)
			throw new MDCompileException("Base class '" ~ Identifier.toLongString(mBaseClassName) ~ "' is not a class!", mLocation);
		
		// TODO: method override mechanism
		// figure out vtbl
		// make member table (check no dup members from base class)

		//foreach(Symbol decl; mDecls)
		//	decl.semantic2(mChild);
	}

	public char[] toString()
	{
		return "class " ~ mIdent.toString();
	}
}

abstract class SimpleDecl : Symbol
{
	public this(Identifier ident, Location location)
	{
		super(ident, location);
	}

	public static SimpleDecl parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Def);
		t = t.nextToken;

		Type type = Type.parse(t);
		Identifier ident = Identifier.parse(t);

		if(t.type == Token.Type.LParen)
		{
			Parameter[] params = Parameter.parseParams(t);
			CompoundStatement funcBody = CompoundStatement.parse(t);

			return new FuncDecl(type, ident, params, funcBody, location);
		}

		Expression init;

		if(t.type == Token.Type.Assign)
		{
			t = t.nextToken;
			init = BaseAssignExp.parse(t);
			assert(init !is null);
		}

		t.check(Token.Type.Semicolon);
		t = t.nextToken;

		return new VarDecl(type, ident, init, location);
	}
}

class VarDecl : SimpleDecl
{
	protected Type mType;
	protected Expression mInitializer;

	public this(Type type, Identifier name, Expression initializer, Location location)
	{
		super(name, location);
		mType = type;
		mInitializer = initializer;

		if(mInitializer is null)
			mInitializer = mType.defaultInitializer();
	}

	public static VarDecl parse(inout Token* t, bool isolated = true)
	{
		Location location = t.location;

		t.check(Token.Type.Def);
		t = t.nextToken;
		
		Type type = Type.parse(t);
		Identifier ident = Identifier.parse(t);
		
		Expression init;
		
		if(t.type == Token.Type.Assign)
		{
			t = t.nextToken;
			init = BaseAssignExp.parse(t);
			assert(init !is null);
		}

		if(isolated)
		{
			t.check(Token.Type.Semicolon);
			t = t.nextToken;
		}

		return new VarDecl(type, ident, init, location);
	}

	protected override void semantic1(Scope sc)
	{
		if(sc.mFunc is null)
			addAsMember(sc);
	}
	
	protected override void semantic2(Scope sc)
	{
		if(mInitializer !is null)
			mInitializer.semantic2(sc);

		if(sc.mFunc !is null)
		{
			sc.mFunc.checkShadowing(this);
			addAsMember(sc);
		}

		mType.semantic2(mLocation, sc);
	}
	
	public char[] toString()
	{
		return std.string.format("%s %s", mType, mIdent);
	}
}

class ThisDecl : VarDecl
{
	public this(Type type, Location location)
	{
		super(type, Identifier.This, null, location);
	}
	
	public char[] toString()
	{
		return "ThisDecl";
	}
}

class FuncDecl : SimpleDecl
{
	protected Type mReturnType;
	protected FunctionType mFuncType;
	protected Parameter[] mParams;
	protected CompoundStatement mBody;
	protected FuncDecl mNextOverload;
	protected ClassDecl mOwnerClass;
	protected SymbolTable mShadowingTable;

	public this(Type returnType, Identifier name, Parameter[] params, CompoundStatement funcBody, Location location)
	{
		super(name, location);
		mReturnType = returnType;
		mParams = params;
		mBody = funcBody;
		
		Type[] paramTypes;
		
		foreach(Parameter p; params)
			paramTypes ~= p.mType;

		mFuncType = new FunctionType(paramTypes);
		mFuncType.mNextType = mReturnType;
		mFuncType.generateMangle();
	}
	
	protected override bool overloadInsert(Symbol sym)
	{
		FuncDecl other = cast(FuncDecl)sym;

		if(other is null)
			return false;

		if(isSameSignature(other))
			return false;
			
		if(mNextOverload !is null)
			return mNextOverload.overloadInsert(other);

		mNextOverload = other;
		
		return true;
	}
	
	protected bool isSameSignature(FuncDecl other)
	{
		if(mReturnType != other.mReturnType)
			return false;
			
		if(mParams.length != other.mParams.length)
			return false;
			
		for(uint i = 0; i < mParams.length; i++)
			if(mParams[i].mType != other.mParams[i].mType)
				return false;

		return true;
	}

	protected void checkShadowing(Symbol sym)
	{
		assert(mChild !is null, "need child scope to see if ident is shadowed");
		
		if(mShadowingTable is null)
			mShadowingTable = new SymbolTable();

		Symbol s = mShadowingTable.update(sym);

		if(s !is sym)
			throw new MDShadowingException(sym, s);
	}

	protected override void semantic1(Scope sc)
	{
		if(sc.mFunc !is null)
			sc.mFunc.checkShadowing(this);

		addAsMember(sc);

		sc = sc.push(this);
		sc.mFunc = this;

		mBody.semantic1(sc);

		sc.pop();
	}

	protected override void semantic2(Scope sc)
	{
		/*if(hasThis())
		{

		}*/

		foreach(Parameter p; mParams)
			p.semantic2(mChild);

		mBody.semantic2(mChild);
	}

	public char[] toString()
	{
		char[] ret = std.string.format("%s %s(", mReturnType, mIdent);

		if(mParams.length == 0)
			ret ~= ")";
		else if(mParams.length == 1)
			ret = std.string.format("%s%s)", ret, mParams[0]);
		else
		{
			foreach(uint i, Parameter p; mParams)
			{
				if(i == mParams.length - 1)
					ret = std.string.format("%s%s)", ret, p);
				else
					ret = std.string.format("%s%s, ", ret, p);
			}
		}
		
		//ret ~= '\n';
		
		//ret = std.string.format("%s%s", ret, mBody);

		return ret;
	}
	
	public void showOverloads(uint tab = 0)
	{
		if(mNextOverload)
		{
			writefln(std.string.repeat("\t", tab), mNextOverload);
			mNextOverload.showChildren(tab + 1);
		}
	}
}

class MainDecl : FuncDecl
{
	protected Identifier mArgName;
	protected VarDecl mArgDecl;

	public this(Identifier argName, CompoundStatement mainBody, Location location)
	{
		super(new VoidType(), Identifier.Main, null, mainBody, location);
		mArgName = argName;
	}
	
	public static MainDecl parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Main);
		t = t.nextToken;
		
		t.check(Token.Type.LParen);
		t = t.nextToken;
		
		Identifier argName;

		if(t.type == Token.Type.RParen)
			t = t.nextToken;
		else
		{
			argName = Identifier.parse(t);
			t.check(Token.Type.RParen);
			t = t.nextToken;
		}

		return new MainDecl(argName, CompoundStatement.parse(t), location);
	}
	
	protected override void semantic2(Scope sc)
	{
		if(mArgName)
		{
			mArgDecl = new VarDecl(new ArrayType(new ArrayType(new CharType())), mArgName, null, mLocation);
			mArgDecl.semantic2(mChild);
		}
		
		mBody.semantic2(mChild);
	}

	public char[] toString()
	{
		if(mArgName is null)
			return "main()";
		else
			return "main(" ~ mArgName.toString() ~ ")";
	}
}

class CtorDecl : FuncDecl
{
	public this(Parameter[] params, CompoundStatement funcBody, Location location)
	{
		super(new VoidType(), Identifier.Ctor, params, funcBody, location);
	}
	
	public char[] toString()
	{
		char[] ret = "this(";

		if(mParams.length == 0)
			ret ~= ")";
		else if(mParams.length == 1)
			ret = std.string.format("%s%s)", ret, mParams[0]);
		else
		{
			foreach(uint i, Parameter p; mParams)
			{
				if(i == mParams.length - 1)
					ret = std.string.format("%s%s)", ret, p);
				else
					ret = std.string.format("%s%s, ", ret, p);
			}
		}

		return ret;
	}
}

class DtorDecl : FuncDecl
{
	public this(CompoundStatement funcBody, Location location)
	{
		super(new VoidType(), Identifier.Dtor, null, funcBody, location);
	}

	public char[] toString()
	{
		return "~this()";
	}
}

class FuncLiteralDecl : FuncDecl
{
	public this(Type returnType, Parameter[] params, CompoundStatement funcBody, Location location)
	{
		super(returnType, Identifier.generateUnique("__funcLiteral"), params, funcBody, location);
	}
	
	public static FuncLiteralDecl parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Function);
		t = t.nextToken;

		Type returnType = Type.parse(t);

		Parameter[] params = Parameter.parseParams(t);
		CompoundStatement funcBody = CompoundStatement.parse(t);
		
		return new FuncLiteralDecl(returnType, params, funcBody, location);
	}
	
	public char[] toString()
	{
		return "function literal";
	}
}

abstract class Type
{
	protected static struct Mangle
	{
		static const char[] Void = "v";
		static const char[] Char = "c";
		static const char[] Bool = "b";
		static const char[] Int = "i";
		static const char[] Float = "f";
		static const char[] Vararg = "x";
		static const char[] Class = "C";
		static const char[] AA = "M";
		static const char[] Array = "A";
		static const char[] Function = "F";
	}

	protected char[] mMangledName;
	
	public static Type parse(inout Token* t)
	{
		BasicType basic;

		switch(t.type)
		{
			case Token.Type.Void, Token.Type.Char, Token.Type.Bool, Token.Type.Int, Token.Type.Float, Token.Type.Ident:
				basic = BasicType.parse(t);
				break;

			case Token.Type.Vararg:
				return VarargType.parse(t);

			default:
				throw new MDCompileException("Type expected, not '" ~ t.toString() ~ "'", t.location);
		}

		ExtendedType ext;

		while(t.type == Token.Type.LBracket || t.type == Token.Type.Function)
		{
			ExtendedType e = ExtendedType.parse(t);

			if(ext is null)
			{
				e.mNextType = basic;
				ext = e;
			}
			else
			{
				e.mNextType = ext;
				ext = e;
			}
		}

		if(ext is null)
		{
			basic.generateMangle();
			return basic;
		}
		else
		{
			ext.generateMangle();
			return ext;
		}
	}
	
	/*public static Type checkConversion(Type typeFrom, Type typeTo)
	{
		if(cast(IntType)typeFrom)
		{
			if(cast(FloatType)typeTo)
				return typeTo;
				
			if(cast(BoolType)typeTo)
				return typeTo;
		}
		
		return null;
	}*/
	
	public bool checkToBoolean()
	{
		return false;
	}
	
	public static enum Conv
	{
		No,
		Implicit,
		Exact
	}

	public Conv implicitConvTo(Type other)
	{
		if(this == other)
			return Conv.Exact;

		return Conv.No;
	}
	
	public Conv explicitConvTo(Type other)
	{
		if(this == other)
			return Conv.Exact;
			
		return Conv.No;
	}
	
	public bool canBeCompared(Type other)
	{
		if(isAA())
			return false;

		if(this != other)
			return false;

		Type b = this;

		ExtendedType t = cast(ExtendedType)b;

		if(t)
		{
			while(cast(ExtendedType)t.mNextType !is null)
				t = cast(ExtendedType)t.mNextType;

			b = t.mNextType;
		}
		
		if(b.isVararg() || b.isFunction() || b.isAA() || b.isVoid() || b.isBool() || b.isClass())
			return false;
			
		return true;
	}
	
	public Expression defaultInitializer()
	{
		assert(false, "Type init needs to be overridden");
	}

	public Type semantic2(Location location, Scope sc)
	{
		return this;
	}

	public bool isVararg()
	{
		return (cast(VarargType)this) !is null;	
	}
	
	public bool isFunction()
	{
		return (cast(FunctionType)this) !is null;
	}

	public bool isArray()
	{
		return (cast(ArrayType)this) !is null;
	}
	
	public bool isAA()
	{
		return (cast(AAType)this) !is null;
	}

	public bool isVoid()
	{
		return (cast(VoidType)this) !is null;
	}
	
	public bool isBool()
	{
		return (cast(BoolType)this) !is null;
	}

	public bool isInt()
	{
		return (cast(IntType)this) !is null;
	}
	
	public bool isFloat()
	{
		return (cast(FloatType)this) !is null;
	}

	public bool isNumeric()
	{
		return isInt() || isFloat();
	}
	
	public bool isChar()
	{
		return (cast(CharType)this) !is null;
	}
	
	public bool isClass()
	{
		return (cast(ClassType)this) !is null;
	}
	
	public bool isReference()
	{
		return (isClass() || isArray() || isAA() || isFunction());	
	}
	
	public bool isNamespace()
	{
		return (cast(NamespaceType)this) !is null;
	}

	public int opEquals(Object o)
	{
		Type other = cast(Type)o;
		assert(other);

		return mMangledName == other.mMangledName;
	}

	protected abstract void generateMangle();
}

class NamespaceType : Type
{
	private static NamespaceType instance;
	
	static this()
	{
		instance = new NamespaceType();
	}

	public override bool checkToBoolean()
	{
		return false;
	}

	public override void generateMangle()
	{
		assert(false, "NamespaceType should never have its mangle generated");
	}
	
	public override Expression defaultInitializer()
	{
		assert(false, "There should never be a void variable");
	}

	public char[] toString()
	{
		return "void";
	}
}

abstract class BasicType : Type
{
	public static BasicType parse(inout Token* t)
	{
		switch(t.type)
		{
			case Token.Type.Void:
				return VoidType.parse(t);

			case Token.Type.Bool:
				return BoolType.parse(t);

			case Token.Type.Int:
				return IntType.parse(t);

			case Token.Type.Float:
				return FloatType.parse(t);

			case Token.Type.Char:
				return CharType.parse(t);
				
			case Token.Type.Ident:
				return ClassType.parse(t);

			default:
				throw new MDCompileException("Basic type expected, not '" ~ t.toString() ~ "'", t.location);
		}
	}
}

class VoidType : BasicType
{
	private static VoidType instance;
	
	static this()
	{
		instance = new VoidType();
		instance.generateMangle();
	}

	public static VoidType parse(inout Token* t)
	{
		t.check(Token.Type.Void);
		t = t.nextToken;

		return instance;
	}

	public override bool checkToBoolean()
	{
		return false;
	}

	public override void generateMangle()
	{
		mMangledName = Mangle.Void;
	}
	
	public override Expression defaultInitializer()
	{
		assert(false, "There should never be a void variable");
	}

	public char[] toString()
	{
		return "void";
	}
}

class BoolType : BasicType
{
	private static BoolType instance;
	private static Expression init;
	
	static this()
	{
		instance = new BoolType();
		instance.generateMangle();
		init = new BoolExp(Location(""), false);
	}

	public static BoolType parse(inout Token* t)
	{
		t.check(Token.Type.Bool);
		t = t.nextToken;

		return instance;
	}
	
	public override bool checkToBoolean()
	{
		return true;
	}

	public override void generateMangle()
	{
		mMangledName = Mangle.Bool;
	}
	
	public override Expression defaultInitializer()
	{
		return init;
	}

	public char[] toString()
	{
		return "bool";
	}
}

class IntType : BasicType
{
	private static IntType instance;
	private static IntExp init;
	
	static this()
	{
		instance = new IntType();
		instance.generateMangle();
		init = new IntExp(Location(""), 0);
	}

	public static IntType parse(inout Token* t)
	{
		t.check(Token.Type.Int);
		t = t.nextToken;
		
		return instance;
	}

	public override bool checkToBoolean()
	{
		return true;
	}
	
	public override Conv explicitConvTo(Type other)
	{
		if(other.isChar())
			return Conv.Exact;
			
		return super.implicitConvTo(other);
	}
	
	public override Conv implicitConvTo(Type other)
	{
		if(other.isFloat() || other.isBool())
			return Conv.Implicit;
			
		return super.implicitConvTo(other);
	}

	public override void generateMangle()
	{
		mMangledName = Mangle.Int;
	}
	
	public override Expression defaultInitializer()
	{
		return init;
	}

	public char[] toString()
	{
		return "int";
	}
}

class FloatType : BasicType
{
	private static FloatType instance;
	private static FloatExp init;
	
	static this()
	{
		instance = new FloatType();
		instance.generateMangle();
		init = new FloatExp(Location(""), float.nan);
	}

	public static FloatType parse(inout Token* t)
	{
		t.check(Token.Type.Float);
		t = t.nextToken;
		
		return instance;
	}
	
	public override bool checkToBoolean()
	{
		return false;
	}
	
	public override Conv explicitConvTo(Type other)
	{
		if(other.isInt())
			return Conv.Exact;

		return super.implicitConvTo(other);
	}
	
	public override void generateMangle()
	{
		mMangledName = Mangle.Float;
	}
	
	public override Expression defaultInitializer()
	{
		return init;
	}
	
	public char[] toString()
	{
		return "float";
	}
}

class CharType : BasicType
{
	private static CharType instance;
	private static CharExp init;
	
	static this()
	{
		instance = new CharType();
		instance.generateMangle();
		init = new CharExp(Location(""), 0);
	}

	public static CharType parse(inout Token* t)
	{
		t.check(Token.Type.Char);
		t = t.nextToken;
		
		return instance;
	}
	
	public override bool checkToBoolean()
	{
		return false;
	}
	
	public override Conv implicitConvTo(Type other)
	{
		if(other.isInt())
			return Conv.Implicit;
			
		return super.implicitConvTo(other);
	}

	public override void generateMangle()
	{
		mMangledName = Mangle.Char;
	}
	
	public override Expression defaultInitializer()
	{
		return init;
	}
	
	public char[] toString()
	{
		return "char";
	}
}

class ClassType : BasicType
{
	protected Identifier mIdent;
	protected ClassDecl mClassDecl;
	protected static NullExp init;
	
	public this(Identifier ident)
	{
		mIdent = ident;
		init = new NullExp(Location(""));
	}

	public static ClassType parse(inout Token* t)
	{
		return new ClassType(Identifier.parse(t));
	}
	
	public override Type semantic2(Location location, Scope sc)
	{
		Symbol sym = sc.search(mIdent);

		if(sym is null)
			throw new MDCompileException("Undefined type '" ~ mIdent.toString() ~ "'", location);

		mClassDecl = cast(ClassDecl)sym;

		if(mClassDecl is null)
			throw new MDCompileException("'" ~ sym.toString() ~ "' is not a class type", location);
			
		return this;
	}
	
	public override bool checkToBoolean()
	{
		return true;
	}
	
	public override Conv explicitConvTo(Type other)
	{
		// TODO: check class hierarchy to assure that this cast is legal

		return super.explicitConvTo(other);
	}
	
	public override Conv implicitConvTo(Type other)
	{
		// TODO: check class hierarchy to assure that this cast is legal

		return super.implicitConvTo(other);
	}

	public override void generateMangle()
	{
		mMangledName = Mangle.Class ~ std.string.toString(mIdent.toString().length) ~ mIdent.toString();	
	}
	
	public override Expression defaultInitializer()
	{
		return init;
	}

	public char[] toString()
	{
		return mIdent.toString();
	}
}

class VarargType : Type
{
	public static VarargType parse(inout Token* t)
	{
		t.check(Token.Type.Vararg);
		t = t.nextToken;
		
		return new VarargType();
	}
	
	public override bool checkToBoolean()
	{
		return false;
	}
	
	public override void generateMangle()
	{
		mMangledName = Mangle.Vararg;
	}
	
	public override Expression defaultInitializer()
	{
		assert(false, "Varargs don't have an init, silly!");
	}
	
	public char[] toString()
	{
		return "vararg";
	}
}

abstract class ExtendedType : Type
{
	protected Type mNextType;
	protected static NullExp init;
	
	static this()
	{
		init = new NullExp(Location(""));
	}

	public static ExtendedType parse(inout Token* t)
	{
		switch(t.type)
		{
			case Token.Type.LBracket:
				if(t.nextToken.type == Token.Type.RBracket)
					return ArrayType.parse(t);
				else
					return AAType.parse(t);

			case Token.Type.Function:
				return FunctionType.parse(t);

			default:
				throw new MDCompileException("Extended type expected, not '" ~ t.toString() ~ "'", t.location);
		}
	}
	
	public override Expression defaultInitializer()
	{
		return init;
	}
}

class FunctionType : ExtendedType
{
	protected Type[] mParamTypes;

	public this(Type[] paramTypes)
	{
		mParamTypes = paramTypes;
		init = new NullExp(Location(""));
	}

	public static FunctionType parse(inout Token* t)
	{
		t.check(Token.Type.Function);
		t = t.nextToken;
		t.check(Token.Type.LParen);
		t = t.nextToken;

		Type[] paramTypes;

		if(t.type != Token.Type.RParen)
		{
			while(true)
			{
				paramTypes ~= Type.parse(t);

				if(t.type == Token.Type.RParen)
					break;

				t.check(Token.Type.Comma);
				t = t.nextToken;
			}
		}

		t = t.nextToken;

		return new FunctionType(paramTypes);
	}

	protected override Type semantic2(Location location, Scope sc)
	{
		mNextType = mNextType.semantic2(location, sc);
		
		foreach(inout Type paramType; mParamTypes)
		{
			paramType = paramType.semantic2(location, sc);
			
			if(paramType.isVoid())
				throw new MDCompileException("Cannot have parameter of type void", location);
		}
		
		return this;
	}
	
	public override bool checkToBoolean()
	{
		return false;
	}

	protected override void generateMangle()
	{
		mMangledName = Mangle.Function;
		
		foreach(Type p; mParamTypes)
		{
			p.generateMangle();
			mMangledName ~= p.mMangledName;
		}

		mNextType.generateMangle();
		mMangledName ~= mNextType.mMangledName;
	}

	public override Expression defaultInitializer()
	{
		return init;
	}
	
	public char[] toString()
	{
		char[] ret = std.string.format("%s function(", mNextType);

		if(mParamTypes.length == 0)
			ret ~= ")";
		else if(mParamTypes.length == 1)
			ret = std.string.format("%s%s)", ret, mParamTypes[0]);
		else
		{
			foreach(uint i, Type t; mParamTypes)
			{
				if(i == mParamTypes.length - 1)
					ret = std.string.format("%s%s)", ret, t);
				else
					ret = std.string.format("%s%s, ", ret, t);
			}
		}

		return ret;
	}
}

class ArrayType : ExtendedType
{
	protected static ArrayType stringInstance;

	static this()
	{
		stringInstance = new ArrayType(new CharType());
		stringInstance.generateMangle();
	}
	
	public this(Type nextType = null)
	{
		mNextType = nextType;
	}

	public static ArrayType parse(inout Token* t)
	{
		t.check(Token.Type.LBracket);
		t = t.nextToken;

		t.check(Token.Type.RBracket);
		t = t.nextToken;

		return new ArrayType();
	}
	
	protected override Type semantic2(Location location, Scope sc)
	{
		mNextType = mNextType.semantic2(location, sc);

		if(mNextType.isVoid() || mNextType.isVararg())
			throw new MDCompileException("Cannot have an array of '" ~ mNextType.toString() ~ "'s", location);

		return this;
	}
	
	public override bool checkToBoolean()
	{
		return false;
	}

	protected override void generateMangle()
	{
		mMangledName = Mangle.Array;
		
		assert(mNextType !is null);

		mNextType.generateMangle();
		mMangledName ~= mNextType.mMangledName;
	}

	public char[] toString()
	{
		return std.string.format("%s[]", mNextType);
	}
}

class AAType : ExtendedType
{
	protected Type mKeyType;

	public this(Type keyType)
	{
		mKeyType = keyType;
	}
	
	public static AAType parse(inout Token* t)
	{
		t.check(Token.Type.LBracket);
		t = t.nextToken;
		
		Type keyType = Type.parse(t);
		
		t.check(Token.Type.RBracket);
		t = t.nextToken;
		
		return new AAType(keyType);
	}
	
	public override Type semantic2(Location location, Scope sc)
	{
		mKeyType = mKeyType.semantic2(location, sc);
		
		if(mKeyType.isVoid() || mKeyType.isBool() || mKeyType.isVararg())
			throw new MDCompileException("Cannot have associative array key type of '" ~ mKeyType.toString() ~ "'", location);
			
		mNextType = mNextType.semantic2(location, sc);
		
		if(mNextType.isVoid() || mNextType.isVararg())
			throw new MDCompileException("Cannot have an associative array of '" ~ mNextType.toString() ~ "'s", location);

		return this;
	}
	
	public override bool checkToBoolean()
	{
		return false;
	}

	protected override void generateMangle()
	{
		mMangledName = Mangle.AA;
		
		assert(mKeyType !is null);
		assert(mNextType !is null);
		
		mKeyType.generateMangle();
		mNextType.generateMangle();
		
		mMangledName ~= mKeyType.mMangledName ~ mNextType.mMangledName;
	}
	
	public char[] toString()
	{
		return std.string.format("%s[%s]", mNextType, mKeyType);
	}
}

class Identifier
{
	protected char[] mName;

	public static Identifier Main;
	public static Identifier Ctor;
	public static Identifier Dtor;
	public static Identifier Get;
	public static Identifier Set;
	public static Identifier This;

	static this()
	{
		Main = new Identifier("__main");
		Ctor = new Identifier("__ctor");
		Dtor = new Identifier("__dtor");
		Get = new Identifier("__get");
		Set = new Identifier("__set");
		This = new Identifier("__this");
	}

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
	
	public static Identifier generateUnique(char[] base)
	{
		static uint i = 0;
		
		i++;
		
		return new Identifier(std.string.format(base, i));
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

class Parameter
{
	protected Type mType;
	protected Identifier mName;
	protected Expression mInitializer;
	protected Location mLocation;

	public this(Type type, Identifier name, Expression initializer, Location location)
	{
		mType = type;
		mName = name;
		mInitializer = initializer;
		mLocation = location;
	}

	public static Parameter parse(inout Token* t)
	{
		Location location = t.location;
		
		Type type = Type.parse(t);
		Identifier ident = Identifier.parse(t);
		Expression init;

		if(t.type == Token.Type.Assign)
		{
			if(type.isVararg())
				throw new MDCompileException("Vararg parameter may not have an initializer", location);

			if(type.isFunction())
				throw new MDCompileException("Function parameter may not have an initializer", location);

			t = t.nextToken;
			init = BaseAssignExp.parse(t);
			assert(init !is null);
		}

		return new Parameter(type, ident, init, location);
	}
	
	public static Parameter[] parseParams(inout Token* t)
	{
		t.check(Token.Type.LParen);
		t = t.nextToken;
		
		Parameter[] params;
		
		bool hasDefault = false;
		bool hasVararg = false;

		if(t.type != Token.Type.RParen)
		{
			while(true)
			{
				Location location = t.location;

				if(hasVararg)
					throw new MDCompileException("No arguments may follow a vararg argument", location);

				params ~= Parameter.parse(t);

				if(params[$ - 1].mType.isVararg())
					hasVararg = true;

				if(hasDefault == false && params[$ - 1].mInitializer !is null)
					hasDefault = true;
				else if(hasDefault == true && params[$ - 1].mInitializer is null)
					throw new MDCompileException("Parameter '" ~ params[$ - 1].mName.toString() ~ "' expected to have an initializer", location);

				if(t.type == Token.Type.RParen)
					break;

				t.check(Token.Type.Comma);
				t = t.nextToken;
			}
		}
		
		t.check(Token.Type.RParen);
		t = t.nextToken;

		return params;
	}
	
	public void semantic2(Scope sc)
	{
		VarDecl v = new VarDecl(mType, mName, null, mLocation);
		v.semantic2(sc);
	}
	
	public char[] toString()
	{
		char[] ret = std.string.format("%s %s", mType, mName);

		return ret;
	}
}

Expression[] parseArgumentList(inout Token* t, Token.Type terminator)
{
	t = t.nextToken;

	Expression[] args;

	if(t.type != terminator)
	{
		while(true)
		{
			args ~= BaseAssignExp.parse(t);

			if(t.type == terminator)
				break;

			t.check(Token.Type.Comma);
			t = t.nextToken;
		}
	}

	t.check(terminator);
	t = t.nextToken;

	return args;
}

abstract class Expression
{
	protected Location mLocation;
	protected Type mSemType;

	public this(Location location)
	{
		mLocation = location;
	}
	
	public Expression semantic2(Scope sc)
	{
		return null;
	}

	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		Expression exp1;

		exp1 = BaseAssignExp.parse(t);

		return exp1;
	}
	
	/*public static Type checkConversion(Expression from, Expression to)
	{
		assert(from.mSemType !is null && to.mSemType !is null, "Need types to check conversion");

		Type t = Type.checkConversion(from.mSemType, to.mSemType);

		if(t is null)
			throw new MDTypeConvException(from, to);

		if(from.mSemType != t)


		//return t;
	}
	
	public static Type checkConvComm(Expression one, Expression two)
	{
		assert(one.mSemType !is null && two.mSemType !is null, "Need types to check conversion");
		
		Type t = Type.checkConversion(one.mSemType, two.mSemType);
		
		if(t is null)
			t = Type.checkConversion(two.mSemType, one.mSemType);

		if(t is null)
			throw new MDTypeConvException(one, two);

		return t;
	}*/
	
	public void checkRValue()
	{
		if(mSemType && mSemType.isVoid())
			throw new MDCompileException("Expression '" ~ toString() ~ "' has no value", mLocation);
	}
	
	public Expression toLValue()
	{
		throw new MDCompileException("'" ~ toString() ~ "' is not an LValue", mLocation);
	}

	public int toInt()
	{
		throw new MDCompileException("Integer literal expected, not '" ~ toString() ~ "'", mLocation);
	}

	public float toFloat()
	{
		throw new MDCompileException("Integer literal expected, not '" ~ toString() ~ "'", mLocation);
	}

	public void checkNumeric()
	{
		if(mSemType.isNumeric() == false)
			throw new MDCompileException("'" ~ toString() ~ "' is not of a numeric type", mLocation);
	}
	
	public void checkNoBool()
	{
		if(mSemType.isBool())
			throw new MDCompileException("Cannot perform operation on boolean expression '" ~ toString() ~ "'; only assignment and equality are allowed", mLocation);
	}

	public void checkInt()
	{
		if(mSemType.isInt() == false)
			throw new MDCompileException("'" ~ toString() ~ "' is not an integral type", mLocation);
	}
	
	public void checkArith()
	{
		checkNumeric();
		checkNoBool();
	}

	// TODO: overload checkSideEffect for expressions which can exist on their own (assignments, calls, &&, ||, delete, new, dot, assert)
	public void checkSideEffect()
	{
		throw new MDCompileException("Expression '" ~ toString() ~ "' doesn't do anything", mLocation);
	}
	
	public Expression checkToBoolean(Scope sc)
	{
		if(mSemType.checkToBoolean() == false)
			throw new MDCompileException("Expression '" ~ toString() ~ "' cannot be used as a boolean", mLocation);
			
		Expression ret = new CastExp(mLocation, BoolType.instance, this);
		ret = ret.semantic2(sc);

		return ret;
	}
	
	public Expression implicitConvTo(Type t, Scope sc)
	{
		Type.Conv c = mSemType.implicitConvTo(t);

		if(c == Type.Conv.No)
			throw new MDCompileException("Cannot implicitly convert expression '" ~ toString() ~ "' of type '" ~ mSemType.toString()
				~ "' to type '" ~ t.toString(), mLocation);
		else if(c == Type.Conv.Implicit)
		{
			Expression ret = new CastExp(mLocation, t, this);
			ret = ret.semantic2(sc);

			return ret;
		}
		else
			return this;
	}
	
	public Expression implicitConvTo(Expression other, Scope sc)
	{
		return implicitConvTo(other.mSemType, sc);
	}

	public bool isBool()
	{
		return false;
	}
}

class DeclExp : Expression
{
	protected SimpleDecl mDecl;

	public this(Location location, SimpleDecl decl)
	{
		super(location);
		mDecl = decl;
	}

	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mDecl.semantic2(sc);
		
		mSemType = VoidType.instance;
	
		return this;
	}

	public char[] toString()
	{
		return mDecl.toString();
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
	
	public void meshTypes()
	out
	{
		assert(mOp1.mSemType == mOp2.mSemType);
	}
	body
	{
		if(mOp1.mSemType != mOp2.mSemType)
		{
			Type t1 = mOp1.mSemType;
			Type t2 = mOp2.mSemType;

			if(t1.implicitConvTo(t2) == Type.Conv.Implicit)
			{
				mOp1 = new CastExp(mOp1.mLocation, t2, mOp1);
				return;
			}

			if(t2.implicitConvTo(t1) == Type.Conv.Implicit)
			{
				mOp2 = new CastExp(mOp2.mLocation, t1, mOp2);
				return;
			}
			
			throw new MDCompileException("Cannot implicitly convert expression '" ~ mOp1.toString() ~ "' of type '" ~ t1.toString()
				~ "' to type '" ~ t2.toString(), mLocation);
		}

		return;
	}
}

abstract class BaseAssignExp : BinaryExp
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
				case Token.Type.Assign:
					t = t.nextToken;
					exp2 = BaseAssignExp.parse(t);
					exp1 = new AssignExp(location, exp1, exp2);
					continue;

				case Token.Type.AddEq:
					t = t.nextToken;
					exp2 = BaseAssignExp.parse(t);
					exp1 = new AddEqExp(location, exp1, exp2);
					continue;

				case Token.Type.SubEq:
					t = t.nextToken;
					exp2 = BaseAssignExp.parse(t);
					exp1 = new SubEqExp(location, exp1, exp2);
					continue;

				case Token.Type.MulEq:
					t = t.nextToken;
					exp2 = BaseAssignExp.parse(t);
					exp1 = new MulEqExp(location, exp1, exp2);
					continue;

				case Token.Type.DivEq:
					t = t.nextToken;
					exp2 = BaseAssignExp.parse(t);
					exp1 = new DivEqExp(location, exp1, exp2);
					continue;

				case Token.Type.ModEq:
					t = t.nextToken;
					exp2 = BaseAssignExp.parse(t);
					exp1 = new ModEqExp(location, exp1, exp2);
					continue;

				case Token.Type.PowEq:
					t = t.nextToken;
					exp2 = BaseAssignExp.parse(t);
					exp1 = new PowEqExp(location, exp1, exp2);
					continue;

				case Token.Type.CatEq:
					t = t.nextToken;
					exp2 = BaseAssignExp.parse(t);
					exp1 = new CatEqExp(location, exp1, exp2);
					continue;

				default:
					break;
			}

			break;
		}
		
		return exp1;
	}
}

class AssignExp : BaseAssignExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}

	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		mOp2 = mOp2.implicitConvTo(mOp1, sc);
		mOp1 = mOp1.toLValue();
		mOp2.checkRValue();

		mSemType = mOp1.mSemType;

		return this;
	}

	public override Expression checkToBoolean(Scope sc)
	{
		throw new MDCompileException("Cannot use assignment '" ~ toString ~ "' as a boolean", mLocation);
	}

	public char[] toString()
	{
		return std.string.format("%s = %s", mOp1, mOp2);
	}
}

class AddEqExp : BaseAssignExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		mOp2 = mOp2.implicitConvTo(mOp1, sc);
		mOp1 = mOp1.toLValue();
		mOp1.checkRValue();
		mOp2.checkRValue();
		mOp1.checkArith();
		mOp2.checkArith();

		mSemType = mOp1.mSemType;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s += %s", mOp1, mOp2);
	}
}

class SubEqExp : BaseAssignExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		mOp2 = mOp2.implicitConvTo(mOp1, sc);
		mOp1 = mOp1.toLValue();
		mOp1.checkRValue();
		mOp2.checkRValue();
		mOp1.checkArith();
		mOp2.checkArith();

		mSemType = mOp1.mSemType;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s -= %s", mOp1, mOp2);
	}
}

class MulEqExp : BaseAssignExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		mOp2 = mOp2.implicitConvTo(mOp1, sc);
		mOp1 = mOp1.toLValue();
		mOp1.checkRValue();
		mOp2.checkRValue();
		mOp1.checkArith();
		mOp2.checkArith();

		mSemType = mOp1.mSemType;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s *= %s", mOp1, mOp2);
	}
}

class DivEqExp : BaseAssignExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}

	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		mOp2 = mOp2.implicitConvTo(mOp1, sc);
		mOp1 = mOp1.toLValue();
		mOp1.checkRValue();
		mOp2.checkRValue();
		mOp1.checkArith();
		mOp2.checkArith();

		mSemType = mOp1.mSemType;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s /= %s", mOp1, mOp2);
	}
}

class ModEqExp : BaseAssignExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}

	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		mOp2 = mOp2.implicitConvTo(mOp1, sc);
		mOp1 = mOp1.toLValue();
		mOp1.checkRValue();
		mOp2.checkRValue();
		mOp1.checkArith();
		mOp2.checkArith();

		mSemType = mOp1.mSemType;
		
		return this;
	}

	public char[] toString()
	{
		return std.string.format("%s %= %s", mOp1, mOp2);
	}
}

class PowEqExp : BaseAssignExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		mOp2 = mOp2.implicitConvTo(mOp1, sc);
		mOp1 = mOp1.toLValue();
		mOp1.checkRValue();
		mOp2.checkRValue();
		mOp1.checkArith();
		mOp2.checkArith();

		mSemType = mOp1.mSemType;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s ^= %s", mOp1, mOp2);
	}
}

class CatEqExp : BaseAssignExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		mOp2 = mOp2.implicitConvTo(mOp1, sc);
		mOp1 = mOp1.toLValue();
		mOp1.checkRValue();
		mOp2.checkRValue();

		if(mOp1.mSemType.isArray() == false)
			throw new MDCompileException("'~=' can only be used to concatenate arrays, not '" ~ mOp1.mSemType.toString() ~ "' and '" ~
				mOp2.mSemType.toString() ~ "'", mLocation);

		mSemType = mOp1.mSemType;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s ~= %s", mOp1, mOp2);
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
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);
		mOp1 = mOp1.checkToBoolean(sc);
		mOp2 = mOp2.checkToBoolean(sc);
		mOp1.checkRValue();
		mOp2.checkRValue();

		mSemType = BoolType.instance;
		
		return this;
	}

	public char[] toString()
	{
		return std.string.format("%s || %s", mOp1, mOp2);
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
		
		exp1 = BaseEqualExp.parse(t);
		
		while(t.type == Token.Type.AndAnd)
		{
			t = t.nextToken;

			exp2 = BaseEqualExp.parse(t);
			exp1 = new AndAndExp(location, exp1, exp2);

			location = t.location;
		}
		
		return exp1;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);
		mOp1 = mOp1.checkToBoolean(sc);
		mOp2 = mOp2.checkToBoolean(sc);
		mOp1.checkRValue();
		mOp2.checkRValue();

		mSemType = BoolType.instance;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s && %s", mOp1, mOp2);
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
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);
		
		meshTypes();

		mOp1.checkRValue();
		mOp2.checkRValue();

		mSemType = BoolType.instance;
		
		return this;
	}

	public char[] toString()
	{
		if(mIsTrue)
			return std.string.format("%s == %s", mOp1, mOp2);
		else
			return std.string.format("%s != %s", mOp1, mOp2);
	}
}

class IsExp : BaseEqualExp
{
	public this(bool isTrue, Location location, Expression left, Expression right)
	{
		super(isTrue, location, left, right);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		meshTypes();

		// rewrite "op1 is op2" as "op1 == op2" for non-reference types
		if(mOp1.mSemType.isReference() == false)
		{
			Expression e = new EqualExp(mIsTrue, mLocation, mOp1, mOp2);
			e.semantic2(sc);
			return e;
		}

		mOp1.checkRValue();
		mOp2.checkRValue();

		mSemType = BoolType.instance;
		
		return this;
	}

	public char[] toString()
	{
		if(mIsTrue)
			return std.string.format("%s is %s", mOp1, mOp2);
		else
			return std.string.format("%s !is %s", mOp1, mOp2);
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
		
		exp1 = BaseAddExp.parse(t);
		
		while(true)
		{
			Token.Type type = t.type;

			switch(type)
			{
				case Token.Type.LT, Token.Type.LE, Token.Type.GT, Token.Type.GE:
					t = t.nextToken;
					exp2 = BaseAddExp.parse(t);
					exp1 = new CmpExp(type, location, exp1, exp2);
					continue;

				default:
					break;
			}
			
			break;
		}
		
		return exp1;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		meshTypes();

		if(mOp1.mSemType.canBeCompared(mOp2.mSemType) == false)
			throw new MDCompileException("Comparison is undefined for '" ~ mOp1.mSemType.toString() ~ "'", mLocation);

		mOp1.checkRValue();
		mOp2.checkRValue();

		mSemType = BoolType.instance;
		
		return this;
	}

	public char[] toString()
	{
		switch(mType)
		{
			case Type.Less: return std.string.format("%s < %s", mOp1, mOp2);
			case Type.LessEq: return std.string.format("%s <= %s", mOp1, mOp2);
			case Type.Greater: return std.string.format("%s > %s", mOp1, mOp2);
			case Type.GreaterEq: return std.string.format("%s >= %s", mOp1, mOp2);
		}
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
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		meshTypes();

		mOp1.checkRValue();
		mOp2.checkRValue();
		mOp1.checkArith();
		mOp2.checkArith();

		mSemType = mOp1.mSemType;
		
		return this;
	}

	public char[] toString()
	{
		return std.string.format("%s + %s", mOp1, mOp2);
	}
}

class SubExp : BaseAddExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		meshTypes();

		mOp1.checkRValue();
		mOp2.checkRValue();
		mOp1.checkArith();
		mOp2.checkArith();

		mSemType = mOp1.mSemType;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s - %s", mOp1, mOp2);
	}
}

class CatExp : BaseAddExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		meshTypes();
		
		if(mOp1.mSemType.isArray() == false)
			throw new MDCompileException("'~' can only be used to concatenate arrays, not '" ~ mOp1.mSemType.toString() ~ "' and '" ~
				mOp2.mSemType.toString() ~ "'", mLocation);

		mOp1.checkRValue();
		mOp2.checkRValue();

		mSemType = mOp1.mSemType;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s ~ %s", mOp1, mOp2);
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
		
		exp1 = PowerExp.parse(t);

		while(true)
		{
			switch(t.type)
			{
				case Token.Type.Mul:
					t = t.nextToken;
					exp2 = PowerExp.parse(t);
					exp1 = new MulExp(location, exp1, exp2);
					continue;
					
				case Token.Type.Div:
					t = t.nextToken;
					exp2 = PowerExp.parse(t);
					exp1 = new DivExp(location, exp1, exp2);
					continue;
					
				case Token.Type.Mod:
					t = t.nextToken;
					exp2 = PowerExp.parse(t);
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
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		meshTypes();

		mOp1.checkRValue();
		mOp2.checkRValue();
		mOp1.checkArith();
		mOp2.checkArith();

		mSemType = mOp1.mSemType;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s * %s", mOp1, mOp2);
	}
}

class DivExp : BaseMulExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		meshTypes();

		mOp1.checkRValue();
		mOp2.checkRValue();
		mOp1.checkArith();
		mOp2.checkArith();

		mSemType = mOp1.mSemType;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s / %s", mOp1, mOp2);
	}
}

class ModExp : BaseMulExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		meshTypes();

		mOp1.checkRValue();
		mOp2.checkRValue();
		mOp1.checkArith();
		mOp2.checkArith();

		mSemType = mOp1.mSemType;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s % %s", mOp1, mOp2);
	}
}

class PowerExp : BinaryExp
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

		while(t.type == Token.Type.Pow)
		{
			t = t.nextToken;

			exp2 = UnaryExp.parse(t);
			exp1 = new PowerExp(location, exp1, exp2);

			location = t.location;
		}

		return exp1;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);

		meshTypes();

		mOp1.checkRValue();
		mOp2.checkRValue();
		mOp1.checkArith();
		mOp2.checkArith();

		mSemType = mOp1.mSemType;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s ^ %s", mOp1, mOp2);
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
				
			case Token.Type.Delete:
				t = t.nextToken;
				exp = UnaryExp.parse(t);
				exp = new DeleteExp(location, exp);
				break;
				
			case Token.Type.New:
				exp = BaseNewExp.parse(t);
				break;
				
			case Token.Type.Closure:
				t = t.nextToken;
				
				if(t.type == Token.Type.Ident)
					exp = new ClosureExp(location, IdentExp.parse(t));
				else
					exp = new ClosureLiteralExp(location, FuncLiteralExp.parse(t));
				break;

			case Token.Type.LParen:
				t = t.nextToken;
				exp = Expression.parse(t);
				
				t.check(Token.Type.RParen);
				t = t.nextToken;

				exp = PostfixExp.parse(t, exp);
				break;
				
			case Token.Type.Cast:
				t = t.nextToken;
				t.check(Token.Type.LParen);
				t = t.nextToken;
				
				Type type = Type.parse(t);
				
				t.check(Token.Type.RParen);
				t = t.nextToken;
				
				exp = UnaryExp.parse(t);
				exp = new CastExp(location, type, exp);
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
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp = mOp.semantic2(sc);

		mOp.checkRValue();
		mOp.checkArith();

		IntExp ie = cast(IntExp)mOp;

		if(ie)
		{
			ie.mValue = -ie.mValue;
			return ie;
		}
		
		FloatExp fe = cast(FloatExp)mOp;

		if(fe)
		{
			fe.mValue = -fe.mValue;
			return fe;
		}

		mSemType = mOp.mSemType;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("-%s", mOp);
	}
}

class NotExp : UnaryExp
{
	public this(Location location, Expression operand)
	{
		super(location, operand);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp = mOp.semantic2(sc);

		mOp.checkRValue();
		mOp = mOp.checkToBoolean(sc);
		
		BoolExp be = cast(BoolExp)mOp;
		
		if(be)
		{
			be.mValue = !be.mValue;
			return be;
		}

		mSemType = BoolType.instance;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("!%s", mOp);
	}
}

class DeleteExp : UnaryExp
{
	public this(Location location, Expression operand)
	{
		super(location, operand);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp = mOp.semantic2(sc);

		if(mOp.mSemType.isReference() == false)
			throw new MDCompileException("'delete' can only be used on reference types, not on '" ~ mOp.mSemType.toString() ~ "'", mLocation);

		mOp.checkRValue();

		mSemType = VoidType.instance;
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("delete %s", mOp);
	}
}

abstract class BaseNewExp : Expression
{
	public this(Location location)
	{
		super(location);
	}
	
	public static Expression parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.New);
		t = t.nextToken;

		Type type = Type.parse(t);

		Expression[] args;

		if(t.type == Token.Type.LParen)
			args = parseArgumentList(t, Token.Type.RParen);

		if(type.isArray())
		{
			if(args.length != 1)
				throw new MDCompileException("There must be exactly one parameter when newing an array type", location);

			return new NewArrayExp(location, type, args[0]);
		}

		return new NewClassExp(location, type, args);
	}
}

class NewArrayExp : BaseNewExp
{
	protected Type mNewType;
	protected Expression mArg;

	public this(Location location, Type type, Expression arg)
	{
		super(location);
		
		mNewType = type;
		mArg = arg;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mArg = mArg.semantic2(sc);
		mArg.checkInt();
		mArg.checkRValue();

		mNewType = mNewType.semantic2(mLocation, sc);

		mSemType = mNewType;

		return this;
	}

	public char[] toString()
	{
		return std.string.format("new %s(%s)", mNewType, mArg);
	}
}

class NewClassExp : BaseNewExp
{
	protected Type mNewType;
	protected Expression[] mArgs;
	
	public this(Location location, Type type, Expression[] args)
	{
		super(location);
		
		mNewType = type;
		mArgs = args;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		// TODO: This is like a callexp..

		mNewType = mNewType.semantic2(mLocation, sc);

		mSemType = mNewType;

		return this;
	}
	
	public char[] toString()
	{
		char[] ret = std.string.format("new %s(", mNewType);

		if(mArgs.length == 1)
			ret = std.string.format("%s%s", ret, mArgs[0]);
		else
		{
			foreach(uint i, Expression a; mArgs)
			{
				if(i == mArgs.length - 1)
					ret = std.string.format("%s%s", ret, a);
				else
					ret = std.string.format("%s%s, ", ret, a);
			}
		}
		
		ret ~= ")";
		
		return ret;
	}
}

class CastExp : UnaryExp
{
	protected Type mType;

	public this(Location location, Type type, Expression operand)
	{
		super(location, operand);
		mType = type;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mType = mType.semantic2(mLocation, sc);
		
		if(mOp.mSemType.explicitConvTo(mType) != Type.Conv.Exact)
			throw new MDCompileException("Cannot cast expression '" ~ mOp.toString() ~ "' of type '" ~ mOp.mSemType.toString()
				~ "' to type '" ~ mType.toString(), mLocation);

		return this;
	}

	public char[] toString()
	{
		return std.string.format("cast(%s)%s", mType, mOp);
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
					
					if(t.type == Token.Type.Ident)
						exp = new DotExp(location, exp, new IdentExp(t.location, Identifier.parse(t)));
					else if(t.type == Token.Type.LParen)
					{
						t = t.nextToken;
				
						Type[] types;
	
						if(t.type != Token.Type.RParen)
						{
							while(true)
							{
								types ~= Type.parse(t);
				
								if(t.type == Token.Type.RParen)
									break;
				
								t.check(Token.Type.Comma);
								t = t.nextToken;
							}
						}
				
						t = t.nextToken;
	
						exp = new OverloadResolveExp(location, exp, types);
					}
					else
						throw new MDCompileException("Identifier expected after '.', not '" ~ t.toString() ~ "'", t.location);

					continue;

				case Token.Type.LParen:
					exp = new CallExp(location, exp, parseArgumentList(t, Token.Type.RParen));
					continue;

				case Token.Type.LBracket:
					t = t.nextToken;
					
					if(t.type == Token.Type.RBracket)
					{
						exp = new SliceExp(location, exp);
						t = t.nextToken;
					}
					else
					{
						Expression index = BaseAssignExp.parse(t);
						
						if(t.type == Token.Type.DotDot)
						{
							t = t.nextToken;
							exp = new SliceExp(location, exp, index, BaseAssignExp.parse(t));
						}
						else
						{
							Expression[] args;
							args ~= index;

							if(t.type == Token.Type.Comma)
							{
								t = t.nextToken;

								while(true)
								{
									args ~= BaseAssignExp.parse(t);
	
									if(t.type == Token.Type.RBracket)
										break;
	
									t.check(Token.Type.Comma);
									t = t.nextToken;
								}
							}

							t.check(Token.Type.RBracket);
							t = t.nextToken;

							exp = new IndexExp(location, exp, args);
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

	public this(Location location, Expression operand, IdentExp ident)
	{
		super(location, operand);
		
		mIdent = ident;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp = mOp.semantic2(sc);
		
		Expression e = this;

		if(mOp.mSemType.isReference())
		{
			e = new ObjMemberRef(mLocation, mOp, mIdent);
			e.semantic2(sc);
		}
		// TODO: else if op.semtype == namespace..

		return this;
	}

	public char[] toString()
	{
		return std.string.format("%s.%s", mOp, mIdent);
	}
}

class ObjMemberRef : BinaryExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp1 = mOp1.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);
		
		assert(mOp1.mSemType.isReference(), "ObjMemberRef should ALWAYS be a ref type");
		
		// TODO: lookup member in class.
		// see if it's a field, a method, or a namespace.
		// convert to appropriate expression for each.

		return this;
	}

	public char[] toString()
	{
		return std.string.format("%s.%s", mOp1, mOp2);
	}
}

class ObjFieldRef : BinaryExp
{
	public this(Location location, Expression left, Expression right)
	{
		super(location, left, right);
	}

	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;
			
		mOp1 = mOp2.semantic2(sc);
		mOp2 = mOp2.semantic2(sc);
		
		assert(mOp1.mSemType.isReference(), "ObjMethodRef should ALWAYS be a ref type");

		return this;
	}

	public char[] toString()
	{
		return std.string.format("%s.%s", mOp1, mOp2);
	}
}

class ModNamespaceRef : PrimaryExp
{
	protected NamespaceDecl mNamespace;

	public this(Location location, NamespaceDecl decl)
	{
		super(location);
		
		mNamespace = decl;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;
			
		

		return this;
	}
}

class OverloadResolveExp : PostfixExp
{
	protected Type[] mTypes;
	
	public this(Location location, Expression operand, Type[] types)
	{
		super(location, operand);
		
		mTypes = types;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp = mOp.semantic2(sc);
		
		return this;
	}
	
	public char[] toString()
	{
		return "overload resolve";
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
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp = mOp.semantic2(sc);
		
		// TODO: check args

		return this;
	}

	public char[] toString()
	{
		char[] ret = std.string.format("%s(", mOp);
		
		if(mArgs.length == 0)
			ret ~= ")";
		else if(mArgs.length == 1)
			ret = std.string.format("%s%s)", ret, mArgs[0]);
		else
		{
			foreach(uint i, Expression a; mArgs)
			{
				if(i == mArgs.length - 1)
					ret = std.string.format("%s%s)", ret, a);
				else
					ret = std.string.format("%s%s, ", ret, a);
			}
		}

		return ret;
	}
}

class IndexExp : PostfixExp
{
	protected Expression[] mArgs;

	public this(Location location, Expression operand, Expression[] args)
	{
		super(location, operand);
		
		mArgs = args;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp = mOp.semantic2(sc);
		
		// TODO: like callexp

		return this;
	}
	
	public char[] toString()
	{
		char[] ret = std.string.format("%s[", mOp);
		
		if(mArgs.length == 0)
			ret ~= "]";
		else if(mArgs.length == 1)
			ret = std.string.format("%s%s]", ret, mArgs[0]);
		else
		{
			foreach(uint i, Expression a; mArgs)
			{
				if(i == mArgs.length - 1)
					ret = std.string.format("%s%s]", ret, a);
				else
					ret = std.string.format("%s%s, ", ret, a);
			}
		}

		return ret;
	}
}

class SliceExp : PostfixExp
{
	protected Expression mLow;
	protected Expression mHigh;
	
	public this(Location location, Expression operand, Expression low = null, Expression high = null)
	{
		super(location, operand);

		mLow = low;
		mHigh = high;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mOp = mOp.semantic2(sc);
		
		mLow = mLow.semantic2(sc);
		mHigh = mHigh.semantic2(sc);
		
		return this;
	}
	
	public char[] toString()
	{
		return std.string.format("%s[%s .. %s]", mOp, mLow, mHigh);
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
				
			case Token.Type.BoolLiteral:
				exp = BoolExp.parse(t);
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
				
			case Token.Type.CharLiteral:
				exp = CharExp.parse(t);
				break;

			case Token.Type.Function:
				exp = FuncLiteralExp.parse(t);
				break;
				
			case Token.Type.This:
				exp = ThisExp.parse(t);
				break;

			case Token.Type.Assert:
				exp = AssertExp.parse(t);
				break;

			default:
				throw new MDCompileException("Expression expected, not '" ~ t.toString() ~ "'", location);
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
	
	public char[] toString()
	{
		return mIdent.toString();
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
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		// TODO: Just leave mSemType null to indicate null?

		return this;
	}
	
	public char[] toString()
	{
		return "null";
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

	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mSemType = BoolType.instance;

		return this;
	}

	public static BoolExp parse(inout Token* t)
	{
		t.check(Token.Type.BoolLiteral);

		scope(success)
			t = t.nextToken;

		return new BoolExp(t.location, t.boolValue);
	}
	
	public char[] toString()
	{
		if(mValue == true)
			return "true";
		else
			return "false";
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
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mSemType = IntType.instance;

		return this;
	}

	public static IntExp parse(inout Token* t)
	{
		t.check(Token.Type.IntLiteral);

		scope(success)
			t = t.nextToken;

		return new IntExp(t.location, t.intValue);
	}
	
	public char[] toString()
	{
		return std.string.toString(mValue);
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
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mSemType = FloatType.instance;

		return this;
	}

	public static FloatExp parse(inout Token* t)
	{
		t.check(Token.Type.FloatLiteral);

		scope(success)
			t = t.nextToken;

		return new FloatExp(t.location, t.floatValue);
	}
	
	public char[] toString()
	{
		return std.string.toString(mValue);
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
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mSemType = ArrayType.stringInstance;

		return this;
	}
	
	public static StringExp parse(inout Token* t)
	{
		t.check(Token.Type.StringLiteral);

		scope(success)
			t = t.nextToken;

		return new StringExp(t.location, t.stringValue);
	}
	
	public char[] toString()
	{
		return '\"' ~ mValue ~ '\"';
	}
}

class CharExp : PrimaryExp
{
	protected char mValue;
	
	public this(Location location, char value)
	{
		super(location);
		
		mValue = value;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mSemType = CharType.instance;

		return this;
	}
	
	public static CharExp parse(inout Token* t)
	{
		t.check(Token.Type.CharLiteral);

		scope(success)
			t = t.nextToken;

		return new CharExp(t.location, t.stringValue[0]);
	}
	
	public char[] toString()
	{
		return "\'" ~ mValue ~ "\'";
	}
}

class FuncLiteralExp : PrimaryExp
{
	protected FuncLiteralDecl mDecl;
	
	public this(Location location, FuncLiteralDecl decl)
	{
		super(location);

		mDecl = decl;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		// semantic1 never happens for func literals.. so we have to do it here
		mDecl.semantic1(sc);

		mDecl.semantic2(sc);

		mSemType = mDecl.mFuncType;

		return this;
	}
	
	public static FuncLiteralExp parse(inout Token* t)
	{
		return new FuncLiteralExp(t.location, FuncLiteralDecl.parse(t));
	}
	
	public char[] toString()
	{
		return mDecl.toString();
	}
}

class ClosureExp : PrimaryExp
{
	protected IdentExp mName;
	
	public this(Location location, IdentExp name)
	{
		super(location);
		
		mName = name;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		// TODO: lookup symbol, see if it's a nested function (inside this or sibling)

		return this;
	}

	public char[] toString()
	{
		return std.string.format("closure %s", mName.toString());
	}
}

class ClosureLiteralExp : PrimaryExp
{
	protected FuncLiteralExp mDecl;
	
	public this(Location location, FuncLiteralExp decl)
	{
		super(location);

		mDecl = decl;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		mDecl.semantic2(sc);
		mSemType = mDecl.mSemType;

		return this;
	}

	public char[] toString()
	{
		return std.string.format("closure %s", mDecl.toString());
	}
}

class ThisExp : PrimaryExp
{
	protected ThisDecl mDecl;

	public this(Location location)
	{
		super(location);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		// TODO: find the "this" declaration for the enclosing function
		// if there is none, it's an error

		return this;
	}

	public static ThisExp parse(inout Token* t)
	{
		t.check(Token.Type.This);

		scope(success)
			t = t.nextToken;

		return new ThisExp(t.location);
	}
	
	public char[] toString()
	{
		return "this";
	}
}

class SuperExp : PrimaryExp
{
	public this(Location location)
	{
		super(location);
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;

		// TODO: set semtype to be of base class type

		return this;
	}

	public static SuperExp parse(inout Token* t)
	{
		t.check(Token.Type.Super);

		scope(success)
			t = t.nextToken;

		return new SuperExp(t.location);
	}
	
	public char[] toString()
	{
		return "super";
	}
}

class AssertExp : PrimaryExp
{
	protected Expression mExpr;
	protected char[] mMsg;

	public this(Location location, Expression expr, char[] msg)
	{
		super(location);
		
		mExpr = expr;
		mMsg = msg;
	}
	
	public override Expression semantic2(Scope sc)
	{
		if(mSemType !is null)
			return this;
			
		// Optimize out asserts which are always true?
		
		mExpr = mExpr.semantic2(sc);

		mSemType = VoidType.instance;

		return this;
	}
	
	public static AssertExp parse(inout Token* t)
	{
		Location location = t.location;

		t.check(Token.Type.Assert);
		t = t.nextToken;
		t.check(Token.Type.LParen);
		t = t.nextToken;

		AssertExp ret;
		Expression exp = BaseAssignExp.parse(t);

		if(t.type == Token.Type.RParen)
			ret = new AssertExp(location, exp, "");
		else if(t.type == Token.Type.Comma)
		{
			t = t.nextToken;
			t.check(Token.Type.StringLiteral);
			ret = new AssertExp(location, exp, t.stringValue);
			t = t.nextToken;
		}

		t.check(Token.Type.RParen);
		t = t.nextToken;
		
		return ret;
	}
	
	public char[] toString()
	{
		char[] ret = std.string.format("assert(%s", mExpr);
		
		if(mMsg.length == 0)
			return ret ~ ")";
		else
			return std.string.format("%s, \"%s\")", mMsg);
	}
}

abstract class Statement
{
	protected Location mLocation;
	protected Scope mChild;

	public this(Location location)
	{
		mLocation = location;
	}
	
	enum Flags
	{
		Compound = 1,
		BraceScope = 2,
		NewScope = 4
	}

	public static Statement parse(inout Token* t, uint flags)
	{
		Location location = t.location;
		
		bool needCompound = cast(bool)(flags & Flags.Compound);
		bool createScope = cast(bool)(flags & Flags.NewScope);
		bool braceScope = cast(bool)(flags & Flags.BraceScope);

		if(needCompound)
			t.check(Token.Type.LBrace);

		switch(t.type)
		{
			case
				Token.Type.Assert,
				Token.Type.Dec,
				Token.Type.Delete,
				Token.Type.False,
				Token.Type.FloatLiteral,
				Token.Type.Ident,
				Token.Type.Inc,
				Token.Type.IntLiteral,
				Token.Type.LParen,
				Token.Type.New,
				Token.Type.Null,
				Token.Type.StringLiteral,
				Token.Type.Sub,
				Token.Type.True:

				return ExpressionStatement.parse(t);

			case Token.Type.Def:
				Statement s = DeclarationStatement.parse(t);

				if(createScope)
					s = new ScopeStatement(location, s);

				return s;

			case Token.Type.LBrace:
				Statement s = CompoundStatement.parse(t);

				if(createScope || braceScope)
					s = new ScopeStatement(location, s);

				return s;
				
			case Token.Type.While:
				return WhileStatement.parse(t);
				
			case Token.Type.Do:
				return DoWhileStatement.parse(t);
				
			case Token.Type.For:
				return ForStatement.parse(t);
				
			case Token.Type.Foreach:
				return ForeachStatement.parse(t);

			case Token.Type.If:
				return IfStatement.parse(t);
				
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
				
			case Token.Type.Semicolon:
				throw new MDCompileException("Empty statements ( ';' ) are not allowed", t.location);
				
			case
				Token.Type.Bool,
				Token.Type.Float,
				Token.Type.Int,
				Token.Type.Char,
				Token.Type.Void:
				
				throw new MDCompileException("If you're trying to define a variable or function, use 'def'", t.location);

			default:
				throw new MDCompileException("Statement expected, not '" ~ t.toString() ~ "'", t.location);
		}
	}
	
	public void semantic1(Scope sc)
	{

	}
	
	public void semantic2(Scope s)
	{
		
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

		Statement[] statements;
		int i = 0;

		void addStatement(Statement s)
		{
			if(statements.length == 0)
				statements.length = 10;
			else if(i >= statements.length)
				statements.length = statements.length * 2;

			statements[i] = s;
			i++;
		}

		while(t.type != Token.Type.RBrace)
			addStatement(Statement.parse(t, Flags.BraceScope));
			
		statements.length = i;

		t.check(Token.Type.RBrace);
		t = t.nextToken;
		
		return new CompoundStatement(location, statements);
	}
	
	protected override void semantic1(Scope sc)
	{
		foreach(Statement s; mStatements)
			s.semantic1(sc);
	}
	
	protected override void semantic2(Scope sc)
	{
		foreach(Statement s; mStatements)
			s.semantic2(sc);
	}

	public char[] toString()
	{
		return "compound statement";
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
	
	protected override void semantic1(Scope sc)
	{
		mChild = sc.push();

		mStatement.semantic1(mChild);

		mChild.pop();
	}
	
	protected override void semantic2(Scope sc)
	{
		mStatement.semantic2(mChild);
	}

	public char[] toString()
	{
		return mStatement.toString();
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
	
	public override void semantic2(Scope sc)
	{
		mExpr.semantic2(sc);
		//mExpr.
	}

	public static ExpressionStatement parse(inout Token* t)
	{
		Expression expr = Expression.parse(t);

		t.check(Token.Type.Semicolon);
		t = t.nextToken;

		return new ExpressionStatement(t.location, expr);
	}

	public char[] toString()
	{
		return mExpr.toString() ~ ";";
	}
}

class DeclarationStatement : ExpressionStatement
{
	protected DeclExp mDeclExp;

	public this(Location location, DeclExp declExp)
	{
		super(location, declExp);
		mDeclExp = declExp;
	}

	public static DeclarationStatement parse(inout Token* t)
	{
		Location location = t.location;

		DeclExp declExp = new DeclExp(location, SimpleDecl.parse(t));

		return new DeclarationStatement(location, declExp);
	}
	
	protected override void semantic1(Scope sc)
	{
		mDeclExp.mDecl.semantic1(sc);
	}
	
	protected override void semantic2(Scope sc)
	{
		mDeclExp.mDecl.semantic2(sc);
	}

	public char[] toString()
	{
		return mDeclExp.toString();
	}
}

class IfStatement : Statement
{
	protected Expression mCondition;
	protected Statement mIfBody;
	protected Statement mElseBody;
	protected Scope mElseScope;

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

		Expression condition = Expression.parse(t);

		t.check(Token.Type.RParen);
		t = t.nextToken;

		Statement ifBody = Statement.parse(t, Flags.NewScope);

		Statement elseBody;

		if(t.type == Token.Type.Else)
		{
			t = t.nextToken;
			elseBody = Statement.parse(t, Flags.NewScope);
		}

		return new IfStatement(location, condition, ifBody, elseBody);
	}
	
	protected override void semantic1(Scope sc)
	{
		mChild = sc.push();
		mIfBody.semantic1(mChild);
		mChild.pop();

		if(mElseBody)
		{
			mElseScope = sc.push();
			mElseBody.semantic1(mElseScope);
			mElseScope.pop();
		}
	}
	
	protected override void semantic2(Scope sc)
	{
		mCondition.semantic2( sc);
		
		mIfBody.semantic2(mChild);
		mElseBody.semantic2(mElseScope);
	}

	public char[] toString()
	{
		char[] ret = std.string.format("if(%s) %s", mCondition, mIfBody);
		
		if(mElseBody !is null)
			ret = std.string.format("%s else %s", ret, mElseBody);
		
		return ret;
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
		
		Expression condition = Expression.parse(t);

		t.check(Token.Type.RParen);
		t = t.nextToken;
		
		Statement whileBody = Statement.parse(t, Flags.NewScope);

		return new WhileStatement(location, condition, whileBody);
	}
	
	protected override void semantic1(Scope sc)
	{
		mChild = sc.push();
		mChild.mBreakableStat = this;
		mChild.mContinuableStat = this;
		mBody.semantic1(mChild);
		mChild.pop();
	}
	
	protected override void semantic2(Scope sc)
	{
		mCondition.semantic2( sc);
		mBody.semantic2(mChild);
	}

	public char[] toString()
	{
		return std.string.format("while(%s) %s", mCondition, mBody);
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
		
		Statement doBody = Statement.parse(t, Flags.NewScope);
		
		t.check(Token.Type.While);
		t = t.nextToken;
		t.check(Token.Type.LParen);
		t = t.nextToken;

		Expression condition = Expression.parse(t);
		
		t.check(Token.Type.RParen);
		t = t.nextToken;

		return new DoWhileStatement(location, doBody, condition);
	}
	
	protected override void semantic1(Scope sc)
	{
		mChild = sc.push();
		mChild.mBreakableStat = this;
		mChild.mContinuableStat = this;
		mBody.semantic1(mChild);
		mChild.pop();
	}
	
	protected override void semantic2(Scope sc)
	{
		mBody.semantic2(mChild);
		
		// Using mChild as the scope for the condition allows constructions like:
		/*
			do
			{
				int x = func();
				...
			} while(x != 0)
		*/
		mCondition.semantic2(mChild);
	}
	
	public char[] toString()
	{
		return std.string.format("do %s while(%s)", mBody, mCondition);
	}
}

class ForStatement : Statement
{
	protected Expression mInit;
	protected Expression mCondition;
	protected Expression mIncrement;
	protected Statement mBody;

	public this(Location location, Expression init, Expression condition, Expression increment, Statement forBody)
	{
		super(location);
		mInit = init;
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
		
		if(t.type == Token.Type.Semicolon)
			t = t.nextToken;
		else
		{
			if(t.type == Token.Type.Def)
				init = new DeclExp(t.location, VarDecl.parse(t, false));
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
			condition = Expression.parse(t);
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
		
		Statement forBody = Statement.parse(t, 0);

		return new ForStatement(location, init, condition, increment, forBody);
	}
	
	protected override void semantic1(Scope sc)
	{
		mChild = sc.push();
		mChild.mBreakableStat = this;
		mChild.mContinuableStat = this;
		mBody.semantic1(mChild);
		mChild.pop();
	}
	
	protected override void semantic2(Scope sc)
	{
		if(mInit !is null)
			mInit.semantic2(mChild);
			
		if(mCondition !is null)
			mCondition.semantic2(mChild);
			
		if(mIncrement !is null)
			mIncrement.semantic2(mChild);
			
		mBody.semantic2(mChild);
	}
	
	public char[] toString()
	{
		char[] ret = "for(";

		if(mInit !is null)
			ret ~= mInit.toString();
			
		ret ~= "; ";

		if(mCondition !is null)
			ret ~= mCondition.toString();
			
		ret ~= "; ";
		
		if(mIncrement !is null)
			ret ~= mIncrement.toString();
			
		return std.string.format("%s) %s", ret, mBody);
	}
}

class ForeachStatement : Statement
{
	protected Parameter[] mIndices;
	protected Expression mContainer;
	protected CompoundStatement mBody;
	protected FuncLiteralDecl mFunc;

	public this(Location location, Parameter[] indices, Expression container, CompoundStatement foreachBody)
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

		Parameter[] indices;

		if(t.type == Token.Type.Semicolon)
			throw new MDCompileException("Foreach loop has no indices", location);
			
		while(t.type != Token.Type.Semicolon)
		{
			Location location2 = t.location;

			Type type = Type.parse(t);
			Identifier ident = Identifier.parse(t);

			indices ~= new Parameter(type, ident, null, location2);

			if(t.type == Token.Type.Comma)
				t = t.nextToken;
		}
		
		t.check(Token.Type.Semicolon);
		t = t.nextToken;

		Expression container = Expression.parse(t);

		t.check(Token.Type.RParen);
		t = t.nextToken;
		
		Statement foreachBody = Statement.parse(t, 0);
		if(cast(CompoundStatement)foreachBody is null)
			foreachBody = new CompoundStatement(foreachBody.mLocation, foreachBody);

		return new ForeachStatement(location, indices, container, cast(CompoundStatement)foreachBody);
	}
	
	protected override void semantic1(Scope sc)
	{
		mChild = sc.push();
		mChild.mForeach = this;
		//mBody.semantic1(mChild);
		mChild.pop();
	}
	
	protected override void semantic2(Scope sc)
	{
		foreach(Parameter exp; mIndices)
			exp.semantic2(mChild);

		mContainer.semantic2(mChild);

		mBody.semantic2(mChild);
	}

	public char[] toString()
	{
		char[] ret = "foreach(";

		if(mIndices.length == 1)
			ret = std.string.format("%s%s; ", ret, mIndices[0].toString());
		else
		{
			foreach(uint i, Parameter index; mIndices)
			{
				if(i != mIndices.length - 1)
					ret = std.string.format("%s%s, ", ret, index.toString());
				else
					ret = std.string.format("%s%s; ", ret, index.toString());
			}
		}

		return std.string.format("%s %s) %s", ret, mContainer, mBody);
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
		
		Expression condition = Expression.parse(t);
		
		t.check(Token.Type.RParen);
		t = t.nextToken;
		t.check(Token.Type.LBrace);
		t = t.nextToken;

		Statement[] cases;
		int i = 0;

		void addCase(Statement c)
		{
			if(cases.length == 0)
				cases.length = 10;
			else if(i >= cases.length)
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
	
	protected override void semantic1(Scope sc)
	{
		mChild = sc.push();

		mChild.mBreakableStat = this;

		foreach(Statement s; mCases)
			s.semantic1(mChild);

		if(mDefault)
			mDefault.semantic1(mChild);
			
		mChild.pop();
	}
	
	protected override void semantic2(Scope sc)
	{
		foreach(Statement s; mCases)
			s.semantic2(mChild);
			
		if(mDefault)
			mDefault.semantic2(mChild);
	}
	
	public char[] toString()
	{
		char[] ret = std.string.format("switch(%s) {\n", mCondition);

		foreach(Statement c; mCases)
			ret = std.string.format("%s%s", ret, c);

		if(mDefault !is null)
			ret = std.string.format("%s%s", ret, mDefault);
	
		ret ~= "}";
		
		return ret;
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

		Expression[] cases;
		int i = 0;

		void addCase(Expression c)
		{
			if(cases.length == 0)
				cases.length = 10;
			else if(i >= cases.length)
				cases.length = cases.length * 2;

			cases[i] = c;
			i++;
		}

		while(true)
		{
			addCase(BaseAssignExp.parse(t));
			
			if(t.type != Token.Type.Comma)
				break;
				
			t = t.nextToken;
		}

		cases.length = i;

		assert(cases.length > 0);
		
		t.check(Token.Type.Colon);
		t = t.nextToken;

		Statement[] statements;
		i = 0;

		void addStatement(Statement s)
		{
			if(statements.length == 0)
				statements.length = 10;
			else if(i >= statements.length)
				statements.length = statements.length * 2;

			statements[i] = s;
			i++;
		}

		while(t.type != Token.Type.Case && t.type != Token.Type.Default && t.type != Token.Type.RBrace)
			addStatement(Statement.parse(t, Statement.Flags.BraceScope));
			
		statements.length = i;
		
		Statement caseBody = new CompoundStatement(location, statements);
		caseBody = new ScopeStatement(location, caseBody);

		CaseStatement ret;

		for(i = cases.length - 1; i >= 0; i--)
			ret = new CaseStatement(location, cases[i], caseBody);
		
		return ret;
	}
	
	protected override void semantic1(Scope sc)
	{
		mBody.semantic1(sc);
	}
	
	protected override void semantic2(Scope sc)
	{
		mBody.semantic2(sc);
	}
	
	public char[] toString()
	{
		return std.string.format("case %s: %s", mCondition, mBody);
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
		
		Statement[] statements;
		int i = 0;

		void addStatement(Statement s)
		{
			if(statements.length == 0)
				statements.length = 10;
			else if(i >= statements.length)
				statements.length = statements.length * 2;

			statements[i] = s;
			i++;
		}

		while(t.type != Token.Type.Case && t.type != Token.Type.Default && t.type != Token.Type.RBrace)
			addStatement(Statement.parse(t, Statement.Flags.BraceScope));
			
		statements.length = i;

		Statement defaultBody = new CompoundStatement(location, statements);
		defaultBody = new ScopeStatement(location, defaultBody);
		return new DefaultStatement(location, defaultBody);
	}
	
	public override void semantic1(Scope sc)
	{
		mBody.semantic1(sc);	
	}
	
	public override void semantic2(Scope sc)
	{
		mBody.semantic2(sc);
	}

	public char[] toString()
	{
		return std.string.format("default: %s", mBody);
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
	
	public char[] toString()
	{
		return "continue;";
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
	
	public char[] toString()
	{
		return "break;";
	}
}

class ReturnStatement : Statement
{
	protected Expression mExpr;

	public this(Location location, Expression expr)
	{
		super(location);
		mExpr = expr;
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
			ReturnStatement ret = new ReturnStatement(location, Expression.parse(t));
			t.check(Token.Type.Semicolon);
			t = t.nextToken;
			return ret;
		}
	}
	
	public char[] toString()
	{
		char[] ret = "return";
		
		if(mExpr !is null)
			ret = std.string.format("%s %s", ret, mExpr);
		
		ret ~= ";";
		
		return ret;	
	}
}