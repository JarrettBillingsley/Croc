
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{
#include "croc/stdlib/repl.croc.hpp"
}

void initReplLib(CrocThread* t)
{
	croc_ex_importFromString(t, "repl", repl_croc_text, "repl.croc");
}
}