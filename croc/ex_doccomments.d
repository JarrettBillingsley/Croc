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
import croc.ex;
import croc.types;
import croc.utils;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

// Expects a doc table on the stack, doesn't change stack size.
void processComment(CrocThread* t, char[] comment)
{
	auto p = CommentProcessor(t);
	p.parse(comment);
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

	enum
	{
		EOC,
		Newline,
		NewParagraph,
		Word,
		SectionBegin,
		TextSpanBegin,
		RBrace,
		Code,
		EndCode,
		Verbatim,
		EndVerbatim,
		BList,
		NList,
		DList,
		EndList,
		ListItem,
		DefListItem,
		Table,
		EndTable,
		Row,
		Cell
	}

	static const char[][] strings =
	[
		EOC: "<end of comment>",
		Newline: "<newline>",
		NewParagraph: "<new paragraph>",

		Word: "Word",
		SectionBegin: "Section command",
		TextSpanBegin: "Text span command",
		RBrace: "}",
		Code: "Code snippet command",
		EndCode: "Code snippet end command",
		Verbatim: "Verbatim command",
		EndVerbatim: "Verbatim end command",
		BList: "Bulleted list command",
		NList: "Numbered list command",
		DList: "Definition list command",
		EndList: "End list command",
		ListItem: "List item command",
		DefListItem: "Definition list item command",
		Table: "Table command",
		EndTable: "Table end command",
		Row: "Row command",
		Cell: "Cell command"
	];

	char[] typeString()
	{
		return strings[type];
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
		"endcode": Token.EndCode,
		"endlist": Token.EndList,
		"endtable": Token.EndTable,
		"endverbatim": Token.EndVerbatim,
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

struct CommentProcessor
{
private:
	CrocThread* t;

	uword mLine;
	uword mCol;
	char[] mCommentSource;
	uword mPosition;
	dchar mCharacter;
	dchar mLookaheadCharacter;
	bool mHaveLookahead;

	Token mTok;

	bool mIsFunction = false;
	uword mListNest = 0;
	uword mNumberedListNest = 0;

	uword docTable;
	uword section;

	static CommentProcessor opCall(CrocThread* t)
	{
		CommentProcessor ret;
		ret.t = t;
		return ret;
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

	dchar readChar()
	{
		if(mPosition >= mCommentSource.length)
		{
			// Useful for avoiding edge cases at the ends of comments
			mPosition++;
			return dchar.init;
		}
		else
		{
			uint ate = 0;
			auto ret = Utf.decode(mCommentSource[mPosition .. $], ate);
			mPosition += ate;
			return ret;
		}
	}

	dchar lookaheadChar()
	{
		if(!mHaveLookahead)
		{
			mLookaheadCharacter = readChar();
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
			mHaveLookahead = false;
		}
		else
		{
			mCharacter = readChar();
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
		if(mHaveLookahead)
			return mPosition - 2;
		else
			return mPosition - 1;
	}

	// ================================================================================================================================================
	// Token-level lexing

	void eatWhitespace()
	{
		while(isWhitespace())
			nextChar();
	}

	char[] readWord()
	{
		auto wordBegin = curPos();

		while(!isWhitespace() && !isEOL())
			nextChar();

		return mCommentSource[wordBegin .. curPos()];
	}

	char[] readUntil(dchar c)
	{
		auto wordBegin = curPos();

		while(!isEOL() && mCharacter != c)
			nextChar();
			
			
		return mCommentSource[wordBegin .. curPos()];
	}

	void nextToken()
	{
		mTok.string = "";
		mTok.arg = "";

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

					nextLine();
					eatWhitespace();

					while(isNewline())
					{
						mTok.type = Token.NewParagraph;
						nextLine();
						eatWhitespace();
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

							case "code":  mTok.type = Token.Code;  break;
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
					}
					else
						error("Invalid command '{}'", mTok.string);
					return;

				default:
					if(isWhitespace())
					{
						eatWhitespace();
						continue;
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
		nextToken();

		while(mTok.type == Token.Newline || mTok.type == Token.NewParagraph)
			nextToken();
	}

	bool isEOP()
	{
		return mTok.type == Token.NewParagraph || mTok.type == Token.EOC || mTok.type == Token.SectionBegin;
	}

	// ================================================================================================================================================
	// Parsing

	void parse(char[] comment)
	{
		mCommentSource = comment;
		docTable = absIndex(t, -1);
		assert(isTable(t, docTable));
		section = docTable + 1;
		field(t, docTable, "kind");
		mIsFunction = getString(t, -1) == "function";
		pop(t);

		// Start up the lexer
		mLine = 1;
		mCol = 0;
		mPosition = 0;
		mHaveLookahead = false;

		nextChar();
		nextNonNewlineToken();

		// Now for the parsing

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

				nextToken();

			} while(mTok.type != Token.EOC)

			insertAndPop(t, docTable);
		}
		else
		{
			beginStdSection("docs");

			while(mTok.type != Token.EOC)
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

	void checkForSectionChange()
	{
		if(mTok.type != Token.SectionBegin)
			return;

		assert(mTok.string.length > 0);

		if(mTok.string[0] == '_')
		{
			endSection();
			beginCustomSection(mTok.string[1 .. $]);
		}
		else if(mTok.string in funcSections)
		{
			if(!mIsFunction)
				error("Section '{}' is only usable in function doc tables", mTok.string);

			endSection();

			switch(mTok.string)
			{
				case "param": beginParamSection(mTok.arg); break;
				case "throws": beginThrowsSection(mTok.arg); break;
				case "returns": beginStdSection(mTok.string); break;
				default: assert(false);
			}
		}
		else
		{
			endSection();
			beginStdSection(mTok.string);
		}

		nextToken();
	}

	void readParagraph()
	{
		auto pgph = beginParagraph();
		readParaElems(pgph, false);

		if(mTok.type == Token.NewParagraph)
			nextToken();
		else
			assert(mTok.type == Token.EOC || mTok.type == Token.SectionBegin);

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
			}
		}

		void commonTextStructure(void delegate() reader)
		{
			if(inTextSpan)
				error("Text structure command '{}' is not allowed inside text spans", mTok.typeString);

			addText();
			reader();
			append(slot);
		}

		_outerLoop: while(true)
		{
			switch(mTok.type)
			{
				case Token.Newline:
					nextToken();
					break;

				case Token.RBrace:
					if(inTextSpan)
						break _outerLoop;
					// else fall through and treat it like a word
				case Token.Word:
					pushString(t, mTok.string);
					numFrags++;

					if(numFrags >= MaxFrags)
					{
						concatTextFragments(slot);
						numFrags = 1;
					}

					nextToken();
					break;

				case Token.TextSpanBegin:
					addText();
					readTextSpan();
					append(slot);
					break;

    			case Token.Code:          commonTextStructure(&readCodeBlock); break;
    			case Token.Verbatim:      commonTextStructure(&readVerbatimBlock); break;
    			case Token.BList:         commonTextStructure(&readBulletedList); break;
    			case Token.NList:         commonTextStructure(&readNumberedList); break;
    			case Token.DList:         commonTextStructure(&readDefinitionList); break;
    			case Token.Table:         commonTextStructure(&readTable); break;

    			default:
    				if(isEOP())
    				{
						// if inside a text span, readTextSpan will deal with this, it can give a better error
						break _outerLoop;
					}
					else
	    				error("Invalid '{}' in paragraph", mTok.typeString);
			}
		}
	}

	void readTextSpan()
	{
		assert(mTok.type == Token.TextSpanBegin);

		auto span = beginTextSpan(mTok.string);
		auto spanString = mTok.string, spanLine = mTok.line, spanCol = mTok.col;
		nextToken();

		readParaElems(span, true);

		if(mTok.type != Token.RBrace)
			error(spanLine, spanCol, "Text span '{}' has no closing brace", spanString);

		nextToken();

		endTextSpan(span);
	}

	void readCodeBlock()
	{
		assert(false);
	}

	void readVerbatimBlock()
	{
		assert(false);
	}

	void readBulletedList()
	{
		assert(false);
	}

	void readNumberedList()
	{
		assert(false);
	}

	void readDefinitionList()
	{
		assert(false);
	}

	void readTable()
	{
		assert(false);
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
	}

	void concatTextFragments(uword pgph)
	{
		debug for(uword slot = pgph + 1; slot < stackSize(t); slot++)
			assert(isString(t, slot));

		auto numPieces = stackSize(t) - (pgph + 1);

		assert(numPieces > 0);

		if(numPieces > 1)
		{
			pushString(t, " ");
			pushNull(t);
			rotate(t, numPieces + 2, 2);
			methodCall(t, pgph + 1, "vjoin", 1);
		}

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

		field(t, docTable, "params");

		foreach(word param; foreachLoop(t, 1))
		{
			if(!hasField(t, param, "docs"))
			{
				newArray(t, 1);
				newArray(t, 1);
				pushString(t, "");
				idxai(t, -2, 0);
				idxai(t, -2, 0);
				fielda(t, param, "docs");
			}
		}
	}

	void error(char[] msg, ...)
	{
		verror(mTok.line, mTok.col, msg, _arguments, _argptr);
	}

	void error(uword line, uword col, char[] msg, ...)
	{
		verror(line, col, msg, _arguments, _argptr);
	}

	void errorHere(char[] msg, ...)
	{
		verror(mLine, mCol, msg, _arguments, _argptr);
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