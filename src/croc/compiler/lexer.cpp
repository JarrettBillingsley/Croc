
#include <limits>
#include <stdlib.h>

#include "croc/compiler/lexer.hpp"
#include "croc/compiler/types.hpp"

namespace croc
{
	crocstr Token::KeywordStrings[] =
	{
#define POOP(_, str) ATODA(str),
		KEYWORD_LIST(POOP)
#undef POOP
	};

	const char* Token::Strings[] =
	{
#define POOP(_, str) str,
		TOKEN_LIST(POOP)
#undef POOP
	};

#define IS_EOF() ((mCharacter == '\0') || (mCharacter == 0xFFFF))
#define IS_EOL() (IS_NEWLINE() || IS_EOF())
#define IS_NEWLINE() ((mCharacter == '\r') || (mCharacter == '\n'))
#define IS_BINARYDIGIT() ((mCharacter == '0') || (mCharacter == '1'))
#define IS_DECIMALDIGIT() ((mCharacter >= '0') && (mCharacter <= '9'))
#define IS_ALPHA() (((mCharacter >= 'a') && (mCharacter <= 'z')) || ((mCharacter >= 'A') && (mCharacter <= 'Z')))
#define IS_IDENTSTART() (IS_ALPHA() || mCharacter == '_')
#define IS_IDENTCONT() (IS_IDENTSTART() || IS_DECIMALDIGIT() || mCharacter == '!')

#define IS_WHITESPACE()\
	((mCharacter == ' ') ||\
	(mCharacter == '\t') ||\
	(mCharacter == '\v') ||\
	(mCharacter == '\u000C') ||\
	IS_EOL())

#define IS_HEXDIGIT()\
	(((mCharacter >= '0') && (mCharacter <= '9')) ||\
	((mCharacter >= 'a') && (mCharacter <= 'f')) ||\
	((mCharacter >= 'A') && (mCharacter <= 'F')))

#define HEXDIGIT_TO_INT(c)\
	(assert((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')),\
	(c >= '0' && c <= '9') ?\
		(cast(uword)(c - '0')) :\
	(c >= 'A' && c <= 'F') ?\
		(cast(uword)(c - 'A' + 10))\
	:\
		(cast(uword)(c - 'a' + 10)))

	// =================================================================================================================
	// Public
	// =================================================================================================================

	void Lexer::begin(crocstr name, crocstr source)
	{
		mLoc.file = name;
		mLoc.line = 1;
		mLoc.col = 0;
		mSource = source;
		mSourceEnd = source.ptr + mSource.length;
		mSourcePtr = source.ptr;

		mHaveLookahead = false;
		mNewlineSinceLastTok = false;
		mHavePeekTok = false;

		nextChar();

		if(mSource.length >= 2 && mSource.slice(0, 2) == ATODA("#!"))
			while(!IS_EOL())
				nextChar();

		next();
	}

	Token Lexer::expect(uword t)
	{
		if(mTok.type != t)
			expected(Token::Strings[t]);

		auto ret = mTok;

		if(t != Token::EOF_)
			next();

		return ret;
	}

	void Lexer::expected(const char* message)
	{
		if(mTok.type == Token::EOF_)
			mCompiler.eofException(mTok.loc, "'%s' expected; found '%s' instead", message, Token::Strings[mTok.type]);
		else
			mCompiler.synException(mTok.loc, "'%s' expected; found '%s' instead", message, Token::Strings[mTok.type]);
	}

	bool Lexer::isStatementTerm()
	{
		return mNewlineSinceLastTok ||
			mTok.type == Token::EOF_ ||
			mTok.type == Token::Semicolon ||
			mTok.type == Token::RBrace ||
			mTok.type == Token::RParen ||
			mTok.type == Token::RBracket;
	}

	void Lexer::statementTerm()
	{
		if(mNewlineSinceLastTok)
			return;

		switch(mTok.type)
		{
			case Token::EOF_:
			case Token::RBrace:
			case Token::RParen:
			case Token::RBracket:
				return;

			case Token::Semicolon:
				next();
				return;

			default:
				mCompiler.synException(mLoc, "Statement terminator expected, not '%s'", Token::Strings[mTok.type]);
		}
	}

	Token& Lexer::peek()
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

	void Lexer::next()
	{
		if(mHavePeekTok)
		{
			mHavePeekTok = false;
			mTok = mPeekTok;
		}
		else
			nextToken();
	}

	const uchar* Lexer::beginCapture()
	{
		mCaptureEnd = mTok.startChar;
		return mCaptureEnd;
	}

	crocstr Lexer::endCapture(const uchar* captureStart)
	{
		//XXX return mCompiler.newString(strTrimWS(crocstr::n(captureStart, mCaptureEnd - captureStart)));
		return mCompiler.newString(crocstr::n(captureStart, mCaptureEnd - captureStart));
	}

	// =================================================================================================================
	// Private
	// =================================================================================================================

	namespace
	{
	extern "C"
	{
		int compareFunc(const void* a, const void* b)
		{
			return (*cast(crocstr*)a).cmp(*cast(crocstr*)b);
		}
	}
	}

	int Lexer::lookupKeyword(crocstr str)
	{
		auto ptr = cast(crocstr*)bsearch(cast(const void*)&str, cast(const void*)Token::KeywordStrings,
			Token::NUM_KEYWORDS, sizeof(crocstr), &compareFunc);

		if(ptr)
			return ptr - Token::KeywordStrings;
		else
			return -1;
	}

	crocchar Lexer::readChar(const uchar*& pos)
	{
		if(mSourcePtr >= mSourceEnd)
		{
			pos = mSourceEnd;
			return 0xFFFF;
		}
		else
		{
			pos = mSourcePtr;
			return fastDecodeUtf8Char(mSourcePtr);
		}
	}

	crocchar Lexer::lookaheadChar()
	{
		assert(!mHaveLookahead);
		mLookaheadCharacter = readChar(mLookaheadCharPos);
		mHaveLookahead = true;
		return mLookaheadCharacter;
	}

	void Lexer::nextChar()
	{
		mLoc.col++;

		if(mHaveLookahead)
		{
			mCharacter = mLookaheadCharacter;
			mCharPos = mLookaheadCharPos;
			mHaveLookahead = false;
		}
		else
		{
			mCharacter = readChar(mCharPos);
		}
	}

	void Lexer::nextLine(bool readMultiple)
	{
		while(IS_NEWLINE() && !IS_EOF())
		{
			auto old = mCharacter;

			nextChar();

			// TODO: this accepts \n\r which... is harmless I guess but isn't technically correct :P
			if(IS_NEWLINE() && mCharacter != old)
				nextChar();

			if(mHadLinePragma)
			{
				mHadLinePragma = false;
				mLoc.line = mLinePragmaLine;

				if(mLinePragmaFile.length != 0)
				{
					mLoc.file = mLinePragmaFile;
					mLinePragmaFile = crocstr();
				}
			}
			else
				mLoc.line++;

			mLoc.col = 1;

			if(!readMultiple)
				return;
		}
	}

	// This expects the input string to consist entirely of digits within the valid range of radix
	bool Lexer::convertInt(crocstr str, crocint& ret, uword radix)
	{
		ret = 0;

		for(auto c: str)
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

			assert(cast(uword)c < radix);

			crocint newValue = ret * radix + c;

			if(newValue < ret)
				return false;

			ret = newValue;
		}

		return true;
	}

	bool Lexer::convertUInt(crocstr str, crocint& ret, uword radix)
	{
		ret = 0;

		uint64_t r = 0;

		for(auto c: str)
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

			assert(cast(uword)c < radix);

			auto newValue = r * radix + c;

			if(newValue < r)
				return false;

			r = newValue;
		}

		ret = cast(crocint)r;
		return true;
	}

	bool Lexer::readNumLiteral(bool prependPoint, crocfloat& fret, crocint& iret)
	{
		auto beginning = mLoc;
		uchar buf[128];
		uword i = 0;

		auto add = [&](crocchar c)
		{
			if(i >= 128)
				mCompiler.lexException(beginning, "Number literal too long");

			assert(c < 128);

			buf[i++] = c;
		};

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
					case 'B': {
						nextChar();

						if(!IS_BINARYDIGIT() && mCharacter != '_')
							mCompiler.lexException(mLoc, "Binary digit expected, not '%c'", mCharacter);

						while(IS_BINARYDIGIT() || mCharacter == '_')
						{
							if(mCharacter != '_')
								add(mCharacter);

							nextChar();
						}

						if(!convertUInt(crocstr::n(buf, i), iret, 2))
							mCompiler.lexException(beginning, "Binary integer literal overflow");

						return true;
					}
					case 'x':
					case 'X': {
						nextChar();

						if(!IS_HEXDIGIT() && mCharacter != '_')
							mCompiler.lexException(mLoc, "Hexadecimal digit expected, not '%c'", mCharacter);

						while(IS_HEXDIGIT() || mCharacter == '_')
						{
							if(mCharacter != '_')
								add(mCharacter);

							nextChar();
						}

						if(!convertUInt(crocstr::n(buf, i), iret, 16))
							mCompiler.lexException(beginning, "Hexadecimal integer literal overflow");

						return true;
					}
					default:
						add('0');
						break;
				}
			}
		}

		while(!hasPoint)
		{
			if(IS_DECIMALDIGIT())
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

					if(IS_DECIMALDIGIT())
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
			if(IS_DECIMALDIGIT())
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

				if(!IS_DECIMALDIGIT() && mCharacter != '_')
				{
					add(0);
					mCompiler.lexException(mLoc, "Exponent value expected in float literal '%s'", buf);
				}

				while(IS_DECIMALDIGIT() || mCharacter == '_')
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
			if(!convertInt(crocstr::n(buf, i), iret, 10))
				mCompiler.lexException(beginning, "Decimal integer literal overflow");

			return true;
		}
		else
		{
			add(0);
			char* check;
			fret = strtod(cast(const char*)buf, &check);

			if(cast(uchar*)check != (buf + i - 1)) // -1 since i was incremented after adding the trailing \0
				mCompiler.lexException(beginning, "Invalid floating point literal");

			return false;
		}
	}

	uint32_t Lexer::readHexDigits(uword num)
	{
		uint32_t ret = 0;

		for(uword i = 0; i < num; i++)
		{
			if(!IS_HEXDIGIT())
				mCompiler.lexException(mLoc, "Hexadecimal escape digits expected");

			ret <<= 4;
			ret |= HEXDIGIT_TO_INT(mCharacter);
			nextChar();
		}

		return ret;
	}

	crocchar Lexer::readEscapeSequence(CompileLoc beginning)
	{
		crocchar ret;

		assert(mCharacter == '\\');

		nextChar();

		if(IS_EOF())
			mCompiler.eofException(beginning, "Unterminated string literal");

		switch(mCharacter)
		{
			case 'n':  nextChar(); return '\n';
			case 'r':  nextChar(); return '\r';
			case 't':  nextChar(); return '\t';
			case '\\': nextChar(); return '\\';
			case '\"': nextChar(); return '\"';
			case '\'': nextChar(); return '\'';

			case 'x': {
				nextChar();

				auto x = readHexDigits(2);

				if(x > 0x7F)
					mCompiler.lexException(mLoc, "Hexadecimal escape sequence too large");

				ret = cast(crocchar)x;
				break;
			}
			case 'u': {
				nextChar();

				auto x = readHexDigits(4);

				if(x == 0xFFFE || x == 0xFFFF)
					mCompiler.lexException(mLoc, "Unicode escape '\\u%.4x' is illegal", x);

				ret = cast(crocchar)x;
				break;
			}
			case 'U': {
				nextChar();

				auto x = readHexDigits(8);

				if(x == 0xFFFE || x == 0xFFFF)
					mCompiler.lexException(mLoc, "Unicode escape '\\U%.8x' is illegal", x);

				if(!isValidChar(cast(crocchar)x))
					mCompiler.lexException(mLoc, "Unicode escape '\\U%.8x' too large", x);

				ret = cast(crocchar)x;
				break;
			}
			default:
				if(!IS_DECIMALDIGIT())
					mCompiler.lexException(mLoc, "Invalid string escape sequence '\\%c'", mCharacter);

				// Decimal char
				int numch = 0;
				int c = 0;

				do
				{
					c = 10 * c + (mCharacter - '0');
					nextChar();
				} while(++numch < 3 && IS_DECIMALDIGIT());

				if(c > 0x7F)
					mCompiler.lexException(mLoc, "Numeric escape sequence too large");

				ret = cast(crocchar)c;
				break;
		}

		return ret;
	}

	crocstr Lexer::readStringLiteral(bool escape)
	{
		auto beginning = mLoc;

		List<uchar, 64> buf(mCompiler);
		auto delimiter = mCharacter;
		assert(delimiter < 0x7f);
		uchar utfbuf[4];
		auto tmp = ustring();

		// Skip opening quote
		nextChar();

		while(true)
		{
			if(IS_EOF())
				mCompiler.eofException(beginning, "Unterminated string literal");

			switch(mCharacter)
			{
				case '\r':
				case '\n':
					buf.add('\n');
					nextLine(false);
					continue;

				case '\\': {
					if(!escape)
						goto _default;

					auto loc = mLoc;

					if(encodeUtf8Char(ustring::n(utfbuf, 4), readEscapeSequence(beginning), tmp) != UtfError_OK)
						mCompiler.lexException(loc, "Invalid escape sequence");

					buf.add(tmp);
					continue;
				}
				default:
				_default:
					if(!escape && mCharacter == delimiter)
						break;
					else
					{
						if(escape && mCharacter == delimiter)
							break;

						auto loc = mLoc;

						if(encodeUtf8Char(ustring::n(utfbuf, 4), mCharacter, tmp) != UtfError_OK)
							mCompiler.lexException(loc, "Invalid character");

						buf.add(tmp);
						nextChar();
					}
					continue;
			}

			break;
		}

		// Skip end quote
		nextChar();
		return mCompiler.newString(buf.toArrayView());
	}

	uword Lexer::readVerbatimOpening(CompileLoc beginning)
	{
		uword len = 0;

		while(!IS_EOF() && mCharacter == '=')
		{
			len++;
			nextChar();
		}

		if(len > 0)
		{
			if(IS_EOF() || mCharacter != '[')
				mCompiler.lexException(beginning, "Invalid verbatim string opening sequence");

			nextChar();
		}

		return len;
	}

	crocstr Lexer::readVerbatimString(CompileLoc beginning, uword equalLen)
	{
		if(IS_NEWLINE())
			nextLine(false);

		List<uchar, 256> buf(mCompiler);
		uchar utfbuf[4];
		auto tmp = ustring();

		while(true)
		{
			if(IS_EOF())
				mCompiler.eofException(beginning, "Unterminated string literal");

			switch(mCharacter)
			{
				case '\r':
				case '\n':
					buf.add('\n');
					nextLine(false);
					continue;

				case ']': {
					auto seqBegin = mLoc;
					// Tentatively add characters until we determine whether or not this is a closing sequence
					buf.add(']');
					nextChar();

					if(IS_EOF())
						mCompiler.eofException(seqBegin, "Invalid verbatim string closing sequence");

					uword len = 0;

					while(!IS_EOF() && mCharacter == '=')
					{
						buf.add('=');
						len++;
						nextChar();
					}

					if(len > 0)
					{
						if(IS_EOF())
							mCompiler.eofException(seqBegin, "Invalid verbatim string closing sequence");
						else if(len == equalLen && mCharacter == ']')
						{
							buf.length(buf.length() - (equalLen + 1)); // get rid of the tentative characters
							break;
						}
					}

					// Wasn't a closing sequence, oh well
					continue;
				}
				default: {
					auto loc = mLoc;

					if(encodeUtf8Char(ustring::n(utfbuf, 4), mCharacter, tmp) != UtfError_OK)
						mCompiler.lexException(loc, "Invalid character");

					buf.add(tmp);
					nextChar();
					continue;
				}
			}

			break;
		}

		nextChar();
		return mCompiler.newString(buf.toArrayView());
	}

	void Lexer::addComment(crocstr str, CompileLoc location)
	{
		auto derp = [&](crocstr& existing)
		{
			if(existing.length == 0)
				existing = str;
			else
				mCompiler.lexException(location,
					"Cannot have multiple doc comments in a row; merge them into one comment");
		};

		if(mTokSinceLastNewline)
		{
			derp(mTok.postComment);
			mTok.postCommentLoc = location;
		}
		else
		{
			derp(mTok.preComment);
			mTok.preCommentLoc = location;
		}
	}

	void Lexer::readLineComment()
	{
		if(mCompiler.docComments() && mCharacter == '/')
		{
			nextChar();

			auto loc = mLoc;

			// eat any extra slashes after the opening triple slash
			while(mCharacter == '/')
				nextChar();

			// eat whitespace too
			while(IS_WHITESPACE() && !IS_EOL())
				nextChar();

			List<uchar, 64> buf(mCompiler);

			while(!IS_EOL())
			{
				buf.add(mCharacter);
				nextChar();
			}

			buf.add('\n');
			addComment(mCompiler.newString(buf.toArrayView()), loc);
		}
		else if(mCharacter == '#')
		{
			nextChar();
			if(mCharacter != 'l') goto _regularComment; nextChar();
			if(mCharacter != 'i') goto _regularComment; nextChar();
			if(mCharacter != 'n') goto _regularComment; nextChar();
			if(mCharacter != 'e') goto _regularComment; nextChar();
			if(mCharacter != ' ' && mCharacter != '\t') goto _regularComment;

			// at this point we're assuming we've got an actual line pragma :P

			while(mCharacter == ' ' || mCharacter == '\t')
				nextChar();

			if(!IS_DECIMALDIGIT())
				mCompiler.lexException(mLoc, "Line number expected");

			List<uchar, 16> lineBuf(mCompiler);
			auto lineNumLoc = mLoc;

			while(IS_DECIMALDIGIT() || mCharacter == '_')
			{
				if(mCharacter != '_')
					lineBuf.add(mCharacter);

				nextChar();
			}

			crocint lineNum;
			if(!convertInt(lineBuf.toArrayView(), lineNum, 10))
				mCompiler.lexException(lineNumLoc, "Line number overflow");

			if(lineNum < 1 || cast(uword)lineNum > std::numeric_limits<uword>::max())
				mCompiler.lexException(lineNumLoc, "Invalid line number");

			mLinePragmaLine = cast(uword)lineNum;

			if(!IS_EOL())
			{
				if(mCharacter != ' ' && mCharacter != '\t')
					mCompiler.lexException(mLoc, "Filename expected");

				while(mCharacter == ' ' || mCharacter == '\t')
					nextChar();

				if(mCharacter != '"')
					mCompiler.lexException(mLoc, "Filename expected");

				auto fileNameLoc = mLoc;
				nextChar();

				List<uchar, 32> fileBuf(mCompiler);

				while(mCharacter != '"')
				{
					if(IS_EOL())
						mCompiler.lexException(mLoc, "Unterminated line pragma filename");

					fileBuf.add(mCharacter);
					nextChar();
				}

				if(fileBuf.length() == 0)
					mCompiler.lexException(fileNameLoc, "Filename cannot be empty");

				nextChar(); // skip closing quote

				if(!IS_EOL())
					mCompiler.lexException(mLoc, "End-of-line expected immediately after line pragma");

				mLinePragmaFile = mCompiler.newString(fileBuf.toArrayView());
			}

			mHadLinePragma = true;
		}
		else
		{
		_regularComment:
			while(!IS_EOL())
				nextChar();
		}
	}

	void Lexer::readBlockComment()
	{
		if(mCompiler.docComments() && mCharacter == '*')
		{
			nextChar();

			// eat any extra asterisks after opening
			while(mCharacter == '*')
				nextChar();

			// eat whitespace too
			while(IS_WHITESPACE() && !IS_EOL())
				nextChar();

			auto loc = mLoc;

			List<uchar, 64> buf(mCompiler);
			uword nesting = 1;

			auto trimTrailingWS = [&]()
			{
				while(buf.length() > 0 && (buf[buf.length() - 1] == ' ' || buf[buf.length() - 1] == '\t'))
					buf.length(buf.length() - 1);
			};

			while(true)
			{
				switch(mCharacter)
				{
					case '/':
						buf.add('/');
						nextChar();

						if(mCharacter == '*')
						{
							buf.add('*');
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
								goto _breakCommentLoop;

							buf.add('*');
							buf.add('/');
						}
						else
							buf.add('*');
						continue;

					case '\r':
					case '\n':
						nextLine(false);
						trimTrailingWS();
						buf.add('\n');
						continue;

					case '\0':
					case 0xFFFF:
						mCompiler.eofException(mTok.loc, "Unterminated /* */ comment");

					default:
						buf.add(mCharacter);
						break;
				}

				nextChar();
			}
		_breakCommentLoop:

			// eat any trailing asterisks
			while(buf.length() > 0 && buf[buf.length() - 1] == '*')
				buf.length(buf.length() - 1);

			if(buf.length() > 0 && buf[buf.length() - 1] != '\n')
				buf.add('\n');

			addComment(mCompiler.newString(buf.toArrayView()), loc);
		}
		else
		{
			uword nesting = 1;

			while(true)
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
								return;
						}
						continue;

					case '\r':
					case '\n':
						nextLine();
						continue;

					case '\0':
					case 0xFFFF:
						mCompiler.eofException(mTok.loc, "Unterminated /* */ comment");

					default:
						break;
				}

				nextChar();
			}
		}
	}

#define RETURN\
	do {\
		mTokSinceLastNewline = true;\
		return;\
	} while(false)

#define TOK(t) (mTok.type = (t))
#define NEXT_AND_TOK(t) (nextChar(), mTok.type = (t))

	void Lexer::nextToken()
	{
		mNewlineSinceLastTok = false;
		mTok.preComment = crocstr();
		mTok.postComment = crocstr();
		mTok.preCommentLoc = {crocstr(), 0, 0};
		mTok.postCommentLoc = {crocstr(), 0, 0};
		mTok.startChar = mCharPos;
		mCaptureEnd = mTok.startChar;

		while(true)
		{
			mTok.loc = mLoc;

			switch(mCharacter)
			{
				case '\r':
				case '\n':
					nextLine();
					mNewlineSinceLastTok = true;
					mTokSinceLastNewline = false;
					mTok.startChar = mCharPos;
					continue;

				case '+':
					nextChar();
					if(mCharacter == '=')      NEXT_AND_TOK(Token::AddEq);
					else if(mCharacter == '+') NEXT_AND_TOK(Token::Inc);
					else                       TOK(Token::Add);
					RETURN;

				case '-':
					nextChar();
					if(mCharacter == '=')      NEXT_AND_TOK(Token::SubEq);
					else if(mCharacter == '-') NEXT_AND_TOK(Token::Dec);
					else if(mCharacter == '>') NEXT_AND_TOK(Token::Arrow);
					else                       TOK(Token::Sub);
					RETURN;

				case '~':
					nextChar();
					if(mCharacter == '=') NEXT_AND_TOK(Token::CatEq);
					else                  TOK(Token::Cat);
					RETURN;

				case '*':
					nextChar();
					if(mCharacter == '=') NEXT_AND_TOK(Token::MulEq);
					else                  TOK(Token::Mul);
					RETURN;

				case '/':
					nextChar();
					if(mCharacter == '=') NEXT_AND_TOK(Token::DivEq);
					else if(mCharacter == '/')
					{
						nextChar();
						readLineComment();
						break;
					}
					else if(mCharacter == '*')
					{
						nextChar();
						readBlockComment();
						break;
					}
					else TOK(Token::Div);
					RETURN;

				case '%':
					nextChar();
					if(mCharacter == '=') NEXT_AND_TOK(Token::ModEq);
					else                  TOK(Token::Mod);
					RETURN;

				case '<':
					nextChar();
					if(mCharacter == '=')
					{
						nextChar();
						if(mCharacter == '>') NEXT_AND_TOK(Token::Cmp3);
						else                  TOK(Token::LE);
					}
					else if(mCharacter == '<')
					{
						nextChar();
						if(mCharacter == '=') NEXT_AND_TOK(Token::ShlEq);
						else                  TOK(Token::Shl);
					}
					else TOK(Token::LT);
					RETURN;

				case '>':
					nextChar();
					if(mCharacter == '=') NEXT_AND_TOK(Token::GE);
					else if(mCharacter == '>')
					{
						nextChar();
						if(mCharacter == '=') NEXT_AND_TOK(Token::ShrEq);
						else if(mCharacter == '>')
						{
							nextChar();
							if(mCharacter == '=') NEXT_AND_TOK(Token::UShrEq);
							else                  TOK(Token::UShr);
						}
						else TOK(Token::Shr);
					}
					else TOK(Token::GT);
					RETURN;

				case '&':
					nextChar();
					if(mCharacter == '=')      NEXT_AND_TOK(Token::AndEq);
					else if(mCharacter == '&') NEXT_AND_TOK(Token::AndAnd);
					else                       TOK(Token::And);
					RETURN;

				case '|':
					nextChar();
					if(mCharacter == '=')      NEXT_AND_TOK(Token::OrEq);
					else if(mCharacter == '|') NEXT_AND_TOK(Token::OrOr);
					else                       TOK(Token::Or);
					RETURN;

				case '^':
					nextChar();
					if(mCharacter == '=') NEXT_AND_TOK(Token::XorEq);
					else                  TOK(Token::Xor);
					RETURN;

				case '=':
					nextChar();
					if(mCharacter == '=') NEXT_AND_TOK(Token::EQ);
					else                  TOK(Token::Assign);
					RETURN;

				case '.':
					nextChar();

					if(IS_DECIMALDIGIT())
					{
						crocint dummy;
						bool b = readNumLiteral(true, mTok.floatValue, dummy);
						assert(!b);
#ifdef NDEBUG
						(void)b;
#endif
						TOK(Token::FloatLiteral);
					}
					else if(mCharacter == '.')
					{
						nextChar();

						if(mCharacter == '.') NEXT_AND_TOK(Token::Ellipsis);
						else                  TOK(Token::DotDot);
					}
					else                      TOK(Token::Dot);
					RETURN;

				case '!':
					nextChar();
					if(mCharacter == '=') NEXT_AND_TOK(Token::NE);
					else                  TOK(Token::Not);
					RETURN;

				case '?':
					nextChar();
					if(mCharacter == '=') NEXT_AND_TOK(Token::DefaultEq);
					else                  TOK(Token::Question);
					RETURN;

				case '\"':
				case '\'':
					mTok.stringValue = readStringLiteral(true);
					TOK(Token::StringLiteral);
					RETURN;

				case '@':
					nextChar();
					if(mCharacter == '\"' || mCharacter == '\'')
					{
						mTok.stringValue = readStringLiteral(false);
						TOK(Token::StringLiteral);
					}
					else TOK(Token::At);
					RETURN;

				case '(':  NEXT_AND_TOK(Token::LParen);    RETURN;
				case ')':  NEXT_AND_TOK(Token::RParen);    RETURN;

				case '[': {
					auto beginning = mLoc;
					nextChar();
					if(auto equalLen = readVerbatimOpening(beginning))
					{
						mTok.stringValue = readVerbatimString(beginning, equalLen);
						TOK(Token::StringLiteral);
					}
					else TOK(Token::LBracket);
					RETURN;
				}
				case ']':  NEXT_AND_TOK(Token::RBracket);  RETURN;
				case '{':  NEXT_AND_TOK(Token::LBrace);    RETURN;
				case '}':  NEXT_AND_TOK(Token::RBrace);    RETURN;
				case ':':  NEXT_AND_TOK(Token::Colon);     RETURN;
				case ',':  NEXT_AND_TOK(Token::Comma);     RETURN;
				case ';':  NEXT_AND_TOK(Token::Semicolon); RETURN;
				case '#':  NEXT_AND_TOK(Token::Length);    RETURN;
				case '\\': NEXT_AND_TOK(Token::Backslash); RETURN;

				case '\0':
				case 0xFFFF:
					TOK(Token::EOF_);
					RETURN;

				default:
					if(IS_WHITESPACE())
					{
						nextChar();
						mTok.startChar = mCharPos;
						continue;
					}
					else if(IS_DECIMALDIGIT())
					{
						crocfloat fval;
						crocint ival;
						bool isInt = readNumLiteral(false, fval, ival);

						if(!isInt)
						{
							mTok.floatValue = fval;
							TOK(Token::FloatLiteral);
						}
						else
						{
							mTok.intValue = ival;
							TOK(Token::IntLiteral);
						}
						RETURN;
					}
					else if(IS_IDENTSTART())
					{
						List<uchar, 32> buf(mCompiler);

						do
						{
							buf.add(cast(uchar)mCharacter);
							nextChar();
						} while(IS_IDENTCONT());

						auto arr = buf.toArrayView();
						auto type = lookupKeyword(arr);

						if(type >= 0)
							TOK(type);
						else
						{
							mTok.stringValue = mCompiler.newString(arr);
							TOK(Token::Ident);
						}
						RETURN;
					}
					else
					{
						if(mCharacter < ' ' || mCharacter >= 0x7f)
							mCompiler.lexException(mTok.loc, "Invalid character 0x%x", mCharacter);
						else
							mCompiler.lexException(mTok.loc, "Invalid character '%c'", mCharacter);
					}
			}
		}
	}
}