/******************************************************************************
This module contains the 'string' standard library.

License:
Copyright (c) 2008 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module croc.stdlib_string;

import tango.text.convert.Float;
import tango.text.convert.Integer;
import tango.text.convert.Utf;
import tango.text.Util;

alias tango.text.convert.Float.toFloat Float_toFloat;
alias tango.text.convert.Integer.toInt Integer_toInt;
alias tango.text.convert.Utf.cropRight Utf_cropRight;
alias tango.text.convert.Utf.decode Utf_decode;
alias tango.text.convert.Utf.toString Utf_toString;
alias tango.text.Util.trim trim;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_format;
import croc.ex_library;
// import croc.stdlib_stringbuffer;
import croc.types;
import croc.utils;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initStringLib(CrocThread* t)
{
	makeModule(t, "string", function uword(CrocThread* t)
	{
		// initStringBuffer(t);

		newNamespace(t, "string");
			registerFields(t, _methodFuncs);
		setTypeMT(t, CrocValue.Type.String);

		return 0;
	});

	importModuleNoNS(t, "string");
}

version(CrocBuiltinDocs) void docStringLib(CrocThread* t)
{
	pushGlobal(t, "string");

	scope doc = new CrocDoc(t, __FILE__);
	doc.push(Docs("module", "string",
	`The string library provides functionality for manipulating strings. Most of these functions are accessed as methods of
	string objects. These are indicated as \tt{s.methodName} in the following docs.

	Remember that strings in Croc are immutable. Therefore these functions never operate on the object on which they were
	called. They will always return new strings distinct from the original string.`));

	// docStringBuffer(t, doc);

	getTypeMT(t, CrocValue.Type.String);
		docFields(t, doc, _methodFuncDocs);
	pop(t);

	doc.pop(-1);
	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

// ===================================================================================================================================
// Methods

const uword VSplitMax = 20;

const RegisterFunc[] _methodFuncs =
[
	{"format",       &_format},
	{"join",         &_join,         maxParams: 1},
	{"vjoin",        &_vjoin},
	{"toInt",        &_toInt,        maxParams: 1},
	{"toFloat",      &_toFloat,      maxParams: 0},
	{"compare",      &_compare,      maxParams: 1},
	{"find",         &_find,         maxParams: 2},
	{"rfind",        &_rfind,        maxParams: 2},
	{"repeat",       &_repeat,       maxParams: 1},
	{"reverse",      &_reverse,      maxParams: 0},
	{"split",        &_split,        maxParams: 1},
	{"splitWS",      &_splitWS,      maxParams: 0},
	{"vsplit",       &_vsplit,       maxParams: 1},
	{"vsplitWS",     &_vsplitWS,     maxParams: 0},
	{"splitLines",   &_splitLines,   maxParams: 0},
	{"vsplitLines",  &_vsplitLines,  maxParams: 0},
	{"strip",        &_strip,        maxParams: 0},
	{"lstrip",       &_lstrip,       maxParams: 0},
	{"rstrip",       &_rstrip,       maxParams: 0},
	{"replace",      &_replace,      maxParams: 2},
	{"opApply",      &_opApply,      maxParams: 1},
	{"startsWith",   &_startsWith,   maxParams: 1},
	{"endsWith",     &_endsWith,     maxParams: 1},
];

uword _format(CrocThread* t)
{
	uint sink(char[] s)
	{
		if(s.length)
			pushString(t, s);

		return s.length;
	}

	checkStringParam(t, 0);
	auto startSize = stackSize(t);
	formatImpl(t, 0, startSize, &sink);
	cat(t, stackSize(t) - startSize);
	return 1;
}

uword _join(CrocThread* t)
{
	auto sep = checkStringParam(t, 0);
	checkParam(t, 1, CrocValue.Type.Array);
	auto arr = getArray(t, 1).toArray();

	if(arr.length == 0)
	{
		pushString(t, "");
		return 1;
	}

	foreach(i, ref val; arr)
		if(val.value.type != CrocValue.Type.String && val.value.type != CrocValue.Type.Char)
			throwStdException(t, "TypeException", "Array element {} is not a string or char", i);

	auto s = StrBuffer(t);

	if(arr[0].value.type == CrocValue.Type.String)
		s.addString(arr[0].value.mString.toString());
	else
		s.addChar(arr[0].value.mChar);

	if(sep.length == 0)
	{
		foreach(ref val; arr[1 .. $])
		{
			if(val.value.type == CrocValue.Type.String)
				s.addString(val.value.mString.toString());
			else
				s.addChar(val.value.mChar);
		}
	}
	else
	{
		foreach(ref val; arr[1 .. $])
		{
			s.addString(sep);

			if(val.value.type == CrocValue.Type.String)
				s.addString(val.value.mString.toString());
			else
				s.addChar(val.value.mChar);
		}
	}

	s.finish();
	return 1;
}

uword _vjoin(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	checkStringParam(t, 0);

	if(numParams == 0)
	{
		pushString(t, "");
		return 1;
	}

	for(uword i = 1; i <= numParams; i++)
		if(!isString(t, i) && !isChar(t, i))
			paramTypeError(t, i, "char|string");

	if(numParams == 1)
	{
		pushToString(t, 1);
		return 1;
	}

	if(len(t, 0) == 0)
	{
		cat(t, numParams);
		return 1;
	}

	for(uword i = 1; i < numParams; i++)
	{
		dup(t, 0);
		insert(t, i * 2);
	}

	cat(t, numParams + numParams - 1);
	return 1;
}

uword _toInt(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	auto src = checkStringParam(t, 0);

	int base = 10;

	if(numParams > 0)
		base = cast(int)getInt(t, 1);

	pushInt(t, safeCode(t, "exceptions.ValueException", Integer_toInt(src, base)));
	return 1;
}

uword _toFloat(CrocThread* t)
{
	pushFloat(t, safeCode(t, "exceptions.ValueException", Float_toFloat(checkStringParam(t, 0))));
	return 1;
}

uword _compare(CrocThread* t)
{
	pushInt(t, scmp(checkStringParam(t, 0), checkStringParam(t, 1)));
	return 1;
}

uword _commonFind(bool reverse)(CrocThread* t)
{
	// Source (search) string
	auto src = checkStringParam(t, 0);
	auto srcLen = len(t, 0);

	// Pattern (searched) string/char
	checkAnyParam(t, 1);

	char[6] buf = void;
	char[] pat;

	if(isString(t, 1))
		pat = getString(t, 1);
	else if(isChar(t, 1))
	{
		dchar[1] dc = getChar(t, 1);
		pat = Utf_toString(dc[], buf);
	}
	else
		paramTypeError(t, 1, "char|string");

	// Start index
	static if(reverse)
		auto start = optIntParam(t, 2, src.length - 1);
	else
		auto start = optIntParam(t, 2, 0);

	if(start < 0)
		start += srcLen;

	if(start < 0 || start >= srcLen)
		throwStdException(t, "BoundsException", "Invalid start index {}", start);

	// Search
	static if(reverse)
		pushInt(t, uniByteIdxToCP(src, src.locatePatternPrior(pat, uniCPIdxToByte(src, cast(uword)start))));
	else
		pushInt(t, uniByteIdxToCP(src, src.locatePattern(pat, uniCPIdxToByte(src, cast(uword)start))));

	return 1;
}

alias _commonFind!(false) _find;
alias _commonFind!(true) _rfind;

uword _repeat(CrocThread* t)
{
	checkStringParam(t, 0);
	auto numTimes = checkIntParam(t, 1);

	if(numTimes < 0)
		throwStdException(t, "RangeException", "Invalid number of repetitions: {}", numTimes);

	auto buf = StrBuffer(t);

	for(crocint i = 0; i < numTimes; i++)
	{
		dup(t, 0);
		buf.addTop();
	}

	buf.finish();
	return 1;
}

uword _reverse(CrocThread* t)
{
	auto src = checkStringParam(t, 0);

	if(len(t, 0) <= 1)
		dup(t, 0);
	else if(src.length <= 256)
	{
		char[256] buf = void;
		auto s = buf[0 .. src.length];
		s[] = src[];
		s.reverse;
		pushString(t, s);
	}
	else
	{
		auto tmp = t.vm.alloc.allocArray!(char)(src.length);
		scope(exit) t.vm.alloc.freeArray(tmp);

		tmp[] = src[];
		tmp.reverse;
		pushString(t, tmp);
	}

	return 1;
}

uword _split(CrocThread* t)
{
	auto src = checkStringParam(t, 0);
	auto splitter = checkStringParam(t, 1);
	auto ret = newArray(t, 0);
	uword num = 0;

	foreach(piece; src.patterns(splitter))
	{
		pushString(t, piece);
		num++;

		if(num >= 50)
		{
			cateq(t, ret, num);
			num = 0;
		}
	}

	if(num > 0)
		cateq(t, ret, num);

	return 1;
}

uword _vsplit(CrocThread* t)
{
	auto src = checkStringParam(t, 0);
	auto splitter = checkStringParam(t, 1);
	uword num = 0;

	foreach(piece; src.patterns(splitter))
	{
		pushString(t, piece);
		num++;

		if(num > VSplitMax)
			throwStdException(t, "ValueException", "Too many (>{}) parts when splitting string", VSplitMax);
	}

	return num;
}

uword _splitWS(CrocThread* t)
{
	auto src = checkStringParam(t, 0);
	auto ret = newArray(t, 0);
	uword num = 0;

	foreach(piece; src.delimiters(" \t\v\r\n\f\u2028\u2029"))
	{
		if(piece.length > 0)
		{
			pushString(t, piece);
			num++;

			if(num >= 50)
			{
				cateq(t, ret, num);
				num = 0;
			}
		}
	}

	if(num > 0)
		cateq(t, ret, num);

	return 1;
}

uword _vsplitWS(CrocThread* t)
{
	auto src = checkStringParam(t, 0);
	uword num = 0;

	foreach(piece; src.delimiters(" \t\v\r\n\f\u2028\u2029"))
	{
		if(piece.length > 0)
		{
			pushString(t, piece);
			num++;

			if(num > VSplitMax)
				throwStdException(t, "ValueException", "Too many (>{}) parts when splitting string", VSplitMax);
		}
	}

	return num;
}

uword _splitLines(CrocThread* t)
{
	auto src = checkStringParam(t, 0);
	auto ret = newArray(t, 0);
	uword num = 0;

	foreach(line; src.lines())
	{
		pushString(t, line);
		num++;

		if(num >= 50)
		{
			cateq(t, ret, num);
			num = 0;
		}
	}

	if(num > 0)
		cateq(t, ret, num);

	return 1;
}

uword _vsplitLines(CrocThread* t)
{
	auto src = checkStringParam(t, 0);
	uword num = 0;

	foreach(line; src.lines())
	{
		pushString(t, line);
		num++;

		if(num > VSplitMax)
			throwStdException(t, "ValueException", "Too many (>{}) parts when splitting string", VSplitMax);
	}

	return num;
}

uword _strip(CrocThread* t)
{
	pushString(t, checkStringParam(t, 0).trim());
	return 1;
}

uword _lstrip(CrocThread* t)
{
	pushString(t, checkStringParam(t, 0).triml());
	return 1;
}

uword _rstrip(CrocThread* t)
{
	pushString(t, checkStringParam(t, 0).trimr());
	return 1;
}

uword _replace(CrocThread* t)
{
	auto src = checkStringParam(t, 0);
	auto from = checkStringParam(t, 1);
	auto to = checkStringParam(t, 2);
	auto buf = StrBuffer(t);

	foreach(piece; src.patterns(from, to))
		buf.addString(piece);

	buf.finish();
	return 1;
}

uword _iterator(CrocThread* t)
{
	checkStringParam(t, 0);
	auto s = getStringObj(t, 0);
	auto fakeIdx = checkIntParam(t, 1) + 1;

	getUpval(t, 0);
	auto realIdx = getInt(t, -1);
	pop(t);

	if(realIdx >= s.length)
		return 0;

	uint ate = void;
	auto c = Utf_decode(s.toString()[cast(uword)realIdx .. $], ate);
	realIdx += ate;

	pushInt(t, realIdx);
	setUpval(t, 0);

	pushInt(t, fakeIdx);
	pushChar(t, c);
	return 2;
}

uword _iteratorReverse(CrocThread* t)
{
	checkStringParam(t, 0);
	auto s = getStringObj(t, 0);
	auto fakeIdx = checkIntParam(t, 1) - 1;

	getUpval(t, 0);
	auto realIdx = getInt(t, -1);
	pop(t);

	if(realIdx <= 0)
		return 0;

	auto tmp = Utf_cropRight(s.toString[0 .. cast(uword)realIdx - 1]);
	uint ate = void;
	auto c = Utf_decode(s.toString()[tmp.length .. $], ate);

	pushInt(t, tmp.length);
	setUpval(t, 0);

	pushInt(t, fakeIdx);
	pushChar(t, c);
	return 2;
}

uword _opApply(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.String);

	if(optStringParam(t, 1, "") == "reverse")
	{
		pushInt(t, getStringObj(t, 0).length);
		newFunction(t, &_iteratorReverse, "iteratorReverse", 1);
		dup(t, 0);
		pushInt(t, len(t, 0));
	}
	else
	{
		pushInt(t, 0);
		newFunction(t, &_iterator, "iterator", 1);
		dup(t, 0);
		pushInt(t, -1);
	}

	return 3;
}

uword _startsWith(CrocThread* t)
{
	pushBool(t, checkStringParam(t, 0).startsWith(checkStringParam(t, 1)));
	return 1;
}

uword _endsWith(CrocThread* t)
{
	pushBool(t, checkStringParam(t, 0).endsWith(checkStringParam(t, 1)));
	return 1;
}

version(CrocBuiltinDocs)
{
	const Docs[] _methodFuncDocs =
	[
		{kind: "function", name: "s.format",
		params: [Param("vararg", "vararg")],
		docs:
		`Functions much like Tango's tango.text.convert.Layout class. \tt{this} is a formatting string, in
		which may be embedded formatting specifiers, which use the same '\tt{{\}}' syntax as found in Tango,
		.Net, and ICU.

		By default, when you format an item, it will call any \b{\tt{toString}} metamethod defined for it.
		If you want to use the "raw" formatting for a parameter instead, write a lowercase 'r' immediately
		after the opening brace of a format specifier. So something like "\tt{format("{r\}", [1, 2, 3])}"
		will call \link{rawToString} on the array parameter, resulting in something like "\tt{array 0x00000000}"
		instead of a string representation of the contents of the array.

		Just about everything else works exactly as it does in Tango. You can use any field width and formatting
		characters that Tango allows.

		Croc's \link{writef} and \link{writefln} functions (as well as their analogues in the IO library) use
		the same internal formatting as this function, so any rules that apply here apply for those functions as
		well.`},

		{kind: "function", name: "s.join",
		params: [Param("arr", "array")],
		docs:
		`The inverse of the \link{split} method. This joins together the elements of \tt{arr} using \tt{s} as the separator. The
		elements of \tt{arr} must all be characters or strings. If \tt{s} is the empty string, this just concatenates all the
		elements of \tt{arr} together. If \tt{#arr} is 0, returns the empty string. If \tt{#arr} is 1, returns \tt{arr[0]} as a
		string (so a single character will be converted to a string). Otherwise, returns the elements joined sequentially with the
		separator \tt{s} between each pair of arguments. So "\tt{".".join(["apple", "banana", "orange"])}" will yield
		the string \tt{"apple.banana.orange"}.

		\throws[exceptions.TypeException] if any element of \tt{arr} is not a string or character.`},

		{kind: "function", name: "s.vjoin",
		params: [Param("vararg", "vararg")],
		docs:
		`Similar to \link{join}, but joins its list of variadic parameters instead of an array. The functionality is otherwise
		identical. So "\tt{".".join("apple", "banana", "orange")}" will yield the string \tt{"apple.banana.orange"}.

		\throws[exceptions.TypeException] if any of the varargs is not a string or character.`},

		{kind: "function", name: "s.toInt",
		params: [Param("base", "int", "10")],
		docs:
		`Converts the string into an integer. The optional \tt{base} parameter defaults to 10, but you can use any base between
		2 and 36 inclusive.

		\throws[exceptions.ValueException] if the string does not follow the format of an integer.`},

		{kind: "function", name: "s.toFloat",
		docs:
		`Converts the string into a float.

		\throws[exceptions.ValueException] if the string does not follow the format of a float.`},

		{kind: "function", name: "s.compare",
		params: [Param("other", "string")],
		docs:
		`Compares the string to the string \tt{other}, and returns an integer. If \tt{s} is less than (alphabetically) \tt{other},
		the return is negative; if they are the same, the return is 0; and otherwise, the return is positive. This does not perform
		language-sensitive collation; this is a pure codepoint comparison. Note that the exact same functionality can be
		achieved by using the \tt{<=>} operator on two strings.`},

		{kind: "function", name: "s.find",
		params: [Param("sub", "string|char"), Param("start", "int", "0")],
		docs:
		`Searches for an occurence of \tt{sub} in \tt{s}. \tt{sub} can be either a string or a single character. The search starts
		from \tt{start} (which defaults to the first character) and goes right. If \tt{sub} is found, this function returns the integer
		index of the occurrence in the string, with 0 meaning the first character. Otherwise, if \tt{sub} cannot be found, \tt{#s}
		is returned.

		If \tt{start < 0} it is treated as an index from the end of the string. If \tt{start >= #s} then this function simply returns
		\tt{#s} (that is, it didn't find anything).

		\throws[exceptions.BoundsException] if \tt{start} is negative and out-of-bounds (that is, \tt{abs(start) > #s}).`},

		{kind: "function", name: "s.rfind",
		params: [Param("sub", "string|char"), Param("start", "int", "#s")],
		docs:
		`Reverse find. Works similarly to \tt{find}, but the search starts with the character at \tt{start - 1} (which defaults to
		the last character) and goes \em{left}. \tt{start} is not included in the search so you can use the result of this function
		as the \tt{start} parameter to successive calls. If \tt{sub} is found, this function returns the integer index of the occurrence
		in the string, with 0 meaning the first character. Otherwise, if \tt{sub} cannot be found, \tt{#s} is returned.

		If \tt{start < 0} it is treated as an index from the end of the string.

		\throws[exceptions.BoundsException] if \tt{start >= #s} or if \tt{start} is negative an out-of-bounds (that is, \tt{abs(start > #s}).`},

		{kind: "function", name: "s.repeat",
		params: [Param("n", "int")],
		docs:
		`\returns a string which is the concatenation of \tt{n} instances of \tt{s}. So \tt{"hello".repeat(3)} will return
		\tt{"hellohellohello"}. If \tt{n == 0}, returns the empty string.

		\throws[exceptions.RangeException] if \tt{n < 0}.`},

		{kind: "function", name: "s.reverse",
		docs:
		`Returns a string which is the reversal of \tt{s}.`},

		{kind: "function", name: "s.split",
		params: [Param("delim", "string")],
		docs:
		`The inverse of the \link{join} method. Splits \tt{s} into pieces and returns an array of the split pieces.

		\param[delim] specifies a delimiting string where \tt{s} will be split. Thus \tt{"one--two--three".split("--")} will return
		\tt{["one", "two", "three"]}.`},

		{kind: "function", name: "s.splitWS",
		docs:
		`Similar to \link{split}, but splits at whitespace (spaces, tabs, newlines etc.), and all the whitespace is stripped from the split
		pieces. Thus \tt{"one\\t\\ttwo".split()} will return \tt{["one", "two"]}.`},

		{kind: "function", name: "s.vsplit",
		params: [Param("delim", "string", "null")],
		docs:
		`Similar to \link{split}, but instead of returning an array, returns the split pieces as multiple return values. It's the inverse
		of \link{vjoin}. \tt{"one--two".split("--")} will return \tt{"one", "two"}. If the string splits into more than 20 pieces, an error
		will be thrown (as returning many values can be a memory problem). Otherwise the behavior is identical to \link{split}.`},

		{kind: "function", name: "s.vsplitWS",
		docs:
		`Similar to \link{vsplit} in that it returns multiple values, but works like \link{splitWS} instead. \tt{"one\\t\\ttwo".split()} will
		return \tt{"one", "two"}. If the string splits into more than 20 pieces, an error will be thrown (as returning many values can be a
		memory problem). Otherwise the behavior is identical to \link{splitWS}.`},

		{kind: "function", name: "s.splitLines",
		docs:
		`This will split the string at any newline characters (\tt{'\\n'}, \tt{'\\r'}, or \tt{'\\r\\n'}). Other whitespace is preserved, and empty
		lines are preserved. This returns an array of strings, each of which holds one line of text.`},

		{kind: "function", name: "s.vsplitLines",
		docs:
		`Similar to \link{splitLines}, but instead of returning an array, returns the split lines as multiple return values. If the string
		splits into more than 20 lines, an error will be thrown. Otherwise the behavior is identical to \link{splitLines}.`},

		{kind: "function", name: "s.strip",
		docs:
		`Strips any whitespace from the beginning and end of the string.`},

		{kind: "function", name: "s.lstrip",
		docs:
		`Strips any whitespace from just the beginning of the string.`},

		{kind: "function", name: "s.rstrip",
		docs:
		`Strips any whitespace from just the end of the string.`},

		{kind: "function", name: "s.replace",
		params: [Param("from", "string"), Param("to", "string")],
		docs:
		`Replaces any occurrences in \tt{s} of the string \tt{from} with the string \tt{to}.`},

		{kind: "function", name: "s.opApply",
		params: [Param("reverse", "string", "null")],
		docs:
		`This function allows you to iterate over the characters of a string with a \tt{foreach} loop.

\code
foreach(i, v; "hello")
	writeln("string[", i, "] = ", v)

foreach(i, v; "hello", "reverse")
	writeln("string[", i, "] = ", v)
\endcode

		As this example shows, if you pass "reverse" to the \b{\tt{opApply}} function, either directly or as the second
		part of the \tt{foreach} container, the iteration will go in reverse, starting at the end of the string.`},

		{kind: "function", name: "s.startsWith",
		params: [Param("other", "string")],
		docs:
		`\returns a bool of whether or not \tt{s} starts with the substring \tt{other}. This is case-sensitive.`},

		{kind: "function", name: "s.endsWith",
		params: [Param("other", "string")],
		docs:
		`\returns a bool of whether or not \tt{s} ends with the substring \tt{other}. This is case-sensitive.`},
	];
}