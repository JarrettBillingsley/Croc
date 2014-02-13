#ifndef CROC_COMPILER_AST_HPP
#define CROC_COMPILER_AST_HPP

#include "croc/apitypes.h"
#include "croc/compiler/types.hpp"
#include "croc/types.hpp"

inline void* operator new(croc::uword size, croc::Compiler& c)
{
	return c.allocNode(size);
}

#define AST_AS(T, exp) ((exp)->type == AstTag_##T ? cast(T*)(exp) : nullptr)

#define AST_LIST(X)\
	X(Identifier,           "identifier",                      AstNode)\
\
	X(FuncDef,              "function definition",             AstNode)\
\
	X(Module,               "module",                          AstNode)\
	X(Decorator,            "decorator",                       AstNode)\
\
	X(VarDecl,              "variable declaration",            Statement)\
	X(FuncDecl,             "function declaration",            Statement)\
	X(ClassDecl,            "class declaration",               Statement)\
	X(NamespaceDecl,        "namespace declaration",           Statement)\
\
	X(AssertStmt,           "assert statement",                Statement)\
	X(ImportStmt,           "import statement",                Statement)\
	X(BlockStmt,            "block statement",                 Statement)\
	X(ScopeStmt,            "scope statement",                 Statement)\
	X(ExpressionStmt,       "expression statement",            Statement)\
	X(IfStmt,               "'if' statement",                  Statement)\
	X(WhileStmt,            "'while' statement",               Statement)\
	X(DoWhileStmt,          "'do-while' statement",            Statement)\
	X(ForStmt,              "'for' statement",                 Statement)\
	X(ForNumStmt,           "numeric 'for' statement",         Statement)\
	X(ForeachStmt,          "'foreach' statement",             Statement)\
	X(SwitchStmt,           "'switch' statement",              Statement)\
	X(CaseStmt,             "'case' statement",                Statement)\
	X(DefaultStmt,          "'default' statement",             Statement)\
	X(ContinueStmt,         "'continue' statement",            Statement)\
	X(BreakStmt,            "'break' statement",               Statement)\
	X(ReturnStmt,           "'return' statement",              Statement)\
	X(TryCatchStmt,         "'try-catch' statement",           Statement)\
	X(TryFinallyStmt,       "'try-finally' statement",         Statement)\
	X(ThrowStmt,            "'throw' statement",               Statement)\
	X(ScopeActionStmt,      "'scope(...)' statement",          Statement)\
\
	X(AssignStmt,           "assignment",                      Statement)\
	X(AddAssignStmt,        "addition assignment",             Statement)\
	X(SubAssignStmt,        "subtraction assignment",          Statement)\
	X(CatAssignStmt,        "concatenation assignment",        Statement)\
	X(MulAssignStmt,        "multiplication assignment",       Statement)\
	X(DivAssignStmt,        "division assignment",             Statement)\
	X(ModAssignStmt,        "modulo assignment",               Statement)\
	X(OrAssignStmt,         "bitwise 'or' assignment",         Statement)\
	X(XorAssignStmt,        "bitwise 'xor' assignment",        Statement)\
	X(AndAssignStmt,        "bitwise 'and' assignment",        Statement)\
	X(ShlAssignStmt,        "left-shift assignment",           Statement)\
	X(ShrAssignStmt,        "right-shift assignment",          Statement)\
	X(UShrAssignStmt,       "unsigned right-shift assignment", Statement)\
	X(CondAssignStmt,       "conditional assignment",          Statement)\
	X(IncStmt,              "increment",                       Statement)\
	X(DecStmt,              "decrement",                       Statement)\
	X(TypecheckStmt,        "typecheck statement",             Statement)\
\
	X(CondExp,              "conditional expression",          Expression)\
	X(OrOrExp,              "logical 'or' expression",         Expression)\
	X(AndAndExp,            "logical 'and' expression",        Expression)\
	X(OrExp,                "bitwise 'or' expression",         Expression)\
	X(XorExp,               "bitwise 'xor' expression",        Expression)\
	X(AndExp,               "bitwise 'and' expression",        Expression)\
	X(EqualExp,             "equality expression",             Expression)\
	X(NotEqualExp,          "inequality expression",           Expression)\
	X(IsExp,                "identity expression",             Expression)\
	X(NotIsExp,             "non-identity expression",         Expression)\
	X(LTExp,                "less-than expression",            Expression)\
	X(LEExp,                "less-or-equals expression",       Expression)\
	X(GTExp,                "greater-than expression",         Expression)\
	X(GEExp,                "greater-or-equals expression",    Expression)\
	X(Cmp3Exp,              "three-way comparison expression", Expression)\
	X(InExp,                "'in' expression",                 Expression)\
	X(NotInExp,             "'!in' expression",                Expression)\
	X(ShlExp,               "left-shift expression",           Expression)\
	X(ShrExp,               "right-shift expression",          Expression)\
	X(UShrExp,              "unsigned right-shift expression", Expression)\
	X(AddExp,               "addition expression",             Expression)\
	X(SubExp,               "subtraction expression",          Expression)\
	X(CatExp,               "concatenation expression",        Expression)\
	X(MulExp,               "multiplication expression",       Expression)\
	X(DivExp,               "division expression",             Expression)\
	X(ModExp,               "modulo expression",               Expression)\
	X(NegExp,               "negation expression",             Expression)\
	X(NotExp,               "logical 'not' expression",        Expression)\
	X(ComExp,               "bitwise complement expression",   Expression)\
	X(LenExp,               "length expression",               Expression)\
	X(VargLenExp,           "vararg length expression",        Expression)\
	X(DotExp,               "dot expression",                  Expression)\
	X(DotSuperExp,          "dot-super expression",            Expression)\
	X(IndexExp,             "index expression",                Expression)\
	X(VargIndexExp,         "vararg index expression",         Expression)\
	X(SliceExp,             "slice expression",                Expression)\
	X(VargSliceExp,         "vararg slice expression",         Expression)\
	X(CallExp,              "call expression",                 Expression)\
	X(MethodCallExp,        "method call expression",          Expression)\
	X(IdentExp,             "identifier expression",           Expression)\
	X(ThisExp,              "'this' expression",               Expression)\
	X(NullExp,              "'null' expression",               Expression)\
	X(BoolExp,              "boolean constant expression",     Expression)\
	X(VarargExp,            "'vararg' expression",             Expression)\
	X(IntExp,               "integer constant expression",     Expression)\
	X(FloatExp,             "float constant expression",       Expression)\
	X(StringExp,            "string constant expression",      Expression)\
	X(FuncLiteralExp,       "function literal expression",     Expression)\
	X(ParenExp,             "parenthesized expression",        Expression)\
	X(TableCtorExp,         "table constructor expression",    Expression)\
	X(ArrayCtorExp,         "array constructor expression",    Expression)\
	X(YieldExp,             "yield expression",                Expression)\
\
	X(ForeachComprehension, "'foreach' comprehension",         AstNode)\
	X(ForNumComprehension,  "numeric 'for' comprehension",     AstNode)\
	X(IfComprehension,      "'if' comprehension",              AstNode)\
	X(ArrayComprehension,   "array comprehension",             Expression)\
	X(TableComprehension,   "table comprehension",             Expression)

namespace croc
{
	enum AstTag
	{
#define POOP(Tag, _, __) AstTag_##Tag,
		AST_LIST(POOP)
		AstTag_NUMBER
#undef POOP
	};

	extern const char* AstTagNames[AstTag_NUMBER];
	extern const char* NiceAstTagNames[AstTag_NUMBER];

	enum class Protection
	{
		Default,
		Local,
		Global
	};

	enum class ScopeAction
	{
		Exit,
		Success,
		Failure
	};

	enum class TypeMask : uint32_t
	{
		Null =      (1 << cast(uint32_t)CrocType_Null),
		Bool =      (1 << cast(uint32_t)CrocType_Bool),
		Int =       (1 << cast(uint32_t)CrocType_Int),
		Float =     (1 << cast(uint32_t)CrocType_Float),
		Nativeobj = (1 << cast(uint32_t)CrocType_Nativeobj),

		String =    (1 << cast(uint32_t)CrocType_String),
		Weakref =   (1 << cast(uint32_t)CrocType_Weakref),

		Table =     (1 << cast(uint32_t)CrocType_Table),
		Namespace = (1 << cast(uint32_t)CrocType_Namespace),
		Array =     (1 << cast(uint32_t)CrocType_Array),
		Memblock =  (1 << cast(uint32_t)CrocType_Memblock),
		Function =  (1 << cast(uint32_t)CrocType_Function),
		Funcdef =   (1 << cast(uint32_t)CrocType_Funcdef),
		Class =     (1 << cast(uint32_t)CrocType_Class),
		Instance =  (1 << cast(uint32_t)CrocType_Instance),
		Thread =    (1 << cast(uint32_t)CrocType_Thread),

		NotNull = Bool | Int | Float | Nativeobj | String | Weakref | Table | Namespace | Array | Memblock | Function |
			Funcdef | Class | Instance | Thread,
		Any = Null | NotNull
	};

	struct CaseStmt;
	struct Decorator;
	struct DefaultStmt;
	struct Expression;
	struct ForComprehension;
	struct FuncLiteralExp;
	struct IdentExp;
	struct Identifier;
	struct IfComprehension;
	struct Statement;
	struct VarDecl;

	struct FuncParam
	{
		Identifier* name;
		uint32_t typeMask;
		DArray<Expression*> classTypes;
		Expression* customConstraint;
		Expression* defValue;
		const char* typeString;
		const char* valueString;

		FuncParam() :
			name(),
			typeMask(cast(uint32_t)TypeMask::Any),
			classTypes(),
			customConstraint(),
			defValue(),
			typeString(),
			valueString()
		{}

		FuncParam(Identifier* name) :
			name(name),
			typeMask(cast(uint32_t)TypeMask::Any),
			classTypes(),
			customConstraint(),
			defValue(),
			typeString(),
			valueString()
		{}
	};

	struct ClassField
	{
		const char* name;
		Expression* initializer;
		FuncLiteralExp* func;
		bool isOverride;
		const char* docs;
		CompileLoc docsLoc;

		ClassField() :
			name(),
			initializer(),
			func(),
			isOverride(),
			docs(),
			docsLoc()
		{}

		ClassField(const char* name, Expression* initializer, FuncLiteralExp* func, bool isOverride) :
			name(name),
			initializer(initializer),
			func(func),
			isOverride(isOverride),
			docs(),
			docsLoc()
		{}
	};

	struct NamespaceField
	{
		const char* name;
		Expression* initializer;
		FuncLiteralExp* func;
		const char* docs;
		CompileLoc docsLoc;

		NamespaceField() :
			name(),
			initializer(),
			func(),
			docs(),
			docsLoc()
		{}

		NamespaceField(const char* name, Expression* initializer, FuncLiteralExp* func) :
			name(name),
			initializer(initializer),
			func(func),
			docs(),
			docsLoc()
		{}
	};

	struct ForStmtInit
	{
		bool isDecl;

		union
		{
			Statement* stmt;
			VarDecl* decl;
		};
	};

	struct CaseCond
	{
		Expression* exp;
		uint32_t dynJump;

		CaseCond() :
			exp(),
			dynJump()
		{}

		CaseCond(Expression* exp) :
			exp(exp),
			dynJump()
		{}
	};

	struct CatchClause
	{
		Identifier* catchVar;
		DArray<Expression*> exTypes;
		Statement* catchBody;

		CatchClause() :
			catchVar(),
			exTypes(),
			catchBody()
		{}

		CatchClause(Identifier* catchVar, DArray<Expression*> exTypes, Statement* catchBody) :
			catchVar(catchVar),
			exTypes(exTypes),
			catchBody(catchBody)
		{}
	};

	struct TableCtorField
	{
		Expression* key;
		Expression* value;

		TableCtorField() :
			key(),
			value()
		{}

		TableCtorField(Expression* key, Expression* value) :
			key(key),
			value(value)
		{}
	};

	struct AstNode
	{
		CompileLoc location;
		CompileLoc endLocation;
		AstTag type;

		AstNode(CompileLoc location, CompileLoc endLocation, AstTag type) :
			location(location),
			endLocation(endLocation),
			type(type)
		{}

		inline const char* toString()   { return AstTagNames[type];     }
		inline const char* niceString() { return NiceAstTagNames[type]; }
	};

	struct Statement : public AstNode
	{
		Statement(CompileLoc location, CompileLoc endLocation, AstTag type) :
			AstNode(location, endLocation, type)
		{}
	};

	struct OpAssignStmt : public Statement
	{
		Expression* lhs;
		Expression* rhs;

		OpAssignStmt(CompileLoc location, CompileLoc endLocation, AstTag type, Expression* lhs, Expression* rhs) :
			Statement(location, endLocation, type),
			lhs(lhs),
			rhs(rhs)
		{}
	};

	struct Expression : public AstNode
	{
		const char* sourceStr;

		Expression(CompileLoc location, CompileLoc endLocation, AstTag type) :
			AstNode(location, endLocation, type)
		{}

		inline void checkToNothing(Compiler& c)
		{
			if(!hasSideEffects())
				c.loneStmtException(location, "%s cannot exist on its own", niceString());
		}

		inline void checkMultRet(Compiler& c)
		{
			if(!isMultRet())
				c.semException(location, "%s cannot be the source of a multi-target assignment", niceString());
		}

		inline void checkLHS(Compiler& c)
		{
			if(!isLHS())
				c.semException(location, "%s cannot be the target of an assignment", niceString());
		}

		bool hasSideEffects();
		bool isMultRet();
		bool isLHS();
		bool isConstant();
		bool isTrue();
		bool isNull();
		bool isBool();
		bool isInt();
		bool isFloat();
		bool isNum();
		bool isString();
		bool asBool();
		crocint asInt();
		crocfloat asFloat();
		const char* asString();
	};

	struct BinaryExp : public Expression
	{
		Expression* op1;
		Expression* op2;

		BinaryExp(CompileLoc location, CompileLoc endLocation, AstTag type, Expression* op1, Expression* op2) :
			Expression(location, endLocation, type),
			op1(op1),
			op2(op2)
		{}
	};

	struct UnExp : public Expression
	{
		Expression* op;

		UnExp(CompileLoc location, CompileLoc endLocation, AstTag type, Expression* op) :
			Expression(location, endLocation, type),
			op(op)
		{}
	};

	struct PostfixExp : public UnExp
	{
		PostfixExp(CompileLoc location, CompileLoc endLocation, AstTag type, Expression* op) :
			UnExp(location, endLocation, type, op)
		{}
	};

	struct PrimaryExp : public Expression
	{
		PrimaryExp(CompileLoc location, AstTag type) :
			Expression(location, location, type)
		{}

		PrimaryExp(CompileLoc location, CompileLoc endLocation, AstTag type) :
			Expression(location, endLocation, type)
		{}
	};

	struct ForComprehension : public AstNode
	{
		IfComprehension* ifComp;
		ForComprehension* forComp;

		ForComprehension(CompileLoc location, CompileLoc endLocation, AstTag type, IfComprehension* ifComp,
			ForComprehension* forComp) :
			AstNode(location, endLocation, type),
			ifComp(ifComp),
			forComp(forComp)
		{}
	};

	struct Identifier : public AstNode
	{
		const char* name;

		Identifier(CompileLoc location, const char* name) :
			AstNode(location, location, AstTag_Identifier),
			name(name)
		{}
	};

	struct FuncDef : public AstNode
	{
		Identifier* name;
		DArray<FuncParam> params;
		bool isVararg;
		Statement* code;
		const char* docs;
		CompileLoc docsLoc;

		FuncDef(CompileLoc location, Identifier* name, DArray<FuncParam> params, bool isVararg, Statement* code) :
			AstNode(location, code->endLocation, AstTag_FuncDef),
			name(name),
			params(params),
			isVararg(isVararg),
			code(code)
		{}
	};

	struct Module : public AstNode
	{
		const char* name;
		Statement* statements;
		Decorator* decorator;
		const char* docs;
		CompileLoc docsLoc;

		Module(CompileLoc location, CompileLoc endLocation, const char* name, Statement* statements,
			Decorator* decorator) :
			AstNode(location, endLocation, AstTag_Module),
			name(name),
			statements(statements),
			decorator(decorator)
		{}
	};

	struct VarDecl : public Statement
	{
		Protection protection;
		DArray<Identifier*> names;
		DArray<Expression*> initializer;
		const char* docs;
		CompileLoc docsLoc;

		VarDecl(CompileLoc location, CompileLoc endLocation, Protection protection, DArray<Identifier*> names,
			DArray<Expression*> initializer) :
			Statement(location, endLocation, AstTag_VarDecl),
			protection(protection),
			names(names),
			initializer(initializer)
		{}
	};

	struct Decorator : public AstNode
	{
		Expression* func;
		Expression* context;
		DArray<Expression*> args;
		Decorator* nextDec;

		Decorator(CompileLoc location, CompileLoc endLocation, Expression* func, Expression* context,
			DArray<Expression*> args, Decorator* nextDec) :
			AstNode(location, endLocation, AstTag_Decorator),
			func(func),
			context(context),
			args(args),
			nextDec(nextDec)
		{}
	};

	struct FuncDecl : public Statement
	{
		Protection protection;
		FuncDef* def;
		Decorator* decorator;

		FuncDecl(CompileLoc location, Protection protection, FuncDef* def, Decorator* decorator) :
			Statement(location, def->endLocation, AstTag_FuncDecl),
			protection(protection),
			def(def),
			decorator(decorator)
		{}
	};

	struct ClassDecl : public Statement
	{
		Protection protection;
		Decorator* decorator;
		Identifier* name;
		DArray<Expression*> baseClasses;
		DArray<ClassField> fields;
		const char* docs;
		CompileLoc docsLoc;

		ClassDecl(CompileLoc location, CompileLoc endLocation, Protection protection, Decorator* decorator,
			Identifier* name, DArray<Expression*> baseClasses, DArray<ClassField> fields) :
			Statement(location, endLocation, AstTag_ClassDecl),
			protection(protection),
			decorator(decorator),
			name(name),
			baseClasses(baseClasses),
			fields(fields)
		{}
	};

	struct NamespaceDecl : public Statement
	{
		Protection protection;
		Decorator* decorator;
		Identifier* name;
		Expression* parent;
		DArray<NamespaceField> fields;
		const char* docs;
		CompileLoc docsLoc;

		NamespaceDecl(CompileLoc location, CompileLoc endLocation, Protection protection, Decorator* decorator,
			Identifier* name, Expression* parent, DArray<NamespaceField> fields) :
			Statement(location, endLocation, AstTag_NamespaceDecl),
			protection(protection),
			decorator(decorator),
			name(name),
			parent(parent),
			fields(fields)
		{}
	};

	struct AssertStmt : public Statement
	{
		Expression* cond;
		Expression* msg;

		AssertStmt(CompileLoc location, CompileLoc endLocation, Expression* cond, Expression* msg = nullptr) :
			Statement(location, endLocation, AstTag_AssertStmt),
			cond(cond),
			msg(msg)
		{}
	};

	struct ImportStmt : public Statement
	{
		Identifier* importName;
		Expression* expr;
		DArray<Identifier*> symbols;
		DArray<Identifier*> symbolNames;

		ImportStmt(CompileLoc location, CompileLoc endLocation, Identifier* importName, Expression* expr,
			DArray<Identifier*> symbols, DArray<Identifier*> symbolNames) :
			Statement(location, endLocation, AstTag_ImportStmt),
			importName(importName),
			expr(expr),
			symbols(symbols),
			symbolNames(symbolNames)
		{}
	};

	struct BlockStmt : public Statement
	{
		DArray<Statement*> statements;

		BlockStmt(CompileLoc location, CompileLoc endLocation, DArray<Statement*> statements) :
			Statement(location, endLocation, AstTag_BlockStmt),
			statements(statements)
		{}
	};

	struct ScopeStmt : public Statement
	{
		Statement* statement;

		ScopeStmt(Statement* statement) :
			Statement(statement->location, statement->endLocation, AstTag_ScopeStmt),
			statement(statement)
		{}
	};

	struct ExpressionStmt : public Statement
	{
		Expression* expr;

		ExpressionStmt(CompileLoc location, CompileLoc endLocation, Expression* expr) :
			Statement(location, endLocation, AstTag_ExpressionStmt),
			expr(expr)
		{}

		ExpressionStmt(Expression* expr) :
			Statement(expr->location, expr->endLocation, AstTag_ExpressionStmt),
			expr(expr)
		{}
	};

	struct IfStmt : public Statement
	{
		IdentExp* condVar;
		Expression* condition;
		Statement* ifBody;
		Statement* elseBody;

		IfStmt(CompileLoc location, CompileLoc endLocation, IdentExp* condVar, Expression* condition, Statement* ifBody,
			Statement* elseBody) :
			Statement(location, endLocation, AstTag_IfStmt),
			condVar(condVar),
			condition(condition),
			ifBody(ifBody),
			elseBody(elseBody)
		{}
	};

	struct WhileStmt : public Statement
	{
		const char* name;
		IdentExp* condVar;
		Expression* condition;
		Statement* code;

		WhileStmt(CompileLoc location, const char* name, IdentExp* condVar, Expression* condition, Statement* code) :
			Statement(location, code->endLocation, AstTag_WhileStmt),
			name(name),
			condVar(condVar),
			condition(condition),
			code(code)
		{}
	};

	struct DoWhileStmt : public Statement
	{
		const char* name;
		Statement* code;
		Expression* condition;

		DoWhileStmt(CompileLoc location, CompileLoc endLocation, const char* name, Statement* code,
			Expression* condition):
			Statement(location, endLocation, AstTag_DoWhileStmt),
			name(name),
			code(code),
			condition(condition)
		{}
	};

	struct ForStmt : public Statement
	{
		const char* name;
		DArray<ForStmtInit> init;
		Expression* condition;
		DArray<Statement*> increment;
		Statement* code;

		ForStmt(CompileLoc location, const char* name, DArray<ForStmtInit> init, Expression* cond,
			DArray<Statement*> inc, Statement* code) :
			Statement(location, endLocation, AstTag_ForStmt),
			name(name),
			init(init),
			condition(cond),
			increment(inc),
			code(code)
		{}
	};

	struct ForNumStmt : public Statement
	{
		const char* name;
		Identifier* index;
		Expression* lo;
		Expression* hi;
		Expression* step;
		Statement* code;

		ForNumStmt(CompileLoc location, const char* name, Identifier* index, Expression* lo, Expression* hi,
			Expression* step, Statement* code) :
			Statement(location, code->endLocation, AstTag_ForNumStmt),
			name(name),
			index(index),
			lo(lo),
			hi(hi),
			step(step),
			code(code)
		{}
	};

	struct ForeachStmt : public Statement
	{
		const char* name;
		DArray<Identifier*> indices;
		DArray<Expression*> container;
		Statement* code;

		ForeachStmt(CompileLoc location, const char* name, DArray<Identifier*> indices, DArray<Expression*> container,
			Statement* code) :
			Statement(location, code->endLocation, AstTag_ForeachStmt),
			name(name),
			indices(indices),
			container(container),
			code(code)
		{}
	};

	struct SwitchStmt : public Statement
	{
		const char* name;
		Expression* condition;
		DArray<CaseStmt*> cases;
		DefaultStmt* caseDefault;

		SwitchStmt(CompileLoc location, CompileLoc endLocation, const char* name, Expression* condition,
			DArray<CaseStmt*> cases, DefaultStmt* caseDefault) :
			Statement(location, endLocation, AstTag_SwitchStmt),
			name(name),
			condition(condition),
			cases(cases),
			caseDefault(caseDefault)
		{}
	};

	struct CaseStmt : public Statement
	{
		DArray<CaseCond> conditions;
		Expression* highRange;
		Statement* code;

		CaseStmt(CompileLoc location, CompileLoc endLocation, DArray<CaseCond> conditions, Expression* highRange,
			Statement* code) :
			Statement(location, endLocation, AstTag_CaseStmt),
			conditions(conditions),
			highRange(highRange),
			code(code)
		{}
	};

	struct DefaultStmt : public Statement
	{
		Statement* code;

		DefaultStmt(CompileLoc location, CompileLoc endLocation, Statement* code) :
			Statement(location, endLocation, AstTag_DefaultStmt),
			code(code)
		{}
	};

	struct ContinueStmt : public Statement
	{
		const char* name;

		ContinueStmt(CompileLoc location, const char* name) :
			Statement(location, location, AstTag_ContinueStmt),
			name(name)
		{}
	};

	struct BreakStmt : public Statement
	{
		const char* name;

		BreakStmt(CompileLoc location, const char* name) :
			Statement(location, location, AstTag_BreakStmt),
			name(name)
		{}
	};

	struct ReturnStmt : public Statement
	{
		DArray<Expression*> exprs;

		ReturnStmt(CompileLoc location, CompileLoc endLocation, DArray<Expression*> exprs) :
			Statement(location, endLocation, AstTag_ReturnStmt),
			exprs(exprs)
		{}
	};

	struct TryCatchStmt : public Statement
	{
		Statement* tryBody;
		DArray<CatchClause> catches;
		Identifier* hiddenCatchVar;
		Statement* transformedCatch;

		TryCatchStmt(CompileLoc location, CompileLoc endLocation, Statement* tryBody, DArray<CatchClause> catches) :
			Statement(location, endLocation, AstTag_TryCatchStmt),
			tryBody(tryBody),
			catches(catches)
		{}
	};

	struct TryFinallyStmt : public Statement
	{
		Statement* tryBody;
		Statement* finallyBody;

		TryFinallyStmt(CompileLoc location, CompileLoc endLocation, Statement* tryBody, Statement* finallyBody) :
			Statement(location, endLocation, AstTag_TryFinallyStmt),
			tryBody(tryBody),
			finallyBody(finallyBody)
		{}
	};

	struct ThrowStmt : public Statement
	{
		Expression* exp;
		bool rethrowing;

		ThrowStmt(CompileLoc location, Expression* exp, bool rethrowing = false) :
			Statement(location, exp->endLocation, AstTag_ThrowStmt),
			exp(exp),
			rethrowing(rethrowing)
		{}
	};

	struct ScopeActionStmt : public Statement
	{
		ScopeAction action;
		Statement* stmt;

		ScopeActionStmt(CompileLoc location, ScopeAction action, Statement* stmt) :
			Statement(location, stmt->endLocation, AstTag_ScopeActionStmt),
			action(action),
			stmt(stmt)
		{}
	};

	struct AssignStmt : public Statement
	{
		DArray<Expression*> lhs;
		DArray<Expression*> rhs;

		AssignStmt(CompileLoc location, CompileLoc endLocation, DArray<Expression*> lhs, DArray<Expression*> rhs) :
			Statement(location, endLocation, AstTag_AssignStmt),
			lhs(lhs),
			rhs(rhs)
		{}
	};

	#define OPASSIGNSTMTCTOR(Tag)\
		Tag(CompileLoc location, CompileLoc endLocation, Expression* lhs, Expression* rhs) :\
			OpAssignStmt(location, endLocation, AstTag_##Tag, lhs, rhs)\
		{}

	struct AddAssignStmt  : public OpAssignStmt { OPASSIGNSTMTCTOR(AddAssignStmt)  };
	struct SubAssignStmt  : public OpAssignStmt { OPASSIGNSTMTCTOR(SubAssignStmt)  };
	struct MulAssignStmt  : public OpAssignStmt { OPASSIGNSTMTCTOR(MulAssignStmt)  };
	struct DivAssignStmt  : public OpAssignStmt { OPASSIGNSTMTCTOR(DivAssignStmt)  };
	struct ModAssignStmt  : public OpAssignStmt { OPASSIGNSTMTCTOR(ModAssignStmt)  };
	struct OrAssignStmt   : public OpAssignStmt { OPASSIGNSTMTCTOR(OrAssignStmt)   };
	struct XorAssignStmt  : public OpAssignStmt { OPASSIGNSTMTCTOR(XorAssignStmt)  };
	struct AndAssignStmt  : public OpAssignStmt { OPASSIGNSTMTCTOR(AndAssignStmt)  };
	struct ShlAssignStmt  : public OpAssignStmt { OPASSIGNSTMTCTOR(ShlAssignStmt)  };
	struct ShrAssignStmt  : public OpAssignStmt { OPASSIGNSTMTCTOR(ShrAssignStmt)  };
	struct UShrAssignStmt : public OpAssignStmt { OPASSIGNSTMTCTOR(UShrAssignStmt) };
	struct CondAssignStmt : public OpAssignStmt { OPASSIGNSTMTCTOR(CondAssignStmt) };

	struct CatAssignStmt : public Statement
	{
		Expression* lhs;
		Expression* rhs;
		DArray<Expression*> operands;
		bool collapsed = false;

		CatAssignStmt(CompileLoc location, CompileLoc endLocation, Expression* lhs, Expression* rhs) :
			Statement(location, endLocation, AstTag_CatAssignStmt),
			lhs(lhs),
			rhs(rhs)
		{}
	};

	struct IncStmt : public Statement
	{
		Expression* exp;

		IncStmt(CompileLoc location, CompileLoc endLocation, Expression* exp) :
			Statement(location, endLocation, AstTag_IncStmt),
			exp(exp)
		{}
	};

	struct DecStmt : public Statement
	{
		Expression* exp;

		DecStmt(CompileLoc location, CompileLoc endLocation, Expression* exp) :
			Statement(location, endLocation, AstTag_DecStmt),
			exp(exp)
		{}
	};

	struct TypecheckStmt : public Statement
	{
		FuncDef* def;

		TypecheckStmt(CompileLoc location, FuncDef* def) :
			Statement(location, location, AstTag_TypecheckStmt),
			def(def)
		{}
	};

	struct CondExp : public Expression
	{
		Expression* cond;
		Expression* op1;
		Expression* op2;

		CondExp(CompileLoc location, CompileLoc endLocation, Expression* cond, Expression* op1, Expression* op2) :
			Expression(location, endLocation, AstTag_CondExp),
			cond(cond),
			op1(op1),
			op2(op2)
		{}

	};

	#define BINEXPCTOR(Tag)\
		Tag(CompileLoc location, CompileLoc endLocation, Expression* left, Expression* right) :\
			BinaryExp(location, endLocation, AstTag_##Tag, left, right)\
		{}

	struct OrOrExp     : public BinaryExp { BINEXPCTOR(OrOrExp)     };
	struct AndAndExp   : public BinaryExp { BINEXPCTOR(AndAndExp)   };

	struct OrExp       : public BinaryExp { BINEXPCTOR(OrExp)       };
	struct XorExp      : public BinaryExp { BINEXPCTOR(XorExp)      };
	struct AndExp      : public BinaryExp { BINEXPCTOR(AndExp)      };
	struct Cmp3Exp     : public BinaryExp { BINEXPCTOR(Cmp3Exp)     };
	struct ShlExp      : public BinaryExp { BINEXPCTOR(ShlExp)      };
	struct ShrExp      : public BinaryExp { BINEXPCTOR(ShrExp)      };
	struct UShrExp     : public BinaryExp { BINEXPCTOR(UShrExp)     };
	struct AddExp      : public BinaryExp { BINEXPCTOR(AddExp)      };
	struct SubExp      : public BinaryExp { BINEXPCTOR(SubExp)      };
	struct MulExp      : public BinaryExp { BINEXPCTOR(MulExp)      };
	struct DivExp      : public BinaryExp { BINEXPCTOR(DivExp)      };
	struct ModExp      : public BinaryExp { BINEXPCTOR(ModExp)      };

	struct EqualExp    : public BinaryExp { BINEXPCTOR(EqualExp)    };
	struct NotEqualExp : public BinaryExp { BINEXPCTOR(NotEqualExp) };
	struct IsExp       : public BinaryExp { BINEXPCTOR(IsExp)       };
	struct NotIsExp    : public BinaryExp { BINEXPCTOR(NotIsExp)    };
	struct InExp       : public BinaryExp { BINEXPCTOR(InExp)       };
	struct NotInExp    : public BinaryExp { BINEXPCTOR(NotInExp)    };

	struct LTExp       : public BinaryExp { BINEXPCTOR(LTExp)       };
	struct LEExp       : public BinaryExp { BINEXPCTOR(LEExp)       };
	struct GTExp       : public BinaryExp { BINEXPCTOR(GTExp)       };
	struct GEExp       : public BinaryExp { BINEXPCTOR(GEExp)       };

	struct CatExp : public BinaryExp
	{
		DArray<Expression*> operands;
		bool collapsed = false;

		CatExp(CompileLoc location, CompileLoc endLocation, Expression* left, Expression* right) :
			BinaryExp(location, endLocation, AstTag_CatExp, left, right),
			operands(),
			collapsed(false)
		{}
	};

	#define UNEXPCTOR(Tag)\
		Tag(CompileLoc location, Expression* op) :\
			UnExp(location, op->endLocation, AstTag_##Tag, op)\
		{}

	struct NegExp : public UnExp { UNEXPCTOR(NegExp) };
	struct NotExp : public UnExp { UNEXPCTOR(NotExp) };
	struct ComExp : public UnExp { UNEXPCTOR(ComExp) };

	struct LenExp : public UnExp
	{
		UNEXPCTOR(LenExp)
	};

	struct DotExp : public PostfixExp
	{
		Expression* name;

		DotExp(Expression* op, Expression* name) :
			PostfixExp(op->location, name->endLocation, AstTag_DotExp, op),
			name(name)
		{}
	};

	struct DotSuperExp : public PostfixExp
	{
		DotSuperExp(CompileLoc location, Expression* op) :
			PostfixExp(location, op->endLocation, AstTag_DotSuperExp, op)
		{}
	};

	struct IndexExp : public PostfixExp
	{
		Expression* index;

		IndexExp(CompileLoc endLocation, Expression* op, Expression* index) :
			PostfixExp(op->location, endLocation, AstTag_IndexExp, op),
			index(index)
		{}
	};

	struct SliceExp : public PostfixExp
	{
		Expression* loIndex;
		Expression* hiIndex;

		SliceExp(CompileLoc endLocation, Expression* op, Expression* loIndex, Expression* hiIndex) :
			PostfixExp(op->location, endLocation, AstTag_SliceExp, op),
			loIndex(loIndex),
			hiIndex(hiIndex)
		{}
	};

	struct CallExp : public PostfixExp
	{
		Expression* context;
		DArray<Expression*> args;

		CallExp(CompileLoc endLocation, Expression* op, Expression* context, DArray<Expression*> args) :
			PostfixExp(op->location, endLocation, AstTag_CallExp, op),
			context(context),
			args(args)
		{}
	};

	struct MethodCallExp : public PostfixExp
	{
		Expression* method;
		DArray<Expression*> args;

		MethodCallExp(CompileLoc location, CompileLoc endLocation, Expression* op, Expression* method,
			DArray<Expression*> args) :
			PostfixExp(location, endLocation, AstTag_MethodCallExp, op),
			method(method),
			args(args)
		{}
	};

	struct IdentExp : public PrimaryExp
	{
		Identifier* name;

		IdentExp(Identifier* name) :
			PrimaryExp(name->location, AstTag_IdentExp),
			name(name)
		{}
	};

	struct ThisExp : public PrimaryExp
	{
		ThisExp(CompileLoc location) :
			PrimaryExp(location, AstTag_ThisExp)
		{}
	};

	struct NullExp : public PrimaryExp
	{
		NullExp(CompileLoc location) :
			PrimaryExp(location, AstTag_NullExp)
		{}
	};

	struct BoolExp : public PrimaryExp
	{
		bool value;

		BoolExp(CompileLoc location, bool value) :
			PrimaryExp(location, AstTag_BoolExp),
			value(value)
		{}
	};

	struct VarargExp : public PrimaryExp
	{
		VarargExp(CompileLoc location) :
			PrimaryExp(location, AstTag_VarargExp)
		{}
	};

	struct VargLenExp : public PrimaryExp
	{
		VargLenExp(CompileLoc location, CompileLoc endLocation) :
			PrimaryExp(location, endLocation, AstTag_VargLenExp)
		{}
	};

	struct VargIndexExp : public PrimaryExp
	{
		Expression* index;

		VargIndexExp(CompileLoc location, CompileLoc endLocation, Expression* index) :
			PrimaryExp(location, endLocation, AstTag_VargIndexExp),
			index(index)
		{}
	};

	struct VargSliceExp : public PrimaryExp
	{
		Expression* loIndex;
		Expression* hiIndex;

		VargSliceExp(CompileLoc location, CompileLoc endLocation, Expression* loIndex, Expression* hiIndex) :
			PrimaryExp(location, endLocation, AstTag_VargSliceExp),
			loIndex(loIndex),
			hiIndex(hiIndex)
		{}
	};

	struct IntExp : public PrimaryExp
	{
		crocint value;

		IntExp(CompileLoc location, crocint value) :
			PrimaryExp(location, AstTag_IntExp),
			value(value)
		{}
	};

	struct FloatExp : public PrimaryExp
	{
		crocfloat value;

		FloatExp(CompileLoc location, crocfloat value) :
			PrimaryExp(location, AstTag_FloatExp),
			value(value)
		{}
	};

	struct StringExp : public PrimaryExp
	{
		const char* value;

		StringExp(CompileLoc location, const char* value) :
			PrimaryExp(location, AstTag_StringExp),
			value(value)
		{}
	};

	struct FuncLiteralExp : public PrimaryExp
	{
		FuncDef* def;

		FuncLiteralExp(CompileLoc location, FuncDef* def) :
			PrimaryExp(location, def->endLocation, AstTag_FuncLiteralExp),
			def(def)
		{}
	};

	struct ParenExp : public PrimaryExp
	{
		Expression* exp;

		ParenExp(CompileLoc location, CompileLoc endLocation, Expression* exp) :
			PrimaryExp(location, endLocation, AstTag_ParenExp),
			exp(exp)
		{}
	};

	struct TableCtorExp : public PrimaryExp
	{
		DArray<TableCtorField> fields;

		TableCtorExp(CompileLoc location, CompileLoc endLocation, DArray<TableCtorField> fields) :
			PrimaryExp(location, endLocation, AstTag_TableCtorExp),
			fields(fields)
		{}
	};

	struct ArrayCtorExp : public PrimaryExp
	{
		DArray<Expression*> values;

		ArrayCtorExp(CompileLoc location, CompileLoc endLocation, DArray<Expression*> values) :
			PrimaryExp(location, endLocation, AstTag_ArrayCtorExp),
			values(values)
		{}
	};

	struct YieldExp : public PrimaryExp
	{
		DArray<Expression*> args;

		YieldExp(CompileLoc location, CompileLoc endLocation, DArray<Expression*> args) :
			PrimaryExp(location, endLocation, AstTag_YieldExp),
			args(args)
		{}
	};

	struct IfComprehension : public AstNode
	{
		Expression* condition;

		IfComprehension(CompileLoc location, Expression* condition) :
			AstNode(location, condition->endLocation, AstTag_IfComprehension),
			condition(condition)
		{}
	};

	struct ForeachComprehension : public ForComprehension
	{
		DArray<Identifier*> indices;
		DArray<Expression*> container;

		ForeachComprehension(CompileLoc location, DArray<Identifier*> indices, DArray<Expression*> container,
			IfComprehension* ifComp, ForComprehension* forComp) :
			ForComprehension(location,
				forComp ?
					forComp->endLocation :
				ifComp ?
					ifComp->endLocation :
				container[container.length - 1]->endLocation,
				AstTag_ForeachComprehension, ifComp, forComp),
			indices(indices),
			container(container)
		{}
	};

	struct ForNumComprehension : public ForComprehension
	{
		Identifier* index;
		Expression* lo;
		Expression* hi;
		Expression* step;

		ForNumComprehension(CompileLoc location, Identifier* index, Expression* lo, Expression* hi, Expression* step,
			IfComprehension* ifComp, ForComprehension* forComp) :
			ForComprehension(location,
				forComp ?
					forComp->endLocation :
				ifComp ?
					ifComp->endLocation :
				step->endLocation,
				AstTag_ForNumComprehension, ifComp, forComp),
			index(index),
			lo(lo),
			hi(hi),
			step(step)
		{}
	};

	struct ArrayComprehension : public PrimaryExp
	{
		Expression* exp;
		ForComprehension* forComp;

		ArrayComprehension(CompileLoc location, CompileLoc endLocation, Expression* exp, ForComprehension* forComp) :
			PrimaryExp(location, endLocation, AstTag_ArrayComprehension),
			exp(exp),
			forComp(forComp)
		{}
	};

	struct TableComprehension : public PrimaryExp
	{
		Expression* key;
		Expression* value;
		ForComprehension* forComp;

		TableComprehension(CompileLoc location, CompileLoc endLocation, Expression* key, Expression* value,
			ForComprehension* forComp) :
			PrimaryExp(location, endLocation, AstTag_TableComprehension),
			key(key),
			value(value),
			forComp(forComp)
		{}
	};
}

#endif