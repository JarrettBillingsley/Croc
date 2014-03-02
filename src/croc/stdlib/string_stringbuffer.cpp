
#include <cmath>
#include <limits>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"
#include "croc/util/str.hpp"

namespace croc
{
	namespace
	{
	const char* Data = "data";
	const char* Length = "length";
	const uword VSplitMax = 20;
	typedef DArray<dchar> dstring;

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
				if(l & (1 << ((sizeof(uword) * 8) - 1)))
					croc_eh_throwStd(t, "RangeError", "StringBuffer too big (%u elements)", size);

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
			auto str = getCrocstr(Thread::from(t), idx);
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

	word_t _constructor(CrocThread* t)
	{
		crocstr data = crocstr();
		uword cpLen = 0;

		if(croc_isValidIndex(t, 1))
		{
			if(croc_isString(t, 1))
			{
				data = getCrocstr(Thread::from(t), 1);
				cpLen = cast(uword)croc_len(t, 1); // need codepoint length
			}
			else if(croc_isInt(t, 1))
			{
				auto l = croc_getInt(t, 1);

				if(l < 0 || l > std::numeric_limits<uword>::max())
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

	word_t _dup(CrocThread* t)
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

	word_t _toString(CrocThread* t)
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto lo = croc_ex_optIntParam(t, 1, 0);
		auto hi = croc_ex_optIntParam(t, 2, len);

		if(lo < 0)
			lo += len;

		if(hi < 0)
			hi += len;

		if(lo < 0 || lo > hi || hi > len)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid slice indices: %" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT " (buffer length: %u)",
				lo, hi, len);

		CrocStrBuffer b;
		croc_ex_buffer_init(t, &b);
		auto data = mb->data.template as<const dchar>().slice(cast(uword)lo, cast(uword)hi);
		auto destSize = fastUtf32GetUtf8Size(data);
		auto dest = croc_ex_buffer_prepare(&b, destSize);
		DArray<const dchar> remaining;
		DArray<char> dummy;
		auto ok = Utf32ToUtf8(data, DArray<char>::n(dest, destSize), remaining, dummy);
		assert(ok == UtfError_OK && remaining.length == 0);
#ifdef NDEBUG
		(void)ok;
#endif
		croc_ex_buffer_addPrepared(&b);
		croc_ex_buffer_finish(&b);
		return 1;
	}

	word_t _opEquals(CrocThread* t)
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		croc_ex_checkAnyParam(t, 1);

		croc_pushGlobal(t, "StringBuffer");

		if(croc_is(t, 0, 1))
			croc_pushBool(t, true);
		else if(croc_isString(t, 1))
		{
			if(len != croc_len(t, 1))
				croc_pushBool(t, false);
			else
			{
				auto data = mb->data.template as<dchar>();
				auto other = getCrocstr(Thread::from(t), 1);
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

	word_t _opCmp(CrocThread* t)
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		croc_ex_checkAnyParam(t, 1);

		croc_pushGlobal(t, "StringBuffer");

		if(croc_is(t, 0, 1))
			croc_pushInt(t, 0);
		else if(croc_isString(t, 1))
		{
			auto otherLen = croc_len(t, 1);
			auto l = len < otherLen ? len : otherLen;

			auto data = mb->data.template as<dchar>();
			auto other = getCrocstr(Thread::from(t), 1);
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

	word_t _opLength(CrocThread* t)
	{
		_getData(t);
		croc_hfielda(t, 0, Length);
		return 1;
	}

	word_t _opLengthAssign(CrocThread* t)
	{
		auto mb = _getData(t);
		auto newLen = croc_ex_checkIntParam(t, 1);

		if(newLen < 0 || newLen > std::numeric_limits<uword>::max())
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

	word_t _opIndex(CrocThread* t)
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto index = croc_ex_checkIntParam(t, 1);

		if(index < 0)
			index += len;

		if(index < 0 || index >= len)
			croc_eh_throwStd(t, "BoundsError", "Invalid index: %" CROC_INTEGER_FORMAT " (buffer length: %u)",
				index, len);

		croc_pushChar(t, mb->data.template as<dchar>()[cast(uword)index]);
		return 1;
	}

	word_t _opIndexAssign(CrocThread* t)
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto index = croc_ex_checkIntParam(t, 1);
		auto ch = croc_ex_checkCharParam(t, 2);

		if(index < 0)
			index += len;

		if(index < 0 || index >= len)
			croc_eh_throwStd(t, "BoundsError", "Invalid index: %" CROC_INTEGER_FORMAT " (buffer length: %u)",
				index, len);

		mb->data.template as<dchar>()[cast(uword)index] = ch;
		return 0;
	}

	word_t _opCat(CrocThread* t)
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
			_toUtf32(getCrocstr(Thread::from(t), 1), dest);
		}
		else if(croc_isInstanceOf(t, 1, -1))
		{
			auto otherLen = _getLength(t, 1);
			makeObj(otherLen).slicea(_getData(t, 1)->data.template as<dchar>().slice(0, otherLen));
		}
		else
		{
			croc_pushToString(t, 1);
			auto s = getCrocstr(Thread::from(t), -1);
			auto dest = makeObj(croc_len(t, -1));
			_toUtf32(s, dest);
			croc_popTop(t);
		}

		return 1;
	}

	word_t _opCat_r(CrocThread* t)
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
			_toUtf32(getCrocstr(Thread::from(t), 1), dest);
		}
		else
		{
			croc_pushToString(t, 1);
			auto s = getCrocstr(Thread::from(t), -1);
			auto dest = makeObj(croc_len(t, -1));
			_toUtf32(s, dest);
			croc_popTop(t);
		}

		return 1;
	}

	word_t _opCatAssign(CrocThread* t)
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

	word_t _opSlice(CrocThread* t)
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto lo = croc_ex_optIntParam(t, 1, 0);
		auto hi = croc_ex_optIntParam(t, 2, len);

		if(lo < 0)
			lo += len;

		if(hi < 0)
			hi += len;

		if(lo < 0 || lo > hi || hi > len)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid slice indices: %" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT " (buffer length: %u)",
				lo, hi, len);

		auto newStr = mb->data.template as<dchar>().slice(cast(uword)lo, cast(uword)hi);

		croc_pushGlobal(t, "StringBuffer");
		croc_pushNull(t);
		croc_pushInt(t, newStr.length);
		croc_call(t, -3, 1);
		_getData(t, -1)->data.template as<dchar>().slicea(newStr);
		_setLength(t, newStr.length, -1);
		return 1;
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
				croc_eh_throwStd(t, "ValueError", "Length of destination (%u) and length of source (%u) do not match",
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
					"Length of destination (%u) and length of source string (%u) do not match",
					hi - lo, cpLen);

			_toUtf32(getCrocstr(Thread::from(t), filler), mb->data.template as<dchar>().slice(lo, hi));
		}
		else if(croc_isArray(t, filler))
		{
			auto data = mb->data.template as<dchar>().slice(lo, hi);

			for(uword i = lo, ai = 0; i < hi; i++, ai++)
			{
				croc_idxi(t, filler, ai);

				if(!croc_isChar(t, -1))
					croc_eh_throwStd(t, "TypeError", "array element %u expected to be a one-character string", i);

				data[ai] = croc_getChar(t, -1);
				croc_popTop(t);
			}
		}
		else
			croc_ex_paramTypeError(t, filler, "string|array|function|StringBuffer");

		croc_popTop(t);
	}

	word_t _fill(CrocThread* t)
	{
		auto mb = _getData(t);
		croc_ex_checkAnyParam(t, 1);
		_fillImpl(t, mb, 1, 0, _getLength(t));
		croc_dup(t, 0);
		return 1;
	}

	word_t _fillRange(CrocThread* t)
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto lo = croc_ex_optIntParam(t, 1, 0);
		auto hi = croc_ex_optIntParam(t, 2, len);
		croc_ex_checkAnyParam(t, 3);

		if(lo < 0)
			lo += len;

		if(hi < 0)
			hi += len;

		if(lo < 0 || lo > hi || hi > len)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid range indices: %" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT " (buffer length: %u)",
				lo, hi, len);

		_fillImpl(t, mb, 3, cast(uword)lo, cast(uword)hi);
		croc_dup(t, 0);
		return 1;
	}

	word_t _fillChar(CrocThread* t)
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto ch = croc_ex_checkCharParam(t, 1);
		auto lo = croc_ex_optIntParam(t, 2, 0);
		auto hi = croc_ex_optIntParam(t, 3, len);

		if(lo < 0)
			lo += len;

		if(hi < 0)
			hi += len;

		if(lo < 0 || lo > hi || hi > len)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid range indices: %" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT " (buffer length: %u)",
				lo, hi, len);

		mb->data.template as<dchar>().slice(cast(uword)lo, cast(uword)hi).fill(ch);
		return 0;
	}

	word_t _insert(CrocThread* t)
	{
		auto mb = _getData(t);
		auto len = _getLength(t);
		auto idx = croc_ex_checkIntParam(t, 1);
		croc_ex_checkAnyParam(t, 2);

		if(idx < 0)
			idx += len;

		// yes, greater, because it's possible to insert at one past the end of the buffer (it appends)
		if(idx < 0 || idx > len)
			croc_eh_throwStd(t, "BoundsError", "Invalid index: %" CROC_INTEGER_FORMAT " (length: %u)", idx, len);

		auto doResize = [&](crocint otherLen)
		{
			auto totalLen = len + otherLen;

			if(totalLen > std::numeric_limits<uword>::max())
				croc_eh_throwStd(t, "RangeError", "Invalid size (%" CROC_INTEGER_FORMAT ")", totalLen);

			auto oldLen = len;

			_ensureSize(t, mb, cast(uword)totalLen);
			_setLength(t, cast(uword)totalLen);

			auto tmp = mb->data.template as<dchar>().slice(0, cast(uword)totalLen);

			if(idx < oldLen)
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
				auto str = getCrocstr(Thread::from(t), 2);
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
				auto str = getCrocstr(Thread::from(t), -1);
				auto tmp = doResize(cpLen);
				_toUtf32(str, tmp);
			}

			croc_popTop(t);
		}

		croc_dup(t, 0);
		return 1;
	}

	word_t _remove(CrocThread* t)
	{
		auto mb = _getData(t);
		auto len = _getLength(t);

		if(len == 0)
			croc_eh_throwStd(t, "ValueError", "StringBuffer is empty");

		auto lo = croc_ex_checkIntParam(t, 1);
		auto hi = croc_ex_optIntParam(t, 2, lo + 1);

		if(lo < 0)
			lo += len;

		if(hi < 0)
			hi += len;

		if(lo < 0 || lo > hi || hi > len)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid indices: %" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT " (length: %u)", lo, hi, len);

		if(lo != hi)
		{
			if(hi < len)
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

	template<bool reverse>
	word_t _commonFind(CrocThread* t)
	{
		// Source (search) string
		auto src = _stringBufferAsUtf32(t, 0);

		// Start index
		auto start = croc_ex_optIntParam(t, 2, reverse ? (src.length - 1) : 0);

		if(start < 0)
			start += src.length;

		if(start < 0 || start >= src.length)
			croc_eh_throwStd(t, "BoundsError", "Invalid start index %" CROC_INTEGER_FORMAT, start);

		// Pattern (searched) string
		dchar buf[64];
		auto tmp = dstring();
		auto pat = _checkStringOrStringBuffer(t, 1, dstring::n(buf, 64), tmp);

		// Search
		if(reverse)
			croc_pushInt(t, strRLocatePattern(src, pat, cast(uword)start));
		else
			croc_pushInt(t, strLocatePattern(src, pat, cast(uword)start));

		tmp.free(Thread::from(t)->vm->mem);

		return 1;
	}

	word_t _startsWith(CrocThread* t)
	{
		auto self = _stringBufferAsUtf32(t, 0);

		dchar buf[64];
		auto tmp = dstring();
		auto other = _checkStringOrStringBuffer(t, 1, dstring::n(buf, 64), tmp);
		croc_pushBool(t, self.length >= other.length && self.slice(0, other.length) == other);
		tmp.free(Thread::from(t)->vm->mem);
		return 0;
	}

	word_t _endsWith(CrocThread* t)
	{
		auto self = _stringBufferAsUtf32(t, 0);

		dchar buf[64];
		auto tmp = dstring();
		auto other = _checkStringOrStringBuffer(t, 1, dstring::n(buf, 64), tmp);
		croc_pushBool(t, self.length >= other.length && self.slice(self.length - other.length, self.length) == other);
		tmp.free(Thread::from(t)->vm->mem);
		return 0;
	}

	word_t _split(CrocThread* t)
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

	word_t _vsplit(CrocThread* t)
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
				croc_eh_throwStd(t, "ValueError", "Too many (>%u) parts when splitting", VSplitMax);
			}
		});

		tmp.free(Thread::from(t)->vm->mem);

		return num;
	}

	const dchar Whitespace_[] = {' ', '\t', '\v', '\r', '\n', '\f'};
	const DArray<const dchar> Whitespace = {Whitespace_, 6};

	word_t _splitWS(CrocThread* t)
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

	word_t _vsplitWS(CrocThread* t)
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
					croc_eh_throwStd(t, "ValueError", "Too many (>%u) parts when splitting", VSplitMax);
			}
		});

		return num;
	}

	word_t _splitLines(CrocThread* t)
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

	word_t _vsplitLines(CrocThread* t)
	{
		auto src = _stringBufferAsUtf32(t, 0);
		uword num = 0;

		lines(src, [&](DArray<const dchar> piece)
		{
			_stringBufferFromUtf32(t, piece);
			num++;

			if(num > VSplitMax)
				croc_eh_throwStd(t, "ValueError", "Too many (>%u) parts when splitting", VSplitMax);
		});

		return num;
	}

	word_t _repeat_ip(CrocThread* t)
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

	word_t _reverse_ip(CrocThread* t)
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

	word_t _strip_ip(CrocThread* t)
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

	word_t _lstrip_ip(CrocThread* t)
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

	word_t _rstrip_ip(CrocThread* t)
	{
		auto src = _stringBufferAsUtf32(t, 0);
		auto trimmed = strTrimrWS(src);

		if(src.length != trimmed.length)
			_setLength(t, trimmed.length);

		croc_dup(t, 0);
		return 1;
	}

	word_t _replace_ip(CrocThread* t)
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

	word_t _repeat(CrocThread* t)
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

	word_t _reverse(CrocThread* t)
	{
		_getData(t);
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "dup", 1);
		croc_pushNull(t);
		return croc_methodCall(t, -2, "reverse!", 1);
	}

	word_t _strip(CrocThread* t)
	{
		_getData(t);
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "dup", 1);
		croc_pushNull(t);
		return croc_methodCall(t, -2, "strip!", 1);
	}

	word_t _lstrip(CrocThread* t)
	{
		_getData(t);
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "dup", 1);
		croc_pushNull(t);
		return croc_methodCall(t, -2, "lstrip!", 1);
	}

	word_t _rstrip(CrocThread* t)
	{
		_getData(t);
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "dup", 1);
		croc_pushNull(t);
		return croc_methodCall(t, -2, "rstrip!", 1);
	}

	word_t _replace(CrocThread* t)
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

	word_t _format(CrocThread* t)
	{
		(void)t;
		return 0;
	}

	word_t _formatln(CrocThread* t)
	{
		(void)t;
		return 0;
	}

	word_t _opSerialize(CrocThread* t)
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

	word_t _opDeserialize(CrocThread* t)
	{
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

	word_t _opApply(CrocThread* t)
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

	word_t _iterator(CrocThread* t)
	{
		auto mb = _getData(t);
		auto index = croc_ex_checkIntParam(t, 1) + 1;

		if(index >= _getLength(t))
			return 0;

		croc_pushInt(t, index);
		croc_pushChar(t, (mb->data.template as<dchar>())[cast(uword)index]);

		return 2;
	}

	word_t _iteratorReverse(CrocThread* t)
	{
		auto mb = _getData(t);
		auto index = croc_ex_checkIntParam(t, 1) - 1;

		if(index < 0)
			return 0;

		croc_pushInt(t, index);
		croc_pushChar(t, (mb->data.template as<dchar>())[cast(uword)index]);

		return 2;
	}

	const CrocRegisterFunc _methods[] =
	{
		{"constructor",     1, &_constructor,       0},
		{"dup",             0, &_dup,               0},
		{"toString",        2, &_toString,          0},
		{"opEquals",        1, &_opEquals,          0},
		{"opCmp",           1, &_opCmp,             0},
		{"opLength",        0, &_opLength,          0},
		{"opLengthAssign",  1, &_opLengthAssign,    0},
		{"opIndex",         1, &_opIndex,           0},
		{"opIndexAssign",   2, &_opIndexAssign,     0},
		{"opCat",           1, &_opCat,             0},
		{"opCat_r",         1, &_opCat_r,           0},
		{"opCatAssign",    -1, &_opCatAssign,       0},
		{"opSlice",         2, &_opSlice,           0},
		{"fill",            1, &_fill,              0},
		{"fillRange",       3, &_fillRange,         0},
		{"fillChar",        3, &_fillChar,          0},
		{"insert",          2, &_insert,            0},
		{"remove",          2, &_remove,            0},
		{"find",            2, &_commonFind<false>, 0},
		{"rfind",           2, &_commonFind<true>,  0},
		{"startsWith",      1, &_startsWith,        0},
		{"endsWith",        1, &_endsWith,          0},
		{"split",           1, &_split,             0},
		{"vsplit",          1, &_vsplit,            0},
		{"splitWS",         0, &_splitWS,           0},
		{"vsplitWS",        0, &_vsplitWS,          0},
		{"splitLines",      0, &_splitLines,        0},
		{"vsplitLines",     0, &_vsplitLines,       0},
		{"repeat!",         1, &_repeat_ip,         0},
		{"reverse!",        0, &_reverse_ip,        0},
		{"strip!",          0, &_strip_ip,          0},
		{"lstrip!",         0, &_lstrip_ip,         0},
		{"rstrip!",         0, &_rstrip_ip,         0},
		{"replace!",        2, &_replace_ip,        0},
		{"repeat",          1, &_repeat,            0},
		{"reverse",         0, &_reverse,           0},
		{"strip",           0, &_strip,             0},
		{"lstrip",          0, &_lstrip,            0},
		{"rstrip",          0, &_rstrip,            0},
		{"replace",         2, &_replace,           0},
		{"format",         -1, &_format,            0},
		{"formatln",       -1, &_formatln,          0},
		{"opSerialize",     2, &_opSerialize,       0},
		{"opDeserialize",   2, &_opDeserialize,     0},
		{nullptr, 0, nullptr, 0}
	};

	const CrocRegisterFunc _opApplyFunc = {"opApply", 1, &_opApply, 2};
	}

	void initStringLib_StringBuffer(CrocThread* t)
	{
		croc_class_new(t, "StringBuffer", 0);
			croc_pushNull(t);   croc_class_addHField(t, -2, Data);
			croc_pushInt(t, 0); croc_class_addHField(t, -2, Length);

			croc_ex_registerMethods(t, _methods);

				croc_function_new(t, "iterator",        1, &_iterator,        0);
				croc_function_new(t, "iteratorReverse", 1, &_iteratorReverse, 0);
			croc_ex_registerMethod(t, _opApplyFunc);

			croc_field(t, -1, "fillRange");   croc_class_addMethod(t, -2, "opSliceAssign");
			croc_field(t, -1, "opCatAssign"); croc_class_addMethod(t, -2, "append");
		croc_newGlobal(t, "StringBuffer");
	}
}