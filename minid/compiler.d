/******************************************************************************
The MiniD compiler.  This is, unsurprisingly, the largest part of the implementation,
although it has a very small public interface.

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

import Float = tango.text.convert.Float;
import Integer = tango.text.convert.Integer;
import tango.core.Exception;
import tango.text.Util;
import utf = tango.text.convert.Utf;
import tango.io.Stdout;
import tango.io.protocol.model.IReader;
import tango.io.protocol.Reader;
import tango.io.FileConduit;
import tango.io.UnicodeFile;
import tango.io.FilePath;
import Uni = tango.text.Unicode;

import minid.types;
import minid.opcodes;
import minid.utils;

//debug = REGPUSHPOP;
//debug = VARACTIVATE;
//debug = WRITECODE;

/**
Compile a source code file into a binary module.  Takes the path to the source file and returns
the compiled module, which can be loaded into a context.

You shouldn't have to deal with this function that much.  Most of the time the compilation of
modules should be handled for you by the import system in MDContext.
*/
public MDModuleDef compileModule(char[] filename)
{
	scope path = FilePath(filename);
	return compileModule((new UnicodeFile!(dchar)(path, Encoding.Unknown)).read(), path.file);
}

/**
Compile a module from a string containing the source code.

Params:
	source = The source code as a string.
	name = The name which should be used as the source name in compiler error message.  Takes the
		place of the filename when compiling from a source file.

Returns:
	The compiled module.
*/
public MDModuleDef compileModule(dchar[] source, char[] name)
{
	scope lexer = new Lexer(name, source);
	return Module.parse(lexer).codeGen();
}

/**
Compile a list of statements into a function body which takes a variadic number of arguments.  Kind
of like a module without the module statement.  

Params:
	source = The source code as a string.
	name = The name to use as the source name for compilation errors.
		
Returns:
	The compiled function.
*/
public MDFuncDef compileStatements(dchar[] source, char[] name)
{
	scope lexer = new Lexer(name, source);
	List!(Statement) s;

	while(lexer.type != Token.Type.EOF)
		s.add(Statement.parse(lexer));
		
	lexer.expect(Token.Type.EOF);

	Statement[] stmts = s.toArray();

	FuncState fs = new FuncState(Location(utf.toString32(name), 1, 1), utf.toString32(name));
	fs.mIsVararg = true;

	foreach(stmt; stmts)
		stmt.fold().codeGen(fs);

	if(stmts.length == 0)
		fs.codeI(1, Op.Ret, 0, 1);
	else
		fs.codeI(stmts[$ - 1].endLocation.line, Op.Ret, 0, 1);
		
	//fs.showMe(); Stdout.flush;

	return fs.toFuncDef();
}

/**
Compile a single expression into a function which returns the value of that expression when called.

Params:
	source = The source code as a string.
	name = The name to use as the source name for compilation errors.
	
Returns:
	The compiled function.
*/
public MDFuncDef compileExpression(dchar[] source, char[] name)
{
	scope lexer = new Lexer(name, source);
	Expression e = Expression.parse(lexer);

	if(lexer.type != Token.Type.EOF)
		throw new MDCompileException(lexer.loc, "Extra unexpected code after expression");
		
	FuncState fs = new FuncState(Location(utf.toString32(name), 1, 1), utf.toString32(name));
	fs.mIsVararg = true;
	
	auto ret = (new ReturnStatement(e)).fold();

	ret.codeGen(fs);
	fs.codeI(ret.endLocation.line, Op.Ret, 0, 1);
	
	return fs.toFuncDef();
}

/**
Parses a JSON string into a MiniD value and returns that value.  Just like the MiniD baselib
function.
*/
public MDValue loadJSON(dchar[] source)
{
	scope lexer = new Lexer("JSON", source, true);

	if(lexer.type == Token.Type.LBrace)
		return TableCtorExp.parseJSON(lexer);
	else
		return ArrayCtorExp.parseJSON(lexer);
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
		Namespace,
		Null,
		Return,
		Super,
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
		Cmp3,
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
		LAttr,
		RAttr,
		Colon,
		Comma,
		Semicolon,
		Length,
		Question,

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
		Type.Namespace: "namespace",
		Type.Null: "null",
		Type.Return: "return",
		Type.Super: "super",
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
		Type.Cmp3: "<=>",
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
		Type.LAttr: "</",
		Type.RAttr: "/>",
		Type.Colon: ":",
		Type.Comma: ",",
		Type.Semicolon: ";",
		Type.Length: "#",
		Type.Question: "?",

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
		foreach(i, val; tokenStrings[0 .. Type.Ident])
			stringToType[val] = cast(Type)i;

		stringToType.rehash;
	}

	public char[] toString()
	{
		switch(type)
		{
			case Type.Ident:         return "Identifier: " ~ utf.toString(stringValue);
			case Type.CharLiteral:   return "Character Literal";
			case Type.StringLiteral: return "String Literal";
			case Type.IntLiteral:    return "Integer Literal: " ~ Integer.toString(intValue);
			case Type.FloatLiteral:  return "Float Literal: " ~ Float.toString(floatValue);
			default:                 return utf.toString(tokenStrings[cast(uint)type]);
		}
	}

	public void expect(Type t)
	{
		if(type != t)
			expected(tokenStrings[t]);
	}
	
	public void expected(dchar[] message)
	{
		auto e = new MDCompileException(location, "'{}' expected; found '{}' instead", message, tokenStrings[type]);
		e.atEOF = type == Type.EOF;
		throw e;
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
		public mdfloat floatValue;
	}

	public Location location;
}

class Lexer
{
	protected dchar[] mSource;
	protected Location mLoc;
	protected size_t mPosition;
	protected dchar mCharacter;
	protected dchar mLookaheadCharacter;
	protected bool mHaveLookahead = false;
	protected bool mIsJSON = false;
	protected Token mTok;
	protected Token mPeekTok;
	protected bool mHavePeekTok = false;
	protected bool mNewlineSinceLastTok = false;

	public this(char[] name, dchar[] source, bool isJSON = false)
	{
		mLoc = Location(utf.toString32(name), 1, 0);

		mSource = source;
		mPosition = 0;
		mIsJSON = isJSON;

		nextChar();

		if(mSource.length >= 2 && mSource[0 .. 2] == "#!")
			while(!isEOL())
				nextChar();

		next();
	}
	
	public final Token* tok()
	{
		return &mTok;
	}
	
	public final Location loc()
	{
		return mTok.location;
	}

	public final Token.Type type()
	{
		return mTok.type;
	}

	public final Token expect(Token.Type t)
	{
		mTok.expect(t);
		Token ret = mTok;

		if(t != Token.Type.EOF)
			next();

		return ret;
	}
	
	public final bool isStatementTerm()
	{
		return mNewlineSinceLastTok || mTok.type == Token.Type.EOF || mTok.type == Token.Type.Semicolon || mTok.type == Token.Type.RBrace;
	}

	public final void statementTerm()
	{
		if(mNewlineSinceLastTok)
			mNewlineSinceLastTok = false;
		else
		{
			if(mTok.type == Token.Type.EOF)
				return;
			else if(mTok.type == Token.Type.Semicolon)
				next();
			else if(mTok.type == Token.Type.RBrace)
				return;
			else
				throw new MDCompileException(mLoc, "Statement terminator expected, not '{}'", mTok.toString());
		}
	}

	public final Token peek()
	{
		if(mHavePeekTok)
			return mPeekTok;

		auto t = mTok;
		nextToken();
		mHavePeekTok = true;
		mPeekTok = mTok;
		mTok = t;

		return mPeekTok;
	}
	
	public final void next()
	{
		if(mHavePeekTok)
		{
			mHavePeekTok = false;
			mTok = mPeekTok;
		}
		else
			nextToken();
	}

	protected final bool isEOF()
	{
		return (mCharacter == '\0') || (mCharacter == dchar.init);
	}

	protected final bool isEOL()
	{
		return isNewline() || isEOF();
	}

	protected final bool isWhitespace()
	{
		return (mCharacter == ' ') || (mCharacter == '\t') || (mCharacter == '\v') || (mCharacter == '\u000C') || isEOL();
	}

	protected final bool isNewline()
	{
		return (mCharacter == '\r') || (mCharacter == '\n');
	}

	protected final bool isBinaryDigit()
	{
		return (mCharacter == '0') || (mCharacter == '1');
	}

	protected final bool isOctalDigit()
	{
		return (mCharacter >= '0') && (mCharacter <= '7');
	}

	protected final bool isHexDigit()
	{
		return ((mCharacter >= '0') && (mCharacter <= '9')) ||
			((mCharacter >= 'a') && (mCharacter <= 'f')) ||
			((mCharacter >= 'A') && (mCharacter <= 'F'));
	}

	protected final bool isDecimalDigit()
	{
		return (mCharacter >= '0') && (mCharacter <= '9');
	}

	protected final bool isAlpha()
	{
		return ((mCharacter >= 'a') && (mCharacter <= 'z')) || ((mCharacter >= 'A') && (mCharacter <= 'Z'));
	}

	protected final ubyte hexDigitToInt(dchar c)
	{
		assert((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'), "hexDigitToInt");

		if(c >= '0' && c <= '9')
			return c - '0';

		if(Uni.isUpper(c))
			return c - 'A' + 10;
		else
			return c - 'a' + 10;
	}

	protected final dchar readChar()
	{
		if(mPosition >= mSource.length)
			return dchar.init;
		else
			return mSource[mPosition++];
	}
	
	protected final dchar lookaheadChar()
	{
		assert(mHaveLookahead == false, "looking ahead too far");

		mLookaheadCharacter = readChar();
		mHaveLookahead = true;
		return mLookaheadCharacter;
	}

	protected final void nextChar()
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

	protected final void nextLine()
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

	protected final bool readNumLiteral(bool prependPoint, out mdfloat fret, out int iret)
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
					case 'b', 'B':
						nextChar();

						if(!isBinaryDigit() && mCharacter != '_')
							throw new MDCompileException(mLoc, "Binary digit expected, not '{}'", mCharacter);

						while(isBinaryDigit() || mCharacter == '_')
						{
							if(mCharacter != '_')
								add(mCharacter);

							nextChar();
						}

						try
							iret = Integer.toInt(buf[0 .. i], 2);
						catch(IllegalArgumentException e)
							throw new MDCompileException(beginning, e.toString());

						return true;

					case 'c', 'C':
						nextChar();

						if(!isOctalDigit() && mCharacter != '_')
							throw new MDCompileException(mLoc, "Octal digit expected, not '{}'", mCharacter);

						while(isOctalDigit() || mCharacter == '_')
						{
							if(mCharacter != '_')
								add(mCharacter);

							nextChar();
						}

						try
							iret = Integer.toInt(buf[0 .. i], 8);
						catch(IllegalArgumentException e)
							throw new MDCompileException(beginning, e.toString());

						return true;

					case 'x', 'X':
						nextChar();

						if(!isHexDigit() && mCharacter != '_')
							throw new MDCompileException(mLoc, "Hexadecimal digit expected, not '{}'", mCharacter);

						while(isHexDigit() || mCharacter == '_')
						{
							if(mCharacter != '_')
								add(mCharacter);

							nextChar();
						}

						try
							iret = Integer.toInt(buf[0 .. i], 16);
						catch(IllegalArgumentException e)
							throw new MDCompileException(beginning, e.toString());

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
				//REACHABLE?
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
			else if(mCharacter == '_')
				nextChar();
			else
				throw new MDCompileException(mLoc, "Floating point literal '{}' must have at least one digit after decimal point", buf[0 .. i]);
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

				if(!isDecimalDigit() && mCharacter != '_')
					throw new MDCompileException(mLoc, "Exponent value expected in float literal '{}'", buf[0 .. i]);

				while(isDecimalDigit() || mCharacter == '_')
				{
					if(mCharacter != '_')
						add(mCharacter);

					nextChar();
				}

				break;
			}
			else if(mCharacter == '_')
			{
				nextChar();
				continue;
			}
			else
				break;
		}

		if(hasPoint == false && hasExponent == false)
		{
			try
				iret = Integer.toInt(buf[0 .. i], 10);
			catch(IllegalArgumentException e)
				throw new MDCompileException(beginning, e.toString());

			return true;
		}
		else
		{
			try
				fret = Float.toFloat(utf.toString(buf[0 .. i]));
			catch(IllegalArgumentException e)
				throw new MDCompileException(beginning, e.toString());

			return false;
		}
	}

	protected final dchar readEscapeSequence(Location beginning)
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
			
			case '/':
				if(mIsJSON)
				{
					nextChar();
					return '/';
				}

				goto default;

			case 'x':
				nextChar();

				uint x = readHexDigits(2);

				if(x > 0x7F)
					throw new MDCompileException(mLoc, "Hexadecimal escape sequence too large");

				ret = cast(dchar)x;
				break;

			case 'u':
				nextChar();

				uint x = readHexDigits(4);

				if(x == 0xFFFE || x == 0xFFFF)
					throw new MDCompileException(mLoc, "Unicode escape '\\u{:x4}' is illegal", x);

				ret = cast(dchar)x;
				break;

			case 'U':
				nextChar();

				uint x = readHexDigits(8);

				if(x == 0xFFFE || x == 0xFFFF)
					throw new MDCompileException(mLoc, "Unicode escape '\\U{:x8}' is illegal", x);

				if(isValidUniChar(cast(dchar)x) == false)
					throw new MDCompileException(mLoc, "Unicode escape '\\U{:x8}' too large", x);

				ret = cast(dchar)x;
				break;

			default:
				if(!isDecimalDigit())
					throw new MDCompileException(mLoc, "Invalid string escape sequence '\\{}'", mCharacter);

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

	protected final dchar[] readStringLiteral(bool escape)
	{
		Location beginning = mLoc;

		List!(dchar) buf;
		dchar delimiter = mCharacter;

		// Skip opening quote
		nextChar();

		do
		{
			if(isEOF())
				throw new MDCompileException(beginning, "Unterminated string literal");

			switch(mCharacter)
			{
				case '\r', '\n':
					buf.add('\n');
					nextLine();
					break;

				case '\\':
					if(escape == false)
						goto default;

					buf.add(readEscapeSequence(beginning));
					continue;

				default:
					if(!escape && mCharacter == delimiter)
					{
						if(lookaheadChar() == delimiter)
						{
							buf.add(delimiter);
							nextChar();
							nextChar();
						}
					}
					else
					{
						if(escape && mCharacter == delimiter)
							break;

						buf.add(mCharacter);
						nextChar();
					}
					break;
			}
		} while(mCharacter != delimiter)

		// Skip end quote
		nextChar();

		return buf.toArray();
	}

	protected final dchar readCharLiteral()
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

	protected final void nextToken()
	{
		Location tokenLoc;

		scope(exit)
			mTok.location = tokenLoc;
			
		mNewlineSinceLastTok = false;

		while(true)
		{
			tokenLoc = mLoc;

			switch(mCharacter)
			{
				case '\r', '\n':
					nextLine();
					mNewlineSinceLastTok = true;
					continue;

				case '+':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.Type.AddEq;
					}
					else if(mCharacter == '+')
					{
						nextChar();
						mTok.type = Token.Type.Inc;
					}
					else
						mTok.type = Token.Type.Add;

					return;

				case '-':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.Type.SubEq;
					}
					else if(mCharacter == '-')
					{
						nextChar();
						mTok.type = Token.Type.Dec;
					}
					else
						mTok.type = Token.Type.Sub;

					return;

				case '~':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.Type.CatEq;
					}
					else
						mTok.type = Token.Type.Cat;

					return;

				case '*':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.Type.MulEq;
					}
					else
						mTok.type = Token.Type.Mul;

					return;

				case '/':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.Type.DivEq;
						return;
					}
					else if(mCharacter == '/')
					{
						while(!isEOL())
							nextChar();
					}
					else if(mCharacter == '>')
					{
						nextChar();
						mTok.type = Token.Type.RAttr;
						return;	
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
						mTok.type = Token.Type.Div;
						return;
					}

					break;

				case '%':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.Type.ModEq;
					}
					else
						mTok.type = Token.Type.Mod;

					return;

				case '<':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();

						if(mCharacter == '>')
						{
							nextChar();
							mTok.type = Token.Type.Cmp3;
						}
						else
							mTok.type = Token.Type.LE;
					}
					else if(mCharacter == '<')
					{
						nextChar();

						if(mCharacter == '=')
						{
							nextChar();
							mTok.type = Token.Type.ShlEq;
						}
						else
							mTok.type = Token.Type.Shl;
					}
					else if(mCharacter == '/')
					{
						nextChar();
						mTok.type = Token.Type.LAttr;
					}
					else
						mTok.type = Token.Type.LT;

					return;

				case '>':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.Type.GE;
					}
					else if(mCharacter == '>')
					{
						nextChar();

						if(mCharacter == '=')
						{
							nextChar();
							mTok.type = Token.Type.ShrEq;
						}
						else if(mCharacter == '>')
						{
							nextChar();

							if(mCharacter == '=')
							{
								nextChar();
								mTok.type = Token.Type.UShrEq;
							}
							else
								mTok.type = Token.Type.UShr;
						}
						else
							mTok.type = Token.Type.Shr;
					}
					else
						mTok.type = Token.Type.GT;

					return;

				case '&':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.Type.AndEq;
					}
					else if(mCharacter == '&')
					{
						nextChar();
						mTok.type = Token.Type.AndAnd;
					}
					else
						mTok.type = Token.Type.And;

					return;

				case '|':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.Type.OrEq;
					}
					else if(mCharacter == '|')
					{
						nextChar();
						mTok.type = Token.Type.OrOr;
					}
					else
						mTok.type = Token.Type.Or;

					return;

				case '^':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.Type.XorEq;
					}
					else
						mTok.type = Token.Type.Xor;

					return;

				case '=':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.Type.EQ;
					}
					else
						mTok.type = Token.Type.Assign;

					return;

				case '.':
					nextChar();

					if(isDecimalDigit())
					{
						int dummy;
						bool b = readNumLiteral(true, mTok.floatValue, dummy);
						assert(b == false, "literal must be float");

						mTok.type = Token.Type.FloatLiteral;
					}
					else if(mCharacter == '.')
					{
						nextChar();
						mTok.type = Token.Type.DotDot;
					}
					else
						mTok.type = Token.Type.Dot;

					return;

				case '!':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.Type.NE;
					}
					else
						mTok.type = Token.Type.Not;

					return;
					
				case '?':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.Type.DefaultEq;
					}
					else
						mTok.type = Token.Type.Question;

					return;

				case '\"':
					mTok.stringValue = readStringLiteral(true);
					mTok.type = Token.Type.StringLiteral;
					return;

				case '`':
					mTok.stringValue = readStringLiteral(false);
					mTok.type = Token.Type.StringLiteral;
					return;

				case '@':
					nextChar();

					if(mCharacter != '\"')
						throw new MDCompileException(tokenLoc, "'@' expected to be followed by '\"'");

					mTok.stringValue = readStringLiteral(false);
					mTok.type = Token.Type.StringLiteral;
					return;

				case '\'':
					mTok.intValue = readCharLiteral();
					mTok.type = Token.Type.CharLiteral;
					return;

				case '\0', dchar.init:
					mTok.type = Token.Type.EOF;
					return;

				default:
					if(isWhitespace())
					{
						nextChar();
						continue;
					}
					else if(isDecimalDigit())
					{
						mdfloat fval;
						int ival;

						bool isInt = readNumLiteral(false, fval, ival);

						if(isInt == false)
						{
							mTok.floatValue = fval;
							mTok.type = Token.Type.FloatLiteral;
						}
						else
						{
							mTok.intValue = ival;
							mTok.type = Token.Type.IntLiteral;
						}

						return;
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
							throw new MDCompileException(tokenLoc, "'{}': Identifiers starting with two underscores are reserved", s);

						Token.Type* t = (s in Token.stringToType);

						if(t is null)
						{
							mTok.type = Token.Type.Ident;
							mTok.stringValue = s;
						}
						else
							mTok.type = *t;
							
						return;
					}
					else
					{
						dchar[] s;
						s ~= mCharacter;

						nextChar();

						Token.Type* t = (s in Token.stringToType);

						if(t is null)
							throw new MDCompileException(tokenLoc, "Invalid token '{}'", s);
						else
							mTok.type = *t;

						return;
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
	IndexedVararg,
	Field,
	Sliced,
	SlicedVararg,
	Length,
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
		static const char[][] typeNames = 
		[
			ExpType.Null: "Null",
			ExpType.True: "True",
			ExpType.False: "False",
			ExpType.Const: "Const",
			ExpType.Var: "Var",
			ExpType.NewGlobal: "NewGlobal",
			ExpType.Indexed: "Indexed",
			ExpType.IndexedVararg: "IndexedVararg",
			ExpType.Field: "Field",
			ExpType.Sliced: "Sliced",
			ExpType.SlicedVararg: "SlicedVararg",
			ExpType.Length: "Length",
			ExpType.Vararg: "Vararg",
			ExpType.Closure: "Closure",
			ExpType.Call: "Call",
			ExpType.Yield: "Yield",
			ExpType.NeedsDest: "NeedsDest",
			ExpType.Src: "Src"
		];

		return Stdout.layout.convert("{} ({}, {}, {}) : ({}, {}, {})", typeNames[cast(uint)type], index, index2, index3, isTempReg, isTempReg2, isTempReg3);
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
	protected bool mIsMethod;

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
		uint switchPC;
		int[MDValue] offsets;
		int defaultOffset = -1;

		SwitchDesc* prev;
	}

	// Switches are kept on this switch stack while being built..
	protected SwitchDesc* mSwitch;
	// ..and are then transfered to this array when they are done.
	protected SwitchDesc*[] mSwitchTables;
	
	protected static ClassDef[] mCurrentClass;
	protected static uint mClassDefIndex = 0;

	public static void enterClass(ClassDef def)
	{
		if(mClassDefIndex >= mCurrentClass.length)
			mCurrentClass.length = mCurrentClass.length + 3;

		mCurrentClass[mClassDefIndex] = def;
		mClassDefIndex++;
	}

	public static void leaveClass()
	{
		assert(mClassDefIndex != 0, "Number of classes underflow");
		mClassDefIndex--;
	}

	public static ClassDef currentClass()
	{
		assert(mClassDefIndex != 0);
		return mCurrentClass[mClassDefIndex - 1];
	}

	public this(Location location, dchar[] guessedName, FuncState parent = null, bool isMethod = false)
	{
		mLocation = location;
		mGuessedName = guessedName;
		mIsMethod = isMethod;

		mParent = parent;
		mScope = new Scope;
		mExpStack = new Exp[10];

		if(parent !is null)
			parent.mInnerFuncs ~= this;
		else
		{
			mNumParams = 1;
			insertLocal(new Identifier(mLocation, "this"));
			activateLocals(1);
		}
	}
	
	public bool isTopLevel()
	{
		return mParent is null;
	}

	public bool isMethod()
	{
		return mIsMethod;
	}

	public uint tagLocal(uint val)
	{
		if((val & ~Instruction.locMask) > MaxRegisters)
			throw new MDCompileException(mLocation, "Too many locals");

		return (val & ~Instruction.locMask) | Instruction.locLocal;
	}
	
	public uint tagConst(uint val)
	{
		if((val & ~Instruction.locMask) >= MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants");
			
		return (val & ~Instruction.locMask) | Instruction.locConst;
	}
	
	public uint tagUpval(uint val)
	{
		if((val & ~Instruction.locMask) >= MaxUpvalues)
			throw new MDCompileException(mLocation, "Too many upvalues");

		return (val & ~Instruction.locMask) | Instruction.locUpval;
	}
	
	public uint tagGlobal(uint val)
	{
		if((val & ~Instruction.locMask) >= MaxConstants)
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
	
	public uint resolveAssignmentConflicts(uint line, uint numVals)
	{
		uint numTemps = 0;

		for(int i = mExpSP - numVals + 1; i < mExpSP; i++)
		{
			Exp* index = &mExpStack[i];
			uint reloc = uint.max;

			for(int j = mExpSP - numVals; j < i; j++)
			{
				Exp* e = &mExpStack[j];

				if(e.index == index.index || e.index2 == index.index)
				{
					if(reloc == uint.max)
					{
						numTemps++;
						reloc = pushRegister();

						if(isLocalTag(index.index))
							codeR(line, Op.MoveLocal, reloc, index.index, 0);
						else
							codeR(line, Op.Move, reloc, index.index, 0);
					}

					if(e.index == index.index)
						e.index = reloc;

					if(e.index2 == index.index)
						e.index2 = reloc;
				}
			}
		}

		return numTemps;
	}
	
	public void popAssignmentConflicts(uint num)
	{
		mFreeReg -= num;
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
	
	public void closeUpvals(uint line)
	{
		if(mScope.hasUpval)
		{
			codeClose(line);
			mScope.hasUpval = false;
		}
	}

	public void beginSwitch(uint line, uint srcReg)
	{
		SwitchDesc* sd = new SwitchDesc;
		sd.switchPC = codeR(line, Op.Switch, 0, srcReg, 0);
		sd.prev = mSwitch;
		mSwitch = sd;
	}

	public void endSwitch()
	{
		SwitchDesc* desc = mSwitch;
		assert(desc !is null, "endSwitch - no switch to end");
		mSwitch = mSwitch.prev;

		mSwitchTables ~= desc;
		mCode[desc.switchPC].rt = mSwitchTables.length - 1;
	}

	public int* addCase(Location location, Expression v)
	{
		assert(mSwitch !is null);

		MDValue val;

		if(v.isNull())
			val.setNull();
		else if(v.isBool())
			val = v.asBool();
		else if(v.isInt())
			val = v.asInt();
		else if(v.isFloat())
			val = v.asFloat();
		else if(v.isChar())
			val = v.asChar();
		else if(v.isString())
			val = v.asString();
		else
			assert(false, "addCase invalid type: " ~ v.toString());

		int* oldOffset = (val in mSwitch.offsets);

		if(oldOffset !is null)
			throw new MDCompileException(location, "Duplicate case value '{}'", val);

		mSwitch.offsets[val] = 0;
		return (val in mSwitch.offsets);
	}

	public void addDefault(Location location)
	{
		assert(mSwitch !is null);
		assert(mSwitch.defaultOffset == -1);
		
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
		int index = searchLocal(ident.name, dummy);

		if(index != -1)
		{
			throw new MDCompileException(ident.location, "Local '{}' conflicts with previous definition at {}",
				ident.name, mLocVars[index].location.toString());
		}

		mLocVars.length = mLocVars.length + 1;

		with(mLocVars[$ - 1])
		{
			name = ident.name;
			location = ident.location;
			reg = pushRegister();
			isActive = false;
		}

		return mLocVars[$ - 1].reg;
	}

	public void activateLocals(uint num)
	{
		for(int i = mLocVars.length - 1; i >= cast(int)(mLocVars.length - num); i--)
		{
			debug(VARACTIVATE) Stdout.formatln("activating {} {} reg {}", mLocVars[i].name, mLocVars[i].location.toString(), mLocVars[i].reg);
			mLocVars[i].isActive = true;
		}
	}

	public void deactivateLocals(int varStart, int regTo)
	{
		for(int i = mLocVars.length - 1; i >= varStart; i--)
		{
			if(mLocVars[i].reg >= regTo && mLocVars[i].isActive)
			{
				debug(VARACTIVATE) Stdout.formatln("deactivating {} {} reg {}", mLocVars[i].name, mLocVars[i].location.toString(), mLocVars[i].reg);
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
		debug(REGPUSHPOP) Stdout.formatln("push ", mFreeReg);
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
		debug(REGPUSHPOP) Stdout.formatln("pop ", mFreeReg, ", ", r);

		assert(mFreeReg >= 0, "temp reg underflow");
		assert(mFreeReg == r, "reg not freed in order");
	}
	
	protected void printExpStack()
	{
		Stdout.formatln("Expression Stack");
		Stdout.formatln("----------------");

		for(int i = 0; i < mExpSP; i++)
			Stdout.formatln("{}: {}", i, mExpStack[i].toString());

		Stdout.formatln("");
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
	
	public void pushVargLen(uint line)
	{
		Exp* e = pushExp();
		e.type = ExpType.NeedsDest;
		e.index = codeR(line, Op.VargLen, 0, 0, 0);
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

	public void pushFloat(mdfloat value)
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
		e.index = tagConst(codeStringConst(name.name));
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
					if(s.mUpvals[i].name == name.name)
					{
						if((s.mUpvals[i].isUpvalue && varType == Upvalue) || (!s.mUpvals[i].isUpvalue && varType == Local))
							return i;
					}
				}

				UpvalDesc ud;

				ud.name = name.name;
				ud.isUpvalue = (varType == Upvalue);
				ud.index = tagLocal(e.index);

				s.mUpvals ~= ud;

				if(mUpvals.length >= MaxUpvalues)
					throw new MDCompileException(mLocation, "Too many upvalues in function");

				return s.mUpvals.length - 1;
			}

			if(s is null)
			{
				varType = Global;
				return Global;
			}

			uint reg;
			int index = s.searchLocal(name.name, reg);

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
			e.index = tagGlobal(codeStringConst(name.name));
			
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

	public void pushClosure(FuncState fs, int attrReg = -1)
	{
		Exp* e = pushExp();

		int index = -1;

		foreach(i, child; mInnerFuncs)
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
		
		if(attrReg != -1)
		{
			e.index2 = attrReg;
			e.isTempReg2 = true;
		}
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
				
			case ExpType.Field:
				toSource(line, src);

				codeR(line, Op.FieldAssign, dest.index, dest.index2, src.index);

				freeExpTempRegs(src);
				freeExpTempRegs(dest);
				break;

			case ExpType.IndexedVararg:
				toSource(line, src);
				
				codeR(line, Op.VargIndexAssign, dest.index, src.index, 0);
				freeExpTempRegs(src);
				break;

			case ExpType.Sliced:
				toSource(line, src);

				codeR(line, Op.SliceAssign, dest.index, src.index, 0);

				freeExpTempRegs(src);
				freeExpTempRegs(dest);
				break;
				
			case ExpType.Length:
				toSource(line, src);
				
				codeR(line, Op.LengthAssign, dest.index, src.index, 0);
				
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
				if(isLocalTag(dest))
					codeR(line, Op.LoadConst, dest, src.index, 0);
				else
					codeR(line, Op.Move, dest, src.index, 0);
				break;

			case ExpType.Var:
				if(dest != src.index)
				{
					if(isLocalTag(dest) && isLocalTag(src.index))
						codeR(line, Op.MoveLocal, dest, src.index, 0);
					else
						codeR(line, Op.Move, dest, src.index, 0);
				}
				break;

			case ExpType.Indexed:
				codeR(line, Op.Index, dest, src.index, src.index2);
				freeExpTempRegs(src);
				break;
				
			case ExpType.Field:
				codeR(line, Op.Field, dest, src.index, src.index2);
				freeExpTempRegs(src);
				break;

			case ExpType.IndexedVararg:
				codeR(line, Op.VargIndex, dest, src.index, 0);
				break;

			case ExpType.Sliced:
				codeR(line, Op.Slice, dest, src.index, 0);
				freeExpTempRegs(src);
				break;

			case ExpType.Length:
				codeR(line, Op.Length, dest, src.index, 0);
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
				
			case ExpType.SlicedVararg:
				mCode[src.index].uimm = 2;
				
				if(dest != src.index2)
				{
					if(isLocalTag(dest) && isLocalTag(src.index2))
						codeR(line, Op.MoveLocal, dest, src.index2, 0);
					else
						codeR(line, Op.Move, dest, src.index2, 0);
				}
				break;

			case ExpType.Closure:
				if(src.isTempReg2)
				{
					codeR(line, Op.Closure, dest, src.index, src.index2 + 1);
					freeExpTempRegs(src);
				}
				else
					codeR(line, Op.Closure, dest, src.index, 0);

				foreach(ref ud; mInnerFuncs[src.index].mUpvals)
					codeR(line, Op.Move, ud.isUpvalue ? 1 : 0, ud.index, 0);

				break;

			case ExpType.Call, ExpType.Yield:
				mCode[src.index].rt = 2;

				if(dest != src.index2)
				{
					if(isLocalTag(dest) && isLocalTag(src.index2))
						codeR(line, Op.MoveLocal, dest, src.index2, 0);
					else
						codeR(line, Op.Move, dest, src.index2, 0);
				}
				
				freeExpTempRegs(src);
				break;

			case ExpType.NeedsDest:
				mCode[src.index].rd = dest;
				break;

			case ExpType.Src:
				if(dest != src.index)
				{
					if(isLocalTag(dest) && isLocalTag(src.index))
						codeR(line, Op.MoveLocal, dest, src.index, 0);
					else
						codeR(line, Op.Move, dest, src.index, 0);
				}
				
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
				
			case ExpType.SlicedVararg:
				assert(src.index2 == reg, "pop to regs - trying to pop sliced varargs to different red");
				mCode[src.index].rt = num + 1;
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
	
	public void popReflexOp(uint line, Op type, uint rd, uint rs, uint rt = 0)
	{
		Exp* dest = pushExp();
		dest.type = ExpType.NeedsDest;
		dest.index = codeR(line, type, rd, rs, rt);

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
	
	public void popLength(uint line)
	{
		Exp* src = &mExpStack[mExpSP - 1];
		toSource(line, src);
		src.type = ExpType.Length;	
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
				{
					if(isLocalTag(dest.index))
						codeR(line, Op.MoveLocal, dest.index, srcReg, 0);
					else
						codeR(line, Op.Move, dest.index, srcReg, 0);
				}
				break;
				
			case ExpType.NewGlobal:
				codeR(line, Op.NewGlobal, 0, srcReg, dest.index);
				break;

			case ExpType.Indexed:
				codeR(line, Op.IndexAssign, dest.index, dest.index2, srcReg);
				freeExpTempRegs(dest);
				break;
				
			case ExpType.Field:
				codeR(line, Op.FieldAssign, dest.index, dest.index2, srcReg);
				freeExpTempRegs(dest);
				break;
				
			case ExpType.IndexedVararg:
				codeR(line, Op.VargIndexAssign, dest.index, srcReg, 0);
				break;
				
			case ExpType.Sliced:
				codeR(line, Op.SliceAssign, dest.index, srcReg, 0);
				freeExpTempRegs(dest);
				break;
				
			case ExpType.Length:
				codeR(line, Op.LengthAssign, dest.index, srcReg, 0);
				freeExpTempRegs(dest);
				break;

			default:
				assert(false);
		}
	}

	public void popField(uint line)
	{
		assert(mExpSP > 1, "pop field from nothing");

		Exp* index = popExp();
		Exp* e = &mExpStack[mExpSP - 1];

		toSource(line, e);
		toSource(line, index);

		e.index2 = index.index;
		e.isTempReg2 = index.isTempReg;
		e.type = ExpType.Field;
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
	
	public void popVargIndex(uint line)
	{
		assert(mExpSP > 0, "pop varg index from nothing");

		Exp* e = &mExpStack[mExpSP - 1];
		toSource(line, e);
		e.type = ExpType.IndexedVararg;
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
	
	public void pushVargSlice(uint line, uint reg)
	{
		Exp* e = pushExp();
		e.index = codeI(line, Op.VargSlice, reg, 0);
		e.index2 = reg;
		e.type = ExpType.SlicedVararg;
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
				
			case ExpType.Field:
				if(cleanup)
					freeExpTempRegs(e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op.Field, temp.index, e.index, e.index2);
				break;

			case ExpType.IndexedVararg:
				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op.VargIndex, temp.index, e.index, 0);
				break;

			case ExpType.Sliced:
				if(cleanup)
					freeExpTempRegs(e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op.Slice, temp.index, e.index, 0);
				break;
				
			case ExpType.Length:
				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op.Length, temp.index, e.index, 0);
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
				if(e.isTempReg2)
				{
					temp.index = e.index2;
					codeR(line, Op.Closure, temp.index, e.index, temp.index + 1);
				}
				else
				{
					temp.index = pushRegister();
					codeI(line, Op.Closure, temp.index, e.index);
				}

				foreach(ref ud; mInnerFuncs[e.index].mUpvals)
					codeR(line, Op.Move, ud.isUpvalue ? 1 : 0, ud.index, 0);

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
				
			case ExpType.SlicedVararg:
				codeI(line, Op.VargSlice, e.index, 2);
				temp.index = e.index;
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
	
	public void patchSwitchJumpToHere(int* offset)
	{
		assert(mSwitch !is null);
		*offset = mCode.length - mSwitch.switchPC - 1;
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
	
	public InstRef* makeFor(uint line, uint baseReg)
	{
		InstRef* i = new InstRef;
		i.pc = codeJ(line, Op.For, baseReg, 0);
		return i;
	}
	
	public InstRef* makeForLoop(uint line, uint baseReg)
	{
		InstRef* i = new InstRef;
		i.pc = codeJ(line, Op.ForLoop, baseReg, 0);
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
		foreach(i, v; mConstants)
			if(v.isString() && v.as!(MDString)() == c)
				return i;

		MDValue v = c;
		mConstants ~= v;

		if(mConstants.length >= MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}
	
	public int codeBoolConst(bool b)
	{
		foreach(i, v; mConstants)
			if(v.isBool() && v.as!(bool)() == b)
				return i;

		MDValue v = b;
		mConstants ~= v;

		if(mConstants.length >= MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}

	public int codeIntConst(int x)
	{
		foreach(i, v; mConstants)
			if(v.isInt() && v.as!(int)() == x)
				return i;

		MDValue v = x;
		mConstants ~= v;

		if(mConstants.length >= MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}
	
	public int codeCharConst(dchar x)
	{
		foreach(i, v; mConstants)
			if(v.isChar() && v.as!(dchar)() == x)
				return i;

		MDValue v = x;
		mConstants ~= v;

		if(mConstants.length >= MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}

	public int codeFloatConst(mdfloat x)
	{
		foreach(i, v; mConstants)
			if(v.isFloat() && v.as!(mdfloat)() == x)
				return i;

		MDValue v = x;
		mConstants ~= v;

		if(mConstants.length >= MaxConstants)
			throw new MDCompileException(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}

	public int codeNullConst()
	{
		foreach(i, v; mConstants)
			if(v.isNull())
				return i;

		MDValue v;
		v.setNull();

		mConstants ~= v;

		if(mConstants.length >= MaxConstants)
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

		debug(WRITECODE) Stdout.formatln(i.toString());

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

		debug(WRITECODE) Stdout.formatln(i.toString());

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
		
		debug(WRITECODE) Stdout.formatln(i.toString());

		mLineInfo ~= line;
		mCode ~= i;
		return mCode.length - 1;
	}

	public void showMe(uint tab = 0)
	{
		Stdout.formatln("{}Function at {} (guessed name: {})", repeat("\t", tab), mLocation.toString(), mGuessedName);
		Stdout.formatln("{}Num params: {} Vararg: {} Stack size: {}", repeat("\t", tab), mNumParams, mIsVararg, mStackSize);

		foreach(i, s; mInnerFuncs)
		{
			Stdout.formatln("{}Inner Func {}", repeat("\t", tab + 1), i);
			s.showMe(tab + 1);
		}
		
		foreach(i, ref t; mSwitchTables)
		{
			Stdout.formatln("{}Switch Table {}", repeat("\t", tab + 1), i);

			foreach(k, v; t.offsets)
				Stdout.formatln("{}{} => {}", repeat("\t", tab + 2), k.toString(), v);

			Stdout.formatln("{}Default: {}", repeat("\t", tab + 2), t.defaultOffset);
		}

		foreach(v; mLocVars)
			Stdout.formatln("{}Local {} (at {}, reg {})", repeat("\t", tab + 1), v.name, v.location.toString(), v.reg);

		foreach(i, u; mUpvals)
			Stdout.formatln("{}Upvalue {}: {} : {} ({})", repeat("\t", tab + 1), i, u.name, u.index, u.isUpvalue ? "upval" : "local");

		foreach(i, c; mConstants)
		{
			switch(c.type)
			{
				case MDValue.Type.Null:
					Stdout.formatln("{}Const {}: null", repeat("\t", tab + 1), i);
					break;
					
				case MDValue.Type.Bool:
					Stdout.formatln("{}Const {}: {}", repeat("\t", tab + 1), i, c.as!(bool)());
					break;

				case MDValue.Type.Int:
					Stdout.formatln("{}Const {}: {}", repeat("\t", tab + 1), i, c.as!(int)());
					break;

				case MDValue.Type.Float:
					Stdout.formatln("{}Const {}: {:6}f", repeat("\t", tab + 1), i, c.as!(mdfloat)());
					break;

				case MDValue.Type.Char:
					Stdout.formatln("{}Const {}: '{}'", repeat("\t", tab + 1), i, c.as!(dchar)());
					break;

				case MDValue.Type.String:
					Stdout.formatln("{}Const {}: \"{}\"", repeat("\t", tab + 1), i, c.as!(dchar[])());
					break;

				default:
					assert(false);
			}
		}

		foreach(i, inst; mCode)
			Stdout.formatln("{}[{,3}:{,4}] {}", repeat("\t", tab + 1), i, mLineInfo[i], inst.toString());
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
		ret.mStackSize = mStackSize + 1;
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
				ret.mSwitchTables[i].offsets = offsets;
				ret.mSwitchTables[i].defaultOffset = defaultOffset;
			}
		}

		return ret;
	}
}

class Identifier
{
	public dchar[] name;
	public Location location;

	public this(Location location, dchar[] name)
	{
		this.name = name;
		this.location = location;
	}

	public static Identifier parse(Lexer l)
	{
		with(l.expect(Token.Type.Ident))
			return new Identifier(location, stringValue);
	}
	
	public static dchar[] parseName(Lexer l)
	{
		with(l.expect(Token.Type.Ident))
			return stringValue;
	}		

	public static dchar[] toLongString(Identifier[] idents)
	{
		dchar[][] strings = new dchar[][idents.length];

		foreach(i, ident; idents)
			strings[i] = ident.name;

		return join(strings, "."d);
	}
}

enum AstTag
{
	Other,
	ClassDef,
	FuncDef,
	NamespaceDef,
	Module,
	ModuleDecl,
	ImportStmt,
	BlockStmt,
	ScopeStmt,
	ExpressionStmt,
	FuncDecl,
	ClassDecl,
	NamespaceDecl,
	VarDecl,
	IfStmt,
	WhileStmt,
	DoWhileStmt,
	ForStmt,
	ForNumStmt,
	ForeachStmt,
	SwitchStmt,
	CaseStmt,
	DefaultStmt,
	ContinueStmt,
	BreakStmt,
	ReturnStmt,
	TryStmt,
	ThrowStmt,
	Assign,
	AddAssign,
	SubAssign,
	CatAssign,
	MulAssign,
	DivAssign,
	ModAssign,
	OrAssign,
	XorAssign,
	AndAssign,
	ShlAssign,
	ShrAssign,
	UShrAssign,
	CondAssign,
	CondExp,
	OrOrExp,
	AndAndExp,
	OrExp,
	XorExp,
	AndExp,
	EqualExp,
	NotEqualExp,
	IsExp,
	NotIsExp,
	LTExp,
	LEExp,
	GTExp,
	GEExp,
	Cmp3Exp,
	AsExp,
	InExp,
	NotInExp,
	ShlExp,
	ShrExp,
	UShrExp,
	AddExp,
	SubExp,
	CatExp,
	MulExp,
	DivExp,
	ModExp,
	NegExp,
	NotExp,
	ComExp,
	LenExp,
	VargLenExp,
	CoroutineExp,
	DotExp,
	DotClassExp,
	DotSuperExp,
	IndexExp,
	SliceExp,
	VargSliceExp,
	CallExp,
	IdentExp,
	ThisExp,
	NullExp,
	BoolExp,
	VarargExp,
	IntExp,
	FloatExp,
	CharExp,
	StringExp,
	FuncLiteralExp,
	ClassLiteralExp,
	ParenExp,
	TableCtorExp,
	ArrayCtorExp,
	NamespaceCtorExp,
	YieldExp,
	SuperCallExp
}

const char[][] AstTagNames = 
[
	AstTag.Other:            "Other",
	AstTag.ClassDef:         "ClassDef",
	AstTag.FuncDef:          "FuncDef",
	AstTag.NamespaceDef:     "NamespaceDef",
    AstTag.Module:           "Module",
    AstTag.ModuleDecl:       "ModuleDecl",
    AstTag.ImportStmt:       "ImportStmt",
    AstTag.BlockStmt:        "BlockStmt",
    AstTag.ScopeStmt:        "ScopeStmt",
    AstTag.ExpressionStmt:   "ExpressionStmt",
    AstTag.FuncDecl:         "FuncDecl",
    AstTag.ClassDecl:        "ClassDecl",
    AstTag.NamespaceDecl:    "NamespaceDecl",
    AstTag.VarDecl:          "VarDecl",
    AstTag.IfStmt:           "IfStmt",
    AstTag.WhileStmt:        "WhileStmt",
    AstTag.DoWhileStmt:      "DoWhileStmt",
    AstTag.ForStmt:          "ForStmt",
    AstTag.ForNumStmt:       "ForNumStmt",
    AstTag.ForeachStmt:      "ForeachStmt",
    AstTag.SwitchStmt:       "SwitchStmt",
    AstTag.CaseStmt:         "CaseStmt",
    AstTag.DefaultStmt:      "DefaultStmt",
    AstTag.ContinueStmt:     "ContinueStmt",
    AstTag.BreakStmt:        "BreakStmt",
    AstTag.ReturnStmt:       "ReturnStmt",
    AstTag.TryStmt:          "TryStmt",
    AstTag.ThrowStmt:        "ThrowStmt",
    AstTag.Assign:           "Assign",
    AstTag.AddAssign:        "AddAssign",
    AstTag.SubAssign:        "SubAssign",
    AstTag.CatAssign:        "CatAssign",
    AstTag.MulAssign:        "MulAssign",
    AstTag.DivAssign:        "DivAssign",
    AstTag.ModAssign:        "ModAssign",
    AstTag.OrAssign:         "OrAssign",
    AstTag.XorAssign:        "XorAssign",
    AstTag.AndAssign:        "AndAssign",
    AstTag.ShlAssign:        "ShlAssign",
    AstTag.ShrAssign:        "ShrAssign",
    AstTag.UShrAssign:       "UShrAssign",
    AstTag.CondAssign:       "CondAssign",
    AstTag.CondExp:          "CondExp",
    AstTag.OrOrExp:          "OrOrExp",
    AstTag.AndAndExp:        "AndAndExp",
    AstTag.OrExp:            "OrExp",
    AstTag.XorExp:           "XorExp",
    AstTag.AndExp:           "AndExp",
    AstTag.EqualExp:         "EqualExp",
    AstTag.NotEqualExp:      "NotEqualExp",
    AstTag.IsExp:            "IsExp",
    AstTag.NotIsExp:         "NotIsExp",
    AstTag.LTExp:          "LTExp",
    AstTag.LEExp:     "LEExp",
    AstTag.GTExp:       "GTExp",
    AstTag.GEExp:  "GEExp",
    AstTag.Cmp3Exp:          "Cmp3Exp",
    AstTag.AsExp:            "AsExp",
    AstTag.InExp:            "InExp",
    AstTag.NotInExp:         "NotInExp",
    AstTag.ShlExp:           "ShlExp",
    AstTag.ShrExp:           "ShrExp",
    AstTag.UShrExp:          "UShrExp",
    AstTag.AddExp:           "AddExp",
    AstTag.SubExp:           "SubExp",
    AstTag.CatExp:           "CatExp",
    AstTag.MulExp:           "MulExp",
    AstTag.DivExp:           "DivExp",
    AstTag.ModExp:           "ModExp",
    AstTag.NegExp:           "NegExp",
    AstTag.NotExp:           "NotExp",
    AstTag.ComExp:           "ComExp",
    AstTag.LenExp:           "LenExp",
    AstTag.VargLenExp:       "VargLenExp",
    AstTag.CoroutineExp:     "CoroutineExp",
    AstTag.DotExp:           "DotExp",
    AstTag.DotClassExp:      "DotClassExp",
    AstTag.DotSuperExp:      "DotSuperExp",
    AstTag.IndexExp:         "IndexExp",
    AstTag.SliceExp:         "SliceExp",
    AstTag.VargSliceExp:     "VargSliceExp",
    AstTag.CallExp:          "CallExp",
    AstTag.IdentExp:         "IdentExp",
    AstTag.ThisExp:          "ThisExp",
    AstTag.NullExp:          "NullExp",
    AstTag.BoolExp:          "BoolExp",
    AstTag.VarargExp:        "VarargExp",
    AstTag.IntExp:           "IntExp",
    AstTag.FloatExp:         "FloatExp",
    AstTag.CharExp:          "CharExp",
    AstTag.StringExp:        "StringExp",
    AstTag.FuncLiteralExp:   "FuncLiteralExp",
    AstTag.ClassLiteralExp:  "ClassLiteralExp",
    AstTag.ParenExp:         "ParenExp",
    AstTag.TableCtorExp:     "TableCtorExp",
    AstTag.ArrayCtorExp:     "ArrayCtorExp",
    AstTag.NamespaceCtorExp: "NamespaceCtorExp",
    AstTag.YieldExp:         "YieldExp",
    AstTag.SuperCallExp:     "SuperCallExp"
];

private Op AstTagToOpcode(AstTag tag)
{
	switch(tag)
	{
		case AstTag.AddAssign: return Op.AddEq;
		case AstTag.SubAssign: return Op.SubEq;
		case AstTag.CatAssign: return Op.CatEq;
		case AstTag.MulAssign: return Op.MulEq;
		case AstTag.DivAssign: return Op.DivEq;
		case AstTag.ModAssign: return Op.ModEq;
		case AstTag.OrAssign: return Op.OrEq;
		case AstTag.XorAssign: return Op.XorEq;
		case AstTag.AndAssign: return Op.AndEq;
		case AstTag.ShlAssign: return Op.ShlEq;
		case AstTag.ShrAssign: return Op.ShrEq;
		case AstTag.UShrAssign: return Op.UShrEq;
		case AstTag.CondAssign: return Op.CondMove;
		case AstTag.OrExp: return Op.Or;
		case AstTag.XorExp: return Op.Xor;
		case AstTag.AndExp: return Op.And;
		case AstTag.EqualExp: return Op.Cmp;
		case AstTag.NotEqualExp: return Op.Cmp;
		case AstTag.IsExp: return Op.Is;
		case AstTag.NotIsExp: return Op.Is;
		case AstTag.LTExp: return Op.Cmp;
		case AstTag.LEExp: return Op.Cmp;
		case AstTag.GTExp: return Op.Cmp;
		case AstTag.GEExp: return Op.Cmp;
		case AstTag.Cmp3Exp: return Op.Cmp3;
		case AstTag.AsExp: return Op.As;
		case AstTag.InExp: return Op.In;
		case AstTag.NotInExp: return Op.NotIn;
		case AstTag.ShlExp: return Op.Shl;
		case AstTag.ShrExp: return Op.Shr;
		case AstTag.UShrExp: return Op.UShr;
		case AstTag.AddExp: return Op.Add;
		case AstTag.SubExp: return Op.Sub;
		case AstTag.CatExp: return Op.Cat;
		case AstTag.MulExp: return Op.Mul;
		case AstTag.DivExp: return Op.Div;
		case AstTag.ModExp: return Op.Mod;
		case AstTag.NegExp: return Op.Neg;
		case AstTag.NotExp: return Op.Not;
		case AstTag.ComExp: return Op.Com;
		case AstTag.LenExp: return Op.Length;
		default: assert(false);
	}
}

abstract class AstNode
{
	public Location location;
	public Location endLocation;
	public AstTag type;

	public this(Location location, Location endLocation, AstTag type)
	{
		this.location = location;
		this.endLocation = endLocation;
		this.type = type;
	}

	public char[] toString()
	{
		return AstTagNames[type];
	}
}

class ClassDef : AstNode
{
	struct Field
	{
		dchar[] name;
		Expression initializer;
	}

	public Identifier name;
	public Expression baseClass;
	public FuncDef[] methods;
	public Field[] fields;
	public TableCtorExp attrs;

	public this(Location location, Location endLocation, Identifier name, Expression baseClass, FuncDef[] methods, Field[] fields, TableCtorExp attrs = null)
	{
		super(location, endLocation, AstTag.ClassDef);
		this.name = name;
		this.baseClass = baseClass;
		this.methods = methods;
		this.fields = fields;
		this.attrs = attrs;

		if(this.name is null)
			this.name = new Identifier(location, "<literal at " ~ utf.toString32(location.toString()) ~ ">");
	}

	public static ClassDef parse(Lexer l, bool nameOptional, TableCtorExp attrs = null)
	{
		auto location = l.expect(Token.Type.Class).location;

		Identifier name;

		if(!nameOptional || l.type == Token.Type.Ident)
			name = Identifier.parse(l);

		Expression baseClass;

		if(l.type == Token.Type.Colon)
		{
			l.next();
			baseClass = Expression.parse(l);
		}
		else
			baseClass = new NullExp(l.loc);

		l.expect(Token.Type.LBrace);

		FuncDef[dchar[]] methods;

		void addMethod(FuncDef m)
		{
			dchar[] name = m.name.name;

			if(name in methods)
				throw new MDCompileException(m.location, "Redeclaration of method '{}'", name);

			methods[name] = m;
		}

		Expression[dchar[]] fields;

		void addField(Identifier name, Expression v)
		{
			if(name.name in fields)
				throw new MDCompileException(name.location, "Redeclaration of field '{}'", name.name);

			fields[name.name] = v;
		}

		while(l.type != Token.Type.RBrace)
		{
			switch(l.type)
			{
				case Token.Type.This:
					auto ctorLocation = l.loc;
					l.next();

					addMethod(FuncDef.parseBody(l, ctorLocation, new Identifier(ctorLocation, "constructor")));
					break;

				case Token.Type.LAttr:
					auto attr = TableCtorExp.parseAttrs(l);

					if(l.type == Token.Type.This)
					{
						auto ctorLocation = l.loc;
						l.next();
						addMethod(FuncDef.parseBody(l, ctorLocation, new Identifier(ctorLocation, "constructor"), attr));
					}
					else
						addMethod(FuncDef.parseSimple(l, attr));
					break;

				case Token.Type.Function:
					addMethod(FuncDef.parseSimple(l));
					break;

				case Token.Type.Ident:
					Identifier id = Identifier.parse(l);

					Expression v;

					if(l.type == Token.Type.Assign)
					{
						l.next();
						v = Expression.parse(l);
					}
					else
						v = new NullExp(id.location);

					l.statementTerm();
					addField(id, v);
					break;

				case Token.Type.EOF:
					auto e = new MDCompileException(l.loc, "Class at {} is missing its closing brace", location.toString());
					e.atEOF = true;
					throw e;

				default:
					l.tok.expected("Class method or field");
			}
		}

		l.tok.expect(Token.Type.RBrace);
		auto endLocation = l.loc;
		l.next();

		auto f = new Field[fields.length];

		uint i = 0;

		foreach(name, initializer; fields)
		{
			f[i].name = name;
			f[i].initializer = initializer;
			i++;
		}

		return new ClassDef(location, endLocation, name, baseClass, methods.values, f, attrs);
	}
	
	public void codeGen(FuncState s)
	{
		/*
		A class declaration/literal actually gets rewritten as a call to a function literal.  This allows
		super calls to work correctly within the methods, by making this class available as an upvalue to those
		methods.
		
		The expression (not the declaration):

		class A : B
		{
			this() { super(); }
			function fork() { super.fork(); }
			function spoon() { writefln("spoon"); }
		}

		is rewritten as:

		(function <class A>()
		{
			local __class;

			__class = class A : B
			{
				this() { __class.super.constructor(with this); }
				function fork() { __class.super.fork(with this); }
				function spoon() { writefln("spoon"); }
			};

			return __class;
		})();

		So a declaration amounts to the assignment of this function call into a variable.
		
		Notice that any methods that don't use supercalls aren't penalized with the creation of an upvalue for __class.
		*/
		
		Expression classExp = new class(this) Expression
		{
			private ClassDef mOuter;

			this(ClassDef _outer)
			{
				super(_outer.location, _outer.endLocation, AstTag.Other);
				mOuter = _outer;
			}

			override void codeGen(FuncState s)
			{
				baseClass.codeGen(s);
				Exp base;
				s.popSource(location.line, base);
				s.freeExpTempRegs(&base);

				uint destReg = s.pushRegister();
				uint nameConst = s.tagConst(s.codeStringConst(name.name));
				s.codeR(location.line, Op.Class, destReg, nameConst, base.index);

				FuncState.enterClass(mOuter);

				foreach(field; fields)
				{
					uint index = s.tagConst(s.codeStringConst(field.name));

					field.initializer.codeGen(s);
					Exp val;
					s.popSource(field.initializer.endLocation.line, val);

					s.codeR(field.initializer.endLocation.line, Op.FieldAssign, destReg, index, val.index);

					s.freeExpTempRegs(&val);
				}

				foreach(method; methods)
				{
					uint index = s.tagConst(s.codeStringConst(method.name.name));

					method.codeGen(s, true);
					Exp val;
					s.popSource(method.endLocation.line, val);

					s.codeR(method.endLocation.line, Op.FieldAssign, destReg, index, val.index);

					s.freeExpTempRegs(&val);
				}

				FuncState.leaveClass();

				if(attrs)
				{
					attrs.codeGen(s);
					Exp src;
					s.popSource(location.line, src);
					s.freeExpTempRegs(&src);
					s.codeR(location.line, Op.SetAttrs, destReg, src.index, 0);
				}

				s.pushTempReg(destReg);
			}

			override InstRef* codeCondition(FuncState fs)
			{
				assert(false);
			}
		};

		Identifier __class = new Identifier(location, "__class");
		Expression __classExp = new IdentExp(__class);

  		CompoundStatement funcBody = new CompoundStatement(location, endLocation,
  		[
	  		cast(Statement)new VarDecl(location, location, Protection.Local, [__class], null),
			new ExpressionStatement(location, endLocation, new Assignment(location, endLocation, [__classExp], classExp)),
			new ReturnStatement(__classExp)
		]);

		FuncLiteralExp func = new FuncLiteralExp(location, new FuncDef(location, name, [FuncDef.Param(new Identifier(location, "this"))], false, funcBody));

		(new CallExp(location, endLocation, func, null, null)).codeGen(s);
	}

	public ClassDef fold()
	{
		baseClass = baseClass.fold();

		foreach(ref field; fields)
			field.initializer = field.initializer.fold();

		foreach(ref method; methods)
			method = method.fold();
		
		if(attrs)
			attrs = attrs.fold();

		return this;
	}

	public bool hasBase()
	{
		return !baseClass.isNull();
	}
}

class FuncDef : AstNode
{
	struct Param
	{
		Identifier name;
		Expression defValue;
	}

	public Identifier name;
	public Param[] params;
	public bool isVararg;
	public Statement code;
	public TableCtorExp attrs;

	public this(Location location, Identifier name, Param[] params, bool isVararg, Statement code, TableCtorExp attrs = null)
	{
		super(location, code.endLocation, AstTag.FuncDef);
		this.params = params;
		this.isVararg = isVararg;
		this.code = code;
		this.name = name;
		this.attrs = attrs;
	}
	
	public static FuncDef parseBody(Lexer l, Location location, Identifier name, TableCtorExp attrs = null)
	{
		bool isVararg;
		Param[] params = parseParams(l, isVararg);
		
		Statement code;

		if(l.type == Token.Type.Assign)
		{
			l.next;
			code = new ReturnStatement(Expression.parse(l));
		}
		else
			code = Statement.parse(l);

		return new FuncDef(location, name, params, isVararg, code, attrs);
	}

	public static FuncDef parseSimple(Lexer l, TableCtorExp attrs = null)
	{
		auto location = l.expect(Token.Type.Function).location;
		auto name = Identifier.parse(l);

		return parseBody(l, location, name, attrs);
	}
	
	public static FuncDef parseLiteral(Lexer l)
	{
		auto location = l.expect(Token.Type.Function).location;

		Identifier name;

		if(l.type == Token.Type.Ident)
			name = Identifier.parse(l);
		else
			name = new Identifier(location, "<literal at " ~ utf.toString32(location.toString()) ~ ">");

		return parseBody(l, location, name);
	}

	public static Param[] parseParams(Lexer l, out bool isVararg)
	{
		Param[] ret = new Param[1];

		ret[0].name = new Identifier(l.loc, "this");

		l.expect(Token.Type.LParen);

		while(l.type != Token.Type.RParen)
		{
			if(l.type == Token.Type.Vararg)
			{
				isVararg = true;
				l.next();
				break;
			}

			Identifier name = Identifier.parse(l);
			Expression defValue = null;

			if(l.type == Token.Type.Assign)
			{
				l.next();
				defValue = Expression.parse(l);
			}

			ret ~= Param(name, defValue);

			if(l.type == Token.Type.RParen)
				break;

			l.expect(Token.Type.Comma);
		}

		l.expect(Token.Type.RParen);
		return ret;
	}

	public void codeGen(FuncState s, bool isMethod = false)
	{
		FuncState fs = new FuncState(location, name.name, s, isMethod);

		fs.mIsVararg = isVararg;
		fs.mNumParams = params.length;

		foreach(p; params)
			fs.insertLocal(p.name);

		fs.activateLocals(params.length);

		foreach(p; params)
			if(p.defValue !is null)
				(new OpEqExp(p.name.location, p.name.location, AstTag.CondAssign, new IdentExp(p.name), p.defValue)).codeGen(fs);

		code.codeGen(fs);
		fs.codeI(code.endLocation.line, Op.Ret, 0, 1);
		fs.popScope(code.endLocation.line);

		if(attrs is null)
			s.pushClosure(fs);
		else
		{
			attrs.codeGen(s);
			Exp src;
			s.popSource(location.line, src);
			s.pushClosure(fs, src.index);
		}
	}

	public FuncDef fold()
	{
		foreach(ref p; params)
			if(p.defValue !is null)
				p.defValue = p.defValue.fold();

		code = code.fold();
		
		if(attrs)
			attrs = attrs.fold();

		return this;
	}
}

class NamespaceDef : AstNode
{
	struct Field
	{
		dchar[] name;
		Expression initializer;
	}

	public Identifier name;
	public Expression parent;
	public Field[] fields;
	public TableCtorExp attrs;

	public this(Location location, Location endLocation, Identifier name, Expression parent, Field[] fields, TableCtorExp attrs = null)
	{
		super(location, endLocation, AstTag.NamespaceDef);
		this.name = name;
		this.parent = parent;
		this.fields = fields;
		this.attrs = attrs;
	}

	public static NamespaceDef parse(Lexer l, TableCtorExp attrs = null)
	{
		auto location = l.loc;
		l.expect(Token.Type.Namespace);

		Identifier name = Identifier.parse(l);
		Expression parent;

		if(l.type == Token.Type.Colon)
		{
			l.next();
			parent = Expression.parse(l);
		}
		else
			parent = new NullExp(l.loc);

		l.expect(Token.Type.LBrace);

		Expression[dchar[]] fields;

		void addField(dchar[] name, Expression v)
		{
			if(name in fields)
				throw new MDCompileException(v.location, "Redeclaration of member '{}'", name);

			fields[name] = v;
		}

		while(l.type != Token.Type.RBrace)
		{
			switch(l.type)
			{
				case Token.Type.Function:
					FuncDef fd = FuncDef.parseSimple(l);
					addField(fd.name.name, new FuncLiteralExp(fd.location, fd));
					break;

				case Token.Type.Ident:
					Identifier id = Identifier.parse(l);

					Expression v;

					if(l.type == Token.Type.Assign)
					{
						l.next();
						v = Expression.parse(l);
					}
					else
						v = new NullExp(id.location);

					l.statementTerm();
					addField(id.name, v);
					break;

				case Token.Type.EOF:
					auto e = new MDCompileException(l.loc, "Namespace at {} is missing its closing brace", location.toString());
					e.atEOF = true;
					throw e;

				default:
					l.tok.expected("Namespace member");
			}
		}

		Field[] fieldsArray = new Field[fields.length];

		uint i = 0;

		foreach(name, initializer; fields)
		{
			fieldsArray[i].name = name;
			fieldsArray[i].initializer = initializer;
			i++;
		}

		l.tok.expect(Token.Type.RBrace);
		auto endLocation = l.loc;
		l.next();
		
		return new NamespaceDef(location, endLocation, name, parent, fieldsArray, attrs);
	}
	
	public void codeGen(FuncState s)
	{
		parent.codeGen(s);
		Exp parent;
		s.popSource(location.line, parent);
		s.freeExpTempRegs(&parent);

		uint destReg = s.pushRegister();
		uint nameConst = s.tagConst(s.codeStringConst(name.name));
		s.codeR(location.line, Op.Namespace, destReg, nameConst, parent.index);

		foreach(field; fields)
		{
			uint index = s.tagConst(s.codeStringConst(field.name));

			field.initializer.codeGen(s);
			Exp val;
			s.popSource(field.initializer.endLocation.line, val);
			s.codeR(field.initializer.endLocation.line, Op.FieldAssign, destReg, index, val.index);
			s.freeExpTempRegs(&val);
		}

		if(attrs)
		{
			attrs.codeGen(s);
			Exp src;
			s.popSource(location.line, src);
			s.freeExpTempRegs(&src);
			s.codeR(location.line, Op.SetAttrs, destReg, src.index, 0);
		}

		s.pushTempReg(destReg);
	}

	public NamespaceDef fold()
	{
		foreach(ref field; fields)
			field.initializer = field.initializer.fold();

		if(attrs)
			attrs = attrs.fold();

		return this;
	}
}

class Module : AstNode
{
	public ModuleDeclaration modDecl;
	public Statement[] statements;

	public this(Location location, Location endLocation, ModuleDeclaration modDecl, Statement[] statements)
	{
		super(location, endLocation, AstTag.Module);
		this.modDecl = modDecl;
		this.statements = statements;
	}

	public static Module parse(Lexer l)
	{
		auto location = l.loc;
		auto modDecl = ModuleDeclaration.parse(l);

		List!(Statement) statements;

		while(l.type != Token.Type.EOF)
			statements.add(Statement.parse(l));

		l.tok.expect(Token.Type.EOF);

		return new Module(location, l.loc, modDecl, statements.toArray());
	}
	
	public MDModuleDef codeGen()
	{
		MDModuleDef def = new MDModuleDef();

		def.mName = join(modDecl.names, "."d);

		FuncState fs = new FuncState(location, "module " ~ modDecl.names[$ - 1]);
		fs.mIsVararg = true;

		try
		{
			modDecl.codeGen(fs);

			foreach(ref s; statements)
			{
				s = s.fold();
				s.codeGen(fs);
			}

			fs.codeI(endLocation.line, Op.Ret, 0, 1);
		}
		finally
		{
			//showMe(); fs.showMe(); Stdout.flush;
			//fs.printExpStack();
		}

		assert(fs.mExpSP == 0, "module - not all expressions have been popped");

		def.mFunc = fs.toFuncDef();

		return def;
	}

	public void showMe()
	{
		Stdout.formatln("module {}", join(modDecl.names, "."d));
	}
}

class ModuleDeclaration : AstNode
{
	public dchar[][] names;
	public TableCtorExp attrs;

	public this(Location location, Location endLocation, dchar[][] names, TableCtorExp attrs)
	{
		super(location, endLocation, AstTag.ModuleDecl);
		this.names = names;
		this.attrs = attrs;
	}

	public static ModuleDeclaration parse(Lexer l)
	{
		auto location = l.loc;

		TableCtorExp attrs;

		if(l.type == Token.Type.LAttr)
			attrs = TableCtorExp.parseAttrs(l);

		l.expect(Token.Type.Module);

		dchar[][] names;
		names ~= Identifier.parseName(l);

		while(l.type == Token.Type.Dot)
		{
			l.next();
			names ~= Identifier.parseName(l);
		}

		auto endLocation = l.loc;
		l.statementTerm();

		return new ModuleDeclaration(location, endLocation, names, attrs);
	}
	
	public void codeGen(FuncState s)
	{
		if(attrs is null)
			return;

		attrs.codeGen(s);
		Exp src;
		s.popSource(attrs.location.line, src);
		s.freeExpTempRegs(&src);

		// rd = 0 means 'this', i.e. the module.
		s.codeR(attrs.location.line, Op.SetAttrs, 0, src.index, 0);
	}
	
	public ModuleDeclaration fold()
	{
		if(attrs)
			attrs = attrs.fold();

		return this;
	}
}

abstract class Statement : AstNode
{
	public this(Location location, Location endLocation, AstTag type)
	{
		super(location, endLocation, type);
	}

	public static Statement parse(Lexer l, bool needScope = true)
	{
		switch(l.type)
		{
			case
				Token.Type.CharLiteral,
				Token.Type.Dec,
				Token.Type.False,
				Token.Type.FloatLiteral,
				Token.Type.Ident,
				Token.Type.Inc,
				Token.Type.IntLiteral,
				Token.Type.LBracket,
				Token.Type.Length,
				Token.Type.LParen,
				Token.Type.Null,
				Token.Type.Or,
				Token.Type.StringLiteral,
				Token.Type.Super,
				Token.Type.This,
				Token.Type.True,
				Token.Type.Vararg,
				Token.Type.Yield:

				return ExpressionStatement.parse(l);

			case
				Token.Type.Class,
				Token.Type.Function,
				Token.Type.Global,
				Token.Type.LAttr,
				Token.Type.Local,
				Token.Type.Namespace:

				return DeclStatement.parse(l);

			case Token.Type.LBrace:
				if(needScope)
					return new ScopeStatement(CompoundStatement.parse(l));
				else
					return CompoundStatement.parse(l);
					
			case Token.Type.Break:    return BreakStatement.parse(l);
			case Token.Type.Continue: return ContinueStatement.parse(l);
			case Token.Type.Do:       return DoWhileStatement.parse(l);
			case Token.Type.For:      return ForStatement.parse(l);
			case Token.Type.Foreach:  return ForeachStatement.parse(l);
			case Token.Type.If:       return IfStatement.parse(l);
			case Token.Type.Import:   return ImportStatement.parse(l);
			case Token.Type.Return:   return ReturnStatement.parse(l);
			case Token.Type.Switch:   return SwitchStatement.parse(l);
			case Token.Type.Throw:    return ThrowStatement.parse(l);
			case Token.Type.Try:      return TryCatchStatement.parse(l);
			case Token.Type.While:    return WhileStatement.parse(l);

			case Token.Type.Semicolon:
				throw new MDCompileException(l.loc, "Empty statements ( ';' ) are not allowed (use {{} for an empty statement)");

			default:
				l.tok.expected("Statement");
		}
	}
	
	public abstract void codeGen(FuncState s);
	public abstract Statement fold();
}

class ImportStatement : Statement
{
	public Expression expr;
	public Identifier[] symbols;

	public this(Location location, Location endLocation, Expression expr, Identifier[] symbols)
	{
		super(location, endLocation, AstTag.ImportStmt);
		this.expr = expr;
		this.symbols = symbols;
	}

	public static ImportStatement parse(Lexer l)
	{
		auto location = l.loc;

		l.expect(Token.Type.Import);

		Expression expr;

		if(l.type == Token.Type.LParen)
		{
			l.next();
			expr = Expression.parse(l);
			l.expect(Token.Type.RParen);
		}
		else
		{
			dchar[] name = Identifier.parseName(l);

			while(l.type == Token.Type.Dot)
			{
				l.next();
				name ~= "." ~ Identifier.parseName(l);
			}

			expr = new StringExp(location, name);
		}

		Identifier[] symbols;

		if(l.type == Token.Type.Colon)
		{
			l.next();
			symbols ~= Identifier.parse(l);

			while(l.type == Token.Type.Comma)
			{
				l.next();
				symbols ~= Identifier.parse(l);
			}
		}
		
		auto endLocation = l.loc;
		l.statementTerm();
		return new ImportStatement(location, endLocation, expr, symbols);
	}
	
	public override void codeGen(FuncState s)
	{
		foreach(i, sym; symbols)
		{
			foreach(sym2; symbols[0 .. i])
			{
				if(sym.name == sym2.name)
				{
					throw new MDCompileException(sym.location, "Variable '{}' conflicts with previous definition at {}",
						sym.name, sym2.location.toString());
				}
			}
		}

		uint firstReg = s.nextRegister();

		foreach(sym; symbols)
			s.pushRegister();

		uint importReg = s.nextRegister();

		expr.codeGen(s);
		Exp src;
		s.popSource(location.line, src);

		assert(s.nextRegister() == importReg, "bad import regs");

		s.codeR(location.line, Op.Import, importReg, src.index, 0);

		for(int reg = firstReg + symbols.length - 1; reg >= firstReg; reg--)
			s.popRegister(reg);

		foreach(i, sym; symbols)
		{
			s.codeR(location.line, Op.Field, firstReg + i, importReg, s.tagConst(s.codeStringConst(sym.name)));
			s.insertLocal(sym);
		}

		s.activateLocals(symbols.length);
	}
	
	public override Statement fold()
	{
		expr = expr.fold();
		return this;
	}
}

class ScopeStatement : Statement
{
	public Statement statement;

	public this(Statement statement)
	{
		super(statement.location, statement.endLocation, AstTag.ScopeStmt);
		this.statement = statement;
	}
	
	public override void codeGen(FuncState s)
	{
		s.pushScope();
		statement.codeGen(s);
		s.popScope(endLocation.line);
	}

	public override Statement fold()
	{
		statement = statement.fold();
		return this;
	}
}

class ExpressionStatement : Statement
{
	public Expression expr;

	public this(Location location, Location endLocation, Expression expr)
	{
		super(location, endLocation, AstTag.ExpressionStmt);
		this.expr = expr;
	}

	public static ExpressionStatement parse(Lexer l)
	{
		auto location = l.loc;
		auto exp = Expression.parseStatement(l);
		auto endLocation = l.loc;
		l.statementTerm();

		return new ExpressionStatement(location, endLocation, exp);
	}
	
	public override void codeGen(FuncState s)
	{
		int freeRegCheck = s.mFreeReg;

		expr.codeGen(s);
		s.popToNothing();

		assert(s.mFreeReg == freeRegCheck, "not all regs freed");
	}

	public override Statement fold()
	{
		expr = expr.fold();
		return this;
	}
}

enum Protection
{
	Default,
	Local,
	Global
}

abstract class DeclStatement : Statement
{
	public Protection protection;

	public this(Location location, Location endLocation, AstTag type, Protection protection)
	{
		super(location, endLocation, type);
		this.protection = protection;
	}

	public static DeclStatement parse(Lexer l, TableCtorExp attrs = null)
	{
		switch(l.type)
		{
			case Token.Type.Local, Token.Type.Global:
				switch(l.peek.type)
				{
					case Token.Type.Ident:
						if(attrs !is null)
							throw new MDCompileException(l.loc, "Cannot attach attributes to variables");

						VarDecl ret = VarDecl.parse(l);
						l.statementTerm();
						return ret;
					
					case Token.Type.Function:
		            	return FuncDecl.parse(l, attrs);

					case Token.Type.Class:
						return ClassDecl.parse(l, attrs);

					case Token.Type.Namespace:
						return NamespaceDecl.parse(l, attrs);

					default:
						throw new MDCompileException(l.loc, "Illegal token '{}' after '{}'", l.peek.toString(), l.tok.toString());
				}

			case Token.Type.Function:
				return FuncDecl.parse(l, attrs);

			case Token.Type.Class:
				return ClassDecl.parse(l, attrs);

			case Token.Type.Namespace:
				return NamespaceDecl.parse(l, attrs);

			case Token.Type.LAttr:
				if(attrs is null)
					return DeclStatement.parse(l, TableCtorExp.parseAttrs(l));
				else
					l.tok.expected("Declaration");

			default:
				l.tok.expected("Declaration");
		}
	}
}

class ClassDecl : DeclStatement
{
	public ClassDef def;

	public this(Location location, Protection protection, ClassDef def)
	{
		super(location, def.endLocation, AstTag.ClassDecl, protection);
		this.def = def;
	}

	public static ClassDecl parse(Lexer l, TableCtorExp attrs = null)
	{
		auto location = l.loc;
		auto protection = Protection.Default;

		if(l.type == Token.Type.Global)
		{
			protection = Protection.Global;
			l.next();
		}
		else if(l.type == Token.Type.Local)
		{
			protection = Protection.Local;
			l.next();
		}

		return new ClassDecl(location, protection, ClassDef.parse(l, false, attrs));
	}
	
	public override void codeGen(FuncState s)
	{
		if(protection == Protection.Default)
			protection = s.isTopLevel() ? Protection.Global : Protection.Local;

		if(protection == Protection.Local)
		{
			s.insertLocal(def.name);
			s.activateLocals(1);
			s.pushVar(def.name);
		}
		else
		{
			assert(protection == Protection.Global);
			s.pushNewGlobal(def.name);
		}

		def.codeGen(s);

		s.popAssign(endLocation.line);
	}

	public override Statement fold()
	{
		def = def.fold();
		return this;
	}
}

class VarDecl : DeclStatement
{
	public Identifier[] names;
	public Expression initializer;

	public this(Location location, Location endLocation, Protection protection, Identifier[] names, Expression initializer)
	{
		super(location, endLocation, AstTag.VarDecl, protection);
		this.names = names;
		this.initializer = initializer;
	}

	public static VarDecl parse(Lexer l)
	{
		auto location = l.loc;
		auto protection = Protection.Local;

		if(l.type == Token.Type.Global)
		{
			protection = Protection.Global;
			l.next();
		}
		else
			l.expect(Token.Type.Local);

		Identifier[] names;
		names ~= Identifier.parse(l);

		while(l.type == Token.Type.Comma)
		{
			l.next();
			names ~= Identifier.parse(l);
		}
		
		auto endLocation = names[$ - 1].location;

		Expression initializer;

		if(l.type == Token.Type.Assign)
		{
			l.next();
			initializer = Expression.parse(l);
			endLocation = initializer.endLocation;
		}

		return new VarDecl(location, endLocation, protection, names, initializer);
	}
	
	public override void codeGen(FuncState s)
	{
		// Check for name conflicts within the definition
		foreach(i, n; names)
		{
			foreach(n2; names[0 .. i])
			{
				if(n.name == n2.name)
				{
					throw new MDCompileException(n.location, "Variable '{}' conflicts with previous definition at {}",
						n.name, n2.location.toString());
				}
			}
		}

		if(protection == Protection.Global)
		{
			if(initializer)
			{
				if(names.length == 1)
				{
					s.pushNewGlobal(names[0]);
					initializer.codeGen(s);
					s.popAssign(initializer.endLocation.line);
				}
				else
				{
					initializer.checkMultRet();

					foreach(n; names)
						s.pushNewGlobal(n);

					uint reg = s.nextRegister();
					initializer.codeGen(s);
					s.popToRegisters(endLocation.line, reg, names.length);

					for(int r = reg + names.length - 1; r >= reg; r--)
						s.popMoveFromReg(endLocation.line, r);
				}
			}
			else
			{
				foreach(n; names)
				{
					s.pushNewGlobal(n);
					s.pushNull();
					s.popAssign(n.location.line);
				}
			}
		}
		else
		{
			assert(protection == Protection.Local);

			if(initializer)
			{
				if(names.length == 1)
				{
					uint destReg = s.nextRegister();
					initializer.codeGen(s);
					s.popMoveTo(location.line, destReg);
					s.insertLocal(names[0]);
				}
				else
				{
					uint destReg = s.nextRegister();
					initializer.checkMultRet();
					initializer.codeGen(s);
					s.popToRegisters(location.line, destReg, names.length);

					foreach(n; names)
						s.insertLocal(n);
				}
			}
			else
			{
				uint reg = s.nextRegister();

				foreach(n; names)
					s.insertLocal(n);

				s.codeNulls(location.line, reg, names.length);
			}

			s.activateLocals(names.length);
		}
	}

	public override VarDecl fold()
	{
		if(initializer)
			initializer = initializer.fold();
	
		return this;
	}
}

class FuncDecl : DeclStatement
{
	public FuncDef def;

	public this(Location location, Protection protection, FuncDef def)
	{
		super(location, def.endLocation, AstTag.FuncDecl, protection);

		this.def = def;
	}

	public static FuncDecl parse(Lexer l, TableCtorExp attrs = null)
	{
		auto location = l.loc;
		auto protection = Protection.Default;

		if(l.type == Token.Type.Global)
		{
			protection = Protection.Global;
			l.next();
		}
		else if(l.type == Token.Type.Local)
		{
			protection = Protection.Local;
			l.next();
		}

		return new FuncDecl(location, protection, FuncDef.parseSimple(l, attrs));
	}
	
	public override void codeGen(FuncState s)
	{
		if(protection == Protection.Default)
			protection = s.isTopLevel() ? Protection.Global : Protection.Local;

		if(protection == Protection.Local)
		{
			s.insertLocal(def.name);
			s.activateLocals(1);
			s.pushVar(def.name);
		}
		else
		{
			assert(protection == Protection.Global);
			s.pushNewGlobal(def.name);
		}

		def.codeGen(s);
		s.popAssign(endLocation.line);
	}

	public override Statement fold()
	{
		def = def.fold();
		return this;
	}
}

class NamespaceDecl : DeclStatement
{
	public NamespaceDef def;

	public this(Location location, Protection protection, NamespaceDef def)
	{
		super(location, def.endLocation, AstTag.NamespaceDecl, protection);

		this.def = def;
	}

	public static NamespaceDecl parse(Lexer l, TableCtorExp attrs = null)
	{
		auto location = l.loc;
		auto protection = Protection.Default;

		if(l.type == Token.Type.Global)
		{
			protection = Protection.Global;
			l.next();
		}
		else if(l.type == Token.Type.Local)
		{
			protection = Protection.Local;
			l.next();
		}

		return new NamespaceDecl(location, protection, NamespaceDef.parse(l, attrs));
	}
	
	public override void codeGen(FuncState s)
	{
		if(protection == Protection.Default)
			protection = s.isTopLevel() ? Protection.Global : Protection.Local;

		if(protection == Protection.Local)
		{
			s.insertLocal(def.name);
			s.activateLocals(1);
			s.pushVar(def.name);
		}
		else
		{
			assert(protection == Protection.Global);
			s.pushNewGlobal(def.name);
		}

		def.codeGen(s);
		s.popAssign(endLocation.line);
	}

	public override Statement fold()
	{
		def = def.fold();
		return this;
	}
}

class CompoundStatement : Statement
{
	public Statement[] statements;

	public this(Location location, Location endLocation, Statement[] statements)
	{
		super(location, endLocation, AstTag.BlockStmt);
		this.statements = statements;
	}

	public static CompoundStatement parse(Lexer l)
	{
		auto location = l.expect(Token.Type.LBrace).location;

		List!(Statement) statements;

		while(l.type != Token.Type.RBrace)
			statements.add(Statement.parse(l));

		auto endLocation = l.expect(Token.Type.RBrace).location;
		return new CompoundStatement(location, endLocation, statements.toArray());
	}

	public override void codeGen(FuncState s)
	{
		foreach(st; statements)
			st.codeGen(s);
	}

	public override CompoundStatement fold()
	{
		foreach(ref statement; statements)
			statement = statement.fold();

		return this;
	}
}

class IfStatement : Statement
{
	public Identifier condVar;
	public Expression condition;
	public Statement ifBody;
	public Statement elseBody;

	public this(Location location, Location endLocation, Identifier condVar, Expression condition, Statement ifBody, Statement elseBody)
	{
		super(location, endLocation, AstTag.IfStmt);

		this.condVar = condVar;
		this.condition = condition;
		this.ifBody = ifBody;
		this.elseBody = elseBody;
	}

	public static IfStatement parse(Lexer l)
	{
		auto location = l.expect(Token.Type.If).location;
		l.expect(Token.Type.LParen);

		Identifier condVar;

		if(l.type == Token.Type.Local)
		{
			l.next();
			condVar = Identifier.parse(l);
			l.expect(Token.Type.Assign);
		}

		auto condition = Expression.parse(l);
		l.expect(Token.Type.RParen);
		auto ifBody = Statement.parse(l);

		Statement elseBody;

		auto endLocation = ifBody.endLocation;

		if(l.type == Token.Type.Else)
		{
			l.next();
			elseBody = Statement.parse(l);
			endLocation = elseBody.endLocation;
		}

		return new IfStatement(location, endLocation, condVar, condition, ifBody, elseBody);
	}

	public override void codeGen(FuncState s)
	{
		InstRef* i;

		s.pushScope();

		if(condVar !is null)
		{
			uint destReg = s.nextRegister();
			condition.codeGen(s);
			s.popMoveTo(location.line, destReg);
			s.insertLocal(condVar);
			s.activateLocals(1);

			i = (new IdentExp(condVar)).codeCondition(s);
		}
		else
			i = condition.codeCondition(s);

		s.invertJump(i);
		s.patchTrueToHere(i);
		ifBody.codeGen(s);

		if(elseBody)
		{
			s.popScope(ifBody.endLocation.line);

			InstRef* j = s.makeJump(elseBody.location.line);
			s.patchFalseToHere(i);
			s.patchJumpToHere(i);

			s.pushScope();
				elseBody.codeGen(s);
			s.popScope(endLocation.line);

			s.patchJumpToHere(j);
			delete j;
		}
		else
		{
			s.popScope(ifBody.endLocation.line);
			s.patchFalseToHere(i);
			s.patchJumpToHere(i);
		}

		delete i;
	}

	public override Statement fold()
	{
		condition = condition.fold();
		ifBody = ifBody.fold();

		if(elseBody)
			elseBody = elseBody.fold();

		if(condition.isConstant)
		{
			if(condition.isTrue)
				return ifBody;
			else
			{
				if(elseBody)
					return elseBody;
				else
					return new CompoundStatement(location, endLocation, null);
			}
		}

		return this;
	}
}

class WhileStatement : Statement
{
	public Identifier condVar;
	public Expression condition;
	public Statement code;

	public this(Location location, Identifier condVar, Expression condition, Statement code)
	{
		super(location, code.endLocation, AstTag.WhileStmt);

		this.condVar = condVar;
		this.condition = condition;
		this.code = code;
	}

	public static WhileStatement parse(Lexer l)
	{
		auto location = l.expect(Token.Type.While).location;
		l.expect(Token.Type.LParen);
		
		Identifier condVar;

		if(l.type == Token.Type.Local)
		{
			l.next();
			condVar = Identifier.parse(l);
			l.expect(Token.Type.Assign);
		}

		auto condition = Expression.parse(l);
		l.expect(Token.Type.RParen);
		auto code = Statement.parse(l, false);
		return new WhileStatement(location, condVar, condition, code);
	}
	
	public override void codeGen(FuncState s)
	{
		InstRef* beginLoop = s.getLabel();

		if(condition.isConstant && condition.isTrue)
		{
			if(condVar !is null)
			{
				s.pushScope();
					s.setBreakable();
					s.setContinuable();

					uint destReg = s.nextRegister();
					condition.codeGen(s);
					s.popMoveTo(location.line, destReg);
					s.insertLocal(condVar);
					s.activateLocals(1);

					code.codeGen(s);
					s.patchContinues(beginLoop);
					s.codeJump(endLocation.line, beginLoop);
					s.patchBreaksToHere();
				s.popScope(endLocation.line);
			}
			else
			{
				s.pushScope();
					s.setBreakable();
					s.setContinuable();
					code.codeGen(s);
					s.patchContinues(beginLoop);
					s.codeJump(endLocation.line, beginLoop);
					s.patchBreaksToHere();
				s.popScope(endLocation.line);
			}
		}
		else
		{
			s.pushScope();
				InstRef* cond;

				if(condVar !is null)
				{
					uint destReg = s.nextRegister();
					condition.codeGen(s);
					s.popMoveTo(location.line, destReg);
					s.insertLocal(condVar);
					s.activateLocals(1);

					cond = (new IdentExp(condVar)).codeCondition(s);
				}
				else
					cond = condition.codeCondition(s);

				s.invertJump(cond);
				s.patchTrueToHere(cond);

				s.setBreakable();
				s.setContinuable();
				code.codeGen(s);
				s.patchContinues(beginLoop);
				s.closeUpvals(endLocation.line);
				s.codeJump(endLocation.line, beginLoop);
				s.patchBreaksToHere();
			s.popScope(endLocation.line);

			s.patchFalseToHere(cond);
			s.patchJumpToHere(cond);

			delete cond;
		}

		delete beginLoop;
	}

	public override Statement fold()
	{
		condition = condition.fold();
		code = code.fold();

		if(condition.isConstant && !condition.isTrue)
			return new CompoundStatement(location, endLocation, null);

		return this;
	}
}

class DoWhileStatement : Statement
{
	public Statement code;
	public Expression condition;

	public this(Location location, Location endLocation, Statement code, Expression condition)
	{
		super(location, endLocation, AstTag.DoWhileStmt);

		this.code = code;
		this.condition = condition;
	}

	public static DoWhileStatement parse(Lexer l)
	{
		auto location = l.expect(Token.Type.Do).location;
		auto doBody = Statement.parse(l, false);

		l.expect(Token.Type.While);
		l.expect(Token.Type.LParen);

		auto condition = Expression.parse(l);
		auto endLocation = l.expect(Token.Type.RParen).location;
		return new DoWhileStatement(location, endLocation, doBody, condition);
	}

	public override void codeGen(FuncState s)
	{
		InstRef* beginLoop = s.getLabel();

		if(condition.isConstant && condition.isTrue)
		{
			s.pushScope();
				s.setBreakable();
				s.setContinuable();
				code.codeGen(s);
				s.patchContinuesToHere();
				s.codeJump(endLocation.line, beginLoop);
				s.patchBreaksToHere();
			s.popScope(endLocation.line);
		}
		else
		{
			s.pushScope();
				s.setBreakable();
				s.setContinuable();
				code.codeGen(s);
				s.closeUpvals(condition.location.line);
				s.patchContinuesToHere();
				InstRef* cond = condition.codeCondition(s);
				s.invertJump(cond);
				s.patchTrueToHere(cond);
				s.codeJump(endLocation.line, beginLoop);
				s.patchBreaksToHere();
			s.popScope(endLocation.line);

			s.patchFalseToHere(cond);
			s.patchJumpToHere(cond);

			delete cond;
		}

		delete beginLoop;
	}

	public override Statement fold()
	{
		code = code.fold();
		condition = condition.fold();

		if(condition.isConstant && !condition.isTrue)
			return code;

		return this;
	}
}

class ForStatement : Statement
{
	struct ForInitializer
	{
		bool isDecl = false;

		union
		{
			Expression init;
			VarDecl decl;
		}
	}

	public ForInitializer[] init;
	public VarDecl initDecl;
	public Expression condition;
	public Expression[] increment;
	public Statement code;

	public this(Location location, ForInitializer[] init, Expression cond, Expression[] inc, Statement code)
	{
		super(location, endLocation, AstTag.ForStmt);

		this.init = init;
		this.condition = cond;
		this.increment = inc;
		this.code = code;
	}

	public static Statement parse(Lexer l)
	{
		auto location = l.expect(Token.Type.For).location;
		l.expect(Token.Type.LParen);

		ForInitializer[] init;

		void parseInitializer()
		{
			init.length = init.length + 1;

			if(l.type == Token.Type.Local)
			{
				init[$ - 1].isDecl = true;
				init[$ - 1].decl = VarDecl.parse(l);
			}
			else
				init[$ - 1].init = Expression.parseStatement(l);
		}

		if(l.type == Token.Type.Semicolon)
			l.next();
		else if(l.type == Token.Type.Ident && l.peek.type == Token.Type.Colon)
		{
			auto index = Identifier.parse(l);

			l.expect(Token.Type.Colon);

			auto lo = Expression.parse(l);
			l.expect(Token.Type.DotDot);
			auto hi = Expression.parse(l);

			Expression step;

			if(l.type == Token.Type.Comma)
			{
				l.next();
				step = Expression.parse(l);
			}
			else
				step = new IntExp(location, 1);

			l.expect(Token.Type.RParen);

			auto code = Statement.parse(l);
			return new NumericForStatement(location, index, lo, hi, step, code);
		}
		else
		{
			parseInitializer();

			while(l.type == Token.Type.Comma)
			{
				l.next();
				parseInitializer();
			}

			l.expect(Token.Type.Semicolon);
		}

		Expression condition;

		if(l.type == Token.Type.Semicolon)
			l.next();
		else
		{
			condition = Expression.parse(l);
			l.expect(Token.Type.Semicolon);
		}

		Expression[] increment;

		if(l.type == Token.Type.RParen)
			l.next();
		else
		{
			increment ~= Expression.parseStatement(l);

			while(l.type == Token.Type.Comma)
			{
				l.next();
				increment ~= Expression.parseStatement(l);
			}

			l.expect(Token.Type.RParen);
		}

		auto code = Statement.parse(l, false);
		return new ForStatement(location, init, condition, increment, code);
	}

	public override void codeGen(FuncState s)
	{
		s.pushScope();
			s.setBreakable();
			s.setContinuable();

			foreach(init; init)
			{
				if(init.isDecl)
					init.decl.codeGen(s);
				else
				{
					init.init.codeGen(s);
					s.popToNothing();
				}
			}

			InstRef* beginLoop = s.getLabel();
			InstRef* cond;

			if(condition)
			{
				cond = condition.codeCondition(s);
				s.invertJump(cond);
				s.patchTrueToHere(cond);
			}

			code.codeGen(s);

			s.closeUpvals(location.line);
			s.patchContinuesToHere();

			foreach(inc; increment)
			{
				inc.codeGen(s);
				s.popToNothing();
			}

			s.codeJump(endLocation.line, beginLoop);
			delete beginLoop;

			s.patchBreaksToHere();
		s.popScope(endLocation.line);

		if(condition)
		{
			s.patchFalseToHere(cond);
			s.patchJumpToHere(cond);
			delete cond;
		}
	}

	public override Statement fold()
	{
		foreach(ref i; init)
		{
			if(i.isDecl)
				i.decl = i.decl.fold();
			else
				i.init = i.init.fold();
		}

		if(condition)
			condition = condition.fold();

		foreach(ref inc; increment)
			inc = inc.fold();

		code = code.fold();

		if(condition && condition.isConstant)
		{
			if(condition.isTrue)
				condition = null;
			else
			{
				if(init.length > 0)
				{
					Statement[] inits;

					foreach(i; init)
					{
						if(i.isDecl)
							inits ~= i.decl;
						else
							inits ~= new ExpressionStatement(i.init.location, i.init.endLocation, i.init);
					}

					return new ScopeStatement(new CompoundStatement(location, endLocation, inits));
				}
				else
					return new CompoundStatement(location, endLocation, null);
			}
		}

		return this;
	}
}

class NumericForStatement : Statement
{
	public Identifier index;
	public Expression lo;
	public Expression hi;
	public Expression step;
	public Statement code;

	public this(Location location, Identifier index, Expression lo, Expression hi, Expression step, Statement code)
	{
		super(location, code.endLocation, AstTag.ForNumStmt);

		this.index = index;
		this.lo = lo;
		this.hi = hi;
		this.step = step;
		this.code = code;
	}
	
	public override void codeGen(FuncState s)
	{
		uint baseReg = s.nextRegister();
		uint loIndex;
		uint hiIndex;
		uint stepIndex;

		s.pushScope();
			s.setBreakable();
			s.setContinuable();

			loIndex = s.nextRegister();
			lo.codeGen(s);
			s.popMoveTo(lo.location.line, loIndex);
			s.pushRegister();

			hiIndex = s.nextRegister();
			hi.codeGen(s);
			s.popMoveTo(hi.location.line, hiIndex);
			s.pushRegister();

			stepIndex = s.nextRegister();
			step.codeGen(s);
			s.popMoveTo(step.location.line, stepIndex);
			s.pushRegister();

			InstRef* beginJump = s.makeFor(location.line, baseReg);
			InstRef* beginLoop = s.getLabel();

			s.insertLocal(index);
			s.activateLocals(1);

			code.codeGen(s);

			s.closeUpvals(endLocation.line);
			s.patchContinuesToHere();

			s.patchJumpToHere(beginJump);
			delete beginJump;

			InstRef* gotoBegin = s.makeForLoop(endLocation.line, baseReg);
			s.patchJumpTo(gotoBegin, beginLoop);

			delete beginLoop;
			delete gotoBegin;

			s.patchBreaksToHere();
		s.popScope(endLocation.line);

		s.popRegister(stepIndex);
		s.popRegister(hiIndex);
		s.popRegister(loIndex);
	}
	
	public override Statement fold()
	{
		lo = lo.fold();
		hi = hi.fold();
		step = step.fold();

		if(lo.isConstant && !lo.isInt)
			throw new MDCompileException(lo.location, "Low value of a numeric for loop must be an integer");

		if(hi.isConstant && !hi.isInt)
			throw new MDCompileException(hi.location, "High value of a numeric for loop must be an integer");

		if(step.isConstant)
		{
			if(!step.isInt)
				throw new MDCompileException(step.location, "Step value of a numeric for loop must be an integer");

			if(step.asInt() == 0)
				throw new MDCompileException(step.location, "Step value of a numeric for loop may not be 0");
		}

		code = code.fold();
		return this;
	}
}

class ForeachStatement : Statement
{
	public Identifier[] indices;
	public Expression[] container;
	public Statement code;

	public this(Location location, Identifier[] indices, Expression[] container, Statement code)
	{
		super(location, code.endLocation, AstTag.ForeachStmt);

		this.indices = indices;
		this.container = container;
		this.code = code;
	}

	private static Identifier dummyIndex(Location l)
	{
		static uint counter = 0;
		return new Identifier(l, "__dummy"d ~ Integer.toString32(counter++));
	}

	public static ForeachStatement parse(Lexer l)
	{
		auto location = l.expect(Token.Type.Foreach).location;
		l.expect(Token.Type.LParen);

		Identifier[] indices;

		indices ~= Identifier.parse(l);

		while(l.type == Token.Type.Comma)
		{
			l.next();
			indices ~= Identifier.parse(l);
		}

		if(indices.length == 1)
			indices = dummyIndex(indices[0].location) ~ indices;

		l.expect(Token.Type.Semicolon);

		Expression[] container;
		container ~= Expression.parse(l);

		while(l.type == Token.Type.Comma)
		{
			l.next();
			container ~= Expression.parse(l);
		}

		if(container.length > 3)
			throw new MDCompileException(location, "'foreach' may have a maximum of three container expressions");

		l.expect(Token.Type.RParen);

		auto code = Statement.parse(l);
		return new ForeachStatement(location, indices, container, code);
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

			if(container.length == 3)
			{
				generator = s.nextRegister();
				container[0].codeGen(s);
				s.popMoveTo(container[0].location.line, generator);
				s.pushRegister();

				invState = s.nextRegister();
				container[1].codeGen(s);
				s.popMoveTo(container[1].location.line, invState);
				s.pushRegister();

				control = s.nextRegister();
				container[2].codeGen(s);
				s.popMoveTo(container[2].location.line, control);
				s.pushRegister();
			}
			else if(container.length == 2)
			{
				generator = s.nextRegister();
				container[0].codeGen(s);
				s.popMoveTo(container[0].location.line, generator);
				s.pushRegister();

				invState = s.nextRegister();
				container[1].codeGen(s);

				if(container[1].isMultRet())
				{
					s.popToRegisters(container[1].location.line, invState, 2);
					s.pushRegister();
					control = s.pushRegister();
				}
				else
				{
					s.popMoveTo(container[1].location.line, invState);
					s.pushRegister();
					control = s.pushRegister();
					s.codeNulls(container[1].location.line, control, 1);
				}
			}
			else
			{
				generator = s.nextRegister();
				container[0].codeGen(s);

				if(container[0].isMultRet())
				{
					s.popToRegisters(container[0].location.line, generator, 3);
					s.pushRegister();
					invState = s.pushRegister();
					control = s.pushRegister();
				}
				else
				{
					s.popMoveTo(container[0].location.line, generator);
					s.pushRegister();
					invState = s.pushRegister();
					control = s.pushRegister();
					s.codeNulls(container[0].location.line, invState, 2);
				}
			}

			InstRef* beginJump = s.makeJump(location.line);
			InstRef* beginLoop = s.getLabel();

			foreach(i; indices)
				s.insertLocal(i);

			s.activateLocals(indices.length);
			code.codeGen(s);

			s.patchJumpToHere(beginJump);
			delete beginJump;

			s.closeUpvals(endLocation.line);
			s.patchContinuesToHere();
			s.codeI(endLocation.line, Op.Foreach, baseReg, indices.length);
			InstRef* gotoBegin = s.makeJump(endLocation.line, Op.Je);

			s.patchJumpTo(gotoBegin, beginLoop);
			delete beginLoop;
			delete gotoBegin;

			s.patchBreaksToHere();
		s.popScope(endLocation.line);

		s.popRegister(control);
		s.popRegister(invState);
		s.popRegister(generator);
	}

	public override Statement fold()
	{
		foreach(ref c; container)
			c = c.fold();

		code = code.fold();
		return this;
	}
}

class SwitchStatement : Statement
{
	public Expression condition;
	public CaseStatement[] cases;
	public DefaultStatement caseDefault;

	public this(Location location, Location endLocation, Expression condition, CaseStatement[] cases, DefaultStatement caseDefault)
	{
		super(location, endLocation, AstTag.SwitchStmt);
		this.condition = condition;
		this.cases = cases;
		this.caseDefault = caseDefault;
	}

	public static SwitchStatement parse(Lexer l)
	{
		auto location = l.expect(Token.Type.Switch).location;
		l.expect(Token.Type.LParen);

		auto condition = Expression.parse(l);

		l.expect(Token.Type.RParen);
		l.expect(Token.Type.LBrace);

		List!(CaseStatement) cases;

		while(l.type == Token.Type.Case)
			cases.add(CaseStatement.parse(l));

		if(cases.length == 0)
			throw new MDCompileException(location, "Switch statement must have at least one case statement");

		DefaultStatement caseDefault;

		if(l.type == Token.Type.Default)
			caseDefault = DefaultStatement.parse(l);

		auto endLocation = l.expect(Token.Type.RBrace).location;
		return new SwitchStatement(location, endLocation, condition, cases.toArray(), caseDefault);
	}

	public override void codeGen(FuncState s)
	{
		struct Case
		{
			Expression expr;
			CaseStatement stmt;
		}

		List!(Case) constCases;
		List!(Case) dynCases;

		foreach(caseStmt; cases)
		{
			foreach(cond; caseStmt.conditions)
			{
				if(cond.isConstant)
					constCases.add(Case(cond, caseStmt));
				else
					dynCases.add(Case(cond, caseStmt));
			}
		}

		s.pushScope();
			s.setBreakable();

			condition.codeGen(s);
			Exp src;
			s.popSource(location.line, src);

			foreach(c; dynCases)
			{
				c.expr.codeGen(s);
				Exp cond;
				s.popSource(location.line, cond);

				s.codeR(location.line, Op.SwitchCmp, 0, src.index, cond.index);
				c.stmt.addDynJump(s.makeJump(location.line, Op.Je, true));
				s.freeExpTempRegs(&cond);
			}

			s.beginSwitch(location.line, src.index);
			s.freeExpTempRegs(&src);

			foreach(c; constCases)
				c.stmt.addConstJump(s.addCase(c.expr.location, c.expr));

			foreach(c; cases)
				c.codeGen(s);

			if(caseDefault)
				caseDefault.codeGen(s);

			s.endSwitch();

			s.patchBreaksToHere();
		s.popScope(endLocation.line);
	}

	public override Statement fold()
	{
		condition = condition.fold();

		foreach(ref c; cases)
			c = c.fold();

		if(caseDefault)
			caseDefault = caseDefault.fold();

		return this;
	}
}

class CaseStatement : Statement
{
	public Expression[] conditions;
	public Statement code;
	protected List!(InstRef*) mDynJumps;
	protected List!(int*) mConstJumps;

	public this(Location location, Location endLocation, Expression[] conditions, Statement code)
	{
		super(location, endLocation, AstTag.CaseStmt);
		this.conditions = conditions;
		this.code = code;
	}

	public static CaseStatement parse(Lexer l)
	{
		auto location = l.expect(Token.Type.Case).location;

		List!(Expression) conditions;
		conditions.add(Expression.parse(l));

		while(l.type == Token.Type.Comma)
		{
			l.next();
			conditions.add(Expression.parse(l));
		}

		l.expect(Token.Type.Colon);

		List!(Statement) statements;

		while(l.type != Token.Type.Case && l.type != Token.Type.Default && l.type != Token.Type.RBrace)
			statements.add(Statement.parse(l));

		auto endLocation = l.loc;

		auto code = new ScopeStatement(new CompoundStatement(location, endLocation, statements.toArray()));
		return new CaseStatement(location, endLocation, conditions.toArray(), code);
	}
	
	public void addDynJump(InstRef* i)
	{
		mDynJumps.add(i);
	}

	public void addConstJump(int* i)
	{
		mConstJumps.add(i);
	}

	public override void codeGen(FuncState s)
	{
		foreach(ref j; mDynJumps)
		{
			s.patchJumpToHere(j);
			delete j;
		}

		foreach(ref j; mConstJumps)
		{
			s.patchSwitchJumpToHere(j);
			j = null;
		}

		code.codeGen(s);
	}

	public override CaseStatement fold()
	{
		foreach(ref cond; conditions)
			cond = cond.fold();

		code = code.fold();
		return this;
	}
}

class DefaultStatement : Statement
{
	public Statement code;

	public this(Location location, Location endLocation, Statement code)
	{
		super(location, endLocation, AstTag.DefaultStmt);
		this.code = code;
	}

	public static DefaultStatement parse(Lexer l)
	{
		auto location = l.loc;

		l.expect(Token.Type.Default);
		l.expect(Token.Type.Colon);

		List!(Statement) statements;

		while(l.type != Token.Type.RBrace)
			statements.add(Statement.parse(l));

		auto endLocation = l.loc;

		auto code = new ScopeStatement(new CompoundStatement(location, endLocation, statements.toArray()));
		return new DefaultStatement(location, endLocation, code);
	}
	
	public override void codeGen(FuncState s)
	{
		s.addDefault(location);
		code.codeGen(s);
	}

	public override DefaultStatement fold()
	{
		code = code.fold();
		return this;
	}
}

class ContinueStatement : Statement
{
	public this(Location location)
	{
		super(location, location, AstTag.ContinueStmt);
	}

	public static ContinueStatement parse(Lexer l)
	{
		auto location = l.expect(Token.Type.Continue).location;
		l.statementTerm();
		return new ContinueStatement(location);
	}
	
	public override void codeGen(FuncState s)
	{
		s.codeContinue(location);
	}

	public override Statement fold()
	{
		return this;
	}
}

class BreakStatement : Statement
{
	public this(Location location)
	{
		super(location, location, AstTag.BreakStmt);
	}

	public static BreakStatement parse(Lexer l)
	{
		auto location = l.expect(Token.Type.Break).location;
		l.statementTerm();
		return new BreakStatement(location);
	}
	
	public override void codeGen(FuncState s)
	{
		s.codeBreak(location);
	}

	public override Statement fold()
	{
		return this;
	}
}

class ReturnStatement : Statement
{
	public Expression[] exprs;

	public this(Location location, Location endLocation, Expression[] exprs)
	{
		super(location, endLocation, AstTag.ReturnStmt);
		this.exprs = exprs;
	}

	public this(Expression value)
	{
		super(value.location, value.endLocation, AstTag.ReturnStmt);
		exprs ~= value;
	}

	public static ReturnStatement parse(Lexer l)
	{
		auto location = l.expect(Token.Type.Return).location;

		if(l.isStatementTerm())
		{
			auto endLocation = l.loc;
			l.statementTerm();
			return new ReturnStatement(location, endLocation, null);
		}
		else
		{
			if(l.loc.line != location.line)
				throw new MDCompileException(l.loc, "No-value returns must be followed by semicolons");

			List!(Expression) exprs;
			exprs.add(Expression.parse(l));

			while(l.type == Token.Type.Comma)
			{
				l.next();
				exprs.add(Expression.parse(l));
			}

			auto endLocation = exprs.toArray()[$ - 1].endLocation;
			l.statementTerm();
			return new ReturnStatement(location, endLocation, exprs.toArray());
		}
	}
	
	public override void codeGen(FuncState s)
	{
		if(exprs.length == 0)
			s.codeI(location.line, Op.Ret, 0, 1);
		else
		{
			uint firstReg = s.nextRegister();

			if(exprs.length == 1 && cast(CallExp)exprs[0])
			{
				exprs[0].codeGen(s);
				s.popToRegisters(endLocation.line, firstReg, -1);
				s.makeTailcall();
			}
			else
			{
				Expression.codeGenListToNextReg(s, exprs);

				if(exprs[$ - 1].isMultRet())
					s.codeI(endLocation.line, Op.Ret, firstReg, 0);
				else
					s.codeI(endLocation.line, Op.Ret, firstReg, exprs.length + 1);
			}
		}
	}

	public override Statement fold()
	{
		foreach(ref exp; exprs)
			exp = exp.fold();

		return this;
	}
}

class TryCatchStatement : Statement
{
	public Statement tryBody;
	public Identifier catchVar;
	public Statement catchBody;
	public Statement finallyBody;

	public this(Location location, Location endLocation, Statement tryBody, Identifier catchVar, Statement catchBody, Statement finallyBody)
	{
		super(location, endLocation, AstTag.TryStmt);

		this.tryBody = tryBody;
		this.catchVar = catchVar;
		this.catchBody = catchBody;
		this.finallyBody = finallyBody;
	}

	public static TryCatchStatement parse(Lexer l)
	{
		auto location = l.expect(Token.Type.Try).location;
		auto tryBody = new ScopeStatement(Statement.parse(l));

		Identifier catchVar;
		Statement catchBody;

		Location endLocation;

		if(l.type == Token.Type.Catch)
		{
			l.next();
			l.expect(Token.Type.LParen);

			catchVar = Identifier.parse(l);

			l.expect(Token.Type.RParen);

			catchBody = new ScopeStatement(Statement.parse(l));
			endLocation = catchBody.endLocation;
		}

		Statement finallyBody;

		if(l.type == Token.Type.Finally)
		{
			l.next();
			finallyBody = new ScopeStatement(Statement.parse(l));
			endLocation = finallyBody.endLocation;
		}

		if(catchBody is null && finallyBody is null)
			throw new MDCompileException(location, "Try statement must be followed by a catch, finally, or both");

		return new TryCatchStatement(location, endLocation, tryBody, catchVar, catchBody, finallyBody);
	}
	
	public override void codeGen(FuncState s)
	{
		if(finallyBody)
		{
			InstRef* pushFinally = s.codeFinally(location.line);

			if(catchBody)
			{
				uint checkReg1;
				InstRef* pushCatch = s.codeCatch(location.line, checkReg1);

				tryBody.codeGen(s);

				s.codeI(tryBody.endLocation.line, Op.PopCatch, 0, 0);
				s.codeI(tryBody.endLocation.line, Op.PopFinally, 0, 0);
				InstRef* jumpOverCatch = s.makeJump(tryBody.endLocation.line);
				s.patchJumpToHere(pushCatch);
				delete pushCatch;

				s.pushScope();
					uint checkReg2 = s.insertLocal(catchVar);

					assert(checkReg1 == checkReg2, "catch var register is not right");

					s.activateLocals(1);
					catchBody.codeGen(s);
				s.popScope(catchBody.endLocation.line);

				s.codeI(catchBody.endLocation.line, Op.PopFinally, 0, 0);
				s.patchJumpToHere(jumpOverCatch);
				delete jumpOverCatch;

				s.patchJumpToHere(pushFinally);
				delete pushFinally;

				finallyBody.codeGen(s);

				s.codeI(finallyBody.endLocation.line, Op.EndFinal, 0, 0);
			}
			else
			{
				tryBody.codeGen(s);
				s.codeI(tryBody.endLocation.line, Op.PopFinally, 0, 0);

				s.patchJumpToHere(pushFinally);
				delete pushFinally;

				finallyBody.codeGen(s);
				s.codeI(finallyBody.endLocation.line, Op.EndFinal, 0, 0);
			}
		}
		else
		{
			assert(catchBody !is null);

			uint checkReg1;
			InstRef* pushCatch = s.codeCatch(location.line, checkReg1);

			tryBody.codeGen(s);

			s.codeI(tryBody.endLocation.line, Op.PopCatch, 0, 0);
			InstRef* jumpOverCatch = s.makeJump(tryBody.endLocation.line);
			s.patchJumpToHere(pushCatch);
			delete pushCatch;

			s.pushScope();
				uint checkReg2 = s.insertLocal(catchVar);

				assert(checkReg1 == checkReg2, "catch var register is not right");

				s.activateLocals(1);
				catchBody.codeGen(s);
			s.popScope(catchBody.endLocation.line);

			s.patchJumpToHere(jumpOverCatch);
			delete jumpOverCatch;
		}
	}

	public override Statement fold()
	{
		tryBody = tryBody.fold();

		if(catchBody)
			catchBody = catchBody.fold();

		if(finallyBody)
			finallyBody = finallyBody.fold();

		return this;
	}
}

class ThrowStatement : Statement
{
	public Expression exp;

	public this(Location location, Expression exp)
	{
		super(location, exp.endLocation, AstTag.ThrowStmt);
		this.exp = exp;
	}

	public static ThrowStatement parse(Lexer l)
	{
		auto location = l.expect(Token.Type.Throw).location;
		auto exp = Expression.parse(l);
		l.statementTerm();
		return new ThrowStatement(location, exp);
	}
	
	public override void codeGen(FuncState s)
	{
		exp.codeGen(s);

		Exp src;
		s.popSource(location.line, src);

		s.codeR(endLocation.line, Op.Throw, 0, src.index, 0);

		s.freeExpTempRegs(&src);
	}

	public override Statement fold()
	{
		exp = exp.fold();
		return this;
	}
}

abstract class Expression : AstNode
{
	public this(Location location, Location endLocation, AstTag type)
	{
		super(location, endLocation, type);
	}

	public static Expression parse(Lexer l)
	{
		return CondExp.parse(l);
	}
	
	public static Expression parseStatement(Lexer l)
	{
		auto location = l.loc;
		Expression exp;

		if(l.type == Token.Type.Inc)
		{
			l.next();
			exp = PrimaryExp.parse(l);
			exp = new OpEqExp(location, location, AstTag.AddAssign, exp, new IntExp(location, 1));
		}
		else if(l.type == Token.Type.Dec)
		{
			l.next();
			exp = PrimaryExp.parse(l);
			exp = new OpEqExp(location, location, AstTag.SubAssign, exp, new IntExp(location, 1));
		}
		else
		{
			if(l.type == Token.Type.Length)
				exp = UnaryExp.parse(l);
			else
				exp = PrimaryExp.parse(l);

			if(l.tok.isOpAssign())
				exp = OpEqExp.parse(l, exp);
			else if(l.type == Token.Type.Assign || l.type == Token.Type.Comma)
				exp = Assignment.parse(l, exp);
			else if(l.type == Token.Type.Inc)
			{
				l.next();
				exp = new OpEqExp(location, location, AstTag.AddAssign, exp, new IntExp(location, 1));
			}
			else if(l.type == Token.Type.Dec)
			{
				l.next();
				exp = new OpEqExp(location, location, AstTag.SubAssign, exp, new IntExp(location, 1));
			}
			else if(l.type == Token.Type.OrOr)
				exp = OrOrExp.parse(l, exp);
			else if(l.type == Token.Type.AndAnd)
				exp = AndAndExp.parse(l, exp);
		}

		exp.checkToNothing();

		return exp;
	}
	
	public static Expression[] parseArguments(Lexer l)
	{
		List!(Expression) args;
		args.add(Expression.parse(l));

		while(l.type == Token.Type.Comma)
		{
			l.next();
			args.add(Expression.parse(l));
		}

		return args.toArray();
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
				s.popToRegisters(exprs[0].endLocation.line, firstReg, -1);
			else
				s.popMoveTo(exprs[0].endLocation.line, firstReg);
		}
		else
		{
			uint firstReg = s.nextRegister();
			exprs[0].codeGen(s);
			s.popMoveTo(exprs[0].endLocation.line, firstReg);
			s.pushRegister();

			uint lastReg = firstReg;

			foreach(i, e; exprs[1 .. $])
			{
				lastReg = s.nextRegister();
				e.codeGen(s);

				// has to be -2 because i _is not the index in the array_ but the _index in the slice_
				if(i == exprs.length - 2 && e.isMultRet())
					s.popToRegisters(e.endLocation.line, lastReg, -1);
				else
					s.popMoveTo(e.endLocation.line, lastReg);

				s.pushRegister();
			}

			for(int i = lastReg; i >= cast(int)firstReg; i--)
				s.popRegister(i);
		}
	}

	public abstract void codeGen(FuncState s);
	public abstract InstRef* codeCondition(FuncState s);

	public void checkToNothing()
	{
		auto e = new MDCompileException(location, "Expression cannot exist on its own");
		e.solitaryExpression = true;
		throw e;
	}

	public void checkMultRet()
	{
		if(isMultRet() == false)
			throw new MDCompileException(location, "Expression cannot be the source of a multi-target assignment");
	}

	public bool isMultRet()
	{
		return false;
	}
	
	public bool isConstant()
	{
		return false;
	}
	
	public bool isNull()
	{
		return false;
	}
	
	public bool isBool()
	{
		return false;
	}
	
	public bool asBool()
	{
		assert(false);
	}
	
	public bool isInt()
	{
		return false;
	}
	
	public int asInt()
	{
		assert(false);
	}

	public bool isFloat()
	{
		return false;
	}

	public mdfloat asFloat()
	{
		assert(false);
	}

	public bool isChar()
	{
		return false;
	}

	public dchar asChar()
	{
		assert(false);
	}

	public bool isString()
	{
		return false;
	}

	public dchar[] asString()
	{
		assert(false);
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
	public Expression[] lhs;
	public Expression rhs;

	public this(Location location, Location endLocation, Expression[] lhs, Expression rhs)
	{
		super(location, endLocation, AstTag.Assign);
		this.lhs = lhs;
		this.rhs = rhs;
	}

	public static Assignment parse(Lexer l, Expression firstLHS)
	{
		auto location = l.loc;

		Expression[] lhs;
		Expression rhs;

		lhs ~= firstLHS;

		while(l.type == Token.Type.Comma)
		{
			l.next();
			lhs ~= PrimaryExp.parse(l);
		}

		l.expect(Token.Type.Assign);

		rhs = Expression.parse(l);

		foreach(exp; lhs)
		{
			if(cast(ThisExp)exp)
				throw new MDCompileException(exp.location, "'this' cannot be the target of an assignment");

			if(cast(VargLengthExp)exp)
				throw new MDCompileException(exp.location, "'#vararg' cannot be the target of an assignment");
		}

		return new Assignment(location, rhs.endLocation, lhs, rhs);
	}
	
	public override void codeGen(FuncState s)
	{
		if(lhs.length == 1)
		{
			lhs[0].codeGen(s);
			rhs.codeGen(s);
			s.popAssign(endLocation.line);
		}
		else
		{
			rhs.checkMultRet();

			foreach(dest; lhs)
				dest.codeGen(s);

			uint numTemps = s.resolveAssignmentConflicts(lhs[$ - 1].location.line, lhs.length);

			uint RHSReg = s.nextRegister();
			rhs.codeGen(s);
			s.popToRegisters(endLocation.line, RHSReg, lhs.length);

			s.popAssignmentConflicts(numTemps);

			for(int reg = RHSReg + lhs.length - 1; reg >= RHSReg; reg--)
				s.popMoveFromReg(endLocation.line, reg);
		}
	}

	public override InstRef* codeCondition(FuncState s)
	{
		//REACHABLE?
		throw new MDCompileException(location, "Assignments cannot be used as a condition");
	}

	public override void checkToNothing()
	{
		// OK
	}

	public override Expression fold()
	{
		foreach(ref exp; lhs)
			exp = exp.fold();
			
		rhs = rhs.fold();
		return this;
	}
}

class OpEqExp : Expression
{
	public Expression lhs;
	public Expression rhs;

	public this(Location location, Location endLocation, AstTag type, Expression lhs, Expression rhs)
	{
		super(location, endLocation, type);
		this.lhs = lhs;
		this.rhs = rhs;
	}

	public static Expression parse(Lexer l, Expression exp1)
	{
		Expression exp2;

		auto location = l.loc;
		AstTag type;

		switch(l.type)
		{
			case Token.Type.AddEq:     type = AstTag.AddAssign;  goto _commonParse;
			case Token.Type.SubEq:     type = AstTag.SubAssign;  goto _commonParse;
			case Token.Type.MulEq:     type = AstTag.MulAssign;  goto _commonParse;
			case Token.Type.DivEq:     type = AstTag.DivAssign;  goto _commonParse;
			case Token.Type.ModEq:     type = AstTag.ModAssign;  goto _commonParse;
			case Token.Type.ShlEq:     type = AstTag.ShlAssign;  goto _commonParse;
			case Token.Type.ShrEq:     type = AstTag.ShrAssign;  goto _commonParse;
			case Token.Type.UShrEq:    type = AstTag.UShrAssign; goto _commonParse;
			case Token.Type.OrEq:      type = AstTag.OrAssign;   goto _commonParse;
			case Token.Type.XorEq:     type = AstTag.XorAssign;  goto _commonParse;
			case Token.Type.AndEq:     type = AstTag.AndAssign;  goto _commonParse;
			case Token.Type.DefaultEq: type = AstTag.CondAssign;

			_commonParse:
				l.next();
				exp2 = Expression.parse(l);
				exp1 = new OpEqExp(location, exp2.endLocation, type, exp1, exp2);
				break;
				
			case Token.Type.CatEq:
				l.next();
				exp2 = Expression.parse(l);
				exp1 = new CatEqExp(location, exp2.endLocation, exp1, exp2);
				break;

			default:
				assert(false, "OpEqExp parse switch");
				break;
		}

		return exp1;
	}

	public override void codeGen(FuncState s)
	{
		if(cast(VargLengthExp)lhs)
			throw new MDCompileException(location, "'#vararg' cannot be the target of an assignment");

		lhs.codeGen(s);
		s.pushSource(lhs.endLocation.line);

		Exp src1;
		s.popSource(lhs.endLocation.line, src1);
		rhs.codeGen(s);
		Exp src2;
		s.popSource(endLocation.line, src2);

		s.freeExpTempRegs(&src2);
		s.freeExpTempRegs(&src1);

		s.popReflexOp(endLocation.line, AstTagToOpcode(type), src1.index, src2.index);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		switch(type)
		{
			case AstTag.AddAssign:  throw new MDCompileException(location, "'+=' cannot be used as a condition");
			case AstTag.SubAssign:  throw new MDCompileException(location, "'-=' cannot be used as a condition");
			case AstTag.MulAssign:  throw new MDCompileException(location, "'*=' cannot be used as a condition");
			case AstTag.DivAssign:  throw new MDCompileException(location, "'/=' cannot be used as a condition");
			case AstTag.ModAssign:  throw new MDCompileException(location, "'%=' cannot be used as a condition");
			case AstTag.ShlAssign:  throw new MDCompileException(location, "'<<=' cannot be used as a condition");
			case AstTag.ShrAssign:  throw new MDCompileException(location, "'>>=' cannot be used as a condition");
			case AstTag.UShrAssign: throw new MDCompileException(location, "'>>>=' cannot be used as a condition");
			case AstTag.OrAssign:   throw new MDCompileException(location, "'|=' cannot be used as a condition");
			case AstTag.XorAssign:  throw new MDCompileException(location, "'^=' cannot be used as a condition");
			case AstTag.AndAssign:  throw new MDCompileException(location, "'&=' cannot be used as a condition");
			case AstTag.CondAssign: throw new MDCompileException(location, "'?=' cannot be used as a condition");
		}
	}

	public override void checkToNothing()
	{
		// OK
	}

	public override Expression fold()
	{
		lhs = lhs.fold();
		rhs = rhs.fold();

		return this;
	}
}

class CatEqExp : Expression
{
	public Expression lhs;
	public Expression rhs;
	public Expression[] operands;
	public bool collapsed = false;

	public this(Location location, Location endLocation, Expression lhs, Expression rhs)
	{
		super(location, endLocation, AstTag.CatAssign);
		this.lhs = lhs;
		this.rhs = rhs;
	}
	
	public override void codeGen(FuncState s)
	{
		assert(collapsed is true, "CatEqExp codeGen not collapsed");
		assert(operands.length >= 1, "CatEqExp codeGen not enough ops");

		lhs.codeGen(s);
		s.pushSource(lhs.endLocation.line);

		Exp src1;
		s.popSource(lhs.endLocation.line, src1);

		uint firstReg = s.nextRegister();
		Expression.codeGenListToNextReg(s, operands);

		s.freeExpTempRegs(&src1);
		
		if(operands[$ - 1].isMultRet())
			s.popReflexOp(endLocation.line, Op.CatEq, src1.index, firstReg, 0);
		else
			s.popReflexOp(endLocation.line, Op.CatEq, src1.index, firstReg, operands.length + 1);
	}

	public override Expression fold()
	{
		lhs = lhs.fold();
		rhs = rhs.fold();

		auto catExp = cast(CatExp)rhs;

		if(catExp)
			operands = catExp.operands;
		else
			operands = [rhs];

		collapsed = true;

		return this;
	}
	
	public override InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(location, "'~=' cannot be used as a condition");
	}

	public override void checkToNothing()
	{
		// OK
	}
}

class CondExp : Expression
{
	public Expression cond;
	public Expression op1;
	public Expression op2;

	public this(Location location, Location endLocation, Expression cond, Expression op1, Expression op2)
	{
		super(location, endLocation, AstTag.CondExp);
		this.cond = cond;
		this.op1 = op1;
		this.op2 = op2;
	}

	public static Expression parse(Lexer l)
	{
		auto location = l.loc;

		Expression exp1;
		Expression exp2;
		Expression exp3;

		exp1 = OrOrExp.parse(l);

		while(l.type == Token.Type.Question)
		{
			l.next();

			exp2 = Expression.parse(l);
			l.expect(Token.Type.Colon);
			exp3 = CondExp.parse(l);
			exp1 = new CondExp(location, exp3.endLocation, exp1, exp2, exp3);

			location = l.loc;
		}

		return exp1;
	}
	
	public override void codeGen(FuncState s)
	{
		uint temp = s.pushRegister();
		
		InstRef* c = cond.codeCondition(s);
		s.invertJump(c);
		s.patchTrueToHere(c);

		op1.codeGen(s);
		s.popMoveTo(op1.endLocation.line, temp);
		InstRef* i = s.makeJump(op1.endLocation.line, Op.Jmp);

		s.patchJumpToHere(c);
		delete c;

		op2.codeGen(s);
		s.popMoveTo(endLocation.line, temp);
		s.patchJumpToHere(i);
		delete i;

		s.pushTempReg(temp);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		InstRef* c = cond.codeCondition(s);
		s.invertJump(c);
		s.patchTrueToHere(c);

		InstRef* left = op1.codeCondition(s);
		s.invertJump(left);
		s.patchTrueToHere(left);
		InstRef* trueJump = s.makeJump(op1.endLocation.line, Op.Jmp, true);

		s.patchFalseToHere(c);
		s.patchJumpToHere(c);
		delete c;

		InstRef* right = op2.codeCondition(s);

		InstRef* i;
		for(i = right; i.falseList !is null; i = i.falseList) {}

		i.falseList = left;

		for(i = right; i.trueList !is null; i = i.trueList) {}
		
		i.trueList = trueJump;
		
		return right;
	}

	public override void checkToNothing()
	{
		// OK
	}
	
	public override Expression fold()
	{
		cond = cond.fold();
		op1 = op1.fold();
		op2 = op2.fold();

		if(cond.isConstant)
		{
			if(cond.isTrue())
				return op1;
			else
				return op2;
		}

		return this;
	}
}

abstract class BinaryExp : Expression
{
	public Expression op1;
	public Expression op2;

	public this(Location location, Location endLocation, AstTag type, Expression op1, Expression op2)
	{
		super(location, endLocation, type);
		this.op1 = op1;
		this.op2 = op2;
	}
	
	public override void codeGen(FuncState s)
	{
		op1.codeGen(s);
		Exp src1;
		s.popSource(op1.endLocation.line, src1);
		op2.codeGen(s);
		Exp src2;
		s.popSource(endLocation.line, src2);

		s.freeExpTempRegs(&src2);
		s.freeExpTempRegs(&src1);

		s.pushBinOp(endLocation.line, AstTagToOpcode(type), src1.index, src2.index);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		uint temp = s.pushRegister();
		codeGen(s);
		s.popMoveTo(endLocation.line, temp);
		s.codeR(endLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* ret = s.makeJump(endLocation.line, Op.Je);
		s.popRegister(temp);
		return ret;
	}
}

class OrOrExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.OrOrExp, left, right);
	}

	public static Expression parse(Lexer l, Expression exp1 = null)
	{
		auto location = l.loc;

		Expression exp2;

		if(exp1 is null)
			exp1 = AndAndExp.parse(l);

		while(l.type == Token.Type.OrOr)
		{
			l.next();

			exp2 = AndAndExp.parse(l);
			exp1 = new OrOrExp(location, exp2.endLocation, exp1, exp2);

			location = l.loc;
		}

		return exp1;
	}
	
	public override void codeGen(FuncState s)
	{
		uint temp = s.pushRegister();
		op1.codeGen(s);
		s.popMoveTo(op1.endLocation.line, temp);
		s.codeR(op1.endLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* i = s.makeJump(op1.endLocation.line, Op.Je);
		op2.codeGen(s);
		s.popMoveTo(endLocation.line, temp);
		s.patchJumpToHere(i);
		delete i;
		s.pushTempReg(temp);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		InstRef* left = op1.codeCondition(s);
		s.patchFalseToHere(left);
		InstRef* right = op2.codeCondition(s);

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
		op1 = op1.fold();
		op2 = op2.fold();

		if(op1.isConstant)
		{
			if(op1.isTrue())
				return op1;
			else
				return op2;
		}

		return this;
	}
}

class AndAndExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.AndAndExp, left, right);
	}

	public static Expression parse(Lexer l, Expression exp1 = null)
	{
		auto location = l.loc;

		Expression exp2;

		if(exp1 is null)
			exp1 = OrExp.parse(l);

		while(l.type == Token.Type.AndAnd)
		{
			l.next();

			exp2 = OrExp.parse(l);
			exp1 = new AndAndExp(location, exp2.endLocation, exp1, exp2);

			location = l.loc;
		}

		return exp1;
	}
	
	public override void codeGen(FuncState s)
	{
		uint temp = s.pushRegister();
		op1.codeGen(s);
		s.popMoveTo(op1.endLocation.line, temp);
		s.codeR(op1.endLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* i = s.makeJump(op1.endLocation.line, Op.Je, false);
		op2.codeGen(s);
		s.popMoveTo(endLocation.line, temp);
		s.patchJumpToHere(i);
		delete i;
		s.pushTempReg(temp);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		InstRef* left = op1.codeCondition(s);
		s.invertJump(left);
		s.patchTrueToHere(left);
		InstRef* right = op2.codeCondition(s);

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
		op1 = op1.fold();
		op2 = op2.fold();

		if(op1.isConstant)
		{
			if(op1.isTrue())
				return op2;
			else
				return op1;
		}

		return this;
	}
}

class OrExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.OrExp, left, right);
	}

	public static Expression parse(Lexer l)
	{
		auto location = l.loc;

		Expression exp1;
		Expression exp2;

		exp1 = XorExp.parse(l);

		while(l.type == Token.Type.Or)
		{
			l.next();

			exp2 = XorExp.parse(l);
			exp1 = new OrExp(location, exp2.endLocation, exp1, exp2);

			location = l.loc;
		}

		return exp1;
	}
	
	public override Expression fold()
	{
		op1 = op1.fold();
		op2 = op2.fold();

		if(op1.isConstant && op2.isConstant)
		{
			if(!op1.isInt || !op2.isInt)
				throw new MDCompileException(location, "Bitwise Or must be performed on integers");

			return new IntExp(location, op1.asInt() | op2.asInt());
		}

		return this;
	}
}

class XorExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.XorExp, left, right);
	}

	public static Expression parse(Lexer l)
	{
		auto location = l.loc;

		Expression exp1;
		Expression exp2;

		exp1 = AndExp.parse(l);

		while(l.type == Token.Type.Xor)
		{
			l.next();

			exp2 = AndExp.parse(l);
			exp1 = new XorExp(location, exp2.endLocation, exp1, exp2);

			location = l.loc;
		}

		return exp1;
	}
	
	public override Expression fold()
	{
		op1 = op1.fold();
		op2 = op2.fold();
		
		if(op1.isConstant && op2.isConstant)
		{
			if(!op1.isInt || !op2.isInt)
				throw new MDCompileException(location, "Bitwise Xor must be performed on integers");

			return new IntExp(location, op1.asInt() ^ op2.asInt());
		}

		return this;
	}
}

class AndExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.AndExp, left, right);
	}

	public static Expression parse(Lexer l)
	{
		Location location = l.loc;

		Expression exp1;
		Expression exp2;

		exp1 = EqualExp.parse(l);

		while(l.type == Token.Type.And)
		{
			l.next();

			exp2 = EqualExp.parse(l);
			exp1 = new AndExp(location, exp2.endLocation, exp1, exp2);

			location = l.loc;
		}

		return exp1;
	}
	
	public override Expression fold()
	{
		op1 = op1.fold();
		op2 = op2.fold();

		if(op1.isConstant && op2.isConstant)
		{
			if(!op1.isInt || !op2.isInt)
				throw new MDCompileException(location, "Bitwise And must be performed on integers");

			return new IntExp(location, op1.asInt() & op2.asInt());
		}

		return this;
	}
}

class EqualExp : BinaryExp
{
	public this(Location location, Location endLocation, AstTag type, Expression left, Expression right)
	{
		super(location, endLocation, type, left, right);
	}

	public static Expression parse(Lexer l)
	{
		auto location = l.loc;

		Expression exp1;
		Expression exp2;

		exp1 = CmpExp.parse(l);

		while(true)
		{
			AstTag type;

			switch(l.type)
			{
				case Token.Type.EQ, Token.Type.NE:
					type = (l.type == Token.Type.EQ ? AstTag.EqualExp : AstTag.NotEqualExp);
					l.next();
					exp2 = CmpExp.parse(l);
					exp1 = new EqualExp(location, exp2.endLocation, type, exp1, exp2);
					continue;

				case Token.Type.Not:
					if(l.peek.type != Token.Type.Is)
						break;

					l.next();
					l.next();
					type = AstTag.NotIsExp;
					goto _doIs;

				case Token.Type.Is:
					type = AstTag.IsExp;
					l.next();

				_doIs:
					exp2 = CmpExp.parse(l);
					exp1 = new EqualExp(location, exp2.endLocation, type, exp1, exp2);
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
		s.popMoveTo(endLocation.line, temp);
		InstRef* j = s.makeJump(endLocation.line, Op.Jmp);
		s.patchJumpToHere(i);
		delete i;
		s.pushBool(true);
		s.popMoveTo(endLocation.line, temp);
		s.patchJumpToHere(j);
		delete j;
		s.pushTempReg(temp);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		op1.codeGen(s);
		Exp src1;
		s.popSource(op1.endLocation.line, src1);
		op2.codeGen(s);
		Exp src2;
		s.popSource(endLocation.line, src2);

		s.freeExpTempRegs(&src2);
		s.freeExpTempRegs(&src1);

		s.codeR(endLocation.line, AstTagToOpcode(type), 0, src1.index, src2.index);

		return s.makeJump(endLocation.line, Op.Je, type == AstTag.EqualExp || type == AstTag.IsExp);
	}

	public override Expression fold()
	{
		op1 = op1.fold();
		op2 = op2.fold();
		
		bool isTrue = type == AstTag.EqualExp || type == AstTag.IsExp;
		
		if(op1.isConstant && op2.isConstant)
		{
			if(op1.isNull && op2.isNull)
				return new BoolExp(location, isTrue ? true : false);

			if(op1.isBool && op2.isBool)
				return new BoolExp(location, isTrue ? op1.asBool() == op2.asBool() : op1.asBool() != op2.asBool());

			if(op1.isInt && op2.isInt)
				return new BoolExp(location, isTrue ? op1.asInt() == op2.asInt() : op1.asInt() != op2.asInt());

			if(type == AstTag.IsExp || type == AstTag.NotIsExp)
			{
				if(op1.isFloat && op2.isFloat)
					return new BoolExp(location, isTrue ? op1.asFloat() == op2.asFloat() : op1.asFloat() != op2.asFloat());
			}
			else
			{
				if((op1.isInt || op1.isFloat) && (op2.isInt || op2.isFloat))
					return new BoolExp(location, isTrue ? op1.asFloat() == op2.asFloat() : op1.asFloat() != op2.asFloat());
			}

			if(op1.isChar && op2.isChar)
				return new BoolExp(location, isTrue ? op1.asChar() == op2.asChar() : op1.asChar() != op2.asChar());

			if(op1.isString && op2.isString)
				return new BoolExp(location, isTrue ? op1.asString() == op2.asString() : op1.asString() != op2.asString());

			if(type == AstTag.IsExp || type == AstTag.NotIsExp)
				return new BoolExp(location, !isTrue);
			else
				throw new MDCompileException(location, "Cannot compare different types");
		}

		return this;
	}
}

class CmpExp : BinaryExp
{
	public this(Location location, Location endLocation, AstTag type, Expression op1, Expression op2)
	{
		super(location, endLocation, type, op1, op2);
	}

	public static Expression parse(Lexer l)
	{
		auto location = l.loc;

		Expression exp1;
		Expression exp2;

		exp1 = ShiftExp.parse(l);

		while(true)
		{
			switch(l.type)
			{
				case Token.Type.LT:
					l.next();
					exp2 = ShiftExp.parse(l);
					exp1 = new CmpExp(location, exp2.endLocation, AstTag.LTExp, exp1, exp2);
					continue;

				case Token.Type.LE:
					l.next();
					exp2 = ShiftExp.parse(l);
					exp1 = new CmpExp(location, exp2.endLocation, AstTag.LEExp, exp1, exp2);
					continue;

				case Token.Type.GT:
					l.next();
					exp2 = ShiftExp.parse(l);
					exp1 = new CmpExp(location, exp2.endLocation, AstTag.GTExp, exp1, exp2);
					continue;

				case Token.Type.GE:
					l.next();
					exp2 = ShiftExp.parse(l);
					exp1 = new CmpExp(location, exp2.endLocation, AstTag.GEExp, exp1, exp2);
					continue;

				case Token.Type.As:
					l.next();
					exp2 = ShiftExp.parse(l);
					exp1 = new AsExp(location, exp2.endLocation, exp1, exp2);
					continue;
					
				case Token.Type.In:
					l.next();
					exp2 = ShiftExp.parse(l);
					exp1 = new InExp(location, exp2.endLocation, exp1, exp2);
					continue;

				case Token.Type.Not:
					if(l.peek.type != Token.Type.In)
						break;

					l.next();
					l.next();
					exp2 = ShiftExp.parse(l);
					exp1 = new NotInExp(location, exp2.endLocation, exp1, exp2);
					continue;
					
				case Token.Type.Cmp3:
					l.next();
					exp2 = ShiftExp.parse(l);
					exp1 = new Cmp3Exp(location, exp2.endLocation, exp1, exp2);
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
		s.popMoveTo(endLocation.line, temp);
		InstRef* j = s.makeJump(endLocation.line, Op.Jmp);
		s.patchJumpToHere(i);
		delete i;
		s.pushBool(true);
		s.popMoveTo(endLocation.line, temp);
		s.patchJumpToHere(j);
		delete j;
		s.pushTempReg(temp);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		op1.codeGen(s);
		Exp src1;
		s.popSource(op1.endLocation.line, src1);
		op2.codeGen(s);
		Exp src2;
		s.popSource(endLocation.line, src2);

		s.freeExpTempRegs(&src2);
		s.freeExpTempRegs(&src1);

		s.codeR(endLocation.line, Op.Cmp, 0, src1.index, src2.index);

		switch(type)
		{
			case AstTag.LTExp: return s.makeJump(endLocation.line, Op.Jlt, true);
			case AstTag.LEExp: return s.makeJump(endLocation.line, Op.Jle, true);
			case AstTag.GTExp: return s.makeJump(endLocation.line, Op.Jle, false);
			case AstTag.GEExp: return s.makeJump(endLocation.line, Op.Jlt, false);
			default: assert(false);
		}
	}

	public override Expression fold()
	{
		op1 = op1.fold();
		op2 = op2.fold();

		if(op1.isConstant && op2.isConstant)
		{
			int cmpVal = 0;

			if(op1.isNull && op2.isNull)
				cmpVal = 0;
			else if(op1.isInt && op2.isInt)
				cmpVal = Compare3(op1.asInt(), op2.asInt());
			else if((op1.isInt || op1.isFloat) && (op2.isInt || op2.isFloat))
				cmpVal = Compare3(op1.asFloat(), op2.asFloat());
			else if(op1.isChar && op2.isChar)
				cmpVal = Compare3(op1.asChar, op2.asChar);
			else if(op1.isString && op2.isString)
				cmpVal = dcmp(op1.asString(), op2.asString());
			else
				throw new MDCompileException(location, "Invalid compile-time comparison");

			switch(type)
			{
				case AstTag.LTExp:         return new BoolExp(location, cmpVal < 0);
				case AstTag.LEExp:    return new BoolExp(location, cmpVal <= 0);
				case AstTag.GTExp:      return new BoolExp(location, cmpVal > 0);
				case AstTag.GEExp: return new BoolExp(location, cmpVal >= 0);
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
			
		super(location, endLocation, AstTag.AsExp, left, right);
	}
}

class InExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.InExp, left, right);
	}
}

class NotInExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.NotInExp, left, right);
	}
}

class Cmp3Exp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.Cmp3Exp, left, right);
	}
	
	public override Expression fold()
	{
		op1 = op1.fold();
		op2 = op2.fold();

		if(op1.isConstant && op2.isConstant)
		{
			int cmpVal = 0;

			if(op1.isNull && op2.isNull)
				cmpVal = 0;
			else if(op1.isInt && op2.isInt)
				cmpVal = Compare3(op1.asInt(), op2.asInt());
			else if((op1.isInt || op1.isFloat) && (op2.isInt || op2.isFloat))
				cmpVal = Compare3(op1.asFloat(), op2.asFloat());
			else if(op1.isChar && op2.isChar)
				cmpVal = Compare3(op1.asChar(), op2.asChar());
			else if(op1.isString && op2.isString)
				cmpVal = dcmp(op1.asString(), op2.asString());
			else
				throw new MDCompileException(location, "Invalid compile-time comparison");

			return new IntExp(location, cmpVal);
		}

		return this;
	}
}

class ShiftExp : BinaryExp
{
	public this(Location location, Location endLocation, AstTag type, Expression left, Expression right)
	{
		super(location, endLocation, type, left, right);
	}

	public static Expression parse(Lexer l)
	{
		auto location = l.loc;

		Expression exp1;
		Expression exp2;

		exp1 = AddExp.parse(l);

		while(true)
		{
			switch(l.type)
			{
				case Token.Type.Shl:
					l.next();
					exp2 = AddExp.parse(l);
					exp1 = new ShiftExp(location, exp2.endLocation, AstTag.ShlExp, exp1, exp2);
					continue;

				case Token.Type.Shr:
					l.next();
					exp2 = AddExp.parse(l);
					exp1 = new ShiftExp(location, exp2.endLocation, AstTag.ShrExp, exp1, exp2);
					continue;

				case Token.Type.UShr:
					l.next();
					exp2 = AddExp.parse(l);
					exp1 = new ShiftExp(location, exp2.endLocation, AstTag.UShrExp, exp1, exp2);
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
		op1 = op1.fold();
		op2 = op2.fold();

		if(op1.isConstant && op2.isConstant)
		{
			if(!op1.isInt || !op2.isInt)
				throw new MDCompileException(location, "Bitshifting must be performed on integers");

			switch(type)
			{
				case AstTag.ShlExp:  return new IntExp(location, op1.asInt() << op2.asInt());
				case AstTag.ShrExp:  return new IntExp(location, op1.asInt() >> op2.asInt());
				case AstTag.UShrExp: return new IntExp(location, op1.asInt() >>> op2.asInt());
				default: assert(false, "ShiftExp fold");
			}
		}

		return this;
	}
}

class AddExp : BinaryExp
{
	public this(Location location, Location endLocation, AstTag type, Expression left, Expression right)
	{
		super(location, endLocation, type, left, right);
	}

	public static Expression parse(Lexer l)
	{
		auto location = l.loc;

		Expression exp1;
		Expression exp2;

		exp1 = MulExp.parse(l);

		while(true)
		{
			switch(l.type)
			{
				case Token.Type.Add:
					l.next();
					exp2 = MulExp.parse(l);
					exp1 = new AddExp(location, exp2.endLocation, AstTag.AddExp, exp1, exp2);
					continue;

				case Token.Type.Sub:
					l.next();
					exp2 = MulExp.parse(l);
					exp1 = new AddExp(location, exp2.endLocation, AstTag.SubExp, exp1, exp2);
					continue;

				case Token.Type.Cat:
					l.next();
					exp2 = MulExp.parse(l);
					exp1 = new CatExp(location, exp2.endLocation, exp1, exp2);
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
		op1 = op1.fold();
		op2 = op2.fold();

		if(op1.isConstant && op2.isConstant)
		{
			if(op1.isInt && op2.isInt)
			{
				if(type == AstTag.AddExp)
					return new IntExp(location, op1.asInt() + op2.asInt());
				else
				{
					assert(type == AstTag.SubExp, "AddExp fold 1");
					return new IntExp(location, op1.asInt() - op2.asInt());
				}
			}

			if((op1.isInt || op1.isFloat) && (op2.isInt || op2.isFloat))
			{
				if(type == AstTag.AddExp)
					return new FloatExp(location, op1.asFloat() + op2.asFloat());
				else
				{
					assert(type == AstTag.SubExp, "AddExp fold 2");
					return new FloatExp(location, op1.asFloat() - op2.asFloat());
				}
			}

			throw new MDCompileException(location, "Addition and Subtraction must be performed on numbers");
		}

		return this;
	}
}

class CatExp : BinaryExp
{
	public Expression[] operands;
	public bool collapsed = false;

	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.CatExp, left, right);
	}
	
	public override void codeGen(FuncState s)
	{
		assert(collapsed is true, "CatExp codeGen not collapsed");
		assert(operands.length >= 2, "CatExp codeGen not enough ops");

		uint firstReg = s.nextRegister();

		Expression.codeGenListToNextReg(s, operands);

		if(operands[$ - 1].isMultRet())
			s.pushBinOp(endLocation.line, Op.Cat, firstReg, 0);
		else
			s.pushBinOp(endLocation.line, Op.Cat, firstReg, operands.length + 1);
	}

	public override Expression fold()
	{
		op1 = op1.fold();
		op2 = op2.fold();

		assert(collapsed is false, "repeated CatExp fold");
		collapsed = true;

		auto l = cast(CatExp)op1;

		if(l)
			operands = l.operands ~ operands;
		else
			operands = op1 ~ operands;

		operands ~= op2;

		endLocation = operands[$ - 1].endLocation;

		for(int i = 0; i < operands.length - 1; i++)
		{
			if(operands[i].isConstant && operands[i + 1].isConstant)
			{
				if(operands[i].isString && operands[i + 1].isString)
				{
					operands[i] = new StringExp(location, operands[i].asString() ~ operands[i + 1].asString());
					operands = operands[0 .. i + 1] ~ operands[i + 2 .. $];
					i--;
				}
				else if(operands[i].isChar && operands[i + 1].isChar)
				{
					dchar[] s = new dchar[2];
					s[0] = operands[i].asChar();
					s[1] = operands[i + 1].asChar();

					operands[i] = new StringExp(location, s);
					operands = operands[0 .. i + 1] ~ operands[i + 2 .. $];
					i--;
				}
				else if(operands[i].isString && operands[i + 1].isChar)
				{
					operands[i] = new StringExp(location, operands[i].asString() ~ operands[i + 1].asChar());
					operands = operands[0 .. i + 1] ~ operands[i + 2 .. $];
					i--;
				}
				else if(operands[i].isChar && operands[i + 1].isString)
				{
					operands[i] = new StringExp(location, operands[i].asChar() ~ operands[i + 1].asString());
					operands = operands[0 .. i + 1] ~ operands[i + 2 .. $];
					i--;
				}
			}
		}

		if(operands.length == 1)
			return operands[0];

		return this;
	}
}

class MulExp : BinaryExp
{
	public this(Location location, Location endLocation, AstTag type, Expression left, Expression right)
	{
		super(location, endLocation, type, left, right);
	}

	public static Expression parse(Lexer l)
	{
		auto location = l.loc;

		Expression exp1;
		Expression exp2;

		exp1 = UnaryExp.parse(l);

		while(true)
		{
			switch(l.type)
			{
				case Token.Type.Mul:
					l.next();
					exp2 = UnaryExp.parse(l);
					exp1 = new MulExp(location, exp2.endLocation, AstTag.MulExp, exp1, exp2);
					continue;

				case Token.Type.Div:
					l.next();
					exp2 = UnaryExp.parse(l);
					exp1 = new MulExp(location, exp2.endLocation, AstTag.DivExp, exp1, exp2);
					continue;

				case Token.Type.Mod:
					l.next();
					exp2 = UnaryExp.parse(l);
					exp1 = new MulExp(location, exp2.endLocation, AstTag.ModExp, exp1, exp2);
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
		op1 = op1.fold();
		op2 = op2.fold();

		if(op1.isConstant && op2.isConstant)
		{
			if(op1.isInt && op2.isInt)
			{
				switch(type)
				{
					case AstTag.MulExp:
						return new IntExp(location, op1.asInt() * op2.asInt());

					case AstTag.DivExp:
						if(op2.asInt == 0)
							throw new MDCompileException(location, "Division by 0");

						return new IntExp(location, op1.asInt() / op2.asInt());

					case AstTag.ModExp:
						if(op2.asInt == 0)
							throw new MDCompileException(location, "Modulo by 0");

						return new IntExp(location, op1.asInt() % op2.asInt());

					default: assert(false, "MulExp fold 1");
				}
			}

			if((op1.isInt || op1.isFloat) && (op2.isInt || op2.isFloat))
			{
				switch(type)
				{
					case AstTag.MulExp:
						return new FloatExp(location, op1.asFloat() * op2.asFloat());

					case AstTag.DivExp:
						if(op2.asFloat() == 0.0)
							throw new MDCompileException(location, "Division by 0");

						return new FloatExp(location, op1.asFloat() / op2.asFloat());

					case AstTag.ModExp:
						if(op2.asFloat() == 0.0)
							throw new MDCompileException(location, "Modulo by 0");

						return new FloatExp(location, op1.asFloat() % op2.asFloat());

					default: assert(false, "MulExp fold 2");
				}
			}
				
			throw new MDCompileException(location, "Multiplication, Division, and Modulo must be performed on numbers");
		}

		return this;
	}
}

abstract class UnaryExp : Expression
{
	protected Expression op;

	public this(Location location, Location endLocation, AstTag type, Expression operand)
	{
		super(location, endLocation, type);
		op = operand;
	}

	public static Expression parse(Lexer l)
	{
		auto location = l.loc;

		Expression exp;

		switch(l.type)
		{
			case Token.Type.Sub:
				l.next();
				exp = UnaryExp.parse(l);
				exp = new NegExp(location, exp.endLocation, exp);
				break;

			case Token.Type.Not:
				l.next();
				exp = UnaryExp.parse(l);
				exp = new NotExp(location, exp.endLocation, exp);
				break;

			case Token.Type.Cat:
				l.next();
				exp = UnaryExp.parse(l);
				exp = new ComExp(location, exp.endLocation, exp);
				break;

			case Token.Type.Length:
				l.next();
				exp = UnaryExp.parse(l);

				if(cast(VarargExp)exp)
					exp = new VargLengthExp(location, exp.endLocation);
				else
					exp = new LengthExp(location, exp.endLocation, exp);
				break;

			case Token.Type.Coroutine:
				l.next();
				exp = UnaryExp.parse(l);
				exp = new CoroutineExp(location, exp.endLocation, exp);
				break;

			default:
				exp = PrimaryExp.parse(l);
				break;
		}

		assert(exp !is null);

		return exp;
	}
	
	public override InstRef* codeCondition(FuncState s)
	{
		uint temp = s.nextRegister();
		codeGen(s);
		s.popMoveTo(endLocation.line, temp);
		s.codeR(endLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* ret = s.makeJump(endLocation.line, Op.Je);
		return ret;
	}
}

class NegExp : UnaryExp
{
	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation, AstTag.NegExp, operand);
	}
	
	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.popUnOp(endLocation.line, Op.Neg);
	}

	public override Expression fold()
	{
		op = op.fold();

		if(op.isConstant)
		{
			if(op.isInt)
			{
				(cast(IntExp)op).value = -op.asInt();
				return op;
			}

			if(op.isFloat)
			{
				(cast(FloatExp)op).value = -op.asFloat();
				return op;
			}

			throw new MDCompileException(location, "Negation must be performed on numbers");
		}

		return this;
	}
}

class NotExp : UnaryExp
{
	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation, AstTag.NotExp, operand);
	}
	
	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.popUnOp(endLocation.line, Op.Not);
	}

	public override Expression fold()
	{
		op = op.fold();

		if(op.isConstant)
			return new BoolExp(location, !op.isTrue);

		if(auto cmpExp = cast(CmpExp)op)
		{
			switch(cmpExp.type)
			{
				case AstTag.LTExp:         cmpExp.type = AstTag.GEExp; break;
				case AstTag.LEExp:    cmpExp.type = AstTag.GTExp; break;
				case AstTag.GTExp:      cmpExp.type = AstTag.LEExp; break;
				case AstTag.GEExp: cmpExp.type = AstTag.LTExp; break;
			}

			return cmpExp;
		}

		if(auto equalExp = cast(EqualExp)op)
		{
			switch(equalExp.type)
			{
				case AstTag.EqualExp:    equalExp.type = AstTag.NotEqualExp; break;
				case AstTag.NotEqualExp: equalExp.type = AstTag.EqualExp; break;
				case AstTag.IsExp:       equalExp.type = AstTag.NotIsExp; break;
				case AstTag.NotIsExp:    equalExp.type = AstTag.IsExp; break;
			}

			return equalExp;
		}

		return this;
	}
}

class ComExp : UnaryExp
{
	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation, AstTag.ComExp, operand);
	}
	
	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.popUnOp(endLocation.line, Op.Com);
	}

	public override Expression fold()
	{
		op = op.fold();

		if(op.isConstant)
		{
			if(op.isInt)
			{
				(cast(IntExp)op).value = ~op.asInt();
				return op;
			}

			throw new MDCompileException(location, "Bitwise complement must be performed on integers");
		}

		return this;
	}
}

class LengthExp : UnaryExp
{
	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation, AstTag.LenExp, operand);
	}
	
	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.popLength(endLocation.line);
	}

	public override Expression fold()
	{
		op = op.fold();

		if(op.isConstant)
		{
			if(op.isString)
				return new IntExp(location, op.asString().length);

			throw new MDCompileException(location, "Length must be performed on a string");
		}

		return this;
	}
}

class VargLengthExp : UnaryExp
{
	public this(Location location, Location endLocation)
	{
		super(location, endLocation, AstTag.VargLenExp, null);
	}
	
	public override void codeGen(FuncState s)
	{
		if(!s.mIsVararg)
			throw new MDCompileException(location, "'vararg' cannot be used in a non-variadic function");

		s.pushVargLen(endLocation.line);
	}
	
	public override Expression fold()
	{
		return this;
	}
}

class CoroutineExp : UnaryExp
{
	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation, AstTag.CoroutineExp, operand);
	}
	
	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.popUnOp(endLocation.line, Op.Coroutine);
	}

	public override Expression fold()
	{
		op = op.fold();
		return this;
	}
}

abstract class PostfixExp : UnaryExp
{
	public this(Location location, Location endLocation, AstTag type, Expression operand)
	{
		super(location, endLocation, type, operand);
	}

	public static Expression parse(Lexer l, Expression exp)
	{
		while(true)
		{
			auto location = l.loc;

			switch(l.type)
			{
				case Token.Type.Dot:
					l.next();

					if(l.type == Token.Type.Ident)
					{
						auto ie = IdentExp.parse(l);
						exp = new DotExp(location, ie.endLocation, exp, new StringExp(ie.location, ie.name.name));
					}
					else if(l.type == Token.Type.Super)
					{
						auto endLocation = l.loc;
						l.next();
						exp = new DotSuperExp(location, endLocation, exp);
					}
					else if(l.type == Token.Type.Class)
					{
						auto endLocation = l.loc;
						l.next();
						exp = new DotClassExp(location, endLocation, exp);
					}
					else
					{
						l.expect(Token.Type.LParen);
						auto subExp = Expression.parse(l);
						l.expect(Token.Type.RParen);
						exp = new DotExp(location, subExp.endLocation, exp, subExp);
					}
					continue;

				case Token.Type.LParen:
					l.next();

					Expression context;
					Expression[] args;

					if(l.type == Token.Type.With)
					{
						l.next();

						args = Expression.parseArguments(l);
						context = args[0];
						args = args[1 .. $];
					}
					else if(l.type != Token.Type.RParen)
						args = Expression.parseArguments(l);

					l.tok.expect(Token.Type.RParen);
					auto endLocation = l.loc;
					l.next();

					exp = new CallExp(location, endLocation, exp, context, args);
					continue;

				case Token.Type.LBracket:
					l.next();

					Expression loIndex;
					Expression hiIndex;

					Location endLocation;

					if(l.type == Token.Type.RBracket)
					{
						// a[]
						loIndex = new NullExp(l.loc);
						hiIndex = new NullExp(l.loc);
						endLocation = l.loc;
						l.next();

						if(cast(VarargExp)exp)
							exp = new VargSliceExp(location, endLocation, loIndex, hiIndex);
						else
							exp = new SliceExp(location, endLocation, exp, loIndex, hiIndex);
					}
					else if(l.type == Token.Type.DotDot)
					{
						loIndex = new NullExp(l.loc);
						l.next();

						if(l.type == Token.Type.RBracket)
						{
							// a[ .. ]
							hiIndex = new NullExp(l.loc);
							endLocation = l.loc;
							l.next();
						}
						else
						{
							// a[ .. 0]
							hiIndex = Expression.parse(l);
							l.tok.expect(Token.Type.RBracket);
							endLocation = l.loc;
							l.next();
						}
						
						if(cast(VarargExp)exp)
							exp = new VargSliceExp(location, endLocation, loIndex, hiIndex);
						else
							exp = new SliceExp(location, endLocation, exp, loIndex, hiIndex);
					}
					else
					{
						loIndex = Expression.parse(l);

						if(l.type == Token.Type.DotDot)
						{
							l.next();

							if(l.type == Token.Type.RBracket)
							{
								// a[0 .. ]
								hiIndex = new NullExp(l.loc);
								endLocation = l.loc;
								l.next();
							}
							else
							{
								// a[0 .. 0]
								hiIndex = Expression.parse(l);
								l.tok.expect(Token.Type.RBracket);
								endLocation = l.loc;
								l.next();
							}

							if(cast(VarargExp)exp)
								exp = new VargSliceExp(location, endLocation, loIndex, hiIndex);
							else
								exp = new SliceExp(location, endLocation, exp, loIndex, hiIndex);
						}
						else
						{
							// a[0]
							l.tok.expect(Token.Type.RBracket);
							endLocation = l.loc;
							l.next();

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
	public Expression name;

	public this(Location location, Location endLocation, Expression operand, Expression name)
	{
		super(location, endLocation, AstTag.DotExp, operand);
		this.name = name;
	}
	
	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.topToSource(endLocation.line);
		name.codeGen(s);
		s.popField(endLocation.line);
	}

	public override Expression fold()
	{
		op = op.fold();
		name = name.fold();
		return this;
	}
}

class DotSuperExp : PostfixExp
{
	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation, AstTag.DotSuperExp, operand);
	}
	
	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.popUnOp(endLocation.line, Op.Super);
	}

	public override Expression fold()
	{
		op = op.fold();
		return this;
	}
}

class DotClassExp : PostfixExp
{
	public this(Location location, Location endLocation, Expression operand)
	{
		super(location, endLocation, AstTag.DotClassExp, operand);
	}
	
	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.popUnOp(endLocation.line, Op.ClassOf);
	}

	public override Expression fold()
	{
		op = op.fold();
		return this;
	}
}

class CallExp : PostfixExp
{
	public Expression context;
	public Expression[] args;

	public this(Location location, Location endLocation, Expression operand, Expression context, Expression[] args)
	{
		super(location, endLocation, AstTag.CallExp, operand);
		this.context = context;
		this.args = args;
	}
	
	public override void codeGen(FuncState s)
	{
		if(auto dotExp = cast(DotExp)op)
		{
			Expression methodName = dotExp.name;

			uint funcReg = s.nextRegister();
			dotExp.op.codeGen(s);

			Exp src;
			s.popSource(op.endLocation.line, src);
			s.freeExpTempRegs(&src);
			assert(s.nextRegister() == funcReg);

			s.pushRegister();

			Exp meth;
			methodName.codeGen(s);
			s.popSource(methodName.endLocation.line, meth);
			s.freeExpTempRegs(&meth);

			uint thisReg = s.nextRegister();

			if(context)
			{
				context.codeGen(s);
				s.popMoveTo(op.endLocation.line, thisReg);
			}

			s.pushRegister();

			Expression.codeGenListToNextReg(s, args);

			s.codeR(op.endLocation.line, (context is null) ? Op.Method : Op.MethodNC, funcReg, src.index, meth.index);
			s.popRegister(thisReg);

			if(args.length == 0)
				s.pushCall(endLocation.line, funcReg, 2);
			else if(args[$ - 1].isMultRet())
				s.pushCall(endLocation.line, funcReg, 0);
			else
				s.pushCall(endLocation.line, funcReg, args.length + 2);
		}
		else
		{
			uint funcReg = s.nextRegister();
			Exp src;
			
			op.codeGen(s);

			s.popSource(op.endLocation.line, src);
			s.freeExpTempRegs(&src);
			assert(s.nextRegister() == funcReg);

			s.pushRegister();
			uint thisReg = s.nextRegister();

			if(context)
			{
				context.codeGen(s);
				s.popMoveTo(op.endLocation.line, thisReg);
			}

			s.pushRegister();

			Expression.codeGenListToNextReg(s, args);

			s.codeR(op.endLocation.line, Op.Precall, funcReg, src.index, (context is null) ? 1 : 0);
			s.popRegister(thisReg);

			if(args.length == 0)
				s.pushCall(endLocation.line, funcReg, 2);
			else if(args[$ - 1].isMultRet())
				s.pushCall(endLocation.line, funcReg, 0);
			else
				s.pushCall(endLocation.line, funcReg, args.length + 2);
		}
	}

	public override void checkToNothing()
	{
		// OK
	}

	public override bool isMultRet()
	{
		return true;
	}

	public override Expression fold()
	{
		op = op.fold();

		if(context)
			context = context.fold();

		foreach(ref arg; args)
			arg = arg.fold();

		return this;
	}
}

class IndexExp : PostfixExp
{
	public Expression index;

	public this(Location location, Location endLocation, Expression operand, Expression index)
	{
		super(location, endLocation, AstTag.IndexExp, operand);
		this.index = index;
	}
	
	public override void codeGen(FuncState s)
	{
		if(cast(VarargExp)op)
		{
			if(!s.mIsVararg)
				throw new MDCompileException(location, "'vararg' cannot be used in a non-variadic function");
				
			index.codeGen(s);
			s.popVargIndex(endLocation.line);
		}
		else
		{
			op.codeGen(s);

			s.topToSource(endLocation.line);

			index.codeGen(s);
			s.popIndex(endLocation.line);
		}
	}

	public override Expression fold()
	{
		op = op.fold();
		index = index.fold();

		if(op.isConstant && index.isConstant)
		{
			if(!op.isString || !index.isInt)
				throw new MDCompileException(location, "Can only index strings with integers at compile time");

			int idx = index.asInt();

			if(idx < 0)
				idx += op.asString.length;

			if(idx < 0 || idx >= op.asString.length)
				throw new MDCompileException(location, "Invalid string index");

			return new CharExp(location, op.asString[idx]);
		}

		return this;
	}
}

class SliceExp : PostfixExp
{
	public Expression loIndex;
	public Expression hiIndex;

	public this(Location location, Location endLocation, Expression operand, Expression loIndex, Expression hiIndex)
	{
		super(location, endLocation, AstTag.SliceExp, operand);
		this.loIndex = loIndex;
		this.hiIndex = hiIndex;
	}
	
	public override void codeGen(FuncState s)
	{
		uint reg = s.nextRegister();
		Expression.codeGenListToNextReg(s, [op, loIndex, hiIndex]);

		s.pushSlice(endLocation.line, reg);
	}

	public override Expression fold()
	{
		op = op.fold();
		loIndex = loIndex.fold();
		hiIndex = hiIndex.fold();

		if(op.isConstant && loIndex.isConstant && hiIndex.isConstant)
		{
			if(!op.isString || !loIndex.isInt || !hiIndex.isInt)
				throw new MDCompileException(location, "Can only slice strings with integers at compile time");

			dchar[] str = op.asString();
			int l = loIndex.asInt();
			int h = hiIndex.asInt();

			if(l < 0)
				l += str.length;

			if(h < 0)
				h += str.length;

			if(l < 0 || l >= str.length || h < 0 || h >= str.length || l > h)
				throw new MDCompileException(location, "Invalid slice indices");

			return new StringExp(location, str[l .. h]);
		}

		return this;
	}
}

class VargSliceExp : PostfixExp
{
	public Expression loIndex;
	public Expression hiIndex;

	public this(Location location, Location endLocation, Expression loIndex, Expression hiIndex)
	{
		super(location, endLocation, AstTag.VargSliceExp, null);
		this.loIndex = loIndex;
		this.hiIndex = hiIndex;
	}
	
	public override void codeGen(FuncState s)
	{
		if(!s.mIsVararg)
			throw new MDCompileException(location, "'vararg' cannot be used in a non-variadic function");

		uint reg = s.nextRegister();
		Expression.codeGenListToNextReg(s, [loIndex, hiIndex]);

		s.pushVargSlice(endLocation.line, reg);
	}

	public override Expression fold()
	{
		loIndex = loIndex.fold();
		hiIndex = hiIndex.fold();
		return this;
	}

	public override bool isMultRet()
	{
		return true;
	}
}

class PrimaryExp : Expression
{
	public this(Location location, AstTag type)
	{
		super(location, location, type);
	}
	
	public this(Location location, Location endLocation, AstTag type)
	{
		super(location, endLocation, type);
	}

	public static Expression parse(Lexer l)
	{
		Expression exp;
		auto location = l.loc;

		switch(l.type)
		{
			case Token.Type.Ident:                  exp = IdentExp.parse(l); break;
			case Token.Type.This:                   exp = ThisExp.parse(l); break;
			case Token.Type.Null:                   exp = NullExp.parse(l); break;
			case Token.Type.True, Token.Type.False: exp = BoolExp.parse(l); break;
			case Token.Type.Vararg:                 exp = VarargExp.parse(l); break;
			case Token.Type.CharLiteral:            exp = CharExp.parse(l); break;
			case Token.Type.IntLiteral:             exp = IntExp.parse(l); break;
			case Token.Type.FloatLiteral:           exp = FloatExp.parse(l); break;
			case Token.Type.StringLiteral:          exp = StringExp.parse(l); break;
			case Token.Type.Function:               exp = FuncLiteralExp.parse(l); break;
			case Token.Type.Class:                  exp = ClassLiteralExp.parse(l); break;
			case Token.Type.LParen:                 exp = ParenExp.parse(l); break;
			case Token.Type.LBrace:                 exp = TableCtorExp.parse(l); break;
			case Token.Type.LBracket:               exp = ArrayCtorExp.parse(l); break;
			case Token.Type.Namespace:              exp = NamespaceCtorExp.parse(l); break;
			case Token.Type.Yield:                  exp = YieldExp.parse(l); break;
			case Token.Type.Super:                  exp = SuperCallExp.parse(l); break;
			default: l.tok.expected("Expression");
		}

		return PostfixExp.parse(l, exp);
	}

	public static MDValue parseJSON(Lexer l)
	{
		MDValue ret;
		auto location = l.loc;

		switch(l.type)
		{
			case Token.Type.Null:                   ret = NullExp.parseJSON(l); break;
			case Token.Type.True, Token.Type.False: ret = BoolExp.parseJSON(l); break;
			case Token.Type.IntLiteral:             ret = IntExp.parseJSON(l); break;
			case Token.Type.FloatLiteral:           ret = FloatExp.parseJSON(l); break;
			case Token.Type.StringLiteral:          ret = StringExp.parseJSON(l); break;
			case Token.Type.LBrace:                 ret = TableCtorExp.parseJSON(l); break;
			case Token.Type.LBracket:               ret = ArrayCtorExp.parseJSON(l); break;
			default: l.tok.expected("Expression");
		}

		return ret;
	}
	
	public override InstRef* codeCondition(FuncState s)
	{
		uint temp = s.pushRegister();
		codeGen(s);
		s.popMoveTo(endLocation.line, temp);
		s.codeR(endLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* ret = s.makeJump(endLocation.line, Op.Je);
		s.popRegister(temp);
		return ret;
	}
}

class IdentExp : PrimaryExp
{
	public Identifier name;

	public this(Location location, dchar[] name)
	{
		super(location, AstTag.IdentExp);
		this.name = new Identifier(location, name);
	}
	
	public this(Identifier i)
	{
		super(i.location, AstTag.IdentExp);
		this.name = i;
	}

	public static IdentExp parse(Lexer l)
	{
		return new IdentExp(Identifier.parse(l));
	}
	
	public override void codeGen(FuncState s)
	{
		s.pushVar(name);
	}

	public InstRef* codeCondition(FuncState s)
	{
		codeGen(s);
		Exp reg;
		s.popSource(endLocation.line, reg);
		s.codeR(endLocation.line, Op.IsTrue, 0, reg.index, 0);
		InstRef* ret = s.makeJump(endLocation.line, Op.Je);

		s.freeExpTempRegs(&reg);

		return ret;
	}
}

class ThisExp : PrimaryExp
{
	public this(Location location)
	{
		super(location, AstTag.ThisExp);
	}

	public static ThisExp parse(Lexer l)
	{
		with(l.expect(Token.Type.This))
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
		s.popSource(endLocation.line, reg);
		s.codeR(endLocation.line, Op.IsTrue, 0, reg.index, 0);
		InstRef* ret = s.makeJump(endLocation.line, Op.Je);

		s.freeExpTempRegs(&reg);

		return ret;
	}
}

class NullExp : PrimaryExp
{
	public this(Location location)
	{
		super(location, AstTag.NullExp);
	}

	public static NullExp parse(Lexer l)
	{
		with(l.expect(Token.Type.Null))
			return new NullExp(location);
	}

	public static MDValue parseJSON(Lexer l)
	{
		l.expect(Token.Type.Null);
		return MDValue.nullValue;
	}
	
	public override void codeGen(FuncState s)
	{
		s.pushNull();
	}

	public override bool isConstant()
	{
		return true;
	}

	public override bool isTrue()
	{
		return false;
	}
	
	public override bool isNull()
	{
		return true;
	}
}

class BoolExp : PrimaryExp
{
	public bool value;

	public this(Location location, bool value)
	{
		super(location, AstTag.BoolExp);
		this.value = value;
	}

	public static BoolExp parse(Lexer l)
	{
		if(l.type == Token.Type.True)
			with(l.expect(Token.Type.True))
				return new BoolExp(location, true);
		else
			with(l.expect(Token.Type.False))
				return new BoolExp(location, false);
	}
	
	public static MDValue parseJSON(Lexer l)
	{
		if(l.type == Token.Type.True)
			with(l.expect(Token.Type.True))
				return MDValue(true);
		else
			with(l.expect(Token.Type.False))
				return MDValue(false);
	}
	
	public override void codeGen(FuncState s)
	{
		s.pushBool(value);
	}

	public override bool isConstant()
	{
		return true;
	}

	public override bool isTrue()
	{
		return value;
	}

	public override bool isBool()
	{
		return true;
	}

	public override bool asBool()
	{
		return value;
	}
}

class VarargExp : PrimaryExp
{
	public this(Location location)
	{
		super(location, AstTag.VarargExp);
	}

	public static VarargExp parse(Lexer l)
	{
		with(l.expect(Token.Type.Vararg))
			return new VarargExp(location);
	}
	
	public override void codeGen(FuncState s)
	{
		if(s.mIsVararg == false)
			throw new MDCompileException(location, "'vararg' cannot be used in a non-variadic function");

		s.pushVararg();
	}

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(location, "Cannot use 'vararg' as a condition");
	}

	public bool isMultRet()
	{
		return true;
	}
}

class CharExp : PrimaryExp
{
	public dchar value;

	public this(Location location, dchar value)
	{
		super(location, AstTag.CharExp);
		this.value = value;
	}

	public static CharExp parse(Lexer l)
	{
		with(l.expect(Token.Type.CharLiteral))
			return new CharExp(location, intValue);
	}
	
	public override void codeGen(FuncState s)
	{
		s.pushChar(value);
	}

	public override bool isConstant()
	{
		return true;
	}

	public override bool isTrue()
	{
		return (value != 0);
	}

	public override bool isChar()
	{
		return true;
	}

	public override dchar asChar()
	{
		return value;
	}
}

class IntExp : PrimaryExp
{
	public int value;

	public this(Location location, int value)
	{
		super(location, AstTag.IntExp);
		this.value = value;
	}

	public static IntExp parse(Lexer l)
	{
		with(l.expect(Token.Type.IntLiteral))
			return new IntExp(location, intValue);
	}

	public static MDValue parseJSON(Lexer l)
	{
		with(l.expect(Token.Type.IntLiteral))
			return MDValue(intValue);
	}
	
	public override void codeGen(FuncState s)
	{
		s.pushInt(value);
	}

	public override bool isConstant()
	{
		return true;
	}

	public override bool isTrue()
	{
		return (value != 0);
	}

	public override bool isInt()
	{
		return true;
	}

	public override int asInt()
	{
		return value;
	}

	public override mdfloat asFloat()
	{
		return cast(mdfloat)value;
	}
}

class FloatExp : PrimaryExp
{
	public mdfloat value;

	public this(Location location, mdfloat value)
	{
		super(location, AstTag.FloatExp);
		this.value = value;
	}

	public static FloatExp parse(Lexer l)
	{
		with(l.expect(Token.Type.FloatLiteral))
			return new FloatExp(location, floatValue);
	}

	public static MDValue parseJSON(Lexer l)
	{
		with(l.expect(Token.Type.FloatLiteral))
			return MDValue(floatValue);
	}
	
	public override void codeGen(FuncState s)
	{
		s.pushFloat(value);
	}

	public override bool isConstant()
	{
		return true;
	}

	public override bool isTrue()
	{
		return (value != 0.0);
	}

	public override bool isFloat()
	{
		return true;
	}

	public override mdfloat asFloat()
	{
		return value;
	}
}

class StringExp : PrimaryExp
{
	public dchar[] value;

	public this(Location location, dchar[] value)
	{
		super(location, AstTag.StringExp);
		this.value = value;
	}

	public static StringExp parse(Lexer l)
	{
		with(l.expect(Token.Type.StringLiteral))
			return new StringExp(location, stringValue);
	}

	public static MDValue parseJSON(Lexer l)
	{
		with(l.expect(Token.Type.StringLiteral))
			return MDValue(stringValue);
	}
	
	public override void codeGen(FuncState s)
	{
		s.pushString(value);
	}

	public override bool isConstant()
	{
		return true;
	}

	public override bool isTrue()
	{
		return true;
	}

	public override bool isString()
	{
		return true;
	}

	public override dchar[] asString()
	{
		return value;
	}
}

class FuncLiteralExp : PrimaryExp
{
	public FuncDef def;

	public this(Location location, FuncDef def)
	{
		super(location, def.endLocation, AstTag.FuncLiteralExp);
		this.def = def;
	}

	public static FuncLiteralExp parse(Lexer l)
	{
		auto location = l.loc;
		auto def = FuncDef.parseLiteral(l);
		return new FuncLiteralExp(location, def);
	}
	
	public override void codeGen(FuncState s)
	{
		def.codeGen(s);
	}

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(location, "Cannot use a function literal as a condition");
	}

	public override FuncLiteralExp fold()
	{
		def = def.fold();
		return this;
	}
}

class ClassLiteralExp : PrimaryExp
{
	public ClassDef def;

	public this(Location location, ClassDef def)
	{
		super(location, def.endLocation, AstTag.ClassLiteralExp);
		this.def = def;
	}
	
	public static ClassLiteralExp parse(Lexer l)
	{
		auto location = l.loc;
		return new ClassLiteralExp(location, ClassDef.parse(l, true));
	}

	public override void codeGen(FuncState s)
	{
		def.codeGen(s);
	}

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(location, "Cannot use a class literal as a condition");
	}

	public override Expression fold()
	{
		def = def.fold();
		return this;
	}
}

class ParenExp : PrimaryExp
{
	public Expression exp;

	public this(Location location, Location endLocation, Expression exp)
	{
		super(location, endLocation, AstTag.ParenExp);
		this.exp = exp;
	}

	public static Expression parse(Lexer l)
	{
		auto location = l.loc;

		l.expect(Token.Type.LParen);
		auto exp = Expression.parse(l);
		Location endLocation = l.expect(Token.Type.RParen).location;

		if(exp.isMultRet())
			return new ParenExp(location, endLocation, exp);
		else
			return exp;
	}
	
	public override void codeGen(FuncState s)
	{
		assert(exp.isMultRet(), "ParenExp codeGen not multret");

		uint reg = s.nextRegister();
		exp.codeGen(s);
		s.popMoveTo(location.line, reg);
		uint checkReg = s.pushRegister();

		assert(reg == checkReg, "ParenExp codeGen wrong regs");

		s.pushTempReg(reg);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		uint temp = s.nextRegister();
		exp.codeGen(s);
		s.popMoveTo(endLocation.line, temp);
		s.codeR(endLocation.line, Op.IsTrue, 0, temp, 0);
		InstRef* ret = s.makeJump(endLocation.line, Op.Je);
		return ret;
	}

	public override Expression fold()
	{
		exp = exp.fold();
		return this;
	}
}

class TableCtorExp : PrimaryExp
{
	public Expression[2][] fields;

	public this(Location location, Location endLocation, Expression[2][] fields)
	{
		super(location, endLocation, AstTag.TableCtorExp);
		this.fields = fields;
	}
	
	public static Expression[2][] parseFields(Lexer l, Token.Type terminator)
	{
		Expression[2][] fields = new Expression[2][8];
		uint i = 0;

		void addPair(Expression k, Expression v)
		{
			if(i >= fields.length)
				fields.length = fields.length * 2;

			fields[i][0] = k;
			fields[i][1] = v;
			i++;
		}

		if(l.type != terminator)
		{
			bool lastWasFunc = false;

			void parseField()
			{
				Expression k;
				Expression v;

				switch(l.type)
				{
					case Token.Type.LBracket:
						l.next();
						k = Expression.parse(l);

						l.expect(Token.Type.RBracket);
						l.expect(Token.Type.Assign);

						v = Expression.parse(l);
						break;

					case Token.Type.Function:
						FuncDef fd = FuncDef.parseSimple(l);
						k = new StringExp(fd.location, fd.name.name);
						v = new FuncLiteralExp(fd.location, fd);
						break;

					default:
						Identifier id = Identifier.parse(l);
						l.expect(Token.Type.Assign);
						k = new StringExp(id.location, id.name);
						v = Expression.parse(l);
						break;
				}

				addPair(k, v);
			}

			parseField();

			while(l.type != terminator)
			{
				if(l.type == Token.Type.Comma)
					l.next();

				parseField();
			}
		}
		
		return fields[0 .. i];
	}

	public static TableCtorExp parse(Lexer l)
	{
		auto location = l.loc;

		l.expect(Token.Type.LBrace);

		auto fields = parseFields(l, Token.Type.RBrace);
		auto endLocation = l.expect(Token.Type.RBrace).location;

		return new TableCtorExp(location, endLocation, fields);
	}

	public static TableCtorExp parseAttrs(Lexer l)
	{
		auto location = l.loc;

		l.expect(Token.Type.LAttr);

		auto fields = parseFields(l, Token.Type.RAttr);
		auto endLocation = l.expect(Token.Type.RAttr).location;

		return new TableCtorExp(location, endLocation, fields);
	}

	public static MDValue parseJSON(Lexer l)
	{
		l.expect(Token.Type.LBrace);

		MDTable ret = new MDTable();

		if(l.type != Token.Type.RBrace)
		{
			void parseField()
			{
				MDValue k = StringExp.parseJSON(l);
				l.expect(Token.Type.Colon);
				MDValue v = PrimaryExp.parseJSON(l);

				ret[k] = v;
			}

			parseField();

			while(l.type != Token.Type.RBrace)
			{
				l.expect(Token.Type.Comma);
				parseField();
			}
		}

		l.tok.expect(Token.Type.RBrace);
		l.next();

		return MDValue(ret);
	}
	
	public override void codeGen(FuncState s)
	{
		uint destReg = s.pushRegister();
		s.codeI(location.line, Op.NewTable, destReg, 0);

		foreach(field; fields)
		{
			field[0].codeGen(s);
			Exp idx;
			s.popSource(field[0].endLocation.line, idx);

			field[1].codeGen(s);
			Exp val;
			s.popSource(field[1].endLocation.line, val);

			s.codeR(field[1].endLocation.line, Op.IndexAssign, destReg, idx.index, val.index);

			s.freeExpTempRegs(&val);
			s.freeExpTempRegs(&idx);
		}

		s.pushTempReg(destReg);
	}

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(location, "Cannot use a table constructor as a condition");
	}

	public override TableCtorExp fold()
	{
		foreach(ref field; fields)
		{
			field[0] = field[0].fold();
			field[1] = field[1].fold();
		}

		return this;
	}
}

class ArrayCtorExp : PrimaryExp
{
	public Expression[] values;

	protected const uint maxFields = Instruction.arraySetFields * Instruction.rtMax;

	public this(Location location, Location endLocation, Expression[] values)
	{
		super(location, endLocation, AstTag.ArrayCtorExp);
		this.values = values;
	}

	public static ArrayCtorExp parse(Lexer l)
	{
		auto location = l.loc;

		l.expect(Token.Type.LBracket);

		List!(Expression) values;

		if(l.type != Token.Type.RBracket)
		{
			values.add(Expression.parse(l));

			while(l.type != Token.Type.RBracket)
			{
				if(l.type == Token.Type.Comma)
					l.next();
					
				values.add(Expression.parse(l));
			}
		}

		auto endLocation = l.expect(Token.Type.RBracket).location;
		return new ArrayCtorExp(location, endLocation, values.toArray());
	}

	public static MDValue parseJSON(Lexer l)
	{
		l.expect(Token.Type.LBracket);

		MDArray ret = new MDArray(0);

		if(l.type != Token.Type.RBracket)
		{
			ret ~= PrimaryExp.parseJSON(l);

			while(l.type != Token.Type.RBracket)
			{
				l.expect(Token.Type.Comma);
				ret ~= PrimaryExp.parseJSON(l);
			}
		}

		l.expect(Token.Type.RBracket);
		return MDValue(ret);
	}
	
	public override void codeGen(FuncState s)
	{
		if(values.length > maxFields)
			throw new MDCompileException(location, "Array constructor has too many fields (more than {})", maxFields);

		uint min(uint a, uint b)
		{
			return (a > b) ? b : a;
		}

		uint destReg = s.pushRegister();

		if(values.length > 0 && values[$ - 1].isMultRet())
			s.codeI(location.line, Op.NewArray, destReg, values.length - 1);
		else
			s.codeI(location.line, Op.NewArray, destReg, values.length);

		if(values.length > 0)
		{
			int index = 0;
			int fieldsLeft = values.length;
			uint block = 0;

			while(fieldsLeft > 0)
			{
				uint numToDo = min(fieldsLeft, Instruction.arraySetFields);

				Expression.codeGenListToNextReg(s, values[index .. index + numToDo]);

				fieldsLeft -= numToDo;

				if(fieldsLeft == 0 && values[$ - 1].isMultRet())
					s.codeR(endLocation.line, Op.SetArray, destReg, 0, block);
				else
					s.codeR(values[index + numToDo - 1].endLocation.line, Op.SetArray, destReg, numToDo + 1, block);

				index += numToDo;
				block++;
			}
		}

		s.pushTempReg(destReg);
	}

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(location, "Cannot use an array constructor as a condition");
	}

	public override Expression fold()
	{
		foreach(ref value; values)
			value = value.fold();
			
		return this;
	}
}

class NamespaceCtorExp : PrimaryExp
{
	public NamespaceDef def;

	public this(Location location, NamespaceDef def)
	{
		super(location, def.endLocation, AstTag.NamespaceCtorExp);
		this.def = def;
	}

	public static NamespaceCtorExp parse(Lexer l)
	{
		auto location = l.loc;
		auto def = NamespaceDef.parse(l);
		return new NamespaceCtorExp(location, def);
	}
	
	public override void codeGen(FuncState s)
	{
		def.codeGen(s);
	}
	
	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(location, "Cannot use namespace constructor as a condition");
	}

	public override Expression fold()
	{
		def = def.fold();
		return this;
	}
}

class YieldExp : PrimaryExp
{
	public Expression[] args;

	public this(Location location, Location endLocation, Expression[] args)
	{
		super(location, endLocation, AstTag.YieldExp);
		this.args = args;
	}

	public static YieldExp parse(Lexer l)
	{
		auto location = l.loc;

		l.expect(Token.Type.Yield);
		l.expect(Token.Type.LParen);

		Expression[] args;

		if(l.type != Token.Type.RParen)
			args = Expression.parseArguments(l);

		auto endLocation = l.expect(Token.Type.RParen).location;
		return new YieldExp(location, endLocation, args);
	}
	
	public override void codeGen(FuncState s)
	{
		uint firstReg = s.nextRegister();

		Expression.codeGenListToNextReg(s, args);

		if(args.length == 0)
			s.pushYield(endLocation.line, firstReg, 1);
		else if(args[$ - 1].isMultRet())
			s.pushYield(endLocation.line, firstReg, 0);
		else
			s.pushYield(endLocation.line, firstReg, args.length + 1);
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
		foreach(ref arg; args)
			arg = arg.fold();

		return this;
	}
}

class SuperCallExp : PrimaryExp
{
	public Expression method;
	public Expression[] args;

	public this(Location location, Location endLocation, Expression method, Expression[] args)
	{
		super(location, endLocation, AstTag.SuperCallExp);
		this.method = method;
		this.args = args;
	}

	public static SuperCallExp parse(Lexer l)
	{
		auto location = l.expect(Token.Type.Super).location;

		Expression method;

		if(l.type == Token.Type.Dot)
		{
			l.next();

			if(l.type == Token.Type.Ident)
			{
				with(l.expect(Token.Type.Ident))
					method = new StringExp(location, stringValue);
			}
			else
			{
				l.expect(Token.Type.LParen);
				method = Expression.parse(l);
				l.expect(Token.Type.RParen);
			}
		}
		else
			method = new StringExp(l.loc, "constructor");

		l.expect(Token.Type.LParen);

		Expression[] args;

		if(l.type != Token.Type.RParen)
			args = Expression.parseArguments(l);

		auto endLocation = l.expect(Token.Type.RParen).location;
		return new SuperCallExp(location, endLocation, method, args);
	}
	
	public override void codeGen(FuncState s)
	{
		if(!s.isMethod())
			throw new MDCompileException(location, "'super' calls may only appear in class methods");

		ClassDef def = FuncState.currentClass();
		assert(def !is null, "SuperCallExp null def");

		if(!def.hasBase())
			throw new MDCompileException(location, "'super' calls may not be used in classes which have no base classes");

		// rewrite super(1, 2, 3) as super.constructor(1, 2, 3)
		// rewrite super.method(1, 2, 3) as __class.super.("method")(with this, 1, 2, 3)
		// rewrite super.("method")(1, 2, 3) as __class.super.("method")(with this, 1, 2, 3)

		ThisExp _this = new ThisExp(location);
		IdentExp _class = new IdentExp(location, "__class");
		DotSuperExp sup = new DotSuperExp(location, endLocation, _class);
		DotExp dot = new DotExp(location, endLocation, sup, method);
		CallExp call = new CallExp(location, endLocation, dot, _this, args);

		call.codeGen(s);
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
		foreach(ref arg; args)
			arg = arg.fold();

		return this;
	}
}