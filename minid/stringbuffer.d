/******************************************************************************
This module contains the implementation of the StringBuffer class defined in
the baselib.

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

module minid.stringbuffer;

import tango.stdc.string;
import Utf = tango.text.convert.Utf;

import minid.ex;
import minid.interpreter;
import minid.misc;
import minid.types;
import minid.utils;
import minid.vector;

struct StringBufferObj
{
static:
	alias VectorObj.Members Members;

	void init(MDThread* t)
	{
		CreateClass(t, "StringBuffer", "Vector", (CreateClass* c)
		{
			c.method("constructor",    &constructor);

			c.method("fill",           &fill);
			c.method("fillRange",      &fillRange);
			c.method("format",         &format);
			c.method("formatln",       &formatln);
			c.method("insert",         &sb_insert);
			c.method("toString",       &toString);

			c.method("opCatAssign",    &opCatAssign);
			c.method("opLengthAssign", &opLengthAssign);
			c.method("opIndex",        &opIndex);
			c.method("opIndexAssign",  &opIndexAssign);
			c.method("opSlice",        &opSlice);

				newFunction(t, &iterator, "iterator");
				newFunction(t, &iteratorReverse, "iteratorReverse");
			c.method("opApply", &opApply, 2);
		});

		field(t, -1, "fillRange");
		fielda(t, -2, "opSliceAssign");

		field(t, -1, "opCatAssign");
		fielda(t, -2, "append");

		newGlobal(t, "StringBuffer");
	}

	private Members* getThis(MDThread* t)
	{
		return checkInstParam!(Members)(t, 0, "StringBuffer");
	}

	uword constructor(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		char[] data = void;
		uword length = void;

		if(optParam(t, 1, MDValue.Type.String))
		{
			data = getString(t, 1);
			length = cast(uword)len(t, 1);
		}
		else
		{
			data = "";
			length = 0;
		}

		auto reg = pushNull(t);
		pushNull(t);
		pushString(t, "u32");
		pushInt(t, length);
		superCall(t, reg, "constructor", 0);

		if(length > 0)
		{
			uint ate = 0;
			Utf.toString32(data, (cast(dchar*)memb.data)[0 .. length], &ate);
		}

		return 0;
	}

	uword opCatAssign(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkAnyParam(t, 1);

		pushGlobal(t, "StringBuffer");

		dchar[] resize(ulong addLen)
		{
			ulong totalLen = memb.length + addLen;

			if(totalLen > uword.max)
				throwException(t, "Invalid size ({})", totalLen);

			auto oldLen = memb.length;

			pushNull(t);
			pushNull(t);
			pushInt(t, cast(mdint)totalLen);
			superCall(t, -3, "opLengthAssign", 0);

			return (cast(dchar*)memb.data)[oldLen .. cast(uword)totalLen];
		}

		for(uword i = 1; i <= numParams; i++)
		{
			if(as(t, i, -1))
			{
				auto other = getMembers!(Members)(t, i);
				resize(other.length)[0 .. other.length] = (cast(dchar*)other.data)[0 .. other.length];
			}
			else if(isString(t, i))
			{
				auto dest = resize(cast(ulong)len(t, i));
				uint ate = 0;
				Utf.toString32(getString(t, i), dest, &ate);
			}
			else if(isChar(t, i))
				resize(1)[0] = getChar(t, i);
			else
			{
				pushToString(t, i);
				auto dest = resize(cast(ulong)len(t, -1));
				uint ate = 0;
				Utf.toString32(getString(t, -1), dest, &ate);
				pop(t);
			}
		}

		// we're returning 'this' in case people want to chain 'append's, since this method is also append.
		dup(t, 0);
		return 1;
	}

	uword sb_insert(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto idx = checkIntParam(t, 1);
		checkAnyParam(t, 2);

		if(idx < 0)
			idx += memb.length;

		if(idx < 0 || idx > memb.length)
			throwException(t, "Invalid index: {} (length: {})", idx, memb.length);

		dchar[] doResize(ulong otherLen)
		{
			ulong totalLen = memb.length + otherLen;

			if(totalLen > uword.max)
				throwException(t, "Invalid size ({})", totalLen);

			auto oldLen = memb.length;

			pushNull(t);
			pushNull(t);
			pushInt(t, cast(mdint)totalLen);
			superCall(t, -3, "opLengthAssign", 0);

			auto tmp = (cast(dchar*)memb.data)[0 .. memb.length];

			if(idx < oldLen)
			{
				auto end = idx + otherLen;
				auto numLeft = oldLen - idx;
				memmove(&tmp[cast(uword)end], &tmp[cast(uword)idx], cast(uint)(numLeft * memb.type.itemSize));
			}

			return tmp[cast(uword)idx .. cast(uword)(idx + otherLen)];
		}

		pushGlobal(t, "StringBuffer");

		if(as(t, 2, -1))
		{
			auto other = getMembers!(Members)(t, 2);

			if(other.length != 0)
			{
				auto tmp = doResize(other.length);
				tmp[] = (cast(dchar*)other.data)[0 .. other.length];
			}
		}
		else if(isString(t, 2))
		{
			auto cpLen = len(t, 2);

			if(cpLen != 0)
			{
				auto str = getString(t, 2);
				auto tmp = doResize(cast(ulong)cpLen);
				uint ate = 0;
				Utf.toString32(str, tmp, &ate);
			}
		}
		else if(isChar(t, 2))
			doResize(1)[0] = getChar(t, 2);
		else
		{
			pushToString(t, 2);

			auto cpLen = len(t, -1);

			if(cpLen != 0)
			{
				auto str = getString(t, -1);
				auto tmp = doResize(cast(ulong)cpLen);
				uint ate = 0;
				Utf.toString32(str, tmp, &ate);
			}

			pop(t);
		}

		dup(t, 0);
		return 1;
	}

	uword toString(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		pushFormat(t, "{}", (cast(dchar*)memb.data)[0 .. memb.length]);
		return 1;
	}

	uword opLengthAssign(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto newLen = checkIntParam(t, 1);

		if(newLen < 0 || newLen > uword.max)
			throwException(t, "Invalid length ({})", newLen);

		auto oldLen = memb.length;

		pushNull(t);
		pushNull(t);
		pushInt(t, newLen);
		superCall(t, -3, "opLengthAssign", 0);

		if(newLen > oldLen)
			(cast(dchar*)memb.data)[oldLen .. cast(uword)newLen] = dchar.init;

		return 0;
	}

	uword opIndex(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkAnyParam(t, 1);

		pushNull(t);
		pushNull(t);
		dup(t, 1);
		superCall(t, -3, "opIndex", 1);

		pushChar(t, cast(dchar)getInt(t, -1));
		return 1;
	}

	uword opIndexAssign(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto index = checkIntParam(t, 1);
		auto ch = checkCharParam(t, 2);

		if(index < 0)
			index += memb.length;

		if(index < 0 || index >= memb.length)
			throwException(t, "Invalid index: {} (buffer length: {})", index, memb.length);

		(cast(dchar*)memb.data)[cast(uword)index] = ch;
		return 0;
	}

	uword iterator(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto index = checkIntParam(t, 1) + 1;

		if(index >= memb.length)
			return 0;

		pushInt(t, index);
		pushChar(t, (cast(dchar*)memb.data)[cast(uword)index]);

		return 2;
	}

	uword iteratorReverse(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto index = checkIntParam(t, 1) - 1;

		if(index < 0)
			return 0;

		pushInt(t, index);
		pushChar(t, (cast(dchar*)memb.data)[cast(uword)index]);

		return 2;
	}

	uword opApply(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		if(optStringParam(t, 1, "") == "reverse")
		{
			getUpval(t, 1);
			dup(t, 0);
			pushInt(t, memb.length);
		}
		else
		{
			getUpval(t, 0);
			dup(t, 0);
			pushInt(t, -1);
		}

		return 3;
	}

	void fillImpl(MDThread* t, Members* memb, word idx, uword lo, uword hi)
	{
		pushGlobal(t, "StringBuffer");

		if(as(t, idx, -1))
		{
			auto other = getMembers!(Members)(t, idx);

			if(other.length != (hi - lo))
				throwException(t, "Length of destination ({}) and length of source ({}) do not match", hi - lo, other.length);

			(cast(dchar*)memb.data)[lo .. hi] = (cast(dchar*)other.data)[0 .. other.length];
		}
		else if(isFunction(t, idx))
		{
			void callFunc(uword i)
			{
				dup(t, idx);
				pushNull(t);
				pushInt(t, i);
				rawCall(t, -3, 1);
			}

			auto data = (cast(dchar*)memb.data)[0 .. memb.length];

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
		else if(isChar(t, idx))
			(cast(dchar*)memb.data)[lo .. hi] = getChar(t, idx);
		else if(isString(t, idx))
		{
			auto cpLen = cast(uword)len(t, idx);

			if(cpLen != (hi - lo))
				throwException(t, "Length of destination ({}) and length of source string ({}) do not match", hi - lo, cpLen);

			uint ate = 0;
			Utf.toString32(getString(t, idx), (cast(dchar*)memb.data)[lo .. hi], &ate);
		}
		else if(isArray(t, idx))
		{
			auto data = (cast(dchar*)memb.data)[lo .. hi];

			for(uword i = lo, ai = 0; i < hi; i++, ai++)
			{
				idxi(t, idx, ai);

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
			paramTypeError(t, idx, "char|string|array|function|StringBuffer");

		pop(t);
	}

	uword fill(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkAnyParam(t, 1);

		fillImpl(t, memb, 1, 0, memb.length);

		dup(t, 0);
		return 1;
	}

	uword fillRange(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto lo = optIntParam(t, 1, 0);
		auto hi = optIntParam(t, 2, memb.length);
		checkAnyParam(t, 3);

		if(lo < 0)
			lo += memb.length;

		if(lo < 0 || lo > memb.length)
			throwException(t, "Invalid low index: {} (buffer length: {})", lo, memb.length);

		if(hi < 0)
			hi += memb.length;

		if(hi < lo || hi > memb.length)
			throwException(t, "Invalid range indices: {} .. {} (buffer length: {})", lo, hi, memb.length);

		fillImpl(t, memb, 3, cast(uword)lo, cast(uword)hi);

		dup(t, 0);
		return 1;
	}

	uword opSlice(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto lo = optIntParam(t, 1, 0);
		auto hi = optIntParam(t, 2, memb.length);

		if(lo < 0)
			lo += memb.length;

		if(lo < 0 || lo >= memb.length)
			throwException(t, "Invalid low index: {} (buffer length: {})", lo, memb.length);

		if(hi < 0)
			hi += memb.length;

		if(hi < lo || hi > memb.length)
			throwException(t, "Invalid slice indices: {} .. {} (buffer length: {})", lo, hi, memb.length);

		pushFormat(t, "{}", (cast(dchar*)memb.data)[cast(uword)lo .. cast(uword)hi]);
		return 1;
	}

	uword format(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		uint sink(char[] data)
		{
			ulong totalLen = memb.length + verify(data);

			if(totalLen > uword.max)
				throwException(t, "Invalid size ({})", totalLen);

			auto oldLen = memb.length;

			pushNull(t);
			pushNull(t);
			pushInt(t, cast(mdint)totalLen);
			superCall(t, -3, "opLengthAssign", 0);

			uint ate = 0;
			Utf.toString32(data, (cast(dchar*)memb.data)[oldLen .. memb.length], &ate);

			return data.length;
		}

		formatImpl(t, numParams, &sink);

		dup(t, 0);
		return 1;
	}

	uword formatln(MDThread* t, uword numParams)
	{
		pushChar(t, '\n');
		return format(t, numParams + 1);
	}
}