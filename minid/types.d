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
		value = new MDString(msg);
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

align(1) struct MDValue
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
		Class,
		Instance,
		Namespace,
		Thread
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
		private mdfloat mFloat;
		private dchar mChar;

		// Object types
		private MDObject mObj;
		private MDString mString;
		private MDTable mTable;
		private MDArray mArray;
		private MDClosure mFunction;
		private MDClass mClass;
		private MDInstance mInstance;
		private MDNamespace mNamespace;
		private MDState mThread;
	}
	
	public static MDValue opCall(T)(T value)
	{
		MDValue ret;
		ret = value;
		return ret;
	}

	public int opEquals(MDValue* other)
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
		if(mType != other.mType)
			return (cast(int)mType - cast(int)other.mType);

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

		assert(false);
	}

	public int compare(MDValue* other)
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
					mdfloat val = mInt;

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
					mdfloat val = other.mInt;
					
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
			case Type.Class:     return "class"d;
			case Type.Instance:  return "instance"d;
			case Type.Namespace: return "namespace"d;
			case Type.Thread:    return "thread"d;
		}
	}

	public dchar[] typeString()
	{
		if(mType == Type.Class)
			return "class " ~ mClass.mGuessedName;
		else if(mType == Type.Instance)
			return "instance of class " ~ mInstance.mClass.mGuessedName;
		else
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
		return (mType == Type.Int) || (mType == Type.Float);
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
	
	public bool isObj()
	{
		return (cast(uint)mType >= Type.String);	
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
	
	public bool isClass()
	{
		return (mType == Type.Class);
	}

	public bool isInstance()
	{
		return (mType == Type.Instance);
	}

	public bool isNamespace()
	{
		return (mType == Type.Namespace);
	}
	
	public bool isThread()
	{
		return (mType == Type.Thread);
	}

	public bool isFalse()
	{
		return (mType == Type.Null) || (mType == Type.Bool && mBool == false) ||
			(mType == Type.Int && mInt == 0) || (mType == Type.Float && mFloat == 0.0);
	}
	
	public bool isTrue()
	{
		return !isFalse();
	}

	public T as(T)()
	{
		static if(is(T == bool))
		{
			assert(mType == Type.Bool, "MDValue as " ~ T.stringof);
			return mBool;
		}
		else static if(isIntType!(T))
		{
			if(mType == Type.Int)
				return mInt;
			else if(mType == Type.Float)
				return cast(T)mFloat;
			else
				assert(false, "MDValue as " ~ T.stringof);
		}
		else static if(isFloatType!(T))
		{
			if(mType == Type.Int)
				return cast(T)mInt;
			else if(mType == Type.Float)
				return mFloat;
			else
				assert(false, "MDValue as " ~ T.stringof);
		}
		else static if(isCharType!(T))
		{
			assert(mType == Type.Char, "MDValue as " ~ T.stringof);
			return mChar;
		}
		else static if(isStringType!(T))
		{
			assert(mType == Type.String, "MDValue as " ~ T.stringof);

			static if(is(T == char[]))
				return mString.asUTF8();
			else static if(is(T == wchar[]))
				return mString.asUTF16();
			else
				return mString.asUTF32();
		}
		else static if(is(T : MDString))
		{
			assert(mType == Type.String, "MDValue as " ~ T.stringof);
			return mString;
		}
		else static if(is(T : MDTable))
		{
			assert(mType == Type.Table, "MDValue as " ~ T.stringof);
			return mTable;
		}
		else static if(is(T : MDArray))
		{
			assert(mType == Type.Array, "MDValue as " ~ T.stringof);
			return mArray;
		}
		else static if(is(T : MDClosure))
		{
			assert(mType == Type.Function, "MDValue as " ~ T.stringof);
			return mFunction;
		}
		else static if(is(T : MDClass))
		{
			assert(mType == Type.Class, "MDValue as " ~ T.stringof);
			return mClass;
		}
		else static if(is(T : MDInstance))
		{
			assert(mType == Type.Instance, "MDValue as " ~ T.stringof);

			static if(is(T == MDInstance))
				T ret = mInstance;
			else
			{
				T ret = cast(T)mInstance;

				if(ret is null)
					throw new MDException("Cannot convert '%s' to " ~ T.stringof, mInstance.classinfo.name);
			}

			return ret;
		}
		else static if(is(T : MDNamespace))
		{
			assert(mType == Type.Namespace, "MDValue as " ~ T.stringof);
			return mNamespace;
		}
		else static if(is(T : MDState))
		{
			assert(mType == Type.Thread, "MDValue as " ~ T.stringof);
			return mThread;
		}
		else static if(is(T : MDObject))
		{
			assert(cast(uint)mType >= cast(uint)Type.String, "MDValue as " ~ T.stringof);
			return mObj;
		}
		else
		{
			// I do this because static assert won't show the template instantiation "call stack."
			pragma(msg, "MDValue.as() - Invalid argument type '" ~ T.stringof ~ "'");
			ARGUMENT_ERROR(T);
		}
	}
	
	public T to(T)()
	{
		static if(is(T == bool))
		{
			if(mType != Type.Bool)
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());

			return mBool;
		}
		else static if(isIntType!(T))
		{
			if(mType == Type.Int)
				return mInt;
			else if(mType == Type.Float)
				return cast(T)mFloat;
			else
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());
		}
		else static if(isFloatType!(T))
		{
			if(mType == Type.Int)
				return cast(T)mInt;
			else if(mType == Type.Float)
				return mFloat;
			else
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());
		}
		else static if(isCharType!(T))
		{
			if(mType != Type.Char)
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());

			return mChar;
		}
		else static if(isStringType!(T))
		{
			if(mType != Type.String)
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());

			static if(is(T == char[]))
				return mString.asUTF8();
			else static if(is(T == wchar[]))
				return mString.asUTF16();
			else
				return mString.asUTF32();
		}
		else static if(is(T : MDString))
		{
			if(mType != Type.String)
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());
				
			return mString;
		}
		else static if(is(T : MDTable))
		{
			if(mType != Type.Table)
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());
				
			return mTable;
		}
		else static if(is(T : MDArray))
		{
			if(mType != Type.Array)
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());
				
			return mArray;
		}
		else static if(is(T : MDClosure))
		{
			if(mType != Type.Function)
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());

			return mFunction;
		}
		else static if(is(T : MDClass))
		{
			if(mType != Type.Class)
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());
				
			return mClass;
		}
		else static if(is(T : MDInstance))
		{
			if(mType != Type.Instance)
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());
				
			static if(is(T == MDInstance))
				T ret = mInstance;
			else
			{
				T ret = cast(T)mInstance;
	
				if(ret is null)
					throw new MDException("Cannot convert '%s' to " ~ T.stringof, mInstance.classinfo.name);
			}
			
			return ret;
		}
		else static if(is(T : MDNamespace))
		{
			if(mType != Type.Namespace)
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());

			return mNamespace;
		}
		else static if(is(T : MDState))
		{
			if(mType != Type.Thread)
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());

			return mThread;
		}
		else static if(is(T : MDObject))
		{
			if(cast(uint)mType < cast(uint)Type.String)
				throw new MDException("Cannot convert '%s' to " ~ T.stringof, typeString());

			return mObj;
		}
		else
		{
			// I do this because static assert won't show the template instantiation "call stack."
			pragma(msg, "MDValue.to() - Invalid argument type '" ~ T.stringof ~ "'");
			ARGUMENT_ERROR(T);
		}
	}

	public void setNull()
	{
		mType = Type.Null;
		mInt = 0;
	}

	public void opAssign(T)(T src)
	{
		static if(is(T == bool))
		{
			mType = Type.Bool;
			mBool = src;
		}
		else static if(isIntType!(T))
		{
			mType = Type.Int;
			mInt = cast(int)src;
		}
		else static if(isFloatType!(T))
		{
			mType = Type.Float;
			mFloat = cast(mdfloat)src;
		}
		else static if(isCharType!(T))
		{
			mType = Type.Char;
			mChar = cast(dchar)src;
		}
		else static if(isStringType!(T))
		{
			mType = Type.String;
			mString = new MDString(src);
		}
		else static if(is(T : MDString))
		{
			mType = Type.String;
			mString = src;	
		}
		else static if(is(T : MDTable))
		{
			mType = src.mType;
			mTable = src;
		}
		else static if(is(T : MDArray))
		{
			mType = Type.Array;
			mArray = src;
		}
		else static if(is(T : MDClosure))
		{
			mType = Type.Function;
			mFunction = src;
		}
		else static if(is(T : MDClass))
		{
			mType = Type.Class;
			mClass = src;
		}
		else static if(is(T : MDInstance))
		{
			mType = Type.Instance;
			mInstance = src;
		}
		else static if(is(T : MDNamespace))
		{
			mType = Type.Namespace;
			mNamespace = src;
		}
		else static if(is(T : MDState))
		{
			mType = Type.Thread;
			mThread = src;
		}
		else static if(is(T : MDObject))
		{
			mType = src.mType;
			mObj = src;
		}
		else static if(is(T : MDValue*))
		{
			*this = *src;
		}
		else static if(is(T == void*))
		{
			assert(src is null, "MDValue.opAssign() - can only assign 'null' to MDValues");
			setNull();
		}
		else static if(isArrayType!(T))
		{
			mType = Type.Array;
			mArray = MDArray.fromArray(src);
		}
		else
		{
			// I do this because static assert won't show the template instantiation "call stack."
			pragma(msg, "MDValue.opAssign() - Invalid argument type '" ~ T.stringof ~ "'");
			ARGUMENT_ERROR(T);
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
				Serialize(s, mString.mData);
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
				ret.mString = new MDString(data);
				break;
				
			default:
				assert(false, "MDValue.deserialize()");
		}
		
		return ret;
	}
}

abstract class MDObject
{
	public MDValue.Type mType;

	public uint length();

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
		
		if(mHash != other.mHash)
			return false;

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
		ret.mData = mData[lo .. hi];
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

	// Returns null on failure, so that the VM can give an error at the appropriate location
	public static MDString concat(MDValue[] values, out uint badIndex)
	{
		uint l = 0;

		for(uint i = 0; i < values.length; i++)
		{
			if(values[i].isString())
				l += values[i].as!(MDString).length;
			else if(values[i].isChar())
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
				MDString s = v.as!(MDString);
				result[i .. i + s.length] = s.mData[];
				i += s.length;
			}
			else
			{
				result[i] = v.as!(dchar);
				i++;
			}
		}
		
		return new MDString(result);
	}
	
	public static MDString concatEq(MDValue dest, MDValue[] values, out uint badIndex)
	{
		MDString ret = concat(dest ~ values, badIndex);

		if(ret is null)
			badIndex--;

		return ret;
	}

	public char[] toString()
	{
		return asUTF8();
	}
}

class MDClosure : MDObject
{
	protected bool mIsNative;
	protected MDNamespace mEnvironment;

	struct NativeClosure
	{
		int function(MDState, uint) func;
		int delegate(MDState, uint) dg;
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
	
	public this(MDNamespace environment, int delegate(MDState, uint) dg, dchar[] name, MDValue[] upvals = null)
	{
		mIsNative = true;
		mEnvironment = environment;
		native.func = null;
		native.dg = dg;
		native.name = name;
		native.upvals = upvals.dup;
		mType = MDValue.Type.Function;
	}
	
	public this(MDNamespace environment, int function(MDState, uint) func, dchar[] name, MDValue[] upvals = null)
	{
		mIsNative = true;
		mEnvironment = environment;
		native.func = func;
		native.dg = &callFunc;
		native.name = name;
		native.upvals = upvals.dup;
		mType = MDValue.Type.Function;
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
	
	protected int callFunc(MDState s, uint numParams)
	{
		return native.func(s, numParams);
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
			INVALID_NUM_ARGS();
		}

		MDTable ret = new MDTable();
		
		foreach(i, arg; args)
			static if(!(i & 1))
				ret[MDValue(arg)] = MDValue(args[i + 1]);

		return ret;
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
	
	public void remove(ref MDValue index)
	{
		MDValue* ptr = (index in mData);

		if(ptr is null)
			return;

		mData.remove(index);
	}
	
	public MDValue* opIn_r(ref MDValue index)
	{
		return (index in mData);
	}

	public MDValue* opIndex(ref MDValue index)
	{
		if(index.isNull())
			throw new MDException("Cannot index a table with null");

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

	public void opIndexAssign(ref MDValue value, ref MDValue index)
	{
		if(index.isNull())
			throw new MDException("Cannot index assign a table with null");

		if(value.isNull())
			mData.remove(index);
		else
			mData[index] = value;
	}

	public void opIndexAssign(ref MDValue value, dchar[] index)
	{
		opIndexAssign(value, MDValue(index));
	}
	
	public void opIndexAssign(MDObject value, ref MDValue index)
	{
		opIndexAssign(MDValue(value), index);
	}
	
	public void opIndexAssign(MDObject value, dchar[] index)
	{
		opIndexAssign(MDValue(value), MDValue(index));
	}

	public int opApply(int delegate(ref MDValue key, ref MDValue value) dg)
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

	public static MDArray create(T...)(T args)
	{
		MDArray ret = new MDArray(args.length);

		foreach(i, arg; args)
			ret.mData[i] = arg;

		return ret;
	}

	public static MDArray fromArray(T)(T[] array)
	{
		MDArray ret = new MDArray(array.length);
		
		static if(is(T == MDValue))
			ret.mData[] = array[];
		else
		{
			foreach(i, val; array)
				ret.mData[i] = val;
		}

		return ret;	
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
	
	public int opCmp(Object o)
	{
		auto other = cast(MDArray)o;
		assert(other !is null, "MDArray opCmp");
		
		auto len = mData.length;
		int result;
	
		if(other.mData.length < len)
			len = other.mData.length;

		result = memcmp(mData.ptr, other.mData.ptr, len * MDValue.sizeof);
	
		if(result == 0)
			result = cast(int)mData.length - cast(int)other.mData.length;

		return result;
	}
	
	public int opEquals(Object o)
	{
		auto other = cast(MDArray)o;
		assert(other !is null, "MDArray opCmp");
		
		return mData == other.mData;
	}
	
	public int opIn_r(ref MDValue v)
	{
		foreach(i, ref val; mData)
			if(val.opEquals(&v))
				return i;
				
		return -1;
	}

	public int opApply(int delegate(ref uint index, ref MDValue value) dg)
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
	
	public MDArray opCat(ref MDValue elem)
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
	
	public MDArray opCatAssign(ref MDValue elem)
	{
		mData ~= elem;
		return this;
	}
	
	public MDValue* opIndex(int index)
	{
		return &mData[index];
	}
	
	public void opIndexAssign(ref MDValue value, uint index)
	{
		mData[index] = value;
	}
	
	public void opIndexAssign(MDObject value, uint index)
	{
		mData[index] = value;
	}
	
	public MDArray opSlice(uint lo, uint hi)
	{
		return new MDArray(mData[lo .. hi]);
	}
	
	public void opSliceAssign(ref MDValue value, uint lo, uint hi)
	{
		mData[lo .. hi] = value;
	}
	
	public void opSliceAssign(MDArray arr, uint lo, uint hi)
	{
		mData[lo .. hi] = arr.mData[];
	}
	
	public void opSliceAssign(ref MDValue value)
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
				l += v.as!(MDArray).length;
			else
				l += 1;
		}
		
		MDArray result = new MDArray(l);
		
		uint i = 0;
		
		foreach(MDValue v; values)
		{
			if(v.isArray())
			{
				MDArray a = v.as!(MDArray);
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
	
	public static void concatEq(MDArray dest, MDValue[] values)
	{
		uint l = 0;

		foreach(uint i, MDValue v; values)
		{
			if(v.isArray())
				l += v.as!(MDArray).length;
			else
				l += 1;
		}

		uint i = dest.mData.length;
		dest.mData.length = dest.mData.length + l;

		foreach(MDValue v; values)
		{
			if(v.isArray())
			{
				MDArray a = v.as!(MDArray);
				dest.mData[i .. i + a.length] = a.mData[];
				i += a.length;
			}
			else
			{
				dest.mData[i] = v;
				i++;
			}
		}
	}
}

class MDClass : MDObject
{
	protected dchar[] mGuessedName;
	protected MDClass mBaseClass;
	protected MDNamespace mFields;
	protected MDNamespace mMethods;

	protected static MDString CtorString;
	
	static this()
	{
		CtorString = new MDString("constructor"d);
	}

	public this(dchar[] guessedName, MDClass baseClass)
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
		}
	}

	public override uint length()
	{
		throw new MDException("Cannot get the length of a class");
	}
	
	public MDValue superClass()
	{
		if(mBaseClass is null)
			return MDValue.nullValue;
		else
			return MDValue(mBaseClass);
	}

	public MDInstance newInstance()
	{
		return new MDInstance(this);
	}

	public MDValue* opIndex(MDString index)
	{
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

	public void opIndexAssign(ref MDValue value, MDString index)
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

	public void opIndexAssign(ref MDValue value, dchar[] index)
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
	
	public void opIndexAssign(ref MDValue value, MDString index)
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

	public void opIndexAssign(ref MDValue value, dchar[] index)
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

class MDNamespace : MDObject
{
	version(MDExperimentalNamespaces)
	{
		struct Slot
		{
			MDString key;
			MDValue value;
			Slot* next;
		}
	
		protected Slot[] mSlots;
		protected size_t mLength;
		protected size_t mColSlot;
	}
	else
		protected MDValue[MDString] mData;

	protected MDNamespace mParent;
	protected dchar[] mName;

	public this(dchar[] name = null, MDNamespace parent = null)
	{
		version(MDExperimentalNamespaces)
			mSlots = new Slot[32];

		mName = name;
		mParent = parent;
		mType = MDValue.Type.Namespace;
	}

	version(MDExperimentalNamespaces)
	{
		private this(Slot[] slots)
		{
			mSlots = slots;
		}
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
				static if(isStringType!(typeof(arg)))
					this[new MDString(arg)] = MDValue(args[i + 1]);
				else static if(is(typeof(arg) : MDString))
					this[arg] = MDValue(args[i + 1]);
				else
				{
					pragma(msg, "Native namespace constructor keys must be strings");
					static assert(false);
				}
			}
		}
	}

	public override uint length()
	{
		version(MDExperimentalNamespaces)
			return mLength;
		else
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

	public MDValue* opIn_r(MDString key)
	{
		version(MDExperimentalNamespaces)
		{
			Slot* slot = lookup(key);
			
			if(slot is null)
				return null;
	
			return &slot.value;
		}
		else
			return key in mData;
	}
	
	public MDValue* opIn_r(dchar[] key)
	{
		scope idx = MDString.newTemp(key);

		version(MDExperimentalNamespaces)
		{
			Slot* slot = lookup(idx);
			
			if(slot is null)
				return null;
	
			return &slot.value;
		}
		else
			return idx in mData;
	}

	public MDNamespace dup()
	{
		version(MDExperimentalNamespaces)
		{
			MDNamespace n = new MDNamespace(mSlots.dup);
			n.mName = mName;
			n.mParent = mParent;
			n.mLength = mLength;
			n.mColSlot = mColSlot;
			
			Slot* oldBase = mSlots.ptr;
			Slot* newBase = n.mSlots.ptr;
			
			foreach(ref slot; n.mSlots)
			{
				if(slot.next !is null)
					slot.next = (slot.next - oldBase) + newBase;
			}
	
			return n;
		}
		else
		{
			MDNamespace n = new MDNamespace(mName, mParent);
			
			foreach(k, v; mData)
				n[k] = v;
				
			return n;
		}
	}
	
	public MDArray keys()
	{
		version(MDExperimentalNamespaces)
		{
			MDArray ret = new MDArray(mLength);
			int i = 0;
	
			foreach(ref v; mSlots)
			{
				if(v.key is null)
					continue;
					
				ret[i] = v.key;
				i++;
			}
	
			return ret;
		}
		else
			return MDArray.fromArray(mData.keys);
	}

	public MDArray values()
	{
		version(MDExperimentalNamespaces)
		{
			MDArray ret = new MDArray(mLength);
			int i = 0;
	
			foreach(ref v; mSlots)
			{
				if(v.key is null)
					continue;
					
				ret[i] = v.value;
				i++;
			}
	
			return ret;
		}
		else
			return new MDArray(mData.values);
	}

	public MDValue* opIndex(MDString key)
	{
		version(MDExperimentalNamespaces)
		{
			Slot* slot = lookup(key);
			
			if(slot is null)
				return null;
	
			return &slot.value;
		}
		else
			return key in mData;
	}

	public MDValue* opIndex(dchar[] key)
	{
		scope str = MDString.newTemp(key);
		
		version(MDExperimentalNamespaces)
		{
			Slot* slot = lookup(str);
	
			if(slot is null)
				return null;
	
			return &slot.value;
		}
		else
			return str in mData;
	}

	public void opIndexAssign(ref MDValue value, MDString key)
	{
		version(MDExperimentalNamespaces)
		{
			hash_t h = key.toHash() % mSlots.length;
	
			if(mSlots[h].key is null)
			{
				mSlots[h].key = key;
				mSlots[h].value = value;
				
				if(h is mColSlot)
					moveColSlot();
			}
			else
			{
				for(Slot* slot = &mSlots[h]; slot !is null; slot = slot.next)
				{
					if(slot.key == key)
					{
						slot.value = value;
						return;
					}
				}
	
				if(mColSlot == mSlots.length)
					grow();
	
				mSlots[mColSlot].key = key;
				mSlots[mColSlot].value = value;
	
				Slot* slot;
				for(slot = &mSlots[h]; slot.next !is null; slot = slot.next)
				{}
	
				slot.next = &mSlots[mColSlot];
				moveColSlot();
			}
			
			mLength++;
		}
		else
			mData[key] = value;
	}

	public void opIndexAssign(ref MDValue value, dchar[] key)
	{
		opIndexAssign(value, new MDString(key));
	}
	
	public void opIndexAssign(MDObject value, MDString key)
	{
		opIndexAssign(MDValue(value), key);
	}
	
	public void opIndexAssign(MDObject value, dchar[] key)
	{
		opIndexAssign(MDValue(value), new MDString(key));
	}
	
	public int opApply(int delegate(ref MDString, ref MDValue) dg)
	{
		int result = 0;
		
		version(MDExperimentalNamespaces)
		{
			foreach(i, ref v; mSlots)
			{
				if(v.key is null)
					continue;
					
				result = dg(v.key, v.value);
	
				if(result)
					break;
			}
		}
		else
		{
			foreach(k, ref v; mData)
			{
				result = dg(k, v);
				
				if(result)
					break;
			}
		}

		return result;
	}

	public dchar[] nameString()
	{
		dchar[] ret = mName;

		if(mParent)
		{
			dchar[] s = mParent.nameString();
			
			if(s.length > 0)
				ret = mParent.nameString() ~ "." ~ ret;
		}

		return ret;
	}

	public char[] toString()
	{
		return string.format("namespace %s", nameString());
	}
	
	version(MDExperimentalNamespaces)
	{
		protected Slot* lookup(MDString key)
		{
			hash_t h = key.toHash() % mSlots.length;
	
			if(mSlots[h].key is null)
				return null;
	
			for(Slot* slot = &mSlots[h]; slot !is null; slot = slot.next)
				if(slot.key == key)
					return slot;
	
			return null;
		}
	
		protected void grow()
		{
			Slot[] newSlots = new Slot[mSlots.length * 2];
			size_t colSlot = 0;
	
			foreach(i, ref v; mSlots)
			{
				if(v.key is null)
					continue;
	
				hash_t h = v.key.toHash() % newSlots.length;
	
				if(newSlots[h].key is null)
				{
					newSlots[h].key = v.key;
					newSlots[h].value = v.value;
				}
				else
				{
					newSlots[colSlot].key = v.key;
					newSlots[colSlot].value = v.value;
	
					Slot* slot;
					for(slot = &newSlots[h]; slot.next !is null; slot = slot.next)
					{}
	
					slot.next = &newSlots[colSlot];
	
					for( ; colSlot < newSlots.length; colSlot++)
						if(newSlots[colSlot].key is null)
							break;
							
					assert(colSlot < newSlots.length, "MDNamespace.grow");
				}
			}
			
			mSlots = newSlots;
		}
		
		protected void moveColSlot()
		{
			for( ; mColSlot < mSlots.length; mColSlot++)
				if(mSlots[mColSlot].key is null)
					return;
	
			grow();
	
			for(mColSlot = 0; mColSlot < mSlots.length; mColSlot++)
				if(mSlots[mColSlot].key is null)
					return;
	
			assert(false, "MDNamespace.moveColSlot");
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

class MDModuleDef
{
	package dchar[] mName;
	package dchar[][] mImports;
	package MDFuncDef mFunc;
	
	dchar[] name()
	{
		return mName;
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
		int[MDValue] offsets;
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
			Serialize(s, st.offsets.length);

			foreach(k, v; st.offsets)
			{
				Serialize(s, k);
				Serialize(s, v);
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
		
		foreach(ref st; ret.mSwitchTables)
		{
			Deserialize(s, len);

			for(int i = 0; i < len; i++)
			{
				MDValue key;
				int value;

				Deserialize(s, key);
				Deserialize(s, value);

				st.offsets[key] = value;
			}

			Deserialize(s, st.defaultOffset);
		}
		
		Deserialize(s, ret.mInnerFuncs);

		return ret;
	}
}

class MDGlobalState
{
	private alias bool delegate(MDState s, dchar[] name, dchar[] fromModule) ModuleLoader;

	private static MDGlobalState instance;
	private MDState mMainThread;
	private MDNamespace[] mBasicTypeMT;
	private MDNamespace mGlobals;
	private ModuleLoader[] mModuleLoaders;
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
		if(type == MDValue.Type.Null)
			throw new MDException("Cannot set global metatable for type 'null'");

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

	public T getGlobal(T = MDValue*)(dchar[] name)
	{
		scope str = MDString.newTemp(name);
		MDValue* value = mGlobals[str];
		
		if(value is null)
			throw new MDException("MDGlobalState.getGlobal() - Attempting to access nonexistent global '%s'", name);

		static if(is(T == MDValue*))
			return value;
		else
			return value.to!(T);
	}

	public MDClosure newClosure(MDFuncDef def)
	{
		return new MDClosure(mGlobals, def);
	}

	public MDClosure newClosure(int delegate(MDState, uint) dg, dchar[] name, MDValue[] upvals = null)
	{
		return new MDClosure(mGlobals, dg, name, upvals);
	}
	
	public MDClosure newClosure(int function(MDState, uint) func, dchar[] name, MDValue[] upvals = null)
	{
		return new MDClosure(mGlobals, func, name, upvals);
	}

	public void registerModuleLoader(ModuleLoader loader)
	{
		mModuleLoaders ~= loader;
	}

	public void importModule(dchar[] name, dchar[] fromModule = null, MDState s = null)
	{
		if(s is null)
			s = mMainThread;

		if(name in mLoadedModules)
			return;

		bool success = false;

		foreach(loader; mModuleLoaders)
		{
			success = loader(s, name, fromModule);

			if(success)
				break;
		}

		if(success == false)
		{
			if(fromModule.length == 0)
				throw new MDException("Could not import module \"%s\"", name);
			else
				throw new MDException("From module \"%s\"", fromModule, ": Could not import module \"%s\"", name);
		}
	}

	public MDNamespace registerModule(MDModuleDef def, MDState s)
	in
	{
		assert(!(def.name in mLoadedModules));
	}
	body
	{
		mLoadedModules[def.name] = true;

		scope(failure)
			mLoadedModules.remove(def.name);
			
		dchar[][] splitName = dsplit(def.name, '.');

		dchar[][] packages = splitName[0 .. $ - 1];
		dchar[] name = splitName[$ - 1];

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
					put = v.as!(MDNamespace);
				else
					s.throwRuntimeException("Error loading module ", def.name, "; conflicts with ", packages[0 .. i + 1]);
			}
		}

		if(name in put)
			throw new MDException("Error loading module ", def.name, "; a global of the same name already exists");

		MDNamespace modNS = new MDNamespace(name, put);
		put[name] = modNS;

		foreach(imp; def.mImports)
			importModule(imp, def.name, s);

		return modNS;
	}
	
	public void staticInitModule(MDModuleDef def, MDNamespace modNS, MDState s, MDValue[] params = null)
	{
		MDClosure cl = new MDClosure(modNS, def.mFunc);

		uint funcReg = s.push(cl);
		s.push(modNS);
		
		foreach(param; params)
			s.push(param);
			
		s.call(funcReg, params.length + 1, 0);
	}
}

final class MDState : MDObject
{
	protected static Location[] Traceback;

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
	
	enum State
	{
		Initial,
		Waiting,
		Running,
		Suspended,
		Dead
	}
	
	static MDString[] StateStrings;

	static this()
	{
		StateStrings = new MDString[5];
		StateStrings[0] = new MDString("initial"d);
		StateStrings[1] = new MDString("waiting"d);
		StateStrings[2] = new MDString("running"d);
		StateStrings[3] = new MDString("suspended"d);
		StateStrings[4] = new MDString("dead"d);
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

	protected State mState = State.Initial;
	protected MDClosure mCoroFunc;
	protected uint mSavedCallDepth;
	protected uint mNumYields;
	protected uint mNativeCallDepth = 0;

	// ===================================================================================
	// Public members
	// ===================================================================================

	public this(MDClosure coroFunc = null)
	{
		mTryRecs = new TryRecord[10];
		mCurrentTR = &mTryRecs[0];

		mActRecs = new ActRecord[10];
		mCurrentAR = &mActRecs[0];

		mStack = new MDValue[20];

		if(coroFunc)
		{
			if(coroFunc.isNative())
				throw new MDException("Cannot create a coroutine thread with a native function closure");

			mCoroFunc = coroFunc;
		}

		mTryRecs[0].actRecord = uint.max;
		mType = MDValue.Type.Thread;
	}

	public override uint length()
	{
		throw new MDException("Cannot get the length of a thread");
	}
	
	public override char[] toString()
	{
		return string.format("thread 0x%0.8X", cast(void*)this);
	}

	public final State state()
	{
		return mState;
	}

	public final MDString stateString()
	{
		return StateStrings[mState];
	}

	debug public final void printStack()
	{
		writefln();
		writefln("-----Stack Dump-----");
		for(int i = 0; i < mCurrentAR.savedTop; i++)
			writefln("[%2d:%3d]: %s", i, i - cast(int)mCurrentAR.base, mStack[i].toString());

		writefln();
	}

	debug public final void printCallStack()
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

	public final uint pushNull()
	{
		MDValue v;
		v.setNull();
		return push(&v);
	}

	public final uint push(T)(T value)
	{
		checkStack(mStackIndex);
		mStack[mStackIndex] = value;
		mStackIndex++;

		debug(STACKINDEX) writefln("push() set mStackIndex to ", mStackIndex);//, " (pushed %s)", val.toString());

		return mStackIndex - 1 - mCurrentAR.base;
	}

	public final T pop(T = MDValue)()
	{
		if(mStackIndex <= mCurrentAR.base)
			throwRuntimeException("MDState.pop() - Stack underflow");

		mStackIndex--;

		static if(is(T == MDValue))
			return mStack[mStackIndex];
		else
			return mStack[mStackIndex].to!(T);
	}
	
	public final uint easyCall(F, T...)(F func, int numReturns, MDValue context, T params)
	{
		static if(is(F : MDClosure))
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
		else
		{
			uint funcSlot = push(func);
			push(context);
			
			foreach(param; params)
				push(param);
				
			if(callPrologue(funcSlot, numReturns, params.length + 1))
				execute();
				
			if(numReturns == -1)
				return mStackIndex - basedIndexToAbs(funcSlot);
			else
			{
				mStackIndex = basedIndexToAbs(funcSlot) + numReturns;
				return numReturns;
			}
		}
	}

	public final uint callMethod(T...)(ref MDValue val, dchar[] methodName, int numReturns, T params)
	{
		scope MDString name = MDString.newTemp(methodName);
		
		uint funcSlot = push(lookupMethod(&val, name));
		push(val);
		
		foreach(param; params)
			push(param);
			
		if(callPrologue(funcSlot, numReturns, params.length + 1))
			execute();

		if(numReturns == -1)
			return mStackIndex - funcSlot;
		else
		{
			mStackIndex = funcSlot + numReturns;
			return numReturns;
		}
	}

	public final uint call(uint slot, int numParams, int numReturns)
	{
		if(callPrologue(slot, numReturns, numParams))
			execute();
			
		if(numReturns == -1)
			return mStackIndex - basedIndexToAbs(slot);
		else
		{
			mStackIndex = basedIndexToAbs(slot) + numReturns;
			return numReturns;
		}
	}

	public final void setUpvalue(T)(uint index, T value)
	{
		if(!mCurrentAR.func)
			throwRuntimeException("MDState.setUpvalue() - No function to set upvalue");

		assert(mCurrentAR.func.isNative(), "MDValue.setUpvalue() used on non-native func");

		if(index >= mCurrentAR.func.native.upvals.length)
			throwRuntimeException("MDState.setUpvalue() - Invalid upvalue index: ", index);

		mCurrentAR.func.native.upvals[index] = value;
	}

	public final T getUpvalue(T = MDValue*)(uint index)
	{
		if(!mCurrentAR.func)
			throwRuntimeException("MDState.getUpvalue() - No function to get upvalue");

		assert(mCurrentAR.func.isNative(), "MDValue.getUpvalue() used on non-native func");

		if(index >= mCurrentAR.func.native.upvals.length)
			throwRuntimeException("MDState.getUpvalue() - Invalid upvalue index: ", index);

		static if(is(T == MDValue*))
			return &mCurrentAR.func.native.upvals[index];
		else
			return mCurrentAR.func.native.upvals[index].to!(T);
	}

	public final bool isParam(char[] type)(uint index)
	{
		if(index >= (getBasedStackIndex() - 1))
			badParamError(index, "not enough parameters");

		static if(type == "null")           return getBasedStack(index + 1).isNull();
		else static if(type == "bool")      return getBasedStack(index + 1).isBool();
		else static if(type == "int")       return getBasedStack(index + 1).isInt();
		else static if(type == "float")     return getBasedStack(index + 1).isFloat();
		else static if(type == "char")      return getBasedStack(index + 1).isChar();
		else static if(type == "string")    return getBasedStack(index + 1).isString();
		else static if(type == "table")     return getBasedStack(index + 1).isTable();
		else static if(type == "array")     return getBasedStack(index + 1).isArray();
		else static if(type == "function")  return getBasedStack(index + 1).isFunction();
		else static if(type == "class")     return getBasedStack(index + 1).isClass();
		else static if(type == "instance")  return getBasedStack(index + 1).isInstance();
		else static if(type == "namespace") return getBasedStack(index + 1).isNamespace();
		else static if(type == "thread")    return getBasedStack(index + 1).isThread();
		else
		{
			pragma(msg, "MDState.isParam() - invalid type '" ~ type ~ "'");
			ERROR_MDState_isParam_InvalidType();
		}
	}

	public final T getParam(T = MDValue)(uint index)
	{
		if(index >= (getBasedStackIndex() - 1))
			badParamError(index, "not enough parameters");
			
		MDValue* val = getBasedStack(index + 1);

		static if(is(T == bool))
		{
			if(val.isBool() == false)
				badParamError(index, "expected 'bool' but got '%s'", val.typeString());

			return val.as!(T);
		}
		else static if(isIntType!(T))
		{
			if(val.isInt() == false)
				badParamError(index, "expected 'int' but got '%s'", val.typeString());
				
			return val.as!(T);
		}
		else static if(isFloatType!(T))
		{
			if(val.isFloat() == false)
				badParamError(index, "expected 'float' but got '%s'", val.typeString());
	
			return val.as!(T);
		}
		else static if(isCharType!(T))
		{
			if(val.isChar() == false)
				badParamError(index, "expected 'char' but got '%s'", val.typeString());

			return val.as!(T);
		}
		else static if(isStringType!(T))
		{
			if(val.isString() == false)
				badParamError(index, "expected 'string' but got '%s'", val.typeString());

			return val.as!(T);
		}
		else static if(is(T : MDString))
		{
			if(val.isString() == false)
				badParamError(index, "expected 'string' but got '%s'", val.typeString());

			return val.as!(T);
		}
		else static if(is(T : MDTable))
		{
			if(val.isTable() == false)
				badParamError(index, "expected 'table' but got '%s'", val.typeString());

			return val.as!(T);
		}
		else static if(is(T : MDArray))
		{
			if(val.isArray() == false)
				badParamError(index, "expected 'array' but got '%s'", val.typeString());

			return val.as!(T);
		}
		else static if(is(T : MDClosure))
		{
			if(val.isFunction() == false)
				badParamError(index, "expected 'function' but got '%s'", val.typeString());

			return val.as!(T);
		}
		else static if(is(T : MDClass))
		{
			if(val.isClass() == false)
				badParamError(index, "expected 'class' but got '%s'", val.typeString());

			return val.as!(T);
		}
		else static if(is(T : MDInstance))
		{
			if(val.isInstance() == false)
				badParamError(index, "expected 'instance' but got '%s'", val.typeString());

			return val.as!(T);
		}
		else static if(is(T : MDNamespace))
		{
			if(val.isString() == false)
				badParamError(index, "expected 'namespace' but got '%s'", val.typeString());

			return val.as!(T);
		}
		else static if(is(T : MDState))
		{
			if(val.isThread() == false)
				badParamError(index, "expected 'thread' but got '%s'", val.typeString());

			return val.as!(T);
		}
		else static if(is(T == MDValue))
		{
			return *val;
		}
		else
		{
			// I do this because static assert won't show the template instantiation "call stack."
			pragma(msg, "MDState.getParam() - Invalid argument type '" ~ T.stringof ~ "'");
			ARGUMENT_ERROR(T);
		}
	}
	
	public final T getContext(T = MDValue)()
	{
		static if(is(T == MDValue))
			return mStack[mCurrentAR.base];
		else
			return mStack[mCurrentAR.base].to!(T);
	}

	public final MDValue[] getParams(int lo, int hi)
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

	public final MDValue[] getAllParams()
	{
		if(getBasedStackIndex() == 1)
			return null;

		return mStack[mCurrentAR.base + 1 .. mStackIndex].dup;
	}

	public final T safeCode(T)(lazy T code)
	{
		try
			return code;
		catch(MDException e)
			throw e;
		catch(Exception e)
			throwRuntimeException(e.toString());
	}

	public final void throwRuntimeException(MDValue* val)
	{
		throw new MDRuntimeException(startTraceback(), val);
	}

	public final void throwRuntimeException(...)
	{
		throw new MDRuntimeException(startTraceback(), _arguments, _argptr);
	}

	public final MDNamespace environment(int depth = 0)
	{
		if(mARIndex < 1)
			throw new MDException("MDState.environment() - no current environment");

		if(depth < 0 || mARIndex - depth < 1)
			throw new MDException("MDState.environment() - Invalid depth: ", depth);

		return mActRecs[mARIndex - depth].env;
	}

	public final MDString valueToString(ref MDValue value)
	{
		if(value.isString())
			return value.as!(MDString);

		MDValue* method = getMM(value, MM.ToString);
		
		if(!method.isFunction())
			return new MDString(value.toString());

		mNativeCallDepth++;
		
		scope(exit)
			mNativeCallDepth--;

		easyCall(method.as!(MDClosure), 1, value);
		MDValue ret = pop();

		if(!ret.isString())
			throwRuntimeException("MDState.valueToString() - '%s' method did not return a string", MetaNames[MM.ToString]);
			
		return ret.as!(MDString);
	}

	public final bool opin(ref MDValue a, ref MDValue b)
	{
		return operatorIn(&a, &b);
	}

	public final int cmp(ref MDValue a, ref MDValue b)
	{
		return compare(&a, &b);
	}
	
	public final MDValue idx(ref MDValue src, ref MDValue index)
	{
		return operatorIndex(&src, &index);
	}
	
	public final void idxa(ref MDValue dest, ref MDValue index, ref MDValue src)
	{
		operatorIndexAssign(&dest, &index, &src);
	}
	
	public final MDValue cat(MDValue[] vals...)
	{
		return operatorCat(vals);
	}
	
	public final void cateq(ref MDValue dest, MDValue[] vals)
	{
		operatorCatAssign(&dest, vals);
	}

	public final MDValue len(ref MDValue val)
	{
		return operatorLength(&val);
	}
	
	public final MDValue slice(ref MDValue src, ref MDValue lo, ref MDValue hi)
	{
		return operatorSlice(&src, &lo, &hi);
	}
	
	public final void slicea(ref MDValue dest, ref MDValue lo, ref MDValue hi, ref MDValue src)
	{
		operatorSliceAssign(&dest, &lo, &hi, &src);
	}
	
	public final MDValue add(ref MDValue a, ref MDValue b)
	{
		return binOp(MM.Add, &a, &b);
	}
	
	public final MDValue sub(ref MDValue a, ref MDValue b)
	{
		return binOp(MM.Sub, &a, &b);
	}

	public final MDValue mul(ref MDValue a, ref MDValue b)
	{
		return binOp(MM.Mul, &a, &b);
	}

	public final MDValue div(ref MDValue a, ref MDValue b)
	{
		return binOp(MM.Div, &a, &b);
	}

	public final MDValue mod(ref MDValue a, ref MDValue b)
	{
		return binOp(MM.Mod, &a, &b);
	}
	
	public final MDValue neg(ref MDValue a)
	{
		return unOp(MM.Neg, &a);
	}
	
	public final void addeq(ref MDValue a, ref MDValue b)
	{
		reflOp(MM.AddEq, &a, &b);
	}
	
	public final void subeq(ref MDValue a, ref MDValue b)
	{
		reflOp(MM.SubEq, &a, &b);
	}

	public final void muleq(ref MDValue a, ref MDValue b)
	{
		reflOp(MM.MulEq, &a, &b);
	}

	public final void diveq(ref MDValue a, ref MDValue b)
	{
		reflOp(MM.DivEq, &a, &b);
	}

	public final void modeq(ref MDValue a, ref MDValue b)
	{
		reflOp(MM.ModEq, &a, &b);
	}
	
	public final MDValue and(ref MDValue a, ref MDValue b)
	{
		return binaryBinOp(MM.And, &a, &b);
	}
	
	public final MDValue or(ref MDValue a, ref MDValue b)
	{
		return binaryBinOp(MM.Or, &a, &b);
	}

	public final MDValue xor(ref MDValue a, ref MDValue b)
	{
		return binaryBinOp(MM.Xor, &a, &b);
	}

	public final MDValue shl(ref MDValue a, ref MDValue b)
	{
		return binaryBinOp(MM.Shl, &a, &b);
	}

	public final MDValue shr(ref MDValue a, ref MDValue b)
	{
		return binaryBinOp(MM.Shr, &a, &b);
	}

	public final MDValue ushr(ref MDValue a, ref MDValue b)
	{
		return binaryBinOp(MM.UShr, &a, &b);
	}
	
	public final MDValue com(ref MDValue a)
	{
		return binaryUnOp(MM.Com, &a);
	}
	
	public final void andeq(ref MDValue a, ref MDValue b)
	{
		binaryReflOp(MM.AndEq, &a, &b);
	}
	
	public final void oreq(ref MDValue a, ref MDValue b)
	{
		binaryReflOp(MM.OrEq, &a, &b);
	}

	public final void xoreq(ref MDValue a, ref MDValue b)
	{
		binaryReflOp(MM.XorEq, &a, &b);
	}

	public final void shleq(ref MDValue a, ref MDValue b)
	{
		binaryReflOp(MM.ShlEq, &a, &b);
	}

	public final void shreq(ref MDValue a, ref MDValue b)
	{
		binaryReflOp(MM.ShrEq, &a, &b);
	}

	public final void ushreq(ref MDValue a, ref MDValue b)
	{
		binaryReflOp(MM.UShrEq, &a, &b);
	}

	public static char[] getTracebackString()
	{
		if(Traceback.length == 0)
			return "";
			
		char[] ret = string.format("Traceback: ", Traceback[0].toString());

		foreach(ref Location l; Traceback[1 .. $])
			ret = string.format("%s\n\tat ", ret, l.toString());

		Traceback.length = 0;

		return ret;
	}

	// ===================================================================================
	// Internal functions
	// ===================================================================================

	protected final Location startTraceback()
	{
		Traceback.length = 0;
		return getDebugLocation();
	}

	protected final Location getDebugLocation()
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

			return Location(mCurrentAR.env.nameString() ~ "." ~ mCurrentAR.func.script.func.mGuessedName, line, instructionIndex);
		}
	}

	protected final void badParamError(uint index, ...)
	{
		throwRuntimeException("Bad argument ", index + 1, ": %s", vformat(_arguments, _argptr));
	}

	protected final bool callPrologue(uint slot, int numReturns, int numParams)
	{
		uint paramSlot;
		MDClosure closure;

		slot = basedIndexToAbs(slot);
		uint returnSlot = slot;

		if(numParams == -1)
			numParams = mStackIndex - slot - 1;

		assert(numParams >= 0, "negative num params in callPrologue");

		MDValue* func = getAbsStack(slot);
		
		switch(func.type())
		{
			case MDValue.Type.Function:
				closure = func.as!(MDClosure);
				paramSlot = slot + 1;
				break;

			case MDValue.Type.Class:
				pushAR();

				*mCurrentAR = mActRecs[mARIndex - 1];
				mCurrentAR.base = slot;
				mCurrentAR.numReturns = numReturns;
				mCurrentAR.funcSlot = slot;

				MDInstance n = func.as!(MDClass).newInstance();
				MDValue* ctor = n.getCtor();

				if(ctor !is null && ctor.isFunction())
				{
					uint thisSlot = slot + 1;
					*getAbsStack(thisSlot) = n;

					if(callPrologue2(ctor.as!(MDClosure), thisSlot, 0, thisSlot, numParams))
						execute();
				}

				*getAbsStack(slot) = n;
				callEpilogue(0, 1);
				return false;

			case MDValue.Type.Thread:
				MDState thread = func.as!(MDState);

				pushAR();
				
				*mCurrentAR = mActRecs[mARIndex - 1];
				mCurrentAR.base = slot;
				mCurrentAR.savedTop = mStackIndex;
				mCurrentAR.funcSlot = slot;
				mCurrentAR.numReturns = numReturns;

				mStackIndex = slot + numParams + 1;

				switch(thread.mState)
				{
					case State.Initial:
						thread.mStackIndex++;
						thread.moveStackFrom(this, numParams);
						break;

					case State.Suspended:
						if(numParams > 0)
						{
							numParams--;
							thread.moveStackFrom(this, numParams);
							mStackIndex--;
						}
						break;

					default:
						throwRuntimeException("Attempting to resume waiting, running, or dead coroutine");
				}
				
				mStackIndex--;
				
				State savedState = mState;
				mState = State.Waiting;

				scope(exit)
					mState = savedState;

				uint numRets;
				
				try
					numRets = thread.resume(numParams);
				catch(MDRuntimeException e)
				{
					callEpilogue(0, 0);
					throw e;
				}
				catch(MDException e)
				{
					Location loc = startTraceback();
					callEpilogue(0, 0);
					throw new MDRuntimeException(loc, &e.value);
				}

				moveStackFrom(thread, numRets);
				callEpilogue(0, numRets);
				return false;

			default:
				mNativeCallDepth++;

				scope(exit)
					mNativeCallDepth--;

				MDValue* method = getMM(*func, MM.Call);

				if(!method.isFunction())
					throwRuntimeException("Attempting to call a value of type '%s'", func.typeString());

				copyAbsStack(slot + 1, slot);
				paramSlot = slot + 1;
				closure = method.as!(MDClosure);
				break;
		}
		
		if(closure is null)
			return false;

		return callPrologue2(closure, returnSlot, numReturns, paramSlot, numParams);
	}

	protected final bool callPrologue2(MDClosure closure, uint returnSlot, int numReturns, uint paramSlot, int numParams)
	{
		if(closure.isNative())
		{
			// Native function
			mStackIndex = paramSlot + numParams;
			checkStack(mStackIndex);

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
				mNativeCallDepth++;

				scope(exit)
					mNativeCallDepth--;

				actualReturns = closure.native.dg(this, numParams - 1);
			}
			catch(MDRuntimeException e)
			{
				callEpilogue(0, 0);
				throw e;
			}
			catch(MDException e)
			{
				Location loc = startTraceback();
				callEpilogue(0, 0);
				throw new MDRuntimeException(loc, &e.value);
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
					checkStack(mStackIndex + funcDef.mNumParams - numParams);

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

	protected final void callEpilogue(uint resultSlot, int numResults)
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
			
		mNumYields = numResults;
		
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

		mStackIndex = destSlot;

		if(mARIndex == 0)
			mState = State.Dead;

		if(!isMultRet)
			mStackIndex = mCurrentAR.savedTop;

		debug(STACKINDEX) writefln("callEpilogue() set mStackIndex to ", mStackIndex);
	}
	
	protected final uint resume(uint numParams)
	{
		switch(mState)
		{
			case State.Initial:
				mStack[0] = mCoroFunc;
				mCoroFunc = null;

				bool result = callPrologue(0, -1, numParams);
				assert(result == true, "resume callPrologue must return true");

				execute();
				return mNumYields;

			case State.Suspended:
				callEpilogue(mStackIndex - numParams - mCurrentAR.base, numParams);
				execute(mSavedCallDepth);
				return mNumYields;

			default:
				assert(false, "resume invalid state");
		}
	}

	protected final void pushAR()
	{
		if(mARIndex >= mActRecs.length - 1)
		{
			try
				mActRecs.length = mActRecs.length * 2;
			catch
			{
				throwRuntimeException("Script call stack overflow");
			}
		}

		mARIndex++;

		mCurrentAR = &mActRecs[mARIndex];
	}

	protected final void popAR()
	{
		mARIndex--;

		assert(mARIndex != uint.max);//BUG , "Script call stack underflow");

		mCurrentAR.func = null;
		mCurrentAR.env = null;
		mCurrentAR = &mActRecs[mARIndex];
	}
	
	protected final void pushTR()
	{
		if(mTRIndex >= mTryRecs.length - 1)
		{
			try
				mTryRecs.length = mTryRecs.length * 2;
			catch
			{
				throwRuntimeException("Script catch/finally stack overflow");
			}
		}

		mTRIndex++;
		mCurrentTR = &mTryRecs[mTRIndex];
		mCurrentTR.actRecord = mARIndex;
	}
	
	protected final void popTR()
	{
		mTRIndex--;

		assert(mTRIndex != uint.max, "Script catch/finally stack underflow");

		mCurrentTR = &mTryRecs[mTRIndex];
	}

	protected final void needStackSlots(uint howMany)
	{
		if(mStack.length - mStackIndex >= howMany + 1)
			return;

		stackSize = howMany + 1 + mStackIndex;
	}
	
	protected final void checkStack(uint absSlot)
	{
		if(absSlot >= mStack.length)
			stackSize = absSlot * 2;
	}

	protected final void stackSize(uint length)
	{
		MDValue* oldBase = mStack.ptr;

		try
			mStack.length = length;
		catch
		{
			throwRuntimeException("Script value stack overflow: ", mStack.length);
		}

		MDValue* newBase = mStack.ptr;

		if(oldBase !is newBase)
			for(MDUpval* uv = mUpvalHead; uv !is null; uv = uv.next)
				uv.value = (uv.value - oldBase) + newBase;
	}

	protected final void copyBasedStack(uint dest, uint src)
	{
		assert((mCurrentAR.base + dest) < mStack.length && (mCurrentAR.base + src) < mStack.length, "invalid based stack indices");
		
		if(dest != src)
			mStack[mCurrentAR.base + dest] = mStack[mCurrentAR.base + src];
	}

	protected final void copyAbsStack(uint dest, uint src)
	{
		assert(dest < mStack.length && src < mStack.length, "invalid copyAbsStack indices");

		if(dest != src)
			mStack[dest] = mStack[src];
	}
	
	protected final void moveStackFrom(MDState other, uint numValues)
	{
		assert(other.mStackIndex >= numValues, "moveStackFrom stack underflow");
		assert(other !is this, "moveStackFrom same thread");

		if(numValues == 0)
			return;
			
		needStackSlots(numValues);
		mStack[mStackIndex .. mStackIndex + numValues] = other.mStack[other.mStackIndex - numValues .. other.mStackIndex];
		mStackIndex += numValues;
		other.mStackIndex -= numValues;
	}

	protected final MDValue* getBasedStack(uint offset)
	{
		assert((mCurrentAR.base + offset) < mStack.length, "invalid based stack index");
		return &mStack[mCurrentAR.base + offset];
	}

	protected final MDValue* getAbsStack(uint offset)
	{
		assert(offset < mStack.length, "invalid getAbsStack stack index");
		return &mStack[offset];
	}

	protected final uint basedIndexToAbs(uint offset)
	{
		assert((mCurrentAR.base + offset) < mStack.length, "invalid basedIndexToAbs index");
		return mCurrentAR.base + offset;
	}
	
	protected final uint absIndexToBased(uint offset)
	{
		assert((cast(int)(offset - mCurrentAR.base)) >= 0 && offset < mStack.length, "invalid absIndexToBased index");
		return offset - mCurrentAR.base;
	}

	protected final void close(uint index)
	{
		MDValue* base = getBasedStack(index);

		for(MDUpval* uv = mUpvalHead; uv !is null && uv.value >= base; uv = mUpvalHead)
		{
			mUpvalHead = uv.next;

			if(uv.prev)
				uv.prev.next = uv.next;

			if(uv.next)
				uv.next.prev = uv.prev;

			uv.closedValue = *uv.value;
			uv.value = &uv.closedValue;
		}
	}

	protected final MDUpval* findUpvalue(uint num)
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

	protected final int getBasedStackIndex()
	{
		return mStackIndex - mCurrentAR.base;
	}

	protected final MDValue* getMM(ref MDValue obj, MM method)
	{
		MDValue* m;
		
		switch(obj.type)
		{
			case MDValue.Type.Table:
				m = obj.as!(MDTable)[MDValue(MetaStrings[method])];

				if(!m.isFunction())
					goto default;

				break;

			case MDValue.Type.Instance:
				m = obj.as!(MDInstance)[MetaStrings[method]];
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
	
	protected final MDValue binOp(MM operation, MDValue* RS, MDValue* RT)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("Arith");

		if(RS.isNum() && RT.isNum())
		{
			if(RS.isFloat() || RT.isFloat())
			{
				switch(operation)
				{
					case MM.Add: return MDValue(RS.as!(mdfloat) + RT.as!(mdfloat));
					case MM.Sub: return MDValue(RS.as!(mdfloat) - RT.as!(mdfloat));
					case MM.Mul: return MDValue(RS.as!(mdfloat) * RT.as!(mdfloat));
					case MM.Div: return MDValue(RS.as!(mdfloat) / RT.as!(mdfloat));
					case MM.Mod: return MDValue(RS.as!(mdfloat) % RT.as!(mdfloat));
				}
			}
			else
			{
				switch(operation)
				{
					case MM.Add: return MDValue(RS.as!(int) + RT.as!(int));
					case MM.Sub: return MDValue(RS.as!(int) - RT.as!(int));
					case MM.Mul: return MDValue(RS.as!(int) * RT.as!(int));

					case MM.Mod:
						if(RT.as!(int) == 0)
							throwRuntimeException("Integer modulo by zero");
						
						return MDValue(RS.as!(int) % RT.as!(int));

					case MM.Div:
						if(RT.as!(int) == 0)
							throwRuntimeException("Integer divide by zero");

						return MDValue(RS.as!(int) / RT.as!(int));
				}
			}
		}
		else
		{
			MDValue* method = getMM(*RS, operation);

			if(!method.isFunction())
				throwRuntimeException("Cannot perform arithmetic (%s) on a '%s' and a '%s'", MetaNames[operation], RS.typeString(), RT.typeString());

			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			uint funcSlot = push(method);
			push(RS);
			push(RT);
			call(funcSlot, 2, 1);
			return pop();
		}
	}

	protected final MDValue unOp(MM operation, MDValue* RS)
	{
		assert(operation == MM.Neg, "invalid unOp operation");

		debug(TIMINGS) scope _profiler_ = new Profiler("Neg");

		if(RS.isFloat())
			return MDValue(-RS.as!(mdfloat));
		else if(RS.isInt())
			return MDValue(-RS.as!(int));
		else
		{
			MDValue* method = getMM(*RS, MM.Neg);

			if(!method.isFunction())
				throwRuntimeException("Cannot perform negation on a '%s'", RS.typeString());

			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			uint funcSlot = push(method);
			push(RS);
			call(funcSlot, 1, 1);
			return pop();
		}
	}

	protected final void reflOp(MM operation, MDValue* RD, MDValue* RS)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("ReflArith");

		if(RD.isNum() && RS.isNum())
		{
			if(RD.isFloat() || RS.isFloat())
			{
				switch(operation)
				{
					case MM.AddEq: *RD = RD.as!(mdfloat) + RS.as!(mdfloat); return;
					case MM.SubEq: *RD = RD.as!(mdfloat) - RS.as!(mdfloat); return;
					case MM.MulEq: *RD = RD.as!(mdfloat) * RS.as!(mdfloat); return;
					case MM.DivEq: *RD = RD.as!(mdfloat) / RS.as!(mdfloat); return;
					case MM.ModEq: *RD = RD.as!(mdfloat) % RS.as!(mdfloat); return;
				}
			}
			else
			{
				switch(operation)
				{
					case MM.AddEq: *RD = RD.as!(int) + RS.as!(int); return;
					case MM.SubEq: *RD = RD.as!(int) - RS.as!(int); return;
					case MM.MulEq: *RD = RD.as!(int) * RS.as!(int); return;

					case MM.ModEq:
						if(RS.as!(int) == 0)
							throwRuntimeException("Integer modulo by zero");

						*RD = RD.as!(int) % RS.as!(int);
						return;

					case MM.DivEq:
						if(RS.as!(int) == 0)
							throwRuntimeException("Integer divide by zero");

						*RD = RD.as!(int) / RS.as!(int);
						return;
				}
			}
		}
		else
		{
			MDValue* method = getMM(*RD, operation);

			if(!method.isFunction())
				throwRuntimeException("Cannot perform arithmetic (%s) on a '%s' and a '%s'", MetaNames[operation], RD.typeString(), RS.typeString());

			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			uint funcSlot = push(method);
			push(RD);
			push(RS);
			call(funcSlot, 2, 0);
		}
	}
	
	protected final MDValue binaryBinOp(MM operation, MDValue* RS, MDValue* RT)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("BitArith");

		if(RS.isInt() && RT.isInt())
		{
			switch(operation)
			{
				case MM.And:  return MDValue(RS.as!(int) & RT.as!(int));
				case MM.Or:   return MDValue(RS.as!(int) | RT.as!(int));
				case MM.Xor:  return MDValue(RS.as!(int) ^ RT.as!(int));
				case MM.Shl:  return MDValue(RS.as!(int) << RT.as!(int));
				case MM.Shr:  return MDValue(RS.as!(int) >> RT.as!(int));
				case MM.UShr: return MDValue(RS.as!(int) >>> RT.as!(int));
			}
		}
		else
		{
			MDValue* method = getMM(*RS, operation);

			if(!method.isFunction())
				throwRuntimeException("Cannot perform bitwise arithmetic (%s) on a '%s' and a '%s'", MetaNames[operation], RS.typeString(), RT.typeString());

			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			uint funcSlot = push(method);
			push(RS);
			push(RT);
			call(funcSlot, 2, 1);
			return pop();
		}
	}
	
	protected final MDValue binaryUnOp(MM operation, MDValue* RS)
	{
		assert(operation == MM.Com, "invalid binaryUnOp operation");
		debug(TIMINGS) scope _profiler_ = new Profiler("Com");

		if(RS.isInt())
			return MDValue(~RS.as!(int));
		else
		{
			MDValue* method = getMM(*RS, MM.Com);

			if(!method.isFunction())
				throwRuntimeException("Cannot perform complement on a '%s'", RS.typeString());

			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			uint funcSlot = push(method);
			push(RS);
			call(funcSlot, 1, 1);
			return pop();
		}
	}
	
	protected final void binaryReflOp(MM operation, MDValue* RD, MDValue* RS)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("ReflBitArith");

		if(RD.isInt() && RS.isInt())
		{
			switch(operation)
			{
				case MM.AndEq:  *RD = RD.as!(int) & RS.as!(int); return;
				case MM.OrEq:   *RD = RD.as!(int) | RS.as!(int); return;
				case MM.XorEq:  *RD = RD.as!(int) ^ RS.as!(int); return;
				case MM.ShlEq:  *RD = RD.as!(int) << RS.as!(int); return;
				case MM.ShrEq:  *RD = RD.as!(int) >> RS.as!(int); return;
				case MM.UShrEq: *RD = RD.as!(int) >>> RS.as!(int); return;
			}
		}
		else
		{
			MDValue* method = getMM(*RD, operation);

			if(!method.isFunction())
				throwRuntimeException("Cannot perform bitwise arithmetic (%s) on a '%s' and a '%s'", MetaNames[operation], RD.typeString(), RS.typeString());

			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			uint funcSlot = push(method);
			push(RD);
			push(RS);
			call(funcSlot, 2, 0);
		}
	}
	
	protected final int compare(MDValue* RS, MDValue* RT)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("Compare");

		int cmpValue;

		if(RS.isNum() && RT.isNum())
		{
			if(RS.isFloat() || RT.isFloat())
			{
				mdfloat f1 = RS.as!(mdfloat);
				mdfloat f2 = RT.as!(mdfloat);

				if(f1 < f2)
					return -1;
				else if(f1 > f2)
					return 1;
				else
					return 0;
			}
			else
				return RS.as!(int) - RT.as!(int);
		}
		else if(RS.type == RT.type)
		{
			switch(RS.type)
			{
				case MDValue.Type.Null:
					return 0;

				case MDValue.Type.Bool:
					return (cast(int)RS.as!(bool) - cast(int)RT.as!(bool));

				case MDValue.Type.Char:
					return RS.as!(dchar) - RT.as!(dchar);

				default:
					MDObject o1 = RS.as!(MDObject);
					MDObject o2 = RT.as!(MDObject);

					if(o1 is o2)
						return 0;
					else
					{
						MDValue* method = getMM(*RS, MM.Cmp);

						if(method.isFunction())
						{
							mNativeCallDepth++;

							scope(exit)
								mNativeCallDepth--;

							uint funcReg = push(method);
							push(RS);
							push(RT);
							call(funcReg, 2, 1);
							MDValue ret = pop();

							if(!ret.isInt())
								throwRuntimeException("opCmp is expected to return an int for type '%s'", RS.typeString());

							return ret.as!(int);
						}
						else
							return MDObject.compare(o1, o2);
					}
			}
		}
		else
		{
			MDValue* method = getMM(*RS, MM.Cmp);

			if(!method.isFunction())
				throwRuntimeException("invalid opCmp metamethod for type '%s'", RS.typeString());

			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			uint funcReg = push(method);
			push(RS);
			push(RT);
			call(funcReg, 2, 1);
			MDValue ret = pop();

			if(!ret.isInt())
				throwRuntimeException("opCmp is expected to return an int for type '%s'", RS.typeString());

			return ret.as!(int);
		}
	}
	
	protected final bool operatorIn(MDValue* RS, MDValue* RT)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("In");

		switch(RT.type)
		{
			case MDValue.Type.String:
				if(RS.isChar() == false)
					throwRuntimeException("Can only use characters to look in strings, not '%s'", RS.typeString());
	
				return ((RS.as!(dchar) in RT.as!(MDString)) >= 0);

			case MDValue.Type.Array:
				return ((*RS in RT.as!(MDArray)) >= 0);

			case MDValue.Type.Table:
				return ((*RS in RT.as!(MDTable)) !is null);

			case MDValue.Type.Namespace:
				if(RS.isString() == false)
					throwRuntimeException("Attempting to access namespace '%s' with type '%s'", RT.as!(MDNamespace)().nameString(), RS.typeString());

				return ((RS.as!(MDString) in RT.as!(MDNamespace)) !is null);

			default:
				MDValue* method = getMM(*RT, MM.In);

				if(!method.isFunction())
					throwRuntimeException("No %s metamethod for type '%s'", MetaNames[MM.In], RT.typeString());
	
				mNativeCallDepth++;
	
				scope(exit)
					mNativeCallDepth--;
	
				uint funcSlot = push(method);
				push(RT);
				push(RS);
				call(funcSlot, 2, 1);
	
				return pop().isTrue();
		}
	}
	
	protected final MDValue operatorLength(MDValue* RS)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("Length");

		switch(RS.type)
		{
			case MDValue.Type.String:
				return MDValue(RS.as!(MDString).length);

			case MDValue.Type.Array:
				return MDValue(RS.as!(MDArray).length);

			default:
				MDValue* method = getMM(*RS, MM.Length);

				if(method.isFunction())
				{
					mNativeCallDepth++;

					scope(exit)
						mNativeCallDepth--;

					uint funcReg = push(method);
					push(RS);
					call(funcReg, 1, 1);
					return pop();
				}
				else
					return MDValue(RS.length);
		}
	}
	
	protected final MDValue operatorIndex(MDValue* RS, MDValue* RT)
	{
		MDValue tryMM(MDRuntimeException delegate() ex)
		{
			MDValue* method = getMM(*RS, MM.Index);

			if(method.isFunction() == false)
				throw ex();

			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			uint funcSlot = push(method);
			push(RS);
			push(RT);
			call(funcSlot, 2, 1);
			return pop();
		}

		switch(RS.type)
		{
			case MDValue.Type.Array:
				if(RT.isInt() == false)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access an array with a '%s'", RT.typeString());});

				int index = RT.as!(int);
				MDArray arr = RS.as!(MDArray);

				if(index < 0)
					index += arr.length;

				if(index < 0 || index >= arr.length)
					return tryMM({return new MDRuntimeException(startTraceback(), "Invalid array index: ", index);});

				return *arr[index];

			case MDValue.Type.String:
				if(RT.isInt() == false)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access a string with a '%s'", RT.typeString());});

				int index = RT.as!(int);
				MDString str = RS.as!(MDString);

				if(index < 0)
					index += str.length;

				if(index < 0 || index >= str.length)
					return tryMM({return new MDRuntimeException(startTraceback(), "Invalid string index: ", index);});

				return MDValue(str[index]);

			case MDValue.Type.Table:
				if(RT.isNull())
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index a table with a key of type 'null'");});

				MDValue* v = RS.as!(MDTable)[*RT];

				if(v.isNull())
				{
					MDValue* method = getMM(*RS, MM.Index);

					if(method.isFunction())
					{
						mNativeCallDepth++;

						scope(exit)
							mNativeCallDepth--;

						uint funcSlot = push(method);
						push(RS);
						push(RT);
						call(funcSlot, 2, 1);
						return pop();
					}
					else
						return MDValue.nullValue;
				}
				else
					return *v;

			case MDValue.Type.Instance:
				if(!RT.isString())
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index an instance with a key of type '%s'", RT.typeString());});

				MDValue* v = RS.as!(MDInstance)[RT.as!(MDString)];

				if(v is null)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access nonexistent member '%s' from class instance", RT.toString());});

				return *v;

			case MDValue.Type.Class:
				if(!RT.isString())
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index a class with a key of type '%s'", RT.typeString());});

				MDValue* v = RS.as!(MDClass)[RT.as!(MDString)];

				if(v is null)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access nonexistent member '%s' from class", RT.toString());});

				return *v;

			case MDValue.Type.Namespace:
				if(!RT.isString())
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index namespace '%s' with a key of type '%s'", RS.as!(MDNamespace).nameString(), RT.typeString());});

				MDValue* v = RS.as!(MDNamespace)[RT.as!(MDString)];

				if(v is null)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access nonexistent member '%s' from namespace %s", RT.toString(), RS.as!(MDNamespace).nameString);});

				return *v;

			default:
				return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index a value of type '%s'", RS.typeString());});
		}
	}

	protected final void operatorIndexAssign(MDValue* RD, MDValue* RS, MDValue* RT)
	{
		void tryMM(MDRuntimeException delegate() ex)
		{
			MDValue* method = getMM(*RD, MM.IndexAssign);

			if(method.isFunction() == false)
				throw ex();

			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			uint funcSlot = push(method);
			push(RD);
			push(RS);
			push(RT);
			call(funcSlot, 3, 0);
		}

		switch(RD.type)
		{
			case MDValue.Type.Array:
				if(RS.isInt() == false)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access an array with a '%s'", RS.typeString());});

				int index = RS.as!(int);
				MDArray arr = RD.as!(MDArray);

				if(index < 0)
					index += arr.length;

				if(index < 0 || index >= arr.length)
					return tryMM({return new MDRuntimeException(startTraceback(), "Invalid array index: ", RS.as!(int));});

				arr[index] = *RT;
				return;

			case MDValue.Type.Table:
				if(RS.isNull())
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign a table with a key of type 'null'");});

				MDTable table = RD.as!(MDTable);
				MDValue* val = (*RS in table);

				if(val is null)
				{
					MDValue* method = getMM(*RD, MM.IndexAssign);

					if(method.isFunction())
					{
						mNativeCallDepth++;

						scope(exit)
							mNativeCallDepth--;

						uint funcSlot = push(method);
						push(RD);
						push(RS);
						push(RT);
						call(funcSlot, 3, 0);
					}
					else
						table[*RS] = *RT;
				}
				else
					*val = *RT;
				return;

			case MDValue.Type.Instance:
				if(!RS.isString())
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign an instance with a key of type '%s'", RS.typeString());});

				MDString k = RS.as!(MDString);
				MDValue* val = RD.as!(MDInstance)[k];

				if(val is null)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to add a member '%s' to a class instance", RS.toString());});

				if(val.isFunction())
					throw new MDRuntimeException(startTraceback(), "Attempting to change method '%s' of class instance", RS.toString());

				*val = RT;
				return;

			case MDValue.Type.Class:
				if(!RS.isString())
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign a class with a key of type '%s'", RS.typeString());});

				RD.as!(MDClass)()[RS.as!(MDString)] = *RT;
				return;

			case MDValue.Type.Namespace:
				if(!RS.isString())
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign a namespace with a key of type '%s'", RS.typeString());});

				RD.as!(MDNamespace)()[RS.as!(MDString)] = *RT;
				return;

			default:
				return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign a value of type '%s'", RD.typeString());});
		}
	}
	
	protected final MDValue operatorSlice(MDValue* src, MDValue* lo, MDValue* hi)
	{
		MDValue tryMM(MDRuntimeException delegate() ex)
		{
			MDValue* method = getMM(*src, MM.Slice);

			if(!method.isFunction())
				throw ex();

			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			uint funcSlot = push(method);
			push(src);
			push(lo);
			push(hi);
			call(funcSlot, 3, 1);
			return pop();
		}

		switch(src.type)
		{
			case MDValue.Type.Array:
				MDArray arr = src.as!(MDArray);
				int loIndex;
				int hiIndex;

				if(lo.isNull() && hi.isNull())
					return *src;

				if(lo.isNull())
					loIndex = 0;
				else if(lo.isInt())
				{
					loIndex = lo.as!(int);

					if(loIndex < 0)
						loIndex += arr.length;
				}
				else
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice an array with a '%s'", lo.typeString());});

				if(hi.isNull())
					hiIndex = arr.length;
				else if(hi.isInt())
				{
					hiIndex = hi.as!(int);

					if(hiIndex < 0)
						hiIndex += arr.length;
				}
				else
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice an array with a '%s'", hi.typeString());});

				if(loIndex > hiIndex || loIndex < 0 || loIndex > arr.length || hiIndex < 0 || hiIndex > arr.length)
					return tryMM({return new MDRuntimeException(startTraceback(), "Invalid slice indices [", loIndex, " .. ", hiIndex, "] (array length = ", arr.length, ")");});

				return MDValue(arr[loIndex .. hiIndex]);

			case MDValue.Type.String:
				MDString str = src.as!(MDString);
				int loIndex;
				int hiIndex;

				if(lo.isNull() && hi.isNull())
					return *src;

				if(lo.isNull())
					loIndex = 0;
				else if(lo.isInt())
				{
					loIndex = lo.as!(int);

					if(loIndex < 0)
						loIndex += str.length;
				}
				else
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice a string with a '%s'", lo.typeString());});

				if(hi.isNull())
					hiIndex = str.length;
				else if(hi.isInt())
				{
					hiIndex = hi.as!(int);

					if(hiIndex < 0)
						hiIndex += str.length;
				}
				else
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice a string with a '%s'", hi.typeString());});

				if(loIndex > hiIndex || loIndex < 0 || loIndex > str.length || hiIndex < 0 || hiIndex > str.length)
					return tryMM({return new MDRuntimeException(startTraceback(), "Invalid slice indices [", loIndex, " .. ", hiIndex, "] (string length = ", str.length, ")");});

				return MDValue(str[loIndex .. hiIndex]);

			default:
				return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice a value of type '%s'", src.typeString());});
		}
	}
	
	protected final void operatorSliceAssign(MDValue* RD, MDValue* lo, MDValue* hi, MDValue* RS)
	{
		void tryMM(MDRuntimeException delegate() ex)
		{
			MDValue* method = getMM(*RD, MM.SliceAssign);

			if(!method.isFunction())
				throw ex();

			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			uint funcSlot = push(method);
			push(RD);
			push(lo);
			push(hi);
			push(RS);
			call(funcSlot, 4, 0);
		}

		switch(RD.type)
		{
			case MDValue.Type.Array:
				MDArray arr = RD.as!(MDArray);
				int loIndex;
				int hiIndex;

				if(lo.isNull())
					loIndex = 0;
				else if(lo.isInt())
				{
					loIndex = lo.as!(int);

					if(loIndex < 0)
						loIndex += arr.length;
				}
				else
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice assign an array with a '%s'", lo.typeString());});

				if(hi.isNull())
					hiIndex = arr.length;
				else if(hi.isInt())
				{
					hiIndex = hi.as!(int);

					if(hiIndex < 0)
						hiIndex += arr.length;
				}
				else
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice assign an array with a '%s'", hi.typeString());});

				if(loIndex > hiIndex || loIndex < 0 || loIndex > arr.length || hiIndex < 0 || hiIndex > arr.length)
					return tryMM({return new MDRuntimeException(startTraceback(), "Invalid slice indices [", loIndex, " .. ", hiIndex, "] (array length = ", arr.length, ")");});

				if(RS.isArray())
				{
					if((hiIndex - loIndex) != RS.as!(MDArray).length)
						throw new MDRuntimeException(startTraceback(), "Array slice assign lengths do not match (", hiIndex - loIndex, " and ", RS.as!(MDArray).length, ")");

					arr[loIndex .. hiIndex] = RS.as!(MDArray);
				}
				else
					arr[loIndex .. hiIndex] = *RS;
				break;

			default:
				return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice assign a value of type '%s'", RD.typeString());});
		}
	}
	
	protected MDValue lookupMethod(MDValue* RS, MDString methodName)
	{
		MDValue* v;

		switch(RS.type)
		{
			case MDValue.Type.Instance:
				v = RS.as!(MDInstance)[methodName];

				if(v is null)
					throwRuntimeException("Attempting to access nonexistent member '%s' from class instance", methodName);

				break;

			case MDValue.Type.Table:
				v = RS.as!(MDTable)[MDValue(methodName)];

				if(v.isFunction())
					break;

				goto default;

			case MDValue.Type.Namespace:
				v = RS.as!(MDNamespace)[methodName];

				if(v is null)
					throwRuntimeException("Attempting to access nonexistent member '%s' from namespace '%s'", methodName, RS.as!(MDNamespace).nameString);

				break;

			case MDValue.Type.Class:
				v = RS.as!(MDClass)[methodName];

				if(v is null)
					throwRuntimeException("Attempting to access nonexistent member '%s' from class '%s'", methodName, RS.as!(MDClass).getName());

				break;

			default:
				MDNamespace metatable = MDGlobalState().getMetatable(RS.type);

				if(metatable is null)
					throwRuntimeException("No metatable for type '%s'", RS.typeString());

				v = metatable[methodName];

				if(v is null)
					throwRuntimeException("No implementation of method '%s' for type '%s'", methodName, RS.typeString());

				break;
		}
		
		return *v;
	}
	
	protected MDValue operatorCat(MDValue[] vals)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("Cat");

		if(vals[0].isArray())
			return MDValue(MDArray.concat(vals));
		else if(vals[0].isString() || vals[0].isChar())
		{
			uint badIndex;
			MDString newStr = MDString.concat(vals, badIndex);

			if(newStr is null)
				throwRuntimeException("Cannot list concatenate a '%s' and a '%s' (index: %d)", vals[0].typeString(), vals[badIndex].typeString(), badIndex);

			return MDValue(newStr);
		}
		else
		{
			MDValue* method = getMM(vals[0], MM.Cat);

			if(method.isFunction())
			{
				uint funcSlot = push(method);
				
				foreach(val; vals)
					push(val);
	
				mNativeCallDepth++;
	
				scope(exit)
					mNativeCallDepth--;
	
				call(funcSlot, vals.length, 1);
				return pop();
			}
			else
				return MDValue(MDArray.concat(vals));
		}
	}
	
	protected void operatorCatAssign(MDValue* dest, MDValue[] vals)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("CatEq");

		if(dest.isArray())
			MDArray.concatEq(dest.as!(MDArray), vals);
		else if(dest.isString() || dest.isChar())
		{
			uint badIndex;
			MDString newStr = MDString.concatEq(*dest, vals, badIndex);

			if(newStr is null)
				throwRuntimeException("Cannot append a '%s' (index: %d) to a '%s'", vals[badIndex].typeString(), badIndex, dest.typeString());

			*dest = newStr;
		}
		else
		{
			MDValue* method = getMM(*dest, MM.CatEq);

			if(!method.isFunction())
				throwRuntimeException("Cannot append values to a '%s'", dest.typeString());

			uint funcSlot = push(method);

			push(dest);

			foreach(val; vals)
				push(val);

			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			call(funcSlot, vals.length + 1, 0);
		}
	}

	protected final void execute(uint depth = 1)
	{
		MDException currentException = null;
		MDValue[] constTable = mCurrentAR.func.script.func.mConstants;

		_exceptionRetry:
		mState = State.Running;

		try
		{
			MDValue RS;
			MDValue RT;
			
			MDValue* get(uint index, MDValue* environment = null)
			{
				switch(index & Instruction.locMask)
				{
					case Instruction.locLocal:
						assert((mCurrentAR.base + (index & ~Instruction.locMask)) < mStack.length, "invalid based stack index");

						if(environment)
							*environment = mCurrentAR.env;

						return &mStack[mCurrentAR.base + (index & ~Instruction.locMask)];

					case Instruction.locConst:
						if(environment)
							*environment = mCurrentAR.env;

						return &constTable[index & ~Instruction.locMask];

					case Instruction.locUpval:
						if(environment)
							*environment = mCurrentAR.env;

						return mCurrentAR.func.script.upvals[index & ~Instruction.locMask].value;

					default:
						assert((index & Instruction.locMask) == Instruction.locGlobal, "get() location");

						MDValue* idx = &constTable[index & ~Instruction.locMask];
						assert(idx.isString(), "trying to get a non-string global");
						MDString name = idx.as!(MDString);

						MDValue* glob = null;
						MDValue* src = getBasedStack(0);

						switch(src.type)
						{
							case MDValue.Type.Table:
								MDValue* v = src.as!(MDTable)[*idx];

								if(v.isNull())
									break;

								glob = v;
								break;

							case MDValue.Type.Instance:  glob = src.as!(MDInstance)[name]; break;
							case MDValue.Type.Class:     glob = src.as!(MDClass)[name]; break;
							case MDValue.Type.Namespace: glob = src.as!(MDNamespace)[name]; break;
							default: break;
						}

						if(glob is null)
						{
							for(MDNamespace ns = mCurrentAR.env; ns !is null; ns = ns.mParent)
							{
								glob = ns[name];

								if(glob !is null)
								{
									if(environment)
										*environment = ns;

									return glob;
								}
							}

							throwRuntimeException("Attempting to get nonexistent global '%s'", name);
						}
						else if(environment)
							*environment = *getBasedStack(0);

						return glob;
				}
			}

			while(true)
			{
				Instruction i = *mCurrentAR.pc;
				mCurrentAR.pc++;

				MM operation = void;

				switch(i.opcode)
				{
					// Binary Arithmetic
					case Op.Add: *get(i.rd) = binOp(MM.Add, get(i.rs), get(i.rt)); break;
					case Op.Sub: *get(i.rd) = binOp(MM.Sub, get(i.rs), get(i.rt)); break;
					case Op.Mul: *get(i.rd) = binOp(MM.Mul, get(i.rs), get(i.rt)); break;
					case Op.Div: *get(i.rd) = binOp(MM.Div, get(i.rs), get(i.rt)); break;
					case Op.Mod: *get(i.rd) = binOp(MM.Mod, get(i.rs), get(i.rt)); break;

					// Unary Arithmetic
					case Op.Neg: *get(i.rd) = unOp(MM.Neg, get(i.rs)); break;

					// Reflexive Arithmetic
					case Op.AddEq: reflOp(MM.AddEq, get(i.rd), get(i.rs)); break;
					case Op.SubEq: reflOp(MM.SubEq, get(i.rd), get(i.rs)); break;
					case Op.MulEq: reflOp(MM.MulEq, get(i.rd), get(i.rs)); break;
					case Op.DivEq: reflOp(MM.DivEq, get(i.rd), get(i.rs)); break;
					case Op.ModEq: reflOp(MM.ModEq, get(i.rd), get(i.rs)); break;

					// Binary Bitwise
					case Op.And:  *get(i.rd) = binaryBinOp(MM.And,  get(i.rs), get(i.rt)); break;
					case Op.Or:   *get(i.rd) = binaryBinOp(MM.Or,   get(i.rs), get(i.rt)); break;
					case Op.Xor:  *get(i.rd) = binaryBinOp(MM.Xor,  get(i.rs), get(i.rt)); break;
					case Op.Shl:  *get(i.rd) = binaryBinOp(MM.Shl,  get(i.rs), get(i.rt)); break;
					case Op.Shr:  *get(i.rd) = binaryBinOp(MM.Shr,  get(i.rs), get(i.rt)); break;
					case Op.UShr: *get(i.rd) = binaryBinOp(MM.UShr, get(i.rs), get(i.rt)); break;

					// Unary Bitwise
					case Op.Com: *get(i.rd) = binaryUnOp(MM.Com, get(i.rs)); break;

					// Reflexive Bitwise
					case Op.AndEq:  binaryReflOp(MM.AndEq,  get(i.rd), get(i.rs)); break;
					case Op.OrEq:   binaryReflOp(MM.OrEq,   get(i.rd), get(i.rs)); break;
					case Op.XorEq:  binaryReflOp(MM.XorEq,  get(i.rd), get(i.rs)); break;
					case Op.ShlEq:  binaryReflOp(MM.ShlEq,  get(i.rd), get(i.rs)); break;
					case Op.ShrEq:  binaryReflOp(MM.ShrEq,  get(i.rd), get(i.rs)); break;
					case Op.UShrEq: binaryReflOp(MM.UShrEq, get(i.rd), get(i.rs)); break;

					// Data Transfer
					case Op.Move:
						debug(TIMINGS) scope _profiler_ = new Profiler("Move");
						*get(i.rd) = *get(i.rs);
						break;
						
					case Op.MoveLocal:
						debug(TIMINGS) scope _profiler_ = new Profiler("MoveLocal");
						mStack[mCurrentAR.base + i.rd] = &mStack[mCurrentAR.base + i.rs];
						break;
						
					case Op.LoadConst:
						debug(TIMINGS) scope _profiler_ = new Profiler("LoadConst");
						mStack[mCurrentAR.base + i.rd] = constTable[i.rs & ~Instruction.locMask];
						break;
						
					case Op.CondMove:
						debug(TIMINGS) scope _profiler_ = new Profiler("CondMove");
						
						MDValue* RD = get(i.rd);
						
						if(RD.isNull())
							*RD = *get(i.rs);
						break;

					case Op.LoadBool:
						debug(TIMINGS) scope _profiler_ = new Profiler("LoadBool");

						*get(i.rd) = (i.rs == 1) ? true : false;
						break;
	
					case Op.LoadNull:
						debug(TIMINGS) scope _profiler_ = new Profiler("LoadNull");

						get(i.rd).setNull();
						break;

					case Op.LoadNulls:
						debug(TIMINGS) scope _profiler_ = new Profiler("LoadNulls");

						assert((i.rd & Instruction.locMask) == Instruction.locLocal, "execute Op.LoadNulls");

						for(int j = 0; j < i.imm; j++)
							getBasedStack(i.rd + j).setNull();
						break;
	
					case Op.NewGlobal:
						debug(TIMINGS) scope _profiler_ = new Profiler("NewGlobal");

						RS = *get(i.rs);
						RT = *get(i.rt);

						assert(RT.isString(), "trying to new a non-string global");

						MDNamespace env = mCurrentAR.env;
						MDValue* val = env[RT.as!(MDString)];

						if(val !is null)
							throwRuntimeException("Attempting to create global '%s' that already exists", RT.toString());

						env[RT.as!(MDString)] = RS;
						break;

					// Logical and Control Flow
					case Op.Not:
						debug(TIMINGS) scope _profiler_ = new Profiler("Not");
						*get(i.rd) = get(i.rs).isFalse();
						break;

					case Op.Cmp:
						Instruction jump = *mCurrentAR.pc;
						mCurrentAR.pc++;

						int cmpValue = compare(get(i.rs), get(i.rt));

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

					case Op.Cmp3:
						*get(i.rd) = compare(get(i.rs), get(i.rt));
						break;

					case Op.SwitchCmp:
						debug(TIMINGS) scope _profiler_ = new Profiler("SwitchCmp");

						RS = *get(i.rs);
						RT = *get(i.rt);

						Instruction jump = *mCurrentAR.pc;
						mCurrentAR.pc++;

						int cmpValue = 1;

						if(RS.type == RT.type)
						{
							switch(RS.type)
							{
								case MDValue.Type.Null:
									cmpValue = 0;
									break;

								case MDValue.Type.Bool:
									cmpValue = (cast(int)RS.as!(bool) - cast(int)RT.as!(bool));
									break;
									
								case MDValue.Type.Int:
									cmpValue = RS.as!(int) - RT.as!(int);
									break;

								case MDValue.Type.Float:
									mdfloat f1 = RS.as!(mdfloat);
									mdfloat f2 = RT.as!(mdfloat);
									
									if(f1 < f2)
										cmpValue = -1;
									else if(f1 > f2)
										cmpValue = 1;
									else
										cmpValue = 0;
									break;

								case MDValue.Type.Char:
									cmpValue = RS.as!(dchar) - RT.as!(dchar);
									break;

								default:
									MDObject o1 = RS.as!(MDObject);
									MDObject o2 = RT.as!(MDObject);

									if(o1 is o2)
										cmpValue = 0;
									else
									{
										MDValue* method = getMM(RS, MM.Cmp);

										if(method.isFunction())
										{
											mNativeCallDepth++;

											scope(exit)
												mNativeCallDepth--;

											uint funcReg = push(method);
											push(RS);
											push(RT);
											call(funcReg, 2, 1);
											MDValue ret = pop();

											if(!ret.isInt())
												throwRuntimeException("opCmp is expected to return an int, not '%s', for type '%s'", ret.typeString(), RS.typeString());
												
											cmpValue = ret.as!(int);
										}
										else
											cmpValue = MDObject.compare(o1, o2);
									}
									break;
							}
						}

						assert(jump.opcode == Op.Je && jump.rd == 1, "invalid 'swcmp' jump");

						if(cmpValue == 0)
							mCurrentAR.pc += jump.imm;

						break;

					case Op.Is:
						debug(TIMINGS) scope _profiler_ = new Profiler("Is");

						Instruction jump = *mCurrentAR.pc;
						mCurrentAR.pc++;

						assert(jump.opcode == Op.Je, "invalid 'is' jump");

						if(get(i.rs).opEquals(get(i.rt)) == jump.rd)
							mCurrentAR.pc += jump.imm;

						break;
	
					case Op.IsTrue:
						debug(TIMINGS) scope _profiler_ = new Profiler("IsTrue");

						Instruction jump = *mCurrentAR.pc;
						mCurrentAR.pc++;

						assert(jump.opcode == Op.Je, "invalid 'istrue' jump");

						if(get(i.rs).isTrue() == cast(bool)jump.rd)
							mCurrentAR.pc += jump.imm;

						break;
	
					case Op.Jmp:
						debug(TIMINGS) scope _profiler_ = new Profiler("Jmp");

						if(i.rd != 0)
							mCurrentAR.pc += i.imm;
						break;
						
					case Op.Switch:
						debug(TIMINGS) scope _profiler_ = new Profiler("Switch");

						RS = *get(i.rs);

						auto t = &mCurrentAR.func.script.func.mSwitchTables[i.rt];
						int offset;
						int* ptr = (RS in t.offsets);

						if(ptr is null)
							offset = t.defaultOffset;
						else
							offset = *ptr;

						if(offset == -1)
							throwRuntimeException("Switch without default");

						mCurrentAR.pc += offset;
						break;

					case Op.Close:
						debug(TIMINGS) scope _profiler_ = new Profiler("Close");
						close(i.rd);
						break;
						
					case Op.For:
						debug(TIMINGS) scope _profiler_ = new Profiler("For");
						MDValue* idx = getBasedStack(i.rd);
						MDValue* hi = getBasedStack(i.rd + 1);
						MDValue* step = getBasedStack(i.rd + 2);
						
						if(!idx.isInt() || !hi.isInt() || !step.isInt())
							throwRuntimeException("Numeric for loop low, high, and step values must be integers");
						
						int intIdx = idx.as!(int);
						int intHi = hi.as!(int);
						int intStep = step.as!(int);

						if(intStep == 0)
							throwRuntimeException("Numeric for loop step value may not be 0");

						if(intIdx > intHi && intStep > 0 || intIdx < intHi && intStep < 0)
							intStep = -intStep;

						if(intStep < 0)
							*idx = intIdx + intStep;
						
						*step = intStep;

						mCurrentAR.pc += i.imm;
						break;

					case Op.ForLoop:
						debug(TIMINGS) scope _profiler_ = new Profiler("ForLoop");
						int idx = mStack[mCurrentAR.base + i.rd].as!(int);
						int hi = mStack[mCurrentAR.base + i.rd + 1].as!(int);
						int step = mStack[mCurrentAR.base + i.rd + 2].as!(int);

						if(step > 0)
						{
							if(idx < hi)
							{
								mStack[mCurrentAR.base + i.rd + 3] = idx;
								mStack[mCurrentAR.base + i.rd] = idx + step;
								mCurrentAR.pc += i.imm;
							}
						}
						else
						{
							if(idx >= hi)
							{
								mStack[mCurrentAR.base + i.rd + 3] = idx;
								mStack[mCurrentAR.base + i.rd] = idx + step;
								mCurrentAR.pc += i.imm;
							}
						}
						break;

					case Op.Foreach:
						debug(TIMINGS) scope _profiler_ = new Profiler("Foreach");

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

							mNativeCallDepth++;

							scope(exit)
								mNativeCallDepth--;

							copyBasedStack(rd + 2, rd + 1);
							*getBasedStack(rd + 1) = src;
							*getBasedStack(rd) = *apply;

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
						debug(TIMINGS) scope _profiler_ = new Profiler("PushCatch");

						pushTR();

						mCurrentTR.isCatch = true;
						mCurrentTR.catchVarSlot = i.rd;
						mCurrentTR.pc = mCurrentAR.pc + i.imm;
						break;

					case Op.PushFinally:
						debug(TIMINGS) scope _profiler_ = new Profiler("PushFinally");

						pushTR();
						
						mCurrentTR.isCatch = false;
						mCurrentTR.pc = mCurrentAR.pc + i.imm;
						break;
						
					case Op.PopCatch:
						debug(TIMINGS) scope _profiler_ = new Profiler("PopCatch");

						assert(mCurrentTR.isCatch, "'catch' popped out of order");

						popTR();
						break;
	
					case Op.PopFinally:
						debug(TIMINGS) scope _profiler_ = new Profiler("PopFinally");

						assert(!mCurrentTR.isCatch, "'finally' popped out of order");

						currentException = null;

						popTR();
						break;
	
					case Op.EndFinal:
						debug(TIMINGS) scope _profiler_ = new Profiler("EndFinal");

						if(currentException !is null)
							throw currentException;

						break;
	
					case Op.Throw:
						debug(TIMINGS) scope _profiler_ = new Profiler("Throw");

						throwRuntimeException(*get(i.rs));
						break;

					// Function Calling
					case Op.Method:
						debug(TIMINGS) scope _profiler_ = new Profiler("Method");

						Instruction call = *mCurrentAR.pc;
						mCurrentAR.pc++;
						assert(i.rd == call.rd, "Op.Method");

						MDString methodName = constTable[i.rt].as!(MDString);
						
						RS = *get(i.rs);
						mStack[mCurrentAR.base + i.rd + 1] = RS;
						mStack[mCurrentAR.base + i.rd] = lookupMethod(&RS, methodName);

						if(call.opcode == Op.Call)
						{
							int funcReg = call.rd;
							int numParams = call.rs - 1;
							int numResults = call.rt - 1;
	
							if(numParams == -1)
								numParams = getBasedStackIndex() - funcReg - 1;
	
							if(callPrologue(funcReg, numResults, numParams) == true)
							{
								depth++;
								constTable = mCurrentAR.func.script.func.mConstants;
							}
						}
						else
						{
							assert(call.opcode == Op.Tailcall, "Op.Method invalid call opcode");
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
								
							constTable = mCurrentAR.func.script.func.mConstants;
						}
						
						break;

					case Op.Precall:
						debug(TIMINGS) scope _profiler_ = new Profiler("Precall");

						if(i.rt == 1)
							RS = *get(i.rs, getBasedStack(i.rd + 1));
						else
							RS = *get(i.rs);

						if(i.rd != i.rs)
							*getBasedStack(i.rd) = RS;

						Instruction call = *mCurrentAR.pc;
						mCurrentAR.pc++;

						if(call.opcode == Op.Call)
						{
							int funcReg = call.rd;
							int numParams = call.rs - 1;
							int numResults = call.rt - 1;

							if(numParams == -1)
								numParams = getBasedStackIndex() - funcReg - 1;

							if(callPrologue(funcReg, numResults, numParams) == true)
							{
								depth++;
								constTable = mCurrentAR.func.script.func.mConstants;
							}
						}
						else
						{
							assert(call.opcode == Op.Tailcall, "Op.Precall invalid call opcode");

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

							{
								scope(failure)
									--depth;

								if(callPrologue(absIndexToBased(destReg), numReturns, numParams) == false)
									--depth;
							}

							if(depth == 0)
								return;
								
							constTable = mCurrentAR.func.script.func.mConstants;
						}
						
						break;

					case Op.Ret:
						debug(TIMINGS) scope _profiler_ = new Profiler("Ret");

						int numResults = i.imm - 1;

						close(0);
						callEpilogue(i.rd, numResults);
						--depth;

						if(depth == 0)
							return;

						constTable = mCurrentAR.func.script.func.mConstants;
						break;

					case Op.Vararg:
						debug(TIMINGS) scope _profiler_ = new Profiler("Vararg");

						int numNeeded = i.imm - 1;
						int numVarargs = mCurrentAR.base - mCurrentAR.vargBase;
	
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

					case Op.Yield:
						if(mNativeCallDepth > 0)
							throwRuntimeException("Attempting to yield across native / metamethod call boundary");

						uint firstValue = basedIndexToAbs(i.rd);

						pushAR();

						*mCurrentAR = mActRecs[mARIndex - 1];
						mCurrentAR.funcSlot = firstValue;
						mCurrentAR.numReturns = i.rt - 1;

						uint numValues = i.rs - 1;

						if(numValues == -1)
							mNumYields = mStackIndex - firstValue;
						else
						{
							mStackIndex = firstValue + numValues;
							mNumYields = numValues;
						}

						mSavedCallDepth = depth;
						mState = State.Suspended;
						return;

					// Array and List Operations
					case Op.Length:
						*get(i.rd) = operatorLength(get(i.rs));
						break;

					case Op.SetArray:
						debug(TIMINGS) scope _profiler_ = new Profiler("SetArray");

						uint sliceBegin = mCurrentAR.base + i.rd + 1;
						int numElems = i.rs - 1;

						if(numElems == -1)
						{
							mStack[mCurrentAR.base + i.rd].as!(MDArray).setBlock(i.rt, mStack[sliceBegin .. mStackIndex]);
							mStackIndex = mCurrentAR.savedTop;
							
							debug(STACKINDEX) writefln("SetArray set mStackIndex to ", mStackIndex);
						}
						else
							mStack[mCurrentAR.base + i.rd].as!(MDArray).setBlock(i.rt, mStack[sliceBegin .. sliceBegin + numElems]);

						break;

					case Op.Cat:
						int numElems = i.rt - 1;
						MDValue[] vals;

						if(numElems == -1)
						{
							vals = mStack[mCurrentAR.base + i.rs .. mStackIndex];
							mStackIndex = mCurrentAR.savedTop;
							debug(STACKINDEX) writefln("Op.Cat set mStackIndex to ", mStackIndex);
						}
						else
							vals = mStack[mCurrentAR.base + i.rs .. mCurrentAR.base + i.rs + numElems];
							
						*get(i.rd) = operatorCat(vals);
						break;

					case Op.CatEq:
						int numElems = i.rt - 1;
						MDValue[] vals;
						
						if(numElems == -1)
						{
							vals = mStack[mCurrentAR.base + i.rs .. mStackIndex];
							mStackIndex = mCurrentAR.savedTop;
						}
						else
							vals = mStack[mCurrentAR.base + i.rs .. mCurrentAR.base + i.rs + numElems];
							
						operatorCatAssign(get(i.rd), vals);
						break;

					case Op.Index:
						debug(TIMINGS) scope _profiler_ = new Profiler("Index");
						*get(i.rd) = operatorIndex(get(i.rs), get(i.rt));
						break;

					case Op.IndexAssign:
						debug(TIMINGS) scope _profiler_ = new Profiler("IndexAssign");
						operatorIndexAssign(get(i.rd), get(i.rs), get(i.rt));
						break;

					case Op.Slice:
						debug(TIMINGS) scope _profiler_ = new Profiler("Slice");
						*get(i.rd) = operatorSlice(getBasedStack(i.rs), getBasedStack(i.rs + 1), getBasedStack(i.rs + 2));
						break;

					case Op.SliceAssign:
						debug(TIMINGS) scope _profiler_ = new Profiler("SliceAssign");
						operatorSliceAssign(getBasedStack(i.rd), getBasedStack(i.rd + 1), getBasedStack(i.rd + 2), get(i.rs));
						break;

					case Op.NotIn:
						*get(i.rd) = !operatorIn(get(i.rs), get(i.rt));
						break;

					case Op.In:
						*get(i.rd) = operatorIn(get(i.rs), get(i.rt));
						break;

					// Value Creation
					case Op.NewArray:
						debug(TIMINGS) scope _profiler_ = new Profiler("NewArray");
						*getBasedStack(i.rd) = new MDArray(i.imm);
						break;

					case Op.NewTable:
						debug(TIMINGS) scope _profiler_ = new Profiler("NewTable");
						*getBasedStack(i.rd) = new MDTable();
						break;

					case Op.Closure:
						debug(TIMINGS) scope _profiler_ = new Profiler("Closure");

						MDFuncDef newDef = mCurrentAR.func.script.func;
						assert(i.imm < newDef.mInnerFuncs.length, "invalid inner func index");
						newDef = newDef.mInnerFuncs[i.imm];
						
						MDClosure n = new MDClosure(mCurrentAR.env, newDef);

						for(int index = 0; index < newDef.mNumUpvals; index++)
						{
							assert(mCurrentAR.pc.opcode == Op.Move, "invalid closure upvalue op");

							if(mCurrentAR.pc.rd == 0)
								n.script.upvals[index] = findUpvalue(mCurrentAR.pc.rs);
							else
							{
								assert(mCurrentAR.pc.rd == 1, "invalid closure upvalue rd");
								n.script.upvals[index] = mCurrentAR.func.script.upvals[mCurrentAR.pc.imm];
							}
	
							mCurrentAR.pc++;
						}

						*get(i.rd) = n;
						break;

					case Op.Class:
						debug(TIMINGS) scope _profiler_ = new Profiler("Class");

						RS = *get(i.rs);
						RT = *get(i.rt);

						if(RT.isNull())
							*get(i.rd) = new MDClass(RS.as!(dchar[]), null);
						else if(!RT.isClass())
							throwRuntimeException("Attempted to derive a class from a value of type '%s'", RT.typeString());
						else
							*get(i.rd) = new MDClass(RS.as!(dchar[]), RT.as!(MDClass));

						break;
						
					case Op.Coroutine:
						debug(TIMINGS) scope _profiler_ = new Profiler("Coroutine");
						
						RS = *get(i.rs);
						
						if(!RS.isFunction() || RS.as!(MDClosure).isNative)
							throwRuntimeException("Coroutines must be created with a script function, not '%s'", RS.typeString());

						*get(i.rd) = new MDState(RS.as!(MDClosure));
						break;
						
					// Class stuff
					case Op.As:
						debug(TIMINGS) scope _profiler_ = new Profiler("As");

						RS = *get(i.rs);
						RT = *get(i.rt);

						if(!RS.isInstance() || !RT.isClass())
							throwRuntimeException("Attempted to perform 'as' on '%s' and '%s'; must be 'instance' and 'class'",
								RS.typeString(), RT.typeString());

						if(RS.as!(MDInstance).castToClass(RT.as!(MDClass)))
							*get(i.rd) = RS;
						else
							get(i.rd).setNull();

						break;
						
					case Op.Super:
						debug(TIMINGS) scope _profiler_ = new Profiler("Super");

						RS = *get(i.rs);

						if(RS.isInstance())
							*get(i.rd) = RS.as!(MDInstance).getClass().superClass();
						else if(RS.isClass())
							*get(i.rd) = RS.as!(MDClass).superClass();
						else
							throwRuntimeException("Can only get superclass of classes and instances, not '%s'", RS.typeString());

						break;

					case Op.ClassOf:
						debug(TIMINGS) scope _profiler_ = new Profiler("ClassOf");

						RS = *get(i.rs);

						if(RS.isInstance())
							*get(i.rd) = RS.as!(MDInstance).getClass();
						else
							throwRuntimeException("Can only get class of instances, not '%s'", RS.typeString());

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
				Traceback ~= getDebugLocation();

				while(mCurrentTR.actRecord is mARIndex)
				{
					TryRecord tr = *mCurrentTR;
					popTR();

					if(tr.isCatch)
					{
						*getBasedStack(tr.catchVarSlot) = e.value;

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

				if(depth > 0)
					constTable = mCurrentAR.func.script.func.mConstants;
			}

			throw e;
		}
	}
}