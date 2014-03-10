
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
#include "croc/stdlib/doctools_output.croc.hpp"
#include "croc/stdlib/doctools_console.croc.hpp"
#include "croc/stdlib/doctools_trac.croc.hpp"
	}

	void initDoctoolsLibs(CrocThread* t)
	{
		croc_ex_importFromString(t, "doctools.output", doctools_output_croc_text, "doctools/output.croc");
		croc_ex_importFromString(t, "doctools.console", doctools_console_croc_text, "doctools/console.croc");
		croc_ex_importFromString(t, "doctools.trac", doctools_trac_croc_text, "doctools/trac.croc");
	}
}