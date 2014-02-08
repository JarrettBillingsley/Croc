#include <string.h>

#include "croc/utils.hpp"

namespace croc
{
	// Returns closest power of 2 that is >= n. Taken from the Stanford Bit Twiddling Hacks page.
	size_t largerPow2(size_t n)
	{
		if(n == 0)
			return 0;

		n--;
		n |= n >> 1;
		n |= n >> 2;
		n |= n >> 4;
		n |= n >> 8;
		n |= n >> 16;
		n |= n >> ((sizeof(size_t) > 4) * 32);
		n++;
		return n;
	}

	// Compares strings stupidly (just by character value, not lexicographically).
	int scmp(DArray<const char> s1, DArray<const char> s2)
	{
		size_t len = s1.length;

		if(s2.length < len)
			len = s2.length;

		int result = strncmp(s1.ptr, s2.ptr, len);

		if(result == 0)
			return Compare3(s1.length, s2.length);
		else
			return result;
	}

	delimiters::delimiters(const char* str, int ch) : mStr(atoda(str)), mChar(ch) {}
	delimiters::iter delimiters::begin() { return delimiters::iter(mStr.ptr, mChar); }
	delimiters::iter delimiters::end()   { delimiters::iter ret(mStr.ptr + mStr.length, mChar); ret++; return ret; }

	delimiters::iter::iter(const delimiters::iter& other): mSlice(other.mSlice), mEnd(other.mEnd), mChar(other.mChar) {}

	delimiters::iter::iter(const char* str, int ch) : mChar(ch)
	{
		mEnd = str + strlen(str);
		mSlice.ptr = str;

		if(auto dot = strchr(str, ch))
			mSlice.length = dot - str;
		else
			mSlice.length = mEnd - str;
	}

	delimiters::iter& delimiters::iter::operator++()
	{
		auto next = mSlice.ptr + mSlice.length + 1;

		if(next > mEnd)
		{
			mSlice.ptr = mEnd + 1;
			mSlice.length = 0;
		}
		else if(next == mEnd)
		{
			mSlice.ptr = mEnd;
			mSlice.length = 0;
		}
		else
		{
			mSlice.ptr = next;

			if(auto dot = strchr(next, mChar))
				mSlice.length = dot - next;
			else
				mSlice.length = mEnd - next;
		}

		return *this;
	}

	delimiters::iter delimiters::iter::operator++(int) { delimiters::iter tmp(*this); operator++(); return tmp; }

	bool delimiters::iter::operator==(const delimiters::iter& rhs)
	{
		return mSlice.ptr == rhs.mSlice.ptr && mSlice.length == rhs.mSlice.length && mChar == rhs.mChar;
	}

	bool delimiters::iter::operator!=(const delimiters::iter& rhs) { return !(*this == rhs); }
	DArray<const char> delimiters::iter::operator*() { return mSlice; }
}