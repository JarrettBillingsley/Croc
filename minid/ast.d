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

import minid.alloc;
import minid.compilertypes;
import minid.opcodes;
import minid.types;

const char[][] AstTagNames =
[
	"Unknown",
	"Identifier",

	"ObjectDef",
	"FuncDef",
	"NamespaceDef",

	"Module",
	"Decorator",

	"VarDecl",
	"FuncDecl",
	"ObjectDecl",
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
	"TryStmt",
	"ThrowStmt",

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
	"FuncEnvStmt",
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
	AstTag.Identifier:           "identifier",

	AstTag.ObjectDef:            "object definition",
	AstTag.FuncDef:              "function definition",
	AstTag.NamespaceDef:         "namespace definition",

	AstTag.Module:               "module",
	AstTag.Decorator:            "decorator",

	AstTag.VarDecl:              "variable declaration",
	AstTag.FuncDecl:             "function declaration",
	AstTag.ObjectDecl:           "object declaration",
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
	AstTag.TryStmt:              "'try-catch-finally' statement",
	AstTag.ThrowStmt:            "'throw' statement",

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
	The tag indicating what kind of node this actually is.
	*/
	public AstTag type;

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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type)
	{
		c.addNode(this);
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
	private this(ICompiler c)
	{
		super(c, CompileLoc.init, CompileLoc.init, AstTag.Unknown);
		//assert(false);
	}
}

/**
This node represents an identifier.  This isn't the same as an IdentExp, as identifiers can
be used in non-expression contexts (such as names in declarations).
*/
class Identifier : AstNode
{
	public char[] name;

	public this(ICompiler c, CompileLoc location, char[] name)
	{
		super(c, location, location, AstTag.Identifier);
		this.name = name;
	}
}

/**
This node represents the guts of an object literal.  This node does not directly correspond
to a single grammar element; rather it represents the common attributes of both object
literals and object declarations.
*/
class ObjectDef : AstNode
{
	/**
	Represents a single field in the object.  Remember that methods are fields too.
	*/
	struct Field
	{
		/**
		The name of the field.  This corresponds to either the name of a data member or
		the name of a method.
		*/
		char[] name;
		
		/**
		The initializer of the field.  This will never be null.  If a field is declared in
		an object but not given a value, a NullExp will be inserted into this field.
		*/
		Expression initializer;
	}

	/**
	The name of the object.  This field can be null, which indicates that the name of the
	object will be taken from its base object at runtime.
	*/
	public Identifier name;

	/**
	The base object from which this object derives.  This field will never be null.  If
	no base object is specified, it is given the value of an IdentExp with the identifier
	"Object".
	*/
	public Expression baseObject;
	
	/**
	The fields in this object, in the order they were declared.  See the Field struct above.
	*/
	public Field[] fields;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Identifier name, Expression baseObject, Field[] fields)
	{
		super(c, location, endLocation, AstTag.ObjectDef);
		this.name = name;
		this.baseObject = baseObject;
		this.fields = fields;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(fields);
	}
}

/**
Similar to ObjectDef, this class represents the common attributes of both function literals
and function declarations.
*/
class FuncDef : AstNode
{
	enum TypeMask : ushort
	{
		Null =      (1 << cast(uint)MDValue.Type.Null),
		Bool =      (1 << cast(uint)MDValue.Type.Bool),
		Int =       (1 << cast(uint)MDValue.Type.Int),
		Float =     (1 << cast(uint)MDValue.Type.Float),
		Char =      (1 << cast(uint)MDValue.Type.Char),

		String =    (1 << cast(uint)MDValue.Type.String),
		Table =     (1 << cast(uint)MDValue.Type.Table),
		Array =     (1 << cast(uint)MDValue.Type.Array),
		Function =  (1 << cast(uint)MDValue.Type.Function),
		Object =    (1 << cast(uint)MDValue.Type.Object),
		Namespace = (1 << cast(uint)MDValue.Type.Namespace),
		Thread =    (1 << cast(uint)MDValue.Type.Thread),
		NativeObj = (1 << cast(uint)MDValue.Type.NativeObj),

		NotNull = Bool | Int | Float | Char | String | Table | Array | Function | Object | Namespace | Thread | NativeObj,
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
		Defaults to TypeMask.Any, which allows any type to be passed.  This should not be
		set to 0; the codegen does not check for this so it's up to you.
		*/
		ushort typeMask = TypeMask.Any;

		/**
		If typeMask allows objects, this can be a list of expressions which should evaluate
		at runtime to object types that this parameter can accept.  This is an optional
		list.  If typeMask does not allow objects, this should be empty.
		*/
		Expression[] objectTypes;

		/**
		The default value for the parameter.  This can be null, in which case it will have
		no default value.
		*/
		Expression defValue;
	}

	/**
	The name of the function.  This will never be null.  In the case of function literals
	without names, this will be filled with an auto-generated name based off the location of
	where the literal occurred.
	*/
	public Identifier name;
	
	/**
	The list of parameters to the function.  See the Param struct above.  This will always be
	at least one element long, and element 0 will always be the 'this' parameter.
	*/
	public Param[] params;

	/**
	Indicates whether or not this function is variadic.
	*/
	public bool isVararg;
	
	/**
	The body of the function.  In the case of lambda functions (i.e. "function(x) = x * x"), this
	is a ReturnStmt with one expression, the expression that is the lambda's body.
	*/
	public Statement code;

	/**
	*/
	public this(ICompiler c, CompileLoc location, Identifier name, Param[] params, bool isVararg, Statement code)
	{
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
			alloc.freeArray(p.objectTypes);

		alloc.freeArray(params);
	}
}

/**
Like the ObjectDef and FuncDef classes, this represents the common attributes of both
namespace literals and declarations.
*/
class NamespaceDef : AstNode
{
	/**
	Represents a single field in the namespace.  Remember that functions are fields too.
	*/
	struct Field
	{
		/**
		The name of the field.  This corresponds to either the name of a data member or
		the name of a function.
		*/
		char[] name;
		
		/**
		The initializer of the field.  This will never be null.  If a field is declared in
		a namespace but not given a value, a NullExp will be inserted into this field.
		*/
		Expression initializer;
	}

	/**
	The name of the namespace.  This field will never be null.
	*/
	public Identifier name;

	/**
	The namespace which will become the parent of this namespace.  This field can be null,
	in which case the namespace's parent will be set to the environment of the current function.
	*/
	public Expression parent;

	/**
	The fields in this namespace, in an arbitrary order.  See the Field struct above.
	*/
	public Field[] fields;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Identifier name, Expression parent, Field[] fields)
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
Represents a MiniD module.  This node forms the root of an AST when a module is compiled.
*/
class Module : AstNode
{
	/**
	The name of this module.  This is an array of strings, each element of which is one
	piece of a dotted name.  This array will always be at least one element long.
	*/
	public char[][] names;

	/**
	A list of 0 or more statements which make up the body of the module.
	*/
	public Statement[] statements;
	
	/**
	*/
	public Decorator decorator;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, char[][] names, Statement[] statements, Decorator decorator)
	{
		super(c, location, endLocation, AstTag.Module);
		this.names = names;
		this.statements = statements;
		this.decorator = decorator;
	}
	
	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(names);
		alloc.freeArray(statements);
	}
}

/**
The base class for all statements.
*/
abstract class Statement : AstNode
{
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type)
	{
		super(c, location, endLocation, type);
	}
}

/**
Defines the types of protection possible for object, function, namespace, and variable
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
	public Protection protection;

	/**
	The list of names to be declared.  This will always have at least one name.
	*/
	public Identifier[] names;

	/**
	The initializer for the variables.  This can be null, in which case the variables
	will be initialized to null.  If this is non-null and there is more than one name,
	this must be a multi-return expression, such as a function call, vararg etc.
	*/
	public Expression initializer;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Protection protection, Identifier[] names, Expression initializer)
	{
		super(c, location, endLocation, AstTag.VarDecl);
		this.protection = protection;
		this.names = names;
		this.initializer = initializer;
	}

	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(names);
	}
}

/**
*/
class Decorator : AstNode
{
	/**
	*/
	public Expression func;
	
	/**
	*/
	public Expression context;

	/**
	*/
	public Expression[] args;

	/**
	*/
	public Decorator nextDec;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression func, Expression context, Expression[] args, Decorator nextDec)
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
This node represents a function declaration.  Note that there are some places in the
grammar which look like function declarations (like inside objects and namespaces) but
which actually are just syntactic sugar.  This is for actual declarations.
*/
class FuncDecl : Statement
{
	/**
	What protection level this declaration uses.
	*/
	public Protection protection;

	/**
	The "guts" of the function declaration.
	*/
	public FuncDef def;

	/**
	*/
	public Decorator decorator;

	/**
	The protection parameter can be any kind of protection.
	*/
	public this(ICompiler c, CompileLoc location, Protection protection, FuncDef def, Decorator decorator)
	{
		super(c, location, def.endLocation, AstTag.FuncDecl);
		this.protection = protection;
		this.def = def;
		this.decorator = decorator;
	}
}

/**
This node represents an object declaration.
*/
class ObjectDecl : Statement
{
	/**
	What protection level this declaration uses.
	*/
	public Protection protection;

	/**
	The actual "guts" of the object.
	*/
	public ObjectDef def;
	
	/**
	*/
	public Decorator decorator;

	/**
	The protection parameter can be any kind of protection.
	*/
	public this(ICompiler c, CompileLoc location, Protection protection, ObjectDef def, Decorator decorator)
	{
		super(c, location, def.endLocation, AstTag.ObjectDecl);
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
	public Protection protection;

	/**
	The "guts" of the namespace.
	*/
	public NamespaceDef def;
	
	/**
	*/
	public Decorator decorator;

	/**
	The protection parameter can be any level of protection.
	*/
	public this(ICompiler c, CompileLoc location, Protection protection, NamespaceDef def, Decorator decorator)
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
	public Expression cond;

	/**
	An optional message that will be used if the assertion fails.  This member
	can be null, in which case a message will be generated for the assertion
	based on its location.  If it's not null, it must evaluate to a string.
	*/
	public Expression msg;
	
	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression cond, Expression msg = null)
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
	An optional renaming of the import.  This member can be null, in which case no renaming
	is done.  In the code "import x = y;", this member corresponds to "x".
	*/
	public Identifier importName;
	
	/**
	The expression which evaluates to a string containing the name of the module to import.
	The statement "import a.b.c" is actually syntactic sugar for "import("a.b.c")", so expr
	will be a StringExp in this case.  This expression is checked (if it's constant) to ensure
	that it's a string when constant folding occurs.
	*/
	public Expression expr;

	/**
	An optional list of symbols to import from the module.  In the code "import x : a, b, c",
	this corresponds to "a, b, c".
	*/
	public Identifier[] symbols;
	
	/**
	A parallel array to the symbols array.  This holds the names of the symbols as they should
	be called in this module.  The code "import x : a, b" is sugar for "import x : a = a, b = b".
	In the code "import x : y = a, z = b", this array corresponds to "y, z".
	*/
	public Identifier[] symbolNames;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Identifier importName, Expression expr, Identifier[] symbols, Identifier[] symbolNames)
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
	public Statement[] statements;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Statement[] statements)
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
A node which doesn't correspond to a grammar element.  This indicates a new nested scope.
An example of where this would be used is in an anonymous scope with some code in it.  All it
does is affects the codegen of the contained statement by beginning a new scope before it
and ending the scope after it.
*/
class ScopeStmt : Statement
{
	/**
	The statement contained within this scope.  Typically a block statement, but can
	be anything.
	*/
	public Statement statement;

	/**
	*/
	public this(ICompiler c, Statement statement)
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
	The expression to be evaluated for this statement.  This must be a side-effecting
	expression, including function calls, yields, and assignments.  Conditional (?:)
	expressions and logical or and logical and (|| and &&) expressions are also allowed,
	providing at least one component is side-effecting.

	This class does $(B not) check that this expression is side-effecting; that is up to
	you.
	*/
	public Expression expr;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression expr)
	{
		super(c, location, endLocation, AstTag.ExpressionStmt);
		this.expr = expr;
	}
	
	/**
	*/
	public this(ICompiler c, Expression expr)
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
	the value of the condition.  In the code "if(local x = y < z){}", this corresponds
	to "x".  This member may be null, in which case there is no variable there.
	*/
	public IdentExp condVar;

	/**
	The condition to test.
	*/
	public Expression condition;
	
	/**
	The code to execute if the condition evaluates to true.
	*/
	public Statement ifBody;

	/**
	If there is an else clause, this is the code to execute if the condition evaluates to
	false.  If there is no else clause, this member is null.
	*/
	public Statement elseBody;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, IdentExp condVar, Expression condition, Statement ifBody, Statement elseBody)
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
	An optional variable to declare inside the statement's condition which will take on
	the value of the condition.  In the code "while(local x = y < z){}", this corresponds
	to "x".  This member may be null, in which case there is no variable there.
	*/
	public IdentExp condVar;
	
	/**
	The condition to test.
	*/
	public Expression condition;
	
	/**
	The code inside the loop.
	*/
	public Statement code;

	/**
	*/
	public this(ICompiler c, CompileLoc location, IdentExp condVar, Expression condition, Statement code)
	{
		super(c, location, code.endLocation, AstTag.WhileStmt);

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
	The code inside the loop.
	*/
	public Statement code;
	
	/**
	The condition to test at the end of the loop.
	*/
	public Expression condition;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Statement code, Expression condition)
	{
		super(c, location, endLocation, AstTag.DoWhileStmt);

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
	There are two types of initializers possible in the first clause of the for loop header:
	variable declarations and expression statements.  This struct holds one or the other.
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
	public Init[] init;
	
	/**
	The condition to test at the beginning of each iteration of the loop.  This can be
	null, in which case the only way to get out of the loop is to break, return, or
	throw an exception.
	*/
	public Expression condition;
	
	/**
	A list of 0 or more increment expression statements to be evaluated at the end of
	each iteration of the loop.
	*/
	public Statement[] increment;

	/**
	The code inside the loop.
	*/
	public Statement code;

	/**
	*/
	public this(ICompiler c, CompileLoc location, Init[] init, Expression cond, Statement[] inc, Statement code)
	{
		super(c, location, endLocation, AstTag.ForStmt);

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
	The name of the index variable.
	*/
	public Identifier index;
	
	/**
	The lower bound of the loop (the value before the "..").  If constant, it must be an
	int.
	*/
	public Expression lo;

	/**
	The upper bound of the loop (the value after the "..").  If constant, it must be an
	int.
	*/
	public Expression hi;

	/**
	The step value of the loop.  If specified, this is the value after the comma after the
	upper bound.  If not specified, this is given an IntExp of value 1.  This member is
	never null.  If constant, it must be an int.
	*/
	public Expression step;

	/**
	The code inside the loop.
	*/
	public Statement code;

	/**
	*/
	public this(ICompiler c, CompileLoc location, Identifier index, Expression lo, Expression hi, Expression step, Statement code)
	{
		super(c, location, code.endLocation, AstTag.ForNumStmt);

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
	The list of index names (the names before the semicolon).  This list is always at least
	two elements long.  This is because when you write a foreach loop with only one index,
	an implicit dummy index is inserted before it.
	*/
	public Identifier[] indices;
	
	/**
	The container (the stuff after the semicolon).  This array can be 1, 2, or 3 elements
	long.  Semantically, the first element is the "iterator", the second the "state", and
	the third the "index".  However MiniD will automatically call opApply on the "iterator"
	if it's not a function, so this can function like a foreach loop in D.
	*/
	public Expression[] container;
	
	/**
	The code inside the loop.
	*/
	public Statement code;

	/**
	*/
	public this(ICompiler c, CompileLoc location, Identifier[] indices, Expression[] container, Statement code)
	{
		super(c, location, code.endLocation, AstTag.ForeachStmt);

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
	The value to switch on.
	*/
	public Expression condition;
	
	/**
	A list of cases.  This is always at least one element long.
	*/
	public CaseStmt[] cases;
	
	/**
	An optional default case.  This member can be null.
	*/
	public DefaultStmt caseDefault;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression condition, CaseStmt[] cases, DefaultStmt caseDefault)
	{
		super(c, location, endLocation, AstTag.SwitchStmt);
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
	The list of values which will cause execution to jump to this case.  In the code
	"case 1, 2, 3:" this corresponds to "1, 2, 3".  This will always be at least one element
	long.
	*/
	public CaseCond[] conditions;

	/**
	The code of the case statement.
	*/
	public Statement code;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, CaseCond[] conditions, Statement code)
	{
		super(c, location, endLocation, AstTag.CaseStmt);
		this.conditions = conditions;
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
	public Statement code;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Statement code)
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
	*/
	public this(ICompiler c, CompileLoc location)
	{
		super(c, location, location, AstTag.ContinueStmt);
	}
}

/**
This node represents a break statement.
*/
class BreakStmt : Statement
{
	/**
	*/
	public this(ICompiler c, CompileLoc location)
	{
		super(c, location, location, AstTag.BreakStmt);
	}
}

/**
This node represents a return statement.
*/
class ReturnStmt : Statement
{
	/**
	The list of expressions to return.  This array may have 0 or more elements.
	*/
	public Expression[] exprs;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression[] exprs)
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
This node represents a try-catch-finally statement.  It holds not only the try clause,
but either or both the catch and finally clauses.
*/
class TryStmt : Statement
{
	/**
	The body of code to try.
	*/
	public Statement tryBody;
	
	/**
	The variable to use in the catch block.  In the code "try{}catch(e){}", this corresponds
	to 'e'.  This member can be null, in which case there is no catch block (and therefore
	there must be a finally block).  If this member is non-null, catchBody must also be
	non-null.
	*/
	public Identifier catchVar;

	/**
	The body of the catch block.  If this member is non-null, catchVar must also be non-null.
	If this member is null, finallyBody must be non-null.
	*/
	public Statement catchBody;

	/**
	The body of the finally block.  If this member is null, catchVar and catchBody must be
	non-null.
	*/
	public Statement finallyBody;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Statement tryBody, Identifier catchVar, Statement catchBody, Statement finallyBody)
	{
		super(c, location, endLocation, AstTag.TryStmt);

		this.tryBody = tryBody;
		this.catchVar = catchVar;
		this.catchBody = catchBody;
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
	public Expression exp;

	/**
	*/
	public this(ICompiler c, CompileLoc location, Expression exp)
	{
		super(c, location, exp.endLocation, AstTag.ThrowStmt);
		this.exp = exp;
	}
}

/**
This node represents normal assignment, either single- or multi-target.
*/
class AssignStmt : Statement
{
	/**
	The list of destination expressions.  This list always has at least one element.
	This list must contain only expressions which can be LHSes.  That will be checked
	at codegen time.
	*/
	public Expression[] lhs;

	/**
	The right-hand side of the assignment.  If lhs.length > 1, this must be a multi-value
	giving expression, meaning either a function call, vararg, sliced vararg, or yield
	expression.  Otherwise, it can be any kind of expression.
	*/
	public Expression rhs;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression[] lhs, Expression rhs)
	{
		super(c, location, endLocation, AstTag.AssignStmt);
		this.lhs = lhs;
		this.rhs = rhs;
	}
	
	override void cleanup(ref Allocator alloc)
	{
		alloc.freeArray(lhs);
	}
}

/**
This node handles the common features of the reflexive assignments, as well as conditional assignment (?=).
*/
abstract class OpAssignStmt : Statement
{
	/**
	The left-hand-side of the assignment.  This may not be a constant value or '#vararg', and if
	this is a conditional assignment, it may not be 'this'.  These conditions will be checked at
	codegen.
	*/
	public Expression lhs;

	/**
	The right-hand-side of the assignment.
	*/
	public Expression rhs;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type, Expression lhs, Expression rhs)
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
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
	The left-hand-side of the assignment.  The same constraints apply here as for other
	reflexive assignments.
	*/
	public Expression lhs;

	/**
	The right-hand-side of the assignment.
	*/
	public Expression rhs;

	public Expression[] operands;
	public bool collapsed = false;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression lhs, Expression rhs)
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
	The expression to modify.  The same constraints apply as for reflexive assignments.
	*/
	public Expression exp;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression exp)
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
	The expression to modify.  The same constraints apply as for reflexive assignments.
	*/
	public Expression exp;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression exp)
	{
		super(c, location, endLocation, AstTag.DecStmt);
		this.exp = exp;
	}
}

/**
This node does not represent a grammar element, but rather a transient node type used when rewriting
the AST.  It's used to set a function's environment.
*/
class FuncEnvStmt : Statement
{
	/**
	*/
	public Identifier funcName;
	
	/**
	*/
	public Identifier envName;

	/**
	*/
	public this(ICompiler c, CompileLoc location, Identifier funcName, Identifier envName)
	{
		super(c, location, location, AstTag.FuncEnvStmt);
		this.funcName = funcName;
		this.envName = envName;
	}
}

/**
This node is an internal node inserted in function bodies if parameter type checking is enabled.
*/
class TypecheckStmt : Statement
{
	/**
	*/
	public FuncDef def;

	/**
	*/
	public this(ICompiler c, CompileLoc location, FuncDef def)
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
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type)
	{
		super(c, location, endLocation, type);
	}

	/**
	Ensure that this expression can be evaluated to nothing, i.e. that it can exist
	on its own.  Throws an exception if not.
	*/
	public void checkToNothing(ICompiler c)
	{
		if(!hasSideEffects())
			c.loneStmtException(location, "{} cannot exist on its own", niceString());
	}

	/**
	Returns whether or not this expression has side effects.  If this returns false,
	checkToNothing will throw an error.
	*/
	public bool hasSideEffects()
	{
		return false;
	}

	/**
	Ensure that this expression can give multiple return values.  If it can't, throws an
	exception.
	*/
	public void checkMultRet(ICompiler c)
	{
		if(!isMultRet())
			c.exception(location, "{} cannot be the source of a multi-target assignment", niceString());
	}

	/**
	Returns whether this expression can give multiple return values.  If this returns
	false, checkMultRet will throw an error.
	*/
	public bool isMultRet()
	{
		return false;
	}

	/**
	Ensure that this expression can be the left-hand side of an assignment.  If it can't,
	throws an exception.
	*/
	public void checkLHS(ICompiler c)
	{
		if(!isLHS())
			c.exception(location, "{} cannot be the target of an assignment", niceString());
	}

	/**
	Returns whether this expression can be the left-hand side of an assignment.  If this
	returns false, checkLHS will throw an error.
	*/
	public bool isLHS()
	{
		return false;
	}

	/**
	Returns whether this expression is a constant value.
	*/
	public bool isConstant()
	{
		return false;
	}

	/**
	Returns whether this expression is 'null'.
	*/
	public bool isNull()
	{
		return false;
	}

	/**
	Returns whether this expression is a boolean constant.
	*/
	public bool isBool()
	{
		return false;
	}

	/**
	Returns this expression as a boolean constant, if possible.  assert(false)s
	otherwise.
	*/
	public bool asBool()
	{
		assert(false);
	}

	/**
	Returns whether this expression is an integer constant.
	*/
	public bool isInt()
	{
		return false;
	}

	/**
	Returns this expression as an integer constant, if possible.  assert(false)s
	otherwise.
	*/
	public mdint asInt()
	{
		assert(false);
	}

	/**
	Returns whether this expression is a floating point constant.
	*/
	public bool isFloat()
	{
		return false;
	}

	/**
	Returns this expression as a floating point constant, if possible.  assert(false)s
	otherwise.
	*/
	public mdfloat asFloat()
	{
		assert(false);
	}

	/**
	Returns whether this expression is a character constant.
	*/
	public bool isChar()
	{
		return false;
	}

	/**
	Returns this expression as a character constant, if possible.  assert(false)s
	otherwise.
	*/
	public dchar asChar()
	{
		assert(false);
	}

	/**
	Returns whether this expression is a string constant.
	*/
	public bool isString()
	{
		return false;
	}

	/**
	Returns this expression as a string constant, if possible.  assert(false)s
	otherwise.
	*/
	public char[] asString()
	{
		assert(false);
	}

	/**
	If this expression is a constant value, returns whether this expression would evaluate
	as true according to MiniD's definition of truth.  Otherwise returns false.
	*/
	public bool isTrue()
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
	public Expression cond;
	
	/**
	The second expression, which comes between the question mark and the colon.
	*/
	public Expression op1;

	/**
	The third expression, which comes after the colon.
	*/
	public Expression op2;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression cond, Expression op1, Expression op2)
	{
		super(c, location, endLocation, AstTag.CondExp);
		this.cond = cond;
		this.op1 = op1;
		this.op2 = op2;
	}

	public override bool hasSideEffects()
	{
		return cond.hasSideEffects() || op1.hasSideEffects() || op2.hasSideEffects();
	}
}

/**
The base class for binary expressions.  Many of them share some or all of their code
generation phases, as well has having other similar properties.
*/
abstract class BinaryExp : Expression
{
	/**
	The left-hand operand.
	*/
	public Expression op1;
	
	/**
	The right-hand operand.
	*/
	public Expression op2;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type, Expression op1, Expression op2)
	{
		super(c, location, endLocation, type);
		this.op1 = op1;
		this.op2 = op2;
	}
}

private const BinExpMixin =
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

	public override bool hasSideEffects()
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

	public override bool hasSideEffects()
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type, Expression left, Expression right)
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
This class serves as a base class for comparison expressions.
*/
abstract class BaseCmpExp : BinaryExp
{
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type, Expression left, Expression right)
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
This node represents an 'in' expression.
*/
class InExp : BinaryExp
{
	mixin(BinExpMixin);
}

/**
This node represents a '!in' expression.
*/
class NotInExp : BinaryExp
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
	public Expression[] operands;
	public bool collapsed = false;

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
This class is the base class for unary expressions.  These tend to share some code
generation, as well as all having a single operand.
*/
abstract class UnExp : Expression
{
	/**
	The operand of the expression.
	*/
	public Expression op;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type, Expression operand)
	{
		super(c, location, endLocation, type);
		op = operand;
	}
}

private const UnExpMixin =
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
	
	public override bool isLHS()
	{
		return true;
	}
}

/**
This node represents the coroutine expression (coroutine a).
*/
class CoroutineExp : UnExp
{
	mixin(UnExpMixin);
}

/**
This class is the base class for postfix expressions, that is expressions which kind of
attach to the end of other expressions.  It inherits from UnExp, so that the single
operand becomes the expression to which the postfix expression becomes attached.
*/
abstract class PostfixExp : UnExp
{
	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type, Expression operand)
	{
		super(c, location, endLocation, type, operand);
	}
}

/**
This node represents dot expressions, in both the dot-ident (a.x) and dot-expression
(a.(expr)) forms.  These correspond to field access.
*/
class DotExp : PostfixExp
{
	/**
	The name.  This can be any expression, as long as it evaluates to a string.  An
	expression like "a.x" is sugar for "a.("x")", so this will be a string literal
	in that case.
	*/
	public Expression name;

	/**
	*/
	public this(ICompiler c, Expression operand, Expression name)
	{
		super(c, operand.location, name.endLocation, AstTag.DotExp, operand);
		this.name = name;
	}
	
	public override bool isLHS()
	{
		return true;
	}
}

/**
This node corresponds to the super expression (a.super).
*/
class DotSuperExp : PostfixExp
{
	public this(ICompiler c, CompileLoc endLocation, Expression operand)
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
	public Expression index;

	/**
	*/
	public this(ICompiler c, CompileLoc endLocation, Expression operand, Expression index)
	{
		super(c, operand.location, endLocation, AstTag.IndexExp, operand);
		this.index = index;
	}

	public override bool isLHS()
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
	The low index of the slice.  If no low index is given, this will be a NullExp.
	This member will therefore never be null.
	*/
	public Expression loIndex;
	
	/**
	The high index of the slice.  If no high index is given, this will be a NullExp.
	This member will therefore never be null.
	*/
	public Expression hiIndex;

	/**
	*/
	public this(ICompiler c, CompileLoc endLocation, Expression operand, Expression loIndex, Expression hiIndex)
	{
		super(c, operand.location, endLocation, AstTag.SliceExp, operand);
		this.loIndex = loIndex;
		this.hiIndex = hiIndex;
	}

	public override bool isLHS()
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
	The context to be used when calling the function.  This corresponds to 'x' in
	the expression "f(with x)".  If this member is null, a context of 'null' will
	be passed to the function.
	*/
	public Expression context;
	
	/**
	The list of arguments to be passed to the function.  This can be 0 or more elements.
	*/
	public Expression[] args;

	/**
	*/
	public this(ICompiler c, CompileLoc endLocation, Expression operand, Expression context, Expression[] args)
	{
		super(c, operand.location, endLocation, AstTag.CallExp, operand);
		this.context = context;
		this.args = args;
	}

	public override bool hasSideEffects()
	{
		return true;
	}

	public override bool isMultRet()
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
	public Expression method;

	/**
	The context to be used when calling the method.  This corresponds to 'x' in
	the expression "a.f(with x)".  If this member is null, there is no custom
	context and the context will be determined automatically.
	*/
	public Expression context;

	/**
	The list of argument to pass to the method.  This can have 0 or more elements.
	*/
	public Expression[] args;

	/**
	If this member is true, 'op' will be null (and will be interpreted as a "this").
	*/
	public bool isSuperCall;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression operand, Expression method, Expression context, Expression[] args, bool isSuperCall)
	{
		super(c, location, endLocation, AstTag.MethodCallExp, operand);
		this.method = method;
		this.context = context;
		this.args = args;
		this.isSuperCall = isSuperCall;
	}
	
	public override bool hasSideEffects()
	{
		return true;
	}

	public override bool isMultRet()
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
	public this(ICompiler c, CompileLoc location, AstTag type)
	{
		super(c, location, location, type);
	}

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag type)
	{
		super(c, location, endLocation, type);
	}
}

/**
An identifier expression.  These can refer to locals, upvalues, or globals.
*/
class IdentExp : PrimaryExp
{
	/**
	The identifier itself.
	*/
	public Identifier name;

	/**
	Create an ident exp from an identifier object.
	*/
	public this(ICompiler c, Identifier i)
	{
		super(c, i.location, AstTag.IdentExp);
		this.name = i;
	}

	public override bool isLHS()
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
	public this(ICompiler c, CompileLoc location)
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
	public this(ICompiler c, CompileLoc location)
	{
		super(c, location, AstTag.NullExp);
	}
	
	public override bool isConstant()
	{
		return true;
	}

	public override bool isTrue()
	{
		return false;
	}

	public override bool isNull()
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
	public bool value;

	/**
	*/
	public this(ICompiler c, CompileLoc location, bool value)
	{
		super(c, location, AstTag.BoolExp);
		this.value = value;
	}

	public override bool isConstant()
	{
		return true;
	}

	public override bool isTrue()
	{
		return value;
	}

	public override bool isBool()
	{
		return true;
	}

	public override bool asBool()
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
	public this(ICompiler c, CompileLoc location)
	{
		super(c, location, AstTag.VarargExp);
	}

	public bool isMultRet()
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
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation)
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
	public Expression index;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression index)
	{
		super(c, location, endLocation, AstTag.VargIndexExp);
		this.index = index;
	}

	public override bool isLHS()
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
	public Expression loIndex;
	
	/**
	The high index of the slice.
	*/
	public Expression hiIndex;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression loIndex, Expression hiIndex)
	{
		super(c, location, endLocation, AstTag.VargSliceExp);
		this.loIndex = loIndex;
		this.hiIndex = hiIndex;
	}

	public override bool isMultRet()
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
	public mdint value;

	/**
	*/
	public this(ICompiler c, CompileLoc location, mdint value)
	{
		super(c, location, AstTag.IntExp);
		this.value = value;
	}

	public override bool isConstant()
	{
		return true;
	}

	public override bool isTrue()
	{
		return (value != 0);
	}

	public override bool isInt()
	{
		return true;
	}

	public override mdint asInt()
	{
		return value;
	}

	public override mdfloat asFloat()
	{
		return cast(mdfloat)value;
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
	public mdfloat value;

	/**
	*/
	public this(ICompiler c, CompileLoc location, mdfloat value)
	{
		super(c, location, AstTag.FloatExp);
		this.value = value;
	}

	public override bool isConstant()
	{
		return true;
	}

	public override bool isTrue()
	{
		return (value != 0.0);
	}

	public override bool isFloat()
	{
		return true;
	}

	public override mdfloat asFloat()
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
	public dchar value;

	/**
	*/
	public this(ICompiler c, CompileLoc location, dchar value)
	{
		super(c, location, AstTag.CharExp);
		this.value = value;
	}

	public override bool isConstant()
	{
		return true;
	}

	public override bool isTrue()
	{
		return (value != 0);
	}

	public override bool isChar()
	{
		return true;
	}

	public override dchar asChar()
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
	public char[] value;

	/**
	*/
	public this(ICompiler c, CompileLoc location, char[] value)
	{
		super(c, location, AstTag.StringExp);
		this.value = value;
	}

	public override bool isConstant()
	{
		return true;
	}

	public override bool isTrue()
	{
		return true;
	}

	public override bool isString()
	{
		return true;
	}

	public override char[] asString()
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
	public FuncDef def;

	/**
	*/
	public this(ICompiler c, CompileLoc location, FuncDef def)
	{
		super(c, location, def.endLocation, AstTag.FuncLiteralExp);
		this.def = def;
	}
}

/**
Represents an object literal.
*/
class ObjectLiteralExp : PrimaryExp
{
	/**
	The actual "guts" of the object.
	*/
	public ObjectDef def;

	/**
	*/
	public this(ICompiler c, CompileLoc location, ObjectDef def)
	{
		super(c, location, def.endLocation, AstTag.ObjectLiteralExp);
		this.def = def;
	}
}

/**
Represents an expression inside a pair of parentheses.  Besides controlling order-of-
operations, this expression will make a multiple-return-value expression return exactly
one result instead.  Thus 'vararg' can give 0 or more values but '(vararg)' gives
exactly one (null in the case that there are no varargs).
*/
class ParenExp : PrimaryExp
{
	/**
	The parenthesized expression.
	*/
	public Expression exp;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression exp)
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
	An array of fields.  The first value in each element is the key; the second the value.
	*/
	public Field[] fields;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Field[] fields)
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
	public Expression[] values;

	protected const uint maxFields = Instruction.arraySetFields * Instruction.rtMax;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression[] values)
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
	public NamespaceDef def;

	/**
	*/
	public this(ICompiler c, CompileLoc location, NamespaceDef def)
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
	public Expression[] args;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression[] args)
	{
		super(c, location, endLocation, AstTag.YieldExp);
		this.args = args;
	}

	public bool hasSideEffects()
	{
		return true;
	}

	public bool isMultRet()
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
	Optional if comprehension that follows this.  This member may be null.
	*/
	public IfComprehension ifComp;

	/**
	Optional for comprehension that follows this.  This member may be null.
	*/
	public ForComprehension forComp;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, AstTag tag)
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
	public Identifier[] indices;
	
	/// ditto
	public Expression[] container;

	/**
	*/
	public this(ICompiler c, CompileLoc location, Identifier[] indices, Expression[] container, IfComprehension ifComp, ForComprehension forComp)
	{
		if(ifComp)
		{
			if(forComp)
				super(c, location, forComp.endLocation, AstTag.ForeachComprehension); // REACHABLE?
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
	public Identifier index;
	
	/// ditto
	public Expression lo;
	
	/// ditto
	public Expression hi;
	
	/// ditto
	public Expression step;

	/**
	*/	
	public this(ICompiler c, CompileLoc location, Identifier index, Expression lo, Expression hi, Expression step, IfComprehension ifComp, ForComprehension forComp)
	{
		if(ifComp)
		{
			if(forComp)
				super(c, location, forComp.endLocation, AstTag.ForNumComprehension); // REACHABLE?
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
	public Expression condition;

	/**
	*/
	public this(ICompiler c, CompileLoc location, Expression condition)
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
	public Expression exp;

	/**
	The root of the comprehension tree.
	*/
	public ForComprehension forComp;

	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression exp, ForComprehension forComp)
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
	The key expression.  This is the thing in the brackets at the beginning.
	*/
	public Expression key;

	/**
	The value expression.  This is the thing after the equals sign at the beginning.
	*/
	public Expression value;
	
	/**
	The root of the comprehension tree.
	*/
	public ForComprehension forComp;
	
	/**
	*/
	public this(ICompiler c, CompileLoc location, CompileLoc endLocation, Expression key, Expression value, ForComprehension forComp)
	{
		super(c, location, endLocation, AstTag.TableComprehension);

		this.key = key;
		this.value = value;
		this.forComp = forComp;
	}
}