
#include <functional>
#include <math.h>
#include <stdarg.h>

#include "croc/api.h"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/json.hpp"
#include "croc/types/base.hpp"
#include "croc/util/array.hpp"
#include "croc/util/utf.hpp"

namespace croc
{
	namespace
	{
	struct Token
	{
		uint32_t type;
		uint32_t line;
		uint32_t col;

		enum
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

			EOF_
		};

		Token() :
			type(),
			line(),
			col()
		{}
	};

	const char* TokenStrings[] =
	{
		"string",
		"integer",
		"float",
		"true",
		"false",
		"null",

		",",
		":",
		"{",
		"}",
		"[",
		"]",

		"<EOF>"
	};

#define IS_EOF() (mCharacter == 0xFFFF)
#define IS_WHITESPACE() ((mCharacter == ' ') || (mCharacter == '\t') || IS_NEWLINE())
#define IS_NEWLINE() ((mCharacter == '\r') || (mCharacter == '\n'))
#define IS_DECIMAL_DIGIT() ((mCharacter >= '0') && (mCharacter <= '9'))
#define IS_HEX_DIGIT()\
	(((mCharacter >= '0') && (mCharacter <= '9')) ||\
	((mCharacter >= 'a') && (mCharacter <= 'f')) ||\
	((mCharacter >= 'A') && (mCharacter <= 'F')))\

	struct JSONLexer
	{
	private:
		CrocThread* t;

		uint32_t mLine;
		uint32_t mCol;
		const uchar* mSourcePtr;
		const uchar* mSourceEnd;
		const uchar* mCharPos;
		crocchar mCharacter;

		Token mTok;

	public:
		JSONLexer(CrocThread* t) :
			t(t),
			mLine(1),
			mCol(0),
			mSourcePtr(),
			mSourceEnd(),
			mCharPos(),
			mCharacter(),
			mTok()
		{}

		void begin(crocstr source)
		{
			mLine = 1;
			mCol = 0;
			mSourcePtr = source.ptr;
			mSourceEnd = source.ptr + source.length;
			nextChar();
			next();
		}

		Token& tok()
		{
			return mTok;
		}

		uint32_t line()
		{
			return mLine;
		}

		uint32_t col()
		{
			return mCol;
		}

		uint32_t type()
		{
			return mTok.type;
		}

		Token expect(uint32_t t)
		{
			if(mTok.type != t)
				expected(TokenStrings[t]);

			auto ret = mTok;

			if(t != Token::EOF_)
				next();

			return ret;
		}

		void expected(const char* message)
		{
			croc_eh_throwStd(t, "SyntaxException", "(%u:%u): '%s' expected; found '%s' instead",
				mTok.line, mTok.col, message, TokenStrings[mTok.type]);
		}

		void next()
		{
			nextToken();
		}

	private:
		uint8_t hexDigitToInt(crocchar c)
		{
			assert((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'));

			if(c >= '0' && c <= '9')
				return cast(uint8_t)(c - '0');
			else if(c >= 'A' && c <= 'F')
				return cast(uint8_t)(c - 'A' + 10);
			else
				return cast(uint8_t)(c - 'a' + 10);
		}

		void nextChar()
		{
			mCol++;

			if(mSourcePtr >= mSourceEnd)
				mCharacter = 0xFFFF;
			else
			{
				mCharPos = mSourcePtr;

				if(decodeUtf8Char(mSourcePtr, mSourceEnd, mCharacter) != UtfError_OK)
					croc_eh_throwStd(t, "LexicalException", "(%u:%u): source is not valid UTF-8", mLine, mCol - 1);
			}
		}

		void nextLine()
		{
			while(IS_NEWLINE() && !IS_EOF())
			{
				auto old = mCharacter;

				nextChar();

				if(IS_NEWLINE() && mCharacter != old)
					nextChar();

				mLine++;
				mCol = 1;
			}
		}

		bool readNumLiteral()
		{
			bool neg = false;

			// sign
			if(mCharacter == '-')
			{
				neg = true;
				nextChar();

				if(!IS_DECIMAL_DIGIT())
					croc_eh_throwStd(t, "LexicalException", "(%u:%u): incomplete number token", mLine, mCol);
			}

			// integral part
			crocint iret = 0;

			if(mCharacter == '0')
				nextChar();
			else
			{
				while(IS_DECIMAL_DIGIT())
				{
					iret = (iret * 10) + (mCharacter - '0');
					nextChar();
				}
			}

			if(IS_EOF() || (mCharacter != '.' && mCharacter != 'e' && mCharacter != 'E'))
			{
				croc_pushInt(t, neg? -iret : iret);
				return true;
			}

			// fraction
			crocfloat fret = iret;

			if(mCharacter == '.')
			{
				nextChar();

				if(!IS_DECIMAL_DIGIT())
					croc_eh_throwStd(t, "LexicalException", "(%u:%u): incomplete number token", mLine, mCol);

				crocfloat frac = 0.0;
				crocfloat mag = 10.0;

				while(IS_DECIMAL_DIGIT())
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

				if(!IS_DECIMAL_DIGIT() && mCharacter != '+' && mCharacter != '-')
					croc_eh_throwStd(t, "LexicalException", "(%u:%u): incomplete number token", mLine, mCol);

				bool negExp = false;

				if(mCharacter == '+')
					nextChar();
				else if(mCharacter == '-')
				{
					negExp = true;
					nextChar();
				}

				if(!IS_DECIMAL_DIGIT())
					croc_eh_throwStd(t, "LexicalException", "(%u:%u): incomplete number token", mLine, mCol);

				crocfloat exp = 0;

				while(IS_DECIMAL_DIGIT())
				{
					exp = (exp * 10) + (mCharacter - '0');
					nextChar();
				}

				fret = fret * powl(10, negExp? -exp : exp);
			}

			croc_pushFloat(t, neg? -fret : fret);
			return false;
		}

		uint32_t readHexDigits(uword num)
		{
			uint32_t ret = 0;

			for(uword i = 0; i < num; i++)
			{
				if(!IS_HEX_DIGIT())
					croc_eh_throwStd(t, "LexicalException", "(%u:%u): Hexadecimal escape digits expected", mLine, mCol);

				ret <<= 4;
				ret |= hexDigitToInt(mCharacter);
				nextChar();
			}

			return ret;
		}

		crocchar readEscapeSequence(uint32_t beginningLine, uint32_t beginningCol)
		{
			assert(mCharacter == '\\');
			nextChar();

			if(IS_EOF())
				croc_eh_throwStd(t, "LexicalException", "(%u:%u): Unterminated string literal",
					beginningLine, beginningCol);

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

				case 'u': {
					nextChar();

					auto x = readHexDigits(4);

					if(x >= 0xD800 && x < 0xDC00)
					{
						if(mCharacter != '\\')
							croc_eh_throwStd(t, "LexicalException", "(%u:%u): second surrogate pair character expected",
								mLine, mCol);

						nextChar();

						if(mCharacter != 'u')
							croc_eh_throwStd(t, "LexicalException", "(%u:%u): second surrogate pair character expected",
								mLine, mCol);

						nextChar();

						auto x2 = readHexDigits(4);

						if(x2 < 0xDC00 || x2 >= 0xE000)
							croc_eh_throwStd(t, "LexicalException", "(%u:%u): invalid surrogate pair sequence",
								mLine, mCol);

						x &= ~0xD800;
						x2 &= ~0xDC00;
						return cast(crocchar)(0x10000 + ((x << 10) | x2));
					}
					else if(x >= 0xDC00 && x < 0xE000)
						croc_eh_throwStd(t, "LexicalException", "(%u:%u): invalid surrogate pair sequence",
							mLine, mCol);
					else
						return cast(crocchar)x;
				}
				default:
					croc_eh_throwStd(t, "LexicalException", "(%u:%u): Invalid string escape sequence", mLine, mCol);
			}

			assert(false);
			return 0; // dummy
		}

		void readStringLiteral()
		{
			auto beginningLine = mLine;
			auto beginningCol = mCol;

			CrocStrBuffer buf;
			croc_ex_buffer_init(t, &buf);

			// Skip opening quote
			nextChar();

			while(true)
			{
				if(IS_EOF())
					croc_eh_throwStd(t, "LexicalException", "(%u:%u): Unterminated string literal",
						beginningLine, beginningCol);

				if(mCharacter == '\\')
					croc_ex_buffer_addChar(&buf, readEscapeSequence(beginningLine, beginningCol));
				else if(mCharacter == '\"')
					break;
				else if(mCharacter <= 0x1f)
					croc_eh_throwStd(t, "LexicalException", "(%u:%u): Invalid character in string token", mLine, mCol);
				else
				{
					croc_ex_buffer_addChar(&buf, mCharacter);
					nextChar();
				}
			}

			// Skip end quote
			nextChar();
			croc_ex_buffer_finish(&buf);
		}

		void nextToken()
		{
			while(true)
			{
				mTok.line = mLine;
				mTok.col = mCol;

				switch(mCharacter)
				{
					case '\r':
					case '\n':
						nextLine();
						continue;

					case '\"':
						readStringLiteral();
						mTok.type = Token::String;
						return;

					case '{':
						nextChar();
						mTok.type = Token::LBrace;
						return;

					case '}':
						nextChar();
						mTok.type = Token::RBrace;
						return;

					case '[':
						nextChar();
						mTok.type = Token::LBracket;
						return;

					case ']':
						nextChar();
						mTok.type = Token::RBracket;
						return;

					case ',':
						nextChar();
						mTok.type = Token::Comma;
						return;

					case ':':
						nextChar();
						mTok.type = Token::Colon;
						return;

					case 0xFFFF:
						mTok.type = Token::EOF_;
						return;

					case 't':
						if(!arrStartsWith(crocstr::n(mCharPos, mSourceEnd - mCharPos), ATODA("rue")))
							// TODO
							croc_eh_throwStd(t, "LexicalException", "(%u:%u): true expected", mLine, mCol);

						nextChar();
						nextChar();
						nextChar();
						nextChar();
						mTok.type = Token::True;
						croc_pushBool(t, true);
						return;

					case 'f':
						if(!arrStartsWith(crocstr::n(mCharPos, mSourceEnd - mCharPos), ATODA("alse")))
							croc_eh_throwStd(t, "LexicalException", "(%u:%u): false expected", mLine, mCol);

						nextChar();
						nextChar();
						nextChar();
						nextChar();
						nextChar();
						mTok.type = Token::False;
						croc_pushBool(t, false);
						return;

					case 'n':
						if(!arrStartsWith(crocstr::n(mCharPos, mSourceEnd - mCharPos), ATODA("ull")))
							croc_eh_throwStd(t, "LexicalException", "(%u:%u): null expected", mLine, mCol);

						nextChar();
						nextChar();
						nextChar();
						nextChar();
						mTok.type = Token::Null;
						croc_pushNull(t);
						return;

					case '-':
					case '0':
					case '1':
					case '2':
					case '3':
					case '4':
					case '5':
					case '6':
					case '7':
					case '8':
					case '9':
						if(readNumLiteral())
							mTok.type = Token::Int;
						else
							mTok.type = Token::Float;
						return;

					default:
						if(IS_WHITESPACE())
						{
							nextChar();
							continue;
						}

						croc_eh_throwStd(t, "LexicalException", "(%u:%u): Invalid character", mLine, mCol);
				}
			}
		}
	};

	word parseArray(CrocThread* t, JSONLexer& l);
	word parseObject(CrocThread* t, JSONLexer& l);

	void parseValue(CrocThread* t, JSONLexer& l)
	{
		switch(l.type())
		{
			case Token::String:
			case Token::Int:
			case Token::Float:
			case Token::True:
			case Token::False:
			case Token::Null:     l.next(); return;
			case Token::LBrace:   parseObject(t, l); return;
			case Token::LBracket: parseArray(t, l); return;
			default: croc_eh_throwStd(t, "SyntaxException", "(%u:%u): value expected", l.line(), l.col());
		}
	}

	word parseArray(CrocThread* t, JSONLexer& l)
	{
		uword length = 8;
		uword idx = 0;
		auto arr = croc_array_new(t, length);

		auto parseItem = [&]()
		{
			parseValue(t, l);

			if(idx >= length)
			{
				length *= 2;
				croc_lenai(t, arr, length);
			}

			croc_idxai(t, arr, idx);
			idx++;
		};

		l.expect(Token::LBracket);

		if(l.type() != Token::RBracket)
		{
			parseItem();

			while(l.type() == Token::Comma)
			{
				l.next();
				parseItem();
			}
		}

		l.expect(Token::RBracket);
		croc_lenai(t, arr, idx);
		return arr;
	}

	void parsePair(CrocThread* t, JSONLexer& l)
	{
		l.expect(Token::String);
		l.expect(Token::Colon);
		parseValue(t, l);
	}

	word parseObject(CrocThread* t, JSONLexer& l)
	{
		auto tab = croc_table_new(t, 8);
		l.expect(Token::LBrace);

		if(l.type() != Token::RBrace)
		{
			parsePair(t, l);
			croc_idxa(t, tab);

			while(l.type() == Token::Comma)
			{
				l.next();
				parsePair(t, l);
				croc_idxa(t, tab);
			}
		}

		l.expect(Token::RBrace);
		return tab;
	}

	struct ToJSON
	{
	private:
		CrocThread* t;
		bool pretty;
		word cycles;
		std::function<void(crocstr)> output;
		std::function<void()> nl;
		word indent;

	public:
		ToJSON(CrocThread* t, bool pretty, word cycles, std::function<void(crocstr)> output, std::function<void()> nl) :
			t(t),
			pretty(pretty),
			cycles(cycles),
			output(output),
			nl(nl),
			indent(0)
		{}

		void outputTable(word tab)
		{
			output(ATODA("{"));

			if(pretty)
				newline(1);

			bool first = true;
			croc_dup(t, tab);
			auto state = croc_foreachBegin(t, 1);

			while(croc_foreachNext(t, state, 2))
			{
				auto k = croc_absIndex(t, -2);
				auto v = k + 1;

				if(!croc_isString(t, k))
					croc_eh_throwStd(t, "ValueError", "All keys in a JSON table must be strings");

				if(first)
					first = false;
				else
				{
					output(ATODA(","));

					if(pretty)
						newline();
				}

				outputValue(k);

				if(pretty)
					output(ATODA(": "));
				else
					output(ATODA(":"));

				outputValue(v);
			}

			croc_foreachEnd(t, state);

			if(pretty)
				newline(-1);

			output(ATODA("}"));
		}

		void outputArray(word arr)
		{
			output(ATODA("["));

			auto l = croc_len(t, arr);

			for(word i = 0; i < l; i++)
			{
				if(i > 0)
				{
					if(pretty)
						output(ATODA(", "));
					else
						output(ATODA(","));
				}

				outputValue(croc_idxi(t, arr, i));
				croc_popTop(t);
			}

			output(ATODA("]"));
		}

	private:
		void fprint(const char* fmt, ...) CROCPRINT(2, 3)
		{
			va_list args;
			va_start(args, fmt);
			croc_vpushFormat(t, fmt, args);
			va_end(args);
			output(getCrocstr(t, -1));
			croc_popTop(t);
		}

		void newline(word dir = 0)
		{
			nl();

			if(dir > 0)
				indent++;
			else if(dir < 0)
				indent--;

			for(word i = 0; i < indent; i++)
				output(ATODA("\t"));
		}

		void outputChar(crocchar c)
		{
			switch(c)
			{
				case '\b': output(ATODA("\\b"));  return;
				case '\f': output(ATODA("\\f"));  return;
				case '\n': output(ATODA("\\n"));  return;
				case '\r': output(ATODA("\\r"));  return;
				case '\t': output(ATODA("\\t"));  return;
				case '"':  output(ATODA("\\\"")); return;
				case '\\': output(ATODA("\\\\")); return;
				case '/':  output(ATODA("\\/"));  return;

				default:
					if(c > 0x7f)
						fprint("\\u%4x", cast(int)c);
					else
					{
						uchar buf[4];
						mcrocstr ret;

						if(encodeUtf8Char(mcrocstr::n(buf, 4), c, ret) != UtfError_OK)
							croc_eh_throwStd(t, "ValueError", "Invalid character U+%6X", cast(uint32_t)c);

						output(ret);
					}

					return;
			}
		}

		void outputValue(word idx)
		{
			switch(croc_type(t, idx))
			{
				case CrocType_Null:
					output(ATODA("null"));
					break;

				case CrocType_Bool:
					output(croc_getBool(t, idx) ? ATODA("true") : ATODA("false"));
					break;

				case CrocType_Int:
					fprint("%" CROC_INTEGER_FORMAT, croc_getInt(t, idx));
					break;

				case CrocType_Float:
					fprint("%f", croc_getFloat(t, idx));
					break;

				case CrocType_String:
					output(ATODA("\""));

					for(auto c: dcharsOf(getCrocstr(t, idx)))
						outputChar(c);

					output(ATODA("\""));
					break;

				case CrocType_Table:
					if(croc_in(t, idx, cycles))
						croc_eh_throwStd(t, "ValueError", "Table is cyclically referenced");

					croc_dup(t, idx);
					croc_pushBool(t, true);
					croc_idxa(t, cycles);
					outputTable(idx);
					croc_dup(t, idx);
					croc_pushNull(t);
					croc_idxa(t, cycles);
					break;

				case CrocType_Array:
					if(croc_in(t, idx, cycles))
						croc_eh_throwStd(t, "ValueError", "Array is cyclically referenced");

					croc_dup(t, idx);
					croc_pushBool(t, true);
					croc_idxa(t, cycles);
					outputArray(idx);
					croc_dup(t, idx);
					croc_pushNull(t);
					croc_idxa(t, cycles);
					break;

				default:
					croc_pushTypeString(t, idx);
					croc_eh_throwStd(t, "TypeError", "Type '%s' is not a valid type for conversion to JSON",
						croc_getString(t, -1));
			}
		}
	};
	}

	word_t fromJSON(CrocThread* t, crocstr source)
	{
		JSONLexer l(t);
		l.begin(source);
		word ret = 0;

		if(l.type() == Token::LBrace)
			ret = parseObject(t, l);
		else if(l.type() == Token::LBracket)
			ret = parseArray(t, l);
		else
			croc_eh_throwStd(t, "ValueError", "JSON must have an object or an array as its top-level value %s",
				TokenStrings[l.type()]);

		l.expect(Token::EOF_);
		return ret;
	}

	void toJSON(CrocThread* t, word_t root, bool pretty, std::function<void(crocstr)> output, std::function<void()> nl)
	{
		root = croc_absIndex(t, root);
		auto cycles = croc_table_new(t, 0);
		ToJSON j(t, pretty, cycles, output, nl);

		auto slot = croc_pushNull(t);
		auto failed = tryCode(Thread::from(t), slot, [&]
		{
			if(croc_isArray(t, root))
				j.outputArray(root);
			else if(croc_isTable(t, root))
				j.outputTable(root);
			else
			{
				croc_pushTypeString(t, root);
				croc_eh_throwStd(t, "TypeError", "Root element must be either a table or an array, not a '%s'",
					croc_getString(t, -1));
			}
		});

		croc_table_clear(t, cycles);

		if(failed)
			croc_eh_rethrow(t);

		croc_pop(t, 2); // dummy eh slot and cycles
	}
}