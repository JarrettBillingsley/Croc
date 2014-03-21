
#include <limits>
#include <stdlib.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/all.hpp"
#include "croc/stdlib/helpers/format.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"
#include "croc/util/str.hpp"

namespace croc
{
	namespace
	{
	inline crocstr checkCrocstrParam(CrocThread* t, word_t slot)
	{
		crocstr ret;
		ret.ptr = cast(const uchar*)croc_ex_checkStringParamn(t, slot, &ret.length);
		return ret;
	}

	const uword VSplitMax = 20;
	const char* Whitespace = " \t\v\r\n\f";

	template<bool reverse>
	word_t _commonFind(CrocThread* t)
	{
		auto src = checkCrocstrParam(t, 0);
		auto srcCPLen = croc_len(t, 0);
		auto pat = checkCrocstrParam(t, 1);

		if(pat.length == 0)
		{
			croc_pushInt(t, srcCPLen);
			return 1;
		}

		auto start = croc_ex_optIndexParam(t, 2, srcCPLen, "start", reverse ? (srcCPLen - 1) : 0);

		if(reverse)
			croc_pushInt(t, utf8ByteIdxToCP(src, strRLocate(src, pat, utf8CPIdxToByte(src, start))));
		else
			croc_pushInt(t, utf8ByteIdxToCP(src, strLocate(src, pat, utf8CPIdxToByte(src, start))));

		return 1;
	}

DBeginList(_methodFuncs)
	Docstr(DFunc("format") DVararg
	R"(Creates a formatted output string by converting the parameters to strings and inserting them as specified by
	\tt{this}, the format string.

	The formatting syntax resembles .Net or ICU's, using \{ curly braces \} to indicate where formatted components
	should be inserted, rather than the printf-like percent signs.

	The syntax is as follows:

\verbatim
FormatString:
	Text (FormatSpecifier Text)*

Text:
	AnythingButLeftBrace*
	'{{'

FormatSpecifier:
	'{' Index? (',' Width)? (':' Fmt)? '}'
	'{r' Index? (',' Width)? '}'

Index:
	Digit+

Width:
	Digit+

Fmt:
	AnythingButRightBrace*
\endverbatim

	Format specifiers begin with '\{' and end with '\}'. If you want to have an open-brace character in the output
	string, just double up the opening brace like '\{\{'. There is no need to double up a close-brace like this.

	Let's look at what happens when a format specifier is encountered:

	\nlist
		\li The appropriate argument is selected from the list of variadic arguments as explained above. Call it
			\em{arg}.
		\li \em{arg} is converted to a string, in some way. Call the resulting string \em{str}.
		\li \em{str} is optionally padded with spaces on one side or the other, and added to the output string.
	\endlist

	First is step 1: selecting the appropriate argument. This is the \tt{Index} in the above grammar. The index is a
	0-based index into the variadic arguments passed to this method. You can use the same parameter multiple times by
	using the same index multiple times, like in \tt{"{0} {0}".format(5)}, which will give the string \tt{"5 5"}. If no
	index is given, an internal counter is used instead. This counter starts at 0 and increases by 1 each time a format
	specifier without an index is read. So in \tt{"{} {}".format(3, 4)}, the result will be the string \tt{"3 4"}. You
	can interleave these kinds of indices. Explicit indices do not reset the counter, so \tt{"{} {0} {}".format(1, 2)}
	gives the string \tt{"1 1 2"}. Specifying an index out of the bounds of the variadic arguments is an error.

	Next is step 2: converting the argument \em{arg} to a string. There are two kinds of format specifiers, regular and
	raw, and they differ on this step.

	Raw format specifiers have a lowercase \tt{'r'} immediately after the opening brace. They can only specify a
	parameter index and a width, and no format string. A raw format specifier converts \em{arg} to a string by calling
	\link{rawToString} on it. That's it.

	A regular format specifier (one without a lowercase \tt{'r'} after the opening brace) can have an optional
	\em{format string}, which is everything between the colon and closing brace. If no format string is given,
	\link{toString} is called on \em{arg} and the resulting string is used in step 3. If a format string is given, how
	it's interpreted depends on the type of \em{arg}:

	\blist
		\li If \em{arg} is an \tt{int}, the format string must be of the format
			\tt{('+'|' ')? '#'? Width? Type?}. This is a subset of the format specifiers for C's printf family, and they
			work the same.

			The optional \tt{'+'} or \tt{' '} flags at the beginning will prepend positive numbers with a plus sign or a
			space, respectively (to make them line up nicely with negative numbers in tables).

			Next comes the optional \tt{'#'}, which changes the way binary and hexadecimal numbers are displayed.

			Then comes the number width, which is separate from the format specifier width. The number width controls
			the minimum number of digits that will be displayed; if the number is fewer than this many digits, it is
			padded with 0s to the left.

			Last comes the type, which controls the radix and signedness of the output. The type can be:

			\blist
				\li \tt{'d'} or \tt{'i'}, which outputs the number as signed base-10. This is the default.
				\li \tt{'u'}, which outputs the number as unsigned base-10. This will make negative numbers output as
					large positive numbers instead.
				\li \tt{'b'} or \tt{'B'}, which outputs the number in base 2 (binary). If the \tt{'#'} flag was given,
					the number will be prepended with \tt{'0b'} or \tt{'0B'}, respectively. These prefixes do \em{not}
					count towards the number width.
				\li \tt{'x'} or \tt{'X'}, which outputs the number in base 16 (hexadecimal). If the \tt{'#'} flag was
					given, the number will be prepended with \tt{'0x'} or \tt{'0X'}, respectively. These prefixes do
					\em{not} count towards the number width.
			\endlist
		\li If \em{arg} is a \tt{float}, the format string must be of the format
			\tt{('+'|' ')? ('.' Precision?)? Type?}. Again, this is a subset of the format specifiers for C's
			printf family, and they work the same.

			The optional \tt{'+'} or \tt{' '} flags at the beginning will prepend positive numbers with a plus sign or a
			space, respectively (to make them line up nicely with negative numbers in tables).

			Next comes the optional precision, which is just an integer and whose meaning depends on the type.

			Last is the type, which can be:

			\blist
				\li \tt{'e'} or \tt{'E'}, which outputs the number in "scientific" notation, or at least an ASCII
					version of scientific notation. For this format, the precision controls how many places appear after
					the decimal point; the default is 6. The only difference between lower- and upper-case is how the
					exponent appears (it will match the case of the type specifier).
				\li \tt{'f'} which outputs the number in "human" notation, which never uses scientific notation. The
					precision controls how many places appear after the decimal point; the default is 6.
				\li \tt{'g'} or \tt{'G'}, which outputs the number in human or scientific notation, whichever is
					shorter. The precision for this format behaves differently, as it controls the \em{maximum} number
					of digits that appear, before and after the decimal point. Trailing zeroes are also trimmed, and if
					the decimal part is zero, no decimal point is printed.
			\endlist
		\li For all other types, the format string is uninterpreted. Instead, if \em{arg} has a method named
			\tt{toStringFmt}, it will have the method called with the format string as the argument, and it should
			return a string. If there is no method of that name, or the method doesn't return a string, it is an error.
	\endlist

	Finally, we come to step 3, where the width specifier comes in. The width specifies a \em{minimum} width, in
	characters, which the outputted string for that argument (\em{str} from above) should be. If the length of \em{str}
	is less than this width, it is padded with spaces up to the width. If the length of \em{str} is the same or greater
	than the width, \em{str} is output as-is (it is \em{not} truncated down to the width).

	If the width is positive, \em{str} will be right-aligned, meaning it will be padded with spaces on the left. If the
	width is negative, \em{str} will be left-aligned, padded with spaces on the left. The default width is 0, so no
	padding will be added. Here is an example:

\code
writeln("'{}'".format(1234)) // prints '1234', no padding added
writeln("'{,0}'".format(1234)) // prints '1234', identical meaning to above
writeln("'{,6}'".format(1234)) // prints '  1234'; padded out on left to 6 characters
writeln("'{,-6}'".format(1234)) // prints '1234  '; padded out on right to 6 characters
\endcode

	\param[vararg] are the arguments to be formatted according to the format string.
	\returns the resulting string.
	)"),

	"format", -1,[](CrocThread* t) -> word_t
	{
		croc_ex_checkStringParam(t, 0);
		auto num = formatImpl(t, 0, croc_getStackSize(t) - 1);
		croc_cat(t, num);
		return 1;
	}

DListSep()
	Docstr(DFunc("join") DParam("arr", "array")
	R"(The inverse of the \link{split} method. This joins together the elements of \tt{arr} using \tt{this} as the
	separator.

	The elements of \tt{arr} must all be strings. If \tt{this} is the empty string, this just concatenates all the
	elements of \tt{arr} together. If \tt{#arr} is 0, returns the empty string. If \tt{#arr} is 1, returns \tt{arr[0]}.
	Otherwise, returns the elements joined sequentially with the separator \tt{this} between each pair of arguments. So
	"\tt{".".join(["apple", "banana", "orange"])}" will yield the string \tt{"apple.banana.orange"}.

	\throws[TypeError] if any element of \tt{arr} is not a string.)"),

	"join", 1, [](CrocThread* t) -> word_t
	{
		auto sep = checkCrocstrParam(t, 0);
		croc_ex_checkParam(t, 1, CrocType_Array);
		auto arr = getArray(Thread::from(t), 1)->toDArray();

		if(arr.length == 0)
		{
			croc_pushString(t, "");
			return 1;
		}

		uint64_t totalLen = 0;
		uword i = 0;

		for(auto &val: arr)
		{
			if(val.value.type == CrocType_String)
				totalLen += val.value.mString->length;
			else
				croc_eh_throwStd(t, "TypeError", "Array element %" CROC_SIZE_T_FORMAT " is not a string", i);

			i++;
		}

		totalLen += sep.length * (arr.length - 1);

		if(totalLen > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "ValueError", "Resulting string is too long");

		auto buf = ustring::alloc(Thread::from(t)->vm->mem, cast(uword)totalLen);
		uword pos = 0;

		i = 0;
		for(auto &val: arr)
		{
			if(i > 0 && sep.length > 0)
			{
				buf.slicea(pos, pos + sep.length, sep);
				pos += sep.length;
			}

			auto s = val.value.mString->toDArray();
			buf.slicea(pos, pos + s.length, s);
			pos += s.length;
			i++;
		}

		pushCrocstr(t, buf);
		buf.free(Thread::from(t)->vm->mem);
		return 1;
	}

DListSep()
	Docstr(DFunc("vjoin") DVararg
	R"(Like \link{join}, but joins its list of variadic parameters instead of an array. The functionality is otherwise
	identical. So "\tt{".".join("apple", "banana", "orange")}" will give the string \tt{"apple.banana.orange"}.

	\throws[TypeError] if any of the varargs is not a string.)"),

	"vjoin", -1,[](CrocThread* t) -> word_t
	{
		auto numParams = croc_getStackSize(t) - 1;
		croc_ex_checkStringParam(t, 0);

		if(numParams == 0)
		{
			croc_pushString(t, "");
			return 1;
		}

		for(uword i = 1; i <= numParams; i++)
			croc_ex_checkStringParam(t, i);

		if(numParams == 1)
		{
			croc_pushToString(t, 1);
			return 1;
		}
		else if(croc_len(t, 0) == 0)
		{
			croc_cat(t, numParams);
			return 1;
		}

		for(uword i = 1; i < numParams; i++)
		{
			croc_dup(t, 0);
			croc_insert(t, i * 2);
		}

		croc_cat(t, numParams + numParams - 1);
		return 1;
	}

DListSep()
	Docstr(DFunc("toInt") DParamD("base", "int", "10")
	R"(Converts \tt{this} into an integer. The optional \tt{base} parameter defaults to 10, but you can use any base
	between 2 and 36 inclusive.

	\throws[ValueError] if the string does not follow the format of an integer.)"),

	"toInt", 1, [](CrocThread* t) -> word_t
	{
		auto src = checkCrocstrParam(t, 0);
		auto base = croc_ex_optIntParam(t, 1, 10);

		if(src.length == 0)
			croc_eh_throwStd(t, "ValueError", "cannot convert empty string to integer");

		if(base < 2 || base > 36)
			croc_eh_throwStd(t, "RangeError", "base must be in the range [2 .. 36]");

		char* endptr;
		auto ret = strtol(cast(const char*)src.ptr, &endptr, base);

		if(cast(const uchar*)endptr != src.ptr + src.length)
			croc_eh_throwStd(t, "ValueError", "invalid integer");

		croc_pushInt(t, ret);
		return 1;
	}

DListSep()
	Docstr(DFunc("toFloat")
	R"(Converts \tt{this} into a float.

	\throws[ValueError] if the string does not follow the format of a float.)"),

	"toFloat", 0, [](CrocThread* t) -> word_t
	{
		auto src = checkCrocstrParam(t, 0);

		if(src.length == 0)
			croc_eh_throwStd(t, "ValueError", "cannot convert empty string to float");

		char* endptr;
		auto ret = strtod(cast(const char*)src.ptr, &endptr);

		if(cast(const uchar*)endptr != src.ptr + src.length)
			croc_eh_throwStd(t, "ValueError", "invalid float");

		croc_pushFloat(t, ret);
		return 1;
	}

DListSep()
	Docstr(DFunc("ord") DParamD("idx", "int", "0")
	R"(Gets the integer codepoint value of the character at the given index, which defaults to 0.

	\param[idx] is the index into \tt{this}, which can be negative.
	\returns the integer codepoint value of the character at \tt{this[idx]}.
	\throws[BoundsError] if \tt{idx} is invalid.)"),

	"ord", 1, [](CrocThread* t) -> word_t
	{
		auto s = checkCrocstrParam(t, 0);
		auto cpLen = croc_len(t, 0); // we want the CP length, not the byte length
		auto idx = croc_ex_optIndexParam(t, 1, cpLen, "codepoint", 0);
		croc_pushInt(t, utf8CharAt(s, idx));
		return 1;
	}

DListSep()
	Docstr(DFunc("find") DParam("sub", "string") DParamD("start", "int", "0")
	R"(Searches for an occurence of \tt{sub} in \tt{this}.

	The search starts from \tt{start} (which defaults to the first character) and goes right. If \tt{sub} is found, this
	function returns the integer index of the occurrence in the string, with 0 meaning the first character. Otherwise,
	if \tt{sub} cannot be found, \tt{#this} is returned.

	\tt{start} can be negative, in which case it's treated as an index from the end of the string.

	\throws[BoundsError] if \tt{start} is invalid.)"),

	"find", 2, &_commonFind<false>

DListSep()
	Docstr(DFunc("rfind") DParam("sub", "string") DParamD("start", "int", "#s - 1")
	R"(Reverse find. Works similarly to \tt{find}, but the search starts with the character at \tt{start} (which
	defaults to the last character) and goes \em{left}.

	If \tt{sub} is found, this function returns the integer index of the occurrence in the string, with 0 meaning the
	first character. Otherwise, if \tt{sub} cannot be found, \tt{#this} is returned.

	\tt{start} can be negative, in which case it's treated as an index from the end of the string.

	\throws[BoundsError] if \tt{start} is invalid.)"),

	"rfind", 2, &_commonFind<true>

DListSep()
	Docstr(DFunc("repeat") DParam("n", "int")
	R"(\returns a string which is the concatenation of \tt{n} instances of \tt{this}. So \tt{"hello".repeat(3)} will
	return \tt{"hellohellohello"}. If \tt{n == 0}, returns the empty string.

	\throws[RangeError] if \tt{n < 0}.)"),

	"repeat", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkStringParam(t, 0);
		auto numTimes = croc_ex_checkIntParam(t, 1);

		if(numTimes < 0)
			croc_eh_throwStd(t, "RangeError", "Invalid number of repetitions: %" CROC_INTEGER_FORMAT, numTimes);

		CrocStrBuffer buf;
		croc_ex_buffer_init(t, &buf);

		for(uword i = 0; i < cast(uword)numTimes; i++)
		{
			croc_dup(t, 0);
			croc_ex_buffer_addTop(&buf);
		}

		croc_ex_buffer_finish(&buf);
		return 1;
	}

DListSep()
	Docstr(DFunc("reverse")
	R"(\returns a string which is the reversal of \tt{this}. Only the codepoints are reversed; no higher-level structure
	(such as combining marks) is preserved.)"),

	"reverse", 0, [](CrocThread* t) -> word_t
	{
		auto src = checkCrocstrParam(t, 0);

		if(croc_len(t, 0) <= 1)
		{
			croc_dup(t, 0);
			return 1;
		}

		char buf[256];
		char* b;
		auto tmp = DArray<char>();

		if(src.length <= 256)
			b = buf;
		else
		{
			tmp = DArray<char>::alloc(Thread::from(t)->vm->mem, src.length);
			b = tmp.ptr;
		}

		auto s = src.ptr + src.length;
		auto prevS = s;

		for(s--, fastAlignUtf8(s); s >= src.ptr; prevS = s, s--, fastAlignUtf8(s))
		{
			for(auto p = s; p < prevS; )
				*b++ = *p++;

			if(s == src.ptr)
				break; // have to break to not read out of bounds
		}

		if(tmp.ptr)
		{
			assert(cast(uword)(b - tmp.ptr) == src.length);
			croc_pushStringn(t, tmp.ptr, src.length);
			// XXX: this might not run if croc_pushStringn fails, but it would only fail in an OOM situation, so..?
			tmp.free(Thread::from(t)->vm->mem);
		}
		else
		{
			assert(cast(uword)(b - buf) == src.length);
			croc_pushStringn(t, buf, src.length);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("split") DParam("delim", "string")
	R"(The inverse of the \link{join} method. Splits \tt{this} into pieces and returns an array of the split pieces.

	\param[delim] specifies a delimiting string where \tt{this} will be split. So \tt{"one--two--three".split("--")}
	will return \tt{["one", "two", "three"]}.)"),

	"split", 1, [](CrocThread* t) -> word_t
	{
		auto src = checkCrocstrParam(t, 0);
		auto splitter = checkCrocstrParam(t, 1);
		auto ret = croc_array_new(t, 0);
		uword_t num = 0;

		patterns(src, splitter, [&](crocstr piece)
		{
			pushCrocstr(t, piece);
			num++;

			if(num >= 50)
			{
				croc_cateq(t, ret, num);
				num = 0;
			}
		});

		if(num > 0)
			croc_cateq(t, ret, num);

		return 1;
	}

DListSep()
	Docstr(DFunc("vsplit") DParam("delim", "string")
	R"(Similar to \link{split}, but instead of returning an array, returns the split pieces as multiple return values.
	It's the inverse of \link{vjoin}.

	\tt{"one--two".split("--")} will return \tt{"one", "two"}. If the string splits into more than 20 pieces, an error
	will be thrown (as returning many values can be a memory problem). Otherwise the behavior is identical to
	\link{split}.)"),

	"vsplit", 1, [](CrocThread* t) -> word_t
	{
		auto src = checkCrocstrParam(t, 0);
		auto splitter = checkCrocstrParam(t, 1);
		uword_t num = 0;

		patterns(src, splitter, [&](crocstr piece)
		{
			pushCrocstr(t, piece);
			num++;

			if(num > VSplitMax)
				croc_eh_throwStd(t, "ValueError", "Too many (>%" CROC_SIZE_T_FORMAT ") parts when splitting string",
					VSplitMax);
		});

		return num;
	}

DListSep()
	Docstr(DFunc("splitWS")
	R"(Similar to \link{split}, but splits at whitespace (spaces, tabs, newlines etc.).

	All the whitespace is stripped from the split pieces, and there will be no empty pieces between consecutive
	whitespace characters. Thus \tt{"one\\t\\ttwo".split()} will return \tt{["one", "two"]}.)"),

	"splitWS", 0, [](CrocThread* t) -> word_t
	{
		auto src = checkCrocstrParam(t, 0);
		auto ret = croc_array_new(t, 0);
		uword_t num = 0;

		delimiters(src, atoda(Whitespace), [&](crocstr piece)
		{
			if(piece.length > 0)
			{
				pushCrocstr(t, piece);
				num++;

				if(num >= 50)
				{
					croc_cateq(t, ret, num);
					num = 0;
				}
			}
		});

		if(num > 0)
			croc_cateq(t, ret, num);

		return 1;
	}

DListSep()
	Docstr(DFunc("vsplitWS")
	R"(Like \link{splitWS}, but returns multiple values like \link{vsplit}. Again, if the string splits into more than
	20 pieces, an error will be thrown.)"),

	"vsplitWS", 0, [](CrocThread* t) -> word_t
	{
		auto src = checkCrocstrParam(t, 0);
		uword_t num = 0;

		delimiters(src, atoda(Whitespace), [&](crocstr piece)
		{
			if(piece.length > 0)
			{
				pushCrocstr(t, piece);
				num++;

				if(num > VSplitMax)
					croc_eh_throwStd(t, "ValueError", "Too many (>%" CROC_SIZE_T_FORMAT ") parts when splitting string",
						VSplitMax);
			}
		});

		return num;
	}

DListSep()
	Docstr(DFunc("splitLines")
	R"(This will split the string at any newline characters (\tt{'\\n'}, \tt{'\\r'}, or \tt{'\\r\\n'}), removing the
	line ending characters. Other whitespace is preserved, and empty lines are preserved. This returns an array of
	strings, each of which holds one line of text.)"),

	"splitLines", 0, [](CrocThread* t) -> word_t
	{
		auto src = checkCrocstrParam(t, 0);
		auto ret = croc_array_new(t, 0);
		uword_t num = 0;

		lines(src, [&](crocstr line)
		{
			pushCrocstr(t, line);
			num++;

			if(num >= 50)
			{
				croc_cateq(t, ret, num);
				num = 0;
			}
		});

		if(num > 0)
			croc_cateq(t, ret, num);

		return 1;
	}

DListSep()
	Docstr(DFunc("vsplitLines")
	R"(Like \link{splitLines}, but returns multiple values like \link{vsplit}. Same deal!)"),

	"vsplitLines", 0, [](CrocThread* t) -> word_t
	{
		auto src = checkCrocstrParam(t, 0);
		uword num = 0;

		lines(src, [&](crocstr line)
		{
			pushCrocstr(t, line);
			num++;

			if(num > VSplitMax)
				croc_eh_throwStd(t, "ValueError", "Too many (>%" CROC_SIZE_T_FORMAT ") parts when splitting string",
					VSplitMax);
		});

		return num;
	}

DListSep()
	Docstr(DFunc("strip")
	R"(Strips any whitespace from the beginning and end of the string.)"),

	"strip", 0, [](CrocThread* t) -> word_t
	{
		pushCrocstr(t, strTrimWS(checkCrocstrParam(t, 0)));
		return 1;
	}

DListSep()
	Docstr(DFunc("lstrip")
	R"(Strips any whitespace from just the beginning of the string.)"),

	"lstrip", 0, [](CrocThread* t) -> word_t
	{
		pushCrocstr(t, strTrimlWS(checkCrocstrParam(t, 0)));
		return 1;
	}

DListSep()
	Docstr(DFunc("rstrip")
	R"(Strips any whitespace from just the end of the string.)"),

	"rstrip", 0, [](CrocThread* t) -> word_t
	{
		pushCrocstr(t, strTrimrWS(checkCrocstrParam(t, 0)));
		return 1;
	}

DListSep()
	Docstr(DFunc("replace") DParam("from", "string") DParam("to", "string")
	R"(Replaces any occurrences in \tt{this} of the string \tt{from} with the string \tt{to}.)"),

	"replace", 2, [](CrocThread* t) -> word_t
	{
		auto src = checkCrocstrParam(t, 0);
		auto from = checkCrocstrParam(t, 1);
		auto to = checkCrocstrParam(t, 2);

		CrocStrBuffer buf;
		croc_ex_buffer_init(t, &buf);

		patternsRep(src, from, to, [&](crocstr piece)
		{
			croc_ex_buffer_addStringn(&buf, cast(const char*)piece.ptr, piece.length);
		});

		croc_ex_buffer_finish(&buf);
		return 1;
	}

DListSep()
	Docstr(DFunc("startsWith") DParam("other", "string")
	R"(\returns a bool indicating whether or not \tt{this} starts with the substring \tt{other}.)"),

	"startsWith", 1, [](CrocThread* t) -> word_t
	{
		auto str = checkCrocstrParam(t, 0);
		auto sub = checkCrocstrParam(t, 1);
		croc_pushBool(t, str.length >= sub.length && str.slice(0, sub.length) == sub);
		return 1;
	}

DListSep()
	Docstr(DFunc("endsWith") DParam("other", "string")
	R"(\returns a bool indicating whether or not \tt{this} ends with the substring \tt{other}.)"),

	"endsWith", 1, [](CrocThread* t) -> word_t
	{
		auto str = checkCrocstrParam(t, 0);
		auto sub = checkCrocstrParam(t, 1);
		croc_pushBool(t, str.length >= sub.length && str.slice(str.length - sub.length, str.length) == sub);
		return 1;
	}

DListSep()
	Docstr(DFunc("opApply") DParamD("mode", "string", "null")
	R"(This allows you to iterate over the individual characters of the string with a \tt{foreach} loop. It gives two
	indices, the first being the character offset and the second being the character as a string.

\code
foreach(i, v; "hello")
	writefln("string[{}] = {}", i, v)

foreach(i, v; "hello", "reverse")
	writefln("string[{}] = {}", i, v)
\endcode

	As this example shows, if you pass "reverse" as the second part of the \tt{foreach} container, the iteration
	will go in reverse, starting at the end of the string.)"),
	"opApply", 1, [](CrocThread* t) -> word_t
	{
		CrocNativeFunc _iterator = [](CrocThread* t) -> word_t
		{
			auto str = checkCrocstrParam(t, 0);
			auto fakeIdx = croc_ex_checkIntParam(t, 1) + 1;

			croc_pushUpval(t, 0);
			auto realIdx = croc_getInt(t, -1);
			croc_popTop(t);

			if(cast(uword)realIdx >= str.length)
				return 0;

			auto ptr = str.ptr + realIdx;
			auto oldPtr = ptr;
			fastDecodeUtf8Char(ptr);

			croc_pushInt(t, ptr - str.ptr);
			croc_setUpval(t, 0);

			croc_pushInt(t, fakeIdx);
			croc_pushStringn(t, cast(const char*)oldPtr, ptr - oldPtr);
			return 2;
		};

		CrocNativeFunc _iteratorReverse = [](CrocThread* t) -> word_t
		{
			auto str = checkCrocstrParam(t, 0);
			auto fakeIdx = croc_ex_checkIntParam(t, 1) - 1;

			croc_pushUpval(t, 0);
			auto realIdx = croc_getInt(t, -1);
			croc_popTop(t);

			if(realIdx <= 0)
				return 0;

			auto ptr = str.ptr + realIdx;
			auto oldPtr = ptr;
			fastReverseUtf8Char(ptr);

			croc_pushInt(t, ptr - str.ptr);
			croc_setUpval(t, 0);

			croc_pushInt(t, fakeIdx);
			croc_pushStringn(t, cast(const char*)ptr, oldPtr - ptr);
			return 2;
		};

		croc_ex_checkParam(t, 0, CrocType_String);
		auto mode = croc_ex_optStringParam(t, 1, "");

		if(strcmp(mode, "reverse") == 0)
		{
			croc_pushInt(t, getStringObj(Thread::from(t), 0)->length);
			croc_function_new(t, "iteratorReverse", 1, _iteratorReverse, 1);
			croc_dup(t, 0);
			croc_pushInt(t, croc_len(t, 0));
		}
		else
		{
			croc_pushInt(t, 0);
			croc_function_new(t, "iterator", 1, _iterator, 1);
			croc_dup(t, 0);
			croc_pushInt(t, -1);
		}

		return 3;
	}
DEndList()

	word loader(CrocThread* t)
	{
		initStringLib_StringBuffer(t);

		croc_namespace_new(t, "string");
			registerFields(t, _methodFuncs);
		croc_vm_setTypeMT(t, CrocType_String);
		return 0;
	}
	}

	void initStringLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "string", &loader);
		croc_ex_import(t, "string");
	}

#ifdef CROC_BUILTIN_DOCS
	void docStringLib(CrocThread* t)
	{
		CrocDoc doc;
		croc_ex_doc_init(t, &doc, __FILE__);
		croc_ex_doc_push(&doc,
		DModule("string")
		R"(The string library provides functionality for manipulating strings, as well as a mutable string type.)");

		croc_vm_pushTypeMT(t, CrocType_String);
			croc_ex_doc_push(&doc,
			DNs("string")
			R"(This is the method namespace for string objects. All the string manipulation functions are accessed as
			methods of strings, e.g. \tt{s.reverse()}.

			Remember that strings in Croc are immutable. These method never operate on the object on which they were
			called. They will always return new strings distinct from the original string.)");

			docFields(&doc, _methodFuncs);

			croc_ex_doc_pop(&doc, -1);
		croc_popTop(t);

		croc_pushGlobal(t, "string");
		docStringLib_StringBuffer(t, &doc);
		croc_ex_doc_pop(&doc, -1);
		croc_popTop(t);
		croc_ex_doc_finish(&doc);
	}
#endif
}