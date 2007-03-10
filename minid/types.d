/******************************************************************************
License:
Copyright (c) 2007 Jarrett Billingsley

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

module minid.types;

import format = std.format;
import std.c.string;
import std.stdarg;
import std.stdio;
import std.stream;
import std.system;
import string = std.string;
import utf = std.utf;

import minid.opcodes;
import minid.utils;

// debug = STACKINDEX;
// debug = CALLEPILOGUE;

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

	public this(Location loc, MDValue* val)
	{
		location = loc;
		super(val);
	}

	public this(Location loc, ...)
	{
		this(loc, _arguments, _argptr);
	}
	
	public this(Location loc, TypeInfo[] arguments, va_list argptr)
	{
		location = loc;
		super(vformat(arguments, argptr));
	}

	public char[] toString()
	{
		return string.format(location.toString(), ": ", msg);
	}
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
	Slice,
	SliceAssign,
	Cat,
	CatEq,
	Call,
	In,

	// Debating on whether or not I want to keep these...
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	Neg,
	And,
	Or,
	Xor,
	Shl,
	Shr,
	UShr,
	Com,
	AddEq,
	SubEq,
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
	MM.Add :         "opAdd",
	MM.AddEq :       "opAddAssign",
	MM.And :         "opAnd",
	MM.AndEq :       "opAndAssign",
	MM.Apply :       "opApply",
	MM.Call :        "opCall",
	MM.Cat :         "opCat",
	MM.CatEq :       "opCatAssign",
	MM.Cmp :         "opCmp",
	MM.Com :         "opCom",
	MM.Div :         "opDiv",
	MM.DivEq :       "opDivAssign",
	MM.In :          "opIn",
	MM.Index :       "opIndex",
	MM.IndexAssign : "opIndexAssign",
	MM.Length :      "opLength",
	MM.Mod :         "opMod",
	MM.ModEq :       "opModAssign",
	MM.Mul :         "opMul",
	MM.MulEq :       "opMulAssign",
	MM.Neg :         "opNeg",
	MM.Or :          "opOr",
	MM.OrEq :        "opOrAssign",
	MM.Shl :         "opShl",
	MM.ShlEq :       "opShlAssign",
	MM.Shr :         "opShr",
	MM.ShrEq :       "opShrAssign",
	MM.Slice :       "opSlice",
	MM.SliceAssign : "opSliceAssign",
	MM.Sub :         "opSub",
	MM.SubEq :       "opSubAssign",
	MM.ToString :    "toString",
	MM.UShr :        "opUShr",
	MM.UShrEq :      "opUShrAssign",
	MM.Xor :         "opXor",
	MM.XorEq :       "opXorAssign",
];

public MDString[] MetaStrings;

static this()
{
	MetaStrings = new MDString[MetaNames.length];

	foreach(uint i, dchar[] name; MetaNames)
		MetaStrings[i] = new MDString(name);
}

package void putInValue(T)(out MDValue dest, T src)
{
	static if(isCharType!(T))
	{
		dest.value = cast(dchar)src;
	}
	else static if(isStringType!(T) || isFloatType!(T) || is(T == bool) || is(T : MDObject))
	{
		dest.value = src;
	}
	else static if(isIntType!(T))
	{
		dest.value = cast(int)src;
	}
	else static if(is(T : MDValue))
	{
		dest.value = src;
	}
	else static if(is(T : MDValue*))
	{
		dest.value = *src;
	}
	else static if(is(T : void*))
	{
		assert(src is null, "putInValue() - can only put 'null' into MDValues");
		dest.setNull();	
	}
	else
	{
		// I do this because static assert won't show the template instantiation "call stack."
		pragma(msg, "putInValue() - Invalid argument type ");
		ARGUMENT_ERROR(T);
	}
}

struct MDValue
{
	public enum Type
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
		Delegate,
		Namespace
	}

	public static MDValue nullValue = { mType : Type.Null, mInt : 0 };

	invariant
	{
		assert(nullValue.mType == Type.Null, "nullValue is not null.  OH NOES");
	}

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
	
	public static MDValue opCall(T)(T value)
	{
		MDValue ret;
		putInValue(ret, value);
		return ret;
	}

	public int opEquals(MDValue* other)
	{
		if(this.mType != other.mType)
			throw new MDException("Attempting to compare unlike objects (%s to %s)", typeString(), other.typeString());

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
		if(!(isNum() && other.isNum()) && this.mType != other.mType)
			throw new MDException("Attempting to compare unlike objects (%s to %s)", typeString(), other.typeString());

		switch(this.mType)
		{
			case Type.Null:
				return 0;

			case Type.Bool:
				return (cast(int)this.mBool - cast(int)other.mBool);

			case Type.Int:
				if(other.mType == Type.Float)
				{
					float val = mInt;

					if(val < other.mFloat)
						return -1;
					else if(val > other.mFloat)
						return 1;
					else
						return 0;
				}
				else
					return this.mInt - other.mInt;

			case Type.Float:
				if(other.mType == Type.Int)
				{
					float val = other.mInt;
					
					if(this.mFloat < val)
						return -1;
					else if(this.mFloat > val)
						return 1;
					else
						return 0;
				}
				else
				{
					if(this.mFloat < other.mFloat)
						return -1;
					else if(this.mFloat > other.mFloat)
						return 1;
					else
						return 0;
				}

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
			case Type.Null:      return "null"d;
			case Type.Bool:      return "bool"d;
			case Type.Int:       return "int"d;
			case Type.Float:     return "float"d;
			case Type.Char:      return "char"d;
			case Type.String:    return "string"d;
			case Type.Table:     return "table"d;
			case Type.Array:     return "array"d;
			case Type.Function:  return "function"d;
			case Type.Userdata:  return "userdata"d;
			case Type.Class:     return "class"d;
			case Type.Instance:  return "instance"d;
			case Type.Delegate:  return "delegate"d;
			case Type.Namespace: return "namespace"d;
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
	
	public bool isNamespace()
	{
		return (mType == Type.Namespace);
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
	
	public MDNamespace asNamespace()
	{
		assert(mType == Type.Namespace, "MDValue asNamespace");
		return mObj.asNamespace();
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
		mType = o.mType;
	}

	public void value(inout MDValue v)
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
	
	package void serialize(Stream s)
	{
		Serialize(s, mType);

		switch(mType)
		{
			case Type.Null:
				break;
				
			case Type.Bool:
				Serialize(s, mBool);
				break;

			case Type.Int:
				Serialize(s, mInt);
				break;
				
			case Type.Float:
				Serialize(s, mFloat);
				break;

			case Type.Char:
				Serialize(s, mChar);
				break;

			case Type.String:
				Serialize(s, mObj.asString.mData);
				break;
				
			default:
				assert(false, "MDValue.serialize()");
		}
	}
	
	package static MDValue deserialize(Stream s)
	{
		MDValue ret;

		Deserialize(s, ret.mType);

		switch(ret.mType)
		{
			case Type.Null:
				break;
				
			case Type.Bool:
				Deserialize(s, ret.mBool);
				break;
				
			case Type.Int:
				Deserialize(s, ret.mInt);
				break;
				
			case Type.Float:
				Deserialize(s, ret.mFloat);
				break;
				
			case Type.Char:
				Deserialize(s, ret.mChar);
				break;

			case Type.String:
				dchar[] data;
				Deserialize(s, data);
				ret.mObj = new MDString(data);
				break;
				
			default:
				assert(false, "MDValue.deserialize()");
		}
		
		return ret;
	}
}

abstract class MDObject
{
	public uint length();

	// avoiding RTTI downcasts for speed
	public MDString asString() { return null; }
	public MDUserdata asUserdata() { return null; }
	public MDClosure asClosure() { return null; }
	public MDTable asTable() { return null; }
	public MDArray asArray() { return null; }
	public MDClass asClass() { return null; }
	public MDInstance asInstance() { return null; }
	public MDDelegate asDelegate() { return null; }
	public MDNamespace asNamespace() { return null; }
	public MDValue.Type mType;
	
	public int opCmp(Object o)
	{
		throw new MDException("No opCmp defined for type '%s'", MDValue.typeString(mType));
	}

	public static int compare(MDObject o1, MDObject o2)
	{
		if(o1.mType == o2.mType)
			return o1.opCmp(o2);
		else
			throw new MDException("Attempting to compare unlike objects");
	}

	public static int equals(MDObject o1, MDObject o2)
	{
		if(o1.mType == o2.mType)
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
		mType = MDValue.Type.String;
	}
	
	public this(wchar[] data)
	{
		mData = utf.toUTF32(data);
		mHash = typeid(typeof(mData)).getHash(&mData);
		mType = MDValue.Type.String;
	}

	public this(char[] data)
	{
		mData = utf.toUTF32(data);
		mHash = typeid(typeof(mData)).getHash(&mData);
		mType = MDValue.Type.String;
	}
	
	package static MDString newTemp(dchar[] data)
	{
		MDString ret = new MDString();
		ret.mData = data;
		ret.mHash = typeid(typeof(data)).getHash(&data);
		return ret;
	}

	protected this()
	{
		mType = MDValue.Type.String;
	}
	
	public override MDString asString()
	{
		return this;
	}

	public override uint length()
	{
		return mData.length;
	}

	public int opIn_r(dchar c)
	{
		foreach(i, ch; mData)
			if(c == ch)
				return i;
				
		return -1;
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
		ret.mHash = typeid(typeof(ret.mData)).getHash(&ret.mData);
		return ret;
	}
	
	public MDString opCat_r(dchar c)
	{
		MDString ret = new MDString();
		ret.mData = c ~ this.mData;
		ret.mHash = typeid(typeof(ret.mData)).getHash(&ret.mData);
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
	protected MDNamespace mMetatable;
	
	public this()
	{
		mType = MDValue.Type.Userdata;
	}

	public override MDUserdata asUserdata()
	{
		return this;
	}
	
	public override uint length()
	{
		throw new MDException("Cannot get the length of a userdatum");
	}
	
	public char[] toString()
	{
		return string.format("userdata 0x%0.8X", cast(void*)this);
	}
	
	public MDNamespace metatable(MDNamespace mt)
	{
		return mMetatable = mt;
	}
	
	public MDNamespace metatable()
	{
		return mMetatable;
	}
}

class MDClosure : MDObject
{
	protected bool mIsNative;
	protected MDNamespace mEnvironment;

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

	public this(MDNamespace environment, MDFuncDef def)
	{
		mIsNative = false;
		mEnvironment = environment;
		script.func = def;
		script.upvals.length = def.mNumUpvals;
		mType = MDValue.Type.Function;
	}
	
	public this(MDNamespace environment, int delegate(MDState) func, dchar[] name, MDValue[] upvals = null)
	{
		mIsNative = true;
		mEnvironment = environment;
		native.func = func;
		native.name = name;
		native.upvals = upvals.dup;
		mType = MDValue.Type.Function;
	}

	public override MDClosure asClosure()
	{
		return this;
	}
	
	public override uint length()
	{
		throw new MDException("Cannot get the length of a closure");
	}

	public char[] toString()
	{
		if(mIsNative)
			return string.format("native function %s", native.name);
		else
			return string.format("script function %s(%s)", script.func.mGuessedName, script.func.mLocation.toString());
	}

	public bool isNative()
	{
		return mIsNative;
	}
	
	public MDNamespace environment()
	{
		return mEnvironment;
	}
}

class MDTable : MDObject
{
	protected MDValue[MDValue] mData;

	public this()
	{
		mType = MDValue.Type.Table;
	}

	public static MDTable create(T...)(T args)
	{
		static if(args.length & 1)
		{
			pragma(msg, "Native table constructor requires an even number of arguments");
			static assert(false);
		}

		MDTable ret = new MDTable();
		
		foreach(i, arg; args)
			static if(!(i & 1))
				ret[MDValue(arg)] = MDValue(args[i + 1]);

		return ret;
	}

	public override MDTable asTable()
	{
		return this;
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
	
	public void remove(inout MDValue index)
	{
		MDValue* ptr = (index in mData);

		if(ptr is null)
			return;

		mData.remove(index);
	}
	
	public MDValue* opIn_r(inout MDValue index)
	{
		return (index in mData);
	}

	public MDValue* opIndex(inout MDValue index)
	{
		MDValue* val = (index in mData);
		
		if(val is null)
			return &MDValue.nullValue;
		else
			return val;
	}
	
	public MDValue* opIndex(dchar[] index)
	{
		scope str = MDString.newTemp(index);
		return opIndex(MDValue(str));
	}

	public void opIndexAssign(inout MDValue value, inout MDValue index)
	{
		if(value.isNull())
			mData.remove(index);
		else
			mData[index] = value;
	}

	public void opIndexAssign(inout MDValue value, dchar[] index)
	{
		opIndexAssign(value, MDValue(index));
	}
	
	public void opIndexAssign(MDObject value, inout MDValue index)
	{
		opIndexAssign(MDValue(value), index);
	}
	
	public void opIndexAssign(MDObject value, dchar[] index)
	{
		opIndexAssign(MDValue(value), MDValue(index));
	}

	public int opApply(int delegate(inout MDValue key, inout MDValue value) dg)
	{
		int result = 0;

		foreach(MDValue key, MDValue value; mData)
		{
			result = dg(key, value);

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
		mType = MDValue.Type.Array;
	}

	package this(MDValue[] data)
	{
		mData = data;
		mType = MDValue.Type.Array;
	}

	package this(MDString[] data)
	{
		mData.length = data.length;

		foreach(i, inout v; mData)
			v.value = data[i];

		mType = MDValue.Type.Array;
	}

	public static MDArray create(T...)(T args)
	{
		MDArray ret = new MDArray(args.length);

		foreach(i, arg; args)
			putInValue(ret.mData[i], arg);

		return ret;
	}

	public override MDArray asArray()
	{
		return this;
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
	
	public int opIn_r(inout MDValue v)
	{
		foreach(i, inout val; mData)
			if(val.rawEquals(&v))
				return i;
				
		return -1;
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
	
	public MDArray opCat(inout MDValue elem)
	{
		MDArray n = new MDArray(mData.length + 1);
		n.mData = mData ~ elem;
		return n;
	}

	public MDArray opCatAssign(MDArray other)
	{
		mData ~= other.mData;
		return this;
	}
	
	public MDArray opCatAssign(inout MDValue elem)
	{
		mData ~= elem;
		return this;
	}
	
	public MDValue* opIndex(int index)
	{
		return &mData[index];
	}
	
	public void opIndexAssign(inout MDValue value, uint index)
	{
		mData[index] = value;
	}
	
	public void opIndexAssign(MDObject value, uint index)
	{
		mData[index].value = value;
	}
	
	public MDArray opSlice(uint lo, uint hi)
	{
		return new MDArray(mData[lo .. hi]);
	}
	
	public void opSliceAssign(inout MDValue value, uint lo, uint hi)
	{
		mData[lo .. hi] = value;
	}
	
	public void opSliceAssign(MDArray arr, uint lo, uint hi)
	{
		mData[lo .. hi] = arr.mData[];
	}
	
	public void opSliceAssign(inout MDValue value)
	{
		mData[] = value;
	}
	
	public void opSliceAssign(MDArray arr)
	{
		mData[] = arr.mData[];
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
				result[i] = v;
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
	protected MDNamespace mFields;
	protected MDNamespace mMethods;

	protected static MDString CtorString;
	protected static MDString SuperString;
	
	static this()
	{
		CtorString = new MDString("constructor"d);
		SuperString = new MDString("super"d);
	}

	package this(dchar[] guessedName, MDClass baseClass)
	{
		mType = MDValue.Type.Class;

		mGuessedName = guessedName.dup;
		mBaseClass = baseClass;

		mFields = new MDNamespace();
		mMethods = new MDNamespace();

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
	
	public override uint length()
	{
		throw new MDException("Cannot get the length of a class");
	}
	
	public MDInstance newInstance()
	{
		return new MDInstance(this);
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
		scope str = MDString.newTemp(index);
		return opIndex(str);
	}

	public void opIndexAssign(inout MDValue value, MDString index)
	{
		if(value.isFunction())
			mMethods[index] = value;
		else
			mFields[index] = value;
	}

	public void opIndexAssign(MDObject value, MDString index)
	{
		opIndexAssign(MDValue(value), index);
	}

	public void opIndexAssign(inout MDValue value, dchar[] index)
	{
		opIndexAssign(value, new MDString(index));
	}

	public void opIndexAssign(MDObject value, dchar[] index)
	{
		opIndexAssign(MDValue(value), new MDString(index));
	}
	
	public dchar[] getName()
	{
		return mGuessedName.dup;
	}
	
	public MDNamespace fields()
	{
		return mFields;
	}
	
	public MDNamespace methods()
	{
		return mMethods;
	}

	public char[] toString()
	{
		return string.format("class %s", mGuessedName);
	}
}

class MDInstance : MDObject
{
	protected MDClass mClass;
	protected MDNamespace mFields;
	protected MDNamespace mMethods;

	private this(MDClass _class)
	{
		mType = MDValue.Type.Instance;
		mClass = _class;
		mFields = mClass.mFields.dup;
		mMethods = mClass.mMethods;
	}

	public override MDInstance asInstance()
	{
		return this;
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
		scope str = MDString.newTemp(index);
		return opIndex(str);
	}
	
	public void opIndexAssign(inout MDValue value, MDString index)
	{
		if(value.isFunction())
			throw new MDException("Attempting to change a method of a class instance");
		else
			mFields[index] = value;
	}

	public void opIndexAssign(MDObject value, MDString index)
	{
		opIndexAssign(MDValue(value), index);
	}

	public void opIndexAssign(inout MDValue value, dchar[] index)
	{
		opIndexAssign(value, new MDString(index));
	}

	public void opIndexAssign(MDObject value, dchar[] index)
	{
		opIndexAssign(MDValue(value), new MDString(index));
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
	
	public MDNamespace fields()
	{
		return mFields;
	}
	
	public MDNamespace methods()
	{
		return mMethods;
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

	public this(MDClosure closure, MDValue[] context)
	{
		mClosure = closure;
		mContext = context;
		mType = MDValue.Type.Delegate;
	}

	public override MDDelegate asDelegate()
	{
		return this;
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

class MDNamespace : MDObject
{
	protected MDValue[MDString] mData;
	protected MDNamespace mParent;
	dchar[] mName;

	public this(dchar[] name = null, MDNamespace parent = null)
	{
		mName = name;
		mParent = parent;
		mType = MDValue.Type.Namespace;
	}
	
	public static MDNamespace create(T...)(dchar[] name, MDNamespace parent, T args)
	{
		MDNamespace ret = new MDNamespace(name, parent);
		ret.addList(args);

		return ret;
	}
	
	public void addList(T...)(T args)
	{
		static if(args.length & 1)
		{
			pragma(msg, "MDNamespace.addList() requires an even number of arguments");
			static assert(false);
		}

		foreach(i, arg; args)
		{
			static if(!(i & 1))
			{
				static if(!isStringType!(typeof(arg)) && !is(typeof(arg) : MDString))
				{
					pragma(msg, "Native namespace constructor keys must be strings");
					static assert(false);
				}

				this[new MDString(arg)] = MDValue(args[i + 1]);
			}
		}
	}

	public override MDNamespace asNamespace()
	{
		return this;
	}
	
	public override uint length()
	{
		return mData.length;
	}
	
	public dchar[] name()
	{
		return mName;
	}
	
	public MDNamespace parent()
	{
		return mParent;
	}

	public MDValue* opIn_r(MDString index)
	{
		return (index in mData);
	}
	
	public MDValue* opIn_r(dchar[] index)
	{
		scope idx = MDString.newTemp(index);
		return (idx in mData);	
	}

	public MDNamespace dup()
	{
		MDNamespace n = new MDNamespace(mName, mParent);

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
	
	public void remove(MDString index)
	{
		MDValue* ptr = (index in mData);

		if(ptr is null)
			return;
			
		mData.remove(index);
	}
	
	public MDValue* opIndex(MDString index)
	{
		return (index in mData);
	}

	public MDValue* opIndex(dchar[] index)
	{
		scope str = MDString.newTemp(index);
		return opIndex(str);
	}

	public void opIndexAssign(inout MDValue value, MDString index)
	{
		mData[index] = value;
	}

	public void opIndexAssign(inout MDValue value, dchar[] index)
	{
		opIndexAssign(value, new MDString(index));
	}
	
	public void opIndexAssign(MDObject value, MDString index)
	{
		opIndexAssign(MDValue(value), index);
	}
	
	public void opIndexAssign(MDObject value, dchar[] index)
	{
		opIndexAssign(MDValue(value), new MDString(index));
	}

	public int opApply(int delegate(inout MDString key, inout MDValue value) dg)
	{
		int result = 0;

		foreach(MDString key, MDValue value; mData)
		{
			result = dg(key, value);

			if(result)
				break;
		}

		return result;
	}

	public dchar[] nameString()
	{
		dchar[] ret = mName;

		if(mParent)
			ret = mParent.nameString() ~ "." ~ ret;
			
		return ret;
	}

	public char[] toString()
	{
		return string.format("namespace %s", nameString());
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

class MDModuleDef
{
	package dchar[][] mName;
	package dchar[][][] mImports;
	package MDFuncDef mFunc;
	
	dchar[] name()
	{
		return djoin(mName, '.');
	}

	align(1) struct FileHeader
	{
		uint magic = FOURCC!("MinD");
		uint _version = MiniDVersion;

		version(X86_64)
		{
			ubyte platformBits = 64;
		}
		else
		{
			ubyte platformBits = 32;
		}

		ubyte endianness = cast(ubyte)std.system.endian;
		ushort _padding1 = 0;
		uint _padding2 = 0;
		
		static const bool SerializeAsChunk = true;
	}
	
	static assert(FileHeader.sizeof == 16);

	public void serialize(Stream s)
	{
		FileHeader header;
		Serialize(s, header);
		Serialize(s, mName);
		Serialize(s, mImports);

		assert(mFunc.mNumUpvals == 0, "MDModuleDef.serialize() - Func def has upvalues");

		Serialize(s, mFunc);
	}

	public static MDModuleDef deserialize(Stream s)
	{
		FileHeader header;
		Deserialize(s, header);

		if(header != FileHeader.init)
			throw new MDException("MDModuleDef.deserialize() - Invalid file header");

		MDModuleDef ret = new MDModuleDef();
		Deserialize(s, ret.mName);
		Deserialize(s, ret.mImports);
		Deserialize(s, ret.mFunc);
		
		return ret;
	}
	
	public static MDModuleDef loadFromFile(char[] filename)
	{
		scope file = new BufferedFile(filename, FileMode.In);
		MDModuleDef ret;
		Deserialize(file, ret);
		return ret;
	}
}

class MDFuncDef
{
	package Location mLocation;
	package bool mIsVararg;
	package dchar[] mGuessedName;
	package uint mNumParams;
	package uint mNumUpvals;
	package uint mStackSize;
	package MDFuncDef[] mInnerFuncs;
	package MDValue[] mConstants;
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
	
	package void serialize(Stream s)
	{
		Serialize(s, mLocation);
		Serialize(s, mIsVararg);
		Serialize(s, mGuessedName);
		Serialize(s, mNumParams);
		Serialize(s, mNumUpvals);
		Serialize(s, mStackSize);
		Serialize(s, mConstants);
		Serialize(s, mCode);
		Serialize(s, mLineInfo);
		Serialize(s, mUpvalNames);
		Serialize(s, mLocVarDescs);

		Serialize(s, mSwitchTables.length);
		
		foreach(st; mSwitchTables)
		{
			Serialize(s, st.isString);
			
			if(st.isString)
			{
				Serialize(s, st.stringOffsets.length);

				foreach(k, v; st.stringOffsets)
				{
					Serialize(s, k);
					Serialize(s, v);
				}
			}
			else
			{
				Serialize(s, st.intOffsets.length);

				foreach(k, v; st.intOffsets)
				{
					Serialize(s, k);
					Serialize(s, v);
				}
			}
			
			Serialize(s, st.defaultOffset);
		}
		
		Serialize(s, mInnerFuncs);
	}
	
	package static MDFuncDef deserialize(Stream s)
	{
		MDFuncDef ret = new MDFuncDef();
		
		Deserialize(s, ret.mLocation);
		Deserialize(s, ret.mIsVararg);
		Deserialize(s, ret.mGuessedName);
		Deserialize(s, ret.mNumParams);
		Deserialize(s, ret.mNumUpvals);
		Deserialize(s, ret.mStackSize);
		Deserialize(s, ret.mConstants);
		Deserialize(s, ret.mCode);
		Deserialize(s, ret.mLineInfo);
		Deserialize(s, ret.mUpvalNames);
		Deserialize(s, ret.mLocVarDescs);

		size_t len;
		Deserialize(s, len);
		ret.mSwitchTables.length = len;
		
		foreach(inout st; ret.mSwitchTables)
		{
			Deserialize(s, st.isString);
			
			if(st.isString)
			{
				Deserialize(s, len);
				
				for(int i = 0; i < len; i++)
				{
					dchar[] key;
					int value;
					
					Deserialize(s, key);
					Deserialize(s, value);

					st.stringOffsets[key] = value;
				}
			}
			else
			{
				Deserialize(s, len);
				
				for(int i = 0; i < len; i++)
				{
					int key;
					int value;
					
					Deserialize(s, key);
					Deserialize(s, value);
					
					st.intOffsets[key] = value;
				}
			}

			Deserialize(s, st.defaultOffset);
		}
		
		Deserialize(s, ret.mInnerFuncs);

		return ret;
	}
}

class MDGlobalState
{
	private static MDGlobalState instance;
	private MDState mMainThread;
	private MDNamespace[] mBasicTypeMT;
	private MDNamespace mGlobals;
	private MDModuleDef delegate(dchar[][])[] mModuleLoaders;
	private bool[dchar[]] mLoadedModules;

	public static bool isInitialized()
	{
		return instance !is null;
	}

	public static MDGlobalState opCall()
	{
		if(instance is null)
			instance = new MDGlobalState();

		return instance;
	}

	private this()
	{
		mGlobals = new MDNamespace();
		mGlobals["_G"d] = mGlobals;

		mMainThread = new MDState();
		mBasicTypeMT = new MDNamespace[MDValue.Type.max + 1];
	}

	public MDNamespace getMetatable(MDValue.Type type)
	{
		return mBasicTypeMT[cast(uint)type];
	}

	public void setMetatable(MDValue.Type type, MDNamespace table)
	{
		debug switch(type)
		{
			case MDValue.Type.Null:
			case MDValue.Type.Userdata:
				throw new MDException("Cannot set global metatable for type '%s'", MDValue.typeString(type));

			default:
				break;
		}

		mBasicTypeMT[type] = table;
	}

	public MDState mainThread()
	{
		return mMainThread;
	}
	
	public MDNamespace globals()
	{
		return mGlobals;
	}
	
	public void setGlobal(T)(dchar[] name, T value)
	{
		mGlobals[new MDString(name)] = MDValue(value);
	}

	public MDValue* getGlobal(dchar[] name)
	{
		scope str = MDString.newTemp(name);
		MDValue* value = mGlobals[str];
		
		if(value is null)
			throw new MDException("MDGlobalState.getGlobal() - Attempting to access nonexistent global '%s'", name);

		return value;
	}
	
	public MDClosure newClosure(MDFuncDef def)
	{
		return new MDClosure(mGlobals, def);
	}
	
	public MDClosure newClosure(int delegate(MDState) func, dchar[] name, MDValue[] upvals = null)
	{
		return new MDClosure(mGlobals, func, name, upvals);
	}
	
	public void registerModuleLoader(MDModuleDef delegate(dchar[][]) loader)
	{
		mModuleLoaders ~= loader;
	}
	
	public void importModule(char[] name)
	{
		char[][] parts = string.split(name, ".");
		
		dchar[][] n = new dchar[][parts.length];
		
		foreach(i, part; parts)
			n[i] = utf.toUTF32(part);
			
		return importModule(n);
	}

	public void importModule(dchar[][] name, dchar[] fromModule = null)
	{
		return importModule(name, fromModule, mMainThread);
	}

	public void importModule(dchar[][] name, dchar[] fromModule, MDState s)
	{
		if(djoin(name, '.') in mLoadedModules)
			return;

		MDModuleDef def;

		foreach(loader; mModuleLoaders)
		{
			def = loader(name);

			if(def !is null)
				break;
		}

		if(def is null)
		{
			if(fromModule.length == 0)
				throw new MDException("Could not import module \"%s\"", djoin(name, '.'));
			else
				throw new MDException("From module \"%s\"", fromModule, ": Could not import module \"%s\"", djoin(name, '.'));
		}
		
		if(def.mName != name)
		{
			if(fromModule.length == 0)
				throw new MDException("Attempting to load module \"%s\"", djoin(name, '.'), ", but module declaration says \"%s\"", djoin(def.mName, '.'), "");
			else
				throw new MDException("From module \"%s\"", fromModule, ": Attempting to load module \"%s\"", djoin(name, '.'), ", but module declaration says \"%s\"", djoin(def.mName, '.'));
		}

		initModule(def, true, s);
	}

	public MDClosure initModule(MDModuleDef def, bool staticInit = true)
	{
		return initModule(def, staticInit, mMainThread);
	}

	public MDClosure initModule(MDModuleDef def, bool staticInit, MDState s)
	{
		mLoadedModules[def.name] = true;

		scope(failure)
			mLoadedModules.remove(def.name);

		dchar[][] packages = def.mName[0 .. $ - 1];
		dchar[] name = def.mName[$ - 1];

		MDNamespace put = mGlobals;
	
		foreach(i, pkg; packages)
		{
			MDValue* v = (pkg in put);

			if(v is null)
			{
				MDNamespace n = new MDNamespace(pkg, put);
				put[pkg] = n;
				put = n;
			}
			else
			{
				if(v.isNamespace())
					put = v.asNamespace();
				else
					s.throwRuntimeException("MDState.loadModule() - Error loading ", def.name, "; conflicts with ", packages[0 .. i + 1]);
			}
		}

		if(name in put)
			throw new MDException("MDState.loadModule() - Module '%s' already exists", def.name);

		MDNamespace modNS = new MDNamespace(name, put);
		put[name] = modNS;

		foreach(imp; def.mImports)
			importModule(imp, def.name, s);

		MDClosure ret = new MDClosure(modNS, def.mFunc);

		if(staticInit)
			s.easyCall(ret, 0, MDValue(modNS));
			
		return ret;
	}
}

class MDState
{
	struct ActRecord
	{
		uint base;
		uint savedTop;
		uint vargBase;
		uint funcSlot;
		MDClosure func;
		Instruction* pc;
		uint numReturns;
		MDNamespace env;
	}

	struct TryRecord
	{
		bool isCatch;
		uint catchVarSlot;
		uint actRecord;
		Instruction* pc;
	}
	
	protected TryRecord[] mTryRecs;
	protected TryRecord* mCurrentTR;
	protected uint mTRIndex = 0;

	protected ActRecord[] mActRecs;
	protected ActRecord* mCurrentAR;
	protected uint mARIndex = 0;

	protected MDValue[] mStack;
	protected uint mStackIndex = 0;
	
	protected MDUpval* mUpvalHead;

	protected Location[] mTraceback;

	// ===================================================================================
	// Public members
	// ===================================================================================

	public this()
	{
		mTryRecs = new TryRecord[10];
		mCurrentTR = &mTryRecs[0];

		mActRecs = new ActRecord[10];
		mCurrentAR = &mActRecs[0];

		mStack = new MDValue[20];

		mTryRecs[0].actRecord = uint.max;
	}

	debug final public void printStack()
	{
		writefln();
		writefln("-----Stack Dump-----");
		for(int i = 0; i < mCurrentAR.savedTop; i++)
			writefln("[%2d:%3d]: %s", i, i - cast(int)mCurrentAR.base, mStack[i].toString());

		writefln();
	}
	
	debug final public void printCallStack()
	{
		writefln();
		writefln("-----Call Stack-----");
		
		for(int i = mARIndex; i > 0; i--)
		{
			with(mActRecs[i])
			{
				writefln("Record ", func.toString());
				writefln("\tBase: ", base);
				writefln("\tSaved Top: ", savedTop);
				writefln("\tVararg Base: ", vargBase);
				writefln("\tFunc Slot: ", funcSlot);
				writefln("\tNum Returns: ", numReturns);
			}
		}
		writefln();
	}

	public uint pushNull()
	{
		MDValue v;
		v.setNull();
		return push(&v);
	}

	public uint push(T)(T value)
	{
		needStackSlots(1);
		mStack[mStackIndex].value = MDValue(value);

		mStackIndex++;

		debug(STACKINDEX) writefln("push() set mStackIndex to ", mStackIndex);//, " (pushed %s)", val.toString());

		return mStackIndex - 1 - mCurrentAR.base;
	}

	public MDValue pop()
	{
		if(mStackIndex <= mCurrentAR.base)
			throwRuntimeException("MDState.pop() - Stack underflow");
			
		mStackIndex--;
		return mStack[mStackIndex];
	}
	
	public uint easyCall(T...)(MDClosure func, int numReturns, MDValue context, T params)
	{
		uint paramSlot = mStackIndex;

		push(context);

		foreach(param; params)
			push(param);

		if(callPrologue2(func, paramSlot, numReturns, paramSlot, params.length + 1))
			execute();
			
		if(numReturns == -1)
			return mStackIndex - paramSlot;
		else
		{
			mStackIndex = paramSlot + numReturns;
			return numReturns;	
		}
	}

	public uint call(uint slot, int numParams, int numReturns)
	{
		if(callPrologue(slot, numReturns, numParams))
			execute();

		return mStackIndex - slot;
	}

	public void setUpvalue(T)(uint index, T value)
	{
		if(!mCurrentAR.func)
			throwRuntimeException("MDState.setUpvalue() - No function to set upvalue");

		if(mCurrentAR.func.isNative() == false)
			throwRuntimeException("MDState.setUpvalue() cannot be used on a non-native function");

		if(index >= mCurrentAR.func.native.upvals.length)
			throwRuntimeException("MDState.setUpvalue() - Invalid upvalue index: ", index);

		putInValue(mCurrentAR.func.native.upvals[index], value);
	}

	public MDValue* getUpvalue(uint index)
	{
		if(mCurrentAR.func)
		{
			if(mCurrentAR.func.isNative() == false)
				throwRuntimeException("MDState.getUpvalue() cannot be used on a non-native function");
				
			if(index >= mCurrentAR.func.native.upvals.length)
				throwRuntimeException("MDState.getUpvalue() - Invalid upvalue index: ", index);
		}
		else
			throwRuntimeException("MDState.getUpvalue() - No function to get upvalue");

		return &mCurrentAR.func.native.upvals[index];
	}

	public uint numParams()
	{
		return getBasedStackIndex() - 1;
	}

	public bool isParam(char[] type)(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		static if(type == "null")           return getBasedStack(index + 1).isNull();
		else static if(type == "bool")      return getBasedStack(index + 1).isBool();
		else static if(type == "int")       return getBasedStack(index + 1).isInt();
		else static if(type == "float")     return getBasedStack(index + 1).isFloat();
		else static if(type == "char")      return getBasedStack(index + 1).isChar();
		else static if(type == "string")    return getBasedStack(index + 1).isString();
		else static if(type == "table")     return getBasedStack(index + 1).isTable();
		else static if(type == "array")     return getBasedStack(index + 1).isArray();
		else static if(type == "function")  return getBasedStack(index + 1).isFunction();
		else static if(type == "userdata")  return getBasedStack(index + 1).isUserdata();
		else static if(type == "class")     return getBasedStack(index + 1).isClass();
		else static if(type == "instance")  return getBasedStack(index + 1).isInstance();
		else static if(type == "delegate")  return getBasedStack(index + 1).isDelegate();
		else static if(type == "namespace") return getBasedStack(index + 1).isNamespace();
		else
		{
			pragma(msg, "MDState.isParam() - invalid type \"" ~ type ~ "\"");
			ERROR_MDState_isParam_InvalidType();
		}
	}

	/*public T getTypeParam(T)(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
			
		MDValue* val = getBasedStack(index);

		static if(isCharType!(T))
		{
			if(val.isChar() == false)
				badParamError(this, index, "expected 'char' but got '%s'", val.typeString());

			return cast(T)val.asChar();
		}
		else static if(isIntType!(T))
		{
			if(val.isInt() == false)
				badParamError(this, index, "expected 'int' but got '%s'", val.typeString());
				
			return cast(T)val.asInt();
		}
		else static if(is(T : float))
		{
			if(val.isFloat() == false)
				badParamError(this, index, "expected 'float' but got '%s'", val.typeString());
	
			return cast(T)val.asFloat();
		}
		else static if(is(T : char[]))
		{
			if(val.isString() == false)
				badParamError(this, index, "expected 'string' but got '%s'", val.typeString());
	
			return val.asString.asUTF8();
		}
		else static if(is(T : wchar[]))
		{
			if(val.isString() == false)
				badParamError(this, index, "expected 'string' but got '%s'", val.typeString());
	
			return val.asString.asUTF16();
		}
		else static if(is(T : dchar[]))
		{
			if(val.isString() == false)
				badParamError(this, index, "expected 'string' but got '%s'", val.typeString());
	
			return val.asString.asUTF32();
		}
	}*/

	public MDValue getParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		return *getBasedStack(index + 1);
	}

	public bool getBoolParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		MDValue* val = getBasedStack(index + 1);

		if(val.isBool() == false)
			badParamError(this, index, "expected 'bool' but got '%s'", val.typeString());

		return val.asBool();
	}

	public int getIntParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		MDValue* val = getBasedStack(index + 1);

		if(val.isInt() == false)
			badParamError(this, index, "expected 'int' but got '%s'", val.typeString());

		return val.asInt();
	}

	public float getFloatParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		MDValue* val = getBasedStack(index + 1);

		if(val.isFloat() == false)
			badParamError(this, index, "expected 'float' but got '%s'", val.typeString());

		return val.asFloat();
	}

	public dchar getCharParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		MDValue* val = getBasedStack(index + 1);

		if(val.isChar() == false)
			badParamError(this, index, "expected 'char' but got '%s'", val.typeString());

		return val.asChar();
	}

	public MDString getStringParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		MDValue* val = getBasedStack(index + 1);

		if(val.isString() == false)
			badParamError(this, index, "expected 'string' but got '%s'", val.typeString());

		return val.asString();
	}

	public MDArray getArrayParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		MDValue* val = getBasedStack(index + 1);

		if(val.isArray() == false)
			badParamError(this, index, "expected 'array' but got '%s'", val.typeString());

		return val.asArray();
	}

	public MDTable getTableParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		MDValue* val = getBasedStack(index + 1);

		if(val.isTable() == false)
			badParamError(this, index, "expected 'table' but got '%s'", val.typeString());

		return val.asTable();
	}

	public MDClosure getClosureParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		MDValue* val = getBasedStack(index + 1);

		if(val.isFunction() == false)
			badParamError(this, index, "expected 'function' but got '%s'", val.typeString());

		return val.asFunction();
	}

	public MDUserdata getUserdataParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		MDValue* val = getBasedStack(index + 1);

		if(val.isUserdata() == false)
			badParamError(this, index, "expected 'userdata' but got '%s'", val.typeString());

		return val.asUserdata();
	}

	public MDClass getClassParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		MDValue* val = getBasedStack(index + 1);

		if(val.isClass() == false)
			badParamError(this, index, "expected 'class' but got '%s'", val.typeString());

		return val.asClass();
	}

	public MDInstance getInstanceParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		MDValue* val = getBasedStack(index + 1);

		if(val.isInstance() == false)
			badParamError(this, index, "expected 'instance' but got '%s'", val.typeString());

		return val.asInstance();
	}

	public MDInstance getInstanceParam(uint index, MDClass type)
	{
		assert(type !is null, "getInstanceParam wants a non-null type!");

		if(index >= numParams())
			badParamError(this, index, "not enough parameters");

		MDValue* val = getBasedStack(index + 1);

		if(val.isInstance() == false)
			badParamError(this, index, "expected 'instance' but got '%s'", val.typeString());

		MDInstance i = val.asInstance();

		if(i.castToClass(type) == false)
			badParamError(this, index, "expected instance of class '%s' but got instance of class '%s'", type.getName(), i.getClass().getName());

		return i;
	}
	
	public MDDelegate getDelegateParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index + 1);

		if(val.isDelegate() == false)
			badParamError(this, index, "expected 'delegate' but got '%s'", val.typeString());

		return val.asDelegate();
	}
	
	public MDNamespace getNamespaceParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index + 1);

		if(val.isNamespace() == false)
			badParamError(this, index, "expected 'namespace' but got '%s'", val.typeString());

		return val.asNamespace();
	}

	public MDValue[] getAllParams()
	{
		if(numParams() == 0)
			return null;

		return mStack[mCurrentAR.base + 1 .. mStackIndex].dup;
	}

	public MDValue getContext()
	{
		return mStack[mCurrentAR.base];
	}
	
	public MDValue[] getParams(int lo, int hi)
	{
		int numParams = getBasedStackIndex();
		
		if(lo < 0)
			lo = numParams + lo + 1;

		if(hi < 0)
			hi = numParams + hi + 1;

		if(lo > hi || lo < 0 || lo > numParams || hi < 0 || hi > numParams)
			throwRuntimeException("Invalid getParams indices (", lo, " .. ", hi, ") (num params = ", numParams, ")");

		return mStack[mCurrentAR.base + lo + 1.. mCurrentAR.base + hi].dup;
	}
	
	public char[] getTracebackString()
	{
		if(mTraceback.length == 0)
			return "";
			
		char[] ret = string.format("Traceback: ", mTraceback[0].toString());

		foreach(inout Location l; mTraceback[1 .. $])
			ret = string.format("%s\n\tat ", ret, l.toString());

		mTraceback.length = 0;

		return ret;
	}
	
	public MDString valueToString(inout MDValue value)
	{
		if(value.isString())
			return value.asString();

		MDValue* method = getMM(value, MM.ToString);
		
		if(method.isNull() || !method.isFunction())
			return new MDString(value.toString());

		easyCall(method.asFunction(), 1, value);
		MDValue ret = pop();

		if(!ret.isString())
			throwRuntimeException("MDState.valueToString() - '%s' method did not return a string", MetaNames[MM.ToString]);
			
		return ret.asString();
	}

	public T safeCode(T)(lazy T code)
	{
		try
			return code;
		catch(MDException e)
			throw e;
		catch(Exception e)
			throwRuntimeException(e.toString());
	}

	public void throwRuntimeException(MDValue* val)
	{
		throw new MDRuntimeException(startTraceback(), val);
	}
	
	public void throwRuntimeException(...)
	{
		throw new MDRuntimeException(startTraceback(), _arguments, _argptr);
	}

	// ===================================================================================
	// Internal functions
	// ===================================================================================

	protected Location startTraceback()
	{
		mTraceback.length = 0;
		return getDebugLocation();
	}

	protected Location getDebugLocation()
	{
		if(mCurrentAR.func is null)
			return Location("<no debug location available>", 0, 0);

		if(mCurrentAR.func.isNative())
			return Location(mCurrentAR.func.native.name, -1, -1);
		else
		{
			MDFuncDef fd = mCurrentAR.func.script.func;

			int line = -1;
			uint instructionIndex = mCurrentAR.pc - fd.mCode.ptr - 1;

			if(instructionIndex < fd.mLineInfo.length)
				line = fd.mLineInfo[instructionIndex];

			return Location(mCurrentAR.func.script.func.mGuessedName, line, instructionIndex);
		}
	}

	protected static void badParamError(MDState s, uint index, ...)
	{
		s.throwRuntimeException("Bad argument ", index + 1, ": %s", vformat(_arguments, _argptr));
	}

	protected bool callPrologue(uint slot, int numReturns, int numParams)
	{
		uint returnSlot;
		uint paramSlot;
		MDClosure closure;

		slot = basedIndexToAbs(slot);
		returnSlot = slot;

		if(numParams == -1)
			numParams = mStackIndex - slot - 1;

		assert(numParams >= 0, "negative num params in callPrologue");

		MDValue* func = getAbsStack(slot);

		switch(func.type())
		{
			case MDValue.Type.Class:
				pushAR();

				*mCurrentAR = mActRecs[mARIndex - 1];
				mCurrentAR.base = slot;
				mCurrentAR.numReturns = numReturns;
				mCurrentAR.funcSlot = slot;

				MDInstance n = func.asClass().newInstance();
				MDValue* ctor = n.getCtor();
	
				if(ctor !is null && ctor.isFunction())
				{
					uint thisSlot = slot + 1;

					getAbsStack(thisSlot).value = n;

					if(callPrologue2(ctor.asFunction(), thisSlot, 0, thisSlot, numParams))
						execute();
				}

				getAbsStack(slot).value = n;
				callEpilogue(0, 1);

				return false;

			case MDValue.Type.Function:
				closure = func.asFunction();
				paramSlot = slot + 1;
				break;

			case MDValue.Type.Delegate:
				MDDelegate dg = func.asDelegate();
				MDValue[] context = dg.getContext();

				if(context.length == 1)
				{
					getAbsStack(slot + 1).value = context[0];
					paramSlot = slot + 1;
				}
				else
				{
					if(context.length > 2)
					{
						needStackSlots(context.length - 2);

						for(int i = mStackIndex + context.length - 3; i > slot + context.length; i--)
							copyAbsStack(i, i - 1);
					}
	
					for(int i = slot, j = 0; j < context.length; i++, j++)
						getAbsStack(i).value = context[j];

					paramSlot = slot;
				}
				
				numParams += context.length - 1;
				closure = dg.getClosure();
				break;

			default:
				MDValue* method = getMM(*func, MM.Call);

				if(method.isNull() || !method.isFunction())
					throwRuntimeException("Attempting to call a value of type '%s'", func.typeString());

				copyAbsStack(slot + 1, slot);
				paramSlot = slot + 1;
				closure = method.asFunction();
				break;
		}

		if(closure is null)
			return false;

		return callPrologue2(closure, returnSlot, numReturns, paramSlot, numParams);
	}

	protected bool callPrologue2(MDClosure closure, uint returnSlot, int numReturns, uint paramSlot, int numParams)
	{
		if(closure.isNative())
		{
			// Native function
			needStackSlots(20);

			mStackIndex = paramSlot + numParams;

			debug(STACKINDEX) writefln("callPrologue2 called a native func '%s'", closure.toString(), " and set mStackIndex to ", mStackIndex, " (got ", numParams, " params)");

			pushAR();

			mCurrentAR.base = paramSlot;
			mCurrentAR.vargBase = 0;
			mCurrentAR.funcSlot = returnSlot;
			mCurrentAR.func = closure;
			mCurrentAR.numReturns = numReturns;
			mCurrentAR.savedTop = mStackIndex;
			mCurrentAR.env = closure.environment();

			int actualReturns;

			try
			{
				actualReturns = closure.native.func(this);
			}
			catch(MDException e)
			{
				callEpilogue(0, 0);
				throw e;
			}

			callEpilogue(getBasedStackIndex() - actualReturns, actualReturns);
			return false;
		}
		else
		{
			// Script function
			MDFuncDef funcDef = closure.script.func;
			mStackIndex = paramSlot + numParams;

			uint base;
			uint vargBase;

			if(funcDef.mIsVararg)
			{
				if(numParams < funcDef.mNumParams)
				{
					needStackSlots(funcDef.mNumParams - numParams);

					for(int i = funcDef.mNumParams - numParams; i > 0; i--)
					{
						mStack[mStackIndex].setNull();
						mStackIndex++;
					}
					
					numParams = funcDef.mNumParams;
				}

				vargBase = paramSlot + funcDef.mNumParams;

				mStackIndex = paramSlot + numParams;

				needStackSlots(funcDef.mStackSize);

				debug(STACKINDEX) writefln("callPrologue2 adjusted the varargs and set mStackIndex to ", mStackIndex);

				uint oldParamSlot = paramSlot;
				base = mStackIndex;

				for(int i = 0; i < funcDef.mNumParams; i++)
				{
					copyAbsStack(mStackIndex, oldParamSlot);
					getAbsStack(oldParamSlot).setNull();
					oldParamSlot++;
					mStackIndex++;
				}
				
				debug(STACKINDEX) writefln("callPrologue2 copied the regular args for a vararg and set mStackIndex to ", mStackIndex);
			}
			else
			{
				base = paramSlot;

				if(mStackIndex > base + funcDef.mNumParams)
				{
					mStackIndex = base + funcDef.mNumParams;
					debug(STACKINDEX) writefln("callPrologue2 adjusted for too many args and set mStackIndex to ", mStackIndex);
				}

				needStackSlots(funcDef.mStackSize);
			}

			pushAR();

			mCurrentAR.base = base;
			mCurrentAR.vargBase = vargBase;
			mCurrentAR.funcSlot = returnSlot;
			mCurrentAR.func = closure;
			mCurrentAR.pc = funcDef.mCode.ptr;
			mCurrentAR.numReturns = numReturns;
			mCurrentAR.env = closure.environment();
			
			mStackIndex = base + funcDef.mStackSize;

			debug(STACKINDEX) writefln("callPrologue2 of function '%s'", closure.toString(), " set mStackIndex to ", mStackIndex, " (local stack size = ", funcDef.mStackSize, ", base = ", base, ")");

			for(int i = base + funcDef.mStackSize; i >= 0 && i >= base + numParams; i--)
				getAbsStack(i).setNull();

			mCurrentAR.savedTop = mStackIndex;

			return true;
		}
	}

	protected void callEpilogue(uint resultSlot, int numResults)
	{
		debug(CALLEPILOGUE) printCallStack();

		resultSlot = basedIndexToAbs(resultSlot);

		debug(CALLEPILOGUE) writefln("callEpilogue for function ", mCurrentAR.func.toString());
		debug(CALLEPILOGUE) writefln("\tResult slot: ", resultSlot, "\n\tNum results: ", numResults);

		uint destSlot = mCurrentAR.funcSlot;
		int numExpRets = mCurrentAR.numReturns;

		debug(CALLEPILOGUE) writefln("\tDest slot: ", destSlot, "\n\tNum expected results: ", numExpRets);

		bool isMultRet = false;

		if(numResults == -1)
			numResults = mStackIndex - resultSlot;

		if(numExpRets == -1)
		{
			isMultRet = true;
			numExpRets = numResults;
			debug(CALLEPILOGUE) writefln("\tNum multi rets: ", numExpRets);
		}

		popAR();

		if(numExpRets <= numResults)
		{
			while(numExpRets > 0)
			{
				copyAbsStack(destSlot, resultSlot);
				debug(CALLEPILOGUE) writefln("\tvalue: ", getAbsStack(destSlot).toString());

				destSlot++;
				resultSlot++;
				numExpRets--;
			}
		}
		else
		{
			while(numResults > 0)
			{
				copyAbsStack(destSlot, resultSlot);
				debug(CALLEPILOGUE) writefln("\tvalue: ", getAbsStack(destSlot).toString());

				destSlot++;
				resultSlot++;
				numResults--;
				numExpRets--;
			}

			while(numExpRets > 0)
			{
				getAbsStack(destSlot).setNull();
				destSlot++;
				numExpRets--;
			}
		}

		if(isMultRet)
			mStackIndex = destSlot;
		else
			mStackIndex = mCurrentAR.savedTop;

		debug(STACKINDEX) writefln("callEpilogue() set mStackIndex to ", mStackIndex);
	}

	protected void pushAR()
	{
		if(mARIndex >= mActRecs.length - 1)
		{
			try
			{
				mActRecs.length = mActRecs.length * 2;
			}
			catch
			{
				throwRuntimeException("Script call stack overflow");
			}
		}

		mARIndex++;

		mCurrentAR = &mActRecs[mARIndex];
	}

	protected void popAR()
	{
		mARIndex--;

		assert(mARIndex != uint.max, "Script call stack underflow");

		mCurrentAR.func = null;
		mCurrentAR.env = null;
		mCurrentAR = &mActRecs[mARIndex];
	}
	
	protected void pushTR()
	{
		if(mTRIndex >= mTryRecs.length - 1)
		{
			try
			{
				mTryRecs.length = mTryRecs.length * 2;
			}
			catch
			{
				throwRuntimeException("Script catch/finally stack overflow");
			}
		}

		mTRIndex++;
		mCurrentTR = &mTryRecs[mTRIndex];
		mCurrentTR.actRecord = mARIndex;
	}
	
	protected void popTR()
	{
		mTRIndex--;

		assert(mTRIndex != uint.max, "Script catch/finally stack underflow");

		mCurrentTR = &mTryRecs[mTRIndex];
	}

	protected void needStackSlots(uint howMany)
	{
		if(mStack.length - mStackIndex >= howMany + 1)
			return;

		stackSize = howMany + 1 + mStackIndex;
	}

	protected void stackSize(uint length)
	{
		MDValue* oldBase = mStack.ptr;

		try
		{
			mStack.length = length;
		}
		catch
		{
			throwRuntimeException("Script value stack overflow: ", mStack.length);
		}

		MDValue* newBase = mStack.ptr;

		if(oldBase !is newBase)
			for(MDUpval* uv = mUpvalHead; uv !is null; uv = uv.next)
				uv.value = (uv.value - oldBase) + newBase;
	}

	// Since this returns a slice of the actual stack, which can move around, the reference
	// shouldn't really be kept for long.
	protected MDValue[] sliceStack(uint lo, int num)
	{
		debug if(num != -1)
			assert(lo <= mStack.length && (lo + num) <= mStack.length, "invalid slice stack params");
		else
			assert(lo <= mStack.length, "invalid slice stack params");

		if(num == -1)
		{
			MDValue[] ret = mStack[lo .. mStackIndex];
			mStackIndex = mCurrentAR.savedTop;
			
			debug(STACKINDEX) writefln("sliceStack() set mStackIndex to ", mStackIndex);
			return ret;
		}
		else
			return mStack[lo .. lo + num];
	}

	protected void copyBasedStack(uint dest, uint src)
	{
		assert((mCurrentAR.base + dest) < mStack.length && (mCurrentAR.base + src) < mStack.length, "invalid based stack indices");
		
		if(dest != src)
			mStack[mCurrentAR.base + dest].value = mStack[mCurrentAR.base + src];
	}

	protected void copyAbsStack(uint dest, uint src)
	{
		assert(dest < mStack.length && src < mStack.length, "invalid copyAbsStack indices");
		
		if(dest != src)
			mStack[dest].value = mStack[src];
	}

	protected MDValue* getBasedStack(uint offset)
	{
		assert((mCurrentAR.base + offset) < mStack.length, "invalid based stack index");
		return &mStack[mCurrentAR.base + offset];
	}

	protected MDValue* getAbsStack(uint offset)
	{
		assert(offset < mStack.length, "invalid getAbsStack stack index");
		return &mStack[offset];
	}

	protected uint basedIndexToAbs(uint offset)
	{
		assert((mCurrentAR.base + offset) < mStack.length, "invalid basedIndexToAbs index");
		return mCurrentAR.base + offset;
	}
	
	protected uint absIndexToBased(uint offset)
	{
		assert((cast(int)(offset - mCurrentAR.base)) >= 0 && offset < mStack.length, "invalid absIndexToBased index");
		return offset - mCurrentAR.base;
	}

	protected MDValue* getConst(uint num)
	{
		assert(mCurrentAR.func.isNative() == false, "cannot get constant from native function");
		return &mCurrentAR.func.script.func.mConstants[num];
	}

	protected MDFuncDef getInnerFunc(uint num)
	{
		assert(mCurrentAR.func.isNative() == false, "cannot get inner func from native function");
		MDFuncDef def = mCurrentAR.func.script.func;
		assert(num < def.mInnerFuncs.length, "invalid inner func index");
		return def.mInnerFuncs[num];
	}
	
	protected void close(uint index)
	{
		MDValue* base = getBasedStack(index);

		for(MDUpval* uv = mUpvalHead; uv !is null && uv.value >= base; uv = mUpvalHead)
		{
			mUpvalHead = uv.next;

			if(uv.prev)
				uv.prev.next = uv.next;

			if(uv.next)
				uv.next.prev = uv.prev;

			uv.closedValue.value = *uv.value;
			uv.value = &uv.closedValue;
		}
	}

	protected MDUpval* getUpvalueRef(uint num)
	{
		assert(mCurrentAR.func.isNative() == false, "cannot get upval ref from native function");
		return mCurrentAR.func.script.upvals[num];
	}

	protected MDUpval* findUpvalue(uint num)
	{
		MDValue* slot = getBasedStack(num);

		for(MDUpval* uv = mUpvalHead; uv !is null && uv.value >= slot; uv = uv.next)
		{
			if(uv.value is slot)
				return uv;
		}

		MDUpval* ret = new MDUpval;
		ret.value = slot;
		
		if(mUpvalHead !is null)
		{
			ret.next = mUpvalHead;
			ret.next.prev = ret;
		}

		mUpvalHead = ret;

		return ret;
	}

	protected int getNumVarargs()
	{
		return mCurrentAR.base - mCurrentAR.vargBase;
	}

	protected int getBasedStackIndex()
	{
		return mStackIndex - mCurrentAR.base;
	}

	protected MDValue* getMM(inout MDValue obj, MM method)
	{
		MDValue* m;
		
		switch(obj.type)
		{
			case MDValue.Type.Table:
				m = obj.asTable[MDValue(MetaStrings[method])];

				if(!m.isFunction())
					goto default;

				break;

			case MDValue.Type.Instance:
				m = obj.asInstance[MetaStrings[method]];
				break;

			case MDValue.Type.Userdata:
				m = obj.asUserdata().metatable[MetaStrings[method]];
				break;

			default:
				MDNamespace n = MDGlobalState().getMetatable(obj.type);

				if(n is null)
					break;

				m = n[MetaStrings[method]];
				break;
		}

		if(m is null || !m.isFunction())
			return &MDValue.nullValue;
		else
			return m;
	}

	// ===================================================================================
	// Interpreter
	// ===================================================================================

	protected final MDValue* lookup(MDValue* src, MDString key)
	{
		switch(src.type)
		{
			case MDValue.Type.Table:
				MDValue* v = src.asTable[MDValue(key)];
				
				if(v.isNull())
					return null;
				
				return v;

			case MDValue.Type.Instance:
				return src.asInstance[key];

			case MDValue.Type.Class:
				return src.asClass[key];

			case MDValue.Type.Namespace:
				return src.asNamespace[key];

			default:
				return null;
		}
	}

	protected final MDValue index(MDValue src, MDValue key)
	{
		MDValue dest;

		void tryMM(MDRuntimeException delegate() ex)
		{
			MDValue* method = getMM(src, MM.Index);

			if(method.isNull())
				throw ex();

			if(method.isFunction() == false)
				throwRuntimeException("Invalid %s metamethod for type '%s'", MetaNames[MM.Index], src.typeString());

			uint funcSlot = push(method);
			push(src);
			push(key);
			call(funcSlot, 2, 1);
			dest.value = *getBasedStack(funcSlot);
		}

		switch(src.type)
		{
			case MDValue.Type.Array:
				if(key.isInt() == false)
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access an array with a '%s'", key.typeString());});
					break;
				}
				
				int index = key.asInt();
				MDArray arr = src.asArray();

				if(index < 0)
					index += arr.length;

				if(index < 0 || index >= arr.length)
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Invalid array index: ", index);});
					break;
				}

				dest.value = *arr[index];
				break;

			case MDValue.Type.String:
				if(key.isInt() == false)
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access a string with a '%s'", key.typeString());});
					break;
				}

				int index = key.asInt();
				MDString str = src.asString();

				if(index < 0)
					index += str.length;

				if(index < 0 || index >= str.length)
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Invalid string index: ", key.asInt());});
					break;
				}

				dest.value = str[index];
				break;

			case MDValue.Type.Table:
				dest.value = *src.asTable[key];
				break;

			case MDValue.Type.Instance:
				if(!key.isString())
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index an instance with a key of type '%s'", key.typeString());});
					break;
				}

				MDValue* v = src.asInstance[key.asString()];

				if(v is null)
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access nonexistent member '%s' from class instance", key.toString());});
					break;
				}

				dest.value = *v;
				break;

			case MDValue.Type.Class:
				if(!key.isString())
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index a class with a key of type '%s'", key.typeString());});
					break;
				}

				MDValue* v = src.asClass[key.asString()];
				
				if(v is null)
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access nonexistent member '%s' from class", key.toString());});
					break;
				}

				dest.value = *v;
				break;
				
			case MDValue.Type.Namespace:
				if(!key.isString())
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index namespace '%s' with a key of type '%s'", src.asNamespace.nameString(), key.typeString());});
					break;
				}

				MDValue* v = src.asNamespace[key.asString()];
				
				if(v is null)
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access nonexistent member '%s' from namespace %s", key.toString(), src.asNamespace.nameString);});
					break;
				}

				dest.value = *v;
				break;

			default:
				tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index a value of type '%s'", src.typeString());});
				break;
		}
		
		return dest;
	}

	protected final void indexAssign(MDValue dest, MDValue key, MDValue value)
	{
		void tryMM(MDRuntimeException delegate() ex)
		{
			MDValue* method = getMM(dest, MM.IndexAssign);

			if(method.isNull())
				throw ex();

			if(method.isFunction() == false)
				throwRuntimeException("Invalid %s metamethod for type '%s'", MetaNames[MM.IndexAssign], dest.typeString());
	
			uint funcSlot = push(method);
			push(dest);
			push(key);
			push(value);
			call(funcSlot, 3, 0);
		}

		switch(dest.type)
		{
			case MDValue.Type.Array:
				if(key.isInt() == false)
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access an array with a '%s'", key.typeString());});
					break;
				}
				
				int index = key.asInt();
				MDArray arr = dest.asArray();
				
				if(index < 0)
					index += arr.length;
					
				if(index < 0 || index >= arr.length)
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Invalid array index: ", key.asInt());});
					break;
				}

				arr[index] = value;
				break;

			case MDValue.Type.Table:
				dest.asTable()[key] = value;
				break;

			case MDValue.Type.Instance:
				if(!key.isString())
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign an instance with a key of type '%s'", key.typeString());});
					break;
				}

				MDString k = key.asString();
				MDValue* val = dest.asInstance[k];

				if(val is null)
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to add a member '%s' to a class instance", key.toString());});
					break;
				}

				if(val.isFunction())
					throw new MDRuntimeException(startTraceback(), "Attempting to change method '%s' of class instance", key.toString());

				val.value = value;
				break;

			case MDValue.Type.Class:
				if(!key.isString())
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign a class with a key of type '%s'", key.typeString());});
					break;
				}

				dest.asClass()[key.asString()] = value;
				break;
				
			case MDValue.Type.Namespace:
				if(!key.isString())
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign a namespace with a key of type '%s'", key.typeString());});
					break;
				}

				dest.asNamespace()[key.asString()] = value;
				break;

			default:
				tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign a value of type '%s'", dest.typeString());});
				break;
		}
	}

	protected final MDValue slice(MDValue src, MDValue lo, MDValue hi)
	{
		MDValue dest;

		void tryMM(MDRuntimeException delegate() ex)
		{
			MDValue* method = getMM(src, MM.Slice);

			if(method.isNull())
				throw ex();

			if(!method.isFunction())
				throwRuntimeException("Invalid %s metamethod for type '%s'", MetaNames[MM.Slice], src.typeString());
	
			uint funcSlot = push(method);
			push(src);
			push(lo);
			push(hi);
			call(funcSlot, 3, 1);
			dest.value = *getBasedStack(funcSlot);
		}

		switch(src.type)
		{
			case MDValue.Type.Array:
				MDArray arr = src.asArray();
				int loIndex;
				int hiIndex;
				
				if(lo.isNull() && hi.isNull())
				{
					dest.value = src;
					break;
				}

				if(lo.isNull())
					loIndex = 0;
				else if(lo.isInt())
				{
					loIndex = lo.asInt();
					
					if(loIndex < 0)
						loIndex += arr.length;
				}
				else
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice an array with a '%s'", lo.typeString());});
					break;
				}

				if(hi.isNull())
					hiIndex = arr.length;
				else if(hi.isInt())
				{
					hiIndex = hi.asInt();
					
					if(hiIndex < 0)
						hiIndex += arr.length;
				}
				else
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice an array with a '%s'", hi.typeString());});
					break;
				}

				if(loIndex > hiIndex || loIndex < 0 || loIndex > arr.length || hiIndex < 0 || hiIndex > arr.length)
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Invalid slice indices [", loIndex, " .. ", hiIndex, "] (array length = ", arr.length, ")");});
					break;
				}

				dest.value = arr[loIndex .. hiIndex];
				break;

			case MDValue.Type.String:
				MDString str = src.asString();
				int loIndex;
				int hiIndex;
				
				if(lo.isNull() && hi.isNull())
				{
					dest.value = src;
					break;
				}

				if(lo.isNull())
					loIndex = 0;
				else if(lo.isInt())
				{
					loIndex = lo.asInt();
					
					if(loIndex < 0)
						loIndex += str.length;
				}
				else
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice a string with a '%s'", lo.typeString());});
					break;
				}

				if(hi.isNull())
					hiIndex = str.length;
				else if(hi.isInt())
				{
					hiIndex = hi.asInt();
					
					if(hiIndex < 0)
						hiIndex += str.length;
				}
				else
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice a string with a '%s'", hi.typeString());});
					break;
				}

				if(loIndex > hiIndex || loIndex < 0 || loIndex > str.length || hiIndex < 0 || hiIndex > str.length)
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Invalid slice indices [", loIndex, " .. ", hiIndex, "] (string length = ", str.length, ")");});
					break;
				}

				dest.value = str[loIndex .. hiIndex];
				break;

			default:
				tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice a value of type '%s'", src.typeString());});
				break;
		}
		
		return dest;
	}
	
	protected final void sliceAssign(MDValue dest, MDValue lo, MDValue hi, MDValue value)
	{
		void tryMM(MDRuntimeException delegate() ex)
		{
			MDValue* method = getMM(dest, MM.SliceAssign);

			if(method.isNull())
				throw ex();

			if(!method.isFunction())
				throwRuntimeException("Invalid %s metamethod for type '%s'", MetaNames[MM.SliceAssign], dest.typeString());

			uint funcSlot = push(method);
			push(dest);
			push(lo);
			push(hi);
			push(value);
			call(funcSlot, 4, 0);
		}

		switch(dest.type)
		{
			case MDValue.Type.Array:
				MDArray arr = dest.asArray();
				int loIndex;
				int hiIndex;

				if(lo.isNull())
					loIndex = 0;
				else if(lo.isInt())
				{
					loIndex = lo.asInt();
					
					if(loIndex < 0)
						loIndex += arr.length;
				}
				else
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice assign an array with a '%s'", lo.typeString());});
					break;
				}

				if(hi.isNull())
					hiIndex = arr.length;
				else if(hi.isInt())
				{
					hiIndex = hi.asInt();
					
					if(hiIndex < 0)
						hiIndex += arr.length;
				}
				else
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice assign an array with a '%s'", hi.typeString());});
					break;
				}

				if(loIndex > hiIndex || loIndex < 0 || loIndex > arr.length || hiIndex < 0 || hiIndex > arr.length)
				{
					tryMM({return new MDRuntimeException(startTraceback(), "Invalid slice indices [", loIndex, " .. ", hiIndex, "] (array length = ", arr.length, ")");});
					break;
				}

				if(value.isArray())
				{
					if((hiIndex - loIndex) != value.asArray.length)
						throw new MDRuntimeException(startTraceback(), "Array slice assign lengths do not match (", hiIndex - loIndex, " and ", value.asArray.length, ")");
				
					arr[loIndex .. hiIndex] = value.asArray();
				}
				else
					arr[loIndex .. hiIndex] = value;
				break;

			default:
				tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice assign a value of type '%s'", dest.typeString());});
				break;
		}
	}

	protected final MDValue* lookupGlobal(MDNamespace ns, MDString name, out MDNamespace owner)
	{
		for( ; ns !is null; ns = ns.mParent)
		{
			MDValue* val = ns[name];
			
			if(val !is null)
			{
				owner = ns;
				return val;
			}
		}

		return null;
	}

	protected final MDValue* lookupMethod(MDValue* src, MDString name)
	{
		MDValue* v;

		switch(src.type)
		{
			case MDValue.Type.Instance:
				v = src.asInstance[name];

				if(v is null)
					throwRuntimeException("Attempting to access nonexistent member '%s' from class instance", name);

				return v;

			case MDValue.Type.Table:
				v = src.asTable[MDValue(name)];

				if(!v.isNull() && v.isFunction())
					return v;
					
				break;

			case MDValue.Type.Namespace:
				v = src.asNamespace[name];

				if(v is null)
					throwRuntimeException("Attempting to access nonexistent member '%s' from namespace '%s'", name, src.asNamespace.nameString);

				return v;

			case MDValue.Type.Class:
				v = src.asClass[name];

				if(v is null)
					throwRuntimeException("Attempting to access nonexistent member '%s' from class '%s'", name, src.asClass.getName());

				return v;
			
			default:
				break;
		}

		MDNamespace metatable = MDGlobalState().getMetatable(src.type);

		if(metatable is null)
			throwRuntimeException("No metatable for type '%s'", src.typeString());

		v = metatable[name];

		if(v is null)
			throwRuntimeException("No implementation of method '%s' for type '%s'", name, src.typeString());

		return v;
	}

	protected void execute()
	{
		int depth = 1;
		MDException currentException = null;

		_exceptionRetry:

		try
		{
			while(true)
			{
				Instruction i = *mCurrentAR.pc;

				mCurrentAR.pc++;

				MDValue RS;
				MDValue RSEnv;
				MDValue RT;

				MDValue* get(uint index, MDValue* environment)
				{
					uint val = index & ~Instruction.locMask;
					uint loc = index & Instruction.locMask;
					
					if(environment)
						environment.value = mCurrentAR.env;

					switch(loc)
					{
						case Instruction.locLocal: return getBasedStack(val);
						case Instruction.locConst: return getConst(val);
						case Instruction.locUpval: return getUpvalueRef(val).value;
						default: break;
					}
					
					assert(loc == Instruction.locGlobal, "get() location");

					MDValue* idx = getConst(val);
					assert(idx.isString(), "trying to get a non-string global");
					MDString name = idx.asString();

					MDValue* glob = lookup(getBasedStack(0), name);

					if(glob is null)
					{
						MDNamespace owner;
						glob = lookupGlobal(mCurrentAR.env, name, owner);

						if(glob is null)
							throwRuntimeException("Attempting to get nonexistent global '%s'", name);

						if(environment)
							environment.value = owner;
					}
					else if(environment)
						environment.value = *getBasedStack(0);

					return glob;
				}

				MDValue* getRD()
				{
					assert((i.rd & Instruction.locMask) != Instruction.locConst, "getRD setting a const");
					return get(i.rd, null);
				}

				void getRS()
				{
					RS = *get(i.rs, null);
				}
				
				void getRSwithEnv()
				{
					RS = *get(i.rs, &RSEnv);
				}

				void getRT()
				{
					RT = *get(i.rt, null);
				}

				Op opcode = cast(Op)i.opcode;
				
				MM operation;

				switch(opcode)
				{
					// Binary Arithmetic
					case Op.Add: operation = MM.Add; goto _doArithmetic;
					case Op.Sub: operation = MM.Sub; goto _doArithmetic;
					case Op.Mul: operation = MM.Mul; goto _doArithmetic;
					case Op.Div: operation = MM.Div; goto _doArithmetic;
					case Op.Mod: operation = MM.Mod; goto _doArithmetic;

					_doArithmetic:
						getRS();
						getRT();

						if(RS.isNum() && RT.isNum())
						{
							if(RS.isFloat() || RT.isFloat())
							{
								switch(operation)
								{
									case MM.Add: getRD().value = RS.asFloat() + RT.asFloat(); break;
									case MM.Sub: getRD().value = RS.asFloat() - RT.asFloat(); break;
									case MM.Mul: getRD().value = RS.asFloat() * RT.asFloat(); break;
									case MM.Div: getRD().value = RS.asFloat() / RT.asFloat(); break;
									case MM.Mod: getRD().value = RS.asFloat() % RT.asFloat(); break;
								}
							}
							else
							{
								switch(operation)
								{
									case MM.Add: getRD().value = RS.asInt() + RT.asInt(); break;
									case MM.Sub: getRD().value = RS.asInt() - RT.asInt(); break;
									case MM.Mul: getRD().value = RS.asInt() * RT.asInt(); break;
									case MM.Mod: getRD().value = RS.asInt() % RT.asInt(); break;

									case MM.Div:
										if(RT.asInt() == 0)
											throwRuntimeException("Integer divide by zero");

										getRD().value = RS.asInt() / RT.asInt(); break;
								}
							}
						}
						else
						{
							MDValue* method = getMM(RS, operation);

							if(!method.isFunction())
								throwRuntimeException("Cannot perform arithmetic on a '%s' and a '%s'", RS.typeString(), RT.typeString());

							uint funcSlot = push(method);
							push(RS);
							push(RT);
							call(funcSlot, 2, 1);
							getRD().value = *getBasedStack(funcSlot);
						}
						break;

					// Unary Arithmetic
					case Op.Neg:
						getRS();

						if(RS.isFloat())
							getRD().value = -RS.asFloat();
						else if(RS.isInt())
							getRD().value = -RS.asInt();
						else
						{
							MDValue* method = getMM(RS, MM.Neg);

							if(!method.isFunction())
								throwRuntimeException("Cannot perform negation on a '%s'", RS.typeString());

							uint funcSlot = push(method);
							push(RS);
							call(funcSlot, 1, 1);
							getRD().value = *getBasedStack(funcSlot);
						}
						break;

					// Reflexive Arithmetic
					case Op.AddEq: operation = MM.AddEq; goto _doReflexiveArithmetic;
					case Op.SubEq: operation = MM.SubEq; goto _doReflexiveArithmetic;
					case Op.MulEq: operation = MM.MulEq; goto _doReflexiveArithmetic;
					case Op.DivEq: operation = MM.DivEq; goto _doReflexiveArithmetic;
					case Op.ModEq: operation = MM.ModEq; goto _doReflexiveArithmetic;

					_doReflexiveArithmetic:
						MDValue* RD = getRD();
						getRS();
				
						if(RD.isNum() && RS.isNum())
						{
							if(RD.isFloat() || RS.isFloat())
							{
								switch(operation)
								{
									case MM.AddEq: RD.value = RD.asFloat() + RS.asFloat(); break;
									case MM.SubEq: RD.value = RD.asFloat() - RS.asFloat(); break;
									case MM.MulEq: RD.value = RD.asFloat() * RS.asFloat(); break;
									case MM.DivEq: RD.value = RD.asFloat() / RS.asFloat(); break;
									case MM.ModEq: RD.value = RD.asFloat() % RS.asFloat(); break;
								}
							}
							else
							{
								switch(operation)
								{
									case MM.AddEq: RD.value = RD.asInt() + RS.asInt(); break;
									case MM.SubEq: RD.value = RD.asInt() - RS.asInt(); break;
									case MM.MulEq: RD.value = RD.asInt() * RS.asInt(); break;
									case MM.ModEq: RD.value = RD.asInt() % RS.asInt(); break;
				
									case MM.DivEq:
										if(RS.asInt() == 0)
											throwRuntimeException("Integer divide by zero");
				
										RD.value = RD.asInt() / RS.asInt(); break;
								}
							}
						}
						else
						{
							MDValue* method = getMM(*RD, operation);
				
							if(!method.isFunction())
								throwRuntimeException("Cannot perform arithmetic on a '%s' and a '%s'", RD.typeString(), RS.typeString());
				
							uint funcSlot = push(method);
							push(RD);
							push(RS);
							call(funcSlot, 2, 0);
						}
						break;

					// Binary Bitwise
					case Op.And:  operation = MM.And;  goto _doBitArith;
					case Op.Or:   operation = MM.Or;   goto _doBitArith;
					case Op.Xor:  operation = MM.Xor;  goto _doBitArith;
					case Op.Shl:  operation = MM.Shl;  goto _doBitArith;
					case Op.Shr:  operation = MM.Shr;  goto _doBitArith;
					case Op.UShr: operation = MM.UShr; goto _doBitArith;

					_doBitArith:
						getRS();
						getRT();

						if(RS.isInt() && RT.isInt())
						{
							switch(operation)
							{
								case MM.And:  getRD().value = RS.asInt() & RT.asInt(); break;
								case MM.Or:   getRD().value = RS.asInt() | RT.asInt(); break;
								case MM.Xor:  getRD().value = RS.asInt() ^ RT.asInt(); break;
								case MM.Shl:  getRD().value = RS.asInt() << RT.asInt(); break;
								case MM.Shr:  getRD().value = RS.asInt() >> RT.asInt(); break;
								case MM.UShr: getRD().value = RS.asInt() >>> RT.asInt(); break;
							}
						}
						else
						{
							MDValue* method = getMM(RS, operation);
				
							if(!method.isFunction())
								throwRuntimeException("Cannot perform bitwise arithmetic on a '%s' and a '%s'", RS.typeString(), RT.typeString());
				
							uint funcSlot = push(method);
							push(RS);
							push(RT);
							call(funcSlot, 2, 1);
							getRD().value = *getBasedStack(funcSlot);
						}
						break;

					// Unary Bitwise
					case Op.Com:
						getRS();

						if(RS.isInt())
							getRD().value = ~RS.asInt();
						else
						{
							MDValue* method = getMM(RS, MM.Com);

							if(!method.isFunction())
								throwRuntimeException("Cannot perform complement on a '%s'", RS.typeString());

							uint funcSlot = push(method);
							push(RS);
							call(funcSlot, 1, 1);
							getRD().value = *getBasedStack(funcSlot);
						}
						break;
						
					// Reflexive Bitwise
					case Op.AndEq:  operation = MM.AndEq;  goto _doReflexiveBitArith;
					case Op.OrEq:   operation = MM.OrEq;   goto _doReflexiveBitArith;
					case Op.XorEq:  operation = MM.XorEq;  goto _doReflexiveBitArith;
					case Op.ShlEq:  operation = MM.ShlEq;  goto _doReflexiveBitArith;
					case Op.ShrEq:  operation = MM.ShrEq;  goto _doReflexiveBitArith;
					case Op.UShrEq: operation = MM.UShrEq; goto _doReflexiveBitArith;
					
					_doReflexiveBitArith:
						MDValue* RD = getRD();
						getRS();

						if(RD.isInt() && RS.isInt())
						{
							switch(operation)
							{
								case MM.AndEq:  RD.value = RD.asInt() & RS.asInt(); break;
								case MM.OrEq:   RD.value = RD.asInt() | RS.asInt(); break;
								case MM.XorEq:  RD.value = RD.asInt() ^ RS.asInt(); break;
								case MM.ShlEq:  RD.value = RD.asInt() << RS.asInt(); break;
								case MM.ShrEq:  RD.value = RD.asInt() >> RS.asInt(); break;
								case MM.UShrEq: RD.value = RD.asInt() >>> RS.asInt(); break;
							}
						}
						else
						{
							MDValue* method = getMM(*RD, operation);
				
							if(!method.isFunction())
								throwRuntimeException("Cannot perform bitwise arithmetic on a '%s' and a '%s'", RD.typeString(), RS.typeString());
				
							uint funcSlot = push(method);
							push(RD);
							push(RS);
							call(funcSlot, 2, 0);
						}
						break;


					// Data Transfer
					case Op.Move:
						getRS();
						getRD().value = RS;
						break;
						
					case Op.LoadBool:
						getRD().value = (i.rs == 1) ? true : false;
						break;
	
					case Op.LoadNull:
						getRD().setNull();
						break;
						
					case Op.LoadNulls:
						assert((i.rd & Instruction.locMask) == Instruction.locLocal, "execute Op.LoadNulls");

						for(int j = 0; j < i.imm; j++)
							getBasedStack(i.rd + j).setNull();
						break;
	
					case Op.NewGlobal:
						getRS();
						getRT();

						assert(RT.isString(), "trying to new a non-string global");

						MDNamespace env = mCurrentAR.env;
						MDValue* val = env[RT.asString()];

						if(val !is null)
							throwRuntimeException("Attempting to create global '%s' that already exists", RT.toString());

						env[RT.asString()] = RS;
						break;

					// Logical and Control Flow
					case Op.Not:
						getRS();

						if(RS.isFalse())
							getRD().value = true;
						else
							getRD().value = false;
	
						break;

					case Op.Cmp:
						getRS();
						getRT();

						Instruction jump = *mCurrentAR.pc;
						mCurrentAR.pc++;

						int cmpValue;

						if(RS.isNum() && RT.isNum())
						{
							if(RS.isFloat() || RT.isFloat())
							{
								float f1 = RS.asFloat();
								float f2 = RT.asFloat();
								
								if(f1 < f2)
									cmpValue = -1;
								else if(f1 > f2)
									cmpValue = 1;
								else
									cmpValue = 0;
							}
							else
								cmpValue = RS.asInt() - RT.asInt();
						}
						else if(RS.type == RT.type)
						{
							switch(RS.type)
							{
								case MDValue.Type.Null:
									cmpValue = 0;
									break;

								case MDValue.Type.Bool:
									cmpValue = (cast(int)RS.asBool() - cast(int)RT.asBool());
									break;

								case MDValue.Type.Char:
									cmpValue = RS.asChar() - RT.asChar();
									break;

								default:
									MDObject o1 = RS.asObj();
									MDObject o2 = RT.asObj();

									if(o1 is o2)
										cmpValue = 0;
									else
									{
										MDValue* method = getMM(RS, MM.Cmp);
										
										if(method.isFunction())
										{
											uint funcReg = push(method);
											push(RS);
											push(RT);
											call(funcReg, 2, 1);
											MDValue ret = pop();
											
											if(!ret.isInt())
												throwRuntimeException("opCmp is expected to return an int for type '%s'", RS.typeString());
												
											cmpValue = ret.asInt();
										}
										else
											cmpValue = MDObject.compare(o1, o2);
									}
									break;
							}
						}
						else
						{
							MDValue* method = getMM(RS, MM.Cmp);
							
							if(!method.isFunction())
								throwRuntimeException("invalid opCmp metamethod for type '%s'", RS.typeString());

							uint funcReg = push(method);
							push(RS);
							push(RT);
							call(funcReg, 2, 1);
							MDValue ret = pop();

							if(!ret.isInt())
								throwRuntimeException("opCmp is expected to return an int for type '%s'", RS.typeString());

							cmpValue = ret.asInt();
						}

						if(jump.rd == 1)
						{
							switch(jump.opcode)
							{
								case Op.Je:  if(cmpValue == 0) mCurrentAR.pc += jump.imm; break;
								case Op.Jle: if(cmpValue <= 0) mCurrentAR.pc += jump.imm; break;
								case Op.Jlt: if(cmpValue < 0)  mCurrentAR.pc += jump.imm; break;
								default: assert(false, "invalid 'cmp' jump");
							}
						}
						else
						{
							switch(jump.opcode)
							{
								case Op.Je:  if(cmpValue != 0) mCurrentAR.pc += jump.imm; break;
								case Op.Jle: if(cmpValue > 0)  mCurrentAR.pc += jump.imm; break;
								case Op.Jlt: if(cmpValue >= 0) mCurrentAR.pc += jump.imm; break;
								default: assert(false, "invalid 'cmp' jump");
							}
						}
	
						break;
	
					case Op.Is:
						getRS();
						getRT();

						Instruction jump = *mCurrentAR.pc;
						mCurrentAR.pc++;

						assert(jump.opcode == Op.Je, "invalid 'is' jump");

						bool cmpValue = RS.rawEquals(&RT);
	
						if(jump.rd == 1)
						{
							if(cmpValue is true)
								mCurrentAR.pc += jump.imm;
						}
						else
						{
							if(cmpValue is false)
								mCurrentAR.pc += jump.imm;
						}
	
						break;
	
					case Op.IsTrue:
						getRS();

						Instruction jump = *mCurrentAR.pc;
						mCurrentAR.pc++;
	
						assert(jump.opcode == Op.Je, "invalid 'istrue' jump");
	
						bool cmpValue = !RS.isFalse();

						if(jump.rd == 1)
						{
							if(cmpValue is true)
								mCurrentAR.pc += jump.imm;
						}
						else
						{
							if(cmpValue is false)
								mCurrentAR.pc += jump.imm;
						}
	
						break;
	
					case Op.Jmp:
						if(i.rd != 0)
							mCurrentAR.pc += i.imm;
						break;
						
					case Op.SwitchInt:
						getRS();

						int value;
						int offset;

						if(RS.isInt() == false)
						{
							if(RS.isChar() == false)
								throwRuntimeException("Attempting to perform an integral switch on a value of type '%s'", RS.typeString());
							
							value = cast(int)RS.asChar();
						}
						else
							value = RS.asInt();

						auto t = &mCurrentAR.func.script.func.mSwitchTables[i.rt];
				
						assert(t.isString == false, "int switch on a string table");
				
						int* ptr = (value in t.intOffsets);
				
						if(ptr is null)
							offset = t.defaultOffset;
						else
							offset = *ptr;

						if(offset == -1)
							throwRuntimeException("Switch without default");

						mCurrentAR.pc += offset;
						break;
	
					case Op.SwitchString:
						getRS();

						int offset;
						
						if(RS.isString() == false)
							throwRuntimeException("Attempting to perform a string switch on a value of type '%s'", RS.typeString());

						auto t = &mCurrentAR.func.script.func.mSwitchTables[i.rt];
				
						assert(t.isString == true, "string switch on an int table");
				
						int* ptr = (RS.asString().mData in t.stringOffsets);
				
						if(ptr is null)
							offset = t.defaultOffset;
						else
							offset = *ptr;

						if(offset == -1)
							throwRuntimeException("Switch without default");
	
						mCurrentAR.pc += offset;
						break;
						
					case Op.Close:
						close(i.rd);
						break;

					case Op.Foreach:
						Instruction jump = *mCurrentAR.pc;
						mCurrentAR.pc++;
	
						uint rd = i.rd;
						uint funcReg = rd + 3;
						MDValue src = *getBasedStack(rd);

						if(!src.isFunction())
						{
							MDValue* apply = getMM(src, MM.Apply);

							if(!apply.isFunction())
								throwRuntimeException("No implementation of %s for type '%s'", MetaStrings[MM.Apply], src.typeString());

							copyBasedStack(rd + 2, rd + 1);
							getBasedStack(rd + 1).value = src;
							getBasedStack(rd).value = *apply;

							call(rd, 2, 3);
						}

						copyBasedStack(funcReg + 2, rd + 2);
						copyBasedStack(funcReg + 1, rd + 1);
						copyBasedStack(funcReg, rd);

						call(funcReg, 2, i.imm);

						if(getBasedStack(funcReg).isNull() == false)
						{
							copyBasedStack(rd + 2, funcReg);

							assert(jump.opcode == Op.Je && jump.rd == 1, "invalid 'foreach' jump " ~ jump.toString());
	
							mCurrentAR.pc += jump.imm;
						}
	
						break;
						
					// Exception Handling
					case Op.PushCatch:
						pushTR();
						
						mCurrentTR.isCatch = true;
						mCurrentTR.catchVarSlot = i.rd;
						mCurrentTR.pc = mCurrentAR.pc + i.imm;
						break;

					case Op.PushFinally:
						pushTR();
						
						mCurrentTR.isCatch = false;
						mCurrentTR.pc = mCurrentAR.pc + i.imm;
						break;
						
					case Op.PopCatch:
						assert(mCurrentTR.isCatch, "'catch' popped out of order");

						popTR();
						break;
	
					case Op.PopFinally:
						assert(!mCurrentTR.isCatch, "'finally' popped out of order");

						currentException = null;

						popTR();
						break;
	
					case Op.EndFinal:
						if(currentException !is null)
							throw currentException;
						
						break;
	
					case Op.Throw:
						getRS();
						throwRuntimeException(RS);

					// Function Calling
					{
						Instruction call;

					case Op.Method:
						getRS();

						call = *mCurrentAR.pc;
						mCurrentAR.pc++;

						MDString methodName = getConst(i.rt).asString();

						getBasedStack(i.rd + 1).value = RS;
						getBasedStack(i.rd).value = *lookupMethod(&RS, methodName);

						assert(i.rd == call.rd, "Op.Method");
						
						if(call.opcode == Op.Call)
						{
							int funcReg = call.rd;
							int numParams = call.rs - 1;
							int numResults = call.rt - 1;
	
							if(numParams == -1)
								numParams = getBasedStackIndex() - funcReg - 1;
	
							if(callPrologue(funcReg, numResults, numParams) == true)
								depth++;
						}
						else
						{
							assert(call.opcode == Op.Tailcall, "Op.Method invalid call opcode");
							goto _doTailcall;
						}
						break;

					case Op.Precall:
						if(i.rt == 1)
						{
							getRSwithEnv();
							getBasedStack(i.rd + 1).value = RSEnv;
						}
						else
							getRS();

						call = *mCurrentAR.pc;
						mCurrentAR.pc++;

						if(i.rd != i.rs)
							getBasedStack(i.rd).value = RS;

						if(call.opcode == Op.Call)
						{
							int funcReg = call.rd;
							int numParams = call.rs - 1;
							int numResults = call.rt - 1;
	
							if(numParams == -1)
								numParams = getBasedStackIndex() - funcReg - 1;

							if(callPrologue(funcReg, numResults, numParams) == true)
								depth++;
								
							break;
						}
						else
							assert(call.opcode == Op.Tailcall, "Op.Precall invalid call opcode");

					_doTailcall:
						close(0);

						int funcReg = call.rd;
						int numParams = call.rs - 1;

						if(numParams == -1)
							numParams = getBasedStackIndex() - funcReg - 1;

						funcReg = basedIndexToAbs(funcReg);

						int destReg = mCurrentAR.funcSlot;

						for(int j = 0; j < numParams + 1; j++)
							copyAbsStack(destReg + j, funcReg + j);

						int numReturns = mCurrentAR.numReturns;

						popAR();

						if(callPrologue(absIndexToBased(destReg), numReturns, numParams) == false)
							--depth;

						if(depth == 0)
							return;

						break;
					}

					case Op.Ret:
						int numResults = i.imm - 1;

						close(0);
						callEpilogue(i.rd, numResults);
						
						--depth;
						
						if(depth == 0)
							return;

						break;
						
					case Op.Vararg:
						int numNeeded = i.imm - 1;
						int numVarargs = getNumVarargs();
	
						if(numNeeded == -1)
							numNeeded = numVarargs;

						needStackSlots(numNeeded);

						uint src = mCurrentAR.vargBase;
						uint dest = basedIndexToAbs(i.rd);

						for(uint index = 0; index < numNeeded; index++)
						{
							if(index < numVarargs)
								copyAbsStack(dest + index, src);
							else
								getAbsStack(dest + index).setNull();
	
							src++;
						}
						
						mStackIndex = dest + numNeeded;
						break;

					// Array and List Operations
					case Op.Length:
						getRS();

						switch(RS.type)
						{
							case MDValue.Type.String:
								getRD().value = cast(int)RS.asString().length;
								break;
								
							case MDValue.Type.Array:
								getRD().value = cast(int)RS.asArray().length;
								break;
								
							default:
								MDValue* method = getMM(RS, MM.Length);
						
								if(method.isFunction())
								{
									
									uint funcReg = push(method);
									push(RS);
									call(funcReg, 1, 1);
									getRD().value = *getBasedStack(funcReg);
								}
								else
									getRD().value = cast(int)RS.length;
									
								break;
						}

						break;

					case Op.SetArray:
						// Since this instruction is only generated for array constructors,
						// there is really no reason to check for type correctness for the dest.
	
						// sliceStack resets the top-of-stack.
	
						uint sliceBegin = mCurrentAR.base + i.rd + 1;
						int numElems = i.rs - 1;

						getBasedStack(i.rd).asArray().setBlock(i.rt, sliceStack(sliceBegin, numElems));
	
						break;

					case Op.Cat:
						MDValue* src1 = getBasedStack(i.rs);

						if(src1.isArray())
						{
							getRD().value = MDArray.concat(sliceStack(mCurrentAR.base + i.rs, i.rt - 1));
							break;
						}

						if(src1.isString() || src1.isChar())
						{
							uint badIndex;
							MDString newStr = MDString.concat(sliceStack(mCurrentAR.base + i.rs, i.rt - 1), badIndex);

							if(newStr is null)
								throwRuntimeException("Cannot list concatenate a 'string' and a '%s'",
									getBasedStack(i.rs + badIndex).typeString());
									
							getRD().value = newStr;
							break;
						}

						MDValue* method = getMM(*src1, MM.Cat);

						if(!method.isFunction())
							throwRuntimeException("Cannot list concatenate a '%s'", src1.typeString());

						uint firstItem = basedIndexToAbs(i.rs);
						uint lastItem;
						int numItems = i.rt - 1;

						if(numItems == -1)
						{
							lastItem = mStackIndex - 1;
							numItems = lastItem - firstItem + 1;
						}
						else
							lastItem = firstItem + numItems - 1;

						uint funcSlot = push(method);

						for(int j = firstItem; j <= lastItem; j++)
							push(getAbsStack(j));

						call(funcSlot, numItems, 1);
						getRD().value = *getBasedStack(funcSlot);
						break;

					case Op.CatEq:
						MDValue* RD = getRD();
						getRS();

						if(RD.isArray())
						{
							if(RS.isArray())
								RD.asArray() ~= RS.asArray();
							else
								RD.asArray() ~= RS;

							break;
						}
						else if(RD.isString())
						{
							if(RS.isString())
							{
								RD.value = RD.asString() ~ RS.asString();
								break;
							}
							else if(RS.isChar())
							{
								RD.value = RD.asString() ~ RS.asChar();
								break;
							}
						}
						else if(RD.isChar())
						{
							if(RS.isString())
							{
								RD.value = RD.asChar() ~ RS.asString();
								break;
							}
							else if(RS.isChar())
							{
								dchar[2] data;
								data[0] = RD.asChar();
								data[1] = RS.asChar();

								RD.value = data;
								
								break;
							}
						}

						MDValue* method = getMM(*RD, MM.CatEq);

						if(!method.isFunction())
							throwRuntimeException("Cannot concatenate a '%s' and a '%s'", RD.typeString(), RS.typeString());

						uint funcSlot = push(method);
						push(RD);
						push(RS);
						call(funcSlot, 2, 0);
						break;

					case Op.Index:
						getRS();
						getRT();
						MDValue dest;

						getRD().value = index(RS, RT);
						break;

					case Op.IndexAssign:
						getRS();
						getRT();

						indexAssign(*getRD(), RS, RT);
						break;
						
					case Op.Slice:
						getRD().value = slice(*getBasedStack(i.rs), *getBasedStack(i.rs + 1), *getBasedStack(i.rs + 2));;
						break;

					case Op.SliceAssign:
						getRS();
						sliceAssign(*getBasedStack(i.rd), *getBasedStack(i.rd + 1), *getBasedStack(i.rd + 2), RS);
						break;
						
					case Op.NotIn:
					case Op.In:
						bool truth = true;
						
						if(opcode == Op.NotIn)
							truth = false;

						getRS();
						getRT();
						
						switch(RT.type)
						{
							case MDValue.Type.String:
								if(RS.isChar() == false)
									throwRuntimeException("Can only use characters to look in strings, not '%s'", RS.typeString());

								getRD().value = ((RS.asChar() in RT.asString()) >= 0) ? truth : !truth;
								break;

							case MDValue.Type.Array:
								getRD().value = ((RS in RT.asArray()) >= 0) ? truth : !truth;
								break;

							case MDValue.Type.Table:
								getRD().value = (RS in RT.asTable()) ? truth : !truth;
								break;

							case MDValue.Type.Namespace:
								if(RS.isString() == false)
									throwRuntimeException("Attempting to access namespace '%s' with type '%s'", RT.asNamespace().nameString(), RS.typeString());

								getRD().value = (RS.asString() in RT.asNamespace()) ? truth : !truth;
								break;
								
							default:
								MDValue* method = getMM(RT, MM.In);

								if(method.isNull())
									throwRuntimeException("No %s metamethod for type '%s'", MetaNames[MM.In], RT.typeString());

								if(method.isFunction() == false)
									throwRuntimeException("Invalid %s metamethod for type '%s'", MetaNames[MM.In], RT.typeString());

								uint funcSlot = push(method);
								push(RT);
								push(RS);
								call(funcSlot, 2, 1);

								getRD().value = (getBasedStack(funcSlot).isFalse()) ? !truth : truth;
						}
						break;

					// Value Creation
					case Op.NewArray:
						getBasedStack(i.rd).value = new MDArray(i.imm);
						break;

					case Op.NewTable:
						getBasedStack(i.rd).value = new MDTable();
						break;

					case Op.Closure:
						MDFuncDef newDef = getInnerFunc(i.imm);
						MDClosure n = new MDClosure(mCurrentAR.env, newDef);
	
						for(int index = 0; index < newDef.mNumUpvals; index++)
						{
							assert(mCurrentAR.pc.opcode == Op.Move, "invalid closure upvalue op");

							if(mCurrentAR.pc.rd == 0)
								n.script.upvals[index] = findUpvalue(mCurrentAR.pc.rs);
							else
							{
								assert(mCurrentAR.pc.rd == 1, "invalid closure upvalue rd");
								n.script.upvals[index] = getUpvalueRef(mCurrentAR.pc.imm);
							}
	
							mCurrentAR.pc++;
						}

						getRD().value = n;
						break;

					case Op.Class:
						getRS();
						getRT();

						if(RT.isNull())
							getRD().value = new MDClass(RS.asString.asUTF32(), null);
						else if(!RT.isClass())
							throwRuntimeException("Attempted to derive a class from a value of type '%s'", RT.typeString());
						else
							getRD().value = new MDClass(RS.asString.asUTF32(), RT.asClass());

						break;
						
					// As
					case Op.As:
						getRS();
						getRT();

						if(!RS.isInstance() || !RT.isClass())
							throwRuntimeException("Attempted to perform 'as' on '%s' and '%s'; must be 'instance' and 'class'",
								RS.typeString(), RT.typeString());

						if(RS.asInstance().castToClass(RT.asClass()))
							getRD().value = RS;
						else
							getRD().setNull();

						break;
						
					case Op.Je:
					case Op.Jle:
					case Op.Jlt:
						assert(false, "lone conditional jump instruction");
						
					case Op.Call:
						assert(false, "lone call instruction");
						
					case Op.Tailcall:
						assert(false, "lone tailcall instruction");

					default:
						throwRuntimeException("Unimplemented opcode \"%s\"", i.toString());
				}
			}
		}
		catch(MDException e)
		{
			while(depth > 0)
			{
				mTraceback ~= getDebugLocation();

				while(mCurrentTR.actRecord is mARIndex)
				{
					TryRecord tr = *mCurrentTR;
					popTR();

					if(tr.isCatch)
					{
						getBasedStack(tr.catchVarSlot).value = e.value;

						for(int i = basedIndexToAbs(tr.catchVarSlot + 1); i < mStackIndex; i++)
							getAbsStack(i).setNull();

						currentException = null;

						mCurrentAR.pc = tr.pc;
						goto _exceptionRetry;
					}
					else
					{
						currentException = e;
						
						mCurrentAR.pc = tr.pc;
						goto _exceptionRetry;
					}
				}

				depth--;
				callEpilogue(0, 0);
			}

			throw e;
		}
	}
}