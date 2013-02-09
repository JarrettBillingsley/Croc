/******************************************************************************
This module contains Croc-accessible part of the built-in runtime documentation
system.

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

module croc.stdlib_docs;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_doccomments;
import croc.ex_library;
import croc.types;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initDocsLib(CrocThread* t)
{
	auto docs = importModuleFromString(t, "docs", docsSource, "docs.croc");

	// docs.processComment = _doc_(<d func>, docs.docsOf(docs.processComment))
	auto f = pushGlobal(t, "_doc_");
	pushNull(t);
	newFunction(t, 2, &_processComment, "processComment");
	lookup(t, "docs.docsOf");
	pushNull(t);
	lookup(t, "docs.processComment");
	rawCall(t, -3, 1);
	rawCall(t, f, 1);
	fielda(t, docs, "processComment");

	// docs.parseCommentText = _doc_(<d func>, docs.docsOf(docs.parseCommentText))
	f = pushGlobal(t, "_doc_");
	pushNull(t);
	newFunction(t, 2, &_parseCommentText, "parseCommentText");
	lookup(t, "docs.docsOf");
	pushNull(t);
	lookup(t, "docs.parseCommentText");
	rawCall(t, -3, 1);
	rawCall(t, f, 1);
	fielda(t, docs, "parseCommentText");

	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

uword _processComment(CrocThread* t)
{
	auto str = checkStringParam(t, 1);
	checkParam(t, 2, CrocValue.Type.Table);
	dup(t, 2);
	processComment(t, str);
	return 1;
}

uword _parseCommentText(CrocThread* t)
{
	auto str = checkStringParam(t, 1);
	parseCommentText(t, str);
	return 1;
}

/*
	HtmlDocOutput
	ConsoleDocOutput
	RstDocOutput?
	LatexDocOutput?
*/

const char[] docsSource =
`/**
This module contains the runtime interface to Croc's built-in documentation system. It defines the decorator function
which the compiler can translate doc comments into, as well as the actual documentation processing functions. It also
contains a basic doc outputting scaffold, so that you can output documentation in a human-readable format without much
extra work.
*/
module docs

import exceptions:
	TypeException,
	ValueException,
	NotImplementedException

local docTables = {}

// Neat: we can actually use doc comments on _doc_ because of the way decorators work. The global _doc_ is
// defined before the decorator is called. So _doc_ can be used on itself!

/**
This is a decorator function used to attach documentation tables to objects. The compiler can attach calls to this
decorator to declarations in your code automatically by extracting documentation comments and information about the
declarations from the code.

Once the documentation table has been set for an object, you can retrieve it with docsOf, which can then be further
processed and output in a human-readable form (for instance, by using the various doc output classes).

This function is also exported in the global namespace so that you can access it unqualified (that is, both \tt{_doc_}
and \tt{docs._doc_} refer to this function.

\param[val] is the decorated object and can be any reference type.
\param[doctable] is a table, presumably one which matches the specifications for doc tables.
\param[vararg] should all be integers and are used to extract the correct sub-table from the root documentation table
(the \tt{doctable} parameter). So, for instance, using "\tt{@_doc_(someTable, 0, 2)}" on a declaration would mean that
the table \tt{someTable.children[0].children[2]} would be used as the documentation for the decorated declaration. If no
variadic arguments are given, the table itself is set as the documentation table of the object.

\returns \tt{val} as per the decorator protocol.

\throws[exceptions.TypeException] if any of the \tt{varargs} are not ints, or if the value that will be set as the
doctable for \tt{val} is not a table.
*/
function _doc_(
	val: table|namespace|array|memblock|function|funcdef|class|instance|thread,
	doctable: table,
	vararg)
{
	local d = doctable

	for(i: 0 .. #vararg)
	{
		local idx = vararg[i]

		if(!isInt(idx))
			throw TypeException("_doc_ - Parameter {} expected to be 'int', not '{}'".format(i + 2, typeof(idx)))

		d = d.children[idx]
	}

	if(!isTable(d))
		throw TypeException("_doc_ - Doc table is not a table, it is of type '{}'", typeof(d))

	docTables[val] = d
	return val
}

// Export globally
_G._doc_ = _doc_

/**
This retrieves the documentation table, if any, associated with an object.

\param[val] is the object whose docs are to be retrieved. Any type is allowed, but only reference types can have
documentation tables associated with them.

\returns the doc table for \tt{val} if one has been set, or \tt{null} if none has been set (or if \tt{val} is
a value type).
*/
function docsOf(val) =
	docTables[val]

/**
Low-level function which takes the raw text from a doc comment and a doctable (with no docs member) and parses the
doc comment, adding the appropriate members to the given doctable.

This is actually the same function that the compiler itself calls to process doc comments. Note that the doctable
that is to be passed to this function must be properly formed (with all the "standard" members, as well as any
extra kind-specific members as defined in the doc comment spec), but there must be no "docs" members at all. The
"docs" members, as well as members for other sections, will be filled in by this function.

\param[comment] is the raw text of the doc comment.
\param[doctable] is the doctable as explained above.
\returns the \tt{doctable} parameter.
\throws[exceptions.SyntaxException] if parsing the comment failed. Note that in this case the \tt{doctable} may be
partially filled-in.
*/
function processComment(comment: string, doctable: table) {} // Dummy function which will be replaced after loading

/**
Takes a string containing Croc doc comment markup, and parses it into a paragraph list.

This doesn't parse the whole text of a doc comment; rather it just parses one or more paragraphs of text. Section
commands are not allowed to appear in the text. Span and text structure commands, however, are valid.

\param[comment] is the raw markup to be parsed.
\returns an array which is a paragraph list as defined in the doc comment spec.
\throws[exceptions.SyntaxException] if parsing failed.
*/
function parseCommentText(comment: string) {} // Dummy function which will be replaced after loading

/**
This class defines a default behavior for mapping documentation links (made with the \tt{\\link} command) to the things
they refer to. It uses a \link{LinkTranslator} which you define in order to turn the mapped links into outputtable link
text.

For URIs (such as with \tt{\\link{http://www.example.com}}), no attempt is made to ensure the correctness or well-
formedness of the link.

All other links are considered links to other documentable items. The way it does this is by taking a snapshot of the
global namespace and all currenly-loaded modules. This means that any modules imported after instantiating this class
are unknown to that instance, and links into them will not resolve. Most of the time this won't be a problem since
you'll likely have imported them beforehand so that you can output their docs!

Once a link has been processed, it is then passed to one of the methods that its \link{LinkTranslator} instance defines.
The results of those methods are returned from \link{resolveLink}.

This class is used automatically by the default doc outputters, but you are free to use it if you write one of your own.
*/
class LinkResolver
{
	// struct ItemDesc { string name, fqn; DocTable docTable; ItemDesc[string] children; }
	__modules // ItemDesc[string]
	__globals // ItemDesc[string]
	__curModule = null // ItemDesc
	__item = null // ItemDesc
	__trans

	/**
	Constructs a resolver with the given link translator.

	The constructor takes a snapshot of the global namespace and all loaded modules, so if there are any modules that
	you want links to resolve to, you must have imported them before instantiating this class.

	When you create a link resolver, any links will be evaluated within the global scope. You can change the scope in
	which links are resolved by using the \tt{enter/leaveItem/Module} methods.

	\param[trans] is the link translator object whose methods will be called by \link{resolveLink}.
	*/
	this(trans: LinkTranslator)
	{
		:__trans = trans

		// Setup modules
		:__modules = {}

		foreach(name, m; modules.loaded)
		{
			if(local dt = docsOf(m))
				:__modules[name] = :__makeMapRec(dt)
		}

		// Setup globals
		if(local dt = docsOf(_G))
			:__globals = :__makeMapRec(dt).children
		else
			:__globals = {}

		// Might be some globals added by user code that aren't in docsOf(_G).children
		foreach(name, val; _G)
		{
			if(name !is "_G" && name !in :__globals && name !in modules.loaded)
			{
				if(local dt = docsOf(val))
					:__globals[name] = :__makeMapRec(dt)
			}
		}
	}

	/**
	Returns a string saying what scope this resolver is currently operating in.

	\returns one of \tt{"global"} (the default), \tt{"module"} (when you have entered a module), or \tt{"item"} (when
	you have entered an item within a module).
	*/
	function currentScope()
	{
		if(:__item is null)
		{
			if(:__module is null)
				return "global"
			else
				return "module"
		}
		else
			return "item"
	}

	/**
	Switches from global scope to module scope, so that links will be resolved in the context of the given module.

	This method is called automatically by the various doc outputters which take link resolvers.

	\throws[exceptions.StateException] if the current scope is not global scope.
	\throws[exceptions.ValueException] if there is no module of the given name.
	*/
	function enterModule(name: string)
	{
		if(:__item !is null || :__curModule !is null)
			throw StateException("Attempting to enter a module from {} scope".format(:currentScope()))

		if(local m = :__modules[name])
			:__curModule = m
		else
			throw ValueException("No module named '{}' (did you import it after creating this resolver?)".format(name))
	}

	/**
	Switches from module scope back to global scope.

	This method is called automatically by the various doc outputters which take link resolvers.

	\throws[exceptions.StateException] if the current scope is not module scope.
	*/
	function leaveModule()
	{
		if(:__item !is null || :__curModule is null)
			throw StateException("Attempting to leave a module from {} scope".format(:currentScope()))

		:__curModule = null
	}

	/**
	Switches from module scope to item scope, so that links will be resolved in the context of the given item (class or
	namespace declaration).

	This method is called automatically by the various doc outputters which take link resolvers.

	\throws[exceptions.StateException] if the current scope is not module scope.
	\throws[exceptions.ValueException] if there is no item of the given name in the current module.
	*/
	function enterItem(name: string)
	{
		if(:__item !is null || :__curModule is null)
			throw StateException("Attempting to enter an item from {} scope".format(:currentScope()))

		if(local i = :__curModule.children[name])
			:__item = i
		else
			throw ValueException("No item named '{}' in {}".format(name, __curModule.name))
	}

	/**
	Switches from item scope back to module scope.

	This method is called automatically by the various doc outputters which take link resolvers.

	\throws[exceptions.StateException] if the current scope is not item scope.
	*/
	function leaveItem()
	{
		if(:__item is null || :__curModule is null)
			throw StateException("Attempting to leave an item from {} scope".format(:currentScope()))

		:__item = null
	}

	/**
	Given a raw, unprocessed link, turns it into a link string suitable for output.

	It does this by analyzing the link, determining whether it's a URI or a code link, ensuring it's a valid link if
	it's a code link, and then calling one of \link{LinkTranslator}'s methods as appropriate to turn the raw link into
	something suitable for output. It does not process the outputs of those methods; whatever they return is what this
	method returns.
	*/
	function resolveLink(link: string)
	{
		if("/" in link)
		{
			// URI; no further processing necessary. If someone writes something like "www.example.com" it's ambiguous
			// and it's their fault when it doesn't resolve :P
			return :__trans.translateURI(link)
		}
		else
		{
			// Okay, so: names aren't really all that specific. Name lookup works more or less like in Croc itself, with
			// one exception: names can refer to other members within classes and namespaces.
			// In any case, a dotted name can resolve to one of two locations (qualified name within current module, or
			// fully-qualified name), and a name without dots can resolve to one of FOUR locations (those two, plus
			// global, or another name within the current class/NS).
			// Also, names shadow one another. If you write a link to \tt{toString} within a class that defines it, the
			// link will resolve to this class's method, rather than the function declared at global scope.

			local isDotted = "." in link

			if(!isDotted && :__inItem(link)) // not dotted, could be item name
				return :__trans.translateLink(:__curModule.name, :__item.name ~ "." ~ link)
			else if(:__inCurModule(link)) // maybe it's something in the current module
				return :__trans.translateLink(:__curModule.name, link)
			else
			{
				// tryyyy all the modules!
				local isFQN, modName, itemName = :__inModules(link)

				if(isFQN)
					return :__trans.translateLink(modName, itemName)

				// um. um. global?!
				// it might be a member of a global class or something, or just a plain old global
				if(:__inGlobalItem(link) || :__inGlobals(link))
					return :__trans.translateLink("", link)
			}
		}

		// noooooo nothing matched :(
		return :__trans.invalidLink(link)
	}

	// =================================================================================================================
	// Private

	function __inGlobalItem(link: string)
	{
		local dot = link.find(".")

		if(dot is #link)
			return false

		local n = link[0 .. dot]
		local f = link[dot + 1 ..]
		local i = :__globals[n]

		return i !is null && i.children && f in i.children
	}

	function __inItem(link: string) =
		:__item !is null && link in :__item.children

	function __inCurModule(link: string) =
		:__curModule !is null && :__inModule(:__curModule, link)

	function __inGlobals(link: string) =
		link in :__globals

	function __inModules(link: string)
	{
		if(link in :__modules)
			return true, link, ""

		// What we're doing here is trying every possible prefix as a module name. So for the name "a.b.c.d" we try
		// "a.b.c", "a.b", and "a" as module names, and see if the rest of the string is an item inside it.
		local lastDot

		for(local dot = link.rfind("."); dot != #link; dot = link.rfind(".", lastDot - 1))
		{
			lastDot = dot
			local modName = link[0 .. dot]

			if(local m = :__modules[modName])
			{
				// There can only be ONE match to the module name. Once you find it, there can't be any other modules
				// with names that are a prefix, since that's enforced by the module system. So if the item doesn't
				// exist in this module, it doesn't exist at all

				local itemName = link[dot + 1 ..]

				if(:__inModule(m, itemName))
					return true, modName, itemName
				else
					return false
			}
		}

		return false
	}

	function __inModule(mod: table, item: string)
	{
		local t = mod

		foreach(piece; item.split("."))
		{
			if(t.children is null)
				return false

			t = t.children[piece]

			if(t is null)
				return false
		}

		return true
	}

	function __makeMapRec(dt: table)
	{
		local ret = { name = dt.name }

		if(dt.children)
		{
			ret.children = {}

			foreach(child; dt.children)
			{
				local c = :__makeMapRec(child)
				ret.children[child.name] = c

				if(local dit = child.dittos)
				{
					foreach(d; dit)
						ret.children[d.name] = c
				}
			}
		}

		return ret
	}
}

/**
A link resolver that does absolutely nothing and resolves all links to empty strings.

It never throws any errors or does anything, really. It's useful for when you don't want any link resolution behavior at
all.
*/
class NullLinkResolver : LinkResolver
{
	this() {}
	function enterModule(name: string) {}
	function leaveModule() {}
	function enterItem(name: string) {}
	function leaveItem() {}
	function resolveLink(link: string) = ""
}

/**
This class defines an interface for mapping links from their raw form to their outputtable form. Since the structure of
the output docs is unknown to the library, how this translation happens is left up to the user.

You create a subclass of this class, override the appropriate methods, and then pass an instance of it to the
constructor of a \link{LinkResolver} class.
*/
class LinkTranslator
{
	/**
	Given a module name and a sub-item name (which may or may not be dotted, since it might be something like a class
	field), translates them into a suitable link string.

	This, and \link{translateURI}, are the only methods you have to override in a subclass.

	\param[mod] is the name of the module that contains the linked item, or the empty string if the linked item is in
		the global namespace.
	\param[item] is the name of the item that is being linked, or the empty string if the link points at the given
		module itself.

	\returns the link translated into a form that makes sense to whatever output format you're using.
	*/
	function translateLink(mod: string, item: string)
		throw NotImplementedException()

	/**
	Given a URI, translates it into a suitable link string.

	This, and \link{translateLink}, are the only methods you have to override in a subclass.

	\param[uri] is the URI to translate.

	\returns the link translated into a form that makes sense to whatever output format you're using.
	*/
	function translateURI(uri: string)
		throw NotImplementedException()

	/**
	This method is called when the given link fails to resolve.

	\link{LinkResolver.resolveLink} will call this method if it fails to find a valid target for the given link. This
	method can return a string which will then be returned by \link{LinkResolver.resolveLink}. By default, this method
	throws a \link{exceptions.ValueException} saying which link failed, but you can override it so that it does
	something else (such as returning a dummy link and logging the error to stderr).

	\param[link] is the link that failed to resolve.

	\returns a replacement string, optionally.
	*/
	function invalidLink(link: string)
		throw ValueException("No target found for link '{}'".format(link))
}

local stdSections =
[
	"deprecated"

	"docs"
	"examples"
	"params"
	"returns"
	"throws"

	"bugs"
	"notes"
	"todo"
	"warnings"

	"see"

	"authors"
	"date"
	"history"
	"since"
	"version"

	"copyright"
	"license"
]

local stdSpans =
[
	"b"
	"em"
	"link"
	"sub"
	"sup"
	"tt"
	"u"
]

local stdStructures =
[
	"code"
	"verbatim"
	"blist"
	"nlist"
	"dlist"
	"table"
]

local function validSectionName(name: string) =
	!(#name == 0 || (#name == 1 && name[0] == '_') || (name[0] != '_' && name !in stdSections))

local function validSpanName(name: string) =
	!(#name == 0 || (#name == 1 && name[0] == '_') || (name[0] != '_' && name !in stdSpans))

class BaseDocOutput
{
	__sectionOrder = [stdSections[i] for i: 0 .. #stdSections] // can't use .dup or foreach here as the arraylib has not yet been loaded
	__sectionHandlers =
	{
    	docs = "handleSection_docs",
    	params = "handleSection_params",
    	throws = "handleSection_throws"
	}

	__spanHandlers =
	{
    	b = "handleSpan_b",
    	em = "handleSpan_em",
    	link = "handleSpan_link",
    	sub = "handleSpan_sub",
    	sup = "handleSpan_sup",
    	tt = "handleSpan_tt",
    	u = "handleSpan_u"
	}

	__linkResolver

	// =================================================================================================
	// Constructor

	this(lr: LinkResolver)
	{
		:__sectionOrder = :__sectionOrder.dup()
		:__sectionHandlers = hash.dup(:__sectionHandlers)
		:__spanHandlers = hash.dup(:__spanHandlers)
		:__linkResolver = lr
	}

	// =================================================================================================
	// Section ordering

	function insertSectionBefore(sec: string, before: string)
		:__insertSectionImpl(sec, before, false)

	function insertSectionAfter(sec: string, after: string)
		:__insertSectionImpl(sec, after, true)

	function __insertSectionImpl(sec: string, target: string, after: bool)
	{
		if(!validSectionName(sec))
			throw ValueException("Invalid section name '{}'".format(sec))
		else if(!validSectionName(target))
			throw ValueException("Invalid section name '{}'".format(target))
		else if(sec == target)
			throw ValueException("Section names must be different")

		local ord = :__sectionOrder

		// Check if this section is already in the order. It's possible for it not to be,
		// if it's a custom section.
		local idx = ord.find(sec)

		if(idx < #ord)
			ord.pop(idx)

		// Find where to insert and put it there.
		local targetIdx = ord.find(target)

		if(targetIdx == #ord)
			throw ValueException("Section '{}' does not exist in the section order".format(target))

		ord.insert(after ? targetIdx + 1 : targetIdx, sec)
	}

	function getSectionOrder() =
		:__sectionOrder.dup()

	function setSectionOrder(order: array)
	{
		// Make sure it's an array of valid section names
		foreach(name; order)
		{
			if(!isString(name))
				throw ValueException("Order must be an array of nothing but strings")
			else if(!validSectionName(name))
				throw ValueException("Invalid section name '{}' in given order".format(name))
		}

		// Make sure all standard sections are accounted for
		foreach(sec; stdSections)
			if(sec !in order)
				throw ValueException("Standard section '{}' does not exist in the given order".format(sec))

		:__sectionOrder = order.dup()
	}

	// =================================================================================================
	// Section handlers

	function getSectionHandler(name: string)
	{
		if(local handler = :__sectionHandlers[name])
			return handler
		else
			return "defaultSectionHandler"
	}

	function setSectionHandler(name: string, handlerName: string)
	{
		if(name !in :__sectionOrder)
			throw ValueException("Section '{}' does not appear in the section order".format(name))

		if(!hasMethod(this, handlerName))
			throw ValueException("No method named '{}' exists in this class".format(handlerName))

		:__sectionHandlers[name] = handlerName
	}

	function defaultSectionHandler(name: string, contents: array)
	{
		:beginParagraph()
		:beginBold()

		if(name.startsWith("_"))
			:outputText(ascii.toUpper(name[1]), name[2..], ": ")
		else
			:outputText(ascii.toUpper(name[0]), name[1..], ": ")
		:endBold()
		:outputParagraphContents(contents[0])
		:endParagraph()

		:outputParagraphs(contents[1 ..])
	}

	function handleSection_docs(name: string, contents: array)
	{
		if(#contents == 1 && #contents[0] == 1 && contents[0][0] is "")
			return

		:outputParagraphs(contents)
	}

	function handleSection_params(name: string, contents: array)
	{
		if(#contents == 0)
			return
		else if(!contents.any(\p -> #p.docs > 1 || #p.docs[0] > 1 || p.docs[0][0] != ""))
			return

		:beginParagraph()
		:beginBold()
		:outputText("Params:")
		:endBold()
		:endParagraph()

		:beginTable()

		foreach(param; contents)
		{
			:beginRow()
			:beginCell()
			:beginBold()
			:outputText(param.name)
			:endBold()
			:endCell()

			:beginCell()
			:outputParagraphs(param.docs)
			:endCell()

			:endRow()
		}

		:endTable()
	}

	function handleSection_throws(name: string, contents: array)
	{
		assert(#contents > 0)

		:beginParagraph()
		:beginBold()
		:outputText("Throws:")
		:endBold()
		:endParagraph()

		:beginDefList()

		foreach(ex; contents)
		{
			:beginDefTerm()
			:beginLink(:resolveLink(ex[0]))
			:outputText(ex[0])
			:endLink()
			:endDefTerm()

			:beginDefDef()
			:outputParagraphs(ex[1..])
			:endDefDef()
		}

		:endDefList()
	}

	function outputSection(name: string, doctable: table)
	{
		local contents = null

		if(name[0] == '_')
		{
			if(hasField(doctable, "custom"))
				contents = doctable.custom[name[1 ..]]
		}
		else
			contents = doctable[name]

		if(contents !is null)
			:(:getSectionHandler(name))(name, contents)
	}

	function outputDocSections(doctable: table)
	{
		foreach(section; :__sectionOrder)
			:outputSection(section, doctable)
	}

	// =================================================================================================
	// Span handlers

	function getSpanHandler(name: string)
	{
		if(local handler = :__spanHandlers[name])
			return handler
		else
			return "defaultSpanHandler"
	}

	function setSpanHandler(name: string, handlerName: string)
	{
		if(!validSpanName(name))
			throw ValueException("Invalid span name '{}'".format(name))

		if(!hasMethod(this, handlerName))
			throw ValueException("No method named '{}' exists in this class".format(handlerName))

		:__spanHandlers[name] = handlerName
	}

	function defaultSpanHandler(contents: array)
	{
		:outputParagraphContents(contents[1..])
	}

	function handleSpan_b(contents: array)
	{
		:beginBold()
		:outputParagraphContents(contents[1..])
		:endBold()
	}

	function handleSpan_em(contents: array)
	{
		:beginEmphasis()
		:outputParagraphContents(contents[1..])
		:endEmphasis()
	}

	function handleSpan_link(contents: array)
	{
		:beginLink(:resolveLink(contents[1]))
		:outputParagraphContents(contents[2..])
		:endLink()
	}

	function handleSpan_sub(contents: array)
	{
		:beginSubscript()
		:outputParagraphContents(contents[1..])
		:endSubscript()
	}

	function handleSpan_sup(contents: array)
	{
		:beginSuperscript()
		:outputParagraphContents(contents[1..])
		:endSuperscript()
	}

	function handleSpan_tt(contents: array)
	{
		:beginMonospace()
		:outputParagraphContents(contents[1..])
		:endMonospace()
	}

	function handleSpan_u(contents: array)
	{
		:beginUnderline()
		:outputParagraphContents(contents[1..])
		:endUnderline()
	}

	function outputSpan(contents: array)
		:(:getSpanHandler(contents[0]))(contents)

	// =================================================================================================
	// Text structure handlers

	function outputCode(contents: array)
	{
		:beginCode(contents[1])
		:outputText(contents[2])
		:endCode()
	}

	function outputVerbatim(contents: array)
	{
		:beginVerbatim()
		:outputText(contents[1])
		:endVerbatim()
	}

	function outputBlist(contents: array)
	{
		:beginBulletList()

		for(i: 1 .. #contents)
		{
			:beginListItem()
			:outputParagraphs(contents[i])
			:endListItem()
		}

		:endBulletList()
	}

	function outputNlist(contents: array)
	{
		:beginNumList(contents[1])

		for(i: 2 .. #contents)
		{
			:beginListItem()
			:outputParagraphs(contents[i])
			:endListItem()
		}

		:endNumList()
	}

	function outputDlist(contents: array)
	{
		:beginDefList()

		for(i: 1 .. #contents)
		{
			:beginDefTerm()
			:outputParagraphContents(contents[i][0])
			:endDefTerm()

			:beginDefDef()
			:outputParagraphs(contents[i][1..])
			:endDefDef()
		}

		:endDefList()
	}

	function outputTable(contents: array)
	{
		:beginTable()

		for(row: 1 .. #contents)
		{
			:beginRow()

			foreach(cell; contents[row])
			{
				:beginCell()
				:outputParagraphs(cell)
				:endCell()
			}

			:endRow()
		}

		:endTable()
	}

	// =================================================================================================
	// Link handling

	function resolveLink(link: string) =
		:__linkResolver.resolveLink(link)

	// =================================================================================================
	// Element-level output functions

	function beginBold() throw NotImplementedException()
	function endBold() throw NotImplementedException()
	function beginEmphasis() throw NotImplementedException()
	function endEmphasis() throw NotImplementedException()
	function beginLink(link: string) throw NotImplementedException()
	function endLink() throw NotImplementedException()
	function beginMonospace() throw NotImplementedException()
	function endMonospace() throw NotImplementedException()
	function beginSubscript() throw NotImplementedException()
	function endSubscript() throw NotImplementedException()
	function beginSuperscript() throw NotImplementedException()
	function endSuperscript() throw NotImplementedException()
	function beginUnderline() throw NotImplementedException()
	function endUnderline() throw NotImplementedException()

	function beginCode(language: string) throw NotImplementedException()
	function endCode() throw NotImplementedException()
	function beginVerbatim() throw NotImplementedException()
	function endVerbatim() throw NotImplementedException()
	function beginBulletList() throw NotImplementedException()
	function endBulletList() throw NotImplementedException()
	function beginNumList(type: string) throw NotImplementedException()
	function endNumList() throw NotImplementedException()
	function beginListItem() throw NotImplementedException()
	function endListItem() throw NotImplementedException()
	function beginDefList() throw NotImplementedException()
	function endDefList() throw NotImplementedException()
	function beginDefTerm() throw NotImplementedException()
	function endDefTerm() throw NotImplementedException()
	function beginDefDef() throw NotImplementedException()
	function endDefDef() throw NotImplementedException()
	function beginTable() throw NotImplementedException()
	function endTable() throw NotImplementedException()
	function beginRow() throw NotImplementedException()
	function endRow() throw NotImplementedException()
	function beginCell() throw NotImplementedException()
	function endCell() throw NotImplementedException()

	function beginParagraph() throw NotImplementedException()
	function endParagraph() throw NotImplementedException()

	function outputText(vararg) throw NotImplementedException()

	function outputParagraphContents(par: array)
	{
		foreach(elem; par)
		{
			if(isString(elem))
				:outputText(elem)
			else if(isArray(elem))
			{
				local tag = elem[0]

				if(tag in stdStructures)
				{
					switch(tag)
					{
						case "code":     :outputCode(elem);     break
						case "verbatim": :outputVerbatim(elem); break
						case "blist":    :outputBlist(elem);    break
						case "nlist":    :outputNlist(elem);    break
						case "dlist":    :outputDlist(elem);    break
						case "table":    :outputTable(elem);    break
						default: assert(false)
					}
				}
				else
					:outputSpan(elem)
			}
			else
				throw ValueException("Malformed documentation")
		}
	}

	function outputParagraph(par: array)
	{
		:beginParagraph()
		:outputParagraphContents(par)
		:endParagraph()
	}

	function outputParagraphs(plist: array)
	{
		foreach(par; plist)
			:outputParagraph(par)
	}

	// =================================================================================================
	// Item-level output functions

	function beginItem(doctable: table, parentFQN: string) throw NotImplementedException()
	function endItem() throw NotImplementedException()

	function outputHeader(doctable: table, parentFQN: string, full: bool = true)
	{
		switch(doctable.kind)
		{
			case "module":
				if(full)
					:outputText("module ")

				:outputText(doctable.name)
				return

			case "function":
				if(parentFQN !is "")
					:outputText(parentFQN, ".")

				:outputText(doctable.name == "constructor" ? "this" : doctable.name)

				if(!full)
					return

				:outputText("(")

				foreach(i, p; doctable.params)
				{
					if(i > 0)
						:outputText(", ")

					:outputText(p.name)

					if(p.type != "any" && p.type != "vararg")
						:outputText(": ", p.type)

					if(p.value)
						:outputText(" = ", p.value)
				}

				:outputText(")")
				break

			case "class", "namespace":
				if(full)
					:outputText(doctable.kind, " ")

				if(parentFQN !is "")
					:outputText(parentFQN, ".")

				:outputText(doctable.name)

				if(!full)
					return

				if(doctable.base)
					write(" : ", doctable.base)
				break

			case "field":
				if(parentFQN !is "")
					:outputText(parentFQN, ".")

				write(doctable.name)

				if(!full)
					return

				if(doctable.value)
					write(" = ", doctable.value)
				break

			case "variable":
				if(full)
					write(doctable.protection, " ")

				if(parentFQN !is "")
					:outputText(parentFQN, ".")

				:outputText(doctable.name)

				if(!full)
					return

				if(doctable.value)
					write(" = ", d.value)
				break

			case "parameter":
				throw ValueException("Cannot call outputHeader on a parameter doctable")

			default:
				throw ValueException("Malformed documentation for {}".format(doctable.name))
		}
	}

	function outputChildren(doctable: table, parentFQN: string)
	{
		foreach(child; doctable.children)
			:outputItem(child, parentFQN)
	}

	function outputModule(doctable: table, parentFQN: string)
	{
		assert(doctable.kind is "module")
		:outputChildren(doctable, "")
	}

	function outputFunction(doctable: table, parentFQN: string)
	{
		assert(doctable.kind is "function")
		// nothing different, all the func-specific sections are already handled
	}

	function outputClass(doctable: table, parentFQN: string)
	{
		assert(doctable.kind is "class")
		:outputChildren(doctable, doctable.name)
	}

	function outputNamespace(doctable: table, parentFQN: string)
	{
		assert(doctable.kind is "namespace")
		:outputChildren(doctable, doctable.name)
	}

	function outputField(doctable: table, parentFQN: string)
	{
		assert(doctable.kind is "field")
		// nothing different
	}

	function outputVariable(doctable: table, parentFQN: string)
	{
		assert(doctable.kind is "variable")
		// nothing different
	}

	function outputItem(doctable: table, parentFQN: string)
	{
		:beginItem(doctable, parentFQN)

		if(doctable.kind is "module")
			:__linkResolver.enterModule(doctable.name)
		else if(doctable.kind is "class" || doctable.kind is "namespace")
			:__linkResolver.enterItem(doctable.name)

		if(doctable.dittos)
		{
			foreach(d; doctable.dittos)
			{
				:endItem()
				:beginItem(d, parentFQN)
			}
		}

		:outputDocSections(doctable)

		switch(doctable.kind)
		{
			case "module":    :outputModule(doctable, parentFQN);    break
			case "function":  :outputFunction(doctable, parentFQN);  break
			case "class":     :outputClass(doctable, parentFQN);     break
			case "namespace": :outputNamespace(doctable, parentFQN); break
			case "field":     :outputField(doctable, parentFQN);     break
			case "variable":  :outputVariable(doctable, parentFQN);  break

			case "parameter":
				throw ValueException("Can't call outputItem on a parameter doctable")

			default:
				throw ValueException("Malformed documentation")
		}

		if(doctable.kind is "module")
			:__linkResolver.leaveModule()
		else if(doctable.kind is "class" || doctable.kind is "namespace")
			:__linkResolver.leaveItem()

		:endItem()
	}

	// =================================================================================================
	// Top-level output functions
}

class TracWikiDocOutput : BaseDocOutput
{
	__listType = []
	__inTable = false
	__itemDepth = 0

	function beginBold() :outputText("'''")
	function endBold()  :outputText("'''")
	function beginEmphasis() :outputText("''")
	function endEmphasis() :outputText("''")

	function beginLink(link: string) :outputText("[",  link, " ")
	function endLink() :outputText("]")
	function beginMonospace() :outputText("` "`" `")
	function endMonospace() :outputText("` "`" `")
	function beginSubscript() :outputText(",,")
	function endSubscript() :outputText(",,")
	function beginSuperscript() :outputText("^")
	function endSuperscript() :outputText("^")
	function beginUnderline() :outputText("__")
	function endUnderline() :outputText("__")

	function beginCode(language: string)
	{
		:checkNotInTable()
		:outputText("\n{{{\n#!", language, "\n")
	}

	function endCode()
		:outputText("\n}}}\n")

	function beginVerbatim()
	{
		:checkNotInTable()
		:outputText("\n{{{\n")
	}

	function endVerbatim()
		:outputText("\n}}}\n")

	function beginBulletList()
	{
		:checkNotInTable()
		:__listType.append("*")
		:outputText("\n")
	}

	function endBulletList()
	{
		:__listType.pop()
		:outputText("\n")
	}

	function beginNumList(type: string)
	{
		:checkNotInTable()
		:__listType.append(type ~ ".")
		:outputText("\n")
	}

	function endNumList()
	{
		:__listType.pop()
		:outputText("\n")
	}

	function beginListItem()
	{
		assert(#:__listType > 0)
		:outputIndent()
		:outputText(:__listType[-1], " ")
	}

	function endListItem()
		:outputText("\n")

	function beginDefList()
	{
		:checkNotInTable()
		:__listType.append(null)
		:outputText("\n")
	}

	function endDefList()
	{
		:__listType.pop()
		:outputText("\n")
	}

	function beginDefTerm()
	{
		assert(#:__listType > 0)
		:outputIndent()
	}

	function endDefTerm()
		:outputText("::\n")

	function beginDefDef()
		:outputIndent()

	function endDefDef()
		:outputText("\n")

	function beginTable()
	{
		if(#:__listType > 0)
			throw ValueException("Sorry, tables inside lists are unsupported in Trac wiki markup")

		:__inTable = true
		:outputText("\n")
	}

	function endTable()
	{
		:__inTable = false
		:outputText("\n")
	}

	function beginRow()
		:outputText("||")

	function endRow()
		:outputText("\n")

	function beginCell() {}

	function endCell()
		:outputText("||")

	function beginParagraph()
	{
		if(!:__inTable)
		{
			:outputText("\n")
			:outputIndent()
		}
	}

	function endParagraph()
	{
		if(:__inTable)
			:outputText(" ")
		else
			:outputText("\n")
	}

	function outputText(vararg)
	{
		for(i: 0 .. #vararg)
			write(vararg[i])
	}

	function beginItem(doctable: table, parentFQN: string)
	{
		if(doctable.kind is "module")
		{
			:outputText("[[PageOutline]]\n")
			:outputWikiHeader(doctable, parentFQN)
		}
		else
			:outputWikiHeader(doctable, parentFQN)

		:__itemDepth++
	}

	function endItem()
	{
		:outputText("\n")
		:__itemDepth--
	}

	function outputWikiHeader(doctable: table, parentFQN: string)
	{
		local h = "=".repeat(:__itemDepth + 1)

		:outputText(h, " ")
		:beginMonospace()
		:outputHeader(doctable, parentFQN, false)
		:endMonospace()
		:outputText(" ", h, "\n")

		if(doctable.kind is "module")
			return

		if((doctable.kind is "variable" || doctable.kind is "field") && doctable.value is null)
			return

		:beginParagraph()
		:beginBold()
		:beginMonospace()
		:outputHeader(doctable, parentFQN, true)
		:endMonospace()
		:endBold()
		:endParagraph()
	}

	function checkNotInTable()
	{
		if(:__inTable)
			throw ValueException("Sorry, text structures inside tables are unsupported in Trac wiki markup")
	}

	function outputIndent()
	{
		if(#:__listType > 0)
			:outputText(" ".repeat(#:__listType * 2 - 1))
	}
}

/*
function help(x, child: string = null)
{
	local d

	if(isString(x))
	{
		local mt

		try
			mt = debug.getMetatable(x)
		catch(e: Exception)
			throw TypeException("Invalid type '{}'".format(x))

		if(child in mt)
			d = docsOf(mt.(child))
	}
	else
	{
		d = docsOf(x)

		if(#d && child !is null)
		{
			if(d.children is null)
				throw ValueException("No children")

			local found = false

			foreach outerLoop(c; d.children)
			{
				if(c.name == child)
				{
					found = true
					d = c
					break
				}

				if(c.dittos)
				{
					foreach(dit; c.dittos)
					{
						if(dit.name == child)
						{
							found = true
							d = c
							break outerLoop
						}
					}
				}
			}

			if(!found)
				throw ValueException("Not found")
		}
	}

	if(#d == 0)
	{
		writeln("<no help available>")
		return
	}

	function writeHeader(d)
	{
		if(d.protection)
			write(d.protection, " ")

		write(d.kind, " ", d.name)

		if(d.params)
		{
			write("(")

			foreach(i, p; d.params)
			{
				if(i > 0)
					write(", ")

				write(p.name)

				if(p.type != "any" && p.type != "vararg")
					write(": ", p.type)

				if(p.value)
					write(" = ", p.value)
			}

			write(")")
		}

		if(d.base)
			write(" : ", d.base)

		if(d.value)
			write(" = ", d.value)

		write(" (", d.file)
		if(d.line != 0)
			write(":  ", d.line)
		writeln(")")
	}

	writeHeader(d)

	if(d.dittos)
		foreach(dit; d.dittos)
			writeHeader(dit)

	foreach(line; d.docs.splitLines())
		writeln("  ", line.strip())

	if(d.children && #d.children)
	{
		writeln()
		writeln("Members:")

		foreach(c; d.children)
			writeln("   ", c.name)
	}

	writeln()
} */`;