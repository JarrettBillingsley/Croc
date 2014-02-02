
#include "croc/types.hpp"
#include "croc/utf.hpp"
#include "croc/utils.hpp"

#define STRING_EXTRA_SIZE(len) (sizeof(char) * (len))

namespace croc
{
	String* String::lookup(VM* vm, crocstr data, uword& h)
	{
		// We don't have to verify the string if it already exists in the string table,
		// because if it does, it means it's a legal string.
		// Neither hashing nor lookup require the string to be valid UTF-8.
		h = data.toHash();

		auto s = vm->stringTab.lookup(data, h);

		if(s)
			return *s;

		return nullptr;
	}

	// Create a new string object. String objects with the same data are reused. Thus,
	// if two string objects are identical, they are also equal.
	String* String::create(VM* vm, crocstr data, uword h, uword cpLen)
	{
		auto ret = ALLOC_OBJSZ_ACYC(vm->mem, String, STRING_EXTRA_SIZE(data.length));
		ret->type = CrocType_String;
		ret->hash = h;
		ret->length = data.length;
		ret->cpLength = cpLen;
		ret->setData(data);
		*vm->stringTab.insert(vm->mem, ret->toDArray()) = ret;
		return ret;
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

		// TODO:
		// return this->toDArray().locatePattern(sub) != this->length;
		return false;
	}

	// The slice indices are in codepoints, not byte indices.
	// And these indices better be good.
	String* String::slice(VM* vm, uword lo, uword hi)
	{
		auto str = utf8Slice(this->toDArray(), lo, hi);
		uword h;

		if(auto s = lookup(vm, str, h))
			return s;

		// don't have to verify since we're slicing from a string we know is good
		return create(vm, str, h, hi - lo);
	}
}