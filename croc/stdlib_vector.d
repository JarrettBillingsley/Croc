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

// import tango.math.Math;
// import tango.stdc.string;
// import Utf = tango.text.convert.Utf;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.stdlib_utils;
import croc.types;

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
		c.allocator("allocator", &BasicClassAllocator!(NumFields, 0));

		registerField(t, 1, "type",        &type);
		registerField(t, 0, "itemSize",    &itemSize);

		registerField(t, 0, "dup",         &mbDup);
		registerField(t, 0, "reverse",     &reverse);
		registerField(t, 0, "sort",        &sort);
		registerField(t, 1, "apply",       &apply);
		registerField(t, 1, "map",         &map);
		registerField(t, 0, "min",         &min);
		registerField(t, 0, "max",         &max);
		registerField(t, 2, "insert",      &mb_insert);
		registerField(t, 2, "remove",      &remove);
		registerField(t, 1, "pop",         &mb_pop);
		registerField(t, 0, "sum",         &sum);
		registerField(t, 0, "product",     &product);
		registerField(t, 5, "copyRange",   &copyRange);
		registerField(t, 1, "fill",        &fill);
		registerField(t, 3, "fillRange",   &fillRange);
		field(t, -1, "fillRange"); fielda(t, -2, "opSliceAssign");

		registerField(t, 1, "opEquals",    &memblockOpEquals);
		registerField(t, 1, "opCmp",       &memblockOpCmp);

			newFunction(t, &memblockIterator, "memblock.iterator");
			newFunction(t, &memblockIteratorReverse, "memblock.iteratorReverse");
		registerField(t, 1, "opApply",     &memblockOpApply,  2);

		registerField(t, 1, "opCat",       &opCat);
		registerField(t, 1, "opCat_r",     &opCat_r);
		registerField(t,    "opCatAssign", &opCatAssign);
		field(t, -1, "opCatAssign"); fielda(t, -2, "append");

		registerField(t, 1, "opAdd",       &opAdd);
		registerField(t, 1, "opAddAssign", &opAddAssign);
		registerField(t, 1, "opSub",       &opSub);
		registerField(t, 1, "opSub_r",     &opSub_r);
		registerField(t, 1, "opSubAssign", &opSubAssign);
		registerField(t, 1, "revSub",      &revSub);
		registerField(t, 1, "opMul",       &opMul);
		registerField(t, 1, "opMulAssign", &opMulAssign);
		registerField(t, 1, "opDiv",       &opDiv);
		registerField(t, 1, "opDiv_r",     &opDiv_r);
		registerField(t, 1, "opDivAssign", &opDivAssign);
		registerField(t, 1, "revDiv",      &revDiv);
		registerField(t, 1, "opMod",       &opMod);
		registerField(t, 1, "opMod_r",     &opMod_r);
		registerField(t, 1, "opModAssign", &opModAssign);
		registerField(t, 1, "revMod",      &revMod);

		field(t, -1, "opAdd"); fielda(t, -2, "opAdd_r");
		field(t, -1, "opMul"); fielda(t, -2, "opMul_r");
	});

// 	field(t, -1, "fillRange");
// 	fielda(t, -2, "opSliceAssign");
//
// 	field(t, -1, "opCatAssign");
// 	fielda(t, -2, "append");

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

enum
{
	Data,
	Length,

	NumFields
}

	// If this changes, grep ORDER MEMBLOCK TYPE
	enum TypeCode : ubyte
	{
		v,
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
		char[] name;
	}

	const TypeStruct[] typeStructs =
	[
		TypeCode.i8:  { TypeCode.i8,  1, "i8"  },
		TypeCode.i16: { TypeCode.i16, 2, "i16" },
		TypeCode.i32: { TypeCode.i32, 4, "i32" },
		TypeCode.i64: { TypeCode.i64, 8, "i64" },
		TypeCode.u8:  { TypeCode.u8,  1, "u8"  },
		TypeCode.u16: { TypeCode.u16, 2, "u16" },
		TypeCode.u32: { TypeCode.u32, 4, "u32" },
		TypeCode.u64: { TypeCode.u64, 8, "u64" },
		TypeCode.f32: { TypeCode.f32, 4, "f32" },
		TypeCode.f64: { TypeCode.f64, 8, "f64" }
	];

	uword itemLength;
	TypeStruct* kind;

	// Indexes the memblock and returns the value. Expects the index to be in a valid range and the kind not to be void.
	CrocValue index(CrocMemblock* m, uword idx)
	{
		assert(idx < m.itemLength);

		switch(m.kind.code)
		{
			case CrocMemblock.TypeCode.i8:  return CrocValue(cast(crocint)(cast(byte*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.i16: return CrocValue(cast(crocint)(cast(short*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.i32: return CrocValue(cast(crocint)(cast(int*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.i64: return CrocValue(cast(crocint)(cast(long*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.u8:  return CrocValue(cast(crocint)(cast(ubyte*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.u16: return CrocValue(cast(crocint)(cast(ushort*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.u32: return CrocValue(cast(crocint)(cast(uint*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.u64: return CrocValue(cast(crocint)(cast(ulong*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.f32: return CrocValue(cast(crocfloat)(cast(float*)m.data.ptr)[idx]);
			case CrocMemblock.TypeCode.f64: return CrocValue(cast(crocfloat)(cast(double*)m.data.ptr)[idx]);

			default: assert(false);
		}
	}

	// Index assigns a value into a memblock. Expects the index to be in a valid range, the kind not to be void, and the value
	// to be of the appropriate type.
	void indexAssign(CrocMemblock* m, uword idx, CrocValue val)
	{
		assert(idx < m.itemLength);

		switch(m.kind.code)
		{
			case CrocMemblock.TypeCode.i8:  return (cast(byte*)m.data.ptr)[idx]   = cast(byte)val.mInt;
			case CrocMemblock.TypeCode.i16: return (cast(short*)m.data.ptr)[idx]  = cast(short)val.mInt;
			case CrocMemblock.TypeCode.i32: return (cast(int*)m.data.ptr)[idx]    = cast(int)val.mInt;
			case CrocMemblock.TypeCode.i64: return (cast(long*)m.data.ptr)[idx]   = cast(long)val.mInt;
			case CrocMemblock.TypeCode.u8:  return (cast(ubyte*)m.data.ptr)[idx]  = cast(ubyte)val.mInt;
			case CrocMemblock.TypeCode.u16: return (cast(ushort*)m.data.ptr)[idx] = cast(ushort)val.mInt;
			case CrocMemblock.TypeCode.u32: return (cast(uint*)m.data.ptr)[idx]   = cast(uint)val.mInt;
			case CrocMemblock.TypeCode.u64: return (cast(ulong*)m.data.ptr)[idx]  = cast(ulong)val.mInt;
			case CrocMemblock.TypeCode.f32: return (cast(float*)m.data.ptr)[idx]  = val.type == CrocValue.Type.Int ? cast(float)val.mInt  : cast(float)val.mFloat;
			case CrocMemblock.TypeCode.f64: return (cast(double*)m.data.ptr)[idx] = val.type == CrocValue.Type.Int ? cast(double)val.mInt : cast(double)val.mFloat;

			default: assert(false);
		}
	}
	
		TypeStruct* ts = void;

	switch(type)
	{
		case "i8" : ts = &CrocMemblock.typeStructs[TypeCode.i8];  break;
		case "i16": ts = &CrocMemblock.typeStructs[TypeCode.i16]; break;
		case "i32": ts = &CrocMemblock.typeStructs[TypeCode.i32]; break;
		case "i64": ts = &CrocMemblock.typeStructs[TypeCode.i64]; break;
		case "u8" : ts = &CrocMemblock.typeStructs[TypeCode.u8];  break;
		case "u16": ts = &CrocMemblock.typeStructs[TypeCode.u16]; break;
		case "u32": ts = &CrocMemblock.typeStructs[TypeCode.u32]; break;
		case "u64": ts = &CrocMemblock.typeStructs[TypeCode.u64]; break;
		case "f32": ts = &CrocMemblock.typeStructs[TypeCode.f32]; break;
		case "f64": ts = &CrocMemblock.typeStructs[TypeCode.f64]; break;

		default:
			throwStdException(t, "ValueException", __FUNCTION__ ~ " - Invalid memblock type code '{}'", type);
	}

/**
Constructs a memblock from a D array and pushes the new instance onto the stack.
The resulting memblock holds a $(B copy) of the data and owns its data.

The array type must be convertible to a single-dimensional array of any integer
type or a float or double array.

Params:
	arr = The array from which the data will be copied into the new memblock.

Returns:
	The stack index of the newly-pushed memblock.
*/
word memblockFromDArray(_T)(CrocThread* t, _T[] arr)
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

/**
Constructs a memblock from a D array and pushes it onto the stack. The resulting
memblock is a $(B view) into the data. That is, modifying the contents of the
returned memblock will actually modify the array that you passed.

Note that you must ensure that the D array is not collected while this memblock
is around. The memblock will not keep it around for you.

The array type must be convertible to a single-dimensional array of any integer
type or a float or double array.

Params:
	arr = The array to which the new memblock will refer.

Returns:
	The stack index of the newly-pushed memblock.
*/
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

/**
Gets the element type of a memblock.

Params:
	mb = The stack index of the memblock object.

Returns:
	A string containing the type code for the given memblock. This points into ROM, so don't modify it, but
	at least you don't have to worry about it being collected.
*/
char[] memblockType(CrocThread* t, word mb)
{
	mixin(apiCheckNumParams!("1"));
	auto m = getMemblock(t, mb);

	if(m is null)
	{
		pushTypeString(t, mb);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - mb must be a memblock, not a '{}'", getString(t, -1));
	}

	return m.kind.name;
}

/**
Sets the element type of a memblock. You cannot change the element type of void memblocks, but you can
change the type of non-void memblocks to void. When changing types, the size of the memblock in bytes
must be an even multiple of the size of the new element type, or else an error is thrown. For instance,
if you have a memblock of type "u8" and its length is 7, you will get an error if you try to change the
type to "u16", as 7 is not a valid multiple of 2, the size of a "u16".

Params:
	mb = The stack index of the memblock object.
	type = A string containing the type code of the new type. Must be one of the valid type codes, or an
		error is thrown.
*/
void setMemblockType(CrocThread* t, word mb, char[] type)
{
	alias CrocMemblock.TypeStruct TypeStruct;
	alias CrocMemblock.TypeCode TypeCode;

	mixin(apiCheckNumParams!("1"));
	auto m = getMemblock(t, mb);

	if(m is null)
	{
		pushTypeString(t, mb);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - mb must be a memblock, not a '{}'", getString(t, -1));
	}

	TypeStruct* ts;

	switch(type)
	{
		case "i8" : ts = &CrocMemblock.typeStructs[TypeCode.i8];  break;
		case "i16": ts = &CrocMemblock.typeStructs[TypeCode.i16]; break;
		case "i32": ts = &CrocMemblock.typeStructs[TypeCode.i32]; break;
		case "i64": ts = &CrocMemblock.typeStructs[TypeCode.i64]; break;
		case "u8" : ts = &CrocMemblock.typeStructs[TypeCode.u8];  break;
		case "u16": ts = &CrocMemblock.typeStructs[TypeCode.u16]; break;
		case "u32": ts = &CrocMemblock.typeStructs[TypeCode.u32]; break;
		case "u64": ts = &CrocMemblock.typeStructs[TypeCode.u64]; break;
		case "f32": ts = &CrocMemblock.typeStructs[TypeCode.f32]; break;
		case "f64": ts = &CrocMemblock.typeStructs[TypeCode.f64]; break;

		default:
			throwStdException(t, "ValueException", __FUNCTION__ ~ " - Invalid memblock type code '{}'", type);
	}

	if(m.kind is ts)
		return;

	auto byteSize = m.itemLength * m.kind.itemSize;

	if(byteSize % ts.itemSize != 0)
		throwStdException(t, "ValueException", __FUNCTION__ ~ " - Memblock's byte size is not an even multiple of new type's item size");
	
	m.kind = ts;
	m.itemLength = byteSize / ts.itemSize;
}
/**
Reassign an existing memblock so that its data is a view of a D array. If the
memblock owns its data, it is freed. The type is also set to the appropriate
type code corresponding to the D array. This is like memblockViewDArray except
that it changes an existing memblock rather than creating a new one.

The same caveats and restrictions that apply to memblockViewDArray apply to this
function as well.

Params:
	slot = The stack index of the memblock to reassign.
	arr = The array to which the given memblock will refer.
*/
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
}



CrocMemblock* _getThis(CrocThread* t)
{
	checkInstParam(t, 0, "Vector");
	getExtraVal(t, 0, Data);

	if(!isMemblock(t, -1))
		throwStdException(t, "ValueException", "Attempting to call a method on an uninitialized Vector");

	auto ret = getMemblock(t, -1);
	pop(t);
	return ret;
}

CrocMemblock* _getData(CrocThread* t, word idx)
{
	getExtraVal(t, idx, Data);

	if(!isMemblock(t, -1))
		throwStdException(t, "ValueException", "Attempting to operate on an uninitialized Vector");

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
				throwStdException(t, "RangeException", "Vector too big ({} elements)", size);
			l <<= 1;
		}

		push(t, CrocValue(mb));
		lenai(t, -1, l);
		pop(t);
	}
}


	void init(CrocThread* t)
	{
		makeModule(t, "memblock", function uword(CrocThread* t)
		{
			register(t, 3, "new", &memblock_new);
			register(t, 4, "range", &range);

			newNamespace(t, "memblock");
				registerField(t, 1, "type",        &type);
				registerField(t, 0, "itemSize",    &itemSize);
				registerField(t, 2, "toArray",     &toArray);
				registerField(t, 0, "toString",    &memblockToString);

				registerField(t, 0, "dup",         &mbDup);
				registerField(t, 0, "reverse",     &reverse);
				registerField(t, 0, "sort",        &sort);
				registerField(t, 1, "apply",       &apply);
				registerField(t, 1, "map",         &map);
				registerField(t, 0, "min",         &min);
				registerField(t, 0, "max",         &max);
				registerField(t, 2, "insert",      &mb_insert);
				registerField(t, 1, "pop",         &mb_pop);
				registerField(t, 2, "remove",      &remove);
				registerField(t, 0, "sum",         &sum);
				registerField(t, 0, "product",     &product);
				registerField(t, 5, "copyRange",   &copyRange);
				registerField(t, 1, "fill",        &fill);
				registerField(t, 3, "fillRange",   &fillRange);
				field(t, -1, "fillRange"); fielda(t, -2, "opSliceAssign");

				registerField(t, 1, "readByte",    &rawRead!(byte));
				registerField(t, 1, "readShort",   &rawRead!(short));
				registerField(t, 1, "readInt",     &rawRead!(int));
				registerField(t, 1, "readLong",    &rawRead!(long));
				registerField(t, 1, "readUByte",   &rawRead!(ubyte));
				registerField(t, 1, "readUShort",  &rawRead!(ushort));
				registerField(t, 1, "readUInt",    &rawRead!(uint));
				registerField(t, 1, "readULong",   &rawRead!(ulong));
				registerField(t, 1, "readFloat",   &rawRead!(float));
				registerField(t, 1, "readDouble",  &rawRead!(double));

				registerField(t, 2, "writeByte",   &rawWrite!(byte));
				registerField(t, 2, "writeShort",  &rawWrite!(short));
				registerField(t, 2, "writeInt",    &rawWrite!(int));
				registerField(t, 2, "writeLong",   &rawWrite!(long));
				registerField(t, 2, "writeUByte",  &rawWrite!(ubyte));
				registerField(t, 2, "writeUShort", &rawWrite!(ushort));
				registerField(t, 2, "writeUInt",   &rawWrite!(uint));
				registerField(t, 2, "writeULong",  &rawWrite!(ulong));
				registerField(t, 2, "writeFloat",  &rawWrite!(float));
				registerField(t, 2, "writeDouble", &rawWrite!(double));

				registerField(t, 4, "rawCopy",     &rawCopy);

				registerField(t, 1, "opEquals",    &memblockOpEquals);
				registerField(t, 1, "opCmp",       &memblockOpCmp);

					newFunction(t, &memblockIterator, "memblock.iterator");
					newFunction(t, &memblockIteratorReverse, "memblock.iteratorReverse");
				registerField(t, 1, "opApply",     &memblockOpApply,  2);

				registerField(t, 1, "opCat",       &opCat);
				registerField(t, 1, "opCat_r",     &opCat_r);
				registerField(t,    "opCatAssign", &opCatAssign);
				field(t, -1, "opCatAssign"); fielda(t, -2, "append");

				registerField(t, 1, "opAdd",       &opAdd);
				registerField(t, 1, "opAddAssign", &opAddAssign);
				registerField(t, 1, "opSub",       &opSub);
				registerField(t, 1, "opSub_r",     &opSub_r);
				registerField(t, 1, "opSubAssign", &opSubAssign);
				registerField(t, 1, "revSub",      &revSub);
				registerField(t, 1, "opMul",       &opMul);
				registerField(t, 1, "opMulAssign", &opMulAssign);
				registerField(t, 1, "opDiv",       &opDiv);
				registerField(t, 1, "opDiv_r",     &opDiv_r);
				registerField(t, 1, "opDivAssign", &opDivAssign);
				registerField(t, 1, "revDiv",      &revDiv);
				registerField(t, 1, "opMod",       &opMod);
				registerField(t, 1, "opMod_r",     &opMod_r);
				registerField(t, 1, "opModAssign", &opModAssign);
				registerField(t, 1, "revMod",      &revMod);

				field(t, -1, "opAdd"); fielda(t, -2, "opAdd_r");
				field(t, -1, "opMul"); fielda(t, -2, "opMul_r");
			setTypeMT(t, CrocValue.Type.Memblock);

			return 0;
		});

		importModuleNoNS(t, "memblock");
	}

	uword memblock_new(CrocThread* t)
	{
		auto typeCode = checkStringParam(t, 1);
		word fillerSlot = 0;

		if(!isValidIndex(t, 2))
			newMemblock(t, typeCode, 0);
		else
		{
			if(isInt(t, 2))
			{
				if(isValidIndex(t, 3))
					fillerSlot = 3;

				auto size = getInt(t, 2);

				if(size < 0 || size > uword.max)
					throwStdException(t, "RangeException", "Invalid size ({})", size);

				newMemblock(t, typeCode, cast(uword)size);
			}
			else if(isArray(t, 2))
			{
				newMemblock(t, typeCode, cast(uword)len(t, 2));
				fillerSlot = 2;
			}
			else
				paramTypeError(t, 2, "int|array");
		}

		if(fillerSlot > 0)
		{
			dup(t);
			pushNull(t);
			dup(t, fillerSlot);
			methodCall(t, -3, "fill", 0);
		}

		return 1;
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
			throwStdException(t, "RangeException", "Memblock is too big ({} items)", size);

		newMemblock(t, type, cast(uword)size);
		auto ret = getMemblock(t, -1);
		auto val = v1;

		if(v2 < v1)
		{
			for(uword i = 0; val > v2; i++, val -= step)
				memblock.indexAssign(ret, i, CrocValue(val));
		}
		else
		{
			for(uword i = 0; val < v2; i++, val += step)
				memblock.indexAssign(ret, i, CrocValue(val));
		}
	}

	uword range(CrocThread* t)
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

	uword type(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto numParams = stackSize(t) - 1;

		if(numParams == 0)
		{
			dup(t, 0);
			pushString(t, memblockType(t, -1));
			return 1;
		}
		else
		{
			auto type = checkStringParam(t, 1);
			dup(t, 0);
			setMemblockType(t, -1, type);
			return 0;
		}
	}

	uword itemSize(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		pushInt(t, getMemblock(t, 0).kind.itemSize);
		return 1;
	}

	uword toArray(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		auto lo = optIntParam(t, 1, 0);
		auto hi = optIntParam(t, 2, mb.itemLength);

		if(lo < 0)
			lo += mb.itemLength;

		if(hi < 0)
			hi += mb.itemLength;

		if(lo < 0 || lo > hi || hi > mb.itemLength)
			throwStdException(t, "BoundsException", "Invalid slice indices: {} .. {} (length: {})", lo, hi, mb.itemLength);

		auto ret = newArray(t, cast(uword)(hi - lo));

		for(uword i = cast(uword)lo, j = 0; i < cast(uword)hi; i++, j++)
		{
			push(t, memblock.index(mb, i));
			idxai(t, ret, j);
		}

		return 1;
	}

	version(CrocBuiltinDocs) Docs memblockToString_docs = {kind: "function", name: "toString", docs:
	"Returns a string representation of this memblock in the form `\"memblock(type)[items]\"`; for example,
	`\"memblock.range(\"i32\", 1, 5).toString()\"` would yield `\"memblock(i32)[1, 2, 3, 4]\"`. If the memblock
	is of type void, then the result will instead be `\"memblock(v)[n bytes]\"`, where ''n'' is the length of
	the memblock.",
	params: [],
	extra: [Extra("section", "Memblock metamethods")]};

	uword memblockToString(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		auto b = StrBuffer(t);
		pushFormat(t, "memblock({})[", mb.kind.name);
		b.addTop();

		if(mb.kind.code == CrocMemblock.TypeCode.u64)
		{
			for(uword i = 0; i < mb.itemLength; i++)
			{
				if(i > 0)
					b.addString(", ");

				auto v = memblock.index(mb, i);
				pushFormat(t, "{}", cast(ulong)v.mInt);
				b.addTop();
			}
		}
		else
		{
			for(uword i = 0; i < mb.itemLength; i++)
			{
				if(i > 0)
					b.addString(", ");

				push(t, memblock.index(mb, i));
				pushToString(t, -1, true);
				insertAndPop(t, -2);
				b.addTop();
			}
		}

		b.addString("]");
		b.finish();
		return 1;
	}

	uword mbDup(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		newMemblock(t, mb.kind.name, mb.itemLength);
		auto n = getMemblock(t, -1);
		auto byteSize = mb.itemLength * mb.kind.itemSize;
		(cast(ubyte*)n.data)[0 .. byteSize] = (cast(ubyte*)mb.data)[0 .. byteSize];

		return 1;
	}

	uword reverse(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		switch(mb.kind.itemSize)
		{
			case 1: (cast(ubyte*)mb.data) [0 .. mb.itemLength].reverse; break;
			case 2: (cast(ushort*)mb.data)[0 .. mb.itemLength].reverse; break;
			case 4: (cast(uint*)mb.data)  [0 .. mb.itemLength].reverse; break;
			case 8: (cast(ulong*)mb.data) [0 .. mb.itemLength].reverse; break;

			default:
				throwStdException(t, "ValueException", "Not a horrible error, but somehow a memblock type must've been added that doesn't have 1-, 2-, 4-, or 8-byte elements, so I don't know how to reverse it.");
		}

		dup(t, 0);
		return 1;
	}

	uword sort(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		switch(mb.kind.code)
		{
			case TypeCode.i8:  (cast(byte*)mb.data)  [0 .. mb.itemLength].sort; break;
			case TypeCode.i16: (cast(short*)mb.data) [0 .. mb.itemLength].sort; break;
			case TypeCode.i32: (cast(int*)mb.data)   [0 .. mb.itemLength].sort; break;
			case TypeCode.i64: (cast(long*)mb.data)  [0 .. mb.itemLength].sort; break;
			case TypeCode.u8:  (cast(ubyte*)mb.data) [0 .. mb.itemLength].sort; break;
			case TypeCode.u16: (cast(ushort*)mb.data)[0 .. mb.itemLength].sort; break;
			case TypeCode.u32: (cast(uint*)mb.data)  [0 .. mb.itemLength].sort; break;
			case TypeCode.u64: (cast(ulong*)mb.data) [0 .. mb.itemLength].sort; break;
			case TypeCode.f32: (cast(float*)mb.data) [0 .. mb.itemLength].sort; break;
			case TypeCode.f64: (cast(double*)mb.data)[0 .. mb.itemLength].sort; break;
			default: assert(false);
		}

		dup(t, 0);
		return 1;
	}

	uword apply(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);
		checkParam(t, 1, CrocValue.Type.Function);

		void doLoop(bool function(CrocThread*, word) test, char[] typeMsg)
		{
			for(uword i = 0; i < mb.itemLength; i++)
			{
				dup(t, 1);
				pushNull(t);
				push(t, memblock.index(mb, i));
				rawCall(t, -3, 1);

				if(!test(t, -1))
				{
					pushTypeString(t, -1);
					throwStdException(t, "TypeException", "application function expected to return {}, not '{}'", typeMsg, getString(t, -1));
				}
				
				memblock.indexAssign(mb, i, *getValue(t, -1));
				pop(t);
			}
		}

		switch(mb.kind.code)
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

	uword map(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
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

	uword max(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		if(mb.itemLength == 0)
			throwStdException(t, "ValueException", "Memblock is empty");

		switch(mb.kind.code)
		{
			case TypeCode.i8:  pushInt(t, minMaxImpl!(">")(cast(byte[])mb.data));     break;
			case TypeCode.i16: pushInt(t, minMaxImpl!(">")(cast(short[])mb.data));    break;
			case TypeCode.i32: pushInt(t, minMaxImpl!(">")(cast(int[])mb.data));      break;
			case TypeCode.i64: pushInt(t, minMaxImpl!(">")(cast(long[])mb.data));     break;
			case TypeCode.u8:  pushInt(t, minMaxImpl!(">")(cast(ubyte[])mb.data));    break;
			case TypeCode.u16: pushInt(t, minMaxImpl!(">")(cast(ushort[])mb.data));   break;
			case TypeCode.u32: pushInt(t, minMaxImpl!(">")(cast(uint[])mb.data));     break;
			case TypeCode.u64: pushInt(t, cast(crocint)minMaxImpl!(">")(cast(ulong[])mb.data)); break;
			case TypeCode.f32: pushFloat(t, minMaxImpl!(">")(cast(float[])mb.data));  break;
			case TypeCode.f64: pushFloat(t, minMaxImpl!(">")(cast(double[])mb.data)); break;
			default: assert(false);
		}

		return 1;
	}

	uword min(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		if(mb.itemLength == 0)
			throwStdException(t, "ValueException", "Memblock is empty");

		switch(mb.kind.code)
		{
			case TypeCode.i8:  pushInt(t, minMaxImpl!("<")(cast(byte[])mb.data));     break;
			case TypeCode.i16: pushInt(t, minMaxImpl!("<")(cast(short[])mb.data));    break;
			case TypeCode.i32: pushInt(t, minMaxImpl!("<")(cast(int[])mb.data));      break;
			case TypeCode.i64: pushInt(t, minMaxImpl!("<")(cast(long[])mb.data));     break;
			case TypeCode.u8:  pushInt(t, minMaxImpl!("<")(cast(ubyte[])mb.data));    break;
			case TypeCode.u16: pushInt(t, minMaxImpl!("<")(cast(ushort[])mb.data));   break;
			case TypeCode.u32: pushInt(t, minMaxImpl!("<")(cast(uint[])mb.data));     break;
			case TypeCode.u64: pushInt(t, cast(crocint)minMaxImpl!("<")(cast(ulong[])mb.data)); break;
			case TypeCode.f32: pushFloat(t, minMaxImpl!("<")(cast(float[])mb.data));  break;
			case TypeCode.f64: pushFloat(t, minMaxImpl!("<")(cast(double[])mb.data)); break;
			default: assert(false);
		}

		return 1;
	}

	uword mb_insert(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);
		auto idx = checkIntParam(t, 1);
		checkAnyParam(t, 2);

		if(!mb.ownData)
			throwStdException(t, "ValueException", "Attempting to insert into a memblock which does not own its data");

		if(idx < 0)
			idx += mb.itemLength;

		// Yes, > and not >=, because you can insert at "one past" the end of the memblock.
		if(idx < 0 || idx > mb.itemLength)
			throwStdException(t, "BoundsException", "Invalid index: {} (length: {})", idx, mb.itemLength);

		void doResize(ulong otherLen)
		{
			ulong totalLen = mb.itemLength + otherLen;

			if(totalLen > uword.max)
				throwStdException(t, "ValueException", "Invalid size ({})", totalLen);

			auto oldLen = mb.itemLength;
			auto isize = mb.kind.itemSize;
			resizeArray(t, mb.data, cast(uword)totalLen * isize);
			mb.itemLength = cast(uword)totalLen;

			if(idx < oldLen)
			{
				auto end = idx + otherLen;
				auto numLeft = oldLen - idx;
				memmove(&mb.data[cast(uword)end * isize], &mb.data[cast(uword)idx * isize], cast(uint)(numLeft * isize));
			}
		}

		if(isMemblock(t, 2))
		{
			auto other = getMemblock(t, 2);

			if(mb.kind !is other.kind)
				throwStdException(t, "ValueException", "Attempting to insert a memblock of type '{}' into a memblock of type '{}'", other.kind.name, mb.kind.name);

			if(other.itemLength != 0)
			{
				doResize(other.itemLength);
				auto isize = mb.kind.itemSize;
				memcpy(&mb.data[cast(uword)idx * isize], other.data.ptr, other.itemLength * isize);
			}
		}
		else
		{
			// ORDER MEMBLOCK TYPE
			if(mb.kind.code <= TypeCode.u64)
				checkIntParam(t, 2);
			else
				checkNumParam(t, 2);

			doResize(1);
			memblock.indexAssign(mb, cast(uword)idx, *getValue(t, 2));
		}

		dup(t, 0);
		return 1;
	}

	uword mb_pop(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		if(!mb.ownData)
			throwStdException(t, "ValueException", "Attempting to pop from a memblock which does not own its data");

		if(mb.itemLength == 0)
			throwStdException(t, "ValueException", "Memblock is empty");

		auto index = optIntParam(t, 1, -1);

		if(index < 0)
			index += mb.itemLength;

		if(index < 0 || index >= mb.itemLength)
			throwStdException(t, "BoundsException", "Invalid index: {}", index);

		push(t, memblock.index(mb, cast(uword)index));

		auto isize = mb.kind.itemSize;

		if(index < mb.itemLength - 1)
			memmove(&mb.data[cast(uword)index * isize], &mb.data[(cast(uword)index + 1) * isize], cast(uint)((mb.itemLength - index - 1) * isize));

		resizeArray(t, mb.data, (mb.itemLength - 1) * isize);
		mb.itemLength--;

		return 1;
	}

	uword remove(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		if(!mb.ownData)
			throwStdException(t, "ValueException", "Attempting to remove from a memblock which does not own its data");

		if(mb.itemLength == 0)
			throwStdException(t, "ValueException", "Memblock is empty");

		auto lo = checkIntParam(t, 1);
		auto hi = optIntParam(t, 2, lo + 1);

		if(lo < 0)
			lo += mb.itemLength;

		if(hi < 0)
			hi += mb.itemLength;

		if(lo < 0 || lo > hi || hi > mb.itemLength)
			throwStdException(t, "BoundsException", "Invalid indices: {} .. {} (length: {})", lo, hi, mb.itemLength);

		if(lo != hi)
		{
			auto isize = mb.kind.itemSize;

			if(hi < mb.itemLength)
				memmove(&mb.data[cast(uword)lo * isize], &mb.data[cast(uword)hi * isize], cast(uint)((mb.itemLength - hi) * isize));

			auto diff = hi - lo;
			resizeArray(t, mb.data, cast(uword)((mb.itemLength - diff) * isize));
			mb.itemLength -= diff;
		}

		dup(t, 0);
		return 1;
	}

	uword sum(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		// ORDER MEMBLOCK TYPE
		if(mb.kind.code <= TypeCode.u64)
		{
			crocint res = 0;

			switch(mb.kind.code)
			{
				case TypeCode.i8:  foreach(val; cast(byte[])mb.data)   res += val; break;
				case TypeCode.i16: foreach(val; cast(short[])mb.data)  res += val; break;
				case TypeCode.i32: foreach(val; cast(int[])mb.data)    res += val; break;
				case TypeCode.i64: foreach(val; cast(long[])mb.data)   res += val; break;
				case TypeCode.u8:  foreach(val; cast(ubyte[])mb.data)  res += val; break;
				case TypeCode.u16: foreach(val; cast(ushort[])mb.data) res += val; break;
				case TypeCode.u32: foreach(val; cast(uint[])mb.data)   res += val; break;
				case TypeCode.u64: foreach(val; cast(ulong[])mb.data)  res += val; break;
				default: assert(false);
			}

			pushInt(t, res);
		}
		else
		{
			crocfloat res = 0.0;

			switch(mb.kind.code)
			{
				case TypeCode.f32: foreach(val; cast(float[])mb.data)  res += val; break;
				case TypeCode.f64: foreach(val; cast(double[])mb.data) res += val; break;
				default: assert(false);
			}

			pushFloat(t, res);
		}

		return 1;
	}

	uword product(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		// ORDER MEMBLOCK TYPE
		if(mb.kind.code <= TypeCode.u64)
		{
			crocint res = 1;

			switch(mb.kind.code)
			{
				case TypeCode.i8:  foreach(val; cast(byte[])mb.data)   res *= val; break;
				case TypeCode.i16: foreach(val; cast(short[])mb.data)  res *= val; break;
				case TypeCode.i32: foreach(val; cast(int[])mb.data)    res *= val; break;
				case TypeCode.i64: foreach(val; cast(long[])mb.data)   res *= val; break;
				case TypeCode.u8:  foreach(val; cast(ubyte[])mb.data)  res *= val; break;
				case TypeCode.u16: foreach(val; cast(ushort[])mb.data) res *= val; break;
				case TypeCode.u32: foreach(val; cast(uint[])mb.data)   res *= val; break;
				case TypeCode.u64: foreach(val; cast(ulong[])mb.data)  res *= val; break;
				default: assert(false);
			}

			pushInt(t, res);
		}
		else
		{
			crocfloat res = 1.0;

			switch(mb.kind.code)
			{
				case TypeCode.f32: foreach(val; cast(float[])mb.data)  res *= val; break;
				case TypeCode.f64: foreach(val; cast(double[])mb.data) res *= val; break;
				default: assert(false);
			}

			pushFloat(t, res);
		}

		return 1;
	}

	uword copyRange(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);
		auto lo = optIntParam(t, 1, 0);
		auto hi = optIntParam(t, 2, mb.itemLength);
		
		if(lo < 0)
			lo += mb.itemLength;

		if(hi < 0)
			hi += mb.itemLength;

		if(lo < 0 || lo > hi || hi > mb.itemLength)
			throwStdException(t, "BoundsException", "Invalid destination slice indices: {} .. {} (length: {})", lo, hi, mb.itemLength);

		checkParam(t, 3, CrocValue.Type.Memblock);
		auto other = getMemblock(t, 3);
		
		if(mb.kind !is other.kind)
			throwStdException(t, "ValueException", "Attempting to copy a memblock of type '{}' into a memblock of type '{}'", other.kind.name, mb.kind.name);

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

		auto isize = mb.kind.itemSize;
		memcpy(&mb.data[cast(uword)lo * isize], &other.data[cast(uword)lo2 * isize], cast(uword)(hi - lo) * isize);

		dup(t, 0);
		return 1;
	}

	void fillImpl(CrocThread* t, CrocMemblock* mb, word filler, uword lo, uword hi)
	{
		if(isMemblock(t, filler))
		{
			auto other = getMemblock(t, filler);

			if(mb.kind !is other.kind)
				throwStdException(t, "ValueException", "Attempting to fill a memblock of type '{}' using a memblock of type '{}'", mb.kind.name, other.kind.name);

			if(other.itemLength != (hi - lo))
				throwStdException(t, "ValueException", "Length of destination ({}) and length of source ({}) do not match", hi - lo, other.itemLength);

			if(mb is other)
				return; // only way this can be is if we're assigning a memblock's entire contents into itself, which is a no-op.

			auto isize = mb.kind.itemSize;
			memcpy(&mb.data[lo * isize], other.data.ptr, other.itemLength * isize);
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
			
			// ORDER MEMBLOCK TYPE
			if(mb.kind.code <= TypeCode.u64)
			{
				for(uword i = lo; i < hi; i++)
				{
					callFunc(i);

					if(!isInt(t, -1))
					{
						pushTypeString(t, -1);
						throwStdException(t, "TypeException", "filler function expected to return an 'int', not '{}'", getString(t, -1));
					}
					
					memblock.indexAssign(mb, i, *getValue(t, -1));
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

					memblock.indexAssign(mb, i, *getValue(t, -1));
					pop(t);
				}
			}
		}
		else if(isNum(t, filler))
		{
			switch(mb.kind.code)
			{
				case TypeCode.i8:  auto val = checkIntParam(t, filler); (cast(byte[])  mb.data)[lo .. hi] = cast(byte)val;   break;
				case TypeCode.i16: auto val = checkIntParam(t, filler); (cast(short[]) mb.data)[lo .. hi] = cast(short)val;  break;
				case TypeCode.i32: auto val = checkIntParam(t, filler); (cast(int[])   mb.data)[lo .. hi] = cast(int)val;    break;
				case TypeCode.i64: auto val = checkIntParam(t, filler); (cast(long[])  mb.data)[lo .. hi] = cast(long)val;   break;
				case TypeCode.u8:  auto val = checkIntParam(t, filler); (cast(ubyte[]) mb.data)[lo .. hi] = cast(ubyte)val;  break;
				case TypeCode.u16: auto val = checkIntParam(t, filler); (cast(ushort[])mb.data)[lo .. hi] = cast(ushort)val; break;
				case TypeCode.u32: auto val = checkIntParam(t, filler); (cast(uint[])  mb.data)[lo .. hi] = cast(uint)val;   break;
				case TypeCode.u64: auto val = checkIntParam(t, filler); (cast(ulong[]) mb.data)[lo .. hi] = cast(ulong)val;  break;
				case TypeCode.f32: auto val = checkNumParam(t, filler); (cast(float[]) mb.data)[lo .. hi] = cast(float)val;  break;
				case TypeCode.f64: auto val = checkNumParam(t, filler); (cast(double[])mb.data)[lo .. hi] = cast(double)val; break;
				default: assert(false);
			}
		}
		else if(isArray(t, filler))
		{
			if(len(t, filler) != (hi - lo))
				throwStdException(t, "ValueException", "Length of destination ({}) and length of array ({}) do not match", hi - lo, len(t, filler));

			// ORDER MEMBLOCK TYPE
			if(mb.kind.code <= TypeCode.u64)
			{
				for(uword i = lo, ai = 0; i < hi; i++, ai++)
				{
					idxi(t, filler, ai);

					if(!isInt(t, -1))
					{
						pushTypeString(t, -1);
						throwStdException(t, "ValueException", "array element {} expected to be 'int', not '{}'", ai, getString(t, -1));
					}

					memblock.indexAssign(mb, i, *getValue(t, -1));
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

					memblock.indexAssign(mb, i, *getValue(t, -1));
					pop(t);
				}
			}
		}
		else
			paramTypeError(t, filler, "int|float|function|array|memblock");

		pop(t);
	}

	uword fill(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);
		checkAnyParam(t, 1);

		fillImpl(t, mb, 1, 0, mb.itemLength);

		dup(t, 0);
		return 1;
	}

	uword fillRange(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);
		auto lo = optIntParam(t, 1, 0);
		auto hi = optIntParam(t, 2, mb.itemLength);
		checkAnyParam(t, 3);

		if(lo < 0)
			lo += mb.itemLength;

		if(hi < 0)
			hi += mb.itemLength;

		if(lo < 0 || lo > hi || hi > mb.itemLength)
			throwStdException(t, "BoundsException", "Invalid range indices ({} .. {})", lo, hi);

		fillImpl(t, mb, 3, cast(uword)lo, cast(uword)hi);

		dup(t, 0);
		return 1;
	}

	version(CrocBuiltinDocs) Docs memblockOpEquals_docs = {kind: "function", name: "opEquals", docs:
	"Compares two memblocks for equality. Throws an error if the two memblocks are of different types. Returns
	true only if the two memblocks are the same length and have the same contents.",
	params: [Param("other", "memblock")],
	extra: [Extra("section", "Memblock metamethods")]};

	uword memblockOpEquals(CrocThread* t)
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
		{
			auto other = getMemblock(t, 1);

			if(mb.kind !is other.kind)
				throwStdException(t, "ValueException", "Attempting to compare memblocks of types '{}' and '{}'", mb.kind.name, other.kind.name);

			if(mb.itemLength != other.itemLength)
				pushBool(t, false);
			else
			{
				auto a = (cast(byte*)mb.data)[0 .. mb.itemLength * mb.kind.itemSize];
				auto b = (cast(byte*)other.data)[0 .. a.length];
				pushBool(t, a == b);
			}
		}

		return 1;
	}

	version(CrocBuiltinDocs) Docs memblockOpCmp_docs = {kind: "function", name: "opCmp", docs:
	"Compares two memblocks for equality. Throws an error if the two memblocks are of different types.",
	params: [Param("other", "memblock")],
	extra: [Extra("section", "Memblock metamethods")]};

	uword memblockOpCmp(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);
		auto len = mb.itemLength;
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

			if(mb.kind !is other.kind)
				throwStdException(t, "ValueException", "Attempting to compare memblocks of types '{}' and '{}'", mb.kind.name, other.kind.name);

			auto otherLen = other.itemLength;
			auto l = .min(len, otherLen);
			int cmp;

			switch(mb.kind.code)
			{
				case CrocMemblock.TypeCode.i8:  auto a = (cast(byte[])  mb.data)[0 .. l]; auto b = (cast(byte[])  other.data)[0 .. l]; cmp = typeid(byte[]). compare(&a, &b); break;
				case CrocMemblock.TypeCode.i16: auto a = (cast(short[]) mb.data)[0 .. l]; auto b = (cast(short[]) other.data)[0 .. l]; cmp = typeid(short[]). compare(&a, &b); break;
				case CrocMemblock.TypeCode.i32: auto a = (cast(int[])   mb.data)[0 .. l]; auto b = (cast(int[])   other.data)[0 .. l]; cmp = typeid(int[]).  compare(&a, &b); break;
				case CrocMemblock.TypeCode.i64: auto a = (cast(long[])  mb.data)[0 .. l]; auto b = (cast(long[])  other.data)[0 .. l]; cmp = typeid(long[]). compare(&a, &b); break;
				case CrocMemblock.TypeCode.u8:  auto a = (cast(ubyte[]) mb.data)[0 .. l]; auto b = (cast(ubyte[]) other.data)[0 .. l]; cmp = typeid(ubyte[]). compare(&a, &b); break;
				case CrocMemblock.TypeCode.u16: auto a = (cast(ushort[])mb.data)[0 .. l]; auto b = (cast(ushort[])other.data)[0 .. l]; cmp = typeid(ushort[]).compare(&a, &b); break;
				case CrocMemblock.TypeCode.u32: auto a = (cast(uint[])  mb.data)[0 .. l]; auto b = (cast(uint[])  other.data)[0 .. l]; cmp = typeid(uint[]). compare(&a, &b); break;
				case CrocMemblock.TypeCode.u64: auto a = (cast(ulong[]) mb.data)[0 .. l]; auto b = (cast(ulong[]) other.data)[0 .. l]; cmp = typeid(ulong[]). compare(&a, &b); break;
				case CrocMemblock.TypeCode.f32: auto a = (cast(float[]) mb.data)[0 .. l]; auto b = (cast(float[]) other.data)[0 .. l]; cmp = typeid(float[]). compare(&a, &b); break;
				case CrocMemblock.TypeCode.f64: auto a = (cast(double[])mb.data)[0 .. l]; auto b = (cast(double[])other.data)[0 .. l]; cmp = typeid(double[]).compare(&a, &b); break;
				default: assert(false);
			}

			if(cmp == 0)
				pushInt(t, Compare3(len, otherLen));
			else
				pushInt(t, cmp);
		}

		return 1;
	}

	uword memblockIterator(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);
		auto index = checkIntParam(t, 1) + 1;

		if(index >= mb.itemLength)
			return 0;

		pushInt(t, index);
		push(t, memblock.index(mb, cast(uword)index));
		return 2;
	}

	uword memblockIteratorReverse(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);
		auto index = checkIntParam(t, 1) - 1;

		if(index < 0)
			return 0;

		pushInt(t, index);
		push(t, memblock.index(mb, cast(uword)index));
		return 2;
	}

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

	uword memblockOpApply(CrocThread* t)
	{
		const Iter = 0;
		const IterReverse = 1;

		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		if(optStringParam(t, 1, "") == "reverse")
		{
			getUpval(t, IterReverse);
			dup(t, 0);
			pushInt(t, mb.itemLength);
		}
		else
		{
			getUpval(t, Iter);
			dup(t, 0);
			pushInt(t, -1);
		}

		return 3;
	}

	uword opCat(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);
		checkAnyParam(t, 1);

		if(isMemblock(t, 1))
		{
			auto other = getMemblock(t, 1);

			if(other.kind !is mb.kind)
				throwStdException(t, "ValueException", "Attempting to concatenate memblocks of types '{}' and '{}'", mb.kind.name, other.kind.name);

			push(t, CrocValue(memblock.cat(t.vm.alloc, mb, other)));
		}
		else
		{
			// ORDER MEMBLOCK TYPE
			if(mb.kind.code <= TypeCode.u64)
				checkIntParam(t, 1);
			else
				checkNumParam(t, 1);

			push(t, CrocValue(memblock.cat(t.vm.alloc, mb, *getValue(t, 1))));
		}

		return 1;
	}

	uword opCat_r(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);
		checkAnyParam(t, 1);

		// ORDER MEMBLOCK TYPE
		if(mb.kind.code <= TypeCode.u64)
			checkIntParam(t, 1);
		else
			checkNumParam(t, 1);

		push(t, CrocValue(memblock.cat_r(t.vm.alloc, *getValue(t, 1), mb)));
		return 1;
	}

	uword opCatAssign(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);
		auto numParams = stackSize(t) - 1;
		checkAnyParam(t, 1);

		if(!mb.ownData)
			throwStdException(t, "ValueException", "Attempting to append to a memblock which does not own its data");

		ulong totalLen = mb.itemLength;

		for(uword i = 1; i <= numParams; i++)
		{
			if(isMemblock(t, i))
			{
				auto other = getMemblock(t, i);

				if(other.kind !is mb.kind)
					throwStdException(t, "ValueException", "Attempting to concatenate memblocks of types '{}' and '{}'", mb.kind.name, other.kind.name);

				totalLen += other.itemLength;
			}
			else
			{
				// ORDER MEMBLOCK TYPE
				if(mb.kind.code <= TypeCode.u64)
					checkIntParam(t, i);
				else
					checkNumParam(t, i);

				totalLen++;
			}
		}

		if(totalLen > uword.max)
			throwStdException(t, "RangeException", "Invalid size ({})", totalLen);

		auto isize = mb.kind.itemSize;
		auto oldLen = mb.itemLength;
		memblock.resize(t.vm.alloc, mb, cast(uword)totalLen);

		uword j = oldLen * isize;

		for(uword i = 1; i <= numParams; i++)
		{
			if(isMemblock(t, i))
			{
				if(opis(t, 0, i))
				{
					// special case for when we're appending a memblock to itself; use the old length
					memcpy(&mb.data[j], mb.data.ptr, oldLen * isize);
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
				memblock.indexAssign(mb, j / isize, *getValue(t, i));
				j += isize;
			}
		}

		return 0;
	}

	char[] opAssign(char[] name, char[] op)
	{
		return `uword op` ~ name ~ `Assign(CrocThread* t)
		{
			checkParam(t, 0, CrocValue.Type.Memblock);
			auto mb = getMemblock(t, 0);
			checkAnyParam(t, 1);

			if(isMemblock(t, 1))
			{
				auto other = getMemblock(t, 1);

				if(other.itemLength != mb.itemLength)
					throwStdException(t, "ValueException", "Cannot perform operation on memblocks of different lengths");

				if(other.kind !is mb.kind)
					throwStdException(t, "ValueException", "Cannot perform operation on memblocks of types '{}' and '{}'", mb.kind.name, other.kind.name);

				switch(mb.kind.code)
				{
					case TypeCode.i8:  (cast(byte[])mb.data)[]   ` ~ op ~ `= (cast(byte[])other.data)[];   break;
					case TypeCode.i16: (cast(short[])mb.data)[]  ` ~ op ~ `= (cast(short[])other.data)[];  break;
					case TypeCode.i32: (cast(int[])mb.data)[]    ` ~ op ~ `= (cast(int[])other.data)[];    break;
					case TypeCode.i64: (cast(long[])mb.data)[]   ` ~ op ~ `= (cast(long[])other.data)[];   break;
					case TypeCode.u8:  (cast(ubyte[])mb.data)[]  ` ~ op ~ `= (cast(ubyte[])other.data)[];  break;
					case TypeCode.u16: (cast(ushort[])mb.data)[] ` ~ op ~ `= (cast(ushort[])other.data)[]; break;
					case TypeCode.u32: (cast(uint[])mb.data)[]   ` ~ op ~ `= (cast(uint[])other.data)[];   break;
					case TypeCode.u64: (cast(ulong[])mb.data)[]  ` ~ op ~ `= (cast(ulong[])other.data)[];  break;
					case TypeCode.f32: (cast(float[])mb.data)[]  ` ~ op ~ `= (cast(float[])other.data)[];  break;
					case TypeCode.f64: (cast(double[])mb.data)[] ` ~ op ~ `= (cast(double[])other.data)[]; break;
					default: assert(false);
				}
			}
			else
			{
				switch(mb.kind.code)
				{
					case TypeCode.i8:  auto val = checkIntParam(t, 1); (cast(byte[])mb.data)[]   ` ~ op ~ `= cast(byte)val;   break;
					case TypeCode.i16: auto val = checkIntParam(t, 1); (cast(short[])mb.data)[]  ` ~ op ~ `= cast(short)val;  break;
					case TypeCode.i32: auto val = checkIntParam(t, 1); (cast(int[])mb.data)[]    ` ~ op ~ `= cast(int)val;    break;
					case TypeCode.i64: auto val = checkIntParam(t, 1); (cast(long[])mb.data)[]   ` ~ op ~ `= cast(long)val;   break;
					case TypeCode.u8:  auto val = checkIntParam(t, 1); (cast(ubyte[])mb.data)[]  ` ~ op ~ `= cast(ubyte)val;  break;
					case TypeCode.u16: auto val = checkIntParam(t, 1); (cast(ushort[])mb.data)[] ` ~ op ~ `= cast(ushort)val; break;
					case TypeCode.u32: auto val = checkIntParam(t, 1); (cast(uint[])mb.data)[]   ` ~ op ~ `= cast(uint)val;   break;
					case TypeCode.u64: auto val = checkIntParam(t, 1); (cast(ulong[])mb.data)[]  ` ~ op ~ `= cast(ulong)val;  break;
					case TypeCode.f32: auto val = checkNumParam(t, 1); (cast(float[])mb.data)[]  ` ~ op ~ `= cast(float)val;  break;
					case TypeCode.f64: auto val = checkNumParam(t, 1); (cast(double[])mb.data)[] ` ~ op ~ `= cast(double)val; break;
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
		return `uword op` ~ name ~ `(CrocThread* t)
		{
			checkParam(t, 0, CrocValue.Type.Memblock);
			auto mb = getMemblock(t, 0);
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
		return `uword op` ~ name ~ `_r(CrocThread* t)
		{
			checkParam(t, 0, CrocValue.Type.Memblock);
			auto mb = getMemblock(t, 0);
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
		return `uword rev` ~ name ~ `(CrocThread* t)
		{
			checkParam(t, 0, CrocValue.Type.Memblock);
			auto mb = getMemblock(t, 0);
			checkAnyParam(t, 1);

			if(isMemblock(t, 1))
			{
				auto other = getMemblock(t, 1);

				if(other.itemLength != mb.itemLength)
					throwStdException(t, "ValueException", "Cannot perform operation on memblocks of different lengths");

				if(other.kind !is mb.kind)
					throwStdException(t, "ValueException", "Cannot perform operation on memblocks of types '{}' and '{}'", mb.kind.name, other.kind.name);

				switch(mb.kind.code)
				{
					case TypeCode.i8:
						auto data = cast(byte[])mb.data;
						auto otherData = cast(byte[])other.data;

						for(uword i = 0; i < data.length; i++)
							data[i] = cast(byte)(otherData[i] ` ~ op ~ ` data[i]);
						break;

					case TypeCode.i16:
						auto data = cast(short[])mb.data;
						auto otherData = cast(short[])other.data;

						for(uword i = 0; i < data.length; i++)
							data[i] = cast(short)(otherData[i] ` ~ op ~ ` data[i]);
						break;

					case TypeCode.i32: auto data = cast(int[])mb.data;  data[] = (cast(int[])other.data)[] ` ~ op ~ ` data[];  break;
					case TypeCode.i64: auto data = cast(long[])mb.data; data[] = (cast(long[])other.data)[] ` ~ op ~ ` data[]; break;

					case TypeCode.u8:
						auto data = cast(ubyte[])mb.data;
						auto otherData = cast(ubyte[])other.data;

						for(uword i = 0; i < data.length; i++)
							data[i] = cast(ubyte)(otherData[i] ` ~ op ~ ` data[i]);
						break;

					case TypeCode.u16:
						auto data = cast(ushort[])mb.data;
						auto otherData = cast(ushort[])other.data;

						for(uword i = 0; i < data.length; i++)
							data[i] = cast(ushort)(otherData[i] ` ~ op ~ ` data[i]);
						break;

					case TypeCode.u32: auto data = cast(uint[])mb.data;   data[] = (cast(uint[])other.data)[] ` ~ op ~ ` data[];   break;
					case TypeCode.u64: auto data = cast(ulong[])mb.data;  data[] = (cast(ulong[])other.data)[] ` ~ op ~ ` data[];  break;
					case TypeCode.f32: auto data = cast(float[])mb.data;  data[] = (cast(float[])other.data)[] ` ~ op ~ ` data[];  break;
					case TypeCode.f64: auto data = cast(double[])mb.data; data[] = (cast(double[])other.data)[] ` ~ op ~ ` data[]; break;
					default: assert(false);
				}
			}
			else
			{
				switch(mb.kind.code)
				{
					case TypeCode.i8:
						auto val = cast(byte)checkIntParam(t, 1);
						auto data = cast(byte[])mb.data;
	
						for(uword i = 0; i < data.length; i++)
							data[i] = cast(byte)(val ` ~ op ~ ` data[i]);
						break;
	
					case TypeCode.i16:
						auto val = cast(short)checkIntParam(t, 1);
						auto data = cast(short[])mb.data;

						for(uword i = 0; i < data.length; i++)
							data[i] = cast(short)(val ` ~ op ~ ` data[i]);
						break;
	
					case TypeCode.i32:
						auto val = cast(int)checkIntParam(t, 1);
						auto data = cast(int[])mb.data;
						data[] = val ` ~ op ~ `data[];
						break;
	
					case TypeCode.i64:
						auto val = cast(long)checkIntParam(t, 1);
						auto data = cast(long[])mb.data;
						data[] = val ` ~ op ~ `data[];
						break;
	
					case TypeCode.u8:
						auto val = cast(ubyte)checkIntParam(t, 1);
						auto data = cast(ubyte[])mb.data;
	
						for(uword i = 0; i < data.length; i++)
							data[i] = cast(ubyte)(val ` ~ op ~ ` data[i]);
						break;
	
					case TypeCode.u16:
						auto val = cast(ushort)checkIntParam(t, 1);
						auto data = cast(ushort[])mb.data;
	
						for(uword i = 0; i < data.length; i++)
							data[i] = cast(ushort)(val ` ~ op ~ ` data[i]);
						break;
	
					case TypeCode.u32:
						auto val = cast(uint)checkIntParam(t, 1);
						auto data = cast(uint[])mb.data;
						data[] = val ` ~ op ~ `data[];
						break;

					case TypeCode.u64:
						auto val = cast(ulong)checkIntParam(t, 1);
						auto data = cast(ulong[])mb.data;
						data[] = val ` ~ op ~ `data[];
						break;
	
					case TypeCode.f32:
						auto val = cast(float)checkNumParam(t, 1);
						auto data = cast(float[])mb.data;
						data[] = val ` ~ op ~ `data[];
						break;
	
					case TypeCode.f64:
						auto val = cast(double)checkNumParam(t, 1);
						auto data = cast(double[])mb.data;
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

/*
uword _constructor(CrocThread* t)
{
	checkInstParam(t, 0, "Vector");

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

	newMemblock(t, "u32", length);

	if(data.length > 0)
	{
		auto mb = getMemblock(t, -1);
		uint ate = 0;
		Utf.toString32(data, cast(dchar[])mb.data, &ate);
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
		Utf.toString32(getString(t, 1), dest, &ate);
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
		Utf.toString32(s, dest, &ate);
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
				auto otherLen = _getLength(t, i);
				resize(otherLen)[] = (cast(dchar[])_getData(t, i).data)[0 .. otherLen];
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
		auto other = cast(dchar[])_getData(t, filler).data;
		auto otherLen = _getLength(t, filler);

		if(otherLen != (hi - lo))
			throwStdException(t, "ValueException", "Length of destination ({}) and length of source ({}) do not match", hi - lo, otherLen);

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

		auto data = (cast(dchar[])mb.data)[0 .. _getLength(t)];

		for(uword i = lo; i < hi; i++)
		{
			callFunc(i);

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
			Utf.toString32(str, tmp, &ate);
		}
	}
	else if(isChar(t, 2))
		doResize(1)[0] = getChar(t, 2);
	else if(as(t, 2, -1))
	{
		auto other = cast(dchar[])_getData(t, 2).data;
		auto otherLen = _getLength(t, 2);

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
		Utf.toString32(data, (cast(dchar[])mb.data)[cast(uword)oldLen .. cast(uword)totalLen], &ate);
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
	assert(isInt(t, -1));
	setExtraVal(t, 0, Length);

	dup(t, 2);
	pushNull(t);
	rawCall(t, -2, 1);
	assert(isMemblock(t, -1));
	setExtraVal(t, 0, Data);

	return 0;
}
*/

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