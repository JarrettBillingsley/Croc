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
import croc.types;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

struct DocsLib
{
static:
	void init(CrocThread* t)
	{
			newTable(t);
			dup(t);
			dup(t);
		newFunction(t, &_doc_, "_doc_", 1);   newGlobal(t, "_doc_");
		newFunction(t, &docsOf, "docsOf", 1); newGlobal(t, "docsOf");
		newFunction(t, &finishLoadingDocs, "finishLoadingDocs", 1); newGlobal(t, "finishLoadingDocs");

		version(CrocBuiltinDocs)
		{
			scope doc = new CrocDoc(t, __FILE__);

			static const Docs Object_docs = {kind: "class", name: "Object", docs:
			"The root of the class hierarchy, `Object`, is declared at global scope. It has no methods defined right
			now. It is the only class in Croc which has no base class (that is, \"`Object.super`\" returns `null`).",
			extra: [Extra("section", "Classes"), Extra("protection", "global")]};

			pushGlobal(t, "Object"); doc(-1, Object_docs); pop(t);

			// Have to do these after the fact because _doc_ is called by the doc system!
			pushGlobal(t, "_doc_");  doc(-1, _doc__docs); pop(t);
			pushGlobal(t, "docsOf"); doc(-1, docsOf_docs); pop(t);
		}
	}

	uword finishLoadingDocs(CrocThread* t)
	{
		auto oldTab = getUpval(t, 0);
		assert(isTable(t, oldTab));

		auto newTab = lookup(t, "hash.WeakKeyTable");
		pushNull(t);
		rawCall(t, -2, 1);

		dup(t, oldTab);

		foreach(word k, word v; foreachLoop(t, 1))
		{
			dup(t, k);
			dup(t, v);
			idxa(t, newTab);
		}

		dup(t, newTab);
		setUpval(t, 0);

		lookup(t, "hash.remove");
		pushNull(t);
		pushGlobal(t, "_G");
		pushString(t, "finishLoadingDocs");
		rawCall(t, -4, 0);
		return 0;
	}

	version(CrocBuiltinDocs) Docs _doc__docs = {kind: "function", name: "_doc_", docs:
	"This is a decorator function used to attach documentation tables to objects. The compiler can attach
	calls to this decorator to declarations in your code automatically by extracting documentation comments
	and information about the declarations from the code.

	The `obj` param can be any non-string reference type. The docTable param must be a table, preferably one
	which matches the specifications for doc tables. The variadic arguments should all be integers and are
	used to extract the correct sub-table from the root documentation table. So, for instance, using
	\"`@_doc_(someTable, 0, 2)`\" on a declaration would mean that the table `someTable.children[0].children[2]`
	would be used as the documentation for the decorated declaration. If no variadic arguments are given,
	the table itself is set as the documentation table of the object.

	Once the documentation table has been set for an object, you can retrieve it with docsOf, which can then
	be further processed and output in a human-readable form.",
	params: [Param("obj", "..."), Param("docTable", "table"), Param("vararg", "vararg")],
	extra: [Extra("section", "Documentation"), Extra("protection", "global")]};

	uword _doc_(CrocThread* t)
	{
		checkAnyParam(t, 1);

		// ORDER CROCVALUE TYPE
		if(type(t, 1) <= CrocValue.Type.String)
			paramTypeError(t, 1, "non-string object type");

		checkParam(t, 2, CrocValue.Type.Table);

		auto size = stackSize(t);

		auto docTable = dup(t, 2);

		for(word i = 3; i < size; i++)
		{
			checkIntParam(t, i);
			field(t, docTable, "children");
			idxi(t, -1, getInt(t, i));
			insertAndPop(t, -3);
		}

		getUpval(t, 0);
		dup(t, 1);
		dup(t, docTable);
		idxa(t, -3);

		dup(t, 1);
		return 1;
	}

	version(CrocBuiltinDocs) Docs docsOf_docs = {kind: "function", name: "docsOf", docs:
	"This retrieves the documentation table, if any, associated with an object. Any type is allowed, but only
	non-string object types can have documentation tables associated with them. Strings, value types, and objects
	for which no documentation table has been defined will return the default value: an empty table.",
	params: [Param("obj")],
	extra: [Extra("section", "Documentation"), Extra("protection", "global")]};

	uword docsOf(CrocThread* t)
	{
		checkAnyParam(t, 1);

		getUpval(t, 0);
		dup(t, 1);
		idx(t, -2);

		if(isNull(t, -1))
			newTable(t);

		return 1;
	}
}