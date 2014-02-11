#ifndef CROC_COMPILER_ASTVISITOR_HPP
#define CROC_COMPILER_ASTVISITOR_HPP

#include <stdlib.h>

#include "croc/compiler/ast.hpp"
#include "croc/compiler/types.hpp"

namespace croc
{
	struct AstVisitor
	{
	protected:
		Compiler& c;

	public:
		AstVisitor(Compiler& c) : c(c) {}

		inline Statement* visit(Statement* n)
		{
			return cast(Statement*)cast(void*)visit(cast(AstNode*)n);
		}

		inline Expression* visit(Expression* n)
		{
			return cast(Expression*)cast(void*)visit(cast(AstNode*)n);
		}

#define POOP(Tag, _, BaseType)\
		virtual BaseType* visit(Tag* node);
		AST_LIST(POOP)
#undef POOP

	protected:
		AstNode* visit(AstNode* n);
	};

	struct IdentityVisitor : public AstVisitor
	{
	public:
		IdentityVisitor(Compiler& c) : AstVisitor(c) {}

#define POOP(Tag, _, BaseType)\
		virtual BaseType* visit(Tag* node) override { return node; }
		AST_LIST(POOP)
#undef POOP
	};
}

#endif