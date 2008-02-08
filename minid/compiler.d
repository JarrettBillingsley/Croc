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
//debug = SHOWME;

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
	
	try
	{
		foreach(stmt; stmts)
			stmt.fold().codeGen(fs);
	
		if(stmts.length == 0)
			fs.codeI(1, Op.Ret, 0, 1);
		else
			fs.codeI(stmts[$ - 1].endLocation.line, Op.Ret, 0, 1);
	}
	finally
	{
		debug(SHOWME)
		{
			fs.showMe(); Stdout.flush;
		}
	}

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

	try
	{
		ret.codeGen(fs);
		fs.codeI(ret.endLocation.line, Op.Ret, 0, 1);
	}
	finally
	{
		debug(SHOWME)
		{
			fs.showMe(); Stdout.flush;
		}
	}

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
		Object,
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
		Type.Object: "object",
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
		return mNewlineSinceLastTok ||
			mTok.type == Token.Type.EOF ||
			mTok.type == Token.Type.Semicolon ||
			mTok.type == Token.Type.RBrace ||
			mTok.type == Token.Type.RParen ||
			mTok.type == Token.Type.RBracket;
	}

	public final void statementTerm()
	{
		if(mNewlineSinceLastTok)
			return;
		else
		{
			if(mTok.type == Token.Type.EOF || mTok.type == Token.Type.RBrace || mTok.type == Token.Type.RParen || mTok.type == Token.Type.RBracket)
				return;
			else if(mTok.type == Token.Type.Semicolon)
				next();
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
				auto ch = lookaheadChar();

				if((ch >= '0' && ch <= '9') || ch == '_')
				{
					hasPoint = true;
					add(mCharacter);
					nextChar();
				}
				else
				{
					// next token is either a .. or maybe it's .something
					break;
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
			{
				// REACHABLE?
				throw new MDCompileException(mLoc, "Floating point literal '{}' must have at least one digit after decimal point", buf[0 .. i]);
			}
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
		{
			auto e = new MDCompileException(beginning, "Unterminated string or character literal");
			e.atEOF = true;
			throw e;
		}

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

		loop: while(true)
		{
			if(isEOF())
			{
				auto e = new MDCompileException(beginning, "Unterminated string literal");
				e.atEOF = true;
				throw e;
			}

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
						else
							break loop;
					}
					else
					{
						if(escape && mCharacter == delimiter)
							break loop;

						buf.add(mCharacter);
						nextChar();
					}
					break;
			}
		}

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
			insertLocal(new Identifier(mLocation, "this"));
			activateLocals(1);
		}
	}
	
	public bool isTopLevel()
	{
		return mParent is null;
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
				
				codeR(line, Op.VargIndexAssign, 0, dest.index, src.index);
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
		topToSource(line);
		mExpStack[mExpSP - 1].type = ExpType.Length;
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
				codeR(line, Op.VargIndexAssign, 0, dest.index, srcReg);
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
				if(cleanup)
					freeExpTempRegs(e);

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
	ObjectDef,
	FuncDef,
	NamespaceDef,
	Module,
	ModuleDecl,
	ImportStmt,
	BlockStmt,
	ScopeStmt,
	ExpressionStmt,
	FuncDecl,
	ObjectDecl,
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
	IncExp,
	DecExp,
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
	DotSuperExp,
	IndexExp,
	VargIndexExp,
	SliceExp,
	VargSliceExp,
	CallExp,
	MethodCallExp,
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
	ObjectLiteralExp,
	ParenExp,
	TableCtorExp,
	ArrayCtorExp,
	NamespaceCtorExp,
	YieldExp,
	SuperCallExp,
	ForeachComprehension,
	ForNumComprehension,
	IfComprehension,
	ArrayComprehension,
	TableComprehension,
}

const char[][] AstTagNames =
[
	AstTag.Other:                "Other",
	AstTag.ObjectDef:            "ObjectDef",
	AstTag.FuncDef:              "FuncDef",
	AstTag.NamespaceDef:         "NamespaceDef",
    AstTag.Module:               "Module",
    AstTag.ModuleDecl:           "ModuleDecl",
    AstTag.ImportStmt:           "ImportStmt",
    AstTag.BlockStmt:            "BlockStmt",
    AstTag.ScopeStmt:            "ScopeStmt",
    AstTag.ExpressionStmt:       "ExpressionStmt",
    AstTag.FuncDecl:             "FuncDecl",
    AstTag.ObjectDecl:           "ObjectDecl",
    AstTag.NamespaceDecl:        "NamespaceDecl",
    AstTag.VarDecl:              "VarDecl",
    AstTag.IfStmt:               "IfStmt",
    AstTag.WhileStmt:            "WhileStmt",
    AstTag.DoWhileStmt:          "DoWhileStmt",
    AstTag.ForStmt:              "ForStmt",
    AstTag.ForNumStmt:           "ForNumStmt",
    AstTag.ForeachStmt:          "ForeachStmt",
    AstTag.SwitchStmt:           "SwitchStmt",
    AstTag.CaseStmt:             "CaseStmt",
    AstTag.DefaultStmt:          "DefaultStmt",
    AstTag.ContinueStmt:         "ContinueStmt",
    AstTag.BreakStmt:            "BreakStmt",
    AstTag.ReturnStmt:           "ReturnStmt",
    AstTag.TryStmt:              "TryStmt",
    AstTag.ThrowStmt:            "ThrowStmt",
    AstTag.Assign:               "Assign",
    AstTag.AddAssign:            "AddAssign",
    AstTag.SubAssign:            "SubAssign",
    AstTag.CatAssign:            "CatAssign",
    AstTag.MulAssign:            "MulAssign",
    AstTag.DivAssign:            "DivAssign",
    AstTag.ModAssign:            "ModAssign",
    AstTag.OrAssign:             "OrAssign",
    AstTag.XorAssign:            "XorAssign",
    AstTag.AndAssign:            "AndAssign",
    AstTag.ShlAssign:            "ShlAssign",
    AstTag.ShrAssign:            "ShrAssign",
    AstTag.UShrAssign:           "UShrAssign",
    AstTag.CondAssign:           "CondAssign",
    AstTag.CondExp:              "CondExp",
    AstTag.IncExp:               "IncExp",
    AstTag.DecExp:               "DecExp",
    AstTag.OrOrExp:              "OrOrExp",
    AstTag.AndAndExp:            "AndAndExp",
    AstTag.OrExp:                "OrExp",
    AstTag.XorExp:               "XorExp",
    AstTag.AndExp:               "AndExp",
    AstTag.EqualExp:             "EqualExp",
    AstTag.NotEqualExp:          "NotEqualExp",
    AstTag.IsExp:                "IsExp",
    AstTag.NotIsExp:             "NotIsExp",
    AstTag.LTExp:                "LTExp",
    AstTag.LEExp:                "LEExp",
    AstTag.GTExp:                "GTExp",
    AstTag.GEExp:                "GEExp",
    AstTag.Cmp3Exp:              "Cmp3Exp",
    AstTag.AsExp:                "AsExp",
    AstTag.InExp:                "InExp",
    AstTag.NotInExp:             "NotInExp",
    AstTag.ShlExp:               "ShlExp",
    AstTag.ShrExp:               "ShrExp",
    AstTag.UShrExp:              "UShrExp",
    AstTag.AddExp:               "AddExp",
    AstTag.SubExp:               "SubExp",
    AstTag.CatExp:               "CatExp",
    AstTag.MulExp:               "MulExp",
    AstTag.DivExp:               "DivExp",
    AstTag.ModExp:               "ModExp",
    AstTag.NegExp:               "NegExp",
    AstTag.NotExp:               "NotExp",
    AstTag.ComExp:               "ComExp",
    AstTag.LenExp:               "LenExp",
    AstTag.VargLenExp:           "VargLenExp",
    AstTag.CoroutineExp:         "CoroutineExp",
    AstTag.DotExp:               "DotExp",
    AstTag.DotSuperExp:          "DotSuperExp",
    AstTag.IndexExp:             "IndexExp",
    AstTag.VargIndexExp:         "VargIndexExp",
    AstTag.SliceExp:             "SliceExp",
    AstTag.VargSliceExp:         "VargSliceExp",
    AstTag.CallExp:              "CallExp",
    AstTag.MethodCallExp:        "MethodCallExp",
    AstTag.IdentExp:             "IdentExp",
    AstTag.ThisExp:              "ThisExp",
    AstTag.NullExp:              "NullExp",
    AstTag.BoolExp:              "BoolExp",
    AstTag.VarargExp:            "VarargExp",
    AstTag.IntExp:               "IntExp",
    AstTag.FloatExp:             "FloatExp",
    AstTag.CharExp:              "CharExp",
    AstTag.StringExp:            "StringExp",
    AstTag.FuncLiteralExp:       "FuncLiteralExp",
    AstTag.ObjectLiteralExp:     "ObjectLiteralExp",
    AstTag.ParenExp:             "ParenExp",
    AstTag.TableCtorExp:         "TableCtorExp",
    AstTag.ArrayCtorExp:         "ArrayCtorExp",
    AstTag.NamespaceCtorExp:     "NamespaceCtorExp",
    AstTag.YieldExp:             "YieldExp",
    AstTag.SuperCallExp:         "SuperCallExp",
    AstTag.ForeachComprehension: "ForeachComprehension",
    AstTag.ForNumComprehension:  "ForNumComprehension",
    AstTag.IfComprehension:      "IfComprehension",
    AstTag.ArrayComprehension:   "ArrayComprehension",
    AstTag.TableComprehension:   "TableComprehension"
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
		case AstTag.IncExp: return Op.Inc;
		case AstTag.DecExp: return Op.Dec;
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

/**
The base class for all the Abstract Syntax Tree nodes in the language.
*/
abstract class AstNode
{
	/**
	The location of the beginning of this node.
	*/
	public Location location;

	/**
	The location of the end of this node.
	*/
	public Location endLocation;
	
	/**
	The tag indicating what kind of node this actually is.  You can switch on this
	to walk an AST.
	*/
	public AstTag type;

	/**
	The base constructor, but since this class is abstract, this can only be
	called from derived classes.
	
	Params:
		location = The location of the beginning of this node.
		endLocation = The location of the end of this node.
		type = The type of this node.
	*/
	public this(Location location, Location endLocation, AstTag type)
	{
		this.location = location;
		this.endLocation = endLocation;
		this.type = type;
	}

	/**
	By default, toString() will return the string representation of the node type.
	*/
	public char[] toString()
	{
		return AstTagNames[type];
	}
}

/**
This node represents the guts of an object literal.  This node does not directly correspond
to a single grammar element; rather it represents the common attributes of both object
literals and object declarations.
*/
class ObjectDef : AstNode
{
	/**
	Represents a single field in the object.  Remember that methods are fields too.
	*/
	struct Field
	{
		/**
		The name of the field.  This corresponds to either the name of a data member or
		the name of a method.
		*/
		dchar[] name;
		
		/**
		The initializer of the field.  This will never be null.  If a field is declared in
		an object but not given a value, a NullExp will be inserted into this field.
		*/
		Expression initializer;
	}

	/**
	The name of the object.  This field can be null, which indicates that the name of the
	object will be taken from its base object at runtime.
	*/
	public Identifier name;
	
	/**
	The base object from which this object derives.  This field will never be null.  If
	no base object is specified, it is given the value of an IdentExp with the identifier
	"Object".
	*/
	public Expression baseObject;
	
	/**
	The fields in this object, in the order they were declared.  See the Field struct above.
	*/
	public Field[] fields;
	
	/**
	Optional attribute table for this object.  This member can be null.
	*/
	public TableCtorExp attrs;

	/**
	*/
	public this(Location location, Location endLocation, Identifier name, Expression baseObject, Field[] fields, TableCtorExp attrs = null)
	{
		super(location, endLocation, AstTag.ObjectDef);
		this.name = name;
		this.baseObject = baseObject;
		this.fields = fields;
		this.attrs = attrs;
	}

	/**
	Parse an object definition.  
	
	Params:
		l = The lexer to be used.
		nameOptional = If true, the name is optional (such as with object literal expressions).
			Otherwise, the name is required (such as with object declarations).
		attrs = An optional attribute table to associate with the object.  This is here
			because an attribute table must first be parsed before the compiler can determine
			what kind of declaration follows it.
			
	Returns:
		An instance of this class.
	*/
	public static ObjectDef parse(Lexer l, bool nameOptional, TableCtorExp attrs = null)
	{
		auto location = l.expect(Token.Type.Object).location;

		Identifier name;

		if(!nameOptional || l.type == Token.Type.Ident)
			name = Identifier.parse(l);

		Expression baseObject;

		if(l.type == Token.Type.Colon)
		{
			l.next();
			baseObject = Expression.parse(l);
		}
		else
			baseObject = new IdentExp(l.loc, "Object");

		l.expect(Token.Type.LBrace);

		bool[dchar[]] fieldMap;
		Field[] fields;

		void addField(Identifier name, Expression v)
		{
			if(name.name in fieldMap)
				throw new MDCompileException(name.location, "Redeclaration of field '{}'", name.name);

			fieldMap[name.name] = true;
			fields ~= Field(name.name, v);
		}

		void addMethod(FuncDef m)
		{
			dchar[] name = m.name.name;
			addField(m.name, new FuncLiteralExp(m.location, m));
		}

		while(l.type != Token.Type.RBrace)
		{
			switch(l.type)
			{
				case Token.Type.LAttr:
					auto attr = TableCtorExp.parseAttrs(l);
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
					auto e = new MDCompileException(l.loc, "Object at {} is missing its closing brace", location.toString());
					e.atEOF = true;
					throw e;

				default:
					l.tok.expected("Object method or field");
			}
		}

		l.tok.expect(Token.Type.RBrace);
		auto endLocation = l.loc;
		l.next();

		return new ObjectDef(location, endLocation, name, baseObject, fields, attrs);
	}
	
	public void codeGen(FuncState s)
	{
		baseObject.codeGen(s);
		Exp base;
		s.popSource(location.line, base);
		s.freeExpTempRegs(&base);

		uint destReg = s.pushRegister();
		uint nameConst = name is null ? s.tagConst(s.codeNullConst()) : s.tagConst(s.codeStringConst(name.name));
		s.codeR(location.line, Op.Object, destReg, nameConst, base.index);

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

	/**
	*/
	public ObjectDef fold()
	{
		baseObject = baseObject.fold();

		foreach(ref field; fields)
			field.initializer = field.initializer.fold();

		if(attrs)
			attrs = attrs.fold();

		return this;
	}
}

/**
Similar to ObjectDef, this class represents the common attributes of both function literals
and function declarations.
*/
class FuncDef : AstNode
{
	/**
	Represents a parameter to the function.
	*/
	struct Param
	{
		/**
		The name of the parameter.
		*/
		Identifier name;
		
		/**
		The default value for the parameter.  This can be null, in which case it will have
		no default value.
		*/
		Expression defValue;
	}

	/**
	The name of the function.  This will never be null.  In the case of function literals
	without names, this will be filled with an auto-generated name based off the location of
	where the literal occurred.
	*/
	public Identifier name;
	
	/**
	The list of parameters to the function.  See the Param struct above.  This will always be
	at least one element long, and element 0 will always be the 'this' parameter.
	*/
	public Param[] params;
	
	/**
	Indicates whether or not this function is variadic.
	*/
	public bool isVararg;
	
	/**
	The body of the function.  In the case of lambda functions (i.e. "function(x) = x * x"), this
	is a ReturnStatement with one expression, the expression that is the lambda's body.
	*/
	public Statement code;
	
	/**
	Optional attribute table for this function.  This can be null.
	*/
	public TableCtorExp attrs;

	/**
	*/
	public this(Location location, Identifier name, Param[] params, bool isVararg, Statement code, TableCtorExp attrs = null)
	{
		super(location, code.endLocation, AstTag.FuncDef);
		this.params = params;
		this.isVararg = isVararg;
		this.code = code;
		this.name = name;
		this.attrs = attrs;
	}

	/**
	Parse everything starting from the left-paren of the parameter list to the end of the body.
	
	Params:
		l = The lexer to use.
		location = Where the function actually started.
		name = The name of the function.  Must be non-null.
		attrs = The optional attribute table.

	Returns:
		The completed function definition.
	*/
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

	/**
	Parse a simple function declaration.  This is basically a function declaration without
	any preceding 'local' or 'global'.  The function must have a name.
	*/
	public static FuncDef parseSimple(Lexer l, TableCtorExp attrs = null)
	{
		auto location = l.expect(Token.Type.Function).location;
		auto name = Identifier.parse(l);

		return parseBody(l, location, name, attrs);
	}
	
	/**
	Parse a function literal.  The name is optional, and one will be autogenerated for the
	function if none exists.
	*/
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

	/**
	Parse a parameter list, opening and closing parens included.
	
	Params:
		l = The lexer to use.
		isVararg = Return value to indicate if the parameter list ended with 'vararg'.
	
	Returns:
		An array of Param structs.
	*/
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

	public void codeGen(FuncState s)
	{
		FuncState fs = new FuncState(location, name.name, s);

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

	/**
	*/
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

/**
Like the ObjectDef and FuncDef classes, this represents the common attributes of both
namespace literals and declarations.
*/
class NamespaceDef : AstNode
{
	/**
	Represents a single field in the namespace.  Remember that functions are fields too.
	*/
	struct Field
	{
		/**
		The name of the field.  This corresponds to either the name of a data member or
		the name of a function.
		*/
		dchar[] name;
		
		/**
		The initializer of the field.  This will never be null.  If a field is declared in
		a namespace but not given a value, a NullExp will be inserted into this field.
		*/
		Expression initializer;
	}

	/**
	The name of the namespace.  This field will never be null.
	*/
	public Identifier name;
	
	/**
	The namespace which will become the parent of this namespace.  This field will never be
	null.  In the case that no parent is specified in the code, this will be a NullExp.
	*/
	public Expression parent;
	
	/**
	The fields in this namespace, in an arbitrary order.  See the Field struct above.
	*/
	public Field[] fields;
	
	/**
	Optional attribute table for this namespace.  This member can be null.
	*/
	public TableCtorExp attrs;

	/**
	*/
	public this(Location location, Location endLocation, Identifier name, Expression parent, Field[] fields, TableCtorExp attrs = null)
	{
		super(location, endLocation, AstTag.NamespaceDef);
		this.name = name;
		this.parent = parent;
		this.fields = fields;
		this.attrs = attrs;
	}

	/**
	Parse a namespace.  Both literals and declarations require a name.
	
	Params:
		l = The lexer to use.
		attrs = The optional attribute table to attach to this namespace.
		
	Returns:
		An instance of this class.
	*/
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

	/**
	*/
	public NamespaceDef fold()
	{
		foreach(ref field; fields)
			field.initializer = field.initializer.fold();

		if(attrs)
			attrs = attrs.fold();

		return this;
	}
}

/**
Represents a MiniD module.  This node usually forms the root of an AST tree, at least
when a module is compiled.
*/
class Module : AstNode
{
	/**
	The module declaration.  This will never be null.
	*/
	public ModuleDeclaration modDecl;
	
	/**
	A list of 0 or more statements which make up the body of the module.
	*/
	public Statement[] statements;

	/**
	*/
	public this(Location location, Location endLocation, ModuleDeclaration modDecl, Statement[] statements)
	{
		super(location, endLocation, AstTag.Module);
		this.modDecl = modDecl;
		this.statements = statements;
	}

	/**
	Parse a module.
	*/
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
			debug(SHOWME)
			{
				showMe(); fs.showMe(); Stdout.flush;
			}
			//fs.printExpStack();
		}

		assert(fs.mExpSP == 0, "module - not all expressions have been popped");

		def.mFunc = fs.toFuncDef();

		return def;
	}

	/**
	A debugging function which just prints the name of the module.
	*/
	public void showMe()
	{
		Stdout.formatln("module {}", join(modDecl.names, "."d));
	}
}

/**
This node represents the module declaration that comes at the top of every module.
*/
class ModuleDeclaration : AstNode
{
	/**
	The name of this module.  This is an array of strings, each element of which is one
	piece of a dotted name.  This array will always be at least one element long.
	*/
	public dchar[][] names;
	
	/**
	An optional attribute table to attach to the module.
	*/
	public TableCtorExp attrs;

	/**
	*/
	public this(Location location, Location endLocation, dchar[][] names, TableCtorExp attrs)
	{
		super(location, endLocation, AstTag.ModuleDecl);
		this.names = names;
		this.attrs = attrs;
	}

	/**
	Parse a module declaration.
	*/
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

	/**
	*/
	public ModuleDeclaration fold()
	{
		if(attrs)
			attrs = attrs.fold();

		return this;
	}
}

/**
The base class for all statements.
*/
abstract class Statement : AstNode
{
	public this(Location location, Location endLocation, AstTag type)
	{
		super(location, endLocation, type);
	}

	/**
	Parse a statement.
	
	Params:
		l = The lexer to use.
		needScope = If true, and the statement is a block statement, the block will be wrapped
			in a ScopeStatement.  Else, the raw block statement will be returned.
	*/
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
				Token.Type.Yield,
				Token.Type.Colon:

				return ExpressionStatement.parse(l);

			case
				Token.Type.Object,
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
	
	/**
	*/
	public abstract Statement fold();
}

/**
This node represents an import statement.
*/
class ImportStatement : Statement
{
	/**
	An optional renaming of the import.  This member can be null, in which case no renaming
	is done.  In the code "import x = y;", this member corresponds to "x".
	*/
	public Identifier importName;
	
	/**
	The expression which evaluates to a string containing the name of the module to import.
	The statement "import a.b.c" is actually syntactic sugar for "import("a.b.c")", so expr
	will be a StringExp in this case.  This expression is checked (if it's constant) to ensure
	that it's a string when constant folding occurs.
	*/
	public Expression expr;
	
	/**
	An optional list of symbols to import from the module.  In the code "import x : a, b, c",
	this corresponds to "a, b, c".
	*/
	public Identifier[] symbols;
	
	/**
	A parallel array to the symbols array.  This holds the names of the symbols as they should
	be called in this module.  The code "import x : a, b" is sugar for "import x : a = a, b = b".
	In the code "import x : y = a, z = b", this array corresponds to "y, z".
	*/
	public Identifier[] symbolNames;

	/**
	*/
	public this(Location location, Location endLocation, Identifier importName, Expression expr, Identifier[] symbols, Identifier[] symbolNames)
	{
		super(location, endLocation, AstTag.ImportStmt);
		this.importName = importName;
		this.expr = expr;
		this.symbols = symbols;
		this.symbolNames = symbolNames;
	}

	/**
	Parse an import statement.
	*/
	public static ImportStatement parse(Lexer l)
	{
		auto location = l.loc;

		l.expect(Token.Type.Import);

		Identifier importName;
		Expression expr;
		
		if(l.type == Token.Type.Ident && l.peek.type == Token.Type.Assign)
		{
			importName = Identifier.parse(l);
			l.next();
		}

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
		Identifier[] symbolNames;
		
		void parseSelectiveImport()
		{
			auto id = Identifier.parse(l);
			
			if(l.type == Token.Type.Assign)
			{
				l.next();
				symbolNames ~= id;
				symbols ~= Identifier.parse(l);
			}
			else
			{
				symbolNames ~= id;
				symbols ~= id;
			}
		}

		if(l.type == Token.Type.Colon)
		{
			l.next();

			parseSelectiveImport();

			while(l.type == Token.Type.Comma)
			{
				l.next();
				parseSelectiveImport();
			}
		}
		
		auto endLocation = l.loc;
		l.statementTerm();
		return new ImportStatement(location, endLocation, importName, expr, symbols, symbolNames);
	}
	
	public override void codeGen(FuncState s)
	{
		foreach(i, sym; symbols)
		{
			if(importName !is null && sym.name == importName.name)
				throw new MDCompileException(sym.location, "Variable '{}' conflicts with previous definition at {}",
					sym.name, importName.location.toString());

			foreach(sym2; symbols[0 .. i])
			{
				if(sym.name == sym2.name)
				{
					throw new MDCompileException(sym.location, "Variable '{}' conflicts with previous definition at {}",
						sym.name, sym2.location.toString());
				}
			}
		}

		if(importName is null)
		{
			uint firstReg = s.nextRegister();

			foreach(sym; symbols)
				s.pushRegister();

			// push then pop to ensure the stack size is set correctly.
			uint importReg = s.pushRegister();
			s.popRegister(importReg);

			expr.codeGen(s);
			Exp src;
			s.popSource(location.line, src);

			s.codeR(location.line, Op.Import, importReg, src.index, 0);

			for(int reg = firstReg + symbols.length - 1; reg >= firstReg; reg--)
				s.popRegister(reg);

			foreach(i, sym; symbols)
			{
				s.codeR(location.line, Op.Field, firstReg + i, importReg, s.tagConst(s.codeStringConst(sym.name)));
				s.insertLocal(symbolNames[i]);
			}

			s.activateLocals(symbols.length);
		}
		else
		{
			uint importReg = s.nextRegister();

			expr.codeGen(s);
			Exp src;
			s.popSource(location.line, src);

			s.codeR(location.line, Op.Import, importReg, src.index, 0);

			s.insertLocal(importName);
			s.activateLocals(1);

			uint firstReg = s.nextRegister();

			foreach(i, sym; symbols)
			{
				s.codeR(location.line, Op.Field, firstReg + i, importReg, s.tagConst(s.codeStringConst(sym.name)));
				s.insertLocal(symbolNames[i]);
			}

			s.activateLocals(symbols.length);
		}
	}

	/**
	*/
	public override Statement fold()
	{
		expr = expr.fold();
		
		if(expr.isConstant() && !expr.isString())
			throw new MDCompileException(expr.location, "Import expression must evaluate to a string");

		return this;
	}
}

/**
Another node which doesn't correspond to a grammar element.  This indicates a new nested scope.
An example of where this would be used is in an anonymous scope with some code in it.  All it
does is affects the codegen of the contained statement by beginning a new scope before it
and ending the scope after it.
*/
class ScopeStatement : Statement
{
	/**
	The statement contained within this scope.  Typically a block statement, but can
	be anything.
	*/
	public Statement statement;

	/**
	*/
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
	
	/**
	*/
	public override Statement fold()
	{
		statement = statement.fold();
		return this;
	}
}

/**
A statement that holds a side-effecting expression to be evaluated as a statement,
such as a function call, assignment etc.
*/
class ExpressionStatement : Statement
{
	/**
	The expression to be evaluated for this statement.  This must be a side-effecting
	expression, including function calls, yields, and assignments.  Conditional (?:)
	expressions and logical or and logical and (|| and &&) expressions are also allowed,
	providing at least one component is side-effecting.
	
	This class does $(B not) check that this expression is side-effecting; that is up to
	you.
	*/
	public Expression expr;

	/**
	*/
	public this(Location location, Location endLocation, Expression expr)
	{
		super(location, endLocation, AstTag.ExpressionStmt);
		this.expr = expr;
	}

	/**
	Parse an expression statement.
	*/
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

	/**
	*/
	public override Statement fold()
	{
		expr = expr.fold();
		return this;
	}
}

/**
Defines the types of protection possible for object, function, namespace, and variable
declarations.
*/
enum Protection
{
	/**
	This indicates "default" protection, which means global at module-level scope and local
	everywhere else.
	*/
	Default,
	
	/**
	This forces local protection.
	*/
	Local,
	
	/**
	This forces global protection.
	*/
	Global
}

/**
The abstract base class for the declaration statements.
*/
abstract class DeclStatement : Statement
{
	/**
	What protection level this declaration uses.
	*/
	public Protection protection;

	/**
	*/
	public this(Location location, Location endLocation, AstTag type, Protection protection)
	{
		super(location, endLocation, type);
		this.protection = protection;
	}

	/**
	Parse a declaration statement.

	Params:
		l = The lexer to use.
		attrs = An optional attribute table to attach to the declaration.  If the declaration
			is a variable declaration and this is non-null, an error will be thrown.
	*/
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

					case Token.Type.Object:
						return ObjectDecl.parse(l, attrs);

					case Token.Type.Namespace:
						return NamespaceDecl.parse(l, attrs);

					default:
						throw new MDCompileException(l.loc, "Illegal token '{}' after '{}'", l.peek.toString(), l.tok.toString());
				}

			case Token.Type.Function:
				return FuncDecl.parse(l, attrs);

			case Token.Type.Object:
				return ObjectDecl.parse(l, attrs);

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

/**
This node represents an object declaration.
*/
class ObjectDecl : DeclStatement
{
	/**
	The actual "guts" of the object.
	*/
	public ObjectDef def;

	/**
	The protection parameter can be any kind of protection.
	*/
	public this(Location location, Protection protection, ObjectDef def)
	{
		super(location, def.endLocation, AstTag.ObjectDecl, protection);
		this.def = def;
	}

	/**
	Parse an object declaration, optional protection included.
	
	Params:
		l = The lexer to use.
		attrs = An optional attribute table to attach to the declaration.
	*/
	public static ObjectDecl parse(Lexer l, TableCtorExp attrs = null)
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

		return new ObjectDecl(location, protection, ObjectDef.parse(l, false, attrs));
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

	/**
	*/
	public override Statement fold()
	{
		def = def.fold();
		return this;
	}
}

/**
Represents local and global variable declarations.
*/
class VarDecl : DeclStatement
{
	/**
	The list of names to be declared.  This will always have at least one name.
	*/
	public Identifier[] names;
	
	/**
	The initializer for the variables.  This can be null, in which case the variables
	will be initialized to null.  If this is non-null and there is more than one name,
	this must be a multi-return expression, such as a function call, vararg etc.
	*/
	public Expression initializer;

	/**
	The protection parameter must be either Protection.Local or Protection.Global.
	*/
	public this(Location location, Location endLocation, Protection protection, Identifier[] names, Expression initializer)
	{
		super(location, endLocation, AstTag.VarDecl, protection);
		this.names = names;
		this.initializer = initializer;
	}

	/**
	Parse a local or global variable declaration.
	*/
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

	/**
	*/
	public override VarDecl fold()
	{
		if(initializer)
			initializer = initializer.fold();
	
		return this;
	}
}

/**
This node represents a function declaration.  Note that there are some places in the
grammar which look like function declarations (like inside objects and namespaces) but
which actually are just syntactic sugar.  This is for actual declarations.
*/
class FuncDecl : DeclStatement
{
	/**
	The "guts" of the function declaration.
	*/
	public FuncDef def;

	/**
	The protection parameter can be any kind of protection.
	*/
	public this(Location location, Protection protection, FuncDef def)
	{
		super(location, def.endLocation, AstTag.FuncDecl, protection);

		this.def = def;
	}

	/**
	Parse a function declaration, optional protection included.
	
	Params:
		l = The lexer to use.
		attrs = An optional attribute table to attach to the function.
	*/
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

	/**
	*/
	public override Statement fold()
	{
		def = def.fold();
		return this;
	}
}

/**
This node represents a namespace declaration.
*/
class NamespaceDecl : DeclStatement
{
	/**
	The "guts" of the namespace.
	*/
	public NamespaceDef def;

	/**
	The protection parameter can be any level of protection.
	*/
	public this(Location location, Protection protection, NamespaceDef def)
	{
		super(location, def.endLocation, AstTag.NamespaceDecl, protection);

		this.def = def;
	}

	/**
	Parse a namespace declaration, optional protection included.
	
	Params:
		l = The lexer to use.
		attrs = An optional attribute table to attach to the namespace.
	*/
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

	/**
	*/
	public override Statement fold()
	{
		def = def.fold();
		return this;
	}
}

/**
This node represents a block statement (i.e. one surrounded by curly braces).
*/
class CompoundStatement : Statement
{
	/**
	The list of statements contained in the braces.
	*/
	public Statement[] statements;

	/**
	*/
	public this(Location location, Location endLocation, Statement[] statements)
	{
		super(location, endLocation, AstTag.BlockStmt);
		this.statements = statements;
	}

	/**
	*/
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

	/**
	*/
	public override CompoundStatement fold()
	{
		foreach(ref statement; statements)
			statement = statement.fold();

		return this;
	}
}

/**
This node represents an if statement.
*/
class IfStatement : Statement
{
	/**
	An optional variable to declare inside the statement's condition which will take on
	the value of the condition.  In the code "if(local x = y < z){}", this corresponds
	to "x".  This member may be null, in which case there is no variable there.
	*/
	public Identifier condVar;
	
	/**
	The condition to test.
	*/
	public Expression condition;
	
	/**
	The code to execute if the condition evaluates to true.
	*/
	public Statement ifBody;

	/**
	If there is an else clause, this is the code to execute if the condition evaluates to
	false.  If there is no else clause, this member is null.
	*/
	public Statement elseBody;

	/**
	*/
	public this(Location location, Location endLocation, Identifier condVar, Expression condition, Statement ifBody, Statement elseBody)
	{
		super(location, endLocation, AstTag.IfStmt);

		this.condVar = condVar;
		this.condition = condition;
		this.ifBody = ifBody;
		this.elseBody = elseBody;
	}

	/**
	*/
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

	/**
	*/
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

/**
This node represents a while loop.
*/
class WhileStatement : Statement
{
	/**
	An optional variable to declare inside the statement's condition which will take on
	the value of the condition.  In the code "while(local x = y < z){}", this corresponds
	to "x".  This member may be null, in which case there is no variable there.
	*/
	public Identifier condVar;
	
	/**
	The condition to test.
	*/
	public Expression condition;
	
	/**
	The code inside the loop.
	*/
	public Statement code;

	/**
	*/
	public this(Location location, Identifier condVar, Expression condition, Statement code)
	{
		super(location, code.endLocation, AstTag.WhileStmt);

		this.condVar = condVar;
		this.condition = condition;
		this.code = code;
	}

	/**
	*/
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

	/**
	*/
	public override Statement fold()
	{
		condition = condition.fold();
		code = code.fold();

		if(condition.isConstant && !condition.isTrue)
			return new CompoundStatement(location, endLocation, null);

		return this;
	}
}

/**
This node corresponds to a do-while loop.
*/
class DoWhileStatement : Statement
{
	/**
	The code inside the loop.
	*/
	public Statement code;
	
	/**
	The condition to test at the end of the loop.
	*/
	public Expression condition;

	/**
	*/
	public this(Location location, Location endLocation, Statement code, Expression condition)
	{
		super(location, endLocation, AstTag.DoWhileStmt);

		this.code = code;
		this.condition = condition;
	}

	/**
	*/
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

	/**
	*/
	public override Statement fold()
	{
		code = code.fold();
		condition = condition.fold();

		if(condition.isConstant && !condition.isTrue)
			return code;

		return this;
	}
}

/**
This node represents a C-style for loop.
*/
class ForStatement : Statement
{
	/**
	There are two types of initializers possible in the first clause of the for loop header:
	variable declarations and expression statements.  This struct holds one or the other.
	*/
	struct ForInitializer
	{
		/**
		If true, the 'decl' member should be used; else, the 'init' member should be used.
		*/
		bool isDecl = false;

		union
		{
			/**
			If isDecl is false, this holds an expression to be evaluated at the beginning
			of the loop.
			*/
			Expression init;

			/**
			If isDecl is true, this holds a variable declaration to be performed at the
			beginning of the loop.
			*/
			VarDecl decl;
		}
	}

	/**
	A list of 0 or more initializers (the first clause of the foreach header).
	*/
	public ForInitializer[] init;
	
	/**
	The condition to test at the beginning of each iteration of the loop.  This can be
	null, in which case the only way to get out of the loop is to break, return, or
	throw an exception.
	*/
	public Expression condition;
	
	/**
	A list of 0 or more increment expression statements to be evaluated at the end of
	each iteration of the loop.
	*/
	public Expression[] increment;
	
	/**
	The code inside the loop.
	*/
	public Statement code;

	/**
	*/
	public this(Location location, ForInitializer[] init, Expression cond, Expression[] inc, Statement code)
	{
		super(location, endLocation, AstTag.ForStmt);

		this.init = init;
		this.condition = cond;
		this.increment = inc;
		this.code = code;
	}

	/**
	This function will actually parse both C-style and numeric for loops.  The return value
	can be either one.
	*/
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
		else if(l.type == Token.Type.Ident && (l.peek.type == Token.Type.Colon || l.peek.type == Token.Type.Semicolon))
		{
			auto index = Identifier.parse(l);

			l.next();

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

	/**
	*/
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

/**
This node represents a numeric for loop, i.e. "for(i: 0 .. 10){}".
*/
class NumericForStatement : Statement
{
	/**
	The name of the index variable.
	*/
	public Identifier index;
	
	/**
	The lower bound of the loop (the value before the "..").  If constant, it must be an
	int.
	*/
	public Expression lo;

	/**
	The upper bound of the loop (the value after the "..").  If constant, it must be an
	int.
	*/
	public Expression hi;

	/**
	The step value of the loop.  If specified, this is the value after the comma after the
	upper bound.  If not specified, this is given an IntExp of value 1.  This member is
	never null.  If constant, it must be an int.
	*/
	public Expression step;
	
	/**
	The code inside the loop.
	*/
	public Statement code;

	/**
	*/
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
	
	/**
	*/
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

/**
This node represents a foreach loop.
*/
class ForeachStatement : Statement
{
	/**
	The list of index names (the names before the semicolon).  This list is always at least
	two elements long.  This is because when you write a foreach loop with only one index,
	an implicit dummy index is inserted before it.
	*/
	public Identifier[] indices;
	
	/**
	The container (the stuff after the semicolon).  This array can be 1, 2, or 3 elements
	long.  Semantically, the first element is the "iterator", the second the "state", and
	the third the "index".  However MiniD will automatically call opApply on the "iterator"
	if it's not a function, so this can function like a foreach loop in D.
	*/
	public Expression[] container;
	
	/**
	The code inside the loop.
	*/
	public Statement code;

	/**
	*/
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

	/**
	*/
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

	/**
	*/
	public override Statement fold()
	{
		foreach(ref c; container)
			c = c.fold();

		code = code.fold();
		return this;
	}
}

/**
This node represents a switch statement.
*/
class SwitchStatement : Statement
{
	/**
	The value to switch on.
	*/
	public Expression condition;
	
	/**
	A list of cases.  This is always at least one element long.
	*/
	public CaseStatement[] cases;
	
	/**
	An optional default case.  This member can be null.
	*/
	public DefaultStatement caseDefault;

	/**
	*/
	public this(Location location, Location endLocation, Expression condition, CaseStatement[] cases, DefaultStatement caseDefault)
	{
		super(location, endLocation, AstTag.SwitchStmt);
		this.condition = condition;
		this.cases = cases;
		this.caseDefault = caseDefault;
	}

	/**
	*/
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

	/**
	*/
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

/**
This node represents a single case statement within a switch statement.
*/
class CaseStatement : Statement
{
	/**
	The list of values which will cause execution to jump to this case.  In the code
	"case 1, 2, 3:" this corresponds to "1, 2, 3".  This will always be at least one element
	long.
	*/
	public Expression[] conditions;
	
	/**
	The code of the case statement.
	*/
	public Statement code;

	protected List!(InstRef*) mDynJumps;
	protected List!(int*) mConstJumps;

	/**
	*/
	public this(Location location, Location endLocation, Expression[] conditions, Statement code)
	{
		super(location, endLocation, AstTag.CaseStmt);
		this.conditions = conditions;
		this.code = code;
	}

	/**
	*/
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
	
	private void addDynJump(InstRef* i)
	{
		mDynJumps.add(i);
	}

	private void addConstJump(int* i)
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

	/**
	*/
	public override CaseStatement fold()
	{
		foreach(ref cond; conditions)
			cond = cond.fold();

		code = code.fold();
		return this;
	}
}

/**
This node represents the default case in a switch statement.
*/
class DefaultStatement : Statement
{
	/**
	The code of the statement.
	*/
	public Statement code;

	/**
	*/
	public this(Location location, Location endLocation, Statement code)
	{
		super(location, endLocation, AstTag.DefaultStmt);
		this.code = code;
	}

	/**
	*/
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

	/**
	*/
	public override DefaultStatement fold()
	{
		code = code.fold();
		return this;
	}
}

/**
This node represents a continue statement.
*/
class ContinueStatement : Statement
{
	/**
	*/
	public this(Location location)
	{
		super(location, location, AstTag.ContinueStmt);
	}

	/**
	*/
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

	/**
	*/
	public override Statement fold()
	{
		return this;
	}
}

/**
This node represents a break statement.
*/
class BreakStatement : Statement
{
	/**
	*/
	public this(Location location)
	{
		super(location, location, AstTag.BreakStmt);
	}

	/**
	*/
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

	/**
	*/
	public override Statement fold()
	{
		return this;
	}
}

/**
This node represents a return statement.
*/
class ReturnStatement : Statement
{
	/**
	The list of expressions to return.  This array may have 0 or more elements.
	*/
	public Expression[] exprs;

	/**
	*/
	public this(Location location, Location endLocation, Expression[] exprs)
	{
		super(location, endLocation, AstTag.ReturnStmt);
		this.exprs = exprs;
	}

	/**
	Construct a return statement from an expression.  This is used in functions which use
	the "lambda" syntax, i.e. "function f(x) = x * x".
	*/
	public this(Expression value)
	{
		super(value.location, value.endLocation, AstTag.ReturnStmt);
		exprs ~= value;
	}

	/**
	*/
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

			if(exprs.length == 1 && (cast(CallExp)exprs[0] || cast(MethodCallExp)exprs[0] || cast(SuperCallExp)exprs[0]))
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

	/**
	*/
	public override Statement fold()
	{
		foreach(ref exp; exprs)
			exp = exp.fold();

		return this;
	}
}

/**
This node represents a try-catch-finally statement.  It holds not only the try clause,
but either or both the catch and finally clauses.
*/
class TryCatchStatement : Statement
{
	/**
	The body of code to try.
	*/
	public Statement tryBody;
	
	/**
	The variable to use in the catch block.  In the code "try{}catch(e){}", this corresponds
	to 'e'.  This member can be null, in which case there is no catch block (and therefore
	there must be a finally block).  If this member is non-null, catchBody must also be
	non-null.
	*/
	public Identifier catchVar;

	/**
	The body of the catch block.  If this member is non-null, catchVar must also be non-null.
	If this member is null, finallyBody must be non-null.
	*/
	public Statement catchBody;

	/**
	The body of the finally block.  If this member is null, catchVar and catchBody must be
	non-null.
	*/
	public Statement finallyBody;

	/**
	*/
	public this(Location location, Location endLocation, Statement tryBody, Identifier catchVar, Statement catchBody, Statement finallyBody)
	{
		super(location, endLocation, AstTag.TryStmt);

		this.tryBody = tryBody;
		this.catchVar = catchVar;
		this.catchBody = catchBody;
		this.finallyBody = finallyBody;
	}

	/**
	*/
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
		{
			auto e = new MDCompileException(location, "Try statement must be followed by a catch, finally, or both");
			e.atEOF = true;
			throw e;
		}

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

	/**
	*/
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

/**
This node represents a throw statement.
*/
class ThrowStatement : Statement
{
	/**
	The value that should be thrown.
	*/
	public Expression exp;

	/**
	*/
	public this(Location location, Expression exp)
	{
		super(location, exp.endLocation, AstTag.ThrowStmt);
		this.exp = exp;
	}

	/**
	*/
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

	/**
	*/
	public override Statement fold()
	{
		exp = exp.fold();
		return this;
	}
}

/**
The base class for all expressions, including assignments.
*/
abstract class Expression : AstNode
{
	/**
	*/
	public this(Location location, Location endLocation, AstTag type)
	{
		super(location, endLocation, type);
	}

	/**
	Parse a non-assignment expression.  The returned expression is therefore guaranteed
	to give some kind of value.
	*/
	public static Expression parse(Lexer l)
	{
		return CondExp.parse(l);
	}

	/**
	Parse any expression which can be executed as a statement, i.e. any expression which
	can have side effects, including assignments, function calls, yields, ?:, &&, and ||
	expressions.  The parsed expression is checked for side effects before being returned.
	*/
	public static Expression parseStatement(Lexer l)
	{
		auto location = l.loc;
		Expression exp;

		if(l.type == Token.Type.Inc)
		{
			l.next();
			exp = PrimaryExp.parse(l);
			exp = new IncExp(location, location, exp);
		}
		else if(l.type == Token.Type.Dec)
		{
			l.next();
			exp = PrimaryExp.parse(l);
			exp = new DecExp(location, location, exp);
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
				exp = new IncExp(location, location, exp);
			}
			else if(l.type == Token.Type.Dec)
			{
				l.next();
				exp = new DecExp(location, location, exp);
			}
			else if(l.type == Token.Type.OrOr)
				exp = OrOrExp.parse(l, exp);
			else if(l.type == Token.Type.AndAnd)
				exp = AndAndExp.parse(l, exp);
			else if(l.type == Token.Type.Question)
				exp = CondExp.parse(l, exp);
		}

		exp.checkToNothing();

		return exp;
	}

	/**
	Parse a comma-separated list of expressions, such as for argument lists.
	*/
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

	/**
	Ensure that this expression can be evaluated to nothing, i.e. that it can exist
	on its own.  Throws an exception if not.
	*/
	public void checkToNothing()
	{
		if(!hasSideEffects())
		{
			auto e = new MDCompileException(location, "Expression cannot exist on its own");
			e.solitaryExpression = true;
			throw e;
		}
	}
	
	/**
	Returns whether or not this expression has side effects.  If this returns false,
	checkToNothing will throw an error.
	*/
	public bool hasSideEffects()
	{
		return false;
	}

	/**
	Ensure that this expression can give multiple return values.  If it can't, throws an
	exception.
	*/
	public void checkMultRet()
	{
		if(isMultRet() == false)
			throw new MDCompileException(location, "Expression cannot be the source of a multi-target assignment");
	}

	/**
	Returns whether this expression can give multiple return values.  If this returns
	false, checkMultRet will throw an error.
	*/
	public bool isMultRet()
	{
		return false;
	}
	
	/**
	Returns whether this expression is a constant value.
	*/
	public bool isConstant()
	{
		return false;
	}

	/**
	Returns whether this expression is 'null'.
	*/
	public bool isNull()
	{
		return false;
	}
	
	/**
	Returns whether this expression is a boolean constant.
	*/
	public bool isBool()
	{
		return false;
	}
	
	/**
	Returns this expression as a boolean constant, if possible.  assert(false)s
	otherwise.
	*/
	public bool asBool()
	{
		assert(false);
	}
	
	/**
	Returns whether this expression is an integer constant.
	*/
	public bool isInt()
	{
		return false;
	}
	
	/**
	Returns this expression as an integer constant, if possible.  assert(false)s
	otherwise.
	*/
	public int asInt()
	{
		assert(false);
	}

	/**
	Returns whether this expression is a floating point constant.
	*/
	public bool isFloat()
	{
		return false;
	}

	/**
	Returns this expression as a floating point constant, if possible.  assert(false)s
	otherwise.
	*/
	public mdfloat asFloat()
	{
		assert(false);
	}

	/**
	Returns whether this expression is a character constant.
	*/
	public bool isChar()
	{
		return false;
	}

	/**
	Returns this expression as a character constant, if possible.  assert(false)s
	otherwise.
	*/
	public dchar asChar()
	{
		assert(false);
	}

	/**
	Returns whether this expression is a string constant.
	*/
	public bool isString()
	{
		return false;
	}

	/**
	Returns this expression as a string constant, if possible.  assert(false)s
	otherwise.
	*/
	public dchar[] asString()
	{
		assert(false);
	}

	/**
	If this expression is a constant value, returns whether this expression would evaluate
	as true according to MiniD's definition of truth.  Otherwise returns false.
	*/
	public bool isTrue()
	{
		return false;
	}

	/**
	*/
	public Expression fold()
	{
		return this;
	}
}

/**
This node represents normal assignment, either single- or multi-target.
*/
class Assignment : Expression
{
	/**
	The list of destination expressions.  This list always has at least one element.
	This list will never contain 'this', '#vararg', or constant values.  These conditions
	will be checked at codegen time.
	*/
	public Expression[] lhs;
	public Expression rhs;

	/**
	*/
	public this(Location location, Location endLocation, Expression[] lhs, Expression rhs)
	{
		super(location, endLocation, AstTag.Assign);
		this.lhs = lhs;
		this.rhs = rhs;
	}

	/**
	Parse an assignment.
	
	Params:
		l = The lexer to use.
		firstLHS = Since you can't tell if you're on an assignment until you parse
		at least one item in the left-hand-side, this parameter should be the first
		item on the left-hand-side.  Therefore this function parses everything $(I but)
		the first item on the left-hand-side.
	*/
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

		return new Assignment(location, rhs.endLocation, lhs, rhs);
	}
	
	public override void codeGen(FuncState s)
	{
		foreach(exp; lhs)
		{
			if(cast(ThisExp)exp)
				throw new MDCompileException(exp.location, "'this' cannot be the target of an assignment");

			if(cast(VargLengthExp)exp)
				throw new MDCompileException(exp.location, "'#vararg' cannot be the target of an assignment");
				
			if(exp.isConstant)
				throw new MDCompileException(exp.location, "constant values cannot be the target of an assignment");
		}

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

	public override bool hasSideEffects()
	{
		return true;
	}

	/**
	*/
	public override Expression fold()
	{
		foreach(ref exp; lhs)
			exp = exp.fold();

		rhs = rhs.fold();
		return this;
	}
}

/**
This node represents most of the reflexive assignments, as well as conditional assignment (?=).
The only kind it doesn't represent is appending (~=), since it has to be handled specially.
*/
class OpEqExp : Expression
{
	/**
	The left-hand-side of the assignment.  This may not be a constant value or '#vararg', and if
	this is a conditional assignment, it may not be 'this'.  These conditions will be checked at
	codegen.
	*/
	public Expression lhs;
	
	/**
	The right-hand-side of the assignment.
	*/
	public Expression rhs;

	/**
	*/
	public this(Location location, Location endLocation, AstTag type, Expression lhs, Expression rhs)
	{
		super(location, endLocation, type);
		this.lhs = lhs;
		this.rhs = rhs;
	}
	
	/**
	Parse a reflexive assignment.
	
	Params:
		l = The lexer to use.
		exp1 = The left-hand-side of the assignment.  As with normal assignments, since
			you can't actually tell that something is an assignment until the LHS is
			at least parsed, this has to be passed as a parameter.
	*/
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
		if(lhs.isConstant)
			throw new MDCompileException(location, "constant values cannot be the target of an assignment");
			
		if(cast(VargLengthExp)lhs)
			throw new MDCompileException(location, "'#vararg' cannot be the target of an assignment");
			
		if(type == AstTag.CondAssign && cast(ThisExp)lhs)
			throw new MDCompileException(location, "'this' cannot be the target of a conditional assignment");

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

	public override bool hasSideEffects()
	{
		return true;
	}

	/**
	*/
	public override Expression fold()
	{
		lhs = lhs.fold();
		rhs = rhs.fold();

		return this;
	}
}

/**
This node represents concatenation assignment, or appending (the ~= operator).
*/
class CatEqExp : Expression
{
	/**
	The left-hand-side of the assignment.  The same constraints apply here as for other
	reflexive assignments.
	*/
	public Expression lhs;
	
	/**
	The right-hand-side of the assignment.
	*/
	public Expression rhs;

	private Expression[] operands;
	private bool collapsed = false;

	/**
	*/
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
		
		if(lhs.isConstant)
			throw new MDCompileException(location, "constant values cannot be the target of an assignment");
			
		if(cast(VargLengthExp)lhs)
			throw new MDCompileException(location, "'#vararg' cannot be the target of an assignment");

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

	/**
	*/
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

	public override bool hasSideEffects()
	{
		return true;
	}
}

/**
This node represents an increment, either prefix or postfix (++a or a++).
*/
class IncExp : Expression
{
	/**
	The expression to modify.  The same constraints apply as for reflexive assignments.
	*/
	public Expression exp;

	/**
	*/
	public this(Location location, Location endLocation, Expression exp)
	{
		super(location, endLocation, AstTag.IncExp);
		this.exp = exp;
	}

	public override void codeGen(FuncState s)
	{
		if(exp.isConstant)
			throw new MDCompileException(location, "constant values cannot be the target of an assignment");

		if(cast(VargLengthExp)exp)
			throw new MDCompileException(location, "'#vararg' cannot be the target of an assignment");

		exp.codeGen(s);
		s.pushSource(exp.endLocation.line);

		Exp src;
		s.popSource(exp.endLocation.line, src);
		s.freeExpTempRegs(&src);

		s.popReflexOp(endLocation.line, AstTagToOpcode(type), src.index, 0);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(location, "'++' cannot be used as a condition");
	}

	public override bool hasSideEffects()
	{
		return true;
	}

	/**
	*/
	public override Expression fold()
	{
		exp = exp.fold();
		return this;
	}
}

/**
This node represents a decrement, either prefix or postfix (--a or a--).
*/
class DecExp : Expression
{
	/**
	The expression to modify.  The same constraints apply as for reflexive assignments.
	*/
	public Expression exp;
	
	/**
	*/
	public this(Location location, Location endLocation, Expression exp)
	{
		super(location, endLocation, AstTag.DecExp);
		this.exp = exp;
	}

	public override void codeGen(FuncState s)
	{
		if(exp.isConstant)
			throw new MDCompileException(location, "constant values cannot be the target of an assignment");

		if(cast(VargLengthExp)exp)
			throw new MDCompileException(location, "'#vararg' cannot be the target of an assignment");

		exp.codeGen(s);
		s.pushSource(exp.endLocation.line);

		Exp src;
		s.popSource(exp.endLocation.line, src);
		s.freeExpTempRegs(&src);

		s.popReflexOp(endLocation.line, AstTagToOpcode(type), src.index, 0);
	}

	public override InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(location, "'--' cannot be used as a condition");
	}

	public override bool hasSideEffects()
	{
		return true;
	}

	/**
	*/
	public override Expression fold()
	{
		exp = exp.fold();
		return this;
	}
}

/**
This node represents a conditional (?:) expression.
*/
class CondExp : Expression
{
	/**
	The first expression, which comes before the question mark.
	*/
	public Expression cond;
	
	/**
	The second expression, which comes between the question mark and the colon.
	*/
	public Expression op1;
	
	/**
	The third expression, which comes after the colon.
	*/
	public Expression op2;

	/**
	*/
	public this(Location location, Location endLocation, Expression cond, Expression op1, Expression op2)
	{
		super(location, endLocation, AstTag.CondExp);
		this.cond = cond;
		this.op1 = op1;
		this.op2 = op2;
	}

	/**
	Parse a conditional expression.
	
	Params:
		l = The lexer to use.
		exp1 = Conditional expressions can occur as statements, in which case the first
			expression must be parsed in order to see what kind of expression it is.
			In this case, the first expression is passed in as a parameter.  Otherwise,
			it defaults to null and this function parses the first expression itself.
	*/
	public static Expression parse(Lexer l, Expression exp1 = null)
	{
		auto location = l.loc;

		Expression exp2;
		Expression exp3;

		if(exp1 is null)
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

	public override bool hasSideEffects()
	{
		return cond.hasSideEffects() || op1.hasSideEffects() || op2.hasSideEffects();
	}
	
	/**
	*/
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

/**
The base class for binary expressions.  Many of them share some or all of their code
generation phases, as well has having other similar properties, such as having two
operands.
*/
abstract class BinaryExp : Expression
{
	/**
	The left-hand operand.
	*/
	public Expression op1;
	
	/**
	The right-hand operand.
	*/
	public Expression op2;

	/**
	*/
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

/**
This node represents a logical or (||) expression.
*/
class OrOrExp : BinaryExp
{
	/**
	*/
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.OrOrExp, left, right);
	}

	/**
	Parse a logical or expression.

	Params:
		l = The lexer to use.
		exp1 = Or-or expressions can occur as statements, in which case the first
			expression must be parsed in order to see what kind of expression it is.
			In this case, the first expression is passed in as a parameter.  Otherwise,
			it defaults to null and this function parses the first expression itself.
	*/
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

	public override bool hasSideEffects()
	{
		return op1.hasSideEffects() || op2.hasSideEffects();
	}
	
	/**
	*/
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

/**
This node represents a logical or (||) expression.
*/
class AndAndExp : BinaryExp
{
	/**
	*/
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.AndAndExp, left, right);
	}

	/**
	Parse a logical and expression.

	Params:
		l = The lexer to use.
		exp1 = And-and expressions can occur as statements, in which case the first
			expression must be parsed in order to see what kind of expression it is.
			In this case, the first expression is passed in as a parameter.  Otherwise,
			it defaults to null and this function parses the first expression itself.
	*/
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

	public override bool hasSideEffects()
	{
		return op1.hasSideEffects() || op2.hasSideEffects();
	}

	/**
	*/
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

/**
This node represents a bitwise or expression.
*/
class OrExp : BinaryExp
{
	/**
	*/
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.OrExp, left, right);
	}

	/**
	*/
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
	
	/**
	*/
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

/**
This node represents a bitwise xor expression.
*/
class XorExp : BinaryExp
{
	/**
	*/
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.XorExp, left, right);
	}

	/**
	*/
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
	
	/**
	*/
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

/**
This node represents a bitwise and expression.
*/
class AndExp : BinaryExp
{
	/**
	*/
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.AndExp, left, right);
	}

	/**
	*/
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
	
	/**
	*/
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

/**
This node represents equality and identity expressions (==, !=, is, !is).
*/
class EqualExp : BinaryExp
{
	/**
	*/
	public this(Location location, Location endLocation, AstTag type, Expression left, Expression right)
	{
		super(location, endLocation, type, left, right);
	}

	/**
	*/
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

	/**
	*/
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

/**
This node represents the four kinds of comparison (<, <=, >, >=).
*/
class CmpExp : BinaryExp
{
	/**
	*/
	public this(Location location, Location endLocation, AstTag type, Expression op1, Expression op2)
	{
		super(location, endLocation, type, op1, op2);
	}

	/**
	Parse a comparison expression.  This actually not only parses the four kinds of
	comparison, but also in, !in, as, and three-way comparison (<=>) expressions.
	*/
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

	/**
	*/
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
				case AstTag.LTExp: return new BoolExp(location, cmpVal < 0);
				case AstTag.LEExp: return new BoolExp(location, cmpVal <= 0);
				case AstTag.GTExp: return new BoolExp(location, cmpVal > 0);
				case AstTag.GEExp: return new BoolExp(location, cmpVal >= 0);
				default: assert(false, "CmpExp fold");
			}
		}

		return this;
	}
}

/**
This node represents an 'as' expression.
*/
class AsExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		if(left.isConstant() || right.isConstant())
			throw new MDCompileException(location, "Neither argument of an 'as' expression may be a constant");
			
		super(location, endLocation, AstTag.AsExp, left, right);
	}
}

/**
This node represents an 'in' expression.
*/
class InExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.InExp, left, right);
	}
}

/**
This node represents a '!in' expression.
*/
class NotInExp : BinaryExp
{
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.NotInExp, left, right);
	}
}

/**
This node represents a three-way comparison (<=>) expression.
*/
class Cmp3Exp : BinaryExp
{
	/**
	*/
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.Cmp3Exp, left, right);
	}

	/**
	*/
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

/**
This node represents bitwise shift expressions (<<, >>, >>>).
*/
class ShiftExp : BinaryExp
{
	/**
	*/
	public this(Location location, Location endLocation, AstTag type, Expression left, Expression right)
	{
		super(location, endLocation, type, left, right);
	}

	/**
	*/
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

	/**
	*/
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

/**
This node represents addition and subtraction expressions (+, -).
*/
class AddExp : BinaryExp
{
	/**
	*/
	public this(Location location, Location endLocation, AstTag type, Expression left, Expression right)
	{
		super(location, endLocation, type, left, right);
	}

	/**
	This function parses not only addition and subtraction expressions, but also
	concatenation expressions.
	*/
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
	
	/**
	*/
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

/**
This node represents concatenation (~) expressions.
*/
class CatExp : BinaryExp
{
	private Expression[] operands;
	private bool collapsed = false;

	/**
	*/
	public this(Location location, Location endLocation, Expression left, Expression right)
	{
		super(location, endLocation, AstTag.CatExp, left, right);
	}

	/**
	*/
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

	/**
	*/
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

/**
This node represents multiplication, division, and modulo expressions (*, /, %).
*/
class MulExp : BinaryExp
{
	/**
	*/
	public this(Location location, Location endLocation, AstTag type, Expression left, Expression right)
	{
		super(location, endLocation, type, left, right);
	}

	/**
	*/
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

	/**
	*/
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

/**
This class is the base class for unary expressions.  These tend to share some code
generation, as well as all having a single operand.
*/
abstract class UnaryExp : Expression
{
	/**
	The operand of the expression.
	*/
	protected Expression op;

	/**
	*/
	public this(Location location, Location endLocation, AstTag type, Expression operand)
	{
		super(location, endLocation, type);
		op = operand;
	}

	/**
	Parse a unary expression.  This parses negation (-), not (!), complement (~),
	length (#), and coroutine expressions.  '#vararg' is also incidentally parsed.
	*/
	public static Expression parse(Lexer l)
	{
		auto location = l.loc;

		Expression exp;

		switch(l.type)
		{
			case Token.Type.Sub:
				l.next();
				exp = UnaryExp.parse(l);
				exp = new NegExp(location, exp);
				break;

			case Token.Type.Not:
				l.next();
				exp = UnaryExp.parse(l);
				exp = new NotExp(location, exp);
				break;

			case Token.Type.Cat:
				l.next();
				exp = UnaryExp.parse(l);
				exp = new ComExp(location, exp);
				break;

			case Token.Type.Length:
				l.next();
				exp = UnaryExp.parse(l);

				if(cast(VarargExp)exp)
					exp = new VargLengthExp(location, exp.endLocation);
				else
					exp = new LengthExp(location, exp);
				break;

			case Token.Type.Coroutine:
				l.next();
				exp = UnaryExp.parse(l);
				exp = new CoroutineExp(exp.endLocation, exp);
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

/**
This node represents a negation (-a).
*/
class NegExp : UnaryExp
{
	/**
	*/
	public this(Location location, Expression operand)
	{
		super(location, operand.endLocation, AstTag.NegExp, operand);
	}

	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.popUnOp(endLocation.line, Op.Neg);
	}

	/**
	*/
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

/**
This node represents a logical not expression (!a).
*/
class NotExp : UnaryExp
{
	/**
	*/
	public this(Location location, Expression operand)
	{
		super(location, operand.endLocation, AstTag.NotExp, operand);
	}

	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.popUnOp(endLocation.line, Op.Not);
	}

	/**
	*/
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

/**
This node represents a bitwise complement expression (~a).
*/
class ComExp : UnaryExp
{
	/**
	*/
	public this(Location location, Expression operand)
	{
		super(location, operand.endLocation, AstTag.ComExp, operand);
	}
	
	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.popUnOp(endLocation.line, Op.Com);
	}

	/**
	*/
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

/**
This node represents a length expression (#a).
*/
class LengthExp : UnaryExp
{
	/**
	*/
	public this(Location location, Expression operand)
	{
		super(location, operand.endLocation, AstTag.LenExp, operand);
	}

	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.popLength(endLocation.line);
	}

	/**
	*/
	public override Expression fold()
	{
		op = op.fold();

		if(op.isConstant)
		{
			if(op.isString)
				return new IntExp(location, op.asString().length);

			throw new MDCompileException(location, "Length must be performed on a string at compile time");
		}

		return this;
	}
}

/**
This node represents the variadic-length expression (#vararg).
*/
class VargLengthExp : UnaryExp
{
	/**
	*/
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

	/**
	*/
	public override Expression fold()
	{
		return this;
	}
}

/**
This node represents the coroutine expression (coroutine a).
*/
class CoroutineExp : UnaryExp
{
	/**
	*/
	public this(Location location, Expression operand)
	{
		super(location, operand.endLocation, AstTag.CoroutineExp, operand);
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

/**
This class is the base class for postfix expressions, that is expressions which kind of
attach to the end of other expressions.  It inherits from UnaryExp, so that the single
operand becomes the expression to which the postfix expression becomes attached.
*/
abstract class PostfixExp : UnaryExp
{
	/**
	*/
	public this(Location location, Location endLocation, AstTag type, Expression operand)
	{
		super(location, endLocation, type, operand);
	}

	/**
	Parse a postfix expression.  This includes dot expressions (.ident, .super, and .(expr)),
	function calls, indexing, slicing, and vararg slicing.
	
	Params:
		l = The lexer to use.
		exp = The expression to which the resulting postfix expression will be attached.
	*/
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
						exp = new DotExp(exp, new StringExp(ie.location, ie.name.name));
					}
					else if(l.type == Token.Type.Super)
					{
						auto endLocation = l.loc;
						l.next();
						exp = new DotSuperExp(endLocation, exp);
					}
					else
					{
						l.expect(Token.Type.LParen);
						auto subExp = Expression.parse(l);
						l.expect(Token.Type.RParen);
						exp = new DotExp(exp, subExp);
					}
					continue;

				case Token.Type.LParen:
					if(exp.endLocation.line != l.loc.line)
						throw new MDCompileException(l.loc, "ambiguous left-paren (chained call or beginning of new statement?)");

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
					
					if(cast(DotExp)exp)
						exp = new MethodCallExp(endLocation, exp, context, args);
					else
						exp = new CallExp(endLocation, exp, context, args);

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
							exp = new SliceExp(endLocation, exp, loIndex, hiIndex);
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
							exp = new SliceExp(endLocation, exp, loIndex, hiIndex);
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
								exp = new SliceExp(endLocation, exp, loIndex, hiIndex);
						}
						else
						{
							// a[0]
							l.tok.expect(Token.Type.RBracket);
							endLocation = l.loc;
							l.next();
							
							if(cast(VarargExp)exp)
								exp = new VargIndexExp(location, endLocation, loIndex);
							else
								exp = new IndexExp(endLocation, exp, loIndex);
						}
					}
					continue;

				default:
					return exp;
			}
		}
	}
}

/**
This node represents dot expressions, in both the dot-ident (a.x) and dot-expression
(a.(expr)) forms.  These correspond to field access.
*/
class DotExp : PostfixExp
{
	/**
	The name.  This can be any expression, as long as it evaluates to a string.  An
	expression like "a.x" is sugar for "a.("x")", so this will be a string literal
	in that case.
	*/
	public Expression name;

	/**
	*/
	public this(Expression operand, Expression name)
	{
		super(operand.location, name.endLocation, AstTag.DotExp, operand);
		this.name = name;
	}

	/**
	Parse a member exp (:a).  This is a shorthand expression for "this.a".  This
	also works with super (:super) and paren (:("a")) versions.
	*/
	public static Expression parseMemberExp(Lexer l)
	{
		auto loc = l.expect(Token.Type.Colon).location;
		Location endLoc;
		Expression exp;

		if(l.type == Token.Type.LParen)
		{
			l.next();
			exp = Expression.parse(l);
			endLoc = l.expect(Token.Type.RParen).location;
			exp = new DotExp(new ThisExp(loc), exp);
		}
		else if(l.type == Token.Type.Super)
		{
			endLoc = l.loc;
			l.next();
			exp = new DotSuperExp(endLoc, new ThisExp(loc));
		}
		else
		{
			endLoc = l.loc;
			auto name = Identifier.parseName(l);
			exp = new DotExp(new ThisExp(loc), new StringExp(endLoc, name));
		}
		
		return exp;
	}

	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.topToSource(endLocation.line);
		name.codeGen(s);
		s.popField(endLocation.line);
	}

	/**
	*/
	public override Expression fold()
	{
		op = op.fold();
		name = name.fold();
		
		if(name.isConstant && !name.isString)
			throw new MDCompileException(name.location, "Field name must be a string");

		return this;
	}
}

/**
This node corresponds to the super expression (a.super).
*/
class DotSuperExp : PostfixExp
{
	/**
	*/
	public this(Location endLocation, Expression operand)
	{
		super(operand.location, endLocation, AstTag.DotSuperExp, operand);
	}

	public override void codeGen(FuncState s)
	{
		op.codeGen(s);
		s.popUnOp(endLocation.line, Op.SuperOf);
	}

	/**
	*/
	public override Expression fold()
	{
		op = op.fold();
		return this;
	}
}

/**
This class corresponds to a method call in either form (a.f() or a.("f")()).
*/
class MethodCallExp : PostfixExp
{
	/**
	The context to be used when calling the method.  This corresponds to 'x' in
	the expression "a.f(with x)".  If this member is null, there is no custom
	context and the context will be determined automatically.
	*/
	public Expression context;
	
	/**
	The list of argument to pass to the method.  This can have 0 or more elements.
	*/
	public Expression[] args;

	/**
	*/
	public this(Location endLocation, Expression operand, Expression context, Expression[] args)
	{
		super(operand.location, endLocation, AstTag.MethodCallExp, operand);
		this.context = context;
		this.args = args;
	}
	
	public override void codeGen(FuncState s)
	{
		codeGen(s, false);
	}

	public void codeGen(FuncState s, bool isSuperCall = false)
	{
		auto dotExp = cast(DotExp)op;

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

		Op opcode;
		
		if(context is null)
			opcode = isSuperCall ? Op.SuperMethod : Op.Method;
		else
			opcode = Op.MethodNC;

		s.codeR(op.endLocation.line, opcode, funcReg, src.index, meth.index);
		s.popRegister(thisReg);

		if(args.length == 0)
			s.pushCall(endLocation.line, funcReg, 2);
		else if(args[$ - 1].isMultRet())
			s.pushCall(endLocation.line, funcReg, 0);
		else
			s.pushCall(endLocation.line, funcReg, args.length + 2);
	}

	public override bool hasSideEffects()
	{
		return true;
	}

	public override bool isMultRet()
	{
		return true;
	}

	/**
	*/
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

/**
This node corresponds to a non-method function call (f()).
*/
class CallExp : PostfixExp
{
	/**
	The context to be used when calling the function.  This corresponds to 'x' in
	the expression "f(with x)".  If this member is null, there is no custom
	context and the context will be determined automatically.
	*/
	public Expression context;
	
	/**
	The list of arguments to be passed to the function.  This can be 0 or more elements.
	*/
	public Expression[] args;

	/**
	*/
	public this(Location endLocation, Expression operand, Expression context, Expression[] args)
	{
		super(operand.location, endLocation, AstTag.CallExp, operand);
		this.context = context;
		this.args = args;
	}

	public override void codeGen(FuncState s)
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

	public override bool hasSideEffects()
	{
		return true;
	}

	public override bool isMultRet()
	{
		return true;
	}

	/**
	*/
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

/**
This node corresponds to an indexing operation (a[x]).
*/
class IndexExp : PostfixExp
{
	/**
	The index of the operation (the value inside the brackets).
	*/
	public Expression index;

	/**
	*/
	public this(Location endLocation, Expression operand, Expression index)
	{
		super(operand.location, endLocation, AstTag.IndexExp, operand);
		this.index = index;
	}

	public override void codeGen(FuncState s)
	{
		op.codeGen(s);

		s.topToSource(endLocation.line);

		index.codeGen(s);
		s.popIndex(endLocation.line);
	}

	/**
	*/
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

/**
This node corresponds to a variadic indexing operation (vararg[x]).
*/
class VargIndexExp : PostfixExp
{
	/**
	The index of the operation (the value inside the brackets).
	*/
	public Expression index;

	/**
	*/
	public this(Location location, Location endLocation, Expression index)
	{
		super(location, endLocation, AstTag.VargIndexExp, null);
		this.index = index;
	}

	public override void codeGen(FuncState s)
	{
		if(!s.mIsVararg)
			throw new MDCompileException(location, "'vararg' cannot be used in a non-variadic function");

		index.codeGen(s);
		s.popVargIndex(endLocation.line);
	}

	/**
	*/
	public override Expression fold()
	{
		index = index.fold();

		if(index.isConstant && !index.isInt)
			throw new MDCompileException(index.location, "index of a vararg indexing must be an integer");

		return this;
	}
}

/**
This node corresponds to a slicing operation (a[x .. y]).
*/
class SliceExp : PostfixExp
{
	/**
	The low index of the slice.  If no low index is given, this will be a NullExp.
	This member will therefore never be null.
	*/
	public Expression loIndex;
	
	/**
	The high index of the slice.  If no high index is given, this will be a NullExp.
	This member will therefore never be null.
	*/
	public Expression hiIndex;

	/**
	*/
	public this(Location endLocation, Expression operand, Expression loIndex, Expression hiIndex)
	{
		super(operand.location, endLocation, AstTag.SliceExp, operand);
		this.loIndex = loIndex;
		this.hiIndex = hiIndex;
	}
	
	public override void codeGen(FuncState s)
	{
		uint reg = s.nextRegister();
		Expression.codeGenListToNextReg(s, [op, loIndex, hiIndex]);

		s.pushSlice(endLocation.line, reg);
	}

	/**
	*/
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

/**
This node represents a variadic slice operation (vararg[x .. y]).
*/
class VargSliceExp : PostfixExp
{
	/**
	The low index of the slice.
	*/
	public Expression loIndex;
	
	/**
	The high index of the slice.
	*/
	public Expression hiIndex;

	/**
	*/
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

	/**
	*/
	public override Expression fold()
	{
		loIndex = loIndex.fold();
		hiIndex = hiIndex.fold();
		
		if(loIndex.isConstant && !(loIndex.isNull || loIndex.isInt))
			throw new MDCompileException(loIndex.location, "low index of vararg slice must be null or int");
			
		if(hiIndex.isConstant && !(hiIndex.isNull || hiIndex.isInt))
			throw new MDCompileException(hiIndex.location, "high index of vararg slice must be null or int");

		return this;
	}

	public override bool isMultRet()
	{
		return true;
	}
}

/**
The base class for primary expressions.  These are expressions which evaluate to a single
value, including constants and literals.
*/
class PrimaryExp : Expression
{
	/**
	*/
	public this(Location location, AstTag type)
	{
		super(location, location, type);
	}
	
	/**
	*/
	public this(Location location, Location endLocation, AstTag type)
	{
		super(location, endLocation, type);
	}

	/**
	Parse a primary expression.  Will also parse any postfix expressions attached
	to the primary exps.
	*/
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
			case Token.Type.Object:                 exp = ObjectLiteralExp.parse(l); break;
			case Token.Type.LParen:                 exp = ParenExp.parse(l); break;
			case Token.Type.LBrace:                 exp = TableCtorExp.parse(l); break;
			case Token.Type.LBracket:               exp = ArrayCtorExp.parse(l); break;
			case Token.Type.Namespace:              exp = NamespaceCtorExp.parse(l); break;
			case Token.Type.Yield:                  exp = YieldExp.parse(l); break;
			case Token.Type.Super:                  exp = SuperCallExp.parse(l); break;
			case Token.Type.Colon:                  exp = DotExp.parseMemberExp(l); break;
			default: l.tok.expected("Expression");
		}

		return PostfixExp.parse(l, exp);
	}

	/**
	Used for parsing JSON.
	*/
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

/**
An identifier expression.  These can refer to locals, upvalues, or globals.
*/
class IdentExp : PrimaryExp
{
	/**
	The identifier itself.
	*/
	public Identifier name;

	/**
	Create an ident exp from a location and name directly.
	*/
	public this(Location location, dchar[] name)
	{
		super(location, AstTag.IdentExp);
		this.name = new Identifier(location, name);
	}
	
	/**
	Create an ident exp from an identifier object.
	*/
	public this(Identifier i)
	{
		super(i.location, AstTag.IdentExp);
		this.name = i;
	}

	/**
	*/
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

/**
Represents the ubiquitous 'this' variable.
*/
class ThisExp : PrimaryExp
{
	/**
	*/
	public this(Location location)
	{
		super(location, AstTag.ThisExp);
	}

	/**
	*/
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

/**
Represents the 'null' literal.
*/
class NullExp : PrimaryExp
{
	/**
	*/
	public this(Location location)
	{
		super(location, AstTag.NullExp);
	}

	/**
	*/
	public static NullExp parse(Lexer l)
	{
		with(l.expect(Token.Type.Null))
			return new NullExp(location);
	}

	/**
	Used for parsing JSON.
	*/
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

/**
Represents either a 'true' or 'false' literal.
*/
class BoolExp : PrimaryExp
{
	/**
	The actual value of the literal.
	*/
	public bool value;

	/**
	*/
	public this(Location location, bool value)
	{
		super(location, AstTag.BoolExp);
		this.value = value;
	}

	/**
	*/
	public static BoolExp parse(Lexer l)
	{
		if(l.type == Token.Type.True)
			with(l.expect(Token.Type.True))
				return new BoolExp(location, true);
		else
			with(l.expect(Token.Type.False))
				return new BoolExp(location, false);
	}
	
	/**
	Used for parsing JSON.
	*/
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

/**
Represents the 'vararg' exp outside of a special form (i.e. not #vararg, vararg[x], or
vararg[x .. y]).
*/
class VarargExp : PrimaryExp
{
	/**
	*/
	public this(Location location)
	{
		super(location, AstTag.VarargExp);
	}

	/**
	*/
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

/**
Represents a character literal.
*/
class CharExp : PrimaryExp
{
	/**
	The actual character of the literal.
	*/
	public dchar value;

	/**
	*/
	public this(Location location, dchar value)
	{
		super(location, AstTag.CharExp);
		this.value = value;
	}

	/**
	*/
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

/**
Represents an integer literal.
*/
class IntExp : PrimaryExp
{
	/**
	The actual value of the literal.
	*/
	public int value;

	/**
	*/
	public this(Location location, int value)
	{
		super(location, AstTag.IntExp);
		this.value = value;
	}

	/**
	*/
	public static IntExp parse(Lexer l)
	{
		with(l.expect(Token.Type.IntLiteral))
			return new IntExp(location, intValue);
	}

	/**
	Used for parsing JSON.
	*/
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

/**
Represents a floating-point literal.
*/
class FloatExp : PrimaryExp
{
	/**
	The actual value of the literal.
	*/
	public mdfloat value;

	/**
	*/
	public this(Location location, mdfloat value)
	{
		super(location, AstTag.FloatExp);
		this.value = value;
	}

	/**
	*/
	public static FloatExp parse(Lexer l)
	{
		with(l.expect(Token.Type.FloatLiteral))
			return new FloatExp(location, floatValue);
	}

	/**
	Used for parsing JSON.
	*/
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

/**
Represents a string literal.
*/
class StringExp : PrimaryExp
{
	/**
	The actual value of the literal.
	*/
	public dchar[] value;

	/**
	*/
	public this(Location location, dchar[] value)
	{
		super(location, AstTag.StringExp);
		this.value = value;
	}

	/**
	*/
	public static StringExp parse(Lexer l)
	{
		with(l.expect(Token.Type.StringLiteral))
			return new StringExp(location, stringValue);
	}

	/**
	Used for parsing JSON.
	*/
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

/**
Represents a function literal.
*/
class FuncLiteralExp : PrimaryExp
{
	/**
	The actual "guts" of the function.
	*/
	public FuncDef def;

	/**
	*/
	public this(Location location, FuncDef def)
	{
		super(location, def.endLocation, AstTag.FuncLiteralExp);
		this.def = def;
	}

	/**
	*/
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

	/**
	*/
	public override FuncLiteralExp fold()
	{
		def = def.fold();
		return this;
	}
}

/**
Represents an object literal.
*/
class ObjectLiteralExp : PrimaryExp
{
	/**
	The actual "guts" of the object.
	*/
	public ObjectDef def;

	/**
	*/
	public this(Location location, ObjectDef def)
	{
		super(location, def.endLocation, AstTag.ObjectLiteralExp);
		this.def = def;
	}

	/**
	*/
	public static ObjectLiteralExp parse(Lexer l)
	{
		auto location = l.loc;
		return new ObjectLiteralExp(location, ObjectDef.parse(l, true));
	}

	public override void codeGen(FuncState s)
	{
		def.codeGen(s);
	}

	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(location, "Cannot use a class literal as a condition");
	}

	/**
	*/
	public override Expression fold()
	{
		def = def.fold();
		return this;
	}
}

/**
Represents an expression inside a pair of parentheses.  Besides controlling order-of-
operations, this expression will make a multiple-return-value expression return exactly
one result instead.  Thus 'vararg' can give 0 or more values but '(vararg)' gives
exactly one (null in the case that there are no varargs).
*/
class ParenExp : PrimaryExp
{
	/**
	The parenthesized expression.
	*/
	public Expression exp;

	/**
	*/
	public this(Location location, Location endLocation, Expression exp)
	{
		super(location, endLocation, AstTag.ParenExp);
		this.exp = exp;
	}

	/**
	Parse a parenthesized expression.  Actually, if the expression contained is
	not multi-return, you'll just get the expression instead (i.e. parsing "(4 + 5)"
	will get you an AddExp of 4 and 5).
	*/
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

	/**
	*/
	public override Expression fold()
	{
		exp = exp.fold();
		return this;
	}
}

/**
This is the base class for both numeric and generic for comprehensions inside array
and table comprehensions.
*/
abstract class ForComprehension : AstNode
{
	/**
	Optional if comprehension that follows this.  This member may be null.
	*/
	public IfComprehension ifComp;

	/**
	Optional for comprehension that follows this.  This member may be null.
	*/
	public ForComprehension forComp;

	/**
	*/
	public this(Location location, Location endLocation, AstTag tag)
	{
		super(location, endLocation, tag);
	}
	
	/**
	Parse a for comprehension.  Note that in the grammar, this actually includes an optional
	if comprehension and optional for comprehension after it, meaning that an entire array
	or table comprehension is parsed in one call.
	*/
	public static ForComprehension parse(Lexer l)
	{
		auto loc = l.expect(Token.Type.For).location;
		
		Identifier[] names;
		names ~= Identifier.parse(l);
		
		while(l.type == Token.Type.Comma)
		{
			l.next();
			names ~= Identifier.parse(l);
		}
		
		l.expect(Token.Type.In);
		
		auto exp = Expression.parse(l);
		
		if(l.type == Token.Type.DotDot)
		{
			if(names.length > 1)
				throw new MDCompileException(loc, "Numeric for comprehension may only have one index");
				
			l.next();
			auto exp2 = Expression.parse(l);
			
			Expression step;

			if(l.type == Token.Type.Comma)
			{
				l.next();
				step = Expression.parse(l);
			}
			
			IfComprehension ifComp;

			if(l.type == Token.Type.If)
				ifComp = IfComprehension.parse(l);
				
			ForComprehension forComp;
			
			if(l.type == Token.Type.For)
				forComp = ForComprehension.parse(l);

			return new ForNumComprehension(loc, names[0], exp, exp2, step, ifComp, forComp);
		}
		else
		{
			Expression[] container;
			container ~= exp;
			
			if(names.length == 1)
				names = ForeachStatement.dummyIndex(names[0].location) ~ names;

			while(l.type == Token.Type.Comma)
			{
				l.next();
				container ~= Expression.parse(l);
			}

			if(container.length > 3)
				throw new MDCompileException(container[0].location, "Too many expressions in container");

			IfComprehension ifComp;

			if(l.type == Token.Type.If)
				ifComp = IfComprehension.parse(l);

			ForComprehension forComp;

			if(l.type == Token.Type.For)
				forComp = ForComprehension.parse(l);

			return new ForeachComprehension(loc, names, container, ifComp, forComp);
		}
	}

	protected abstract Statement rewrite(Statement innerStmt);
	
	/**
	*/
	public abstract ForComprehension fold();
}

/**
This node represents a foreach comprehension in an array or table comprehension, i.e.
in the code "[x for x in a]", it represents "for x in a".
*/
class ForeachComprehension : ForComprehension
{
	/**
	These members are the same as for a ForeachStatement.
	*/
	public Identifier[] indices;
	
	/// ditto
	public Expression[] container;

	/**
	*/
	public this(Location location, Identifier[] indices, Expression[] container, IfComprehension ifComp, ForComprehension forComp)
	{
		if(ifComp)
		{
			if(forComp)
				super(location, forComp.endLocation, AstTag.ForeachComprehension);
			else
				super(location, ifComp.endLocation, AstTag.ForeachComprehension);
		}
		else if(forComp)
			super(location, forComp.endLocation, AstTag.ForeachComprehension);
		else
			super(location, container[$ - 1].endLocation, AstTag.ForeachComprehension);

		this.indices = indices;
		this.container = container;
		this.ifComp = ifComp;
		this.forComp = forComp;
	}

	protected override Statement rewrite(Statement innerStmt)
	{
		if(ifComp)
		{
			if(forComp)
				innerStmt = ifComp.rewrite(forComp.rewrite(innerStmt));
			else
				innerStmt = ifComp.rewrite(innerStmt);
		}
		else if(forComp)
			innerStmt = forComp.rewrite(innerStmt);

		return (new ForeachStatement(location, indices, container, innerStmt)).fold();
	}

	/**
	*/
	public override ForComprehension fold()
	{
		foreach(ref exp; container)
			exp = exp.fold();

		if(ifComp)
			ifComp = ifComp.fold();

		if(forComp)
			forComp = forComp.fold();

		return this;
	}
}

/**
This node represents a numeric for comprehension in an array or table comprehension, i.e.
in the code "[x for x in 0 .. 10]" this represents "for x in 0 .. 10".
*/
class ForNumComprehension : ForComprehension
{
	/**
	These members are the same as for a NumericForStatement.
	*/
	public Identifier index;
	
	/// ditto
	public Expression lo;
	
	/// ditto
	public Expression hi;
	
	/// ditto
	public Expression step;

	/**
	*/	
	public this(Location location, Identifier index, Expression lo, Expression hi, Expression step, IfComprehension ifComp, ForComprehension forComp)
	{
		if(ifComp)
		{
			if(forComp)
				super(location, forComp.endLocation, AstTag.ForNumComprehension);
			else
				super(location, ifComp.endLocation, AstTag.ForNumComprehension);
		}
		else if(forComp)
			super(location, forComp.endLocation, AstTag.ForNumComprehension);
		else if(step)
			super(location, step.endLocation, AstTag.ForNumComprehension);
		else
			super(location, hi.endLocation, AstTag.ForNumComprehension);

		this.index = index;
		this.lo = lo;
		this.hi = hi;
		
		if(step is null)
			this.step = new IntExp(location, 1);
		else
			this.step = step;

		this.ifComp = ifComp;
		this.forComp = forComp;
	}
	
	protected override Statement rewrite(Statement innerStmt)
	{
		if(ifComp)
		{
			if(forComp)
				innerStmt = ifComp.rewrite(forComp.rewrite(innerStmt));
			else
				innerStmt = ifComp.rewrite(innerStmt);
		}
		else if(forComp)
			innerStmt = forComp.rewrite(innerStmt);
			
		return (new NumericForStatement(location, index, lo, hi, step, innerStmt)).fold();
	}
	
	/**
	*/
	public override ForComprehension fold()
	{
		lo = lo.fold();
		hi = hi.fold();
		
		if(step)
			step = step.fold();
			
		if(ifComp)
			ifComp = ifComp.fold();

		if(forComp)
			forComp = forComp.fold();
			
		return this;
	}
}

/**
This node represents an if comprehension an an array or table comprehension, i.e.
in the code "[x for x in a if x < 10]", this represents "if x < 10".
*/
class IfComprehension : AstNode
{
	/**
	The condition to test.
	*/
	public Expression condition;

	/**
	*/
	public this(Location location, Expression condition)
	{
		super(location, condition.endLocation, AstTag.IfComprehension);
		
		this.condition = condition;
	}
	
	/**
	*/
	public static IfComprehension parse(Lexer l)
	{
		auto loc = l.expect(Token.Type.If).location;
		auto condition = Expression.parse(l);
		return new IfComprehension(loc, condition);
	}
	
	protected Statement rewrite(Statement innerStmt)
	{
		return (new IfStatement(location, endLocation, null, condition, innerStmt, null)).fold();
	}
	
	/**
	*/
	public IfComprehension fold()
	{
		condition = condition.fold();
		return this;
	}
}

/**
This node represents either a table literal or an attribute table.  Both are the
same thing, really.
*/
class TableCtorExp : PrimaryExp
{
	/**
	An array of fields.  The first value in each element is the key; the second the value.
	*/
	public Expression[2][] fields;

	/**
	*/
	public this(Location location, Location endLocation, Expression[2][] fields)
	{
		super(location, endLocation, AstTag.TableCtorExp);
		this.fields = fields;
	}

	private static Expression parseImpl(Lexer l, bool isAttr)
	{
		auto location = l.loc;
		Token.Type terminator;

		if(isAttr)
		{
			l.expect(Token.Type.LAttr);
			terminator = Token.Type.RAttr;
		}
		else
		{
			l.expect(Token.Type.LBrace);
			terminator = Token.Type.RBrace;
		}

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
			bool lastWasPlain = false;

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
						
						lastWasPlain = true;
						break;

					case Token.Type.Function:
						FuncDef fd = FuncDef.parseSimple(l);
						k = new StringExp(fd.location, fd.name.name);
						v = new FuncLiteralExp(fd.location, fd);
						lastWasPlain = false;
						break;

					default:
						Identifier id = Identifier.parse(l);
						l.expect(Token.Type.Assign);
						k = new StringExp(id.location, id.name);
						v = Expression.parse(l);
						lastWasPlain = false;
						break;
				}

				addPair(k, v);
			}

			parseField();

			if(!isAttr && lastWasPlain && l.type == Token.Type.For)
			{
				auto forComp = ForComprehension.parse(l);
				auto endLocation = l.expect(terminator).location;
				return new TableComprehension(location, endLocation, fields[0][0], fields[0][1], forComp);
			}

			while(l.type != terminator)
			{
				if(l.type == Token.Type.Comma)
					l.next();

				parseField();
			}
		}

		auto endLocation = l.expect(terminator).location;

		return new TableCtorExp(location, endLocation, fields[0 .. i]);
	}

	/**
	*/
	public static Expression parse(Lexer l)
	{
		return parseImpl(l, false);
	}

	/**
	Parse an attribute table.  The only difference is the delimiters (</ /> instead
	of { }).
	*/
	public static TableCtorExp parseAttrs(Lexer l)
	{
		return cast(TableCtorExp)parseImpl(l, true);
	}

	/**
	Used for parsing JSON.
	*/
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

	/**
	*/
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

/**
This node represents an array literal.
*/
class ArrayCtorExp : PrimaryExp
{
	/**
	The list of values.
	*/
	public Expression[] values;

	protected const uint maxFields = Instruction.arraySetFields * Instruction.rtMax;

	/**
	*/
	public this(Location location, Location endLocation, Expression[] values)
	{
		super(location, endLocation, AstTag.ArrayCtorExp);
		this.values = values;
	}

	/**
	*/
	public static PrimaryExp parse(Lexer l)
	{
		auto location = l.loc;

		l.expect(Token.Type.LBracket);

		List!(Expression) values;

		if(l.type != Token.Type.RBracket)
		{
			auto exp = Expression.parse(l);
			
			if(l.type == Token.Type.For)
			{
				auto forComp = ForComprehension.parse(l);
				auto endLocation = l.expect(Token.Type.RBracket).location;
				return new ArrayComprehension(location, endLocation, exp, forComp);
			}
			else
			{
				values.add(exp);

				while(l.type != Token.Type.RBracket)
				{
					if(l.type == Token.Type.Comma)
						l.next();

					values.add(Expression.parse(l));
				}
			}
		}

		auto endLocation = l.expect(Token.Type.RBracket).location;
		return new ArrayCtorExp(location, endLocation, values.toArray());
	}

	/**
	Used for parsing JSON.
	*/
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

	/**
	*/
	public override Expression fold()
	{
		foreach(ref value; values)
			value = value.fold();
			
		return this;
	}
}

/**
This node represents an array comprehension, such as "[x for x in a]".
*/
class ArrayComprehension : PrimaryExp
{
	/**
	The expression which is executed as the innermost thing in the loop and whose values
	are used to construct the array.
	*/
	public Expression exp;
	
	/**
	The root of the comprehension tree.
	*/
	public ForComprehension forComp;
	
	/**
	*/
	public this(Location location, Location endLocation, Expression exp, ForComprehension forComp)
	{
		super(location, endLocation, AstTag.ArrayComprehension);

		this.exp = exp;
		this.forComp = forComp;
	}

	public override void codeGen(FuncState s)
	{
		uint destReg = s.pushRegister();
		s.codeI(location.line, Op.NewArray, destReg, 0);

		auto exp = new class(this, destReg) Expression
		{
			ArrayComprehension mOuter;
			uint mReg;

			this(ArrayComprehension _outer, uint reg)
			{
				super(_outer.exp.location, _outer.exp.endLocation, AstTag.Other);
				mOuter = _outer;
				mReg = reg;
			}

			public override bool hasSideEffects()
			{
				return true;
			}

			public override void codeGen(FuncState s)
			{
				auto e = s.pushExp();
				e.type = ExpType.Var;
				e.index = mReg;
				s.pushSource(endLocation.line);

				Exp dest;
				s.popSource(endLocation.line, dest);

				mOuter.exp.codeGen(s);
				Exp src;
				s.popSource(endLocation.line, src);

				s.freeExpTempRegs(&src);
				s.freeExpTempRegs(&dest);

				s.popReflexOp(endLocation.line, Op.Append, dest.index, src.index, 2);

				// for popToNothing
				s.pushNull();
			}

			public override InstRef* codeCondition(FuncState s) { assert(false); }
		};

		auto stmt = new ExpressionStatement(location, endLocation, exp);

		forComp.rewrite(stmt).codeGen(s);
		s.pushTempReg(destReg);
	}
	
	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(location, "Cannot use an array comprehension as a condition");
	}
	
	/**
	*/
	public override Expression fold()
	{
		exp = exp.fold;
		forComp = forComp.fold();
		
		return this;
	}
}

/**
This node represents a table comprehension, such as "{[v] = k for k, v in a}".
*/
class TableComprehension : PrimaryExp
{
	/**
	The key expression.  This is the thing in the brackets at the beginning.
	*/
	public Expression key;

	/**
	The value expression.  This is the thing after the equals sign at the beginning.
	*/
	public Expression value;
	
	/**
	The root of the comprehension tree.
	*/
	public ForComprehension forComp;
	
	/**
	*/
	public this(Location location, Location endLocation, Expression key, Expression value, ForComprehension forComp)
	{
		super(location, endLocation, AstTag.TableComprehension);

		this.key = key;
		this.value = value;
		this.forComp = forComp;
	}
	
	public override void codeGen(FuncState s)
	{
		uint destReg = s.pushRegister();
		s.codeI(location.line, Op.NewTable, destReg, 0);

		auto exp = new class(this, destReg) Expression
		{
			TableComprehension mOuter;
			uint mReg;

			this(TableComprehension _outer, uint reg)
			{
				super(Location(""), Location(""), AstTag.Other);
				mOuter = _outer;
				mReg = reg;
			}

			public override bool hasSideEffects()
			{
				return true;
			}

			public override void codeGen(FuncState s)
			{
				mOuter.key.codeGen(s);
				Exp idx;
				s.popSource(mOuter.key.endLocation.line, idx);

				mOuter.value.codeGen(s);
				Exp val;
				s.popSource(mOuter.value.endLocation.line, val);

				s.codeR(mOuter.value.endLocation.line, Op.IndexAssign, mReg, idx.index, val.index);

				s.freeExpTempRegs(&val);
				s.freeExpTempRegs(&idx);

				// for popToNothing
				s.pushNull();
			}

			public override InstRef* codeCondition(FuncState s) { assert(false); }
		};

		auto stmt = new ExpressionStatement(location, endLocation, exp);

		forComp.rewrite(stmt).codeGen(s);
		s.pushTempReg(destReg);
	}
	
	public InstRef* codeCondition(FuncState s)
	{
		throw new MDCompileException(location, "Cannot use an array comprehension as a condition");
	}
	
	/**
	*/
	public override Expression fold()
	{
		key = key.fold();
		value = value.fold();
		forComp = forComp.fold();
		
		return this;
	}
}

/**
This node represents a namespace literal.
*/
class NamespaceCtorExp : PrimaryExp
{
	/**
	The actual "guts" of the namespace.
	*/
	public NamespaceDef def;

	/**
	*/
	public this(Location location, NamespaceDef def)
	{
		super(location, def.endLocation, AstTag.NamespaceCtorExp);
		this.def = def;
	}

	/**
	*/
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

	/**
	*/
	public override Expression fold()
	{
		def = def.fold();
		return this;
	}
}

/**
This node represents a yield expression, such as "yield(1, 2, 3)".
*/
class YieldExp : PrimaryExp
{
	/**
	The arguments inside the yield expression.
	*/
	public Expression[] args;

	/**
	*/
	public this(Location location, Location endLocation, Expression[] args)
	{
		super(location, endLocation, AstTag.YieldExp);
		this.args = args;
	}

	/**
	*/
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

	public bool hasSideEffects()
	{
		return true;
	}

	public bool isMultRet()
	{
		return true;
	}

	/**
	*/
	public override Expression fold()
	{
		foreach(ref arg; args)
			arg = arg.fold();

		return this;
	}
}

/**
This node represents a super call exp, such as "super.f()" or "super.("f")()"
(the former is sugar for the latter).
*/
class SuperCallExp : PrimaryExp
{
	/**
	The method name.  This can be any expression as long as it evaluates to a string.
	*/
	public Expression method;
	
	/**
	The arguments to pass to the function.
	*/
	public Expression[] args;

	/**
	*/
	public this(Location location, Location endLocation, Expression method, Expression[] args)
	{
		super(location, endLocation, AstTag.SuperCallExp);
		this.method = method;
		this.args = args;
	}

	/**
	*/
	public static SuperCallExp parse(Lexer l)
	{
		auto location = l.expect(Token.Type.Super).location;

		Expression method;

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

		l.expect(Token.Type.LParen);

		Expression[] args;

		if(l.type != Token.Type.RParen)
			args = Expression.parseArguments(l);

		auto endLocation = l.expect(Token.Type.RParen).location;
		return new SuperCallExp(location, endLocation, method, args);
	}
	
	public override void codeGen(FuncState s)
	{
		auto _this = new ThisExp(location);
		auto dot = new DotExp(_this, method);
		auto call = new MethodCallExp(endLocation, dot, null, args);

		call.codeGen(s, true);
	}

	public bool hasSideEffects()
	{
		return true;
	}

	public bool isMultRet()
	{
		return true;
	}

	public override Expression fold()
	{
		method = method.fold();
		
		if(method.isConstant && !method.isString)
			throw new MDCompileException(method.location, "Method name must be a string");

		foreach(ref arg; args)
			arg = arg.fold();

		return this;
	}
}