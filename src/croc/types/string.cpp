module croc.types_string;

#include "croc/types.hpp"
#include "croc/utils.hpp"

#define STRING_SIZE(len) (sizeof(String) + sizeof(char) * (len))

namespace croc
{
	namespace string
	{
		String* lookup(VM* vm, DArray<const char> data, uword& h)
		{
			// We don't have to verify the string if it already exists in the string table,
			// because if it does, it means it's a legal string.
			// Neither hashing nor lookup require the string to be valid UTF-8.
			h = data.toHash();

			String** s = vm->stringTab.lookup(data, h);

			if(s)
				return *s;

			return NULL;
		}

		// Create a new string object. String objects with the same data are reused. Thus,
		// if two string objects are identical, they are also equal.
		String* create(VM* vm, DArray<const char> data, uword h, uword cpLen)
		{
			String* ret = vm->alloc.allocate<String>(STRING_SIZE(data.length));
			ret->hash = h;
			ret->length = data.length;
			ret->cpLength = cpLen;
			ret->toString().slicea(data);

			*vm->stringTab.insert(vm->alloc, ret->toString()) = ret;
			return ret;
		}

		// Free a string object.
		void free(VM* vm, String* s)
		{
			bool b = vm->stringTab.remove(s->toString());
			assert(b);
			vm->alloc.free(s);
		}

		// Compare two string objects.
		crocint compare(String* a, String* b)
		{
			return scmp(a->toString(), b->toString());
		}

		// See if the string contains the given character.
		bool contains(String* s, crocchar c)
		{
			// TODO:

			// foreach(crocchar ch; s.toString())
			// 	if(c == ch)
			// 		return true;

			return false;
		}

		// See if the string contains the given substring.
		bool contains(String* s, DArray<const char> sub)
		{
			if(s->length < sub.length)
				return false;

			// TODO:
			// return s.toString().locatePattern(sub) != s.length;
			return false;
		}

		// The slice indices are in codepoints, not byte indices.
		// And these indices better be good.
		String* slice(VM* vm, String* s, uword lo, uword hi)
		{

			auto str = uniSlice(s.toString(), lo, hi);
			uword h = void;

			if(auto s = lookup(vm, str, h))
				return s;

			// don't have to verify since we're slicing from a string we know is good
			return create(vm, uniSlice(s.toString(), lo, hi), h, hi - lo);
		}

		// Like slice, the index is in codepoints, not byte indices.
		crocchar charAt(String* s, uword idx)
		{
			return uniCharAt(s.toString(), idx);
		}
	}
}