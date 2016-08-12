#include <ctype.h>
#include <functional>

#include "croc/compiler/luagenvisitor.hpp"

#define VISIT(e)               do { visit(e);                     } while(false)
#define COND_VISIT(e)          do { if(e) visit(e);               } while(false)
#define VISIT_ARR(a)           do { for(auto &x: a) visit(x);     } while(false)
#define VISIT_ARR_FIELD(a, y)  do { for(auto &x: a) visit(x.y); } while(false)
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

Identifier* LuaGenVisitor::visit(Identifier* id)
{
	mOutput.outputWord(id);
	return id;
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
	throw CompileEx("imports unimplemented", s->location);
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
	throw CompileEx("decorators unimplemented", d->location);
}

FuncDecl* LuaGenVisitor::visit(FuncDecl* d)
{
	if(d->decorator)
		throw CompileEx("decorators unimplemented", d->location);

	PROTECTION(d);

	if(d->protection == Protection::Local)
		mOutput.outputWord(d->location, "local");

	mOutput.funcName(d->def->location, d->owner, d->def->name);
	VISIT(d->def);
	return d;
}

Statement* LuaGenVisitor::visit(BlockStmt* s)
{
	mOutput.beginBraceBlock(s->location);
	VISIT_ARR(s->statements);
	mOutput.endBraceBlock(s->endLocation);
	return s;
}

Statement* LuaGenVisitor::visit(IfStmt* s)
{
	mOutput.outputWord(s->location, "if");
	VISIT(s->condition);
	mOutput.outputWord(s->condition->endLocation, "then");
	mOutput.beginControlBlock();
	VISIT(s->ifBody);
	mOutput.endControlBlock();

	if(s->elseBody)
	{
		auto eb = s->elseBody;

		while(auto ifs = AST_AS(IfStmt, eb))
		{
			mOutput.outputWord(ifs->location, "elseif");
			VISIT(ifs->condition);
			mOutput.outputWord(ifs->condition->endLocation, "then");
			mOutput.beginControlBlock();
			VISIT(ifs->ifBody);
			mOutput.endControlBlock();

			eb = ifs->elseBody;

			if(eb == nullptr)
				break;
		}

		if(eb)
		{
			mOutput.outputWord(eb->location, "else");
			mOutput.beginControlBlock();
			VISIT(eb);
			mOutput.endControlBlock();
			mOutput.outputWord(eb->endLocation, "end");
		}
	}
	else
	{
		mOutput.outputWord(s->ifBody->endLocation, "end");
	}

	return s;
}

Statement* LuaGenVisitor::visit(WhileStmt* s)
{
	mOutput.outputWord(s->location, "while");
	VISIT(s->condition);
	mOutput.outputWord(s->condition->endLocation, "do");
	mOutput.beginControlBlock();
	VISIT(s->code);
	mOutput.endControlBlock();
	mOutput.outputWord(s->code->endLocation, "end");
	return s;
}

Statement* LuaGenVisitor::visit(DoWhileStmt* s)
{
	mOutput.outputWord(s->location, "repeat");
	mOutput.beginControlBlock();
	VISIT(s->code);
	mOutput.endControlBlock();
	mOutput.outputWord(s->condition->location, "until not");
	VISIT(s->condition);
	return s;
}

Statement* LuaGenVisitor::visit(ForStmt* s)
{
	throw CompileEx("generic for unimplemented", s->location);
}

Statement* LuaGenVisitor::visit(ForNumStmt* s)
{
	mOutput.outputWord(s->location, "for");
	mOutput.outputWord(s->index);
	mOutput.outputSymbol(s->index->endLocation, " = ");
	VISIT(s->lo);
	mOutput.outputSymbol(s->lo->endLocation, ", ");
	VISIT(s->hi);
	auto intStep = AST_AS(IntExp, s->step);

	if(!intStep or intStep->value != 1)
	{
		mOutput.outputSymbol(s->hi->endLocation, ", ");
		VISIT(s->step);
	}

	mOutput.outputWord(s->step->endLocation, "do");
	mOutput.beginControlBlock();
	VISIT(s->code);
	mOutput.endControlBlock();
	mOutput.outputWord(s->code->endLocation, "end");
	return s;
}

ForeachStmt* LuaGenVisitor::visit(ForeachStmt* s)
{
	mOutput.outputWord(s->location, "for");
	visitList(s->indices);
	mOutput.outputWord(s->indices.last()->endLocation, "in");
	visitList(s->container);
	mOutput.outputWord(s->container.last()->endLocation, "do");
	mOutput.beginControlBlock();
	VISIT(s->code);
	mOutput.endControlBlock();
	mOutput.outputWord(s->code->endLocation, "end");
	return s;
}

ContinueStmt* LuaGenVisitor::visit(ContinueStmt* s)
{
	throw CompileEx("continue unimplemented", s->location);
}

BreakStmt* LuaGenVisitor::visit(BreakStmt* s)
{
	if(s->name.length)
		throw CompileEx("named break unimplemented", s->location);

	mOutput.outputWord(s->location, "break");
	return s;
}

ReturnStmt* LuaGenVisitor::visit(ReturnStmt* s)
{
	mOutput.outputWord(s->location, "return");
	visitList(s->exprs);
	return s;
}

AssignStmt* LuaGenVisitor::visit(AssignStmt* s)
{
	visitList(s->lhs);
	mOutput.outputSymbol(s->rhs[0]->location, " = ");
	visitList(s->rhs);
	return s;
}

AddAssignStmt* LuaGenVisitor::visit(AddAssignStmt* s)
{
	throw CompileEx("augmentation assignment unimplemented", s->location);
}

SubAssignStmt* LuaGenVisitor::visit(SubAssignStmt* s)
{
	throw CompileEx("augmentation assignment unimplemented", s->location);
}

MulAssignStmt* LuaGenVisitor::visit(MulAssignStmt* s)
{
	throw CompileEx("augmentation assignment unimplemented", s->location);
}

DivAssignStmt* LuaGenVisitor::visit(DivAssignStmt* s)
{
	throw CompileEx("augmentation assignment unimplemented", s->location);
}

ModAssignStmt* LuaGenVisitor::visit(ModAssignStmt* s)
{
	throw CompileEx("augmentation assignment unimplemented", s->location);
}

ShlAssignStmt* LuaGenVisitor::visit(ShlAssignStmt* s)
{
	throw CompileEx("augmentation assignment unimplemented", s->location);
}

ShrAssignStmt* LuaGenVisitor::visit(ShrAssignStmt* s)
{
	throw CompileEx("augmentation assignment unimplemented", s->location);
}

UShrAssignStmt* LuaGenVisitor::visit(UShrAssignStmt* s)
{
	throw CompileEx("augmentation assignment unimplemented", s->location);
}

XorAssignStmt* LuaGenVisitor::visit(XorAssignStmt* s)
{
	throw CompileEx("augmentation assignment unimplemented", s->location);
}

OrAssignStmt*  LuaGenVisitor::visit(OrAssignStmt* s)
{
	throw CompileEx("augmentation assignment unimplemented", s->location);
}

AndAssignStmt* LuaGenVisitor::visit(AndAssignStmt* s)
{
	throw CompileEx("augmentation assignment unimplemented", s->location);
}


Statement* LuaGenVisitor::visit(CondAssignStmt* s)
{
	throw CompileEx("augmentation assignment unimplemented", s->location);
}

IncStmt* LuaGenVisitor::visit(IncStmt* s)
{
	throw CompileEx("crements unimplemented", s->location);
}

DecStmt* LuaGenVisitor::visit(DecStmt* s)
{
	throw CompileEx("crements unimplemented", s->location);
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
	mOutput.outputWord(e->location, "select");
	mOutput.outputSymbol(e->location, "(");
	VISIT(e->index);
	mOutput.outputSymbol(e->location, ", ...)");
	return e;
}

Expression* LuaGenVisitor::visit(VargLenExp* e)
{
	mOutput.outputWord(e->location, "select('#', ...");
	mOutput.outputSymbol(e->endLocation, ")");
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
