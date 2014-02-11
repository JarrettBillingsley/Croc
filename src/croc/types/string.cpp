
#include <functional>

#include "croc/api.h"
#include "croc/types.hpp"
#include "croc/utf.hpp"
#include "croc/utils.hpp"

#define STRING_EXTRA_SIZE(len) (1 + (sizeof(char) * (len)))

namespace croc
{
	namespace
	{
		String* createInternal(VM* vm, crocstr data, std::function<uword()> getCPLen)
		{
			auto h = data.toHash();

			if(auto s = vm->stringTab.lookup(data, h))
				return *s;

			auto cpLen = getCPLen();
			auto ret = ALLOC_OBJSZ_ACYC(vm->mem, String, STRING_EXTRA_SIZE(data.length));
			ret->type = CrocType_String;
			ret->hash = h;
			ret->length = data.length;
			ret->cpLength = cpLen;
			ret->setData(data);
			*vm->stringTab.insert(vm->mem, ret->toDArray()) = ret;
			return ret;
		}
	}

	// Create a new string object. String objects with the same data are reused. Thus,
	// if two string objects are identical, they are also equal.
	String* String::create(VM* vm, crocstr data)
	{
		return createInternal(vm, data, [&vm, &data]()
		{
			uword cpLen;

			if(verifyUtf8(data, cpLen) != UtfError_OK)
				croc_eh_throwStd(*vm->curThread, "UnicodeError", "Invalid UTF-8 sequence");

			return cpLen;
		});
	}

	String* String::createUnverified(VM* vm, crocstr data, uword cpLen)
	{
		return createInternal(vm, data, [&cpLen]() { return cpLen; });
	}

	// Free a string object.
	void String::free(VM* vm, String* s)
	{
		bool b = vm->stringTab.remove(s->toDArray());
		assert(b);
		FREE_OBJ(vm->mem, String, s);
	}

	// Compare two string objects.
	crocint String::compare(String* other)
	{
		return scmp(this->toDArray(), other->toDArray());
	}

	// See if the string contains the given substring.
	bool String::contains(crocstr sub)
	{
		if(this->length < sub.length)
			return false;

		// TODO: string locate
		// return this->toDArray().locatePattern(sub) != this->length;
		return false;
	}

	// The slice indices are in codepoints, not byte indices.
	// And these indices better be good.
	String* String::slice(VM* vm, uword lo, uword hi)
	{
		return createUnverified(vm, utf8Slice(this->toDArray(), lo, hi), hi - lo);
	}
}