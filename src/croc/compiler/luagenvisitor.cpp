#include <ctype.h>
#include <functional>

#include "croc/compiler/luagenvisitor.hpp"

#define VISIT(e)               do { e = visit(e);                     } while(false)
#define COND_VISIT(e)          do { if(e) e = visit(e);               } while(false)
#define VISIT_ARR(a)           do { for(auto &x: a) x = visit(x);     } while(false)
#define VISIT_ARR_FIELD(a, y)  do { for(auto &x: a) x.y = visit(x.y); } while(false)
#define PROTECTION(d)\
	do {\
		if(d->protection == Protection::Default)\
			d->protection = isTopLevel() ? Protection::Global : Protection::Local;\
	} while(false)

const char* LuaGenVisitor::getOutput()
{
	return mOutput.getOutput();
}

#define IS_ALPHA(c) (((c >= 'a') && (c <= 'z')) || ((c >= 'A') && (c <= 'Z')))
#define IS_DECIMALDIGIT(c) ((c >= '0') && (c <= '9'))
#define IS_IDENTSTART(c) (IS_ALPHA(c) || c == '_')
#define IS_IDENTCONT(c) (IS_IDENTSTART(c) || IS_DECIMALDIGIT(c))

bool LuaGenVisitor::isIdent(crocstr id)
{
	if(id.length == 0)
		return false;

	bool first = true;

	for(auto c: dcharsOf(id))
	{
		if(first)
		{
			first = false;
			if(!IS_IDENTSTART(c))
				return false;
		}
		else if(!IS_IDENTCONT(c))
			return false;
	}

	return true;
}

template<typename T>
void LuaGenVisitor::visitList(DArray<T> vals)
{
	for(uword i = 0; i < vals.length; i++)
	{
		if(i != 0)
			mOutput.nextArg(vals[i - 1]->location);

		VISIT(vals[i]);
	}
}

void LuaGenVisitor::visitArgs(CompileLoc& loc, DArray<Expression*> args)
{
	mOutput.beginArgs(loc);
	visitList(args);
	mOutput.endArgs(args.length == 0 ? loc : args.last()->location);
}

FuncDef* LuaGenVisitor::visit(FuncDef* d)
{
	mOutput.beginFunction(d->name->endLocation, d->params, d->isVararg);
	VISIT(d->code);
	mOutput.endFunction(d->endLocation);
	return d;
}

Statement* LuaGenVisitor::visit(ImportStmt* s)
{
	// VISIT(s->expr);
	throw CompileEx("imports unimplemented", s->location);
	return s;
}

ScopeStmt* LuaGenVisitor::visit(ScopeStmt* s)
{
	VISIT(s->statement);
	return s;
}

ExpressionStmt* LuaGenVisitor::visit(ExpressionStmt* s)
{
	VISIT(s->expr);
	return s;
}

VarDecl* LuaGenVisitor::visit(VarDecl* d)
{
	PROTECTION(d);

	if(d->protection == Protection::Local)
		mOutput.outputWord(d->location, "local");

	for(uword i = 0; i < d->names.length; i++)
	{
		if(i != 0)
			mOutput.outputSymbol(d->names[i - 1]->endLocation, ", ");

		mOutput.outputWord(d->names[i]);
	}

	mOutput.outputSymbol(d->names.last()->endLocation, " = ");

	visitList(d->initializer);
	return d;
}

Decorator* LuaGenVisitor::visit(Decorator* d)
{
	VISIT(d->func);
	VISIT_ARR(d->args);
	COND_VISIT(d->nextDec);
	return d;
}

FuncDecl* LuaGenVisitor::visit(FuncDecl* d)
{
	if(d->decorator)
		throw CompileEx("decorators unimplemented", d->location);

	PROTECTION(d);

	if(d->protection == Protection::Local)
		mOutput.outputWord(d->location, "local");

	mOutput.funcName(d->def->location, d->def->name);
	VISIT(d->def);
	return d;
}

Statement* LuaGenVisitor::visit(BlockStmt* s)
{
	mOutput.beginBlock(s->location);
	VISIT_ARR(s->statements);
	mOutput.endBlock(s->endLocation);
	return s;
}

Statement* LuaGenVisitor::visit(IfStmt* s)
{
	VISIT(s->condition);
	VISIT(s->ifBody);
	COND_VISIT(s->elseBody);
	return s;
}

Statement* LuaGenVisitor::visit(WhileStmt* s)
{
	VISIT(s->condition);
	VISIT(s->code);
	return s;
}

Statement* LuaGenVisitor::visit(DoWhileStmt* s)
{
	VISIT(s->code);
	VISIT(s->condition);
	return s;
}

Statement* LuaGenVisitor::visit(ForStmt* s)
{
	for(auto &i: s->init)
	{
		if(i.isDecl)
			i.decl = visit(i.decl);
		else
			i.stmt = visit(i.stmt);
	}

	COND_VISIT(s->condition);
	VISIT_ARR(s->increment);
	VISIT(s->code);
	return s;
}

Statement* LuaGenVisitor::visit(ForNumStmt* s)
{
	VISIT(s->lo);
	VISIT(s->hi);
	VISIT(s->step);
	VISIT(s->code);
	return s;
}

ForeachStmt* LuaGenVisitor::visit(ForeachStmt* s)
{
	VISIT_ARR(s->container);
	VISIT(s->code);
	return s;
}

ContinueStmt* LuaGenVisitor::visit(ContinueStmt* s)
{
	return s;
}

BreakStmt* LuaGenVisitor::visit(BreakStmt* s)
{
	return s;
}

ReturnStmt* LuaGenVisitor::visit(ReturnStmt* s)
{
	VISIT_ARR(s->exprs);
	return s;
}

AssignStmt* LuaGenVisitor::visit(AssignStmt* s)
{
	// mOutput.beginLHS();
	VISIT_ARR(s->lhs);
	// mOutput.beginRHS();
	VISIT_ARR(s->rhs);
	// mOutput.endAssignment();
	return s;
}

AddAssignStmt* LuaGenVisitor::visit(AddAssignStmt* s)
{
	VISIT(s->lhs);
	VISIT(s->rhs);
	return s;
}

SubAssignStmt* LuaGenVisitor::visit(SubAssignStmt* s)
{
	VISIT(s->lhs);
	VISIT(s->rhs);
	return s;
}

MulAssignStmt* LuaGenVisitor::visit(MulAssignStmt* s)
{
	VISIT(s->lhs);
	VISIT(s->rhs);
	return s;
}

DivAssignStmt* LuaGenVisitor::visit(DivAssignStmt* s)
{
	VISIT(s->lhs);
	VISIT(s->rhs);
	return s;
}

ModAssignStmt* LuaGenVisitor::visit(ModAssignStmt* s)
{
	VISIT(s->lhs);
	VISIT(s->rhs);
	return s;
}

ShlAssignStmt* LuaGenVisitor::visit(ShlAssignStmt* s)
{
	VISIT(s->lhs);
	VISIT(s->rhs);
	return s;
}

ShrAssignStmt* LuaGenVisitor::visit(ShrAssignStmt* s)
{
	VISIT(s->lhs);
	VISIT(s->rhs);
	return s;
}

UShrAssignStmt* LuaGenVisitor::visit(UShrAssignStmt* s)
{
	VISIT(s->lhs);
	VISIT(s->rhs);
	return s;
}

XorAssignStmt* LuaGenVisitor::visit(XorAssignStmt* s)
{
	VISIT(s->lhs);
	VISIT(s->rhs);
	return s;
}

OrAssignStmt*  LuaGenVisitor::visit(OrAssignStmt* s)
{
	VISIT(s->lhs);
	VISIT(s->rhs);
	return s;
}

AndAssignStmt* LuaGenVisitor::visit(AndAssignStmt* s)
{
	VISIT(s->lhs);
	VISIT(s->rhs);
	return s;
}


Statement* LuaGenVisitor::visit(CondAssignStmt* s)
{
	VISIT(s->lhs);
	VISIT(s->rhs);
	return s;
}

CatAssignStmt* LuaGenVisitor::visit(CatAssignStmt* s)
{
	VISIT(s->lhs);
	VISIT(s->rhs);

	if(auto catExp = AST_AS(CatExp, s->rhs))
	{
		s->operands = catExp->operands;
		catExp->operands = DArray<Expression*>();
	}
	else
	{
		List<Expression*> dummy(c);
		dummy.add(s->rhs);
		s->operands = dummy.toArray();
	}

	s->collapsed = true;
	return s;
}

IncStmt* LuaGenVisitor::visit(IncStmt* s)
{
	VISIT(s->exp);
	return s;
}

DecStmt* LuaGenVisitor::visit(DecStmt* s)
{
	VISIT(s->exp);
	return s;
}

Expression* LuaGenVisitor::visit(CondExp* e)
{
	throw CompileEx("?: unimplemented", e->location);
}

Expression* LuaGenVisitor::visit(OrOrExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " or ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(AndAndExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " and ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(OrExp* e)
{
	mOutput.outputWord(e->location, "bit.bor");
	mOutput.outputSymbol(e->location, "(");
	VISIT(e->op1);
	mOutput.outputSymbol(e->op1->location, ", ");
	VISIT(e->op2);
	mOutput.outputSymbol(e->endLocation, ")");
	return e;
}

Expression* LuaGenVisitor::visit(XorExp* e)
{
	mOutput.outputWord(e->location, "bit.bxor");
	mOutput.outputSymbol(e->location, "(");
	VISIT(e->op1);
	mOutput.outputSymbol(e->op1->location, ", ");
	VISIT(e->op2);
	mOutput.outputSymbol(e->endLocation, ")");
	return e;
}

Expression* LuaGenVisitor::visit(AndExp* e)
{
	mOutput.outputWord(e->location, "bit.band");
	mOutput.outputSymbol(e->location, "(");
	VISIT(e->op1);
	mOutput.outputSymbol(e->op1->location, ", ");
	VISIT(e->op2);
	mOutput.outputSymbol(e->endLocation, ")");
	return e;
}

Expression* LuaGenVisitor::visit(EqualExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " == ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(NotEqualExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " ~= ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(IsExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " == ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(NotIsExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " ~= ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(LTExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " < ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(LEExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " <= ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(GTExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " > ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(GEExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " >= ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(ShlExp* e)
{
	mOutput.outputWord(e->location, "bit.lshift");
	mOutput.outputSymbol(e->location, "(");
	VISIT(e->op1);
	mOutput.outputSymbol(e->op1->location, ", ");
	VISIT(e->op2);
	mOutput.outputSymbol(e->endLocation, ")");
	return e;
}

Expression* LuaGenVisitor::visit(ShrExp* e)
{
	mOutput.outputWord(e->location, "bit.rshift");
	mOutput.outputSymbol(e->location, "(");
	VISIT(e->op1);
	mOutput.outputSymbol(e->op1->location, ", ");
	VISIT(e->op2);
	mOutput.outputSymbol(e->endLocation, ")");
	return e;
}

Expression* LuaGenVisitor::visit(UShrExp* e)
{
	mOutput.outputWord(e->location, "bit.arshift");
	mOutput.outputSymbol(e->location, "(");
	VISIT(e->op1);
	mOutput.outputSymbol(e->op1->location, ", ");
	VISIT(e->op2);
	mOutput.outputSymbol(e->endLocation, ")");
	return e;
}

Expression* LuaGenVisitor::visit(AddExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " + ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(SubExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " - ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(CatExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " .. ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(MulExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " * ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(DivExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " / ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(ModExp* e)
{
	VISIT(e->op1);
	mOutput.outputSymbol(e->location, " % ");
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(NegExp* e)
{
	mOutput.outputSymbol(e->location, "-");
	VISIT(e->op);
	return e;
}

Expression* LuaGenVisitor::visit(NotExp* e)
{
	mOutput.outputWord(e->location, "not");
	VISIT(e->op);
	return e;
}

Expression* LuaGenVisitor::visit(ComExp* e)
{
	mOutput.outputWord(e->location, "bit.bnot");
	mOutput.outputSymbol(e->location, "(");
	VISIT(e->op);
	mOutput.outputSymbol(e->endLocation, ")");
	return e;
}

Expression* LuaGenVisitor::visit(LenExp* e)
{
	mOutput.outputSymbol(e->location, "#");
	VISIT(e->op);
	return e;
}

Expression* LuaGenVisitor::visit(DotExp* e)
{
	VISIT(e->op);
	auto str = AST_AS(StringExp, e->name);

	if(str && isIdent(str->value))
	{
		mOutput.outputSymbol(e->name->location, ".");
		mOutput.outputWord(str->location, str->value);
	}
	else
	{
		mOutput.outputSymbol(e->name->location, "[");
		VISIT(e->name);
		mOutput.outputSymbol(e->name->endLocation, "]");
	}
	return e;
}

Expression* LuaGenVisitor::visit(MethodCallExp* e)
{
	VISIT(e->op);
	mOutput.outputSymbol(e->method->location, ":");
	mOutput.outputWord(e->method);
	visitArgs(e->op->endLocation, e->args);
	return e;
}

Expression* LuaGenVisitor::visit(CallExp* e)
{
	VISIT(e->op);
	visitArgs(e->op->endLocation, e->args);
	return e;
}

Expression* LuaGenVisitor::visit(IndexExp* e)
{
	VISIT(e->op);
	mOutput.outputSymbol(e->index->location, "[");
	VISIT(e->index);
	mOutput.outputSymbol(e->index->endLocation, "]");
	return e;
}

Expression* LuaGenVisitor::visit(VargIndexExp* e)
{
	//TODO mOutput.checkNotLHS(e->location);
	mOutput.outputWord(e->location, "select(");
	VISIT(e->index);
	mOutput.outputSymbol(e->location, ", ...)");
	return e;
}

FuncLiteralExp* LuaGenVisitor::visit(FuncLiteralExp* e)
{
	mOutput.outputWord(e->location, "function");
	VISIT(e->def);
	return e;
}

Expression* LuaGenVisitor::visit(ParenExp* e)
{
	mOutput.outputSymbol(e->location, "(");
	VISIT(e->exp);
	mOutput.outputSymbol(e->endLocation, ")");
	return e;
}

TableCtorExp* LuaGenVisitor::visit(TableCtorExp* e)
{
	mOutput.outputSymbol(e->location, "{");
	mOutput.indent();

	for(auto &field: e->fields)
	{
		auto str = AST_AS(StringExp, field.key);

		if(str && isIdent(str->value))
			mOutput.outputWord(str->location, str->value);
		else
		{
			mOutput.outputSymbol(field.key->location, "[");
			VISIT(field.key);
			mOutput.outputSymbol(field.key->endLocation, "]");
		}

		mOutput.outputSymbol(field.key->endLocation, " = ");
		VISIT(field.value);
		mOutput.outputSymbol(field.value->endLocation, ",");
	}

	mOutput.dedent();
	mOutput.outputSymbol(e->endLocation, "}");
	return e;
}

ArrayCtorExp* LuaGenVisitor::visit(ArrayCtorExp* e)
{
	mOutput.outputSymbol(e->location, "{");
	visitList(e->values);
	mOutput.outputSymbol(e->endLocation, "}");
	return e;
}

YieldExp* LuaGenVisitor::visit(YieldExp* e)
{
	mOutput.outputWord(e->location, "coroutine.yield");
	visitArgs(e->location, e->args);
	return e;
}

Expression* LuaGenVisitor::visit(IdentExp* e)
{
	mOutput.outputWord(e->name);
	return e;
}

Expression* LuaGenVisitor::visit(ThisExp* e)
{
	mOutput.outputWord(e->location, "self");
	return e;
}

Expression* LuaGenVisitor::visit(NullExp* e)
{
	mOutput.outputWord(e->location, "nil");
	return e;
}

Expression* LuaGenVisitor::visit(BoolExp* e)
{
	mOutput.outputWord(e->location, e->value ? "true" : "false");
	return e;
}

Expression* LuaGenVisitor::visit(VarargExp* e)
{
	mOutput.outputSymbol(e->location, "...");
	return e;
}

Expression* LuaGenVisitor::visit(IntExp* e)
{
	char buf[100];

	if(e->format == NumFormat::Dec)
		snprintf(buf, 100, "%" CROC_INTEGER_FORMAT, e->value);
	else
		snprintf(buf, 100, "0x%" CROC_HEX64_FORMAT, e->value);

	mOutput.outputWord(e->location, buf);
	return e;
}

Expression* LuaGenVisitor::visit(FloatExp* e)
{
	char buf[100];
	snprintf(buf, 100, "%.21g", e->value);
	mOutput.outputWord(e->location, buf);
	return e;
}

Expression* LuaGenVisitor::visit(StringExp* e)
{
	mOutput.outputWord(e->location, "\"");

	for(dchar c: dcharsOf(e->value))
	{
		if(c > 0x7f)
			throw CompileEx("Unicode chars unimplemented", e->location);

		char buf[8];

		switch(c)
		{
			case '\r': snprintf(buf, 8, "\\r"); break;
			case '\n': snprintf(buf, 8, "\\n"); break;
			case '\t': snprintf(buf, 8, "\\t"); break;
			case '\\': snprintf(buf, 8, "\\\\"); break;
			case '\"': snprintf(buf, 8, "\\\""); break;
			case '\'': snprintf(buf, 8, "\\\'"); break;

			default:
				if(iscntrl(c))
					snprintf(buf, 8, "\\%d", c);
				else
					snprintf(buf, 8, "%c", c);
				break;
		}

		mOutput.output(buf);
	}

	mOutput.output("\"");
	return e;
}
