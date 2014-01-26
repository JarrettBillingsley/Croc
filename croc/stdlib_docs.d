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
	newTable(t);
		registerFields(t, _funcs);
	newGlobal(t, "_docstmp");

	importModuleFromStringNoNS(t, "docs", docsSource, "docs.croc");

	pushGlobal(t, "_G");
	pushString(t, "_docstmp");
	removeKey(t, -2);
	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

const RegisterFunc[] _funcs =
[
	{"processComment",   &_processComment,   maxParams: 2},
	{"parseCommentText", &_parseCommentText, maxParams: 2},
	{"getMetatable",     &_getMetatable,     maxParams: 1}
];

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

uword _getMetatable(CrocThread* t)
{
	CrocValue.Type type;

	switch(checkStringParam(t, 1))
	{
		case "null":      type = CrocValue.Type.Null;      break;
		case "bool":      type = CrocValue.Type.Bool;      break;
		case "int":       type = CrocValue.Type.Int;       break;
		case "float":     type = CrocValue.Type.Float;     break;
		case "nativeobj": type = CrocValue.Type.NativeObj; break;
		case "string":    type = CrocValue.Type.String;    break;
		case "weakref":   type = CrocValue.Type.WeakRef;   break;
		case "table":     type = CrocValue.Type.Table;     break;
		case "namespace": type = CrocValue.Type.Namespace; break;
		case "array":     type = CrocValue.Type.Array;     break;
		case "memblock":  type = CrocValue.Type.Memblock;  break;
		case "function":  type = CrocValue.Type.Function;  break;
		case "funcdef":   type = CrocValue.Type.FuncDef;   break;
		case "class":     type = CrocValue.Type.Class;     break;
		case "instance":  type = CrocValue.Type.Instance;  break;
		case "thread":    type = CrocValue.Type.Thread;    break;

		default:
			pushBool(t, false);
			return 1;
	}

	pushBool(t, true);
	getTypeMT(t, type);
	return 2;
}

const char[] docsSource =
`/**
This module contains the runtime interface to Croc's built-in documentation system. It defines the decorator function
which the compiler can translate doc comments into, as well as the actual documentation processing functions. It also
contains a basic doc outputting scaffold, so that you can output documentation in a human-readable format without much
extra work.
*/
module docs

local docTables = {}
local _processComment, _parseCommentText, _getMetatable = _docstmp.processComment, _docstmp.parseCommentText, _docstmp.getMetatable

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

\throws[exceptions.TypeError] if any of the \tt{varargs} are not ints, or if the value that will be set as the
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
			throw TypeError("_doc_ - Parameter {} expected to be 'int', not '{}'".format(i + 2, typeof(idx)))

		d = d.children[idx]
	}

	if(!isTable(d))
		throw TypeError("_doc_ - Doc table is not a table, it is of type '{}'", typeof(d))

	docTables[val] = d
	return val
}

// Export globally
_G._doc_ = _doc_

/**
This retrieves the documentation table, if any, associated with an object.

\param[val] is the object whose docs are to be retrieved. Any type is allowed, but only reference types can have
documentation tables associated with them.

Some program elements can't have their docs directly retrieved with this function. See also \link{metamethodDocs} and
\link{childDocs}.

\returns the doc table for \tt{val} if one has been set, or \tt{null} if none has been set (or if \tt{val} is
a value type).
*/
function docsOf(val) =
	docTables[val]

/**
This retrieves the documentation table, if any, associated with a metamethod in a global type metatable.

Normally, without access to the debug lib, Croc code can't actually get a direct reference to these methods (such as
the \tt{format} method of strings). This function lets you get docs for those methods without the debug lib.

\param[type] is the name of the built-in type you want to get the method's docs from.
\param[method] is the name of the method to get the docs of.

\returns the doc table for the given method if one has been set, or \tt{null} if not.

\throws[exceptions.ValueError] if \tt{type} does not name a valid built-in type, or if \tt{type} has no metatable
set for it.
\throws[exceptions.FieldError] if there is no method named \tt{method} in \tt{type}'s metatable.
*/
function metamethodDocs(type: string, method: string)
{
	local ok, mt = _getMetatable(type)

	if(!ok)
		throw ValueError("Invalid type")

	if(mt is null)
		throw ValueError("Type has no metatable")

	local func = mt[method]

	if(func is null)
		throw FieldError("No method '{}' in given type's metatable".format(method))

	return docsOf(func)
}

/**
This retrieves the documentation table, if any, associated with a child element of a class or namespace.

Functions defined in classes and namespaces can have their docs accessed directly, but for other fields, you have to
access their doc tables through their parents' \tt{children} doctable member. This function automates that for you.

\param[obj] is the class or namespace in which the field is defined.
\param[child] is the name of the field whose docs you want to retrieve. Any field name is valid, not just non-functions.

\returns the doc table for the given field if one has been set, or \tt{null} if not.

\throws[exceptions.ValueError] if \tt{obj} has no child named \tt{child}, or if \tt{obj} has no doctable.
*/
function childDocs(obj: class|namespace, child: string)
{
	if(child !in obj)
		throw ValueError("Object has no child named '{}'".format(child))

	local docs = docsOf(obj)

	if(docs is null)
		throw ValueError("Object has no doc table")

	foreach outerLoop(c; docs.children)
	{
		if(c.name == child)
			return c

		if(c.dittos)
		{
			foreach(dit; c.dittos)
			{
				if(dit.name == child)
					return c
			}
		}
	}

	return null
}

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
function processComment(comment: string, doctable: table) =
	_processComment(comment, doctable)

/**
Takes a string containing Croc doc comment markup, and parses it into a paragraph list.

This doesn't parse the whole text of a doc comment; rather it just parses one or more paragraphs of text. Section
commands are not allowed to appear in the text. Span and text structure commands, however, are valid.

\param[comment] is the raw markup to be parsed.
\returns an array which is a paragraph list as defined in the doc comment spec.
\throws[exceptions.SyntaxException] if parsing failed.
*/
function parseCommentText(comment: string) =
	_parseCommentText(comment)

/**
A class which defines a simple interface for visiting all the elements in a doctable. You can use this as a base class
for your own visitors to do things like output docs in various formats.

By default this class doesn't do much, but it does remove some of the boilerplate involved in dispatching to the various
methods. Some methods are unimplemented and must be defined in a derived class in order to work.

Note that there is another class, \link{doctools.output.OutputDocVisitor}, which implements this class's interface in a
way that makes making document outputters easier.
*/
class DocVisitor
{
	/**
	Visits one program item's doctable. This dispatches based on \tt{item.kind} to one of the six methods after this
	one.

	\throws[exceptions.ValueError] if the given doctable has an invalid \tt{kind} field.
	*/
	function visitItem(item: table)
	{
		switch(item.kind)
		{
			case "module":    :visitModule(item);    break
			case "function":  :visitFunction(item);  break
			case "class":     :visitClass(item);     break
			case "namespace": :visitNamespace(item); break
			case "field":     :visitField(item);     break
			case "variable":  :visitVariable(item);  break
			default: throw ValueError("Malformed documentation (invalid doctable kind '{}')".format(item.kind))
		}
	}

	/**
	These methods are called by \link{visitItem}. You must implement these methods yourself.
	*/
	function visitModule(item: table) throw NotImplementedError()
	function visitClass(item: table) throw NotImplementedError()
	function visitNamespace(item: table) throw NotImplementedError()
	function visitFunction(item: table) throw NotImplementedError()
	function visitField(item: table) throw NotImplementedError()
	function visitVariable(item: table) throw NotImplementedError()

	/**
	A convenience method for doctables which have children (such as modules, classes, and namespaces). This just loops
	over the doctable's \tt{children} field and calls \link{visitItem} on each one.
	*/
	function visitChildren(item: table)
	{
		foreach(child; item.children)
			:visitItem(child)
	}

	/**
	A convenience method for visiting a list of paragraphs (plist). This just loops over the plist and calls
	\link{visitParagraph} on each one.
	*/
	function visitPlist(plist: array)
	{
		foreach(par; plist)
			:visitParagraph(par)
	}

	/**
	Visits one paragraph of documentation. By default, just calls \link{visitParagraphElements} with \tt{par} as the
	argument, but often you will want to do something at the beginning/end of a paragraph (such as insert indentation
	or newlines), so you can override this method to do so.
	*/
	function visitParagraph(par: array)
		:visitParagraphElements(par)

	/**
	Visits an array of paragraph elements. You can use this method to implement the text visitor methods which follow,
	and this method will dispatch to those visitor methods.
	*/
	function visitParagraphElements(elems: array)
	{
		foreach(elem; elems)
		{
			if(isString(elem))
				:visitText(elem)
			else if(isArray(elem))
			{
				if(#elem == 0)
					throw ValueError("Malformed documentation (invalid paragraph element)")

				local type = elem[0]

				switch(type)
				{
					case "code":     :visitCode(elem[1], elem[2]);     break
					case "verbatim": :visitVerbatim(elem[1], elem[2]); break
					case "blist":    :visitBlist(elem[1..]);           break
					case "nlist":    :visitNlist(elem[1], elem[2..]);  break
					case "dlist":    :visitDlist(elem[1..]);           break
					case "table":    :visitTable(elem[1..]);           break
					case "em":       :visitEmphasis(elem[1..]);        break
					case "link":     :visitLink(elem[1], elem[2..]);   break
					case "sub":      :visitSubscript(elem[1..]);       break
					case "sup":      :visitSuperscript(elem[1..]);     break
					case "tt":       :visitMonospace(elem[1..]);       break
					case "u":        :visitUnderline(elem[1..]);       break

					default:
						if(isString(type) && type.startsWith("_"))
							:visitCustomSpan(type, elem[1..])
						else
							throw ValueError("Malformed documentation (invalid paragraph element type)")
				}
			}
			else
				throw ValueError("Malformed documentation (invalid paragraph element)")
		}
	}

	/// Visits a segment of plain text that appears in a paragraph. Must be overridden.
	function visitText(elem: string) throw NotImplementedError()

	/// Visits a code snippet. Must be overridden.
	function visitCode(language: string, contents: string) throw NotImplementedError()

	/// Visits a verbatim block. Must be overridden.
	function visitVerbatim(type: string, contents: string) throw NotImplementedError()

	/// Visits a bulleted list. Must be overridden.
	function visitBlist(items: array) throw NotImplementedError()

	/// Visits a numbered list. Must be overridden.
	function visitNlist(type: string, items: array) throw NotImplementedError()

	/// Visits a definition list. Must be overridden.
	function visitDlist(items: array) throw NotImplementedError()

	/// Visits a table. Must be overridden.
	function visitTable(rows: array) throw NotImplementedError()

	/// Visits an emphasis text span. Must be overridden.
	function visitEmphasis(contents: array) throw NotImplementedError()

	/// Visits a link text span. Must be overridden.
	function visitLink(link: string, contents: array) throw NotImplementedError()

	/// Visits a subscript text span. Must be overridden.
	function visitSubscript(contents: array) throw NotImplementedError()

	/// Visits a superscript text span. Must be overridden.
	function visitSuperscript(contents: array) throw NotImplementedError()

	/// Visits a monospace text span. Must be overridden.
	function visitMonospace(contents: array) throw NotImplementedError()

	/// Visits an underline text span. Must be overridden.
	function visitUnderline(contents: array) throw NotImplementedError()

	/// Visits a custom text span. Must be overridden.
	function visitCustomSpan(type: string, contents: array) throw NotImplementedError()
}`;