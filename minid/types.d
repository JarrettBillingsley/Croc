module minid.types;

import utf = std.utf;
import string = std.string;
import format = std.format;
import std.c.string;

import minid.opcodes;
import minid.state;

const uint MaxRegisters = Instruction.rs1Max >> 1;
const uint MaxConstants = Instruction.immMax;
const uint MaxUpvalues = Instruction.immMax;

char[] vformat(TypeInfo[] arguments, void* argptr)
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
	public this(...)
	{
		super(vformat(_arguments, _argptr));
	}
}

int dcmp(dchar[] s1, dchar[] s2)
{
    auto len = s1.length;
    int result;

    //printf("cmp('%.*s', '%.*s')\n", s1, s2);
    if (s2.length < len)
	len = s2.length;
    result = memcmp(s1, s2, len);
    if (result == 0)
	result = cast(int)s1.length - cast(int)s2.length;
    return result;
}

abstract class MDObject
{
	public uint length();
	
	// avoiding RTTI downcasts for speed
	public MDString asString() { return null; }
	public MDUserData asUserData() { return null; }
	public MDClosure asClosure() { return null; }
	public MDTable asTable() { return null; }
	public MDArray asArray() { return null; }
}

class MDString : MDObject
{
	protected dchar[] mData;
	
	public override MDString asString()
	{
		return this;
	}

	public this(dchar[] data)
	{
		mData = data.dup;
	}
	
	public this(char[] data)
	{
		mData = utf.toUTF32(data);
	}

	public override uint length()
	{
		return mData.length;
	}
	
	public MDString opCat(MDString other)
	{
		return new MDString(this.mData ~ other.mData);
	}
	
	public MDString opCatAssign(MDString other)
	{
		return opCat(other);
	}
	
	public int opEquals(Object o)
	{
		MDString other = cast(MDString)o;
		assert(other);
		
		return mData == other.mData;
	}
	
	public int opCmp(Object o)
	{
		MDString other = cast(MDString)o;
		assert(other);
		
		return dcmp(mData, other.mData);
	}
	
	public int opEquals(char[] v)
	{
		return mData == utf.toUTF32(v);
	}

	public int opCmp(char[] v)
	{
		return dcmp(mData, utf.toUTF32(v));
	}
	
	public int opEquals(dchar[] v)
	{
		return mData == v;
	}

	public int opCmp(dchar[] v)
	{
		return dcmp(mData, v);
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
	public static MDString concat(MDValue[] values)
	{
		uint l = 0;

		foreach(MDValue v; values)
		{
			if(v.isString() == false)
				return null;
				
			l += v.asString().length;
		}
		
		dchar[] result = new dchar[l];
		
		uint i = 0;
		
		foreach(MDValue v; values)
		{
			MDString s = v.asString();
			result[i .. i + s.length] = s.mData[];
			i += s.length;
		}
		
		return new MDString(result);
	}
	
	public char[] toString()
	{
		return utf.toUTF8(mData);
	}
}

class MDUserData : MDObject
{
	public override MDUserData asUserData()
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
}

class MDClosure : MDObject
{
	protected bool mIsNative;
	
	struct NativeClosure
	{
		int delegate(MDState) func;
		MDValue[] upvals;
	}
	
	struct ScriptClosure
	{
		MDFuncDef func;
		MDUpval[] upvals;
	}
	
	union
	{
		NativeClosure native;
		ScriptClosure script;
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
		return string.format("closure 0x%0.8X", cast(void*)this);
	}
	
	public bool isNative()
	{
		return mIsNative;
	}
}

class MDTable : MDObject
{
	protected MDValue[MDValue] mData;
	protected MDTable mMetatable;
	
	public override MDTable asTable()
	{
		return this;
	}

	public MDValue opIndex(MDValue index)
	{
		MDValue* v = (index in mData);

		if(v is null)
		{
			MDValue ret;
			ret.setNull();
			return ret;
		}
		else
			return *v;
	}

	public MDValue opIndexAssign(MDValue value, MDValue index)
	{
		mData[index] = value;
		return value;
	}

	public override uint length()
	{
		return mData.length;
	}
	
	public char[] toString()
	{
		return string.format("table 0x%0.8X", cast(void*)this);
	}
}

class MDArray : MDObject
{
	protected MDValue[] mData;
	
	public override MDArray asArray()
	{
		return this;
	}

	public override uint length()
	{
		return mData.length;
	}
	
	public char[] toString()
	{
		return string.format("array 0x%0.8X", cast(void*)this);
	}
}

struct MDValue
{
	public static enum Type
	{
		None = -1,
		
		// Non-object types
		Null,
		Bool,
		Int,
		Float,

		// Object types
		String,
		Table,
		Array,
		Function,
		UserData
	}

	private Type mType = Type.None;

	union
	{
		// Non-object types
		private bool mBool;
		private int mInt;
		private float mFloat;
	}
	
	// Object types
	// This has to be outside the union, so the GC doesn't confuse other types of
	// values for a pointer.
	private MDObject mObj;

	public int opEquals(MDValue* other)
	{
		if(this.mType != other.mType)
			return 0;

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

			default:
				assert(this.mType != Type.None);
				return this.mObj.opEquals(other.mObj);
		}
	}

	public int opCmp(MDValue* other)
	{
		if(this.mType != other.mType)
			return (cast(int)this.mType - cast(int)other.mType);

		switch(this.mType)
		{
			case Type.Null:
				return 0;

			case Type.Bool:
				return (cast(int)this.mBool - cast(int)other.mBool);

			case Type.Int:
				if(this.mInt < other.mInt)
					return -1;
				else if(this.mInt > other.mInt)
					return 1;
				else
					return 0;
					
			case Type.Float:
				if(this.mFloat < other.mFloat)
					return -1;
				else if(this.mFloat > other.mFloat)
					return 1;
				else
					return 0;

			default:
				assert(this.mType != Type.None);
				return this.mObj.opCmp(other.mObj);
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

			default:
				assert(mType != Type.None);
				return mObj.toHash();
		}
	}
	
	public Type type()
	{
		return mType;
	}
	
	public bool isNone()
	{
		return (mType == Type.None);
	}
	
	public bool isNull()
	{
		return (mType == Type.Null);
	}
	
	public bool isNoneOrNull()
	{
		return (mType == Type.None || mType == Type.Null);
	}
	
	public bool isBool()
	{
		return (mType == Type.Bool);
	}

	public bool isInt()
	{
		return (mType == Type.Int);
	}
	
	public bool isFloat()
	{
		return (mType == Type.Float);
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
	
	public bool isUserData()
	{
		return (mType == Type.UserData);
	}
	
	public bool asBool()
	{
		assert(mType == Type.Bool);
		return mBool;
	}

	public int asInt()
	{
		assert(mType == Type.Int);
		return mInt;
	}

	public float asFloat()
	{
		assert(mType == Type.Float);
		return mFloat;
	}

	public MDObject asObj()
	{
		assert(cast(uint)mType >= cast(uint)Type.String);
		return mObj;
	}

	public MDString asString()
	{
		assert(mType == Type.String);
		return mObj.asString();
	}
	
	public MDUserData asUserData()
	{
		assert(mType == Type.UserData);
		return mObj.asUserData();
	}

	public MDClosure asFunction()
	{
		assert(mType == Type.Function);
		return mObj.asClosure();
	}

	public MDTable asTable()
	{
		assert(mType == Type.Table);
		return mObj.asTable();
	}
	
	public MDArray asArray()
	{
		assert(mType == Type.Array);
		return mObj.asArray();
	}

	public bool isFalse()
	{
		return (mType == Type.Null) || (mType == Type.Bool && mBool == false) ||
			(mType == Type.Int && mInt == 0) || (mType == Type.Float && mFloat == 0.0);
	}
	
	public void setNull()
	{
		mType = Type.Null;
		mObj = null;
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

	public void value(MDString s)
	{
		mType = Type.String;
		mObj = s;
	}
	
	public void value(MDUserData ud)
	{
		mType = Type.UserData;
		mObj = ud;
	}
	
	public void value(MDClosure f)
	{
		mType = Type.Function;
		mObj = f;
	}
	
	public void value(MDTable t)
	{
		mType = Type.Table;
		mObj = t;
	}
	
	public void value(MDArray a)
	{
		mType = Type.Array;
		mObj = a;
	}

	public void value(MDValue v)
	{
		mType = v.mType;
		
		switch(mType)
		{
			case Type.None, Type.Null:
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
				
			default:
				mObj = v.mObj;
				break;
		}
	}

	public char[] toString()
	{
		switch(mType)
		{
			case Type.None:
				return "none";
				
			case Type.Null:
				return "null";
				
			case Type.Bool:
				return string.toString(mBool);
				
			case Type.Int:
				return string.toString(mInt);
				
			case Type.Float:
				return string.toString(mFloat);
				
			default:
				return mObj.toString();
		}
	}
}

struct MDUpval
{
	// When open (parent scope is still on the stack), this points to a stack slot
	// which holds the value.  When the parent scope exits, the value is copied from
	// the stack into the closedValue member, and this points to closedMember.  
	// This means data should only ever be accessed through this member.
	MDValue* value;

	union
	{
		MDValue closedValue;
		
		// For the open upvalue doubly-linked list.
		struct
		{
			MDUpval* next;
			MDUpval* prev;
		}
	}
}

struct Location
{
	public uint line = 1;
	public uint column = 1;
	public char[] fileName;

	public static Location opCall(char[] fileName, uint line = 1, uint column = 1)
	{
		Location l;
		l.fileName = fileName;
		l.line = line;
		l.column = column;
		return l;
	}

	public char[] toString()
	{
		return string.format("%s(%d:%d)", fileName, line, column);
	}
}

class MDFuncDef
{
	package bool mIsVararg;
	package Location mLocation;
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
		char[] name;
		Location location;
		uint reg;
	}
	
	package LocVarDesc[] mLocVarDescs;
	
	struct SwitchTable
	{
		bool isString;

		union
		{
			int[] intValues;
			dchar[][] stringValues;
		}

		int[] offsets;
		int defaultOffset = -1;
	}

	package SwitchTable[] mSwitchTables;
}