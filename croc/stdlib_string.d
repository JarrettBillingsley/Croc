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
		importModuleNoNS(t, "memblock");

		StringBufferObj.init(t);
		
		registerGlobals(t, _globalFuncs);

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
	doc.push(Docs("module", "String Library",
	"The string library provides functionality for manipulating strings. Most of these functions are accessed as methods of
	string objects. These are indicated as `s.methodName` in the following docs.

	Remember that strings in Croc are immutable. Therefore these functions never operate on the object on which they were
	called. They will always return new strings distinct from the original string."));

	// docStringBufferObj(t, doc);

	docFields(t, doc, _globalFuncDocs);

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
// Global functions

const RegisterFunc[] _globalFuncs =
[
	{"fromRawUnicode", &_fromRawUnicode, maxParams: 3},
	{"fromRawAscii",   &_fromRawAscii,   maxParams: 3}
];

uword _fromRawUnicode(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 1);
	auto lo = optIntParam(t, 2, 0);
	auto hi = optIntParam(t, 3, mb.itemLength);
	
	if(lo < 0)
		lo += mb.itemLength;
	
	if(hi < 0)
		hi += mb.itemLength;
		
	if(lo < 0 || lo > hi || hi > mb.itemLength)
		throwStdException(t, "BoundsException", "Invalid memblock slice indices {} .. {} (memblock length: {})", lo, hi, mb.itemLength);

	switch(mb.kind.code)
	{
		case CrocMemblock.TypeCode.u8:  pushFormat(t, "{}", (cast(char[])mb.data)[cast(uword)lo .. cast(uword)hi]); break;
		case CrocMemblock.TypeCode.u16: pushFormat(t, "{}", (cast(wchar[])mb.data)[cast(uword)lo .. cast(uword)hi]); break;
		case CrocMemblock.TypeCode.u32: pushFormat(t, "{}", (cast(dchar[])mb.data)[cast(uword)lo .. cast(uword)hi]); break;
		default: throwStdException(t, "ValueException", "Memblock must be of type 'u8', 'u16', or 'u32', not '{}'", mb.kind.name);
	}

	return 1;
}

uword _fromRawAscii(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 1);
	auto lo = optIntParam(t, 2, 0);
	auto hi = optIntParam(t, 3, mb.itemLength);
	
	if(lo < 0)
		lo += mb.itemLength;
	
	if(hi < 0)
		hi += mb.itemLength;
		
	if(lo < 0 || lo > hi || hi > mb.itemLength)
		throwStdException(t, "BoundsException", "Invalid memblock slice indices {} .. {} (memblock length: {})", lo, hi, mb.itemLength);

	if(mb.kind.code != CrocMemblock.TypeCode.u8)
		throwStdException(t, "ValueException", "Memblock must be of type 'u8', not '{}'", mb.kind.name);

	auto src = (cast(char[])mb.data)[cast(uword)lo .. cast(uword)hi];
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

// ===================================================================================================================================
// Methods

const uword VSplitMax = 20;

const RegisterFunc[] _methodFuncs =
[
	{"toRawUnicode", &_toRawUnicode, maxParams: 2},
	{"toRawAscii",   &_toRawAscii,   maxParams: 1},
	{"opApply",      &_opApply,      maxParams: 1},
	{"join",         &_join,         maxParams: 1},
	{"vjoin",        &_vjoin},
	{"isAscii",      &_isAscii,      maxParams: 0},
	{"toInt",        &_toInt,        maxParams: 1},
	{"toFloat",      &_toFloat,      maxParams: 0},
	{"compare",      &_compare,      maxParams: 1},
	{"icompare",     &_icompare,     maxParams: 1},
	{"find",         &_find,         maxParams: 2},
	{"ifind",        &_ifind,        maxParams: 2},
	{"rfind",        &_rfind,        maxParams: 2},
	{"irfind",       &_irfind,       maxParams: 2},
	{"toLower",      &_toLower,      maxParams: 0},
	{"toUpper",      &_toUpper,      maxParams: 0},
	{"repeat",       &_repeat,       maxParams: 1},
	{"reverse",      &_reverse,      maxParams: 0},
	{"split",        &_split,        maxParams: 1},
	{"vsplit",       &_vsplit,       maxParams: 1},
	{"splitLines",   &_splitLines,   maxParams: 0},
	{"vsplitLines",  &_vsplitLines,  maxParams: 0},
	{"strip",        &_strip,        maxParams: 0},
	{"lstrip",       &_lstrip,       maxParams: 0},
	{"rstrip",       &_rstrip,       maxParams: 0},
	{"replace",      &_replace,      maxParams: 2},
	{"startsWith",   &_startsWith,   maxParams: 1},
	{"endsWith",     &_endsWith,     maxParams: 1},
	{"istartsWith",  &_istartsWith,  maxParams: 1},
	{"iendsWith",    &_iendsWith,    maxParams: 1}
];

uword _toRawUnicode(CrocThread* t)
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

uword _toRawAscii(CrocThread* t)
{
	checkStringParam(t, 0);
	auto str = getStringObj(t, 0);
	
	// Take advantage of the fact that in UTF-8, codepoint length == data length iff all codepoints <= 0x7f -- valid ASCII
	if(str.length != str.cpLength)
		throwStdException(t, "ValueException", "Cannot convert string with codepoints higher than U+0007F to ASCII");

	CrocMemblock* ret;

	if(optParam(t, 1, CrocValue.Type.Memblock))
	{
		ret = getMemblock(t, 1);
		dup(t, 1);
		pushNull(t);
		pushString(t, "u8");
		methodCall(t, -3, "type", 0);
		lenai(t, 1, str.length);
	}
	else
	{
		newMemblock(t, "u8", str.length);
		ret = getMemblock(t, -1);
	}

	(cast(char*)ret.data.ptr)[0 .. str.length] = str.toString()[];
	push(t, CrocValue(ret));
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

	pushInt(t, safeCode(t, "exceptions.ValueException", Integer.toInt(src, base)));
	return 1;
}

uword _toFloat(CrocThread* t)
{
	pushFloat(t, safeCode(t, "exceptions.ValueException", Float.toFloat(checkStringParam(t, 0))));
	return 1;
}

uword _isAscii(CrocThread* t)
{
	checkStringParam(t, 0);
	auto str = getStringObj(t, 0);
	// Take advantage of the fact that we're using UTF-8... ASCII strings will have a codepoint length
	// exactly equal to their data length
	pushBool(t, str.length == str.cpLength);
	return 1;
}

uword _compare(CrocThread* t)
{
	pushInt(t, scmp(checkStringParam(t, 0), checkStringParam(t, 1)));
	return 1;
}

uword _icompare(CrocThread* t)
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

uword _find(CrocThread* t)
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

uword _ifind(CrocThread* t)
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

uword _rfind(CrocThread* t)
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

uword _irfind(CrocThread* t)
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

uword _toLower(CrocThread* t)
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

uword _toUpper(CrocThread* t)
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

uword _vsplit(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	auto src = checkStringParam(t, 0);
	uword num = 0;

	if(numParams > 0)
	{
		foreach(piece; src.patterns(checkStringParam(t, 1)))
		{
			pushString(t, piece);
			num++;

			if(num > VSplitMax)
				throwStdException(t, "ValueException", "Too many (>{}) parts when splitting string", VSplitMax);
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

				if(num > VSplitMax)
					throwStdException(t, "ValueException", "Too many (>{}) parts when splitting string", VSplitMax);
			}
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
	auto c = Utf.decode(s.toString()[cast(uword)realIdx .. $], ate);
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

	auto tmp = Utf.cropRight(s.toString[0 .. cast(uword)realIdx - 1]);
	uint ate = void;
	auto c = Utf.decode(s.toString()[tmp.length .. $], ate);

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
	pushBool(t, .startsWith(checkStringParam(t, 0), checkStringParam(t, 1)));
	return 1;
}

uword _endsWith(CrocThread* t)
{
	pushBool(t, .endsWith(checkStringParam(t, 0), checkStringParam(t, 1)));
	return 1;
}

uword _istartsWith(CrocThread* t)
{
	char[64] buf1 = void;
	char[64] buf2 = void;
	auto s1 = Uni.toFold(checkStringParam(t, 0), buf1);
	auto s2 = Uni.toFold(checkStringParam(t, 1), buf2);

	pushBool(t, .startsWith(s1, s2));
	return 1;
}

uword _iendsWith(CrocThread* t)
{
	char[64] buf1 = void;
	char[64] buf2 = void;
	auto s1 = Uni.toFold(checkStringParam(t, 0), buf1);
	auto s2 = Uni.toFold(checkStringParam(t, 1), buf2);

	pushBool(t, .endsWith(s1, s2));
	return 1;
}

version(CrocBuiltinDocs)
{
	const Docs[] _globalFuncDocs =
	[
		{kind: "function", name: "string.fromRawUnicode", docs:
		"Converts data stored in a memblock into a string. The given memblock must be of type `u8`, `u16`, or `u32`.
		If it's `u8`, it must contain UTF-8 data; if it's `u16`, it must contain UTF-16 data; and if it's `u32`, it
		must contain UTF-32 data. You can specify only a slice of the memblock to convert into a string with the `lo`
		and `hi` parameters; the default behavior is to convert the entire memblock. If the data is invalid Unicode,
		an exception will be thrown. Returns the converted string.",
		params: [Param("mb", "memblock"), Param("lo", "int", "0"), Param("hi", "int", "#mb")]},

		{kind: "function", name: "string.fromRawAscii", docs:
		"Similar to `fromRawUnicode`, except converts a memblock containing ASCII data into a string. The memblock
		must be of type `u8`. Any bytes above U+0007F are turned into the Unicode replacement character, U+0001A.
		Returns the converted string.",
		params: [Param("mb", "memblock"), Param("lo", "int", "0"), Param("hi", "int", "#mb")]},
	];

	const Docs[] _methodFuncDocs =
	[
		{kind: "function", name: "s.toRawUnicode", docs:
		"Converts a string into a memblock containing Unicode-encoded data. The `bits` parameter determines which
		encoding to use. It defaults to 8, which means the resulting memblock will be filled with a UTF-8 encoding of
		`s`, and its type will be `u8`. The other two valid values are 16, which will encode UTF-16 data in a memblock
		of type `u16`, and 32, which will encode UTF-32 data in a memblock of type `u32`.

		You may optionally pass a memblock as the second parameter to be used as the destination memblock. This way you
		can reuse a memblock as a conversion buffer to avoid memory allocations. The memblock's type will be set
		appropriately and its data will be replaced by the encoded string data.

		Returns the memblock containing the encoded string data, either a new memblock if `mb` is `null`, or `mb`
		otherwise.",
		params: [Param("bits", "int", "8"), Param("mb", "memblock", "null")]},

		{kind: "function", name: "s.toRawAscii", docs:
		"Similar to `toRawUnicode`, except encodes `s` as ASCII. `s` must not contain any codepoints above U+0007F; that
		is, `s.isAscii()` must return true for this method to work.

		Just like `toRawUnicode` you can pass a memblock as a destination buffer. Its type will be set to `u8`.

		Returns the memblock containing the encoded string data, either a new memblock if `mb` is `null`, or `mb`
		otherwise.",
		params: [Param("mb", "memblock", "null")]},

		{kind: "function", name: "s.opApply", docs:
		"This function allows you to iterate over the characters of a string with a `foreach` loop.

{{{
#!croc
foreach(i, v; \"hello\")
	writeln(\"string[\", i, \"] = \", v)

foreach(i, v; \"hello\", \"reverse\")
	writeln(\"string[\", i, \"] = \", v)
}}}

		As this example shows, if you pass \"reverse\" to the '''`opApply`''' function, either directly or as the second
		part of the `foreach` container, the iteration will go in reverse, starting at the end of the string.",
		params: [Param("reverse", "string", "null")]},

		{kind: "function", name: "s.join", docs:
		"The inverse of the `split` method. This joins together the elements of `arr` using `s` as the separator. The
		elements of `arr` must all be characters or strings. If `s` is the empty string, this just concatenates all the
		elements of `arr` together. If `#arr` is 0, returns the empty string. If `#arr` is 1, returns `arr[0]` as a string
		(so a single character will be converted to a string). Otherwise, returns the elements joined sequentially with the
		separator (`s`) between each pair of arguments. So \"`\".\".join([\"apple\", \"banana\", \"orange\"])`\" will yield
		the string `\"apple.banana.orange\"`.",
		params: [Param("arr", "array")]},

		{kind: "function", name: "s.vjoin", docs:
		"Similar to `join`, but joins its list of variadic parameters instead of an array. The functionality is otherwise
		identical. So \"`\".\".join(\"apple\", \"banana\", \"orange\")`\" will yield the string `\"apple.banana.orange\"`.",
		params: [Param("vararg", "vararg")]},

		{kind: "function", name: "s.isAscii", docs:
		"Returns a bool indicating whether or not this string is pure ASCII, that is, whether or not all the codepoints in it
		are less than or equal to U+0007F."},

		{kind: "function", name: "s.toInt", docs:
		"Converts the string into an integer. If the string does not follow the format of an integer, an exception will be
		thrown. The optional `base` parameter defaults to 10, but you can use any base between 2 and 36 inclusive.",
		params: [Param("base", "int", "10")]},
		
		{kind: "function", name: "s.toFloat", docs:
		"Converts the string into a float. If the string does not follow the format of a float, an exception will be thrown."},
		
		{kind: "function", name: "s.compare", docs:
		"Compares the string to the string `other`, and returns an integer. If `s` is less than (alphabetically) `other`, the
		return is negative; if they are the same, the return is 0; and otherwise, the return is positive. This does not perform
		language-sensitive collation; this is a pure codepoint comparison. Note that the exact same functionality can be
		achieved by using the `<=>` operator on two strings.",
		params: [Param("other", "string")]},

		{kind: "function", name: "s.icompare", docs:
		"The same as `compare`, but case-insensitive, so \"foo\", \"Foo\", and \"FOO\" will all compare equal, for instance.",
		params: [Param("other", "string")]},
		
		{kind: "function", name: "s.find", docs:
		"Searches for an occurence of `sub` in `s`. `sub` can be either a string or a single character. The search starts from
		`start` (which defaults to the first character) and goes right. If `sub` is found, this function returns the integer
		index of the occurrence in the string, with 0 meaning the first character. Otherwise, if `sub` cannot be found, `#s`
		is returned.",
		params: [Param("sub", "string|char"), Param("start", "int", "0")]},

		{kind: "function", name: "s.ifind", docs:
		"The same as `find`, but case-insensitive.",
		params: [Param("sub", "string|char"), Param("start", "int", "0")]},

		{kind: "function", name: "s.rfind", docs:
		"Reverse find. Works similarly to `find`, but the search starts with the character at `start - 1` (which defaults to
		the last character) and goes ''left''. `start` is not included in the search so you can use the result of this function
		as the `start` parameter to successive calls. If `sub` is found, this function returns the integer index of the occurrence
		in the string, with 0 meaning the first character. Otherwise, if `sub` cannot be found, `#s` is returned.",
		params: [Param("sub", "string|char"), Param("start", "int", "#s")]},

		{kind: "function", name: "s.irfind", docs:
		"The same as `rfind`, but case-insensitive.",
		params: [Param("sub", "string|char"), Param("start", "int", "#s")]},
		
		{kind: "function", name: "s.toLower", docs:
		"Returns a new string with any uppercase letters converted to lowercase. Non-uppercase letters and non-letters are not
		affected."},
		
		{kind: "function", name: "s.toUpper", docs:
		"Returns a new string with any lowercase letters converted to uppercase. Non-lowercase letters and non-letters are not
		affected."},
		
		{kind: "function", name: "s.repeat", docs:
		"Returns a string which is the concatenation of `n` instances of `s`. So `\"hello\".repeat(3)` will return
		`\"hellohellohello\"`. `n` must be greater than or equal to 0.",
		params: [Param("n", "int")]},
		
		{kind: "function", name: "s.reverse", docs:
		"Returns a string which is the reversal of `s`."},
		
		{kind: "function", name: "s.split", docs:
		"The inverse of the `join` method. Splits `s` into pieces and returns an array of the split pieces. If no parameters are
		given, the splitting occurs at whitespace (spaces, tabs, newlines etc.) and all the whitespace is stripped from the split
		pieces. Thus `\"one\\t\\ttwo\".split()` will return `[\"one\", \"two\"]`. If the `delim` parameter is given, it specifies
		a delimiting string where `s` will be split. Thus `\"one--two--three\".split(\"--\")` will return `[\"one\", \"two\", \"three\"]`.",
		params: [Param("delim", "string", "null")]},

		{kind: "function", name: "s.vsplit", docs:
		"Similar to `split`, but instead of returning an array, returns the split pieces as multiple return values. Thus
		`\"one\\t\\ttwo\".split()` will return `\"one\", \"two\"`. If the string splits into more than 20 pieces, an error will be
		thrown (as returning many values can be a memory problem). Otherwise the behavior is identical to `split`.",
		params: [Param("delim", "string", "null")]},
		
		{kind: "function", name: "s.splitLines", docs:
		"This will split the string at any newline characters (`'\n'`, `'\r'`, or `'\r\n'`). Other whitespace is preserved, and empty
		lines are preserved. This returns an array of strings, each of which holds one line of text."},
		
		{kind: "function", name: "s.vsplitLines", docs:
		"Similar to `splitLines`, but instead of returning an array, returns the split lines as multiple return values. If the string
		splits into more than 20 lines, an error will be thrown. Otherwise the behavior is identical to `splitLines`."},
		
		{kind: "function", name: "s.strip", docs:
		"Strips any whitespace from the beginning and end of the string."},
		
		{kind: "function", name: "s.lstrip", docs:
		"Strips any whitespace from just the beginning of the string."},

		{kind: "function", name: "s.rstrip", docs:
		"Strips any whitespace from just the end of the string."},

		{kind: "function", name: "s.replace", docs:
		"Replaces any occurrences in `s` of the string `from` with the string `to`.",
		params: [Param("from", "string"), Param("to", "string")]},
		
		{kind: "function", name: "s.startsWith", docs:
		"Returns a bool of whether or not `s` starts with the substring `other`. This is case-sensitive.",
		params: [Param("other", "string")]},
		
		{kind: "function", name: "s.endsWith", docs:
		"Returns a bool of whether or not `s` ends with the substring `other`. This is case-sensitive.",
		params: [Param("other", "string")]},

		{kind: "function", name: "s.istartsWith", docs:
		"Returns a bool of whether or not `s` starts with the substring `other`. This is case-insensitive.",
		params: [Param("other", "string")]},

		{kind: "function", name: "s.iendsWith", docs:
		"Returns a bool of whether or not `s` ends with the substring `other`. This is case-insensitive.",
		params: [Param("other", "string")]}
	];
}