module minid.types;

import utf = std.utf;
import string = std.string;
import format = std.format;
import std.c.string;
import std.stdarg;

import minid.state;
import minid.opcodes;

const uint MaxRegisters = Instruction.rs1Max >> 1;
const uint MaxConstants = Instruction.constMax;
const uint MaxUpvalues = Instruction.immMax;

// Don't know why this isn't in phobos.
char[] vformat(TypeInfo[] arguments, va_list argptr)
{
	char[] s;
	
	void putc(dchar c)
	{
		utf.encode(s, c);
	}
	
	format.doFormat(&putc, arguments, argptr);

	return s;
}

class MDException : Exception
{
	public MDValue value;

	public this(...)
	{
		char[] msg = vformat(_arguments, _argptr);
		super(msg);
		value.value = new MDString(msg);
	}

	public this(MDValue val)
	{
		this(&val);
	}
	
	public this(MDValue* val)
	{
		value = *val;
		super(value.toString());
	}
	
	public this(MDTable t)
	{
		MDValue val;
		val.value = t;
		this(&val);
	}
}

class MDCompileException : MDException
{
	public this(Location loc, ...)
	{
		super(loc.toString(), ": ", vformat(_arguments, _argptr));
	}
}

class MDRuntimeException : MDException
{
	public Location location;

	public this(MDState s, MDValue* val)
	{
		location = s.startTraceback();
		super(val);
	}

	public this(MDState s, ...)
	{
		location = s.startTraceback();
		super(vformat(_arguments, _argptr));
	}

	public char[] toString()
	{
		return string.format(location.toString(), ": ", msg);
	}
}

int dcmp(dchar[] s1, dchar[] s2)
{
	auto len = s1.length;
	int result;

	if(s2.length < len)
		len = s2.length;

	result = memcmp(s1, s2, len);

	if(result == 0)
		result = cast(int)s1.length - cast(int)s2.length;

	return result;
}

// All available metamethods.
// These are kind of ordered by "importance," so that the most commonly-used ones are at the
// beginning for possible optimization purposes.
enum MM
{
	Index,
	IndexAssign,
	Cmp,
	ToString,
	Length,
	Apply,
	Add,
	Sub,
	Cat,
	Mul,
	Div,
	Mod,
	Neg,
	Call,
	And,
	Or,
	Xor,
	Shl,
	Shr,
	UShr,
	Com,
	AddEq,
	SubEq,
	CatEq,
	MulEq,
	DivEq,
	ModEq,
	AndEq,
	OrEq,
	XorEq,
	ShlEq,
	ShrEq,
	UShrEq
}

const dchar[][] MetaNames =
[
	MM.Add : "opAdd",
	MM.AddEq : "opAddEq",
	MM.And : "opAnd",
	MM.AndEq : "opAndEq",
	MM.Apply : "opApply",
	MM.Call : "opCall",
	MM.Cat : "opCat",
	MM.CatEq : "opCatEq",
	MM.Cmp : "opCmp",
	MM.Com : "opCom",
	MM.Div : "opDiv",
	MM.DivEq : "opDivEq",
	MM.Index : "opIndex",
	MM.IndexAssign : "opIndexAssign",
	MM.Length : "opLength",
	MM.Mod : "opMod",
	MM.ModEq : "opModEq",
	MM.Mul : "opMul",
	MM.MulEq : "opMulEq",
	MM.Neg : "opNeg",
	MM.Or : "opOr",
	MM.OrEq : "opOrEq",
	MM.Shl : "opShl",
	MM.ShlEq : "opShlEq",
	MM.Shr : "opShr",
	MM.ShrEq : "opShrEq",
	MM.Sub : "opSub",
	MM.SubEq : "opSubEq",
	MM.ToString : "opToString",
	MM.UShr : "opUShr",
	MM.UShrEq : "opUShrEq",
	MM.Xor : "opXor",
	MM.XorEq : "opXorEq",
];

public MDValue[] MetaStrings;

static this()
{
	MetaStrings = new MDValue[MetaNames.length];

	foreach(uint i, dchar[] name; MetaNames)
		MetaStrings[i].value = new MDString(name);
}

abstract class MDObject
{
	public uint length();
	
	// avoiding RTTI downcasts for speed
	public static enum Type
	{
		String,
		Userdata,
		Closure,
		Table,
		Array,
		Class,
		Instance,
		Delegate
	}

	public MDString asString() { return null; }
	public MDUserdata asUserdata() { return null; }
	public MDClosure asClosure() { return null; }
	public MDTable asTable() { return null; }
	public MDArray asArray() { return null; }
	public MDClass asClass() { return null; }
	public MDInstance asInstance() { return null; }
	public MDDelegate asDelegate() { return null; }
	public abstract Type type();
	
	public static int compare(MDObject o1, MDObject o2)
	{
		if(o1.type == o2.type)
			return o1.opCmp(o2);
		else
			throw new MDException("Attempting to compare unlike objects");
	}

	public static int equals(MDObject o1, MDObject o2)
	{
		if(o1.type == o2.type)
			return o1.opEquals(o2);
		else
			throw new MDException("Attempting to compare unlike objects");
	}
}

class MDString : MDObject
{
	//TODO: Hmmm.  package..
	package dchar[] mData;
	protected hash_t mHash;

	public this(dchar[] data)
	{
		mData = data.dup;
		mHash = typeid(typeof(mData)).getHash(&mData);
	}
	
	public this(wchar[] data)
	{
		mData = utf.toUTF32(data);
		mHash = typeid(typeof(mData)).getHash(&mData);
	}

	public this(char[] data)
	{
		mData = utf.toUTF32(data);
		mHash = typeid(typeof(mData)).getHash(&mData);
	}
	
	protected this()
	{

	}
	
	public override MDString asString()
	{
		return this;
	}

	public override Type type()
	{
		return Type.String;
	}

	public override uint length()
	{
		return mData.length;
	}
	
	public MDString opCat(MDString other)
	{
		// avoid double duplication ((this ~ other).dup)
		MDString ret = new MDString();
		ret.mData = this.mData ~ other.mData;
		ret.mHash = typeid(typeof(ret.mData)).getHash(&ret.mData);
		return ret;
	}

	public MDString opCat(dchar c)
	{
		MDString ret = new MDString();
		ret.mData = this.mData ~ c;
		ret.mHash = typeid(typeof(mData)).getHash(&ret.mData);
		return ret;
	}
	
	public MDString opCat_r(dchar c)
	{
		MDString ret = new MDString();
		ret.mData = c ~ this.mData;
		ret.mHash = typeid(typeof(mData)).getHash(&ret.mData);
		return ret;
	}

	public MDString opCatAssign(MDString other)
	{
		return opCat(other);
	}
	
	public MDString opCatAssign(dchar c)
	{
		return opCat(c);
	}

	public hash_t toHash()
	{
		return mHash;
	}
	
	public int opEquals(Object o)
	{
		MDString other = cast(MDString)o;
		assert(other, "MDString opEquals");
		
		return mData == other.mData;
	}
	
	public int opEquals(char[] v)
	{
		return mData == utf.toUTF32(v);
	}
	
	public int opEquals(wchar[] v)
	{
		return mData == utf.toUTF32(v);
	}
	
	public int opEquals(dchar[] v)
	{
		return mData == v;
	}

	public int opCmp(Object o)
	{
		MDString other = cast(MDString)o;
		assert(other, "MDString opCmp");
		
		return dcmp(mData, other.mData);
	}

	public int opCmp(char[] v)
	{
		return dcmp(mData, utf.toUTF32(v));
	}
	
	public int opCmp(wchar[] v)
	{
		return dcmp(mData, utf.toUTF32(v));
	}

	public int opCmp(dchar[] v)
	{
		return dcmp(mData, v);
	}

	public dchar opIndex(uint index)
	{
		debug if(index < 0 || index >= mData.length)
			throw new MDException("Invalid string character index: ", index);

		return mData[index];
	}

	public MDString opSlice(uint lo, uint hi)
	{
		debug if(lo > hi || lo < 0 || lo > mData.length || hi < 0 || hi > mData.length)
			throw new MDException("Invalid string slice indices [%s .. %s]", lo, hi);
			
			
		MDString ret = new MDString();
		ret.mData = mData[lo .. hi].dup;
		ret.mHash = typeid(typeof(ret.mData)).getHash(&ret.mData);

		return ret;
	}

	public char[] asUTF8()
	{
		return utf.toUTF8(mData);
	}
	
	public wchar[] asUTF16()
	{
		return utf.toUTF16(mData);
	}
	
	public dchar[] asUTF32()
	{
		return mData.dup;
	}

	public static MDString concat(MDString[] strings)
	{
		uint l = 0;
		
		foreach(MDString s; strings)
			l += s.length;
			
		dchar[] result = new dchar[l];
		
		uint i = 0;
		
		foreach(MDString s; strings)
		{
			result[i .. i + s.length] = s.mData[];
			i += s.length;
		}

		return new MDString(result);
	}
	
	// Returns null on failure, so that the VM can give an error at the appropriate location
	public static MDString concat(MDValue[] values, out uint badIndex)
	{
		uint l = 0;

		foreach(uint i, MDValue v; values)
		{
			if(v.isString())
				l += v.asString().length;
			else if(v.isChar())
				l += 1;
			else
			{
				badIndex = i;
				return null;
			}
		}
		
		dchar[] result = new dchar[l];
		
		uint i = 0;
		
		foreach(MDValue v; values)
		{
			if(v.isString())
			{
				MDString s = v.asString();
				result[i .. i + s.length] = s.mData[];
				i += s.length;
			}
			else
			{
				result[i] = v.asChar();
				i++;
			}
		}
		
		return new MDString(result);
	}
	
	public char[] toString()
	{
		return asUTF8();
	}
}

class MDUserdata : MDObject
{
	protected MDTable mMetatable;

	public override MDUserdata asUserdata()
	{
		return this;
	}
	
	public override Type type()
	{
		return Type.Userdata;
	}

	public override uint length()
	{
		throw new MDException("Cannot get the length of a userdatum");
	}
	
	public char[] toString()
	{
		return string.format("userdata 0x%0.8X", cast(void*)this);
	}
	
	public MDTable metatable(MDTable mt)
	{
		return mMetatable = mt;
	}
	
	public MDTable metatable()
	{
		return mMetatable;
	}
}

class MDClosure : MDObject
{
	protected bool mIsNative;
	protected MDTable mEnvironment;
	
	struct NativeClosure
	{
		int delegate(MDState) func;
		dchar[] name;
		MDValue[] upvals;
	}
	
	struct ScriptClosure
	{
		MDFuncDef func;
		MDUpval*[] upvals;
	}
	
	union
	{
		NativeClosure native;
		ScriptClosure script;
	}
	
	public this(MDState s, MDFuncDef def)
	{
		mIsNative = false;
		mEnvironment = s.getGlobals();
		script.func = def;
		script.upvals.length = def.mNumUpvals;
	}
	
	public this(MDState s, int delegate(MDState) func, dchar[] name, MDValue[] upvals = null)
	{
		mIsNative = true;
		mEnvironment = s.getGlobals();
		native.func = func;
		native.name = name;
		native.upvals = upvals.dup;
	}

	public override MDClosure asClosure()
	{
		return this;
	}
	
	public override Type type()
	{
		return Type.Closure;
	}

	public override uint length()
	{
		throw new MDException("Cannot get the length of a closure");
	}
	
	public char[] toString()
	{
		if(mIsNative)
			return string.format("native function %s", utf.toUTF8(native.name));
		else
			return string.format("script function %s(%s)", script.func.mGuessedName, script.func.mLocation.toString());
	}
	
	public bool isNative()
	{
		return mIsNative;
	}
	
	public MDTable environment()
	{
		return mEnvironment;
	}
}

class MDTable : MDObject
{
	protected MDValue[MDValue] mData;

	public this()
	{
		
	}
	
	public static MDTable create(...)
	{
		if(_arguments.length & 1)
			throw new MDException("Native table constructor requires an even number of arguments");
			
		MDTable ret = new MDTable();

		MDValue key;
		MDValue value;
		
		void getVal(uint arg, out MDValue v)
		{
			TypeInfo ti = _arguments[arg];
			TypeInfo_Class tic = cast(TypeInfo_Class)ti;

			if(tic is null)
			{
				if(ti == typeid(bool))             v.value = cast(bool)va_arg!(bool)(_argptr);
				else if(ti == typeid(byte))        v.value = cast(int)va_arg!(byte)(_argptr);
				else if(ti == typeid(ubyte))       v.value = cast(int)va_arg!(ubyte)(_argptr);
				else if(ti == typeid(short))       v.value = cast(int)va_arg!(ushort)(_argptr);
				else if(ti == typeid(ushort))      v.value = cast(int)va_arg!(ushort)(_argptr);
				else if(ti == typeid(int))         v.value = cast(int)va_arg!(int)(_argptr);
				else if(ti == typeid(uint))        v.value = cast(int)va_arg!(uint)(_argptr);
				else if(ti == typeid(long))        v.value = cast(int)va_arg!(long)(_argptr);
				else if(ti == typeid(ulong))       v.value = cast(int)va_arg!(ulong)(_argptr);
				else if(ti == typeid(float))       v.value = cast(float)va_arg!(float)(_argptr);
				else if(ti == typeid(double))      v.value = cast(float)va_arg!(double)(_argptr);
				else if(ti == typeid(real))        v.value = cast(float)va_arg!(real)(_argptr);
				else if(ti == typeid(char[]))      v.value = new MDString(va_arg!(char[])(_argptr));
				else if(ti == typeid(wchar[]))     v.value = new MDString(va_arg!(wchar[])(_argptr));
				else if(ti == typeid(dchar[]))     v.value = new MDString(va_arg!(dchar[])(_argptr));
				else throw new MDException("Native table constructor: invalid argument %d of type ", arg, ti);
			}
			else
			{
				ClassInfo ci = tic.info;
				
				for( ; ci !is null; ci = ci.base)
				{
					if(ci == MDObject.classinfo)
					{
						v.value = cast(MDObject)va_arg!(MDObject)(_argptr);
						break;
					}
				}

				if(ci is null)
					throw new MDException("Native table constructor: invalid argument %d of type ", arg, ti);
			}
		}

		for(int i = 0; i < _arguments.length; i += 2)
		{
			getVal(i, key);
			getVal(i + 1, value);
			
			ret[&key] = &value;
		}
		
		return ret;
	}

	public override MDTable asTable()
	{
		return this;
	}
	
	public override Type type()
	{
		return Type.Table;
	}
	
	public override uint length()
	{
		return mData.length;
	}
	
	public MDTable dup()
	{
		MDTable n = new MDTable();
		
		foreach(k, v; mData)
			n.mData[k] = v;
			
		return n;
	}
	
	public MDArray keys()
	{
		return new MDArray(mData.keys);
	}
	
	public MDArray values()
	{
		return new MDArray(mData.values);
	}
	
	public void remove(MDValue* index)
	{
		MDValue* ptr = (*index in mData);

		if(ptr is null)
			return;
			
		mData.remove(*index);
	}
	
	public MDValue* opIndex(MDValue* index)
	{
		MDValue* ptr = (*index in mData);

		if(ptr is null)
			return null;

		return ptr;
	}
	
	public MDValue* opIndex(dchar[] index)
	{
		MDValue key;
		key.value = new MDString(index);
		
		return opIndex(&key);
	}

	public MDValue* opIndexAssign(MDValue* value, MDValue* index)
	{
		mData[*index] = *value;
		return value;
	}

	public MDValue* opIndexAssign(MDValue* value, dchar[] index)
	{
		MDValue idx;
		idx.value = new MDString(index);
		return opIndexAssign(value, &idx);
	}
	
	public MDValue* opIndexAssign(MDObject value, MDValue* index)
	{
		MDValue val;
		val.value = value;
		return opIndexAssign(&val, index);
	}
	
	public MDValue* opIndexAssign(MDObject value, dchar[] index)
	{
		MDValue idx;
		idx.value = new MDString(index);

		MDValue val;
		val.value = value;
		
		return opIndexAssign(&val, &idx);
	}
	
	public int opApply(int delegate(inout MDValue* key, inout MDValue* value) dg)
	{
		int result = 0;
		
		foreach(MDValue key, MDValue value; mData)
		{
			MDValue* k = &key;
			MDValue* v = &value;

			result = dg(k, v);

			if(result)
				break;
		}

		return result;
	}

	public char[] toString()
	{
		return string.format("table 0x%0.8X", cast(void*)this);
	}
}

class MDArray : MDObject
{
	protected MDValue[] mData;
	
	public this(uint size)
	{
		mData = new MDValue[size];
	}
	
	package this(MDValue[] data)
	{
		mData = data;
	}

	public static MDArray create(...)
	{
		MDArray ret = new MDArray(_arguments.length);

		MDValue value;

		void getVal(uint arg)
		{
			TypeInfo ti = _arguments[arg];
			TypeInfo_Class tic = cast(TypeInfo_Class)ti;

			if(tic is null)
			{
				if(ti == typeid(bool))             value.value = cast(bool)va_arg!(bool)(_argptr);
				else if(ti == typeid(byte))        value.value = cast(int)va_arg!(byte)(_argptr);
				else if(ti == typeid(ubyte))       value.value = cast(int)va_arg!(ubyte)(_argptr);
				else if(ti == typeid(short))       value.value = cast(int)va_arg!(ushort)(_argptr);
				else if(ti == typeid(ushort))      value.value = cast(int)va_arg!(ushort)(_argptr);
				else if(ti == typeid(int))         value.value = cast(int)va_arg!(int)(_argptr);
				else if(ti == typeid(uint))        value.value = cast(int)va_arg!(uint)(_argptr);
				else if(ti == typeid(long))        value.value = cast(int)va_arg!(long)(_argptr);
				else if(ti == typeid(ulong))       value.value = cast(int)va_arg!(ulong)(_argptr);
				else if(ti == typeid(float))       value.value = cast(float)va_arg!(float)(_argptr);
				else if(ti == typeid(double))      value.value = cast(float)va_arg!(double)(_argptr);
				else if(ti == typeid(real))        value.value = cast(float)va_arg!(real)(_argptr);
				else if(ti == typeid(char[]))      value.value = new MDString(va_arg!(char[])(_argptr));
				else if(ti == typeid(wchar[]))     value.value = new MDString(va_arg!(wchar[])(_argptr));
				else if(ti == typeid(dchar[]))     value.value = new MDString(va_arg!(dchar[])(_argptr));
				else throw new MDException("Native array constructor: invalid argument %d of type ", arg, ti);
			}
			else
			{
				ClassInfo ci = tic.info;
				
				for( ; ci !is null; ci = ci.base)
				{
					if(ci == MDObject.classinfo)
					{
						value.value = cast(MDObject)va_arg!(MDObject)(_argptr);
						break;
					}
				}

				if(ci is null)
					throw new MDException("Native table constructor: invalid argument %d of type ", arg, ti);
			}
		}

		for(int i = 0; i < _arguments.length; i++)
		{
			getVal(i);
			
			ret[i] = &value;
		}
		
		return ret;
	}

	public override MDArray asArray()
	{
		return this;
	}
	
	public override Type type()
	{
		return Type.Array;
	}

	public override uint length()
	{
		return mData.length;
	}

	public uint length(int newLength)
	{
		mData.length = newLength;
		return newLength;
	}
	
	public void sort()
	{
		mData.sort;
	}
	
	public void reverse()
	{
		mData.reverse;
	}
	
	public MDArray dup()
	{
		MDArray n = new MDArray(0);
		n.mData = mData.dup;
		return n;
	}

	public int opApply(int delegate(inout uint index, inout MDValue value) dg)
	{
		int result = 0;

		for(uint i = 0; i < mData.length; i++)
		{

			result = dg(i, mData[i]);

			if(result)
				break;
		}
		
		return result;
	}
	
	public MDArray opCat(MDArray other)
	{
		MDArray n = new MDArray(mData.length + other.mData.length);
		n.mData = mData ~ other.mData;
		return n;
	}
	
	public MDArray opCat(MDValue* elem)
	{
		MDArray n = new MDArray(mData.length + 1);
		n.mData = mData ~ *elem;
		return n;
	}

	public MDArray opCatAssign(MDArray other)
	{
		mData ~= other.mData;
		return this;
	}
	
	public MDArray opCatAssign(MDValue* elem)
	{
		mData ~= *elem;
		return this;
	}
	
	public MDValue* opIndex(int index)
	{
		if(index < 0 || index >= mData.length)
			return null;
			
		return &mData[index];
	}
	
	public MDValue* opIndexAssign(MDValue* value, int index)
	{
		if(index < 0 || index >= mData.length)
			return null;
			
		mData[index] = *value;

		return value;
	}
	
	public MDObject opIndexAssign(MDObject value, int index)
	{
		if(index < 0 || index >= mData.length)
			return null;

		mData[index].value = value;

		return value;
	}
	
	public MDArray opSlice(uint lo, uint hi)
	{
		return new MDArray(mData[lo .. hi]);
	}

	package void setBlock(uint block, MDValue[] data)
	{
		uint start = block * Instruction.arraySetFields;
		uint end = start + data.length;
		
		// Since Op.SetArray can use a variadic number of values, the number
		// of elements actually added to the array in the array constructor
		// may exceed the size with which the array was created.  So it should be
		// resized.
		if(end >= mData.length)
			mData.length = end;
			
		mData[start .. end] = data[];
	}

	public char[] toString()
	{
		return string.format("array 0x%0.8X", cast(void*)this);
	}
	
	public static MDArray concat(MDValue[] values)
	{
		uint l = 0;

		foreach(uint i, MDValue v; values)
		{
			if(v.isArray())
				l += v.asArray().length;
			else
				l += 1;
		}
		
		MDArray result = new MDArray(l);
		
		uint i = 0;
		
		foreach(MDValue v; values)
		{
			if(v.isArray())
			{
				MDArray a = v.asArray();
				result.mData[i .. i + a.length] = a.mData[];
				i += a.length;
			}
			else
			{
				result[i] = &v;
				i++;
			}
		}

		return result;
	}
}

class MDClass : MDObject
{
	protected dchar[] mGuessedName;
	protected MDClass mBaseClass;
	protected MDValue[MDString] mFields;
	protected MDValue[MDString] mMethods;

	protected static MDString CtorString;
	protected static MDString SuperString;
	
	static this()
	{
		CtorString = new MDString("constructor"d);
		SuperString = new MDString("super"d);
	}

	package this(MDState s, dchar[] guessedName, MDClass baseClass)
	{
		mGuessedName = guessedName.dup;
		mBaseClass = baseClass;

		if(baseClass !is null)
		{
			foreach(key, value; mBaseClass.mMethods)
				mMethods[key] = value;

			foreach(key, value; mBaseClass.mFields)
				mFields[key] = value;
				
			MDValue* superCtor = mBaseClass[CtorString];
			
			if(superCtor !is null)
				mMethods[SuperString] = *superCtor;
		}
	}

	public override MDClass asClass()
	{
		return this;
	}
	
	public override Type type()
	{
		return Type.Class;
	}

	public override uint length()
	{
		throw new MDException("Cannot get the length of a class");
	}
	
	public MDInstance newInstance()
	{
		MDInstance n = new MDInstance();
		n.mClass = this;
		
		foreach(k, v; mFields)
			n.mFields[k] = v;

		n.mMethods = mMethods;

		return n;
	}

	public MDValue* opIndex(MDString index)
	{
		//TODO: Statics?
		/*MDValue* ptr = mStaticMembers[index];

		if(ptr !is null)
			return ptr;*/

		MDValue* ptr = (index in mMethods);

		if(ptr !is null)
			return ptr;

		ptr = (index in mFields);

		if(ptr !is null)
			return ptr;
			
		if(mBaseClass !is null)
			return mBaseClass[index];
		else
			return null;
	}
	
	public MDValue* opIndex(dchar[] index)
	{
		return opIndex(new MDString(index));
	}

	public MDValue* opIndexAssign(MDValue* value, MDString index)
	{
		if(value.isFunction())
			mMethods[index] = *value;
		else
			mFields[index] = *value;
			
		return value;
	}

	public MDValue* opIndexAssign(MDObject value, MDString index)
	{
		MDValue val;
		val.value = value;
		return opIndexAssign(&val, index);
	}

	public MDValue* opIndexAssign(MDValue* value, dchar[] index)
	{
		return opIndexAssign(value, new MDString(index));
	}
	
	public MDValue* opIndexAssign(MDObject value, dchar[] index)
	{
		MDValue val;
		val.value = value;
		
		return opIndexAssign(&val, new MDString(index));
	}
	
	public dchar[] getName()
	{
		return mGuessedName.dup;	
	}

	public char[] toString()
	{
		return string.format("class %s", mGuessedName);
	}
}

class MDInstance : MDObject
{
	protected MDClass mClass;
	protected MDValue[MDString] mFields;
	protected MDValue[MDString] mMethods;

	private this()
	{
		
	}

	public override MDInstance asInstance()
	{
		return this;
	}

	public override Type type()
	{
		return Type.Instance;
	}

	public override uint length()
	{
		throw new MDException("Cannot get the length of a class instance");
	}
	
	public MDValue* opIndex(MDString index)
	{
		MDValue* ptr = (index in mMethods);
		
		if(ptr !is null)
			return ptr;

		ptr = (index in mFields);
		
		if(ptr !is null)
			return ptr;
			
		return null;
	}
	
	public MDValue* opIndex(dchar[] index)
	{
		return opIndex(new MDString(index));
	}
	
	public MDValue* opIndexAssign(MDValue* value, MDString index)
	{
		if(value.isFunction())
			throw new MDException("Attempting to change a method of a class instance!");
		else
			mFields[index] = *value;
			
		return value;
	}

	public MDValue* opIndexAssign(MDObject value, MDString index)
	{
		MDValue val;
		val.value = value;
		return opIndexAssign(&val, index);
	}

	public MDValue* opIndexAssign(MDValue* value, dchar[] index)
	{
		return opIndexAssign(value, new MDString(index));
	}
	
	public MDValue* opIndexAssign(MDObject value, dchar[] index)
	{
		MDValue val;
		val.value = value;
		
		return opIndexAssign(&val, new MDString(index));
	}

	public char[] toString()
	{
		return string.format("instance of %s", mClass.toString());
	}
	
	public bool castToClass(MDClass cls)
	{
		assert(cls !is null, "MDInstance.castToClass() class is null");

		for(MDClass c = mClass; c !is null; c = c.mBaseClass)
		{
			if(c is cls)
				return true;
		}

		return false;
	}

	package MDClass getClass()
	{
		return mClass;
	}
	
	package MDValue* getCtor()
	{
		return this[MDClass.CtorString];
	}
}

class MDDelegate : MDObject
{
	protected MDValue[] mContext;
	protected MDClosure mClosure;

	public this(MDState s, MDClosure closure, MDValue[] context)
	{
		mClosure = closure;
		mContext = context;
	}

	public override MDDelegate asDelegate()
	{
		return this;
	}

	public override Type type()
	{
		return Type.Delegate;
	}

	public override uint length()
	{
		throw new MDException("Cannot get the length of a delegate");
	}

	public char[] toString()
	{
		char[] ret = string.format("delegate %s(", mClosure.toString());

		foreach(i, v; mContext)
		{
			if(i == mContext.length - 1)
				ret = string.format("%s%s", ret, v.toString());
			else
				ret = string.format("%s%s, ", ret, v.toString());
		}

		return ret ~ ")";
	}

	package MDValue[] getContext()
	{
		return mContext;
	}
	
	package MDClosure getClosure()
	{
		return mClosure;
	}
}

struct MDValue
{
	public static enum Type
	{
		// Non-object types
		Null,
		Bool,
		Int,
		Float,
		Char,

		// Object types
		String,
		Table,
		Array,
		Function,
		Userdata,
		Class,
		Instance,
		Delegate
	}
	
	//public static MDValue nullValue = { mType : Type.Null };
	
	// No one should ever change nullValue!
	//invariant
	//{
	//	assert(nullValue.mType == Type.Null, "Someone changed nullValue!");
	//}

	public Type mType = Type.Null;

	union
	{
		// Non-object types
		private bool mBool;
		private int mInt;
		private float mFloat;
		private dchar mChar;
		
		// Object types
		private MDObject mObj;
	}

	public int opEquals(MDValue* other)
	{
		if(this.mType != other.mType)
			throw new MDException("Attempting to compare unlike objects");

		switch(this.mType)
		{
			case Type.Null:
				return 1;
				
			case Type.Bool:
				return this.mBool == other.mBool;

			case Type.Int:
				return this.mInt == other.mInt;

			case Type.Float:
				return this.mFloat == other.mFloat;
				
			case Type.Char:
				return this.mChar == other.mChar;

			default:
				return MDObject.equals(this.mObj, other.mObj);
		}
	}
	
	public bool rawEquals(MDValue* other)
	{
		if(this.mType != other.mType)
			return false;
			
		switch(this.mType)
		{
			case Type.Null:
				return true;
				
			case Type.Bool:
				return this.mBool == other.mBool;

			case Type.Int:
				return this.mInt == other.mInt;

			case Type.Float:
				return this.mFloat == other.mFloat;
				
			case Type.Char:
				return this.mChar == other.mChar;

			default:
				return (this.mObj is other.mObj);
		}
	}

	public int opCmp(MDValue* other)
	{
		if(this.mType != other.mType)
			throw new MDException("Attempting to compare unlike objects (%s to %s)", typeString(), other.typeString());

		switch(this.mType)
		{
			case Type.Null:
				return 0;

			case Type.Bool:
				return (cast(int)this.mBool - cast(int)other.mBool);

			case Type.Int:
				return this.mInt - other.mInt;

			case Type.Float:
				if(this.mFloat < other.mFloat)
					return -1;
				else if(this.mFloat > other.mFloat)
					return 1;
				else
					return 0;

			case Type.Char:
				return this.mChar - other.mChar;

			default:
				if(this.mObj is other.mObj)
					return 0;

				return MDObject.compare(this.mObj, other.mObj);
		}

		return -1;
	}
	
	public hash_t toHash()
	{
		switch(mType)
		{
			case Type.Null:
				return 0;

			case Type.Bool:
				return typeid(typeof(mBool)).getHash(&mBool);

			case Type.Int:
				return typeid(typeof(mInt)).getHash(&mInt);
				
			case Type.Float:
				return typeid(typeof(mFloat)).getHash(&mFloat);
				
			case Type.Char:
				return typeid(typeof(mChar)).getHash(&mChar);

			default:
				return mObj.toHash();
		}
	}
	
	public uint length()
	{
		switch(mType)
		{
			case Type.Null:
			case Type.Bool:
			case Type.Int:
			case Type.Float:
			case Type.Char:
				throw new MDException("Attempting to get length of %s value", typeString());

			default:
				return mObj.length();
		}
	}
	
	public Type type()
	{
		return mType;
	}
	
	public static dchar[] typeString(Type type)
	{
		switch(type)
		{
			case Type.Null:     return "null"d;
			case Type.Bool:     return "bool"d;
			case Type.Int:      return "int"d;
			case Type.Float:    return "float"d;
			case Type.Char:     return "char"d;
			case Type.String:   return "string"d;
			case Type.Table:    return "table"d;
			case Type.Array:    return "array"d;
			case Type.Function: return "function"d;
			case Type.Userdata: return "userdata"d;
			case Type.Class:    return "class"d;
			case Type.Instance: return "instance"d;
			case Type.Delegate: return "delegate"d;
		}
	}

	public dchar[] typeString()
	{
		return typeString(mType);
	}

	public bool isNull()
	{
		return (mType == Type.Null);
	}
	
	public bool isBool()
	{
		return (mType == Type.Bool);
	}
	
	public bool isNum()
	{
		return isInt() || isFloat();
	}

	public bool isInt()
	{
		return (mType == Type.Int);
	}
	
	public bool isFloat()
	{
		return (mType == Type.Float);
	}
	
	public bool isChar()
	{
		return (mType == Type.Char);
	}

	public bool isString()
	{
		return (mType == Type.String);
	}
	
	public bool isTable()
	{
		return (mType == Type.Table);
	}
	
	public bool isArray()
	{
		return (mType == Type.Array);
	}
	
	public bool isFunction()
	{
		return (mType == Type.Function);
	}
	
	public bool isUserdata()
	{
		return (mType == Type.Userdata);
	}
	
	public bool isClass()
	{
		return (mType == Type.Class);
	}

	public bool isInstance()
	{
		return (mType == Type.Instance);
	}
	
	public bool isDelegate()
	{
		return (mType == Type.Delegate);
	}

	public bool asBool()
	{
		assert(mType == Type.Bool, "MDValue asBool");
		return mBool;
	}

	public int asInt()
	{
		if(mType == Type.Float)
			return cast(int)mFloat;
		else if(mType == Type.Int)
			return mInt;
		else
			assert(false, "MDValue asInt");
	}

	public float asFloat()
	{
		if(mType == Type.Float)
			return mFloat;
		else if(mType == Type.Int)
			return cast(float)mInt;
		else
			assert(false, "MDValue asFloat");
	}
	
	public dchar asChar()
	{
		if(mType == Type.Char)
			return mChar;
		else
			assert(false, "MDValue asChar");
	}

	public MDObject asObj()
	{
		assert(cast(uint)mType >= cast(uint)Type.String, "MDValue asObj");
		return mObj;
	}

	public MDString asString()
	{
		assert(mType == Type.String, "MDValue asString");
		return mObj.asString();
	}
	
	public MDUserdata asUserdata()
	{
		assert(mType == Type.Userdata, "MDValue asUserdata");
		return mObj.asUserdata();
	}

	public MDClosure asFunction()
	{
		assert(mType == Type.Function, "MDValue asFunction");
		return mObj.asClosure();
	}

	public MDTable asTable()
	{
		assert(mType == Type.Table, "MDValue asTable");
		return mObj.asTable();
	}
	
	public MDArray asArray()
	{
		assert(mType == Type.Array, "MDValue asArray");
		return mObj.asArray();
	}
	
	public MDClass asClass()
	{
		assert(mType == Type.Class, "MDValue asClass");
		return mObj.asClass();
	}

	public MDInstance asInstance()
	{
		assert(mType == Type.Instance, "MDValue asInstance");
		return mObj.asInstance();
	}

	public MDDelegate asDelegate()
	{
		assert(mType == Type.Delegate, "MDValue asDelegate");
		return mObj.asDelegate();
	}

	public bool isFalse()
	{
		return (mType == Type.Null) || (mType == Type.Bool && mBool == false) ||
			(mType == Type.Int && mInt == 0) || (mType == Type.Float && mFloat == 0.0);
	}
	
	public void setNull()
	{
		mType = Type.Null;
		mInt = 0;
	}

	public void value(bool b)
	{
		mType = Type.Bool;
		mBool = b;
	}

	public void value(int n)
	{
		mType = Type.Int;
		mInt = n;
	}

	public void value(float n)
	{
		mType = Type.Float;
		mFloat = n;
	}
	
	public void value(char n)
	{
		mType = Type.Char;
		mChar = n;
	}
	
	public void value(wchar n)
	{
		mType = Type.Char;
		mChar = n;
	}

	public void value(dchar n)
	{
		mType = Type.Char;
		mChar = n;
	}
	
	public void value(char[] s)
	{
		mType = Type.String;
		mObj = new MDString(s);
	}
	
	public void value(wchar[] s)
	{
		mType = Type.String;
		mObj = new MDString(s);
	}
	
	public void value(dchar[] s)
	{
		mType = Type.String;
		mObj = new MDString(s);
	}

	public void value(MDObject o)
	{
		mObj = o;
		
		switch(o.type())
		{
			case MDObject.Type.String: mType = Type.String; break;
			case MDObject.Type.Userdata: mType = Type.Userdata; break;
			case MDObject.Type.Closure: mType = Type.Function; break;
			case MDObject.Type.Table: mType = Type.Table; break;
			case MDObject.Type.Array: mType = Type.Array; break;
			case MDObject.Type.Class: mType = Type.Class; break;
			case MDObject.Type.Instance: mType = Type.Instance; break;
			case MDObject.Type.Delegate: mType = Type.Delegate; break;
			default: assert(false, "invalid MDValue.value(MDObject) switch");
		}
	}

	public void value(MDValue v)
	{
		value(&v);
	}
	
	public void value(MDValue* v)
	{
		mType = v.mType;
		
		switch(mType)
		{
			case Type.Null:
				mInt = 0;
				break;

			case Type.Bool:
				mBool = v.mBool;
				break;

			case Type.Int:
				mInt = v.mInt;
				break;

			case Type.Float:
				mFloat = v.mFloat;
				break;
				
			case Type.Char:
				mChar = v.mChar;
				break;

			default:
				mObj = v.mObj;
				break;
		}
	}

	public char[] toString()
	{
		switch(mType)
		{
			case Type.Null:
				return "null";

			case Type.Bool:
				return string.toString(mBool);
				
			case Type.Int:
				return string.toString(mInt);
				
			case Type.Float:
				return string.toString(mFloat);
				
			case Type.Char:
				char[] ret;
				utf.encode(ret, mChar);
				return ret;
				
			default:
				return mObj.toString();
		}
	}
}

struct Location
{
	public int line = 1;
	public int column = 1;
	public dchar[] fileName;

	public static Location opCall(dchar[] fileName, int line = 1, int column = 1)
	{
		Location l;
		l.fileName = fileName;
		l.line = line;
		l.column = column;
		return l;
	}

	public char[] toString()
	{
		if(line == -1 && column == -1)
			return string.format("%s(native)", fileName);
		else
			return string.format("%s(%d:%d)", fileName, line, column);
	}
}

struct MDUpval
{
	// When open (parent scope is still on the stack), this points to a stack slot
	// which holds the value.  When the parent scope exits, the value is copied from
	// the stack into the closedValue member, and this points to closedMember.  
	// This means data should only ever be accessed through this member.
	MDValue* value;

	MDValue closedValue;

	// For the open upvalue doubly-linked list.
	MDUpval* next;
	MDUpval* prev;
}

class MDFuncDef
{
	package bool mIsVararg;
	package Location mLocation;
	package dchar[] mGuessedName;
	package MDFuncDef[] mInnerFuncs;
	package MDValue[] mConstants;
	package uint mNumParams;
	package uint mNumUpvals;
	package uint mStackSize;
	package Instruction[] mCode;
	package uint[] mLineInfo;
	package dchar[][] mUpvalNames;

	struct LocVarDesc
	{
		dchar[] name;
		Location location;
		uint reg;
	}
	
	package LocVarDesc[] mLocVarDescs;
	
	struct SwitchTable
	{
		bool isString;

		union
		{
			int[int] intOffsets;
			int[dchar[]] stringOffsets;
		}

		int defaultOffset = -1;
	}

	package SwitchTable[] mSwitchTables;
}