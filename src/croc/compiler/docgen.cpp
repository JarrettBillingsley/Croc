
#include "croc/api.h"
#include "croc/compiler/docgen.hpp"
#include "croc/compiler/docparser.hpp"
#include "croc/compiler/types.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"
#include "croc/util/str.hpp"

namespace croc
{
	FuncDef* DocGen::visitStatements(FuncDef* d)
	{
		DocTableDesc desc;
		pushDocTable(desc, d->location, d->location, "module", d->name->name, ATODA(""));

		auto b = AST_AS(BlockStmt, d->code);
		assert(b != nullptr);

		for(auto &s: b->statements)
			s = visit(s);

		if(c.docDecorators())
		{
			// create a "local __doctable = { ... }" as the first statement
			List<Identifier*> names(c);
			names.add(doctableIdent(d->location));
			List<Expression*> inits(c);
			inits.add(docTableToAST(d->location));

			List<Statement*> stmts(c);
			stmts.add(new(c) VarDecl(d->location, d->location, Protection::Local, names.toArray(), inits.toArray()));
			stmts.add(b->statements);
			b->statements = stmts.toArray();
		}

		return d;
	}

	Module* DocGen::visit(Module* m)
	{
		DocTableDesc desc;
		pushDocTable(desc, m->location, m->docsLoc, "module", m->name, m->docs.length ? m->docs : ATODA(""));

		auto b = AST_AS(BlockStmt, m->statements);
		assert(b != nullptr);

		for(auto &s: b->statements)
			s = visit(s);

		if(c.docDecorators())
		{
			// create a "local __doctable = { ... }" as the first statement
			List<Identifier*> names(c);
			names.add(doctableIdent(m->location));
			List<Expression*> inits(c);
			inits.add(docTableToAST(m->location));

			List<Statement*> stmts(c);
			stmts.add(new(c) VarDecl(m->location, m->location, Protection::Local, names.toArray(), inits.toArray()));
			stmts.add(b->statements);
			b->statements = stmts.toArray();

			// put a decorator on the module
			m->decorator = makeDeco(m->location, m->decorator, false);
		}

		// leave the doc table on the stack -- it's up to the compiler to decide whether or not to drop it
		return m;
	}

	FuncDecl* DocGen::visit(FuncDecl* d)
	{
		if(d->def->docs.length == 0)
			return d;

		d->def = visit(d->def);
		doProtection(d->protection);

		if(c.docDecorators())
			d->decorator = makeDeco(d->location, d->decorator);

		return d;
	}

	FuncDef* DocGen::visit(FuncDef* d)
	{
		if(d->docs.length == 0)
			return d;

		bool isDitto = strTrimWS(d->docs) == ATODA("ditto");

		// We don't actually process the comments here, as with other kinds of doc tables..
		DocTableDesc desc;
		pushDocTable(desc, d->location, d->location, "function", d->name->name, d->docs);

		if(isDitto)
			mDittoDepth--;

		bool first = true;

		for(auto &p: d->params)
		{
			// Skip "this" unless it has a nontrivial typemask
			if(first)
			{
				first = false;
				if(p.typeMask == cast(uint32_t)TypeMask::Any && p.customConstraint == nullptr)
					continue;
			}

			// TODO: this currently does not report the correct typemask for params like "x: int = 4", since
			// these are technically "int|null"
			DocTableDesc pdesc;
			pushDocTable(pdesc, d->location, d->location, "parameter", p.name->name, ATODA(""));

			if(p.typeString.length)
				pushCrocstr(t, p.typeString);
			else
				croc_pushString(t, "any");

			croc_fielda(t, mDocTable, "type");

			if(p.valueString.length)
			{
				pushCrocstr(t, p.valueString);
				croc_fielda(t, mDocTable, "value");
			}

			popDocTable(pdesc, "params");
		}

		if(d->isVararg)
		{
			DocTableDesc pdesc;
			pushDocTable(pdesc, d->location, d->location, "parameter", ATODA("vararg"), ATODA(""));
			croc_pushString(t, "vararg");
			croc_fielda(t, mDocTable, "type");
			popDocTable(pdesc, "params");
		}

		if(isDitto)
			mDittoDepth++;
		else
		{
			// NOW we do the comment processing
			addComments(d->docsLoc, d->docs);
		}

		popDocTable(desc);
		return d;
	}

	ClassDecl* DocGen::visit(ClassDecl* d)
	{
		if(d->docs.length == 0)
			return d;

		DocTableDesc desc;
		pushDocTable(desc, d->location, d->docsLoc, "class", d->name->name, d->docs);

		if(d->baseClasses.length > 0)
		{
			auto s = d->baseClasses[0]->sourceStr;
			croc_pushStringn(t, cast(const char*)s.ptr, s.length);

			for(auto base: d->baseClasses.sliceToEnd(1))
			{
				croc_pushString(t, ", ");
				croc_pushStringn(t, cast(const char*)base->sourceStr.ptr, base->sourceStr.length);
			}

			croc_cat(t, (d->baseClasses.length * 2) - 1);
			croc_fielda(t, mDocTable, "base");
		}

		doFields(d->fields);
		popDocTable(desc);
		doProtection(d->protection);

		if(c.docDecorators())
			d->decorator = makeDeco(d->location, d->decorator);

		return d;
	}

	NamespaceDecl* DocGen::visit(NamespaceDecl* d)
	{
		if(d->docs.length == 0)
			return d;

		DocTableDesc desc;
		pushDocTable(desc, d->location, d->docsLoc, "namespace", d->name->name, d->docs);

		if(d->parent)
		{
			croc_pushStringn(t, cast(const char*)d->parent->sourceStr.ptr, d->parent->sourceStr.length);
			croc_fielda(t, mDocTable, "base");
		}

		doFields(d->fields);
		popDocTable(desc);
		doProtection(d->protection);

		if(c.docDecorators())
			d->decorator = makeDeco(d->location, d->decorator);

		return d;
	}

	VarDecl* DocGen::visit(VarDecl* d)
	{
		if(d->docs.length == 0)
			return d;

		auto makeTable = [&, this](uword idx)
		{
			DocTableDesc desc;
			pushDocTable(desc, d->location, d->docsLoc, "variable", d->names[idx]->name, idx == 0 ? d->docs : ATODA("ditto"));

			if(idx < d->initializer.length)
			{
				pushTrimmedString(d->initializer[idx]->sourceStr);
				croc_fielda(t, mDocTable, "value");
			}

			if(d->protection == Protection::Local)
				croc_pushString(t, "local");
			else
				croc_pushString(t, "global"); // covers "default" protection as well, since we're only dealing with globals

			croc_fielda(t, -2, "protection");
			popDocTable(desc);
		};

		for(uword i = 0; i < d->names.length; i++)
			makeTable(i);

		return d;
	}

	ScopeStmt* DocGen::visit(ScopeStmt* s)
	{
		s->statement = visit(s->statement);
		return s;
	}

	BlockStmt* DocGen::visit(BlockStmt* s)
	{
		for(auto &stmt: s->statements)
			stmt = visit(stmt);

		return s;
	}

	FuncLiteralExp* DocGen::visit(FuncLiteralExp* e)
	{
		e->def = visit(e->def);
		return e;
	}

	void DocGen::addComments(CompileLoc docsLoc, crocstr docs)
	{
		auto slot = croc_getStackSize(t) - 1;

		if(tryCode(Thread::from(t), slot, [&]
		{
			processComment(t, docs);
		}))
		{
			auto loc = croc_field(t, slot, "location");
			croc_field(t, loc, "line");
			auto line = croc_getInt(t, -1);
			croc_popTop(t);
			croc_field(t, loc, "col");
			auto col = croc_getInt(t, -1);
			croc_popTop(t);

			line = line + docsLoc.line - 1; // - 1 because it's one-based

			if(line == 1)
				col += docsLoc.col - 1; // - 1 because it's one-based

			croc_pushInt(t, line);
			croc_fielda(t, loc, "line");
			croc_pushInt(t, col);
			croc_fielda(t, loc, "col");

			croc_popTop(t);
			croc_eh_throw(t);
		}
	}

	void DocGen::pushDocTable(DocTableDesc &desc, CompileLoc loc, CompileLoc docsLoc, const char* kind, crocstr name, crocstr docs)
	{
		if(mDittoDepth > 0)
		{
			mDittoDepth++;
			return;
		}

		desc.prev = mDocTableDesc;
		mDocTableDesc = &desc;
		desc.childIndex = 0;
		mDocTable = croc_table_new(t, 0);
		desc.docTable = mDocTable;

		pushCrocstr(t, loc.file);     croc_fielda(t, mDocTable, "file");
		croc_pushInt(t,    loc.line); croc_fielda(t, mDocTable, "line");
		croc_pushString(t, kind);     croc_fielda(t, mDocTable, "kind");
		pushCrocstr(t, name);         croc_fielda(t, mDocTable, "name");

		if(strcmp(kind, "module") == 0 || strcmp(kind, "class") == 0 || strcmp(kind, "namespace") == 0)
			ensureChildren();
		else if(strcmp(kind, "function") == 0)
			ensureChildren("params");

		if(strTrimWS(docs) == ATODA("ditto"))
		{
			// At top level?
			if(desc.prev == nullptr)
				c.semException(loc, "Cannot use ditto on the top-level declaration");

			// Get the parent and try to get the last declaration before this one
			croc_dup(t, desc.prev->docTable);

			if(croc_hasField(t, -1, "children"))
			{
				croc_field(t, -1, "children");

				if(croc_len(t, -1) > 0)
				{
					croc_idxi(t, -1, -1);
					croc_insertAndPop(t, -3);
					goto _okay;
				}
			}

			c.semException(loc, "No previous declaration to ditto from");
		_okay:

			// See if the previous decl's kind is the same
			croc_field(t, -1, "kind");

			if(strcmp(croc_getString(t, -1), kind) != 0)
			{
				croc_field(t, -2, "name");
				c.semException(loc, "Can't ditto documentation for '%.*s': it's a %s, but '%s' was a %s",
					cast(int)name.length, name.ptr, kind, croc_getString(t, -1), croc_getString(t, -2));
			}

			croc_popTop(t);

			// Okay, we can ditto.
			mDittoDepth++;

			if(!croc_hasField(t, -1, "dittos"))
			{
				croc_array_new(t, 0);
				croc_fielda(t, -2, "dittos");
			}

			// Append this doctable to the dittos of the previous decl.
			croc_field(t, -1, "dittos");
			croc_dup(t, mDocTable);
			croc_cateq(t, -2, 1);
			croc_pop(t, 2);

			// Fill in its docs member with just a single paragraph holding "ditto".
			croc_array_new(t, 1);
			croc_array_new(t, 1);
			croc_pushString(t, "ditto");
			croc_idxai(t, -2, 0);
			croc_idxai(t, -2, 0);
			croc_fielda(t, mDocTable, "docs");
		}
		else if(strcmp(kind, "function") != 0 && strcmp(kind, "parameter") != 0)
		{
			// Function docs are handled a little differently since they have to be done *after* the param doctables are added
			addComments(docsLoc, docs);
		}
	}

	void DocGen::popDocTable(DocTableDesc &desc, const char* parentField)
	{
		bool wasDitto = false;

		if(mDittoDepth > 0)
		{
			mDittoDepth--;

			if(mDittoDepth > 0)
				return;

			wasDitto = true;
		}

		assert(mDocTable == croc_getStackSize(t) - 1);
		mDocTableDesc = desc.prev;
		assert(mDocTableDesc != nullptr);

		if(!wasDitto)
		{
			if(mDocTableDesc->childIndex == 0)
			{
				croc_array_new(t, 1);
				croc_dup(t, mDocTable);
				croc_idxai(t, -2, 0);
				croc_fielda(t, mDocTableDesc->docTable, parentField);
			}
			else
			{
				croc_field(t, mDocTableDesc->docTable, parentField);
				croc_dup(t, mDocTable);
				croc_cateq(t, -2, 1);
				croc_popTop(t);
			}

			mDocTableDesc->childIndex++;
		}

		croc_popTop(t);
		mDocTable = mDocTableDesc->docTable;
	}

	void DocGen::ensureChildren(const char* parentField)
	{
		croc_pushString(t, parentField);

		if(!croc_in(t, -1, mDocTable))
		{
			croc_array_new(t, 0);
			croc_idxa(t, mDocTable);
		}
		else
			croc_popTop(t);
	}

	void DocGen::unpopTable()
	{
		croc_field(t, mDocTable, "children");
		croc_idxi(t, -1, -1);
		croc_insertAndPop(t, -2);
	}

	void DocGen::doProtection(Protection p)
	{
		unpopTable();

		if(p == Protection::Local)
			croc_pushString(t, "local");
		else
			croc_pushString(t, "global"); // covers "default" protection as well, since we're only dealing with globals

		croc_fielda(t, -2, "protection");
		croc_popTop(t);
	}

	Expression* DocGen::docTableToAST(CompileLoc loc)
	{
		auto t_ = Thread::from(t);

		// just has to handle tables, arrays, strings, and ints
		std::function<Expression*(word)> derp = [&, this](word slot) -> Expression*
		{
			switch(croc_type(t, slot))
			{
				case CrocType_Int:    return new(c) IntExp(loc, croc_getInt(t, slot));
				case CrocType_String: return new(c) StringExp(loc, c.newString(getCrocstr(t, slot)));

				case CrocType_Table: {
					List<TableCtorField> fields(c);

					for(auto node: getTable(t_, slot)->data)
					{
						auto kslot = push(t_, node->key);
						auto key = derp(kslot);
						auto vslot = push(t_, node->value);
						auto val = derp(vslot);
						croc_pop(t, 2);
						fields.add(TableCtorField(key, val));
					}

					return new(c) TableCtorExp(loc, loc, fields.toArray());
				}
				case CrocType_Array: {
					List<Expression*> exps(c);

					for(auto &v: getArray(t_, slot)->toDArray())
					{
						auto vslot = push(t_, v.value);
						exps.add(derp(vslot));
						croc_popTop(t);
					}

					return new(c) ArrayCtorExp(loc, loc, exps.toArray());
				}
				default: assert(false); return nullptr; // dummy
			}
		};

		return derp(mDocTable);
	}

	Identifier* DocGen::docIdent(CompileLoc loc)
	{
		return new(c) Identifier(loc, c.newString(ATODA("_doc_")));
	}

	Identifier* DocGen::doctableIdent(CompileLoc loc)
	{
		return new(c) Identifier(loc, c.newString(ATODA(CROC_INTERNAL_NAME("doctable"))));
	}

	Decorator* DocGen::makeDeco(CompileLoc loc, Decorator* existing, bool lastIndex)
	{
		if(mDittoDepth > 0)
			return existing;

		auto f = new(c) IdentExp(docIdent(loc));
		List<Expression*> args(c);
		args.add(new(c) IdentExp(doctableIdent(loc)));

		std::function<void(DocTableDesc*)> work = [&](DocTableDesc* desc)
		{
			if(desc->prev)
				work(desc->prev);

			args.add(new(c) IntExp(loc, desc->childIndex));
		};

		if(mDocTableDesc->prev)
			work(mDocTableDesc->prev);

		if(lastIndex)
			args.add(new(c) IntExp(loc, mDocTableDesc->childIndex - 1));

		return new(c) Decorator(loc, loc, f, nullptr, args.toArray(), existing);
	}

	Expression* DocGen::makeDocCall(Expression* init)
	{
		if(mDittoDepth > 0)
			return init;

		auto f = new(c) IdentExp(docIdent(init->location));
		List<Expression*> args(c);
		args.add(init);
		args.add(new(c) IdentExp(doctableIdent(init->location)));

		std::function<void(DocTableDesc*)> work = [&](DocTableDesc* desc)
		{
			if(desc->prev)
				work(desc->prev);

			args.add(new(c) IntExp(init->location, desc->childIndex));
		};

		if(mDocTableDesc->prev)
			work(mDocTableDesc->prev);

		args.add(new(c) IntExp(init->location, mDocTableDesc->childIndex - 1));

		return new(c) CallExp(init->endLocation, f, nullptr, args.toArray());
	}

	void DocGen::pushTrimmedString(crocstr str)
	{
		auto pos = findCharFast(str, '\n');

		if(pos == str.length)
			pushCrocstr(t, str);
		else
		{
			pushCrocstr(t, str.slice(0, pos));
			croc_pushString(t, "...");
			croc_cat(t, 2);
		}
	}
}