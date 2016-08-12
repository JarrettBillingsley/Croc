#ifndef CROC_COMPILER_LUAGENVISITOR_HPP
#define CROC_COMPILER_LUAGENVISITOR_HPP

#include <functional>

#include "croc/compiler/astvisitor.hpp"
#include "croc/compiler/luaoutput.hpp"
#include "croc/compiler/types.hpp"

class LuaGenVisitor : public IdentityVisitor
{
private:
	uword mDummyNameCounter = 0;
	LuaOutput mOutput;

public:
	LuaGenVisitor(Compiler& c) :
		IdentityVisitor(c),
		mDummyNameCounter(0),
		mOutput(c)
	{}

	using AstVisitor::visit;

	bool isTopLevel() { return true; }
	Identifier* genDummyVar(CompileLoc loc, const char* fmt);
	const char* getOutput();
	bool isIdent(crocstr id);
	template<typename T> void visitList(DArray<T> vals);
	void visitArgs(CompileLoc& loc, DArray<Expression*> args);
	void visitField(Expression* name);
	OpAssignStmt* visitOpAssign(OpAssignStmt* s);
	OpAssignStmt* visitBitOpAssign(OpAssignStmt* s);
	const char* opAssignOp(AstTag type);

	virtual Identifier* visit(Identifier* id) override;
	virtual FuncDef* visit(FuncDef* d) override;
	virtual Statement* visit(ImportStmt* s) override;
	virtual ScopeStmt* visit(ScopeStmt* s) override;
	virtual ExpressionStmt* visit(ExpressionStmt* s) override;
	virtual VarDecl* visit(VarDecl* d) override;
	virtual Decorator* visit(Decorator* d) override;
	virtual FuncDecl* visit(FuncDecl* d) override;
	virtual Statement* visit(BlockStmt* s) override;
	virtual Statement* visit(IfStmt* s) override;
	virtual Statement* visit(WhileStmt* s) override;
	virtual Statement* visit(DoWhileStmt* s) override;
	virtual Statement* visit(ForStmt* s) override;
	virtual Statement* visit(ForNumStmt* s) override;
	virtual ForeachStmt* visit(ForeachStmt* s) override;
	virtual ContinueStmt* visit(ContinueStmt* s) override;
	virtual BreakStmt* visit(BreakStmt* s) override;
	virtual ReturnStmt* visit(ReturnStmt* s) override;
	virtual AssignStmt* visit(AssignStmt* s) override;
	virtual Statement* visit(AddAssignStmt* s) override;
	virtual Statement* visit(SubAssignStmt* s) override;
	virtual Statement* visit(MulAssignStmt* s) override;
	virtual Statement* visit(DivAssignStmt* s) override;
	virtual Statement* visit(ModAssignStmt* s) override;
	virtual Statement* visit(ShlAssignStmt* s) override;
	virtual Statement* visit(ShrAssignStmt* s) override;
	virtual Statement* visit(UShrAssignStmt* s) override;
	virtual Statement* visit(XorAssignStmt* s) override;
	virtual Statement* visit(OrAssignStmt* s) override;
	virtual Statement* visit(AndAssignStmt* s) override;
	virtual Statement* visit(CondAssignStmt* s) override;
	virtual IncStmt* visit(IncStmt* s) override;
	virtual DecStmt* visit(DecStmt* s) override;
	virtual Expression* visit(CondExp* e) override;
	virtual Expression* visit(OrOrExp* e) override;
	virtual Expression* visit(AndAndExp* e) override;
	virtual Expression* visit(OrExp* e) override;
	virtual Expression* visit(XorExp* e) override;
	virtual Expression* visit(AndExp* e) override;
	virtual Expression* visit(EqualExp* e) override;
	virtual Expression* visit(NotEqualExp* e) override;
	virtual Expression* visit(IsExp* e) override;
	virtual Expression* visit(NotIsExp* e) override;
	virtual Expression* visit(LTExp* e) override;
	virtual Expression* visit(LEExp* e) override;
	virtual Expression* visit(GTExp* e) override;
	virtual Expression* visit(GEExp* e) override;
	virtual Expression* visit(ShlExp* e) override;
	virtual Expression* visit(ShrExp* e) override;
	virtual Expression* visit(UShrExp* e) override;
	virtual Expression* visit(AddExp* e) override;
	virtual Expression* visit(SubExp* e) override;
	virtual Expression* visit(CatExp* e) override;
	virtual Expression* visit(MulExp* e) override;
	virtual Expression* visit(DivExp* e) override;
	virtual Expression* visit(ModExp* e) override;
	virtual Expression* visit(NegExp* e) override;
	virtual Expression* visit(NotExp* e) override;
	virtual Expression* visit(ComExp* e) override;
	virtual Expression* visit(LenExp* e) override;
	virtual Expression* visit(DotExp* e) override;
	virtual Expression* visit(MethodCallExp* e) override;
	virtual Expression* visit(CallExp* e) override;
	virtual Expression* visit(IndexExp* e) override;
	virtual Expression* visit(VargIndexExp* e) override;
	virtual Expression* visit(VargLenExp* e) override;
	virtual FuncLiteralExp* visit(FuncLiteralExp* e) override;
	virtual Expression* visit(ParenExp* e) override;
	virtual TableCtorExp* visit(TableCtorExp* e) override;
	virtual ArrayCtorExp* visit(ArrayCtorExp* e) override;
	virtual YieldExp* visit(YieldExp* e) override;

	virtual Expression* visit(IdentExp* e) override;
	virtual Expression* visit(ThisExp* e) override;
	virtual Expression* visit(NullExp* e) override;
	virtual Expression* visit(BoolExp* e) override;
	virtual Expression* visit(VarargExp* e) override;
	virtual Expression* visit(IntExp* e) override;
	virtual Expression* visit(FloatExp* e) override;
	virtual Expression* visit(StringExp* e) override;
};

#endif