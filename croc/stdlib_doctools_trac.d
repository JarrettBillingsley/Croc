/******************************************************************************
This module contains the 'doctools.trac' module of the standard library.

License:
Copyright (c) 2013 Jarrett Billingsley

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

module croc.stdlib_doctools_trac;

import croc.ex;
import croc.types;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initDoctoolsTracLib(CrocThread* t)
{
	importModuleFromStringNoNS(t, "doctools.trac", Code, __FILE__);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

const char[] Code =
`/**
This module defines a means of outputting docs in the Trac wiki syntax format.
*/
module doctools.trac

import doctools.output:
	DocOutputter,
	LinkResolver,
	toHeader

class TracWikiOutputter : DocOutputter
{
	_linkResolver
	_listType
	_inTable = false
	_itemDepth = 0
	_isFirstInSection = false
	_isSpecialSection = false

	this(lr)
	{
		:_linkResolver = lr
		:_listType = []
	}

	// =================================================================================================================
	// Item-level stuff

	override function beginModule(doctable: table)
	{
		:outputText("[[PageOutline]]\n")
		:beginItem(doctable)
		:_linkResolver.enterModule(doctable.name)
	}

	override function endModule()
	{
		:_linkResolver.leave()
		:endItem()
	}

	override function beginFunction(doctable: table) :beginItem(doctable)
	override function endFunction() :endItem()

	override function beginClass(doctable: table)
	{
		:beginItem(doctable)
		:_linkResolver.enterItem(doctable.name)
	}

	override function endClass()
	{
		:_linkResolver.leave()
		:endItem()
	}

	override function beginNamespace(doctable: table)
	{
		:beginItem(doctable)
		:_linkResolver.enterItem(doctable.name)
	}

	override function endNamespace()
	{
		:_linkResolver.leave()
		:endItem()
	}

	override function beginField(doctable: table) :beginItem(doctable)
	override function endField() :endItem()
	override function beginVariable(doctable: table) :beginItem(doctable)
	override function endVariable() :endItem()

	function beginItem(doctable: table)
	{
		:outputHeader(doctable)
		:_itemDepth++
	}

	function endItem()
	{
		:outputText("\n")
		:_itemDepth--
	}

	function outputHeader(doctable: table)
	{
		local h = "=".repeat(:_itemDepth + 1)
		:outputWikiHeader(doctable, h)

		if(doctable.dittos)
		{
			foreach(dit; doctable.dittos)
				:outputWikiHeader(dit, h)
		}

		if(doctable.kind is "module")
			return

		if((doctable.kind is "variable" || doctable.kind is "field") && doctable.value is null)
			return

		:outputFullHeader(doctable)


		if(doctable.dittos)
		{
			foreach(dit; doctable.dittos)
				:outputFullHeader(dit)
		}
	}

	function outputWikiHeader(doctable: table, h: string)
	{
		:outputText(h, " ")
		:beginMonospace()
		:outputText(toHeader(doctable, "", false))
		:endMonospace()
		:outputText(" ", h, "\n")
	}

	function outputFullHeader(doctable: table)
	{
		:beginParagraph()
		:beginBold()
		:beginMonospace()
		:outputText(toHeader(doctable, "", true))
		:endMonospace()
		:endBold()
		:endParagraph()
	}

	// =================================================================================================================
	// Section-level stuff

	override function beginSection(name: string)
	{
		if(name !is "docs")
		{
			:beginParagraph()
			:beginBold()

			if(name.startsWith("_"))
				:outputText(ascii.toUpper(name[1]), name[2..], ":")
			else
				:outputText(ascii.toUpper(name[0]), name[1..], ":")

			:endBold()
			:outputText(" ")
			:_isFirstInSection = true
		}

		:_isSpecialSection = name is "params" || name is "throws"

		if(:_isSpecialSection)
			:beginDefList()
	}

	override function endSection()
	{
		if(:_isSpecialSection)
		{
			:endDefList()
			:_isSpecialSection = false
		}
	}

	override function beginParameter(doctable: table)
	{
		:beginDefTerm()
		:outputText(doctable.name)
		:endDefTerm()
		:beginDefDef()
	}

	override function endParameter() :endDefDef()

	override function beginException(name: string)
	{
		:beginDefTerm()
		:beginLink(:_linkResolver.resolveLink(name))
		:outputText(name)
		:endLink()
		:endDefTerm()
		:beginDefDef()
	}

	override function endException() :endDefDef()

	// =================================================================================================================
	// Paragraph-level stuff

	override function beginParagraph()
	{
		if(:_isFirstInSection)
			:_isFirstInSection = false
		else if(!:_inTable)
		{
			:outputText("\n")
			:outputIndent()
		}
	}

	override function endParagraph()
	{
		if(:_inTable)
			:outputText(" ")
		else
			:outputText("\n")
	}

	override function beginCode(language: string)
	{
		:checkNotInTable()
		:outputText("\n{{{\n#!", language, "\n")
	}

	override function endCode()
		:outputText("\n}}}\n")

	override function beginVerbatim(type: string)
	{
		:checkNotInTable()
		:outputText("\n{{{\n")
	}

	override function endVerbatim()
		:outputText("\n}}}\n")

	override function beginBulletList()
	{
		:checkNotInTable()
		:_listType.append("*")
		:outputText("\n")
	}

	override function endBulletList()
	{
		:_listType.pop()
		:outputText("\n")
	}

	override function beginNumList(type: string)
	{
		:checkNotInTable()
		:_listType.append(type ~ ".")
		:outputText("\n")
	}

	override function endNumList()
	{
		:_listType.pop()
		:outputText("\n")
	}

	override function beginListItem()
	{
		assert(#:_listType > 0)
		:outputIndent()
		:outputText(:_listType[-1], " ")
	}

	override function endListItem() {}

	override function beginDefList()
	{
		:checkNotInTable()
		:_listType.append(null)
		:outputText("\n")
	}

	override function endDefList()
	{
		:_listType.pop()
		:outputText("\n")
	}

	override function beginDefTerm()
	{
		assert(#:_listType > 0)
		:outputIndent()
	}

	override function endDefTerm()
		:outputText("::\n")

	override function beginDefDef()
		:outputIndent()

	override function endDefDef() {}

	override function beginTable()
	{
		if(#:_listType > 0)
			throw ValueError("Sorry, tables inside lists are unsupported in Trac wiki markup")

		:_inTable = true
		:outputText("\n")
	}

	override function endTable()
	{
		:_inTable = false
		:outputText("\n")
	}

	override function beginRow()
		:outputText("||")

	override function endRow()
		:outputText("\n")

	override function beginCell() {}

	override function endCell()
		:outputText("||")

	override function beginBold() :outputText("'''")
	override function endBold() :outputText("'''")
	override function beginEmphasis() :outputText("''")
	override function endEmphasis() :outputText("''")
	override function beginLink(link: string) :outputText("[",  :_linkResolver.resolveLink(link), " ")
	override function endLink() :outputText("]")
	override function beginMonospace() :outputText("` "`" `")
	override function endMonospace() :outputText("` "`" `")
	override function beginStrikethrough() :outputText("~~")
	override function endStrikethrough() :outputText("~~")
	override function beginSubscript() :outputText(",,")
	override function endSubscript() :outputText(",,")
	override function beginSuperscript() :outputText("^")
	override function endSuperscript() :outputText("^")
	override function beginUnderline() :outputText("__")
	override function endUnderline() :outputText("__")

	/**
	By default, this method just outputs each of its params to stdout. If you want to make the output go somewhere else,
	you can derive from this class and override this method.
	*/
	override function outputText(vararg)
	{
		for(i: 0 .. #vararg)
			write(vararg[i])
	}

	function checkNotInTable()
	{
		if(:_inTable)
			throw ValueError("Sorry, text structures inside tables are unsupported in Trac wiki markup")
	}

	function outputIndent()
	{
		if(#:_listType > 0)
			:outputText(" ".repeat(#:_listType * 2 - 1))
	}
}
`;