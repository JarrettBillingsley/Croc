#ifndef CROC_COMPILER_SEMANTIC_HPP
#define CROC_COMPILER_SEMANTIC_HPP

#include "croc/compiler/astvisitor.hpp"
#include "croc/compiler/types.hpp"

namespace croc
{
	class Semantic : public IdentityVisitor
	{
	private:
		struct FinallyDepth
		{
			word depth;
			FinallyDepth* prev;

			FinallyDepth(word depth, FinallyDepth* prev):
				depth(depth),
				prev(prev)
			{}
		};

		FinallyDepth* mFinallyDepth;
		uword mDummyNameCounter = 0;

	public:
		Semantic(Compiler& c) :
			IdentityVisitor(c),
			mFinallyDepth(nullptr),
			mDummyNameCounter(0)
		{}

		using AstVisitor::visit;

		bool isTopLevel();
		void enterFinally();
		void leaveFinally();
		bool inFinally();

		FuncDef* commonVisitFuncDef(FuncDef* d);
		OpAssignStmt* visitOpAssign(OpAssignStmt* s);
		Expression* visitEquality(BinaryExp* e);
		word commonCompare(Expression* op1, Expression* op2);
		Expression* visitComparison(BinaryExp* e);
		ForComprehension* visitForComp(ForComprehension* e);
		Identifier* genDummyVar(CompileLoc loc, const char* fmt);

		virtual Module* visit(Module* m) override;
		virtual FuncDef* visit(FuncDef* d) override;
		virtual Statement* visit(AssertStmt* s) override;
		virtual Statement* visit(ImportStmt* s) override;
		virtual ScopeStmt* visit(ScopeStmt* s) override;
		virtual ExpressionStmt* visit(ExpressionStmt* s) override;
		virtual VarDecl* visit(VarDecl* d) override;
		virtual Decorator* visit(Decorator* d) override;
		virtual FuncDecl* visit(FuncDecl* d) override;
		virtual ClassDecl* visit(ClassDecl* d) override;
		virtual NamespaceDecl* visit(NamespaceDecl* d) override;
		virtual Statement* visit(BlockStmt* s) override;
		virtual Statement* visit(IfStmt* s) override;
		virtual Statement* visit(WhileStmt* s) override;
		virtual Statement* visit(DoWhileStmt* s) override;
		virtual Statement* visit(ForStmt* s) override;
		virtual Statement* visit(ForNumStmt* s) override;
		virtual ForeachStmt* visit(ForeachStmt* s) override;
		virtual SwitchStmt* visit(SwitchStmt* s) override;
		virtual CaseStmt* visit(CaseStmt* s) override;
		virtual DefaultStmt* visit(DefaultStmt* s) override;
		virtual ContinueStmt* visit(ContinueStmt* s) override;
		virtual BreakStmt* visit(BreakStmt* s) override;
		virtual ReturnStmt* visit(ReturnStmt* s) override;
		virtual TryCatchStmt* visit(TryCatchStmt* s) override;
		virtual TryFinallyStmt* visit(TryFinallyStmt* s) override;
		virtual ThrowStmt* visit(ThrowStmt* s) override;
		virtual ScopeActionStmt* visit(ScopeActionStmt* s) override;
		virtual AssignStmt* visit(AssignStmt* s) override;
		virtual AddAssignStmt* visit(AddAssignStmt* s) override;
		virtual SubAssignStmt* visit(SubAssignStmt* s) override;
		virtual MulAssignStmt* visit(MulAssignStmt* s) override;
		virtual DivAssignStmt* visit(DivAssignStmt* s) override;
		virtual ModAssignStmt* visit(ModAssignStmt* s) override;
		virtual ShlAssignStmt* visit(ShlAssignStmt* s) override;
		virtual ShrAssignStmt* visit(ShrAssignStmt* s) override;
		virtual UShrAssignStmt* visit(UShrAssignStmt* s) override;
		virtual XorAssignStmt* visit(XorAssignStmt* s) override;
		virtual OrAssignStmt* visit(OrAssignStmt* s) override;
		virtual AndAssignStmt* visit(AndAssignStmt* s) override;
		virtual Statement* visit(CondAssignStmt* s) override;
		virtual CatAssignStmt* visit(CatAssignStmt* s) override;
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
		virtual Expression* visit(Cmp3Exp* e) override;
		virtual Expression* visit(InExp* e) override;
		virtual Expression* visit(NotInExp* e) override;
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
		virtual Expression* visit(DotSuperExp* e) override;
		virtual Expression* visit(MethodCallExp* e) override;
		virtual Expression* visit(CallExp* e) override;
		virtual Expression* visit(IndexExp* e) override;
		virtual Expression* visit(VargIndexExp* e) override;
		virtual Expression* visit(SliceExp* e) override;
		virtual Expression* visit(VargSliceExp* e) override;
		virtual FuncLiteralExp* visit(FuncLiteralExp* e) override;
		virtual Expression* visit(ParenExp* e) override;
		virtual TableCtorExp* visit(TableCtorExp* e) override;
		virtual ArrayCtorExp* visit(ArrayCtorExp* e) override;
		virtual YieldExp* visit(YieldExp* e) override;
		virtual TableComprehension* visit(TableComprehension* e) override;
		virtual Expression* visit(ArrayComprehension* e) override;
		virtual ForeachComprehension* visit(ForeachComprehension* e) override;
		virtual ForNumComprehension* visit(ForNumComprehension* e) override;
		virtual IfComprehension* visit(IfComprehension* e) override;
	};
}

#endif