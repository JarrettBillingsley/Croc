
#include <stdarg.h>
#include <stdlib.h>

#include "croc/api.h"
#include "croc/compiler/docparser.hpp"
#include "croc/internal/stack.hpp"
#include "croc/util/utf.hpp"

namespace croc
{
	namespace
	{
#define TOKEN_LIST(X)\
	X(EOC,           "<end of comment>")\
	X(Whitespace,    "Whitespace")\
	X(Newline,       "<newline>")\
	X(NewParagraph,  "<new paragraph>")\
	X(Word,          "Word")\
	X(SectionBegin,  "Section command")\
	X(TextSpanBegin, "Text span command")\
	X(RBrace,        "}")\
	X(Code,          "Code snippet")\
	X(Verbatim,      "Verbatim block")\
	X(BList,         "Bulleted list command")\
	X(NList,         "Numbered list command")\
	X(DList,         "Definition list command")\
	X(Table,         "Table command")\
	X(EndList,       "End list command")\
	X(EndTable,      "Table end command")\
	X(ListItem,      "List item command")\
	X(DefListItem,   "Definition list item command")\
	X(Row,           "Row command")\
	X(Cell,          "Cell command")

	 // Token::DefListItem is handled elsewhere
#define TEXT_STRUCTURE_LIST(X)\
	X("blist",    Token::BList)\
	X("cell",     Token::Cell)\
	X("code",     Token::Code)\
	X("dlist",    Token::DList)\
	X("endlist",  Token::EndList)\
	X("endtable", Token::EndTable)\
	X("li",       Token::ListItem)\
	X("nlist",    Token::NList)\
	X("row",      Token::Row)\
	X("table",    Token::Table)\
	X("verbatim", Token::Verbatim)

	struct Token
	{
		uword type;
		uword line;
		uword col;
		crocstr string;
		crocstr arg;
		crocstr contents;

		enum
		{
#define POOP(name, _) name,
			TOKEN_LIST(POOP)
#undef POOP
		};

		static const char* strings[];

		Token() :
			type(0),
			line(0),
			col(0),
			string(),
			arg(),
			contents()
		{}

		const char* typeString()
		{
			return strings[type];
		}

		bool isSubStructure()
		{
			return type >= EndList;
		}
	};

	const char* Token::strings[] =
	{
#define POOP(_, str) str,
		TOKEN_LIST(POOP)
#undef POOP
	};

	const crocstr StdSectionNames[] =
	{
		ATODA("authors"),
		ATODA("bugs"),
		ATODA("copyright"),
		ATODA("date"),
		ATODA("deprecated"),
		ATODA("examples"),
		ATODA("history"),
		ATODA("license"),
		ATODA("notes"),
		ATODA("param"), // duplicated in FuncSectionNames
		ATODA("returns"), // duplicated in FuncSectionNames
		ATODA("see"),
		ATODA("since"),
		ATODA("throws"), // duplicated in FuncSectionNames
		ATODA("todo"),
		ATODA("version"),
		ATODA("warnings"),
	};

	const crocstr FuncSectionNames[] =
	{
		ATODA("param"),
		ATODA("returns"),
		ATODA("throws"),
	};

	const crocstr TextSpanNames[] =
	{
		ATODA("b"),
		ATODA("em"),
		ATODA("link"),
		ATODA("s"),
		ATODA("sub"),
		ATODA("sup"),
		ATODA("tt"),
		ATODA("u"),
	};

	const crocstr TextStructureNames[] =
	{
#define POOP(str, _) ATODA(str),
		TEXT_STRUCTURE_LIST(POOP)
#undef POOP
	};

	const uword TextStructureTypes[] =
	{
#define POOP(_, tok) tok,
		TEXT_STRUCTURE_LIST(POOP)
#undef POOP
	};

	namespace
	{
	extern "C"
	{
		int compareFunc_crocstr(const void* a, const void* b)
		{
			return (cast(crocstr*)a)->cmp(*cast(crocstr const*)b);
		}
	}
	}

	int lookupStdSection(crocstr str)
	{
		auto ptr = cast(crocstr*)bsearch(cast(const void*)&str, cast(const void*)StdSectionNames,
			sizeof(StdSectionNames) / sizeof(crocstr), sizeof(crocstr), &compareFunc_crocstr);

		if(ptr)
			return ptr - StdSectionNames;
		else
			return -1;
	}

	int lookupFuncSection(crocstr str)
	{
		auto ptr = cast(crocstr*)bsearch(cast(const void*)&str, cast(const void*)FuncSectionNames,
			sizeof(FuncSectionNames) / sizeof(crocstr), sizeof(crocstr), &compareFunc_crocstr);

		if(ptr)
			return ptr - FuncSectionNames;
		else
			return -1;
	}

	int lookupTextSpan(crocstr str)
	{
		auto ptr = cast(crocstr*)bsearch(cast(const void*)&str, cast(const void*)TextSpanNames,
			sizeof(TextSpanNames) / sizeof(crocstr), sizeof(crocstr), &compareFunc_crocstr);

		if(ptr)
			return ptr - TextSpanNames;
		else
			return -1;
	}

	const uword* lookupTextStructure(crocstr str)
	{
		auto ptr = cast(crocstr*)bsearch(cast(const void*)&str, cast(const void*)TextStructureNames,
			sizeof(TextStructureNames) / sizeof(crocstr), sizeof(crocstr), &compareFunc_crocstr);

		if(ptr)
			return &TextStructureTypes[ptr - TextStructureNames];
		else
			return nullptr;
	}

	/*
	DocComment:
		Paragraph* Section*

	Section:
		SectionCommand Paragraph*

	SectionCommand:
		RawSectionCommand ':'?

	RawSectionCommand:
		'\authors'
		'\bugs'
		'\copyright'
		'\date'
		'\deprecated'
		'\examples'
		'\history'
		'\license'
		'\notes'
		'\param[' Word ']'
		'\returns'
		'\see'
		'\since'
		'\throws[' Word ']'
		'\todo'
		'\version'
		'\warnings'
		'\_'Word

	Paragraph:
		(ParaElem | TextStructure)+ EOP

	ParaElem:
		Newline
		Word
		TextSpan

	TextSpan:
		TextSpanCommand ParaElem+ '}'
		'\link{' Word '}'

	TextSpanCommand:
		'\b{'
		'\em{'
		'\link[' Word ']{'
		'\s{'
		'\sub{'
		'\sup{'
		'\tt{'
		'\u{'
		'\_'Word'{'

	TextStructure:
		CodeSnippet
		Verbatim
		List
		Table

	CodeSnippet:
		'\code' Newline Anything '\endcode' EOL
		'\code[' Word ']' Newline Anything '\endcode' EOL

	Verbatim:
		'\verbatim' Newline Anything '\endverbatim' EOL
		'\verbatim[' Word ']' Newline Anything '\endverbatim' EOL

	List:
		('\blist' | '\nlist' | '\nlist[' Word ']') Newline ListItem+ '\endlist' EOL
		'\dlist' Newline DefListItem+ '\endlist' EOL

	ListItem:
		'\li' Paragraph*

	DefListItem:
		'\li{' ParaElem+ '}' Paragraph*

	Table:
		'\table' Newline Row+ '\endtable' EOL

	Row:
		'\row' Newline Cell+

	Cell:
		'\cell' Paragraph*

	EOC:
		<End of comment>

	EOL:
		Newline
		EOC

	EOP:
		2 or more Newlines
		EOC
		SectionCommand
	*/

	struct CommentParser;

	struct CommentLexer
	{
	private:
		friend class CommentParser;

		CommentParser* parser;
		crocstr mCommentSource;
		const uchar* mSourcePtr;
		const uchar* mSourceEnd;
		const uchar* mCharPos;
		const uchar* mLookaheadCharPos;
		uword mLine;
		uword mCol;
		dchar mCharacter;
		dchar mLookaheadCharacter;
		bool mHaveLookahead;
		bool mNewlineSinceLastTok;

		Token mTok;

		CommentLexer(CommentParser* p) :
			parser(p),
			mCommentSource(),
			mSourcePtr(),
			mSourceEnd(),
			mCharPos(),
			mLookaheadCharPos(),
			mLine(),
			mCol(),
			mCharacter(),
			mLookaheadCharacter(),
			mHaveLookahead(),
			mNewlineSinceLastTok()
		{}

		void begin(crocstr source)
		{
			mCommentSource = source;
			mSourcePtr = source.ptr;
			mSourceEnd = source.ptr + source.length;
			mLine = 1;
			mCol = 0;
			mCharacter = 0xFFFF;
			mHaveLookahead = false;
			mTok = Token();

			nextChar();
			next();
			nextNonNewlineToken();

			// set it to true so the very first token is flagged as being at the beginning of a line
			mNewlineSinceLastTok = true;
		}

		// =============================================================================================================
		// Character-level lexing

#define IS_ESCAPABLE_CHAR(c) ((c) == '\\' || (c) == '{' || (c) == '}')
#define IS_EOC() (mCharacter == 0xFFFF)
#define IS_EOL() (IS_NEWLINE() || IS_EOC())
#define IS_NEWLINE() (mCharacter == '\r' || mCharacter == '\n')
#define IS_WHITESPACE()\
			((mCharacter == ' ') || (mCharacter == '\t') || (mCharacter == '\v') || (mCharacter == '\u000C'))
#define IS_ALPHA() (((mCharacter >= 'a') && (mCharacter <= 'z')) || ((mCharacter >= 'A') && (mCharacter <= 'Z')))
#define IS_COMMAND_CHAR() (mCharacter == '_' || IS_ALPHA())

		dchar readChar(const uchar*& pos)
		{
			if(mSourcePtr >= mSourceEnd)
			{
				// Useful for avoiding edge cases at the ends of comments
				mSourcePtr++;
				pos = mSourceEnd;
				return 0xFFFF;
			}
			else
			{
				pos = mSourcePtr;
				dchar ret = 0;

				if(decodeUtf8Char(mSourcePtr, mSourceEnd, ret) != UtfError_OK)
					errorHere("Comment source is not valid UTF-8");

				return ret;
			}
		}

		dchar lookaheadChar()
		{
			if(!mHaveLookahead)
			{
				mLookaheadCharacter = readChar(mLookaheadCharPos);
				mHaveLookahead = true;
			}

			return mLookaheadCharacter;
		}

		void nextChar()
		{
			mCol++;

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

		void nextLine()
		{
			if(IS_NEWLINE() && !IS_EOC())
			{
				dchar old = mCharacter;

				nextChar();

				if(IS_NEWLINE() && mCharacter != old)
					nextChar();

				mLine++;
				mCol = 1;
			}
		}

		uword curPos()
		{
			return mCharPos - mCommentSource.ptr;
		}

		void eatWhitespace()
		{
			while(IS_WHITESPACE())
				nextChar();
		}

		void eatLineBegin()
		{
			eatWhitespace();

			if(mCharacter == '*' && lookaheadChar() != '/')
			{
				nextChar();
				eatWhitespace();
			}
		}

		crocstr readWord()
		{
			auto begin = curPos();

			while(!IS_WHITESPACE() && !IS_EOL())
				nextChar();

			return mCommentSource.slice(begin, curPos());
		}

		crocstr readUntil(dchar c)
		{
			auto begin = curPos();

			while(!IS_EOL() && mCharacter != c)
				nextChar();

			return mCommentSource.slice(begin, curPos());
		}

		void readRawBlock(const char* kind, const char* endCommand)
		{
			if(mCharacter != '\n')
				errorHere("%s block opening command must be followed by a newline", kind);

			nextLine();

			auto begin = curPos();
			uword endPos = begin;
			auto endCommandStr = atoda(endCommand);

			while(!IS_EOC())
			{
				if(mCharacter == '\\')
				{
					auto slice = mCommentSource.slice(curPos() + 1, mCommentSource.length);

					if(slice.length >= endCommandStr.length && slice.slice(0, endCommandStr.length) == endCommandStr)
					{
						mSourcePtr += endCommandStr.length; // mSourcePtr is one ahead, it's already past the backslash
						nextChar();

						if(!IS_EOC() && mCharacter != '\n')
							errorHere("\\%s must be followed by newline or end-of-comment", endCommand);

						mTok.contents = mCommentSource.slice(begin, endPos);
						return;
					}
				}

				readUntil('\n');
				endPos = curPos();
				nextLine();
			}

			error("%s block has no matching '%s'", kind, endCommand);
		}

		// =============================================================================================================
		// Token-level lexing
public:
		void next()
		{
			if(mTok.type != Token::Newline && mTok.type != Token::NewParagraph)
				mNewlineSinceLastTok = false;

			mTok.string = crocstr();
			mTok.arg = crocstr();
			mTok.contents = crocstr();

			while(true)
			{
				mTok.line = mLine;
				mTok.col = mCol;

				switch(mCharacter)
				{
					case 0xFFFF:
						mTok.type = Token::EOC;
						return;

					case '\r':
					case '\n':
						mTok.type = Token::Newline;
						mNewlineSinceLastTok = true;

						nextLine();
						eatLineBegin();

						while(IS_NEWLINE())
						{
							mTok.type = Token::NewParagraph;
							nextLine();
							eatLineBegin();
						}

						if(IS_EOC())
							mTok.type = Token::EOC;
						return;

					case '}':
						nextChar();
						mTok.type = Token::RBrace;
						return;

					case '\\': {
						if(IS_ESCAPABLE_CHAR(lookaheadChar()))
							goto _Word;

						nextChar();

						if(IS_EOC())
							errorHere("Unexpected end-of-comment after backslash");
						else if(!IS_COMMAND_CHAR())
							errorHere("Invalid character after backslash");

						auto commandStart = curPos();

						while(IS_COMMAND_CHAR())
							nextChar();

						mTok.string = mCommentSource.slice(commandStart, curPos());

						if(mTok.string == ATODA("_"))
							error("Custom command must have at least one character after the underscore");

						if(mCharacter == '{')
						{
							// text span or \li{
							nextChar();

							if(mTok.string == ATODA("li"))
								mTok.type = Token::DefListItem;
							else
							{
								if(mTok.string[0] != '_' && lookupTextSpan(mTok.string) == -1)
									error("Invalid text span name '%.*s'",
										cast(int)mTok.string.length, mTok.string.ptr);

								mTok.type = Token::TextSpanBegin;
							}
						}
						else if(mCharacter == '[')
						{
							// has to be one of param, throws, link, code, verbatim, or nlist
							nextChar();

							eatWhitespace();
							mTok.arg = readUntil(']');
							eatWhitespace();

							if(mCharacter != ']')
								errorHere("Expected ']' after command argument");

							nextChar();

							if(mTok.string == ATODA("param") || mTok.string == ATODA("throws"))
							{
								mTok.type = Token::SectionBegin;
								if(mCharacter == ':')
									nextChar();
							}
							else if(mTok.string == ATODA("link"))
							{
								mTok.type = Token::TextSpanBegin;

								if(mCharacter != '{')
									errorHere("Expected '{{' after text span command");

								nextChar();
							}
							else if(mTok.string == ATODA("code"))
							{
								mTok.type = Token::Code;
								readRawBlock("Code", "endcode");
							}
							else if(mTok.string == ATODA("verbatim"))
							{
								mTok.type = Token::Verbatim;
								readRawBlock("Verbatim", "endverbatim");
							}
							else if(mTok.string == ATODA("nlist"))
								mTok.type = Token::NList;
							else
								error("Invalid command name '%.*s'", cast(int)mTok.string.length, mTok.string.ptr);
						}
						else if(mTok.string[0] == '_' || lookupStdSection(mTok.string) != -1)
						{
							if(mCharacter == ':')
								nextChar();

							mTok.type = Token::SectionBegin;
						}
						else if(auto type = lookupTextStructure(mTok.string))
						{
							mTok.type = *type;

							if(mTok.type == Token::Code)
							{
								mTok.arg = ATODA("croc");
								readRawBlock("Code", "endcode");
							}
							else if(mTok.type == Token::Verbatim)
							{
								mTok.arg = ATODA("");
								readRawBlock("Verbatim", "endverbatim");
							}
						}
						else
							error("Invalid command '%.*s'", cast(int)mTok.string.length, mTok.string.ptr);
						return;
					}
					default:
						if(IS_WHITESPACE())
						{
							eatWhitespace();
							mTok.type = Token::Whitespace;
							return;
						}

					_Word:
						auto wordStart = curPos();

						while(!IS_WHITESPACE() && !IS_EOL())
						{
							if(mCharacter == '\\')
							{
								if(IS_ESCAPABLE_CHAR(lookaheadChar()))
								{
									// Have to do this cause otherwise it would pick up on the second backslash as the
									// beginning of a command
									nextChar();
									nextChar();
								}
								else
									break;
							}
							else if(mCharacter == '}')
								break;
							else
								nextChar();
						}

						mTok.string = mCommentSource.slice(wordStart, curPos());
						mTok.type = Token::Word;
						return;
				}
			}
		}

		void nextNonNewlineToken()
		{
			while(mTok.type == Token::Newline || mTok.type == Token::NewParagraph)
				next();
		}

		void nextNonWhitespaceToken()
		{
			while(mTok.type == Token::Newline || mTok.type == Token::NewParagraph || mTok.type == Token::Whitespace)
				next();
		}

		// =============================================================================================================
		// Other interfaces

		Token tok()
		{
			return mTok;
		}

		uword type()
		{
			return mTok.type;
		}

		bool isEOP()
		{
			return mTok.type == Token::NewParagraph || mTok.type == Token::EOC || mTok.type == Token::SectionBegin;
		}

		bool isFirstOnLine()
		{
			return mNewlineSinceLastTok;
		}

		// =============================================================================================================
		// Error handling
private:
		void error(const char* msg, ...) CROCPRINT(2, 3);
		void error(uword line, uword col, const char* msg, ...) CROCPRINT(4, 5);
		void errorHere(const char* msg, ...) CROCPRINT(2, 3);
	};

	struct CommentParser
	{
	private:
		friend class CommentLexer;
		static const char NumberedListTypes[];
		static const uword NumberedListMax;

		CrocThread* t;
		CommentLexer l;

		bool mIsFunction = false;
		uword mNumberedListNest = 0;
		bool mInTable = false;

		uword docTable;
		uword section;

	public:
		CommentParser(CrocThread* t) :
			t(t),
			l(this),
			mIsFunction(false),
			mNumberedListNest(0),
			mInTable(false),
			docTable(),
			section()
		{}

	public:
		void parse(crocstr comment)
		{
			docTable = croc_absIndex(t, -1);
			assert(croc_isTable(t, docTable));
			section = docTable + 1;
			croc_field(t, docTable, "kind");
			mIsFunction = atoda(croc_getString(t, -1)) == ATODA("function");
			croc_popTop(t);

			l.begin(comment);

#if 0
			croc_array_new(t, 0);

			do
			{
				croc_pushFormat(t, "(%" CROC_SIZE_T_FORMAT ":%" CROC_SIZE_T_FORMAT ") %.*s '%.*s'",
					mTok.line, mTok.col,
					cast(int)mTok.typeString.length, mTok.typeString.ptr,
					cast(int)mTok.string.length, mTok.string.ptr);

				if(mTok.arg.length > 0)
				{
					croc_pushFormat(t, ": '%.*s'", cast(int)mTok.arg.length, mTok.arg.ptr);
					croc_cat(t, 2);
				}

				croc_cateq(t, -2, 1);
				next();

			} while(mTok.type != Token::EOC)

			croc_insertAndPop(t, docTable);
#else
			beginStdSection(ATODA("docs"));

			while(l.type() != Token::EOC)
			{
				checkForSectionChange();
				readParagraph();
			}

			endSection();

			// If it's a function doc table, make sure all the params have docs members; give them empty docs if not
			if(mIsFunction)
				ensureParamDocs();
#endif
		}

		word parseText(crocstr comment)
		{
			// dummy doctable
			docTable = croc_table_new(t, 0);
			section = docTable + 1;
			l.begin(comment);

			beginStdSection(ATODA("docs"));

			while(l.type() != Token::EOC)
			{
				if(l.type() == Token::SectionBegin)
					error("Section commands are not allowed when parsing plain comment text");

				readParagraph();
			}

			endSection();

			croc_field(t, -1, "docs");
			croc_insertAndPop(t, docTable);
			return croc_getStackSize(t) - 1;
		}

	private:
		void checkForSectionChange()
		{
			if(l.type() != Token::SectionBegin)
				return;

			assert(l.tok().string.length > 0);

			if(!l.isFirstOnLine())
				error("Section command must come at the beginning of a line");

			if(l.tok().string[0] == '_')
			{
				endSection();
				beginCustomSection(l.tok().string.sliceToEnd(1));
			}
			else if(lookupFuncSection(l.tok().string) != -1)
			{
				if(!mIsFunction)
					error("Section '%.*s' is only usable in function doc tables",
						cast(int)l.tok().string.length, l.tok().string.ptr);

				endSection();

				if     (l.tok().string == ATODA("param"))   beginParamSection(l.tok().arg);
				else if(l.tok().string == ATODA("throws"))  beginThrowsSection(l.tok().arg);
				else if(l.tok().string == ATODA("returns")) beginStdSection(l.tok().string);
				else assert(false);
			}
			else
			{
				endSection();
				beginStdSection(l.tok().string);
			}

			l.next();
		}

		void readParagraph()
		{
			auto pgph = beginParagraph();
			readParaElems(pgph, false);

			if(l.type() == Token::NewParagraph)
				l.next();
			else
				assert(l.type() == Token::EOC || l.type() == Token::SectionBegin || l.tok().isSubStructure());

			endParagraph(pgph);
		}

		void readParaElems(uword slot, bool inTextSpan)
		{
			const uword MaxFrags = 50;
			uword numFrags = 0;

			auto addText = [this, &numFrags, &slot]()
			{
				if(numFrags > 0)
				{
					concatTextFragments(slot);
					append(slot);
					numFrags = 0;
				}
			};

			auto commonTextStructure = [this, &addText, &slot, &inTextSpan](std::function<void()> reader)
			{
				if(inTextSpan)
					error("Text structure command '%s' is not allowed inside text spans", l.tok().typeString());

				addText();
				reader();
				append(slot);
			};

			l.nextNonWhitespaceToken();

			while(true)
			{
				switch(l.type())
				{
					case Token::Newline:
					case Token::Whitespace:
						croc_pushString(t, " ");
						goto _commonWord;

					case Token::RBrace:
						if(inTextSpan)
							goto _breakOuterLoop;

						croc_pushString(t, "}");
						goto _commonWord;

					case Token::Word:
						croc_pushStringn(t, cast(const char*)l.tok().string.ptr, l.tok().string.length);

					_commonWord:
						l.next();

						numFrags++;

						if(numFrags >= MaxFrags)
						{
							concatTextFragments(slot);
							numFrags = 1;
						}
						break;

					case Token::TextSpanBegin:
						addText();
						readTextSpan();
						append(slot);
						break;

	    			case Token::Code:          commonTextStructure([this](){ readCodeBlock(); }); break;
	    			case Token::Verbatim:      commonTextStructure([this](){ readVerbatimBlock(); }); break;
	    			case Token::BList:
	    			case Token::NList:
	    			case Token::DList:         commonTextStructure([this](){ readList(); }); break;
	    			case Token::Table:         commonTextStructure([this](){ readTable(); }); break;

	    			default:
	    				if(l.isEOP() || l.tok().isSubStructure())
	    				{
							// if inside a text span, readTextSpan will deal with this, it can give a better error
							goto _breakOuterLoop;
						}
						else
		    				error("Invalid '%s' in paragraph", l.tok().typeString());
				}
			}

			_breakOuterLoop:;
		}

		void readTextSpan()
		{
			assert(l.type() == Token::TextSpanBegin);

			auto tok = l.tok();
			auto span = beginTextSpan(tok.string);

			if(tok.string == ATODA("link") && tok.arg.length)
			{
				croc_pushStringn(t, cast(const char*)tok.arg.ptr, tok.arg.length);
				append(span);
			}

			l.next();

			readParaElems(span, true);

			if(l.type() != Token::RBrace)
				error(tok.line, tok.col, "Text span '%.*s' has no closing brace",
					cast(int)tok.string.length, tok.string.ptr);

			l.next();

			endTextSpan(span);
		}

		void readCodeBlock()
		{
			assert(l.type() == Token::Code);

			if(!l.isFirstOnLine())
				error("Code command must come at the beginning of a line");

			croc_array_new(t, 3);
			croc_pushString(t, "code");
			croc_idxai(t, -2, 0);
			croc_pushStringn(t, cast(const char*)l.tok().arg.ptr, l.tok().arg.length);
			croc_idxai(t, -2, 1);
			croc_pushStringn(t, cast(const char*)l.tok().contents.ptr, l.tok().contents.length);
			croc_idxai(t, -2, 2);

			l.next();

			if(l.type() != Token::Newline && l.type() != Token::NewParagraph && l.type() != Token::EOC)
				error("\\endcode must be followed by a newline or end-of-comment, not '%s'", l.tok().typeString());

			l.next();
		}

		void readVerbatimBlock()
		{
			assert(l.type() == Token::Verbatim);

			if(!l.isFirstOnLine())
				error("Verbatim command must come at the beginning of a line");

			croc_array_new(t, 3);
			croc_pushString(t, "verbatim");
			croc_idxai(t, -2, 0);
			croc_pushStringn(t, cast(const char*)l.tok().arg.ptr, l.tok().arg.length);
			croc_idxai(t, -2, 1);
			croc_pushStringn(t, cast(const char*)l.tok().contents.ptr, l.tok().contents.length);
			croc_idxai(t, -2, 2);

			l.next();

			if(l.type() != Token::Newline && l.type() != Token::NewParagraph && l.type() != Token::EOC)
				error("\\endverbatim must be followed by a newline or end-of-comment, not '%s'", l.tok().typeString());

			l.next();
		}

		void readList()
		{
			assert(l.type() == Token::BList || l.type() == Token::NList || l.type() == Token::DList);

			if(!l.isFirstOnLine())
				error("List command must come at the beginning of a line");

			uword numListSave = mNumberedListNest;
			bool isDefList = l.type() == Token::DList;
			uword arr;

			if(l.type() == Token::NList)
			{
				auto type = l.tok().arg;

				if(type.length > 0)
				{
					if(type.length > 1)
						error("Invalid numbered list type");

					for(uword i = 0; i < NumberedListMax; i++)
					{
						if(type[0] == NumberedListTypes[i])
						{
							mNumberedListNest = i;
							goto _found;
						}
					}

					error("Invalid numbered list type '%c'", type[0]);
					_found:;
				}

				arr = croc_array_new(t, 2);
				croc_pushString(t, "nlist");
				croc_idxai(t, -2, 0);
				croc_pushStringn(t, &NumberedListTypes[mNumberedListNest], 1);
				croc_idxai(t, -2, 1);
				mNumberedListNest = (mNumberedListNest + 1) % NumberedListMax;
			}
			else
			{
				mNumberedListNest = 0;
				arr = croc_array_new(t, 1);

				if(isDefList)
					croc_pushString(t, "dlist");
				else
					croc_pushString(t, "blist");

				croc_idxai(t, -2, 0);
			}

			auto tok = l.tok();
			l.next();

			if(l.type() != Token::Newline && l.type() != Token::NewParagraph)
				error("List start command must be followed by a newline");

			l.next();
			l.nextNonNewlineToken();

			bool first = true;
			uword item;

			auto beginItem = [&]()
			{
				item = croc_array_new(t, 0);
				croc_dupTop(t);
				append(arr);
			};

			auto endItem = [&]()
			{
				if(croc_len(t, item) == 0)
				{
					croc_array_new(t, 1);
					croc_pushString(t, "");
					croc_idxai(t, -2, 0);
					append(item);
				}

				croc_popTop(t);
			};

			auto switchItems = [&]()
			{
				if(first)
					first = false;
				else
					endItem();

				beginItem();
			};

			while(l.type() != Token::EOC && l.type() != Token::EndList)
			{
				if(l.type() == Token::ListItem)
				{
					if(isDefList)
						error("Cannot use a regular list item in a definition list");

					switchItems();
					l.next();
				}
				else if(l.type() == Token::DefListItem)
				{
					if(!isDefList)
						error("Cannot use a definition list item in a numbered/bulleted list");

					switchItems();
					auto liTok = l.tok();
					l.next();

					auto defItem = croc_array_new(t, 0);
					readParaElems(defItem, true);

					if(l.type() != Token::RBrace)
						error(liTok.line, liTok.col, "Definition list item has no closing brace");

					l.next();

					if(croc_getStackSize(t) - 1 > cast(uword)defItem)
					{
						concatTextFragments(defItem);
						append(defItem);
					}

					if(croc_len(t, defItem) == 0)
						error(liTok.line, liTok.col, "Definition list item must contain a term");
					else
						trimFinalText(defItem);

					append(item);
				}
				else if(l.type() == Token::SectionBegin)
					error("Cannot change sections inside a list");
				else if(first)
					error("Cannot have text before a list item");
				else
					readParagraph();
			}

			if(first)
				error(tok.line, tok.col, "List must have at least one item");
			else if(l.type() == Token::EOC)
				error(tok.line, tok.col, "List has no matching \\endlist command");

			endItem();
			l.next();
			mNumberedListNest = numListSave;
		}

		void readTable()
		{
			assert(l.type() == Token::Table);

			if(!l.isFirstOnLine())
				error("Table command must come at the beginning of a line");

			if(mInTable)
				error("Tables cannot be nested");

			mInTable = true;

			auto beginTok = l.tok();
			l.next();

			if(l.type() != Token::Newline && l.type() != Token::NewParagraph)
				error("Table start command must be followed by a newline");

			l.next();
			l.nextNonNewlineToken();

			auto tab = croc_array_new(t, 1);
			croc_pushString(t, "table");
			croc_idxai(t, -2, 0);

			bool firstRow = true;
			bool firstCell = true;
			uword maxRowLength = 0;
			uword curRowLength = 0;
			uword row;
			uword cell;

			auto beginRow = [&]()
			{
				row = croc_array_new(t, 0);
				croc_dupTop(t);
				append(tab);
				firstCell = true;
				curRowLength = 0;
			};

			auto beginCell = [&]()
			{
				cell = croc_array_new(t, 0);
				croc_dupTop(t);
				append(row);
				curRowLength++;
				maxRowLength = curRowLength > maxRowLength ? curRowLength : maxRowLength;
			};

			auto endRow = [&]()
			{
				assert(!firstRow);
				croc_popTop(t);
				row = 0;
			};

			auto endCell = [&]()
			{
				assert(!firstCell);

				if(croc_len(t, cell) == 0)
				{
					croc_array_new(t, 1);
					croc_pushString(t, "");
					croc_idxai(t, -2, 0);
					append(cell);
				}

				croc_popTop(t);
				cell = 0;
			};

			auto switchRows = [&]()
			{
				if(!firstCell)
					endCell();

				if(firstRow)
					firstRow = false;
				else
					endRow();

				beginRow();
				l.next();
				l.nextNonWhitespaceToken();
			};

			auto switchCells = [&]()
			{
				if(firstCell)
					firstCell = false;
				else
					endCell();

				beginCell();
				l.next();
			};

			while(l.type() != Token::EOC && l.type() != Token::EndTable)
			{
				if(l.type() == Token::SectionBegin)
					error("Cannot change sections inside a table");
				else if(l.type() == Token::Cell)
				{
					if(firstRow)
						error("Cannot have a cell outside a row");
					else
						switchCells();
				}
				else if(l.type() == Token::Row)
				{
					if(!l.isFirstOnLine())
						error("Row command must come at the beginning of a line");

					switchRows();
				}
				else if(firstRow || firstCell)
					error("Cannot have text outside a cell");
				else
					readParagraph();
			}

			if(firstRow)
				error(beginTok.line, beginTok.col, "Table must have at least one row");
			else if(l.type() == Token::EOC)
				error(beginTok.line, beginTok.col, "Table has no matching \\endtable command");

			if(!firstCell)
				endCell();

			endRow();
			l.next();

			// Now normalize table columns.
			auto tableLen = croc_len(t, tab);
			for(uword i = 1; i < tableLen; i++)
			{
				row = croc_idxi(t, tab, i);
				auto rowLen = croc_len(t, row);
				assert(rowLen <= maxRowLength);

				if(rowLen < maxRowLength)
				{
					croc_lenai(t, row, maxRowLength);

					for(uword j = cast(uword)rowLen; j < maxRowLength; j++)
					{
						croc_array_new(t, 1);
						croc_array_new(t, 1);
						croc_pushString(t, "");
						croc_idxai(t, -2, 0);
						croc_idxai(t, -2, 0);
						croc_idxai(t, row, j);
					}
				}

				croc_popTop(t);
			}

			mInTable = false;
		}

		// =============================================================================================================
		// Helpers

		void append(uword pgph)
		{
			croc_lenai(t, pgph, croc_len(t, pgph) + 1);
			croc_idxai(t, pgph, -1);
		}

		void beginStdSection(crocstr name)
		{
			assert(croc_getStackSize(t) - 1 == docTable);

			croc_pushStringn(t, cast(const char*)name.ptr, name.length);

			if(croc_hasFieldStk(t, docTable, -1))
				error("Section '%.*s' already exists", cast(int)name.length, name.ptr);

			croc_array_new(t, 0);
			croc_swapTop(t);
			croc_dup(t, -2);
			croc_fieldaStk(t, docTable);
		}

		void beginCustomSection(crocstr name)
		{
			assert(croc_getStackSize(t) - 1 == docTable);

			if(!croc_hasField(t, docTable, "custom"))
			{
				croc_table_new(t, 0);
				croc_dupTop(t);
				croc_fielda(t, docTable, "custom");
			}
			else
				croc_field(t, docTable, "custom");

			auto custom = croc_absIndex(t, -1);

			croc_pushStringn(t, cast(const char*)name.ptr, name.length);

			if(croc_hasFieldStk(t, custom, -1))
				error("Custom section '%.*s' already exists", cast(int)name.length, name.ptr);

			croc_array_new(t, 0);
			croc_swapTop(t);
			croc_dup(t, -2);
			croc_fieldaStk(t, custom);
			croc_insertAndPop(t, custom);
		}

		void beginThrowsSection(crocstr exName)
		{
			assert(croc_getStackSize(t) - 1 == docTable);
			assert(mIsFunction);

			if(exName.length == 0)
				error("Empty \\throws command");

			if(!croc_hasField(t, docTable, "throws"))
			{
				croc_array_new(t, 0);
				croc_dupTop(t);
				croc_fielda(t, docTable, "throws");
			}
			else
				croc_field(t, docTable, "throws");

			auto throws = croc_absIndex(t, -1);
			croc_lenai(t, throws, croc_len(t, throws) + 1);

			croc_array_new(t, 1);
			croc_pushStringn(t, cast(const char*)exName.ptr, exName.length);
			croc_idxai(t, -2, 0);
			croc_dupTop(t);
			croc_idxai(t, throws, -1);
			croc_insertAndPop(t, throws);
		}

		void beginParamSection(crocstr paramName)
		{
			assert(croc_getStackSize(t) - 1 == docTable);
			assert(mIsFunction);

			if(paramName.length == 0)
				error("Empty \\param command");

			auto params = croc_field(t, docTable, "params");
			auto numParams = croc_len(t, params);
			crocint idx;

			for(idx = 0; idx < numParams; idx++)
			{
				croc_idxi(t, params, idx);

				croc_field(t, -1, "name");

				if(getCrocstr(Thread::from(t), -1) == paramName)
				{
					croc_popTop(t);
					croc_insertAndPop(t, params);
					break;
				}

				croc_pop(t, 2);
			}

			if(idx == numParams)
				error("Function has no parameter named '%.*s'", cast(int)paramName.length, paramName.ptr);

			// param doctable is sitting on the stack where params used to be

			if(croc_hasField(t, params, "docs"))
				error("Parameter '%.*s' has already been documented", cast(int)paramName.length, paramName.ptr);

			croc_array_new(t, 0);
			croc_dupTop(t);
			croc_fielda(t, params, "docs");
			croc_insertAndPop(t, params);
		}

		void endSection()
		{
			assert(croc_getStackSize(t) - 1 == section);

			if(croc_len(t, section) == 0)
			{
				croc_array_new(t, 1);
				croc_pushString(t, "");
				croc_idxai(t, -2, 0);
				append(section);
			}

			croc_popTop(t);
		}

		uword beginParagraph()
		{
			assert(croc_isArray(t, -1));

			croc_lenai(t, -1, croc_len(t, -1) + 1);
			croc_array_new(t, 0);
			croc_dupTop(t);
			croc_idxai(t, -3, -1);

			return croc_absIndex(t, -1);
		}

		void endParagraph(uword pgph)
		{
			assert(croc_isArray(t, pgph));

			if(croc_getStackSize(t) - 1 > pgph)
			{
				concatTextFragments(pgph);
				append(pgph);
			}

			if(croc_len(t, pgph) == 0)
			{
				croc_pushString(t, "");
				append(pgph);
			}
			else
				trimFinalText(pgph);

			croc_popTop(t);
		}

		uword beginTextSpan(crocstr type)
		{
			croc_array_new(t, 1);
			croc_pushStringn(t, cast(const char*)type.ptr, type.length);
			croc_idxai(t, -2, 0);
			return croc_absIndex(t, -1);
		}

		void endTextSpan(uword span)
		{
			assert(croc_isArray(t, span));

			if(croc_getStackSize(t) - 1 > span)
			{
				concatTextFragments(span);
				append(span);
			}

			if(croc_len(t, span) == 1)
			{
				croc_pushString(t, "");
				append(span);
			}
			else
				trimFinalText(span);

			croc_idxi(t, span, 0);

			if(getCrocstr(Thread::from(t), -1) == ATODA("link") && croc_len(t, span) == 2)
			{
				croc_idxi(t, span, -1);
				append(span);
			}

			croc_popTop(t);
		}

		void trimFinalText(uword pgph)
		{
			assert(croc_isArray(t, pgph));
			assert(croc_len(t, pgph) > 0);

			croc_idxi(t, pgph, -1);

			if(croc_isString(t, -1))
			{
				croc_pushNull(t);
				croc_methodCall(t, -2, "rstrip", 1);

				if(croc_len(t, -1) > 0)
					croc_idxai(t, pgph, -1);
				else
				{
					croc_popTop(t);
					croc_lenai(t, pgph, croc_len(t, pgph) - 1);
				}
			}
			else
				croc_popTop(t);
		}

		void concatTextFragments(uword pgph)
		{
#ifndef NDEBUG
			for(uword slot = pgph + 1; slot < croc_getStackSize(t); slot++)
				assert(croc_isString(t, slot));
#endif
			auto numPieces = croc_getStackSize(t) - (pgph + 1);
			assert(numPieces > 0);

			croc_cat(t, numPieces);

			croc_pushNull(t);
			croc_pushString(t, "\\\\");
			croc_pushString(t, "\\");
			croc_methodCall(t, -4, "replace", 1);

			croc_pushNull(t);
			croc_pushString(t, "\\{");
			croc_pushString(t, "{");
			croc_methodCall(t, -4, "replace", 1);

			croc_pushNull(t);
			croc_pushString(t, "\\}");
			croc_pushString(t, "}");
			croc_methodCall(t, -4, "replace", 1);
		}

		void ensureParamDocs()
		{
			assert(mIsFunction);

			auto params = croc_field(t, docTable, "params");
			auto paramsLength = cast(uword)croc_len(t, -1);

			for(uword i = 0; i < paramsLength; i++)
			{
				auto param = croc_idxi(t, params, i);

				if(!croc_hasField(t, param, "docs"))
				{
					croc_array_new(t, 1);
					croc_array_new(t, 1);
					croc_pushString(t, "");
					croc_idxai(t, -2, 0);
					croc_idxai(t, -2, 0);
					croc_fielda(t, param, "docs");
				}

				croc_popTop(t);
			}

			croc_popTop(t);
		}

		// =============================================================================================================
		// Error handling

		void error(const char* msg, ...) CROCPRINT(2, 3)
		{
			va_list args;
			va_start(args, msg);
			verror(l.tok().line, l.tok().col, msg, args);
			va_end(args);
		}

		void error(uword line, uword col, const char* msg, ...) CROCPRINT(4, 5)
		{
			va_list args;
			va_start(args, msg);
			verror(line, col, msg, args);
			va_end(args);
		}

		void verror(uword line, uword col, const char* msg, va_list args)
		{
			auto ex = croc_eh_pushStd(t, "SyntaxException");
			croc_pushNull(t);
			croc_vpushFormat(t, msg, args);
			croc_call(t, ex, 1);
			croc_dupTop(t);
			croc_pushNull(t);
			croc_eh_pushLocationObject(t, "<doc comment>", line, col);
			croc_methodCall(t, -3, "setLocation", 0);
			croc_eh_throw(t);
		}
	};

	void CommentLexer::error(const char* msg, ...)
	{
		va_list args;
		va_start(args, msg);
		parser->verror(mTok.line, mTok.col, msg, args);
		va_end(args);
	}

	void CommentLexer::error(uword line, uword col, const char* msg, ...)
	{
		va_list args;
		va_start(args, msg);
		parser->verror(line, col, msg, args);
		va_end(args);
	}

	void CommentLexer::errorHere(const char* msg, ...)
	{
		va_list args;
		va_start(args, msg);
		parser->verror(mLine, mCol, msg, args);
		(void)msg;
		va_end(args);
	}

	const char CommentParser::NumberedListTypes[] = {'1', 'a', 'i', 'A', 'I'};
	const uword CommentParser::NumberedListMax = sizeof(CommentParser::NumberedListTypes) / sizeof(char);

	}

	void processComment(CrocThread* t, crocstr comment)
	{
		CommentParser p(t);
		p.parse(comment);
	}

	word parseCommentText(CrocThread* t, crocstr comment)
	{
		CommentParser p(t);
		return p.parseText(comment);
	}
}