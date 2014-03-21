
#include <cmath>
#include <limits>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/format.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"
#include "croc/util/str.hpp"

namespace croc
{
	namespace
	{
	const char* Data = "data";
	const char* Length = "length";
	const uword VSplitMax = 20;
	const dchar Whitespace_[] = {' ', '\t', '\v', '\r', '\n', '\f'};
	const cdstring Whitespace = {Whitespace_, sizeof(Whitespace_) / sizeof(dchar)};

	// =================================================================================================================
	// Helpers

	Memblock* _getData(CrocThread* t, word idx = 0)
	{
		croc_hfield(t, idx, Data);

		if(!croc_isMemblock(t, -1))
			croc_eh_throwStd(t, "StateError", "Attempting to operate on an uninitialized StringBuffer");

		auto ret = getMemblock(Thread::from(t), -1);
		croc_popTop(t);
		return ret;
	}

	uword _getLength(CrocThread* t, word idx = 0)
	{
		croc_hfield(t, idx, Length);
		auto ret = cast(uword)croc_getInt(t, -1);
		croc_popTop(t);
		return ret;
	}

	void _setLength(CrocThread* t, uword l, word idx = 0)
	{
		idx = croc_absIndex(t, idx);
		croc_pushInt(t, cast(crocint)l);
		croc_hfielda(t, idx, Length);
	}

	void _ensureSize(CrocThread* t, Memblock* mb, uword size)
	{
		auto dataLength = mb->data.length >> 2;

		if(dataLength == 0)
		{
			push(Thread::from(t), Value::from(mb));
			croc_lenai(t, -1, size << 2);
			croc_popTop(t);
		}
		else if(size > dataLength)
		{
			auto l = dataLength;

			while(size > l)
			{
				if(l & (1ULL << ((sizeof(uword) * 8) - 1)))
					croc_eh_throwStd(t, "RangeError", "StringBuffer too big (%" CROC_SIZE_T_FORMAT " elements)", size);

				l <<= 1;
			}

			push(Thread::from(t), Value::from(mb));
			croc_lenai(t, -1, l << 2);
			croc_popTop(t);
		}
	}

	dstring _stringBufferAsUtf32(CrocThread* t, word idx)
	{
		auto mb = _getData(t, idx);
		return dstring::n(cast(dchar*)mb->data.ptr, _getLength(t, idx));
	}

	word _stringBufferFromUtf32(CrocThread* t, DArray<const dchar> text)
	{
		auto ret = croc_pushGlobal(t, "StringBuffer");
		croc_pushNull(t);
		croc_pushInt(t, text.length);
		croc_call(t, ret, 1);
		_setLength(t, text.length, ret);
		_stringBufferAsUtf32(t, ret).slicea(text);
		return ret;
	}

	dstring _toUtf32(crocstr str, dstring buf)
	{
		crocstr remaining;
		auto ret = Utf8ToUtf32(str, buf, remaining);
		assert(remaining.length == 0);
		return ret;
	}

	bool _isStringOrStringBuffer(CrocThread* t, word idx)
	{
		croc_ex_checkAnyParam(t, idx);

		if(croc_isString(t, idx))
			return true;

		croc_pushGlobal(t, "StringBuffer");
		auto ret = croc_isInstanceOf(t, idx, -1);
		croc_popTop(t);
		return ret;
	}

	dstring _checkStringOrStringBuffer(CrocThread* t, word idx, dstring buf, dstring& tmp)
	{
		croc_ex_checkAnyParam(t, idx);

		if(croc_isString(t, idx))
		{
			auto str = getCrocstr(t, idx);
			auto strCPLen = cast(uword)croc_len(t, idx);

			if(strCPLen <= buf.length)
				return _toUtf32(str, buf);
			else
			{
				tmp = dstring::alloc(Thread::from(t)->vm->mem, strCPLen);
				return _toUtf32(str, tmp);
			}
		}
		else
		{
			croc_pushGlobal(t, "StringBuffer");

			if(croc_isInstanceOf(t, idx, -1))
			{
				croc_popTop(t);
				return _stringBufferAsUtf32(t, idx);
			}
			else
				croc_ex_paramTypeError(t, idx, "string|StringBuffer");
		}

		assert(false);
		return dstring(); // dummy
	}

	void _fillImpl(CrocThread* t, Memblock* mb, word filler, uword lo, uword hi)
	{
		croc_pushGlobal(t, "StringBuffer");

		if(croc_isInstanceOf(t, filler, -1))
		{
			if(croc_is(t, 0, filler))
				return;

			auto other = _getData(t, filler)->data.template as<dchar>();
			auto otherLen = _getLength(t, filler);

			if(otherLen != (hi - lo))
				croc_eh_throwStd(t, "ValueError",
					"Length of destination (%" CROC_SIZE_T_FORMAT ") and length of source (%" CROC_SIZE_T_FORMAT
						") do not match",
					hi - lo, otherLen);

			mb->data.template as<dchar>().slicea(lo, hi, other.slice(0, otherLen));
		}
		else if(croc_isFunction(t, filler))
		{
			auto data = mb->data.template as<dchar>().slice(0, _getLength(t));

			for(uword i = lo; i < hi; i++)
			{
				croc_dup(t, filler);
				croc_pushNull(t);
				croc_pushInt(t, i);
				croc_call(t, -3, 1);

				if(!croc_isChar(t, -1))
				{
					croc_pushTypeString(t, -1);
					croc_eh_throwStd(t, "TypeError", "filler function expected to return a 'string', not '%s'",
						croc_getString(t, -1));
				}

				data[i] = croc_getChar(t, -1);
				croc_popTop(t);
			}
		}
		else if(croc_isString(t, filler))
		{
			auto cpLen = cast(uword)croc_len(t, filler);

			if(cpLen != (hi - lo))
				croc_eh_throwStd(t, "ValueError",
					"Length of destination (%" CROC_SIZE_T_FORMAT ") and length of source string (%" CROC_SIZE_T_FORMAT
						") do not match",
					hi - lo, cpLen);

			_toUtf32(getCrocstr(t, filler), mb->data.template as<dchar>().slice(lo, hi));
		}
		else if(croc_isArray(t, filler))
		{
			auto data = mb->data.template as<dchar>().slice(lo, hi);

			for(uword i = lo, ai = 0; i < hi; i++, ai++)
			{
				croc_idxi(t, filler, ai);

				if(!croc_isChar(t, -1))
					croc_eh_throwStd(t, "TypeError", "array element %" CROC_SIZE_T_FORMAT
						" expected to be a one-character string", i);

				data[ai] = croc_getChar(t, -1);
				croc_popTop(t);
			}
		}
		else
			croc_ex_paramTypeError(t, filler, "string|array|function|StringBuffer");

		croc_popTop(t);
	}

	template<bool reverse>
	word_t _commonFind(CrocThread* t)
	{
		auto src = _stringBufferAsUtf32(t, 0);
		auto start = croc_ex_optIndexParam(t, 2, src.length, "start", reverse ? (src.length - 1) : 0);
		dchar buf[64];
		auto tmp = dstring();
		auto pat = _checkStringOrStringBuffer(t, 1, dstring::n(buf, 64), tmp);

		if(reverse)
			croc_pushInt(t, strRLocatePattern(src, pat, start));
		else
			croc_pushInt(t, strLocatePattern(src, pat, start));

		tmp.free(Thread::from(t)->vm->mem);
		return 1;
	}

	word_t _format(CrocThread* t)
	{
		croc_ex_checkStringParam(t, 1);
		auto numPieces = formatImpl(t, 1, croc_getStackSize(t) - 2);

		croc_dup(t, 0);
		croc_pushNull(t);
		croc_rotate(t, numPieces + 2, 2);
		return croc_methodCall(t, -numPieces - 2, "append", 1);
	}

	// =================================================================================================================
	// Methods

DBeginList(_methods)
	Docstr(DFunc("constructor") DParamD("init", "string|int", "null")
	R"(If you pass nothing to the constructor, the \tt{StringBuffer} will be empty. If you pass a string, the
	\tt{StringBuffer} will be filled with that string's data. If you pass an integer, it means how much space, in
	characters, should be preallocated in the buffer. However, the length of the \tt{StringBuffer} will still be 0; it's
	just that no memory will have to be allocated until you put at least \tt{init} characters into it.

	\throws[RangeError] if \tt{init} is a negative integer or is an integer so large that the memory cannot be
	allocated.)"),

	"constructor", 1, [](CrocThread* t) -> word_t
	{
		crocstr data = crocstr();
		uword cpLen = 0;

		if(croc_isValidIndex(t, 1))
		{
			if(croc_isString(t, 1))
			{
				data = getCrocstr(t, 1);
				cpLen = cast(uword)croc_len(t, 1); // need codepoint length
			}
			else if(croc_isInt(t, 1))
			{
				auto l = croc_getInt(t, 1);

				if(l < 0 || cast(uword)l > std::numeric_limits<uword>::max())
					croc_eh_throwStd(t, "RangeError", "Invalid length: %" CROC_INTEGER_FORMAT, l);

				cpLen = cast(uword)l;
			}
			else
				croc_ex_paramTypeError(t, 1, "string|int");
		}

		croc_memblock_new(t, cpLen << 2);

		if(data.length > 0)
		{
			auto mb = getMemblock(Thread::from(t), -1);
			_toUtf32(data, mb->data.template as<dchar>());
			_setLength(t, cpLen);
		}
		else
			_setLength(t, 0);

		croc_hfielda(t, 0, Data);
		return 0;
	}

DListSep()
	Docstr(DFunc("dup")
	R"(Creates a new \tt{StringBuffer} that is a duplicate of this one. Its length and contents will be identical.

	\returns the new \tt{StringBuffer}.)"),

	"dup", 0, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto len = _getLength(t);

		croc_pushGlobal(t, "StringBuffer");
		croc_pushNull(t);
		croc_pushInt(t, len);
		croc_call(t, -3, 1);

		auto other = _getData(t, -1);
		other->data.slicea(0, len << 2, mb->data.slice(0, len << 2));
		_setLength(t, len, -1);
		return 1;
	}

DListSep()
	Docstr(DFunc("toString") DParamD("lo", "int", "0") DParamD("hi", "int", "#this")
	R"(Converts this \tt{StringBuffer} to a string.

	You can optionally slice out only a part of the buffer to turn into a string with the \tt{lo} and \tt{hi}
	parameters, which work like regular slice indices.

	\throws[BoundsError] if the slice boundaries are invalid.)"),

	"toString", 2, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		uword_t lo, hi;
		lo = croc_ex_checkSliceParams(t, 1, len, "slice", &hi);
		CrocStrBuffer b;
		croc_ex_buffer_init(t, &b);
		auto data = mb->data.template as<const dchar>().slice(lo, hi);
		auto destSize = fastUtf32GetUtf8Size(data);
		auto dest = cast(uchar*)croc_ex_buffer_prepare(&b, destSize);
		cdstring remaining;
		ustring dummy;
		auto ok = Utf32ToUtf8(data, ustring::n(dest, destSize), remaining, dummy);
		assert(ok == UtfError_OK && remaining.length == 0);
#ifdef NDEBUG
		(void)ok;
#endif
		croc_ex_buffer_addPrepared(&b);
		croc_ex_buffer_finish(&b);
		return 1;
	}

DListSep()
	Docstr(DFunc("opEquals") DParam("other", "string|StringBuffer")
	R"(Compares this \tt{StringBuffer} to a \tt{string} or another \tt{StringBuffer} for equality. Works the same as
	string equality.)"),

	"opEquals", 1, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		croc_ex_checkAnyParam(t, 1);

		croc_pushGlobal(t, "StringBuffer");

		if(croc_is(t, 0, 1))
			croc_pushBool(t, true);
		else if(croc_isString(t, 1))
		{
			if(len != cast(uword)croc_len(t, 1))
				croc_pushBool(t, false);
			else
			{
				auto data = mb->data.template as<dchar>();
				auto other = getCrocstr(t, 1);
				uword pos = 0;

				for(auto c: dcharsOf(other))
				{
					if(c != data[pos++])
					{
						croc_pushBool(t, false);
						return 1;
					}
				}

				croc_pushBool(t, true);
			}
		}
		else if(croc_isInstanceOf(t, 1, -1))
		{
			auto otherLen = _getLength(t, 1);

			if(len != otherLen)
				croc_pushBool(t, false);
			else
			{
				auto other = _getData(t, 1);
				auto a = mb->data.template as<dchar>().slice(0, len);
				auto b = other->data.template as<dchar>().slice(0, a.length);
				croc_pushBool(t, a == b);
			}
		}
		else
			croc_ex_paramTypeError(t, 1, "string|StringBuffer");

		return 1;
	}

DListSep()
	Docstr(DFunc("opCmp") DParam("other", "string|StringBuffer")
	R"(Compares this \tt{StringBuffer} to a \tt{string} or other \tt{StringBuffer}. Works the same as string
	comparison.)"),

	"opCmp", 1, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		croc_ex_checkAnyParam(t, 1);

		croc_pushGlobal(t, "StringBuffer");

		if(croc_is(t, 0, 1))
			croc_pushInt(t, 0);
		else if(croc_isString(t, 1))
		{
			auto otherLen = cast(uword)croc_len(t, 1);
			auto l = len < otherLen ? len : otherLen;

			auto data = mb->data.template as<dchar>();
			auto other = getCrocstr(t, 1);
			uword pos = 0;

			for(auto c: dcharsOf(other))
			{
				if(pos >= l)
					break;

				if(c != data[pos])
				{
					croc_pushInt(t, Compare3(c, data[pos]));
					return 1;
				}

				pos++;
			}

			croc_pushInt(t, Compare3(len, cast(uword)otherLen));
		}
		else if(croc_isInstanceOf(t, 1, -1))
		{
			auto otherLen = _getLength(t, 1);
			auto l = len < otherLen ? len : otherLen;
			auto other = _getData(t, 1);
			auto a = mb->data.template as<dchar>().slice(0, l);
			auto b = other->data.template as<dchar>().slice(0, l);

			if(auto cmp = a.cmp(b))
				croc_pushInt(t, cmp);
			else
				croc_pushInt(t, Compare3(len, cast(uword)otherLen));
		}
		else
			croc_ex_paramTypeError(t, 1, "string|StringBuffer");

		return 1;
	}

DListSep()
	Docstr(DFunc("opLength")
	R"(Gets the length of this \tt{StringBuffer} in characters. Note that this is just the number of characters
	currently in use; if you preallocate space either with the constructor or by setting the length longer and shorter,
	the true size of the underlying buffer will not be reported.)"),

	"opLength", 0, [](CrocThread* t) -> word_t
	{
		_getData(t);
		croc_hfielda(t, 0, Length);
		return 1;
	}

DListSep()
	Docstr(DFunc("opLengthAssign") DParam("len", "int")
	R"(Sets the length of this \tt{StringBuffer}. If you increase the length, the new characters will be filled with
	U+00FFFF. If you decrease the length, characters will be truncated. Note that when you increase the length of the
	buffer, memory may be overallocated to avoid allocations on every size increase. When you decrease the length of the
	buffer, that memory is not deallocated, so you can reserve memory for a \tt{StringBuffer} by setting its length to
	the size you need and then setting it back to 0, like so:

\code
local s = StringBuffer()
#s = 1000
#s = 0
// now s can hold up to 1000 characters before it will have to reallocate its memory.
\endcode

	Note that in the above example, simply doing \tt{local s = StringBuffer(1000)} will have the same effect.

	\throws[RangeError] if \tt{len} is negative or is so large that the memory cannot be allocated.)"),

	"opLengthAssign", 1, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto newLen = croc_ex_checkIntParam(t, 1);

		if(newLen < 0 || cast(uword)newLen > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid length: %" CROC_INTEGER_FORMAT, newLen);

		auto oldLen = _getLength(t);

		if(cast(uword)newLen < oldLen)
			_setLength(t, cast(uword)newLen);
		else if(cast(uword)newLen > oldLen)
		{
			_ensureSize(t, mb, cast(uword)newLen);
			_setLength(t, cast(uword)newLen);
			mb->data.template as<dchar>().slice(oldLen, cast(uword)newLen).fill(0xFFFF);
		}

		return 0;
	}

DListSep()
	Docstr(DFunc("opIndex") DParam("idx", "int")
	R"(Gets the character at the given index as a string.

	\throws[BoundsError] if the index is invalid.)"),

	"opIndex", 1, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto index = croc_ex_checkIndexParam(t, 1, len, "codepoint");
		croc_pushChar(t, mb->data.template as<dchar>()[index]);
		return 1;
	}

DListSep()
	Docstr(DFunc("opIndexAssign") DParam("idx", "int") DParam("c", "string")
	R"(Sets the character at the given index to the given character.

	\throws[BoundsError] if the index is invalid.
	\throws[ValueError] if \tt{#c != 1}.)"),

	"opIndexAssign", 2, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto index = croc_ex_checkIndexParam(t, 1, len, "codepoint");
		auto ch = croc_ex_checkCharParam(t, 2);
		mb->data.template as<dchar>()[index] = ch;
		return 0;
	}

DListSep()
	Docstr(DFunc("opCat") DParamAny("o")
	R"(Concatenates this \tt{StringBuffer} with another value and returns a \b{new} \tt{StringBuffer} containing the
	concatenation. If you want to instead add data to the beginning or end of a \tt{StringBuffer}, use the
	\link{opCatAssign} or \link{insert} methods.

	Any type can be concatenated with a \tt{StringBuffer}; if it isn't a string or another \tt{StringBuffer}, it will
	have its \tt{toString} method called on it and the result will be concatenated.)"),

	"opCat", 1, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto src = mb->data.template as<dchar>();

		auto makeObj = [&](crocint addLen)
		{
			auto totalLen = len + addLen;

			if(totalLen > std::numeric_limits<uword>::max())
				croc_eh_throwStd(t, "RangeError", "Result too big (%" CROC_INTEGER_FORMAT " elements)", totalLen);

			croc_pushGlobal(t, "StringBuffer");
			croc_pushNull(t);
			croc_pushInt(t, totalLen);
			croc_call(t, -3, 1);
			_setLength(t, cast(uword)totalLen, -1);
			auto ret = _getData(t, -1)->data.template as<dchar>();
			ret.slicea(0, len, src.slice(0, len));
			return ret.slice(len, ret.length);
		};

		croc_ex_checkAnyParam(t, 1);
		croc_pushGlobal(t, "StringBuffer");

		if(croc_isString(t, 1))
		{
			auto dest = makeObj(croc_len(t, 1));
			_toUtf32(getCrocstr(t, 1), dest);
		}
		else if(croc_isInstanceOf(t, 1, -1))
		{
			auto otherLen = _getLength(t, 1);
			makeObj(otherLen).slicea(_getData(t, 1)->data.template as<dchar>().slice(0, otherLen));
		}
		else
		{
			croc_pushToString(t, 1);
			auto s = getCrocstr(t, -1);
			auto dest = makeObj(croc_len(t, -1));
			_toUtf32(s, dest);
			croc_popTop(t);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("opCat_r") DParamAny("o")
	R"(ditto)"),

	"opCat_r", 1, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto src = mb->data.template as<dchar>();

		auto makeObj = [&](crocint addLen)
		{
			auto totalLen = len + addLen;

			if(totalLen > std::numeric_limits<uword>::max())
				croc_eh_throwStd(t, "RangeError", "Result too big (%" CROC_INTEGER_FORMAT " elements)", totalLen);

			croc_pushGlobal(t, "StringBuffer");
			croc_pushNull(t);
			croc_pushInt(t, totalLen);
			croc_call(t, -3, 1);
			_setLength(t, cast(uword)totalLen, -1);
			auto ret = _getData(t, -1)->data.template as<dchar>();
			ret.slicea(cast(uword)addLen, ret.length, src.slice(0, len));
			return ret.slice(0, cast(uword)addLen);
		};

		croc_ex_checkAnyParam(t, 1);

		if(croc_isString(t, 1))
		{
			auto dest = makeObj(croc_len(t, 1));
			_toUtf32(getCrocstr(t, 1), dest);
		}
		else
		{
			croc_pushToString(t, 1);
			auto s = getCrocstr(t, -1);
			auto dest = makeObj(croc_len(t, -1));
			_toUtf32(s, dest);
			croc_popTop(t);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("opCatAssign") DVararg
	R"x(\b{Also aliased to \tt{append}.} Appends its parameters to the end of this \tt{StringBuffer}.

	Each parameter will have \tt{toString} called on it (unless it's a \tt{StringBuffer} itself, so no \tt{toString} is
	necessary), and the resulting string will be appended to the end of this \tt{StringBuffer}'s data.

	You can either use the \tt{~=} operators to use this method, or you can call the \tt{append} method; both are
	aliased to the same method and do the same thing. Thus, \tt{"s ~= a ~ b ~ c"} is functionally identical to
	\tt{"s.append(a, b, c)"} and vice versa.

	\throws[RangeError] if the size of the buffer grows so large that the memory cannot be allocated.)x"),

	"opCatAssign", -1, [](CrocThread* t) -> word_t
	{
		auto numParams = croc_getStackSize(t) - 1;
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto oldLen = len;

		auto resize = [&](crocint addLen)
		{
			auto totalLen = len + addLen;

			if(totalLen > std::numeric_limits<uword>::max())
				croc_eh_throwStd(t, "RangeError", "Result too big (%" CROC_INTEGER_FORMAT " elements)", totalLen);

			_ensureSize(t, mb, cast(uword)totalLen);
			_setLength(t, cast(uword)totalLen);
			auto ret = mb->data.template as<dchar>().slice(len, cast(uword)totalLen);
			len = cast(uword)totalLen;
			return ret;
		};

		croc_ex_checkAnyParam(t, 1);
		croc_pushGlobal(t, "StringBuffer");
		auto t_ = Thread::from(t);

		for(uword i = 1; i <= numParams; i++)
		{
			if(croc_isString(t, i))
			{
				auto dest = resize(croc_len(t, i));
				_toUtf32(getCrocstr(t_, i), dest);
			}
			else if(croc_isInstanceOf(t, i, -1))
			{
				if(croc_is(t, 0, i))
				{
					// special case for when we're appending a stringbuffer to itself. use the old length
					resize(oldLen).slicea(mb->data.template as<dchar>().slice(0, oldLen));
				}
				else
				{
					auto otherLen = _getLength(t, i);
					resize(otherLen).slicea(_getData(t, 0)->data.template as<dchar>().slice(0, otherLen));
				}
			}
			else
			{
				croc_pushToString(t, i);
				auto dest = resize(croc_len(t, -1));
				_toUtf32(getCrocstr(t_, -1), dest);
				croc_popTop(t);
			}
		}

		// we're returning 'this' in case people want to chain 'append's, since this method is also append.
		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("opSlice") DParamD("lo", "int", "0") DParamD("hi", "int", "#this")
	R"(Slices data out of this \tt{StringBuffer} and creates a new \tt{StringBuffer} with that slice of data. Works just
	like string slicing.)"),

	"opSlice", 2, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		uword_t lo, hi;
		lo = croc_ex_checkSliceParams(t, 1, len, "slice", &hi);
		auto newStr = mb->data.template as<dchar>().slice(lo, hi);
		croc_pushGlobal(t, "StringBuffer");
		croc_pushNull(t);
		croc_pushInt(t, newStr.length);
		croc_call(t, -3, 1);
		_getData(t, -1)->data.template as<dchar>().slicea(newStr);
		_setLength(t, newStr.length, -1);
		return 1;
	}

DListSep()
	Docstr(DFunc("fill") DParam("v", "string|array|function|StringBuffer")
	R"(A flexible way to fill a \tt{StringBuffer} with some data. This only modifies existing data; the buffer's length
	is never changed.

	If you pass a string, it must be the same length as the buffer, and the string's data is copied into the buffer.

	If you pass an array, it must be the same length of the buffer and all its elements must be one-character strings.
	The character values of those strings will be copied into the buffer.

	If you pass a \tt{StringBuffer}, it must be the same length as the buffer and its data will be copied into this
	buffer.

	If you pass a function, it must take an integer and return a one-character string. It will be called on each
	location in the buffer, and the resulting characters will be put into the buffer.)"),

	"fill", 1, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		croc_ex_checkAnyParam(t, 1);
		_fillImpl(t, mb, 1, 0, _getLength(t));
		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("fillRange") DParamD("lo", "int", "0") DParamD("hi", "int", "#this")
		DParam("v", "string|array|function|StringBuffer")
	R"x(\b{Also aliased to \tt{opSliceAssign}.}

	Works just like \link{fill}, except it works on just a subrange of the buffer. The \tt{lo} and \tt{hi} params work
	just like slice indices - low inclusive, high noninclusive, negative from the end.

	You can either call this method directly, or you can use slice-assignment; they are aliased to the same method and
	do the same thing. Thus, \tt{"s.fillRange(x, y, z)"} is functionally identical to \tt{"s[x .. y] = z"} and vice
	versa.)x"),

	"fillRange", 3, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		uword_t lo, hi;
		lo = croc_ex_checkSliceParams(t, 1, len, "range", &hi);
		_fillImpl(t, mb, 3, lo, hi);
		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("fillChar") DParam("ch", "string") DParamD("lo", "int", "0") DParamD("hi", "int", "#this")
	R"(Sets every character to the character given by \tt{ch}, which must be a one-character string. Can optionally just
	set the characters of a slice given by \tt{lo} and \tt{hi}.)"),

	"fillChar", 3, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto ch = croc_ex_checkCharParam(t, 1);
		uword_t lo, hi;
		lo = croc_ex_checkSliceParams(t, 2, len, "range", &hi);
		mb->data.template as<dchar>().slice(lo, hi).fill(ch);
		return 0;
	}

DListSep()
	Docstr(DFunc("insert") DParam("idx", "int") DParamAny("val")
	R"(Inserts the string representation of \tt{val} before the character indexed by \tt{idx}. \tt{idx} can be negative,
	which means an index from the end of the buffer. It can also be the same as the length of this \tt{StringBuffer}, in
	which case the behavior is identical to appending.)"),

	"insert", 2, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto idx = croc_ex_checkIntParam(t, 1);
		croc_ex_checkAnyParam(t, 2);

		if(idx < 0)
			idx += len;

		// yes, greater, because it's possible to insert at one past the end of the buffer (it appends)
		if(idx < 0 || cast(uword)idx > len)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid index: %" CROC_INTEGER_FORMAT " (length: %" CROC_SIZE_T_FORMAT ")", idx, len);

		auto doResize = [&](crocint otherLen)
		{
			auto totalLen = len + otherLen;

			if(totalLen > std::numeric_limits<uword>::max())
				croc_eh_throwStd(t, "RangeError", "Invalid size (%" CROC_INTEGER_FORMAT ")", totalLen);

			auto oldLen = len;

			_ensureSize(t, mb, cast(uword)totalLen);
			_setLength(t, cast(uword)totalLen);

			auto tmp = mb->data.template as<dchar>().slice(0, cast(uword)totalLen);

			if(cast(uword)idx < oldLen)
			{
				auto end = idx + otherLen;
				auto numLeft = oldLen - idx;
				memmove(&tmp[cast(uword)end], &tmp[cast(uword)idx], cast(uword)(numLeft * sizeof(dchar)));
			}

			return tmp.slice(cast(uword)idx, cast(uword)(idx + otherLen));
		};

		croc_pushGlobal(t, "StringBuffer");

		if(croc_isString(t, 2))
		{
			auto cpLen = croc_len(t, 2);

			if(cpLen != 0)
			{
				auto str = getCrocstr(t, 2);
				auto tmp = doResize(cpLen);
				_toUtf32(str, tmp);
			}
		}
		else if(croc_isInstanceOf(t, 2, -1))
		{
			if(croc_is(t, 0, 2))
			{
				// special case for inserting a stringbuffer into itself

				if(len != 0)
				{
					auto slice = doResize(len);
					auto data = _getData(t)->data.template as<dchar>();
					slice.slicea(0, cast(uword)idx, data.slice(0, cast(uword)idx));
					slice.slicea(cast(uword)idx, slice.length, data.slice(cast(uword)idx + len, data.length));
				}
			}
			else
			{
				auto other = _getData(t, 2)->data.template as<dchar>();
				auto otherLen = _getLength(t, 2);

				if(otherLen != 0)
					doResize(otherLen).slicea(other.slice(0, otherLen));
			}
		}
		else
		{
			croc_pushToString(t, 2);
			auto cpLen = croc_len(t, -1);

			if(cpLen != 0)
			{
				auto str = getCrocstr(t, -1);
				auto tmp = doResize(cpLen);
				_toUtf32(str, tmp);
			}

			croc_popTop(t);
		}

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("remove") DParam("lo", "int") DParamD("hi", "int", "lo + 1")
	R"(Removes characters from a \tt{StringBuffer}, shifting the data after them (if any) down. The indices work like
	slice indices. The \tt{hi} index defaults to one more than the \tt{lo} index, so you can remove a single character
	by just passing the \tt{lo} index.)"),

	"remove", 2, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto len = _getLength(t);

		if(len == 0)
			croc_eh_throwStd(t, "ValueError", "StringBuffer is empty");

		auto lo = croc_ex_checkIntParam(t, 1);
		auto hi = croc_ex_optIntParam(t, 2, lo + 1);
		if(lo < 0) lo += len;
		if(hi < 0) hi += len;
		croc_ex_checkValidSlice(t, lo, hi, len, "slice");

		if(lo != hi)
		{
			if(cast(uword)hi < len)
				memmove(&mb->data[cast(uword)lo * sizeof(dchar)], &mb->data[cast(uword)hi * sizeof(dchar)],
					cast(uword)((len - hi) * sizeof(dchar)));

			croc_dup(t, 0);
			croc_pushNull(t);
			croc_pushInt(t, len - (hi - lo));
			croc_methodCall(t, -3, "opLengthAssign", 0);
		}

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("find") DParam("sub", "string|StringBuffer") DParamD("start", "int", "0")
	R"(Searches for an occurence of \tt{sub} in \tt{this}. \tt{sub} can be a string or another \tt{StringBuffer}. The
	search starts from \tt{start} (which defaults to the first character) and goes right. If \tt{sub} is found, this
	function returns the integer index of the occurrence in the string, with 0 meaning the first character. Otherwise,
	if \tt{sub} cannot be found, \tt{#this} is returned.

	If \tt{start < 0} it is treated as an index from the end of \tt{this}.

	\throws[BoundsError] if \tt{start} is invalid.)"),

	"find", 2, &_commonFind<false>

DListSep()
	Docstr(DFunc("rfind") DParam("sub", "string|StringBuffer") DParamD("start", "int", "#this - 1")
	R"(Reverse find. Works similarly to \tt{find}, but the search starts with the character at \tt{start} (which
	defaults to the last character) and goes \em{left}. If \tt{sub} is found, this function returns the integer index of
	the occurrence in the string, with 0 meaning the first character. Otherwise, if \tt{sub} cannot be found, \tt{#this}
	is returned.

	If \tt{start < 0} it is treated as an index from the end of \tt{this}.

	\throws[BoundsError] if \tt{start} is invalid.)"),

	"rfind", 2, &_commonFind<true>

DListSep()
	Docstr(DFunc("startsWith") DParam("other", "string|StringBuffer")
	R"(\returns a bool of whether or not \tt{this} starts with the substring \tt{other}. This is case-sensitive.)"),

	"startsWith", 1, [](CrocThread* t) -> word_t
	{
		auto self = _stringBufferAsUtf32(t, 0);

		dchar buf[64];
		auto tmp = dstring();
		auto other = _checkStringOrStringBuffer(t, 1, dstring::n(buf, 64), tmp);
		croc_pushBool(t, self.length >= other.length && self.slice(0, other.length) == other);
		tmp.free(Thread::from(t)->vm->mem);
		return 0;
	}

DListSep()
	Docstr(DFunc("endsWith") DParam("other", "string|StringBuffer")
	R"(\returns a bool of whether or not \tt{this} ends with the substring \tt{other}. This is case-sensitive.)"),

	"endsWith", 1, [](CrocThread* t) -> word_t
	{
		auto self = _stringBufferAsUtf32(t, 0);

		dchar buf[64];
		auto tmp = dstring();
		auto other = _checkStringOrStringBuffer(t, 1, dstring::n(buf, 64), tmp);
		croc_pushBool(t, self.length >= other.length && self.slice(self.length - other.length, self.length) == other);
		tmp.free(Thread::from(t)->vm->mem);
		return 0;
	}

DListSep()
	Docstr(DFunc("split") DParam("delim", "string|StringBuffer")
	R"(Splits \tt{this} into pieces (each piece being a new \tt{StringBuffer}) and returns an array of the split pieces.

	\param[delim] specifies a delimiting string where \tt{this} will be split.)"),

	"split", 1, [](CrocThread* t) -> word_t
	{
		auto src = _stringBufferAsUtf32(t, 0);

		dchar buf[64];
		auto tmp = dstring();
		auto splitter = _checkStringOrStringBuffer(t, 1, dstring::n(buf, 64), tmp);
		auto ret = croc_array_new(t, 0);
		uword num = 0;

		patterns(src, splitter, [&](DArray<const dchar> piece)
		{
			_stringBufferFromUtf32(t, piece);
			num++;

			if(num >= 50)
			{
				croc_cateq(t, ret, num);
				num = 0;
			}
		});

		if(num > 0)
			croc_cateq(t, ret, num);

		tmp.free(Thread::from(t)->vm->mem);

		return 1;
	}

DListSep()
	Docstr(DFunc("vsplit") DParam("delim", "string|StringBuffer")
	R"(Similar to \link{split}, but instead of returning an array, returns the split pieces as multiple return values.
	If \tt{this} splits into more than 20 pieces, an error will be thrown (as returning many values can be a memory
	problem). Otherwise the behavior is identical to \link{split}.)"),

	"vsplit", 1, [](CrocThread* t) -> word_t
	{
		auto src = _stringBufferAsUtf32(t, 0);

		dchar buf[64];
		auto tmp = dstring();
		auto splitter = _checkStringOrStringBuffer(t, 1, dstring::n(buf, 64), tmp);
		uword num = 0;

		patterns(src, splitter, [&](DArray<const dchar> piece)
		{
			_stringBufferFromUtf32(t, piece);
			num++;

			if(num > VSplitMax)
			{
				tmp.free(Thread::from(t)->vm->mem);
				croc_eh_throwStd(t, "ValueError", "Too many (>%" CROC_SIZE_T_FORMAT ") parts when splitting",
					VSplitMax);
			}
		});

		tmp.free(Thread::from(t)->vm->mem);

		return num;
	}

DListSep()
	Docstr(DFunc("splitWS")
	R"(Similar to \link{split}, but splits at whitespace (spaces, tabs, newlines etc.), and all the whitespace is
	stripped from the split pieces. No empty pieces will be returned.)"),

	"splitWS", 0, [](CrocThread* t) -> word_t
	{
		auto src = _stringBufferAsUtf32(t, 0);
		auto ret = croc_array_new(t, 0);
		uword num = 0;

		delimiters(src, Whitespace, [&](DArray<const dchar> piece)
		{
			if(piece.length > 0)
			{
				_stringBufferFromUtf32(t, piece);
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
	R"(Similar to \link{vsplit} in that it returns multiple values, but works like \link{splitWS} instead. If \tt{this}
	splits into more than 20 pieces, an error will be thrown (as returning many values can be a memory problem).
	Otherwise the behavior is identical to \link{splitWS}.)"),

	"vsplitWS", 0, [](CrocThread* t) -> word_t
	{
		auto src = _stringBufferAsUtf32(t, 0);
		uword num = 0;

		delimiters(src, Whitespace, [&](DArray<const dchar> piece)
		{
			if(piece.length > 0)
			{
				_stringBufferFromUtf32(t, piece);
				num++;

				if(num > VSplitMax)
					croc_eh_throwStd(t, "ValueError", "Too many (>%" CROC_SIZE_T_FORMAT ") parts when splitting",
						VSplitMax);
			}
		});

		return num;
	}

DListSep()
	Docstr(DFunc("splitLines")
	R"(This will split \tt{this} at any newline characters (\tt{'\\n'}, \tt{'\\r'}, or \tt{'\\r\\n'}). The newline
	characters will be removed. Other whitespace is preserved, and empty lines are preserved. This returns an array of
	\tt{StringBuffer}s, each of which holds one line of text.)"),

	"splitLines", 0, [](CrocThread* t) -> word_t
	{
		auto src = _stringBufferAsUtf32(t, 0);
		auto ret = croc_array_new(t, 0);
		uword num = 0;

		lines(src, [&](DArray<const dchar> piece)
		{
			_stringBufferFromUtf32(t, piece);
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
	R"(Similar to \link{splitLines}, but instead of returning an array, returns the split lines as multiple return
	values. If \tt{this} splits into more than 20 lines, an error will be thrown. Otherwise the behavior is identical to
	\link{splitLines}.)"),

	"vsplitLines", 0, [](CrocThread* t) -> word_t
	{
		auto src = _stringBufferAsUtf32(t, 0);
		uword num = 0;

		lines(src, [&](DArray<const dchar> piece)
		{
			_stringBufferFromUtf32(t, piece);
			num++;

			if(num > VSplitMax)
				croc_eh_throwStd(t, "ValueError", "Too many (>%" CROC_SIZE_T_FORMAT ") parts when splitting",
					VSplitMax);
		});

		return num;
	}

DListSep()
	Docstr(DFunc("repeat") DParam("n", "int")
	R"(\returns a new \tt{StringBuffer} which is the concatenation of \tt{n} instances of \tt{this}. If \tt{n == 0},
	returns an empty \tt{StringBuffer}.

	\throws[RangeError] if \tt{n < 0}.)"),

	"repeat", 1, [](CrocThread* t) -> word_t
	{
		_getData(t);
		croc_ex_checkIntParam(t, 1);
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "dup", 1);
		croc_pushNull(t);
		croc_dup(t, 1);
		return croc_methodCall(t, -3, "repeat!", 1);
	}

DListSep()
	Docstr(DFunc("reverse")
	R"(\returns a new \tt{StringBuffer} whose contents are the reversal of \tt{this}.)"),

	"reverse", 0, [](CrocThread* t) -> word_t
	{
		_getData(t);
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "dup", 1);
		croc_pushNull(t);
		return croc_methodCall(t, -2, "reverse!", 1);
	}

DListSep()
	Docstr(DFunc("strip")
	R"(\returns a new \tt{StringBuffer} whose contents are the same as \tt{this} but with any whitespace stripped from
	the beginning and end.)"),

	"strip", 0, [](CrocThread* t) -> word_t
	{
		_getData(t);
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "dup", 1);
		croc_pushNull(t);
		return croc_methodCall(t, -2, "strip!", 1);
	}

DListSep()
	Docstr(DFunc("lstrip")
	R"(\returns a new \tt{StringBuffer} whose contents are the same as \tt{this} but with any whitespace stripped from
	just the beginning of the string.)"),

	"lstrip", 0, [](CrocThread* t) -> word_t
	{
		_getData(t);
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "dup", 1);
		croc_pushNull(t);
		return croc_methodCall(t, -2, "lstrip!", 1);
	}

DListSep()
	Docstr(DFunc("rstrip")
	R"(\returns a new \tt{StringBuffer} whose contents are the same as \tt{this} but with any whitespace stripped from
	just the end of the string.)"),

	"rstrip", 0, [](CrocThread* t) -> word_t
	{
		_getData(t);
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "dup", 1);
		croc_pushNull(t);
		return croc_methodCall(t, -2, "rstrip!", 1);
	}

DListSep()
	Docstr(DFunc("replace") DParam("from", "string|StringBuffer") DParam("to", "string|StringBuffer")
	R"(\returns a new \tt{StringBuffer} where any occurrences in \tt{this} of the string \tt{from} are replaced with the
	string \tt{to}.)"),

	"replace", 2, [](CrocThread* t) -> word_t
	{
		if(!_isStringOrStringBuffer(t, 1))
			croc_ex_paramTypeError(t, 1, "string|StringBuffer");
		else if(!_isStringOrStringBuffer(t, 2))
			croc_ex_paramTypeError(t, 2, "string|StringBuffer");

		auto src = _stringBufferAsUtf32(t, 0);
		auto ret = croc_pushGlobal(t, "StringBuffer");
		croc_pushNull(t);
		croc_pushInt(t, src.length);
		croc_call(t, -3, 1);

		dchar buf1[64], buf2[64];
		auto tmp1 = dstring(), tmp2 = dstring();
		auto from = _checkStringOrStringBuffer(t, 1, dstring::n(buf1, 64), tmp1);
		auto to = _checkStringOrStringBuffer(t, 2, dstring::n(buf2, 64), tmp2);
		auto destmb = _getData(t, ret);
		auto dest = destmb->data.template as<dchar>();
		bool shouldCheckSize = from.length < to.length; // only have to grow if the 'to' string is bigger than the 'from' string
		uword destIdx = 0;
		auto t_ = Thread::from(t);

		patternsRep(src, from, to, [&](DArray<const dchar> piece)
		{
			auto newEnd = destIdx + piece.length;

			if(shouldCheckSize && newEnd > dest.length)
			{
				push(t_, Value::from(destmb));
				croc_lenai(t, -1, sizeof(dchar) * (newEnd > dest.length * 2 ? newEnd : dest.length * 2));
				croc_popTop(t);
				dest = destmb->data.template as<dchar>();
			}

			dest.slicea(destIdx, newEnd, piece);
			destIdx = newEnd;
		});

		tmp1.free(t_->vm->mem);
		tmp2.free(t_->vm->mem);

		_setLength(t, destIdx, ret);
		return 1;
	}

DListSep()
	Docstr(DFunc("repeat!") DParam("n", "int")
	R"(These are all \em{in-place} versions of their corresponding methods. They work identically, except instead of
	returning a new \tt{StringBuffer} object leaving \tt{this} unchanged, they replace the contents of \tt{this} with
	their output.)"),

	"repeat!", 1, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto oldLen = _getLength(t);
		auto numTimes = croc_ex_checkIntParam(t, 1);

		if(numTimes < 0)
			croc_eh_throwStd(t, "RangeError", "Invalid number of repetitions: %" CROC_INTEGER_FORMAT, numTimes);

		auto newLen = cast(uword)numTimes * oldLen;

		_ensureSize(t, mb, newLen);
		_setLength(t, newLen);

		if(numTimes > 1)
		{
			auto src = mb->data.template as<dchar>().slice(0, oldLen);
			auto dest = (cast(dchar*)mb->data.ptr) + oldLen;
			auto end = (cast(dchar*)mb->data.ptr) + newLen;

			for( ; dest < end; dest += oldLen)
				dstring::n(dest, oldLen).slicea(src);
		}

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("reverse!")
	R"(ditto)"),

	"reverse!", 0, [](CrocThread* t) -> word_t
	{
		auto src = _stringBufferAsUtf32(t, 0);

		if(src.length > 1)
		{
			for(uword i = 0, j = src.length - 1; i < j; i++, j--)
			{
				auto tmp = src[i];
				src[i] = src[j];
				src[j] = tmp;
			}
		}

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("strip!")
	R"(ditto)"),

	"strip!", 0, [](CrocThread* t) -> word_t
	{
		auto src = _stringBufferAsUtf32(t, 0);
		auto trimmed = strTrimWS(src);

		if(src.length != trimmed.length)
		{
			if(src.ptr != trimmed.ptr)
				memmove(src.ptr, trimmed.ptr, trimmed.length * sizeof(dchar));

			_setLength(t, trimmed.length);
		}

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("lstrip!")
	R"(ditto)"),

	"lstrip!", 0, [](CrocThread* t) -> word_t
	{
		auto src = _stringBufferAsUtf32(t, 0);
		auto trimmed = strTrimlWS(src);

		if(src.length != trimmed.length)
		{
			memmove(src.ptr, trimmed.ptr, trimmed.length * sizeof(dchar));
			_setLength(t, trimmed.length);
		}

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("rstrip!")
	R"(ditto)"),

	"rstrip!", 0, [](CrocThread* t) -> word_t
	{
		auto src = _stringBufferAsUtf32(t, 0);
		auto trimmed = strTrimrWS(src);

		if(src.length != trimmed.length)
			_setLength(t, trimmed.length);

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("replace!") DParam("from", "string|StringBuffer") DParam("to", "string|StringBuffer")
	R"(ditto)"),

	"replace!", 2, [](CrocThread* t) -> word_t
	{
		if(!_isStringOrStringBuffer(t, 1))
			croc_ex_paramTypeError(t, 1, "string|StringBuffer");
		else if(!_isStringOrStringBuffer(t, 2))
			croc_ex_paramTypeError(t, 2, "string|StringBuffer");

		auto src = _stringBufferAsUtf32(t, 0);
		auto &mem = Thread::from(t)->vm->mem;

		dchar buf1[64], buf2[64];
		auto tmp1 = dstring(), tmp2 = dstring();
		auto from = _checkStringOrStringBuffer(t, 1, dstring::n(buf1, 64), tmp1);
		auto to = _checkStringOrStringBuffer(t, 2, dstring::n(buf2, 64), tmp2);
		auto buffer = dstring::alloc(mem, src.length);
		bool shouldCheckSize = from.length < to.length; // only have to grow if the 'to' string is bigger than the 'from' string
		uword destIdx = 0;

		patternsRep(src, from, to, [&](DArray<const dchar> piece)
		{
			auto newEnd = destIdx + piece.length;

			if(shouldCheckSize && newEnd > buffer.length)
				buffer.resize(mem, newEnd > buffer.length * 2 ? newEnd : buffer.length * 2);

			buffer.slicea(destIdx, newEnd, piece);
			destIdx = newEnd;
		});

		auto mb = _getData(t, 0);
		_ensureSize(t, mb, destIdx);
		_setLength(t, destIdx);
		src = _stringBufferAsUtf32(t, 0); // has been invalidated!
		src.slicea(0, destIdx, buffer.slice(0, destIdx));

		tmp1.free(mem);
		tmp2.free(mem);
		buffer.free(mem);

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("format") DParam("fmt", "string") DVararg
	R"(Just like \link{string.format}, except the results are appended directly to the end of this \tt{StringBuffer}
	without needing a string temporary.)"),

	"format", -1, &_format

DListSep()
	Docstr(DFunc("formatln") DParam("fmt", "string") DVararg
	R"(Same as \tt{format}, but also appends the \tt{\\n} character after appending the formatted string.)"),

	"formatln", -1, [](CrocThread* t) -> word_t
	{
		_format(t);
		croc_pushNull(t);
		croc_pushString(t, "\n");
		return croc_methodCall(t, -3, "append", 1);
	}

DListSep()
	Docstr(DFunc("opSerialize")
	R"(These allow instances of \tt{StringBuffer} to be serialized by the \link{serialization} library.)"),

	"opSerialize", 2, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);

		// don't know if this is possible, but can't hurt to check
		if(!mb->ownData)
			croc_eh_throwStd(t, "ValueError", "Attempting to serialize a StringBuffer which does not own its data");

		croc_dup(t, 2);
		croc_pushNull(t);
		croc_hfield(t, 0, Length);
		croc_call(t, -3, 0);
		croc_dup(t, 2);
		croc_pushNull(t);
		croc_hfield(t, 0, Data);
		croc_call(t, -3, 0);
		return 0;
	}

DListSep()
	Docstr(DFunc("opDeserialize")
	R"(ditto)"),

	"opDeserialize", 2, [](CrocThread* t) -> word_t	{
		croc_dup(t, 2);
		croc_pushNull(t);
		croc_pushString(t, "int");
		croc_call(t, -3, 1);

		auto len = croc_getInt(t, -1);

		if(len < 0 || std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "ValueError", "Malformed data (invalid StringBuffer length)");

		croc_hfielda(t, 0, Length);

		croc_dup(t, 2);
		croc_pushNull(t);
		croc_pushString(t, "memblock");
		croc_call(t, -3, 1);

		auto mbLen = croc_len(t, -1);

		if(len > mbLen || (mbLen & 3) != 0) // not a multiple of 4
			croc_eh_throwStd(t, "ValueError", "Malformed data (invalid StringBuffer data)");

		croc_hfielda(t, 0, Data);

		return 0;
	}
DEndList()

DBeginList(_opApply)
	nullptr,
	"iterator", 1, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto index = croc_ex_checkIntParam(t, 1) + 1;

		if(cast(uword)index >= _getLength(t))
			return 0;

		croc_pushInt(t, index);
		croc_pushChar(t, (mb->data.template as<dchar>())[cast(uword)index]);

		return 2;
	}

DListSep()
	nullptr,

	"iteratorReverse", 1, [](CrocThread* t) -> word_t
	{
		auto mb = _getData(t);
		auto index = croc_ex_checkIntParam(t, 1) - 1;

		if(index < 0)
			return 0;

		croc_pushInt(t, index);
		croc_pushChar(t, (mb->data.template as<dchar>())[cast(uword)index]);

		return 2;
	}

DListSep()
	Docstr(DFunc("opApply") DParamD("reverse", "string", "null")
	R"(Lets you iterate over \tt{StringBuffer}s with foreach loops just like strings. You can iterate in reverse, just
	like strings, by passing the string \tt{"reverse"} as the second value in the foreach container:

\code
local sb = StringBuffer("hello")
foreach(i, c; sb) { }
foreach(i, c; sb, "reverse") { } // goes backwards
\endcode
	)"),

	"opApply", 1, [](CrocThread* t) -> word_t
	{
		_getData(t);
		auto mode = croc_ex_optStringParam(t, 1, "");

		if(strcmp(mode, "reverse") == 0)
		{
			croc_pushUpval(t, 1);
			croc_dup(t, 0);
			croc_pushInt(t, _getLength(t));
		}
		else
		{
			croc_pushUpval(t, 0);
			croc_dup(t, 0);
			croc_pushInt(t, -1);
		}

		return 3;
	}
DEndList()
	}

	void initStringLib_StringBuffer(CrocThread* t)
	{
		croc_class_new(t, "StringBuffer", 0);
			croc_pushNull(t);   croc_class_addHField(t, -2, Data);
			croc_pushInt(t, 0); croc_class_addHField(t, -2, Length);
			registerMethods(t, _methods);
			registerMethodUV(t, _opApply);
			croc_field(t, -1, "fillRange");   croc_class_addMethod(t, -2, "opSliceAssign");
			croc_field(t, -1, "opCatAssign"); croc_class_addMethod(t, -2, "append");
		croc_newGlobal(t, "StringBuffer");
	}

#ifdef CROC_BUILTIN_DOCS
	void docStringLib_StringBuffer(CrocThread* t, CrocDoc* doc)
	{
		croc_field(t, -1, "StringBuffer");
			croc_ex_doc_push(doc, DClass("StringBuffer")
			R"(Croc's strings are immutable. While this makes dealing with strings much easier in most cases, it also
			introduces inefficiency for some operations, such as performing text modification on large pieces of textual
			data. \tt{StringBuffer} is a mutable string class that makes these sorts of things possible. It's mutable,
			and stores the data in a way that makes indexing and slicing constant time instead of linear time.

			While this class is good for complex text manipulation, if you just need to build up a string piecewise,
			using this class will be less efficient than just appending pieces to an array and then using the string
			\tt{join} method on it.

			A note on some of the methods: as per the standard library convention, there are some methods which have two
			versions, one of which operates in-place, and the other which returns a new object and leaves the original
			unchanged. In this case, the in-place version's name has an exclamation point appended, while the non-
			modifying version has none. For example, \link{reverse} will create a new \tt{StringBuffer}, whereas
			\link{reverse!} will modify the given one in place.)");

			docFields(doc, _methods);
			docFieldUV(doc, _opApply);
			croc_ex_doc_pop(doc, -1);
		croc_popTop(t);
	}
#endif
}