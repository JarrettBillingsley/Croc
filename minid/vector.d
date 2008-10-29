
module minid.vector;

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
		c
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
		"c"
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

	word get_c(MDThread* t, Members* memb, uword idx)              { return pushChar(t, (cast(dchar*)memb.data)[idx]); }
	void set_c(MDThread* t, Members* memb, uword idx, word item)   { (cast(dchar*)memb.data)[idx] = cast(dchar)getChar(t, item); }

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
		{ TypeCode.c,   sizes[TypeCode.c],   &get_c,   &set_c }
	];

	struct Members
	{
		void* data;
		uword length;
		TypeStruct* type;
	}

	void init(MDThread* t)
	{
		CreateObject(t, "Vector", (CreateObject* o)
		{
				newFunction(t, &finalizer, "Vector.finalizer");
				dup(t);
			o.method("clone",          &clone, 1);
			o.method("dup",            &vec_dup, 1);

			o.method("apply",          &apply);
			o.method("fill",           &fill);
// 			o.method("insert",         &insert);
// 			o.method("map",            &map);
// 			o.method("max",            &max);
// 			o.method("min",            &min);
// 			o.method("pop",            &pop);
// 			o.method("pow",            &pow);
			o.method("product",        &product);
// 			o.method("remove",         &remove);
// 			o.method("reverse",        &reverse);
// 			o.method("sort",           &sort);
			o.method("sum",            &sum);
			o.method("toArray",        &toArray);
			o.method("toString",       &toString);
			o.method("toStringValue",  &toStringValue);
			o.method("type",           &type);

			o.method("opLength",       &opLength);
			o.method("opLengthAssign", &opLengthAssign);
			o.method("opIndex",        &opIndex);
			o.method("opIndexAssign",  &opIndexAssign);
// 			o.method("opSlice",        &opSlice);
// 			o.method("opSliceAssign",  &opSliceAssign);

			o.method("opAdd",          &opAdd);
			o.method("opAddAssign",    &opAddAssign);
			o.method("opSub",          &opSub);
			o.method("opSub_r",        &opSub_r);
			o.method("opSubAssign",    &opSubAssign);
			o.method("revSub",         &revSub);
// 			o.method("opCat",          &opCat);
// 			o.method("opCat_r",        &opCat_r);
// 			o.method("opCatAssign",    &opCatAssign);
			o.method("opMul",          &opMul);
			o.method("opMulAssign",    &opMulAssign);
			o.method("opDiv",          &opDiv);
			o.method("opDiv_r",        &opDiv_r);
			o.method("opDivAssign",    &opDivAssign);
			o.method("revDiv",         &revDiv);
			o.method("opMod",          &opMod);
			o.method("opMod_r",        &opMod_r);
			o.method("opModAssign",    &opModAssign);
			o.method("revMod",         &revMod);

// 			o.method("opEquals",       &opEquals);
// 			o.method("opCmp",          &opCmp);

// 				newFunction(t, &iterator, "Vector.iterator");
// 				newFunction(t, &iteratorReverse, "Vector.iteratorReverse");
// 			o.method("opApply", &opApply, 2);
		});

// 		field(t, -1, "opCatAssign");
// 		fielda(t, -2, "append");

		field(t, -1, "opAdd");
		fielda(t, -2, "opAdd_r");

		field(t, -1, "opMul");
		fielda(t, -2, "opMul_r");

		newGlobal(t, "Vector");
	}

	private Members* getThis(MDThread* t)
	{
		return checkObjParam!(Members)(t, 0, "Vector");
	}

	uword finalizer(MDThread* t, uword numParams)
	{
		auto memb = cast(Members*)getExtraBytes(t, 0).ptr;

		if(memb.data !is null)
		{
			auto tmp = memb.data[0 .. memb.length * memb.type.itemSize];
			t.vm.alloc.freeArray(tmp);
			memb.data = null;
			memb.length = 0;
		}

		return 0;
	}

	uword clone(MDThread* t, uword numParams)
	{
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
			case "c"  : ts = &typeStructs[TypeCode.c];   break;

			default:
				throwException(t, "Invalid type code '{}'", type);
		}

		auto ret = newObject(t, 0, null, 0, Members.sizeof);
		auto memb = getMembers!(Members)(t, ret);
		*memb = Members.init;

		memb.type = ts;
		memb.length = cast(uword)size;
		memb.data = t.vm.alloc.allocArray!(void)(cast(uword)size * memb.type.itemSize).ptr;

		getUpval(t, 0);
		setFinalizer(t, ret);

		if(haveFiller)
		{
			dup(t, ret);
			pushNull(t);
			dup(t, 3);
			methodCall(t, -3, "fill", 0);
		}
		else
			(cast(byte*)memb.data)[0 .. memb.length * memb.type.itemSize] = 0;

		return 1;
	}

	uword vec_dup(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		auto base = pushGlobal(t, "Vector");
		auto ret = newObject(t, base, null, 0, Members.sizeof);
		auto newMemb = getMembers!(Members)(t, ret);
		*newMemb = Members.init;

		newMemb.type = memb.type;
		newMemb.length = memb.length;

		auto byteSize = memb.length * memb.type.itemSize;
		newMemb.data = t.vm.alloc.allocArray!(void)(byteSize).ptr;
		(cast(byte*)newMemb.data)[0 .. byteSize] = (cast(byte*)memb.data)[0 .. byteSize];

		getUpval(t, 0);
		setFinalizer(t, ret);

		return 1;
	}

	uword apply(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkParam(t, 1, MDValue.Type.Function);

		void callFunc(uword i)
		{
			dup(t, 1);
			pushNull(t);
			memb.type.getItem(t, memb, i);
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

				for(uword i = 0; i < memb.length; i++)
				{
					callFunc(i);

					if(!isInt(t, -1))
					{
						pushTypeString(t, -1);
						throwException(t, "application function expected to return an 'int', not '{}'", getString(t, -1));
					}

					memb.type.setItem(t, memb, i, -1);
					pop(t);
				}
				break;

			case TypeCode.f32, TypeCode.f64:
				for(uword i = 0; i < memb.length; i++)
				{
					callFunc(i);

					if(!isNum(t, -1))
					{
						pushTypeString(t, -1);
						throwException(t, "application function expected to return an 'int' or 'float', not '{}'", getString(t, -1));
					}

					memb.type.setItem(t, memb, i, -1);
					pop(t);
				}
				break;

			case TypeCode.c:
				for(uword i = 0; i < memb.length; i++)
				{
					callFunc(i);

					if(!isChar(t, -1))
					{
						pushTypeString(t, -1);
						throwException(t, "application function expected to return a 'char', not '{}'", getString(t, -1));
					}

					memb.type.setItem(t, memb, i, -1);
					pop(t);
				}
				break;

			default: assert(false);
		}

		dup(t, 0);
		return 1;
	}

	uword fill(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkAnyParam(t, 1);

		if(isFunction(t, 1))
		{
			void callFunc(uword i)
			{
				dup(t, 1);
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

					for(uword i = 0; i < memb.length; i++)
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
					for(uword i = 0; i < memb.length; i++)
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

				case TypeCode.c:
					for(uword i = 0; i < memb.length; i++)
					{
						callFunc(i);

						if(!isChar(t, -1))
						{
							pushTypeString(t, -1);
							throwException(t, "filler function expected to return a 'char', not '{}'", getString(t, -1));
						}

						memb.type.setItem(t, memb, i, -1);
						pop(t);
					}
					break;

				default: assert(false);
			}
		}
		else
		{
			switch(memb.type.code)
			{
				case TypeCode.i8:  auto val = checkIntParam(t, 1);  (cast(byte*)memb.data)[0 .. memb.length] = cast(byte)val;     break;
				case TypeCode.i16: auto val = checkIntParam(t, 1);  (cast(short*)memb.data)[0 .. memb.length] = cast(short)val;   break;
				case TypeCode.i32: auto val = checkIntParam(t, 1);  (cast(int*)memb.data)[0 .. memb.length] = cast(int)val;       break;
				case TypeCode.i64: auto val = checkIntParam(t, 1);  (cast(long*)memb.data)[0 .. memb.length] = cast(long)val;     break;
				case TypeCode.u8:  auto val = checkIntParam(t, 1);  (cast(ubyte*)memb.data)[0 .. memb.length] = cast(ubyte)val;   break;
				case TypeCode.u16: auto val = checkIntParam(t, 1);  (cast(ushort*)memb.data)[0 .. memb.length] = cast(ushort)val; break;
				case TypeCode.u32: auto val = checkIntParam(t, 1);  (cast(uint*)memb.data)[0 .. memb.length] = cast(uint)val;     break;
				case TypeCode.u64: auto val = checkIntParam(t, 1);  (cast(ulong*)memb.data)[0 .. memb.length] = cast(ulong)val;   break;
				case TypeCode.f32: auto val = checkNumParam(t, 1);  (cast(float*)memb.data)[0 .. memb.length] = cast(float)val;   break;
				case TypeCode.f64: auto val = checkNumParam(t, 1);  (cast(double*)memb.data)[0 .. memb.length] = cast(double)val; break;
				case TypeCode.c:   auto val = checkCharParam(t, 1); (cast(dchar*)memb.data)[0 .. memb.length] = cast(dchar)val;   break;
				default: assert(false);
			}
		}

		dup(t, 0);
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
			case TypeCode.c:   throwException(t, "cannot get the product of a character vector");
			default: assert(false);
		}

		pushFloat(t, res);
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
			case TypeCode.c:   throwException(t, "cannot get the sum of a character vector");
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

	uword toStringValue(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		if(memb.type.code != TypeCode.c)
			throwException(t, "toStringValue may only be called on character vectors, not '{}' vectors", typeNames[memb.type.code]);

		pushFormat(t, "{}", (cast(dchar*)memb.data)[0 .. memb.length]);
		return 1;
	}

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

			case TypeCode.c:
				checkCharParam(t, 2);
				break;

			default: assert(false);
		}

		memb.type.setItem(t, memb, cast(uword)idx, 2);
		return 0;
	}

	char[] opAssign(char[] name, char[] op)
	{
		return `uword op` ~ name ~ `Assign(MDThread* t, uword numParams)
		{
			auto memb = getThis(t);
			checkAnyParam(t, 1);

			pushGlobal(t, "Vector");

			if(strictlyAs(t, 1, -1))
			{
				auto other = getMembers!(Members)(t, 1);

				if(other.length != memb.length)
					throwException(t, "Cannot perform operation on vectors of different lengths");

				if(memb.type.code == TypeCode.c)
				{
					switch(other.type.code)
					{
						case TypeCode.i8, TypeCode.i16, TypeCode.i64, TypeCode.u8, TypeCode.u16, TypeCode.u64:
							for(uword i = 0; i < memb.length; i++)
							{
								other.type.getItem(t, other, i);
								(cast(dchar*)memb.data)[i] ` ~ op ~ `= getInt(t, -1);
								pop(t);
							}
							break;

						case TypeCode.i32, TypeCode.u32:
							(cast(dchar*)memb.data)[0 .. memb.length] ` ~ op ~ `= (cast(dchar*)other.data)[0 .. other.length];
							break;

						case TypeCode.f32, TypeCode.f64, TypeCode.c:
							throwException(t, "Character vectors may only be used with integer vectors for this operation");

						default: assert(false);
					}
				}
				else
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
					case TypeCode.c:   auto val = checkIntParam(t, 1); (cast(dchar*)memb.data)[0 .. memb.length]  ` ~ op ~ `= cast(uint)val;   break;
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

			if(strictlyAs(t, 1, -1) && getMembers!(Members)(t, 1).type.code == TypeCode.c)
			{
				first = 1;
				second = 0;
			}

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

			if(strictlyAs(t, 1, -1) && getMembers!(Members)(t, 1).type.code == TypeCode.c)
			{
				first = 1;
				second = 0;
			}

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

			if(memb.type.code == TypeCode.c)
				throwException(t, "Cannot perform operation on character vectors");

			checkAnyParam(t, 1);
			pushGlobal(t, "Vector");

			if(strictlyAs(t, 1, -1))
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

			return 0;
		}`; /+ " +/
	}

	mixin(rev_func("Sub", "-"));
	mixin(rev_func("Div", "/"));
	mixin(rev_func("Mod", "%"));
}