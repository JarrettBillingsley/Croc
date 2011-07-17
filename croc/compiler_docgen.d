/******************************************************************************
This module contains an AST visitor which outputs documentation extracted from
documentation comments in the code.

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

module croc.compiler_docgen;

import tango.text.Util;

import croc.api_interpreter;
import croc.api_stack;
import croc.compiler_ast;
import croc.compiler_astvisitor;
import croc.compiler_types;
import croc.types;

scope class DocGen : IdentityVisitor
{
	private word[] mChildIndices;
	private word[] mDocTables;
	private CrocThread* t;
	private word mDocTable;
	private int mDittoDepth;

	public this(ICompiler c)
	{
		super(c);
		t = c.thread;
	}

	~this()
	{
		c.alloc.freeArray(mChildIndices);
		c.alloc.freeArray(mDocTables);
	}

	private void pushDocTable(ref CompileLoc loc, char[] kind, char[] name, char[] docs)
	{
		if(mDittoDepth > 0)
		{
			mDittoDepth++;
			return;
		}

		c.alloc.resizeArray(mChildIndices, mChildIndices.length + 1);
		c.alloc.resizeArray(mDocTables, mDocTables.length + 1);

		mChildIndices[$ - 1] = 0;
		mDocTable = newTable(t);
		mDocTables[$ - 1] = mDocTable;

		pushString(t, loc.file); fielda(t, mDocTable, "file");
		pushInt(t,    loc.line); fielda(t, mDocTable, "line");
		pushString(t, kind);     fielda(t, mDocTable, "kind");
		pushString(t, name);     fielda(t, mDocTable, "name");
		pushString(t, docs);     fielda(t, mDocTable, "docs");

		if(kind == "module" || kind == "class" || kind == "namespace")
			ensureChildren();
		else if(kind == "function")
			ensureChildren("params");

		if(docs.trim() == "ditto")
		{
			// At top level?
			if(mDocTables.length == 1)
				c.exception(loc, "Cannot use ditto on the top-level declaration");

			// Get the parent and try to get the last declaration before this one
			dup(t, mDocTables[$ - 2]);

			bool okay = false;

			if(hasField(t, -1, "children"))
			{
				field(t, -1, "children");

				if(len(t, -1) > 0)
				{
					idxi(t, -1, -1);
					insertAndPop(t, -3);
					okay = true;
				}
			}

			if(!okay)
				c.exception(loc, "No previous declaration to ditto from");

			// See if the previous decl's kind is the same
			field(t, -1, "kind");

			if(getString(t, -1) != kind)
			{
				field(t, -2, "name");
				c.exception(loc, "Can't ditto documentation for '{}': it's a {}, but '{}' was a {}", name, kind, getString(t, -1), getString(t, -2));
			}

			pop(t);

			// Okay, we can ditto.
			mDittoDepth++;

			if(!hasField(t, -1, "dittos"))
			{
				newArray(t, 0);
				fielda(t, -2, "dittos");
			}

			// Append this doctable to the dittos of the previous decl.
			field(t, -1, "dittos");
			dup(t, mDocTable);
			cateq(t, -2, 1);
			pop(t, 2);
		}
	}

	private void popDocTable(char[] parentField = "children")
	{
		bool wasDitto = false;

		if(mDittoDepth > 0)
		{
			mDittoDepth--;

			if(mDittoDepth > 0)
				return;
				
			wasDitto = true;
		}

		assert(mDocTable == stackSize(t) - 1);
		assert(mChildIndices.length > 1);

		c.alloc.resizeArray(mChildIndices, mChildIndices.length - 1);
		c.alloc.resizeArray(mDocTables, mDocTables.length - 1);

		if(!wasDitto)
		{
			if(mChildIndices[$ - 1] == 0)
			{
				newArray(t, 1);
				dup(t, mDocTable);
				idxai(t, -2, 0);
				fielda(t, mDocTables[$ - 1], parentField);
			}
			else
			{
				field(t, mDocTables[$ - 1], parentField);
				dup(t, mDocTable);
				cateq(t, -2, 1);
				pop(t);
			}
	
			mChildIndices[$ - 1]++;
		}

		pop(t);
		mDocTable = mDocTables[$ - 1];
	}

	private void ensureChildren(char[] parentField = "children")
	{
		pushString(t, parentField);

		if(!opin(t, -1, mDocTable))
		{
			newArray(t, 0);
			idxa(t, mDocTable);
		}
		else
			pop(t);
	}

	private void unpopTable()
	{
		field(t, mDocTable, "children");
		idxi(t, -1, -1);
		insertAndPop(t, -2);
	}

	private void doProtection(Protection p)
	{
		unpopTable();

		if(p == Protection.Local)
			pushString(t, "local");
		else
			pushString(t, "global"); // covers "default" protection as well, since we're only dealing with globals

		fielda(t, -2, "protection");
		pop(t);
	}

	private void doFields(T)(T[] fields)
	{
		foreach(ref f; fields)
		{
			if(f.docs.length == 0)
				continue;

			if(auto method = f.initializer.as!(FuncLiteralExp))
			{
				f.initializer = visit(method);

				if(c.docDecorators)
					f.initializer = makeDocCall(f.initializer);
			}
			else
			{
				// TODO: this location might not be on exactly the same line as the field itself.. huge deal?
				pushDocTable(f.initializer.location, "field", f.name, f.docs);

				if(f.initializer.sourceStr)
				{
					pushString(t, f.initializer.sourceStr);
					fielda(t, mDocTable, "value");
				}

				popDocTable();
			}
		}
	}

	private Expression docTableToAST(CompileLoc loc)
	{
		// just has to handle tables, arrays, strings, and ints
		Expression derp(word slot)
		{
			switch(type(t, slot))
			{
				case CrocValue.Type.Int:    return new(c) IntExp(c, loc, getInt(t, slot));
				case CrocValue.Type.String: return new(c) StringExp(c, loc, getString(t, slot));

				case CrocValue.Type.Table:
					scope fields = new List!(TableCtorExp.Field)(c.alloc);

					dup(t, slot);

					foreach(word k, word v; foreachLoop(t, 1))
					{
						auto key = derp(k);
						auto val = derp(v);
						fields ~= TableCtorExp.Field(key, val);
					}

					return new(c) TableCtorExp(c, loc, loc, fields.toArray());

				case CrocValue.Type.Array:
					scope exps = new List!(Expression)(c.alloc);

					dup(t, slot);

					foreach(word v; foreachLoop(t, 1))
						exps ~= derp(v);

					return new(c) ArrayCtorExp(c, loc, loc, exps.toArray());

				default: assert(false);
			}
		}

		return derp(mDocTable);
	}

	Identifier docIdent(CompileLoc loc)
	{
		return new(c) Identifier(c, loc, c.newString("_doc_"));
	}

	Identifier doctableIdent(CompileLoc loc)
	{
		return new(c) Identifier(c, loc, c.newString("__doctable"));
	}

	Decorator makeDeco(CompileLoc loc, Decorator existing, bool lastIndex = true)
	{
		if(mDittoDepth > 0)
			return existing;

		auto f = new(c) IdentExp(c, docIdent(loc));
		scope args = new List!(Expression)(c.alloc);
		args ~= new(c) IdentExp(c, doctableIdent(loc));

		foreach(idx; mChildIndices[0 .. $ - 1])
			args ~= new(c) IntExp(c, loc, idx);

		if(lastIndex)
			args ~= new(c) IntExp(c, loc, mChildIndices[$ - 1] - 1);

		return new(c) Decorator(c, loc, loc, f, null, args.toArray(), existing);
	}

	Expression makeDocCall(Expression init)
	{
		if(mDittoDepth > 0)
			return init;

		auto f = new(c) IdentExp(c, docIdent(init.location));
		scope args = new List!(Expression)(c.alloc);
		args ~= init;
		args ~= new(c) IdentExp(c, doctableIdent(init.location));

		foreach(idx; mChildIndices[0 .. $ - 1])
			args ~= new(c) IntExp(c, init.location, idx);

		args ~= new(c) IntExp(c, init.location, mChildIndices[$ - 1] - 1);

		return new(c) CallExp(c, init.endLocation, f, null, args.toArray());
	}

	public override Module visit(Module m)
	{
		assert(m.statements.as!(BlockStmt) !is null);

		foreach(i, n; m.names)
		{
			if(i > 0)
				pushChar(t, '.');
			pushString(t, n);
		}

		cat(t, (m.names.length * 2) - 1);
		auto name = c.newString(getString(t, -1));
		pop(t);

		pushDocTable(m.location, "module", name, m.docs ? m.docs : "\n");

		auto b = m.statements.as!(BlockStmt);

		foreach(ref s; b.statements)
			s = visitS(s);
			
		if(c.docDecorators)
		{
			// create a "local __doctable = { ... }" as the first statement
			scope names = new List!(Identifier)(c.alloc);
			names ~= doctableIdent(m.location);
			scope inits = new List!(Expression)(c.alloc);
			inits ~= docTableToAST(m.location);

			scope stmts = new List!(Statement)(c.alloc);
			stmts ~= new(c) VarDecl(c, m.location, m.location, Protection.Local, names.toArray(), inits.toArray());
			stmts ~= b.statements;
			auto oldStmts = b.statements;
			b.statements = stmts.toArray();
			c.alloc.freeArray(oldStmts);

			// put a decorator on the module
			m.decorator = makeDeco(m.location, m.decorator, false);
		}

		// leave the doc table on the stack -- it's up to the compiler to decide whether or not to drop it
		return m;
	}

	public FuncDef visitStatements(FuncDef d)
	{
		pushDocTable(d.location, "module", d.name.name, "\n");

		auto b = d.code.as!(BlockStmt);
		assert(b !is null);

		foreach(ref s; b.statements)
			s = visitS(s);

		if(c.docDecorators)
		{
			// create a "local __doctable = { ... }" as the first statement
			scope names = new List!(Identifier)(c.alloc);
			names ~= doctableIdent(d.location);
			scope inits = new List!(Expression)(c.alloc);
			inits ~= docTableToAST(d.location);

			scope stmts = new List!(Statement)(c.alloc);
			stmts ~= new(c) VarDecl(c, d.location, d.location, Protection.Local, names.toArray(), inits.toArray());
			stmts ~= b.statements;
			auto oldStmts = b.statements;
			b.statements = stmts.toArray();
			c.alloc.freeArray(oldStmts);
		}

		return d;
	}

	public override FuncDecl visit(FuncDecl d)
	{
		if(d.def.docs.length == 0)
			return d;

		d.def = visit(d.def);
		doProtection(d.protection);

		if(c.docDecorators)
			d.decorator = makeDeco(d.location, d.decorator);

		return d;
	}

	public override FuncDef visit(FuncDef d)
	{
		if(d.docs.length == 0)
			return d;

		pushDocTable(d.location, "function", d.name.name, d.docs);

		foreach(i, ref p; d.params)
		{
			// Skip "this" unless it has a nontrivial typemask
			if(i == 0 && p.typeMask == FuncDef.TypeMask.Any)
				continue;

			// TODO: this currently does not report the correct typemask for params like "x: int = 4", since
			// these are technically "int|null"
			pushDocTable(d.location, "parameter", p.name.name, "\n");
			
			pushString(t, p.typeString ? p.typeString : "any");
			fielda(t, mDocTable, "type");

			if(p.valueString)
			{
				pushString(t, p.valueString);
				fielda(t, mDocTable, "value");
			}

			popDocTable("params");
		}

		if(d.isVararg)
		{
			pushDocTable(d.location, "parameter", "vararg", "\n");
			pushString(t, "vararg");
			fielda(t, mDocTable, "type");
			popDocTable("params");
		}

		popDocTable();
		return d;
	}

	public override ClassDecl visit(ClassDecl d)
	{
		if(d.def.docs.length == 0)
			return d;

		d.def = visit(d.def);
		doProtection(d.protection);

		if(c.docDecorators)
			d.decorator = makeDeco(d.location, d.decorator);

		return d;
	}

	public override ClassDef visit(ClassDef d)
	{
		if(d.docs.length == 0)
			return d;

		pushDocTable(d.location, "class", d.name.name, d.docs);

		auto base = d.baseClass.as!(IdentExp);

		if(!base || base.name.name != "Object")
		{
			pushString(t, d.baseClass.sourceStr);
			fielda(t, mDocTable, "base");
		}

		doFields(d.fields);
		popDocTable();
		return d;
	}

	public override NamespaceDecl visit(NamespaceDecl d)
	{
		if(d.def.docs.length == 0)
			return d;

		d.def = visit(d.def);
		doProtection(d.protection);

		if(c.docDecorators)
			d.decorator = makeDeco(d.location, d.decorator);

		return d;
	}

	public override NamespaceDef visit(NamespaceDef d)
	{
		if(d.docs.length == 0)
			return d;

		pushDocTable(d.location, "namespace", d.name.name, d.docs);

		if(d.parent)
		{
			pushString(t, d.parent.sourceStr);
			fielda(t, mDocTable, "base");
		}

		doFields(d.fields);
		popDocTable();
		return d;
	}
	
	public override VarDecl visit(VarDecl d)
	{
		if(d.docs.length == 0)
			return d;
			
		foreach(i, name; d.names)
		{
			if(i > 0)
				pushString(t, ",");
			pushString(t, name.name);
		}

		cat(t, (d.names.length * 2) - 1);
		auto name = c.newString(getString(t, -1));
		pop(t);

		pushDocTable(d.location, "variable", name, d.docs);

		if(d.initializer)
		{
			foreach(i, init; d.initializer)
			{
				if(i > 0)
					pushString(t, ", ");
				pushString(t, init.sourceStr);
			}

			cat(t, (d.initializer.length * 2) - 1);
			fielda(t, mDocTable, "value");
		}

		popDocTable();
		doProtection(d.protection);
		return d;
	}

	public override ScopeStmt visit(ScopeStmt s)
	{
		s.statement = visitS(s.statement);
		return s;
	}

	public override BlockStmt visit(BlockStmt s)
	{
		foreach(ref stmt; s.statements)
			stmt = visitS(stmt);

		return s;
	}

	public override FuncLiteralExp visit(FuncLiteralExp e)
	{
		e.def = visit(e.def);
		return e;
	}
}