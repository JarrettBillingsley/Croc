#ifndef CROC_TYPES_STRING_HPP
#define CROC_TYPES_STRING_HPP

#include "croc/types.hpp"

namespace croc
{
	namespace string
	{
		String* lookup(VM* vm, DArray<const char> data, uword& h);
		String* create(VM* vm, DArray<const char> data, uword h, uword cpLen);
		void free(VM* vm, String* s);
		crocint compare(String* a, String* b);
		bool contains(String* s, crocchar c);
		bool contains(String* s, DArray<const char> sub);
		String* slice(VM* vm, String* s, uword lo, uword hi);
		crocchar charAt(String* s, uword idx);
	}
}

#endif