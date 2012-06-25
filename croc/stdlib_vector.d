/******************************************************************************
This module contains the implementation of the Vector class defined in
the base library.

License:
Copyright (c) 2012 Jarrett Billingsley

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

module croc.stdlib_vector;

import tango.math.Math;
import tango.stdc.string;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
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

void initVector(CrocThread* t)
{
	CreateClass(t, "Vector", (CreateClass* c)
	{
		c.allocator("allocator", &BasicClassAllocator!(NumFields, Members));

		c.method("constructor",    3, &_constructor);
		c.method("range",          4, &_range);

		c.method("type",           1, &_type);
		c.method("itemSize",       0, &_itemSize);
		c.method("toArray",        2, &_toArray);
		c.method("toString",       0, &_toString);
		c.method("getMemblock",    0, &_getMemblock);

		c.method("dup",            0, &_dup);
		c.method("reverse",        0, &_reverse);
		c.method("sort",           0, &_sort);
		c.method("apply",          1, &_apply);
		c.method("map",            1, &_map);
		c.method("min",            0, &_min);
		c.method("max",            0, &_max);
		c.method("insert",         2, &_insert);
		c.method("pop",            1, &_pop);
		c.method("remove",         2, &_remove);
		c.method("sum",            0, &_sum);
		c.method("product",        0, &_product);
		c.method("copyRange",      5, &_copyRange);
		c.method("fill",           1, &_fill);
		c.method("fillRange",      3, &_fillRange);

		c.method("opEquals",       1, &_opEquals);
		c.method("opCmp",          1, &_opCmp);
		c.method("opLength",       0, &_opLength);
		c.method("opLengthAssign", 1, &_opLengthAssign);
		c.method("opIndex",        1, &_opIndex);
		c.method("opIndexAssign",  2, &_opIndexAssign);
		c.method("opSlice",        2, &_opSlice);

			newFunction(t, &_iterator, "iterator");
			newFunction(t, &_iteratorReverse, "iteratorReverse");
		c.method("opApply",        1, &_opApply, 2);

		c.method("opSerialize",    2, &_opSerialize);
		c.method("opDeserialize",  2, &_opDeserialize);

		c.method("opCat",          1, &_opCat);
		c.method("opCat_r",        1, &_opCat_r);
		c.method("opCatAssign",       &_opCatAssign);

		c.method("opAdd",          1, &_opAdd);
		c.method("opAddAssign",    1, &_opAddAssign);
		c.method("opSub",          1, &_opSub);
		c.method("opSub_r",        1, &_opSub_r);
		c.method("opSubAssign",    1, &_opSubAssign);
		c.method("revSub",         1, &_revSub);
		c.method("opMul",          1, &_opMul);
		c.method("opMulAssign",    1, &_opMulAssign);
		c.method("opDiv",          1, &_opDiv);
		c.method("opDiv_r",        1, &_opDiv_r);
		c.method("opDivAssign",    1, &_opDivAssign);
		c.method("revDiv",         1, &_revDiv);
		c.method("opMod",          1, &_opMod);
		c.method("opMod_r",        1, &_opMod_r);
		c.method("opModAssign",    1, &_opModAssign);
		c.method("revMod",         1, &_revMod);
	});

	field(t, -1, "fillRange");   fielda(t, -2, "opSliceAssign");
	field(t, -1, "opCatAssign"); fielda(t, -2, "append");
	field(t, -1, "opAdd");       fielda(t, -2, "opAdd_r");
	field(t, -1, "opMul");       fielda(t, -2, "opMul_r");

	newGlobal(t, "Vector");
}

version(CrocBuiltinDocs) void docVector(CrocThread* t, CrocDoc doc)
{
// 	pushGlobal(t, "Vector");
// 		doc.push(_classDocs);
// 		docFields(t, doc, _methodDocs);
// 		doc.pop(-1);
// 	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

enum TypeCode : ubyte
{
	i8,
	i16,
	i32,
	i64,
	u8,
	u16,
	u32,
	u64,
	f32,
	f64,
}

static struct TypeStruct
{
	TypeCode code;
	ubyte itemSize;
	ubyte sizeShift;
	char[] name;
}

const TypeStruct[] _typeStructs =
[
	TypeCode.i8:  { TypeCode.i8,  1, 0, "i8"  },
	TypeCode.i16: { TypeCode.i16, 2, 1, "i16" },
	TypeCode.i32: { TypeCode.i32, 4, 2, "i32" },
	TypeCode.i64: { TypeCode.i64, 8, 3, "i64" },
	TypeCode.u8:  { TypeCode.u8,  1, 0, "u8"  },
	TypeCode.u16: { TypeCode.u16, 2, 1, "u16" },
	TypeCode.u32: { TypeCode.u32, 4, 2, "u32" },
	TypeCode.u64: { TypeCode.u64, 8, 3, "u64" },
	TypeCode.f32: { TypeCode.f32, 4, 2, "f32" },
	TypeCode.f64: { TypeCode.f64, 8, 3, "f64" }
];

enum
{
	Data,
	NumFields
}

struct Members
{
	CrocMemblock* m; // redundantly stored here for convenience
	TypeStruct* kind;
	uword itemLength;
}

CrocValue _rawIndex(Members* m, uword idx)
{
	assert(idx < m.itemLength);

	switch(m.kind.code)
	{
		case TypeCode.i8:  return CrocValue(cast(crocint)(cast(byte*)m.m.data.ptr)[idx]);
		case TypeCode.i16: return CrocValue(cast(crocint)(cast(short*)m.m.data.ptr)[idx]);
		case TypeCode.i32: return CrocValue(cast(crocint)(cast(int*)m.m.data.ptr)[idx]);
		case TypeCode.i64: return CrocValue(cast(crocint)(cast(long*)m.m.data.ptr)[idx]);
		case TypeCode.u8:  return CrocValue(cast(crocint)(cast(ubyte*)m.m.data.ptr)[idx]);
		case TypeCode.u16: return CrocValue(cast(crocint)(cast(ushort*)m.m.data.ptr)[idx]);
		case TypeCode.u32: return CrocValue(cast(crocint)(cast(uint*)m.m.data.ptr)[idx]);
		case TypeCode.u64: return CrocValue(cast(crocint)(cast(ulong*)m.m.data.ptr)[idx]);
		case TypeCode.f32: return CrocValue(cast(crocfloat)(cast(float*)m.m.data.ptr)[idx]);
		case TypeCode.f64: return CrocValue(cast(crocfloat)(cast(double*)m.m.data.ptr)[idx]);

		default: assert(false);
	}
}

void _rawIndexAssign(Members* m, uword idx, CrocValue val)
{
	assert(idx < m.itemLength);

	switch(m.kind.code)
	{
		case TypeCode.i8:  return (cast(byte*)m.m.data.ptr)[idx]   = cast(byte)val.mInt;
		case TypeCode.i16: return (cast(short*)m.m.data.ptr)[idx]  = cast(short)val.mInt;
		case TypeCode.i32: return (cast(int*)m.m.data.ptr)[idx]    = cast(int)val.mInt;
		case TypeCode.i64: return (cast(long*)m.m.data.ptr)[idx]   = cast(long)val.mInt;
		case TypeCode.u8:  return (cast(ubyte*)m.m.data.ptr)[idx]  = cast(ubyte)val.mInt;
		case TypeCode.u16: return (cast(ushort*)m.m.data.ptr)[idx] = cast(ushort)val.mInt;
		case TypeCode.u32: return (cast(uint*)m.m.data.ptr)[idx]   = cast(uint)val.mInt;
		case TypeCode.u64: return (cast(ulong*)m.m.data.ptr)[idx]  = cast(ulong)val.mInt;
		case TypeCode.f32: return (cast(float*)m.m.data.ptr)[idx]  = val.type == CrocValue.Type.Int ? cast(float)val.mInt  : cast(float)val.mFloat;
		case TypeCode.f64: return (cast(double*)m.m.data.ptr)[idx] = val.type == CrocValue.Type.Int ? cast(double)val.mInt : cast(double)val.mFloat;

		default: assert(false);
	}
}

Members* _getMembers(CrocThread* t, uword slot = 0)
{
	auto ret = checkInstParam!(Members)(t, slot, "Vector");
	assert(ret.m !is null);

	uword len = ret.m.data.length >> ret.kind.sizeShift;

	if(len << ret.kind.sizeShift != ret.m.data.length)
		throwStdException(t, "ValueException", "Vector's underlying memblock length is not an even multiple of its item size");

	ret.itemLength = len;
	return ret;
}

/*word memblockFromDArray(_T)(CrocThread* t, _T[] arr)
{
	alias realType!(_T) T;

	static      if(is(T == byte))   const code = "i8";
	else static if(is(T == ubyte))  const code = "u8";
	else static if(is(T == short))  const code = "i16";
	else static if(is(T == ushort)) const code = "u16";
	else static if(is(T == int))    const code = "i32";
	else static if(is(T == uint))   const code = "u32";
	else static if(is(T == long))   const code = "i64";
	else static if(is(T == ulong))  const code = "u64";
	else static if(is(T == float))  const code = "f32";
	else static if(is(T == double)) const code = "f64";
	else static assert(false, "memblockFromDArray - invalid array type '" ~ typeof(arr).stringof ~ "'");

	auto ret = newMemblock(t, code, arr.length);
	auto data = getMemblock(t, ret).data;
	(cast(_T*)data)[0 .. arr.length] = arr[];
	return ret;
}

word memblockViewDArray(_T)(CrocThread* t, _T[] arr)
{
	alias realType!(_T) T;
	CrocMemblock.TypeStruct* ts = void;

	static      if(is(T == byte))   ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.i8];
	else static if(is(T == ubyte))  ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.u8];
	else static if(is(T == short))  ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.i16];
	else static if(is(T == ushort)) ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.u16];
	else static if(is(T == int))    ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.i32];
	else static if(is(T == uint))   ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.u32];
	else static if(is(T == long))   ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.i64];
	else static if(is(T == ulong))  ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.u64];
	else static if(is(T == float))  ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.f32];
	else static if(is(T == double)) ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.f64];
	else static assert(false, "memblockViewDArray - invalid array type '" ~ typeof(arr).stringof ~ "'");

	return push(t, CrocValue(memblock.createView(t.vm.alloc, ts, cast(void[])arr)));
}

void memblockReviewDArray(_T)(CrocThread* t, word slot, _T[] arr)
{
	mixin(apiCheckNumParams!("1"));
	auto m = getMemblock(t, slot);

	if(m is null)
	{
		pushTypeString(t, slot);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - slot must be a memblock, not a '{}'", getString(t, -1));
	}

	alias realType!(_T) T;
	CrocMemblock.TypeStruct* ts = void;

	static      if(is(T == byte))   ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.i8];
	else static if(is(T == ubyte))  ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.u8];
	else static if(is(T == short))  ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.i16];
	else static if(is(T == ushort)) ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.u16];
	else static if(is(T == int))    ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.i32];
	else static if(is(T == uint))   ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.u32];
	else static if(is(T == long))   ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.i64];
	else static if(is(T == ulong))  ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.u64];
	else static if(is(T == float))  ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.f32];
	else static if(is(T == double)) ts = &CrocMemblock.typeStructs[CrocMemblock.TypeCode.f64];
	else static assert(false, "memblockViewDArray - invalid array type '" ~ typeof(arr).stringof ~ "'");

	memblock.view(t.vm.alloc, m, ts, cast(void[])arr);
} */

uword _constructor(CrocThread* t)
{
	auto self = checkInstParam!(Members)(t, 0, "Vector");
	auto typeCode = checkStringParam(t, 1);

	switch(typeCode)
	{
		case "i8" : self.kind = &_typeStructs[TypeCode.i8];  break;
		case "i16": self.kind = &_typeStructs[TypeCode.i16]; break;
		case "i32": self.kind = &_typeStructs[TypeCode.i32]; break;
		case "i64": self.kind = &_typeStructs[TypeCode.i64]; break;
		case "u8" : self.kind = &_typeStructs[TypeCode.u8];  break;
		case "u16": self.kind = &_typeStructs[TypeCode.u16]; break;
		case "u32": self.kind = &_typeStructs[TypeCode.u32]; break;
		case "u64": self.kind = &_typeStructs[TypeCode.u64]; break;
		case "f32": self.kind = &_typeStructs[TypeCode.f32]; break;
		case "f64": self.kind = &_typeStructs[TypeCode.f64]; break;

		default:
			throwStdException(t, "ValueException", "Invalid type code '{}'", typeCode);
	}

	word fillerSlot = 0;

	if(!isValidIndex(t, 2))
		newMemblock(t, 0);
	else if(isInt(t, 2))
	{
		if(isValidIndex(t, 3))
			fillerSlot = 3;

		auto size = getInt(t, 2);

		if(size < 0 || size > uword.max)
			throwStdException(t, "RangeException", "Invalid size ({})", size);

		newMemblock(t, cast(uword)size * self.kind.itemSize);
	}
	else if(isArray(t, 2))
	{
		newMemblock(t, cast(uword)len(t, 2) * self.kind.itemSize);
		fillerSlot = 2;
	}
	else
		paramTypeError(t, 2, "int|array");

	self.m = getMemblock(t, -1);
	pop(t);

	if(fillerSlot > 0)
	{
		dup(t, 0);
		pushNull(t);
		dup(t, fillerSlot);
		methodCall(t, -3, "fill", 0);
	}

	return 0;
}

void rangeImpl(alias check, T)(CrocThread* t, char[] type)
{
	auto numParams = stackSize(t) - 1;
	T v1 = check(t, 2);
	T v2 = void;
	T step = 1;

	if(numParams == 2)
	{
		v2 = v1;
		v1 = 0;
	}
	else if(numParams == 3)
		v2 = check(t, 3);
	else
	{
		v2 = check(t, 3);
		step = abs(check(t, 4));

		if(step == 0)
			throwStdException(t, "RangeException", "Step may not be 0");
	}

	auto range = abs(v2 - v1);
	long size = cast(long)(range / step);

	if((range % step) != 0)
		size++;

	if(size > uword.max)
		throwStdException(t, "RangeException", "Vector is too big ({} items)", size);

	pushGlobal(t, "Vector");
	pushNull(t);
	pushString(t, type);
	pushInt(t, size);
	rawCall(t, -4, 1);
	
	auto m = _getMembers(t, -1);
	auto val = v1;

	if(v2 < v1)
	{
		for(uword i = 0; val > v2; i++, val -= step)
			_rawIndexAssign(m, i, CrocValue(val));
	}
	else
	{
		for(uword i = 0; val < v2; i++, val += step)
			_rawIndexAssign(m, i, CrocValue(val));
	}
}

uword _range(CrocThread* t)
{
	auto type = checkStringParam(t, 1);

	switch(type)
	{
		case "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64": rangeImpl!(checkIntParam, crocint)(t, type); break;
		case "f32", "f64":                                         rangeImpl!(checkNumParam, crocfloat)(t, type); break;
		default:                                                   throwStdException(t, "ValueException", "Invalid type code '{}'", type);
	}

	return 1;
}

uword _type(CrocThread* t)
{
	auto m = _getMembers(t);
	auto numParams = stackSize(t) - 1;

	if(numParams == 0)
	{
		dup(t, 0);
		pushString(t, m.kind.name);
		return 1;
	}
	else
	{
		auto typeCode = checkStringParam(t, 1);
		TypeStruct* ts = void;

		switch(typeCode)
		{
			case "i8" : ts = &_typeStructs[TypeCode.i8];  break;
			case "i16": ts = &_typeStructs[TypeCode.i16]; break;
			case "i32": ts = &_typeStructs[TypeCode.i32]; break;
			case "i64": ts = &_typeStructs[TypeCode.i64]; break;
			case "u8" : ts = &_typeStructs[TypeCode.u8];  break;
			case "u16": ts = &_typeStructs[TypeCode.u16]; break;
			case "u32": ts = &_typeStructs[TypeCode.u32]; break;
			case "u64": ts = &_typeStructs[TypeCode.u64]; break;
			case "f32": ts = &_typeStructs[TypeCode.f32]; break;
			case "f64": ts = &_typeStructs[TypeCode.f64]; break;

			default:
				throwStdException(t, "ValueException", "Invalid type code '{}'", typeCode);
		}
		
		if(m.kind is ts)
			return 0;

		auto byteSize = m.itemLength * m.kind.itemSize;

		if(byteSize % ts.itemSize != 0)
			throwStdException(t, "ValueException", "Vector's byte size is not an even multiple of new type's item size");

		m.kind = ts;
		return 0;
	}
}

uword _itemSize(CrocThread* t)
{
	auto m = _getMembers(t);
	pushInt(t, m.kind.itemSize);
	return 1;
}

uword _toArray(CrocThread* t)
{
	auto m = _getMembers(t);
	auto lo = optIntParam(t, 1, 0);
	auto hi = optIntParam(t, 2, m.itemLength);

	if(lo < 0)
		lo += m.itemLength;

	if(hi < 0)
		hi += m.itemLength;

	if(lo < 0 || lo > hi || hi > m.itemLength)
		throwStdException(t, "BoundsException", "Invalid slice indices: {} .. {} (length: {})", lo, hi, m.itemLength);

	auto ret = newArray(t, cast(uword)(hi - lo));

	for(uword i = cast(uword)lo, j = 0; i < cast(uword)hi; i++, j++)
	{
		push(t, _rawIndex(m, i));
		idxai(t, ret, j);
	}

	return 1;
}

uword _toString(CrocThread* t)
{
	auto m = _getMembers(t);

	auto b = StrBuffer(t);
	pushFormat(t, "Vector({})[", m.kind.name);
	b.addTop();

	if(m.kind.code == TypeCode.u64)
	{
		for(uword i = 0; i < m.itemLength; i++)
		{
			if(i > 0)
				b.addString(", ");

			auto v = _rawIndex(m, i);
			pushFormat(t, "{}", cast(ulong)v.mInt);
			b.addTop();
		}
	}
	else
	{
		for(uword i = 0; i < m.itemLength; i++)
		{
			if(i > 0)
				b.addString(", ");

			push(t, _rawIndex(m, i));
			pushToString(t, -1, true);
			insertAndPop(t, -2);
			b.addTop();
		}
	}

	b.addString("]");
	b.finish();
	return 1;
}

uword _getMemblock(CrocThread* t)
{
	auto m = _getMembers(t);
	push(t, CrocValue(m.m));
	return 1;
}

uword _dup(CrocThread* t)
{
	auto m = _getMembers(t);

	pushGlobal(t, "Vector");
	pushNull(t);
	pushString(t, m.kind.name);
	pushInt(t, m.itemLength);
	rawCall(t, -4, 1);

	auto n = _getMembers(t, -1);
	auto byteSize = m.itemLength * m.kind.itemSize;
	(cast(ubyte*)n.m.data)[0 .. byteSize] = (cast(ubyte*)m.m.data)[0 .. byteSize];

	return 1;
}

uword _reverse(CrocThread* t)
{
	auto m = _getMembers(t);

	switch(m.kind.itemSize)
	{
		case 1: (cast(ubyte*)m.m.data) [0 .. m.itemLength].reverse; break;
		case 2: (cast(ushort*)m.m.data)[0 .. m.itemLength].reverse; break;
		case 4: (cast(uint*)m.m.data)  [0 .. m.itemLength].reverse; break;
		case 8: (cast(ulong*)m.m.data) [0 .. m.itemLength].reverse; break;

		default:
			throwStdException(t, "ValueException", "A Vector type must've been added that doesn't have 1-, 2-, 4-, or 8-byte elements, so I don't know how to reverse it.");
	}

	dup(t, 0);
	return 1;
}

uword _sort(CrocThread* t)
{
	auto m = _getMembers(t);

	switch(m.kind.code)
	{
		case TypeCode.i8:  (cast(byte*)m.m.data)  [0 .. m.itemLength].sort; break;
		case TypeCode.i16: (cast(short*)m.m.data) [0 .. m.itemLength].sort; break;
		case TypeCode.i32: (cast(int*)m.m.data)   [0 .. m.itemLength].sort; break;
		case TypeCode.i64: (cast(long*)m.m.data)  [0 .. m.itemLength].sort; break;
		case TypeCode.u8:  (cast(ubyte*)m.m.data) [0 .. m.itemLength].sort; break;
		case TypeCode.u16: (cast(ushort*)m.m.data)[0 .. m.itemLength].sort; break;
		case TypeCode.u32: (cast(uint*)m.m.data)  [0 .. m.itemLength].sort; break;
		case TypeCode.u64: (cast(ulong*)m.m.data) [0 .. m.itemLength].sort; break;
		case TypeCode.f32: (cast(float*)m.m.data) [0 .. m.itemLength].sort; break;
		case TypeCode.f64: (cast(double*)m.m.data)[0 .. m.itemLength].sort; break;
		default: assert(false);
	}

	dup(t, 0);
	return 1;
}

uword _apply(CrocThread* t)
{
	auto m = _getMembers(t);
	checkParam(t, 1, CrocValue.Type.Function);

	void doLoop(bool function(CrocThread*, word) test, char[] typeMsg)
	{
		for(uword i = 0; i < m.itemLength; i++)
		{
			dup(t, 1);
			pushNull(t);
			push(t, _rawIndex(m, i));
			rawCall(t, -3, 1);

			if(!test(t, -1))
			{
				pushTypeString(t, -1);
				throwStdException(t, "TypeException", "application function expected to return {}, not '{}'", typeMsg, getString(t, -1));
			}

			_rawIndexAssign(m, i, *getValue(t, -1));
			pop(t);
		}
	}

	switch(m.kind.code)
	{
		case
			TypeCode.i8, TypeCode.i16, TypeCode.i32, TypeCode.i64,
			TypeCode.u8, TypeCode.u16, TypeCode.u32, TypeCode.u64:

			doLoop(&isInt, "'int'");
			break;

		case TypeCode.f32, TypeCode.f64:
			doLoop(&isNum, "'int|float'");
			break;

		default: assert(false);
	}

	dup(t, 0);
	return 1;
}

uword _map(CrocThread* t)
{
	_getMembers(t, 0);
	checkParam(t, 1, CrocValue.Type.Function);

	dup(t, 0);
	pushNull(t);
	methodCall(t, -2, "dup", 1);

	pushNull(t);
	dup(t, 1);
	methodCall(t, -3, "apply", 1);

	return 1;
}

template minMaxImpl(char[] compare)
{
	T minMaxImpl(T)(T[] arr)
	{
		auto m = arr[0];

		foreach(val; arr[1 .. $])
			if(mixin("val " ~ compare ~ " m"))
				m = val;

		return m;
	}
}

uword _max(CrocThread* t)
{
	auto m = _getMembers(t);

	if(m.itemLength == 0)
		throwStdException(t, "ValueException", "Vector is empty");

	switch(m.kind.code)
	{
		case TypeCode.i8:  pushInt(t, minMaxImpl!(">")(cast(byte[])m.m.data));     break;
		case TypeCode.i16: pushInt(t, minMaxImpl!(">")(cast(short[])m.m.data));    break;
		case TypeCode.i32: pushInt(t, minMaxImpl!(">")(cast(int[])m.m.data));      break;
		case TypeCode.i64: pushInt(t, minMaxImpl!(">")(cast(long[])m.m.data));     break;
		case TypeCode.u8:  pushInt(t, minMaxImpl!(">")(cast(ubyte[])m.m.data));    break;
		case TypeCode.u16: pushInt(t, minMaxImpl!(">")(cast(ushort[])m.m.data));   break;
		case TypeCode.u32: pushInt(t, minMaxImpl!(">")(cast(uint[])m.m.data));     break;
		case TypeCode.u64: pushInt(t, cast(crocint)minMaxImpl!(">")(cast(ulong[])m.m.data)); break;
		case TypeCode.f32: pushFloat(t, minMaxImpl!(">")(cast(float[])m.m.data));  break;
		case TypeCode.f64: pushFloat(t, minMaxImpl!(">")(cast(double[])m.m.data)); break;
		default: assert(false);
	}

	return 1;
}

uword _min(CrocThread* t)
{
	auto m = _getMembers(t);

	if(m.itemLength == 0)
		throwStdException(t, "ValueException", "Vector is empty");

	switch(m.kind.code)
	{
		case TypeCode.i8:  pushInt(t, minMaxImpl!("<")(cast(byte[])m.m.data));     break;
		case TypeCode.i16: pushInt(t, minMaxImpl!("<")(cast(short[])m.m.data));    break;
		case TypeCode.i32: pushInt(t, minMaxImpl!("<")(cast(int[])m.m.data));      break;
		case TypeCode.i64: pushInt(t, minMaxImpl!("<")(cast(long[])m.m.data));     break;
		case TypeCode.u8:  pushInt(t, minMaxImpl!("<")(cast(ubyte[])m.m.data));    break;
		case TypeCode.u16: pushInt(t, minMaxImpl!("<")(cast(ushort[])m.m.data));   break;
		case TypeCode.u32: pushInt(t, minMaxImpl!("<")(cast(uint[])m.m.data));     break;
		case TypeCode.u64: pushInt(t, cast(crocint)minMaxImpl!("<")(cast(ulong[])m.m.data)); break;
		case TypeCode.f32: pushFloat(t, minMaxImpl!("<")(cast(float[])m.m.data));  break;
		case TypeCode.f64: pushFloat(t, minMaxImpl!("<")(cast(double[])m.m.data)); break;
		default: assert(false);
	}

	return 1;
}

uword _insert(CrocThread* t)
{
	auto m = _getMembers(t);
	auto len = m.itemLength;
	auto idx = checkIntParam(t, 1);
	checkAnyParam(t, 2);

	if(!m.m.ownData)
		throwStdException(t, "ValueException", "Attempting to insert into a Vector which does not own its data");

	if(idx < 0)
		idx += len;

	// Yes, > and not >=, because you can insert at "one past" the end of the Vector.
	if(idx < 0 || idx > len)
		throwStdException(t, "BoundsException", "Invalid index: {} (length: {})", idx, len);

	void[] doResize(ulong otherLen)
	{
		ulong totalLen = len + otherLen;

		if(totalLen > uword.max)
			throwStdException(t, "RangeException", "Invalid size ({})", totalLen);

		auto oldLen = len;
		auto isize = m.kind.itemSize;

		push(t, CrocValue(m.m));
		lenai(t, -1, cast(uword)totalLen * isize);
		pop(t);

		m.itemLength = cast(uword)totalLen;

		if(idx < oldLen)
		{
			auto end = idx + otherLen;
			auto numLeft = oldLen - idx;
			memmove(&m.m.data[cast(uword)end * isize], &m.m.data[cast(uword)idx * isize], cast(uint)(numLeft * isize));
		}
		
		return m.m.data[cast(uword)idx * isize.. cast(uword)(idx + otherLen) * isize];
	}

	pushGlobal(t, "Vector");

	if(as(t, 2, -1))
	{
		if(opis(t, 0, 2))
		{
			// special case for inserting a Vector into itself

			if(m.itemLength != 0)
			{
				auto slice = doResize(len);
				auto data = m.m.data;
				auto isize = m.kind.itemSize;
				slice[0 .. cast(uword)idx * isize] = data[0 .. cast(uword)idx * isize];
				slice[cast(uword)idx * isize .. $] = data[cast(uword)(idx + len) * isize .. $];
			}
		}
		else
		{
			auto other = _getMembers(t, 2);

			if(m.kind !is other.kind)
				throwStdException(t, "ValueException", "Attempting to insert a Vector of type '{}' into a Vector of type '{}'", other.kind.name, m.kind.name);

			if(other.itemLength != 0)
			{
				auto slice = doResize(other.itemLength);
				memcpy(slice.ptr, other.m.data.ptr, other.itemLength * m.kind.itemSize);
			}
		}
	}
	else
	{
		if(m.kind.code <= TypeCode.u64)
			checkIntParam(t, 2);
		else
			checkNumParam(t, 2);

		doResize(1);
		_rawIndexAssign(m, cast(uword)idx, *getValue(t, 2));
	}

	dup(t, 0);
	return 1;
}

uword _pop(CrocThread* t)
{
	auto m = _getMembers(t);

	if(!m.m.ownData)
		throwStdException(t, "ValueException", "Attempting to pop from a Vector which does not own its data");

	if(m.itemLength == 0)
		throwStdException(t, "ValueException", "Vector is empty");

	auto index = optIntParam(t, 1, -1);

	if(index < 0)
		index += m.itemLength;

	if(index < 0 || index >= m.itemLength)
		throwStdException(t, "BoundsException", "Invalid index: {}", index);

	push(t, _rawIndex(m, cast(uword)index));

	auto isize = m.kind.itemSize;

	if(index < m.itemLength - 1)
		memmove(&m.m.data[cast(uword)index * isize], &m.m.data[(cast(uword)index + 1) * isize], cast(uint)((m.itemLength - index - 1) * isize));

	push(t, CrocValue(m.m));
	lenai(t, -1, (m.itemLength - 1) * isize);
	pop(t);

	return 1;
}

uword _remove(CrocThread* t)
{
	auto m = _getMembers(t);

	if(!m.m.ownData)
		throwStdException(t, "ValueException", "Attempting to remove from a Vector which does not own its data");

	if(m.itemLength == 0)
		throwStdException(t, "ValueException", "Vector is empty");

	auto lo = checkIntParam(t, 1);
	auto hi = optIntParam(t, 2, lo + 1);

	if(lo < 0)
		lo += m.itemLength;

	if(hi < 0)
		hi += m.itemLength;

	if(lo < 0 || lo > hi || hi > m.itemLength)
		throwStdException(t, "BoundsException", "Invalid indices: {} .. {} (length: {})", lo, hi, m.itemLength);

	if(lo != hi)
	{
		auto isize = m.kind.itemSize;

		if(hi < m.itemLength)
			memmove(&m.m.data[cast(uword)lo * isize], &m.m.data[cast(uword)hi * isize], cast(uint)((m.itemLength - hi) * isize));

		auto diff = hi - lo;
		push(t, CrocValue(m.m));
		lenai(t, -1, cast(uword)((m.itemLength - diff) * isize));
		pop(t);
	}

	dup(t, 0);
	return 1;
}

uword _sum(CrocThread* t)
{
	auto m = _getMembers(t);

	if(m.kind.code <= TypeCode.u64)
	{
		crocint res = 0;

		switch(m.kind.code)
		{
			case TypeCode.i8:  foreach(val; cast(byte[])m.m.data)   res += val; break;
			case TypeCode.i16: foreach(val; cast(short[])m.m.data)  res += val; break;
			case TypeCode.i32: foreach(val; cast(int[])m.m.data)    res += val; break;
			case TypeCode.i64: foreach(val; cast(long[])m.m.data)   res += val; break;
			case TypeCode.u8:  foreach(val; cast(ubyte[])m.m.data)  res += val; break;
			case TypeCode.u16: foreach(val; cast(ushort[])m.m.data) res += val; break;
			case TypeCode.u32: foreach(val; cast(uint[])m.m.data)   res += val; break;
			case TypeCode.u64: foreach(val; cast(ulong[])m.m.data)  res += val; break;
			default: assert(false);
		}

		pushInt(t, res);
	}
	else
	{
		crocfloat res = 0.0;

		switch(m.kind.code)
		{
			case TypeCode.f32: foreach(val; cast(float[])m.m.data)  res += val; break;
			case TypeCode.f64: foreach(val; cast(double[])m.m.data) res += val; break;
			default: assert(false);
		}

		pushFloat(t, res);
	}

	return 1;
}

uword _product(CrocThread* t)
{
	auto m = _getMembers(t);

	if(m.kind.code <= TypeCode.u64)
	{
		crocint res = 1;

		switch(m.kind.code)
		{
			case TypeCode.i8:  foreach(val; cast(byte[])m.m.data)   res *= val; break;
			case TypeCode.i16: foreach(val; cast(short[])m.m.data)  res *= val; break;
			case TypeCode.i32: foreach(val; cast(int[])m.m.data)    res *= val; break;
			case TypeCode.i64: foreach(val; cast(long[])m.m.data)   res *= val; break;
			case TypeCode.u8:  foreach(val; cast(ubyte[])m.m.data)  res *= val; break;
			case TypeCode.u16: foreach(val; cast(ushort[])m.m.data) res *= val; break;
			case TypeCode.u32: foreach(val; cast(uint[])m.m.data)   res *= val; break;
			case TypeCode.u64: foreach(val; cast(ulong[])m.m.data)  res *= val; break;
			default: assert(false);
		}

		pushInt(t, res);
	}
	else
	{
		crocfloat res = 1.0;

		switch(m.kind.code)
		{
			case TypeCode.f32: foreach(val; cast(float[])m.m.data)  res *= val; break;
			case TypeCode.f64: foreach(val; cast(double[])m.m.data) res *= val; break;
			default: assert(false);
		}

		pushFloat(t, res);
	}

	return 1;
}

uword _copyRange(CrocThread* t)
{
	auto m = _getMembers(t);
	auto lo = optIntParam(t, 1, 0);
	auto hi = optIntParam(t, 2, m.itemLength);

	if(lo < 0)
		lo += m.itemLength;

	if(hi < 0)
		hi += m.itemLength;

	if(lo < 0 || lo > hi || hi > m.itemLength)
		throwStdException(t, "BoundsException", "Invalid destination slice indices: {} .. {} (length: {})", lo, hi, m.itemLength);

	auto other = _getMembers(t, 3);

	if(m.kind !is other.kind)
		throwStdException(t, "ValueException", "Attempting to copy a Vector of type '{}' into a Vector of type '{}'", other.kind.name, m.kind.name);

	auto lo2 = optIntParam(t, 4, 0);
	auto hi2 = optIntParam(t, 5, lo2 + (hi - lo));

	if(lo2 < 0)
		lo2 += other.itemLength;

	if(hi2 < 0)
		hi2 += other.itemLength;

	if(lo2 < 0 || lo2 > hi2 || hi2 > other.itemLength)
		throwStdException(t, "BoundsException", "Invalid source slice indices: {} .. {} (length: {})", lo2, hi2, other.itemLength);

	if((hi - lo) != (hi2 - lo2))
		throwStdException(t, "ValueException", "Destination length ({}) and source length({}) do not match", hi - lo, hi2 - lo2);

	auto isize = m.kind.itemSize;
	memcpy(&m.m.data[cast(uword)lo * isize], &other.m.data[cast(uword)lo2 * isize], cast(uword)(hi - lo) * isize);

	dup(t, 0);
	return 1;
}

void fillImpl(CrocThread* t, Members* m, word filler, uword lo, uword hi)
{
	pushGlobal(t, "Vector");

	if(as(t, filler, -1))
	{
		auto other = _getMembers(t, filler);

		if(m.kind !is other.kind)
			throwStdException(t, "ValueException", "Attempting to fill a Vector of type '{}' using a Vector of type '{}'", m.kind.name, other.kind.name);

		if(other.itemLength != (hi - lo))
			throwStdException(t, "ValueException", "Length of destination ({}) and length of source ({}) do not match", hi - lo, other.itemLength);

		if(m is other)
			return; // only way this can be is if we're assigning a Vector's entire contents into itself, which is a no-op.

		auto isize = m.kind.itemSize;
		memcpy(&m.m.data[lo * isize], other.m.data.ptr, other.itemLength * isize);
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

		if(m.kind.code <= TypeCode.u64)
		{
			for(uword i = lo; i < hi; i++)
			{
				callFunc(i);

				if(!isInt(t, -1))
				{
					pushTypeString(t, -1);
					throwStdException(t, "TypeException", "filler function expected to return an 'int', not '{}'", getString(t, -1));
				}

				_rawIndexAssign(m, i, *getValue(t, -1));
				pop(t);
			}
		}
		else
		{
			for(uword i = lo; i < hi; i++)
			{
				callFunc(i);

				if(!isNum(t, -1))
				{
					pushTypeString(t, -1);
					throwStdException(t, "TypeException", "filler function expected to return an 'int' or 'float', not '{}'", getString(t, -1));
				}

				_rawIndexAssign(m, i, *getValue(t, -1));
				pop(t);
			}
		}
	}
	else if(isNum(t, filler))
	{
		switch(m.kind.code)
		{
			case TypeCode.i8:  auto val = checkIntParam(t, filler); (cast(byte[])  m.m.data)[lo .. hi] = cast(byte)val;   break;
			case TypeCode.i16: auto val = checkIntParam(t, filler); (cast(short[]) m.m.data)[lo .. hi] = cast(short)val;  break;
			case TypeCode.i32: auto val = checkIntParam(t, filler); (cast(int[])   m.m.data)[lo .. hi] = cast(int)val;    break;
			case TypeCode.i64: auto val = checkIntParam(t, filler); (cast(long[])  m.m.data)[lo .. hi] = cast(long)val;   break;
			case TypeCode.u8:  auto val = checkIntParam(t, filler); (cast(ubyte[]) m.m.data)[lo .. hi] = cast(ubyte)val;  break;
			case TypeCode.u16: auto val = checkIntParam(t, filler); (cast(ushort[])m.m.data)[lo .. hi] = cast(ushort)val; break;
			case TypeCode.u32: auto val = checkIntParam(t, filler); (cast(uint[])  m.m.data)[lo .. hi] = cast(uint)val;   break;
			case TypeCode.u64: auto val = checkIntParam(t, filler); (cast(ulong[]) m.m.data)[lo .. hi] = cast(ulong)val;  break;
			case TypeCode.f32: auto val = checkNumParam(t, filler); (cast(float[]) m.m.data)[lo .. hi] = cast(float)val;  break;
			case TypeCode.f64: auto val = checkNumParam(t, filler); (cast(double[])m.m.data)[lo .. hi] = cast(double)val; break;
			default: assert(false);
		}
	}
	else if(isArray(t, filler))
	{
		if(len(t, filler) != (hi - lo))
			throwStdException(t, "ValueException", "Length of destination ({}) and length of array ({}) do not match", hi - lo, len(t, filler));

		if(m.kind.code <= TypeCode.u64)
		{
			for(uword i = lo, ai = 0; i < hi; i++, ai++)
			{
				idxi(t, filler, ai);

				if(!isInt(t, -1))
				{
					pushTypeString(t, -1);
					throwStdException(t, "ValueException", "array element {} expected to be 'int', not '{}'", ai, getString(t, -1));
				}

				_rawIndexAssign(m, i, *getValue(t, -1));
				pop(t);
			}
		}
		else
		{
			for(uword i = lo, ai = 0; i < hi; i++, ai++)
			{
				idxi(t, filler, ai);

				if(!isNum(t, -1))
				{
					pushTypeString(t, -1);
					throwStdException(t, "ValueException", "array element {} expected to be 'int' or 'float', not '{}'", ai, getString(t, -1));
				}

				_rawIndexAssign(m, i, *getValue(t, -1));
				pop(t);
			}
		}
	}
	else
		paramTypeError(t, filler, "int|float|function|array|Vector");

	pop(t);
}

uword _fill(CrocThread* t)
{
	auto m = _getMembers(t);
	checkAnyParam(t, 1);
	fillImpl(t, m, 1, 0, m.itemLength);
	dup(t, 0);
	return 1;
}

uword _fillRange(CrocThread* t)
{
	auto m = _getMembers(t);
	auto lo = optIntParam(t, 1, 0);
	auto hi = optIntParam(t, 2, m.itemLength);
	checkAnyParam(t, 3);

	if(lo < 0)
		lo += m.itemLength;

	if(hi < 0)
		hi += m.itemLength;

	if(lo < 0 || lo > hi || hi > m.itemLength)
		throwStdException(t, "BoundsException", "Invalid range indices ({} .. {})", lo, hi);

	fillImpl(t, m, 3, cast(uword)lo, cast(uword)hi);
	dup(t, 0);
	return 1;
}

uword _opEquals(CrocThread* t)
{
	auto m = _getMembers(t);
	auto other = _getMembers(t, 1);

	if(opis(t, 0, 1))
		pushBool(t, true);
	else
	{
		if(m.kind !is other.kind)
			throwStdException(t, "ValueException", "Attempting to compare Vectors of types '{}' and '{}'", m.kind.name, other.kind.name);

		if(m.itemLength != other.itemLength)
			pushBool(t, false);
		else
		{
			auto a = (cast(byte*)m.m.data)[0 .. m.itemLength * m.kind.itemSize];
			auto b = (cast(byte*)other.m.data)[0 .. a.length];
			pushBool(t, a == b);
		}
	}

	return 1;
}

uword _opCmp(CrocThread* t)
{
	auto m = _getMembers(t);
	auto len = m.itemLength;
	auto other = _getMembers(t, 1);

	if(opis(t, 0, 1))
		pushInt(t, 0);
	else
	{
		if(m.kind !is other.kind)
			throwStdException(t, "ValueException", "Attempting to compare Vectors of types '{}' and '{}'", m.kind.name, other.kind.name);

		auto otherLen = other.itemLength;
		auto l = min(len, otherLen);
		int cmp;

		switch(m.kind.code)
		{
			case TypeCode.i8:  auto a = (cast(byte[])  m.m.data)[0 .. l]; auto b = (cast(byte[])  other.m.data)[0 .. l]; cmp = typeid(byte[]).  compare(&a, &b); break;
			case TypeCode.i16: auto a = (cast(short[]) m.m.data)[0 .. l]; auto b = (cast(short[]) other.m.data)[0 .. l]; cmp = typeid(short[]). compare(&a, &b); break;
			case TypeCode.i32: auto a = (cast(int[])   m.m.data)[0 .. l]; auto b = (cast(int[])   other.m.data)[0 .. l]; cmp = typeid(int[]).   compare(&a, &b); break;
			case TypeCode.i64: auto a = (cast(long[])  m.m.data)[0 .. l]; auto b = (cast(long[])  other.m.data)[0 .. l]; cmp = typeid(long[]).  compare(&a, &b); break;
			case TypeCode.u8:  auto a = (cast(ubyte[]) m.m.data)[0 .. l]; auto b = (cast(ubyte[]) other.m.data)[0 .. l]; cmp = typeid(ubyte[]). compare(&a, &b); break;
			case TypeCode.u16: auto a = (cast(ushort[])m.m.data)[0 .. l]; auto b = (cast(ushort[])other.m.data)[0 .. l]; cmp = typeid(ushort[]).compare(&a, &b); break;
			case TypeCode.u32: auto a = (cast(uint[])  m.m.data)[0 .. l]; auto b = (cast(uint[])  other.m.data)[0 .. l]; cmp = typeid(uint[]).  compare(&a, &b); break;
			case TypeCode.u64: auto a = (cast(ulong[]) m.m.data)[0 .. l]; auto b = (cast(ulong[]) other.m.data)[0 .. l]; cmp = typeid(ulong[]). compare(&a, &b); break;
			case TypeCode.f32: auto a = (cast(float[]) m.m.data)[0 .. l]; auto b = (cast(float[]) other.m.data)[0 .. l]; cmp = typeid(float[]). compare(&a, &b); break;
			case TypeCode.f64: auto a = (cast(double[])m.m.data)[0 .. l]; auto b = (cast(double[])other.m.data)[0 .. l]; cmp = typeid(double[]).compare(&a, &b); break;
			default: assert(false);
		}

		if(cmp == 0)
			pushInt(t, Compare3(len, otherLen));
		else
			pushInt(t, cmp);
	}

	return 1;
}

uword _opLength(CrocThread* t)
{
	auto m = _getMembers(t);
	pushInt(t, m.itemLength);
	return 1;
}

uword _opLengthAssign(CrocThread* t)
{
	auto m = _getMembers(t);
	auto len = checkIntParam(t, 1);
	
	if(!m.m.ownData)
		throwStdException(t, "ValueException", "Attempting to change the length of a Vector which does not own its data");

	if(len < 0 || len > uword.max)
		throwStdException(t, "ValueException", "Invalid new length: {}", len);
	
	auto isize = cast(uword)len * m.kind.itemSize;
	push(t, CrocValue(m.m));
	lenai(t, -1, isize);
	return 0;
}

uword _opIndex(CrocThread* t)
{
	auto m = _getMembers(t);
	auto idx = checkIntParam(t, 1);

	if(idx < 0)
		idx += m.itemLength;

	if(idx < 0 || idx >= m.itemLength)
		throwStdException(t, "BoundsException", "Invalid index {} for Vector of length {}", idx, m.itemLength);

	push(t, _rawIndex(m, cast(uword)idx));
	return 1;
}

uword _opIndexAssign(CrocThread* t)
{
	auto m = _getMembers(t);
	auto idx = checkIntParam(t, 1);

	if(idx < 0)
		idx += m.itemLength;

	if(idx < 0 || idx >= m.itemLength)
		throwStdException(t, "BoundsException", "Invalid index {} for Vector of length {}", idx, m.itemLength);

	if(m.kind.code <= TypeCode.u64)
		checkIntParam(t, 2);
	else
		checkNumParam(t, 2);

	_rawIndexAssign(m, cast(uword)idx, *getValue(t, 2));
	return 0;
}

uword _opSlice(CrocThread* t)
{
	auto m = _getMembers(t);
	auto lo = optIntParam(t, 1, 0);
	auto hi = optIntParam(t, 2, m.itemLength);

	if(lo < 0)
		lo += m.itemLength;

	if(hi < 0)
		hi += m.itemLength;

	if(lo < 0 || lo > hi || hi > m.itemLength)
		throwStdException(t, "BoundsException", "Invalid slice indices {} .. {} for Vector of length {}", lo, hi, m.itemLength);

	pushGlobal(t, "Vector");
	pushNull(t);
	pushString(t, m.kind.name);
	pushInt(t, hi - lo);
	rawCall(t, -4, 1);
	auto n = _getMembers(t, -1);
	auto isize = m.kind.itemSize;

	memcpy(n.m.data.ptr, m.m.data.ptr + (cast(uword)lo * isize), (cast(uword)hi - cast(uword)lo) * isize);

	return 0;
}

uword _iterator(CrocThread* t)
{
	auto m = _getMembers(t);
	auto index = checkIntParam(t, 1) + 1;

	if(index >= m.itemLength)
		return 0;

	pushInt(t, index);
	push(t, _rawIndex(m, cast(uword)index));
	return 2;
}

uword _iteratorReverse(CrocThread* t)
{
	auto m = _getMembers(t);
	auto index = checkIntParam(t, 1) - 1;

	if(index < 0)
		return 0;

	pushInt(t, index);
	push(t, _rawIndex(m, cast(uword)index));
	return 2;
}

uword _opApply(CrocThread* t)
{
	const Iter = 0;
	const IterReverse = 1;

	auto m = _getMembers(t);
	auto dir = optStringParam(t, 1, "");

	if(dir == "")
	{
		getUpval(t, Iter);
		dup(t, 0);
		pushInt(t, -1);
	}
	else if(dir == "reverse")
	{
		getUpval(t, IterReverse);
		dup(t, 0);
		pushInt(t, m.itemLength);
	}
	else
		throwStdException(t, "ValueException", "Invalid iteration mode");

	return 3;
}

uword _opSerialize(CrocThread* t)
{
	auto m = _getMembers(t);

	if(!m.m.ownData)
		throwStdException(t, "ValueException", "Attempting to serialize a Vector which does not own its data");

	dup(t, 2);
	pushNull(t);
	pushString(t, m.kind.name);
	rawCall(t, -3, 0);

	dup(t, 2);
	pushNull(t);
	push(t, CrocValue(m.m));
	rawCall(t, -3, 0);

	return 0;
}

uword _opDeserialize(CrocThread* t)
{
	auto m = checkInstParam!(Members)(t, 0, "Vector");
	*m = Members.init;

	dup(t, 2);
	pushNull(t);
	rawCall(t, -2, 1);

	if(!isString(t, -1))
		throwStdException(t, "TypeException", "Invalid data encountered when deserializing - expected 'string' but found '{}' instead", type(t, -1));

	switch(getString(t, -1))
	{
		case "i8" : m.kind = &_typeStructs[TypeCode.i8];  break;
		case "i16": m.kind = &_typeStructs[TypeCode.i16]; break;
		case "i32": m.kind = &_typeStructs[TypeCode.i32]; break;
		case "i64": m.kind = &_typeStructs[TypeCode.i64]; break;
		case "u8" : m.kind = &_typeStructs[TypeCode.u8];  break;
		case "u16": m.kind = &_typeStructs[TypeCode.u16]; break;
		case "u32": m.kind = &_typeStructs[TypeCode.u32]; break;
		case "u64": m.kind = &_typeStructs[TypeCode.u64]; break;
		case "f32": m.kind = &_typeStructs[TypeCode.f32]; break;
		case "f64": m.kind = &_typeStructs[TypeCode.f64]; break;

		default:
			throwStdException(t, "ValueException", "Invalid data encountered when deserializing - Invalid type code '{}'", getString(t, -1));
	}

	pop(t);

	dup(t, 2);
	pushNull(t);
	rawCall(t, -2, 1);

	if(!isMemblock(t, -1))
		throwStdException(t, "TypeException", "Invalid data encountered when deserializing - expected 'memblock' but found '{}' instead", type(t, -1));

	m.m = getMemblock(t, -1);
	return 0;
}

uword _opCat(CrocThread* t)
{
	auto m = _getMembers(t);
	checkAnyParam(t, 1);

	pushGlobal(t, "Vector");

	if(as(t, 1, -1))
	{
		auto other = _getMembers(t, 1);

		if(other.kind !is m.kind)
			throwStdException(t, "ValueException", "Attempting to concatenate Vectors of types '{}' and '{}'", m.kind.name, other.kind.name);
	
		pushGlobal(t, "Vector");
		pushNull(t);
		pushString(t, m.kind.name);
		pushInt(t, m.itemLength + other.itemLength);
		rawCall(t, -4, 1);

		auto n = _getMembers(t, -1);
		n.m.data[0 .. m.m.data.length] = m.m.data[];
		n.m.data[m.m.data.length .. $] = other.m.data[];
	}
	else
	{
		if(m.kind.code <= TypeCode.u64)
			checkIntParam(t, 1);
		else
			checkNumParam(t, 1);

		pushGlobal(t, "Vector");
		pushNull(t);
		pushString(t, m.kind.name);
		pushInt(t, m.itemLength + 1);
		rawCall(t, -4, 1);

		auto n = _getMembers(t, -1);
		n.m.data[0 .. m.m.data.length] = m.m.data[];
		_rawIndexAssign(n, n.itemLength - 1, *getValue(t, 1));
	}

	return 1;
}

uword _opCat_r(CrocThread* t)
{
	auto m = _getMembers(t);
	checkAnyParam(t, 1);

	if(m.kind.code <= TypeCode.u64)
		checkIntParam(t, 1);
	else
		checkNumParam(t, 1);

	pushGlobal(t, "Vector");
	pushNull(t);
	pushString(t, m.kind.name);
	pushInt(t, m.itemLength + 1);
	rawCall(t, -4, 1);

	auto n = _getMembers(t, -1);
	_rawIndexAssign(n, 0, *getValue(t, 1));
	n.m.data[1 .. $] = m.m.data[];

	return 1;
}

uword _opCatAssign(CrocThread* t)
{
	auto m = _getMembers(t);
	auto numParams = stackSize(t) - 1;
	checkAnyParam(t, 1);

	if(!m.m.ownData)
		throwStdException(t, "ValueException", "Attempting to append to a Vector which does not own its data");

	ulong totalLen = m.itemLength;

	auto Vector = pushGlobal(t, "Vector");

	for(uword i = 1; i <= numParams; i++)
	{
		if(as(t, i, Vector))
		{
			auto other = _getMembers(t, i);

			if(other.kind !is m.kind)
				throwStdException(t, "ValueException", "Attempting to concatenate Vectors of types '{}' and '{}'", m.kind.name, other.kind.name);

			totalLen += other.itemLength;
		}
		else
		{
			if(m.kind.code <= TypeCode.u64)
				checkIntParam(t, i);
			else
				checkNumParam(t, i);

			totalLen++;
		}
	}

	pop(t);

	if(totalLen > uword.max)
		throwStdException(t, "RangeException", "Invalid size ({})", totalLen);

	auto isize = m.kind.itemSize;
	auto oldLen = m.itemLength;

	dup(t, 0);
	pushNull(t);
	pushInt(t, cast(crocint)totalLen);
	methodCall(t, -3, "opLengthAssign", 0);

	uword j = oldLen * isize;

	Vector = pushGlobal(t, "Vector");

	for(uword i = 1; i <= numParams; i++)
	{
		if(as(t, i, Vector))
		{
			if(opis(t, 0, i))
			{
				// special case for when we're appending a Vector to itself; use the old length
				memcpy(m.m.data.ptr + j, m.m.data.ptr, oldLen * isize);
				j += oldLen;
			}
			else
			{
				auto other = _getMembers(t, i);
				m.m.data[j .. j + other.m.data.length] = other.m.data[];
				j += other.m.data.length;
			}
		}
		else
		{
			_rawIndexAssign(m, j / isize, *getValue(t, i));
			j += isize;
		}
	}

	return 0;
}

char[] opAssign(char[] name, char[] op)
{
	return `uword _op` ~ name ~ `Assign(CrocThread* t)
	{
		auto m = _getMembers(t);
		checkAnyParam(t, 1);

		pushGlobal(t, "Vector");

		if(as(t, 1, -1))
		{
			auto other = _getMembers(t, 1);

			if(other.itemLength != m.itemLength)
				throwStdException(t, "ValueException", "Cannot perform operation on Vectors of different lengths");

			if(other.kind !is m.kind)
				throwStdException(t, "ValueException", "Cannot perform operation on Vectors of types '{}' and '{}'", m.kind.name, other.kind.name);

			switch(m.kind.code)
			{
				case TypeCode.i8:  (cast(byte[])m.m.data)[]   ` ~ op ~ `= (cast(byte[])other.m.data)[];   break;
				case TypeCode.i16: (cast(short[])m.m.data)[]  ` ~ op ~ `= (cast(short[])other.m.data)[];  break;
				case TypeCode.i32: (cast(int[])m.m.data)[]    ` ~ op ~ `= (cast(int[])other.m.data)[];    break;
				case TypeCode.i64: (cast(long[])m.m.data)[]   ` ~ op ~ `= (cast(long[])other.m.data)[];   break;
				case TypeCode.u8:  (cast(ubyte[])m.m.data)[]  ` ~ op ~ `= (cast(ubyte[])other.m.data)[];  break;
				case TypeCode.u16: (cast(ushort[])m.m.data)[] ` ~ op ~ `= (cast(ushort[])other.m.data)[]; break;
				case TypeCode.u32: (cast(uint[])m.m.data)[]   ` ~ op ~ `= (cast(uint[])other.m.data)[];   break;
				case TypeCode.u64: (cast(ulong[])m.m.data)[]  ` ~ op ~ `= (cast(ulong[])other.m.data)[];  break;
				case TypeCode.f32: (cast(float[])m.m.data)[]  ` ~ op ~ `= (cast(float[])other.m.data)[];  break;
				case TypeCode.f64: (cast(double[])m.m.data)[] ` ~ op ~ `= (cast(double[])other.m.data)[]; break;
				default: assert(false);
			}
		}
		else
		{
			switch(m.kind.code)
			{
				case TypeCode.i8:  auto val = checkIntParam(t, 1); (cast(byte[])m.m.data)[]   ` ~ op ~ `= cast(byte)val;   break;
				case TypeCode.i16: auto val = checkIntParam(t, 1); (cast(short[])m.m.data)[]  ` ~ op ~ `= cast(short)val;  break;
				case TypeCode.i32: auto val = checkIntParam(t, 1); (cast(int[])m.m.data)[]    ` ~ op ~ `= cast(int)val;    break;
				case TypeCode.i64: auto val = checkIntParam(t, 1); (cast(long[])m.m.data)[]   ` ~ op ~ `= cast(long)val;   break;
				case TypeCode.u8:  auto val = checkIntParam(t, 1); (cast(ubyte[])m.m.data)[]  ` ~ op ~ `= cast(ubyte)val;  break;
				case TypeCode.u16: auto val = checkIntParam(t, 1); (cast(ushort[])m.m.data)[] ` ~ op ~ `= cast(ushort)val; break;
				case TypeCode.u32: auto val = checkIntParam(t, 1); (cast(uint[])m.m.data)[]   ` ~ op ~ `= cast(uint)val;   break;
				case TypeCode.u64: auto val = checkIntParam(t, 1); (cast(ulong[])m.m.data)[]  ` ~ op ~ `= cast(ulong)val;  break;
				case TypeCode.f32: auto val = checkNumParam(t, 1); (cast(float[])m.m.data)[]  ` ~ op ~ `= cast(float)val;  break;
				case TypeCode.f64: auto val = checkNumParam(t, 1); (cast(double[])m.m.data)[] ` ~ op ~ `= cast(double)val; break;
				default: assert(false);
			}
		}

		return 0;
	}`; /+  +/
}

mixin(opAssign("Add", "+"));
mixin(opAssign("Sub", "-"));
mixin(opAssign("Mul", "*"));
mixin(opAssign("Div", "/"));
mixin(opAssign("Mod", "%"));

// These are implemented like this because "a[] + b[]" will allocate on the D heap... bad.
char[] op(char[] name)
{
	return `uword _op` ~ name ~ `(CrocThread* t)
	{
		auto m = _getMembers(t);
		checkAnyParam(t, 1);

		auto ret = dup(t, 0);
		pushNull(t);
		methodCall(t, -2, "dup", 1);

		dup(t, ret);
		pushNull(t);
		dup(t, 1);
		methodCall(t, -3, "op` ~ name ~ `Assign", 0);

		return 1;
	}`; /+  +/
}

mixin(op("Add"));
mixin(op("Sub"));
mixin(op("Mul"));
mixin(op("Div"));
mixin(op("Mod"));

char[] op_rev(char[] name)
{
	return `uword _op` ~ name ~ `_r(CrocThread* t)
	{
		auto m = _getMembers(t);
		checkAnyParam(t, 1);

		auto ret = dup(t, 0);
		pushNull(t);
		methodCall(t, -2, "dup", 1);

		dup(t, ret);
		pushNull(t);
		dup(t, 1);
		methodCall(t, -3, "rev` ~ name ~ `", 0);

		return 1;
	}`; /+  +/
}

mixin(op_rev("Sub"));
mixin(op_rev("Div"));
mixin(op_rev("Mod"));

// BUG 2434: Compiler generates code that does not pass with -w for some array operations
// namely, for the [u](byte|short) cases for div and mod.

char[] rev_func(char[] name, char[] op)
{
	return `uword _rev` ~ name ~ `(CrocThread* t)
	{
		auto m = _getMembers(t);
		checkAnyParam(t, 1);
		
		pushGlobal(t, "Vector");

		if(as(t, 1, -1))
		{
			auto other = _getMembers(t, 1);

			if(other.itemLength != m.itemLength)
				throwStdException(t, "ValueException", "Cannot perform operation on Vectors of different lengths");

			if(other.kind !is m.kind)
				throwStdException(t, "ValueException", "Cannot perform operation on Vectors of types '{}' and '{}'", m.kind.name, other.kind.name);

			switch(m.kind.code)
			{
				case TypeCode.i8:
					auto data = cast(byte[])m.m.data;
					auto otherData = cast(byte[])other.m.data;

					for(uword i = 0; i < data.length; i++)
						data[i] = cast(byte)(otherData[i] ` ~ op ~ ` data[i]);
					break;

				case TypeCode.i16:
					auto data = cast(short[])m.m.data;
					auto otherData = cast(short[])other.m.data;

					for(uword i = 0; i < data.length; i++)
						data[i] = cast(short)(otherData[i] ` ~ op ~ ` data[i]);
					break;

				case TypeCode.i32: auto data = cast(int[])m.m.data;  data[] = (cast(int[])other.m.data)[] ` ~ op ~ ` data[];  break;
				case TypeCode.i64: auto data = cast(long[])m.m.data; data[] = (cast(long[])other.m.data)[] ` ~ op ~ ` data[]; break;

				case TypeCode.u8:
					auto data = cast(ubyte[])m.m.data;
					auto otherData = cast(ubyte[])other.m.data;

					for(uword i = 0; i < data.length; i++)
						data[i] = cast(ubyte)(otherData[i] ` ~ op ~ ` data[i]);
					break;

				case TypeCode.u16:
					auto data = cast(ushort[])m.m.data;
					auto otherData = cast(ushort[])other.m.data;

					for(uword i = 0; i < data.length; i++)
						data[i] = cast(ushort)(otherData[i] ` ~ op ~ ` data[i]);
					break;

				case TypeCode.u32: auto data = cast(uint[])m.m.data;   data[] = (cast(uint[])other.m.data)[] ` ~ op ~ ` data[];   break;
				case TypeCode.u64: auto data = cast(ulong[])m.m.data;  data[] = (cast(ulong[])other.m.data)[] ` ~ op ~ ` data[];  break;
				case TypeCode.f32: auto data = cast(float[])m.m.data;  data[] = (cast(float[])other.m.data)[] ` ~ op ~ ` data[];  break;
				case TypeCode.f64: auto data = cast(double[])m.m.data; data[] = (cast(double[])other.m.data)[] ` ~ op ~ ` data[]; break;
				default: assert(false);
			}
		}
		else
		{
			switch(m.kind.code)
			{
				case TypeCode.i8:
					auto val = cast(byte)checkIntParam(t, 1);
					auto data = cast(byte[])m.m.data;

					for(uword i = 0; i < data.length; i++)
						data[i] = cast(byte)(val ` ~ op ~ ` data[i]);
					break;

				case TypeCode.i16:
					auto val = cast(short)checkIntParam(t, 1);
					auto data = cast(short[])m.m.data;

					for(uword i = 0; i < data.length; i++)
						data[i] = cast(short)(val ` ~ op ~ ` data[i]);
					break;

				case TypeCode.i32:
					auto val = cast(int)checkIntParam(t, 1);
					auto data = cast(int[])m.m.data;
					data[] = val ` ~ op ~ `data[];
					break;

				case TypeCode.i64:
					auto val = cast(long)checkIntParam(t, 1);
					auto data = cast(long[])m.m.data;
					data[] = val ` ~ op ~ `data[];
					break;

				case TypeCode.u8:
					auto val = cast(ubyte)checkIntParam(t, 1);
					auto data = cast(ubyte[])m.m.data;

					for(uword i = 0; i < data.length; i++)
						data[i] = cast(ubyte)(val ` ~ op ~ ` data[i]);
					break;

				case TypeCode.u16:
					auto val = cast(ushort)checkIntParam(t, 1);
					auto data = cast(ushort[])m.m.data;

					for(uword i = 0; i < data.length; i++)
						data[i] = cast(ushort)(val ` ~ op ~ ` data[i]);
					break;

				case TypeCode.u32:
					auto val = cast(uint)checkIntParam(t, 1);
					auto data = cast(uint[])m.m.data;
					data[] = val ` ~ op ~ `data[];
					break;

				case TypeCode.u64:
					auto val = cast(ulong)checkIntParam(t, 1);
					auto data = cast(ulong[])m.m.data;
					data[] = val ` ~ op ~ `data[];
					break;

				case TypeCode.f32:
					auto val = cast(float)checkNumParam(t, 1);
					auto data = cast(float[])m.m.data;
					data[] = val ` ~ op ~ `data[];
					break;

				case TypeCode.f64:
					auto val = cast(double)checkNumParam(t, 1);
					auto data = cast(double[])m.m.data;
					data[] = val ` ~ op ~ `data[];
					break;

				default: assert(false);
			}
		}

		dup(t, 0);
		return 0;
	}`; /+  +/
}

mixin(rev_func("Sub", "-"));
mixin(rev_func("Div", "/"));
mixin(rev_func("Mod", "%"));

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

		You can either use the \tt{~=} and \tt{~} operators to use this method, or you can call the \link{append} method; both are aliased to
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