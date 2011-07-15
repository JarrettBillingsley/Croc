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

struct MemblockLib
{
static:
	alias CrocMemblock.TypeStruct TypeStruct;
	alias CrocMemblock.TypeCode TypeCode;

	void init(CrocThread* t)
	{
		makeModule(t, "memblock", function uword(CrocThread* t)
		{
			register(t, 3, "new", &memblock_new);
			register(t, 4, "range", &range);

			getTypeMT(t, CrocValue.Type.Memblock);

			if(isNull(t, -1))
			{
				pop(t);
				newNamespace(t, "memblock");
			}

				registerField(t, 1, "type",        &type);
				registerField(t, 0, "itemSize",    &itemSize);
				registerField(t, 2, "toArray",     &toArray);

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
					throwException(t, "Invalid size ({})", size);

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
				throwException(t, "Step may not be 0");
		}

		auto range = abs(v2 - v1);
		long size = cast(long)(range / step);

		if((range % step) != 0)
			size++;

		if(size > uword.max)
			throwException(t, "Memblock is too big ({} items)", size);

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
			default:                                                   throwException(t, "Invalid type code '{}'", type);
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

		if(mb.kind.code == TypeCode.v)
			throwException(t, "Attempting to convert a void memblock to an array");

		auto lo = optIntParam(t, 1, 0);
		auto hi = optIntParam(t, 2, mb.itemLength);

		if(lo < 0)
			lo += mb.itemLength;

		if(hi < 0)
			hi += mb.itemLength;

		if(lo < 0 || lo > hi || hi > mb.itemLength)
			throwException(t, "Invalid slice indices: {} .. {} (length: {})", lo, hi, mb.itemLength);

		auto ret = newArray(t, cast(uword)(hi - lo));

		for(uword i = cast(uword)lo, j = 0; i < cast(uword)hi; i++, j++)
		{
			push(t, memblock.index(mb, i));
			idxai(t, ret, j);
		}

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

		if(mb.kind.code == TypeCode.v)
			throwException(t, "Attempting to reverse a void memblock");

		switch(mb.kind.itemSize)
		{
			case 1: (cast(ubyte*)mb.data) [0 .. mb.itemLength].reverse; break;
			case 2: (cast(ushort*)mb.data)[0 .. mb.itemLength].reverse; break;
			case 4: (cast(uint*)mb.data)  [0 .. mb.itemLength].reverse; break;
			case 8: (cast(ulong*)mb.data) [0 .. mb.itemLength].reverse; break;

			default:
				throwException(t, "Not a horrible error, but somehow a memblock type must've been added that doesn't have 1-, 2-, 4-, or 8-byte elements, so I don't know how to reverse it.");
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
			case TypeCode.v:   throwException(t, "Attempting to sort a void memblock");
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
					throwException(t, "application function expected to return {}, not '{}'", typeMsg, getString(t, -1));
				}
				
				memblock.indexAssign(mb, i, *getValue(t, -1));
				pop(t);
			}
		}

		switch(mb.kind.code)
		{
			case TypeCode.v:
				throwException(t, "Attempting to modify a void memblock");

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

		if(getMemblock(t, 0).kind.code == TypeCode.v)
			throwException(t, "Attempting to map a void memblock");

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
			throwException(t, "Memblock is empty");

		switch(mb.kind.code)
		{
			case TypeCode.v:   throwException(t, "Cannot get the max of a void memblock");
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
			throwException(t, "Memblock is empty");

		switch(mb.kind.code)
		{
			case TypeCode.v:   throwException(t, "Cannot get the min of a void memblock");
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
			throwException(t, "Attempting to insert into a memblock which does not own its data");

		if(mb.kind.code == TypeCode.v)
			throwException(t, "Attempting to insert into a void memblock");

		if(idx < 0)
			idx += mb.itemLength;

		// Yes, > and not >=, because you can insert at "one past" the end of the memblock.
		if(idx < 0 || idx > mb.itemLength)
			throwException(t, "Invalid index: {} (length: {})", idx, mb.itemLength);

		void doResize(ulong otherLen)
		{
			ulong totalLen = mb.itemLength + otherLen;

			if(totalLen > uword.max)
				throwException(t, "Invalid size ({})", totalLen);

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
				throwException(t, "Attempting to insert a memblock of type '{}' into a memblock of type '{}'", other.kind.name, mb.kind.name);

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
			throwException(t, "Attempting to pop from a memblock which does not own its data");

		if(mb.kind.code == TypeCode.v)
			throwException(t, "Attempting to pop from a void memblock");

		if(mb.itemLength == 0)
			throwException(t, "Memblock is empty");

		auto index = optIntParam(t, 1, -1);

		if(index < 0)
			index += mb.itemLength;

		if(index < 0 || index >= mb.itemLength)
			throwException(t, "Invalid index: {}", index);

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
			throwException(t, "Attempting to remove from a memblock which does not own its data");

		if(mb.kind.code == TypeCode.v)
			throwException(t, "Attempting to remove from a void memblock");

		if(mb.itemLength == 0)
			throwException(t, "Memblock is empty");

		auto lo = checkIntParam(t, 1);
		auto hi = optIntParam(t, 2, lo + 1);

		if(lo < 0)
			lo += mb.itemLength;

		if(hi < 0)
			hi += mb.itemLength;

		if(lo < 0 || lo > hi || hi > mb.itemLength)
			throwException(t, "Invalid indices: {} .. {} (length: {})", lo, hi, mb.itemLength);

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
				case TypeCode.v:   throwException(t, "Attempting to sum a void memblock");
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
				case TypeCode.v:   throwException(t, "Attempting to sum a void memblock");
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
		
		if(mb.kind.code == TypeCode.v)
			throwException(t, "Attempting to copy into a void memblock");

		if(lo < 0)
			lo += mb.itemLength;

		if(hi < 0)
			hi += mb.itemLength;

		if(lo < 0 || lo > hi || hi > mb.itemLength)
			throwException(t, "Invalid destination slice indices: {} .. {} (length: {})", lo, hi, mb.itemLength);

		checkParam(t, 3, CrocValue.Type.Memblock);
		auto other = getMemblock(t, 3);
		
		if(other.kind.code == TypeCode.v)
			throwException(t, "Attempting to copy from a void memblock");

		if(mb.kind !is other.kind)
			throwException(t, "Attempting to copy a memblock of type '{}' into a memblock of type '{}'", other.kind.name, mb.kind.name);

		auto lo2 = optIntParam(t, 4, 0);
		auto hi2 = optIntParam(t, 5, lo2 + (hi - lo));

		if(lo2 < 0)
			lo2 += other.itemLength;

		if(hi2 < 0)
			hi2 += other.itemLength;

		if(lo2 < 0 || lo2 > hi2 || hi2 > other.itemLength)
			throwException(t, "Invalid source slice indices: {} .. {} (length: {})", lo2, hi2, other.itemLength);

		if((hi - lo) != (hi2 - lo2))
			throwException(t, "Destination length ({}) and source length({}) do not match", hi - lo, hi2 - lo2);

		auto isize = mb.kind.itemSize;
		memcpy(&mb.data[cast(uword)lo * isize], &other.data[cast(uword)lo2 * isize], cast(uword)(hi - lo) * isize);

		dup(t, 0);
		return 1;
	}

	void fillImpl(CrocThread* t, CrocMemblock* mb, word filler, uword lo, uword hi)
	{
		if(mb.kind.code == TypeCode.v)
			throwException(t, "Attempting to fill a void memblock");

		if(isMemblock(t, filler))
		{
			auto other = getMemblock(t, filler);

			if(mb.kind !is other.kind)
				throwException(t, "Attempting to fill a memblock of type '{}' using a memblock of type '{}'", mb.kind.name, other.kind.name);

			if(other.itemLength != (hi - lo))
				throwException(t, "Length of destination ({}) and length of source ({}) do not match", hi - lo, other.itemLength);

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
						throwException(t, "filler function expected to return an 'int', not '{}'", getString(t, -1));
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
						throwException(t, "filler function expected to return an 'int' or 'float', not '{}'", getString(t, -1));
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
				throwException(t, "Length of destination ({}) and length of array ({}) do not match", hi - lo, len(t, filler));

			// ORDER MEMBLOCK TYPE
			if(mb.kind.code <= TypeCode.u64)
			{
				for(uword i = lo, ai = 0; i < hi; i++, ai++)
				{
					idxi(t, filler, ai);

					if(!isInt(t, -1))
					{
						pushTypeString(t, -1);
						throwException(t, "array element {} expected to be 'int', not '{}'", ai, getString(t, -1));
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
						throwException(t, "array element {} expected to be 'int' or 'float', not '{}'", ai, getString(t, -1));
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
			throwException(t, "Invalid range indices ({} .. {})", lo, hi);

		fillImpl(t, mb, 3, cast(uword)lo, cast(uword)hi);

		dup(t, 0);
		return 1;
	}

	uword rawRead(T)(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		if(mb.kind.code == TypeCode.v)
			throwException(t, "Attempting to read from a void memblock");

		word maxIdx = mb.data.length < T.sizeof ? -1 : mb.data.length - T.sizeof;
		auto idx = checkIntParam(t, 1);

		if(idx < 0)
			idx += mb.itemLength * mb.kind.itemSize;

		if(idx < 0 || idx > maxIdx)
			throwException(t, "Invalid index '{}'", idx);

		static if(isIntegerType!(T))
			pushInt(t, cast(crocint)*(cast(T*)(mb.data.ptr + idx)));
		else
			pushFloat(t, cast(crocfloat)*(cast(T*)(mb.data.ptr + idx)));

		return 1;
	}

	uword rawWrite(T)(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		if(mb.kind.code == TypeCode.v)
			throwException(t, "Attempting to write to a void memblock");

		word maxIdx = mb.data.length < T.sizeof ? -1 : mb.data.length - T.sizeof;
		auto idx = checkIntParam(t, 1);

		if(idx < 0)
			idx += mb.itemLength * mb.kind.itemSize;

		if(idx < 0 || idx > maxIdx)
			throwException(t, "Invalid index '{}'", idx);

		static if(isIntegerType!(T))
			auto val = checkIntParam(t, 2);
		else
			auto val = checkNumParam(t, 2);

		*(cast(T*)(mb.data.ptr + idx)) = cast(T)val;

		return 0;
	}

	uword opCat(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);
		checkAnyParam(t, 1);

		if(mb.kind.code == TypeCode.v)
			throwException(t, "Attempting to concatenate a void memblock");

		if(isMemblock(t, 1))
		{
			auto other = getMemblock(t, 1);

			if(other.kind !is mb.kind)
				throwException(t, "Attempting to concatenate memblocks of types '{}' and '{}'", mb.kind.name, other.kind.name);

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

		if(mb.kind.code == TypeCode.v)
			throwException(t, "Attempting to concatenate a void memblock");

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

		if(mb.kind.code == TypeCode.v)
			throwException(t, "Attempting to append to a void memblock");

		if(!mb.ownData)
			throwException(t, "Attempting to append to a memblock which does not own its data");

		ulong totalLen = mb.itemLength;

		for(uword i = 1; i <= numParams; i++)
		{
			if(isMemblock(t, i))
			{
				auto other = getMemblock(t, i);

				if(other.kind !is mb.kind)
					throwException(t, "Attempting to concatenate memblocks of types '{}' and '{}'", mb.kind.name, other.kind.name);

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
			throwException(t, "Invalid size ({})", totalLen);

		auto isize = mb.kind.itemSize;
		auto oldLen = mb.itemLength;
		memblock.resize(t.vm.alloc, mb, cast(uword)totalLen);

		uword j = oldLen * isize;

		for(uword i = 1; i <= numParams; i++)
		{
			if(isMemblock(t, i))
			{
				auto other = getMemblock(t, i);
				memcpy(&mb.data[j], other.data.ptr, other.data.length);
				j += other.data.length;
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

			if(mb.kind.code == TypeCode.v)
				throwException(t, "Attempting to modify a void memblock");

			if(isMemblock(t, 1))
			{
				auto other = getMemblock(t, 1);

				if(other.itemLength != mb.itemLength)
					throwException(t, "Cannot perform operation on memblocks of different lengths");

				if(other.kind !is mb.kind)
					throwException(t, "Cannot perform operation on memblocks of types '{}' and '{}'", mb.kind.name, other.kind.name);

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
		}`; /+ " +/
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
			
			if(mb.kind.code == TypeCode.v)
				throwException(t, "Attempting to modify a void memblock");

			if(isMemblock(t, 1))
			{
				auto other = getMemblock(t, 1);

				if(other.itemLength != mb.itemLength)
					throwException(t, "Cannot perform operation on memblocks of different lengths");

				if(other.kind !is mb.kind)
					throwException(t, "Cannot perform operation on memblocks of types '{}' and '{}'", mb.kind.name, other.kind.name);

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
		}`; /+ " +/
	}

	mixin(rev_func("Sub", "-"));
	mixin(rev_func("Div", "/"));
	mixin(rev_func("Mod", "%"));
}