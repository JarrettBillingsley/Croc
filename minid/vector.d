/******************************************************************************
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

module minid.vector;

import tango.math.Math;
import tango.stdc.string;

import minid.ex;
import minid.interpreter;
import minid.types;

struct VectorObj
{
static:
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
// 		c
	}

	const char[][] typeNames =
	[
		"i8",
		"i16",
		"i32",
		"i64",
		"u8",
		"u16",
		"u32",
		"u64",
		"f32",
		"f64",
// 		"c"
	];

	const ubyte[] sizes =
	[
		1, // i8
		2, // i16
		4, // i32
		8, // i64
		1, // u8
		2, // u16
		4, // u32
		8, // u64
		4, // f32
		8, // f64
		4  // c
	];

	word get_i8(MDThread* t, Members* memb, uword idx)             { return pushInt(t, (cast(byte*)memb.data)[idx]); }
	void set_i8(MDThread* t, Members* memb, uword idx, word item)  { (cast(byte*)memb.data)[idx] = cast(byte)getInt(t, item); }
	word get_i16(MDThread* t, Members* memb, uword idx)            { return pushInt(t, (cast(short*)memb.data)[idx]); }
	void set_i16(MDThread* t, Members* memb, uword idx, word item) { (cast(short*)memb.data)[idx] = cast(short)getInt(t, item); }
	word get_i32(MDThread* t, Members* memb, uword idx)            { return pushInt(t, (cast(int*)memb.data)[idx]); }
	void set_i32(MDThread* t, Members* memb, uword idx, word item) { (cast(int*)memb.data)[idx] = cast(int)getInt(t, item); }
	word get_i64(MDThread* t, Members* memb, uword idx)            { return pushInt(t, (cast(long*)memb.data)[idx]); }
	void set_i64(MDThread* t, Members* memb, uword idx, word item) { (cast(long*)memb.data)[idx] = cast(long)getInt(t, item); }

	word get_u8(MDThread* t, Members* memb, uword idx)             { return pushInt(t, (cast(ubyte*)memb.data)[idx]); }
	void set_u8(MDThread* t, Members* memb, uword idx, word item)  { (cast(ubyte*)memb.data)[idx] = cast(ubyte)getInt(t, item); }
	word get_u16(MDThread* t, Members* memb, uword idx)            { return pushInt(t, (cast(ushort*)memb.data)[idx]); }
	void set_u16(MDThread* t, Members* memb, uword idx, word item) { (cast(ushort*)memb.data)[idx] = cast(ushort)getInt(t, item); }
	word get_u32(MDThread* t, Members* memb, uword idx)            { return pushInt(t, (cast(uint*)memb.data)[idx]); }
	void set_u32(MDThread* t, Members* memb, uword idx, word item) { (cast(uint*)memb.data)[idx] = cast(uint)getInt(t, item); }
	word get_u64(MDThread* t, Members* memb, uword idx)            { return pushInt(t, (cast(long*)memb.data)[idx]); }
	void set_u64(MDThread* t, Members* memb, uword idx, word item) { (cast(long*)memb.data)[idx] = cast(long)getInt(t, item); }

	word get_f32(MDThread* t, Members* memb, uword idx)            { return pushFloat(t, (cast(float*)memb.data)[idx]); }
	void set_f32(MDThread* t, Members* memb, uword idx, word item) { (cast(float*)memb.data)[idx] = cast(float)getNum(t, item); }
	word get_f64(MDThread* t, Members* memb, uword idx)            { return pushFloat(t, (cast(double*)memb.data)[idx]); }
	void set_f64(MDThread* t, Members* memb, uword idx, word item) { (cast(double*)memb.data)[idx] = cast(double)getNum(t, item); }

// 	word get_c(MDThread* t, Members* memb, uword idx)              { return pushChar(t, (cast(dchar*)memb.data)[idx]); }
// 	void set_c(MDThread* t, Members* memb, uword idx, word item)   { (cast(dchar*)memb.data)[idx] = cast(dchar)getChar(t, item); }

	struct TypeStruct
	{
		TypeCode code;
		ubyte itemSize;
		word function(MDThread* t, Members* memb, uword idx) getItem;
		void function(MDThread* t, Members* memb, uword idx, word item) setItem;
	}

	const TypeStruct[] typeStructs =
	[
		{ TypeCode.i8,  sizes[TypeCode.i8],  &get_i8,  &set_i8 },
		{ TypeCode.i16, sizes[TypeCode.i16], &get_i16, &set_i16 },
		{ TypeCode.i32, sizes[TypeCode.i32], &get_i32, &set_i32 },
		{ TypeCode.i64, sizes[TypeCode.i64], &get_i64, &set_i64 },
		{ TypeCode.u8,  sizes[TypeCode.u8],  &get_u8,  &set_u8 },
		{ TypeCode.u16, sizes[TypeCode.u16], &get_u16, &set_u16 },
		{ TypeCode.u32, sizes[TypeCode.u32], &get_u32, &set_u32 },
		{ TypeCode.u64, sizes[TypeCode.u64], &get_u64, &set_u64 },
		{ TypeCode.f32, sizes[TypeCode.f32], &get_f32, &set_f32 },
		{ TypeCode.f64, sizes[TypeCode.f64], &get_f64, &set_f64 },
// 		{ TypeCode.c,   sizes[TypeCode.c],   &get_c,   &set_c }
	];

	align(1) struct Members
	{
		void* data;
		uword length;
		TypeStruct* type;
	}

	void init(MDThread* t)
	{
		CreateClass(t, "Vector", (CreateClass* c)
		{
			c.method("constructor",    &constructor);
			c.method("dup",            &vec_dup);
			c.method("range",          &range);
			c.method("fromArray",      &fromArray);

			c.method("apply",          &apply);
			c.method("copyRange",      &copyRange);
			c.method("fill",           &fill);
			c.method("fillRange",      &fillRange);
			c.method("insert",         &vec_insert);
			c.method("itemSize",       &itemSize);
			c.method("map",            &map);
			c.method("max",            &max);
			c.method("min",            &min);
			c.method("pop",            &vec_pop);
			c.method("product",        &product);
			c.method("remove",         &remove);
			c.method("reverse",        &reverse);
			c.method("sort",           &sort);
			c.method("sum",            &sum);
			c.method("toArray",        &toArray);
			c.method("toString",       &toString);
// 			c.method("toStringValue",  &toStringValue);
			c.method("type",           &type);

			c.method("opLength",       &opLength);
			c.method("opLengthAssign", &opLengthAssign);
			c.method("opIndex",        &opIndex);
			c.method("opIndexAssign",  &opIndexAssign);
			c.method("opSlice",        &opSlice);

			c.method("opAdd",          &opAdd);
			c.method("opAddAssign",    &opAddAssign);
			c.method("opSub",          &opSub);
			c.method("opSub_r",        &opSub_r);
			c.method("opSubAssign",    &opSubAssign);
			c.method("revSub",         &revSub);
			c.method("opCat",          &opCat);
			c.method("opCat_r",        &opCat_r);
			c.method("opCatAssign",    &opCatAssign);
			c.method("opMul",          &opMul);
			c.method("opMulAssign",    &opMulAssign);
			c.method("opDiv",          &opDiv);
			c.method("opDiv_r",        &opDiv_r);
			c.method("opDivAssign",    &opDivAssign);
			c.method("revDiv",         &revDiv);
			c.method("opMod",          &opMod);
			c.method("opMod_r",        &opMod_r);
			c.method("opModAssign",    &opModAssign);
			c.method("revMod",         &revMod);

			c.method("opEquals",       &opEquals);

				newFunction(t, &iterator, "Vector.iterator");
				newFunction(t, &iteratorReverse, "Vector.iteratorReverse");
			c.method("opApply", &opApply, 2);
		});
		
		newFunction(t, &allocator, "Vector.allocator");
		setAllocator(t, -2);

		newFunction(t, &finalizer, "Vector.finalizer");
		setFinalizer(t, -2);

		field(t, -1, "opCatAssign");
		fielda(t, -2, "append");

		field(t, -1, "opAdd");
		fielda(t, -2, "opAdd_r");

		field(t, -1, "opMul");
		fielda(t, -2, "opMul_r");
		
		field(t, -1, "fillRange");
		fielda(t, -2, "opSliceAssign");

		newGlobal(t, "Vector");
	}

	private Members* getThis(MDThread* t)
	{
		auto ret = checkInstParam!(Members)(t, 0, "Vector");
		
		if(ret.type is null)
			throwException(t, "Attempting to call a method on an uninitialized Vector");
			
		return ret;
	}

	uword allocator(MDThread* t, uword numParams)
	{
		newInstance(t, 0, 0, Members.sizeof);
		*(cast(Members*)getExtraBytes(t, -1).ptr) = Members.init;
		
		dup(t);
		pushNull(t);
		rotateAll(t, 3);
		methodCall(t, 2, "constructor", 0);
		return 1;
	}

	uword finalizer(MDThread* t, uword numParams)
	{
		auto memb = cast(Members*)getExtraBytes(t, 0).ptr;

		if(memb.type !is null && memb.data !is null)
		{
			auto tmp = memb.data[0 .. memb.length * memb.type.itemSize];
			t.vm.alloc.freeArray(tmp);
			memb.data = null;
			memb.length = 0;
		}

		return 0;
	}

	uword constructor(MDThread* t, uword numParams)
	{
		// don't use getThis here or else you'll get errors upon construction
		auto memb = checkInstParam!(Members)(t, 0, "Vector");
		
		if(memb.type !is null)
			throwException(t, "Attempting to reinitialize an already-initialized Vector");

		auto type = checkStringParam(t, 1);
		auto size = optIntParam(t, 2, 0);
		auto haveFiller = isValidIndex(t, 3);

		if(size < 0 || size > uword.max)
			throwException(t, "Invalid size ({})", size);

		TypeStruct* ts;

		switch(type)
		{
			case "i8" : ts = &typeStructs[TypeCode.i8];  break;
			case "i16": ts = &typeStructs[TypeCode.i16]; break;
			case "i32": ts = &typeStructs[TypeCode.i32]; break;
			case "i64": ts = &typeStructs[TypeCode.i64]; break;
			case "u8" : ts = &typeStructs[TypeCode.u8];  break;
			case "u16": ts = &typeStructs[TypeCode.u16]; break;
			case "u32": ts = &typeStructs[TypeCode.u32]; break;
			case "u64": ts = &typeStructs[TypeCode.u64]; break;
			case "f32": ts = &typeStructs[TypeCode.f32]; break;
			case "f64": ts = &typeStructs[TypeCode.f64]; break;
// 			case "c"  : ts = &typeStructs[TypeCode.c];   break;

			default:
				throwException(t, "Invalid type code '{}'", type);
		}

		memb.type = ts;
		memb.length = cast(uword)size;
		memb.data = t.vm.alloc.allocArray!(void)(cast(uword)size * memb.type.itemSize).ptr;

		if(haveFiller)
		{
			dup(t, 0);
			pushNull(t);
			dup(t, 3);
			methodCall(t, -3, "fill", 0);
		}

		return 0;
	}

	uword vec_dup(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		pushGlobal(t, "Vector");
		pushNull(t);
		pushString(t, typeNames[memb.type.code]);
		pushInt(t, memb.length);
		rawCall(t, -4, 1);

		auto newMemb = getMembers!(Members)(t, -1);
		auto byteSize = memb.length * memb.type.itemSize;
		(cast(byte*)newMemb.data)[0 .. byteSize] = (cast(byte*)memb.data)[0 .. byteSize];

		return 1;
	}

	uword range(MDThread* t, uword numParams)
	{
		auto type = checkStringParam(t, 1);

		TypeStruct* ts;

		switch(type)
		{
			case "i8" : ts = &typeStructs[TypeCode.i8];  break;
			case "i16": ts = &typeStructs[TypeCode.i16]; break;
			case "i32": ts = &typeStructs[TypeCode.i32]; break;
			case "i64": ts = &typeStructs[TypeCode.i64]; break;
			case "u8" : ts = &typeStructs[TypeCode.u8];  break;
			case "u16": ts = &typeStructs[TypeCode.u16]; break;
			case "u32": ts = &typeStructs[TypeCode.u32]; break;
			case "u64": ts = &typeStructs[TypeCode.u64]; break;
			case "f32": ts = &typeStructs[TypeCode.f32]; break;
			case "f64": ts = &typeStructs[TypeCode.f64]; break;
// 			case "c"  : ts = &typeStructs[TypeCode.c];   break;

			default:
				throwException(t, "Invalid type code '{}'", type);
		}

		Members* makeObj(long size)
		{
			pushGlobal(t, "Vector");
			pushNull(t);
			pushString(t, type);
			pushInt(t, cast(mdint)size);
			rawCall(t, -4, 1);
			return getMembers!(Members)(t, -1);
		}

		switch(ts.code)
		{
			case
				TypeCode.i8,
				TypeCode.i16,
				TypeCode.i32,
				TypeCode.i64,
				TypeCode.u8,
				TypeCode.u16,
				TypeCode.u32,
				TypeCode.u64:

				auto v1 = checkIntParam(t, 2);
				mdint v2 = void;
				mdint step = 1;

				if(numParams == 2)
				{
					v2 = v1;
					v1 = 0;
				}
				else if(numParams == 3)
					v2 = checkIntParam(t, 3);
				else
				{
					v2 = checkIntParam(t, 3);
					step = checkIntParam(t, 4);
				}

				if(step <= 0)
					throwException(t, "Step may not be negative or 0");

				mdint range = abs(v2 - v1);
				long size = range / step;

				if((range % step) != 0)
					size++;

				if(size > uword.max)
					throwException(t, "Vector is too big");

				auto ret = makeObj(size);
				auto val = v1;

				if(v2 < v1)
				{
					for(uword i = 0; val > v2; i++, val -= step)
					{
						pushInt(t, val);
						ret.type.setItem(t, ret, i, -1);
						pop(t);
					}
				}
				else
				{
					for(uword i = 0; val < v2; i++, val += step)
					{
						pushInt(t, val);
						ret.type.setItem(t, ret, i, -1);
						pop(t);
					}
				}

				break;

			case TypeCode.f32, TypeCode.f64:
				auto v1 = checkNumParam(t, 2);
				mdfloat v2 = void;
				mdfloat step = 1;

				if(numParams == 2)
				{
					v2 = v1;
					v1 = 0;
				}
				else if(numParams == 3)
					v2 = checkNumParam(t, 3);
				else
				{
					v2 = checkNumParam(t, 3);
					step = checkNumParam(t, 4);
				}

				if(step <= 0)
					throwException(t, "Step may not be negative or 0");

				auto range = abs(v2 - v1);
				long size = cast(long)(range / step);

				if((range % step) != 0)
					size++;

				if(size > uword.max)
					throwException(t, "Vector is too big");

				auto ret = makeObj(size);
				auto val = v1;

				if(v2 < v1)
				{
					for(uword i = 0; i < size; i++, val -= step)
					{
						pushFloat(t, val);
						ret.type.setItem(t, ret, i, -1);
						pop(t);
					}
				}
				else
				{
					for(uword i = 0; i < size; i++, val += step)
					{
						pushFloat(t, val);
						ret.type.setItem(t, ret, i, -1);
						pop(t);
					}
				}

				break;

// 			case TypeCode.c:
// 				auto v1 = checkCharParam(t, 2);
// 				dchar v2 = void;
// 				mdint step = 1;
// 
// 				if(numParams == 2)
// 				{
// 					v2 = v1;
// 					v1 = '\0';
// 				}
// 				else if(numParams == 3)
// 					v2 = checkCharParam(t, 3);
// 				else
// 				{
// 					v2 = checkCharParam(t, 3);
// 					step = checkIntParam(t, 4);
// 				}
// 
// 				if(step <= 0)
// 					throwException(t, "Step may not be negative or 0");
// 
// 				long range = abs(cast(int)v2 - cast(int)v1);
// 				long size = range / step;
// 
// 				if((range % step) != 0)
// 					size++;
// 
// 				if(size > uword.max)
// 					throwException(t, "Vector is too big");
// 
// 				auto ret = makeObj(size);
// 				auto val = v1;
// 
// 				if(v2 < v1)
// 				{
// 					for(uword i = 0; val > v2; i++, val -= step)
// 					{
// 						pushChar(t, val);
// 						ret.type.setItem(t, ret, i, -1);
// 						pop(t);
// 					}
// 				}
// 				else
// 				{
// 					for(uword i = 0; val < v2; i++, val += step)
// 					{
// 						pushChar(t, val);
// 						ret.type.setItem(t, ret, i, -1);
// 						pop(t);
// 					}
// 				}
// 
// 				break;

			default: assert(false);
		}

		return 1;
	}

	uword fromArray(MDThread* t, uword numParams)
	{
		auto code = checkStringParam(t, 1);
		checkAnyParam(t, 2);

// 		if(code == "c" && !isArray(t, 2))
// 			checkStringParam(t, 2);
// 		else
			checkParam(t, 2, MDValue.Type.Array);

		pushGlobal(t, "Vector");
		pushNull(t);
		dup(t, 1);
		pushLen(t, 2);
		dup(t, 2);
		rawCall(t, -5, 1);

		return 1;
	}

	uword apply(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkParam(t, 1, MDValue.Type.Function);

		void doLoop(bool function(MDThread*, word) test, char[] typeMsg)
		{
			for(uword i = 0; i < memb.length; i++)
			{
				dup(t, 1);
				pushNull(t);
				memb.type.getItem(t, memb, i);
				rawCall(t, -3, 1);

				if(!test(t, -1))
				{
					pushTypeString(t, -1);
					throwException(t, "application function expected to return {}, not '{}'", typeMsg, getString(t, -1));
				}

				memb.type.setItem(t, memb, i, -1);
				pop(t);
			}
		}

		switch(memb.type.code)
		{
			case
				TypeCode.i8, TypeCode.i16, TypeCode.i32, TypeCode.i64,
				TypeCode.u8, TypeCode.u16, TypeCode.u32, TypeCode.u64:

				doLoop(&isInt, "'int'");
				break;

			case TypeCode.f32, TypeCode.f64:
				doLoop(&isNum, "'int' or 'float'");
				break;

// 			case TypeCode.c:
// 				doLoop(&isChar, "'char'");
// 				break;

			default: assert(false);
		}

		dup(t, 0);
		return 1;
	}
	
	uword copyRange(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto lo = optIntParam(t, 1, 0);
		auto hi = optIntParam(t, 2, memb.length);

		if(lo < 0)
			lo += memb.length;

		if(lo < 0 || lo > memb.length)
			throwException(t, "Invalid destination low index: {} (length: {})", lo, memb.length);

		if(hi < 0)
			hi += memb.length;

		if(hi < lo || hi > memb.length)
			throwException(t, "Invalid destination slice indices: {} .. {} (length: {})", lo, hi, memb.length);

		pushGlobal(t, "Vector");

		if(!as(t, 3, -1))
			paramTypeError(t, 3, "Vector");

		pop(t);

		auto other = getMembers!(Members)(t, 3);
		auto lo2 = optIntParam(t, 4, 0);
		auto hi2 = optIntParam(t, 5, lo2 + (hi - lo));

		if(lo2 < 0)
			lo2 += other.length;

		if(lo2 < 0 || lo2 > other.length)
			throwException(t, "Invalid source low index: {} (length: {})", lo2, other.length);

		if(hi2 < 0)
			hi2 += other.length;

		if(hi2 < lo2 || hi2 > other.length)
			throwException(t, "Invalid source slice indices: {} .. {} (length: {})", lo2, hi2, other.length);

		if((hi - lo) != (hi2 - lo2))
			throwException(t, "Destination length ({}) and source length({}) do not match", hi - lo, hi2 - lo2);

		auto isize = memb.type.itemSize;
		(cast(byte*)memb.data)[cast(uword)lo * isize .. cast(uword)hi * isize] = (cast(byte*)other.data)[cast(uword)lo2 * isize .. cast(uword)hi2 * isize];

		dup(t, 0);
		return 1;
	}

	void fillImpl(MDThread* t, Members* memb, word idx, uword lo, uword hi)
	{
		pushGlobal(t, "Vector");

		if(as(t, idx, -1))
		{
			auto other = getMembers!(Members)(t, idx);

			if(memb.type !is other.type)
				throwException(t, "Attempting to fill a vector of type '{}' using a vector of type '{}'", typeNames[memb.type.code], typeNames[other.type.code]);

			if(other.length != (hi - lo))
				throwException(t, "Length of destination ({}) and length of source ({}) do not match", hi - lo, other.length);

			auto isize = memb.type.itemSize;
			(cast(byte*)memb.data)[lo * isize .. hi * isize] = (cast(byte*)other.data)[0 .. other.length * isize];
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

			switch(memb.type.code)
			{
				case
					TypeCode.i8,
					TypeCode.i16,
					TypeCode.i32,
					TypeCode.i64,
					TypeCode.u8,
					TypeCode.u16,
					TypeCode.u32,
					TypeCode.u64:

					for(uword i = lo; i < hi; i++)
					{
						callFunc(i);

						if(!isInt(t, -1))
						{
							pushTypeString(t, -1);
							throwException(t, "filler function expected to return an 'int', not '{}'", getString(t, -1));
						}

						memb.type.setItem(t, memb, i, -1);
						pop(t);
					}
					break;

				case TypeCode.f32, TypeCode.f64:
					for(uword i = lo; i < hi; i++)
					{
						callFunc(i);

						if(!isNum(t, -1))
						{
							pushTypeString(t, -1);
							throwException(t, "filler function expected to return an 'int' or 'float', not '{}'", getString(t, -1));
						}

						memb.type.setItem(t, memb, i, -1);
						pop(t);
					}
					break;

// 				case TypeCode.c:
// 					for(uword i = lo; i < hi; i++)
// 					{
// 						callFunc(i);
// 
// 						if(!isChar(t, -1))
// 						{
// 							pushTypeString(t, -1);
// 							throwException(t, "filler function expected to return a 'char', not '{}'", getString(t, -1));
// 						}
// 
// 						memb.type.setItem(t, memb, i, -1);
// 						pop(t);
// 					}
// 					break;

				default: assert(false);
			}
		}
		else if(isNum(t, idx) || isChar(t, idx))
		{
			switch(memb.type.code)
			{
				case TypeCode.i8:  auto val = checkIntParam(t, idx);  (cast(byte*)memb.data)[lo .. hi] = cast(byte)val;     break;
				case TypeCode.i16: auto val = checkIntParam(t, idx);  (cast(short*)memb.data)[lo .. hi] = cast(short)val;   break;
				case TypeCode.i32: auto val = checkIntParam(t, idx);  (cast(int*)memb.data)[lo .. hi] = cast(int)val;       break;
				case TypeCode.i64: auto val = checkIntParam(t, idx);  (cast(long*)memb.data)[lo .. hi] = cast(long)val;     break;
				case TypeCode.u8:  auto val = checkIntParam(t, idx);  (cast(ubyte*)memb.data)[lo .. hi] = cast(ubyte)val;   break;
				case TypeCode.u16: auto val = checkIntParam(t, idx);  (cast(ushort*)memb.data)[lo .. hi] = cast(ushort)val; break;
				case TypeCode.u32: auto val = checkIntParam(t, idx);  (cast(uint*)memb.data)[lo .. hi] = cast(uint)val;     break;
				case TypeCode.u64: auto val = checkIntParam(t, idx);  (cast(ulong*)memb.data)[lo .. hi] = cast(ulong)val;   break;
				case TypeCode.f32: auto val = checkNumParam(t, idx);  (cast(float*)memb.data)[lo .. hi] = cast(float)val;   break;
				case TypeCode.f64: auto val = checkNumParam(t, idx);  (cast(double*)memb.data)[lo .. hi] = cast(double)val; break;
// 				case TypeCode.c:   auto val = checkCharParam(t, idx); (cast(dchar*)memb.data)[lo .. hi] = cast(dchar)val;   break;
				default: assert(false);
			}
		}
		else
		{
// 			if(memb.type.code == TypeCode.c && !isArray(t, idx))
// 				checkStringParam(t, idx);
// 			else
				checkParam(t, idx, MDValue.Type.Array);

			if(len(t, idx) != (hi - lo))
				throwException(t, "Length of destination ({}) and length of array ({}) do not match", hi - lo, len(t, idx));

			switch(memb.type.code)
			{
				case
					TypeCode.i8,
					TypeCode.i16,
					TypeCode.i32,
					TypeCode.i64,
					TypeCode.u8,
					TypeCode.u16,
					TypeCode.u32,
					TypeCode.u64:

					for(uword i = lo, ai = 0; i < hi; i++, ai++)
					{
						idxi(t, idx, ai);

						if(!isInt(t, -1))
						{
							pushTypeString(t, -1);
							throwException(t, "array element {} expected to be 'int', not '{}'", ai, getString(t, -1));
						}

						memb.type.setItem(t, memb, i, -1);
						pop(t);
					}
					break;

				case TypeCode.f32, TypeCode.f64:
					for(uword i = lo, ai = 0; i < hi; i++, ai++)
					{
						idxi(t, idx, ai);

						if(!isNum(t, -1))
						{
							pushTypeString(t, -1);
							throwException(t, "array element {} expected to be 'int' or 'float', not '{}'", ai, getString(t, -1));
						}

						memb.type.setItem(t, memb, i, -1);
						pop(t);
					}
					break;

// 				case TypeCode.c:
// 					auto ddat = (cast(dchar*)memb.data)[lo .. hi];
// 
// 					if(isArray(t, idx))
// 					{
// 						for(uword i = lo, ai = 0; i < hi; i++, ai++)
// 						{
// 							idxi(t, idx, ai);
// 
// 							if(!isChar(t, -1))
// 							{
// 								pushTypeString(t, -1);
// 								throwException(t, "array element {} expected to be 'char', not '{}'", ai, getString(t, -1));
// 							}
// 
// 							ddat[ai] = getChar(t, -1);
// 							pop(t);
// 						}
// 					}
// 					else
// 					{
// 						foreach(i, dchar c; getString(t, idx))
// 							ddat[i] = c;
// 					}
// 					break;

				default: assert(false);
			}
		}
		
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

		if(hi < 0)
			hi += memb.length;

		if(lo > hi || lo < 0 || lo > memb.length || hi < 0 || hi > memb.length)
			throwException(t, "Invalid range indices ({} .. {})", lo, hi);

		fillImpl(t, memb, 3, cast(uword)lo, cast(uword)hi);

		dup(t, 0);
		return 1;
	}
	
	uword vec_insert(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto idx = checkIntParam(t, 1);
		checkAnyParam(t, 2);
		
		if(idx < 0)
			idx += memb.length;
			
		if(idx < 0 || idx > memb.length)
			throwException(t, "Invalid index: {} (length: {})", idx, memb.length);

		void[] doResize(long otherLen)
		{
			long totalLen = memb.length + otherLen;

			if(totalLen > uword.max)
				throwException(t, "Invalid size ({})", totalLen);

			auto oldLen = memb.length;
			memb.length = cast(uword)totalLen;
			auto isize = memb.type.itemSize;
			auto tmp = memb.data[0 .. oldLen * isize];
			t.vm.alloc.resizeArray(tmp, cast(uword)totalLen * isize);
			memb.data = tmp.ptr;

			if(idx < oldLen)
			{
				auto end = idx + otherLen;
				auto numLeft = oldLen - idx;
				memmove(&tmp[cast(uword)end * isize], &tmp[cast(uword)idx * isize], cast(uint)(numLeft * isize));
			}

			return tmp;
		}

		pushGlobal(t, "Vector");

		if(as(t, 2, -1))
		{
			auto other = getMembers!(Members)(t, 2);

			if(memb.type !is other.type)
				throwException(t, "Attempting to insert a Vector of type '{}' into a Vector of type '{}'", typeNames[other.type.code], typeNames[memb.type.code]);

			auto tmp = doResize(other.length);
			auto isize = memb.type.itemSize;
			memcpy(&tmp[cast(uword)idx * isize], other.data, other.length * isize);
		}
		else
		{
// 			if(memb.type.code == TypeCode.c && isString(t, 2))
// 			{
// 				auto cpLen = len(t, 2);
// 
// 				if(cpLen != 0)
// 				{
// 					auto str = getString(t, 2);
// 					doResize(cpLen);
// 					auto dstr = (cast(dchar*)memb.data)[cast(uword)idx .. memb.length];
// 
// 					foreach(i, dchar c; str)
// 						dstr[i] = c;
// 				}
// 			}
// 			else
			{
				switch(memb.type.code)
				{
					case
						TypeCode.i8,
						TypeCode.i16,
						TypeCode.i32,
						TypeCode.i64,
						TypeCode.u8,
						TypeCode.u16,
						TypeCode.u32,
						TypeCode.u64:

						checkIntParam(t, 2);
						break;

					case TypeCode.f32, TypeCode.f64:
						checkNumParam(t, 2);
						break;

// 					case TypeCode.c:
// 						checkCharParam(t, 2);
// 						break;

					default: assert(false);
				}

				doResize(1);
				memb.type.setItem(t, memb, cast(uword)idx, 2);
			}
		}

		dup(t, 0);
		return 1;
	}
	
	uword itemSize(MDThread* t, uword numParams)
	{
		pushInt(t, getThis(t).type.itemSize);
		return 1;
	}

	uword map(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkParam(t, 1, MDValue.Type.Function);
		
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
		T minMaxImpl(T)(T* data, uword length)
		{
			auto arr = data[0 .. length];
			auto m = arr[0];

			foreach(val; arr[1 .. $])
				if(mixin("val " ~ compare ~ " m"))
					m = val;

			return m;
		}
	}

	uword max(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		if(memb.length == 0)
			throwException(t, "Vector is empty");

		switch(memb.type.code)
		{
			case TypeCode.i8:  pushInt(t, minMaxImpl!(">")(cast(byte*)memb.data, memb.length));             break;
			case TypeCode.i16: pushInt(t, minMaxImpl!(">")(cast(short*)memb.data, memb.length));            break;
			case TypeCode.i32: pushInt(t, minMaxImpl!(">")(cast(int*)memb.data, memb.length));              break;
			case TypeCode.i64: pushInt(t, minMaxImpl!(">")(cast(long*)memb.data, memb.length));             break;
			case TypeCode.u8:  pushInt(t, minMaxImpl!(">")(cast(ubyte*)memb.data, memb.length));            break;
			case TypeCode.u16: pushInt(t, minMaxImpl!(">")(cast(ushort*)memb.data, memb.length));           break;
			case TypeCode.u32: pushInt(t, minMaxImpl!(">")(cast(uint*)memb.data, memb.length));             break;
			case TypeCode.u64: pushInt(t, cast(mdint)minMaxImpl!(">")(cast(ulong*)memb.data, memb.length)); break;
			case TypeCode.f32: pushFloat(t, minMaxImpl!(">")(cast(float*)memb.data, memb.length));          break;
			case TypeCode.f64: pushFloat(t, minMaxImpl!(">")(cast(double*)memb.data, memb.length));         break;
// 			case TypeCode.c:   pushChar(t, minMaxImpl!(">")(cast(dchar*)memb.data, memb.length));           break;
			default: assert(false);
		}

		return 1;
	}

	uword min(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		if(memb.length == 0)
			throwException(t, "Vector is empty");

		switch(memb.type.code)
		{
			case TypeCode.i8:  pushInt(t, minMaxImpl!("<")(cast(byte*)memb.data, memb.length));             break;
			case TypeCode.i16: pushInt(t, minMaxImpl!("<")(cast(short*)memb.data, memb.length));            break;
			case TypeCode.i32: pushInt(t, minMaxImpl!("<")(cast(int*)memb.data, memb.length));              break;
			case TypeCode.i64: pushInt(t, minMaxImpl!("<")(cast(long*)memb.data, memb.length));             break;
			case TypeCode.u8:  pushInt(t, minMaxImpl!("<")(cast(ubyte*)memb.data, memb.length));            break;
			case TypeCode.u16: pushInt(t, minMaxImpl!("<")(cast(ushort*)memb.data, memb.length));           break;
			case TypeCode.u32: pushInt(t, minMaxImpl!("<")(cast(uint*)memb.data, memb.length));             break;
			case TypeCode.u64: pushInt(t, cast(mdint)minMaxImpl!("<")(cast(ulong*)memb.data, memb.length)); break;
			case TypeCode.f32: pushFloat(t, minMaxImpl!("<")(cast(float*)memb.data, memb.length));          break;
			case TypeCode.f64: pushFloat(t, minMaxImpl!("<")(cast(double*)memb.data, memb.length));         break;
// 			case TypeCode.c:   pushChar(t, minMaxImpl!("<")(cast(dchar*)memb.data, memb.length));           break;
			default: assert(false);
		}

		return 1;
	}

	uword vec_pop(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		
		if(memb.length == 0)
			throwException(t, "Vector is empty");

		auto index = optIntParam(t, 1, -1);

		if(index < 0)
			index += memb.length;

		if(index < 0 || index >= memb.length)
			throwException(t, "Invalid index: {}", index);

		memb.type.getItem(t, memb, cast(uword)index);

		auto isize = memb.type.itemSize;
		auto data = memb.data[0 .. memb.length * isize];

		if(index < memb.length - 1)
			memmove(&data[cast(uword)index * isize], &data[(cast(uword)index + 1) * isize], cast(uint)((memb.length - index - 1) * isize));

		t.vm.alloc.resizeArray(data, (memb.length - 1) * isize);
		memb.length--;
		memb.data = data.ptr;

		return 1;
	}

	uword product(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		mdfloat res = 1.0;

		switch(memb.type.code)
		{
			case TypeCode.i8:  foreach(val; (cast(byte*)memb.data)[0 .. memb.length]) res *= val;   break;
			case TypeCode.i16: foreach(val; (cast(short*)memb.data)[0 .. memb.length]) res *= val;  break;
			case TypeCode.i32: foreach(val; (cast(int*)memb.data)[0 .. memb.length]) res *= val;    break;
			case TypeCode.i64: foreach(val; (cast(long*)memb.data)[0 .. memb.length]) res *= val;   break;
			case TypeCode.u8:  foreach(val; (cast(ubyte*)memb.data)[0 .. memb.length]) res *= val;  break;
			case TypeCode.u16: foreach(val; (cast(ushort*)memb.data)[0 .. memb.length]) res *= val; break;
			case TypeCode.u32: foreach(val; (cast(uint*)memb.data)[0 .. memb.length]) res *= val;   break;
			case TypeCode.u64: foreach(val; (cast(ulong*)memb.data)[0 .. memb.length]) res *= val;  break;
			case TypeCode.f32: foreach(val; (cast(float*)memb.data)[0 .. memb.length]) res *= val;  break;
			case TypeCode.f64: foreach(val; (cast(double*)memb.data)[0 .. memb.length]) res *= val; break;
// 			case TypeCode.c:   throwException(t, "cannot get the product of a character vector");
			default: assert(false);
		}

		pushFloat(t, res);
		return 1;
	}

	uword remove(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		if(memb.length == 0)
			throwException(t, "Vector is empty");

		auto start = checkIntParam(t, 1);

		if(start < 0)
			start += memb.length;

		if(start < 0 || start > memb.length)
			throwException(t, "Invalid start index: {} (length: {})", start, memb.length);

		auto end = optIntParam(t, 2, start + 1);

		if(end < 0)
			end += memb.length;

		if(end < start || end > memb.length)
			throwException(t, "Invalid indices: {} .. {} (length: {})", start, end, memb.length);

		if(start == end)
		{
			dup(t, 0);
			return 1;
		}

		auto isize = memb.type.itemSize;
		auto data = memb.data[0 .. memb.length * isize];

		if(end < memb.length)
			memmove(&data[cast(uword)start * isize], &data[cast(uword)end * isize], cast(uint)((memb.length - end) * isize));

		auto diff = end - start;
		t.vm.alloc.resizeArray(data, cast(uword)((memb.length - diff) * isize));
		memb.length -= diff;
		memb.data = data.ptr;

		dup(t, 0);
		return 1;
	}

	uword reverse(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		switch(memb.type.itemSize)
		{
			case 1: (cast(byte*)memb.data)[0 .. memb.length].reverse;  break;
			case 2: (cast(short*)memb.data)[0 .. memb.length].reverse; break;
			case 4: (cast(int*)memb.data)[0 .. memb.length].reverse;   break;
			case 8: (cast(long*)memb.data)[0 .. memb.length].reverse;  break;

			default:
				throwException(t, "Not a horrible error, but somehow a vector type must've been added that doesn't have 1-, 2-, 4-, or 8-byte elements, so I don't know how to reverse it.");
		}

		dup(t, 0);
		return 1;
	}

	uword sort(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		switch(memb.type.code)
		{
			case TypeCode.i8:  (cast(byte*)memb.data)[0 .. memb.length].sort;   break;
			case TypeCode.i16: (cast(short*)memb.data)[0 .. memb.length].sort;  break;
			case TypeCode.i32: (cast(int*)memb.data)[0 .. memb.length].sort;    break;
			case TypeCode.i64: (cast(long*)memb.data)[0 .. memb.length].sort;   break;
			case TypeCode.u8:  (cast(ubyte*)memb.data)[0 .. memb.length].sort;  break;
			case TypeCode.u16: (cast(ushort*)memb.data)[0 .. memb.length].sort; break;
			case TypeCode.u32: (cast(uint*)memb.data)[0 .. memb.length].sort;   break;
			case TypeCode.u64: (cast(ulong*)memb.data)[0 .. memb.length].sort;  break;
			case TypeCode.f32: (cast(float*)memb.data)[0 .. memb.length].sort;  break;
			case TypeCode.f64: (cast(double*)memb.data)[0 .. memb.length].sort; break;
// 			case TypeCode.c:   (cast(dchar*)memb.data)[0 .. memb.length].sort;  break;
			default: assert(false);
		}

		dup(t, 0);
		return 1;
	}

	uword sum(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		mdfloat res = 0;

		switch(memb.type.code)
		{
			case TypeCode.i8:  foreach(val; (cast(byte*)memb.data)[0 .. memb.length]) res += val;   break;
			case TypeCode.i16: foreach(val; (cast(short*)memb.data)[0 .. memb.length]) res += val;  break;
			case TypeCode.i32: foreach(val; (cast(int*)memb.data)[0 .. memb.length]) res += val;    break;
			case TypeCode.i64: foreach(val; (cast(long*)memb.data)[0 .. memb.length]) res += val;   break;
			case TypeCode.u8:  foreach(val; (cast(ubyte*)memb.data)[0 .. memb.length]) res += val;  break;
			case TypeCode.u16: foreach(val; (cast(ushort*)memb.data)[0 .. memb.length]) res += val; break;
			case TypeCode.u32: foreach(val; (cast(uint*)memb.data)[0 .. memb.length]) res += val;   break;
			case TypeCode.u64: foreach(val; (cast(ulong*)memb.data)[0 .. memb.length]) res += val;  break;
			case TypeCode.f32: foreach(val; (cast(float*)memb.data)[0 .. memb.length]) res += val;  break;
			case TypeCode.f64: foreach(val; (cast(double*)memb.data)[0 .. memb.length]) res += val; break;
// 			case TypeCode.c:   throwException(t, "cannot get the sum of a character vector");
			default: assert(false);
		}

		pushFloat(t, res);
		return 1;
	}

	uword toArray(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto ret = newArray(t, memb.length);

		for(uword i = 0; i < memb.length; i++)
		{
			memb.type.getItem(t, memb, i);
			idxai(t, ret, i, true);
		}

		return 1;
	}

	uword toString(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		auto b = StrBuffer(t);
		b.addString("Vector(");
		pushFormat(t, "{})[", typeNames[memb.type.code]);
		b.addTop();

		if(memb.length > 0)
		{
			memb.type.getItem(t, memb, 0);
			pushToString(t, -1, true);
			insertAndPop(t, -2);
			b.addTop();

			for(uword i = 1; i < memb.length; i++)
			{
				b.addString(", ");
				memb.type.getItem(t, memb, i);
				pushToString(t, -1, true);
				insertAndPop(t, -2);
				b.addTop();
			}
		}

		b.addString("]");
		b.finish();
		return 1;
	}

// 	uword toStringValue(MDThread* t, uword numParams)
// 	{
// 		auto memb = getThis(t);
// 
// 		if(memb.type.code != TypeCode.c)
// 			throwException(t, "toStringValue may only be called on character vectors, not '{}' vectors", typeNames[memb.type.code]);
// 
// 		pushFormat(t, "{}", (cast(dchar*)memb.data)[0 .. memb.length]);
// 		return 1;
// 	}

	uword type(MDThread* t, uword numParams)
	{
		pushString(t, typeNames[getThis(t).type.code]);
		return 1;
	}

	uword opLength(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		pushInt(t, memb.length);
		return 1;
	}

	uword opLengthAssign(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto newLen = checkIntParam(t, 1);

		if(newLen < 0 || newLen > uword.max)
			throwException(t, "Invalid length ({})", newLen);

		auto oldLen = memb.length;

		if(newLen != oldLen)
		{
			memb.length = cast(uword)newLen;
			auto isize = memb.type.itemSize;

			if(oldLen == 0)
				memb.data = t.vm.alloc.allocArray!(void)(cast(uword)newLen * isize).ptr;
			else
			{
				auto tmp = memb.data[0 .. oldLen * isize];
				t.vm.alloc.resizeArray(tmp, cast(uword)newLen * isize);
				memb.data = tmp.ptr;
			}

			if(newLen > oldLen)
				(cast(byte*)memb.data)[oldLen * isize .. cast(uword)newLen * isize] = 0;
		}

		return 0;
	}

	uword opIndex(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto idx = checkIntParam(t, 1);

		if(idx < 0)
			idx += memb.length;

		if(idx < 0 || idx >= memb.length)
			throwException(t, "Invalid index ({})", idx);

		memb.type.getItem(t, memb, cast(uword)idx);
		return 1;
	}

	uword opIndexAssign(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto idx = checkIntParam(t, 1);

		if(idx < 0)
			idx += memb.length;

		if(idx < 0 || idx >= memb.length)
			throwException(t, "Invalid index ({})", idx);

		switch(memb.type.code)
		{
			case
				TypeCode.i8,
				TypeCode.i16,
				TypeCode.i32,
				TypeCode.i64,
				TypeCode.u8,
				TypeCode.u16,
				TypeCode.u32,
				TypeCode.u64:

				checkIntParam(t, 2);
				break;

			case TypeCode.f32, TypeCode.f64:
				checkNumParam(t, 2);
				break;

// 			case TypeCode.c:
// 				checkCharParam(t, 2);
// 				break;

			default: assert(false);
		}

		memb.type.setItem(t, memb, cast(uword)idx, 2);
		return 0;
	}
	
	uword opSlice(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto lo = optIntParam(t, 1, 0);
		auto hi = optIntParam(t, 2, memb.length);

		if(lo < 0)
			lo += memb.length;

		if(lo < 0 || lo > memb.length)
			throwException(t, "Invalid low index: {} (length: {})", lo, memb.length);

		if(hi < 0)
			hi += memb.length;

		if(hi < lo || hi > memb.length)
			throwException(t, "Invalid slice indices: {} .. {} (length: {})", lo, hi, memb.length);

		pushGlobal(t, "Vector");
		pushNull(t);
		pushString(t, typeNames[memb.type.code]);
		pushInt(t, hi - lo);
		rawCall(t, -4, 1);

		auto other = getMembers!(Members)(t, -1);
		auto isize = memb.type.itemSize;
		(cast(byte*)other.data)[0 .. other.length * isize] = (cast(byte*)memb.data)[cast(uword)lo * isize .. cast(uword)hi * isize];

		return 1;
	}

	uword iterator(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto index = checkIntParam(t, 1) + 1;

		if(index >= memb.length)
			return 0;

		pushInt(t, index);
		memb.type.getItem(t, memb, cast(uword)index);

		return 2;
	}

	uword iteratorReverse(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto index = checkIntParam(t, 1) - 1;

		if(index < 0)
			return 0;

		pushInt(t, index);
		memb.type.getItem(t, memb, cast(uword)index);

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

	uword opEquals(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkAnyParam(t, 1);

		pushGlobal(t, "Vector");

		if(!as(t, 1, -1))
		{
			pushTypeString(t, 1);
			throwException(t, "Attempting to compare a Vector to a '{}'", getString(t, -1));
		}

		if(opis(t, 0, 1))
			pushBool(t, true);
		else
		{
			auto other = getMembers!(Members)(t, 1);

			if(memb.type !is other.type)
				throwException(t, "Attempting to compare Vectors of types '{}' and '{}'", typeNames[memb.type.code], typeNames[other.type.code]);

			if(memb.length != other.length)
				pushBool(t, false);
			else
			{
				auto a = (cast(byte*)memb.data)[0 .. memb.length * memb.type.itemSize];
				auto b = (cast(byte*)other.data)[0 .. a.length];
				pushBool(t, a == b);
			}
		}

		return 1;
	}

	uword opCat(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkAnyParam(t, 1);
		
		pushGlobal(t, "Vector");
		
		if(as(t, 1, -1))
		{
			auto other = getMembers!(Members)(t, 1);

			if(other.type !is memb.type)
				throwException(t, "Attempting to concatenate Vectors of types '{}' and '{}'", typeNames[memb.type.code], typeNames[other.type.code]);

			pushNull(t);
			pushString(t, typeNames[memb.type.code]);
			pushInt(t, memb.length + other.length);
			rawCall(t, -4, 1);

			auto ret = getMembers!(Members)(t, -1);
			auto retData = (cast(byte*)ret.data)[0 .. ret.length * ret.type.itemSize];
			auto membData = (cast(byte*)memb.data)[0 .. memb.length * memb.type.itemSize];

			retData[0 .. membData.length] = membData[];
			retData[membData.length .. $] = (cast(byte*)other.data)[0 .. other.length * other.type.itemSize];
		}
		else
		{
			switch(memb.type.code)
			{
				case
					TypeCode.i8,
					TypeCode.i16,
					TypeCode.i32,
					TypeCode.i64,
					TypeCode.u8,
					TypeCode.u16,
					TypeCode.u32,
					TypeCode.u64:                checkIntParam(t, 1); break;
				case TypeCode.f32, TypeCode.f64: checkNumParam(t, 1); break;
// 				case TypeCode.c:                 checkCharParam(t, 1); break;
				default: assert(false);
			}

			pushNull(t);
			pushString(t, typeNames[memb.type.code]);
			pushInt(t, memb.length + 1);
			rawCall(t, -4, 1);

			auto ret = getMembers!(Members)(t, -1);
			auto retData = (cast(byte*)ret.data)[0 .. ret.length * ret.type.itemSize];
			auto membData = (cast(byte*)memb.data)[0 .. memb.length * memb.type.itemSize];

			retData[0 .. membData.length] = membData[];
			ret.type.setItem(t, ret, ret.length - 1, 1);
		}

		return 1;
	}

	uword opCat_r(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkAnyParam(t, 1);

		switch(memb.type.code)
		{
			case
				TypeCode.i8,
				TypeCode.i16,
				TypeCode.i32,
				TypeCode.i64,
				TypeCode.u8,
				TypeCode.u16,
				TypeCode.u32,
				TypeCode.u64:                checkIntParam(t, 1); break;
			case TypeCode.f32, TypeCode.f64: checkNumParam(t, 1); break;
// 			case TypeCode.c:                 checkCharParam(t, 1); break;
			default: assert(false);
		}

		pushGlobal(t, "Vector");
		pushNull(t);
		pushString(t, typeNames[memb.type.code]);
		pushInt(t, memb.length + 1);
		rawCall(t, -4, 1);

		auto ret = getMembers!(Members)(t, -1);
		auto retData = (cast(byte*)ret.data)[0 .. ret.length * ret.type.itemSize];
		auto membData = (cast(byte*)memb.data)[0 .. memb.length * memb.type.itemSize];

		retData[1 .. membData.length + 1] = membData[];
		ret.type.setItem(t, ret, 0, 1);

		return 1;
	}

	uword opCatAssign(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkAnyParam(t, 1);

		pushGlobal(t, "Vector");
		ulong totalLen = memb.length;

		for(uword i = 1; i <= numParams; i++)
		{
			if(as(t, i, -1))
			{
				auto other = getMembers!(Members)(t, i);

				if(other.type !is memb.type)
					throwException(t, "Attempting to concatenate Vectors of types '{}' and '{}'", typeNames[memb.type.code], typeNames[other.type.code]);

				totalLen += other.length;
			}
			else
			{
				switch(memb.type.code)
				{
					case
						TypeCode.i8,
						TypeCode.i16,
						TypeCode.i32,
						TypeCode.i64,
						TypeCode.u8,
						TypeCode.u16,
						TypeCode.u32,
						TypeCode.u64:                checkIntParam(t, i);  break;
					case TypeCode.f32, TypeCode.f64: checkNumParam(t, i);  break;
// 					case TypeCode.c:                 checkCharParam(t, i); break;
					default: assert(false);
				}

				totalLen++;
			}
		}

		if(totalLen > uword.max)
			throwException(t, "Invalid size ({})", totalLen);

		auto oldLen = memb.length;
		memb.length = cast(uword)totalLen;
		auto isize = memb.type.itemSize;
		auto tmp = memb.data[0 .. oldLen * isize];
		t.vm.alloc.resizeArray(tmp, cast(uword)totalLen * isize);
		memb.data = tmp.ptr;

		uword j = oldLen * isize;

		for(uword i = 1; i <= numParams; i++)
		{
			if(as(t, i, -1))
			{
				auto other = getMembers!(Members)(t, i);
				auto otherData = (cast(byte*)other.data)[0 .. other.length * isize];
				(cast(byte*)memb.data)[j .. j + otherData.length] = otherData[];
				j += otherData.length;
			}
			else
			{
				memb.type.setItem(t, memb, j / isize, i);
				j += isize;
			}
		}

		return 0;
	}

	char[] opAssign(char[] name, char[] op)
	{
		return `uword op` ~ name ~ `Assign(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			checkAnyParam(t, 1);

			pushGlobal(t, "Vector");

			if(as(t, 1, -1))
			{
				auto other = getMembers!(Members)(t, 1);

				if(other.length != memb.length)
					throwException(t, "Cannot perform operation on vectors of different lengths");

// 				if(memb.type.code == TypeCode.c)
// 				{
// 					switch(other.type.code)
// 					{
// 						case TypeCode.i8, TypeCode.i16, TypeCode.i64, TypeCode.u8, TypeCode.u16, TypeCode.u64:
// 							for(uword i = 0; i < memb.length; i++)
// 							{
// 								other.type.getItem(t, other, i);
// 								(cast(dchar*)memb.data)[i] ` ~ op ~ `= getInt(t, -1);
// 								pop(t);
// 							}
// 							break;
// 
// 						case TypeCode.i32, TypeCode.u32:
// 							(cast(dchar*)memb.data)[0 .. memb.length] ` ~ op ~ `= (cast(dchar*)other.data)[0 .. other.length];
// 							break;
// 
// 						case TypeCode.f32, TypeCode.f64, TypeCode.c:
// 							throwException(t, "Character vectors may only be used with integer vectors for this operation");
// 
// 						default: assert(false);
// 					}
// 				}
// 				else
				{
					if(other.type !is memb.type)
						throwException(t, "Cannot perform operation on vectors of types '{}' and '{}'", typeNames[memb.type.code], typeNames[other.type.code]);

					switch(memb.type.code)
					{
						case TypeCode.i8:  (cast(byte*)memb.data)[0 .. memb.length]   ` ~ op ~ `= (cast(byte*)other.data)[0 .. other.length];   break;
						case TypeCode.i16: (cast(short*)memb.data)[0 .. memb.length]  ` ~ op ~ `= (cast(short*)other.data)[0 .. other.length];  break;
						case TypeCode.i32: (cast(int*)memb.data)[0 .. memb.length]    ` ~ op ~ `= (cast(int*)other.data)[0 .. other.length];    break;
						case TypeCode.i64: (cast(long*)memb.data)[0 .. memb.length]   ` ~ op ~ `= (cast(long*)other.data)[0 .. other.length];   break;
						case TypeCode.u8:  (cast(ubyte*)memb.data)[0 .. memb.length]  ` ~ op ~ `= (cast(ubyte*)other.data)[0 .. other.length];  break;
						case TypeCode.u16: (cast(ushort*)memb.data)[0 .. memb.length] ` ~ op ~ `= (cast(ushort*)other.data)[0 .. other.length]; break;
						case TypeCode.u32: (cast(uint*)memb.data)[0 .. memb.length]   ` ~ op ~ `= (cast(uint*)other.data)[0 .. other.length];   break;
						case TypeCode.u64: (cast(ulong*)memb.data)[0 .. memb.length]  ` ~ op ~ `= (cast(ulong*)other.data)[0 .. other.length];  break;
						case TypeCode.f32: (cast(float*)memb.data)[0 .. memb.length]  ` ~ op ~ `= (cast(float*)other.data)[0 .. other.length];  break;
						case TypeCode.f64: (cast(double*)memb.data)[0 .. memb.length] ` ~ op ~ `= (cast(double*)other.data)[0 .. other.length]; break;
						default: assert(false);
					}
				}
			}
			else
			{
				switch(memb.type.code)
				{
					case TypeCode.i8:  auto val = checkIntParam(t, 1); (cast(byte*)memb.data)[0 .. memb.length]   ` ~ op ~ `= cast(byte)val;   break;
					case TypeCode.i16: auto val = checkIntParam(t, 1); (cast(short*)memb.data)[0 .. memb.length]  ` ~ op ~ `= cast(short)val;  break;
					case TypeCode.i32: auto val = checkIntParam(t, 1); (cast(int*)memb.data)[0 .. memb.length]    ` ~ op ~ `= cast(int)val;    break;
					case TypeCode.i64: auto val = checkIntParam(t, 1); (cast(long*)memb.data)[0 .. memb.length]   ` ~ op ~ `= cast(long)val;   break;
					case TypeCode.u8:  auto val = checkIntParam(t, 1); (cast(ubyte*)memb.data)[0 .. memb.length]  ` ~ op ~ `= cast(ubyte)val;  break;
					case TypeCode.u16: auto val = checkIntParam(t, 1); (cast(ushort*)memb.data)[0 .. memb.length] ` ~ op ~ `= cast(ushort)val; break;
					case TypeCode.u32: auto val = checkIntParam(t, 1); (cast(uint*)memb.data)[0 .. memb.length]   ` ~ op ~ `= cast(uint)val;   break;
					case TypeCode.u64: auto val = checkIntParam(t, 1); (cast(ulong*)memb.data)[0 .. memb.length]  ` ~ op ~ `= cast(ulong)val;  break;
					case TypeCode.f32: auto val = checkNumParam(t, 1); (cast(float*)memb.data)[0 .. memb.length]  ` ~ op ~ `= cast(float)val;  break;
					case TypeCode.f64: auto val = checkNumParam(t, 1); (cast(double*)memb.data)[0 .. memb.length] ` ~ op ~ `= cast(double)val; break;
// 					case TypeCode.c:   auto val = checkIntParam(t, 1); (cast(dchar*)memb.data)[0 .. memb.length]  ` ~ op ~ `= cast(uint)val;   break;
					default: assert(false);
				}
			}

			return 0;
		}`; /+ " +/
	}

	mixin(opAssign("Add", "+"));
	mixin(opAssign("Sub", "-"));
	mixin(opAssign("Mul", "*"));
	mixin(opAssign("Div", "/"));
	mixin(opAssign("Mod", "%"));

	char[] op(char[] name)
	{
		return `uword op` ~ name ~ `(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			checkAnyParam(t, 1);

			word first = 0, second = 1;

			pushGlobal(t, "Vector");

// 			if(as(t, 1, -1) && getMembers!(Members)(t, 1).type.code == TypeCode.c)
// 			{
// 				first = 1;
// 				second = 0;
// 			}

			pop(t);

			auto ret = dup(t, first);
			pushNull(t);
			methodCall(t, -2, "dup", 1);

			dup(t, ret);
			pushNull(t);
			dup(t, second);
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
		return `uword op` ~ name ~ `_r(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			checkAnyParam(t, 1);

			word first = 0, second = 1;

			pushGlobal(t, "Vector");

// 			if(as(t, 1, -1) && getMembers!(Members)(t, 1).type.code == TypeCode.c)
// 			{
// 				first = 1;
// 				second = 0;
// 			}

			pop(t);

			auto ret = dup(t, first);
			pushNull(t);
			methodCall(t, -2, "dup", 1);

			dup(t, ret);
			pushNull(t);
			dup(t, second);
			methodCall(t, -3, "rev` ~ name ~ `", 0);

			return 1;
		}`; /+ " +/
	}

	mixin(op_rev("Sub"));
	mixin(op_rev("Div"));
	mixin(op_rev("Mod"));

	// BUG 2434: Compiler generates code that does not pass with -w for some array operations
	// namely, for the [u](byte|short) cases for div and mod.

	char[] rev_func(char[] name, char[] op)
	{
		return `uword rev` ~ name ~ `(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);

// 			if(memb.type.code == TypeCode.c)
// 				throwException(t, "Cannot perform operation on character vectors");

			checkAnyParam(t, 1);
			pushGlobal(t, "Vector");

			if(as(t, 1, -1))
			{
				auto other = getMembers!(Members)(t, 1);

				if(other.length != memb.length)
					throwException(t, "Cannot perform operation on vectors of different lengths");

				if(other.type !is memb.type)
					throwException(t, "Cannot perform operation on vectors of types '{}' and '{}'", typeNames[memb.type.code], typeNames[other.type.code]);

				switch(memb.type.code)
				{
					case TypeCode.i8:
						auto data = (cast(byte*)memb.data)[0 .. memb.length];
						auto otherData = (cast(byte*)other.data)[0 .. other.length];

						for(uword i = 0; i < data.length; i++)
							data[i] = cast(byte)(otherData[i] ` ~ op ~ ` data[i]);
						break;

					case TypeCode.i16:
						auto data = (cast(short*)memb.data)[0 .. memb.length];
						auto otherData = (cast(short*)other.data)[0 .. other.length];

						for(uword i = 0; i < data.length; i++)
							data[i] = cast(short)(otherData[i] ` ~ op ~ ` data[i]);
						break;

					case TypeCode.i32:
						auto dat = (cast(int*)memb.data)[0 .. memb.length];
						dat[] = (cast(int*)other.data)[0 .. other.length] ` ~ op ~ ` dat[];
						break;

					case TypeCode.i64:
						auto dat = (cast(long*)memb.data)[0 .. memb.length];
						dat[] = (cast(long*)other.data)[0 .. other.length] ` ~ op ~ ` dat[];
						break;

					case TypeCode.u8:
						auto data = (cast(ubyte*)memb.data)[0 .. memb.length];
						auto otherData = (cast(ubyte*)other.data)[0 .. other.length];

						for(uword i = 0; i < data.length; i++)
							data[i] = cast(ubyte)(otherData[i] ` ~ op ~ ` data[i]);
						break;

					case TypeCode.u16:
						auto data = (cast(ushort*)memb.data)[0 .. memb.length];
						auto otherData = (cast(ushort*)other.data)[0 .. other.length];

						for(uword i = 0; i < data.length; i++)
							data[i] = cast(ushort)(otherData[i] ` ~ op ~ ` data[i]);
						break;

					case TypeCode.u32:
						auto dat = (cast(uint*)memb.data)[0 .. memb.length];
						dat[] = (cast(uint*)other.data)[0 .. other.length] ` ~ op ~ ` dat[];
						break;

					case TypeCode.u64:
						auto dat = (cast(ulong*)memb.data)[0 .. memb.length];
						dat[] = (cast(ulong*)other.data)[0 .. other.length] ` ~ op ~ ` dat[];
						break;

					case TypeCode.f32:
						auto dat = (cast(float*)memb.data)[0 .. memb.length];
						dat[] = (cast(float*)other.data)[0 .. other.length] ` ~ op ~ ` dat[];
						break;

					case TypeCode.f64:
						auto dat = (cast(double*)memb.data)[0 .. memb.length];
						dat[] = (cast(double*)other.data)[0 .. other.length] ` ~ op ~ ` dat[];
						break;

					default: assert(false);
				}
			}
			else
			{
				switch(memb.type.code)
				{
					case TypeCode.i8:
						auto val = cast(byte)checkIntParam(t, 1);
						auto dat = (cast(byte*)memb.data)[0 .. memb.length];

						for(uword i = 0; i < dat.length; i++)
							dat[i] = cast(byte)(val ` ~ op ~ ` dat[i]);
						break;

					case TypeCode.i16:
						auto val = cast(short)checkIntParam(t, 1);
						auto dat = (cast(short*)memb.data)[0 .. memb.length];

						for(uword i = 0; i < dat.length; i++)
							dat[i] = cast(short)(val ` ~ op ~ ` dat[i]);
						break;

					case TypeCode.i32:
						auto val = cast(int)checkIntParam(t, 1);
						auto dat = (cast(int*)memb.data)[0 .. memb.length];
						dat[] = val ` ~ op ~ `dat[];
						break;

					case TypeCode.i64:
						auto val = cast(long)checkIntParam(t, 1);
						auto dat = (cast(long*)memb.data)[0 .. memb.length];
						dat[] = val ` ~ op ~ `dat[];
						break;

					case TypeCode.u8:
						auto val = cast(ubyte)checkIntParam(t, 1);
						auto dat = (cast(ubyte*)memb.data)[0 .. memb.length];

						for(uword i = 0; i < dat.length; i++)
							dat[i] = cast(ubyte)(val ` ~ op ~ ` dat[i]);
						break;

					case TypeCode.u16:
						auto val = cast(ushort)checkIntParam(t, 1);
						auto dat = (cast(ushort*)memb.data)[0 .. memb.length];

						for(uword i = 0; i < dat.length; i++)
							dat[i] = cast(ushort)(val ` ~ op ~ ` dat[i]);
						break;

					case TypeCode.u32:
						auto val = cast(uint)checkIntParam(t, 1);
						auto dat = (cast(uint*)memb.data)[0 .. memb.length];
						dat[] = val ` ~ op ~ `dat[];
						break;

					case TypeCode.u64:
						auto val = cast(ulong)checkIntParam(t, 1);
						auto dat = (cast(ulong*)memb.data)[0 .. memb.length];
						dat[] = val ` ~ op ~ `dat[];
						break;

					case TypeCode.f32:
						auto val = cast(float)checkNumParam(t, 1);
						auto dat = (cast(float*)memb.data)[0 .. memb.length];
						dat[] = val ` ~ op ~ `dat[];
						break;

					case TypeCode.f64:
						auto val = cast(double)checkNumParam(t, 1);
						auto dat = (cast(double*)memb.data)[0 .. memb.length];
						dat[] = val ` ~ op ~ `dat[];
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