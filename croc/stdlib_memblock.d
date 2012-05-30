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
			registerField(t, _opApplyFunc);

			field(t, -1, "opCatAssign"); fielda(t, -2, "append");
		setTypeMT(t, CrocValue.Type.Memblock);

		return 0;
	});

	importModuleNoNS(t, "memblock");
}

version(CrocBuiltinDocs) void docMemblockLib(CrocThread* t)
{
	pushGlobal(t, "memblock");

	scope doc = new CrocDoc(t, __FILE__);
	doc.push(Docs("module", "memblock",
	`The memblock library provides built-in methods for the \tt{memblock} type, as well as the only means to actually create memblocks.`));

	docFields(t, doc, _globalFuncDocs);

	getTypeMT(t, CrocValue.Type.Memblock);
		docFields(t, doc, _methodFuncDocs);
	pop(t);

	doc.pop(-1);

	pop(t);
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
	{"toString",     &_toString,           maxParams: 0},
	{"dup",          &_dup,                maxParams: 0},
	{"fill",         &_fill,               maxParams: 1},
	{"readInt8",     &_rawRead!(byte),     maxParams: 1},
	{"readInt16",    &_rawRead!(short),    maxParams: 1},
	{"readInt32",    &_rawRead!(int),      maxParams: 1},
	{"readInt64",    &_rawRead!(long),     maxParams: 1},
	{"readUInt8",    &_rawRead!(ubyte),    maxParams: 1},
	{"readUInt16",   &_rawRead!(ushort),   maxParams: 1},
	{"readUInt32",   &_rawRead!(uint),     maxParams: 1},
	{"readUInt64",   &_rawRead!(ulong),    maxParams: 1},
	{"readFloat32",  &_rawRead!(float),    maxParams: 1},
	{"readFloat64",  &_rawRead!(double),   maxParams: 1},
	{"writeInt8",    &_rawWrite!(byte),    maxParams: 1},
	{"writeInt16",   &_rawWrite!(short),   maxParams: 1},
	{"writeInt32",   &_rawWrite!(int),     maxParams: 1},
	{"writeInt64",   &_rawWrite!(long),    maxParams: 1},
	{"writeUInt8",   &_rawWrite!(ubyte),   maxParams: 1},
	{"writeUInt16",  &_rawWrite!(ushort),  maxParams: 1},
	{"writeUInt32",  &_rawWrite!(uint),    maxParams: 1},
	{"writeUInt64",  &_rawWrite!(ulong),   maxParams: 1},
	{"writeFloat32", &_rawWrite!(float),   maxParams: 1},
	{"writeFloat64", &_rawWrite!(double),  maxParams: 1},
	{"copy",         &_copy,               maxParams: 4},
	{"opEquals",     &_opEquals,           maxParams: 1},
	{"opCmp",        &_opCmp,              maxParams: 1},
	{"opCat",        &_opCat,              maxParams: 1},
	{"opCatAssign",  &_opCatAssign}
];

const RegisterFunc _opApplyFunc = {"opApply", &_opApply, maxParams: 1, numUpvals: 2};

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

uword _copy(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto dst = getMemblock(t, 0);
	auto dstOffs = checkIntParam(t, 1);
	checkParam(t, 2, CrocValue.Type.Memblock);
	auto src = getMemblock(t, 2);
	auto srcOffs = checkIntParam(t, 3);
	auto size = checkIntParam(t, 4);

	if     (size < 0 || size > uword.max)             throwStdException(t, "RangeException",  "Invalid size: {}", size);
	else if(dstOffs < 0 || dstOffs > dst.data.length) throwStdException(t, "BoundsException", "Invalid destination offset {} (memblock length: {})", dstOffs, dst.data.length);
	else if(srcOffs < 0 || srcOffs > src.data.length) throwStdException(t, "BoundsException", "Invalid source offset {} (memblock length: {})", srcOffs, src.data.length);
	else if(dstOffs + size > dst.data.length)         throwStdException(t, "BoundsException", "Copy size exceeds size of destination memblock");
	else if(srcOffs + size > src.data.length)         throwStdException(t, "BoundsException", "Copy size exceeds size of source memblock");

	auto srcPtr = src.data.ptr + srcOffs;
	auto dstPtr = dst.data.ptr + dstOffs;

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
	checkParam(t, 1, CrocValue.Type.Memblock);

	if(opis(t, 0, 1))
		pushBool(t, true);
	else
		pushBool(t, mb.data == getMemblock(t, 1).data);

	return 1;
}

uword _opCmp(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	checkParam(t, 1, CrocValue.Type.Memblock);

	if(opis(t, 0, 1))
		pushInt(t, 0);
	else
	{
		auto mb = getMemblock(t, 0);
		auto len = mb.data.length;
		auto other = getMemblock(t, 1);
		auto otherLen = other.data.length;
		auto l = .min(len, otherLen);
		auto cmp = memcmp(mb.data.ptr, other.data.ptr, l);

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
	checkParam(t, 1, CrocValue.Type.Memblock);
	push(t, CrocValue(memblock.cat(t.vm.alloc, getMemblock(t, 0), getMemblock(t, 1))));
	return 1;
}

uword _opCatAssign(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Memblock);
	auto mb = getMemblock(t, 0);

	if(!mb.ownData)
		throwStdException(t, "ValueException", "Attempting to append to a memblock which does not own its data");

	checkAnyParam(t, 1);
	auto numParams = stackSize(t) - 1;
	ulong totalLen = mb.data.length;

	for(uword i = 1; i <= numParams; i++)
	{
		checkParam(t, i, CrocValue.Type.Memblock);
		totalLen += getMemblock(t, i).data.length;
	}

	if(totalLen > uword.max)
		throwStdException(t, "RangeException", "Invalid size ({})", totalLen);

	auto oldLen = mb.data.length;
	memblock.resize(t.vm.alloc, mb, cast(uword)totalLen);

	uword j = oldLen;

	for(uword i = 1; i <= numParams; i++)
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

	return 0;
}

version(CrocBuiltinDocs)
{
	Docs[] _globalFuncDocs = 
	[
		{kind: "function", name: "new", docs:
		`Creates a new memblock.

		\param[size] is the size of the memblock to create, in bytes. Can be 0.
		\param[fill] is the value to fill each byte of the memblock with. Defaults to 0. The value will be wrapped to the
		range of an unsigned byte.

		\throws[exceptions.RangeException] if \tt{size} is invalid (negative or too large to be represented).`,
		params: [Param("size", "int"), Param("fill", "int", "0")]}
	];

	Docs[] _methodFuncDocs =
	[
		{kind: "function", name: "toString", docs:
		`\returns a string representation of this memblock in the form "memblock[contents]".

		For example, \tt{memblock.new(3, 10).toString()} would give the string \tt{"memblock[10, 10, 10]"}.`},

		{kind: "function", name: "dup", docs:
		`\returns a duplicate of this memblock.

		The new memblock will have the same length and this memblock's data will be copied into it. The new memblock
		will own its data, regardless of whether or not this memblock does.`},

		{kind: "function", name: "fill", docs:
		`Fills every byte of this memblock with the given value (wrapped to the range of an unsigned byte).

		\param[val] the value to fill the memblock with.`,
		params: [Param("val", "int")]},

		{kind: "function", name: "readInt8", docs:
		`These functions all read a numerical value of the given type from the byte offset \tt{offs}.

		The "Int" versions read a signed integer of the given number of bits. The "Uint" versions read an unsigned integer
		of the given number of bits. Note that \tt{readUInt64} will return the same values as \tt{readInt64} as Croc's \tt{int}
		type is a signed 64-bit integer, and thus cannot represent the range of unsigned 64-bit integers. It is included for
		completion.

		The "Float" versions read an IEEE 754 floating point number. \tt{readFloat32} reads a single-precision float while
		\tt{readFloat64} reads a double-precision float.

		\param[offs] the byte offset from where the value should be read. Can be negative to mean from the end of the memblock.
		\returns the value read, as either an \tt{int} or a \tt{float}, depending on the function.
		\throws[exceptions.BoundsException] if \tt{offs < 0 || offs >= #this - (size of value)}.

		\see \link{Vector} for a typed numerical array type which may suit your needs better than raw memblock access.`,
		params: [Param("offs", "int")]},

		{kind: "function", name: "readInt16",   docs: "ditto", params: [Param("offs", "int")]},
		{kind: "function", name: "readInt32",   docs: "ditto", params: [Param("offs", "int")]},
		{kind: "function", name: "readInt64",   docs: "ditto", params: [Param("offs", "int")]},
		{kind: "function", name: "readUInt8",   docs: "ditto", params: [Param("offs", "int")]},
		{kind: "function", name: "readUInt16",  docs: "ditto", params: [Param("offs", "int")]},
		{kind: "function", name: "readUInt32",  docs: "ditto", params: [Param("offs", "int")]},
		{kind: "function", name: "readUInt64",  docs: "ditto", params: [Param("offs", "int")]},
		{kind: "function", name: "readFloat32", docs: "ditto", params: [Param("offs", "int")]},
		{kind: "function", name: "readFloat64", docs: "ditto", params: [Param("offs", "int")]},

		{kind: "function", name: "writeInt8", docs:
		`These functions all write the numerical value \tt{val} of the given type to the byte offset \tt{offs}.

		The "Int" versions write a signed integer of the given number of bits. The "Uint" versions write an unsigned integer
		of the given number of bits. Note that \tt{writeUInt64} will in fact write an unsigned 64-bit integer, even though
		Croc's \tt{int} type is a signed 64-bit integer.

		The "Float" versions write an IEEE 754 floating point number. \tt{writeFloat32} writes a single-precision float while
		\tt{writeFloat64} writes a double-precision float.

		\param[offs] the byte offset to which the value should be written. Can be negative to mean from the end of the memblock.
		\param[val] the value to write.
		\throws[exceptions.BoundsException] if \tt{offs < 0 || offs >= #this - (size of value)}.

		\see \link{Vector} for a typed numerical array type which may suit your needs better than raw memblock access.`,
		params: [Param("offs", "int"), Param("val", "int")]},

		{kind: "function", name: "writeInt16",   docs: "ditto", params: [Param("offs", "int"), Param("val", "int")]},
		{kind: "function", name: "writeInt32",   docs: "ditto", params: [Param("offs", "int"), Param("val", "int")]},
		{kind: "function", name: "writeInt64",   docs: "ditto", params: [Param("offs", "int"), Param("val", "int")]},
		{kind: "function", name: "writeUInt8",   docs: "ditto", params: [Param("offs", "int"), Param("val", "int")]},
		{kind: "function", name: "writeUInt16",  docs: "ditto", params: [Param("offs", "int"), Param("val", "int")]},
		{kind: "function", name: "writeUInt32",  docs: "ditto", params: [Param("offs", "int"), Param("val", "int")]},
		{kind: "function", name: "writeUInt64",  docs: "ditto", params: [Param("offs", "int"), Param("val", "int")]},
		{kind: "function", name: "writeFloat32", docs: "ditto", params: [Param("offs", "int"), Param("val", "int|float")]},
		{kind: "function", name: "writeFloat64", docs: "ditto", params: [Param("offs", "int"), Param("val", "int|float")]},

		{kind: "function", name: "copy", docs:
		`Copies a block of memory from one memblock to another, or within the same memblock. Also handles overlapping copies.

		\param[dstOffs] the byte offset in this memblock to where the data should be copied. May \b{not} be negative.
		\param[src] the memblock from which the data should be copied. Can be the same memblock as \tt{this}.
		\param[srcOffs] the byte offset in the source memblock from which the data should be copied. May \b{not} be negative.
		\param[size] the number of bytes to copy. 0 is an acceptable value.

		\throws[exceptions.RangeException] if the \tt{size} parameter is negative.
		\throws[exceptions.BoundsException] if \tt{dstOffs} or \tt{srcOffs} are invalid indices into their respective memblocks,
			or if either the source or destination ranges extend past the ends of their respective memblocks.`,
		params: [Param("dstOffs", "int"), Param("src", "memblock"), Param("srcOffs", "int"), Param("size", "int")]},

		{kind: "function", name: "opEquals", docs:
		`Compares two memblocks for exact data equality.

		\returns \tt{true} if both memblocks are the same length and contain the exact same data. Returns \tt{false} otherwise.`,
		params: [Param("other", "memblock")]},

		{kind: "function", name: "opCmp", docs:
		`Compares the contents of two memblocks for ordering. Ordering works just like array or string ordering.

		\returns a negative integer if \tt{this} compares before \tt{other}, a positive integer if \tt{this} compares after
		\tt{other}, and 0 if \tt{this} and \tt{other} have identical contents.`,
		params: [Param("other", "memblock")]},

		{kind: "function", name: "opApply", docs:
		`Allows you to iterate over the contents of a memblock with \tt{foreach} loops.

		You can iterate forwards (the default) or backwards:

\code
local m = memblock.new(3)
m[1] = 1
m[2] = 2
m[3] = 3

foreach(val; m)
	writeln(val) // prints 1 through 3

foreach(val; m, "reverse")
	writeln(val) // prints 3 through 1
\endcode

		\param[mode] The iteration mode. Defaults to null, which means forwards; if passed "reverse", iterates backwards.`,
		params: [Param("mode", "string", "null")]},

		{kind: "function", name: "opCat", docs:
		`Concatenates two memblocks, returning a new memblock whose contents are a concatenation of the two sources.

		\param[other] the second memblock in the concatenation.
		\returns a new memblock whose contents are a concatenation of \tt{this} followed by \tt{other}.`,
		params: [Param("other", "memblock")]},

		{kind: "function", name: "opCatAssign", docs:
		`Appends memblocks to the end of this memblock, resizing this memblock to hold all the contents and copying the contents
		from the source memblocks.

		\param[vararg] the memblocks to be appended.
		\throws[exceptions.ValueException] if \tt{this} does not own its data (and therefore cannot be resized).
		\throws[exceptions.RangeException] if the total length of \tt{this} after appending would be too large to be represented.`,
		params: [Param("vararg", "vararg")]},
	];
}