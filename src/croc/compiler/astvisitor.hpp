#ifndef CROC_COMPILER_ASTVISITOR_HPP
#define CROC_COMPILER_ASTVISITOR_HPP

#include <functional>
#include <stdlib.h>

#include "croc/compiler/ast.hpp"
#include "croc/compiler/types.hpp"

namespace croc
{
	struct Visitor
	{
	private:
		static const std::function<AstNode*(Visitor*, AstNode*)> dispatchTable[];
	protected:
		Compiler* c;

	public:
		// Visit methods
#define POOP(Tag, _, BaseType)\
		virtual BaseType* visit(Tag* node)\
		{\
			(void)node;\
			fprintf(stderr, "no visit method implemented for AST node '" #Tag "'");\
			abort();\
		}

		AST_LIST(POOP)
#undef POOP

		// Dispatch functions
#define POOP(Tag, _, BaseType)\
		static BaseType* visit##Tag(Visitor* visitor, Tag* c)\
		{\
			return visitor->visit(c);\
		}

		AST_LIST(POOP)
#undef POOP

		Visitor(Compiler* c) : c(c) {}

		inline Statement* visit(Statement* n)    { return visitS(n);                               }
		inline Expression* visit(Expression* n)  { return visitE(n);                               }
		inline AstNode* visit(AstNode* n)        { return visitN(n);                               }
		inline Statement* visitS(Statement* n)   { return cast(Statement*)cast(void*)dispatch(n);  }
		inline Expression* visitE(Expression* n) { return cast(Expression*)cast(void*)dispatch(n); }
		inline AstNode* visitN(AstNode* n)       { return dispatch(n);                             }

	protected:
		inline std::function<AstNode*(Visitor*, AstNode*)> getDispatchFunction(AstNode* n)
		{
			return dispatchTable[n->type];
		}

		inline AstNode* dispatch(AstNode* n)
		{
			return getDispatchFunction(n)(this, n);
		}
	};

	struct IdentityVisitor : public Visitor
	{
	public:
#define POOP(Tag, _, BaseType) virtual BaseType* visit(Tag* node) override { return node; }
		AST_LIST(POOP)
#undef POOP

		IdentityVisitor(Compiler* c) : Visitor(c) {}
	};
}

#endif