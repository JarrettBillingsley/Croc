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

import croc.api_interpreter;
import croc.api_stack;
import croc.compiler_ast;
import croc.compiler_astvisitor;
import croc.compiler_types;
import croc.types;

// TODO: Adding decorators

scope class DocGen : IdentityVisitor
{
	private word[] mChildIndices;
	private word[] mDocTables;
	private CrocThread* t;
	private word mDocTable;

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
	
	private void pushDocTable(ref CompileLoc loc, char[] type, char[] name, char[] docs)
	{
		c.alloc.resizeArray(mChildIndices, mChildIndices.length + 1);
		c.alloc.resizeArray(mDocTables, mDocTables.length + 1);
		
		mChildIndices[$ - 1] = 0;
		mDocTable = newTable(t);
		mDocTables[$ - 1] = mDocTable;
		
		pushString(t, loc.file);
		fielda(t, mDocTable, "file");
		pushInt(t, loc.line);
		fielda(t, mDocTable, "line");
		pushString(t, type);
		fielda(t, mDocTable, "type");
		pushString(t, name);
		fielda(t, mDocTable, "name");

		if(docs)
		{
			pushString(t, docs);
			fielda(t, mDocTable, "docs");
		}
	}
	
	private void popDocTable(char[] parentField = "children")
	{
		assert(mDocTable == stackSize(t) - 1);
		assert(mChildIndices.length > 1);

		c.alloc.resizeArray(mChildIndices, mChildIndices.length - 1);
		c.alloc.resizeArray(mDocTables, mDocTables.length - 1);

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
		
		pop(t);
		mChildIndices[$ - 1]++;
		mDocTable = mDocTables[$ - 1];
	}
	
	void unpopTable()
	{
		field(t, mDocTable, "children");
		idxi(t, -1, -1);
		insertAndPop(t, -2);
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

		pushDocTable(m.location, "module", name, m.docs);

		foreach(ref s; m.statements.as!(BlockStmt).statements)
			s = visitS(s);
			
		// leave the doc table on the stack
		return m;
	}
	
	public override FuncDecl visit(FuncDecl d)
	{
		d.def = visit(d.def);
		unpopTable();
		
		if(d.protection == Protection.Local)
			pushString(t, "local");
		else
			pushString(t, "global");
		
		fielda(t, -2, "protection");
		pop(t);
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
			pushDocTable(d.location, p.typeString ? p.typeString : "any", p.name.name, null);

			if(p.valueString)
			{
				pushString(t, p.valueString);
				fielda(t, mDocTable, "value");
			}

			popDocTable("params");
		}

		if(d.isVararg)
		{
			pushDocTable(d.location, "vararg", "vararg", null);
			popDocTable("params");
		}

		popDocTable();
		return d;
	}

	public override ClassDecl visit(ClassDecl d)
	{
		d.def = visit(d.def);
		unpopTable();
		
		if(d.protection == Protection.Local)
			pushString(t, "local");
		else
			pushString(t, "global");
		
		fielda(t, -2, "protection");
		pop(t);
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

		foreach(ref f; d.fields)
		{
			if(auto method = f.initializer.as!(FuncLiteralExp))
				f.initializer = visit(method);
			else
			{
				// TODO: this location might not be on exactly the same line as the field itself..
				pushDocTable(f.initializer.location, "field", f.name, f.docs);
				
				if(f.initializer.sourceStr)
				{
					pushString(t, f.initializer.sourceStr);
					fielda(t, mDocTable, "value");
				}

				popDocTable();
			}
		}

		popDocTable();
		return d;
	}
	
	public override NamespaceDecl visit(NamespaceDecl d)
	{
		d.def = visit(d.def);
		unpopTable();
		
		if(d.protection == Protection.Local)
			pushString(t, "local");
		else
			pushString(t, "global");
		
		fielda(t, -2, "protection");
		pop(t);
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

		foreach(ref f; d.fields)
		{
			if(auto method = f.initializer.as!(FuncLiteralExp))
				f.initializer = visit(method);
			else
			{
				// TODO: this location might not be on the exact line of the field..
				pushDocTable(f.initializer.location, "field", f.name, f.docs);
				
				if(f.initializer.sourceStr)
				{
					pushString(t, f.initializer.sourceStr);
					fielda(t, mDocTable, "value");
				}

				popDocTable();
			}
		}

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
				pushString(t, ", ");
			pushString(t, name.name);
		}
		
		cat(t, (d.names.length * 2) - 1);
		auto name = c.newString(getString(t, -1));
		pop(t);
		
		pushDocTable(d.location, d.protection == Protection.Local ? "local" : "global", name, d.docs);
		
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
		return d;
	}

	public override FuncLiteralExp visit(FuncLiteralExp e)
	{
		e.def = visit(e.def);
		return e;
	}
}