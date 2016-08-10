
#include <cstdio>

#include "croc/compiler/ast.hpp"
#include "croc/compiler/astvisitor.hpp"
#include "croc/compiler/types.hpp"

// Visit methods
#define POOP(Tag, _, BaseType)\
BaseType* AstVisitor::visit(Tag* node)\
{\
	(void)node;\
	fprintf(stderr, "no visit method implemented for AST node '" #Tag "'");\
	abort();\
}
AST_LIST(POOP)
#undef POOP

AstNode* AstVisitor::visit(AstNode* n)
{
	switch(n->type)
	{
#define POOP(Tag, _, __)\
		case AstTag_##Tag: return visit(cast(Tag*)n);
		AST_LIST(POOP)
#undef poop

		default: assert(false); return nullptr; // dummy
	}
}