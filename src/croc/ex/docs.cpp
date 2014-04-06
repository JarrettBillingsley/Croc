
#include <ctype.h>

#include "croc/api.h"
#include "croc/compiler/docparser.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"
#include "croc/util/array.hpp"
#include "croc/util/str.hpp"

using namespace croc;

namespace
{
	const char* DocTables = "ex.CrocDoc.docTables";

	word getDocTables(CrocDoc* d)
	{
		auto reg = croc_vm_pushRegistry(d->t);
		croc_pushString(d->t, DocTables);

		if(!croc_in(d->t, -1, reg))
		{
			croc_array_new(d->t, 0);
			croc_fielda(d->t, reg, DocTables);
		}

		croc_fieldStk(d->t, reg);
		croc_insertAndPop(d->t, reg);
		return croc_absIndex(d->t, -1);
	}

	/*
	First line is the header.
	!<line> <type> <name><etc>\n
	!(\d+) (\w+) (\w+)<etc>\n

	If type is "global" or "field":
		<etc> is an optional "=<val>" (=(.*))?$
	Otherwise:
		<etc> is ""

	After the first line
		If type is "function", there are 0 or more lines of the form "!param <name>:<type>(=<val>)?\n"
		If type is "class", there are 0 or more lines of the form "!base <base>\n"
		If type is "namespace", there is an optional line of the form "!base <base>\n"

	After that comes the docs.
	*/

	enum class Kind
	{
		Module,
		Function,
		Class,
		Namespace,
		Global,
		Field,
	};

	Kind strToKind(CrocThread* t, crocstr s)
	{
		if(s == ATODA("module"))    return Kind::Module;  else
		if(s == ATODA("function"))  return Kind::Function;  else
		if(s == ATODA("class"))     return Kind::Class;     else
		if(s == ATODA("namespace")) return Kind::Namespace; else
		if(s == ATODA("global"))    return Kind::Global;    else
		if(s == ATODA("field"))     return Kind::Field;     else
		croc_eh_throwStd(t, "ApiError", "Invalid kind '%.*s' in docstring", cast(int)s.length, s.ptr);
		return Kind::Function; // dummy
	}

	void doDitto(CrocDoc* d, word dt)
	{
		auto t = d->t;

		auto thisTab = croc_getStackSize(t) - 1;

		// At top level?
		if(croc_len(t, dt) <= 1)
			croc_eh_throwStd(t, "ApiError", "Cannot use ditto on the top-level declaration");

		// Get the parent and try to get the last declaration before this one
		auto prevTab = croc_idxi(t, dt, -2);

		if(croc_hasField(t, -1, "children"))
		{
			croc_field(t, -1, "children");

			if(croc_len(t, -1) > 0)
			{
				croc_idxi(t, -1, -1);
				croc_insertAndPop(t, prevTab);
				goto _okay;
			}
		}

		croc_eh_throwStd(t, "ApiError", "No previous declaration to ditto from");
	_okay:
		// See if the previous decl's kind is the same
		auto thisKind = croc_field(t, thisTab, "kind");
		auto prevKind = croc_field(t, prevTab, "kind");

		if(!croc_equals(t, thisKind, prevKind))
		{
			croc_field(t, thisTab, "name");
			croc_field(t, prevTab, "name");
			croc_eh_throwStd(t, "ApiError", "Can't ditto documentation for '%s': it's a %s, but '%s' was a %s",
				croc_getString(t, -2), croc_getString(t, thisKind), croc_getString(t, -1), croc_getString(t, prevKind));
		}

		croc_pop(t, 2);

		// Okay, we can ditto.
		d->dittoDepth++;

		if(!croc_hasField(t, prevTab, "dittos"))
		{
			croc_array_new(t, 0);
			croc_fielda(t, prevTab, "dittos");
		}

		// Append this doctable to the dittos of the previous decl.
		croc_field(t, prevTab, "dittos");
		croc_dup(t, thisTab);
		croc_cateq(t, -2, 1);
		croc_pop(t, 2);
	}

	void parseDocString(CrocDoc* d, word dt, crocstr docString)
	{
		auto t = d->t;

		if(!arrStartsWith(docString, ATODA("!")))
			croc_eh_throwStd(t, "ApiError", "Docstring must start with '!'");

		bool first = true;
		crocstr firstDocLine = docString;
		auto kind = Kind::Function;

		linesBreak(docString, [&](crocstr line)
		{
			if(first)
			{
				first = false;
				line = line.sliceToEnd(1); // slice off '!'

				// Parse line number
				if(line.length == 0 || !isdigit(line[0]))
					croc_eh_throwStd(t, "ApiError", "Line number must follow '!' in docstring");

				auto p = line.ptr;
				auto e = p + line.length;

				crocint lineNum = 0;

				while(p < e && isdigit(*p))
				{
					lineNum = (lineNum * 10) + (*(p++) - '0');

					if(lineNum < 0)
						croc_eh_throwStd(t, "ApiError", "Line number too big in docstring");
				}

				if(p == e || *p != ' ')
					croc_eh_throwStd(t, "ApiError", "Expected space after line number in docstring");

				// Parse kind
				line = crocstr::n(p + 1, e - p - 1);

				if(line.length == 0)
					croc_eh_throwStd(t, "ApiError", "Expected kind after line number in docstring");

				auto spacePos = findCharFast(line, ' ');

				if(spacePos == 0)
					croc_eh_throwStd(t, "ApiError", "Expected kind after line number in docstring");
				else if(spacePos == line.length || spacePos == line.length - 1)
					croc_eh_throwStd(t, "ApiError", "Expected name after kind in docstring");

				auto kindStr = line.slice(0, spacePos);
				kind = strToKind(t, kindStr);
				line = line.sliceToEnd(spacePos + 1);

				// Parse name (and optional value)
				crocstr name;

				if(kind == Kind::Field || kind == Kind::Global)
				{
					auto eqPos = findCharFast(line, '=');

					if(eqPos == 0)
						croc_eh_throwStd(t, "ApiError", "Expected name after kind in docstring");
					else if(eqPos == line.length - 1)
						croc_eh_throwStd(t, "ApiError", "Expected value after '=' in docstring");

					name = line.slice(0, eqPos);

					if(eqPos == line.length)
						line = crocstr();
					else
						line = line.sliceToEnd(eqPos + 1);
				}
				else
				{
					name = line;
					line = crocstr();
				}

				// Fill in required fields and some type-specific fields
				croc_pushString(t, d->file); croc_fielda(t, -2, "file");
				croc_pushInt(t, lineNum);    croc_fielda(t, -2, "line");
				pushCrocstr(t, name);        croc_fielda(t, -2, "name");

				if(kind == Kind::Global)
				{
					croc_pushString(t, "global");
					croc_fielda(t, -2, "protection");
					croc_pushString(t, "variable");
				}
				else
					pushCrocstr(t, kindStr);

				croc_fielda(t, -2, "kind");

				if(line.length)
				{
					pushCrocstr(t, line);
					croc_fielda(t, -2, "value");
				}
				else if(kind == Kind::Function)
				{
					croc_array_new(t, 0);
					croc_fielda(t, -2, "params");

					if(croc_len(t, dt) <= 2) // module + function
					{
						croc_pushString(t, "global");
						croc_fielda(t, -2, "protection");
					}
				}
				else if(kind == Kind::Module || kind == Kind::Class || kind == Kind::Namespace)
				{
					croc_array_new(t, 0);
					croc_fielda(t, -2, "children");

					if(kind != Kind::Module)
					{
						croc_pushString(t, "global");
						croc_fielda(t, -2, "protection");
					}
				}
			}
			else if((kind == Kind::Class || kind == Kind::Namespace) && arrStartsWith(line, ATODA("!base ")))
			{
				line = line.sliceToEnd(ATODA("!base ").length);
				auto haveBase = croc_hasField(t, -1, "base");

				if(kind == Kind::Namespace && haveBase)
					croc_eh_throwStd(t, "ApiError", "Namespace docstring cannot have more than one !base line");

				if(!haveBase)
					pushCrocstr(t, line);
				else
				{
					croc_field(t, -2, "base");
					croc_pushString(t, ", ");
					pushCrocstr(t, line);
					croc_cat(t, 3);
				}

				croc_fielda(t, -2, "base");
			}
			else if(kind == Kind::Function && arrStartsWith(line, ATODA("!param ")))
			{
				line = line.sliceToEnd(ATODA("!param ").length);

				if(line.length == 0)
					croc_eh_throwStd(t, "ApiError", "Expected parameter name after !param in docstring");

				auto colonPos = findCharFast(line, ':');

				if(colonPos == 0)
					croc_eh_throwStd(t, "ApiError", "Expected parameter name after !param in docstring");
				else if(colonPos == line.length || colonPos == line.length - 1)
					croc_eh_throwStd(t, "ApiError", "Expected parameter type after name in docstring");

				auto name = line.slice(0, colonPos);
				line = line.sliceToEnd(colonPos + 1);

				auto eqPos = findCharFast(line, '=');

				if(eqPos == 0)
					croc_eh_throwStd(t, "ApiError", "Expected parameter type after colon in docstring");
				else if(eqPos == line.length - 1)
					croc_eh_throwStd(t, "ApiError", "Expected default value after '=' in parameter docstring");

				auto type = line.slice(0, eqPos);

				if(eqPos == line.length)
					line = crocstr();
				else
					line = line.sliceToEnd(eqPos + 1);

				croc_field(t, -1, "params");
				croc_table_new(t, 0);
				croc_pushString(t, d->file);     croc_fielda(t, -2, "file");
				croc_field(t, -3, "line");       croc_fielda(t, -2, "line");
				croc_pushString(t, "parameter"); croc_fielda(t, -2, "kind");
				pushCrocstr(t, name);            croc_fielda(t, -2, "name");
				pushCrocstr(t, type);            croc_fielda(t, -2, "type");

				if(line.length)
				{
					pushCrocstr(t, line);
					croc_fielda(t, -2, "value");
				}

				croc_cateq(t, -2, 1);
				croc_popTop(t);
			}
			else
			{
				firstDocLine = line;
				return false;
			}

			return true;
		});

		if(firstDocLine.length)
			docString = strTrimWS(crocstr::n(firstDocLine.ptr, docString.ptr + docString.length - firstDocLine.ptr));
		else
			docString = crocstr();

		if(docString == ATODA("ditto"))
			doDitto(d, dt);
		else
		{
			pushCrocstr(t, docString);
			croc_compiler_processDocComment(t);
		}
	}
}

extern "C"
{
	void croc_ex_doc_init(CrocThread* t, CrocDoc* d, const char* file)
	{
		d->t = t;
		d->file = file;
		d->dittoDepth = 0;

		getDocTables(d);
		d->startIdx = croc_len(t, -1);
		croc_popTop(t);
	}

	void croc_ex_doc_finish(CrocDoc* d)
	{
		getDocTables(d);
		auto l = croc_len(d->t, -1);
		if(l != d->startIdx)
		{
			if(l < d->startIdx)
				croc_eh_throwStd(d->t, "ApiError",
					"Mismatched documentation pushes and pops (stack is smaller by %" CROC_INTEGER_FORMAT ")",
					d->startIdx - l);
			else
				croc_eh_throwStd(d->t, "ApiError",
					"Mismatched documentation pushes and pops (stack is bigger by %" CROC_INTEGER_FORMAT ")",
					l - d->startIdx);
		}
		croc_popTop(d->t);
	}

	void croc_ex_doc_push(CrocDoc* d, const char* docString)
	{
		if(d->dittoDepth > 0)
		{
			d->dittoDepth++;
			return;
		}

		auto dt = getDocTables(d);
		croc_table_new(d->t, 0);
		croc_dupTop(d->t);
		croc_cateq(d->t, dt, 1);
		parseDocString(d, dt, atoda(docString));
		croc_pop(d->t, 2);
	}

	void croc_ex_doc_popNamed(CrocDoc* d, word_t idx, const char* parentField)
	{
		auto t = d->t;
		idx = croc_absIndex(t, idx);

		auto dt = getDocTables(d);

		if(croc_len(t, dt) == 0)
			croc_eh_throwStd(t, "ApiError", "Documentation stack underflow!");

		if(d->dittoDepth > 0)
		{
			d->dittoDepth--;

			if(d->dittoDepth > 0)
				return;

			switch(croc_type(t, idx))
			{
				case CrocType_Function:
				case CrocType_Class:
				case CrocType_Namespace: {
					auto dittoed = croc_idxi(t, dt, -2);

					if(!croc_hasField(t, dittoed, parentField))
						croc_eh_throwStd(t, "ApiError",
							"Corruption! Parent decl doesn't have %s anymore.", parentField);

					croc_field(t, dittoed, parentField);

					if(croc_len(t, -1) == 0)
						croc_eh_throwStd(t, "ApiError",
							"Corruption! Parent decl's %s array is empty somehow.", parentField);

					croc_idxi(t, -1, -1);
					croc_insertAndPop(t, dittoed);

					croc_lenai(t, dt, croc_len(t, dt) - 1); // remove ditto doctable

					croc_pushGlobal(t, "_doc_");
					croc_pushNull(t);
					croc_dup(t, idx);
					croc_dup(t, dittoed);
					croc_call(t, -4, 0);
					croc_pop(t, 2);
					return;
				}
				default:
					croc_popTop(t);
					return;
			}
		}

		auto docTab = croc_idxi(t, dt, -1);

		// first call _doc_ on the thing if we should
		switch(croc_type(t, idx))
		{
			case CrocType_Function:
			case CrocType_Class:
			case CrocType_Namespace:
				croc_pushGlobal(t, "_doc_");
				croc_pushNull(t);
				croc_dup(t, idx);
				croc_dup(t, docTab);
				croc_call(t, -4, 0);
				break;

			default:
				break;
		}

		// then put it in the parent
		croc_lenai(t, dt, croc_len(t, dt) - 1);

		if(croc_len(t, dt) > 0)
		{
			auto parent = croc_idxi(t, dt, -1);

			croc_pushString(t, parentField);

			if(!croc_in(t, -1, -2))
			{
				croc_array_new(t, 0);
				croc_fielda(t, parent, parentField);
			}

			croc_fieldStk(t, parent);
			croc_dup(t, docTab);
			croc_cateq(t, -2, 1);
			croc_pop(t, 2);
		}

		croc_pop(t, 2);
	}

	void croc_ex_doc_mergeModuleDocs(CrocDoc* d)
	{
		auto t = d->t;
		auto subModule = croc_absIndex(t, -1);

		if(!croc_isValidIndex(t, subModule) || !croc_isTable(t, subModule))
			croc_eh_throwStd(t, "ApiError", "No sub-module doc table on top of the stack");

		croc_field(t, subModule, "kind");

		if(!croc_isString(t, -1) || getCrocstr(t, -1) != ATODA("module") || !croc_hasField(t, subModule, "children"))
			croc_eh_throwStd(t, "ApiError", "Sub-module doc table is malformed or not a module doc table");

		croc_popTop(t);

		auto dt = getDocTables(d);

		if(croc_len(t, dt) == 0)
			croc_eh_throwStd(t, "ApiError", "No parent module to merge docs with");

		auto parent = croc_idxi(t, dt, -1);

		croc_pushString(t, "children");

		if(!croc_in(t, -1, parent))
		{
			croc_array_new(t, 0);
			croc_fielda(t, parent, "children");
		}

		croc_fieldStk(t, parent);
		croc_insertAndPop(t, parent);

		croc_field(t, subModule, "children");
		croc_cateq(t, parent, 1);

		croc_pop(t, 2);
	}

	namespace
	{
		void docGlobalImpl(CrocDoc* d, const char* str, uword dt)
		{
			croc_ex_doc_push(d, str);
			croc_idxi(d->t, dt, -1);
			croc_field(d->t, -1, "name");
			croc_pushGlobalStk(d->t);
			croc_ex_doc_pop(d, -1);
			croc_pop(d->t, 2);
		}

		void docFieldImpl(CrocDoc* d, const char* str, uword dt, uword obj)
		{
			croc_ex_doc_push(d, str);
			croc_idxi(d->t, dt, -1);
			croc_field(d->t, -1, "name");
			croc_fieldStk(d->t, obj);
			croc_ex_doc_pop(d, -1);
			croc_pop(d->t, 2);
		}
	}

	void croc_ex_docGlobal(CrocDoc* d, const char* docString)
	{
		auto t = d->t;
		auto dt = getDocTables(d);
		docGlobalImpl(d, docString, dt);
		assert(croc_getStackSize(t) - 1 == cast(uword)dt);
		croc_popTop(t);
	}

	void croc_ex_docField(CrocDoc* d, const char* docString)
	{
		auto t = d->t;
		auto obj = croc_getStackSize(t) - 1;
		auto dt = getDocTables(d);
		docFieldImpl(d, docString, dt, obj);
		assert(croc_getStackSize(t) - 1 == cast(uword)dt);
		croc_popTop(t);
	}

	void croc_ex_docGlobals(CrocDoc* d, const char** docStrings)
	{
		auto t = d->t;
		auto dt = getDocTables(d);

		for(auto str = *docStrings++; str != nullptr; str = *docStrings++)
			docGlobalImpl(d, str, dt);

		assert(croc_getStackSize(t) - 1 == cast(uword)dt);
		croc_popTop(t);
	}

	void croc_ex_docFields(CrocDoc* d, const char** docStrings)
	{
		auto t = d->t;
		auto obj = croc_getStackSize(t) - 1;
		auto dt = getDocTables(d);

		for(auto str = *docStrings++; str != nullptr; str = *docStrings++)
			docFieldImpl(d, str, dt, obj);

		assert(croc_getStackSize(t) - 1 == cast(uword)dt);
		croc_popTop(t);
	}
}