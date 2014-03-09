#ifndef CROC_COMPILER_DOCPARSER_HPP
#define CROC_COMPILER_DOCPARSER_HPP

#include "croc/types/base.hpp"

namespace croc
{
	void processComment(CrocThread* t, crocstr comment);
	word parseCommentText(CrocThread* t, crocstr comment);
}

#endif