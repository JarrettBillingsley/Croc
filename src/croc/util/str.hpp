#ifndef CROC_UTIL_STR_HPP
#define CROC_UTIL_STR_HPP

#include <functional>
#include <stddef.h>

#include "croc/base/darray.hpp"

namespace croc
{
	// =================================================================================================================
	// UTF-8

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

	// =================================================================================================================
	// UTF-32

	size_t findCharFast(DArray<const uint32_t> str, uint32_t ch);
	size_t strLocate(DArray<const uint32_t> source, DArray<const uint32_t> match, size_t start);
	size_t strLocateChar(DArray<const uint32_t> source, uint32_t match, size_t start);
	size_t strLocatePattern(DArray<const uint32_t> source, DArray<const uint32_t> match, size_t start);
	size_t strRLocate(DArray<const uint32_t> source, DArray<const uint32_t> match, size_t start);
	size_t strRLocateChar(DArray<const uint32_t> source, uint32_t match, size_t start);
	size_t strRLocatePattern(DArray<const uint32_t> source, DArray<const uint32_t> match, size_t start);
	bool strEqFast(const uint32_t* s1, const uint32_t* s2, size_t length);
	size_t strMismatchFast(const uint32_t* s1, const uint32_t* s2, size_t length);
	DArray<const uint32_t> strTrimWS(DArray<const uint32_t> str);
	DArray<const uint32_t> strTrimlWS(DArray<const uint32_t> str);
	DArray<const uint32_t> strTrimrWS(DArray<const uint32_t> str);

	void delimiters(DArray<const uint32_t> str, DArray<const uint32_t> set,
		std::function<void(DArray<const uint32_t>)> dg);
	void delimitersBreak(DArray<const uint32_t> str, DArray<const uint32_t> set,
		std::function<bool(DArray<const uint32_t>)> dg);

	void patterns(DArray<const uint32_t> str, DArray<const uint32_t> pat,
		std::function<void(DArray<const uint32_t>)> dg);
	void patternsBreak(DArray<const uint32_t> str, DArray<const uint32_t> pat,
		std::function<bool(DArray<const uint32_t>)> dg);
	void patternsRep(DArray<const uint32_t> str, DArray<const uint32_t> pat, DArray<const uint32_t> rep,
		std::function<void(DArray<const uint32_t>)> dg);
	void patternsRepBreak(DArray<const uint32_t> str, DArray<const uint32_t> pat, DArray<const uint32_t> rep,
		std::function<bool(DArray<const uint32_t>)> dg);

	void lines(DArray<const uint32_t> str, std::function<void(DArray<const uint32_t>)> dg);
	void linesBreak(DArray<const uint32_t> str, std::function<bool(DArray<const uint32_t>)> dg);
}

#endif