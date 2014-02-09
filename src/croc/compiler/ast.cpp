
#include "croc/compiler/ast.hpp"
#include "croc/compiler/types.hpp"

namespace croc
{
	const char* AstTagNames[AstTag_NUMBER] =
	{
#define POOP(Tag, _, __) #Tag,
		AST_LIST(POOP)
#undef POOP
	};

	const char* NiceAstTagNames[AstTag_NUMBER] =
	{
#define POOP(_, NiceName, __) NiceName,
		AST_LIST(POOP)
#undef POOP
	};
}