/******************************************************************************
This module contains the 'memblock' standard library.

License:
Copyright (c) 2011 Jarrett Billingsley

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

module croc.stdlib_memblock;

import tango.core.Traits;
import tango.math.Math;
import tango.stdc.string;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.stdlib_utils;
import croc.types;
import croc.types_memblock;
import croc.utils;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initMemblockLib(CrocThread* t)
{
	makeModule(t, "memblock", function uword(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);

		newNamespace(t, "memblock");
			registerFields(t, _methodFuncs);

				newFunction(t, &_iterator, "memblock.iterator");
				newFunction(t, &_iteratorReverse, "memblock.iteratorReverse");
			registerField(t, 1, "opApply", &_opApply, 2);

			field(t, -1, "opCatAssign"); fielda(t, -2, "append");
		setTypeMT(t, CrocValue.Type.Memblock);

		return 0;
	});

	importModuleNoNS(t, "memblock");
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

const RegisterFunc[] _globalFuncs =
[
	{"new", &_new, maxParams: 2},
];

uword _new(CrocThread* t)
{
	auto size = checkIntParam(t, 1);

	if(size < 0 || size > uword.max)
		throwStdException(t, "RangeException", "Invalid size ({})", size);

	bool haveFill = isValidIndex(t, 2);

	newMemblock(t, cast(uword)size);

	if(haveFill)
		getMemblock(t, -1).data[] = cast(ubyte)checkIntParam(t, 2);

	return 1;
}

const RegisterFunc[] _methodFuncs =
[
	{"toString",    &_toString,          maxParams: 0},
	{"dup",         &_dup,               maxParams: 0},
	{"fill",        &_fill,              maxParams: 1},
	{"copyRange",   &_copyRange,         maxParams: 5},
	{"readByte",    &_rawRead!(byte),    maxParams: 1},
	{"readShort",   &_rawRead!(short),   maxParams: 1},
	{"readInt",     &_rawRead!(int),     maxParams: 1},
	{"readLong",    &_rawRead!(long),    maxParams: 1},
	{"readUByte",   &_rawRead!(ubyte),   maxParams: 1},
	{"readUShort",  &_rawRead!(ushort),  maxParams: 1},
	{"readUInt",    &_rawRead!(uint),    maxParams: 1},
	{"readULong",   &_rawRead!(ulong),   maxParams: 1},
	{"readFloat",   &_rawRead!(float),   maxParams: 1},
	{"readDouble",  &_rawRead!(double),  maxParams: 1},
	{"writeByte",   &_rawWrite!(byte),   maxParams: 2},
	{"writeShort",  &_rawWrite!(short),  maxParams: 2},
	{"writeInt",    &_rawWrite!(int),    maxParams: 2},
	{"writeLong",   &_rawWrite!(long),   maxParams: 2},
	{"writeUByte",  &_rawWrite!(ubyte),  maxParams: 2},
	{"writeUShort", &_rawWrite!(ushort), maxParams: 2},
	{"writeUInt",   &_rawWrite!(uint),   maxParams: 2},
	{"writeULong",  &_rawWrite!(ulong),  maxParams: 2},
	{"writeFloat",  &_rawWrite!(float),  maxParams: 2},
	{"writeDouble", &_rawWrite!(double), maxParams: 2},
	{"rawCopy",     &_rawCopy,           maxParams: 4},
	{"opEquals",    &_opEquals,          maxParams: 1},
	{"opCmp",       &_opCmp,             maxParams: 1},
	{"opCat",       &_opCat,             maxParams: 1},
	{"opCat_r",     &_opCat_r,           maxParams: 1},
	{"opCatAssign", &_opCatAssign}
];

uword _toString(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);

	auto b = StrBuffer(t);
	b.addString("memblock[");

	foreach(i, val; mb.data)
	{
		if(i > 0)
			b.addString(", ");
			
		pushFormat(t, "{}", val);
		b.addTop();
	}

	b.addString("]");
	b.finish();
	return 1;
}

uword _dup(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);
	
	newMemblock(t, mb.data.length);
	getMemblock(t, -1).data[] = mb.data[];
	return 1;
}

uword _fill(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);
	mb.data[] = cast(ubyte)checkIntParam(t, 1);
	return 0;
}

uword _copyRange(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);
	auto lo = optIntParam(t, 1, 0);
	auto hi = optIntParam(t, 2, mb.data.length);

	if(lo < 0)
		lo += mb.data.length;

	if(hi < 0)
		hi += mb.data.length;

	if(lo < 0 || lo > hi || hi > mb.data.length)
		throwStdException(t, "BoundsException", "Invalid destination slice indices: {} .. {} (length: {})", lo, hi, mb.data.length);

	checkParam(t, 3, CrocValue.Type.Memblock);
	auto other = getMemblock(t, 3);

	auto lo2 = optIntParam(t, 4, 0);
	auto hi2 = optIntParam(t, 5, lo2 + (hi - lo));

	if(lo2 < 0)
		lo2 += other.data.length;

	if(hi2 < 0)
		hi2 += other.data.length;

	if(lo2 < 0 || lo2 > hi2 || hi2 > other.data.length)
		throwStdException(t, "BoundsException", "Invalid source slice indices: {} .. {} (length: {})", lo2, hi2, other.data.length);

	if((hi - lo) != (hi2 - lo2))
		throwStdException(t, "ValueException", "Destination length ({}) and source length({}) do not match", hi - lo, hi2 - lo2);

	memcpy(&mb.data[cast(uword)lo], &other.data[cast(uword)lo2], cast(uword)(hi - lo));

	dup(t, 0);
	return 1;
}

uword _rawRead(T)(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);

	word maxIdx = mb.data.length < T.sizeof ? -1 : mb.data.length - T.sizeof;
	auto idx = checkIntParam(t, 1);

	if(idx < 0)
		idx += mb.data.length;

	if(idx < 0 || idx > maxIdx)
		throwStdException(t, "BoundsException", "Invalid index '{}'", idx);

	static if(isIntegerType!(T))
		pushInt(t, cast(crocint)*(cast(T*)(mb.data.ptr + idx)));
	else
		pushFloat(t, cast(crocfloat)*(cast(T*)(mb.data.ptr + idx)));

	return 1;
}

uword _rawWrite(T)(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);

	word maxIdx = mb.data.length < T.sizeof ? -1 : mb.data.length - T.sizeof;
	auto idx = checkIntParam(t, 1);

	if(idx < 0)
		idx += mb.data.length;

	if(idx < 0 || idx > maxIdx)
		throwStdException(t, "BoundsException", "Invalid index '{}'", idx);

	static if(isIntegerType!(T))
		auto val = checkIntParam(t, 2);
	else
		auto val = checkNumParam(t, 2);

	*(cast(T*)(mb.data.ptr + idx)) = cast(T)val;

	return 0;
}

uword _rawCopy(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto dst = getMemblock(t, 0);
	auto dstPos = checkIntParam(t, 1);
	checkParam(t, 2, CrocValue.Type.Memblock);
	auto src = getMemblock(t, 2);
	auto srcPos = checkIntParam(t, 3);
	auto size = checkIntParam(t, 4);

	if     (dstPos < 0 || dstPos > dst.data.length) throwStdException(t, "BoundsException", "Invalid destination position {} (memblock length: {})", dstPos, dst.data.length);
	else if(srcPos < 0 || srcPos > src.data.length) throwStdException(t, "BoundsException", "Invalid source position {} (memblock length: {})", srcPos, src.data.length);
	else if(size < 0 || size > uword.max)           throwStdException(t, "RangeException",  "Invalid size: {}", size);
	else if(dstPos + size > dst.data.length)        throwStdException(t, "BoundsException", "Copy size exceeds size of destination memblock");
	else if(srcPos + size > src.data.length)        throwStdException(t, "BoundsException", "Copy size exceeds size of source memblock");

	auto srcPtr = src.data.ptr + srcPos;
	auto dstPtr = dst.data.ptr + dstPos;

	if(abs(dstPtr - srcPtr) < size)
		memmove(dstPtr, srcPtr, cast(uword)size);
	else
		memcpy(dstPtr, srcPtr, cast(uword)size);

	return 0;
}

uword _opEquals(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);
	checkAnyParam(t, 1);

	if(!isMemblock(t, 1))
	{
		pushTypeString(t, 1);
		throwStdException(t, "TypeException", "Attempting to compare a memblock to a '{}'", getString(t, -1));
	}

	if(opis(t, 0, 1))
		pushBool(t, true);
	else
		pushBool(t, mb.data == getMemblock(t, 1).data);

	return 1;
}

uword _opCmp(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);
	auto len = mb.data.length;
	checkAnyParam(t, 1);

	if(!isMemblock(t, 1))
	{
		pushTypeString(t, 1);
		throwStdException(t, "TypeException", "Attempting to compare a memblock to a '{}'", getString(t, -1));
	}
	
	if(opis(t, 0, 1))
		pushInt(t, 0);
	else
	{
		auto other = getMemblock(t, 1);

		auto otherLen = other.data.length;
		auto l = .min(len, otherLen);
		
		auto a = (cast(ubyte[])mb.data)[0 .. l];
		auto b = (cast(ubyte[])other.data)[0 .. l];
		auto cmp = typeid(ubyte[]).compare(&a, &b);

		if(cmp == 0)
			pushInt(t, Compare3(len, otherLen));
		else
			pushInt(t, cmp);
	}

	return 1;
}

uword _iterator(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);
	auto index = checkIntParam(t, 1) + 1;

	if(index >= mb.data.length)
		return 0;

	pushInt(t, index);
	pushInt(t, mb.data[cast(uword)index]);
	return 2;
}

uword _iteratorReverse(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);
	auto index = checkIntParam(t, 1) - 1;

	if(index < 0)
		return 0;

	pushInt(t, index);
	pushInt(t, mb.data[cast(uword)index]);
	return 2;
}

uword _opApply(CrocThread* t)
{
	const Iter = 0;
	const IterReverse = 1;

	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);

	if(optStringParam(t, 1, "") == "reverse")
	{
		getUpval(t, IterReverse);
		dup(t, 0);
		pushInt(t, mb.data.length);
	}
	else
	{
		getUpval(t, Iter);
		dup(t, 0);
		pushInt(t, -1);
	}

	return 3;
}

uword _opCat(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);
	checkAnyParam(t, 1);

	if(isMemblock(t, 1))
		push(t, CrocValue(memblock.cat(t.vm.alloc, mb, getMemblock(t, 1))));
	else
		push(t, CrocValue(memblock.cat(t.vm.alloc, mb, cast(ubyte)checkIntParam(t, 1))));

	return 1;
}

uword _opCat_r(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);
	checkAnyParam(t, 1);

	push(t, CrocValue(memblock.cat_r(t.vm.alloc, cast(ubyte)checkIntParam(t, 1), mb)));
	return 1;
}

uword _opCatAssign(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);
	auto numParams = stackSize(t) - 1;
	checkAnyParam(t, 1);

	if(!mb.ownData)
		throwStdException(t, "ValueException", "Attempting to append to a memblock which does not own its data");

	ulong totalLen = mb.data.length;

	for(uword i = 1; i <= numParams; i++)
	{
		if(isMemblock(t, i))
		{
			auto other = getMemblock(t, i);
			totalLen += other.data.length;
		}
		else
		{
			checkIntParam(t, i);
			totalLen++;
		}
	}

	if(totalLen > uword.max)
		throwStdException(t, "RangeException", "Invalid size ({})", totalLen);

	auto oldLen = mb.data.length;
	memblock.resize(t.vm.alloc, mb, cast(uword)totalLen);

	uword j = oldLen;

	for(uword i = 1; i <= numParams; i++)
	{
		if(isMemblock(t, i))
		{
			if(opis(t, 0, i))
			{
				// special case for when we're appending a memblock to itself; use the old length
				memcpy(&mb.data[j], mb.data.ptr, oldLen);
				j += oldLen;
			}
			else
			{
				auto other = getMemblock(t, i);
				memcpy(&mb.data[j], other.data.ptr, other.data.length);
				j += other.data.length;
			}
		}
		else
		{
			mb.data[j] = cast(ubyte)getInt(t, i);
			j++;
		}
	}

	return 0;
}

	version(CrocBuiltinDocs) Docs memblockOpEquals_docs = {kind: "function", name: "opEquals", docs:
	"Compares two memblocks for equality. Throws an error if the two memblocks are of different types. Returns
	true only if the two memblocks are the same length and have the same contents.",
	params: [Param("other", "memblock")],
	extra: [Extra("section", "Memblock metamethods")]};

	version(CrocBuiltinDocs) Docs memblockOpCmp_docs = {kind: "function", name: "opCmp", docs:
	"Compares two memblocks for equality. Throws an error if the two memblocks are of different types.",
	params: [Param("other", "memblock")],
	extra: [Extra("section", "Memblock metamethods")]};

	version(CrocBuiltinDocs) Docs memblockOpApply_docs = {kind: "function", name: "opApply", docs:
	"This lets you iterate over the elements of memblocks with foreach loops, just like with arrays. Also
	like arrays, you can pass `\"reverse\"` to iterate over the elements backwards.
{{{
#!croc
local m = memblock.range(\"i32\", 1, 6)

foreach(val; m)
	writeln(val) // prints 1 through 5

foreach(val; m, \"reverse\")
	writeln(val) // prints 5 through 1
}}}
	",
	params: [Param("mode", "string", "null")],
	extra: [Extra("section", "Memblock metamethods")]};

	version(CrocBuiltinDocs) Docs memblockToString_docs = {kind: "function", name: "toString", docs:
	"Returns a string representation of this memblock in the form `\"memblock(type)[items]\"`; for example,
	`\"memblock.range(\"i32\", 1, 5).toString()\"` would yield `\"memblock(i32)[1, 2, 3, 4]\"`. If the memblock
	is of type void, then the result will instead be `\"memblock(v)[n bytes]\"`, where ''n'' is the length of
	the memblock.",
	params: [],
	extra: [Extra("section", "Memblock metamethods")]};