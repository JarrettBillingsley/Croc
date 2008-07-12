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

module minid.ast;

import minid.compilertypes;

const char[][] AstTagNames =
[
	"Unknown",
	
	"ObjectDef",
	"FuncDef",
	"NamespaceDef",

	"Module",

	"ModuleDecl",
	"FuncDecl",
	"ObjectDecl",
	"NamespaceDecl",
	"VarDecl",

	"AssertStmt",
	"ImportStmt",
	"BlockStmt",
	"ScopeStmt",
	"ExpressionStmt",
	"IfStmt",
	"WhileStmt",
	"DoWhileStmt",
	"ForStmt",
	"ForNumStmt",
	"ForeachStmt",
	"SwitchStmt",
	"CaseStmt",
	"DefaultStmt",
	"ContinueStmt",
	"BreakStmt",
	"ReturnStmt",
	"TryStmt",
	"ThrowStmt",

	"Assign",
	"AddAssign",
	"SubAssign",
	"CatAssign",
	"MulAssign",
	"DivAssign",
	"ModAssign",
	"OrAssign",
	"XorAssign",
	"AndAssign",
	"ShlAssign",
	"ShrAssign",
	"UShrAssign",
	"CondAssign",
	"IncExp",
	"DecExp",

	"CondExp",
	"OrOrExp",
	"AndAndExp",
	"OrExp",
	"XorExp",
	"AndExp",
	"EqualExp",
	"NotEqualExp",
	"IsExp",
	"NotIsExp",
	"LTExp",
	"LEExp",
	"GTExp",
	"GEExp",
	"Cmp3Exp",
	"AsExp",
	"InExp",
	"NotInExp",
	"ShlExp",
	"ShrExp",
	"UShrExp",
	"AddExp",
	"SubExp",
	"CatExp",
	"MulExp",
	"DivExp",
	"ModExp",
	"NegExp",
	"NotExp",
	"ComExp",
	"LenExp",
	"VargLenExp",
	"CoroutineExp",
	"DotExp",
	"DotSuperExp",
	"IndexExp",
	"VargIndexExp",
	"SliceExp",
	"VargSliceExp",
	"CallExp",
	"MethodCallExp",
	"IdentExp",
	"ThisExp",
	"NullExp",
	"BoolExp",
	"VarargExp",
	"IntExp",
	"FloatExp",
	"CharExp",
	"StringExp",
	"FuncLiteralExp",
	"ObjectLiteralExp",
	"ParenExp",
	"TableCtorExp",
	"ArrayCtorExp",
	"NamespaceCtorExp",
	"YieldExp",
	"SuperCallExp",
	"ForeachComprehension",
	"ForNumComprehension",
	"IfComprehension",
	"ArrayComprehension",
	"TableComprehension"
];

private char[] genEnumMembers()
{
	char[] ret;

	foreach(tag; AstTagNames)
		ret ~= tag ~ ",";

	return ret;
}

mixin("enum AstTag {" ~ genEnumMembers() ~ "}");

const char[][] NiceAstTagNames =
[
	AstTag.Unknown:              "<unknown node type>",

	AstTag.ObjectDef:            "object definition",
	AstTag.FuncDef:              "function definition",
	AstTag.NamespaceDef:         "namespace definition",

	AstTag.Module:               "module",

	AstTag.ModuleDecl:           "module declaration",
	AstTag.FuncDecl:             "function declaration",
	AstTag.ObjectDecl:           "object declaration",
	AstTag.NamespaceDecl:        "namespace declaration",
	AstTag.VarDecl:              "variable declaration",

	AstTag.AssertStmt:           "assert statement",
	AstTag.ImportStmt:           "import statement",
	AstTag.BlockStmt:            "block statement",
	AstTag.ScopeStmt:            "scope statement",
	AstTag.ExpressionStmt:       "expression statement",
	AstTag.IfStmt:               "'if' statement",
	AstTag.WhileStmt:            "'while' statement",
	AstTag.DoWhileStmt:          "'do-while' statement",
	AstTag.ForStmt:              "'for' statement",
	AstTag.ForNumStmt:           "numeric 'for' statement",
	AstTag.ForeachStmt:          "'foreach' statement",
	AstTag.SwitchStmt:           "'switch' statement",
	AstTag.CaseStmt:             "'case' statement",
	AstTag.DefaultStmt:          "'default' statement",
	AstTag.ContinueStmt:         "'continue' statement",
	AstTag.BreakStmt:            "'break' statement",
	AstTag.ReturnStmt:           "'return' statement",
	AstTag.TryStmt:              "'try-catch-finally' statement",
	AstTag.ThrowStmt:            "'throw' statement",

	AstTag.Assign:               "assignment",
	AstTag.AddAssign:            "addition assignment",
	AstTag.SubAssign:            "subtraction assignment",
	AstTag.CatAssign:            "concatenation assignment",
	AstTag.MulAssign:            "multiplication assignment",
	AstTag.DivAssign:            "division assignment",
	AstTag.ModAssign:            "modulo assignment",
	AstTag.OrAssign:             "bitwise 'or' assignment",
	AstTag.XorAssign:            "bitwise 'xor' assignment",
	AstTag.AndAssign:            "bitwise 'and' assignment",
	AstTag.ShlAssign:            "left-shift assignment",
	AstTag.ShrAssign:            "right-shift assignment",
	AstTag.UShrAssign:           "unsigned right-shift assignment",
	AstTag.CondAssign:           "conditional assignment",
	AstTag.IncExp:               "increment",
	AstTag.DecExp:               "decrement",

	AstTag.CondExp:              "conditional expression",
	AstTag.OrOrExp:              "logical 'or' expression",
	AstTag.AndAndExp:            "logical 'and' expression",
	AstTag.OrExp:                "bitwise 'or' expression",
	AstTag.XorExp:               "bitwise 'xor' expression",
	AstTag.AndExp:               "bitwise 'and' expression",
	AstTag.EqualExp:             "equality expression",
	AstTag.NotEqualExp:          "inequality expression",
	AstTag.IsExp:                "identity expression",
	AstTag.NotIsExp:             "non-identity expression",
	AstTag.LTExp:                "less-than expression",
	AstTag.LEExp:                "less-or-equals expression",
	AstTag.GTExp:                "greater-than expression",
	AstTag.GEExp:                "greater-or-equals expression",
	AstTag.Cmp3Exp:              "three-way comparison expression",
	AstTag.AsExp:                "'as' expression",
	AstTag.InExp:                "'in' expression",
	AstTag.NotInExp:             "'!in' expression",
	AstTag.ShlExp:               "left-shift expression",
	AstTag.ShrExp:               "right-shift expression",
	AstTag.UShrExp:              "unsigned right-shift expression",
	AstTag.AddExp:               "addition expression",
	AstTag.SubExp:               "subtraction expression",
	AstTag.CatExp:               "concatenation expression",
	AstTag.MulExp:               "multiplication expression",
	AstTag.DivExp:               "division expression",
	AstTag.ModExp:               "modulo expression",
	AstTag.NegExp:               "negation expression",
	AstTag.NotExp:               "logical 'not' expression",
	AstTag.ComExp:               "bitwise complement expression",
	AstTag.LenExp:               "length expression",
	AstTag.VargLenExp:           "vararg length expression",
	AstTag.CoroutineExp:         "coroutine expression",
	AstTag.DotExp:               "dot expression",
	AstTag.DotSuperExp:          "dot-super expression",
	AstTag.IndexExp:             "index expression",
	AstTag.VargIndexExp:         "vararg index expression",
	AstTag.SliceExp:             "slice expression",
	AstTag.VargSliceExp:         "vararg slice expression",
	AstTag.CallExp:              "call expression",
	AstTag.MethodCallExp:        "method call expression",
	AstTag.IdentExp:             "identifier expression",
	AstTag.ThisExp:              "'this' expression",
	AstTag.NullExp:              "'null' expression",
	AstTag.BoolExp:              "boolean constant expression",
	AstTag.VarargExp:            "'vararg' expression",
	AstTag.IntExp:               "integer constant expression",
	AstTag.FloatExp:             "float constant expression",
	AstTag.CharExp:              "character constant expression",
	AstTag.StringExp:            "string constant expression",
	AstTag.FuncLiteralExp:       "function literal expression",
	AstTag.ObjectLiteralExp:     "object literal expression",
	AstTag.ParenExp:             "parenthesized expression",
	AstTag.TableCtorExp:         "table constructor expression",
	AstTag.ArrayCtorExp:         "array constructor expression",
	AstTag.NamespaceCtorExp:     "namespace constructor expression",
	AstTag.YieldExp:             "yield expression",
	AstTag.SuperCallExp:         "super call expression",
	AstTag.ForeachComprehension: "'foreach' comprehension",
	AstTag.ForNumComprehension:  "numeric 'for' comprehension",
	AstTag.IfComprehension:      "'if' comprehension",
	AstTag.ArrayComprehension:   "array comprehension",
	AstTag.TableComprehension:   "table comprehension"
];

/**
The base class for all the Abstract Syntax Tree nodes in the language.
*/
abstract class AstNode : IAstNode
{
	mixin IAstNodeMixin;

	/**
	The location of the beginning of this node.
	*/
	public CompileLoc location;

	/**
	The location of the end of this node.
	*/
	public CompileLoc endLocation;

	/**
	The tag indicating what kind of node this actually is.  You can switch on this
	to walk an AST.
	*/
	public AstTag type;

	/**
	The base constructor, but since this class is abstract, this can only be
	called from derived classes.

	Params:
		location = The location of the beginning of this node.
		endLocation = The location of the end of this node.
		type = The type of this node.
	*/
	public this(CompileLoc location, CompileLoc endLocation, AstTag type)
	{
		this.location = location;
		this.endLocation = endLocation;
		this.type = type;
	}

	/**
	By default, toString() will return the string representation of the node type.
	*/
	public char[] toString()
	{
		return AstTagNames[type];
	}

	/**
	Returns a nicer (readable) representation of this kind of node.
	*/
	public char[] niceString()
	{
		return NiceAstTagNames[type];
	}

	/**
	Similar to a dynamic cast, except it uses the 'type' field to determine if the
	cast is legal, making it faster.  Returns this casted to the given class type
	if the cast succeeds and null otherwise.
	*/
	public T as(T)()
	{
		if(type == mixin("AstTag." ~ T.stringof))
			return cast(T)cast(void*)this;

		return null;
	}
}