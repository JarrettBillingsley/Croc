#ifndef CROC_COMPILER_CODEGEN_HPP
#define CROC_COMPILER_CODEGEN_HPP

#include "croc/compiler/builder.hpp"
#include "croc/compiler/ast.hpp"
#include "croc/compiler/astvisitor.hpp"
#include "croc/compiler/types.hpp"

// #define PRINTEXPSTACK

#if defined(PRINTEXPSTACK) && !defined(NDEBUG)
#define DEBUG_PRINTEXPSTACK(x) x
#else
#define DEBUG_PRINTEXPSTACK(x)
#endif

namespace croc
{
	class Codegen : public AstVisitor
	{
	private:
		FuncBuilder* fb;

	public:
		Codegen(Compiler& c) :
			AstVisitor(c)
		{}

		using AstVisitor::visit;

		void codegenStatements(FuncDef* d);
		word dottedNameToString(Expression* exp);
		void visitDecorator(Decorator* d, std::function<void()> obj);
		void visitIf(CompileLoc endLocation, CompileLoc elseLocation, IdentExp* condVar, Expression* condition, std::function<void()> genBody, std::function<void()> genElse);
		void visitForNum(CompileLoc location, CompileLoc endLocation, crocstr name, Expression* lo, Expression* hi, Expression* step, Identifier* index, std::function<void()> genBody);
		void visitForeach(CompileLoc location, CompileLoc endLocation, crocstr name, DArray<Identifier*> indices, DArray<Expression*> container, std::function<void()> genBody);
		void codeReturn(CompileLoc location, uword numRets);
		OpAssignStmt* visitOpAssign(OpAssignStmt* s);
		BinaryExp* visitBinExp(BinaryExp* e);
		BinaryExp* visitComparisonExp(BinaryExp* e);
		UnExp* visitUnExp(UnExp* e);
		void visitMethodCall(CompileLoc location, CompileLoc endLocation, Expression* op, Expression* method, std::function<uword()> genArgs);
		void visitCall(CompileLoc endLocation, Expression* op, Expression* context, std::function<uword()> genArgs);
		ForComprehension* visitForComp(ForComprehension* e, std::function<void()> inner);
		ForeachComprehension* visitForeachComp(ForeachComprehension* e, std::function<void()> inner);
		ForNumComprehension* visitForNumComp(ForNumComprehension* e, std::function<void()> inner);
		IfComprehension* visit(IfComprehension* e, std::function<void()> inner);
		void codeGenList(DArray<Expression*> exprs, bool allowMultRet = true);
		void codeGenAssignRHS(DArray<Expression*> exprs);
		InstRef codeCondition(Expression* e);
		InstRef codeCondition(CondExp* e);
		InstRef codeCondition(OrOrExp* e);
		InstRef codeCondition(AndAndExp* e);
		InstRef codeEqualExpCondition(BinaryExp* e);
		InstRef codeCondition(EqualExp* e);
		InstRef codeCondition(NotEqualExp* e);
		InstRef codeCondition(IsExp* e);
		InstRef codeCondition(NotIsExp* e);
		InstRef codeCondition(InExp* e);
		InstRef codeCondition(NotInExp* e);
		InstRef codeCmpExpCondition(BinaryExp* e);
		InstRef codeCondition(LTExp* e);
		InstRef codeCondition(LEExp* e);
		InstRef codeCondition(GTExp* e);
		InstRef codeCondition(GEExp* e);
		InstRef codeCondition(ParenExp* e);

		Module* visit(Module* m) override;
		FuncDef* visit(FuncDef* d) override;
		TypecheckStmt* visit(TypecheckStmt* s) override;
		ImportStmt* visit(ImportStmt* s) override;
		ScopeStmt* visit(ScopeStmt* s) override;
		ExpressionStmt* visit(ExpressionStmt* s) override;
		FuncDecl* visit(FuncDecl* d) override;
		ClassDecl* visit(ClassDecl* d) override;
		NamespaceDecl* visit(NamespaceDecl* d) override;
		VarDecl* visit(VarDecl* d) override;
		BlockStmt* visit(BlockStmt* s) override;
		AssertStmt* visit(AssertStmt* s) override;
		IfStmt* visit(IfStmt* s) override;
		WhileStmt* visit(WhileStmt* s) override;
		DoWhileStmt* visit(DoWhileStmt* s) override;
		ForStmt* visit(ForStmt* s) override;
		ForNumStmt* visit(ForNumStmt* s) override;
		ForeachStmt* visit(ForeachStmt* s) override;
		SwitchStmt* visit(SwitchStmt* s) override;
		CaseStmt* visit(CaseStmt* s) override;
		DefaultStmt* visit(DefaultStmt* s) override;
		ContinueStmt* visit(ContinueStmt* s) override;
		BreakStmt* visit(BreakStmt* s) override;
		ReturnStmt* visit(ReturnStmt* s) override;
		TryCatchStmt* visit(TryCatchStmt* s) override;
		TryFinallyStmt* visit(TryFinallyStmt* s) override;
		ThrowStmt* visit(ThrowStmt* s) override;
		AssignStmt* visit(AssignStmt* s) override;
		Statement* visit(AddAssignStmt* s) override;
		Statement* visit(SubAssignStmt* s) override;
		Statement* visit(MulAssignStmt* s) override;
		Statement* visit(DivAssignStmt* s) override;
		Statement* visit(ModAssignStmt* s) override;
		Statement* visit(AndAssignStmt* s) override;
		Statement* visit(OrAssignStmt* s) override;
		Statement* visit(XorAssignStmt* s) override;
		Statement* visit(ShlAssignStmt* s) override;
		Statement* visit(ShrAssignStmt* s) override;
		Statement* visit(UShrAssignStmt* s) override;
		CondAssignStmt* visit(CondAssignStmt* s) override;
		CatAssignStmt* visit(CatAssignStmt* s) override;
		IncStmt* visit(IncStmt* s) override;
		DecStmt* visit(DecStmt* s) override;
		CondExp* visit(CondExp* e) override;
		OrOrExp* visit(OrOrExp* e) override;
		AndAndExp* visit(AndAndExp* e) override;
		UnExp* visit(AsExp* e) override;
		BinaryExp* visit(AddExp* e) override;
		BinaryExp* visit(SubExp* e) override;
		BinaryExp* visit(MulExp* e) override;
		BinaryExp* visit(DivExp* e) override;
		BinaryExp* visit(ModExp* e) override;
		BinaryExp* visit(AndExp* e) override;
		BinaryExp* visit(OrExp* e) override;
		BinaryExp* visit(XorExp* e) override;
		BinaryExp* visit(ShlExp* e) override;
		BinaryExp* visit(ShrExp* e) override;
		BinaryExp* visit(UShrExp* e) override;
		BinaryExp* visit(Cmp3Exp* e) override;
		CatExp* visit(CatExp* e) override;
		BinaryExp* visit(EqualExp* e) override;
		BinaryExp* visit(NotEqualExp* e) override;
		BinaryExp* visit(IsExp* e) override;
		BinaryExp* visit(NotIsExp* e) override;
		BinaryExp* visit(LTExp* e) override;
		BinaryExp* visit(LEExp* e) override;
		BinaryExp* visit(GTExp* e) override;
		BinaryExp* visit(GEExp* e) override;
		BinaryExp* visit(InExp* e) override;
		BinaryExp* visit(NotInExp* e) override;
		UnExp* visit(NegExp* e) override;
		UnExp* visit(NotExp* e) override;
		UnExp* visit(ComExp* e) override;
		UnExp* visit(DotSuperExp* e) override;
		LenExp* visit(LenExp* e) override;
		VargLenExp* visit(VargLenExp* e) override;
		DotExp* visit(DotExp* e) override;
		MethodCallExp* visit(MethodCallExp* e) override;
		CallExp* visit(CallExp* e) override;
		IndexExp* visit(IndexExp* e) override;
		VargIndexExp* visit(VargIndexExp* e) override;
		SliceExp* visit(SliceExp* e) override;
		IdentExp* visit(IdentExp* e) override;
		ThisExp* visit(ThisExp* e) override;
		NullExp* visit(NullExp* e) override;
		BoolExp* visit(BoolExp* e) override;
		IntExp* visit(IntExp* e) override;
		FloatExp* visit(FloatExp* e) override;
		StringExp* visit(StringExp* e) override;
		VarargExp* visit(VarargExp* e) override;
		FuncLiteralExp* visit(FuncLiteralExp* e) override;
		ParenExp* visit(ParenExp* e) override;
		TableCtorExp* visit(TableCtorExp* e) override;
		ArrayCtorExp* visit(ArrayCtorExp* e) override;
		YieldExp* visit(YieldExp* e) override;
		TableComprehension* visit(TableComprehension* e) override;
		ArrayComprehension* visit(ArrayComprehension* e) override;
	};
}

#endif