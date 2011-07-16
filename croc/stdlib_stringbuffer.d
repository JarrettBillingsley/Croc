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
import Utf = tango.text.convert.Utf;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_format;
import croc.types;
import croc.utils;

struct StringBufferObj
{
static:
	private enum
	{
		Data,
		Length,

		NumFields
	}

	void init(CrocThread* t)
	{
		CreateClass(t, "StringBuffer", (CreateClass* c)
		{
			c.allocator("allocator", &BasicClassAllocator!(NumFields, 0));

			c.method("constructor",    1, &constructor);
			c.method("toString",       2, &toString);

			c.method("opEquals",       1, &opEquals);
			c.method("opCmp",          1, &opCmp);
			c.method("opLength",       0, &opLength);
			c.method("opLengthAssign", 1, &opLengthAssign);
			c.method("opIndex",        1, &opIndex);
			c.method("opIndexAssign",  2, &opIndexAssign);
			c.method("opCat",          1, &opCat);
			c.method("opCat_r",        1, &opCat_r);
			c.method("opCatAssign",       &opCatAssign);
			c.method("opSlice",        2, &opSlice);

			c.method("fill",           1, &fill);
			c.method("fillRange",      3, &fillRange);
			c.method("insert",         2, &sb_insert);
			c.method("remove",         2, &remove);

			c.method("format",            &format);
			c.method("formatln",          &formatln);

				newFunction(t, &iterator, "iterator");
				newFunction(t, &iteratorReverse, "iteratorReverse");
			c.method("opApply", 1, &opApply, 2);

			c.method("opSerialize",   &opSerialize);
			c.method("opDeserialize", &opDeserialize);
		});

		field(t, -1, "fillRange");
		fielda(t, -2, "opSliceAssign");

		field(t, -1, "opCatAssign");
		fielda(t, -2, "append");

		newGlobal(t, "StringBuffer");
	}

	private CrocMemblock* getThis(CrocThread* t)
	{
		checkInstParam(t, 0, "StringBuffer");
		getExtraVal(t, 0, Data);

		if(!isMemblock(t, -1))
			throwException(t, "Attempting to call a method on an uninitialized StringBuffer");

		auto ret = getMemblock(t, -1);
		pop(t);
		return ret;
	}

	private CrocMemblock* getData(CrocThread* t, word idx)
	{
		getExtraVal(t, idx, Data);

		if(!isMemblock(t, -1))
			throwException(t, "Attempting to operate on an uninitialized StringBuffer");

		auto ret = getMemblock(t, -1);
		pop(t);
		return ret;
	}

	private uword getLength(CrocThread* t, word idx = 0)
	{
		getExtraVal(t, idx, Length);
		auto ret = cast(uword)getInt(t, -1);
		pop(t);
		return ret;
	}

	private void setLength(CrocThread* t, uword l, word idx = 0)
	{
		idx = absIndex(t, idx);
		pushInt(t, cast(crocint)l);
		setExtraVal(t, idx, Length);
	}

	void ensureSize(CrocThread* t, CrocMemblock* mb, uword size)
	{
		if(mb.itemLength == 0)
		{
			push(t, CrocValue(mb));
			lenai(t, -1, size);
			pop(t);
		}
		else if(size > mb.itemLength)
		{
			auto l = mb.itemLength;

			while(size > l)
			{
				if(l & (1 << ((uword.sizeof * 8) - 1)))
					throwException(t, "StringBuffer too big ({} elements)", size);
				l <<= 1;
			}

			push(t, CrocValue(mb));
			lenai(t, -1, l);
			pop(t);
		}
	}

	uword constructor(CrocThread* t)
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
					throwException(t, "Invalid length: {}", l);

				length = cast(uword)l;
			}
		}
		else
		{
			data = "";
			length = 0;
		}

		newMemblock(t, "u32", length);

		if(data.length > 0)
		{
			auto mb = getMemblock(t, -1);
			uint ate = 0;
			Utf.toString32(data, cast(dchar[])mb.data, &ate);
			setLength(t, length);
		}
		else
			setLength(t, 0);

		setExtraVal(t, 0, Data);
		return 0;
	}

	uword toString(CrocThread* t)
	{
		auto mb = getThis(t);
		auto len = getLength(t);
		auto lo = optIntParam(t, 1, 0);
		auto hi = optIntParam(t, 2, len);
		
		if(lo < 0)
			lo += len;

		if(hi < 0)
			hi += len;
			
		if(lo < 0 || lo > hi || hi > len)
			throwException(t, "Invalid slice indices: {} .. {} (buffer length: {})", lo, hi, len);

		pushFormat(t, "{}", (cast(dchar[])mb.data)[cast(uword)lo .. cast(uword)hi]);
		return 1;
	}

	uword opEquals(CrocThread* t)
	{
		auto mb = getThis(t);
		auto len = getLength(t);
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
			auto otherLen = getLength(t, 1);

			if(len != otherLen)
				pushBool(t, false);
			else
			{
				auto other = getData(t, 1);

				auto a = (cast(dchar[])mb.data)[0 .. len];
				auto b = (cast(dchar[])other.data)[0 .. a.length];
				pushBool(t, a == b);
			}
		}
		else
			paramTypeError(t, 1, "string|StringBuffer");

		return 1;
	}

	uword opCmp(CrocThread* t)
	{
		auto mb = getThis(t);
		auto len = getLength(t);
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
			auto otherLen = getLength(t, 1);
			auto l = min(len, otherLen);
			auto other = getData(t, 1);
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

	uword opLength(CrocThread* t)
	{
		getThis(t);
		getExtraVal(t, 0, Length);
		return 1;
	}

	uword opLengthAssign(CrocThread* t)
	{
		auto mb = getThis(t);
		auto newLen = checkIntParam(t, 1);

		if(newLen < 0 || newLen > uword.max)
			throwException(t, "Invalid length: {}", newLen);

		auto oldLen = getLength(t);

		if(cast(uword)newLen < oldLen)
			setLength(t, cast(uword)newLen);
		else if(cast(uword)newLen > oldLen)
		{
			ensureSize(t, mb, cast(uword)newLen);
			setLength(t, cast(uword)newLen);
			(cast(dchar[])mb.data)[oldLen .. cast(uword)newLen] = dchar.init;
		}

		return 0;
	}

	uword opIndex(CrocThread* t)
	{
		auto mb = getThis(t);
		auto len = getLength(t);
		auto index = checkIntParam(t, 1);

		if(index < 0)
			index += len;

		if(index < 0 || index >= len)
			throwException(t, "Invalid index: {} (buffer length: {})", index, len);

		pushChar(t, (cast(dchar[])mb.data)[cast(uword)index]);
		return 1;
	}

	uword opIndexAssign(CrocThread* t)
	{
		auto mb = getThis(t);
		auto len = getLength(t);
		auto index = checkIntParam(t, 1);
		auto ch = checkCharParam(t, 2);

		if(index < 0)
			index += len;

		if(index < 0 || index >= len)
			throwException(t, "Invalid index: {} (buffer length: {})", index, len);

		(cast(dchar[])mb.data)[cast(uword)index] = ch;
		return 0;
	}

	uword opSlice(CrocThread* t)
	{
		auto mb = getThis(t);
		auto len = getLength(t);
		auto lo = optIntParam(t, 1, 0);
		auto hi = optIntParam(t, 2, len);

		if(lo < 0)
			lo += len;

		if(hi < 0)
			hi += len;

		if(lo < 0 || lo > hi || hi > len)
			throwException(t, "Invalid slice indices: {} .. {} (buffer length: {})", lo, hi, len);

		auto newStr = (cast(dchar[])mb.data)[cast(uword)lo .. cast(uword)hi];
		
		pushGlobal(t, "StringBuffer");
		pushNull(t);
		pushInt(t, newStr.length);
		rawCall(t, -3, 1);
		(cast(dchar[])getData(t, -1).data)[] = newStr[];
		setLength(t, newStr.length, -1);
		return 1;
	}

	uword opCat(CrocThread* t)
	{
		auto mb = getThis(t);
		auto len = getLength(t);
		auto src = cast(dchar[])mb.data;

		dchar[] makeObj(crocint addLen)
		{
			auto totalLen = len + addLen;

			if(totalLen > uword.max)
				throwException(t, "Result too big ({} elements)", totalLen);

			pushGlobal(t, "StringBuffer");
			pushNull(t);
			pushInt(t, totalLen);
			rawCall(t, -3, 1);
			setLength(t, cast(uword)totalLen, -1);
			auto ret = cast(dchar[])getData(t, -1).data;
			ret[0 .. len] = src[0 .. len];
			return ret[len .. $];
		}

		checkAnyParam(t, 1);
		pushGlobal(t, "StringBuffer");

		if(isString(t, 1))
		{
			auto dest = makeObj(.len(t, 1));
			uint ate = 0;
			Utf.toString32(getString(t, 1), dest, &ate);
		}
		else if(isChar(t, 1))
		{
			makeObj(1)[0] = getChar(t, 1);
		}
		else if(as(t, 1, -1))
		{
			auto otherLen = getLength(t, 1);
			makeObj(otherLen)[] = (cast(dchar[])getData(t, 1).data)[0 .. otherLen];
		}
		else
		{
			pushToString(t, 1);
			auto s = getString(t, -1);
			auto dest = makeObj(.len(t, -1));
			uint ate = 0;
			Utf.toString32(s, dest, &ate);
			pop(t);
		}

		return 1;
	}

	uword opCat_r(CrocThread* t)
	{
		auto mb = getThis(t);
		auto len = getLength(t);
		auto src = cast(dchar[])mb.data;

		dchar[] makeObj(crocint addLen)
		{
			auto totalLen = len + addLen;

			if(totalLen > uword.max)
				throwException(t, "Result too big ({} elements)", totalLen);

			pushGlobal(t, "StringBuffer");
			pushNull(t);
			pushInt(t, totalLen);
			rawCall(t, -3, 1);
			setLength(t, cast(uword)totalLen, -1);
			auto ret = cast(dchar[])getData(t, -1).data;
			ret[cast(uword)addLen .. $] = src[0 .. len];
			return ret[0 .. cast(uword)addLen];
		}

		checkAnyParam(t, 1);

		if(isString(t, 1))
		{
			auto dest = makeObj(.len(t, 1));
			uint ate = 0;
			Utf.toString32(getString(t, 1), dest, &ate);
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
			Utf.toString32(s, dest, &ate);
			pop(t);
		}

		return 1;
	}

	uword opCatAssign(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto mb = getThis(t);
		auto len = getLength(t);
		auto oldLen = len;

		dchar[] resize(crocint addLen)
		{
			auto totalLen = len + addLen;

			if(totalLen > uword.max)
				throwException(t, "Result too big ({} elements)", totalLen);

			ensureSize(t, mb, cast(uword)totalLen);
			setLength(t, cast(uword)totalLen);
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
				Utf.toString32(getString(t, i), dest, &ate);
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
					auto otherLen = getLength(t, i);
					resize(otherLen)[] = (cast(dchar[])getData(t, i).data)[0 .. otherLen];
				}
			}
			else
			{
				pushToString(t, i);
				auto dest = resize(.len(t, -1));
				uint ate = 0;
				Utf.toString32(getString(t, -1), dest, &ate);
				pop(t);
			}
		}

		// we're returning 'this' in case people want to chain 'append's, since this method is also append.
		dup(t, 0);
		return 1;
	}

	uword iterator(CrocThread* t)
	{
		auto mb = getThis(t);
		auto index = checkIntParam(t, 1) + 1;

		if(index >= getLength(t))
			return 0;

		pushInt(t, index);
		pushChar(t, (cast(dchar[])mb.data)[cast(uword)index]);

		return 2;
	}

	uword iteratorReverse(CrocThread* t)
	{
		auto mb = getThis(t);
		auto index = checkIntParam(t, 1) - 1;

		if(index < 0)
			return 0;

		pushInt(t, index);
		pushChar(t, (cast(dchar[])mb.data)[cast(uword)index]);

		return 2;
	}

	uword opApply(CrocThread* t)
	{
		getThis(t);

		if(optStringParam(t, 1, "") == "reverse")
		{
			getUpval(t, 1);
			dup(t, 0);
			pushInt(t, getLength(t));
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
			auto other = cast(dchar[])getData(t, filler).data;
			auto otherLen = getLength(t, filler);

			if(otherLen != (hi - lo))
				throwException(t, "Length of destination ({}) and length of source ({}) do not match", hi - lo, otherLen);

			(cast(dchar[])mb.data)[lo .. hi] = other[0 .. otherLen];
		}
		else if(isFunction(t, filler))
		{
			void callFunc(uword i)
			{
				dup(t, filler);
				pushNull(t);
				pushInt(t, i);
				rawCall(t, -3, 1);
			}

			auto data = (cast(dchar[])mb.data)[0 .. getLength(t)];

			for(uword i = lo; i < hi; i++)
			{
				callFunc(i);

				if(!isChar(t, -1))
				{
					pushTypeString(t, -1);
					throwException(t, "filler function expected to return a 'char', not '{}'", getString(t, -1));
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
				throwException(t, "Length of destination ({}) and length of source string ({}) do not match", hi - lo, cpLen);

			uint ate = 0;
			Utf.toString32(getString(t, filler), (cast(dchar[])mb.data)[lo .. hi], &ate);
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
					throwException(t, "array element {} expected to be 'char', not '{}'", ai, getString(t, -1));
				}

				data[ai] = getChar(t, -1);
				pop(t);
			}
		}
		else
			paramTypeError(t, filler, "char|string|array|function|StringBuffer");

		pop(t);
	}

	uword fill(CrocThread* t)
	{
		auto mb = getThis(t);
		checkAnyParam(t, 1);
		fillImpl(t, mb, 1, 0, getLength(t));
		dup(t, 0);
		return 1;
	}

	uword fillRange(CrocThread* t)
	{
		auto mb = getThis(t);
		auto len = getLength(t);
		auto lo = optIntParam(t, 1, 0);
		auto hi = optIntParam(t, 2, len);
		checkAnyParam(t, 3);

		if(lo < 0)
			lo += len;

		if(hi < 0)
			hi += len;

		if(lo < 0 || lo > hi || hi > len)
			throwException(t, "Invalid range indices: {} .. {} (buffer length: {})", lo, hi, len);

		fillImpl(t, mb, 3, cast(uword)lo, cast(uword)hi);
		dup(t, 0);
		return 1;
	}

	uword sb_insert(CrocThread* t)
	{
		auto mb = getThis(t);
		auto len = getLength(t);
		auto idx = checkIntParam(t, 1);
		checkAnyParam(t, 2);

		if(idx < 0)
			idx += len;

		// yes, greater, because it's possible to insert at one past the end of the buffer (it appends)
		if(len < 0 || idx > len)
			throwException(t, "Invalid index: {} (length: {})", idx, len);

		dchar[] doResize(crocint otherLen)
		{
			auto totalLen = len + otherLen;

			if(totalLen > uword.max)
				throwException(t, "Invalid size ({})", totalLen);

			auto oldLen = len;

			ensureSize(t, mb, cast(uword)totalLen);
			setLength(t, cast(uword)totalLen);

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
				Utf.toString32(str, tmp, &ate);
			}
		}
		else if(isChar(t, 2))
			doResize(1)[0] = getChar(t, 2);
		else if(as(t, 2, -1))
		{
			auto other = cast(dchar[])getData(t, 2).data;
			auto otherLen = getLength(t, 2);

			if(otherLen != 0)
				doResize(otherLen)[] = other[0 .. otherLen];
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
				Utf.toString32(str, tmp, &ate);
			}

			pop(t);
		}

		dup(t, 0);
		return 1;
	}

	uword remove(CrocThread* t)
	{
		auto mb = getThis(t);
		auto len = getLength(t);

		if(len == 0)
			throwException(t, "StringBuffer is empty");

		auto lo = checkIntParam(t, 1);
		auto hi = optIntParam(t, 2, lo + 1);

		if(lo < 0)
			lo += len;

		if(hi < 0)
			hi += len;

		if(lo < 0 || lo > hi || hi > len)
			throwException(t, "Invalid indices: {} .. {} (length: {})", lo, hi, len);

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

	uword format(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto mb = getThis(t);
		auto len = getLength(t);

		uint sink(char[] data)
		{
			ulong totalLen = cast(uword)len + verify(data);

			if(totalLen > uword.max)
				throwException(t, "Invalid size ({})", totalLen);

			ensureSize(t, mb, cast(uword)totalLen);
			setLength(t, cast(uword)totalLen);
			auto oldLen = len;
			len = cast(uword)totalLen;

			uint ate = 0;
			Utf.toString32(data, (cast(dchar[])mb.data)[cast(uword)oldLen .. cast(uword)totalLen], &ate);
			return data.length;
		}

		formatImpl(t, numParams, &sink);

		dup(t, 0);
		return 1;
	}

	uword formatln(CrocThread* t)
	{
		format(t);
		pushNull(t);
		pushChar(t, '\n');
		methodCall(t, -3, "append", 1);
		return 1;
	}

	uword opSerialize(CrocThread* t)
	{
		auto mb = getThis(t);

		// don't know if this is possible, but can't hurt to check
		if(!mb.ownData)
			throwException(t, "Attempting to serialize a string buffer which does not own its data");

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

	uword opDeserialize(CrocThread* t)
	{
		checkInstParam(t, 0, "StringBuffer");

		dup(t, 2);
		pushNull(t);
		rawCall(t, -2, 1);
		assert(isInt(t, -1));
		setExtraVal(t, 0, Length);

		dup(t, 2);
		pushNull(t);
		rawCall(t, -2, 1);
		assert(isMemblock(t, -1));
		setExtraVal(t, 0, Data);

		return 0;
	}
}