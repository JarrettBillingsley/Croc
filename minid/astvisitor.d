/******************************************************************************
This module defines a visitor for an AST as defined by nodes in minid.ast.
You can make an AST visitor by just deriving from the Visitor or
IdentityVisitor class.

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

template returnType(string tag)
{
	static if(is(typeof(mixin(tag)) : Statement))
		alias Statement returnType;
	else static if(is(typeof(mixin(tag)) : Expression))
		alias Expression returnType;
	else
		alias AstNode returnType;
}

string generateVisitMethods()
{
	string ret;

	foreach(tag; AstTagNames)
		ret ~= "public returnType!(\"" ~ tag ~ "\") visit(" ~ tag ~ " node){ throw new Exception(\"no visit method implemented for AST node '" ~ tag ~ "'\"); }\n";

	return ret;
}

string generateDispatchFunctions()
{
	string ret;

	foreach(tag; AstTagNames)
		ret ~= "public static returnType!(\"" ~ tag ~ "\") visit" ~ tag ~ "(Visitor visitor, " ~ tag ~ " c) { return visitor.visit(c); }\n";

	return ret;
}

string generateDispatchTable()
{
	string ret = "private static const void*[] dispatchTable = [";

	foreach(tag; AstTagNames)
		ret ~= "cast(void*)&visit" ~ tag ~ ",\n";

	return ret[0 .. $ - 2] ~ "];"; // slice away last ",\n"
}

/**
This is an AST visitor.  It implements a form of dynamic dispatch based on the type of the node that is
being visited.  In order to make an AST visitor, you derive from this class and override the visit method
for each type of node, such as "AddExp visit(AddExp e)".  Each visit method should return an AST node.  If
you are not performing a transformation on the AST, you can just return the node that was passed in.  If
you are transforming the AST, you just return a new/different AST node than the one that was passed in.

When visiting an AST node, you should assign the result of visit back into the place where you got the node:

-----
e.op1 = visit(e.op1);
-----

By default, the visit methods are defined to throw an exception saying that it is unimplemented for that
type.


*/
abstract class Visitor
{
	mixin(generateVisitMethods());
	mixin(generateDispatchFunctions());
	mixin(generateDispatchTable());
	static assert(dispatchTable.length == AstTagNames.length, "vtable length doesn't match number of AST tags");

	protected ICompiler c;

	/**
	Construct a new instance of Visitor.  Each visitor is associated with a compiler.  The compiler is used
	to allocate AST nodes and to throw errors.
	*/
	public this(ICompiler c)
	{
		this.c = c;
	}

	/**
	Visit a statement node.
	*/
	public final Statement visit(Statement n)
	{
		return visitS(n);
	}

	/**
	Visit an expression node.
	*/
	public final Expression visit(Expression n)
	{
		return visitE(n);
	}

	/**
	Visit some other kind of node.
	*/
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

	protected final AstNode function(Visitor, AstNode) getDispatchFunction(AstNode n)
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

/**
This class is derived from Visitor and overrides all the visit methods with identity methods - that is,
all they do is return the node that was passed in.  This means that this visitor just returns the AST
that was passed in, unaffected.  You can derive from this when many/most of your visit methods don't
do anything.
*/
abstract class IdentityVisitor : Visitor
{
	mixin(generateIdentityVisitMethods());
	
	public this(ICompiler c)
	{
		super(c);
	}
}