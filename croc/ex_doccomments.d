/******************************************************************************
This module contains the functionality used to parse the contents of doc
comments and turn them into the contents of doc tables.

License:
Copyright (c) 2012 Jarrett Billingsley

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

module croc.ex_doccomments;

import tango.core.Vararg;
import tango.text.Util;

import croc.api_interpreter;
import croc.api_stack;
import croc.types;
import croc.utf;
import croc.utils;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

// Expects a doc table on the stack, doesn't change stack size.
void processComment(CrocThread* t, char[] comment)
{
	auto p = CommentParser(t);
	p.parse(comment);
}

// Pushes the parsed text to the stack.
word parseCommentText(CrocThread* t, char[] comment)
{
	auto p = CommentParser(t);
	return p.parseText(comment);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

struct Token
{
	uword type;
	uword line;
	uword col;
	char[] string;
	char[] arg;
	char[] contents;

	enum
	{
		EOC,
		Whitespace,
		Newline,
		NewParagraph,
		Word,
		SectionBegin,
		TextSpanBegin,
		RBrace,
		Code,
		Verbatim,
		BList,
		NList,
		DList,
		Table,

		EndList,
		EndTable,
		ListItem,
		DefListItem,
		Row,
		Cell
	}

	static const char[][] strings =
	[
		EOC: "<end of comment>",
		Whitespace: "Whitespace",
		Newline: "<newline>",
		NewParagraph: "<new paragraph>",

		Word: "Word",
		SectionBegin: "Section command",
		TextSpanBegin: "Text span command",
		RBrace: "}",
		Code: "Code snippet",
		Verbatim: "Verbatim block",
		BList: "Bulleted list command",
		NList: "Numbered list command",
		DList: "Definition list command",
		Table: "Table command",

		EndList: "End list command",
		EndTable: "Table end command",
		ListItem: "List item command",
		DefListItem: "Definition list item command",
		Row: "Row command",
		Cell: "Cell command"
	];

	char[] typeString()
	{
		return strings[type];
	}

	bool isSubStructure()
	{
		return type >= EndList;
	}
}

const char[][] StdSectionNames =
[
	"authors",
	"bugs",
	"copyright",
	"date",
	"deprecated",
	"examples",
	"history",
	"license",
	"notes",
	"see",
	"since",
	"todo",
	"version",
	"warnings",
];

const char[][] FuncSectionNames =
[
	"param",
	"returns",
	"throws"
];

const char[][] TextSpanNames =
[
	"b",
	"em",
	"link",
	"s",
	"sub",
	"sup",
	"tt",
	"u",
];

bool[char[]] stdSections;
bool[char[]] funcSections;
bool[char[]] textSpans;
uword[char[]] textStructures;

static this()
{
	foreach(name; StdSectionNames)
		stdSections[name] = true;

	foreach(name; FuncSectionNames)
	{
		stdSections[name] = true;
		funcSections[name] = true;
	}

	foreach(name; TextSpanNames)
		textSpans[name] = true;

	textStructures =
	[
		"blist"[]: Token.BList,
		"cell": Token.Cell,
		"code": Token.Code,
		"dlist": Token.DList,
		"endlist": Token.EndList,
		"endtable": Token.EndTable,
		"li": Token.ListItem, // Token.DefListItem is handled elsewhere
		"nlist": Token.NList,
		"row": Token.Row,
		"table": Token.Table,
		"verbatim": Token.Verbatim
	];
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

struct CommentLexer
{
private:
	CommentParser* parser;
	char[] mCommentSource;
	char* mSourcePtr;
	char* mSourceEnd;
	char* mCharPos;
	char* mLookaheadCharPos;
	uword mLine;
	uword mCol;
	dchar mCharacter;
	dchar mLookaheadCharacter;
	bool mHaveLookahead;
	bool mNewlineSinceLastTok;

	Token mTok;

	void begin(char[] source)
	{
		mCommentSource = source;
		mSourcePtr = source.ptr;
		mSourceEnd = source.ptr + source.length;
		mLine = 1;
		mCol = 0;
		mCharacter = dchar.init;
		mHaveLookahead = false;
		mTok = Token.init;

		nextChar();
		next();
		nextNonNewlineToken();

		mNewlineSinceLastTok = true; // set it to true so the very first token is flagged as being at the beginning of a line
	}

	// ================================================================================================================================================
	// Character-level lexing

	static bool isEscapableChar(char c)
	{
		return c == '\\' || c == '{' || c == '}';
	}

	bool isEOC()
	{
		return mCharacter == dchar.init;
	}

	bool isEOL()
	{
		return isNewline() || isEOC();
	}

	bool isNewline()
	{
		return mCharacter == '\r' || mCharacter == '\n';
	}

	bool isWhitespace()
	{
		return (mCharacter == ' ') || (mCharacter == '\t') || (mCharacter == '\v') || (mCharacter == '\u000C');
	}

	bool isAlpha()
	{
		return ((mCharacter >= 'a') && (mCharacter <= 'z')) || ((mCharacter >= 'A') && (mCharacter <= 'Z'));
	}

	bool isCommandChar()
	{
		return mCharacter == '_' || isAlpha();
	}

	dchar readChar(ref char* pos)
	{
		if(mSourcePtr >= mSourceEnd)
		{
			// Useful for avoiding edge cases at the ends of comments
			mSourcePtr++;
			pos = mSourceEnd;
			return dchar.init;
		}
		else
		{
			pos = mSourcePtr;
			dchar ret = void;

			if(decodeUtf8Char(mSourcePtr, mSourceEnd, ret) != UtfError.OK)
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
		if(isNewline() && !isEOC())
		{
			dchar old = mCharacter;

			nextChar();

			if(isNewline() && mCharacter != old)
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
		while(isWhitespace())
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

	char[] readWord()
	{
		auto begin = curPos();

		while(!isWhitespace() && !isEOL())
			nextChar();

		return mCommentSource[begin .. curPos()];
	}

	char[] readUntil(dchar c)
	{
		auto begin = curPos();

		while(!isEOL() && mCharacter != c)
			nextChar();

		return mCommentSource[begin .. curPos()];
	}

	void readRawBlock(char[] kind, char[] endCommand)
	{
		if(mCharacter != '\n')
			errorHere("{} block opening command must be followed by a newline", kind);

		nextLine();

		auto begin = curPos();
		uword endPos = begin;

		while(!isEOC())
		{
			if(mCharacter == '\\' && mCommentSource[curPos() + 1 .. $].startsWith(endCommand))
			{
				mSourcePtr += endCommand.length; // since mSourcePtr is one ahead, it's already past the backslash
				nextChar();

				if(!isEOC() && mCharacter != '\n')
					errorHere("\\{} must be followed by newline or end-of-comment", endCommand);

				mTok.contents = mCommentSource[begin .. endPos];
				return;
			}

			readUntil('\n');
			endPos = curPos();
			nextLine();
		}

		error("{} block has no matching '{}'", kind, endCommand);
	}

	// ================================================================================================================================================
	// Token-level lexing

	void next()
	{
		if(mTok.type != Token.Newline && mTok.type != Token.NewParagraph)
			mNewlineSinceLastTok = false;

		mTok.string = null;
		mTok.arg = null;
		mTok.contents = null;

		while(true)
		{
			mTok.line = mLine;
			mTok.col = mCol;

			switch(mCharacter)
			{
				case dchar.init:
					mTok.type = Token.EOC;
					return;

				case '\r', '\n':
					mTok.type = Token.Newline;
					mNewlineSinceLastTok = true;

					nextLine();
					eatLineBegin();

					while(isNewline())
					{
						mTok.type = Token.NewParagraph;
						nextLine();
						eatLineBegin();
					}

					if(isEOC())
						mTok.type = Token.EOC;
					return;

				case '}':
					nextChar();
					mTok.type = Token.RBrace;
					return;

				case '\\':
					if(isEscapableChar(lookaheadChar()))
						goto _Word;

					nextChar();

					if(isEOC())
						errorHere("Unexpected end-of-comment after backslash");
					else if(!isCommandChar())
						errorHere("Invalid character '{}' after backslash", mCharacter);

					auto commandStart = curPos();

					while(isCommandChar())
						nextChar();

					mTok.string = mCommentSource[commandStart .. curPos()];

					if(mTok.string == "_")
						error("Custom command must have at least one character after the underscore");

					if(mCharacter == '{')
					{
						// text span or \li{
						nextChar();

						if(mTok.string == "li")
							mTok.type = Token.DefListItem;
						else
						{
							if(mTok.string[0] != '_' && !(mTok.string in textSpans))
								error("Invalid text span name '{}'", mTok.string);

							mTok.type = Token.TextSpanBegin;
						}
					}
					else if(mCharacter == '[')
					{
						// has to be one of param, throws, link, code, or nlist
						nextChar();

						eatWhitespace();
						mTok.arg = readUntil(']');
						eatWhitespace();

						if(mCharacter != ']')
							errorHere("Expected ']' after command argument, not '{}'", mCharacter);

						nextChar();

						switch(mTok.string)
						{
							case "param", "throws":
								mTok.type = Token.SectionBegin;
								if(mCharacter == ':')
									nextChar();
								break;

							case "link":
								mTok.type = Token.TextSpanBegin;

								if(mCharacter != '{')
									errorHere("Expected '{{' after text span command, not '{}'", mCharacter);

								nextChar();
								break;

							case "code":
								mTok.type = Token.Code;
								readRawBlock("Code", "endcode");
								break;

							case "nlist": mTok.type = Token.NList; break;
							default:      error("Invalid command name '{}'", mTok.string);
						}
					}
					else if(mTok.string[0] == '_' || mTok.string in stdSections)
					{
						if(mCharacter == ':')
							nextChar();

						mTok.type = Token.SectionBegin;
					}
					else if(auto type = mTok.string in textStructures)
					{
						mTok.type = *type;

						if(mTok.type == Token.Code)
						{
							mTok.arg = "croc";
							readRawBlock("Code", "endcode");
						}
						else if(mTok.type == Token.Verbatim)
							readRawBlock("Verbatim", "endverbatim");
					}
					else
						error("Invalid command '{}'", mTok.string);
					return;

				default:
					if(isWhitespace())
					{
						eatWhitespace();
						mTok.type = Token.Whitespace;
						return;
					}

				_Word:
					auto wordStart = curPos();

					while(!isWhitespace() && !isEOL())
					{
						if(mCharacter == '\\')
						{
							if(isEscapableChar(lookaheadChar()))
							{
								// Have to do this cause otherwise it would pick up on the second backslash as the beginning of a command
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

					mTok.string = mCommentSource[wordStart .. curPos()];
					mTok.type = Token.Word;
					return;
			}
		}
	}

	void nextNonNewlineToken()
	{
		while(mTok.type == Token.Newline || mTok.type == Token.NewParagraph)
			next();
	}

	void nextNonWhitespaceToken()
	{
		while(mTok.type == Token.Newline || mTok.type == Token.NewParagraph || mTok.type == Token.Whitespace)
			next();
	}

	// ================================================================================================================================================
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
		return mTok.type == Token.NewParagraph || mTok.type == Token.EOC || mTok.type == Token.SectionBegin;
	}

	bool isFirstOnLine()
	{
		return mNewlineSinceLastTok;
	}

	// ================================================================================================================================================
	// Error handling

	void error(char[] msg, ...)
	{
		parser.verror(mTok.line, mTok.col, msg, _arguments, _argptr);
	}

	void error(uword line, uword col, char[] msg, ...)
	{
		parser.verror(line, col, msg, _arguments, _argptr);
	}

	void errorHere(char[] msg, ...)
	{
		parser.verror(mLine, mCol, msg, _arguments, _argptr);
	}
}

struct CommentParser
{
private:
	static const char[] NumberedListTypes = ['1', 'a', 'i', 'A', 'I'];
	static const uword NumberedListMax = NumberedListTypes.length;

	CrocThread* t;
	CommentLexer l;

	bool mIsFunction = false;
	uword mNumberedListNest = 0;
	bool mInTable = false;

	uword docTable;
	uword section;

	static CommentParser opCall(CrocThread* t)
	{
		CommentParser ret;
		ret.t = t;
		return ret;
	}

	void parse(char[] comment)
	{
		docTable = absIndex(t, -1);
		assert(isTable(t, docTable));
		section = docTable + 1;
		field(t, docTable, "kind");
		mIsFunction = getString(t, -1) == "function";
		pop(t);

		l.parser = this;
		l.begin(comment);

		version(none)
		{
			newArray(t, 0);

			do
			{
				pushFormat(t, "({}:{}) {} '{}'", mTok.line, mTok.col, mTok.typeString, mTok.string);

				if(mTok.arg.length > 0)
				{
					pushFormat(t, ": '{}'", mTok.arg);
					cat(t, 2);
				}

				cateq(t, -2, 1);

				next();

			} while(mTok.type != Token.EOC)

			insertAndPop(t, docTable);
		}
		else
		{
			beginStdSection("docs");

			while(l.type != Token.EOC)
			{
				checkForSectionChange();
				readParagraph();
			}

			endSection();

			// If it's a function doc table, make sure all the params have docs members; give them empty docs if not
			if(mIsFunction)
				ensureParamDocs();
		}
	}

	word parseText(char[] comment)
	{
		// dummy doctable
		docTable = newTable(t);
		section = docTable + 1;

		l.parser = this;
		l.begin(comment);

		beginStdSection("docs");

		while(l.type != Token.EOC)
		{
			if(l.type == Token.SectionBegin)
				error("Section commands are not allowed when parsing plain comment text");

			readParagraph();
		}

		endSection();

		field(t, -1, "docs");
		insertAndPop(t, docTable);

		return stackSize(t) - 1;
	}

	void checkForSectionChange()
	{
		if(l.type != Token.SectionBegin)
			return;

		assert(l.tok.string.length > 0);

		if(!l.isFirstOnLine())
			error("Section command must come at the beginning of a line");

		if(l.tok.string[0] == '_')
		{
			endSection();
			beginCustomSection(l.tok.string[1 .. $]);
		}
		else if(l.tok.string in funcSections)
		{
			if(!mIsFunction)
				error("Section '{}' is only usable in function doc tables", l.tok.string);

			endSection();

			switch(l.tok.string)
			{
				case "param": beginParamSection(l.tok.arg); break;
				case "throws": beginThrowsSection(l.tok.arg); break;
				case "returns": beginStdSection(l.tok.string); break;
				default: assert(false);
			}
		}
		else
		{
			endSection();
			beginStdSection(l.tok.string);
		}

		l.next();
	}

	void readParagraph()
	{
		auto pgph = beginParagraph();
		readParaElems(pgph, false);

		if(l.type == Token.NewParagraph)
			l.next();
		else
			assert(l.type == Token.EOC || l.type == Token.SectionBegin || l.tok.isSubStructure());

		endParagraph(pgph);
	}

	void readParaElems(uword slot, bool inTextSpan)
	{
		const MaxFrags = 50;
		uword numFrags = 0;

		void addText()
		{
			if(numFrags > 0)
			{
				concatTextFragments(slot);
				append(slot);
				numFrags = 0;
			}
		}

		void commonTextStructure(void delegate() reader)
		{
			if(inTextSpan)
				error("Text structure command '{}' is not allowed inside text spans", l.tok.typeString);

			addText();
			reader();
			append(slot);
		}

		l.nextNonWhitespaceToken();

		_outerLoop: while(true)
		{
			switch(l.type)
			{
				case Token.Newline, Token.Whitespace:
					pushString(t, " ");
					goto _commonWord;

				case Token.RBrace:
					if(inTextSpan)
						break _outerLoop;

					pushString(t, "}");
					goto _commonWord;

				case Token.Word:
					pushString(t, l.tok.string);

				_commonWord:
					l.next();

					numFrags++;

					if(numFrags >= MaxFrags)
					{
						concatTextFragments(slot);
						numFrags = 1;
					}
					break;

				case Token.TextSpanBegin:
					addText();
					readTextSpan();
					append(slot);
					break;

    			case Token.Code:          commonTextStructure(&readCodeBlock); break;
    			case Token.Verbatim:      commonTextStructure(&readVerbatimBlock); break;
    			case Token.BList:
    			case Token.NList:
    			case Token.DList:         commonTextStructure(&readList); break;
    			case Token.Table:         commonTextStructure(&readTable); break;

    			default:
    				if(l.isEOP() || l.tok.isSubStructure())
    				{
						// if inside a text span, readTextSpan will deal with this, it can give a better error
						break _outerLoop;
					}
					else
	    				error("Invalid '{}' in paragraph", l.tok.typeString);
			}
		}
	}

	void readTextSpan()
	{
		assert(l.type == Token.TextSpanBegin);

		auto tok = l.tok;
		auto span = beginTextSpan(tok.string);

		if(tok.string == "link" && tok.arg)
		{
			pushString(t, tok.arg);
			append(span);
		}

		l.next();

		readParaElems(span, true);

		if(l.type != Token.RBrace)
			error(tok.line, tok.col, "Text span '{}' has no closing brace", tok.string);

		l.next();

		endTextSpan(span);
	}

	void readCodeBlock()
	{
		assert(l.type == Token.Code);

		if(!l.isFirstOnLine())
			error("Code command must come at the beginning of a line");

		newArray(t, 3);
		pushString(t, "code");
		idxai(t, -2, 0);
		pushString(t, l.tok.arg);
		idxai(t, -2, 1);
		pushString(t, l.tok.contents);
		idxai(t, -2, 2);

		l.next();

		if(l.type != Token.Newline && l.type != Token.NewParagraph && l.type != Token.EOC)
			error("\\endcode must be followed by a newline or end-of-comment, not '{}'", l.tok.typeString());

		l.next();
	}

	void readVerbatimBlock()
	{
		assert(l.type == Token.Verbatim);

		if(!l.isFirstOnLine())
			error("Verbatim command must come at the beginning of a line");

		newArray(t, 2);
		pushString(t, "verbatim");
		idxai(t, -2, 0);
		pushString(t, l.tok.contents);
		idxai(t, -2, 1);

		l.next();

		if(l.type != Token.Newline && l.type != Token.NewParagraph && l.type != Token.EOC)
			error("\\endverbatim must be followed by a newline or end-of-comment, not '{}'", l.tok.typeString());

		l.next();
	}

	void readList()
	{
		assert(l.type == Token.BList || l.type == Token.NList || l.type == Token.DList);

		if(!l.isFirstOnLine())
			error("List command must come at the beginning of a line");

		uword numListSave = mNumberedListNest;
		scope(exit) mNumberedListNest = numListSave;

		bool isDefList = l.type == Token.DList;
		uword arr;

		if(l.type == Token.NList)
		{
			auto type = l.tok.arg;

			if(type.length > 0)
			{
				if(type.length > 1)
					error("Invalid numbered list type '{}'", type);

				auto level = NumberedListTypes.find(type[0]);

				if(level == NumberedListMax)
					error("Invalid numbered list type '{}'", type);

				mNumberedListNest = level;
			}

			arr = newArray(t, 2);
			pushString(t, "nlist");
			idxai(t, -2, 0);
			pushFormat(t, "{}", NumberedListTypes[mNumberedListNest]);
			idxai(t, -2, 1);

			mNumberedListNest = (mNumberedListNest + 1) % NumberedListMax;
		}
		else
		{
			mNumberedListNest = 0;
			arr = newArray(t, 1);

			if(isDefList)
				pushString(t, "dlist");
			else
				pushString(t, "blist");

			idxai(t, -2, 0);
		}

		auto tok = l.tok;
		l.next();

		if(l.type != Token.Newline && l.type != Token.NewParagraph)
			error("List start command must be followed by a newline");

		l.next();
		l.nextNonNewlineToken();

		bool first = true;
		uword item;

		void beginItem()
		{
			item = newArray(t, 0);
			dup(t);
			append(arr);
		}

		void endItem()
		{
			if(len(t, item) == 0)
			{
				newArray(t, 1);
				pushString(t, "");
				idxai(t, -2, 0);
				append(item);
			}

			pop(t);
		}

		void switchItems()
		{
			if(first)
				first = false;
			else
				endItem();

			beginItem();
		}

		while(l.type != Token.EOC && l.type != Token.EndList)
		{
			if(l.type == Token.ListItem)
			{
				if(isDefList)
					error("Cannot use a regular list item in a definition list");

				switchItems();
				l.next();
			}
			else if(l.type == Token.DefListItem)
			{
				if(!isDefList)
					error("Cannot use a definition list item in a numbered/bulleted list");

				switchItems();
				auto liTok = l.tok;
				l.next();

				auto defItem = newArray(t, 0);
				readParaElems(defItem, true);

				if(l.type != Token.RBrace)
					error(liTok.line, liTok.col, "Definition list item has no closing brace");

				l.next();

				if(stackSize(t) - 1 > defItem)
				{
					concatTextFragments(defItem);
					append(defItem);
				}

				if(len(t, defItem) == 0)
					error(liTok.line, liTok.col, "Definition list item must contain a term");
				else
					trimFinalText(defItem);

				append(item);
			}
			else if(l.type == Token.SectionBegin)
				error("Cannot change sections inside a list");
			else if(first)
				error("Cannot have text before a list item");
			else
				readParagraph();
		}

		if(first)
			error(tok.line, tok.col, "List must have at least one item");
		else if(l.type == Token.EOC)
			error(tok.line, tok.col, "List has no matching \\endlist command");

		endItem();
		l.next();
	}

	void readTable()
	{
		assert(l.type == Token.Table);

		if(!l.isFirstOnLine())
			error("Table command must come at the beginning of a line");

		if(mInTable)
			error("Tables cannot be nested");

		mInTable = true;
		scope(exit) mInTable = false;

		auto beginTok = l.tok;
		l.next();

		if(l.type != Token.Newline && l.type != Token.NewParagraph)
			error("Table start command must be followed by a newline");

		l.next();
		l.nextNonNewlineToken();

		auto tab = newArray(t, 1);
		pushString(t, "table");
		idxai(t, -2, 0);

		bool firstRow = true;
		bool firstCell = true;
		uword maxRowLength = 0;
		uword curRowLength = 0;
		uword row;
		uword cell;

		void beginRow()
		{
			row = newArray(t, 0);
			dup(t);
			append(tab);
			firstCell = true;
			curRowLength = 0;
		}

		void beginCell()
		{
			cell = newArray(t, 0);
			dup(t);
			append(row);
			curRowLength++;
			maxRowLength = curRowLength > maxRowLength ? curRowLength : maxRowLength;
		}

		void endRow()
		{
			assert(!firstRow);
			pop(t);
			row = 0;
		}

		void endCell()
		{
			assert(!firstCell);

			if(len(t, cell) == 0)
			{
				newArray(t, 1);
				pushString(t, "");
				idxai(t, -2, 0);
				append(cell);
			}

			pop(t);
			cell = 0;
		}

		void switchRows()
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
		}

		void switchCells()
		{
			if(firstCell)
				firstCell = false;
			else
				endCell();

			beginCell();
			l.next();
		}

		while(l.type != Token.EOC && l.type != Token.EndTable)
		{
			if(l.type == Token.SectionBegin)
				error("Cannot change sections inside a table");
			else if(l.type == Token.Cell)
			{
				if(firstRow)
					error("Cannot have a cell outside a row");
				else
					switchCells();
			}
			else if(l.type == Token.Row)
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
		else if(l.type == Token.EOC)
			error(beginTok.line, beginTok.col, "Table has no matching \\endtable command");

		if(!firstCell)
			endCell();

		endRow();
		l.next();

		// Now normalize table columns.
		auto tableLen = len(t, tab);
		for(uword i = 1; i < tableLen; i++)
		{
			row = idxi(t, tab, i);
			auto rowLen = len(t, row);
			assert(rowLen <= maxRowLength);

			if(rowLen < maxRowLength)
			{
				lenai(t, row, maxRowLength);

				for(uword j = cast(uword)rowLen; j < maxRowLength; j++)
				{
					newArray(t, 1);
					newArray(t, 1);
					pushString(t, "");
					idxai(t, -2, 0);
					idxai(t, -2, 0);
					idxai(t, row, j);
				}
			}

			pop(t);
		}
	}

	// ================================================================================================================================================
	// Helpers

	void append(uword pgph)
	{
		lenai(t, pgph, len(t, pgph) + 1);
		idxai(t, pgph, -1);
	}

	void beginStdSection(char[] name)
	{
		assert(stackSize(t) - 1 == docTable);

		if(hasField(t, docTable, name))
			error("Section '{}' already exists", name);

		newArray(t, 0);
		dup(t);
		fielda(t, docTable, name);
	}

	void beginCustomSection(char[] name)
	{
		assert(stackSize(t) - 1 == docTable);

		if(!hasField(t, docTable, "custom"))
		{
			newTable(t);
			dup(t);
			fielda(t, docTable, "custom");
		}
		else
			field(t, docTable, "custom");

		auto custom = absIndex(t, -1);

		if(hasField(t, custom, name))
			error("Custom section '{}' already exists", name);

		newArray(t, 0);
		dup(t);
		fielda(t, custom, name);
		insertAndPop(t, custom);
	}

	void beginThrowsSection(char[] exName)
	{
		assert(stackSize(t) - 1 == docTable);
		assert(mIsFunction);

		if(!hasField(t, docTable, "throws"))
		{
			newArray(t, 0);
			dup(t);
			fielda(t, docTable, "throws");
		}
		else
			field(t, docTable, "throws");

		auto throws = absIndex(t, -1);
		lenai(t, throws, len(t, throws) + 1);

		newArray(t, 1);
		pushString(t, exName);
		idxai(t, -2, 0);
		dup(t);
		idxai(t, throws, -1);
		insertAndPop(t, throws);
	}

	void beginParamSection(char[] paramName)
	{
		assert(stackSize(t) - 1 == docTable);
		assert(mIsFunction);

		auto params = field(t, docTable, "params");
		auto numParams = len(t, params);
		crocint idx;

		for(idx = 0; idx < numParams; idx++)
		{
			idxi(t, params, idx);

			field(t, -1, "name");

			if(getString(t, -1) == paramName)
			{
				pop(t);
				insertAndPop(t, params);
				break;
			}

			pop(t, 2);
		}

		if(idx == numParams)
			error("Function has no parameter named '{}'", paramName);

		// param doctable is sitting on the stack where params used to be
		alias params param;

		if(hasField(t, param, "docs"))
			error("Parameter '{}' has already been documented", paramName);

		newArray(t, 0);
		dup(t);
		fielda(t, param, "docs");
		insertAndPop(t, param);
	}

	void endSection()
	{
		assert(stackSize(t) - 1 == section);

		if(len(t, section) == 0)
		{
			newArray(t, 1);
			pushString(t, "");
			idxai(t, -2, 0);
			append(section);
		}

		pop(t);
	}

	uword beginParagraph()
	{
		assert(isArray(t, -1));

		lenai(t, -1, len(t, -1) + 1);
		newArray(t, 0);
		dup(t);
		idxai(t, -3, -1);

		return absIndex(t, -1);
	}

	void endParagraph(uword pgph)
	{
		assert(isArray(t, pgph));

		if(stackSize(t) - 1 > pgph)
		{
			concatTextFragments(pgph);
			append(pgph);
		}

		if(len(t, pgph) == 0)
		{
			pushString(t, "");
			append(pgph);
		}
		else
			trimFinalText(pgph);

		pop(t);
	}

	uword beginTextSpan(char[] type)
	{
		newArray(t, 1);
		pushString(t, type);
		idxai(t, -2, 0);
		return absIndex(t, -1);
	}

	void endTextSpan(uword span)
	{
		assert(isArray(t, span));

		if(stackSize(t) - 1 > span)
		{
			concatTextFragments(span);
			append(span);
		}

		if(len(t, span) == 1)
		{
			pushString(t, "");
			append(span);
		}
		else
			trimFinalText(span);

		idxi(t, span, 0);

		if(getString(t, -1) == "link" && len(t, span) == 2)
		{
			idxi(t, span, -1);
			append(span);
		}

		pop(t);
	}

	void trimFinalText(uword pgph)
	{
		assert(isArray(t, pgph));
		assert(len(t, pgph) > 0);

		idxi(t, pgph, -1);

		if(isString(t, -1))
		{
			pushNull(t);
			methodCall(t, -2, "rstrip", 1);

			if(len(t, -1) > 0)
				idxai(t, pgph, -1);
			else
			{
				pop(t);
				lenai(t, pgph, len(t, pgph) - 1);
			}
		}
		else
			pop(t);
	}

	void concatTextFragments(uword pgph)
	{
		debug for(uword slot = pgph + 1; slot < stackSize(t); slot++)
			assert(isString(t, slot));

		auto numPieces = stackSize(t) - (pgph + 1);
		assert(numPieces > 0);

		cat(t, numPieces);

		pushNull(t);
		pushString(t, "\\\\");
		pushString(t, "\\");
		methodCall(t, -4, "replace", 1);

		pushNull(t);
		pushString(t, "\\{");
		pushString(t, "{");
		methodCall(t, -4, "replace", 1);

		pushNull(t);
		pushString(t, "\\}");
		pushString(t, "}");
		methodCall(t, -4, "replace", 1);
	}

	void ensureParamDocs()
	{
		assert(mIsFunction);

		auto params = field(t, docTable, "params");
		auto paramsLength = len(t, -1);

		for(uword i = 0; i < paramsLength; i++)
		{
			auto param = idxi(t, params, i);

			if(!hasField(t, param, "docs"))
			{
				newArray(t, 1);
				newArray(t, 1);
				pushString(t, "");
				idxai(t, -2, 0);
				idxai(t, -2, 0);
				fielda(t, param, "docs");
			}

			pop(t);
		}

		pop(t);
	}

	// ================================================================================================================================================
	// Error handling

	void error(char[] msg, ...)
	{
		verror(l.tok.line, l.tok.col, msg, _arguments, _argptr);
	}

	void error(uword line, uword col, char[] msg, ...)
	{
		verror(line, col, msg, _arguments, _argptr);
	}

	void verror(uword line, uword col, char[] msg, TypeInfo[] arguments, va_list argptr)
	{
		auto ex = getStdException(t, "SyntaxException");
		pushNull(t);
		pushVFormat(t, msg, arguments, argptr);
		rawCall(t, ex, 1);
		dup(t);
		pushNull(t);
		pushLocationObject(t, "<doc comment>", line, col);
		methodCall(t, -3, "setLocation", 0);
		throwException(t);
	}
}