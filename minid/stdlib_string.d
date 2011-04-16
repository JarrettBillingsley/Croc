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

module minid.stdlib_string;

import Float = tango.text.convert.Float;
import Integer = tango.text.convert.Integer;
import tango.core.Array;
import tango.text.Util;
import Uni = tango.text.Unicode;
import Utf = tango.text.convert.Utf;

import minid.ex;
import minid.interpreter;
import minid.stackmanip;
import minid.stdlib_vector;
import minid.types;
import minid.utils;

struct StringLib
{
static:
	public void init(MDThread* t)
	{
		makeModule(t, "string", function uword(MDThread* t)
		{
			newFunction(t, 2, &joinArray,      "joinArray");      newGlobal(t, "joinArray");
			newFunction(t, 1, &fromRawUnicode, "fromRawUnicode"); newGlobal(t, "fromRawUnicode");
			newFunction(t, 1, &fromRawAscii,   "fromRawAscii");   newGlobal(t, "fromRawAscii");

			newNamespace(t, "string");
				newFunction(t, 1, &opApply,     "opApply");     fielda(t, -2, "opApply");
				newFunction(t,    &join,        "join");        fielda(t, -2, "join");
				newFunction(t, 1, &toInt,       "toInt");       fielda(t, -2, "toInt");
				newFunction(t, 0, &toFloat,     "toFloat");     fielda(t, -2, "toFloat");
				newFunction(t, 1, &compare,     "compare");     fielda(t, -2, "compare");
				newFunction(t, 1, &icompare,    "icompare");    fielda(t, -2, "icompare");
				newFunction(t, 2, &find,        "find");        fielda(t, -2, "find");
				newFunction(t, 2, &ifind,       "ifind");       fielda(t, -2, "ifind");
				newFunction(t, 2, &rfind,       "rfind");       fielda(t, -2, "rfind");
				newFunction(t, 2, &irfind,      "irfind");      fielda(t, -2, "irfind");
				newFunction(t, 0, &toLower,     "toLower");     fielda(t, -2, "toLower");
				newFunction(t, 0, &toUpper,     "toUpper");     fielda(t, -2, "toUpper");
				newFunction(t, 1, &repeat,      "repeat");      fielda(t, -2, "repeat");
				newFunction(t, 0, &reverse,     "reverse");     fielda(t, -2, "reverse");
				newFunction(t, 1, &split,       "split");       fielda(t, -2, "split");
				newFunction(t, 0, &splitLines,  "splitLines");  fielda(t, -2, "splitLines");
				newFunction(t, 0, &strip,       "strip");       fielda(t, -2, "strip");
				newFunction(t, 0, &lstrip,      "lstrip");      fielda(t, -2, "lstrip");
				newFunction(t, 0, &rstrip,      "rstrip");      fielda(t, -2, "rstrip");
				newFunction(t, 2, &replace,     "replace");     fielda(t, -2, "replace");
				newFunction(t, 1, &startsWith,  "startsWith");  fielda(t, -2, "startsWith");
				newFunction(t, 1, &endsWith,    "endsWith");    fielda(t, -2, "endsWith");
				newFunction(t, 1, &istartsWith, "istartsWith"); fielda(t, -2, "istartsWith");
				newFunction(t, 1, &iendsWith,   "iendsWith");   fielda(t, -2, "iendsWith");
			setTypeMT(t, MDValue.Type.String);

			return 0;
		});

		importModuleNoNS(t, "string");
	}

	uword joinArray(MDThread* t)
	{
		checkParam(t, 1, MDValue.Type.Array);
		auto sep = optStringParam(t, 2, "");
		auto arr = getArray(t, 1).toArray();

		if(arr.length == 0)
		{
			pushString(t, "");
			return 1;
		}
		
		foreach(i, ref val; arr)
			if(val.type != MDValue.Type.String && val.type != MDValue.Type.Char)
				throwException(t, "Array element {} is not a string or char", i);

		auto s = StrBuffer(t);

		if(arr[0].type == MDValue.Type.String)
			s.addString(arr[0].mString.toString());
		else
			s.addChar(arr[0].mChar);

		if(sep.length == 0)
		{
			foreach(ref val; arr[1 .. $])
			{
				if(val.type == MDValue.Type.String)
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

				if(val.type == MDValue.Type.String)
					s.addString(val.mString.toString());
				else
					s.addChar(val.mChar);
			}
		}

		s.finish();
		return 1;
	}
	
	uword fromRawUnicode(MDThread* t)
	{
		auto v = checkInstParam!(VectorObj.Members)(t, 1, "Vector");

		switch(v.type.code)
		{
			case VectorObj.TypeCode.u8:  pushFormat(t, "{}", (cast(char*)v.data)[0 .. v.length]); break;
			case VectorObj.TypeCode.u16: pushFormat(t, "{}", (cast(wchar*)v.data)[0 .. v.length]); break;
			case VectorObj.TypeCode.u32: pushFormat(t, "{}", (cast(dchar*)v.data)[0 .. v.length]); break;

			default:
				throwException(t, "Vector must be of type 'u8', 'u16', or 'u32', not '{}'", VectorObj.typeNames[v.type.code]);
				return 0;
		}

		return 1;
	}

	uword fromRawAscii(MDThread* t)
	{
		auto v = checkInstParam!(VectorObj.Members)(t, 1, "Vector");

		if(v.type.code != VectorObj.TypeCode.u8)
			throwException(t, "Vector must be of type 'u8', not '{}'", VectorObj.typeNames[v.type.code]);

		auto src = (cast(char*)v.data)[0 .. v.length];
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

	uword join(MDThread* t)
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

	uword toInt(MDThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto src = checkStringParam(t, 0);

		int base = 10;

		if(numParams > 0)
			base = cast(int)getInt(t, 1);

		pushInt(t, safeCode(t, Integer.toInt(src, base)));
		return 1;
	}

	uword toFloat(MDThread* t)
	{
		pushFloat(t, safeCode(t, Float.toFloat(checkStringParam(t, 0))));
		return 1;
	}

	uword compare(MDThread* t)
	{
		pushInt(t, scmp(checkStringParam(t, 0), checkStringParam(t, 1)));
		return 1;
	}

	uword icompare(MDThread* t)
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

	uword find(MDThread* t)
	{
		auto src = checkStringParam(t, 0);
		auto srcLen = len(t, 0);
		auto start = optIntParam(t, 2, 0);

		if(start < 0)
		{
			start += srcLen;

			if(start < 0)
				throwException(t, "Invalid start index {}", start);
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

	uword ifind(MDThread* t)
	{
		auto src = checkStringParam(t, 0);
		auto srcLen = len(t, 0);
		auto start = optIntParam(t, 2, 0);

		if(start < 0)
		{
			start += srcLen;

			if(start < 0)
				throwException(t, "Invalid start index {}", start);
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

	uword rfind(MDThread* t)
	{
		auto src = checkStringParam(t, 0);
		auto srcLen = len(t, 0);
		auto start = optIntParam(t, 2, srcLen);

		if(start > srcLen)
			throwException(t, "Invalid start index: {}", start);

		if(start < 0)
		{
			start += srcLen;

			if(start < 0)
				throwException(t, "Invalid start index {}", start);
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

	uword irfind(MDThread* t)
	{
		auto src = checkStringParam(t, 0);
		auto srcLen = len(t, 0);
		auto start = optIntParam(t, 2, srcLen);

		if(start > srcLen)
			throwException(t, "Invalid start index: {}", start);

		if(start < 0)
		{
			start += srcLen;

			if(start < 0)
				throwException(t, "Invalid start index {}", start);
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

	uword toLower(MDThread* t)
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

	uword toUpper(MDThread* t)
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

	uword repeat(MDThread* t)
	{
		checkStringParam(t, 0);
		auto numTimes = checkIntParam(t, 1);

		if(numTimes < 0)
			throwException(t, "Invalid number of repetitions: {}", numTimes);

		auto buf = StrBuffer(t);

		for(mdint i = 0; i < numTimes; i++)
		{
			dup(t, 0);
			buf.addTop();
		}

		buf.finish();
		return 1;
	}

	uword reverse(MDThread* t)
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

	uword split(MDThread* t)
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

	uword splitLines(MDThread* t)
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

	uword strip(MDThread* t)
	{
		pushString(t, checkStringParam(t, 0).trim());
		return 1;
	}

	uword lstrip(MDThread* t)
	{
		pushString(t, checkStringParam(t, 0).triml());
		return 1;
	}

	uword rstrip(MDThread* t)
	{
		pushString(t, checkStringParam(t, 0).trimr());
		return 1;
	}

	uword replace(MDThread* t)
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

	uword iterator(MDThread* t)
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

	uword iteratorReverse(MDThread* t)
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

	uword opApply(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.String);

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

	uword startsWith(MDThread* t)
	{
		pushBool(t, .startsWith(checkStringParam(t, 0), checkStringParam(t, 1)));
		return 1;
	}

	uword endsWith(MDThread* t)
	{
		pushBool(t, .endsWith(checkStringParam(t, 0), checkStringParam(t, 1)));
		return 1;
	}

	uword istartsWith(MDThread* t)
	{
		char[64] buf1 = void;
		char[64] buf2 = void;
		auto s1 = Uni.toFold(checkStringParam(t, 0), buf1);
		auto s2 = Uni.toFold(checkStringParam(t, 1), buf2);

		pushBool(t, .startsWith(s1, s2));
		return 1;
	}

	uword iendsWith(MDThread* t)
	{
		char[64] buf1 = void;
		char[64] buf2 = void;
		auto s1 = Uni.toFold(checkStringParam(t, 0), buf1);
		auto s2 = Uni.toFold(checkStringParam(t, 1), buf2);

		pushBool(t, .endsWith(s1, s2));
		return 1;
	}
}