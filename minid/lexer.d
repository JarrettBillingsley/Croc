/******************************************************************************
License:
Copyright (c) 2008 Jarrett Billingsley

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

module minid.lexer;

import Float = tango.text.convert.Float;
import Integer = tango.text.convert.Integer;
import tango.core.Exception;
import Uni = tango.text.Unicode;
import Utf = tango.text.convert.Utf;

import minid.compilertypes;
import minid.interpreter;
import minid.string;
import minid.types;
import minid.utils;

struct Token
{
	public uint type;

	union
	{
		public bool boolValue;
		public dchar[] stringValue;
		public mdint intValue;
		public mdfloat floatValue;
	}

	public CompileLoc loc;

	public enum
	{
		As,
		Assert,
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
		Backslash,
		Arrow,
		Dollar,

		Ident,
		CharLiteral,
		StringLiteral,
		IntLiteral,
		FloatLiteral,
		EOF
	}

	public static const dchar[][] strings =
	[
		As: "as",
		Assert: "assert",
		Break: "break",
		Case: "case",
		Catch: "catch",
		Continue: "continue",
		Coroutine: "coroutine",
		Default: "default",
		Do: "do",
		Else: "else",
		False: "false",
		Finally: "finally",
		For: "for",
		Foreach: "foreach",
		Function: "function",
		Global: "global",
		If: "if",
		Import: "import",
		In: "in",
		Is: "is",
		Local: "local",
		Module: "module",
		Namespace: "namespace",
		Null: "null",
		Object: "object",
		Return: "return",
		Super: "super",
		Switch: "switch",
		This: "this",
		Throw: "throw",
		True: "true",
		Try: "try",
		Vararg: "vararg",
		While: "while",
		With: "with",
		Yield: "yield",

		Add: "+",
		AddEq: "+=",
		Inc: "++",
		Sub: "-",
		SubEq: "-=",
		Dec: "--",
		Cat: "~",
		CatEq: "~=",
		Cmp3: "<=>",
		Mul: "*",
		MulEq: "*=",
		DefaultEq: "?=",
		Div: "/",
		DivEq: "/=",
		Mod: "%",
		ModEq: "%=",
		LT: "<",
		LE: "<=",
		Shl: "<<",
		ShlEq: "<<=",
		GT: ">",
		GE: ">=",
		Shr: ">>",
		ShrEq: ">>=",
		UShr: ">>>",
		UShrEq: ">>>=",
		And: "&",
		AndEq: "&=",
		AndAnd: "&&",
		Or: "|",
		OrEq: "|=",
		OrOr: "||",
		Xor: "^",
		XorEq: "^=",
		Assign: "=",
		EQ: "==",
		Dot: ".",
		DotDot: "..",
		Not: "!",
		NE: "!=",
		LParen: "(",
		RParen: ")",
		LBracket: "[",
		RBracket: "]",
		LBrace: "{",
		RBrace: "}",
		LAttr: "</",
		RAttr: "/>",
		Colon: ":",
		Comma: ",",
		Semicolon: ";",
		Length: "#",
		Question: "?",
		Backslash: "\\",
		Arrow: "->",
		Dollar: "$",

		Ident: "Identifier",
		CharLiteral: "Char Literal",
		StringLiteral: "String Literal",
		IntLiteral: "Int Literal",
		FloatLiteral: "Float Literal",
		EOF: "<EOF>"
	];

	public static uint[dchar[]] stringToType;

	static this()
	{
		foreach(i, val; strings[0 .. Ident])
			stringToType[val] = i;

		stringToType.rehash;
	}

	public bool isOpAssign()
	{
		switch(type)
		{
			case Token.AddEq,
				Token.SubEq,
				Token.CatEq,
				Token.MulEq,
				Token.DivEq,
				Token.ModEq,
				Token.ShlEq,
				Token.ShrEq,
				Token.UShrEq,
				Token.OrEq,
				Token.XorEq,
				Token.AndEq,
				Token.DefaultEq:
				return true;

			default:
				return false;
		}

		assert(false);
	}
	
	public dchar[] typeString()
	{
		return strings[type];
	}
}

struct Lexer
{
	private ICompiler mCompiler;
	private word mStringTab;
	private CompileLoc mLoc;
	private dchar[] mSource;
	private bool mIsJSON;

	private uword mPosition;
	private dchar mCharacter;
	private dchar mLookaheadCharacter;
	private bool mHaveLookahead;
	private bool mNewlineSinceLastTok;

	private Token mTok;
	private Token mPeekTok;
	private bool mHavePeekTok;

	package static Lexer opCall(ICompiler compiler)
	{
		Lexer ret;
		ret.mCompiler = compiler;
		return ret;
	}

// ================================================================================================================================================
// Public
// ================================================================================================================================================

	public void begin(dchar[] name, dchar[] source, bool isJSON = false)
	{
		mStringTab = newTable(mCompiler.thread);

		mLoc = CompileLoc(name, 1, 0);
		mSource = source;
		mIsJSON = isJSON;
		mPosition = 0;

		mHaveLookahead = false;
		mNewlineSinceLastTok = false;
		mHavePeekTok = false;

		nextChar();

		if(mSource.startsWith("#!"d))
			while(!isEOL())
				nextChar();

		next();
	}

	public void end()
	{
		assert(stackSize(mCompiler.thread) - 1 == mStringTab, "OH NO String table is not in the right place!");
		pop(mCompiler.thread);
	}

	public Token* tok()
	{
		return &mTok;
	}

	public CompileLoc loc()
	{
		return mTok.loc;
	}

	public uint type()
	{
		return mTok.type;
	}

	public Token expect(uint t)
	{
		if(mTok.type != t)
			expected(Token.strings[t]);

		auto ret = mTok;

		if(t != Token.EOF)
			next();

		return ret;
	}

	public void expected(dchar[] message)
	{
		auto dg = (type == Token.EOF) ? &mCompiler.eofException : &mCompiler.exception;
		dg(mTok.loc, "'{}' expected; found '{}' instead", message, Token.strings[mTok.type]);
	}

	public bool isStatementTerm()
	{
		return mNewlineSinceLastTok ||
			mTok.type == Token.EOF ||
			mTok.type == Token.Semicolon ||
			mTok.type == Token.RBrace ||
			mTok.type == Token.RParen ||
			mTok.type == Token.RBracket;
	}

	public void statementTerm()
	{
		if(mNewlineSinceLastTok)
			return;
		else
		{
			if(mTok.type == Token.EOF || mTok.type == Token.RBrace || mTok.type == Token.RParen || mTok.type == Token.RBracket)
				return;
			else if(mTok.type == Token.Semicolon)
				next();
			else
				mCompiler.exception(mLoc, "Statement terminator expected, not '{}'", Token.strings[mTok.type]);
		}
	}

	public Token peek()
	{
		if(!mHavePeekTok)
		{
			auto t = mTok;
			nextToken();
			mHavePeekTok = true;
			mPeekTok = mTok;
			mTok = t;
		}

		return mPeekTok;
	}

	public void next()
	{
		if(mHavePeekTok)
		{
			mHavePeekTok = false;
			mTok = mPeekTok;
		}
		else
			nextToken();
	}

// ================================================================================================================================================
// Package
// ================================================================================================================================================

	package dchar[] newString(dchar[] data)
	{
		auto s = string.create(mCompiler.thread.vm, data);
		pushStringObj(mCompiler.thread, s);
		pushBool(mCompiler.thread, true);
		idxa(mCompiler.thread, mStringTab);
		return s.toString32();
	}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

	private bool isEOF()
	{
		return (mCharacter == '\0') || (mCharacter == dchar.init);
	}

	private bool isEOL()
	{
		return isNewline() || isEOF();
	}

	private bool isWhitespace()
	{
		return (mCharacter == ' ') || (mCharacter == '\t') || (mCharacter == '\v') || (mCharacter == '\u000C') || isEOL();
	}

	private bool isNewline()
	{
		return (mCharacter == '\r') || (mCharacter == '\n');
	}

	private bool isBinaryDigit()
	{
		return (mCharacter == '0') || (mCharacter == '1');
	}

	private bool isOctalDigit()
	{
		return (mCharacter >= '0') && (mCharacter <= '7');
	}

	private bool isHexDigit()
	{
		return ((mCharacter >= '0') && (mCharacter <= '9')) ||
			((mCharacter >= 'a') && (mCharacter <= 'f')) ||
			((mCharacter >= 'A') && (mCharacter <= 'F'));
	}

	private bool isDecimalDigit()
	{
		return (mCharacter >= '0') && (mCharacter <= '9');
	}

	private bool isAlpha()
	{
		return ((mCharacter >= 'a') && (mCharacter <= 'z')) || ((mCharacter >= 'A') && (mCharacter <= 'Z'));
	}

	private ubyte hexDigitToInt(dchar c)
	{
		assert((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'), "hexDigitToInt");

		if(c >= '0' && c <= '9')
			return cast(ubyte)(c - '0');

		if(Uni.isUpper(c))
			return cast(ubyte)(c - 'A' + 10);
		else
			return cast(ubyte)(c - 'a' + 10);
	}

	private dchar readChar()
	{
		if(mPosition >= mSource.length)
			return dchar.init;
		else
			return mSource[mPosition++];
	}

	private dchar lookaheadChar()
	{
		assert(!mHaveLookahead, "looking ahead too far");

		mLookaheadCharacter = readChar();
		mHaveLookahead = true;
		return mLookaheadCharacter;
	}

	private void nextChar()
	{
		mLoc.col++;

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

	private void nextLine()
	{
		while(isNewline() && !isEOF())
		{
			dchar old = mCharacter;

			nextChar();

			if(isNewline() && mCharacter != old)
				nextChar();

			mLoc.line++;
			mLoc.col = 1;
		}
	}

	private bool readNumLiteral(bool prependPoint, out mdfloat fret, out int iret)
	{
		auto beginning = mLoc;
		dchar[128] buf;
		uint i = 0;

		void add(dchar c)
		{
			if(i >= buf.length)
				mCompiler.exception(beginning, "Number literal too long");

			buf[i++] = c;
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
							mCompiler.exception(mLoc, "Binary digit expected, not '{}'", mCharacter);

						while(isBinaryDigit() || mCharacter == '_')
						{
							if(mCharacter != '_')
								add(mCharacter);

							nextChar();
						}

						try
							iret = Integer.toInt(buf[0 .. i], 2);
						catch(IllegalArgumentException e)
							mCompiler.exception(beginning, "Invalid binary integer literal");

						return true;

					case 'c', 'C':
						nextChar();

						if(!isOctalDigit() && mCharacter != '_')
							mCompiler.exception(mLoc, "Octal digit expected, not '{}'", mCharacter);

						while(isOctalDigit() || mCharacter == '_')
						{
							if(mCharacter != '_')
								add(mCharacter);

							nextChar();
						}

						try
							iret = Integer.toInt(buf[0 .. i], 8);
						catch(IllegalArgumentException e)
							mCompiler.exception(beginning, "Invalid octal integer literal");

						return true;

					case 'x', 'X':
						nextChar();

						if(!isHexDigit() && mCharacter != '_')
							mCompiler.exception(mLoc, "Hexadecimal digit expected, not '{}'", mCharacter);

						while(isHexDigit() || mCharacter == '_')
						{
							if(mCharacter != '_')
								add(mCharacter);

							nextChar();
						}

						try
							iret = Integer.toInt(buf[0 .. i], 16);
						catch(IllegalArgumentException e)
							mCompiler.exception(beginning, "Invalid hexadecimal integer literal");

						return true;

					default:
						add('0');
						break;
				}
			}
		}

		while(!hasPoint)
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
				//throw new OldCompileException(mLoc, "Floating point literal '{}' must have at least one digit after decimal point", buf[0 .. i]);
				assert(false);
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
					mCompiler.exception(mLoc, "Exponent value expected in float literal '{}'", buf[0 .. i]);

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

		if(!hasPoint && !hasExponent)
		{
			try
				iret = Integer.toInt(buf[0 .. i], 10);
			catch(IllegalArgumentException e)
				mCompiler.exception(beginning, "Invalid decimal integer literal");

			return true;
		}
		else
		{
			try
				fret = Float.toFloat(Utf.toString(buf[0 .. i]));
			catch(IllegalArgumentException e)
				mCompiler.exception(beginning, "Invalid floating point literal");

			return false;
		}
	}

	private dchar readEscapeSequence(CompileLoc beginning)
	{
		uint readHexDigits(uint num)
		{
			uint ret = 0;

			for(uint i = 0; i < num; i++)
			{
				if(!isHexDigit())
					mCompiler.exception(mLoc, "Hexadecimal escape digits expected");

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
			mCompiler.eofException(beginning, "Unterminated string or character literal");

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

				auto x = readHexDigits(2);

				if(x > 0x7F)
					mCompiler.exception(mLoc, "Hexadecimal escape sequence too large");

				ret = cast(dchar)x;
				break;

			case 'u':
				nextChar();

				auto x = readHexDigits(4);

				if(x == 0xFFFE || x == 0xFFFF)
					mCompiler.exception(mLoc, "Unicode escape '\\u{:x4}' is illegal", x);

				ret = cast(dchar)x;
				break;

			case 'U':
				nextChar();

				auto x = readHexDigits(8);

				if(x == 0xFFFE || x == 0xFFFF)
					mCompiler.exception(mLoc, "Unicode escape '\\U{:x8}' is illegal", x);

				if(!isValidUniChar(cast(dchar)x))
					mCompiler.exception(mLoc, "Unicode escape '\\U{:x8}' too large", x);

				ret = cast(dchar)x;
				break;

			default:
				if(!isDecimalDigit())
					mCompiler.exception(mLoc, "Invalid string escape sequence '\\{}'", mCharacter);

				// Decimal char
				int numch = 0;
				int c = 0;

				do
				{
					c = 10 * c + (mCharacter - '0');
					nextChar();
				} while(++numch < 3 && isDecimalDigit());

				if(c > 0x7F)
					mCompiler.exception(mLoc, "Numeric escape sequence too large");

				ret = cast(dchar)c;
				break;
		}

		return ret;
	}

	private dchar[] readStringLiteral(bool escape)
	{
		auto beginning = mLoc;

		// TODO: hm.
		scope buf = new List!(dchar)(mCompiler.alloc);
		dchar delimiter = mCharacter;

		// Skip opening quote
		nextChar();

		while(true)
		{
			if(isEOF())
				mCompiler.eofException(beginning, "Unterminated string literal");

			switch(mCharacter)
			{
				case '\r', '\n':
					buf ~= '\n';
					nextLine();
					continue;

				case '\\':
					if(!escape)
						goto default;

					buf ~= readEscapeSequence(beginning);
					continue;

				default:
					if(!escape && mCharacter == delimiter)
					{
						if(lookaheadChar() == delimiter)
						{
							buf ~= delimiter;
							nextChar();
							nextChar();
						}
						else
							break;
					}
					else
					{
						if(escape && mCharacter == delimiter)
							break;

						buf ~= mCharacter;
						nextChar();
					}

					continue;
			}

			break;
		}

		// Skip end quote
		nextChar();

		return newString(buf.toArray());
	}

	private dchar readCharLiteral()
	{
		auto beginning = mLoc;
		dchar ret;

		assert(mCharacter == '\'', "char literal must start with single quote");
		nextChar();

		if(isEOF())
			mCompiler.exception(beginning, "Unterminated character literal");

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
			mCompiler.exception(beginning, "Unterminated character literal");

		nextChar();

		return ret;
	}

	private void nextToken()
	{
		mNewlineSinceLastTok = false;

		while(true)
		{
			mTok.loc = mLoc;

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
						mTok.type = Token.AddEq;
					}
					else if(mCharacter == '+')
					{
						nextChar();
						mTok.type = Token.Inc;
					}
					else
						mTok.type = Token.Add;

					return;

				case '-':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.SubEq;
					}
					else if(mCharacter == '-')
					{
						nextChar();
						mTok.type = Token.Dec;
					}
					else if(mCharacter == '>')
					{
						nextChar();
						mTok.type = Token.Arrow;
					}
					else
						mTok.type = Token.Sub;

					return;

				case '~':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.CatEq;
					}
					else
						mTok.type = Token.Cat;

					return;

				case '*':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.MulEq;
					}
					else
						mTok.type = Token.Mul;

					return;

				case '/':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.DivEq;
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
						mTok.type = Token.RAttr;
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
									mCompiler.eofException(mTok.loc, "Unterminated /* */ comment");

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
									mCompiler.eofException(mTok.loc, "Unterminated /+ +/ comment");

								default:
									break;
							}
							
							nextChar();
						}
					}
					else
					{
						mTok.type = Token.Div;
						return;
					}

					break;

				case '%':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.ModEq;
					}
					else
						mTok.type = Token.Mod;

					return;

				case '<':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();

						if(mCharacter == '>')
						{
							nextChar();
							mTok.type = Token.Cmp3;
						}
						else
							mTok.type = Token.LE;
					}
					else if(mCharacter == '<')
					{
						nextChar();

						if(mCharacter == '=')
						{
							nextChar();
							mTok.type = Token.ShlEq;
						}
						else
							mTok.type = Token.Shl;
					}
					else if(mCharacter == '/')
					{
						nextChar();
						mTok.type = Token.LAttr;
					}
					else
						mTok.type = Token.LT;

					return;

				case '>':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.GE;
					}
					else if(mCharacter == '>')
					{
						nextChar();

						if(mCharacter == '=')
						{
							nextChar();
							mTok.type = Token.ShrEq;
						}
						else if(mCharacter == '>')
						{
							nextChar();

							if(mCharacter == '=')
							{
								nextChar();
								mTok.type = Token.UShrEq;
							}
							else
								mTok.type = Token.UShr;
						}
						else
							mTok.type = Token.Shr;
					}
					else
						mTok.type = Token.GT;

					return;

				case '&':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.AndEq;
					}
					else if(mCharacter == '&')
					{
						nextChar();
						mTok.type = Token.AndAnd;
					}
					else
						mTok.type = Token.And;

					return;

				case '|':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.OrEq;
					}
					else if(mCharacter == '|')
					{
						nextChar();
						mTok.type = Token.OrOr;
					}
					else
						mTok.type = Token.Or;

					return;

				case '^':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.XorEq;
					}
					else
						mTok.type = Token.Xor;

					return;

				case '=':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.EQ;
					}
					else
						mTok.type = Token.Assign;

					return;

				case '.':
					nextChar();

					if(isDecimalDigit())
					{
						int dummy;
						bool b = readNumLiteral(true, mTok.floatValue, dummy);
						assert(!b, "literal must be float");

						mTok.type = Token.FloatLiteral;
					}
					else if(mCharacter == '.')
					{
						nextChar();
						mTok.type = Token.DotDot;
					}
					else
						mTok.type = Token.Dot;

					return;

				case '!':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.NE;
					}
					else
						mTok.type = Token.Not;

					return;
					
				case '?':
					nextChar();

					if(mCharacter == '=')
					{
						nextChar();
						mTok.type = Token.DefaultEq;
					}
					else
						mTok.type = Token.Question;

					return;

				case '\"':
					mTok.stringValue = readStringLiteral(true);
					mTok.type = Token.StringLiteral;
					return;

				case '`':
					mTok.stringValue = readStringLiteral(false);
					mTok.type = Token.StringLiteral;
					return;

				case '@':
					nextChar();

					if(mCharacter != '\"')
						mCompiler.exception(mTok.loc, "'@' expected to be followed by '\"'");

					mTok.stringValue = readStringLiteral(false);
					mTok.type = Token.StringLiteral;
					return;

				case '\'':
					mTok.intValue = readCharLiteral();
					mTok.type = Token.CharLiteral;
					return;

				case '\0', dchar.init:
					mTok.type = Token.EOF;
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

						if(!isInt)
						{
							mTok.floatValue = fval;
							mTok.type = Token.FloatLiteral;
						}
						else
						{
							mTok.intValue = ival;
							mTok.type = Token.IntLiteral;
						}

						return;
					}
					else if(isAlpha() || mCharacter == '_')
					{
						auto start = mPosition - 1;

						do
							nextChar();
						while(isAlpha() || isDecimalDigit() || mCharacter == '_');

						auto s = mSource[start .. mPosition - 1];

						if(s.startsWith("__"d))
							mCompiler.exception(mTok.loc, "'{}': Identifiers starting with two underscores are reserved", s);

						if(auto t = (s in Token.stringToType))
							mTok.type = *t;
						else
						{
							mTok.type = Token.Ident;
							mTok.stringValue = newString(s);
						}

						return;
					}
					else
					{
						dchar[1] buf;
						buf[0] = mCharacter;
						auto s = buf[];

						nextChar();

						if(auto t = (s in Token.stringToType))
							mTok.type = *t;
						else
							mCompiler.exception(mTok.loc, "Invalid token '{}'", s);

						return;
					}
			}
		}
	}
}