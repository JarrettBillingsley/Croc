#include <string.h>

#include "croc/util/str.hpp"

namespace croc
{
	size_t findCharFast(DArray<const char> str, char ch)
	{
		if(str.length)
		{
			// "smear" searched character across m
			size_t m = ch;
			m += m << 8;
			m += m << 16;

			if(sizeof(size_t) > 4)
				m += m << ((sizeof(size_t) > 4) * 32);

			auto p = str.ptr;
			auto e = p + str.length - sizeof(size_t);

			while(p < e)
			{
				// clear matching T segments
				auto v = (*cast(size_t*)p) ^ m;

				if((v - cast(size_t)0x0101010101010101) & ~v & cast(size_t)0x8080808080808080)
					break;

				p += sizeof(size_t);
			}

			e += sizeof(size_t);

			while(p < e)
			{
				if(*p++ == ch)
					return cast(size_t)(p - str.ptr - 1);
			}
		}

		return str.length;
	}

	size_t strLocate(DArray<const char> source, DArray<const char> match, size_t start)
	{
		if(match.length == 1)
			return strLocateChar(source, match[0], start);
		else
			return strLocatePattern(source, match, start);
	}

	size_t strLocateChar(DArray<const char> source, char match, size_t start)
	{
		if(start > source.length)
			start = source.length;

		return findCharFast(DArray<const char>::n(source.ptr + start, source.length - start), match) + start;
	}

	size_t strLocatePattern(DArray<const char> source, DArray<const char> match, size_t start)
	{
		size_t idx;
		const char* p = source.ptr + start;
		size_t extent = source.length - start - match.length + 1;

		if(match.length && extent <= source.length)
		{
			while(extent)
			{
				idx = findCharFast(DArray<const char>::n(p, extent), match[0]);

				if(idx == extent)
					break;

				p += idx;

				if(strEqFast(p, match.ptr, match.length))
					return p - source.ptr;
				else
				{
					extent -= idx + 1;
					++p;
				}
			}
		}

		return source.length;
	}

	size_t strRLocate(DArray<const char> source, DArray<const char> match, size_t start)
	{
		if(match.length == 1)
			return strRLocateChar(source, match[0], start);
		else
			return strRLocatePattern(source, match, start);
	}

	size_t strRLocateChar(DArray<const char> source, char match, size_t start)
	{
		if(start > source.length)
			start = source.length;

		while(start > 0)
		{
			if(source[--start] == match)
				return start;
		}

		return source.length;
	}

	size_t strRLocatePattern(DArray<const char> source, DArray<const char> match, size_t start)
	{
		if(start > source.length)
			start = source.length;

		if(match.length && match.length <= source.length)
		{
			while(start > 0)
			{
				start = strRLocateChar(source, match[0], start);

				if(start == source.length)
					break;

				if((start + match.length) <= source.length && strEqFast(source.ptr + start, match.ptr, match.length))
					return start;
			}
		}

		return source.length;
	}

	bool strEqFast(const char* s1, const char* s2, size_t length)
	{
		return strMismatchFast(s1, s2, length) == length;
	}

	size_t strMismatchFast(const char* s1, const char* s2, size_t length)
	{
		if(length)
		{
			auto start = s1;
			auto e = start + length - sizeof(size_t);

			while(s1 < e)
			{
				if(*cast(size_t*)s1 != *cast(size_t*)s2)
					break;

				s1 += sizeof(size_t);
				s2 += sizeof(size_t);
			}

			e += sizeof(size_t);

			while(s1 < e)
			{
				if(*s1++ != *s2++)
					return s1 - start - 1;
			}
		}

		return length;
	}

#define IS_WHITESPACE(c)\
	((c) <= 32 && ((c) == ' ' || (c) == '\t' || (c) == '\v' || (c) == '\r' || (c) == '\n' || (c) == '\f'))

	DArray<const char> strTrimWS(DArray<const char> str)
	{
		if(str.length == 0)
			return str;

		auto head = str.ptr;
		auto tail = str.ptr + str.length;

		for(auto c = head[0]; head < tail && IS_WHITESPACE(c); c = (++head)[0]) {}
		for(auto c = tail[-1]; tail > head && IS_WHITESPACE(c); c = (--tail)[-1]) {}

		return DArray<const char>::n(head, tail - head);
	}

	DArray<const char> strTrimlWS(DArray<const char> str)
	{
		if(str.length == 0)
			return str;

		auto head = str.ptr;
		auto tail = str.ptr + str.length;

		for(auto c = head[0]; head < tail && IS_WHITESPACE(c); c = (++head)[0]) {}

		return DArray<const char>::n(head, tail - head);
	}

	DArray<const char> strTrimrWS(DArray<const char> str)
	{
		if(str.length == 0)
			return str;

		auto head = str.ptr;
		auto tail = str.ptr + str.length;

		for(auto c = tail[-1]; tail > head && IS_WHITESPACE(c); c = (--tail)[-1]) {}

		return DArray<const char>::n(head, tail - head);
	}

	// =================================================================================================================
	// Delimiters

	void delimiters(DArray<const char> str, DArray<const char> set, std::function<void(DArray<const char>)> dg)
	{
		delimitersBreak(str, set, [&](DArray<const char> s) { dg(s); return true; });
	}

	void delimitersBreak(DArray<const char> str, DArray<const char> set, std::function<bool(DArray<const char>)> dg)
	{
		const char* pos;
		size_t mark = 0;
		auto end = str.ptr + str.length;
		auto next = str.ptr;

		if(set.length == 1)
		{
			auto ch = set[0];

			while((pos = cast(const char*)memchr(next, ch, end - next)) != nullptr)
			{
				if(!dg(str.slice(mark, pos - str.ptr)))
					return;

				mark = (pos - str.ptr) + 1;
				next = str.ptr + mark;
			}
		}
		else if(set.length > 1)
		{
			size_t i = 0;
			for(auto ch: str)
			{
				if(memchr(set.ptr, ch, set.length) != nullptr)
				{
					if(!dg(str.slice(mark, i)))
						return;

					mark = i + 1;
				}

				i++;
			}
		}

		if(mark <= str.length)
			dg(str.slice(mark, str.length));
	}

	// =================================================================================================================
	// Patterns

	void patterns(DArray<const char> str, DArray<const char> pat, std::function<void(DArray<const char>)> dg)
	{
		patternsRepBreak(str, pat, DArray<const char>(), [&](DArray<const char> s) { dg(s); return true; });
	}

	void patternsBreak(DArray<const char> str, DArray<const char> pat, std::function<bool(DArray<const char>)> dg)
	{
		patternsRepBreak(str, pat, DArray<const char>(), dg);
	}

	void patternsRep(DArray<const char> str, DArray<const char> pat, DArray<const char> rep,
		std::function<void(DArray<const char>)> dg)
	{
		patternsRepBreak(str, pat, rep, [&](DArray<const char> s) { dg(s); return true; });
	}

	void patternsRepBreak(DArray<const char> str, DArray<const char> pat, DArray<const char> rep,
		std::function<bool(DArray<const char>)> dg)
	{
		size_t pos;
		size_t mark = 0;

		while((pos = strLocate(str, pat, mark)) < str.length)
		{
			if(!dg(str.slice(mark, pos)))
				return;

			if(rep.length > 0 && !dg(rep))
				return;

			mark = pos + pat.length;
		}

		if(mark <= str.length)
			dg(str.slice(mark, str.length));
	}

	// =================================================================================================================
	// lines

	void lines(DArray<const char> str, std::function<void(DArray<const char>)> dg)
	{
		linesBreak(str, [&](DArray<const char> s) { dg(s); return true; });
	}

	void linesBreak(DArray<const char> str, std::function<bool(DArray<const char>)> dg)
	{
		const char* pos;
		size_t mark = 0;
		auto end = str.ptr + str.length;
		auto next = str.ptr;

		while((pos = cast(const char*)memchr(next, '\n', end - next)) != nullptr)
		{
			auto end = pos;

			if(end > str.ptr && end[-1] == '\r')
				end--;

			if(!dg(str.slice(mark, end - str.ptr)))
				return;

			mark = (pos - str.ptr) + 1;
			next = str.ptr + mark;
		}

		if(mark <= str.length)
			dg(str.slice(mark, str.length));
	}
}