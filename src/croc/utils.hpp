#ifndef CROC_UTILS_HPP
#define CROC_UTILS_HPP

#include <stddef.h>

#include "croc/base/darray.hpp"

namespace croc
{
	size_t largerPow2(size_t n);
	int scmp(DArray<const char> s1, DArray<const char> s2);

	template<typename T>
	inline int Compare3(T a, T b)
	{
		return a < b ? -1 : a > b ? 1 : 0;
	}

	inline DArray<const char> atoda(const char* str)
	{
		return DArray<const char>::n(str, strlen(str));
	}

	struct delimiters
	{
	private:
		DArray<const char> mStr;
		int mChar;

	public:
		delimiters(const char* str, int ch);

		struct iter
		{
		private:
			DArray<const char> mSlice;
			const char* mEnd;
			int mChar;

		public:
			iter(const char* str, int ch);
			iter(const iter& other);
			iter& operator++();
			iter operator++(int);
			bool operator==(const iter& rhs);
			bool operator!=(const iter& rhs);
			DArray<const char> operator*();
		};

		iter begin();
		iter end();
	};
}

#endif