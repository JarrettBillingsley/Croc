#ifndef CROC_TYPES_STRING_HPP
#define CROC_TYPES_STRING_HPP

#include "croc/types.hpp"
#include "croc/utf.hpp"

namespace croc
{
	namespace string
	{
		String* lookup(VM* vm, crocstr data, uword& h);
		String* create(VM* vm, crocstr data, uword h, uword cpLen);
		void free(VM* vm, String* s);
		crocint compare(String* a, String* b);
		bool contains(String* s, crocstr sub);
		String* slice(VM* vm, String* s, uword lo, uword hi);
		dchar charAt(String* s, uword idx);
	}
}

#endif