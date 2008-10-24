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