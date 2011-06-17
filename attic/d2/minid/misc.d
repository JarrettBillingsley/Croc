/******************************************************************************
This holds miscellaneous functionality used in the internal library and also
as part of the extended API.  There are no public functions in here.

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

module minid.misc;

import std.c.stdlib;
import std.format;
import std.math;
import std.string;
import std.uni;
import std.utf;

import minid.alloc;
import minid.ex;
import minid.interpreter;
import minid.types;
import minid.utils;

package void formatImpl(MDThread* t, uword numParams, void delegate(string) sink)
{
	void shim(...)
	{
		doFormat((dchar c)
		{
			char[4] buf;
			sink(cast(string)buf[0 .. encode(buf, c)]);
		}, _arguments, _argptr);
	}

	void output(string fmt, uword param, bool isRaw)
	{
		if(isRaw)
		{
			auto tmp = (cast(char*)alloca(fmt.length + 1))[0 .. fmt.length + 1];
			tmp[0 .. fmt.length] = fmt[];
			tmp[$ - 1] = 's';
			pushToString(t, param, true);
			shim(tmp, getString(t, -1));
			pop(t);
		}
		else
		{
			switch(type(t, param))
			{
				case MDValue.Type.Int:   shim(fmt, getInt(t, param));   break;
				case MDValue.Type.Float: shim(fmt, getFloat(t, param)); break;
				case MDValue.Type.Char:  shim(fmt, getChar(t, param));  break;

				default:
					pushToString(t, param);
					shim(fmt, getString(t, -1));
					pop(t);
					break;
			}
		}
	}

	auto formatStr = checkStringParam(t, 1);
	uword autoIndex = 2;
	uword begin = 0;

	while(begin < formatStr.length)
	{
		auto tmppos = formatStr[begin .. $].indexOf('%');
		auto fmtBegin = tmppos == -1 ? formatStr.length : tmppos + begin;

		// output anything outside the {}
		if(fmtBegin > begin)
		{
			sink(formatStr[begin .. fmtBegin]);
			begin = fmtBegin;
		}

		// did we run out of string?
		if(fmtBegin == formatStr.length)
			break;
			
		// is it an incomplete format spec?
		if(fmtBegin + 1 == formatStr.length)
		{
			sink("{incomplete format spec}");
			break;
		}

		// Check if it's an escaped {
		if(formatStr[fmtBegin + 1] == '%')
		{
			begin = fmtBegin + 2;
			sink("%");
			continue;
		}

		// Stupid C-style format strings.. have to parse them to find the end :P
		// parse flags
		uword fmtEnd = fmtBegin + 1;

		for(; fmtEnd < formatStr.length; fmtEnd++)
		{
			switch(formatStr[fmtEnd])
			{
				case '-', '+', '0', ' ': continue;
				default: break;
			}
			break;
		}

		// parse width
		for(; fmtEnd < formatStr.length; fmtEnd++)
		{
			switch(formatStr[fmtEnd])
			{
				case '0': .. case '9': continue;
				default: break;
			}
			break;
		}

		// parse precision
		if(fmtEnd < formatStr.length && formatStr[fmtEnd] == '.')
		{
			fmtEnd++;

			for(; fmtEnd < formatStr.length; fmtEnd++)
			{
				switch(formatStr[fmtEnd])
				{
					case '0': .. case '9': continue;
					default: break;
				}
				break;
			}
		}

		if(fmtEnd >= formatStr.length)
		{
			sink("{incomplete format spec}");
			break;
		}

		auto fmtSpec = formatStr[fmtBegin .. fmtEnd + 1];
		bool isRaw = false;

		if(fmtSpec[$ - 1] == 'r')
		{
			isRaw = true;
			fmtSpec = fmtSpec[0 .. $ - 1];
		}

		// check for parameter index and remove it if there
		// TODO: C-style param selectors (ughhh)
		auto index = autoIndex;

// 		if(isdigit(fmtSpec[0]))
// 		{
// 			uword j = 0;
//
// 			for(; j < fmtSpec.length && isdigit(fmtSpec[j]); j++)
// 			{}
//
// 			index = Integer.atoi(fmtSpec[0 .. j]) + 2;
// 			fmtSpec = fmtSpec[j .. $];
// 		}
// 		else
			autoIndex++;

		// output it (or see if it's an invalid index)
		if(index > numParams)
			sink("{invalid index}");
		else
			output(fmtSpec, index, isRaw);

		begin = fmtEnd + 1;
	}
}

struct JSON
{
static:
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

		public static const string[] strings =
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
		private MDThread* t;

		private uword mLine;
		private uword mCol;
		private string mSource;

		private uword mPosition;
		private dchar mCharacter;

		private Token mTok;

		public void begin(MDThread* t, string source)
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
	
		public void expected(string message)
		{
			throwException(t, "(%s:%s): '%s' expected; found '%s' instead", mTok.line, mTok.col, message, Token.strings[mTok.type]);
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

			if(isUniUpper(c))
				return cast(ubyte)(c - 'A' + 10);
			else
				return cast(ubyte)(c - 'a' + 10);
		}
	
		private dchar readChar()
		{
			if(mPosition >= mSource.length)
				return dchar.init;
			else
				return decode(mSource, mPosition);
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
	
		private bool convertInt(dchar[] str, out mdint ret)
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
					throwException(t, "(%s:%s): incomplete number token", mLine, mCol);
			}
	
			// integral part
			mdint iret = 0;

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

			if(isEOF() || ".eE"d.indexOf(mCharacter) == -1)
			{
				pushInt(t, neg? -iret : iret);
				return true;
			}

			// fraction
			mdfloat fret = iret;
	
			if(mCharacter == '.')
			{
				nextChar();
	
				if(!isDecimalDigit())
					throwException(t, "(%s:%s): incomplete number token", mLine, mCol);
	
				mdfloat frac = 0.0;
				mdfloat mag = 10.0;
	
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
					throwException(t, "(%s:%s): incomplete number token", mLine, mCol);
	
				bool negExp = false;
	
				if(mCharacter == '+')
					nextChar();
				else if(mCharacter == '-')
				{
					negExp = true;
					nextChar();
				}
	
				if(!isDecimalDigit())
					throwException(t, "(%s:%s): incomplete number token", mLine, mCol);
	
				mdfloat exp = 0;
	
				while(isDecimalDigit())
				{
					exp = (exp * 10) + (mCharacter - '0');
					nextChar();
				}

				fret = fret * pow(10.0, negExp? -exp : exp);
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
						throwException(t, "(%s:%s): Hexadecimal escape digits expected", mLine, mCol);
	
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
				throwException(t, "(%s:%s): Unterminated string literal", beginningLine, beginningCol);
	
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
							throwException(t, "(%s:%s): second surrogate pair character expected", mLine, mCol);
	
						nextChar();
	
						if(mCharacter != 'u')
							throwException(t, "(%s:%s): second surrogate pair character expected", mLine, mCol);
							
						nextChar();
						
						auto x2 = readHexDigits(4);
	
						x &= ~0xD800;
						x2 &= ~0xDC00;
						ret = cast(dchar)(0x10000 + ((x << 10) | x2));
					}
					else if(x >= 0xDC00 && x < 0xE000)
						throwException(t, "(%s:%s): invalid surrogate pair sequence", mLine, mCol);
					else
						ret = cast(dchar)x;

					break;

				default:
					throwException(t, "(%s:%s): Invalid string escape sequence '\\%s'", mLine, mCol, mCharacter);
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
					throwException(t, "(%s:%s): Unterminated string literal", beginningLine, beginningCol);

				if(mCharacter == '\\')
					buf.addChar(readEscapeSequence(beginningLine, beginningCol));
				else if(mCharacter == '"')
					break;
				else if(mCharacter <= 0x1f)
					throwException(t, "(%s:%s): Invalid character in string token", mLine, mCol);
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
							throwException(t, "(%s:%s): true expected", mLine, mCol);
	
						nextChar();
						nextChar();
						nextChar();
						nextChar();
						mTok.type = Token.True;
						pushBool(t, true);
						return;

					case 'f':
						if(!mSource[mPosition .. $].startsWith("alse"))
							throwException(t, "(%s:%s): false expected", mLine, mCol);

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
							throwException(t, "(%s:%s): null expected", mLine, mCol);

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
						
						throwException(t, "(%s:%s): Invalid character '%s'", mLine, mCol, mCharacter);
				}
			}
		}
	}
	
	private void parseValue(MDThread* t, ref Lexer l)
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
			default: throwException(t, "(%s:%s): value expected", l.line, l.col);
		}
	}

	private word parseArray(MDThread* t, ref Lexer l)
	{
		auto arr = newArray(t, 0);
		l.expect(Token.LBracket);
		
		if(l.type != Token.RBracket)
		{
			parseValue(t, l);
			dup(t, arr);
			pushNull(t);
			rotate(t, 3, 2);
			methodCall(t, -3, "append", 0);

			while(l.type == Token.Comma)
			{
				l.next();
				parseValue(t, l);
				dup(t, arr);
				pushNull(t);
				rotate(t, 3, 2);
				methodCall(t, -3, "append", 0);
			}
		}

		l.expect(Token.RBracket);
		return arr;
	}

	private void parsePair(MDThread* t, ref Lexer l)
	{
		l.expect(Token.String);
		l.expect(Token.Colon);
		parseValue(t, l);
	}

	private word parseObject(MDThread* t, ref Lexer l)
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

	package word load(MDThread* t, string source)
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
	package void save(MDThread* t, word root, bool pretty, void delegate(string) printer)
	{
		root = absIndex(t, root);
		auto cycles = newTable(t);

		word indent = 0;

		void newline(word dir = 0)
		{
			printer(.newline);
	
			if(dir > 0)
				indent++;
			else if(dir < 0)
				indent--;

			for(word i = indent; i > 0; i--)
				printer("\t");
		}

		void delegate(word) outputValue;

		void outputTable(word tab)
		{
			printer("{");
	
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
					printer(",");
	
					if(pretty)
						newline();
				}
	
				outputValue(k);
	
				if(pretty)
					printer(": ");
				else
					printer(":");
	
				outputValue(v);
			}
	
			if(pretty)
				newline(-1);
	
			printer("}");
		}
	
		void outputArray(word arr)
		{
			printer("[");
	
			auto l = len(t, arr);
	
			for(word i = 0; i < l; i++)
			{
				if(i > 0)
				{
					if(pretty)
						printer(", ");
					else
						printer(",");
				}
	
				outputValue(idxi(t, arr, i));
				pop(t);
			}
	
			printer("]");
		}
		
		void outputChar(dchar c)
		{
			switch(c)
			{
				case '\b': printer("\\b"); return;
				case '\f': printer("\\f"); return;
				case '\n': printer("\\n"); return;
				case '\r': printer("\\r"); return;
				case '\t': printer("\\t"); return;
	
				case '"', '\\', '/':
					printer("\\");
					char[4] buf = void;
					printer(cast(string)buf[0 .. encode(buf, c)]);
					return;

				default:
					if(c > 0x7f)
						printer(format("\\u%4x", cast(int)c)); // TODO: make this not allocate memory
					else
					{
						char[4] buf = void;
						printer(cast(string)buf[0 .. encode(buf, c)]);
					}

					return;
			}
		}
	
		void _outputValue(word idx)
		{
			switch(type(t, idx))
			{
				case MDValue.Type.Null:
					printer("null");
					break;
	
				case MDValue.Type.Bool:
					printer(getBool(t, idx) ? "true" : "false");
					break;
	
				case MDValue.Type.Int:
					printer(format("%s", getInt(t, idx))); // TODO: make this not allocate memory
					break;

				case MDValue.Type.Float:
					printer(format("%s", getFloat(t, idx))); // TODO: make this not allocate memory
					break;
	
				case MDValue.Type.Char:
					printer("\"");
					outputChar(getChar(t, idx));
					printer("\"");
					break;

				case MDValue.Type.String:
					printer("\"");

					foreach(dchar c; getString(t, idx))
						outputChar(c);

					printer("\"");
					break;

				case MDValue.Type.Table:
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
	
				case MDValue.Type.Array:
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
					throwException(t, "Type '%s' is not a valid type for conversion to JSON", getString(t, -1));
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
			throwException(t, "Root element must be either a table or an array, not a '%s'", getString(t, -1));
		}
	
		pop(t);
	}
}