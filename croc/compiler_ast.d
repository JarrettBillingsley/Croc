/******************************************************************************
This module contains the definition of all the classes which correspond to
Croc's grammar productions. These are used to represent the AST during
compilation.

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

module croc.compiler_ast;

import croc.base_alloc;
import croc.base_opcodes;
import croc.compiler_types;
import croc.types;

const char[][] AstTagNames =
[
	"Unknown",
	"Identifier",

	"ClassDef",
	"FuncDef",
	"NamespaceDef",

	"Module",
	"Decorator",

	"VarDecl",
	"FuncDecl",
	"ClassDecl",
	"NamespaceDecl",

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
	"TryCatchStmt",
	"TryFinallyStmt",
	"ThrowStmt",
	"ScopeActionStmt",

	"AssignStmt",
	"AddAssignStmt",
	"SubAssignStmt",
	"CatAssignStmt",
	"MulAssignStmt",
	"DivAssignStmt",
	"ModAssignStmt",
	"OrAssignStmt",
	"XorAssignStmt",
	"AndAssignStmt",
	"ShlAssignStmt",
	"ShrAssignStmt",
	"UShrAssignStmt",
	"CondAssignStmt",
	"IncStmt",
	"DecStmt",
	"TypecheckStmt",

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
	"ClassLiteralExp",
	"ParenExp",
	"TableCtorExp",
	"ArrayCtorExp",
	"NamespaceCtorExp",
	"YieldExp",

	"ForeachComprehension",
	"ForNumComprehension",
	"IfComprehension",
	"ArrayComprehension",
	"TableComprehension"
];

char[] genEnumMembers()
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
	AstTag.Identifier:           "identifier",

	AstTag.ClassDef:             "class definition",
	AstTag.FuncDef:              "function definition",
	AstTag.NamespaceDef:         "namespace definition",

	AstTag.Module:               "module",
	AstTag.Decorator:            "decorator",

	AstTag.VarDecl:              "variable declaration",
	AstTag.FuncDecl:             "function declaration",
	AstTag.ClassDecl:            "class declaration",
	AstTag.NamespaceDecl:        "namespace declaration",

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
	AstTag.TryCatchStmt:         "'try-catch' statement",
	AstTag.TryFinallyStmt:       "'try-finally' statement",
	AstTag.ThrowStmt:            "'throw' statement",
	AstTag.ScopeActionStmt:      "'scope(...)' statement",

	AstTag.AssignStmt:           "assignment",
	AstTag.AddAssignStmt:        "addition assignment",
	AstTag.SubAssignStmt:        "subtraction assignment",
	AstTag.CatAssignStmt:        "concatenation assignment",
	AstTag.MulAssignStmt:        "multiplication assignment",
	AstTag.DivAssignStmt:        "division assignment",
	AstTag.ModAssignStmt:        "modulo assignment",
	AstTag.OrAssignStmt:         "bitwise 'or' assignment",
	AstTag.XorAssignStmt:        "bitwise 'xor' assignment",
	AstTag.AndAssignStmt:        "bitwise 'and' assignment",
	AstTag.ShlAssignStmt:        "left-shift assignment",
	AstTag.ShrAssignStmt:        "right-shift assignment",
	AstTag.UShrAssignStmt:       "unsigned right-shift assignment",
	AstTag.CondAssignStmt:       "conditional assignment",
	AstTag.IncStmt:              "increment",
	AstTag.DecStmt:              "decrement",
	AstTag.TypecheckStmt:        "typecheck statement",

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
	AstTag.ClassLiteralExp:      "class literal expression",
	AstTag.ParenExp:             "parenthesized expression",
	AstTag.TableCtorExp:         "table constructor expression",
	AstTag.ArrayCtorExp:         "array constructor expression",
	AstTag.NamespaceCtorExp:     "namespace constructor expression",
	AstTag.YieldExp:             "yield expression",

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
	CompileLoc location;

	/**
	The location of the end of this node.
	*/
	CompileLoc endLocation;

	/**
	The tag indicating what kind of node this actually is.
	*/
	AstTag type;

	new(uword size, ICompiler c)
	{
		return c.alloc().allocArray!(void)(size).ptr;
	}

	/**
	The base constructor, but since this class is abstract, this can only be
	called from derived classes.

	Params:
		c = The compiler with which the node will be associated.
		location = The location of the beginning of this node.
		endLocation = The location of the end of this node.
		type = The type of this node.
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type)
	{
		c.addNode(this);
		this.location = location;
		this.endLocation = endLocation;
		this.type = type;
	}

	/**
	By default, toString() will return the string representation of the node type.
	*/
	char[] toString()
	{
		return AstTagNames[type];
	}

	/**
	Returns a nicer (readable) representation of this kind of node.
	*/
	char[] niceString()
	{
		return NiceAstTagNames[type];
	}

	/**
	Similar to a dynamic cast, except it uses the 'type' field to determine if the
	cast is legal, making it faster. Returns this casted to the given class type
	if the cast succeeds and null otherwise.
	*/
	T as(T)()
	{
		if(type == mixin("AstTag." ~ T.stringof))
			return cast(T)cast(void*)this;

		return null;
	}

	override void cleanup(ref Allocator alloc)
	{
		// nothing.
	}
}

/**
Dummy unknown node type.
*/
class Unknown : AstNode
{
	this(ICompiler c)
	{
		super(c, CompileLoc.init, CompileLoc.init, AstTag.Unknown);
		//assert(false);
	}
}

/**
This node represents an identifier. This isn't the same as an IdentExp, as identifiers can
be used in non-expression contexts (such as names in declarations).
*/
class Identifier : AstNode
{
	char[] name;

	this(ICompiler c, CompileLoc location, char[] name)
	{
		super(c, location, location, AstTag.Identifier);
		this.name = name;
	}
}

/**
This node represents the guts of an class literal. This node does not directly correspond
to a single grammar element; rather it represents the common attributes of both class
literals and class declarations.
*/
class ClassDef : AstNode
{
	/**
	Represents a single field in the class. Remember that methods are fields too.
	*/
	struct Field
	{
		/**
		The name of the field. This corresponds to either the name of a data member or
		the name of a method.
		*/
		char[] name;

		/**
		The initializer of the field. This will never be null. If a field is declared in
		a class but not given a value, a NullExp will be inserted into this field.
		*/
		Expression initializer;

		bool isPublic;
		bool isMethod;

		/**
		Document comments for the field.
		*/
		char[] docs;

		/**
		The location of the doc comments for the field.
		*/
		CompileLoc docsLoc;
	}

	/**
	The name of the class. This field will never be null.
	*/
	Identifier name;

	/**
	The base class from which this class derives. Optional.
	*/
	Expression baseClass;

	/**
	The fields in this class, in the order they were declared. See the Field struct above.
	*/
	Field[] fields;

	/**
	Document comments for the declaration.
	*/
	char[] docs;

	/**
	The location of the doc comments for the declaration.
	*/
	CompileLoc docsLoc;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Identifier name, Expression baseClass, Field[] fields)
	{
		super(c, location, endLocation, AstTag.ClassDef);
		this.name = name;
		this.baseClass = baseClass;
		this.fields = fields;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(fields);
	}
}

/**
Similar to ClassDef, this class represents the common attributes of both function literals
and function declarations.
*/
class FuncDef : AstNode
{
	enum TypeMask : uint
	{
		Null =      (1 << cast(uint)CrocValue.Type.Null),
		Bool =      (1 << cast(uint)CrocValue.Type.Bool),
		Int =       (1 << cast(uint)CrocValue.Type.Int),
		Float =     (1 << cast(uint)CrocValue.Type.Float),
		Char =      (1 << cast(uint)CrocValue.Type.Char),

		String =    (1 << cast(uint)CrocValue.Type.String),
		Table =     (1 << cast(uint)CrocValue.Type.Table),
		Array =     (1 << cast(uint)CrocValue.Type.Array),
		Memblock =  (1 << cast(uint)CrocValue.Type.Memblock),
		Function =  (1 << cast(uint)CrocValue.Type.Function),
		Class =     (1 << cast(uint)CrocValue.Type.Class),
		Instance =  (1 << cast(uint)CrocValue.Type.Instance),
		Namespace = (1 << cast(uint)CrocValue.Type.Namespace),
		Thread =    (1 << cast(uint)CrocValue.Type.Thread),
		NativeObj = (1 << cast(uint)CrocValue.Type.NativeObj),
		WeakRef =   (1 << cast(uint)CrocValue.Type.WeakRef),
		FuncDef =   (1 << cast(uint)CrocValue.Type.FuncDef),

		NotNull = Bool | Int | Float | Char | String | Table | Array | Memblock | Function | Class | Instance | Namespace | Thread | NativeObj | WeakRef | FuncDef,
		Any = Null | NotNull
	}

	/**
	Represents a parameter to the function.
	*/
	struct Param
	{
		/**
		The name of the parameter.
		*/
		Identifier name;

		/**
		The type mask of the parameter, that is, what basic types can be passed to it.
		Defaults to TypeMask.Any, which allows any type to be passed. This should not be
		set to 0; the codegen does not check for this so it's up to you.
		*/
		uint typeMask = TypeMask.Any;

		/**
		If typeMask allows instances, this can be a list of expressions which should evaluate
		at runtime to class types that this parameter can accept. This is an optional
		list. If typeMask does not allow instances, this should be empty.
		*/
		Expression[] classTypes;

		/**
		If this parameter has a custom constraint instead of a normal type constraint, the
		name after the @ will be turned into an expression and placed here. After the semantic
		pass, this instead holds a call to the custom constraint with the parameter as its
		argument.
		*/
		Expression customConstraint;

		/**
		The default value for the parameter. This can be null, in which case it will have
		no default value.
		*/
		Expression defValue;

		/**
		The slice of the source code that corresponds to this parameter's typemask. Can be null
		if no typemask is given (implies "any"). Used for documentation generation.
		*/
		char[] typeString;

		/**
		The slice of the source code that corresponds to this parameter's default value. Can be
		null if no default value is given. Used for documentation generation.
		*/
		char[] valueString;
	}

	/**
	The name of the function. This will never be null. In the case of function literals
	without names, this will be filled with an auto-generated name based off the location of
	where the literal occurred.
	*/
	Identifier name;

	/**
	The list of parameters to the function. See the Param struct above. This will always be
	at least one element long, and element 0 will always be the 'this' parameter.
	*/
	Param[] params;

	/**
	Indicates whether or not this function is variadic.
	*/
	bool isVararg;

	/**
	The body of the function. In the case of lambda functions (i.e. "function(x) = x * x"), this
	is a ReturnStmt with one expression, the expression that is the lambda's body. Otherwise, it
	must (($B must)) be a BlockStmt. This will be checked upon construction.
	*/
	Statement code;

	/**
	Document comments for the declaration.
	*/
	char[] docs;

	/**
	The location of the doc comments for the declaration.
	*/
	CompileLoc docsLoc;

	/**
	*/
	this(ICompiler c, CompileLoc location, Identifier name, Param[] params, bool isVararg, Statement code)
	{
		if(!code.as!(ReturnStmt) && !code.as!(BlockStmt))
			c.semException(location, "FuncDef code must be a ReturnStmt or BlockStmt, not a '{}'", code.niceString());

		super(c, location, code.endLocation, AstTag.FuncDef);

		assert(params.length > 0 && params[0].name.name == "this");

		this.params = params;
		this.isVararg = isVararg;
		this.code = code;
		this.name = name;
	}

	override void cleanup(ref Allocator alloc)
	{
		foreach(ref p; params)
			alloc.freeArray(p.classTypes);

		alloc.freeArray(params);
	}
}

/**
Like the ClassDef and FuncDef classes, this represents the common attributes of both
namespace literals and declarations.
*/
class NamespaceDef : AstNode
{
	/**
	Represents a single field in the namespace. Remember that functions are fields too.
	*/
	struct Field
	{
		/**
		The name of the field. This corresponds to either the name of a data member or
		the name of a function.
		*/
		char[] name;

		/**
		The initializer of the field. This will never be null. If a field is declared in
		a namespace but not given a value, a NullExp will be inserted into this field.
		*/
		Expression initializer;

		/**
		Document comments for the field.
		*/
		char[] docs;

		/**
		The location of the doc comments for the field.
		*/
		CompileLoc docsLoc;
	}

	/**
	The name of the namespace. This field will never be null.
	*/
	Identifier name;

	/**
	The namespace which will become the parent of this namespace. This field can be null,
	in which case the namespace's parent will be set to the environment of the current function.
	*/
	Expression parent;

	/**
	The fields in this namespace, in an arbitrary order. See the Field struct above.
	*/
	Field[] fields;

	/**
	Document comments for the declaration.
	*/
	char[] docs;

	/**
	The location of the doc comments for the declaration.
	*/
	CompileLoc docsLoc;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Identifier name, Expression parent, Field[] fields)
	{
		super(c, location, endLocation, AstTag.NamespaceDef);
		this.name = name;
		this.parent = parent;
		this.fields = fields;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(fields);
	}
}

/**
Represents a Croc module. This node forms the root of an AST when a module is compiled.
*/
class Module : AstNode
{
	/**
	The name of this module. This is an array of strings, each element of which is one
	piece of a dotted name. This array will always be at least one element long.
	*/
	char[][] names;

	/**
	The statements which make up the body of the module. Normally this will be a block
	statement but it can be other kinds due to semantic analysis.
	*/
	Statement statements;

	/**
	*/
	Decorator decorator;

	/**
	Document comments for the module.
	*/
	char[] docs;

	/**
	The location of the doc comments for the module.
	*/
	CompileLoc docsLoc;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, char[][] names, Statement statements, Decorator decorator)
	{
		super(c, location, endLocation, AstTag.Module);
		this.names = names;
		this.statements = statements;
		this.decorator = decorator;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(names);
	}
}

/**
The base class for all statements.
*/
abstract class Statement : AstNode
{
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type)
	{
		super(c, location, endLocation, type);
	}
}

/**
Defines the types of protection possible for class, function, namespace, and variable
declarations.
*/
enum Protection
{
	/**
	This indicates "default" protection, which means global at module-level scope and local
	everywhere else.
	*/
	Default,

	/**
	This forces local protection.
	*/
	Local,

	/**
	This forces global protection.
	*/
	Global
}

/**
Represents local and global variable declarations.
*/
class VarDecl : Statement
{
	/**
	What protection level this declaration uses.
	*/
	Protection protection;

	/**
	The list of names to be declared. This will always have at least one name.
	*/
	Identifier[] names;

	/**
	The initializer for the variables. This can be empty, in which case the variables
	will be all be initialized to null.
	*/
	Expression[] initializer;

	/**
	Document comments for the declaration.
	*/
	char[] docs;

	/**
	The location of the doc comments for the declaration.
	*/
	CompileLoc docsLoc;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Protection protection, Identifier[] names, Expression[] initializer)
	{
		super(c, location, endLocation, AstTag.VarDecl);
		this.protection = protection;
		this.names = names;
		this.initializer = initializer;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(names);
		alloc.freeArray(initializer);
	}
}

/**
*/
class Decorator : AstNode
{
	/**
	*/
	Expression func;

	/**
	*/
	Expression context;

	/**
	*/
	Expression[] args;

	/**
	*/
	Decorator nextDec;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression func, Expression context, Expression[] args, Decorator nextDec)
	{
		super(c, location, endLocation, AstTag.Decorator);
		this.func = func;
		this.context = context;
		this.args = args;
		this.nextDec = nextDec;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(args);
	}
}

/**
This node represents a function declaration. Note that there are some places in the
grammar which look like function declarations (like inside classes and namespaces) but
which actually are just syntactic sugar. This is for actual declarations.
*/
class FuncDecl : Statement
{
	/**
	What protection level this declaration uses.
	*/
	Protection protection;

	/**
	The "guts" of the function declaration.
	*/
	FuncDef def;

	/**
	*/
	Decorator decorator;

	/**
	The protection parameter can be any kind of protection.
	*/
	this(ICompiler c, CompileLoc location, Protection protection, FuncDef def, Decorator decorator)
	{
		super(c, location, def.endLocation, AstTag.FuncDecl);
		this.protection = protection;
		this.def = def;
		this.decorator = decorator;
	}
}

/**
This node represents a class declaration.
*/
class ClassDecl : Statement
{
	/**
	What protection level this declaration uses.
	*/
	Protection protection;

	/**
	The actual "guts" of the class.
	*/
	ClassDef def;

	/**
	*/
	Decorator decorator;

	/**
	The protection parameter can be any kind of protection.
	*/
	this(ICompiler c, CompileLoc location, Protection protection, ClassDef def, Decorator decorator)
	{
		super(c, location, def.endLocation, AstTag.ClassDecl);
		this.protection = protection;
		this.def = def;
		this.decorator = decorator;
	}
}

/**
This node represents a namespace declaration.
*/
class NamespaceDecl : Statement
{
	/**
	What protection level this declaration uses.
	*/
	Protection protection;

	/**
	The "guts" of the namespace.
	*/
	NamespaceDef def;

	/**
	*/
	Decorator decorator;

	/**
	The protection parameter can be any level of protection.
	*/
	this(ICompiler c, CompileLoc location, Protection protection, NamespaceDef def, Decorator decorator)
	{
		super(c, location, def.endLocation, AstTag.NamespaceDecl);
		this.protection = protection;
		this.def = def;
		this.decorator = decorator;
	}
}

/**
This node represents an assertion statement.
*/
class AssertStmt : Statement
{
	/**
	A required expression that is the condition checked by the assertion.
	*/
	Expression cond;

	/**
	An optional message that will be used if the assertion fails. This member
	can be null, in which case a message will be generated for the assertion
	based on its location. If it's not null, it must evaluate to a string.
	*/
	Expression msg;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression cond, Expression msg = null)
	{
		super(c, location, endLocation, AstTag.AssertStmt);
		this.cond = cond;
		this.msg = msg;
	}
}

/**
This node represents an import statement.
*/
class ImportStmt : Statement
{
	/**
	An optional renaming of the import. This member can be null, in which case no renaming
	is done. In the code "import y as x;", this member corresponds to "x".
	*/
	Identifier importName;

	/**
	The expression which evaluates to a string containing the name of the module to import.
	The statement "import a.b.c" is actually syntactic sugar for "import("a.b.c")", so expr
	will be a StringExp in this case. This expression is checked (if it's constant) to ensure
	that it's a string when constant folding occurs.
	*/
	Expression expr;

	/**
	An optional list of symbols to import from the module. In the code "import x : a, b, c",
	this corresponds to "a, b, c".
	*/
	Identifier[] symbols;

	/**
	A parallel array to the symbols array. This holds the names of the symbols as they should
	be called in this module. The code "import x : a, b" is sugar for "import x : a as a, b as b".
	In the code "import x : a as y, b as z", this array corresponds to "y, z".
	*/
	Identifier[] symbolNames;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Identifier importName, Expression expr, Identifier[] symbols, Identifier[] symbolNames)
	{
		super(c, location, endLocation, AstTag.ImportStmt);
		this.importName = importName;
		this.expr = expr;
		this.symbols = symbols;
		this.symbolNames = symbolNames;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(symbols);
		alloc.freeArray(symbolNames);
	}
}

/**
This node represents a block statement (i.e. one surrounded by curly braces).
*/
class BlockStmt : Statement
{
	/**
	The list of statements contained in the braces.
	*/
	Statement[] statements;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Statement[] statements)
	{
		super(c, location, endLocation, AstTag.BlockStmt);
		this.statements = statements;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(statements);
	}
}

/**
A node which doesn't correspond to a grammar element. This indicates a new nested scope.
An example of where this would be used is in an anonymous scope with some code in it. All it
does is affects the codegen of the contained statement by beginning a new scope before it
and ending the scope after it.

If you're looking for the "scope(exit)" kind of statements, look at the ScopeActionStmt node.
*/
class ScopeStmt : Statement
{
	/**
	The statement contained within this scope. Typically a block statement, but can
	be anything.
	*/
	Statement statement;

	/**
	*/
	this(ICompiler c, Statement statement)
	{
		super(c, statement.location, statement.endLocation, AstTag.ScopeStmt);
		this.statement = statement;
	}
}

/**
A statement that holds a side-effecting expression to be evaluated as a statement,
such as a function call, assignment etc.
*/
class ExpressionStmt : Statement
{
	/**
	The expression to be evaluated for this statement. This must be a side-effecting
	expression, including function calls, yields, and assignments. Conditional (?:)
	expressions and logical or and logical and (|| and &&) expressions are also allowed,
	providing at least one component is side-effecting.

	This class does $(B not) check that this expression is side-effecting; that is up to
	you.
	*/
	Expression expr;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression expr)
	{
		super(c, location, endLocation, AstTag.ExpressionStmt);
		this.expr = expr;
	}

	/**
	*/
	this(ICompiler c, Expression expr)
	{
		super(c, expr.location, expr.endLocation, AstTag.ExpressionStmt);
		this.expr = expr;
	}
}

/**
This node represents an if statement.
*/
class IfStmt : Statement
{
	/**
	An optional variable to declare inside the statement's condition which will take on
	the value of the condition. In the code "if(local x = y < z){}", this corresponds
	to "x". This member may be null, in which case there is no variable there.
	*/
	IdentExp condVar;

	/**
	The condition to test.
	*/
	Expression condition;

	/**
	The code to execute if the condition evaluates to true.
	*/
	Statement ifBody;

	/**
	If there is an else clause, this is the code to execute if the condition evaluates to
	false. If there is no else clause, this member is null.
	*/
	Statement elseBody;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, IdentExp condVar, Expression condition, Statement ifBody, Statement elseBody)
	{
		super(c, location, endLocation, AstTag.IfStmt);

		this.condVar = condVar;
		this.condition = condition;
		this.ifBody = ifBody;
		this.elseBody = elseBody;
	}
}

/**
This node represents a while loop.
*/
class WhileStmt : Statement
{
	/**
	An optional loop label used for named breaks/continues. This member may be null, in which
	case it's an unnamed loop.
	*/
	char[] name;

	/**
	An optional variable to declare inside the statement's condition which will take on
	the value of the condition. In the code "while(local x = y < z){}", this corresponds
	to "x". This member may be null, in which case there is no variable there.
	*/
	IdentExp condVar;

	/**
	The condition to test.
	*/
	Expression condition;

	/**
	The code inside the loop.
	*/
	Statement code;

	/**
	*/
	this(ICompiler c, CompileLoc location, char[] name, IdentExp condVar, Expression condition, Statement code)
	{
		super(c, location, code.endLocation, AstTag.WhileStmt);

		this.name = name;
		this.condVar = condVar;
		this.condition = condition;
		this.code = code;
	}
}

/**
This node corresponds to a do-while loop.
*/
class DoWhileStmt : Statement
{
	/**
	An optional loop label used for named breaks/continues. This member may be null, in which
	case it's an unnamed loop.
	*/
	char[] name;

	/**
	The code inside the loop.
	*/
	Statement code;

	/**
	The condition to test at the end of the loop.
	*/
	Expression condition;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, char[] name, Statement code, Expression condition)
	{
		super(c, location, endLocation, AstTag.DoWhileStmt);

		this.name = name;
		this.code = code;
		this.condition = condition;
	}
}

/**
This node represents a C-style for loop.
*/
class ForStmt : Statement
{
	/**
	An optional loop label used for named breaks/continues. This member may be null, in which
	case it's an unnamed loop.
	*/
	char[] name;

	/**
	There are two types of initializers possible in the first clause of the for loop header:
	variable declarations and expression statements. This struct holds one or the other.
	*/
	struct Init
	{
		/**
		If true, the 'decl' member should be used; else, the 'init' member should be used.
		*/
		bool isDecl = false;

		union
		{
			/**
			If isDecl is false, this holds an expression statement to be evaluated at the beginning
			of the loop.
			*/
			Statement stmt;

			/**
			If isDecl is true, this holds a variable declaration to be performed at the
			beginning of the loop.
			*/
			VarDecl decl;
		}
	}

	/**
	A list of 0 or more initializers (the first clause of the foreach header).
	*/
	Init[] init;

	/**
	The condition to test at the beginning of each iteration of the loop. This can be
	null, in which case the only way to get out of the loop is to break, return, or
	throw an exception.
	*/
	Expression condition;

	/**
	A list of 0 or more increment expression statements to be evaluated at the end of
	each iteration of the loop.
	*/
	Statement[] increment;

	/**
	The code inside the loop.
	*/
	Statement code;

	/**
	*/
	this(ICompiler c, CompileLoc location, char[] name, Init[] init, Expression cond, Statement[] inc, Statement code)
	{
		super(c, location, endLocation, AstTag.ForStmt);

		this.name = name;
		this.init = init;
		this.condition = cond;
		this.increment = inc;
		this.code = code;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(init);
		alloc.freeArray(increment);
	}
}

/**
This node represents a numeric for loop, i.e. "for(i: 0 .. 10){}".
*/
class ForNumStmt : Statement
{
	/**
	An optional loop label used for named breaks/continues. This member may be null, in which
	case it's an unnamed loop.
	*/
	char[] name;

	/**
	The name of the index variable.
	*/
	Identifier index;

	/**
	The lower bound of the loop (the value before the ".."). If constant, it must be an
	int.
	*/
	Expression lo;

	/**
	The upper bound of the loop (the value after the ".."). If constant, it must be an
	int.
	*/
	Expression hi;

	/**
	The step value of the loop. If specified, this is the value after the comma after the
	upper bound. If not specified, this is given an IntExp of value 1. This member is
	never null. If constant, it must be an int.
	*/
	Expression step;

	/**
	The code inside the loop.
	*/
	Statement code;

	/**
	*/
	this(ICompiler c, CompileLoc location, char[] name, Identifier index, Expression lo, Expression hi, Expression step, Statement code)
	{
		super(c, location, code.endLocation, AstTag.ForNumStmt);

		this.name = name;
		this.index = index;
		this.lo = lo;
		this.hi = hi;
		this.step = step;
		this.code = code;
	}
}

/**
This node represents a foreach loop.
*/
class ForeachStmt : Statement
{
	/**
	An optional loop label used for named breaks/continues. This member may be null, in which
	case it's an unnamed loop.
	*/
	char[] name;

	/**
	The list of index names (the names before the semicolon). This list is always at least
	two elements long. This is because when you write a foreach loop with only one index,
	an implicit dummy index is inserted before it.
	*/
	Identifier[] indices;

	/**
	The container (the stuff after the semicolon). This array can be 1, 2, or 3 elements
	long. Semantically, the first element is the "iterator", the second the "state", and
	the third the "index". However Croc will automatically call opApply on the "iterator"
	if it's not a function, so this can function like a foreach loop in D.
	*/
	Expression[] container;

	/**
	The code inside the loop.
	*/
	Statement code;

	/**
	*/
	this(ICompiler c, CompileLoc location, char[] name, Identifier[] indices, Expression[] container, Statement code)
	{
		super(c, location, code.endLocation, AstTag.ForeachStmt);

		this.name = name;
		this.indices = indices;
		this.container = container;
		this.code = code;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(indices);
		alloc.freeArray(container);
	}
}

/**
This node represents a switch statement.
*/
class SwitchStmt : Statement
{
	/**
	An optional label used for named breaks. This member may be null, in which case it's
	an unnamed switch.
	*/
	char[] name;

	/**
	The value to switch on.
	*/
	Expression condition;

	/**
	A list of cases. This is always at least one element long.
	*/
	CaseStmt[] cases;

	/**
	An optional default case. This member can be null.
	*/
	DefaultStmt caseDefault;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, char[] name, Expression condition, CaseStmt[] cases, DefaultStmt caseDefault)
	{
		super(c, location, endLocation, AstTag.SwitchStmt);
		this.name = name;
		this.condition = condition;
		this.cases = cases;
		this.caseDefault = caseDefault;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(cases);
	}
}

/**
This node represents a single case statement within a switch statement.
*/
class CaseStmt : Statement
{
	struct CaseCond
	{
		Expression exp;
		uint dynJump;
	}

	/**
	The list of values which will cause execution to jump to this case. In the code
	"case 1, 2, 3:" this corresponds to "1, 2, 3". This will always be at least one element
	long.
	*/
	CaseCond[] conditions;

	/**
	If this member is null, this is a "normal" case statement. If this member is non-null, this
	is a ranged case statement like "case 1 .. 10:". In that case, the 'conditions' member will
	be exactly one element long and will contain the low range value.
	*/
	Expression highRange;

	/**
	The code of the case statement.
	*/
	Statement code;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, CaseCond[] conditions, Expression highRange, Statement code)
	{
		super(c, location, endLocation, AstTag.CaseStmt);
		this.conditions = conditions;
		this.highRange = highRange;
		this.code = code;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(conditions);
	}
}

/**
This node represents the default case in a switch statement.
*/
class DefaultStmt : Statement
{
	/**
	The code of the statement.
	*/
	Statement code;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Statement code)
	{
		super(c, location, endLocation, AstTag.DefaultStmt);
		this.code = code;
	}
}

/**
This node represents a continue statement.
*/
class ContinueStmt : Statement
{
	/**
	Optional name of control structure to continue. Can be null, which means an unnamed continue.
	*/
	char[] name;

	/**
	*/
	this(ICompiler c, CompileLoc location, char[] name)
	{
		super(c, location, location, AstTag.ContinueStmt);
		this.name = name;
	}
}

/**
This node represents a break statement.
*/
class BreakStmt : Statement
{
	/**
	Optional name of control structure to break. Can be null, which means an unnamed break.
	*/
	char[] name;

	/**
	*/
	this(ICompiler c, CompileLoc location, char[] name)
	{
		super(c, location, location, AstTag.BreakStmt);
		this.name = name;
	}
}

/**
This node represents a return statement.
*/
class ReturnStmt : Statement
{
	/**
	The list of expressions to return. This array may have 0 or more elements.
	*/
	Expression[] exprs;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression[] exprs)
	{
		super(c, location, endLocation, AstTag.ReturnStmt);
		this.exprs = exprs;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(exprs);
	}
}

/**
This node represents a try-catch statement. Note that something like "try{}catch(e:E){}finally{}"
is actually turned into "try{try{}catch(e:E){}}finally{}", that is, a try-catch nested inside a
try-finally.
*/
class TryCatchStmt : Statement
{
	/**
	The body of code to try.
	*/
	Statement tryBody;

	struct CatchClause
	{
		/**
		The variable to use in this catch clause. In the code "try{}catch(e:E){}", this corresponds
		to 'e'.
		*/
		Identifier catchVar;

		/**
		The list of exception types that this catch clause catches. In the code "try{}catch(e:E1|E2){}",
		this corresponds to 'E1|E2'. This array will always be at least one element long.
		*/
		Expression[] exTypes;

		/**
		The body of this catch clause.
		*/
		Statement catchBody;
	}

	/**
	An array of one or more catch clauses that follow the try block.
	*/
	CatchClause[] catches;

	/**
	Filled in during semantic analysis. This is the hidden variable used to actually catch the exception,
	and its type is switched on by the transformedCatch statement.
	*/
	Identifier hiddenCatchVar;

	/**
	Filled in during semantic analysis. The pretty catch syntax is actually turned into a switch by the
	compiler. This is that autogenerated statement.
	*/
	Statement transformedCatch;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Statement tryBody, CatchClause[] catches)
	{
		super(c, location, endLocation, AstTag.TryCatchStmt);

		this.tryBody = tryBody;
		this.catches = catches;
	}

	override void cleanup(ref Allocator alloc)
	{
		foreach(ref c; catches)
			alloc.freeArray(c.exTypes);

		alloc.freeArray(catches);
	}
}

/**
This node represents a try-finally statement. See TryCatchStmt for information on how "try-catch-finally"
statements are represented.
*/
class TryFinallyStmt : Statement
{
	/**
	The body of code to try.
	*/
	Statement tryBody;

	/**
	The body of the finally block.
	*/
	Statement finallyBody;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Statement tryBody, Statement finallyBody)
	{
		super(c, location, endLocation, AstTag.TryFinallyStmt);

		this.tryBody = tryBody;
		this.finallyBody = finallyBody;
	}
}

/**
This node represents a throw statement.
*/
class ThrowStmt : Statement
{
	/**
	The value that should be thrown.
	*/
	Expression exp;

	/**
	True if this throw is rethrowing a caught exception. This is only set when the throw is
	auto-generated by scope(success) and scope(failure), and is used to control whether a traceback
	is needed for the exception (no new traceback is generated for rethrown exceptions).
	*/
	bool rethrowing;

	/**
	*/
	this(ICompiler c, CompileLoc location, Expression exp, bool rethrowing = false)
	{
		super(c, location, exp.endLocation, AstTag.ThrowStmt);
		this.exp = exp;
		this.rethrowing = rethrowing;
	}
}

/**
This node represents a scope (exit, success, or failure) statement.
*/
class ScopeActionStmt : Statement
{
	enum
	{
		/** scope(exit) */
		Exit,
		/** scope(success) */
		Success,
		/** scope(failure) */
		Failure
	}

	/**
	One of the above constants, indicates which kind of scope statement this is.
	*/
	ubyte type;

	/**
	The statement which will be executed if this scope statement is run.
	*/
	Statement stmt;

	/**
	*/
	this(ICompiler c, CompileLoc location, ubyte type, Statement stmt)
	{
		super(c, location, stmt.endLocation, AstTag.ScopeActionStmt);
		this.type = type;
		this.stmt = stmt;
	}
}

/**
This node represents normal assignment, either single- or multi-target.
*/
class AssignStmt : Statement
{
	/**
	The list of destination expressions. This list always has at least one element.
	This list must contain only expressions which can be LHSes. That will be checked
	at codegen time.
	*/
	Expression[] lhs;

	/**
	The right-hand side of the assignment. Must always have at least 1 item. This is not checked
	by the ctor.
	*/
	Expression[] rhs;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression[] lhs, Expression[] rhs)
	{
		super(c, location, endLocation, AstTag.AssignStmt);
		this.lhs = lhs;
		this.rhs = rhs;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(lhs);
		alloc.freeArray(rhs);
	}
}

/**
This node handles the common features of the reflexive assignments, as well as conditional assignment (?=).
*/
abstract class OpAssignStmt : Statement
{
	/**
	The left-hand-side of the assignment. This may not be a constant value or '#vararg', and if
	this is a conditional assignment, it may not be 'this'. These conditions will be checked at
	codegen.
	*/
	Expression lhs;

	/**
	The right-hand-side of the assignment.
	*/
	Expression rhs;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, type);
		this.lhs = lhs;
		this.rhs = rhs;
	}
}

/**
This node represents addition assignment (+=).
*/
class AddAssignStmt : OpAssignStmt
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.AddAssignStmt, lhs, rhs);
	}
}

/**
This node represents subtraction assignment (-=).
*/
class SubAssignStmt : OpAssignStmt
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.SubAssignStmt, lhs, rhs);
	}
}

/**
This node represents concatenation assignment (~=).
*/
class CatAssignStmt : Statement
{
	/**
	The left-hand-side of the assignment. The same constraints apply here as for other
	reflexive assignments.
	*/
	Expression lhs;

	/**
	The right-hand-side of the assignment.
	*/
	Expression rhs;

	Expression[] operands;
	bool collapsed = false;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.CatAssignStmt);
		this.lhs = lhs;
		this.rhs = rhs;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(operands);
	}
}

/**
This node represents multiplication assignment (*=).
*/
class MulAssignStmt : OpAssignStmt
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.MulAssignStmt, lhs, rhs);
	}
}

/**
This node represents division assignment (/=).
*/
class DivAssignStmt : OpAssignStmt
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.DivAssignStmt, lhs, rhs);
	}
}

/**
This node represents modulo assignment (%=).
*/
class ModAssignStmt : OpAssignStmt
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.ModAssignStmt, lhs, rhs);
	}
}

/**
This node represents bitwise OR assignment (|=).
*/
class OrAssignStmt : OpAssignStmt
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.OrAssignStmt, lhs, rhs);
	}
}

/**
This node represents bitwise XOR assignment (^=).
*/
class XorAssignStmt : OpAssignStmt
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.XorAssignStmt, lhs, rhs);
	}
}

/**
This node represents bitwise AND assignment (&=).
*/
class AndAssignStmt : OpAssignStmt
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.AndAssignStmt, lhs, rhs);
	}
}

/**
This node represents bitwise left-shift assignment (<<=).
*/
class ShlAssignStmt : OpAssignStmt
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.ShlAssignStmt, lhs, rhs);
	}
}

/**
This node represents bitwise right-shift assignment (>>=).
*/
class ShrAssignStmt : OpAssignStmt
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.ShrAssignStmt, lhs, rhs);
	}
}

/**
This node represents bitwise unsigned right-shift assignment (>>>=).
*/
class UShrAssignStmt : OpAssignStmt
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.UShrAssignStmt, lhs, rhs);
	}
}

/**
This node represents conditional assignment (?=).
*/
class CondAssignStmt : OpAssignStmt
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.CondAssignStmt, lhs, rhs);
	}
}

/**
This node represents an increment, either prefix or postfix (++a or a++).
*/
class IncStmt : Statement
{
	/**
	The expression to modify. The same constraints apply as for reflexive assignments.
	*/
	Expression exp;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression exp)
	{
		super(c, location, endLocation, AstTag.IncStmt);
		this.exp = exp;
	}
}

/**
This node represents a decrement, either prefix or postfix (--a or a--).
*/
class DecStmt : Statement
{
	/**
	The expression to modify. The same constraints apply as for reflexive assignments.
	*/
	Expression exp;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression exp)
	{
		super(c, location, endLocation, AstTag.DecStmt);
		this.exp = exp;
	}
}

/**
This node is an internal node inserted in function bodies if parameter type checking is enabled.
*/
class TypecheckStmt : Statement
{
	/**
	*/
	FuncDef def;

	/**
	*/
	this(ICompiler c, CompileLoc location, FuncDef def)
	{
		super(c, location, location, AstTag.TypecheckStmt);
		this.def = def;
	}
}

/**
The base class for all expressions.
*/
abstract class Expression : AstNode
{
	/**
	The slice of the source code that corresponds to this expression. Can be null.
	Only set on a "root" expression and not its children. Used for documentation
	generation.
	*/
	char[] sourceStr;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type)
	{
		super(c, location, endLocation, type);
	}

	/**
	Ensure that this expression can be evaluated to nothing, i.e. that it can exist
	on its own. Throws an exception if not.
	*/
	void checkToNothing(ICompiler c)
	{
		if(!hasSideEffects())
			c.loneStmtException(location, "{} cannot exist on its own", niceString());
	}

	/**
	Returns whether or not this expression has side effects. If this returns false,
	checkToNothing will throw an error.
	*/
	bool hasSideEffects()
	{
		return false;
	}

	/**
	Ensure that this expression can give multiple return values. If it can't, throws an
	exception.
	*/
	void checkMultRet(ICompiler c)
	{
		if(!isMultRet())
			c.semException(location, "{} cannot be the source of a multi-target assignment", niceString());
	}

	/**
	Returns whether this expression can give multiple return values. If this returns
	false, checkMultRet will throw an error.
	*/
	bool isMultRet()
	{
		return false;
	}

	/**
	Ensure that this expression can be the left-hand side of an assignment. If it can't,
	throws an exception.
	*/
	void checkLHS(ICompiler c)
	{
		if(!isLHS())
			c.semException(location, "{} cannot be the target of an assignment", niceString());
	}

	/**
	Returns whether this expression can be the left-hand side of an assignment. If this
	returns false, checkLHS will throw an error.
	*/
	bool isLHS()
	{
		return false;
	}

	/**
	Returns whether this expression is a constant value.
	*/
	bool isConstant()
	{
		return false;
	}

	/**
	Returns whether this expression is 'null'.
	*/
	bool isNull()
	{
		return false;
	}

	/**
	Returns whether this expression is a boolean constant.
	*/
	bool isBool()
	{
		return false;
	}

	/**
	Returns this expression as a boolean constant, if possible. assert(false)s
	otherwise.
	*/
	bool asBool()
	{
		assert(false);
	}

	/**
	Returns whether this expression is an integer constant.
	*/
	bool isInt()
	{
		return false;
	}

	/**
	Returns this expression as an integer constant, if possible. assert(false)s
	otherwise.
	*/
	crocint asInt()
	{
		assert(false);
	}

	/**
	Returns whether this expression is a floating point constant.
	*/
	bool isFloat()
	{
		return false;
	}

	/**
	Returns this expression as a floating point constant, if possible. assert(false)s
	otherwise.
	*/
	crocfloat asFloat()
	{
		assert(false);
	}

	/**
	Returns whether this expression is a character constant.
	*/
	bool isChar()
	{
		return false;
	}

	/**
	Returns this expression as a character constant, if possible. assert(false)s
	otherwise.
	*/
	dchar asChar()
	{
		assert(false);
	}

	/**
	Returns whether this expression is a string constant.
	*/
	bool isString()
	{
		return false;
	}

	/**
	Returns this expression as a string constant, if possible. assert(false)s
	otherwise.
	*/
	char[] asString()
	{
		assert(false);
	}

	/**
	If this expression is a constant value, returns whether this expression would evaluate
	as true according to Croc's definition of truth. Otherwise returns false.
	*/
	bool isTrue()
	{
		return false;
	}
}

/**
This node represents a conditional (?:) expression.
*/
class CondExp : Expression
{
	/**
	The first expression, which comes before the question mark.
	*/
	Expression cond;

	/**
	The second expression, which comes between the question mark and the colon.
	*/
	Expression op1;

	/**
	The third expression, which comes after the colon.
	*/
	Expression op2;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression cond, Expression op1, Expression op2)
	{
		super(c, location, endLocation, AstTag.CondExp);
		this.cond = cond;
		this.op1 = op1;
		this.op2 = op2;
	}

	override bool hasSideEffects()
	{
		return cond.hasSideEffects() || op1.hasSideEffects() || op2.hasSideEffects();
	}
}

/**
The base class for binary expressions. Many of them share some or all of their code
generation phases, as well has having other similar properties.
*/
abstract class BinaryExp : Expression
{
	/**
	The left-hand operand.
	*/
	Expression op1;

	/**
	The right-hand operand.
	*/
	Expression op2;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type, Expression op1, Expression op2)
	{
		super(c, location, endLocation, type);
		this.op1 = op1;
		this.op2 = op2;
	}
}

const BinExpMixin =
"public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression left, Expression right)"
"{"
	"super(c, location, endLocation, mixin(\"AstTag.\" ~ typeof(this).stringof), left, right);"
"}";

/**
This node represents a logical or (||) expression.
*/
class OrOrExp : BinaryExp
{
	mixin(BinExpMixin);

	override bool hasSideEffects()
	{
		return op1.hasSideEffects() || op2.hasSideEffects();
	}
}

/**
This node represents a logical or (||) expression.
*/
class AndAndExp : BinaryExp
{
	mixin(BinExpMixin);

	override bool hasSideEffects()
	{
		return op1.hasSideEffects() || op2.hasSideEffects();
	}
}

/**
This node represents a bitwise or expression.
*/
class OrExp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This node represents a bitwise xor expression.
*/
class XorExp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This node represents a bitwise and expression.
*/
class AndExp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This class serves as a base class for all equality expressions.
*/
abstract class BaseEqualExp : BinaryExp
{
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type, Expression left, Expression right)
	{
		super(c, location, endLocation, type, left, right);
	}
}

/**
This node represents an equality (==) expression.
*/
class EqualExp : BaseEqualExp
{
	mixin(BinExpMixin);
}

/**
This node represents an inequality (!=) expression.
*/
class NotEqualExp : BaseEqualExp
{
	mixin(BinExpMixin);
}

/**
This node represents an identity (is) expression.
*/
class IsExp : BaseEqualExp
{
	mixin(BinExpMixin);
}

/**
This node represents a nonidentity (!is) expression.
*/
class NotIsExp : BaseEqualExp
{
	mixin(BinExpMixin);
}

/**
This node represents an 'in' expression.
*/
class InExp : BaseEqualExp
{
	mixin(BinExpMixin);
}

/**
This node represents a '!in' expression.
*/
class NotInExp : BaseEqualExp
{
	mixin(BinExpMixin);
}


/**
This class serves as a base class for comparison expressions.
*/
abstract class BaseCmpExp : BinaryExp
{
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type, Expression left, Expression right)
	{
		super(c, location, endLocation, type, left, right);
	}
}

/**
This node represents a less-than (<) comparison.
*/
class LTExp : BaseCmpExp
{
	mixin(BinExpMixin);
}

/**
This node represents a less-than-or-equals (<=) comparison.
*/
class LEExp : BaseCmpExp
{
	mixin(BinExpMixin);
}

/**
This node represents a greater-than (>) comparison.
*/
class GTExp : BaseCmpExp
{
	mixin(BinExpMixin);
}

/**
This node represents a greater-than-or-equals (>=) comparison.
*/
class GEExp : BaseCmpExp
{
	mixin(BinExpMixin);
}

/**
This node represents a three-way comparison (<=>) expression.
*/
class Cmp3Exp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This node represents an 'as' expression.
*/
class AsExp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This node represents a bitwise left-shift (<<) expression.
*/
class ShlExp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This node represents a bitwise right-shift (>>) expression.
*/
class ShrExp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This node represents a bitwise unsigned right-shift (>>>) expression.
*/
class UShrExp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This node represents an addition (+) expression.
*/
class AddExp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This node represents a subtraction (-) expression.
*/
class SubExp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This node represents a concatenation (~) expression.
*/
class CatExp : BinaryExp
{
	Expression[] operands;
	bool collapsed = false;

	mixin(BinExpMixin);

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(operands);
	}
}

/**
This node represents a multiplication (*) expression.
*/
class MulExp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This node represents a division (/) expression.
*/
class DivExp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This node represents a modulo (%) expression.
*/
class ModExp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This class is the base class for unary expressions. These tend to share some code
generation, as well as all having a single operand.
*/
abstract class UnExp : Expression
{
	/**
	The operand of the expression.
	*/
	Expression op;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type, Expression operand)
	{
		super(c, location, endLocation, type);
		op = operand;
	}
}

const UnExpMixin =
"public this(ICompiler c, CompileLoc location, Expression operand)"
"{"
	"super(c, location, operand.endLocation, mixin(\"AstTag.\" ~ typeof(this).stringof), operand);"
"}";

/**
This node represents a negation (-a).
*/
class NegExp : UnExp
{
	mixin(UnExpMixin);
}

/**
This node represents a logical not expression (!a).
*/
class NotExp : UnExp
{
	mixin(UnExpMixin);
}

/**
This node represents a bitwise complement expression (~a).
*/
class ComExp : UnExp
{
	mixin(UnExpMixin);
}

/**
This node represents a length expression (#a).
*/
class LenExp : UnExp
{
	mixin(UnExpMixin);

	override bool isLHS()
	{
		return true;
	}
}

/**
This class is the base class for postfix expressions, that is expressions which kind of
attach to the end of other expressions. It inherits from UnExp, so that the single
operand becomes the expression to which the postfix expression becomes attached.
*/
abstract class PostfixExp : UnExp
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type, Expression operand)
	{
		super(c, location, endLocation, type, operand);
	}
}

/**
This node represents dot expressions, in both the dot-ident (a.x) and dot-expression
(a.(expr)) forms. These correspond to field access.
*/
class DotExp : PostfixExp
{
	/**
	The name. This can be any expression, as long as it evaluates to a string. An
	expression like "a.x" is sugar for "a.("x")", so this will be a string literal
	in that case.
	*/
	Expression name;

	/**
	*/
	this(ICompiler c, Expression operand, Expression name)
	{
		super(c, operand.location, name.endLocation, AstTag.DotExp, operand);
		this.name = name;
	}

	override bool isLHS()
	{
		return true;
	}
}

/**
This node corresponds to the super expression (a.super).
*/
class DotSuperExp : PostfixExp
{
	this(ICompiler c, CompileLoc endLocation, Expression operand)
	{
		super(c, operand.location, endLocation, AstTag.DotSuperExp, operand);
	}
}

/**
This node corresponds to an indexing operation (a[x]).
*/
class IndexExp : PostfixExp
{
	/**
	The index of the operation (the value inside the brackets).
	*/
	Expression index;

	/**
	*/
	this(ICompiler c, CompileLoc endLocation, Expression operand, Expression index)
	{
		super(c, operand.location, endLocation, AstTag.IndexExp, operand);
		this.index = index;
	}

	override bool isLHS()
	{
		return true;
	}
}

/**
This node corresponds to a slicing operation (a[x .. y]).
*/
class SliceExp : PostfixExp
{
	/**
	The low index of the slice. If no low index is given, this will be a NullExp.
	This member will therefore never be null.
	*/
	Expression loIndex;

	/**
	The high index of the slice. If no high index is given, this will be a NullExp.
	This member will therefore never be null.
	*/
	Expression hiIndex;

	/**
	*/
	this(ICompiler c, CompileLoc endLocation, Expression operand, Expression loIndex, Expression hiIndex)
	{
		super(c, operand.location, endLocation, AstTag.SliceExp, operand);
		this.loIndex = loIndex;
		this.hiIndex = hiIndex;
	}

	override bool isLHS()
	{
		return true;
	}
}

/**
This node corresponds to a non-method function call (f()).
*/
class CallExp : PostfixExp
{
	/**
	The context to be used when calling the function. This corresponds to 'x' in
	the expression "f(with x)". If this member is null, a context of 'null' will
	be passed to the function.
	*/
	Expression context;

	/**
	The list of arguments to be passed to the function. This can be 0 or more elements.
	*/
	Expression[] args;

	/**
	*/
	this(ICompiler c, CompileLoc endLocation, Expression operand, Expression context, Expression[] args)
	{
		super(c, operand.location, endLocation, AstTag.CallExp, operand);
		this.context = context;
		this.args = args;
	}

	override bool hasSideEffects()
	{
		return true;
	}

	override bool isMultRet()
	{
		return true;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(args);
	}
}

/**
This class corresponds to a method call in either form (a.f() or a.("f")()).
*/
class MethodCallExp : PostfixExp
{
	/**
	*/
	Expression method;

	/**
	The list of argument to pass to the method. This can have 0 or more elements.
	*/
	Expression[] args;

	/**
	If this member is true, 'op' will be null (and will be interpreted as a "this").
	*/
	bool isSuperCall;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression operand, Expression method, Expression[] args, bool isSuperCall)
	{
		super(c, location, endLocation, AstTag.MethodCallExp, operand);
		this.method = method;
		this.args = args;
		this.isSuperCall = isSuperCall;
	}

	override bool hasSideEffects()
	{
		return true;
	}

	override bool isMultRet()
	{
		return true;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(args);
	}
}

/**
The base class for primary expressions.
*/
class PrimaryExp : Expression
{
	/**
	*/
	this(ICompiler c, CompileLoc location, AstTag type)
	{
		super(c, location, location, type);
	}

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type)
	{
		super(c, location, endLocation, type);
	}
}

/**
An identifier expression. These can refer to locals, upvalues, or globals.
*/
class IdentExp : PrimaryExp
{
	/**
	The identifier itself.
	*/
	Identifier name;

	/**
	Create an ident exp from an identifier object.
	*/
	this(ICompiler c, Identifier i)
	{
		super(c, i.location, AstTag.IdentExp);
		this.name = i;
	}

	override bool isLHS()
	{
		return true;
	}
}

/**
Represents the ubiquitous 'this' variable.
*/
class ThisExp : PrimaryExp
{
	/**
	*/
	this(ICompiler c, CompileLoc location)
	{
		super(c, location, AstTag.ThisExp);
	}
}

/**
Represents the 'null' literal.
*/
class NullExp : PrimaryExp
{
	/**
	*/
	this(ICompiler c, CompileLoc location)
	{
		super(c, location, AstTag.NullExp);
	}

	override bool isConstant()
	{
		return true;
	}

	override bool isTrue()
	{
		return false;
	}

	override bool isNull()
	{
		return true;
	}
}

/**
Represents either a 'true' or 'false' literal.
*/
class BoolExp : PrimaryExp
{
	/**
	The actual value of the literal.
	*/
	bool value;

	/**
	*/
	this(ICompiler c, CompileLoc location, bool value)
	{
		super(c, location, AstTag.BoolExp);
		this.value = value;
	}

	override bool isConstant()
	{
		return true;
	}

	override bool isTrue()
	{
		return value;
	}

	override bool isBool()
	{
		return true;
	}

	override bool asBool()
	{
		return value;
	}
}

/**
Represents the 'vararg' exp outside of a special form (i.e. not #vararg, vararg[x], or
vararg[x .. y]).
*/
class VarargExp : PrimaryExp
{
	/**
	*/
	this(ICompiler c, CompileLoc location)
	{
		super(c, location, AstTag.VarargExp);
	}

	bool isMultRet()
	{
		return true;
	}
}

/**
This node represents the variadic-length expression (#vararg).
*/
class VargLenExp : PrimaryExp
{
	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation)
	{
		super(c, location, endLocation, AstTag.VargLenExp);
	}
}

/**
This node corresponds to a variadic indexing operation (vararg[x]).
*/
class VargIndexExp : PrimaryExp
{
	/**
	The index of the operation (the value inside the brackets).
	*/
	Expression index;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression index)
	{
		super(c, location, endLocation, AstTag.VargIndexExp);
		this.index = index;
	}

	override bool isLHS()
	{
		return true;
	}
}

/**
This node represents a variadic slice operation (vararg[x .. y]).
*/
class VargSliceExp : PrimaryExp
{
	/**
	The low index of the slice.
	*/
	Expression loIndex;

	/**
	The high index of the slice.
	*/
	Expression hiIndex;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression loIndex, Expression hiIndex)
	{
		super(c, location, endLocation, AstTag.VargSliceExp);
		this.loIndex = loIndex;
		this.hiIndex = hiIndex;
	}

	override bool isMultRet()
	{
		return true;
	}
}

/**
Represents an integer literal.
*/
class IntExp : PrimaryExp
{
	/**
	The actual value of the literal.
	*/
	crocint value;

	/**
	*/
	this(ICompiler c, CompileLoc location, crocint value)
	{
		super(c, location, AstTag.IntExp);
		this.value = value;
	}

	override bool isConstant()
	{
		return true;
	}

	override bool isTrue()
	{
		return (value != 0);
	}

	override bool isInt()
	{
		return true;
	}

	override crocint asInt()
	{
		return value;
	}

	override crocfloat asFloat()
	{
		return cast(crocfloat)value;
	}
}

/**
Represents a floating-point literal.
*/
class FloatExp : PrimaryExp
{
	/**
	The actual value of the literal.
	*/
	crocfloat value;

	/**
	*/
	this(ICompiler c, CompileLoc location, crocfloat value)
	{
		super(c, location, AstTag.FloatExp);
		this.value = value;
	}

	override bool isConstant()
	{
		return true;
	}

	override bool isTrue()
	{
		return (value != 0.0);
	}

	override bool isFloat()
	{
		return true;
	}

	override crocfloat asFloat()
	{
		return value;
	}
}

/**
Represents a character literal.
*/
class CharExp : PrimaryExp
{
	/**
	The actual character of the literal.
	*/
	dchar value;

	/**
	*/
	this(ICompiler c, CompileLoc location, dchar value)
	{
		super(c, location, AstTag.CharExp);
		this.value = value;
	}

	override bool isConstant()
	{
		return true;
	}

	override bool isTrue()
	{
		return (value != 0);
	}

	override bool isChar()
	{
		return true;
	}

	override dchar asChar()
	{
		return value;
	}
}

/**
Represents a string literal.
*/
class StringExp : PrimaryExp
{
	/**
	The actual value of the literal.
	*/
	char[] value;

	/**
	*/
	this(ICompiler c, CompileLoc location, char[] value)
	{
		super(c, location, AstTag.StringExp);
		this.value = value;
	}

	override bool isConstant()
	{
		return true;
	}

	override bool isTrue()
	{
		return true;
	}

	override bool isString()
	{
		return true;
	}

	override char[] asString()
	{
		return value;
	}
}

/**
Represents a function literal.
*/
class FuncLiteralExp : PrimaryExp
{
	/**
	The actual "guts" of the function.
	*/
	FuncDef def;

	/**
	*/
	this(ICompiler c, CompileLoc location, FuncDef def)
	{
		super(c, location, def.endLocation, AstTag.FuncLiteralExp);
		this.def = def;
	}
}

/**
Represents a class literal.
*/
class ClassLiteralExp : PrimaryExp
{
	/**
	The actual "guts" of the class.
	*/
	ClassDef def;

	/**
	*/
	this(ICompiler c, CompileLoc location, ClassDef def)
	{
		super(c, location, def.endLocation, AstTag.ClassLiteralExp);
		this.def = def;
	}
}

/**
Represents an expression inside a pair of parentheses. Besides controlling order-of-
operations, this expression will make a multiple-return-value expression return exactly
one result instead. Thus 'vararg' can give 0 or more values but '(vararg)' gives
exactly one (null in the case that there are no varargs).
*/
class ParenExp : PrimaryExp
{
	/**
	The parenthesized expression.
	*/
	Expression exp;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression exp)
	{
		super(c, location, endLocation, AstTag.ParenExp);
		this.exp = exp;
	}
}

/**
This node represents a table literal.
*/
class TableCtorExp : PrimaryExp
{
	struct Field
	{
		Expression key;
		Expression value;
	}

	/**
	An array of fields. The first value in each element is the key; the second the value.
	*/
	Field[] fields;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Field[] fields)
	{
		super(c, location, endLocation, AstTag.TableCtorExp);
		this.fields = fields;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(fields);
	}
}

/**
This node represents an array literal.
*/
class ArrayCtorExp : PrimaryExp
{
	/**
	The list of values.
	*/
	Expression[] values;

	protected const uint maxFields = Instruction.MaxArrayFields;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression[] values)
	{
		super(c, location, endLocation, AstTag.ArrayCtorExp);
		this.values = values;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(values);
	}
}

/**
This node represents a namespace literal.
*/
class NamespaceCtorExp : PrimaryExp
{
	/**
	The actual "guts" of the namespace.
	*/
	NamespaceDef def;

	/**
	*/
	this(ICompiler c, CompileLoc location, NamespaceDef def)
	{
		super(c, location, def.endLocation, AstTag.NamespaceCtorExp);
		this.def = def;
	}
}

/**
This node represents a yield expression, such as "yield(1, 2, 3)".
*/
class YieldExp : PrimaryExp
{
	/**
	The arguments inside the yield expression.
	*/
	Expression[] args;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression[] args)
	{
		super(c, location, endLocation, AstTag.YieldExp);
		this.args = args;
	}

	bool hasSideEffects()
	{
		return true;
	}

	bool isMultRet()
	{
		return true;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(args);
	}
}

/**
This is the base class for both numeric and generic for comprehensions inside array
and table comprehensions.
*/
abstract class ForComprehension : AstNode
{
	/**
	Optional if comprehension that follows this. This member may be null.
	*/
	IfComprehension ifComp;

	/**
	Optional for comprehension that follows this. This member may be null.
	*/
	ForComprehension forComp;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag tag)
	{
		super(c, location, endLocation, tag);
	}
}

/**
This node represents a foreach comprehension in an array or table comprehension, i.e.
in the code "[x for x in a]", it represents "for x in a".
*/
class ForeachComprehension : ForComprehension
{
	/**
	These members are the same as for a ForeachStmt.
	*/
	Identifier[] indices;

	/// ditto
	Expression[] container;

	/**
	*/
	this(ICompiler c, CompileLoc location, Identifier[] indices, Expression[] container, IfComprehension ifComp, ForComprehension forComp)
	{
		if(ifComp)
		{
			if(forComp)
				super(c, location, forComp.endLocation, AstTag.ForeachComprehension);
			else
				super(c, location, ifComp.endLocation, AstTag.ForeachComprehension);
		}
		else if(forComp)
			super(c, location, forComp.endLocation, AstTag.ForeachComprehension);
		else
			super(c, location, container[$ - 1].endLocation, AstTag.ForeachComprehension);

		this.indices = indices;
		this.container = container;
		this.ifComp = ifComp;
		this.forComp = forComp;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(indices);
		alloc.freeArray(container);
	}
}

/**
This node represents a numeric for comprehension in an array or table comprehension, i.e.
in the code "[x for x in 0 .. 10]" this represents "for x in 0 .. 10".
*/
class ForNumComprehension : ForComprehension
{
	/**
	These members are the same as for a ForNumStmt.
	*/
	Identifier index;

	/// ditto
	Expression lo;

	/// ditto
	Expression hi;

	/// ditto
	Expression step;

	/**
	*/
	this(ICompiler c, CompileLoc location, Identifier index, Expression lo, Expression hi, Expression step, IfComprehension ifComp, ForComprehension forComp)
	{
		if(ifComp)
		{
			if(forComp)
				super(c, location, forComp.endLocation, AstTag.ForNumComprehension);
			else
				super(c, location, ifComp.endLocation, AstTag.ForNumComprehension);
		}
		else if(forComp)
			super(c, location, forComp.endLocation, AstTag.ForNumComprehension);
		else if(step)
			super(c, location, step.endLocation, AstTag.ForNumComprehension);
		else
			super(c, location, hi.endLocation, AstTag.ForNumComprehension); // NOT REACHABLE

		this.index = index;
		this.lo = lo;
		this.hi = hi;
		this.step = step;

		this.ifComp = ifComp;
		this.forComp = forComp;
	}
}

/**
This node represents an if comprehension an an array or table comprehension, i.e.
in the code "[x for x in a if x < 10]", this represents "if x < 10".
*/
class IfComprehension : AstNode
{
	/**
	The condition to test.
	*/
	Expression condition;

	/**
	*/
	this(ICompiler c, CompileLoc location, Expression condition)
	{
		super(c, location, condition.endLocation, AstTag.IfComprehension);
		this.condition = condition;
	}
}

/**
This node represents an array comprehension, such as "[x for x in a]".
*/
class ArrayComprehension : PrimaryExp
{
	/**
	The expression which is executed as the innermost thing in the loop and whose values
	are used to construct the array.
	*/
	Expression exp;

	/**
	The root of the comprehension tree.
	*/
	ForComprehension forComp;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression exp, ForComprehension forComp)
	{
		super(c, location, endLocation, AstTag.ArrayComprehension);

		this.exp = exp;
		this.forComp = forComp;
	}
}

/**
This node represents a table comprehension, such as "{[v] = k for k, v in a}".
*/
class TableComprehension : PrimaryExp
{
	/**
	The key expression. This is the thing in the brackets at the beginning.
	*/
	Expression key;

	/**
	The value expression. This is the thing after the equals sign at the beginning.
	*/
	Expression value;

	/**
	The root of the comprehension tree.
	*/
	ForComprehension forComp;

	/**
	*/
	this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression key, Expression value, ForComprehension forComp)
	{
		super(c, location, endLocation, AstTag.TableComprehension);

		this.key = key;
		this.value = value;
		this.forComp = forComp;
	}
}