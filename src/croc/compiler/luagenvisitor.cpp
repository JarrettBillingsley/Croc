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

FuncDef* LuaGenVisitor::visit(FuncDef* d)
{
	VISIT(d->code);
	return d;
}

Statement* LuaGenVisitor::visit(ImportStmt* s)
{
	VISIT(s->expr);
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
	VISIT_ARR(d->initializer);
	PROTECTION(d);
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
	PROTECTION(d);
	VISIT(d->def);
	COND_VISIT(d->decorator);
	return d;
}

Statement* LuaGenVisitor::visit(BlockStmt* s)
{
	VISIT_ARR(s->statements);
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
	VISIT_ARR(s->lhs);
	VISIT_ARR(s->rhs);
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
	VISIT(e->cond);
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(OrOrExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(AndAndExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(OrExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(XorExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(AndExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(EqualExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(NotEqualExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(IsExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(NotIsExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(LTExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(LEExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(GTExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(GEExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(Cmp3Exp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(ShlExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(ShrExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(UShrExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(AddExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(SubExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(CatExp* e)
{
	if(e->collapsed)
		return e;

	e->collapsed = true;

	VISIT(e->op1);
	VISIT(e->op2);

	// Collapse
	List<Expression*> tmp(c);

	if(auto l = AST_AS(CatExp, e->op1))
		tmp.add(l->operands);
	else
		tmp.add(e->op1);

	// Not needed? e->operands should be empty
	tmp.add(e->op2);
	e->operands = tmp.toArray();
	e->endLocation = e->operands[e->operands.length - 1]->endLocation;
	return e;
}

Expression* LuaGenVisitor::visit(MulExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(DivExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(ModExp* e)
{
	VISIT(e->op1);
	VISIT(e->op2);
	return e;
}

Expression* LuaGenVisitor::visit(NegExp* e)
{
	VISIT(e->op);
	return e;
}

Expression* LuaGenVisitor::visit(NotExp* e)
{
	VISIT(e->op);
	return e;
}

Expression* LuaGenVisitor::visit(ComExp* e)
{
	VISIT(e->op);
	return e;
}

Expression* LuaGenVisitor::visit(LenExp* e)
{
	VISIT(e->op);
	return e;
}

Expression* LuaGenVisitor::visit(DotExp* e)
{
	VISIT(e->op);
	VISIT(e->name);
	return e;
}

Expression* LuaGenVisitor::visit(MethodCallExp* e)
{
	COND_VISIT(e->op);
	VISIT(e->method);
	VISIT_ARR(e->args);
	return e;
}

Expression* LuaGenVisitor::visit(CallExp* e)
{
	VISIT(e->op);
	VISIT_ARR(e->args);
	return e;
}

Expression* LuaGenVisitor::visit(IndexExp* e)
{
	VISIT(e->op);
	VISIT(e->index);
	return e;
}

Expression* LuaGenVisitor::visit(VargIndexExp* e)
{
	VISIT(e->index);
	return e;
}

FuncLiteralExp* LuaGenVisitor::visit(FuncLiteralExp* e)
{
	VISIT(e->def);
	return e;
}

Expression* LuaGenVisitor::visit(ParenExp* e)
{
	VISIT(e->exp);
	return e;
}

TableCtorExp* LuaGenVisitor::visit(TableCtorExp* e)
{
	for(auto &field: e->fields)
	{
		VISIT(field.key);
		VISIT(field.value);
	}

	return e;
}

ArrayCtorExp* LuaGenVisitor::visit(ArrayCtorExp* e)
{
	VISIT_ARR(e->values);
	return e;
}

YieldExp* LuaGenVisitor::visit(YieldExp* e)
{
	VISIT_ARR(e->args);
	return e;
}