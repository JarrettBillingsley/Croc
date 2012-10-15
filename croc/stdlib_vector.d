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

void initVector(CrocThread* t)
{
	CreateClass(t, "Vector", (CreateClass* c)
	{
		pushNull(t);   c.field("_m");
		pushInt(t, 0); c.field("_kind");
		pushInt(t, 0); c.field("_itemLength");

		c.method("constructor",    3, &_constructor);
		c.method("fromArray",      2, &_fromArray);
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
		c.method("remove",         2, &_remove);
		c.method("pop",            1, &_pop);
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
	pushGlobal(t, "Vector");
		doc.push(_classDocs);
		docFields(t, doc, _methodDocs);
		doc.pop(-1);
	pop(t);
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

Members _getMembers(CrocThread* t, uword slot = 0)
{
	Members ret = void;

	field(t, slot, "Vector_m");
	assert(!isNull(t, -1));
	ret.m = getMemblock(t, -1);
	pop(t);

	field(t, slot, "Vector_kind");
	ret.kind = cast(TypeStruct*)getInt(t, -1);
	pop(t);

	uword len = ret.m.data.length >> ret.kind.sizeShift;

	if(len << ret.kind.sizeShift != ret.m.data.length)
		throwStdException(t, "ValueException", "Vector's underlying memblock length is not an even multiple of its item size");

	pushInt(t, len);
	fielda(t, slot, "Vector_itemLength");
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

TypeStruct* _typeCodeToKind(char[] typeCode)
{
	switch(typeCode)
	{
		case "i8" : return &_typeStructs[TypeCode.i8];
		case "i16": return &_typeStructs[TypeCode.i16];
		case "i32": return &_typeStructs[TypeCode.i32];
		case "i64": return &_typeStructs[TypeCode.i64];
		case "u8" : return &_typeStructs[TypeCode.u8];
		case "u16": return &_typeStructs[TypeCode.u16];
		case "u32": return &_typeStructs[TypeCode.u32];
		case "u64": return &_typeStructs[TypeCode.u64];
		case "f32": return &_typeStructs[TypeCode.f32];
		case "f64": return &_typeStructs[TypeCode.f64];
		default:    return null;
	}
}

uword _constructor(CrocThread* t)
{
	checkInstParam(t, 0, "Vector");

	field(t, 0, "Vector_m");

	if(isNull(t, -1))
		throwStdException(t, "StateException", "Attempting to call the constructor on an already-initialized Vector");

	pop(t);

	auto kind = _typeCodeToKind(checkStringParam(t, 1));

	if(kind is null)
		throwStdException(t, "ValueException", "Invalid type code '{}'", getString(t, 1));

	auto size = checkIntParam(t, 2);

	if(size < 0 || size > uword.max)
		throwStdException(t, "RangeException", "Invalid size ({})", size);

	newMemblock(t, cast(uword)size * self.kind.itemSize);
	self.m = getMemblock(t, -1);
	setExtraVal(t, 0, Data);

	if(isValidIndex(t, 3))
	{
		dup(t, 0);
		pushNull(t);
		dup(t, 3);
		methodCall(t, -3, "fill", 0);
	}

	return 0;
}

uword _fromArray(CrocThread* t)
{
	checkStringParam(t, 1);
	checkParam(t, 2, CrocValue.Type.Array);

	pushGlobal(t, "Vector");
	pushNull(t);
	dup(t, 1);
	pushInt(t, len(t, 2));
	dup(t, 2);
	rawCall(t, -5, 1);

	return 1;
}

void _rangeImpl(alias check, T)(CrocThread* t, char[] type)
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
		case "i8", "i16", "i32", "i64":
		case "u8", "u16", "u32", "u64": _rangeImpl!(checkIntParam, crocint)(t, type); break;
		case "f32", "f64":              _rangeImpl!(checkNumParam, crocfloat)(t, type); break;
		default:                        throwStdException(t, "ValueException", "Invalid type code '{}'", type);
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
		auto ts = _typeCodeToKind(checkStringParam(t, 1));

		if(ts is null)
			throwStdException(t, "ValueException", "Invalid type code '{}'", getString(t, 1));

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

	if(opis(t, 0, 3))
		memmove(&m.m.data[cast(uword)lo * isize], &other.m.data[cast(uword)lo2 * isize], cast(uword)(hi - lo) * isize);
	else
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
		throwStdException(t, "RangeException", "Invalid new length: {}", len);

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

	m.kind = _typeCodeToKind(getString(t, -1));

	if(m.kind is null)
		throwStdException(t, "ValueException", "Invalid data encountered when deserializing - Invalid type code '{}'", getString(t, -1));

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
	}`;
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
	}`;
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
	}`;
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
	}`;
}

mixin(rev_func("Sub", "-"));
mixin(rev_func("Div", "/"));
mixin(rev_func("Mod", "%"));

version(CrocBuiltinDocs)
{
	const Docs _classDocs =
	{kind: "class", name: "Vector",
	extra: [Extra("protection", "global")],
	docs:
	`Croc's built-in array type is fine for most tasks, but they're not very well-suited to high-speed number crunching.
	Memblocks give you a low-level memory buffer, but don't provide any data structuring. Vectors solve both these
	problems: they are dynamically-resizable strongly-typed single-dimensional arrays of numerical values built on top of
	memblocks.

	There are ten possible types a Vector can hold. Each type has an associated "type code", which is just a string.
	The types and their type codes are as follows:

	\table
		\row \cell \b{Type Code} \cell \b{Definition}
		\row \cell \tt{i8}       \cell Signed 8-bit integer
		\row \cell \tt{i16}      \cell Signed 16-bit integer
		\row \cell \tt{i32}      \cell Signed 32-bit integer
		\row \cell \tt{i64}      \cell Signed 64-bit integer
		\row \cell \tt{u8}       \cell Unsigned 8-bit integer
		\row \cell \tt{u16}      \cell Unsigned 16-bit integer
		\row \cell \tt{u32}      \cell Unsigned 32-bit integer
		\row \cell \tt{u64}      \cell Unsigned 64-bit integer
		\row \cell \tt{f32}      \cell Single-precision IEEE 754 float
		\row \cell \tt{f64}      \cell Double-precision IEEE 754 float
	\endtable

	These type codes are case-sensitive, so for example, passing \tt{"u8"} to the constructor is legal, whereas \tt{"U8"}
	is not.

	A note on the \tt{"u64"} type: Croc's int type is a signed 64-bit integer, which does not have the range to represent
	all possible values that an unsigned 64-bit integer can. So when dealing with \tt{"u64" Vectors}, values larger than
	2\sup{63} - 1 will be represented as negative Croc integers. However, internally, all the operations on these Vectors
	will be performed according to unsigned integer rules. The \tt{toString} method is also aware of this and will print
	the values correctly, and if you'd like to print out unsigned 64-bit integers yourself, you can use \tt{toString(val, 'u')}
	from the base library.

	A note on all types: for performance reasons, Vectors do not check the ranges of the values that are stored in them.
	For instance, if you assign an integer into a \tt{"u8" Vector}, only the lowest 8 bits will be stored. Storing \tt{floats}
	into \tt{"f32" Vectors} will similarly round the value to the nearest representable value.

	Finally, the underlying memblock can be retrieved and manipulated directly; however, changing its size must be done carefully.
	If the size is set to a byte length that is not an even multiple of the item size of the Vector, an exception will be
	thrown the next time a method is called on the Vector that uses that memblock.

	All methods, unless otherwise documented, return the Vector object on which they were called.`};

	const Docs[] _methodDocs =
	[
		{kind: "function", name: "constructor",
		params: [Param("type", "string"), Param("size", "int"), Param("filler", "any", "null")],
		docs:
		`Constructor.

		\param[type] is a string containing one of the type codes listed above.
		\param[size] is the length of the new Vector, measured in the number of elements.
		\param[filler] is optional. If it is not given, the Vector is filled with 0s. If it is given, the instance will have
		the \link{fill} method called on it with \tt{filler} as the argument. As such, if the \tt{filler} is invalid, any exceptions
		that \link{fill} can throw, the constructor can throw as well.

		\throws[exceptions.ValueException] if \tt{type} is not a valid type code.
		\throws[exceptions.RangeException] if \tt{size} is invalid (negative or too large).`},

		{kind: "function", name: "fromArray",
		params: [Param("type", "string"), Param("arr", "array")],
		docs:
		`A convenience function to convert an \tt{array} into a Vector.

		Calling \tt{Vector.fromArray(type, arr)} is basically the same as calling \tt{Vector(type, #arr, arr)}; that is, the length
		of the Vector will be the length of the array, and the array will be passed as the \tt{filler} to the constructor.

		\param[type] is a string containing one of the type codes.
		\param[arr] is an array (single-dimensional, containing only numbers that can be converted to the Vector's element type)
		that will be used to fill the Vector with data.

		\returns the new Vector.`},

		{kind: "function", name: "range",
		params: [Param("type", "string"), Param("val1", "int|float"), Param("val2", "int|float", "null"), Param("step", "int|float", "1")],
		docs:
		`Creates a Vector whose values are a range of ascending or numbers, much like the \link{array.range} function.

		If the \tt{type} parameter is one of the integral types, the next three parameters must be ints; otherwise, they can be
		ints or floats.

		If called with just \tt{val1}, it specifies a noninclusive end index, with a start index of 0 and a step of 1. So
		\tt{Vector.range("i32", 5)} gives \tt{"Vector(i32)[0, 1, 2, 3, 4]"}, and \tt{Vector.range("i32", -5)} gives
		\tt{"Vector(i32)[0, -1, -2, -3, -4]"}.

		If called with \tt{val1} and \tt{val2}, \tt{val1} will be the inclusive start index, and \tt{val2} will be the noninclusive
		end index. The step will be 1.

		The \tt{step}, if specified, specifies how much each successive element should differ by. The sign is ignored, but the step
		may not be 0.

		\param[type] is a string containing one of the type codes.
		\param[val1] is either the end index or the start index as explained above.
		\param[val2] is the optional end index; if specified, makes \tt{val1} the start index.
		\param[step] is the optional step size.

		\returns the new Vector.
		\throws[exceptions.RangeException] if \tt{step} is 0.
		\throws[exceptions.RangeException] if the resulting Vector would have too many elements to be represented.`},

		{kind: "function", name: "type",
		params: [Param("type", "string", "null")],
		docs:
		`Gets or sets the type of this Vector.

		If called with no parameters, gets the type and returns it as a string.

		If called with a parameter, it must be one of the type codes given above. The Vector's type will be set to the
		new type, but only if the Vector's byte length is an multiple of the new type's item size. That is, if you had
		a \tt{"u8" Vector} of length 7, and tried to change its type to \tt{"u16"}, it would fail because 7 is not an even
		multiple of the size of a \tt{"u16"} element, 2 bytes.

		When the type is changed, the data is not affected at all. The existing bit patterns will simply be interpreted according
		to the new type.

		\param[type] is the new type if changing this Vector's type, or \tt{null} if not.
		\returns the current type of the Vector if \tt{type} is \tt{null}, or nothing otherwise.
		\throws[exceptions.ValueException] if \tt{type} is not a valid type code.
		\throws[exceptions.ValueException] if the byte size is not an even multiple of the new type's item size.`},

		{kind: "function", name: "itemSize",
		params: [],
		docs:
		`Returns the size of one item of this Vector in bytes.`},

		{kind: "function", name: "toArray",
		params: [Param("lo", "int", "0"), Param("hi", "int", "#this")],
		docs:
		`Converts this Vector or a slice of it into an \tt{array}.

		Simply creates a new array and fills it with the values held in the Vector, or just a slice of it if the parameters
		are given.

		\param[lo] the low slice index.
		\param[hi] the high slice index.
		\returns an array holding the values from the given slice.`},

		{kind: "function", name: "toString",
		params: [],
		docs:
		`Returns a string representation of this Vector.

		The format will be \tt{"Vector(<type>)[<elements>]"}; that is, \tt{Vector.fromArray("i32", [1, 2, 3]).toString()} will
		yield the string \tt{"Vector(i32)[1, 2, 3]"}.`},

		{kind: "function", name: "getMemblock",
		params: [],
		docs:
		`Returns the underlying \tt{memblock} in which this Vector stores its data.

		Note that which memblock a Vector uses to store its data cannot be changed, but you can change the data and size of
		the memblock returned from this method. As explained in the class's documentation, though, setting the underlying
		memblock's length to something that is not an even multiple of the Vector's item size will result in an exception
		being thrown the next time a method is called on the Vector.`},

		{kind: "function", name: "dup",
		params: [],
		docs:
		`Duplicates this Vector.

		Creates a new Vector with the same type and a copy of this Vector's data.

		\returns the new Vector.`},

		{kind: "function", name: "reverse",
		params: [],
		docs:
		`Reverses the elements of this Vector.

		This method operates in-place.`},

		{kind: "function", name: "sort",
		params: [],
		docs:
		`Sorts the elements of this Vector in ascending order.

		This method operates in-place.`},

		{kind: "function", name: "apply",
		params: [Param("func", "function")],
		docs:
		`Like \link{array.apply}, calls a function on each element of this Vector and assigns the results back into it.

		\param[func] should be a function which takes one value (an int for integral Vectors or a float for floating-point
		ones), and should return one value of the same type that was passed in (though it's okay to return ints for floating-point
		Vectors.

		\throws[exceptions.TypeException] if \tt{func} returns a value of an invalid type.`},

		{kind: "function", name: "map",
		params: [Param("func", "function")],
		docs:
		`Same as \link{apply}, except puts the results into a new Vector instead of operating in-place.

		This is functionally equivalent to writing \tt{this.dup().apply(func)}.

		\param[func] is the same as the \tt{func} parameter for \link{apply}.
		\returns the new Vector.
		\throws[exceptions.TypeException] if \tt{func} returns a value of an invalid type.`},

		{kind: "function", name: "max",
		params: [],
		docs:
		`Finds the largest value in this Vector.

		\returns the largest value.
		\throws[exceptions.ValueException] if \tt{#this == 0}.`},

		{kind: "function", name: "max",
		params: [],
		docs:
		`Finds the smallest value in this Vector.

		\returns the smallest value.
		\throws[exceptions.ValueException] if \tt{#this == 0}.`},

		{kind: "function", name: "insert",
		params: [Param("idx", "int"), Param("val", "int|float|Vector")],
		docs:
		`Inserts a single number or another Vector's contents at the given position.

		\param[idx] is the position where \tt{val} should be inserted. All the elements (if any) after \tt{idx} are
		shifted down to make room for the inserted data. \tt{idx} can be \tt{#this}, in which case \tt{val} will be appended
		to the end of \tt{this}. \tt{idx} can be negative to mean an index from the end of this Vector.
		\param[val] is the value to insert. If \tt{val} is a Vector, it must be the same type as \tt{this}. It is legal
		for \tt{val} to be \tt{this}. If \tt{val} isn't a Vector, it must be a valid type for this Vector.
		\throws[exceptions.ValueException] if this Vector's memblock does not own its data.
		\throws[exceptions.BoundsException] if \tt{idx} is invalid.
		\throws[exceptions.ValueException] if \tt{val} is a Vector but its type differs from \tt{this}'s type.
		\throws[exceptions.RangeException] if inserting would cause this Vector to grow too large.`},

		{kind: "function", name: "remove",
		params: [Param("lo", "int"), Param("hi", "int", "lo + 1")],
		docs:
		`Removes one or more items from this Vector, shifting the data after the removed data up.

		It is legal for the size of the slice to be removed to be 0, in which case nothing happens.

		\param[lo] is the lower slice index of the items to be removed.
		\param[hi] is the upper slice index of the items to be removed. It defaults to one after \tt{lo}, so that called with
		just one parameter, this method will remove one item.
		\throws[exceptions.ValueException] if this Vector's memblock does not own its data.
		\throws[exceptions.ValueException] if this Vector is empty.
		\throws[exceptions.BoundsException] if \tt{lo} and \tt{hi} are invalid.`},

		{kind: "function", name: "pop",
		params: [Param("idx", "int", "-1")],
		docs:
		`Removes one item from anywhere in this Vector (the last item by default) and returns its value, like
		\link{array.pop}.

		\param[idx] is the index of the item to be removed, which defaults to the last item in this Vector.
		\returns the value of the item that was removed.
		\throws[exceptions.ValueException] if this Vector's memblock does not own its data.
		\throws[exceptions.ValueException] if this Vector is empty.
		\throws[exceptions.BoundsException] if \tt{idx} is invalid.`},

		{kind: "function", name: "sum",
		params: [],
		docs:
		`Sums all the elements in this Vector, returning 0 or 0.0 if empty.

		\returns the sum.`},

		{kind: "function", name: "product",
		params: [],
		docs:
		`Multiplies all the elements in this Vector together, returning 1 or 1.0 if empty.

		\returns the product.`},

		{kind: "function", name: "copyRange",
		params: [Param("lo1", "int", "0"), Param("hi1", "int", "#this"), Param("other", "Vector"), Param("lo2", "int", "0"), Param("hi2", "int", "lo2 + (hi - lo)")],
		docs:
		`Copies a slice of another Vector into a slice of this one without creating an unnecessary temporary.

		If you try to use slice-assignment to copy a slice of one vector into another (such as \tt{a[x .. y] = b[z .. w]}), an
		unnecessary temporary Vector will be created, as well as performing two memory copies. For better performance, you can
		use this method to copy the data directly without creating an intermediate object and only performing one memory copy.

		The lengths of the slices must be identical.

		\param[lo1] is the lower index of the slice into this Vector.
		\param[hi1] is the upper index of the slice into this Vector.
		\param[other] is the Vector from which data will be copied.
		\param[lo2] is the lower index of the slice into \tt{other}.
		\param[hi2] is the upper index of the slice into \tt{other}. Note that its default value means \tt{lo2 + the size of the
		slice into this}.

		\throws[exceptions.BoundsException] if either pair of slice indices is invalid for its respective Vector.
		\throws[exceptions.ValueException] if \tt{other}'s type is not the same as this Vector's.
		\throws[exceptions.ValueException] if the sizes of the slices differ.`},

		{kind: "function", name: "fill",
		params: [Param("val", "int|float|function|array|Vector")],
		docs:
		`A flexible way to fill a Vector with data.

		This method never changes the Vector's size; it always works in-place, and all data in this Vector is replaced. The
		behavior of this method depends on the type of its \tt{val} parameter.

		\param[val] is the value used to fill this Vector.

		If \tt{this} is an integral Vector, and \tt{val} is an int, all items in this Vector will be set to \tt{val}.

		If \tt{this} is a floating-point Vector, \tt{val} can be an int or float, and all items in this Vector will be set to
		the float representation of \tt{val}.

		If \tt{val} is a function, it should take an integer that is the index of the element, and should return one value
		the appropriate type which will be the value placed in that index. This function is called once for each element
		this Vector.

		If \tt{val} is an array, it should be the same length as this Vector, be single-dimensional, and all elements must be
		valid types for this Vector. The values will be assigned element-for-element into this Vector.

		Lastly, if \tt{val} is a Vector, it must be the same length and type, and the data will be copied from \tt{val} into
		this Vector.`},

		{kind: "function", name: "fillRange",
		params: [Param("lo", "int", "0"), Param("hi", "int", "#this"), Param("val", "int|float|function|array|Vector")],
		docs:
		`Same as \link{fill}, but operates on only a slice of this Vector instead of on the entire length.

		\b{Also aliased to opSliceAssign.} This means that any slice-assignment of the form \tt{"v[x, y] = b"} can be written
		equivalently as \tt{"v.fillRange(x, y, b)"}, and vice versa.

		\param[lo] is the lower slice index.
		\param[hi] is the upper slice index.
		\param[val] is the same as for \link{fill}.`},

		{kind: "function", name: "opEquals",
		params: [Param("other", "Vector")],
		docs:
		`Checks if two Vectors have the same contents. Both Vectors must be the same type.

		\param[other] is the Vector to compare \tt{this} to.
		\returns \tt{true} if \tt{this} and \tt{other} are the same length and contain the same data, or \tt{false} otherwise.
		\throws[exceptions.ValueException] if \tt{other}'s type differs from \tt{this}'s.`},

		{kind: "function", name: "opCmp",
		params: [Param("other", "Vector")],
		docs:
		`Compares two Vectors lexicographically. Both Vectors must be the same type.

		\param[other] is the Vector to compare \tt{this} to.
		\returns a negative integer if \tt{this} compares less than \tt{other}, positive if \tt{this} compares greater than \tt{other},
		and 0 if \tt{this} and \tt{other} have the same length and contents.
		\throws[exceptions.ValueException] if \tt{other}'s type differs from \tt{this}'s.`},

		{kind: "function", name: "opLength",
		params: [],
		docs:
		`Gets the number of items in this Vector.

		\returns the length as an integer.`},

		{kind: "function", name: "opLengthAssign",
		params: [Param("len", "int")],
		docs:
		`Sets the number of items in this Vector.

		\param[len] is the new length.
		\throws[exceptions.ValueException] if this Vector's memblock does not own its data.
		\throws[exceptions.RangeException] if \tt{len} is invalid.`},

		{kind: "function", name: "opIndex",
		params: [Param("idx", "int")],
		docs:
		`Gets a single item from this Vector at the given index.

		\param[idx] is the index of the item to retrieve. Can be negative.
		\throws[exception.BoundsException] if \tt{idx} is invalid.`},

		{kind: "function", name: "opIndex",
		params: [Param("idx", "int"), Param("val", "int|float")],
		docs:
		`Sets a single item in this Vector at the given index to the given value.

		\param[idx] is the index of the item to set. Can be negative.
		\param[val] is the value to be set.
		\throws[exception.BoundsException] if \tt{idx} is invalid.`},

		{kind: "function", name: "opSlice",
		params: [Param("lo", "int", "0"), Param("hi", "int", "#this")],
		docs:
		`Creates a new Vector whose data is a copy of a slice of this Vector.

		Note that in the case that you want to copy data from a slice of one Vector into a slice of another (or even
		between parts of the same Vector), you can avoid creating unnecessary temporaries by using \link{copyRange}
		instead.

		\param[lo] is lower slice index into this Vector.
		\param[hi] is upper slice index into this Vector.
		\returns a new Vector with the same type as \tt{this}, whose data is a copy of the given slice.
		\throws[exception.BoundsException] if \tt{lo} and \tt{hi} are invalid.`},

		{kind: "function", name: "opApply",
		params: [Param("mode", "string", "\"\"")],
		docs:
		`Allows you to iterate over the contents of a Vector using a \tt{foreach} loop.

		This works just like the \tt{opApply} defined for arrays. The indices in the loop will be the element index
		followed by the element value. You can iterate in reverse by passing the string value \tt{"reverse"} as the
		\tt{mode} argument. For example:

\code
local v = Vector.range("i32", 1, 6)
foreach(i, val; v) write(val) // prints 12345
foreach(i, val; v, "reverse") write(val) // prints 54321
\endcode

		\param[mode] is the iteration mode. The only valid modes are \tt{"reverse"}, which runs iteration backwards,
		and the empty string \{""}, which is normal forward iteration.
		\throws[exceptions.ValueException] if \tt{mode} is invalid.`},

		{kind: "field", name: "opSerialize",
		docs:
		`These are methods meant to work with the \tt{serialization} library, allowing instances of \tt{Vector} to be
		serialized and deserialized.`},

		{kind: "field", name: "opDeserialize", docs: `ditto`},

		{kind: "function", name: "opCat",
		params: [Param("other", "int|float|Vector")],
		docs:
		`Concatenates this Vector with a number or another Vector, returning a new Vector that is the concatenation
		of the two.

		\tt{opCat_r} is to allow reverse concatenation, where the value is on the left and the Vector is on the right.

		\param[other] is either a number of the appropriate type, or another Vector. If \tt{other} is a Vector, it
		must be the same type as \tt{this}.
		\returns the new Vector object.
		\throws[exceptions.ValueException] if \tt{other} is a Vector and its type differs from \tt{this}'s.`},

		{kind: "function", name: "opCat_r", docs: `ditto`, params: [Param("other", "int|float")]},

		{kind: "function", name: "opCatAssign",
		params: [Param("vararg", "vararg")],
		docs:
		`Appends one or more values or Vectors to the end of this Vector, in place.

		\param[vararg] is one or more values, each of which must be either a number of the appropriate type, or a Vector
		whose type is the same as \tt{this}'s. All the arguments will be appended to the end of this Vector in order.
		\throws[exceptions.ParamException] if no varargs were passed.
		\throws[exceptions.ValueException] if this Vector's memblock does not own its data.
		\throws[exceptions.ValueException] if one of the varargs is a Vector whose type differs from \tt{this}'s.
		\throws[exceptions.RangeException] if this memblock grows too large.`},

		{kind: "function", name: "opAdd",
		params: [Param("other", "int|float|Vector")],
		docs:
		`These all implement binary mathematical operators on Vectors. All return new Vector objects as the results.

		When performing an operation on a Vector and a number, the operation will be performed on each element of the
		Vector using the number as the other operand. When performing an operation on two Vectors, they must be the
		same type and length, and the operation is performed on each pair of elements.

		\param[other] is the second operand in the operation.
		\returns the new Vector whos values are the result of the operation.
		\throws[exceptions.ValueException] if \tt{other} is a Vector and it is not the same length and type as \tt{this}.`},

		{kind: "function", name: "opSub",   docs: `ditto`, params: [Param("other", "int|float|Vector")]},
		{kind: "function", name: "opMul",   docs: `ditto`, params: [Param("other", "int|float|Vector")]},
		{kind: "function", name: "opDiv",   docs: `ditto`, params: [Param("other", "int|float|Vector")]},
		{kind: "function", name: "opMod",   docs: `ditto`, params: [Param("other", "int|float|Vector")]},
		{kind: "function", name: "opAdd_r", docs: `ditto`, params: [Param("other", "int|float|Vector")]},
		{kind: "function", name: "opSub_r", docs: `ditto`, params: [Param("other", "int|float|Vector")]},
		{kind: "function", name: "opMul_r", docs: `ditto`, params: [Param("other", "int|float|Vector")]},
		{kind: "function", name: "opDiv_r", docs: `ditto`, params: [Param("other", "int|float|Vector")]},
		{kind: "function", name: "opMod_r", docs: `ditto`, params: [Param("other", "int|float|Vector")]},

		{kind: "function", name: "opAddAssign",
		params: [Param("other", "int|float|Vector")],
		docs:
		`These all implement reflexive mathematical operators on Vectors. All operate in-place on this Vector.

		The behavior is otherwise identical to the binary operator metamethods.

		\param[other] is the right-hand side of the operation.
		\throws[exceptions.ValueException] if \tt{other} is a Vector and it is not the same length and type as \tt{this}.`},

		{kind: "function", name: "opSubAssign", docs: `ditto`, params: [Param("other", "int|float|Vector")]},
		{kind: "function", name: "opMulAssign", docs: `ditto`, params: [Param("other", "int|float|Vector")]},
		{kind: "function", name: "opDivAssign", docs: `ditto`, params: [Param("other", "int|float|Vector")]},
		{kind: "function", name: "opModAssign", docs: `ditto`, params: [Param("other", "int|float|Vector")]},

		{kind: "function", name: "revSub",
		params: [Param("other", "int|float|Vector")],
		docs:
		`These allow you to perform in-place reflexive operations where this Vector will be used as the second operand instead
		of as the first.

		For example, doing \tt{"v -= 5"} will subtract 5 from each element in \tt{v}, but doing \tt{"v.revSub(5)"} will instead
		subtract each element in \tt{v} from 5.

		The behavior is otherwise identical to the reflexive operator metamethods.

		\param[other] is the left-hand side of the operation.
		\throws[exceptions.ValueException] if \tt{other} is a Vector and it is not the same length and type as \tt{this}.`},

		{kind: "function", name: "revDiv", docs: `ditto`, params: [Param("other", "int|float|Vector")]},
		{kind: "function", name: "revMod", docs: `ditto`, params: [Param("other", "int|float|Vector")]}
	];
}