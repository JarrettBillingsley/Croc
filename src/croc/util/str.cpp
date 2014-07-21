#include <string.h>

#include "croc/util/str.hpp"

namespace croc
{
	// =================================================================================================================
	// UTF-8
	// =================================================================================================================

	size_t findCharFast(custring str, uchar ch)
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
				// clear matching segments
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

	size_t strLocate(custring source, custring match, size_t start)
	{
		if(match.length == 1)
			return strLocateChar(source, match[0], start);
		else
			return strLocatePattern(source, match, start);
	}

	size_t strLocateChar(custring source, uchar match, size_t start)
	{
		if(start > source.length)
			start = source.length;

		return findCharFast(custring::n(source.ptr + start, source.length - start), match) + start;
	}

	size_t strLocatePattern(custring source, custring match, size_t start)
	{
		if(source.length)
		{
			size_t idx;
			const uchar* p = source.ptr + start;
			size_t extent = source.length - start - match.length + 1;

			if(match.length && extent <= source.length)
			{
				while(extent)
				{
					idx = findCharFast(custring::n(p, extent), match[0]);

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
		}

		return source.length;
	}

	size_t strRLocate(custring source, custring match)
	{
		return strRLocate(source, match, source.length);
	}

	size_t strRLocate(custring source, custring match, size_t start)
	{
		if(match.length == 1)
			return strRLocateChar(source, match[0], start);
		else
			return strRLocatePattern(source, match, start);
	}

	size_t strRLocateChar(custring source, uchar match)
	{
		return strRLocateChar(source, match, source.length);
	}

	size_t strRLocateChar(custring source, uchar match, size_t start)
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

	size_t strRLocatePatterh(custring source, custring match)
	{
		return strRLocatePattern(source, match, source.length);
	}

	size_t strRLocatePattern(custring source, custring match, size_t start)
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

	bool strEqFast(const uchar* s1, const uchar* s2, size_t length)
	{
		return strMismatchFast(s1, s2, length) == length;
	}

	size_t strMismatchFast(const uchar* s1, const uchar* s2, size_t length)
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

	custring strTrimWS(custring str)
	{
		if(str.length == 0)
			return str;

		auto head = str.ptr;
		auto tail = str.ptr + str.length;

		for(auto c = head[0]; head < tail && IS_WHITESPACE(c); c = (++head)[0]) {}
		for(auto c = tail[-1]; tail > head && IS_WHITESPACE(c); c = (--tail)[-1]) {}

		return custring::n(head, tail - head);
	}

	custring strTrimlWS(custring str)
	{
		if(str.length == 0)
			return str;

		auto head = str.ptr;
		auto tail = str.ptr + str.length;

		for(auto c = head[0]; head < tail && IS_WHITESPACE(c); c = (++head)[0]) {}

		return custring::n(head, tail - head);
	}

	custring strTrimrWS(custring str)
	{
		if(str.length == 0)
			return str;

		auto head = str.ptr;
		auto tail = str.ptr + str.length;

		for(auto c = tail[-1]; tail > head && IS_WHITESPACE(c); c = (--tail)[-1]) {}

		return custring::n(head, tail - head);
	}

	// =================================================================================================================
	// Delimiters

	void delimiters(custring str, custring set, std::function<void(custring)> dg)
	{
		delimitersBreak(str, set, [&](custring s) { dg(s); return true; });
	}

	void delimitersBreak(custring str, custring set, std::function<bool(custring)> dg)
	{
		if(str.length == 0)
			return;

		const uchar* pos;
		size_t mark = 0;
		auto end = str.ptr + str.length;
		auto next = str.ptr;

		if(set.length == 1)
		{
			auto ch = set[0];

			while((pos = cast(const uchar*)memchr(next, ch, end - next)) != nullptr)
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

	void patterns(custring str, custring pat, std::function<void(custring)> dg)
	{
		patternsRepBreak(str, pat, custring(), [&](custring s) { dg(s); return true; });
	}

	void patternsBreak(custring str, custring pat, std::function<bool(custring)> dg)
	{
		patternsRepBreak(str, pat, custring(), dg);
	}

	void patternsRep(custring str, custring pat, custring rep,
		std::function<void(custring)> dg)
	{
		patternsRepBreak(str, pat, rep, [&](custring s) { dg(s); return true; });
	}

	void patternsRepBreak(custring str, custring pat, custring rep, std::function<bool(custring)> dg)
	{
		if(str.length == 0)
			return;

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

	void lines(custring str, std::function<void(custring)> dg)
	{
		linesBreak(str, [&](custring s) { dg(s); return true; });
	}

	void linesBreak(custring str, std::function<bool(custring)> dg)
	{
		const uchar* pos;
		size_t mark = 0;
		auto end = str.ptr + str.length;
		auto next = str.ptr;

		while((pos = cast(const uchar*)memchr(next, '\n', end - next)) != nullptr)
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

	// =================================================================================================================
	// UTF-32
	// =================================================================================================================

	size_t findCharFast(cdstring str, dchar ch)
	{
		for(auto p = str.ptr, e = str.ptr + str.length; p < e; p++)
		{
			if(*p == ch)
				return cast(size_t)(p - str.ptr);
		}

		return str.length;
	}

	size_t strLocate(cdstring source, cdstring match, size_t start)
	{
		if(match.length == 1)
			return strLocateChar(source, match[0], start);
		else
			return strLocatePattern(source, match, start);
	}

	size_t strLocateChar(cdstring source, dchar match, size_t start)
	{
		if(start > source.length)
			start = source.length;

		return findCharFast(cdstring::n(source.ptr + start, source.length - start), match) + start;
	}

	size_t strLocatePattern(cdstring source, cdstring match, size_t start)
	{
		if(source.length)
		{
			size_t idx;
			const dchar* p = source.ptr + start;
			size_t extent = source.length - start - match.length + 1;

			if(match.length && extent <= source.length)
			{
				while(extent)
				{
					idx = findCharFast(cdstring::n(p, extent), match[0]);

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
		}

		return source.length;
	}

	size_t strRLocate(cdstring source, cdstring match, size_t start)
	{
		if(match.length == 1)
			return strRLocateChar(source, match[0], start);
		else
			return strRLocatePattern(source, match, start);
	}

	size_t strRLocateChar(cdstring source, dchar match, size_t start)
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

	size_t strRLocatePattern(cdstring source, cdstring match, size_t start)
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

	bool strEqFast(const dchar* s1, const dchar* s2, size_t length)
	{
		return strMismatchFast(s1, s2, length) == length;
	}

	size_t strMismatchFast(const dchar* s1, const dchar* s2, size_t length)
	{
		auto i = length;

		for(auto p = s1; i--; )
		{
			if(*p++ != *s2++)
				return p - s1 - 1;
		}

		return length;
	}

	cdstring strTrimWS(cdstring str)
	{
		if(str.length == 0)
			return str;

		auto head = str.ptr;
		auto tail = str.ptr + str.length;

		for(auto c = head[0]; head < tail && IS_WHITESPACE(c); c = (++head)[0]) {}
		for(auto c = tail[-1]; tail > head && IS_WHITESPACE(c); c = (--tail)[-1]) {}

		return cdstring::n(head, tail - head);
	}

	cdstring strTrimlWS(cdstring str)
	{
		if(str.length == 0)
			return str;

		auto head = str.ptr;
		auto tail = str.ptr + str.length;

		for(auto c = head[0]; head < tail && IS_WHITESPACE(c); c = (++head)[0]) {}

		return cdstring::n(head, tail - head);
	}

	cdstring strTrimrWS(cdstring str)
	{
		if(str.length == 0)
			return str;

		auto head = str.ptr;
		auto tail = str.ptr + str.length;

		for(auto c = tail[-1]; tail > head && IS_WHITESPACE(c); c = (--tail)[-1]) {}

		return cdstring::n(head, tail - head);
	}

	// =================================================================================================================
	// Delimiters

	void delimiters(cdstring str, cdstring set, std::function<void(cdstring)> dg)
	{
		delimitersBreak(str, set, [&](cdstring s) { dg(s); return true; });
	}

	void delimitersBreak(cdstring str, cdstring set, std::function<bool(cdstring)> dg)
	{
		if(str.length == 0)
			return;

		size_t pos;
		size_t mark = 0;

		if(set.length == 1)
		{
			auto ch = set[0];

			while((pos = findCharFast(str, ch)) != str.length)
			{
				if(!dg(str.slice(mark, pos)))
					return;

				mark = pos + 1;
			}
		}
		else if(set.length > 1)
		{
			size_t i = 0;
			for(auto ch: str)
			{
				if(findCharFast(set, ch) != set.length)
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

	void patterns(cdstring str, cdstring pat, std::function<void(cdstring)> dg)
	{
		patternsRepBreak(str, pat, cdstring(), [&](cdstring s) { dg(s); return true; });
	}

	void patternsBreak(cdstring str, cdstring pat, std::function<bool(cdstring)> dg)
	{
		patternsRepBreak(str, pat, cdstring(), dg);
	}

	void patternsRep(cdstring str, cdstring pat, cdstring rep, std::function<void(cdstring)> dg)
	{
		patternsRepBreak(str, pat, rep, [&](cdstring s) { dg(s); return true; });
	}

	void patternsRepBreak(cdstring str, cdstring pat, cdstring rep, std::function<bool(cdstring)> dg)
	{
		if(str.length == 0)
			return;

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

	void lines(cdstring str, std::function<void(cdstring)> dg)
	{
		linesBreak(str, [&](cdstring s) { dg(s); return true; });
	}

	void linesBreak(cdstring str, std::function<bool(cdstring)> dg)
	{
		size_t pos;
		size_t mark = 0;

		while((pos = findCharFast(str, '\n')) != str.length)
		{
			auto end = pos;

			if(end > 0 && str[end - 1] == '\r')
				end--;

			if(!dg(str.slice(mark, end)))
				return;

			mark = pos + 1;
		}

		if(mark <= str.length)
			dg(str.slice(mark, str.length));
	}

	// =================================================================================================================
	// conversion

	const uchar* Lowercase = cast(const uchar*)"0123456789abcdefghijklmnopqrstuvwxyz";
	const uchar* Uppercase = cast(const uchar*)"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";

	size_t intToString(ustring buf, uint64_t x, size_t radix, bool isUppercase)
	{
		auto chars = isUppercase ? Uppercase : Lowercase;
		auto dest = buf.ptr + buf.length;

		size_t total = 0;

		do
		{
			*--dest = chars[cast(size_t)(x % radix)];
			total++;
		} while(x /= radix);

		return total;
	}
}