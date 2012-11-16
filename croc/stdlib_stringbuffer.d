/******************************************************************************
This module contains the implementation of the StringBuffer class defined in
the string stdlib.

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

module croc.stdlib_stringbuffer;

import tango.math.Math;
import tango.stdc.string;
import tango.text.Util;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_format;
import croc.ex_library;
import croc.types;
import croc.utils;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initStringBuffer(CrocThread* t)
{
	CreateClass(t, "StringBuffer", (CreateClass* c)
	{
		c.allocator("allocator", &BasicClassAllocator!(NumFields, 0));

		c.method("constructor",    1, &_constructor);
		c.method("dup",            0, &_dup);
		c.method("toString",       2, &_toString);

		c.method("opEquals",       1, &_opEquals);
		c.method("opCmp",          1, &_opCmp);
		c.method("opLength",       0, &_opLength);
		c.method("opLengthAssign", 1, &_opLengthAssign);
		c.method("opIndex",        1, &_opIndex);
		c.method("opIndexAssign",  2, &_opIndexAssign);
		c.method("opCat",          1, &_opCat);
		c.method("opCat_r",        1, &_opCat_r);
		c.method("opCatAssign",       &_opCatAssign);
		c.method("opSlice",        2, &_opSlice);

		c.method("fill",           1, &_fill);
		c.method("fillRange",      3, &_fillRange);
		c.method("insert",         2, &_insert);
		c.method("remove",         2, &_remove);

		c.method("find",           2, &_find);
		c.method("rfind",          2, &_rfind);
		c.method("startsWith",     1, &_startsWith);
		c.method("endsWith",       1, &_endsWith);

		c.method("split",          1, &_split);
		c.method("splitWS",        0, &_splitWS);
		c.method("vsplit",         1, &_vsplit);
		c.method("vsplitWS",       0, &_vsplitWS);
		c.method("splitLines",     0, &_splitLines);
		c.method("vsplitLines",    0, &_vsplitLines);

		c.method("repeat!",        1, &_repeat_ip);
		c.method("reverse!",       0, &_reverse_ip);
		c.method("strip!",         0, &_strip_ip);
		c.method("lstrip!",        0, &_lstrip_ip);
		c.method("rstrip!",        0, &_rstrip_ip);
		c.method("replace!",       2, &_replace_ip);

		c.method("repeat",         1, &_repeat);
		c.method("reverse",        0, &_reverse);
		c.method("strip",          0, &_strip);
		c.method("lstrip",         0, &_lstrip);
		c.method("rstrip",         0, &_rstrip);
		c.method("replace",        2, &_replace);

		c.method("format",            &_format);
		c.method("formatln",          &_formatln);

			newFunction(t, &_iterator, "iterator");
			newFunction(t, &_iteratorReverse, "iteratorReverse");
		c.method("opApply", 1, &_opApply, 2);

		c.method("opSerialize",   &_opSerialize);
		c.method("opDeserialize", &_opDeserialize);
	});

	field(t, -1, "fillRange");
	fielda(t, -2, "opSliceAssign");

	field(t, -1, "opCatAssign");
	fielda(t, -2, "append");

	newGlobal(t, "StringBuffer");
}

version(CrocBuiltinDocs) void docStringBuffer(CrocThread* t, CrocDoc doc)
{
	field(t, -1, "StringBuffer");
		doc.push(_classDocs);
		docFields(t, doc, _methodDocs);
		doc.pop(-1);
	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

// =============================================================
// Helpers

enum
{
	Data,
	Length,

	NumFields
}

CrocMemblock* _getData(CrocThread* t, word idx = 0)
{
	getExtraVal(t, idx, Data);

	if(!isMemblock(t, -1))
		throwStdException(t, "StateException", "Attempting to operate on an uninitialized StringBuffer");

	auto ret = getMemblock(t, -1);
	pop(t);
	return ret;
}

uword _getLength(CrocThread* t, word idx = 0)
{
	getExtraVal(t, idx, Length);
	auto ret = cast(uword)getInt(t, -1);
	pop(t);
	return ret;
}

void _setLength(CrocThread* t, uword l, word idx = 0)
{
	idx = absIndex(t, idx);
	pushInt(t, cast(crocint)l);
	setExtraVal(t, idx, Length);
}

void _ensureSize(CrocThread* t, CrocMemblock* mb, uword size)
{
	auto dataLength = mb.data.length >> 2;

	if(dataLength == 0)
	{
		push(t, CrocValue(mb));
		lenai(t, -1, size << 2);
		pop(t);
	}
	else if(size > dataLength)
	{
		auto l = dataLength;

		while(size > l)
		{
			if(l & (1 << ((uword.sizeof * 8) - 1)))
				throwStdException(t, "RangeException", "StringBuffer too big ({} elements)", size);
			l <<= 1;
		}

		push(t, CrocValue(mb));
		lenai(t, -1, l << 2);
		pop(t);
	}
}

dchar[] _stringBufferAsUtf32(CrocThread* t, word idx)
{
	auto mb = _getData(t, idx);
	return (cast(dchar*)mb.data)[0 .. _getLength(t, idx)];
}

word _stringBufferFromUtf32(CrocThread* t, dchar[] text)
{
	auto ret = pushGlobal(t, "StringBuffer");
	pushNull(t);
	pushInt(t, text.length);
	rawCall(t, ret, 1);
	_setLength(t, text.length, ret);
	_stringBufferAsUtf32(t, ret)[] = text[];
	return ret;
}

dchar[] _checkStringOrStringBuffer(CrocThread* t, word idx, ref dchar[] tmp, char[] errMsg = "string|StringBuffer")
{
	checkAnyParam(t, idx);

	if(isString(t, idx))
	{
		tmp = allocArray!(dchar)(t, cast(uword)len(t, idx));
		return UTF8toUTF32(getString(t, idx), tmp);
	}
	else
	{
		pushGlobal(t, "StringBuffer");

		if(as(t, idx, -1))
		{
			pop(t);
			return _stringBufferAsUtf32(t, idx);
		}
		else
			paramTypeError(t, idx, errMsg);
	}

	assert(false);
}

// =============================================================
// Methods

const uword VSplitMax = 20;

uword _constructor(CrocThread* t)
{
	checkInstParam(t, 0, "StringBuffer");

	char[] data = void;
	uword length = void;

	if(isValidIndex(t, 1))
	{
		if(isString(t, 1))
		{
			data = getString(t, 1);
			length = cast(uword)len(t, 1); // need codepoint length
		}
		else if(isInt(t, 1))
		{
			data = "";
			auto l = getInt(t, 1);

			if(l < 0 || l > uword.max)
				throwStdException(t, "RangeException", "Invalid length: {}", l);

			length = cast(uword)l;
		}
	}
	else
	{
		data = "";
		length = 0;
	}

	newMemblock(t, length << 2);

	if(data.length > 0)
	{
		auto mb = getMemblock(t, -1);
		UTF8ToUTF32(data, cast(dchar[])mb.data);
		_setLength(t, length);
	}
	else
		_setLength(t, 0);

	setExtraVal(t, 0, Data);
	return 0;
}

uword _dup(CrocThread* t)
{
	auto mb = _getData(t);
	auto len = _getLength(t);

	pushGlobal(t, "StringBuffer");
	pushNull(t);
	pushInt(t, len);
	rawCall(t, -3, 1);

	auto other = _getData(t, -1);
	other.data[0 .. len << 2] = mb.data[0 .. len << 2];
	_setLength(t, len, -1);
	return 1;
}

uword _toString(CrocThread* t)
{
	auto mb = _getData(t);
	auto len = _getLength(t);
	auto lo = optIntParam(t, 1, 0);
	auto hi = optIntParam(t, 2, len);

	if(lo < 0)
		lo += len;

	if(hi < 0)
		hi += len;

	if(lo < 0 || lo > hi || hi > len)
		throwStdException(t, "BoundsException", "Invalid slice indices: {} .. {} (buffer length: {})", lo, hi, len);

	pushFormat(t, "{}", (cast(dchar[])mb.data)[cast(uword)lo .. cast(uword)hi]);
	return 1;
}

uword _opEquals(CrocThread* t)
{
	auto mb = _getData(t);
	auto len = _getLength(t);
	checkAnyParam(t, 1);

	pushGlobal(t, "StringBuffer");

	if(opis(t, 0, 1))
		pushBool(t, true);
	else if(isString(t, 1))
	{
		if(len != .len(t, 1))
			pushBool(t, false);
		else
		{
			auto data = cast(dchar[])mb.data;
			auto other = getString(t, 1);
			uword pos = 0;

			foreach(dchar c; other)
			{
				if(c != data[pos++])
				{
					pushBool(t, false);
					return 1;
				}
			}

			pushBool(t, true);
		}
	}
	else if(as(t, 1, -1))
	{
		auto otherLen = _getLength(t, 1);

		if(len != otherLen)
			pushBool(t, false);
		else
		{
			auto other = _getData(t, 1);

			auto a = (cast(dchar[])mb.data)[0 .. len];
			auto b = (cast(dchar[])other.data)[0 .. a.length];
			pushBool(t, a == b);
		}
	}
	else
		paramTypeError(t, 1, "string|StringBuffer");

	return 1;
}

uword _opCmp(CrocThread* t)
{
	auto mb = _getData(t);
	auto len = _getLength(t);
	checkAnyParam(t, 1);

	pushGlobal(t, "StringBuffer");

	if(opis(t, 0, 1))
		pushInt(t, 0);
	else if(isString(t, 1))
	{
		auto otherLen = .len(t, 1);
		auto l = min(len, otherLen);

		auto data = cast(dchar[])mb.data;
		auto other = getString(t, 1);
		uword pos = 0;

		foreach(i, dchar c; other)
		{
			if(pos >= l)
				break;

			if(c != data[pos])
			{
				pushInt(t, Compare3(c, data[pos]));
				return 1;
			}

			pos++;
		}

		pushInt(t, Compare3(len, cast(uword)otherLen));
	}
	else if(as(t, 1, -1))
	{
		auto otherLen = _getLength(t, 1);
		auto l = min(len, otherLen);
		auto other = _getData(t, 1);
		auto a = (cast(dchar[])mb.data)[0 .. l];
		auto b = (cast(dchar[])other.data)[0 .. l];

		if(auto cmp = typeid(dchar[]).compare(&a, &b))
			pushInt(t, cmp);
		else
			pushInt(t, Compare3(len, cast(uword)otherLen));
	}
	else
		paramTypeError(t, 1, "string|StringBuffer");

	return 1;
}

uword _opLength(CrocThread* t)
{
	_getData(t);
	getExtraVal(t, 0, Length);
	return 1;
}

uword _opLengthAssign(CrocThread* t)
{
	auto mb = _getData(t);
	auto newLen = checkIntParam(t, 1);

	if(newLen < 0 || newLen > uword.max)
		throwStdException(t, "RangeException", "Invalid length: {}", newLen);

	auto oldLen = _getLength(t);

	if(cast(uword)newLen < oldLen)
		_setLength(t, cast(uword)newLen);
	else if(cast(uword)newLen > oldLen)
	{
		_ensureSize(t, mb, cast(uword)newLen);
		_setLength(t, cast(uword)newLen);
		(cast(dchar[])mb.data)[oldLen .. cast(uword)newLen] = dchar.init;
	}

	return 0;
}

uword _opIndex(CrocThread* t)
{
	auto mb = _getData(t);
	auto len = _getLength(t);
	auto index = checkIntParam(t, 1);

	if(index < 0)
		index += len;

	if(index < 0 || index >= len)
		throwStdException(t, "BoundsException", "Invalid index: {} (buffer length: {})", index, len);

	pushChar(t, (cast(dchar[])mb.data)[cast(uword)index]);
	return 1;
}

uword _opIndexAssign(CrocThread* t)
{
	auto mb = _getData(t);
	auto len = _getLength(t);
	auto index = checkIntParam(t, 1);
	auto ch = checkCharParam(t, 2);

	if(index < 0)
		index += len;

	if(index < 0 || index >= len)
		throwStdException(t, "BoundsException", "Invalid index: {} (buffer length: {})", index, len);

	(cast(dchar[])mb.data)[cast(uword)index] = ch;
	return 0;
}

uword _opSlice(CrocThread* t)
{
	auto mb = _getData(t);
	auto len = _getLength(t);
	auto lo = optIntParam(t, 1, 0);
	auto hi = optIntParam(t, 2, len);

	if(lo < 0)
		lo += len;

	if(hi < 0)
		hi += len;

	if(lo < 0 || lo > hi || hi > len)
		throwStdException(t, "BoundsException", "Invalid slice indices: {} .. {} (buffer length: {})", lo, hi, len);

	auto newStr = (cast(dchar[])mb.data)[cast(uword)lo .. cast(uword)hi];

	pushGlobal(t, "StringBuffer");
	pushNull(t);
	pushInt(t, newStr.length);
	rawCall(t, -3, 1);
	(cast(dchar[])_getData(t, -1).data)[] = newStr[];
	_setLength(t, newStr.length, -1);
	return 1;
}

uword _opCat(CrocThread* t)
{
	auto mb = _getData(t);
	auto len = _getLength(t);
	auto src = cast(dchar[])mb.data;

	dchar[] makeObj(crocint addLen)
	{
		auto totalLen = len + addLen;

		if(totalLen > uword.max)
			throwStdException(t, "RangeException", "Result too big ({} elements)", totalLen);

		pushGlobal(t, "StringBuffer");
		pushNull(t);
		pushInt(t, totalLen);
		rawCall(t, -3, 1);
		_setLength(t, cast(uword)totalLen, -1);
		auto ret = cast(dchar[])_getData(t, -1).data;
		ret[0 .. len] = src[0 .. len];
		return ret[len .. $];
	}

	checkAnyParam(t, 1);
	pushGlobal(t, "StringBuffer");

	if(isString(t, 1))
	{
		auto dest = makeObj(.len(t, 1));
		UTF8ToUTF32(getString(t, 1), dest);
	}
	else if(isChar(t, 1))
	{
		makeObj(1)[0] = getChar(t, 1);
	}
	else if(as(t, 1, -1))
	{
		auto otherLen = _getLength(t, 1);
		makeObj(otherLen)[] = (cast(dchar[])_getData(t, 1).data)[0 .. otherLen];
	}
	else
	{
		pushToString(t, 1);
		auto s = getString(t, -1);
		auto dest = makeObj(.len(t, -1));
		UTF8ToUTF32(s, dest);
		pop(t);
	}

	return 1;
}

uword _opCat_r(CrocThread* t)
{
	auto mb = _getData(t);
	auto len = _getLength(t);
	auto src = cast(dchar[])mb.data;

	dchar[] makeObj(crocint addLen)
	{
		auto totalLen = len + addLen;

		if(totalLen > uword.max)
			throwStdException(t, "RangeException", "Result too big ({} elements)", totalLen);

		pushGlobal(t, "StringBuffer");
		pushNull(t);
		pushInt(t, totalLen);
		rawCall(t, -3, 1);
		_setLength(t, cast(uword)totalLen, -1);
		auto ret = cast(dchar[])_getData(t, -1).data;
		ret[cast(uword)addLen .. $] = src[0 .. len];
		return ret[0 .. cast(uword)addLen];
	}

	checkAnyParam(t, 1);

	if(isString(t, 1))
	{
		auto dest = makeObj(.len(t, 1));
		UTF8ToUTF32(getString(t, 1), dest);
	}
	else if(isChar(t, 1))
	{
		makeObj(1)[0] = getChar(t, 1);
	}
	else
	{
		pushToString(t, 1);
		auto s = getString(t, -1);
		auto dest = makeObj(.len(t, -1));
		UTF8ToUTF32(s, dest);
		pop(t);
	}

	return 1;
}

uword _opCatAssign(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	auto mb = _getData(t);
	auto len = _getLength(t);
	auto oldLen = len;

	dchar[] resize(crocint addLen)
	{
		auto totalLen = len + addLen;

		if(totalLen > uword.max)
			throwStdException(t, "RangeException", "Result too big ({} elements)", totalLen);

		_ensureSize(t, mb, cast(uword)totalLen);
		_setLength(t, cast(uword)totalLen);
		auto ret = (cast(dchar[])mb.data)[len .. cast(uword)totalLen];
		len = cast(uword)totalLen;
		return ret;
	}

	checkAnyParam(t, 1);
	pushGlobal(t, "StringBuffer");

	for(uword i = 1; i <= numParams; i++)
	{
		if(isString(t, i))
		{
			auto dest = resize(.len(t, i));
			UTF8ToUTF32(getString(t, i), dest);
		}
		else if(isChar(t, i))
			resize(1)[0] = getChar(t, i);
		else if(as(t, i, -1))
		{
			if(opis(t, 0, i))
			{
				// special case for when we're appending a stringbuffer to itself. use the old length
				resize(oldLen)[] = (cast(dchar[])mb.data)[0 .. oldLen];
			}
			else
			{
				auto otherLen = _getLength(t, i);
				resize(otherLen)[] = (cast(dchar[])_getData(t, i).data)[0 .. otherLen];
			}
		}
		else
		{
			pushToString(t, i);
			auto dest = resize(.len(t, -1));
			UTF8ToUTF32(getString(t, -1), dest);
			pop(t);
		}
	}

	// we're returning 'this' in case people want to chain 'append's, since this method is also append.
	dup(t, 0);
	return 1;
}

uword _iterator(CrocThread* t)
{
	auto mb = _getData(t);
	auto index = checkIntParam(t, 1) + 1;

	if(index >= _getLength(t))
		return 0;

	pushInt(t, index);
	pushChar(t, (cast(dchar[])mb.data)[cast(uword)index]);

	return 2;
}

uword _iteratorReverse(CrocThread* t)
{
	auto mb = _getData(t);
	auto index = checkIntParam(t, 1) - 1;

	if(index < 0)
		return 0;

	pushInt(t, index);
	pushChar(t, (cast(dchar[])mb.data)[cast(uword)index]);

	return 2;
}

uword _opApply(CrocThread* t)
{
	_getData(t);

	if(optStringParam(t, 1, "") == "reverse")
	{
		getUpval(t, 1);
		dup(t, 0);
		pushInt(t, _getLength(t));
	}
	else
	{
		getUpval(t, 0);
		dup(t, 0);
		pushInt(t, -1);
	}

	return 3;
}

void fillImpl(CrocThread* t, CrocMemblock* mb, word filler, uword lo, uword hi)
{
	pushGlobal(t, "StringBuffer");

	if(as(t, filler, -1))
	{
		if(opis(t, 0, filler))
			return;

		auto other = cast(dchar[])_getData(t, filler).data;
		auto otherLen = _getLength(t, filler);

		if(otherLen != (hi - lo))
			throwStdException(t, "ValueException", "Length of destination ({}) and length of source ({}) do not match", hi - lo, otherLen);

		(cast(dchar[])mb.data)[lo .. hi] = other[0 .. otherLen];
	}
	else if(isFunction(t, filler))
	{
		auto data = (cast(dchar[])mb.data)[0 .. _getLength(t)];

		for(uword i = lo; i < hi; i++)
		{
			dup(t, filler);
			pushNull(t);
			pushInt(t, i);
			rawCall(t, -3, 1);

			if(!isChar(t, -1))
			{
				pushTypeString(t, -1);
				throwStdException(t, "TypeException", "filler function expected to return a 'char', not '{}'", getString(t, -1));
			}

			data[i] = getChar(t, -1);
			pop(t);
		}
	}
	else if(isChar(t, filler))
		(cast(dchar[])mb.data)[lo .. hi] = getChar(t, filler);
	else if(isString(t, filler))
	{
		auto cpLen = cast(uword)len(t, filler);

		if(cpLen != (hi - lo))
			throwStdException(t, "ValueException", "Length of destination ({}) and length of source string ({}) do not match", hi - lo, cpLen);

		UTF8ToUTF32(getString(t, filler), (cast(dchar[])mb.data)[lo .. hi]);
	}
	else if(isArray(t, filler))
	{
		auto data = (cast(dchar[])mb.data)[lo .. hi];

		for(uword i = lo, ai = 0; i < hi; i++, ai++)
		{
			idxi(t, filler, ai);

			if(!isChar(t, -1))
			{
				pushTypeString(t, -1);
				throwStdException(t, "TypeException", "array element {} expected to be 'char', not '{}'", ai, getString(t, -1));
			}

			data[ai] = getChar(t, -1);
			pop(t);
		}
	}
	else
		paramTypeError(t, filler, "char|string|array|function|StringBuffer");

	pop(t);
}

uword _fill(CrocThread* t)
{
	auto mb = _getData(t);
	checkAnyParam(t, 1);
	fillImpl(t, mb, 1, 0, _getLength(t));
	dup(t, 0);
	return 1;
}

uword _fillRange(CrocThread* t)
{
	auto mb = _getData(t);
	auto len = _getLength(t);
	auto lo = optIntParam(t, 1, 0);
	auto hi = optIntParam(t, 2, len);
	checkAnyParam(t, 3);

	if(lo < 0)
		lo += len;

	if(hi < 0)
		hi += len;

	if(lo < 0 || lo > hi || hi > len)
		throwStdException(t, "BoundsException", "Invalid range indices: {} .. {} (buffer length: {})", lo, hi, len);

	fillImpl(t, mb, 3, cast(uword)lo, cast(uword)hi);
	dup(t, 0);
	return 1;
}

uword _insert(CrocThread* t)
{
	auto mb = _getData(t);
	auto len = _getLength(t);
	auto idx = checkIntParam(t, 1);
	checkAnyParam(t, 2);

	if(idx < 0)
		idx += len;

	// yes, greater, because it's possible to insert at one past the end of the buffer (it appends)
	if(len < 0 || idx > len)
		throwStdException(t, "BoundsException", "Invalid index: {} (length: {})", idx, len);

	dchar[] doResize(crocint otherLen)
	{
		auto totalLen = len + otherLen;

		if(totalLen > uword.max)
			throwStdException(t, "RangeException", "Invalid size ({})", totalLen);

		auto oldLen = len;

		_ensureSize(t, mb, cast(uword)totalLen);
		_setLength(t, cast(uword)totalLen);

		auto tmp = (cast(dchar[])mb.data)[0 .. cast(uword)totalLen];

		if(idx < oldLen)
		{
			auto end = idx + otherLen;
			auto numLeft = oldLen - idx;
			memmove(&tmp[cast(uword)end], &tmp[cast(uword)idx], cast(uword)(numLeft * dchar.sizeof));
		}

		return tmp[cast(uword)idx .. cast(uword)(idx + otherLen)];
	}

	pushGlobal(t, "StringBuffer");

	if(isString(t, 2))
	{
		auto cpLen = .len(t, 2);

		if(cpLen != 0)
		{
			auto str = getString(t, 2);
			auto tmp = doResize(cpLen);
			UTF8ToUTF32(str, tmp);
		}
	}
	else if(isChar(t, 2))
		doResize(1)[0] = getChar(t, 2);
	else if(as(t, 2, -1))
	{
		if(opis(t, 0, 2))
		{
			// special case for inserting a stringbuffer into itself

			if(len != 0)
			{
				auto slice = doResize(len);
				auto data = cast(dchar[])_getData(t).data;
				slice[0 .. cast(uword)idx] = data[0 .. cast(uword)idx];
				slice[cast(uword)idx .. $] = data[cast(uword)idx + len .. $];
			}
		}
		else
		{
			auto other = cast(dchar[])_getData(t, 2).data;
			auto otherLen = _getLength(t, 2);

			if(otherLen != 0)
				doResize(otherLen)[] = other[0 .. otherLen];
		}
	}
	else
	{
		pushToString(t, 2);

		auto cpLen = .len(t, -1);

		if(cpLen != 0)
		{
			auto str = getString(t, -1);
			auto tmp = doResize(cpLen);
			UTF8ToUTF32(str, tmp);
		}

		pop(t);
	}

	dup(t, 0);
	return 1;
}

uword _remove(CrocThread* t)
{
	auto mb = _getData(t);
	auto len = _getLength(t);

	if(len == 0)
		throwStdException(t, "ValueException", "StringBuffer is empty");

	auto lo = checkIntParam(t, 1);
	auto hi = optIntParam(t, 2, lo + 1);

	if(lo < 0)
		lo += len;

	if(hi < 0)
		hi += len;

	if(lo < 0 || lo > hi || hi > len)
		throwStdException(t, "BoundsException", "Invalid indices: {} .. {} (length: {})", lo, hi, len);

	if(lo != hi)
	{
		if(hi < len)
			memmove(&mb.data[cast(uword)lo * dchar.sizeof], &mb.data[cast(uword)hi * dchar.sizeof], cast(uint)((len - hi) * dchar.sizeof));

		dup(t, 0);
		pushNull(t);
		pushInt(t, len - (hi - lo));
		methodCall(t, -3, "opLengthAssign", 0);
	}

	dup(t, 0);
	return 1;
}

uword _commonFind(bool reverse)(CrocThread* t)
{
	auto src = _stringBufferAsUtf32(t, 0);

	// Pattern (searched) string/char
	dchar[1] buf;
	dchar[] tmp = null;
	dchar[] pat;
	scope(exit) freeArray(t, tmp);

	checkAnyParam(t, 1);

	if(isChar(t, 1))
	{
		buf[0] = getChar(t, 1);
		pat = buf[];
	}
	else
		pat = _checkStringOrStringBuffer(t, 1, tmp, "char|string|StringBuffer");

	// Start index
	static if(reverse)
		auto start = optIntParam(t, 2, src.length - 1);
	else
		auto start = optIntParam(t, 2, 0);

	if(start < 0)
		start += src.length;

	if(start < 0 || start >= src.length)
		throwStdException(t, "BoundsException", "Invalid start index {}", start);

	// Search

	static if(reverse)
		pushInt(t, src.locatePatternPrior(pat, cast(uword)start));
	else
		pushInt(t, src.locatePattern(pat, cast(uword)start));

	return 1;
}

alias _commonFind!(false) _find;
alias _commonFind!(true) _rfind;

uword _commonStartEnd(bool starts)(CrocThread* t)
{
	auto self = _stringBufferAsUtf32(t, 0);

	dchar[] tmp = null;
	scope(exit) freeArray(t, tmp);

	auto other = _checkStringOrStringBuffer(t, 1, tmp);

	static if(starts)
		pushBool(t, self.startsWith(other));
	else
		pushBool(t, self.endsWith(other));

	return 1;
}

alias _commonStartEnd!(true) _startsWith;
alias _commonStartEnd!(false) _endsWith;

uword _split(CrocThread* t)
{
	auto src = _stringBufferAsUtf32(t, 0);

	dchar[] tmp;
	scope(exit) freeArray(t, tmp);

	auto splitter = _checkStringOrStringBuffer(t, 1, tmp);
	auto ret = newArray(t, 0);
	uword num = 0;

	foreach(piece; src.patterns(splitter))
	{
		_stringBufferFromUtf32(t, piece);
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
	auto src = _stringBufferAsUtf32(t, 0);

	dchar[] tmp;
	scope(exit) freeArray(t, tmp);

	auto splitter = _checkStringOrStringBuffer(t, 1, tmp);
	uword num = 0;

	foreach(piece; src.patterns(splitter))
	{
		_stringBufferFromUtf32(t, piece);
		num++;

		if(num > VSplitMax)
			throwStdException(t, "ValueException", "Too many (>{}) parts when splitting", VSplitMax);
	}

	return num;
}

uword _splitWS(CrocThread* t)
{
	auto src = _stringBufferAsUtf32(t, 0);
	auto ret = newArray(t, 0);
	uword num = 0;

	foreach(piece; src.delimiters(" \t\v\r\n\f\u2028\u2029"d))
	{
		if(piece.length > 0)
		{
			_stringBufferFromUtf32(t, piece);
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
	auto src = _stringBufferAsUtf32(t, 0);
	uword num = 0;

	foreach(piece; src.delimiters(" \t\v\r\n\f\u2028\u2029"d))
	{
		if(piece.length > 0)
		{
			_stringBufferFromUtf32(t, piece);
			num++;

			if(num > VSplitMax)
				throwStdException(t, "ValueException", "Too many (>{}) parts when splitting string", VSplitMax);
		}
	}

	return num;
}

uword _splitLines(CrocThread* t)
{
	auto src = _stringBufferAsUtf32(t, 0);
	auto ret = newArray(t, 0);
	uword num = 0;

	foreach(line; src.lines())
	{
		_stringBufferFromUtf32(t, line);
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
	auto src = _stringBufferAsUtf32(t, 0);
	uword num = 0;

	foreach(line; src.lines())
	{
		_stringBufferFromUtf32(t, line);
		num++;

		if(num > VSplitMax)
			throwStdException(t, "ValueException", "Too many (>{}) parts when splitting string", VSplitMax);
	}

	return num;
}

uword _repeat_ip(CrocThread* t)
{
	auto mb = _getData(t);
	auto oldLen = _getLength(t);
	auto numTimes = checkIntParam(t, 1);

	if(numTimes < 0)
		throwStdException(t, "RangeException", "Invalid number of repetitions: {}", numTimes);

	auto newLen = cast(uword)numTimes * oldLen;

	_ensureSize(t, mb, newLen);
	_setLength(t, newLen);

	if(numTimes > 1)
	{
		auto src = (cast(dchar*)mb.data)[0 .. oldLen];
		auto dest = (cast(dchar*)mb.data) + oldLen;
		auto end = (cast(dchar*)mb.data) + newLen;

		for( ; dest < end; dest += oldLen)
			dest[0 .. oldLen] = src[0 .. oldLen];
	}

	dup(t, 0);
	return 1;
}

uword _reverse_ip(CrocThread* t)
{
	auto src = _stringBufferAsUtf32(t, 0);

	if(src.length > 1)
		src.reverse;

	dup(t, 0);
	return 1;
}

uword _strip_ip(CrocThread* t)
{
	auto src = _stringBufferAsUtf32(t, 0);

	auto trimmed = src.trim();

	if(src.length != trimmed.length)
	{
		if(src.ptr !is trimmed.ptr)
			memmove(src.ptr, trimmed.ptr, trimmed.length * dchar.sizeof);

		_setLength(t, trimmed.length);
	}

	dup(t, 0);
	return 1;
}

uword _lstrip_ip(CrocThread* t)
{
	auto src = _stringBufferAsUtf32(t, 0);

	auto trimmed = src.triml();

	if(src.length != trimmed.length)
	{
		memmove(src.ptr, trimmed.ptr, trimmed.length * dchar.sizeof);
		_setLength(t, trimmed.length);
	}

	dup(t, 0);
	return 1;
}

uword _rstrip_ip(CrocThread* t)
{
	auto src = _stringBufferAsUtf32(t, 0);

	auto trimmed = src.trimr();

	if(src.length != trimmed.length)
		_setLength(t, trimmed.length);

	dup(t, 0);
	return 1;
}

uword _replace_ip(CrocThread* t)
{
	auto src = _stringBufferAsUtf32(t, 0);

	dchar[] tmp1, tmp2, buffer;

	scope(exit)
	{
		freeArray(t, tmp1);
		freeArray(t, tmp2);
		freeArray(t, buffer);
	}

	auto from = _checkStringOrStringBuffer(t, 1, tmp1);
	auto to = _checkStringOrStringBuffer(t, 2, tmp2);
	buffer = allocArray!(dchar)(t, src.length);
	bool shouldCheckSize = from.length < to.length; // only have to grow if the 'to' string is bigger than the 'from' string
	uword destIdx = 0;

	foreach(piece; src.patterns(from, to))
	{
		if(shouldCheckSize && destIdx + piece.length > buffer.length)
			resizeArray(t, buffer, max(destIdx + piece.length, buffer.length * 2));

		buffer[destIdx .. destIdx + piece.length] = piece[];
		destIdx += piece.length;
	}

	auto mb = _getData(t, 0);
	_ensureSize(t, mb, destIdx);
	_setLength(t, destIdx);
	src = _stringBufferAsUtf32(t, 0); // has been invalidated!
	src[0 .. destIdx] = buffer[0 .. destIdx];

	dup(t, 0);
	return 1;
}

uword _repeat(CrocThread* t)
{
	_getData(t);
	checkIntParam(t, 1);

	dup(t, 0);
	pushNull(t);
	methodCall(t, -2, "dup", 1);
	pushNull(t);
	dup(t, 1);
	return methodCall(t, -3, "repeat!", 1);
}

uword _commonNonInPlace(char[] method)(CrocThread* t)
{
	_getData(t);

	dup(t, 0);
	pushNull(t);
	methodCall(t, -2, "dup", 1);
	pushNull(t);
	return methodCall(t, -2, method, 1);
}

alias _commonNonInPlace!("reverse!") _reverse;
alias _commonNonInPlace!("strip!") _strip;
alias _commonNonInPlace!("lstrip!") _lstrip;
alias _commonNonInPlace!("rstrip!") _rstrip;

uword _replace(CrocThread* t)
{
	auto src = _stringBufferAsUtf32(t, 0);

	dchar[] tmp1, tmp2;

	scope(exit)
	{
		freeArray(t, tmp1);
		freeArray(t, tmp2);
	}

	auto from = _checkStringOrStringBuffer(t, 1, tmp1);
	auto to = _checkStringOrStringBuffer(t, 2, tmp2);

	auto ret = pushGlobal(t, "StringBuffer");
	pushNull(t);
	pushInt(t, src.length);
	rawCall(t, -3, 1);

	auto destmb = _getData(t, ret);
	auto dest = cast(dchar[])destmb.data;
	bool shouldCheckSize = from.length < to.length; // only have to grow if the 'to' string is bigger than the 'from' string
	uword destIdx = 0;

	foreach(piece; src.patterns(from, to))
	{
		if(shouldCheckSize && destIdx + piece.length > dest.length)
		{
			push(t, CrocValue(destmb));
			lenai(t, -1, dchar.sizeof * max(destIdx + piece.length, dest.length * 2));
			pop(t);
			dest = cast(dchar[])destmb.data;
		}

		dest[destIdx .. destIdx + piece.length] = piece[];
		destIdx += piece.length;
	}

	_setLength(t, destIdx, ret);
	return 1;
}

uword _format(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	auto mb = _getData(t);
	auto len = _getLength(t);

	uint sink(char[] data)
	{
		uword datalen = void;
		verifyUTF8(data, datalen);
		ulong totalLen = cast(uword)len + datalen;

		if(totalLen > uword.max)
			throwStdException(t, "RangeException", "Invalid size ({})", totalLen);

		_ensureSize(t, mb, cast(uword)totalLen);
		_setLength(t, cast(uword)totalLen);
		auto oldLen = len;
		len = cast(uword)totalLen;

		UTF8ToUTF32(data, (cast(dchar[])mb.data)[cast(uword)oldLen .. cast(uword)totalLen]);
		return data.length;
	}

	formatImpl(t, numParams, &sink);

	dup(t, 0);
	return 1;
}

uword _formatln(CrocThread* t)
{
	_format(t);
	pushNull(t);
	pushChar(t, '\n');
	methodCall(t, -3, "append", 1);
	return 1;
}

uword _opSerialize(CrocThread* t)
{
	auto mb = _getData(t);

	// don't know if this is possible, but can't hurt to check
	if(!mb.ownData)
		throwStdException(t, "ValueException", "Attempting to serialize a string buffer which does not own its data");

	dup(t, 2);
	pushNull(t);
	getExtraVal(t, 0, Length);
	rawCall(t, -3, 0);

	dup(t, 2);
	pushNull(t);
	getExtraVal(t, 0, Data);
	rawCall(t, -3, 0);

	return 0;
}

uword _opDeserialize(CrocThread* t)
{
	checkInstParam(t, 0, "StringBuffer");

	dup(t, 2);
	pushNull(t);
	rawCall(t, -2, 1);

	if(!isInt(t, -1))
		throwStdException(t, "TypeException", "Invalid data encountered when deserializing - expected 'int' but found '{}' instead", type(t, -1));

	setExtraVal(t, 0, Length);

	dup(t, 2);
	pushNull(t);
	rawCall(t, -2, 1);

	if(!isMemblock(t, -1))
		throwStdException(t, "TypeException", "Invalid data encountered when deserializing - expected 'memblock' but found '{}' instead", type(t, -1));

	setExtraVal(t, 0, Data);

	return 0;
}

version(CrocBuiltinDocs)
{
	const Docs _classDocs =
	{kind: "class", name: "StringBuffer",
	extra: [Extra("protection", "global")],
	docs:
	`Croc's strings are immutable. While this makes dealing with strings much easier in most cases, it also
	introduces inefficiency for some operations, such as building up strings piecewise or performing text modification
	on large string data. \tt{StringBuffer} is a mutable string class that makes these sorts of things possible.
	\tt{StringBuffer} is optimized for building up strings dynamically, and will overallocate space when the buffer
	size is increased. It can also preallocate space so that operations on the buffer will not allocate memory. This
	is particularly useful in situations where memory allocations or GC cycles need to be kept to a minimum.

	A note on some of the methods: as per the standard library convention, there are some methods which have two
	versions, one of which operates in-place, and the other which returns a new object and leaves the original unchanged.
	In this case, the in-place version's name has an exclamation point appended, while the non-modifying version has none.
	For example, \link{reverse} will create a new \tt{StringBuffer}, whereas \link{reverse!} will modify the given one
	in place.`};

	const Docs[] _methodDocs =
	[
		{kind: "function", name: "constructor",
		params: [Param("init", "string|int", "null")],
		docs:
		`If you pass nothing to the constructor, the \tt{StringBuffer} will be empty. If you pass a string, the \tt{StringBuffer}
		will be filled with that string's data. If you pass an integer, it means how much space, in characters, should be
		preallocated in the buffer. However, the length of the \tt{StringBuffer} will still be 0; it's just that no memory will
		have to be allocated until you put at least \tt{init} characters into it.

		\throws[exceptions.RangeException] if \tt{init} is a negative integer or is an integer so large that the memory cannot
		be allocated.`},

		{kind: "function", name: "dup",
		docs:
		`Creates a new \tt{StringBuffer} that is a duplicate of this one. Its length and contents will be identical.

		\returns the new \tt{StringBuffer}.`},

		{kind: "function", name: "toString",
		params: [Param("lo", "int", "0"), Param("hi", "int", "#this")],
		docs:
		`Converts this \tt{StringBuffer} to a string. You can optionally slice out only a part of the buffer to turn into a
		string with the \tt{lo} and \tt{hi} parameters, which work like regular slice indices.

		\throws[exceptions.BoundsException] if the slice boundaries are invalid.`},

		{kind: "function", name: "opEquals",
		params: [Param("other", "string|StringBuffer")],
		docs:
		`Compares this \tt{StringBuffer} to a \tt{string} or other \tt{StringBuffer} for equality. Works the same as string equality.`},

		{kind: "function", name: "opCmp",
		params: [Param("other", "string|StringBuffer")],
		docs:
		`Compares this \tt{StringBuffer} to a \tt{string} or other \tt{StringBuffer}. Works the same as string comparison.`},

		{kind: "function", name: "opLength",
		docs:
		`Gets the length of this \tt{StringBuffer} in characters. Note that this is just the number of characters currently
		in use; if you preallocate space either with the constructor or by setting the length longer and shorter, the true
		size of the underlying buffer will not be reported.`},

		{kind: "function", name: "opLengthAssign",
		params: [Param("len", "int")],
		docs:
		`Sets the length of this \tt{StringBuffer}. If you increase the length, the new characters will be filled with U+00FFFF.
		If you decrease the length, characters will be truncated. Note that when you increase the length of the buffer, memory
		may be overallocated to avoid allocations on every size increase. When you decrease the length of the buffer, that memory
		is not deallocated, so you can reserve memory for a \tt{StringBuffer} by setting its length to the size you need and then
		setting it back to 0, like so:

\code
local s = StringBuffer()
#s = 1000
#s = 0
// now s can hold up to 1000 characters before it will have to reallocate its memory.
\endcode

		\throws[exceptions.RangeException] if \tt{len} is negative or is so large that the memory cannot be allocated.`},

		{kind: "function", name: "opIndex",
		params: [Param("idx", "int")],
		docs:
		`Gets the character at the given index.

		\throws[exceptions.BoundsException] if the index is invalid.`},

		{kind: "function", name: "opIndexAssign",
		params: [Param("idx", "int"), Param("c", "char")],
		docs:
		`Sets the character at the given index to the given character.

		\throws[exceptions.BoundsException] if the index is invalid.`},

		{kind: "function", name: "opCat",
		params: [Param("o")],
		docs:
		`Concatenates this \tt{StringBuffer} with another value and returns a \b{new} \tt{StringBuffer} containing the concatenation.
		If you want to instead add data to the beginning or end of a \tt{StringBuffer}, use the \link{opCatAssign} or \link{insert} methods.

		Any type can be concatenated with a \tt{StringBuffer}; if it isn't a string, character, or another \tt{StringBuffer}, it will have
		its \tt{toString} method called on it and the result will be concatenated.`},

		{kind: "function", name: "opCat_r", docs: "ditto", params: [Param("o")]},

		{kind: "function", name: "opCatAssign",
		params: [Param("vararg", "vararg")],
		docs:
		`\b{Also aliased to \tt{append}.}

		This is the main way to add data into a \tt{StringBuffer} when building up strings piecewise. Each parameter will have \tt{toString}
		called on it (unless it's a \tt{StringBuffer} itself, so no \tt{toString} is necessary), and the resulting string will be
		appended to the end of this \tt{StringBuffer}'s data.

		You can either use the \tt{~=} and \tt{~} operators to use this method, or you can call the \tt{append} method; both are aliased to
		the same method and do the same thing. Thus, \tt{"s ~= a ~ b ~ c"} is functionally identical to \tt{"s.append(a, b, c)"} and
		vice versa.

		\throws[exceptions.RangeException] if the size of the buffer grows so large that the memory cannot be allocated.`},

		{kind: "function", name: "opSlice",
		params: [Param("lo", "int", "0"), Param("hi", "int", "#this")],
		docs:
		`Slices data out of this \tt{StringBuffer} and creates a new \tt{StringBuffer} with that slice of data. Works just like string
		slicing.`},

		{kind: "function", name: "fill",
		params: [Param("v", "char|string|array|function|StringBuffer")],
		docs:
		`A pretty flexible way to fill a \tt{StringBuffer} with some data. This only modifies existing data; the buffer's length is
		never changed.

		If you pass a character, every character in the buffer will be set to that character.

		If you pass a string, it must be the same length as the buffer, and the string's data is copied into the buffer.

		If you pass an array, it must be the same length of the buffer and all its elements must be characters. Those characters
		will be copied into the buffer.

		If you pass a \tt{StringBuffer}, it must be the same length as the buffer and its data will be copied into this buffer.

		If you pass a function, it must take an integer and return a character. It will be called on each location in the buffer,
		and the resulting characters will be put into the buffer.`},

		{kind: "function", name: "fillRange",
		params: [Param("lo", "int", "0"), Param("hi", "int", "#this"), Param("v", "char|string|array|function|StringBuffer")],
		docs:
		`\b{Also aliased to \tt{opSliceAssign}.}

		Works just like \link{fill}, except it works on just a subrange of the buffer. The \tt{lo} and \tt{hi} params work just like slice
		indices - low inclusive, high noninclusive, negative from the end.

		You can either call this method directly, or you can use slice-assignment; they are aliased to the same method and do
		the same thing. Thus, \tt{"s.fillRange(x, y, z)"} is functionally identical to \tt{"s[x .. y] = z"} and vice versa.`},

		{kind: "function", name: "insert",
		params: [Param("idx", "int"), Param("val")],
		docs:
		`Inserts the string representation of \tt{val} before the character indexed by \tt{idx}. \tt{idx} can be negative, which means an
		index from the end of the buffer. It can also be the same as the length of this \tt{StringBuffer}, in which case the behavior
		is identical to appending.`},

		{kind: "function", name: "remove",
		params: [Param("lo", "int"), Param("hi", "int", "lo + 1")],
		docs:
		`Removes characters from a \tt{StringBuffer}, shifting the data after them (if any) down. The indices work like slice indices.
		The \tt{hi} index defaults to one more than the \tt{lo} index, so you can remove a single character by just passing the \tt{lo} index.`},

		{kind: "function", name: "find",
		params: [Param("sub", "string|char|StringBuffer"), Param("start", "int", "0")],
		docs:
		`Searches for an occurence of \tt{sub} in \tt{this}. \tt{sub} can be a string, a single character, or another \tt{StringBuffer}.
		The search starts from \tt{start} (which defaults to the first character) and goes right. If \tt{sub} is found, this function returns
		the integer index of the occurrence in the string, with 0 meaning the first character. Otherwise, if \tt{sub} cannot be found, \tt{#this}
		is returned.

		If \tt{start < 0} it is treated as an index from the end of \tt{this}. If \tt{start >= #this} then this function simply returns
		\tt{#this} (that is, it didn't find anything).

		\throws[exceptions.BoundsException] if \tt{start} is negative and out-of-bounds (that is, \tt{abs(start) > #this}).`},

		{kind: "function", name: "rfind",
		params: [Param("sub", "string|char|StringBuffer"), Param("start", "int", "#this")],
		docs:
		`Reverse find. Works similarly to \tt{find}, but the search starts with the character at \tt{start - 1} (which defaults to
		the last character) and goes \em{left}. \tt{start} is not included in the search so you can use the result of this function
		as the \tt{start} parameter to successive calls. If \tt{sub} is found, this function returns the integer index of the occurrence
		in the string, with 0 meaning the first character. Otherwise, if \tt{sub} cannot be found, \tt{#this} is returned.

		If \tt{start < 0} it is treated as an index from the end of \tt{this}.

		\throws[exceptions.BoundsException] if \tt{start >= #this} or if \tt{start} is negative an out-of-bounds (that is, \tt{abs(start > #this}).`},

		{kind: "function", name: "startsWith",
		params: [Param("other", "string|StringBuffer")],
		docs:
		`\returns a bool of whether or not \tt{this} starts with the substring \tt{other}. This is case-sensitive.`},

		{kind: "function", name: "endsWith",
		params: [Param("other", "string|StringBuffer")],
		docs:
		`\returns a bool of whether or not \tt{this} ends with the substring \tt{other}. This is case-sensitive.`},

		{kind: "function", name: "split",
		params: [Param("delim", "string|StringBuffer")],
		docs:
		`Splits \tt{this} into pieces (each piece being a new \tt{StringBuffer}) and returns an array of the split pieces.

		\param[delim] specifies a delimiting string where \tt{this} will be split.`},

		{kind: "function", name: "splitWS",
		docs:
		`Similar to \link{split}, but splits at whitespace (spaces, tabs, newlines etc.), and all the whitespace is stripped from the split
		pieces.`},

		{kind: "function", name: "vsplit",
		params: [Param("delim", "string|StringBuffer", "null")],
		docs:
		`Similar to \link{split}, but instead of returning an array, returns the split pieces as multiple return values. If \tt{this} splits into more
		than 20 pieces, an error will be thrown (as returning many values can be a memory problem). Otherwise the behavior is identical to \link{split}.`},

		{kind: "function", name: "vsplitWS",
		docs:
		`Similar to \link{vsplit} in that it returns multiple values, but works like \link{splitWS} instead. If \tt{this} splits into more than 20 pieces,
		an error will be thrown (as returning many values can be a memory problem). Otherwise the behavior is identical to \link{splitWS}.`},

		{kind: "function", name: "splitLines",
		docs:
		`This will split \tt{this} at any newline characters (\tt{'\\n'}, \tt{'\\r'}, or \tt{'\\r\\n'}). Other whitespace is preserved, and empty
		lines are preserved. This returns an array of \tt{StringBuffer}s, each of which holds one line of text.`},

		{kind: "function", name: "vsplitLines",
		docs:
		`Similar to \link{splitLines}, but instead of returning an array, returns the split lines as multiple return values. If \tt{this}
		splits into more than 20 lines, an error will be thrown. Otherwise the behavior is identical to \link{splitLines}.`},

		{kind: "function", name: "repeat",
		params: [Param("n", "int")],
		docs:
		`\returns a new \tt{StringBuffer} which is the concatenation of \tt{n} instances of \tt{this}. If \tt{n == 0}, returns an empty \tt{StringBuffer}.

		\throws[exceptions.RangeException] if \tt{n < 0}.`},

		{kind: "function", name: "s.reverse",
		docs:
		`Returns a new \tt{StringBuffer} whose contents are the reversal of \tt{this}.`},

		{kind: "function", name: "strip",
		docs:
		`Returns a new \tt{StringBuffer} whose contents are the same as \tt{this} but with any whitespace stripped from the beginning and end.`},

		{kind: "function", name: "lstrip",
		docs:
		`Returns a new \tt{StringBuffer} whose contents are the same as \tt{this} but with any whitespace stripped from just the beginning of the string.`},

		{kind: "function", name: "s.rstrip",
		docs:
		`Returns a new \tt{StringBuffer} whose contents are the same as \tt{this} but with any whitespace stripped from just the end of the string.`},

		{kind: "function", name: "s.replace",
		params: [Param("from", "string|StringBuffer"), Param("to", "string|StringBuffer")],
		docs:
		`Returns a new \tt{StringBuffer} where any occurrences in \tt{s} of the string \tt{from} are replaced with the string \tt{to}.`},

		{kind: "function", name: "repeat!",
		params: [Param("n", "int")],
		docs:
		`These are all \em{in-place} versions of their corresponding methods. They work identically, except instead of returning a new \tt{StringBuffer}
		object leaving \tt{this} unchanged, they replace the contents of \tt{this} with their output.`},

		{kind: "function", name: "reverse!", docs: "ditto"},
		{kind: "function", name: "strip!", docs: "ditto"},
		{kind: "function", name: "lstrip!", docs: "ditto"},
		{kind: "function", name: "rstrip!", docs: "ditto"},
		{kind: "function", name: "replace!", params: [Param("from", "string|StringBuffer"), Param("to", "string|StringBuffer")], docs: "ditto"},

		{kind: "function", name: "format",
		params: [Param("fmt", "string"), Param("vararg", "vararg")],
		docs:
		`Just like \link{string.format}, except the results are appended directly to the end of this \tt{StringBuffer} without needing a
		string temporary.`},

		{kind: "function", name: "formatln",
		params: [Param("fmt", "string"), Param("vararg", "vararg")],
		docs:
		`Same as \tt{format}, but also appends the \tt{\\n} character after appending the formatted string.`},

		{kind: "function", name: "opApply",
		params: [Param("reverse", "string", "null")],
		docs:
		`Lets you iterate over \tt{StringBuffer}s with foreach loops just like strings. You can iterate in reverse, just like strings,
		by passing the string \tt{"reverse"} as the second value in the foreach container:

\code
local sb = StringBuffer("hello")
foreach(i, c; sb) { }
foreach(i, c; sb, "reverse") { } // goes backwards
\endcode
		`},

		{kind: "function", name: "opSerialize",
		docs:
		`Overloads to allow instances of \tt{StringBuffer} to be serialized by the \tt{serialization} library.`},

		{kind: "function", name: "opDeserialize", docs: "ditto"},
	];
}