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
	scope p = new CommentProcessor();
	p.process(t, comment);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

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

const char[][] TextStructureNames =
[
	"blist",
	"cell",
	"code",
	"dlist",
	"endcode",
	"endlist",
	"endtable",
	"endverbatim",
	"li",
	"nlist",
	"row",
	"table",
	"verbatim",
];

bool[char[]] stdSections;
bool[char[]] funcSections;
bool[char[]] textSpans;
bool[char[]] textStructures;

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

	foreach(name; TextStructureNames)
		textStructures[name] = true;
}

scope class CommentProcessor
{
private:
	enum
	{
		BlankLines,
		Paragraph,
		CodeVerbatim,
		ListBegin,
		ListItem,
		TableBegin,
		RowBegin,
		Cell
	}
	
	CrocThread* t;
	uword docTable;

	bool mIsFunction = false;
	bool mInTable = false;

	uword mMode = BlankLines;
	uword mListNest = 0;
	uword mNumberedListNest = 0;
	uword mLongestTableRow = 0;

	this()
	{

	}

	~this()
	{

	}

	void process(CrocThread* t, char[] comment)
	{
		this.t = t;
		docTable = absIndex(t, -1);
		assert(isTable(t, docTable));

		// First check if it's a function -- some sections are allowed on functions that aren't on anything else
		checkIfFunction();
		
		// Now create the docs section
		startStdSection("docs");

		foreach(rawLine; comment.lines())
		{
			auto line = rawLine.trim();

			switch(mMode)
			{
				case BlankLines:
				
					break; 
					
				case Paragraph:
					if(line.length == 0)
					{

					}

					if(line.startsWith("\\"))
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
		}

		// If it's a function doc table, make sure all the params have docs members; give them empty docs if not
		if(mIsFunction)
			ensureParamDocs();
	}

	void checkIfFunction()
	{
		field(t, docTable, "kind");
		mIsFunction = getString(t, -1) == "function";
		pop(t);
	}

	void startStdSection(char[] name)
	{
		dup(t, docTable);

// 		if(hasField(t, -1, name))
// 			throwStdException(t, "ParseException",
	}

	void ensureParamDocs()
	{
		assert(mIsFunction);

		// TODO:
	}
}