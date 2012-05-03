/******************************************************************************
This module contains the lexical analysis phase of the Croc compiler.

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

module croc.compiler_lexer;

import Float = tango.text.convert.Float;
import Integer = tango.text.convert.Integer;
import tango.core.Exception;
import tango.text.Util;
import Uni = tango.text.Unicode;
import Utf = tango.text.convert.Utf;

import croc.compiler_types;
import croc.types;
import croc.utils;

struct Token
{
	uint type;

	union
	{
		bool boolValue;
		char[] stringValue;
		crocint intValue;
		crocfloat floatValue;
	}

	CompileLoc loc;
	char[] preComment, postComment;
	CompileLoc preCommentLoc, postCommentLoc;
	uword startChar;

	enum
	{
		As,
		Assert,
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
		Scope,
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
		Colon,
		Comma,
		Semicolon,
		Length,
		Question,
		Backslash,
		Arrow,
		Dollar,
		At,

		Ident,
		CharLiteral,
		StringLiteral,
		IntLiteral,
		FloatLiteral,
		EOF
	}

	static const char[][] strings =
	[
		As: "as",
		Assert: "assert",
		Break: "break",
		Case: "case",
		Catch: "catch",
		Class: "class",
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
		Return: "return",
		Scope: "scope",
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
		Colon: ":",
		Comma: ",",
		Semicolon: ";",
		Length: "#",
		Question: "?",
		Backslash: "\\",
		Arrow: "->",
		Dollar: "$",
		At: "@",

		Ident: "Identifier",
		CharLiteral: "Char Literal",
		StringLiteral: "String Literal",
		IntLiteral: "Int Literal",
		FloatLiteral: "Float Literal",
		EOF: "<EOF>"
	];

	static uint[char[]] stringToType;

	static this()
	{
		foreach(i, val; strings[0 .. Ident])
			stringToType[val] = i;

		stringToType.rehash;
	}

	bool isOpAssign()
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
	}

	char[] typeString()
	{
		return strings[type];
	}
}

struct Lexer
{
private:
	ICompiler mCompiler;
	CompileLoc mLoc;
	char[] mSource;

	uword mPosition;
	dchar mCharacter;
	dchar mLookaheadCharacter;
	bool mHaveLookahead;
	bool mNewlineSinceLastTok;
	bool mTokSinceLastNewline;

	uword mCaptureStart;
	uword mCaptureEnd;

	Token mTok;
	Token mPeekTok;
	bool mHavePeekTok;

package:
	static Lexer opCall(ICompiler compiler)
	{
		Lexer ret;
		ret.mCompiler = compiler;
		return ret;
	}

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

	void begin(char[] name, char[] source)
	{
		mLoc = CompileLoc(name, 1, 0);
		mSource = source;
		mPosition = 0;

		mHaveLookahead = false;
		mNewlineSinceLastTok = false;
		mHavePeekTok = false;

		nextChar();

		if(mSource.startsWith("#!"))
			while(!isEOL())
				nextChar();

		next();
	}

	Token* tok()
	{
		return &mTok;
	}

	CompileLoc loc()
	{
		return mTok.loc;
	}

	uint type()
	{
		return mTok.type;
	}

	Token expect(uint t)
	{
		if(mTok.type != t)
			expected(Token.strings[t]);

		auto ret = mTok;

		if(t != Token.EOF)
			next();

		return ret;
	}

	void expected(char[] message)
	{
		auto dg = (type == Token.EOF) ? &mCompiler.eofException : &mCompiler.synException;
		dg(mTok.loc, "'{}' expected; found '{}' instead", message, Token.strings[mTok.type]);
	}

	bool isStatementTerm()
	{
		return mNewlineSinceLastTok ||
			mTok.type == Token.EOF ||
			mTok.type == Token.Semicolon ||
			mTok.type == Token.RBrace ||
			mTok.type == Token.RParen ||
			mTok.type == Token.RBracket;
	}

	void statementTerm()
	{
		if(mNewlineSinceLastTok)
			return;
		else if(mTok.type == Token.EOF || mTok.type == Token.RBrace || mTok.type == Token.RParen || mTok.type == Token.RBracket)
			return;
		else if(mTok.type == Token.Semicolon)
			next();
		else
			mCompiler.synException(mLoc, "Statement terminator expected, not '{}'", Token.strings[mTok.type]);
	}

	Token peek()
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

	void next()
	{
		if(mHavePeekTok)
		{
			mHavePeekTok = false;
			mTok = mPeekTok;
		}
		else
			nextToken();
	}

	uword beginCapture()
	{
		mCaptureEnd = mTok.startChar;
		return mCaptureEnd;
	}

	char[] endCapture(uword captureStart)
	{
		return mCompiler.newString(mSource[captureStart .. mCaptureEnd].trim());
	}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

	bool isEOF()
	{
		return (mCharacter == '\0') || (mCharacter == dchar.init);
	}

	bool isEOL()
	{
		return isNewline() || isEOF();
	}

	bool isWhitespace()
	{
		return (mCharacter == ' ') || (mCharacter == '\t') || (mCharacter == '\v') || (mCharacter == '\u000C') || isEOL();
	}

	bool isNewline()
	{
		return (mCharacter == '\r') || (mCharacter == '\n');
	}

	bool isBinaryDigit()
	{
		return (mCharacter == '0') || (mCharacter == '1');
	}

	bool isHexDigit()
	{
		return ((mCharacter >= '0') && (mCharacter <= '9')) ||
			((mCharacter >= 'a') && (mCharacter <= 'f')) ||
			((mCharacter >= 'A') && (mCharacter <= 'F'));
	}

	bool isDecimalDigit()
	{
		return (mCharacter >= '0') && (mCharacter <= '9');
	}

	bool isAlpha()
	{
		return ((mCharacter >= 'a') && (mCharacter <= 'z')) || ((mCharacter >= 'A') && (mCharacter <= 'Z'));
	}

	ubyte hexDigitToInt(dchar c)
	{
		assert((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'), "hexDigitToInt");

		if(c >= '0' && c <= '9')
			return cast(ubyte)(c - '0');

		if(Uni.isUpper(c))
			return cast(ubyte)(c - 'A' + 10);
		else
			return cast(ubyte)(c - 'a' + 10);
	}

	dchar readChar()
	{
		if(mPosition >= mSource.length)
			return dchar.init;
		else
		{
			uint ate = 0;
			auto ret = Utf.decode(mSource[mPosition .. $], ate);
			mPosition += ate;
			return ret;
		}
	}

	dchar lookaheadChar()
	{
		assert(!mHaveLookahead, "looking ahead too far");

		mLookaheadCharacter = readChar();
		mHaveLookahead = true;
		return mLookaheadCharacter;
	}

	void nextChar()
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

	void nextLine(bool readMultiple = true)
	{
		while(isNewline() && !isEOF())
		{
			dchar old = mCharacter;

			nextChar();

			if(isNewline() && mCharacter != old)
				nextChar();

			mLoc.line++;
			mLoc.col = 1;

			if(!readMultiple)
				return;
		}
	}

	// This expects the input string to consist entirely of digits within the valid range of radix
	bool convertInt(dchar[] str, out crocint ret, uint radix)
	{
		ret = 0;

		foreach(c; str)
		{
			if (c >= '0' && c <= '9')
			{}
			else if (c >= 'a' && c <= 'z')
				c -= 39;
			else if (c >= 'A' && c <= 'Z')
				c -= 7;
			else
				assert(false);

			c -= '0';

			assert(c < radix);

			auto newValue = ret * radix + c;

			if(newValue < ret)
				return false;

			ret = newValue;
		}

		return true;
	}

	bool convertUInt(dchar[] str, out crocint ret, uint radix)
	{
		ret = 0;

		static if(crocint.sizeof == 8)
			ulong r = 0;
		else static if(crocint.sizeof == 4)
			uint r = 0;
		else
			static assert(false, "wtf r u doin");

		foreach(c; str)
		{
			if (c >= '0' && c <= '9')
			{}
			else if (c >= 'a' && c <= 'z')
				c -= 39;
			else if (c >= 'A' && c <= 'Z')
				c -= 7;
			else
				assert(false);

			c -= '0';

			assert(c < radix);

			auto newValue = r * radix + c;

			if(newValue < r)
				return false;

			r = newValue;
		}

		ret = cast(crocint)r;
		return true;
	}

	bool readNumLiteral(bool prependPoint, out crocfloat fret, out crocint iret)
	{
		auto beginning = mLoc;
		dchar[128] buf;
		uint i = 0;

		void add(dchar c)
		{
			if(i >= buf.length)
				mCompiler.lexException(beginning, "Number literal too long");

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
							mCompiler.lexException(mLoc, "Binary digit expected, not '{}'", mCharacter);

						while(isBinaryDigit() || mCharacter == '_')
						{
							if(mCharacter != '_')
								add(mCharacter);

							nextChar();
						}
						
						if(!convertUInt(buf[0 .. i], iret, 2))
							mCompiler.lexException(beginning, "Binary integer literal overflow");

						return true;

					case 'x', 'X':
						nextChar();

						if(!isHexDigit() && mCharacter != '_')
							mCompiler.lexException(mLoc, "Hexadecimal digit expected, not '{}'", mCharacter);

						while(isHexDigit() || mCharacter == '_')
						{
							if(mCharacter != '_')
								add(mCharacter);

							nextChar();
						}

						if(!convertUInt(buf[0 .. i], iret, 16))
							mCompiler.lexException(beginning, "Hexadecimal integer literal overflow");

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
					
					if(isDecimalDigit())
					{
						add(mCharacter);
						nextChar();
					}
					else if(mCharacter == '_')
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
				nextChar();
				continue;
			}
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

				if(!isDecimalDigit() && mCharacter != '_')
					mCompiler.lexException(mLoc, "Exponent value expected in float literal '{}'", buf[0 .. i]);

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
			if(!convertInt(buf[0 .. i], iret, 10))
				mCompiler.lexException(beginning, "Decimal integer literal overflow");

			return true;
		}
		else
		{
			try
				fret = Float.toFloat(buf[0 .. i]);
			catch(IllegalArgumentException e)
				mCompiler.lexException(beginning, "Invalid floating point literal");

			return false;
		}
	}

	dchar readEscapeSequence(CompileLoc beginning)
	{
		uint readHexDigits(uint num)
		{
			uint ret = 0;

			for(uint i = 0; i < num; i++)
			{
				if(!isHexDigit())
					mCompiler.lexException(mLoc, "Hexadecimal escape digits expected");

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

			case 'x':
				nextChar();

				auto x = readHexDigits(2);

				if(x > 0x7F)
					mCompiler.lexException(mLoc, "Hexadecimal escape sequence too large");

				ret = cast(dchar)x;
				break;

			case 'u':
				nextChar();

				auto x = readHexDigits(4);

				if(x == 0xFFFE || x == 0xFFFF)
					mCompiler.lexException(mLoc, "Unicode escape '\\u{:x4}' is illegal", x);

				ret = cast(dchar)x;
				break;

			case 'U':
				nextChar();

				auto x = readHexDigits(8);

				if(x == 0xFFFE || x == 0xFFFF)
					mCompiler.lexException(mLoc, "Unicode escape '\\U{:x8}' is illegal", x);

				if(!Utf.isValid(cast(dchar)x))
					mCompiler.lexException(mLoc, "Unicode escape '\\U{:x8}' too large", x);

				ret = cast(dchar)x;
				break;

			default:
				if(!isDecimalDigit())
					mCompiler.lexException(mLoc, "Invalid string escape sequence '\\{}'", mCharacter);

				// Decimal char
				int numch = 0;
				int c = 0;

				do
				{
					c = 10 * c + (mCharacter - '0');
					nextChar();
				} while(++numch < 3 && isDecimalDigit());

				if(c > 0x7F)
					mCompiler.lexException(mLoc, "Numeric escape sequence too large");

				ret = cast(dchar)c;
				break;
		}

		return ret;
	}

	char[] readStringLiteral(bool escape)
	{
		auto beginning = mLoc;

		scope buf = new List!(char)(mCompiler.alloc);
		dchar delimiter = mCharacter;

		// to be safe..
		char[6] utfbuf = void;

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
					nextLine(false);
					continue;

				case '\\':
					if(!escape)
						goto default;

					buf ~= Utf.encode(utfbuf, readEscapeSequence(beginning));
					continue;

				default:
					if(!escape && mCharacter == delimiter)
					{
						if(lookaheadChar() == delimiter)
						{
							buf ~= Utf.encode(utfbuf, delimiter);
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
						
						buf ~= Utf.encode(utfbuf, mCharacter);
						nextChar();
					}
					continue;
			}

			break;
		}

		// Skip end quote
		nextChar();

		auto arr = buf.toArray();
		
		scope(exit)
			mCompiler.alloc.freeArray(arr);

		return mCompiler.newString(arr);
	}

	dchar readCharLiteral()
	{
		auto beginning = mLoc;
		dchar ret;

		assert(mCharacter == '\'', "char literal must start with single quote");
		nextChar();

		if(isEOF())
			mCompiler.lexException(beginning, "Unterminated character literal");

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
			mCompiler.lexException(beginning, "Unterminated character literal");

		nextChar();

		return ret;
	}
	
	void addComment(char[] str, CompileLoc location)
	{
		void derp(ref char[] existing)
		{
			if(existing is null)
				existing = str;
			else
				mCompiler.lexException(location, "Cannot have multiple doc comments in a row; merge them into one comment");
		}

		if(mTokSinceLastNewline)
			derp(mTok.postComment);
		else
			derp(mTok.preComment);
	}

	void readLineComment()
	{
		if(mCompiler.docComments && mCharacter == '/')
		{
			nextChar();

			auto loc = mLoc;

			// eat any extra slashes after the opening triple slash
			while(mCharacter == '/')
				nextChar();

			// eat whitespace too
			while(isWhitespace() && !isEOL())
				nextChar();

			scope buf = new List!(char)(mCompiler.alloc);

			while(!isEOL())
			{
				buf ~= mCharacter;
				nextChar();
			}

			buf ~= '\n';
			auto arr = buf.toArray();
			scope(exit) mCompiler.alloc.freeArray(arr);
			addComment(mCompiler.newString(arr), loc);
		}
		else
		{
			while(!isEOL())
				nextChar();
		}
	}

	void readBlockComment()
	{
		if(mCompiler.docComments && mCharacter == '*')
		{
			nextChar();

			auto loc = mLoc;

			// eat any extra asterisks after opening
			while(mCharacter == '*')
				nextChar();

			// eat whitespace too
			while(isWhitespace() && !isEOL())
				nextChar();

			scope buf = new List!(char)(mCompiler.alloc);
			uint nesting = 1;
			bool justWS = false;

			void trimTrailingWS()
			{
				while(buf.length > 0 && (buf[buf.length - 1] == ' ' || buf[buf.length - 1] == '\t'))
					buf.length = buf.length - 1;
			}

			_commentLoop: while(true)
			{
				switch(mCharacter)
				{
					case '/':
						buf ~= '/';
						nextChar();

						if(mCharacter == '*')
						{
							buf ~= '*';
							nextChar();
							nesting++;
						}

						continue;

					case '*':
						nextChar();

						if(mCharacter == '/')
						{
							nextChar();
							nesting--;

							if(nesting == 0)
								break _commentLoop;

							buf ~= "*/";
						}
						else if(justWS)
						{
							justWS = false;
							trimTrailingWS();
						}
						else
							buf ~= '*';
						continue;

					case '\r', '\n':
						nextLine(false);
						justWS = true;
						trimTrailingWS();
						buf ~= '\n';
						continue;

					case '\0', dchar.init:
						mCompiler.eofException(mTok.loc, "Unterminated /* */ comment");

					default:
						if(mCharacter != ' ' && mCharacter != '\t')
							justWS = false;

						buf ~= mCharacter;
						break;
				}

				nextChar();
			}

			// eat any trailing asterisks
			while(buf.length > 0 && buf[buf.length - 1] == '*')
				buf.length = buf.length - 1;

			if(buf.length > 0 && buf[buf.length - 1] != '\n')
				buf ~= '\n';

			auto arr = buf.toArray();
			scope(exit) mCompiler.alloc.freeArray(arr);
			addComment(mCompiler.newString(arr), loc);
		}
		else
		{
			uint nesting = 1;

			_commentLoop2: while(true)
			{
				switch(mCharacter)
				{
					case '/':
						nextChar();
	
						if(mCharacter == '*')
						{
							nextChar();
							nesting++;
						}
	
						continue;
						
					case '*':
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
						mCompiler.eofException(mTok.loc, "Unterminated /* */ comment");

					default:
						break;
				}

				nextChar();
			}
		}
	}

	void nextToken()
	{
		mNewlineSinceLastTok = false;
		mTok.preComment = null;
		mTok.postComment = null;
		mTok.preCommentLoc = CompileLoc.init;
		mTok.postCommentLoc = CompileLoc.init;
		mTok.startChar = mPosition - 1;
		mCaptureEnd = mTok.startChar;

		scope(exit)
			mTokSinceLastNewline = true;

		while(true)
		{
			mTok.loc = mLoc;

			switch(mCharacter)
			{
				case '\r', '\n':
					nextLine();
					mNewlineSinceLastTok = true;
					mTokSinceLastNewline = false;
					mTok.startChar = mPosition - 1;
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
						nextChar();
						readLineComment();
					}
					else if(mCharacter == '*')
					{
						nextChar();
						readBlockComment();
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
						crocint dummy;
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

				case '@':
					nextChar();

					if(mCharacter == '\"' || mCharacter == '\'' || mCharacter == '`')
					{
						mTok.stringValue = readStringLiteral(false);
						mTok.type = Token.StringLiteral;
					}
					else
						mTok.type = Token.At;

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
						mTok.startChar = mPosition - 1;
						continue;
					}
					else if(isDecimalDigit())
					{
						crocfloat fval;
						crocint ival;

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
						scope buf = new List!(char)(mCompiler.alloc);
						char[6] utfbuf = void;

						do
						{
							buf ~= Utf.encode(utfbuf, mCharacter);
							nextChar();
						} while(isAlpha() || isDecimalDigit() || mCharacter == '_');

						auto arr = buf.toArray();
						
						scope(exit)
							mCompiler.alloc.freeArray(arr);

						auto s = mCompiler.newString(arr);

						if(s.startsWith("__"))
							mCompiler.lexException(mTok.loc, "'{}': Identifiers starting with two underscores are reserved", s);

						if(auto t = (s in Token.stringToType))
							mTok.type = *t;
						else
						{
							mTok.type = Token.Ident;
							mTok.stringValue = mCompiler.newString(s);
						}

						return;
					}
					else
					{
						if(mCharacter > 0x7f)
							mCompiler.lexException(mTok.loc, "Invalid token '{}'", mCharacter);

						char[1] buf = void;
						buf[0] = cast(char)mCharacter;
						auto s = buf[];

						nextChar();

						if(auto t = (s in Token.stringToType))
							mTok.type = *t;
						else
							mCompiler.lexException(mTok.loc, "Invalid token '{}'", s);

						return;
					}
			}
		}
	}
}