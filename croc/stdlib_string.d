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

import Float = tango.text.convert.Float;
import Integer = tango.text.convert.Integer;
import tango.core.Array;
import tango.text.Util;
import Uni = tango.text.Unicode;
import Utf = tango.text.convert.Utf;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.stdlib_stringbuffer;
import croc.stdlib_utils;
import croc.types;
import croc.utils;

struct StringLib
{
static:
	public void init(CrocThread* t)
	{
		makeModule(t, "string", function uword(CrocThread* t)
		{
			StringBufferObj.init(t);

			register(t, 2, "joinArray", &joinArray);
			register(t, 1, "fromRawUnicode", &fromRawUnicode);
			register(t, 1, "fromRawAscii", &fromRawAscii);

			newNamespace(t, "string");
				registerField(t, 2, "toRawUnicode", &toRawUnicode);
				registerField(t, 1, "opApply", &opApply);
				registerField(t,    "join", &join);
				registerField(t, 1, "toInt", &toInt);
				registerField(t, 0, "toFloat", &toFloat);
				registerField(t, 1, "compare", &compare);
				registerField(t, 1, "icompare", &icompare);
				registerField(t, 2, "find", &find);
				registerField(t, 2, "ifind", &ifind);
				registerField(t, 2, "rfind", &rfind);
				registerField(t, 2, "irfind", &irfind);
				registerField(t, 0, "toLower", &toLower);
				registerField(t, 0, "toUpper", &toUpper);
				registerField(t, 1, "repeat", &repeat);
				registerField(t, 0, "reverse", &reverse);
				registerField(t, 1, "split", &split);
				registerField(t, 0, "splitLines", &splitLines);
				registerField(t, 0, "strip", &strip);
				registerField(t, 0, "lstrip", &lstrip);
				registerField(t, 0, "rstrip", &rstrip);
				registerField(t, 2, "replace", &replace);
				registerField(t, 1, "startsWith", &startsWith);
				registerField(t, 1, "endsWith", &endsWith);
				registerField(t, 1, "istartsWith", &istartsWith);
				registerField(t, 1, "iendsWith", &iendsWith);
			setTypeMT(t, CrocValue.Type.String);

			return 0;
		});

		importModuleNoNS(t, "string");
	}

	uword joinArray(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Array);
		auto sep = optStringParam(t, 2, "");
		auto arr = getArray(t, 1).toArray();

		if(arr.length == 0)
		{
			pushString(t, "");
			return 1;
		}
		
		foreach(i, ref val; arr)
			if(val.type != CrocValue.Type.String && val.type != CrocValue.Type.Char)
				throwStdException(t, "TypeException", "Array element {} is not a string or char", i);

		auto s = StrBuffer(t);

		if(arr[0].type == CrocValue.Type.String)
			s.addString(arr[0].mString.toString());
		else
			s.addChar(arr[0].mChar);

		if(sep.length == 0)
		{
			foreach(ref val; arr[1 .. $])
			{
				if(val.type == CrocValue.Type.String)
					s.addString(val.mString.toString());
				else
					s.addChar(val.mChar);
			}
		}
		else
		{
			foreach(ref val; arr[1 .. $])
			{
				s.addString(sep);

				if(val.type == CrocValue.Type.String)
					s.addString(val.mString.toString());
				else
					s.addChar(val.mChar);
			}
		}

		s.finish();
		return 1;
	}
	
	uword fromRawUnicode(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 1);

		switch(mb.kind.code)
		{
			case CrocMemblock.TypeCode.u8:  pushFormat(t, "{}", (cast(char[])mb.data)[0 .. mb.itemLength]); break;
			case CrocMemblock.TypeCode.u16: pushFormat(t, "{}", (cast(wchar[])mb.data)[0 .. mb.itemLength]); break;
			case CrocMemblock.TypeCode.u32: pushFormat(t, "{}", (cast(dchar[])mb.data)[0 .. mb.itemLength]); break;
			default: throwStdException(t, "ValueException", "Memblock must be of type 'u8', 'u16', or 'u32', not '{}'", mb.kind.name);
		}

		return 1;
	}

	uword fromRawAscii(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 1);

		if(mb.kind.code != CrocMemblock.TypeCode.u8)
			throwStdException(t, "ValueException", "Memblock must be of type 'u8', not '{}'", mb.kind.name);

		auto src = (cast(char[])mb.data)[0 .. mb.itemLength];
  		auto dest = allocArray!(char)(t, src.length);

  		scope(exit)
  			freeArray(t, dest);

  		foreach(i, char c; src)
  		{
		  	if(c <= 0x7f)
  				dest[i] = c;
  			else
  				dest[i] = '\u001a';
		}

		pushString(t, dest);
		return 1;
	}
	
	uword toRawUnicode(CrocThread* t)
	{
		checkStringParam(t, 0);
		auto str = getStringObj(t, 0);
		auto bitSize = optIntParam(t, 1, 8);

		char[] typeCode;

		switch(bitSize)
		{
			case 8:  typeCode = "u8"; break;
			case 16: typeCode = "u16"; break;
			case 32: typeCode = "u32"; break;
			default: throwStdException(t, "ValueException", "Invalid encoding size of {} bits", bitSize);
		}

		CrocMemblock* ret;

		if(optParam(t, 2, CrocValue.Type.Memblock))
		{
			ret = getMemblock(t, 2);
			// round off to a multiple of 4 so the re-type always works
			lenai(t, 2, len(t, 2) & ~3);
			dup(t, 2);
			pushNull(t);
			pushString(t, typeCode);
			methodCall(t, -3, "type", 0);
			lenai(t, 2, str.length);
		}
		else
		{
			newMemblock(t, typeCode, str.length);
			ret = getMemblock(t, -1);
		}
		
		uword len = 0;
		auto src = str.toString();

		switch(bitSize)
		{
			case 8:
				(cast(char*)ret.data.ptr)[0 .. str.length] = src[];
				len = str.length;
				break;

			case 16:
				auto dest = (cast(wchar*)ret.data.ptr)[0 .. str.length];
				
				auto temp = allocArray!(dchar)(t, str.length);
				scope(exit) freeArray(t, temp);

				uint ate = 0;
				auto tempData = safeCode(t, "exceptions.UnicodeException", Utf.toString32(src, temp, &ate));
				len = safeCode(t, "exceptions.UnicodeException", Utf.toString16(temp, dest, &ate)).length;
				break;

			case 32:
				auto dest = (cast(dchar*)ret.data.ptr)[0 .. str.length];
				uint ate = 0;
				len = safeCode(t, "exceptions.UnicodeException", Utf.toString32(src, dest, &ate)).length;
				break;

			default: assert(false);
		}
		
		push(t, CrocValue(ret));
		lenai(t, -1, len);
		return 1;
	}

	uword join(CrocThread* t)
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

	uword toInt(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto src = checkStringParam(t, 0);

		int base = 10;

		if(numParams > 0)
			base = cast(int)getInt(t, 1);

		pushInt(t, safeCode(t, "exceptions.ValueException", Integer.toInt(src, base)));
		return 1;
	}

	uword toFloat(CrocThread* t)
	{
		pushFloat(t, safeCode(t, "exceptions.ValueException", Float.toFloat(checkStringParam(t, 0))));
		return 1;
	}

	uword compare(CrocThread* t)
	{
		pushInt(t, scmp(checkStringParam(t, 0), checkStringParam(t, 1)));
		return 1;
	}

	uword icompare(CrocThread* t)
	{
		auto s1 = checkStringParam(t, 0);
		auto s2 = checkStringParam(t, 1);

		char[64] buf1 = void;
		char[64] buf2 = void;
		s1 = Uni.toFold(s1, buf1);
		s2 = Uni.toFold(s2, buf2);

		pushInt(t, scmp(s1, s2));
		return 1;
	}

	uword find(CrocThread* t)
	{
		auto src = checkStringParam(t, 0);
		auto srcLen = len(t, 0);
		auto start = optIntParam(t, 2, 0);

		if(start < 0)
		{
			start += srcLen;

			if(start < 0)
				throwStdException(t, "BoundsException", "Invalid start index {}", start);
		}

		if(start >= srcLen)
		{
			pushInt(t, srcLen);
			return 1;
		}

		char[6] buf = void;
		char[] pat;

		if(isString(t, 1))
			pat = getString(t, 1);
		else if(isChar(t, 1))
		{
			dchar[1] dc = getChar(t, 1);
			pat = Utf.toString(dc[], buf);
		}
		else
			paramTypeError(t, 1, "char|string");

		pushInt(t, src.locatePattern(pat, uniCPIdxToByte(src, cast(uword)start)));

		return 1;
	}

	uword ifind(CrocThread* t)
	{
		auto src = checkStringParam(t, 0);
		auto srcLen = len(t, 0);
		auto start = optIntParam(t, 2, 0);

		if(start < 0)
		{
			start += srcLen;

			if(start < 0)
				throwStdException(t, "BoundsException", "Invalid start index {}", start);
		}

		if(start >= srcLen)
		{
			pushInt(t, srcLen);
			return 1;
		}

		char[64] buf1 = void;
		char[64] buf2 = void;
		src = Uni.toFold(src, buf1);
		char[] pat;

		if(isString(t, 1))
			pat = Uni.toFold(getString(t, 1), buf2);
		else if(isChar(t, 1))
		{
			dchar[1] dc = getChar(t, 1);
			char[6] cbuf = void;
			pat = Utf.toString(dc[], cbuf);
			pat = Uni.toFold(pat, buf2);
		}
		else
			paramTypeError(t, 1, "char|string");

		pushInt(t, src.locatePattern(pat, uniCPIdxToByte(src, cast(uword)start)));

		return 1;
	}

	uword rfind(CrocThread* t)
	{
		auto src = checkStringParam(t, 0);
		auto srcLen = len(t, 0);
		auto start = optIntParam(t, 2, srcLen);

		if(start > srcLen)
			throwStdException(t, "BoundsException", "Invalid start index: {}", start);

		if(start < 0)
		{
			start += srcLen;

			if(start < 0)
				throwStdException(t, "BoundsException", "Invalid start index {}", start);
		}

		if(start == 0)
		{
			pushInt(t, srcLen);
			return 1;
		}

		char[6] buf = void;
		char[] pat;

		if(isString(t, 1))
			pat = getString(t, 1);
		else if(isChar(t, 1))
		{
			dchar[1] dc = getChar(t, 1);
			pat = Utf.toString(dc[], buf);
		}
		else
			paramTypeError(t, 1, "char|string");

		pushInt(t, src.locatePatternPrior(pat, uniCPIdxToByte(src, cast(uword)start)));

		return 1;
	}

	uword irfind(CrocThread* t)
	{
		auto src = checkStringParam(t, 0);
		auto srcLen = len(t, 0);
		auto start = optIntParam(t, 2, srcLen);

		if(start > srcLen)
			throwStdException(t, "BoundsException", "Invalid start index: {}", start);

		if(start < 0)
		{
			start += srcLen;

			if(start < 0)
				throwStdException(t, "BoundsException", "Invalid start index {}", start);
		}

		if(start == 0)
		{
			pushInt(t, srcLen);
			return 1;
		}

		char[64] buf1 = void;
		char[64] buf2 = void;
		src = Uni.toFold(src, buf1);
		char[] pat;

		if(isString(t, 1))
			pat = Uni.toFold(getString(t, 1), buf2);
		else if(isChar(t, 1))
		{
			dchar[1] dc = getChar(t, 1);
			char[6] cbuf = void;
			pat = Utf.toString(dc[], cbuf);
			pat = Uni.toFold(pat, buf2);
		}
		else
			paramTypeError(t, 1, "char|string");

		pushInt(t, src.locatePatternPrior(pat, uniCPIdxToByte(src, cast(uword)start)));

		return 1;
	}

	uword toLower(CrocThread* t)
	{
		auto src = checkStringParam(t, 0);
		auto buf = StrBuffer(t);
		
		foreach(dchar c; src)
		{
			dchar[4] outbuf = void;
			
			foreach(ch; Uni.toLower((&c)[0 .. 1], outbuf))
				buf.addChar(ch);
		}

		buf.finish();
		return 1;
	}

	uword toUpper(CrocThread* t)
	{
		auto src = checkStringParam(t, 0);
		auto buf = StrBuffer(t);
		
		foreach(dchar c; src)
		{
			dchar[4] outbuf = void;
			
			foreach(ch; Uni.toUpper((&c)[0 .. 1], outbuf))
				buf.addChar(ch);
		}

		buf.finish();
		return 1;
	}

	uword repeat(CrocThread* t)
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

	uword reverse(CrocThread* t)
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

	uword split(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto src = checkStringParam(t, 0);
		auto ret = newArray(t, 0);
		uword num = 0;

		if(numParams > 0)
		{
			foreach(piece; src.patterns(checkStringParam(t, 1)))
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
		else
		{
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
		}

		if(num > 0)
			cateq(t, ret, num);

		return 1;
	}

	uword splitLines(CrocThread* t)
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

	uword strip(CrocThread* t)
	{
		pushString(t, checkStringParam(t, 0).trim());
		return 1;
	}

	uword lstrip(CrocThread* t)
	{
		pushString(t, checkStringParam(t, 0).triml());
		return 1;
	}

	uword rstrip(CrocThread* t)
	{
		pushString(t, checkStringParam(t, 0).trimr());
		return 1;
	}

	uword replace(CrocThread* t)
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

	uword iterator(CrocThread* t)
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
		auto c = Utf.decode(s.toString()[cast(uword)realIdx .. $], ate);
		realIdx += ate;

		pushInt(t, realIdx);
		setUpval(t, 0);
		
		pushInt(t, fakeIdx);
		pushChar(t, c);
		return 2;
	}

	uword iteratorReverse(CrocThread* t)
	{
		checkStringParam(t, 0);
		auto s = getStringObj(t, 0);
		auto fakeIdx = checkIntParam(t, 1) - 1;

		getUpval(t, 0);
		auto realIdx = getInt(t, -1);
		pop(t);

		if(realIdx <= 0)
			return 0;

		auto tmp = Utf.cropRight(s.toString[0 .. cast(uword)realIdx - 1]);
		uint ate = void;
		auto c = Utf.decode(s.toString()[tmp.length .. $], ate);

		pushInt(t, tmp.length);		
		setUpval(t, 0);

		pushInt(t, fakeIdx);
		pushChar(t, c);
		return 2;
	}

	uword opApply(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.String);

		if(optStringParam(t, 1, "") == "reverse")
		{
			pushInt(t, getStringObj(t, 0).length);
			newFunction(t, &iteratorReverse, "iteratorReverse", 1);
			dup(t, 0);
			pushInt(t, len(t, 0));
		}
		else
		{
			pushInt(t, 0);
			newFunction(t, &iterator, "iterator", 1);
			dup(t, 0);
			pushInt(t, -1);
		}

		return 3;
	}

	uword startsWith(CrocThread* t)
	{
		pushBool(t, .startsWith(checkStringParam(t, 0), checkStringParam(t, 1)));
		return 1;
	}

	uword endsWith(CrocThread* t)
	{
		pushBool(t, .endsWith(checkStringParam(t, 0), checkStringParam(t, 1)));
		return 1;
	}

	uword istartsWith(CrocThread* t)
	{
		char[64] buf1 = void;
		char[64] buf2 = void;
		auto s1 = Uni.toFold(checkStringParam(t, 0), buf1);
		auto s2 = Uni.toFold(checkStringParam(t, 1), buf2);

		pushBool(t, .startsWith(s1, s2));
		return 1;
	}

	uword iendsWith(CrocThread* t)
	{
		char[64] buf1 = void;
		char[64] buf2 = void;
		auto s1 = Uni.toFold(checkStringParam(t, 0), buf1);
		auto s2 = Uni.toFold(checkStringParam(t, 1), buf2);

		pushBool(t, .endsWith(s1, s2));
		return 1;
	}
}