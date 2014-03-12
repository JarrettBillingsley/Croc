#ifndef CROC_UTIL_STR_HPP
#define CROC_UTIL_STR_HPP

#include <functional>
#include <stddef.h>

#include "croc/base/darray.hpp"
#include "croc/util/utf.hpp"

namespace croc
{
	// =================================================================================================================
	// UTF-8

	size_t findCharFast(custring str, uchar ch);
	// NOTE: the start indices on all these is in BYTES, not codepoints!
	size_t strLocate(custring source, custring match, size_t start = 0);
	size_t strLocateChar(custring source, uchar match, size_t start = 0);
	size_t strLocatePattern(custring source, custring match, size_t start = 0);
	size_t strRLocate(custring source, custring match, size_t start = 0);
	size_t strRLocateChar(custring source, uchar match, size_t start = 0);
	size_t strRLocatePattern(custring source, custring match, size_t start = 0);
	bool strEqFast(const uchar* s1, const uchar* s2, size_t length);
	size_t strMismatchFast(const uchar* s1, const uchar* s2, size_t length);

	custring strTrimWS(custring str);
	custring strTrimlWS(custring str);
	custring strTrimrWS(custring str);

	void delimiters(custring str, custring set, std::function<void(custring)> dg);
	void delimitersBreak(custring str, custring set, std::function<bool(custring)> dg);

	void patterns(custring str, custring pat, std::function<void(custring)> dg);
	void patternsBreak(custring str, custring pat, std::function<bool(custring)> dg);
	void patternsRep(custring str, custring pat, custring rep, std::function<void(custring)> dg);
	void patternsRepBreak(custring str, custring pat, custring rep, std::function<bool(custring)> dg);

	void lines(custring str, std::function<void(custring)> dg);
	void linesBreak(custring str, std::function<bool(custring)> dg);

	// =================================================================================================================
	// UTF-32

	size_t findCharFast(cdstring str, dchar ch);
	size_t strLocate(cdstring source, cdstring match, size_t start);
	size_t strLocateChar(cdstring source, dchar match, size_t start);
	size_t strLocatePattern(cdstring source, cdstring match, size_t start);
	size_t strRLocate(cdstring source, cdstring match, size_t start);
	size_t strRLocateChar(cdstring source, dchar match, size_t start);
	size_t strRLocatePattern(cdstring source, cdstring match, size_t start);
	bool strEqFast(const dchar* s1, const dchar* s2, size_t length);
	size_t strMismatchFast(const dchar* s1, const dchar* s2, size_t length);
	cdstring strTrimWS(cdstring str);
	cdstring strTrimlWS(cdstring str);
	cdstring strTrimrWS(cdstring str);

	void delimiters(cdstring str, cdstring set, std::function<void(cdstring)> dg);
	void delimitersBreak(cdstring str, cdstring set, std::function<bool(cdstring)> dg);

	void patterns(cdstring str, cdstring pat, std::function<void(cdstring)> dg);
	void patternsBreak(cdstring str, cdstring pat, std::function<bool(cdstring)> dg);
	void patternsRep(cdstring str, cdstring pat, cdstring rep, std::function<void(cdstring)> dg);
	void patternsRepBreak(cdstring str, cdstring pat, cdstring rep, std::function<bool(cdstring)> dg);

	void lines(cdstring str, std::function<void(cdstring)> dg);
	void linesBreak(cdstring str, std::function<bool(cdstring)> dg);
}

#endif