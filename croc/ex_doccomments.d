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
	ParaElem+ EOP

ParaElem:
	Newline
	Word
	TextSpan
	TextStructure

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
		assert(!mHaveLookahead, "looking ahead too far");

		mLookaheadCharacter = readChar();
		mHaveLookahead = true;
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

	// ================================================================================================================================================
	// Token-level lexing

	void eatWhitespace()
	{
		while(isWhitespace())
			nextChar();
	}
	
	char[] readWord()
	{
		return "";
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

					auto commandStart = mPosition - 1;

					while(isCommandChar())
						nextChar();

					mTok.string = mCommentSource[commandStart .. mPosition - 1];

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

						eatWhitespace();
						mTok.arg = readWord();
						eatWhitespace();

						if(mCharacter != ']')
							errorHere("Expected ']' after command argument, not '{}'", mCharacter);

						nextChar();

						switch(mTok.string)
						{
							case "param", "throws": mTok.type = Token.SectionBegin; break;

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
					auto wordStart = mPosition - 1;

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
						else
							nextChar();
					}

					mTok.string = mCommentSource[wordStart .. mPosition - 1];
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

// 		beginStdSection("docs");
//
// 		while(mTok.type != Token.EOC)
// 		{
// 			checkForSectionChange();
// 			readParagraph();
// 		}
//
// 		endSection();
	}

// 	void checkForSectionChange()
// 	{
// 		assert(mLine.length > 0);
// 
// 		if(mLine[0] == '\\')
// 		{
// 			if(mLine.length > 1 && isEscapableChar(mLine[1]))
// 				return;
// 
// 			bool isSpan;
// 			auto cmd = peekCommand(isSpan);
// 
// 			if(isSpan)
// 				return;
//
// 			if(cmd in stdSections)
// 			{
// 				if(cmd in funcSections)
// 				{
// 					if(!mIsFunction)
// 						error("Section '{}' can only be used in function doc comments", cmd);
// 
// 					switch(cmd)
// 					{
// 						case "param":
// 
// 						case "throws":
// 
// 						case "returns":
// 							break; // go to normal section processing
// 
// 						default: assert(false);
// 					}
// 				}
// 			}
// 			else if(cmd[0] == '_')
// 			{
// 
// 			}
// 			else
// 				error("Unrecognized command '{}'", cmd);
// 		}
// 	}

	void blah()
	{

/*					if(line.startsWith("\\"))
					{
						if(line.startsWith("\\\\") || line.startsWith("\\{") || line.startsWith("\\}"))
							goto _Plaintext;
// 						Else if line starts with structural command,
// 							If there is text after it,
// 								Error.
// 							End current stretch of text and add to end of paragraph array.
// 							Switch to the appropriate mode.
// 						Else if line starts with a section command,
// 							If current section has no text,
// 								Add the empty string to the end of current paragraph.
// 							If new section has already been encountered,
// 								Error.
// 							Change section.
// 							Add field to doctable for new section.
// 							If there is text after the section command,
// 								Add it as a paragraph fragment.
// 						Else if line starts with a text span command,
// 							Go to plaintext processing.
// 						Else,
// 							Error.
					}
					else
						goto _Plaintext;
					break;

				_Plaintext:
// 						...
					break;

				case CodeVerbatim:
// 					If line consists of nothing but the appropriate ending command,
// 						Switch to paragraph mode.
// 					Else,
// 						Append untrimmed line to verbatim text.
					break;
				
				case ListBegin:
// 					If line starts with backslash,
// 						If line starts with \li,
// 							If inappropriate type for this list,
// 								Error.
// 							Start new list item.
// 							If there is any extra text after \li,
// 								Add it to the list item's first paragraph.
// 							Switch to ListItem mode.
// 						Else if line starts with \endlist,
// 							Error (no list items).
// 					Error (must have \li as the first thing inside a list).
					break;
				
				case ListItem:
// 					If line is empty
// 					If line starts with backslash,
// 						If backslash is followed by \, {, or },
// 							Go to plaintext processing.
// 						Else if line starts with \endlist,
// 							If there is text after it,
// 								Error.
// 							If current list item has no text,
// 								Add the empty string to the end of current paragraph.
// 							End the list array and add it to the owning paragraph.
// 							Decrease list nesting.
// 							If current list is a numbered list, decrease numbered list nesting.
// 							If list nesting is 0,
// 								Switch to Paragraph mode.
// 						Else if line starts with \li,
// 							If inappropriate type for this list,
// 								Error.
// 							If current list item has no text,
// 								Add the empty string to the end of current paragraph.
// 							Start new list item.
// 							If there is text after \li,
// 								Add it as a paragraph fragment.
// 						Else if line starts with a text span command,
// 							Go to plaintext processing.
// 						Else,
// 							Error.
// 					Else,
// 						Go to plaintext processing.
					break;

				case TableBegin:
// 					If already inside a table,
// 						Error.
// 					Set "inside table" to true.
// 					If line starts with backslash,
// 						If line starts with \row,
// 							If there is any extra text after \row,
// 								Error.
// 							Start new row.
// 							Switch to RowBegin mode.
// 						Else if line starts with \endtable,
// 							Error (no rows).
// 					Error (must have \row as the first thing inside a table).
					break;

				case RowBegin:
// 					If line starts with backslash,
// 						If line starts with \cell,
// 							Start new cell.
// 							If there is text after \cell,
// 								Add it as a paragraph fragment.
// 							Switch to Cell mode.
// 						Else if line starts with \endtable or \row,
// 							Error (no cells).
// 					Error (must have \cell as the first thing inside a row).
					break;

				case Cell:
// 					If line starts with backslash,
// 						If backslash is followed by \, {, or },
// 							Go to plaintext processing.
// 						Else if line starts with \endtable,
// 							If there is text after it,
// 								Error.
// 							If current cell has no text,
// 								Add the empty string to the end of current paragraph.
// 							End the table, normalizing row lengths, and add it to the owning paragraph.
// 							Set "inside table" to false.
// 							Switch to Paragraph mode.
// 						Else if line starts with \cell,
// 							If current cell has no text,
// 								Add the empty string to the end of current paragraph.
// 							Start new cell.
// 							If there is text after \cell,
// 								Add it as a paragraph fragment.
// 						Else if line starts with a text span command,
// 							Go to plaintext processing.
// 						Else,
// 							Error.
// 					Else,
// 						Go to plaintext processing.
					break;

				default: assert(false);
			}
		} */

		// If it's a function doc table, make sure all the params have docs members; give them empty docs if not
		if(mIsFunction)
			ensureParamDocs();
	}

	void beginStdSection(char[] name)
	{
		assert(stackSize(t) - 1 == docTable);

		if(hasField(t, docTable, name))
			error("Section '{}' already exists", name);

		newArray(t, 0);
		dup(t);
		fielda(t, docTable, name);

		beginParagraph();
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

		beginParagraph();
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

		beginParagraph();
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

		beginParagraph();
	}

	void endSection()
	{
		endParagraph(section + 1);

		assert(stackSize(t) - 1 == section);

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
			cateq(t, pgph, 1);
		}

		if(len(t, pgph) == 0)
		{
			pushString(t, "");
			cateq(t, pgph, 1);
		}

		pop(t);
	}

	void concatTextFragments(uword pgph)
	{
		debug for(uword slot = pgph + 1; slot < stackSize(t); slot++)
			assert(isString(t, slot));

		cat(t, stackSize(t) - pgph - 1);
		
		// TODO: replace \\, \{, \}
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

	void errorHere(char[] msg, ...)
	{
		verror(mLine, mCol, msg, _arguments, _argptr);
	}

// 	void error(uword col, char[] msg, ...)
// 	{
// 		verror(mTok.line, col, msg, _arguments, _argptr);
// 	}
//
// 	void error(uword line, uword col, char[] msg, ...)
// 	{
// 		verror(line, col, msg, _arguments, _argptr);
// 	}

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