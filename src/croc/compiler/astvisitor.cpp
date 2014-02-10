
#include "croc/compiler/ast.hpp"
#include "croc/compiler/astvisitor.hpp"
#include "croc/compiler/types.hpp"

namespace croc
{
	const std::function<AstNode*(Visitor*, AstNode*)> Visitor::dispatchTable[] =
	{
#define POOP(Tag, _, BaseType)\
		[](Visitor* v, AstNode* n) -> AstNode*\
		{\
			return v->visit(cast(Tag*)n);\
		},

		AST_LIST(POOP)
#undef POOP
	};
}