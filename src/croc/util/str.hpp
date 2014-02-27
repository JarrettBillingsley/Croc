#ifndef CROC_UTIL_STR_HPP
#define CROC_UTIL_STR_HPP

#include <functional>
#include <stddef.h>

#include "croc/base/darray.hpp"

namespace croc
{
	size_t findCharFast(DArray<const char> str, char ch);
	// NOTE: the start indices on all these is in BYTES, not codepoints!
	size_t strLocate(DArray<const char> source, DArray<const char> match, size_t start = 0);
	size_t strLocateChar(DArray<const char> source, char match, size_t start = 0);
	size_t strLocatePattern(DArray<const char> source, DArray<const char> match, size_t start = 0);
	size_t strRLocate(DArray<const char> source, DArray<const char> match, size_t start = 0);
	size_t strRLocateChar(DArray<const char> source, char match, size_t start = 0);
	size_t strRLocatePattern(DArray<const char> source, DArray<const char> match, size_t start = 0);
	bool strEqFast(const char* s1, const char* s2, size_t length);
	size_t strMismatchFast(const char* s1, const char* s2, size_t length);

	DArray<const char> strTrimWS(DArray<const char> str);
	DArray<const char> strTrimlWS(DArray<const char> str);
	DArray<const char> strTrimrWS(DArray<const char> str);

	void delimiters(DArray<const char> str, DArray<const char> set, std::function<void(DArray<const char>)> dg);
	void delimitersBreak(DArray<const char> str, DArray<const char> set, std::function<bool(DArray<const char>)> dg);

	void patterns(DArray<const char> str, DArray<const char> pat, std::function<void(DArray<const char>)> dg);
	void patternsBreak(DArray<const char> str, DArray<const char> pat, std::function<bool(DArray<const char>)> dg);

	void patternsRep(DArray<const char> str, DArray<const char> pat, DArray<const char> rep,
		std::function<void(DArray<const char>)> dg);
	void patternsRepBreak(DArray<const char> str, DArray<const char> pat, DArray<const char> rep,
		std::function<bool(DArray<const char>)> dg);

	void lines(DArray<const char> str, std::function<void(DArray<const char>)> dg);
	void linesBreak(DArray<const char> str, std::function<bool(DArray<const char>)> dg);
}

#endif