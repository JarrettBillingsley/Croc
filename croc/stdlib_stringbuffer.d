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
import tango.text.convert.Utf;

alias tango.text.convert.Utf.toString32 Utf_toString32;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_format;
import croc.stdlib_utils;
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

enum
{
	Data,
	Length,

	NumFields
}

CrocMemblock* _getThis(CrocThread* t)
{
	checkInstParam(t, 0, "StringBuffer");
	getExtraVal(t, 0, Data);

	if(!isMemblock(t, -1))
		throwStdException(t, "ValueException", "Attempting to call a method on an uninitialized StringBuffer");

	auto ret = getMemblock(t, -1);
	pop(t);
	return ret;
}

CrocMemblock* _getData(CrocThread* t, word idx)
{
	getExtraVal(t, idx, Data);

	if(!isMemblock(t, -1))
		throwStdException(t, "ValueException", "Attempting to operate on an uninitialized StringBuffer");

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
		uint ate = 0;
		Utf_toString32(data, cast(dchar[])mb.data, &ate);
		_setLength(t, length);
	}
	else
		_setLength(t, 0);

	setExtraVal(t, 0, Data);
	return 0;
}

uword _toString(CrocThread* t)
{
	auto mb = _getThis(t);
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
	auto mb = _getThis(t);
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
	auto mb = _getThis(t);
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
	_getThis(t);
	getExtraVal(t, 0, Length);
	return 1;
}

uword _opLengthAssign(CrocThread* t)
{
	auto mb = _getThis(t);
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
	auto mb = _getThis(t);
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
	auto mb = _getThis(t);
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
	auto mb = _getThis(t);
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
	auto mb = _getThis(t);
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
		uint ate = 0;
		Utf_toString32(getString(t, 1), dest, &ate);
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
		uint ate = 0;
		Utf_toString32(s, dest, &ate);
		pop(t);
	}

	return 1;
}

uword _opCat_r(CrocThread* t)
{
	auto mb = _getThis(t);
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
		uint ate = 0;
		Utf_toString32(getString(t, 1), dest, &ate);
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
		uint ate = 0;
		Utf_toString32(s, dest, &ate);
		pop(t);
	}

	return 1;
}

uword _opCatAssign(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	auto mb = _getThis(t);
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
			uint ate = 0;
			Utf_toString32(getString(t, i), dest, &ate);
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
			uint ate = 0;
			Utf_toString32(getString(t, -1), dest, &ate);
			pop(t);
		}
	}

	// we're returning 'this' in case people want to chain 'append's, since this method is also append.
	dup(t, 0);
	return 1;
}

uword _iterator(CrocThread* t)
{
	auto mb = _getThis(t);
	auto index = checkIntParam(t, 1) + 1;

	if(index >= _getLength(t))
		return 0;

	pushInt(t, index);
	pushChar(t, (cast(dchar[])mb.data)[cast(uword)index]);

	return 2;
}

uword _iteratorReverse(CrocThread* t)
{
	auto mb = _getThis(t);
	auto index = checkIntParam(t, 1) - 1;

	if(index < 0)
		return 0;

	pushInt(t, index);
	pushChar(t, (cast(dchar[])mb.data)[cast(uword)index]);

	return 2;
}

uword _opApply(CrocThread* t)
{
	_getThis(t);

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

		uint ate = 0;
		Utf_toString32(getString(t, filler), (cast(dchar[])mb.data)[lo .. hi], &ate);
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
	auto mb = _getThis(t);
	checkAnyParam(t, 1);
	fillImpl(t, mb, 1, 0, _getLength(t));
	dup(t, 0);
	return 1;
}

uword _fillRange(CrocThread* t)
{
	auto mb = _getThis(t);
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
	auto mb = _getThis(t);
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
			uint ate = 0;
			Utf_toString32(str, tmp, &ate);
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
				auto data = cast(dchar[])_getData(t, 0).data;
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
			uint ate = 0;
			Utf_toString32(str, tmp, &ate);
		}

		pop(t);
	}

	dup(t, 0);
	return 1;
}

uword _remove(CrocThread* t)
{
	auto mb = _getThis(t);
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

uword _format(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	auto mb = _getThis(t);
	auto len = _getLength(t);

	uint sink(char[] data)
	{
		ulong totalLen = cast(uword)len + verify(data);

		if(totalLen > uword.max)
			throwStdException(t, "RangeException", "Invalid size ({})", totalLen);

		_ensureSize(t, mb, cast(uword)totalLen);
		_setLength(t, cast(uword)totalLen);
		auto oldLen = len;
		len = cast(uword)totalLen;

		uint ate = 0;
		Utf_toString32(data, (cast(dchar[])mb.data)[cast(uword)oldLen .. cast(uword)totalLen], &ate);
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
	auto mb = _getThis(t);

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
	{kind: "class", name: "StringBuffer", docs:
	`Croc's strings are immutable. While this makes dealing with strings much easier in most cases, it also
	introduces inefficiency for some operations, such as building up strings piecewise or performing text modification
	on large string data. \tt{StringBuffer} is a mutable string class that makes these sorts of things possible.
	\tt{StringBuffer} is optimized for building up strings dynamically, and will overallocate space when the buffer
	size is increased. It can also preallocate space so that operations on the buffer will not allocate memory. This
	is particularly useful in situations where memory allocations or GC cycles need to be kept to a minimum.`,
	extra: [Extra("protection", "global")]};

	const Docs[] _methodDocs =
	[
		{kind: "function", name: "constructor", docs:
		`If you pass nothing to the constructor, the \tt{StringBuffer} will be empty. If you pass a string, the \tt{StringBuffer}
		will be filled with that string's data. If you pass an integer, it means how much space, in characters, should be
		preallocated in the buffer. However, the length of the \tt{StringBuffer} will still be 0; it's just that no memory will
		have to be allocated until you put at least \tt{init} characters into it.

		\throws[exceptions.RangeException] if \tt{init} is a negative integer or is an integer so large that the memory cannot
		be allocated.`,
		params: [Param("init", "string|int", "null")]},

		{kind: "function", name: "toString", docs:
		`Converts this \tt{StringBuffer} to a string. You can optionally slice out only a part of the buffer to turn into a
		string with the \tt{lo} and \tt{hi} parameters, which work like regular slice indices.

		\throws[exceptions.BoundsException] if the slice boundaries are invalid.`,
		params: [Param("lo", "int", "0"), Param("hi", "int", "#this")]},

		{kind: "function", name: "opEquals", docs:
		`Compares this \tt{StringBuffer} to a \tt{string} or other \tt{StringBuffer} for equality. Works the same as string equality.`,
		params: [Param("other", "string|StringBuffer")]},

		{kind: "function", name: "opCmp", docs:
		`Compares this \tt{StringBuffer} to a \tt{string} or other \tt{StringBuffer}. Works the same as string comparison.`,
		params: [Param("other", "string|StringBuffer")]},

		{kind: "function", name: "opLength", docs:
		`Gets the length of this \tt{StringBuffer} in characters. Note that this is just the number of characters currently
		in use; if you preallocate space either with the constructor or by setting the length longer and shorter, the true
		size of the underlying buffer will not be reported.`},

		{kind: "function", name: "opLengthAssign", docs:
		`Sets the length of this \tt{StringBuffer}. If you increase the length, the new characters will be filled with U+0FFFF.
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

		\throws[exceptions.RangeException] if \tt{len} is negative or is so large that the memory cannot be allocated.`,
		params: [Param("len", "int")]},

		{kind: "function", name: "opIndex", docs:
		`Gets the character at the given index.

		\throws[exceptions.BoundsException] if the index is invalid.`,
		params: [Param("idx", "int")]},

		{kind: "function", name: "opIndexAssign", docs:
		`Sets the character at the given index to the given character.

		\throws[exceptions.BoundsException] if the index is invalid.`,
		params: [Param("idx", "int"), Param("c", "char")]},

		{kind: "function", name: "opCat", docs:
		`Concatenates this \tt{StringBuffer} with another value and returns a \b{new} \tt{StringBuffer} containing the concatenation.
		If you want to instead add data to the beginning or end of a \tt{StringBuffer}, use the \link{opCatAssign} or \link{insert} methods.

		Any type can be concatenated with a \tt{StringBuffer}; if it isn't a string, character, or another \tt{StringBuffer}, it will have
		its \tt{toString} method called on it and the result will be concatenated.`,
		params: [Param("o")]},

		{kind: "function", name: "opCat_r", docs:
		"ditto",
		params: [Param("o")]},

		{kind: "function", name: "opCatAssign", docs:
		`\b{Also aliased to \tt{append}.}

		This is the main way to add data into a \tt{StringBuffer} when building up strings piecewise. Each parameter will have \tt{toString}
		called on it (unless it's a \tt{StringBuffer} itself, so no \tt{toString} is necessary), and the resulting string will be
		appended to the end of this \tt{StringBuffer}'s data.

		You can either use the \tt{~=} and \tt{~} operators to use this method, or you can call the \tt{append} method; both are aliased to
		the same method and do the same thing. Thus, \tt{"s ~= a ~ b ~ c"} is functionally identical to \tt{"s.append(a, b, c)"} and
		vice versa.

		\throws[exceptions.RangeException] if the size of the buffer grows so large that the memory cannot be allocated.`,
		params: [Param("vararg", "vararg")]},

		{kind: "function", name: "opSlice", docs:
		`Slices data out of this \tt{StringBuffer} and creates a new \tt{StringBuffer} with that slice of data. Works just like string
		slicing.`,
		params: [Param("lo", "int", "0"), Param("hi", "int", "#this")]},

		{kind: "function", name: "fill", docs:
		`A pretty flexible way to fill a \tt{StringBuffer} with some data. This only modifies existing data; the buffer's length is
		never changed.

		If you pass a character, every character in the buffer will be set to that character.

		If you pass a string, it must be the same length as the buffer, and the string's data is copied into the buffer.

		If you pass an array, it must be the same length of the buffer and all its elements must be characters. Those characters
		will be copied into the buffer.

		If you pass a \tt{StringBuffer}, it must be the same length as the buffer and its data will be copied into this buffer.

		If you pass a function, it must take an integer and return a character. It will be called on each location in the buffer,
		and the resulting characters will be put into the buffer.`,
		params: [Param("v", "char|string|array|function|StringBuffer")]},

		{kind: "function", name: "fillRange", docs:
		`\b{Also aliased to \tt{opSliceAssign}.}

		Works just like \link{fill}, except it works on just a subrange of the buffer. The \tt{lo} and \tt{hi} params work just like slice
		indices - low inclusive, high noninclusive, negative from the end.

		You can either call this method directly, or you can use slice-assignment; they are aliased to the same method and do
		the same thing. Thus, \tt{"s.fillRange(x, y, z)"} is functionally identical to \tt{"s[x .. y] = z"} and vice versa.`,
		params: [Param("lo", "int", "0"), Param("hi", "int", "#this"), Param("v", "char|string|array|function|StringBuffer")]},

		{kind: "function", name: "insert", docs:
		`Inserts the string representation of \tt{val} before the character indexed by \tt{idx}. \tt{idx} can be negative, which means an
		index from the end of the buffer. It can also be the same as the length of this \tt{StringBuffer}, in which case the behavior
		is identical to appending.`,
		params: [Param("idx", "int"), Param("val")]},

		{kind: "function", name: "remove", docs:
		`Removes characters from a \tt{StringBuffer}, shifting the data after them (if any) down. The indices work like slice indices.
		The \tt{hi} index defaults to one more than the \tt{lo} index, so you can remove a single character by just passing the \tt{lo} index.`,
		params: [Param("lo", "int"), Param("hi", "int", "lo + 1")]},

		{kind: "function", name: "format", docs:
		`Just like the \tt{format} function in the baselib, except the results are appended directly to the end of this \tt{StringBuffer}
		without needing a string temporary.`,
		params: [Param("fmt", "string"), Param("vararg", "vararg")]},

		{kind: "function", name: "formatln", docs:
		`Same as \tt{format}, but also appends the \tt{\\n} character after appending the formatted string.`,
		params: [Param("fmt", "string"), Param("vararg", "vararg")]},

		{kind: "function", name: "opApply", docs:
		`Lets you iterate over \tt{StringBuffer}s with foreach loops just like strings. You can iterate in reverse, just like strings,
		by passing the string \tt{"reverse"} as the second value in the foreach container:

\code
local sb = StringBuffer("hello")
foreach(i, c; sb) { }
foreach(i, c; sb, "reverse") { } // goes backwards
\endcode
		`,
		params: [Param("reverse", "string", "null")]},

		{kind: "function", name: "opSerialize", docs:
		`Overloads to allow instances of \tt{StringBuffer} to be serialized by the \tt{serialization} library.`},

		{kind: "function", name: "opDeserialize", docs:
		"ditto"},
	];
}