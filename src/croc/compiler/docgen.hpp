#ifndef CROC_COMPILER_DOCGEN_HPP
#define CROC_COMPILER_DOCGEN_HPP

#include "croc/api.h"
#include "croc/compiler/astvisitor.hpp"
#include "croc/compiler/types.hpp"

namespace croc
{
	class DocGen : public IdentityVisitor
	{
	private:
		struct DocTableDesc
		{
			DocTableDesc* prev;
			word docTable;
			word childIndex;

			DocTableDesc() :
				prev(),
				docTable(),
				childIndex()
			{}
		};

		DocTableDesc* mDocTableDesc;
		CrocThread* t;
		uword mDocTable;
		word mDittoDepth;

	public:
		DocGen(Compiler& c) :
			IdentityVisitor(c),
			mDocTableDesc(),
			t(*c.thread()),
			mDocTable(),
			mDittoDepth()
		{}

		using AstVisitor::visit;

		FuncDef* visitStatements(FuncDef* d);
		virtual Module* visit(Module* m) override;
		virtual FuncDecl* visit(FuncDecl* d) override;
		virtual FuncDef* visit(FuncDef* d) override;
		virtual ClassDecl* visit(ClassDecl* d) override;
		virtual NamespaceDecl* visit(NamespaceDecl* d) override;
		virtual VarDecl* visit(VarDecl* d) override;
		virtual ScopeStmt* visit(ScopeStmt* s) override;
		virtual BlockStmt* visit(BlockStmt* s) override;
		virtual FuncLiteralExp* visit(FuncLiteralExp* e) override;

	private:
		void addComments(CompileLoc docsLoc, crocstr docs);
		void pushDocTable(DocTableDesc& desc, CompileLoc loc, CompileLoc docsLoc, crocstr kind, crocstr name, crocstr docs);
		void popDocTable(DocTableDesc& desc, const char* parentField = "children");
		void ensureChildren(const char* parentField = "children");
		void unpopTable();
		void doProtection(Protection p);
		Expression* docTableToAST(CompileLoc loc);
		Identifier* docIdent(CompileLoc loc);
		Identifier* doctableIdent(CompileLoc loc);
		Decorator* makeDeco(CompileLoc loc, Decorator* existing, bool lastIndex = true);
		Expression* makeDocCall(Expression* init);
		void pushTrimmedString(crocstr str);

		template<typename T>
		void doFields(DArray<T> fields)
		{
			for(auto &f: fields)
			{
				if(f.docs.length == 0)
					continue;

				if(auto method = f.func)
				{
					visit(method);

					if(c.docDecorators())
						f.initializer = makeDocCall(f.initializer);
				}
				else
				{
					// TODO: this location might not be on exactly the same line as the field itself.. huge deal?
					DocTableDesc desc;
					pushDocTable(desc, f.initializer->location, f.docsLoc, ATODA("field"), f.name, f.docs);

					if(f.initializer->sourceStr.length)
					{
						pushTrimmedString(f.initializer->sourceStr);
						croc_fielda(t, mDocTable, "value");
					}

					popDocTable(desc);
				}
			}
		}
	};
}

#endif