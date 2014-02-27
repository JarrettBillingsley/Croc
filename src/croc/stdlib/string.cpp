
#include <stdlib.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"
#include "croc/util/str.hpp"

namespace croc
{
	namespace
	{
	crocstr checkCrocstrParam(CrocThread* t, word_t slot)
	{
		auto ret = crocstr();
		ret.ptr = croc_ex_checkStringParamn(t, slot, &ret.length);
		return ret;
	}

#define pushCrocstr(t, str) croc_pushStringn((t), (str).ptr, (str).length)

	const uword VSplitMax = 20;

	// word_t _format(CrocThread* t)
	// {
	// 	uint sink(char[] s)
	// 	{
	// 		if(s.length)
	// 			croc_pushString(t, s);

	// 		return s.length;
	// 	}

	// 	croc_ex_checkStringParam(t, 0);
	// 	auto startSize = croc_getStackSize(t);
	// 	formatImpl(t, 0, startSize, &sink);
	// 	croc_cat(t, croc_getStackSize(t) - startSize);
	// 	return 1;
	// }

	word_t _join(CrocThread* t)
	{
		auto sep = checkCrocstrParam(t, 0);
		croc_ex_checkParam(t, 1, CrocType_Array);
		auto arr = getArray(Thread::from(t), 1)->toDArray();

		if(arr.length == 0)
		{
			croc_pushString(t, "");
			return 1;
		}

		uword totalLen = 0;
		uword i = 0;

		for(auto &val: arr)
		{
			if(val.value.type == CrocType_String)
				totalLen += val.value.mString->length;
			else
				croc_eh_throwStd(t, "TypeError", "Array element %u is not a string", i);

			i++;
		}

		// TODO:range
		totalLen += sep.length * (arr.length - 1);
		auto buf = DArray<char>::alloc(Thread::from(t)->vm->mem, totalLen);
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

	word_t _vjoin(CrocThread* t)
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

	word_t _toInt(CrocThread* t)
	{
		auto src = checkCrocstrParam(t, 0);
		auto base = croc_ex_optIntParam(t, 1, 10);

		if(src.length == 0)
			croc_eh_throwStd(t, "ValueError", "cannot convert empty string to integer");

		if(base < 2 || base > 36)
			croc_eh_throwStd(t, "RangeError", "base must be in the range [2 .. 36]");

		char* endptr;
		auto ret = strtol(src.ptr, &endptr, base);

		if(endptr != src.ptr + src.length)
			croc_eh_throwStd(t, "ValueError", "invalid integer");

		croc_pushInt(t, ret);
		return 1;
	}

	word_t _toFloat(CrocThread* t)
	{
		auto src = checkCrocstrParam(t, 0);

		if(src.length == 0)
			croc_eh_throwStd(t, "ValueError", "cannot convert empty string to float");

		char* endptr;
		auto ret = strtod(src.ptr, &endptr);

		if(endptr != src.ptr + src.length)
			croc_eh_throwStd(t, "ValueError", "invalid float");

		croc_pushFloat(t, ret);
		return 1;
	}

	word_t _ord(CrocThread* t)
	{
		auto s = checkCrocstrParam(t, 0);
		auto cpLen = croc_len(t, 0); // we want the CP length, not the byte length
		auto idx = croc_ex_optIntParam(t, 1, 0);

		if(idx < 0)
			idx += cpLen;

		if(idx < 0 || idx >= cpLen)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid index %" CROC_INTEGER_FORMAT " (string length: %" CROC_UINTEGER_FORMAT ")", idx, cpLen);

		croc_pushInt(t, utf8CharAt(s, cast(uword)idx));
		return 1;
	}

	word_t _compare(CrocThread* t)
	{
		croc_pushInt(t, checkCrocstrParam(t, 0).cmp(checkCrocstrParam(t, 1)));
		return 1;
	}

	template<bool reverse>
	word_t _commonFind(CrocThread* t)
	{
		// Source (search) string
		auto src = checkCrocstrParam(t, 0);
		auto srcCPLen = croc_len(t, 0);

		// Pattern (searched) string
		auto pat = checkCrocstrParam(t, 1);

		if(pat.length == 0)
		{
			croc_pushInt(t, srcCPLen);
			return 1;
		}

		// Start index
		auto start = croc_ex_optIntParam(t, 2, reverse ? (srcCPLen - 1) : 0);

		if(start < 0)
			start += srcCPLen;

		if(start < 0 || start >= srcCPLen)
			croc_eh_throwStd(t, "BoundsError", "Invalid start index %" CROC_INTEGER_FORMAT, start);

		if(reverse)
			start++; // because of the way fastReverseUtf8Char works

		// Search
		if(reverse)
			croc_pushInt(t, utf8ByteIdxToCP(src, strRLocate(src, pat, utf8CPIdxToByte(src, cast(uword)start))));
		else
			croc_pushInt(t, utf8ByteIdxToCP(src, strLocate(src, pat, utf8CPIdxToByte(src, cast(uword)start))));

		return 1;
	}

	word_t _repeat(CrocThread* t)
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

	word_t _reverse(CrocThread* t)
	{
		uword srcByteLen;
		auto src = croc_ex_checkStringParamn(t, 0, &srcByteLen);

		if(croc_len(t, 0) <= 1)
		{
			croc_dup(t, 0);
			return 1;
		}

		char buf[256];
		char* b;
		auto tmp = DArray<char>();

		if(srcByteLen <= 256)
			b = buf;
		else
		{
			tmp = DArray<char>::alloc(Thread::from(t)->vm->mem, srcByteLen);
			b = tmp.ptr;
		}

		const char* s = src + srcByteLen;
		auto prevS = s;

		for(s--, fastAlignUtf8(s); s >= src; prevS = s, s--, fastAlignUtf8(s))
		{
			for(auto p = s; p < prevS; )
				*b++ = *p++;

			if(s == src)
				break; // have to break to not read out of bounds
		}

		if(tmp.ptr)
		{
			assert(cast(uword)(b - tmp.ptr) == srcByteLen);
			croc_pushStringn(t, tmp.ptr, srcByteLen);
			// XXX: this might not run if croc_pushStringn fails, but it would only fail in an OOM situation, so..?
			tmp.free(Thread::from(t)->vm->mem);
		}
		else
		{
			assert(cast(uword)(b - buf) == srcByteLen);
			croc_pushStringn(t, buf, srcByteLen);
		}

		return 1;
	}

	word_t _split(CrocThread* t)
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

	word_t _vsplit(CrocThread* t)
	{
		auto src = checkCrocstrParam(t, 0);
		auto splitter = checkCrocstrParam(t, 1);
		uword_t num = 0;

		patterns(src, splitter, [&](crocstr piece)
		{
			pushCrocstr(t, piece);
			num++;

			if(num > VSplitMax)
				croc_eh_throwStd(t, "ValueError", "Too many (>%u) parts when splitting string", VSplitMax);
		});

		return num;
	}

	const char* Whitespace = " \t\v\r\n\f";

	word_t _splitWS(CrocThread* t)
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

	word_t _vsplitWS(CrocThread* t)
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
					croc_eh_throwStd(t, "ValueError", "Too many (>%u) parts when splitting string", VSplitMax);
			}
		});

		return num;
	}

	word_t _splitLines(CrocThread* t)
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

	word_t _vsplitLines(CrocThread* t)
	{
		auto src = checkCrocstrParam(t, 0);
		uword num = 0;

		lines(src, [&](crocstr line)
		{
			pushCrocstr(t, line);
			num++;

			if(num > VSplitMax)
				croc_eh_throwStd(t, "ValueError", "Too many (>%u) parts when splitting string", VSplitMax);
		});

		return num;
	}

	word_t _strip(CrocThread* t)
	{
		// no inline because pushCrocstr evals string twice
		auto ret = strTrimWS(checkCrocstrParam(t, 0));
		pushCrocstr(t, ret);
		return 1;
	}

	word_t _lstrip(CrocThread* t)
	{
		// no inline because pushCrocstr evals string twice
		auto ret = strTrimlWS(checkCrocstrParam(t, 0));
		pushCrocstr(t, ret);
		return 1;
	}

	word_t _rstrip(CrocThread* t)
	{
		// no inline because pushCrocstr evals string twice
		auto ret = strTrimrWS(checkCrocstrParam(t, 0));
		pushCrocstr(t, ret);
		return 1;
	}

	word_t _replace(CrocThread* t)
	{
		auto src = checkCrocstrParam(t, 0);
		auto from = checkCrocstrParam(t, 1);
		auto to = checkCrocstrParam(t, 2);

		CrocStrBuffer buf;
		croc_ex_buffer_init(t, &buf);

		patternsRep(src, from, to, [&](crocstr piece)
		{
			croc_ex_buffer_addStringn(&buf, piece.ptr, piece.length);
		});

		croc_ex_buffer_finish(&buf);
		return 1;
	}

	word_t _iterator(CrocThread* t)
	{
		auto str = checkCrocstrParam(t, 0);
		auto fakeIdx = croc_ex_checkIntParam(t, 1) + 1;

		croc_pushUpval(t, 0);
		auto realIdx = croc_getInt(t, -1);
		croc_popTop(t);

		if(realIdx >= str.length)
			return 0;

		const char* ptr = str.ptr + realIdx;
		auto oldPtr = ptr;
		fastDecodeUtf8Char(ptr);

		croc_pushInt(t, ptr - str.ptr);
		croc_setUpval(t, 0);

		croc_pushInt(t, fakeIdx);
		croc_pushStringn(t, oldPtr, ptr - oldPtr);
		return 2;
	}

	word_t _iteratorReverse(CrocThread* t)
	{
		auto str = checkCrocstrParam(t, 0);
		auto fakeIdx = croc_ex_checkIntParam(t, 1) - 1;

		croc_pushUpval(t, 0);
		auto realIdx = croc_getInt(t, -1);
		croc_popTop(t);

		if(realIdx <= 0)
			return 0;

		const char* ptr = str.ptr + realIdx;
		auto oldPtr = ptr;
		fastReverseUtf8Char(ptr);

		croc_pushInt(t, ptr - str.ptr);
		croc_setUpval(t, 0);

		croc_pushInt(t, fakeIdx);
		croc_pushStringn(t, ptr, oldPtr - ptr);
		return 2;
	}

	word_t _opApply(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_String);
		auto mode = croc_ex_optStringParam(t, 1, "");

		if(strcmp(mode, "reverse") == 0)
		{
			croc_pushInt(t, getStringObj(Thread::from(t), 0)->length);
			croc_function_new(t, "iteratorReverse", 1, &_iteratorReverse, 1);
			croc_dup(t, 0);
			croc_pushInt(t, croc_len(t, 0));
		}
		else
		{
			croc_pushInt(t, 0);
			croc_function_new(t, "iterator", 1, &_iterator, 1);
			croc_dup(t, 0);
			croc_pushInt(t, -1);
		}

		return 3;
	}

	word_t _startsWith(CrocThread* t)
	{
		auto str = checkCrocstrParam(t, 0);
		auto sub = checkCrocstrParam(t, 1);
		croc_pushBool(t, str.length >= sub.length && str.slice(0, sub.length) == sub);
		return 1;
	}

	word_t _endsWith(CrocThread* t)
	{
		auto str = checkCrocstrParam(t, 0);
		auto sub = checkCrocstrParam(t, 1);
		croc_pushBool(t, str.length >= sub.length && str.slice(str.length - sub.length, str.length) == sub);
		return 1;
	}

	const CrocRegisterFunc _methodFuncs[] =
	{
		// {"format",       -1, &_format,            0},
		{"join",          1, &_join,              0},
		{"vjoin",        -1, &_vjoin,             0},
		{"toInt",         1, &_toInt,             0},
		{"toFloat",       0, &_toFloat,           0},
		{"ord",           1, &_ord,               0},
		{"compare",       1, &_compare,           0},
		{"find",          2, &_commonFind<false>, 0},
		{"rfind",         2, &_commonFind<true>,  0},
		{"repeat",        1, &_repeat,            0},
		{"reverse",       0, &_reverse,           0},
		{"split",         1, &_split,             0},
		{"splitWS",       0, &_splitWS,           0},
		{"vsplit",        1, &_vsplit,            0},
		{"vsplitWS",      0, &_vsplitWS,          0},
		{"splitLines",    0, &_splitLines,        0},
		{"vsplitLines",   0, &_vsplitLines,       0},
		{"strip",         0, &_strip,             0},
		{"lstrip",        0, &_lstrip,            0},
		{"rstrip",        0, &_rstrip,            0},
		{"replace",       2, &_replace,           0},
		{"opApply",       1, &_opApply,           0},
		{"startsWith",    1, &_startsWith,        0},
		{"endsWith",      1, &_endsWith,          0},
		{nullptr, 0, nullptr, 0}
	};

	word loader(CrocThread* t)
	{
		// initStringBuffer(t);

		croc_namespace_new(t, "string");
			croc_ex_registerFields(t, _methodFuncs);
		croc_vm_setTypeMT(t, CrocType_String);
		return 0;
	}
	}

	void initStringLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "string", &loader);
		croc_ex_importModuleNoNS(t, "string");
	}
}