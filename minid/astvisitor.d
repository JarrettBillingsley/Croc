/******************************************************************************
License:
Copyright (c) 2008 Jarrett Billingsley

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

module minid.astvisitor;

import minid.ast;
import minid.compilertypes;

template returnType(char[] tag)
{
	static if(is(typeof(mixin(tag)) : Statement))
		alias Statement returnType;
	else static if(is(typeof(mixin(tag)) : Expression))
		alias Expression returnType;
	else
		alias AstNode returnType;
}

char[] generateVisitMethods()
{
	char[] ret;

	foreach(tag; AstTagNames)
		ret ~= "public returnType!(\"" ~ tag ~ "\") visit(" ~ tag ~ " node){ throw new Exception(\"no visit method implemented for AST node '" ~ tag ~ "'\"); }\n";

	return ret;
}

char[] generateDispatchFunctions()
{
	char[] ret;

	foreach(tag; AstTagNames)
		ret ~= "public static returnType!(\"" ~ tag ~ "\") visit" ~ tag ~ "(Visitor visitor, " ~ tag ~ " c) { return visitor.visit(c); }\n";

	return ret;
}

char[] generateDispatchTable()
{
	char[] ret = "private static const void*[] dispatchTable = [";

	foreach(tag; AstTagNames)
		ret ~= "cast(void*)&visit" ~ tag ~ ",\n";

	return ret[0 .. $ - 2] ~ "];"; // slice away last ",\n"
}

abstract class Visitor
{
	mixin(generateVisitMethods());
	mixin(generateDispatchFunctions());
	mixin(generateDispatchTable());
	static assert(dispatchTable.length == AstTagNames.length, "vtable length doesn't match number of AST tags");

	protected ICompiler c;

	public this(ICompiler c)
	{
		this.c = c;
	}

	public final Statement visit(Statement n)
	{
		return visitS(n);
	}

	public final Expression visit(Expression n)
	{
		return visitE(n);
	}

	public final AstNode visit(AstNode n)
	{
		return visitN(n);
	}

	public final Statement visitS(Statement n)
	{
		return cast(Statement)cast(void*)dispatch(n);
	}

	public final Expression visitE(Expression n)
	{
		return cast(Expression)cast(void*)dispatch(n);
	}

	public final AstNode visitN(AstNode n)
	{
		return dispatch(n);
	}
	
	protected final AstNode function(Visitor, AstNode) getDispatchFunction()(AstNode n)
	{
		return cast(AstNode function(Visitor, AstNode))dispatchTable[n.type];
	}

	protected final AstNode dispatch(AstNode n)
	{
		return getDispatchFunction(n)(this, n);
	}
}

char[] generateIdentityVisitMethods()
{
	char[] ret;

	foreach(tag; AstTagNames)
		ret ~= "public override returnType!(\"" ~ tag ~ "\") visit(" ~ tag ~ " node){ return node; }\n";

	return ret;
}

abstract class IdentityVisitor : Visitor
{
	mixin(generateIdentityVisitMethods());
	
	public this(ICompiler c)
	{
		super(c);
	}
}

debug class TestVisitor : Visitor
{
	import tango.io.Stdout;

	public this(ICompiler c)
	{
		super(c);
	}

	alias Visitor.visit visit;

	public override Module visit(Module m)
	{
		visit(m.modDecl);

		foreach(stmt; m.statements)
			visit(stmt);
			
		Stdout.newline;

		return m;
	}
	
	public override ModuleDecl visit(ModuleDecl m)
	{
		if(m.attrs)
			visitAttrs(m.attrs);
			
		Stdout("module ");

		bool first = true;

		foreach(name; m.names)
		{
			if(first)
				first = false;
			else
				Stdout(".");
				
			Stdout(name);
		}
		
		Stdout.newline;
		
		return m;
	}
	
	public override ExpressionStmt visit(ExpressionStmt s)
	{
		visit(s.expr);
		Stdout.newline;
		return s;
	}
	
	public override CallExp visit(CallExp e)
	{
		visit(e.op);
		Stdout("(");
		
		if(e.context)
		{
			Stdout("with ");
			visit(e.context);
			
			if(e.args.length > 0)
				Stdout(", ");
		}
		
		bool first = true;
		
		foreach(arg; e.args)
		{
			if(first)
				first = false;
			else
				Stdout(",");
			
			visit(arg);
		}
		
		Stdout(")");
		return e;
	}
	
	public override IdentExp visit(IdentExp e)
	{
		visit(e.name);
		return e;
	}
	
	public override Identifier visit(Identifier i)
	{
		Stdout(i.name);
		return i;
	}
	
	public override IntExp visit(IntExp e)
	{
		Stdout(e.value);
		return e;
	}

	public override StringExp visit(StringExp e)
	{
		Stdout("\"");

		foreach(c; e.value)
		{
			if(c < ' ')
				Stdout("\\x{:x2}", c);
			else if(c > 0x7f)
				Stdout("\\U{:X8}", c);
			else
				Stdout(c);
		}

		Stdout("\"");

		return e;
	}
	
	public override VarDecl visit(VarDecl d)
	{
		if(d.protection == Protection.Local)
			Stdout("local ");
		else if(d.protection == Protection.Global)
			Stdout("global ");
		else
			Stdout("??? ");
			
		bool first = true;
		
		foreach(name; d.names)
		{
			if(first)
				first = false;
			else
				Stdout(", ");

			visit(name);
		}

		if(d.initializer)
		{
			Stdout(" = ");
			visit(d.initializer);
		}
		
		return d;
	}

	public TableCtorExp visitAttrs(TableCtorExp attrs)
	{
		Stdout("</").newline;
		visit(attrs);
		Stdout("/>").newline;

		return attrs;
	}
	
	public override FuncLiteralExp visit(FuncLiteralExp e)
	{
		visit(e.def);
		return e;
	}
	
	public override FuncDef visit(FuncDef d)
	{
		Stdout("function ");
		visit(d.name);
		Stdout("(");

		if(d.params.length > 0)
		{
			visit(d.params[0].name);

			foreach(ref param; d.params[1 .. $])
			{
				Stdout(", ");
				visit(param.name);
			}
		}
		
		Stdout(")");

		visit(d.code);

		return d;
	}
	
	public override FuncDecl visit(FuncDecl d)
	{
		if(d.protection == Protection.Local)
			Stdout("local ");
		else
			Stdout("global ");
			
		visit(d.def);
		
		return d;
	}
	
	public override BlockStmt visit(BlockStmt s)
	{
		Stdout("{").newline;
		
		foreach(stmt; s.statements)
		{
			visit(stmt);
			Stdout.newline;
		}

		Stdout("}").newline;
		
		return s;
	}
	
	public override RawNamespaceExp visit(RawNamespaceExp e)
	{
		Stdout("raw_namespace ");
		visit(e.name);
		
		if(e.parent)
		{
			Stdout(" : ");
			visit(e.parent);
		}
		
		return e;
	}
	
	public override AssignStmt visit(AssignStmt s)
	{
		visit(s.lhs[0]);
		
		foreach(lhs; s.lhs[1 .. $])
		{
			Stdout(", ");
			visit(lhs);
		}
		
		Stdout(" = ");
		visit(s.rhs);
		
		return s;
	}
	
	public override DotExp visit(DotExp e)
	{
		visit(e.op);
		Stdout(".(");
		visit(e.name);
		Stdout(")");

		return e;
	}
	
	public override ScopeStmt visit(ScopeStmt s)
	{
		visit(s.statement);
		return s;
	}
	
	public override FuncEnvStmt visit(FuncEnvStmt s)
	{
		Stdout("funcenv ");
		visit(s.funcName);
		Stdout(", ");
		visit(s.envName);
		return s;
	}
	
	public override ReturnStmt visit(ReturnStmt s)
	{
		if(s.exprs.length == 0)
			Stdout("return");
		else
		{
			Stdout("return ");
			visit(s.exprs[0]);
			
			foreach(exp; s.exprs[1 .. $])
			{
				Stdout(", ");
				visit(exp);
			}
		}
		
		return s;
	}
}