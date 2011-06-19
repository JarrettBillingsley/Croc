/******************************************************************************
This module holds a simple API to both save and load JSON, a simple, popular
data interchange format for the web.

License:
Copyright (c) 2011 Jarrett Billingsley

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

module croc.ex_json;

import tango.io.stream.Format;
import tango.math.Math;
import tango.text.Util;
import Uni = tango.text.Unicode;
import Utf = tango.text.convert.Utf;

alias tango.text.Util.contains contains;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.types;
import croc.utils;

// ================================================================================================================================================
// Public
// ================================================================================================================================================
public:

word fromJSON(CrocThread* t, char[] source)
{
	Lexer l;
	l.begin(t, source);
	word ret;

	if(l.type == Token.LBrace)
		ret = parseObject(t, l);
	else if(l.type == Token.LBracket)
		ret = parseArray(t, l);
	else
		throwException(t, "JSON must have an object or an array as its top-level value");

	l.expect(Token.EOF);
	return ret;
}

// Expects root to be at the top of the stack
void toJSON(T)(CrocThread* t, word root, bool pretty, FormatOutput!(T) printer)
{
	root = absIndex(t, root);
	auto cycles = newTable(t);

	word indent = 0;

	void newline(word dir = 0)
	{
		printer.newline;

		if(dir > 0)
			indent++;
		else if(dir < 0)
			indent--;

		for(word i = indent; i > 0; i--)
			printer.print("\t");
	}

	void delegate(word) outputValue;

	void outputTable(word tab)
	{
		printer.print("{");

		if(pretty)
			newline(1);

		bool first = true;
		dup(t, tab);

		foreach(word k, word v; foreachLoop(t, 1))
		{
			if(!isString(t, k))
				throwException(t, "All keys in a JSON table must be strings");

			if(first)
				first = false;
			else
			{
				printer.print(",");

				if(pretty)
					newline();
			}

			outputValue(k);

			if(pretty)
				printer.print(": ");
			else
				printer.print(":");

			outputValue(v);
		}

		if(pretty)
			newline(-1);

		printer.print("}");
	}

	void outputArray(word arr)
	{
		printer.print("[");

		auto l = len(t, arr);

		for(word i = 0; i < l; i++)
		{
			if(i > 0)
			{
				if(pretty)
					printer.print(", ");
				else
					printer.print(",");
			}

			outputValue(idxi(t, arr, i));
			pop(t);
		}

		printer.print("]");
	}

	void outputChar(dchar c)
	{
		switch(c)
		{
			case '\b': printer.print("\\b"); return;
			case '\f': printer.print("\\f"); return;
			case '\n': printer.print("\\n"); return;
			case '\r': printer.print("\\r"); return;
			case '\t': printer.print("\\t"); return;

			case '"', '\\', '/':
				printer.print("\\");
				printer.print(c);
				return;

			default:
				if(c > 0x7f)
					printer.format("\\u{:x4}", cast(int)c);
				else
					printer.print(c);

				return;
		}
	}

	void _outputValue(word idx)
	{
		switch(type(t, idx))
		{
			case CrocValue.Type.Null:
				printer.print("null");
				break;

			case CrocValue.Type.Bool:
				printer.print(getBool(t, idx) ? "true" : "false");
				break;

			case CrocValue.Type.Int:
				printer.format("{}", getInt(t, idx));
				break;

			case CrocValue.Type.Float:
				printer.format("{}", getFloat(t, idx));
				break;

			case CrocValue.Type.Char:
				printer.print('"');
				outputChar(getChar(t, idx));
				printer.print('"');
				break;

			case CrocValue.Type.String:
				printer.print('"');

				foreach(dchar c; getString(t, idx))
					outputChar(c);

				printer.print('"');
				break;

			case CrocValue.Type.Table:
				if(opin(t, idx, cycles))
					throwException(t, "Table is cyclically referenced");

				dup(t, idx);
				pushBool(t, true);
				idxa(t, cycles);

				scope(exit)
				{
					dup(t, idx);
					pushNull(t);
					idxa(t, cycles);
				}

				outputTable(idx);
				break;

			case CrocValue.Type.Array:
				if(opin(t, idx, cycles))
					throwException(t, "Array is cyclically referenced");

				dup(t, idx);
				pushBool(t, true);
				idxa(t, cycles);

				scope(exit)
				{
					dup(t, idx);
					pushNull(t);
					idxa(t, cycles);
				}

				outputArray(idx);
				break;

			default:
				pushTypeString(t, idx);
				throwException(t, "Type '{}' is not a valid type for conversion to JSON", getString(t, -1));
		}
	}

	outputValue = &_outputValue;

	if(isArray(t, root))
		outputArray(root);
	else if(isTable(t, root))
		outputTable(root);
	else
	{
		pushTypeString(t, root);
		throwException(t, "Root element must be either a table or an array, not a '{}'", getString(t, -1));
	}

	printer.flush();
	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

struct Token
{
	public uint type;
	public uword line;
	public uword col;

	public enum
	{
		String,
		Int,
		Float,
		True,
		False,
		Null,

		Comma,
		Colon,
		LBrace,
		RBrace,
		LBracket,
		RBracket,

		EOF
	}

	public static const char[][] strings =
	[
		String: "string",
		Int: "integer",
		Float: "float",
		True: "true",
		False: "false",
		Null: "null",

		Comma: ",",
		Colon: ":",
		LBrace: "{",
		RBrace: "}",
		LBracket: "[",
		RBracket: "]",

		EOF: "<EOF>"
	];
}

struct Lexer
{
	private CrocThread* t;

	private uword mLine;
	private uword mCol;
	private char[] mSource;

	private uword mPosition;
	private dchar mCharacter;

	private Token mTok;

	public void begin(CrocThread* t, char[] source)
	{
		this.t = t;
		mLine = 1;
		mCol = 0;
		mSource = source;
		mPosition = 0;

		nextChar();
		next();
	}

	public Token* tok()
	{
		return &mTok;
	}
	
	public uword line()
	{
		return mLine;
	}
	
	public uword col()
	{
		return mCol;
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

	public void expected(char[] message)
	{
		throwException(t, "({}:{}): '{}' expected; found '{}' instead", mTok.line, mTok.col, message, Token.strings[mTok.type]);
	}

	public void next()
	{
		nextToken();
	}

	private bool isEOF()
	{
		return mCharacter == dchar.init;
	}

	private bool isWhitespace()
	{
		return (mCharacter == ' ') || (mCharacter == '\t') || isNewline();
	}

	private bool isNewline()
	{
		return (mCharacter == '\r') || (mCharacter == '\n');
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
		{
			uint ate = 0;
			auto ret = Utf.decode(mSource[mPosition .. $], ate);
			mPosition += ate;
			return ret;
		}
	}

	private void nextChar()
	{
		mCol++;
		mCharacter = readChar();
	}

	private void nextLine()
	{
		while(isNewline() && !isEOF())
		{
			dchar old = mCharacter;

			nextChar();

			if(isNewline() && mCharacter != old)
				nextChar();

			mLine++;
			mCol = 1;
		}
	}

	private bool convertInt(dchar[] str, out crocint ret)
	{
		ret = 0;

		foreach(c; str)
		{
			c -= '0';
			auto newValue = ret * 10 + c;

			if(newValue < ret)
				return false;

			ret = newValue;
		}

		return true;
	}

	private bool readNumLiteral()
	{
		bool neg = false;

		// sign
		if(mCharacter == '-')
		{
			neg = true;
			nextChar();

			if(!isDecimalDigit())
				throwException(t, "({}:{}): incomplete number token", mLine, mCol);
		}

		// integral part
		crocint iret = 0;

		if(mCharacter == '0')
			nextChar();
		else
		{
			while(isDecimalDigit())
			{
				iret = (iret * 10) + (mCharacter - '0');
				nextChar();
			}
		}

		if(isEOF() || !contains(".eE"d, mCharacter))
		{
			pushInt(t, neg? -iret : iret);
			return true;
		}

		// fraction
		crocfloat fret = iret;

		if(mCharacter == '.')
		{
			nextChar();

			if(!isDecimalDigit())
				throwException(t, "({}:{}): incomplete number token", mLine, mCol);

			crocfloat frac = 0.0;
			crocfloat mag = 10.0;

			while(isDecimalDigit())
			{
				frac += (mCharacter - '0') / mag;
				mag *= 10;
				nextChar();
			}

			fret += frac;
		}

		// exponent
		if(mCharacter == 'e' || mCharacter == 'E')
		{
			nextChar();

			if(!isDecimalDigit() && mCharacter != '+' && mCharacter != '-')
				throwException(t, "({}:{}): incomplete number token", mLine, mCol);

			bool negExp = false;

			if(mCharacter == '+')
				nextChar();
			else if(mCharacter == '-')
			{
				negExp = true;
				nextChar();
			}

			if(!isDecimalDigit())
				throwException(t, "({}:{}): incomplete number token", mLine, mCol);

			crocfloat exp = 0;

			while(isDecimalDigit())
			{
				exp = (exp * 10) + (mCharacter - '0');
				nextChar();
			}

			fret = fret * pow(10, negExp? -exp : exp);
		}
		
		pushFloat(t, neg? -fret : fret);
		return false;
	}

	private dchar readEscapeSequence(uword beginningLine, uword beginningCol)
	{
		uint readHexDigits(uint num)
		{
			uint ret = 0;

			for(uint i = 0; i < num; i++)
			{
				if(!isHexDigit())
					throwException(t, "({}:{}): Hexadecimal escape digits expected", mLine, mCol);

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
			throwException(t, "({}:{}): Unterminated string literal", beginningLine, beginningCol);

		switch(mCharacter)
		{
			case 'b':  nextChar(); return '\b';
			case 'f':  nextChar(); return '\f';
			case 'n':  nextChar(); return '\n';
			case 'r':  nextChar(); return '\r';
			case 't':  nextChar(); return '\t';
			case '\\': nextChar(); return '\\';
			case '\"': nextChar(); return '\"';
			case '/':  nextChar(); return '/';

			case 'u':
				nextChar();

				auto x = readHexDigits(4);

				if(x >= 0xD800 && x < 0xDC00)
				{
					if(mCharacter != '\\')
						throwException(t, "({}:{}): second surrogate pair character expected", mLine, mCol);

					nextChar();

					if(mCharacter != 'u')
						throwException(t, "({}:{}): second surrogate pair character expected", mLine, mCol);
						
					nextChar();
					
					auto x2 = readHexDigits(4);

					x &= ~0xD800;
					x2 &= ~0xDC00;
					ret = cast(dchar)(0x10000 + ((x << 10) | x2));
				}
				else if(x >= 0xDC00 && x < 0xE000)
					throwException(t, "({}:{}): invalid surrogate pair sequence", mLine, mCol);
				else
					ret = cast(dchar)x;

				break;

			default:
				throwException(t, "({}:{}): Invalid string escape sequence '\\{}'", mLine, mCol, mCharacter);
		}

		return ret;
	}

	private void readStringLiteral()
	{
		auto beginningLine = mLine;
		auto beginningCol = mCol;

		auto buf = StrBuffer(t);

		// Skip opening quote
		nextChar();

		while(true)
		{
			if(isEOF())
				throwException(t, "({}:{}): Unterminated string literal", beginningLine, beginningCol);

			if(mCharacter == '\\')
				buf.addChar(readEscapeSequence(beginningLine, beginningCol));
			else if(mCharacter == '"')
				break;
			else if(mCharacter <= 0x1f)
				throwException(t, "({}:{}): Invalid character in string token", mLine, mCol);
			else
			{
				buf.addChar(mCharacter);
				nextChar();
			}
		}

		// Skip end quote
		nextChar();
		buf.finish();
	}

	private void nextToken()
	{
		while(true)
		{
			mTok.line = mLine;
			mTok.col = mCol;

			switch(mCharacter)
			{
				case '\r', '\n':
					nextLine();
					continue;

				case '\"':
					readStringLiteral();
					mTok.type = Token.String;
					return;

				case '{':
					nextChar();
					mTok.type = Token.LBrace;
					return;

				case '}':
					nextChar();
					mTok.type = Token.RBrace;
					return;

				case '[':
					nextChar();
					mTok.type = Token.LBracket;
					return;

				case ']':
					nextChar();
					mTok.type = Token.RBracket;
					return;

				case ',':
					nextChar();
					mTok.type = Token.Comma;
					return;

				case ':':
					nextChar();
					mTok.type = Token.Colon;
					return;

				case dchar.init:
					mTok.type = Token.EOF;
					return;
					
				case 't':
					if(!mSource[mPosition .. $].startsWith("rue"))
						throwException(t, "({}:{}): true expected", mLine, mCol);

					nextChar();
					nextChar();
					nextChar();
					nextChar();
					mTok.type = Token.True;
					pushBool(t, true);
					return;

				case 'f':
					if(!mSource[mPosition .. $].startsWith("alse"))
						throwException(t, "({}:{}): false expected", mLine, mCol);

					nextChar();
					nextChar();
					nextChar();
					nextChar();
					nextChar();
					mTok.type = Token.False;
					pushBool(t, false);
					return;

				case 'n':
					if(!mSource[mPosition .. $].startsWith("ull"))
						throwException(t, "({}:{}): null expected", mLine, mCol);

					nextChar();
					nextChar();
					nextChar();
					nextChar();
					mTok.type = Token.Null;
					pushNull(t);
					return;

				case '-', '1', '2', '3', '4', '5', '6', '7', '8', '9':
					if(readNumLiteral())
						mTok.type = Token.Int;
					else
						mTok.type = Token.Float;
					return;

				default:
					if(isWhitespace())
					{
						nextChar();
						continue;
					}
					
					throwException(t, "({}:{}): Invalid character '{}'", mLine, mCol, mCharacter);
			}
		}
	}
}

private void parseValue(CrocThread* t, ref Lexer l)
{
	switch(l.type)
	{
		case Token.String:
		case Token.Int:
		case Token.Float:
		case Token.True:
		case Token.False:
		case Token.Null:     l.next(); return;
		case Token.LBrace:   return parseObject(t, l);
		case Token.LBracket: return parseArray(t, l);
		default: throwException(t, "({}:{}): value expected", l.line, l.col);
	}
}

private word parseArray(CrocThread* t, ref Lexer l)
{
	uword length = 8;
	uword idx = 0;
	auto arr = newArray(t, length);

	void parseItem()
	{
		parseValue(t, l);
		
		if(idx >= length)
		{
			length *= 2;
			pushInt(t, length);
			lena(t, arr);
		}

		idxai(t, arr, idx);
		idx++;
	}

	l.expect(Token.LBracket);

	if(l.type != Token.RBracket)
	{
		parseItem();

		while(l.type == Token.Comma)
		{
			l.next();
			parseItem();
		}
	}

	l.expect(Token.RBracket);
	
	pushInt(t, idx);
	lena(t, arr);
	return arr;
}

private void parsePair(CrocThread* t, ref Lexer l)
{
	l.expect(Token.String);
	l.expect(Token.Colon);
	parseValue(t, l);
}

private word parseObject(CrocThread* t, ref Lexer l)
{
	auto tab = newTable(t);
	l.expect(Token.LBrace);

	if(l.type != Token.RBrace)
	{
		parsePair(t, l);
		idxa(t, tab);

		while(l.type == Token.Comma)
		{
			l.next();
			parsePair(t, l);
			idxa(t, tab);
		}
	}

	l.expect(Token.RBrace);
	return tab;
}