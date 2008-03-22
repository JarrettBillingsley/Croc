/******************************************************************************
The main header file of the MiniD interpreter.  This file defines all the basic types
of MiniD, as well as the MDState type, which is the interpreter (and doubles as the
'thread' type for coroutines).

It makes me sad to have to have so much stuff in one file, but D just can't handle
circular imports (which would be necessary for splitting this up) without throwing
up all over itself in a flurry of forward declaration/reference errors.  Sigh, if
only it followed the spec where it says "things to drop: forward declarations."

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

import tango.core.Array;
import tango.core.Thread;
import tango.core.Vararg;
import tango.io.FileConduit;
import tango.io.FilePath;
import tango.io.FileSystem;
import tango.io.protocol.model.IReader;
import tango.io.protocol.model.IWriter;
import tango.io.protocol.Reader;
import tango.io.protocol.Writer;
import tango.io.Stdout;
import tango.stdc.string : memcmp;
import tango.text.Ascii;
import Float = tango.text.convert.Float;
import Integer = tango.text.convert.Integer;
import utf = tango.text.convert.Utf;
import tango.text.Util;

import minid.opcodes;
import minid.utils;

// debug = STACKINDEX;
// debug = CALLEPILOGUE;

/**
The root of the MiniD exception hierarchy.

All exceptions in MiniD derive from this class.  In order to be compatible with the scripting language,
where values of any type can be thrown as exceptions, it has a public member which exposes this value.
*/
class MDException : Exception
{
	/**
	The MiniD value which is used if the exception is caught by a catch statement in MiniD code.
	*/
	public MDValue value;

	/**
	Construct an MDException using a format string and a list of arguments, using Tango-style formatting.
	The string will be formatted, and assigned into the value member as well.
	*/
	public this(char[] fmt, ...)
	{
		this(fmt, _arguments, _argptr);
	}

	/**
	Like above, but for when you already have the two variadic parameters from another variadic function.
	*/
	public this(char[] fmt, TypeInfo[] arguments, va_list argptr)
	{
		char[] msg = Stdout.layout.convert(arguments, argptr, fmt);
		value = new MDString(msg);
		super(msg);
	}

	/**
	Construct an MDException from an MDValue.  It will be assigned to the value member, and the string
	representation of it (not calling toString metamethods) will be used as the exception message.
	*/
	public this(MDValue val)
	{
		this(&val);
	}

	/**
	Like above, but for MDValue pointers instead.
	*/
	public this(MDValue* val)
	{
		value = *val;
		super(value.toString());
	}
}

/**
Thrown by the compiler whenever there's a compilation error.

The message will be in the form "filename(line:colunm): error message".
*/
class MDCompileException : MDException
{
	/**
	Indicates whether the compiler threw this at the end of the file or not.  If this is
	true, this might be because the compiler ran out of input, in which case the code could
	be made to compile by adding more code.
	*/
	bool atEOF = false;

	/**
	Takes the location of the error, and a variadic list of Tango-style formatted arguments.
	*/
	public this(Location loc, char[] fmt, ...)
	{
		super("{}: {}", loc.toString(), Stdout.layout.convert(_arguments, _argptr, fmt));
	}
}

/**
Thrown to indicate an error at run-time, often by the interpreter but not always.

This class includes a location of where the exception was thrown.
*/
class MDRuntimeException : MDException
{
	/**
	The location of where the exception was thrown.  This may not be entirely accurate,
	depending on whether or not debug information was compiled into the bytecode, who
	threw the exception etc.
	*/
	public Location location;

	/**
	Constructs the exception from a location and an MDValue pointer to the value to be thrown.
	*/
	public this(Location loc, MDValue* val)
	{
		location = loc;
		super(val);
	}

	/**
	Constructs the exception from a location and Tango-style formatted arguments.
	*/
	public this(Location loc, char[] fmt, ...)
	{
		this(loc, fmt, _arguments, _argptr);
	}

	/**
	Like above, but takes the variadic function parameters instead.
	*/
	public this(Location loc, char[] fmt, TypeInfo[] arguments, va_list argptr)
	{
		location = loc;
		super(fmt, arguments, argptr);
	}

	/**
	Overridden to include the location in the error message.  Note that the result of this
	is in the format "filename(line:instruction): error message".  The 'instruction' in this
	message is the index of the instruction in the bytecode that caused the exception, and
	is mostly meant for low-level debugging.
	*/
	public char[] toString()
	{
		return Stdout.layout.convert("{}: {}", location.toString(), msg);
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

/**
The basic variant data type which represents a MiniD value.

This structure is the underlying representation of every variable, array slot, table key/value
etc. that appears in the language.  It is a variant type which can hold any of the language types.
It's a simple tagged union, with a 4-byte type and an 8-byte data segment (large enough to hold
a double-precision floating-point value, the largest type that it can hold).
*/
align(1) struct MDValue
{
	/**
	Enumerates the basic datatypes of MiniD.  See the 'Types' section of the spec for more info.
	*/
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

	/**
	A static MDValue instance which should always, always hold 'null'.  There is an invariant
	which ensures this.  This is mostly used by functions which need to return a pointer to a
	null MDValue, rather than returning an actual null pointer.  You can also use this any time
	you need a null MDValue in your D code.
	*/
	public static MDValue nullValue = { mType : Type.Null, mInt : 0 };

	invariant
	{
		assert(nullValue.mType == Type.Null, "nullValue is not null.  OH NOES");
	}

	private Type mType = Type.Null;

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
	
	/**
	The "constructor" for the struct.  It's templated based on the parameter, and all it does is
	call opAssign, so see opAssign for more info.
	*/
	public static MDValue opCall(T)(T value)
	{
		MDValue ret;
		ret = value;
		return ret;
	}

	/**
	Returns true if this and the other value are exactly the same type and the same value.  The semantics
	of this are exactly the same as the 'is' expression in MiniD.
	*/
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
	
	/**
	This is mostly overridden for using MDValues as AA keys.  You probably shouldn't use this for
	comparing MDValues in general, because (1) it will return 'less' or 'greater' for values which are
	different types, which doesn't really make sense, and (2) will not call opCmp metamethods.
	*/
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
				return Compare3(this.mInt, other.mInt);

			case Type.Float:
				return Compare3(this.mFloat, other.mFloat);

			case Type.Char:
				return Compare3(this.mChar, other.mChar);

			default:
				if(this.mObj is other.mObj)
					return 0;

				return MDObject.compare(this.mObj, other.mObj);
		}

		assert(false);
	}

	/**
	Compares this to another MDValue in a more sensible way.  If the two objects are different types, and are not
	both numeric types (int or float), an exception will be thrown.  Integers will automatically be cast to floats
	when comparing an int and a float.  This function still does not call opCmp metamethods, however; you should use
	the APIs in the MDState class for the best comparison.
	*/
	public int compare(MDValue* other)
	{
		if(!(isNum() && other.isNum()) && this.mType != other.mType)
			throw new MDException("Attempting to compare unlike objects ({} to {})", typeString(), other.typeString());

		switch(this.mType)
		{
			case Type.Null:
				return 0;

			case Type.Bool:
				return (cast(int)this.mBool - cast(int)other.mBool);

			case Type.Int:
				if(other.mType == Type.Float)
					return Compare3(cast(mdfloat)this.mInt, other.mFloat);
				else
					return Compare3(this.mInt, other.mInt);

			case Type.Float:
				if(other.mType == Type.Int)
					return Compare3(this.mFloat, cast(mdfloat)other.mInt);
				else
					return Compare3(this.mFloat, other.mFloat);

			case Type.Char:
				return this.mChar < other.mChar ? -1 : this.mChar > other.mChar ? 1 : 0;

			default:
				if(this.mObj is other.mObj)
					return 0;

				return MDObject.compare(this.mObj, other.mObj);
		}

		return -1;
	}
	
	/**
	Overridden to allow the use of MDValues as AA keys.
	*/
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
	
	/**
	Gets the length of the MDValue, which will fail (throw an exception) if getting the length
	makes no sense for the MDValue's type.  Does not call opLength metamethods.
	*/
	public uint length()
	{
		switch(mType)
		{
			case Type.Null:
			case Type.Bool:
			case Type.Int:
			case Type.Float:
			case Type.Char:
				throw new MDException("Attempting to get length of {} value", typeString());

			default:
				return mObj.length();
		}
	}
	
	/**
	Returns the current type of this value, as a value from the MDValue.Type enumeration.
	*/
	public Type type()
	{
		return mType;
	}

	/**
	A static method which, given a value from the MDValue.Type enumeration, will give the
	string representation of that type.
	*/
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

	/**
	Gets a string representation of the type of this value.  Differs from passing the type
	into the static typeString() function in that it will include the name of the class if
	this is a class or instance value.
	*/
	public dchar[] typeString()
	{
		if(mType == Type.Class)
			return "class " ~ mClass.mGuessedName;
		else if(mType == Type.Instance)
			return "instance of class " ~ mInstance.mClass.mGuessedName;
		else
			return typeString(mType);
	}

	/**
	These return true if this is the given type, and false otherwise.
	*/
	public bool isNull()
	{
		return (mType == Type.Null);
	}

	/// ditto
	public bool isBool()
	{
		return (mType == Type.Bool);
	}
	
	/// ditto
	public bool isNum()
	{
		return (mType == Type.Int) || (mType == Type.Float);
	}

	/// ditto
	public bool isInt()
	{
		return (mType == Type.Int);
	}

	/// ditto
	public bool isFloat()
	{
		return (mType == Type.Float);
	}

	/// ditto
	public bool isChar()
	{
		return (mType == Type.Char);
	}

	/// ditto
	public bool isObj()
	{
		return (cast(uint)mType >= Type.String);
	}

	/// ditto
	public bool isString()
	{
		return (mType == Type.String);
	}

	/// ditto
	public bool isTable()
	{
		return (mType == Type.Table);
	}

	/// ditto
	public bool isArray()
	{
		return (mType == Type.Array);
	}

	/// ditto
	public bool isFunction()
	{
		return (mType == Type.Function);
	}
	
	/// ditto
	public bool isClass()
	{
		return (mType == Type.Class);
	}

	/// ditto
	public bool isInstance()
	{
		return (mType == Type.Instance);
	}

	/// ditto
	public bool isNamespace()
	{
		return (mType == Type.Namespace);
	}

	/// ditto
	public bool isThread()
	{
		return (mType == Type.Thread);
	}

	/**
	Returns true if this value is false (null, 'false', an integer with the value 0, a float
	with the value 0.0, or a NUL ('\0') character).
	*/
	public bool isFalse()
	{
		return (mType == Type.Null) || (mType == Type.Bool && mBool == false) ||
			(mType == Type.Int && mInt == 0) || (mType == Type.Float && mFloat == 0.0) || (mType == Type.Char && mChar != 0);
	}
	
	/**
	Returns the opposite of isFalse().
	*/
	public bool isTrue()
	{
		return !isFalse();
	}

	/**
	A templated method which checks if this value can be converted to the given D type.  Array
	and AA types will check the entire contents of the Array or Table (if the value is one) to make
	sure all the elements can be cast as well, so this can be a non-trivial operation for the container
	types.  .canCastTo!(floating point type)() will return true if the value is either a float or an int.
	If the value is an instance, it will check that it can be downcast to the given class instance type.
	*/
	public bool canCastTo(T)()
	{
		static if(is(T == bool))
		{
			return mType == Type.Bool;
		}
		else static if(isIntType!(realType!(T)))
		{
			return mType == Type.Int;
		}
		else static if(isFloatType!(T))
		{
			return mType == Type.Int || mType == Type.Float;
		}
		else static if(isCharType!(T))
		{
			return mType == Type.Char;
		}
		else static if(isStringType!(T) || is(T : MDString))
		{
			return mType == Type.String;
		}
		else static if(is(T : MDTable))
		{
			return mType == Type.Table;
		}
		else static if(is(T : MDArray))
		{
			return mType == Type.Array;
		}
		else static if(is(T : MDClosure))
		{
			return mType == Type.Function;
		}
		else static if(is(T : MDClass))
		{
			return mType == Type.Class;
		}
		else static if(is(T : MDInstance))
		{
			if(mType != Type.Instance)
				return false;

			static if(is(T == MDInstance))
				return true;
			else
				return (cast(T)mInstance) !is null;

		}
		else static if(is(T : MDNamespace))
		{
			return mType == Type.Namespace;
		}
		else static if(is(T : MDState))
		{
			return mType == Type.Thread;
		}
		else static if(is(T : MDObject))
		{
			return cast(uint)mType >= cast(uint)Type.String;
		}
		else static if(isArrayType!(T))
		{
			if(mType != Type.Array)
				return false;

			alias typeof(T[0]) ElemType;

			foreach(ref v; mArray)
				if(!v.canCastTo!(ElemType))
					return false;
					
			return true;
		}
		else static if(isAAType!(T))
		{
			if(mType != Type.Table)
				return false;
				
			alias typeof(T.init.keys[0]) KeyType;
			alias typeof(T.init.values[0]) ValueType;
			
			foreach(ref k, ref v; mTable)
				if(!k.canCastTo!(KeyType) || !v.canCastTo!(ValueType))
					return false;
					
			return true;
		}
		else
			return false;
	}

	/**
	A templated method which converts this value to the given D type.  This is kind of a power-user
	method, used for converting a MiniD value to a D value as long as you know in advance that this
	conversion can be done.  If the conversion can't be done, an assertion will be thrown in debug
	builds, but the behavior is undefined in release builds.
	*/
	public T as(T)()
	{
		static if(!isStringType!(T) && isArrayType!(T))
		{
			assert(mType == Type.Array, "MDValue as " ~ T.stringof);

			alias typeof(T[0]) ElemType;

			T ret = new T(mArray.length);
			
			foreach(i, ref v; mArray)
			{
				assert(v.canCastTo!(ElemType), "MDValue as " ~ T.stringof);
				ret[i] = v.as!(typeof(T[0]));
			}

			return ret;
		}
		else static if(isAAType!(T))
		{
			assert(mType == Type.Table, "MDValue as " ~ T.stringof);

			alias typeof(T.init.keys[0]) KeyType;
			alias typeof(T.init.values[0]) ValueType;

			T ret;

			foreach(ref k, ref v; mTable)
			{
				assert(k.canCastTo!(KeyType), "MDValue as " ~ T.stringof);
				assert(v.canCastTo!(ValueType), "MDValue as " ~ T.stringof);
				ret[k.as!(typeof(T.init.keys[0]))] = v.as!(typeof(T.init.values[0]));
			}

			return ret;
		}
		else
		{
			assert(canCastTo!(T)(), "MDValue as " ~ T.stringof);
			return this.convertTo!(T);
		}
	}

	/**
	A 'safer' version of .as(), this will do basically the same thing, but will throw an exception on
	a failed conversion.
	*/
	public T to(T)()
	{
		static if(!isStringType!(T) && isArrayType!(T))
		{
			if(mType != Type.Array)
				throw new MDException("MDValue.to() - Cannot convert '{}' to '" ~ T.stringof ~ "'", typeString());

			alias typeof(T[0]) ElemType;

			T ret = new T(mArray.length);

			foreach(i, ref v; mArray)
			{
				if(!v.canCastTo!(ElemType))
					throw new MDException("MDValue.to() - Cannot convert '{}' to '" ~ T.stringof ~ "': element {} should be '" ~
						ElemType.stringof ~ "', not '{}'", typeString(), v.typeString());

				ret[i] = v.as!(typeof(T[0]));
			}

			return ret;
		}
		else static if(isAAType!(T))
		{
			if(mType != Type.Table)
				throw new MDException("MDValue.to() - Cannot convert '{}' to '" ~ T.stringof ~ "'", typeString());

			alias typeof(T.init.keys[0]) KeyType;
			alias typeof(T.init.values[0]) ValueType;

			T ret;

			foreach(ref k, ref v; mTable)
			{
				if(!k.canCastTo!(KeyType))
					throw new MDException("MDValue.to() - Cannot convert '{}' to '" ~ T.stringof ~ "': key {} should be '" ~
						KeyType.stringof ~ "', not '{}'", typeString(), k.typeString());

				if(!v.canCastTo!(ValueType))
					throw new MDException("MDValue.to() - Cannot convert '{}' to '" ~ T.stringof ~ "': value {} should be '" ~
						ValueType.stringof ~ "', not '{}'", typeString(), v.typeString());

				ret[k.as!(typeof(T.init.keys[0]))] = v.as!(typeof(T.init.values[0]));
			}

			return ret;
		}
		else
		{
			if(!canCastTo!(T))
				throw new MDException("MDValue.to() - Cannot convert '{}' to '" ~ T.stringof ~ "'", typeString());

			return this.convertTo!(T);
		}
	}

	private T convertTo(T)()
	{
		static if(is(T == bool))
		{
			return mBool;
		}
		else static if(isIntType!(realType!(T)))
		{
			return cast(T)mInt;
		}
		else static if(isFloatType!(T))
		{
			if(mType == Type.Int)
				return cast(T)mInt;
			else if(mType == Type.Float)
				return mFloat;
			else
				assert(false, "MDValue.convertTo!(" ~ T.stringof ~ ")");
		}
		else static if(isCharType!(T))
		{
			return mChar;
		}
		else static if(isStringType!(T))
		{
			static if(is(T == char[]))
				return mString.asUTF8();
			else static if(is(T == wchar[]))
				return mString.asUTF16();
			else
				return mString.asUTF32();
		}
		else static if(is(T : MDString))
		{
			return mString;
		}
		else static if(is(T : MDTable))
		{
			return mTable;
		}
		else static if(is(T : MDArray))
		{
			return mArray;
		}
		else static if(is(T : MDClosure))
		{
			return mFunction;
		}
		else static if(is(T : MDClass))
		{
			return mClass;
		}
		else static if(is(T : MDInstance))
		{
			static if(is(T == MDInstance))
				return mInstance;
			else
				return cast(T)mInstance;
		}
		else static if(is(T : MDNamespace))
		{
			return mNamespace;
		}
		else static if(is(T : MDState))
		{
			return mThread;
		}
		else static if(is(T : MDObject))
		{
			return mObj;
		}
		else
		{
			// I do this because static assert won't show the template instantiation "call stack."
			pragma(msg, "MDValue.convertTo() - Invalid argument type '" ~ T.stringof ~ "'");
			ARGUMENT_ERROR(T);
		}
	}

	/**
	Sets this value to null.  You can also set a value to null by assigning it the D 'null' value.
	*/
	public void setNull()
	{
		mType = Type.Null;
		mInt = 0;
	}

	/**
	A templated opAssign which allows the assignment of many D types into an MDValue.  All reasonable
	assignments are valid.  Assignment of an array or AA to an MDValue will convert it into a MiniD
	array or table.  You can assign 'null' into an MDValue as well.  An invalid type will trigger
	a compile-time error.
	*/
	public void opAssign(T)(T src)
	{
		static if(is(T == bool))
		{
			mType = Type.Bool;
			mBool = src;
		}
		else static if(isIntType!(realType!(T)))
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
		else static if(isAAType!(T))
		{
			mType = Type.Table;
			mTable = MDTable.fromAA(src);
		}
		else
		{
			// I do this because static assert won't show the template instantiation "call stack."
			pragma(msg, "MDValue.opAssign() - Invalid argument type '" ~ T.stringof ~ "'");
			ARGUMENT_ERROR(T);
		}
	}

	/**
	Returns the string representation of the value.  Does not call toString metamethods.
	*/
	public char[] toString()
	{
		switch(mType)
		{
			case Type.Null:
				return "null";

			case Type.Bool:
				return mBool ? "true" : "false";

			case Type.Int:
				return Integer.toString(mInt);
				
			case Type.Float:
				return Float.toString(mFloat);
				
			case Type.Char:
				return utf.toString([mChar]);

			default:
				return mObj.toString();
		}
	}

	package void serialize(IWriter s)
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
	
	package static MDValue deserialize(IReader s)
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

/**
The base class for all the object (reference) types in MiniD.
*/
abstract class MDObject
{
	private MDValue.Type mType;

	public abstract uint length();

	public int opCmp(Object o)
	{
		throw new MDException("No opCmp defined for type '{}'", MDValue.typeString(mType));
	}

	/**
	Given two MDObject references, compares them.  Doesn't call opCmp metamethods, and
	throws an exception if the two objects are of different types.
	*/
	public static int compare(MDObject o1, MDObject o2)
	{
		if(o1.mType == o2.mType)
			return o1.opCmp(o2);
		else
			throw new MDException("Attempting to compare unlike objects");
	}
}

/**
The class that represents the MiniD 'string' type.

This holds an immutable string.  The hash for this string is calculated once upon creation,
improving speed when used as the key to an AA (which, in MiniD, is very often -- all namespaces
use MDStrings as keys).  Immutability also avoids the problem of using a string as an AA key
and then changing it, which would result in undefined behavior.
*/
class MDString : MDObject
{
	//TODO: Hmmm.  package..
	package dchar[] mData;
	protected hash_t mHash;

	/**
	These construct an MDString from the given D string.  The data is duplicated, so you don't
	have to worry about changing the source data after the MDString has been created.
	*/
	public this(dchar[] data)
	{
		mData = data.dup;
		mHash = typeid(typeof(mData)).getHash(&mData);
		mType = MDValue.Type.String;
	}

	/// ditto
	public this(wchar[] data)
	{
		mData = utf.toString32(data);
		mHash = typeid(typeof(mData)).getHash(&mData);
		mType = MDValue.Type.String;
	}

	/// ditto
	public this(char[] data)
	{
		mData = utf.toString32(data);
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
	
	/**
	Gets the length of the string in characters (codepoints?  code units?  it's all so confusing).
	*/
	public override uint length()
	{
		return mData.length;
	}

	/**
	If the given character is in the string, returns the index of its first occurrence; otherwise
	returns -1.
	*/
	public int opIn_r(dchar c)
	{
		foreach(i, ch; mData)
			if(c == ch)
				return i;

		return -1;
	}

	/**
	Concatenates two MDStrings, resulting in a new MDString.
	*/
	public MDString opCat(MDString other)
	{
		// avoid double duplication ((this ~ other).dup)
		MDString ret = new MDString();
		ret.mData = this.mData ~ other.mData;
		ret.mHash = typeid(typeof(ret.mData)).getHash(&ret.mData);
		return ret;
	}

	/**
	Concatenates an MDString with a single character, resulting in a new MDString.
	*/
	public MDString opCat(dchar c)
	{
		MDString ret = new MDString();
		ret.mData = this.mData ~ c;
		ret.mHash = typeid(typeof(ret.mData)).getHash(&ret.mData);
		return ret;
	}

	/// ditto
	public MDString opCat_r(dchar c)
	{
		MDString ret = new MDString();
		ret.mData = c ~ this.mData;
		ret.mHash = typeid(typeof(ret.mData)).getHash(&ret.mData);
		return ret;
	}

	/**
	Returns the hash of the string (which was computed at construction).
	*/
	public hash_t toHash()
	{
		return mHash;
	}

	/**
	Returns true if this and another string are identical; false otherwise.
	Checks to see if the hashes diff first, which can save a lot of time.
	*/
	public int opEquals(Object o)
	{
		MDString other = cast(MDString)o;
		assert(other !is null, "MDString opEquals");

		if(mHash != other.mHash)
			return false;

		return mData == other.mData;
	}

	/**
	Returns true if this MDString's data is identical to the given D string; false otherwise.
	*/
	public int opEquals(char[] v)
	{
		return mData == utf.toString32(v);
	}

	/// ditto
	public int opEquals(wchar[] v)
	{
		return mData == utf.toString32(v);
	}

	/// ditto
	public int opEquals(dchar[] v)
	{
		return mData == v;
	}

	/**
	Compares this string to another MDString by character values (i.e. it doesn't do a full lexicographical
	language-correct comparison).
	*/
	public int opCmp(Object o)
	{
		MDString other = cast(MDString)o;
		assert(other !is null, "MDString opCmp");

		return dcmp(mData, other.mData);
	}

	/**
	Same as above, but for D string arguments.
	*/
	public int opCmp(char[] v)
	{
		return dcmp(mData, utf.toString32(v));
	}

	/// ditto
	public int opCmp(wchar[] v)
	{
		return dcmp(mData, utf.toString32(v));
	}

	/// ditto
	public int opCmp(dchar[] v)
	{
		return dcmp(mData, v);
	}

	/**
	Gets the character at the given index.
	*/
	public dchar opIndex(uint index)
	{
		debug if(index < 0 || index >= mData.length)
			throw new MDException("Invalid string character index: {}", index);

		return mData[index];
	}

	/**
	Slices this string, returning a new MDString.  Thanks to immutability, the
	new string's data will simply point into the old string's, meaning the only memory
	allocation is for the new string's instance.
	*/
	public MDString opSlice(uint lo, uint hi)
	{
		MDString ret = new MDString();
		ret.mData = mData[lo .. hi];
		ret.mHash = typeid(typeof(ret.mData)).getHash(&ret.mData);

		return ret;
	}

	package dchar[] sliceData(uint lo, uint hi)
	{
		return mData[lo .. hi];
	}

	/**
	These convert this string into the given UTF encoding.  The returned value will never
	reference the data inside the instance, to preserve immutability.
	*/
	public char[] asUTF8()
	{
		return utf.toString(mData);
	}

	/// ditto
	public wchar[] asUTF16()
	{
		return utf.toString16(mData);
	}

	/// ditto
	public dchar[] asUTF32()
	{
		return mData.dup;
	}

	// Returns null on failure, so that the VM can give an error at the appropriate location
	package static MDString concat(MDValue[] values, out uint badIndex)
	{
		uint l = 0;

		for(uint i = 0; i < values.length; i++)
		{
			if(values[i].mType == MDValue.Type.String)
				l += values[i].mString.length;
			else if(values[i].mType == MDValue.Type.Char)
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
			if(v.mType == MDValue.Type.String)
			{
				MDString s = v.mString;
				result[i .. i + s.length] = s.mData[];
				i += s.length;
			}
			else
			{
				result[i] = v.mChar;
				i++;
			}
		}
		
		return new MDString(result);
	}

	package static MDString concatEq(MDValue dest, MDValue[] values, out uint badIndex)
	{
		MDString ret = concat(dest ~ values, badIndex);

		if(ret is null)
			badIndex--;

		return ret;
	}

	/**
	Returns the UTF-8 string representation of the string; basically just returns .asUTF8().
	*/
	public char[] toString()
	{
		return asUTF8();
	}
}

/**
The class which represents the MiniD 'function' type.

This is a closure, that is a function and all the environment it needs to execute correctly.
It can hold either a MiniD closure (a "script closure"), or a reference to a native D function
(a "native closure").  In virtually all cases this distinction is transparent, except when it
comes to coroutines.  You cannot yield out of a coroutine across the boundary of a native function
call.

In addition to their executable function, closures also have what's called the "environment."
In the global lookup process (in script functions, that is), the first step is to check if the
global exists in the 'this' parameter.  If it doesn't, the next step goes to the closure's
environment.  This is a namespace which usually is the module in which the function was defined.
Global lookup begins at the environment, and travels up the chain of namespaces (since each
namespace can have a parent namespace) until the chain is exhausted.  The environment is important
for global lookup in script closures, but it's usually not that important in native closures.
Furthermore, if a function is called as a non-method (a plain function call), and is not given
an explicit context with the 'with' keyword, its environment will be passed as the 'this' parameter.
*/
class MDClosure : MDObject
{
	protected bool mIsNative;
	protected MDNamespace mEnvironment;

	struct NativeClosure
	{
		private int function(MDState, uint) func;
		private int delegate(MDState, uint) dg;
		private dchar[] name;
		private MDValue[] upvals;
	}

	struct ScriptClosure
	{
		private MDFuncDef func;
		private MDUpval*[] upvals;
	}

	union
	{
		private NativeClosure native;
		private ScriptClosure script;
	}

	/**
	Constructs a script closure.
	
	Params:
		environment = The environment of the closure.  See the description of this class for info.
		def = The MDFuncDef, which was either loaded from a file or just compiled, which holds the
			bytecode representation of the closure.
	*/
	public this(MDNamespace environment, MDFuncDef def)
	{
		mIsNative = false;
		mEnvironment = environment;
		script.func = def;
		script.upvals.length = def.mNumUpvals;
		mType = MDValue.Type.Function;
	}
	
	/**
	Constructs a native closure.  Both function pointers and delegates are allowed; using delegates will be
	slightly faster when the closure is called.

	All native functions which interact with the API follow the same signature.  They take two Params:
	an MDValue which represents the thread from which this closure was called, and the number of parameters
	(not including the context 'this' parameter, which is always present) with which the function was called.
	The MDState parameter contains all the parameters which were passed to the function, as well as being a
	very important interface through which much of the native API is used.  Native functions return an integer,
	which is how many values they are returning (which were pushed onto the MDState's stack prior to returning).

	Params:
		environment = The environment of the closure.  See the description of this class for info.
		dg = (or func) The delegate or function pointer of the native function.
		name = The name of the function, which will be used in error messages and when its toString is called.
		upvals = An optional array of MDValues which serve as the upvalues to the closure.  In MiniD, upvalues
			are automatic, and are simply local variables declared in enclosing functions.  In native code,
			you can achieve similar results by either creating an instance of a struct on the heap and using
			one of its methods as the delegate for the closure, and keep the closure's upvalues in there; or
			by passing an array of MDValues to this constructor.  The array of upvalues will be available
			through the MDState parameter to the native function.
	*/
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

	/// ditto
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

	/**
	Getting the length of a closure makes no sense; this just throws an exception.
	*/
	public override uint length()
	{
		throw new MDException("Cannot get the length of a closure");
	}

	/**
	Gets a string representation of the closure.  For native closures, it looks something like "native function name";
	for script closures, "script function name(location defined)".
	*/
	public char[] toString()
	{
		if(mIsNative)
			return Stdout.layout.convert("native function {}", native.name);
		else
			return Stdout.layout.convert("script function {}({})", script.func.mGuessedName, script.func.mLocation.toString());
	}

	/**
	Returns whether or not this is a native closure.
	*/
	public bool isNative()
	{
		return mIsNative;
	}

	/**
	Gets or sets the environment of the closure.  See the class description for info.
	*/
	public MDNamespace environment()
	{
		return mEnvironment;
	}

	/// ditto
	public void environment(MDNamespace env)
	{
		mEnvironment = env;
	}

	protected int callFunc(MDState s, uint numParams)
	{
		return native.func(s, numParams);
	}
}

/**
The class which represents the MiniD 'table' type.

This is basically an AA which is indexed by and holds MDValues.  Null MDValues cannot be
used as indices.  Assigning a null value to a key-value pair removes that pair from the
table, and accessing a key which doesn't exist will return a null value.
*/
class MDTable : MDObject
{
	protected MDValue[MDValue] mData;

	/// Creates a new table.
	public this()
	{
		mType = MDValue.Type.Table;
	}

	/**
	Create a table from a templated list of variadic arguments.  There must be an even
	number of arguments.  Each pair of arguments is interpreted as a key-value pair, and
	the types of these must be convertible to MiniD types.
	*/
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
	
	/**
	Create a table from an associative array.  The key and value types must be convertible
	to MiniD types.
	*/
	public static MDTable fromAA(K, V)(V[K] aa)
	{
		MDTable ret = new MDTable();

		foreach(k, ref v; aa)
		{
			MDValue key = k;
			MDValue val = v;
			
			ret[key] = val;
		}

		return ret;
	}

	/**
	Gets the number of key-value pairs in the table.
	*/
	public override uint length()
	{
		return mData.length;
	}

	/**
	Creates a shallow copy of the table.  The keys and values in the new table will be the same;
	they are not recursively duplicated.
	*/
	public MDTable dup()
	{
		MDTable n = new MDTable();

		foreach(k, v; mData)
			n.mData[k] = v;

		return n;
	}
	
	/**
	Gets an MDArray of all the keys of the table.
	*/
	public MDArray keys()
	{
		return new MDArray(mData.keys);
	}

	/**
	Gets an MDArray of all the values of the table.
	*/
	public MDArray values()
	{
		return new MDArray(mData.values);
	}

	/**
	Removes a key-value pair from the table with the given key.  If the key doesn't exist, this
	simply returns.  You can also remove a pair by assigning a null value to it.
	*/
	public void remove(ref MDValue index)
	{
		MDValue* ptr = (index in mData);

		if(ptr is null)
			return;

		mData.remove(index);
	}
	
	/**
	Returns a pointer to the value given the key.  Returns a null pointer if the key doesn't exist.
	*/
	public MDValue* opIn_r(ref MDValue index)
	{
		return (index in mData);
	}

	/**
	Returns a pointer to the value given the key.  Throws an exception if the key is a null MDValue.
	Never returns a null MDValue*; if the key doesn't exist, returns a pointer to a null MDValue instead.
	*/
	public MDValue* opIndex(ref MDValue index)
	{
		if(index.mType == MDValue.Type.Null)
			throw new MDException("Cannot index a table with null");

		MDValue* val = (index in mData);

		if(val is null)
			return &MDValue.nullValue;
		else
			return val;
	}

	/**
	Assigns a value to a key-value pair.  Throws an exception if the key is a null MDValue.  Removes
	the pair, if it exists, if the value is a null MDValue.
	*/
	public void opIndexAssign(ref MDValue value, ref MDValue index)
	{
		if(index.mType == MDValue.Type.Null)
			throw new MDException("Cannot index assign a table with null");

		if(value.mType == MDValue.Type.Null)
		{
			if(index in mData)
				mData.remove(index);
		}
		else
			mData[index] = value;
	}

	/**
	Overloaded opApply so you can use a foreach loop on an MDTable.  They key and value are both
	MDValues.
	*/
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

	/**
	Returns a string representation of the table, in the format "table 0x00000000", where the number
	is the hexidecimal representation of the 'this' pointer.
	*/
	public char[] toString()
	{
		return Stdout.layout.convert("table 0x{:X8}", cast(size_t)cast(void*)this);
	}
}

/**
The class which represents the MiniD 'array' type.

This is a very simple and straightforward class.  It's basically a mutable, resizable array of MDValues.
*/
class MDArray : MDObject
{
	protected MDValue[] mData;

	/**
	Construct this array with a given size.  All the elements will be the null MDValue.
	*/
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

	/**
	Create an MDArray from a templated list of variadic arguments.  All the arguments must have types
	which are convertible to MiniD types.
	*/
	public static MDArray create(T...)(T args)
	{
		MDArray ret = new MDArray(args.length);

		foreach(i, arg; args)
			ret.mData[i] = arg;

		return ret;
	}

	/**
	Create an MDArray from a D array.  The element type must be convertible to a MiniD type.  Multi-dimensional
	arrays work as well.
	*/
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

	/**
	Gets the number of elements in the array.
	*/
	public override uint length()
	{
		return mData.length;
	}

	/**
	Sets the length of the array.  If the new length is longer than the old, the new elements will
	be filled in with the null MDValue.
	*/
	public uint length(int newLength)
	{
		mData.length = newLength;
		return newLength;
	}

	/**
	Sorts the array.  All the elements must be the same type for this to succeed; throws an exception on failure.
	*/
	public void sort()
	{
		mData.sort;
	}

	/**
	Sorts the array, using a custom predicate.  This predicate takes two values and should return 'true'
	if the first is less than the second, and 'false' otherwise.
	*/
	public void sort(bool delegate(MDValue, MDValue) predicate)
	{
		.sort(mData, predicate);
	}

	/**
	Reverses the order of the array.
	*/
	public void reverse()
	{
		mData.reverse;
	}

	/**
	Performs a shallow copy of the array.
	*/
	public MDArray dup()
	{
		MDArray n = new MDArray(0);
		n.mData = mData.dup;
		return n;
	}
	
	/**
	Compares this array to another array.  Comparison works just like on D arrays.  As long as the
	length and data are identical, the arrays will compare equal.  If all the elements of both arrays
	are the same type, you can even compare for ordering; smaller arrays and arrays with smaller elements
	will compare less than larger arrays.  If the elements are different types, comparing for ordering
	doesn't make much sense, but equality still works.
	*/
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

	/**
	Sees if this array is identical to another array.
	*/
	public int opEquals(Object o)
	{
		auto other = cast(MDArray)o;
		assert(other !is null, "MDArray opCmp");

		return mData == other.mData;
	}

	/**
	If the given value is in the array, returns the index of the first instance; otherwise, returns -1.
	*/
	public int opIn_r(ref MDValue v)
	{
		foreach(i, ref val; mData)
			if(val.opEquals(&v))
				return i;

		return -1;
	}

	/**
	opApply overloads to allow using foreach on an MDArray.  Both index-value and value-only forms are
	available.  The value type is an MDValue.
	*/
	public int opApply(int delegate(ref MDValue value) dg)
	{
		int result = 0;

		for(uint i = 0; i < mData.length; i++)
		{
			result = dg(mData[i]);

			if(result)
				break;
		}

		return result;
	}

	/// ditto
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
	
	/**
	Concatenates two arrays into a new array.  The data is always copied from
	the source arrays.
	*/
	public MDArray opCat(MDArray other)
	{
		MDArray n = new MDArray(mData.length + other.mData.length);
		n.mData[0 .. mData.length] = mData[];
		n.mData[mData.length .. $] = other.mData[];
		return n;
	}

	/**
	Concatenates an array with a single element.  Always copies from the source array.
	*/
	public MDArray opCat(ref MDValue elem)
	{
		MDArray n = new MDArray(mData.length + 1);
		n.mData[0 .. mData.length] = mData[];
		n.mData[$ - 1] = elem;
		return n;
	}

	/// ditto
	public MDArray opCat_r(ref MDValue elem)
	{
		MDArray n = new MDArray(mData.length + 1);
		n.mData[0] = elem;
		n.mData[1 .. $] = mData[];
		return n;
	}

	/**
	Appends another array onto the end of this one.  No new array is created; this array is
	just resized.
	*/
	public MDArray opCatAssign(MDArray other)
	{
		mData ~= other.mData;
		return this;
	}

	/**
	Appends a single element to the end of this array.
	*/
	public MDArray opCatAssign(ref MDValue elem)
	{
		mData ~= elem;
		return this;
	}

	/**
	Gets a pointer to the value stored at the given index.  Returns a pointer instead of a plain
	MDValue so that the array data can be updated after the fact.
	*/
	public MDValue* opIndex(int index)
	{
		return &mData[index];
	}

	/**
	Assigns a value into the given index.
	*/
	public void opIndexAssign(ref MDValue value, uint index)
	{
		mData[index] = value;
	}

	/**
	Creates a new array which is a slice into this array's data.  Modifying the contents of the
	sliced array will modify the contents of this array (unless this array is resized, in which
	case it may not).
	*/
	public MDArray opSlice(uint lo, uint hi)
	{
		return new MDArray(mData[lo .. hi]);
	}

	/**
	Assigns a single value to a range of indices.
	*/
	public void opSliceAssign(ref MDValue value, uint lo, uint hi)
	{
		mData[lo .. hi] = value;
	}

	/**
	Copies the data from another MDArray into this one.  The length of the other array must be the
	same as the length of the slice indicated by the indices.
	*/
	public void opSliceAssign(MDArray arr, uint lo, uint hi)
	{
		mData[lo .. hi] = arr.mData[];
	}

	/**
	Assigns a single value to every element of this array.
	*/
	public void opSliceAssign(ref MDValue value)
	{
		mData[] = value;
	}

	/**
	Copies the data from another array into this one.  Both arrays must have the same length.
	*/
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

	/**
	Returns a string representation of the array, in the format "array 0x00000000", where the number
	is the hexidecimal representation of the 'this' pointer.
	*/
	public char[] toString()
	{
		return Stdout.layout.convert("array 0x{:X8}", cast(void*)this);
	}

	private static MDArray concat(MDValue[] values)
	{
		if(values.length == 2 && values[0].mType == MDValue.Type.Array)
		{
			if(values[1].mType == MDValue.Type.Array)
				return values[0].mArray ~ values[1].mArray;
			else
				return values[0].mArray ~ values[1];
		}

		uint l = 0;

		foreach(uint i, MDValue v; values)
		{
			if(v.mType == MDValue.Type.Array)
				l += v.mArray.length;
			else
				l += 1;
		}

		MDArray result = new MDArray(l);

		uint i = 0;

		foreach(MDValue v; values)
		{
			if(v.mType == MDValue.Type.Array)
			{
				MDArray a = v.mArray;
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

	private static void concatEq(MDArray dest, MDValue[] values)
	{
		foreach(uint i, ref MDValue v; values)
		{
			if(v.mType == MDValue.Type.Array)
				dest ~= v.mArray;
			else
				dest ~= v;
		}
	}
}

/**
The class which represents the MiniD 'class' type.

Classes hold two namespaces: one for fields and one for methods.  The method namespace is shared among
all instances of the class, while the field namespace is duplicated for each instance.  Classes can
inherit from other classes.

When assigning members to the class, they will automatically be put into the proper namespace based on their
type -- closures go into the method namespace, all others into the fields namespace.  You can also get
references to each of these namespaces.
*/
class MDClass : MDObject
{
	protected dchar[] mGuessedName;
	protected MDClass mBaseClass;
	protected MDNamespace mFields;
	protected MDNamespace mMethods;
	protected bool mIsCtorCached = false;
	protected MDValue* mCtor;

	protected static MDString CtorString;

	static this()
	{
		CtorString = new MDString("constructor"d);
	}

	/**
	Creates a new class.

	Params:
		guessedName = The name of the class.  This is called "guessed" mostly because in MiniD code, classes
			do not have any intrinsic name associated with them, and sometimes the compiler will generate a
			name for an anonymous class.  For any classes that you create from native code, though, you'll
			probably give them a real name.

		baseClass = An optional base class from which this one should derive.  If you skip this parameter or
			pass null, the class will have no base class.  Otherwise, it will copy the fields and methods
			from the base class into its own namespaces, which you can then overwrite (override) with your
			own versions.
	*/
	public this(dchar[] guessedName, MDClass baseClass = null)
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

	/**
	Throws an exception since classes do not have a length.
	*/
	public override uint length()
	{
		throw new MDException("Cannot get the length of a class");
	}

	/**
	Returns an MDValue containing the base class.  Returns a null MDValue if it has no base class.
	*/
	public MDValue superClass()
	{
		if(mBaseClass is null)
			return MDValue.nullValue;
		else
			return MDValue(mBaseClass);
	}

	/**
	Creates a new instance of this class; this doesn't, however, run the constructor, so the instance
	may be incompletely initialized.  The fields are copied from the class into the new instance; the
	instance's method namespace simply points to this class's method namespace.
	*/
	public MDInstance newInstance()
	{
		return new MDInstance(this);
	}

	/**
	Look up a member of the class.  This will look in the methods, the fields, and then continue the
	search in the base class if there is any.  Returns a null pointer (not a pointer to a null MDValue)
	if the member wasn't found.
	*/
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

	/// ditto
	public MDValue* opIndex(dchar[] index)
	{
		scope str = MDString.newTemp(index);
		return opIndex(str);
	}

	/**
	Sets a member of a class.  If the value is a function, it'll be put into the methods namespace;
	otherwise, it'll be put into the fields namespace.
	*/
	public void opIndexAssign(ref MDValue value, MDString index)
	{
		if(value.mType == MDValue.Type.Function)
			mMethods[index] = value;
		else
			mFields[index] = value;

		mIsCtorCached = false;
	}

	/// ditto
	public void opIndexAssign(ref MDValue value, dchar[] index)
	{
		opIndexAssign(value, new MDString(index));
	}

	/**
	Returns the guessed name (a duplicate of the internal name, so it can't be corrupted).
	*/
	public dchar[] getName()
	{
		return mGuessedName.dup;
	}

	/**
	Returns the namespace that contains the fields for this class.  Manually adding members to the returned
	namespace is not recommended, as this bypasses some caching logic that MDClass performs with a normal
	member add.
	*/
	public MDNamespace fields()
	{
		return mFields;
	}

	/**
	Returns the namespace that contains the methods for this class.  Manually adding members to the returned
	namespace is not recommended, as this bypasses some caching logic that MDClass performs with a normal
	member add.
	*/
	public MDNamespace methods()
	{
		return mMethods;
	}

	/**
	Returns a string representation of the class in the form "class name".
	*/
	public char[] toString()
	{
		return Stdout.layout.convert("class {}", mGuessedName);
	}

	package MDValue* getCtor()
	{
		if(mIsCtorCached)
			return mCtor;

		mIsCtorCached = true;
		mCtor = this[MDClass.CtorString];
		return mCtor;
	}
}

/**
The class which represents the MiniD 'instance' type.

Instances are a bit different from other types in that they also have a class type from which they were
instantiated.  This class defines the methods which can be called on its instances, as well as the 
fields which they given when they are created.  You can query the runtime type of an instance, as well
as see if a given class is anywhere in its inheritance hierarchy (or if it is an instance of that class
itself).

Instances must be created through a class; you cannot instantiate an instance on its own.
*/
class MDInstance : MDObject
{
	protected MDClass mClass;
	protected MDNamespace mMethods;
	protected MDNamespace mFields;

	private this(MDClass _class)
	{
		mType = MDValue.Type.Instance;
		mClass = _class;
		mMethods = mClass.mMethods;
		mFields = mClass.mFields.dup;
	}

	/**
	Getting the length of an instance $(I could) make sense, if the instance had an opLength method.
	However, none of these class methods call (or can call) metamethods, so this just throws an
	exception.
	*/
	public override uint length()
	{
		throw new MDException("Cannot get the length of a class instance");
	}

	/**
	Looks up a member in the instance.  If the member doesn't exist, returns a null pointer.
	*/
	public MDValue* opIndex(MDString index)
	{
		if(auto ptr = index in mMethods)
			return ptr;

		return (index in mFields);
	}

	/// ditto
	public MDValue* opIndex(dchar[] index)
	{
		scope str = MDString.newTemp(index);
		return opIndex(str);
	}

	/**
	Sets a member in an instance.  You cannot reassign instance methods; attempting to do so will
	result in an exception being thrown.  You also can't add fields to the class instance which
	it didn't have to begin with (also throws an error).
	*/
	public void opIndexAssign(ref MDValue value, MDString index)
	{
		if(value.mType == MDValue.Type.Function)
			throw new MDException("Attempting to change a method of an instance of '{}'", mClass.toString());
		else if(auto member = index in mFields)
			*member = value;
		else
			throw new MDException("Attempting to insert a new member '{}' into an instance of '{}'", mClass.toString());
	}

	/// ditto
	public void opIndexAssign(ref MDValue value, dchar[] index)
	{
		opIndexAssign(value, new MDString(index));
	}

	/**
	Gets a string representation of the instance, in the form "instance of class classname".  Does
	not call toString metamethods.
	*/
	public char[] toString()
	{
		return Stdout.layout.convert("instance of {}", mClass.toString());
	}

	/**
	Given a reference to a class, sees if this instance can be cast to the given class.
	
	Returns:
		'this' if it can be cast; null otherwise.
	*/
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

	/**
	Get a reference to the field namespace of this instance.  Every instance has its own field namespace.
	*/
	public MDNamespace fields()
	{
		return mFields;
	}

	/**
	Get a reference to the method namespace of this instance.  All instances of a class and the class itself
	share the method namespace.
	*/
	public MDNamespace methods()
	{
		return mMethods;
	}

	/**
	Gets a reference to the owning class.
	*/
	public MDClass getClass()
	{
		return mClass;
	}
	
	private MDValue* getField(MDString index)
	{
		return (index in mFields);
	}
}

import tango.stdc.stdlib: cmalloc = malloc, cfree = free;
import tango.core.Exception;
import tango.core.Memory;

/**
The class which represents the MiniD 'namespace' type.

Namespaces are kind of like tables, but have somewhat different semantics.  They are a mapping from strings to
values; only string keys are allowed.  Namespaces may hold null values, so assigning a null value to a key-value
pair does not remove that pair from the namespace.  Accessing a key-value pair which has not yet been inserted
will throw an exception instead of returning null as tables do.  Namespaces can have a name.  Lastly namespaces
can also have a parent namespace, which is used in global lookup.  

Namespaces are used as symbol tables throughout MiniD.  Modules, packages, class fields, and class methods are all
held in namespaces.  They are also used as function closure environments.  When global lookup reaches the closure's
environment, it looks up the global in that namespace; if it's not found, it goes to that namespace's parent
namespace, all the way up the chain of namespaces until either the global is found or the namespace chain ends.
*/
final class MDNamespace : MDObject
{
	protected MDValue[MDString] mData;
	protected MDNamespace mParent;
	protected dchar[] mName;

	/**
	Construct a new namespace.
	
	Params:
		name = The optional name of the namespace.  It can be null, in which case the namespace will be anonymous.
			class method and field namespaces are anonymous, for example.
		parent = The optional parent of the namespace.  The parent is used for global lookup (see the description
			of this class).  If the namespace won't be being used as the environment for a function, the parent
			is mostly purposeless, except for debugging, when the parent's name will be included in the namespace's
			name.  The parent can be null, which means global lookup will terminate after searching this namespace.
	*/
	public this(dchar[] name = null, MDNamespace parent = null)
	{
		mName = name;
		mParent = parent;
		mType = MDValue.Type.Namespace;
	}

	/**
	Create a namespace from a variadic list of arguments.  This is similar to the MDTable.create() function,
	in that there must be an even number of arguments, and each pair is interpreted as a key-value pair.
	This has the additional requirement that the keys must all be strings.  The name and parent parameters
	are the same as in the constructor.
	*/
	public static MDNamespace create(T...)(dchar[] name, MDNamespace parent, T args)
	{
		MDNamespace ret = new MDNamespace(name, parent);
		ret.addList(args);

		return ret;
	}

	/**
	Similar to create(), but just adds a list of key-value pairs to an already-created namespace.
	*/
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

	/**
	Gets the number of key-value pairs in the namespace.
	*/
	public override uint length()
	{
		return mData.length;
	}

	/**
	Gets the name of the namespace (not including the parent's name).
	*/
	public dchar[] name()
	{
		return mName;
	}

	/**
	Gets the parent of this namespace.
	*/
	public MDNamespace parent()
	{
		return mParent;
	}

	/**
	Looks up a value in the namespace from a string key.  As usual for D's 'in', returns null if
	the value isn't found, and a pointer to the value if it is.
	*/
	public MDValue* opIn_r(MDString key)
	{
		return key in mData;
	}

	/// ditto
	public MDValue* opIn_r(dchar[] key)
	{
		scope idx = MDString.newTemp(key);
		return idx in mData;
	}

	/**
	Duplicate this namespace, performing a shallow copy of all the key-value pairs.
	*/
	public MDNamespace dup()
	{
		MDNamespace n = new MDNamespace(mName, mParent);

		foreach(k, ref v; mData)
			n.mData[k] = v;

		return n;
	}

	/**
	Gets an MDArray of all the keys in the namespace.
	*/
	public MDArray keys()
	{
		return MDArray.fromArray(mData.keys);
	}

	/**
	Gets an MDArray of all the values in the namespace.
	*/
	public MDArray values()
	{
		return new MDArray(mData.values);
	}

	/**
	Looks up a value from the namespace.  Returns a null pointer if the key doesn't exist.
	*/
	public MDValue* opIndex(MDString key)
	{
		return key in mData;
	}

	/// ditto
	public MDValue* opIndex(dchar[] key)
	{
		scope str = MDString.newTemp(key);
		return str in mData;
	}

	/**
	Assigns a value to a key n the namespace.  Will insert the pair if the key doesn't exist
	already.  Assigning a null value to a key-value pair will $(I not) remove the pair from
	the namespace as it does with tables.
	*/
	public void opIndexAssign(ref MDValue value, MDString key)
	{
		mData[key] = value;
	}

	/// ditto
	public void opIndexAssign(ref MDValue value, dchar[] key)
	{
		opIndexAssign(value, new MDString(key));
	}

	/**
	Remove the given key from the namespace.  Throws an exception if they key does not exist.
	*/
	public void remove(MDString key)
	{
		mData.remove(key);
	}
	
	/// ditto
	public void remove(dchar[] key)
	{
		scope k = MDString.newTemp(key);
		remove(k);
	}

	/**
	Overload of opApply to allow using foreach over a namespace.  The keys are MDStrings, and
	the values are MDValues.
	*/
	public int opApply(int delegate(ref MDString, ref MDValue) dg)
	{
		int result = 0;

		foreach(k, ref v; mData)
		{
			result = dg(k, v);

			if(result)
				break;
		}

		return result;
	}

	/**
	Gets a more complete name of the namespace, including the name of all parent namespaces.
	So if namespace 'b's parent is namespace 'a', this will return a string like "a.b".
	*/
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

	/**
	Gets a string representation of the namespace in the form "namespace full.name".
	*/
	public char[] toString()
	{
		return Stdout.layout.convert("namespace {}", nameString());
	}
}

/**
A struct that holds a location (a filename, a line number, and a column number) of
a piece of code.  Used by the compiler and in runtime debug locations.
*/
struct Location
{
	public int line = 1;
	public int column = 1;
	public dchar[] fileName;

	/**
	Create a location with the given filename, line, and column.  Lines and columns start
	at 1.  A line, column pair of -1, -1 has the special meaning of "in a native function."
	*/
	public static Location opCall(dchar[] fileName, int line = 1, int column = 1)
	{
		Location l;
		l.fileName = fileName;
		l.line = line;
		l.column = column;
		return l;
	}

	/**
	Gets a string representation of the location.  If the line and column are both -1, the
	string is formatted like "fileName(native)", meaning that the location came from a native
	function (i.e. a native function may have thrown an exception).  Otherwise, it's in
	the form "fileName(line:column)".  For runtime debug locations, 'column' is actually
	replaced by the index of the bytecode instruction.
	*/
	public char[] toString()
	{
		if(line == -1 && column == -1)
			return Stdout.layout.convert("{}(native)", fileName);
		else
			return Stdout.layout.convert("{}({}:{})", fileName, line, column);
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

/**
A definition of a MiniD module.

This is really just a name and the code for the top-level function of the module.  This can
be serialized and deserialized using the minid.utils serialization protocol.  This can also
be loaded by the MDContext class, but that's a very low-level API.
*/
class MDModuleDef
{
	package dchar[] mName;
	package MDFuncDef mFunc;

	/**
	Gets the name of the module.  This is the name given in the module declaration.
	*/
	public dchar[] name()
	{
		return mName;
	}

	align(1) struct FileHeader
	{
		uint magic = FOURCC!("MinD");
		uint _version = MiniDVersion;

		version(X86_64)
			ubyte platformBits = 64;
		else
			ubyte platformBits = 32;

		version(BigEndian)
			ubyte endianness = 1;
		else
			ubyte endianness = 0;

		ushort _padding1 = 0;
		uint _padding2 = 0;
		
		static const bool SerializeAsChunk = true;
	}
	
	static assert(FileHeader.sizeof == 16);

	/**
	Serialize this module to some kind of output.  To be used with the minid.utils serialization
	protocol.
	*/
	public void serialize(IWriter s)
	{
		FileHeader header;
		Serialize(s, header);
		Serialize(s, mName);

		assert(mFunc.mNumUpvals == 0, "MDModuleDef.serialize() - Func def has upvalues");

		Serialize(s, mFunc);
	}

	/**
	Deserialize this module from some kind of input.  To be used with the minid.utils serialization
	protocol.
	*/
	public static MDModuleDef deserialize(IReader s)
	{
		FileHeader header;
		Deserialize(s, header);

		if(header != FileHeader.init)
			throw new MDException("MDModuleDef.deserialize() - Invalid file header");

		MDModuleDef ret = new MDModuleDef();
		Deserialize(s, ret.mName);
		Deserialize(s, ret.mFunc);

		return ret;
	}

	/**
	Load a module definition from a filename.  This is a low-level API that you probably won't have
	to deal with.
	*/
	public static MDModuleDef loadFromFile(char[] filename)
	{
		scope file = new Reader(new FileConduit(filename));
		MDModuleDef ret;
		Deserialize(file, ret);
		return ret;
	}

	/**
	Save this module to a filename.
	*/
	public void writeToFile(char[] filename)
	{
		scope file = new Writer(new FileConduit(filename, FileConduit.ReadWriteCreate));
		serialize(file);
		file.flush();
	}
}

/**
A class which holds a script function's byte code, as well as all (most) of the information needed to
instantiate a closure of it, and some debug info as well.

You probably won't need to worry about using this class that much.
*/
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

	package void serialize(IWriter s)
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
	
	package static MDFuncDef deserialize(IReader s)
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

version(MDDynLibs)
{
/*
 * Copyright (c) 2005-2006 Derelict Developers
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 * * Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 *
 * * Neither the names 'Derelict', 'DerelictUtil', nor the names of its contributors
 *   may be used to endorse or promote products derived from this software
 *   without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

version(linux)
	version = Dlfcn;
else version(darwin)
	version = Dlfcn;
else version(Unix)
	version = Dlfcn;

class DynLib
{
	private extern(C) alias void function(void*) InitProc;
	private extern(C) alias void function() UninitProc;
	private extern(C) alias MDNamespace function(MDGlobalState, dchar[]) LoadModuleProc;
	
	private void* mHandle;
	private dchar[] mName;
	private LoadModuleProc mLoadModuleProc;
	private static bool[DynLib] DynLibs;
	private static DynLib[dchar[]] LibsByName;

	static ~this()
	{
		foreach(lib; DynLibs.keys)
			lib.unload();
	}

	private this(void* handle, dchar[] name)
	{
		mHandle = handle;
		mName = name;
		
		auto initProc = cast(InitProc)getProc("MDInitialize");
		initProc(std.gc.getGCHandle());
		
		mLoadModuleProc = cast(LoadModuleProc)getProc("MDLoadModule");
		
		DynLibs[this] = true;
		LibsByName[name] = this;
	}

	public dchar[] name()
	{
		return mName;
	}

	version(Windows)
		import std.c.windows.windows;
	else version(Dlfcn)
	{
		version(linux)
			private import std.c.linux.linux;
		else
		{
			extern(C)
			{
				// From <dlfcn.h>
				// See http://www.opengroup.org/onlinepubs/007908799/xsh/dlsym.html
				const int RTLD_NOW = 2;
				void* dlopen(char* file, int mode);
				int dlclose(void* handle);
				void *dlsym(void* handle, char* name);
				char* dlerror();
			}
		}
	}
	else
		static assert(false, "MiniD cannot use dynamic libraries -- unsupported platform.  Compile without the MDDynLibs version defined.");
		
	import std.string;
		
	public static DynLib load(dchar[] libName)
	{
		if(auto l = libName in LibsByName)
			return *l;

		version(Windows)
			HMODULE hlib = LoadLibraryA(toStringz(utf.toUTF8(libName)));
		else version(Dlfcn)
			void* hlib = dlopen(toStringz(utf.toUTF8(libName)), RTLD_NOW);

		if(hlib is null)
			throw new MDException("Could not load dynamic library '{}'", libName);

		return new DynLib(hlib, libName);
	}

	public void unload()
	{
		auto uninitProc = cast(UninitProc)getProc("MDUninitialize");
		uninitProc();
		
		version(Windows)
			FreeLibrary(cast(HMODULE)mHandle);
		else version(Dlfcn)
			dlclose(mHandle);

		mHandle = null;
		LibsByName.remove(mName);
		DynLibs.remove(this);
	}

	public void* getProc(char[] procName)
	{
		version(Windows)
			void* proc = GetProcAddress(cast(HMODULE)mHandle, toStringz(procName));
		else version(Dlfcn)
			void* proc = dlsym(mHandle, toStringz(procName));

		if(proc is null)
			throw new MDException("Could not get function '{}' from dynamic library '{}'", procName, mName);

		return proc;
	}
	
	public MDNamespace loadModule(dchar[] name)
	{
		auto ret = mLoadModuleProc(MDGlobalState(), name);
		return ret;
	}
}

}

/**
A class which represents an execution context for MiniD code.  It holds a global namespace hierarchy into
which modules can be imported, as well as a set of type metatables.  Also provides a state which can be
used to run code.

You can create multiple, independent MiniD execution contexts.  These are not the same as states.  A state
is simply a thread of execution, and there can be multiple states associated with a single context.
When you create a context, a default state (its "main thread") is created for you.  This thread can spawn
other threads with the creation of coroutines.

A context is useful for creating a "sandbox."  What you can do is create a context, and only load into it
libraries which you know are safe.  Then you can execute untrusted code in this sandbox, and it won't have
access to potentially dangerous functionality.  Then you can have a separate context for executing trusted
code.

You can instantiate this class directly, and then load the standard libraries into it manually, but there
is minid.minid.NewContext, a helper function which will load standard libraries into the context based on
a flags parameter, which is a bit more compact.
*/
final class MDContext
{
	package static MDModuleDef function(FilePath, char[][]) tryPath;
	version(MDDynLibs) package static char[] function(char[], char[][]) tryDynLibPath;
	
	private Location[] mTraceback;
	private MDState mMainThread;
	private MDNamespace[] mBasicTypeMT;
	private MDNamespace[dchar[]] mLoadedModules;
	private MDClosure[dchar[]] mModuleLoaders;
	private bool[dchar[]] mModulesLoading;
	private bool[FilePath] mImportPaths;

	/**
	This struct isn't meant to be used as a type in its own right; it's just a helper for accessing globals.
	*/
	struct _Globals
	{
		private MDNamespace mGlobals;

		/**
		Attempts to get a global of the given name from the global namespace.  Throws an exception if the
		global does not exist.  This is a templated function and returns an MDValue* by default.  If you
		want to get another type, you can use the 'get' alias to this function and call it as a templated
		method.
		*/
		public T opIndex(T = MDValue*)(dchar[] name)
		{
			MDValue* value = mGlobals[name];

			if(value is null)
				throw new MDException("MDContext.globals.get() - Attempting to access nonexistent global '{}'", name);

			static if(is(T == MDValue*))
				return value;
			else
				return value.to!(T);
		}

		/// ditto
		public alias opIndex get;

		/**
		Set a global in the global namespace.
		*/
		public void opIndexAssign(T)(T value, dchar[] name)
		{
			mGlobals[new MDString(name)] = MDValue(value);
		}

		/**
		Get the underlying MDNamespace which actually holds the globals.
		*/
		public MDNamespace ns()
		{
			return mGlobals;
		}
	}

	/**
	An instance of the above struct.  You can access _globals by writing things like "context._globals["x"d] = 5".
	*/
	public _Globals globals;

	public this()
	{
		globals.mGlobals = new MDNamespace();
		globals.mGlobals["_G"d] = MDValue(globals.mGlobals);
		mMainThread = new MDState(this);
		mBasicTypeMT = new MDNamespace[MDValue.Type.max + 1];
	}

	/**
	Gets or sets the metatable for the given type.  Every type has a metatable associated with it where metamethods
	are looked up after any normal method indexing mechanisms fail.  For example, the 'string' standard library sets
	itself as the metatable for the 'string' type, making it possible to call the library functions as if they were
	methods of the string objects themselves.
	*/
	public final MDNamespace getMetatable(MDValue.Type type)
	{
		return mBasicTypeMT[cast(uint)type];
	}

	/// ditto
	public final void setMetatable(MDValue.Type type, MDNamespace table)
	{
		if(type == MDValue.Type.Null)
			throw new MDException("Cannot set global metatable for type 'null'");

		mBasicTypeMT[type] = table;
	}

	/**
	Gets the main thread of execution.  This thread is created when the context is created,
	and is the default thread of execution.
	*/
	public final MDState mainThread()
	{
		return mMainThread;
	}

	/**
	Create a new closure in the global namespace from the given script function definition.
	*/
	public final MDClosure newClosure(MDFuncDef def)
	{
		return new MDClosure(globals.mGlobals, def);
	}

	/**
	Create a new closure in the global namespace from the given native closure information.  See
	MDClosure.this() for info on these parameters.
	*/
	public final MDClosure newClosure(int delegate(MDState, uint) dg, dchar[] name, MDValue[] upvals = null)
	{
		return new MDClosure(globals.mGlobals, dg, name, upvals);
	}

	/// ditto
	public final MDClosure newClosure(int function(MDState, uint) func, dchar[] name, MDValue[] upvals = null)
	{
		return new MDClosure(globals.mGlobals, func, name, upvals);
	}

	/**
	Add a path to be searched when performing an import.  See importModule() for information on the
	import mechanism.
	*/
	public final void addImportPath(char[] path)
	{
		version(Windows)
			alias icompare fcompare;
		else
			alias compare fcompare;

		foreach(p, _; mImportPaths)
			if(fcompare(p.toString(), path) == 0)
				return;

		mImportPaths[new FilePath(path)] = true;
	}

	/**
	Sets a module loader for a given module name.  The name should be in the format of a module declaration
	name, such as "fork.knife.spoon".

	The closure takes two Params: the name of the module to load (so that multiple modules can be loaded
	by the same function), and a namespace in which to place the loaded module symbols.  It is not expected to
	return anything.
	*/
	public final void setModuleLoader(dchar[] name, MDClosure loader)
	{
		mModuleLoaders[name] = loader;
	}

	/**
	Import a given module.  The process goes something like this.
	
	1. See if the module has been loaded.  Module names are case sensitive.  If the module name is found
		in the internal list of loaded modules, the process stops here.
		
	2. If the module hasn't been loaded, see if a loader was registered for it with setModuleLoader().  If one
		has been, the loader is called with the module name and the namespace in which to place the module's
		symbols.  The process ends here if this succeeds.
		
	3. If there's no registered loader, it attempts to load the module from disk, from either a source file or
		a compiled binary module file.  This is where the search paths come in.  The first path it attempts is
		the current working directory.  If the module's name is multipartite, the parts before the final part
		become directory names.  So for example, the name is "fork.knife.spoon", it will look in "fork/knife/"
		for both "spoon.md" and "spoon.mdm".  If both a source and a binary file are found, it will load the
		one with the more recent modification time.  After the current directory is tried, it will go through
		the list of custom directories (in no particular order) attempting the same process.
		
	4. $(B Not implemented in this release.) If no source or binary module could be found, the last attempt is
		to try to load a dynamic library with the same name as the module (with a similar pattern as with the
		source/binary search; "fork.knife.spoon" will look in fork/knife for the module named "spoon").
		
	If all these steps fail, the import process fails.
	
	Params:
		name = The name of the module to load, in the format "fork.knife.spoon".
		s = The state to use to load the module.  This is used when calling any custom module loader functions,
			or if the module being loaded is a script module, in which case the top-level function will be called.
			Defaults to null, in which case the main thread will be used.
			
	Returns:
		The namespace which holds the module's symbols.
	*/
	public final MDNamespace importModule(dchar[] name, MDState s = null)
	{
		// See if it's already loaded
		if(auto ns = name in mLoadedModules)
			return *ns;
			
		if(s is null)
			s = mMainThread;

		// Check for circular imports
		if(name in mModulesLoading)
			throw new MDException("Attempting to import module \"{}\" while it's in the process of being imported; is it being circularly imported?", name);

		mModulesLoading[name] = true;

		scope(exit)
			mModulesLoading.remove(name);

		// See if there's a loader registered for it
		if(auto cl = name in mModuleLoaders)
		{
			MDNamespace modNS = findNamespace(s, name);

			try
				s.easyCall(*cl, 0, MDValue((*cl).environment), name, modNS);
			catch(MDException e)
				throw new MDException("Could not import module \"{}\":\n\t{}", name, e.toString());

			mLoadedModules[name] = modNS;
			return modNS;
		}

		// OK, now let's try to load a source or binary module file
		if(MDNamespace ns = loadModuleFromFile(s, name, null))
		{
			mLoadedModules[name] = ns;
			return ns;
		}

		// Last try: see if there's a dynamic module we can load
		version(MDDynLibs)
		{
			char[] libName = tryDynLibPath(file.getcwd(), elements);

			if(libName is null)
			{
				foreach(customPath, _; mImportPaths)
				{
					libName = tryDynLibPath(customPath, elements);

					if(libName !is null)
						break;
				}
			}

			if(libName !is null)
			{
				DynLib dl = DynLib.load(utf.toUTF32(libName));

				MDNamespace modNS;

				try
					modNS = dl.loadModule(name);
				catch(MDException e)
					throw new MDException("Error loading module \"{}\" from a dynamic library:\n\t{}", name, e.toString());

				mLoadedModules[name] = modNS;
				return modNS;
			}
		}

		throw new MDException("Error loading module \"{}\": could not find anything to load", name);
	}

	public final MDNamespace loadModuleFromFile(MDState s, dchar[] name, MDValue[] params)
	{
		assert(tryPath !is null, "MDGlobalState tryPath not initialized");
		char[][] elements = split(utf.toString(name), "."c);

		scope curDir = new FilePath(FileSystem.getDirectory());

		MDModuleDef def = tryPath(curDir, elements);

		if(def is null)
		{
			foreach(customPath, _; mImportPaths)
			{
				def = tryPath(customPath, elements);

				if(def !is null)
					break;
			}
		}

		if(def !is null)
		{
			if(def.mName != name)
				throw new MDException("Attempting to load module \"{}\", but module declaration says \"{}\"", name, def.name);

			return initializeModule(s, def, params);
		}

		return null;
	}

	/**
	Initialize a module given the module's definition and a list of parameters which will be 
	passed as vararg parameters to the top-level function.  This is a very low-level API.

	Params:
		s = The state to use to call the top-level module function.
		def = The module definition, which was compiled from source or loaded from a file.
		params = An array of parameters which will be passed as varargs to the top-level function.
		
	Returns:
		The namespace of the module.
	*/
	public final MDNamespace initializeModule(MDState s, MDModuleDef def, MDValue[] params)
	{
		MDNamespace modNS = findNamespace(s, def.name);

		MDClosure cl = new MDClosure(modNS, def.mFunc);
		uint funcReg = s.push(cl);
		s.push(modNS);

		foreach(ref val; params)
			s.push(val);

		try
			s.call(funcReg, params.length + 1, 0);
		catch(MDException e)
			throw new MDException("Error loading module \"{}\":\n\t{}", def.name, e.toString());
			
		return modNS;
	}
	
	private final MDNamespace findNamespace(MDState s, dchar[] name)
	{
		dchar[][] splitName = split(name, "."d);
		dchar[][] packages = splitName[0 .. $ - 1];
		dchar[] modName = splitName[$ - 1];

		MDNamespace put = globals.mGlobals;

		foreach(i, pkg; packages)
		{
			MDValue* v = (pkg in put);

			if(v is null)
			{
				MDNamespace n = new MDNamespace(pkg, put);
				put[pkg] = MDValue(n);
				put = n;
			}
			else
			{
				if(v.mType == MDValue.Type.Namespace)
					put = v.mNamespace;
				else
					throw new MDException("Error loading module \"{}\": conflicts with {}", name, join(packages[0 .. i + 1], "."d));
			}
		}

		MDNamespace modNS;
		MDValue* v = modName in put;

		if(v !is null)
		{
			if(v.mType != MDValue.Type.Namespace)
				throw new MDException("Error loading module \"{}\": a global of the same name already exists", name);

			modNS = v.mNamespace;
		}
		else
		{
			modNS = new MDNamespace(modName, put);
			put[modName] = MDValue(modNS);
		}

		return modNS;
	}
	
	/**
	Gets traceback info of the most recently-thrown exception, and clears the traceback
	info.  This method is here because exceptions can propagate through multiple states
	and through coroutine calls.
	*/
	public final char[] getTracebackString()
	{
		if(mTraceback.length == 0)
			return "";

		char[] ret = Stdout.layout.convert("Traceback: {}", mTraceback[0].toString());

		foreach(ref loc; mTraceback[1 .. $])
			ret = Stdout.layout.convert("{}\n\tat {}", ret, loc.toString());

		mTraceback.length = 0;

		return ret;
	}
}

/**
The class which represents the MiniD 'thread' type.  Also probably the singularly most important class
in the native API, this is passed as a "context" to all native functions and contains the script interpreter.
Also keeps track of the script call call stack and locals stack.
*/
final class MDState : MDObject
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
	
	/**
	An enumeration of all the valid states a thread can be in, for coroutine support.
	*/
	enum State
	{
		/**
		Means the coroutine has been instantiated, but not yet called with the initial parameters.
		When called, the context parameter that is passed will be saved, and the coroutine's function
		will begin execution.
		*/
		Initial,

		/**
		Means that the coroutine resumed another coroutine and is waiting for it to yield or return.
		*/
		Waiting,
		
		/**
		Means that the coroutine is currently executing.  You can only get this state if a coroutine
		queries its own state.
		*/
		Running,
		
		/**
		Means that the coroutine executed a yield expression, and is waiting to be resumed.
		*/
		Suspended,
		
		/**
		Means that the coroutine was exited, either by returning or by having an exception propagate
		out of the coroutine.  The coroutine can be reset to the initial state and restarted.
		*/
		Dead
	}

	static MDString[5] StateStrings;

	static this()
	{
		StateStrings[0] = new MDString("initial"d);
		StateStrings[1] = new MDString("waiting"d);
		StateStrings[2] = new MDString("running"d);
		StateStrings[3] = new MDString("suspended"d);
		StateStrings[4] = new MDString("dead"d);
	}
	
	private TryRecord[] mTryRecs;
	private TryRecord* mCurrentTR;
	private uint mTRIndex = 0;

	private ActRecord[] mActRecs;
	private ActRecord* mCurrentAR;
	private uint mARIndex = 0;

	private MDValue[] mStack;
	private uint mStackIndex = 0;

	private MDValue[] mResults;
	private uint mResultIndex = 0;
	private int[] mResultsLengths;

	private MDUpval* mUpvalHead;

	private State mState = State.Initial;
	private MDClosure mCoroFunc;
	private uint mSavedCallDepth;
	private uint mNumYields;
	private uint mNativeCallDepth = 0;
	
	private Fiber mCoroFiber;
	private MDContext mContext;

	// ===================================================================================
	// Public members
	// ===================================================================================

	/**
	Construct a new thread.  A default thread of execution, the 'main thread', is created for
	you by MDContext, so you'll really only need this for creating coroutines.

	If you pass a script function closure to this constructor, this thread will be a coroutine.  It
	can then be subsequently resumed by calling it with another MDState (just like how you call
	threads to resume them in MiniD).
	
	Attempting to pass a native function closure will throw an exception.
	
	Passing null as the closure (the default) will simply create a new state with no special
	properties.  Not all that useful.
	*/
	public this(MDContext context)
	{
		mTryRecs = new TryRecord[10];
		mCurrentTR = &mTryRecs[0];

		mActRecs = new ActRecord[10];
		mCurrentAR = &mActRecs[0];

		mStack = new MDValue[20];
		mResults = new MDValue[8];

		mTryRecs[0].actRecord = uint.max;
		mType = MDValue.Type.Thread;
		
		mContext = context;
	}

	/// ditto
	public this(MDContext context, MDClosure coroFunc)
	{
		this(context);

		if(coroFunc.isNative())
			mCoroFiber = new Fiber(&coroResume);

		mCoroFunc = coroFunc;
	}

	/**
	You can't get the length of a state.  Throws an exception.
	*/
	public override uint length()
	{
		throw new MDException("Cannot get the length of a thread");
	}

	/**
	Returns a string representation of the thread, in the form "thread 0x00000000", where the number
	is the hexadecimal representation of the 'this' pointer.
	*/
	public char[] toString()
	{
		return Stdout.layout.convert("thread 0x{:X8}", cast(void*)this);
	}

	/**
	Gets the current coroutine state of the state as a member of the State enumeration.
	*/
	public final State state()
	{
		return mState;
	}

	/**
	Gets a string representation of the current state of the coroutine.
	*/
	public final MDString stateString()
	{
		return StateStrings[mState];
	}

	debug public final void printStack()
	{
		Stdout.newline;
		Stdout("-----Stack Dump-----");

		for(int i = 0; i < mStack.length; i++)
			Stdout.formatln("[{,2}:{,3}]: {}", i, i - cast(int)mCurrentAR.base, mStack[i].toString());

		Stdout.newline;
	}

	debug public final void printCallStack()
	{
		Stdout.newline;
		Stdout("-----Call Stack-----").newline;

		for(int i = mARIndex; i > 0; i--)
		{
			with(mActRecs[i])
			{
				Stdout.formatln("Record {}", func.toString());
				Stdout.formatln("\tBase: {}", base);
				Stdout.formatln("\tSaved Top: {}", savedTop);
				Stdout.formatln("\tVararg Base: {}", vargBase);
				Stdout.formatln("\tFunc Slot: {}", funcSlot);
				Stdout.formatln("\tNum Returns: {}", numReturns);
			}
		}

		Stdout.newline;
	}

	/**
	Push a null value onto the value stack.
	
	Returns:
		The stack index of the just-pushed value.
	*/
	public final uint pushNull()
	{
		MDValue v;
		v.setNull();
		return push(&v);
	}

	/**
	Push a value onto the value stack.  This is a templated method which can accept any type which can be
	converted to a MiniD type.
	
	Params:
		value = The value to push.
		
	Returns:
		The stack index of the just-pushed value.
	*/
	public final uint push(T)(T value)
	{
		checkStack(mStackIndex);
		mStack[mStackIndex] = value;
		mStackIndex++;

		debug(STACKINDEX) Stdout.formatln("push() set mStackIndex to {}", mStackIndex);//, " (pushed {})", val.toString());

		return mStackIndex - 1 - mCurrentAR.base;
	}

	/**
	Pop a value off the value stack.  This is templated so that you can pop any type that can be converted from
	a MiniD type, but it defaults to MDValue.
	*/
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
	
	/**
	Call any callable MiniD type with a simple interface.  There are multiple callable types in MiniD.  Functions are the
	most obvious.  You can also call threads, which will resume them.  You can call classes to create instances of them.
	And you can call any object which has an opCall metamethod.  
	
	Once the call completes, you must pop any return values off the stack.
	
	Params:
		func = Any callable type.  This is templated to allow any type.
		numReturns = How many return values you want from this function call.  If >= 0, will leave exactly that many values
			on the value stack which you can then pop.  If this is -1, indicates that you want as many return values that
			the call gives back, in which case you can get how many it returned by getting the return value of this method.
		context = All calls require a context which will be passed as the 'this' parameter to the function.  Only significant
			for functions.  Classes, threads, and objects with opCall will overwrite the context with their own value, so
			it's alright to pass null as the context for those.
		params = A variadic list of parameters to be passed to the function.  All values must be convertible to MiniD types.
		
	Returns:
		The number of return values from this call.  If the numReturns parameter was >= 0, this is the same as that parameter,
		and isn't particularly useful.  But if the numReturns parameter was -1, this is very useful, as it indicates how many
		values the call gave back.
	*/
	public final uint easyCall(F, T...)(F func, int numReturns, MDValue context, T params)
	{
		assert(numReturns >= -1, "easyCall - invalid number of returns");

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
				return mStackIndex - (mCurrentAR.base + funcSlot);
			else
			{
				mStackIndex = mCurrentAR.base + funcSlot + numReturns;
				return numReturns;
			}
		}
	}

	/**
	Very similar to the easyCall method, this will call a method of any object.
	
	Params:
		val = The object whose method you would like to call.
		methodName = The name of the method to call.
		numReturns = See easyCall for a description of this parameter.
		params = See easyCall for a description of this parameter.
		
	Returns:
		See easyCall for a description of the return value.
	*/
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

	/// ditto
	public final uint callMethod(T...)(ref MDValue val, MDString methodName, int numReturns, T params)
	{
		uint funcSlot = push(lookupMethod(&val, methodName));
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


	/**
	Perform a slightly lower-level call to any callable type.
	
	This interface makes slightly less code bloat than the easyCall, as it doesn't require the use of a
	variadic templated function.  The protocol for calling something is as follows:

	-----
	// 1. Push the object you're calling onto the stack, and save its stack index.
	auto funcIdx = s.push(something);

	// 2. Push the context.  You must always have a context.
	s.push(someContext);

	// 3. Push any parameters.
	s.push(param1);
	s.push(param2);

	// 4. Make the call.
	s.call(funcIdx, 3, 1);

	// 5. Pop any return values.
	auto ret = s.pop!(int);
	-----
	
	Params:
		slot = The stack slot of the object to call.  Usually you get this from a push.
		numParams = How many parameters, including the context, you are passing to the function.
			Since you always need context, this must always be at least 1.
		numReturns = See easyCall for an explanation of this parameter.
		
	Returns:
		See easyCall for an explanation of this return value.
	*/
	public final uint call(uint slot, int numParams, int numReturns)
	{
		assert(numParams >= 1, "call - must have at least context");

		if(callPrologue(slot, numReturns, numParams))
			execute();
			
		if(numReturns == -1)
			return mStackIndex - (mCurrentAR.base + slot);
		else
		{
			mStackIndex = mCurrentAR.base + slot + numReturns;
			return numReturns;
		}
	}

	/**
	This is to be used from native closures which were created with a list of upvalues.  Sets the
	value of the upvalue at the given integer index (upvalues are like an array).
	
	Params:
		index = The index of the upvalue to set.
		value = The value, which must have a type convertible to a MiniD type, to be set to the upvalue.
	*/
	public final void setUpvalue(T)(uint index, T value)
	{
		if(!mCurrentAR.func)
			throwRuntimeException("MDState.setUpvalue() - No function to set upvalue");

		assert(mCurrentAR.func.isNative(), "MDValue.setUpvalue() used on non-native func");

		if(index >= mCurrentAR.func.native.upvals.length)
			throwRuntimeException("MDState.setUpvalue() - Invalid upvalue index: {}", index);

		mCurrentAR.func.native.upvals[index] = value;
	}

	/**
	The opposite of setUpvalue.  This is templated to return any type, and by default will return an
	MDValue*.  You can then modify the contents of this return value and the changes will be reflected
	in the internal upvalue array.
	
	Params:
		index = The index of the upvalue to get.
		
	Returns:
		The value of the upvalue, templated to return whatever you'd like it to.  Defaults to MDValue*.
	*/
	public final T getUpvalue(T = MDValue*)(uint index)
	{
		if(!mCurrentAR.func)
			throwRuntimeException("MDState.getUpvalue() - No function to get upvalue");

		assert(mCurrentAR.func.isNative(), "MDValue.getUpvalue() used on non-native func");

		if(index >= mCurrentAR.func.native.upvals.length)
			throwRuntimeException("MDState.getUpvalue() - Invalid upvalue index: {}", index);

		static if(is(T == MDValue*))
			return &mCurrentAR.func.native.upvals[index];
		else
			return mCurrentAR.func.native.upvals[index].to!(T);
	}

	/**
	A quirky function which lets you check if the parameter at the given index is of a certain type.
	This is a templated method which takes a string that indicates the type you'd like to check for.
	Possible values are "null", "bool", "int", "float", "char", "string", "table", "array", "function",
	"class", "instance", "namespace", and "thread".  Any other value will give a compile-time error.

	Params:
		index = The 0-based index of the parameter whose type you'd like to check.  Throws an error
			if this index is invalid.

	Returns:
		True if the parameter is of the given type; false otherwise.
	*/
	public final bool isParam(char[] type)(uint index)
	{
		if(index >= (mStackIndex - mCurrentAR.base - 1))
			badParamError(index, "not enough parameters");

		static if(type == "null")           return mStack[mCurrentAR.base + index + 1].mType == MDValue.Type.Null;
		else static if(type == "bool")      return mStack[mCurrentAR.base + index + 1].mType == MDValue.Type.Bool;
		else static if(type == "int")       return mStack[mCurrentAR.base + index + 1].mType == MDValue.Type.Int;
		else static if(type == "float")     return mStack[mCurrentAR.base + index + 1].mType == MDValue.Type.Float;
		else static if(type == "char")      return mStack[mCurrentAR.base + index + 1].mType == MDValue.Type.Char;
		else static if(type == "string")    return mStack[mCurrentAR.base + index + 1].mType == MDValue.Type.String;
		else static if(type == "table")     return mStack[mCurrentAR.base + index + 1].mType == MDValue.Type.Table;
		else static if(type == "array")     return mStack[mCurrentAR.base + index + 1].mType == MDValue.Type.Array;
		else static if(type == "function")  return mStack[mCurrentAR.base + index + 1].mType == MDValue.Type.Function;
		else static if(type == "class")     return mStack[mCurrentAR.base + index + 1].mType == MDValue.Type.Class;
		else static if(type == "instance")  return mStack[mCurrentAR.base + index + 1].mType == MDValue.Type.Instance;
		else static if(type == "namespace") return mStack[mCurrentAR.base + index + 1].mType == MDValue.Type.Namespace;
		else static if(type == "thread")    return mStack[mCurrentAR.base + index + 1].mType == MDValue.Type.Thread;
		else
		{
			pragma(msg, "MDState.isParam() - invalid type '" ~ type ~ "'");
			ERROR_MDState_isParam_InvalidType();
		}
	}

	/**
	Gets the value of a parameter off the stack.  
	
	Params:
		index = The index of the parameter to get.  Throws an error if this index is invalid.
		
	Returns:
		The value of the parameter, templated to whatever type you'd like.  Throws an error if it
		can't be converted to your desired type.  Defaults to MDValue.
	*/
	public final T getParam(T = MDValue)(uint index)
	{
		if(index >= (mStackIndex - mCurrentAR.base - 1))
			badParamError(index, "not enough parameters");

		static if(is(T == MDValue))
		{
			return mStack[mCurrentAR.base + index + 1];
		}
		else
		{
			MDValue* val = &mStack[mCurrentAR.base + index + 1];

			if(!val.canCastTo!(T))
				badParamError(index, "expected '" ~ T.stringof ~ "' but got '{}'", val.typeString());
				
			return val.as!(T);
		}
	}

	/**
	Gets the context (what would be the 'this' pointer in MiniD code) with which the function was called.
	The context, being special, is not included with the rest of the parameters.  
	
	Returns:
		The context, whose type is templated to whatever you'd like.
	*/
	public final T getContext(T = MDValue)()
	{
		static if(is(T == MDValue))
			return mStack[mCurrentAR.base];
		else
			return mStack[mCurrentAR.base].to!(T);
	}

	/**
	Gets a slice of the parameters as an array.  Throws an error if the slice boundaries are invalid.

	Params:
		lo = The low index of the slice.  Can be negative, which means "from the end," i.e. -1 would mean
			"begin at the very last parameter."  Inclusive.
		hi = The high index of the slice.  Can be negative, which means "from the end," i.e. -1 would mean
			"end after the very last parameter".  Noninclusive.

	Returns:
		An array containing the parameter values.  Because of the way the stack works, this is not (and cannot
		be) a slice into the internal stack, but is instead a copy.
	*/
	public final MDValue[] getParams(int lo, int hi)
	{
		int numParams = mStackIndex - mCurrentAR.base;

		if(lo < 0)
			lo = numParams + lo + 1;

		if(hi < 0)
			hi = numParams + hi + 1;

		if(lo > hi || lo < 0 || lo > numParams || hi < 0 || hi > numParams)
			throwRuntimeException("Invalid getParams indices ({} .. {}) (num params = {})", lo, hi, numParams);

		return mStack[mCurrentAR.base + lo + 1.. mCurrentAR.base + hi].dup;
	}

	/**
	Gets all the parameters passed to the function as an array.  Equivalent to calling getParams(0, -1).

	Returns:
		An array of all the parameters.  It's a copy of the internal stack.
	*/
	public final MDValue[] getAllParams()
	{
		if(mStackIndex - mCurrentAR.base == 1)
			return null;

		return mStack[mCurrentAR.base + 1 .. mStackIndex].dup;
	}

	/**
	An odd sort of protective function.  You can use this function to wrap a call to a library function etc. which
	could throw an exception, but when you don't want to have to bother with catching the exception yourself.  Useful
	for writing native MiniD libraries.

	Say you had a function which opened a file:

	-----
	File f = OpenFile("filename");
	-----

	Say this function could throw an exception if it failed.  Since the interpreter can only catch (and make meaningful
	stack traces about) exceptions which derive from MDException, any exceptions that this throws would just percolate
	up out of the interpreter stack.  You could catch the exception yourself, but that's kind of tedious, especially when
	you call a lot of native functions.

	Instead, you can wrap the call to this unsafe function with a call to safeCode().
	
	-----
	File f = s.safeCode(OpenFile("filename"));
	-----
	
	What safeCode() does is it tries to execute the code it is passed.  If it succeeds, it simply returns any value that
	the code returns.  If it throws an exception derived from MDException, it rethrows the exception.  And if it throws
	an exception that derives from Exception, it throws a new MDException with the original exception's message as the
	message.  
	
	safeCode() is templated to allow any return value.  
	
	Params:
		code = The code to be executed.  This is a lazy parameter, so it's not actually executed until inside the call to
			safeCode.
			
	Returns:
		Whatever the code parameter returns.
	*/
	public final T safeCode(T)(lazy T code)
	{
		try
			return code;
		catch(MDException e)
			throw e;
		catch(Exception e)
			throwRuntimeException(e.toString());
	}

	/**
	Throws a new runtime exception, starting the debug traceback with the current debug location.
	*/
	public final void throwRuntimeException(MDValue* val)
	{
		throw new MDRuntimeException(startTraceback(), val);
	}

	/// ditto
	public final void throwRuntimeException(char[] fmt, ...)
	{
		throwRuntimeException(fmt, _arguments, _argptr);
	}
	
	// ditto
	public final void throwRuntimeException(char[] fmt, TypeInfo[] arguments, va_list argptr)
	{
		throw new MDRuntimeException(startTraceback(), fmt, arguments, argptr);
	}

	/**
	Gets the environment of a closure on the call stack.

	Params:
		depth = The depth into the call stack of the closure whose environment to get.  Defaults to 0, which
			means the currently-executing closure.  A depth of 1 would mean the closure which called this
			closure, 2 the closure that called that one etc.

	Returns:
		The closure's environment.
	*/
	public final MDNamespace environment(int depth = 0)
	{
		if(mARIndex < 1)
			throw new MDException("MDState.environment() - no current environment");

		if(depth < 0 || mARIndex - depth < 1)
			throw new MDException("MDState.environment() - Invalid depth: {}", depth);

		return mActRecs[mARIndex - depth].env;
	}
	
	/**
	Gets the current call depth, that is, how many functions are currently on the call stack which
	have yet to return.
	*/
	public final size_t callDepth()
	{
		return mARIndex;
	}

	/**
	Get a string representation of any MiniD value.  This is different from MDValue.toString() in that it will call
	any toString metamethods defined for the object.  
	
	Params:
		The value to get a string representation of.
		
	Returns:
		The string representation of the value.
	*/
	public final MDString valueToString(ref MDValue value)
	{
		if(value.mType == MDValue.Type.String)
			return value.mString;

		MDValue* method = getMM(value, MM.ToString);
		
		if(method.mType != MDValue.Type.Function)
			return new MDString(value.toString());

		mNativeCallDepth++;

		scope(exit)
			mNativeCallDepth--;

		easyCall(method.mFunction, 1, value);
		MDValue ret = pop();

		if(ret.mType != MDValue.Type.String)
			throwRuntimeException("MDState.valueToString() - '{}' method did not return a string", MetaNames[MM.ToString]);

		return ret.mString;
	}

	/**
	Determines if the value a is in the container b.  Returns true if so, false if not.
	*/
	public final bool opin(ref MDValue a, ref MDValue b)
	{
		return operatorIn(&a, &b);
	}

	/**
	Compares the two values, calling any opCmp metamethods, and returns the result.
	*/
	public final int cmp(ref MDValue a, ref MDValue b)
	{
		return compare(&a, &b);
	}

	/**
	Indexes src with index, and gives the result.  Like writing src[index] in MiniD.  Calls metamethods.
	*/
	public final MDValue idx(ref MDValue src, ref MDValue index)
	{
		return operatorIndex(&src, &index);
	}

	/**
	Index-assigns src into the index slot of dest.  Like writing dest[index] = src in MiniD.  Calls metamethods.
	*/
	public final void idxa(ref MDValue dest, ref MDValue index, ref MDValue src)
	{
		operatorIndexAssign(&dest, &index, &src);
	}

	/**
	Gets the length of val.  Like #val in MiniD.  Calls metamethods.
	*/
	public final MDValue len(ref MDValue val)
	{
		return operatorLength(&val);
	}

	/**
	Slice src from lo to hi.  Like src[lo .. hi] in MiniD.  Calls metamethods.
	*/
	public final MDValue slice(ref MDValue src, ref MDValue lo, ref MDValue hi)
	{
		return operatorSlice(&src, &lo, &hi);
	}

	/**
	Assign a slice src to dest from lo to hi.  Like dest[lo .. hi] = src in MiniD.  Calls metamethods.
	*/
	public final void slicea(ref MDValue dest, ref MDValue lo, ref MDValue hi, ref MDValue src)
	{
		operatorSliceAssign(&dest, &lo, &hi, &src);
	}

	/**
	Performs an arithmetic operation on the two values and returns the result.  Calls metamethods.
	*/
	public final MDValue add(ref MDValue a, ref MDValue b)
	{
		return binOp(MM.Add, &a, &b);
	}

	/// ditto
	public final MDValue sub(ref MDValue a, ref MDValue b)
	{
		return binOp(MM.Sub, &a, &b);
	}

	/// ditto
	public final MDValue mul(ref MDValue a, ref MDValue b)
	{
		return binOp(MM.Mul, &a, &b);
	}

	/// ditto
	public final MDValue div(ref MDValue a, ref MDValue b)
	{
		return binOp(MM.Div, &a, &b);
	}

	/// ditto
	public final MDValue mod(ref MDValue a, ref MDValue b)
	{
		return binOp(MM.Mod, &a, &b);
	}
	
	/**
	Negates the argument.  Calls metamethods.
	*/
	public final MDValue neg(ref MDValue a)
	{
		return unOp(MM.Neg, &a);
	}

	/**
	Performs a reflexive arithmetic operation on a, with b as the right hand side.  Calls metamethods.
	*/
	public final void addeq(ref MDValue a, ref MDValue b)
	{
		reflOp(MM.AddEq, &a, &b);
	}
	
	/// ditto
	public final void subeq(ref MDValue a, ref MDValue b)
	{
		reflOp(MM.SubEq, &a, &b);
	}
	
	/// ditto
	public final void muleq(ref MDValue a, ref MDValue b)
	{
		reflOp(MM.MulEq, &a, &b);
	}

	/// ditto
	public final void diveq(ref MDValue a, ref MDValue b)
	{
		reflOp(MM.DivEq, &a, &b);
	}

	/// ditto
	public final void modeq(ref MDValue a, ref MDValue b)
	{
		reflOp(MM.ModEq, &a, &b);
	}

	/**
	Performs a binary operation on the two values and returns the result.  Calls metamethods.
	*/
	public final MDValue and(ref MDValue a, ref MDValue b)
	{
		return binaryBinOp(MM.And, &a, &b);
	}

	/// ditto
	public final MDValue or(ref MDValue a, ref MDValue b)
	{
		return binaryBinOp(MM.Or, &a, &b);
	}

	/// ditto
	public final MDValue xor(ref MDValue a, ref MDValue b)
	{
		return binaryBinOp(MM.Xor, &a, &b);
	}

	/// ditto
	public final MDValue shl(ref MDValue a, ref MDValue b)
	{
		return binaryBinOp(MM.Shl, &a, &b);
	}

	/// ditto
	public final MDValue shr(ref MDValue a, ref MDValue b)
	{
		return binaryBinOp(MM.Shr, &a, &b);
	}

	/// ditto
	public final MDValue ushr(ref MDValue a, ref MDValue b)
	{
		return binaryBinOp(MM.UShr, &a, &b);
	}

	/**
	Performs a bitwise complement of the argument.  Calls metamethods.
	*/
	public final MDValue com(ref MDValue a)
	{
		return binaryUnOp(MM.Com, &a);
	}

	/**
	Performs a reflexive bitwise operation on a, with b as the right hand side.  Calls metamethods.
	*/
	public final void andeq(ref MDValue a, ref MDValue b)
	{
		binaryReflOp(MM.AndEq, &a, &b);
	}

	/// ditto
	public final void oreq(ref MDValue a, ref MDValue b)
	{
		binaryReflOp(MM.OrEq, &a, &b);
	}

	/// ditto
	public final void xoreq(ref MDValue a, ref MDValue b)
	{
		binaryReflOp(MM.XorEq, &a, &b);
	}

	/// ditto
	public final void shleq(ref MDValue a, ref MDValue b)
	{
		binaryReflOp(MM.ShlEq, &a, &b);
	}

	/// ditto
	public final void shreq(ref MDValue a, ref MDValue b)
	{
		binaryReflOp(MM.ShrEq, &a, &b);
	}

	/// ditto
	public final void ushreq(ref MDValue a, ref MDValue b)
	{
		binaryReflOp(MM.UShrEq, &a, &b);
	}
	
	/**
	Concatenates the list of values (which must be at least two items long) into a single value and
	returns it.  Calls metamethods.
	*/
	public final MDValue cat(MDValue[] vals)
	{
		if(vals.length < 2)
			throwRuntimeException("MDState.cat() - Must have at least two values to concatenate");

		return operatorCat(vals);
	}

	/**
	Appends the list of values (which must have at least one item) to the end of the value held in dest.
	Calls metamethods.
	*/
	public final void cateq(ref MDValue dest, MDValue[] vals)
	{
		if(vals.length < 1)
			throwRuntimeException("MDState.cateq() - Must have at least one value to append");

		operatorCatAssign(&dest, vals);
	}

	/** Yields from a native function acting as a coroutine, just like using the yield() expression
	in MiniD.
	
	Params:
		numReturns = How many returns you'd like to get from the yield operation.  -1 means as many
			values as are passed to this coroutine when it's resumed, in which case the return value
			of this method becomes significant.
			
		values = A list of values to yield.
		
	Returns:
		The number of return values to be popped off the stack.  If numReturns was -1, this is how many
		values you must pop.  If numReturns was >= 0, it's the same as numReturns.
	*/
	public final uint yield(uint numReturns, MDValue[] values...)
	{
		if(mCoroFiber is null)
			throwRuntimeException("Attempting to yield a non-coroutine state");
			
		if(Fiber.getThis() !is mCoroFiber)
			throwRuntimeException("Attempting to yield a coroutine with the wrong state, or attempting to yield outside the coroutine's execution");

		pushAR();
		
		uint first = mStackIndex;

		*mCurrentAR = mActRecs[mARIndex - 1];
		mCurrentAR.funcSlot = first;
		mCurrentAR.numReturns = numReturns;
		mStackIndex += values.length;
		checkStack(mStackIndex);
		mStack[first .. mStackIndex] = values[];
		mNumYields = values.length;

		mState = State.Suspended;
		Fiber.yield();
		callEpilogue(true);

		if(numReturns == -1)
			return mStackIndex - first;
		else
		{
			mStackIndex = first + numReturns;
			return numReturns;
		}
	}
	
	/**
	Resets this coroutine.  Only works if this coroutine is in the Dead state.
	*/
	public final void reset()
	{
		if(mState != State.Dead)
			throwRuntimeException("Can only reset a dead coroutine, not a {} coroutine", stateString());

		if(mCoroFiber)
			mCoroFiber.reset();

		mState = State.Initial;
	}

	/**
	Gets the context which owns this thread.
	*/
	public final MDContext context()
	{
		return mContext;
	}

	// ===================================================================================
	// Internal functions
	// ===================================================================================

	protected final Location startTraceback()
	{
		mContext.mTraceback.length = 0;
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

	protected final void badParamError(uint index, char[] fmt, ...)
	{
		throwRuntimeException("Bad argument {}: {}", index + 1, Stdout.layout.convert(_arguments, _argptr, fmt));
	}

	protected final bool callPrologue(uint slot, int numReturns, int numParams)
	{
		uint paramSlot;
		MDClosure closure;

		slot = mCurrentAR.base + slot;
		uint returnSlot = slot;

		if(numParams == -1)
			numParams = mStackIndex - slot - 1;

		assert(numParams >= 0, "negative num params in callPrologue");

		MDValue* func = &mStack[slot];
		
		switch(func.type())
		{
			case MDValue.Type.Function:
				closure = func.mFunction;
				paramSlot = slot + 1;
				break;

			case MDValue.Type.Class:
				MDClass cls = func.mClass;
				MDInstance n = cls.newInstance();
				MDValue* ctor = cls.getCtor();

				if(ctor !is null && ctor.mType == MDValue.Type.Function)
				{
					uint thisSlot = slot + 1;
					mStack[thisSlot] = n;

					try
					{
						if(callPrologue2(ctor.mFunction, thisSlot, 0, thisSlot, numParams))
							execute();
					}
					catch(MDRuntimeException e)
						throw e;
					catch(MDException e)
						throw new MDRuntimeException(startTraceback(), &e.value);
				}
				
				mStack[slot] = n;

				if(numReturns == -1)
					mStackIndex = slot + 1;
				else if(numReturns > 1)
				{
					slot++;
					numReturns--;

					auto stk = mStack;

					while(numReturns > 0)
					{
						stk[slot].setNull();
						slot++;
						numReturns--;
					}

					mStackIndex = mCurrentAR.savedTop;
				}

				if(mARIndex == 0)
					mState = State.Dead;
				return false;

			case MDValue.Type.Thread:
				MDState thread = func.mThread;
				
				if(thread is this)
					throwRuntimeException("Thread attempted to resume itself");

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

						if(numParams > 0)
						{
							assert(mStackIndex >= numParams, "thread resume initial stack underflow");

							thread.needStackSlots(numParams);
							thread.mStack[thread.mStackIndex .. thread.mStackIndex + numParams] = mStack[mStackIndex - numParams .. mStackIndex];
							thread.mStackIndex += numParams;
							mStackIndex -= numParams;
						}
						break;

					case State.Suspended:
						if(numParams > 0)
						{
							numParams--;
							assert(mStackIndex >= numParams, "thread resume suspended stack underflow");

							thread.saveResults(mStack[mStackIndex - numParams .. mStackIndex]);
							mStackIndex -= numParams + 1;
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
					callEpilogue(false);
					throw e;
				}
				catch(MDException e)
				{
					Location loc = startTraceback();
					callEpilogue(false);
					throw new MDRuntimeException(loc, &e.value);
				}

				assert(thread.mStackIndex >= numRets, "thread finished resuming stack underflow");
				
				saveResults(thread.mStack[thread.mStackIndex - numRets .. thread.mStackIndex]);
				thread.mStackIndex -= numRets;

				callEpilogue(true);
				return false;

			default:
				MDValue* method = getMM(*func, MM.Call);

				if(method.mType != MDValue.Type.Function)
					throwRuntimeException("Attempting to call a value of type '{}'", func.typeString());

				mStack[slot + 1] = mStack[slot];
				paramSlot = slot + 1;
				closure = method.mFunction;
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
			nativeCallPrologue(closure, returnSlot, numReturns, paramSlot, numParams);

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
				callEpilogue(false);
				throw e;
			}
			catch(MDException e)
			{
				Location loc = startTraceback();
				callEpilogue(false);
				throw new MDRuntimeException(loc, &e.value);
			}

			saveResults(mStack[mStackIndex - actualReturns .. mStackIndex]);
			callEpilogue(true);
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

				debug(STACKINDEX) Stdout.formatln("callPrologue2 adjusted the varargs and set mStackIndex to {}", mStackIndex);

				uint oldParamSlot = paramSlot;
				base = mStackIndex;

				for(int i = 0; i < funcDef.mNumParams; i++)
				{
					mStack[mStackIndex] = mStack[oldParamSlot];
					mStack[oldParamSlot].setNull();
					oldParamSlot++;
					mStackIndex++;
				}
				
				debug(STACKINDEX) Stdout.formatln("callPrologue2 copied the regular args for a vararg and set mStackIndex to {}", mStackIndex);
			}
			else
			{
				base = paramSlot;

				if(mStackIndex > base + funcDef.mNumParams)
				{
					mStackIndex = base + funcDef.mNumParams;
					debug(STACKINDEX) Stdout.formatln("callPrologue2 adjusted for too many args and set mStackIndex to {}", mStackIndex);
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

			debug(STACKINDEX) Stdout.formatln("callPrologue2 of function '{}' set mStackIndex to {} (local stack size = {}, base = {})", closure.toString(), mStackIndex, funcDef.mStackSize, base);

			for(int i = base + funcDef.mStackSize; i >= 0 && i >= base + numParams; i--)
				mStack[i].setNull();

			mCurrentAR.savedTop = mStackIndex;
			return true;
		}
	}

	protected final void nativeCallPrologue(MDClosure closure, uint returnSlot, int numReturns, uint paramSlot, int numParams)
	{
		mStackIndex = paramSlot + numParams;
		checkStack(mStackIndex);

		debug(STACKINDEX) Stdout.formatln("nativeCallPrologue called a native func '{}' and set mStackIndex to {} (got {} params)", closure.toString(), mStackIndex, numParams);

		pushAR();

		mCurrentAR.base = paramSlot;
		mCurrentAR.vargBase = 0;
		mCurrentAR.funcSlot = returnSlot;
		mCurrentAR.func = closure;
		mCurrentAR.numReturns = numReturns;
		mCurrentAR.savedTop = mStackIndex;
		mCurrentAR.env = closure.environment();
	}

	protected final void callEpilogue(bool needResults)
	{
		uint destSlot = mCurrentAR.funcSlot;
		int numExpRets = mCurrentAR.numReturns;

		bool isMultRet = false;
		
		MDValue[] results;
		
		if(needResults)
			results = loadResults();

		if(numExpRets == -1)
		{
			isMultRet = true;
			numExpRets = results.length;
		}

		popAR();

		if(needResults)
		{
			mNumYields = results.length;

			auto stk = mStack;

			if(numExpRets <= results.length)
				stk[destSlot .. destSlot + numExpRets] = results[0 .. numExpRets];
			else
			{
				stk[destSlot .. destSlot + results.length] = results[];
				stk[destSlot + results.length .. destSlot + numExpRets] = MDValue.nullValue;
			}
		}
		else
		{
			mNumYields = 0;
		}

		if(mARIndex == 0)
			mState = State.Dead;

		if(isMultRet)
			mStackIndex = destSlot + numExpRets;
		else
			mStackIndex = mCurrentAR.savedTop;

		debug(STACKINDEX) Stdout.formatln("callEpilogue() set mStackIndex to {}", mStackIndex);
	}
	
	protected final void saveResults(MDValue[] results)
	{
		if(mResults.length - mResultIndex < results.length)
		{
			try
				mResults.length = mResults.length * 2;
			catch
			{
				throwRuntimeException("Script result stack overflow");
			}
		}
		
		mResults[mResultIndex .. mResultIndex + results.length] = results[];
		mResultIndex += results.length;
		mResultsLengths ~= results.length;
	}

	protected final MDValue[] loadResults()
	{
		assert(mResultsLengths.length > 0);//, "Script result stack underflow");

		int len = mResultsLengths[$ - 1];
		mResultsLengths.length = mResultsLengths.length - 1;

		MDValue[] ret = mResults[mResultIndex - len .. mResultIndex];
		mResultIndex -= len;
		return ret;
	}

	protected final uint resume(uint numParams)
	{
		if(mCoroFunc is null)
			throwRuntimeException("Cannot resume a state which has no associated coroutine");

		switch(mState)
		{
			case State.Initial:
				mStack[0] = mCoroFunc;

				if(mCoroFunc.isNative)
				{
					assert(mCoroFiber !is null, "no coroutine fiber for native coroutine");

					nativeCallPrologue(mCoroFunc, 0, -1, 1, numParams);
					mCoroFiber.call();

					if(mCoroFiber.state == Fiber.State.HOLD)
						mState = State.Suspended;
					else if(mCoroFiber.state == Fiber.State.TERM)
						mState = State.Dead;
				}
				else
				{
					bool result = callPrologue(0, -1, numParams);
					assert(result == true, "resume callPrologue must return true");

					execute();
				}

				return mNumYields;

			case State.Suspended:
				if(mCoroFunc.isNative)
				{
					mCoroFiber.call();

					if(mCoroFiber.state == Fiber.State.HOLD)
						mState = State.Suspended;
					else if(mCoroFiber.state == Fiber.State.TERM)
						mState = State.Dead;
				}
				else
				{
					callEpilogue(true);
					execute(mSavedCallDepth);
				}

				return mNumYields;

			default:
				assert(false, "resume invalid state");
		}
	}
	
	protected final void coroResume()
	{
		int actualReturns;

		try
		{
			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			actualReturns = mCoroFunc.native.dg(this, mStackIndex - 2);
		}
		catch(MDRuntimeException e)
		{
			callEpilogue(false);
			throw e;
		}
		catch(MDException e)
		{
			Location loc = startTraceback();
			callEpilogue(false);
			throw new MDRuntimeException(loc, &e.value);
		}

		saveResults(mStack[mStackIndex - actualReturns .. mStackIndex]);
		callEpilogue(true);
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
			throwRuntimeException("Script value stack overflow: {}", mStack.length);
		}

		MDValue* newBase = mStack.ptr;

		if(oldBase !is newBase)
			for(MDUpval* uv = mUpvalHead; uv !is null; uv = uv.next)
				uv.value = (uv.value - oldBase) + newBase;
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

	protected final void close(uint index)
	{
		MDValue* base = &mStack[mCurrentAR.base + index];

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
		MDValue* slot = &mStack[mCurrentAR.base + num];

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

	protected final MDValue* getMM(ref MDValue obj, MM method)
	{
		MDValue* m;
		
		switch(obj.type)
		{
			case MDValue.Type.Table:
				m = obj.mTable[MDValue(MetaStrings[method])];

				if(m.mType != MDValue.Type.Function)
					goto default;

				break;

			case MDValue.Type.Instance:
				m = obj.mInstance[MetaStrings[method]];
				break;

			default:
				MDNamespace n = mContext.getMetatable(obj.type);

				if(n is null)
					break;

				m = n[MetaStrings[method]];
				break;
		}

		if(m is null || m.mType != MDValue.Type.Function)
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
		
		mdfloat f1 = void;
		mdfloat f2 = void;

		if(RS.mType == MDValue.Type.Int)
		{
			if(RT.mType == MDValue.Type.Int)
			{
				int i1 = RS.mInt;
				int i2 = RT.mInt;
    
				switch(operation)
				{
					case MM.Add: return MDValue(i1 + i2);
					case MM.Sub: return MDValue(i1 - i2);
					case MM.Mul: return MDValue(i1 * i2);

					case MM.Mod:
						if(i2 == 0)
							throwRuntimeException("Integer modulo by zero");

						return MDValue(i1 % i2);

					case MM.Div:
						if(i2 == 0)
							throwRuntimeException("Integer divide by zero");

						return MDValue(i1 / i2);

					default:
						assert(false);
				}
			}
			else if(RT.mType == MDValue.Type.Float)
			{
				f1 = RS.mInt;
				f2 = RT.mFloat;
				goto _float;
			}
		}
		else if(RS.mType == MDValue.Type.Float)
		{
			if(RT.mType == MDValue.Type.Int)
			{
				f1 = RS.mFloat;
				f2 = RT.mInt;
				goto _float;
			}
			else if(RT.mType == MDValue.Type.Float)
			{
				f1 = RS.mFloat;
				f2 = RT.mFloat;

				_float:
				switch(operation)
				{
					case MM.Add: return MDValue(f1 + f2);
					case MM.Sub: return MDValue(f1 - f2);
					case MM.Mul: return MDValue(f1 * f2);
					case MM.Div: return MDValue(f1 / f2);
					case MM.Mod: return MDValue(f1 % f2);

					default:
						assert(false);
				}
			}
		}

		// mm
		MDValue* method = getMM(*RS, operation);

		if(method.mType != MDValue.Type.Function)
			throwRuntimeException("Cannot perform arithmetic ({}) on a '{}' and a '{}'", MetaNames[operation], RS.typeString(), RT.typeString());

		mNativeCallDepth++;

		scope(exit)
			mNativeCallDepth--;

		uint funcSlot = push(method);
		push(RS);
		push(RT);
		call(funcSlot, 2, 1);
		return pop();
	}

	protected final MDValue unOp(MM operation, MDValue* RS)
	{
		assert(operation == MM.Neg, "invalid unOp operation");

		debug(TIMINGS) scope _profiler_ = new Profiler("Neg");

		if(RS.mType == MDValue.Type.Int)
			return MDValue(-RS.mInt);
		else if(RS.mType == MDValue.Type.Float)
			return MDValue(-RS.mFloat);

		MDValue* method = getMM(*RS, MM.Neg);

		if(method.mType != MDValue.Type.Function)
			throwRuntimeException("Cannot perform negation on a '{}'", RS.typeString());

		mNativeCallDepth++;

		scope(exit)
			mNativeCallDepth--;

		uint funcSlot = push(method);
		push(RS);
		call(funcSlot, 1, 1);
		return pop();
	}
	
	protected final void reflOp(MM operation, MDValue* RD, MDValue* RS)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("ReflArith");

		mdfloat f1 = void;
		mdfloat f2 = void;

		if(RD.mType == MDValue.Type.Int)
		{
			if(RS.mType == MDValue.Type.Int)
			{
				int i2 = RS.mInt;

				switch(operation)
				{
					case MM.AddEq: RD.mInt += i2; return;
					case MM.SubEq: RD.mInt -= i2; return;
					case MM.MulEq: RD.mInt *= i2; return;

					case MM.ModEq:
						if(i2 == 0)
							throwRuntimeException("Integer modulo by zero");

						RD.mInt %= i2;
						return;

					case MM.DivEq:
						if(i2 == 0)
							throwRuntimeException("Integer divide by zero");

						RD.mInt /= i2;
						return;

					default:
						assert(false);
				}
			}
			else if(RS.mType == MDValue.Type.Float)
			{
				f1 = RD.mInt;
				f2 = RS.mFloat;
				goto _float;
			}
		}
		else if(RD.mType == MDValue.Type.Float)
		{
			if(RS.mType == MDValue.Type.Int)
			{
				f1 = RD.mFloat;
				f2 = RS.mInt;
				goto _float;
			}
			else if(RS.mType == MDValue.Type.Float)
			{
				f1 = RD.mFloat;
				f2 = RS.mFloat;

				_float:
				RD.mType = MDValue.Type.Float;

				switch(operation)
				{
					case MM.AddEq: RD.mFloat = f1 + f2; return;
					case MM.SubEq: RD.mFloat = f1 - f2; return;
					case MM.MulEq: RD.mFloat = f1 * f2; return;
					case MM.DivEq: RD.mFloat = f1 / f2; return;
					case MM.ModEq: RD.mFloat = f1 % f2; return;

					default:
						assert(false);
				}
			}
		}

		MDValue* method = getMM(*RD, operation);

		if(method.mType != MDValue.Type.Function)
			throwRuntimeException("Cannot perform arithmetic ({}) on a '{}' and a '{}'", MetaNames[operation], RD.typeString(), RS.typeString());

		mNativeCallDepth++;

		scope(exit)
			mNativeCallDepth--;

		uint funcSlot = push(method);
		push(RD);
		push(RS);
		call(funcSlot, 2, 0);
	}

	protected final MDValue binaryBinOp(MM operation, MDValue* RS, MDValue* RT)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("BitArith");

		if(RS.mType == MDValue.Type.Int && RT.mType == MDValue.Type.Int)
		{
			switch(operation)
			{
				case MM.And:  return MDValue(RS.mInt & RT.mInt);
				case MM.Or:   return MDValue(RS.mInt | RT.mInt);
				case MM.Xor:  return MDValue(RS.mInt ^ RT.mInt);
				case MM.Shl:  return MDValue(RS.mInt << RT.mInt);
				case MM.Shr:  return MDValue(RS.mInt >> RT.mInt);
				case MM.UShr: return MDValue(RS.mInt >>> RT.mInt);
				
				default:
					assert(false);
			}
		}

		MDValue* method = getMM(*RS, operation);

		if(method.mType != MDValue.Type.Function)
			throwRuntimeException("Cannot perform bitwise arithmetic ({}) on a '{}' and a '{}'", MetaNames[operation], RS.typeString(), RT.typeString());

		mNativeCallDepth++;

		scope(exit)
			mNativeCallDepth--;

		uint funcSlot = push(method);
		push(RS);
		push(RT);
		call(funcSlot, 2, 1);
		return pop();
	}
	
	protected final MDValue binaryUnOp(MM operation, MDValue* RS)
	{
		assert(operation == MM.Com, "invalid binaryUnOp operation");
		debug(TIMINGS) scope _profiler_ = new Profiler("Com");

		if(RS.mType == MDValue.Type.Int)
			return MDValue(~RS.mInt);

		MDValue* method = getMM(*RS, MM.Com);

		if(method.type != MDValue.Type.Function)
			throwRuntimeException("Cannot perform complement on a '{}'", RS.typeString());

		mNativeCallDepth++;

		scope(exit)
			mNativeCallDepth--;

		uint funcSlot = push(method);
		push(RS);
		call(funcSlot, 1, 1);
		return pop();
	}

	protected final void binaryReflOp(MM operation, MDValue* RD, MDValue* RS)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("ReflBitArith");

		if(RD.mType == MDValue.Type.Int && RS.mType == MDValue.Type.Int)
		{
			switch(operation)
			{
				case MM.AndEq:  RD.mInt &= RS.mInt; return;
				case MM.OrEq:   RD.mInt |= RS.mInt; return;
				case MM.XorEq:  RD.mInt ^= RS.mInt; return;
				case MM.ShlEq:  RD.mInt <<= RS.mInt; return;
				case MM.ShrEq:  RD.mInt >>= RS.mInt; return;
				case MM.UShrEq: RD.mInt >>>= RS.mInt; return;

				default:
					assert(false);
			}
		}

		MDValue* method = getMM(*RD, operation);

		if(method.mType != MDValue.Type.Function)
			throwRuntimeException("Cannot perform bitwise arithmetic ({}) on a '{}' and a '{}'", MetaNames[operation], RD.typeString(), RS.typeString());

		mNativeCallDepth++;

		scope(exit)
			mNativeCallDepth--;

		uint funcSlot = push(method);
		push(RD);
		push(RS);
		call(funcSlot, 2, 0);
	}

	protected final int compare(MDValue* RS, MDValue* RT)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("Compare");

		int cmpValue;
		
		mdfloat f1 = void;
		mdfloat f2 = void;

		if(RS.mType == MDValue.Type.Int)
		{
			if(RT.mType == MDValue.Type.Int)
				return Compare3(RS.mInt, RT.mInt);
			else if(RT.mType == MDValue.Type.Float)
			{
				f1 = RS.mInt;
				f2 = RT.mFloat;
				goto _float;
			}
		}
		else if(RS.mType == MDValue.Type.Float)
		{
			if(RT.mType == MDValue.Type.Int)
			{
				f1 = RS.mFloat;
				f2 = RT.mInt;
				goto _float;
			}
			else if(RT.mType == MDValue.Type.Float)
			{
				f1 = RS.mFloat;
				f2 = RT.mFloat;

				_float:
				return Compare3(f1, f2);
			}
		}
		
		if(RS.type == RT.type)
		{
			switch(RS.type)
			{
				case MDValue.Type.Null:
					return 0;

				case MDValue.Type.Bool:
					return (cast(int)RS.mBool - cast(int)RT.mBool);

				case MDValue.Type.Char:
					return Compare3(RS.mChar, RT.mChar);

				default:
					MDObject o1 = RS.mObj;
					MDObject o2 = RT.mObj;

					if(o1 is o2)
						return 0;
					else
					{
						MDValue* method = getMM(*RS, MM.Cmp);

						if(method.mType == MDValue.Type.Function)
						{
							mNativeCallDepth++;

							scope(exit)
								mNativeCallDepth--;

							uint funcReg = push(method);
							push(RS);
							push(RT);
							call(funcReg, 2, 1);
							MDValue ret = pop();

							if(ret.mType != MDValue.Type.Int)
								throwRuntimeException("opCmp is expected to return an int for type '{}'", RS.typeString());

							return ret.mInt;
						}
						else
							return MDObject.compare(o1, o2);
					}
			}
		}
		else
		{
			MDValue* method = getMM(*RS, MM.Cmp);

			if(method.mType != MDValue.Type.Function)
				throwRuntimeException("cannot compare values of type '{}' and '{}' (no opCmp defined for '{0}')", RS.typeString(), RT.typeString());

			mNativeCallDepth++;

			scope(exit)
				mNativeCallDepth--;

			uint funcReg = push(method);
			push(RS);
			push(RT);
			call(funcReg, 2, 1);
			MDValue ret = pop();

			if(ret.mType != MDValue.Type.Int)
				throwRuntimeException("opCmp is expected to return an int for type '{}'", RS.typeString());

			return ret.mInt;
		}
	}

	protected final bool operatorIn(MDValue* RS, MDValue* RT)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("In");

		switch(RT.type)
		{
			case MDValue.Type.String:
				if(RS.mType != MDValue.Type.Char)
					throwRuntimeException("Can only use characters to look in strings, not '{}'", RS.typeString());

				return ((RS.mChar in RT.mString) >= 0);

			case MDValue.Type.Array:
				return ((*RS in RT.mArray) >= 0);

			case MDValue.Type.Table:
				return ((*RS in RT.mTable) !is null);

			case MDValue.Type.Namespace:
				if(RS.mType != MDValue.Type.String)
					throwRuntimeException("Attempting to access namespace '{}' with type '{}'", RT.mNamespace.nameString(), RS.typeString());

				return ((RS.mString in RT.mNamespace) !is null);

			default:
				MDValue* method = getMM(*RT, MM.In);

				if(method.mType != MDValue.Type.Function)
					throwRuntimeException("No {} metamethod for type '{}'", MetaNames[MM.In], RT.typeString());

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
				return MDValue(RS.mString.length);

			case MDValue.Type.Array:
				return MDValue(RS.mArray.length);

			default:
				MDValue* method = getMM(*RS, MM.Length);

				if(method.mType == MDValue.Type.Function)
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

			if(method.mType != MDValue.Type.Function)
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
				if(RT.mType != MDValue.Type.Int)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access an array with a '{}'", RT.typeString());});

				int index = RT.mInt;
				MDArray arr = RS.mArray;

				if(index < 0)
					index += arr.length;

				if(index < 0 || index >= arr.length)
					return tryMM({return new MDRuntimeException(startTraceback(), "Invalid array index: {}", index);});

				return *arr[index];

			case MDValue.Type.String:
				if(RT.mType != MDValue.Type.Int)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access a string with a '{}'", RT.typeString());});

				int index = RT.mInt;
				MDString str = RS.mString;

				if(index < 0)
					index += str.length;

				if(index < 0 || index >= str.length)
					return tryMM({return new MDRuntimeException(startTraceback(), "Invalid string index: {}", index);});

				return MDValue(str[index]);

			case MDValue.Type.Table:
				if(RT.mType == MDValue.Type.Null)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index a table with a key of type 'null'");});

				MDValue* v = RS.mTable[*RT];

				if(v.mType == MDValue.Type.Null)
				{
					MDValue* method = getMM(*RS, MM.Index);

					if(method.mType == MDValue.Type.Function)
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
				if(RT.mType != MDValue.Type.String)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index an instance with a key of type '{}'", RT.typeString());});

				MDValue* v = RS.mInstance[RT.mString];

				if(v is null)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access nonexistent member '{}' from class instance", RT.toString());});

				return *v;

			case MDValue.Type.Class:
				if(RT.mType != MDValue.Type.String)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index a class with a key of type '{}'", RT.typeString());});

				MDValue* v = RS.mClass[RT.mString];

				if(v is null)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access nonexistent member '{}' from class", RT.toString());});

				return *v;

			case MDValue.Type.Namespace:
				if(RT.mType != MDValue.Type.String)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index namespace '{}' with a key of type '{}'", RS.mNamespace.nameString(), RT.typeString());});

				MDValue* v = RS.mNamespace[RT.mString];

				if(v is null)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access nonexistent member '{}' from namespace {}", RT.toString(), RS.mNamespace.nameString);});

				return *v;

			default:
				return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index a value of type '{}'", RS.typeString());});
		}
	}

	protected final void operatorIndexAssign(MDValue* RD, MDValue* RS, MDValue* RT)
	{
		void tryMM(MDRuntimeException delegate() ex)
		{
			MDValue* method = getMM(*RD, MM.IndexAssign);

			if(method.mType != MDValue.Type.Function)
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
				if(RS.mType != MDValue.Type.Int)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to access an array with a '{}'", RS.typeString());});

				int index = RS.mInt;
				MDArray arr = RD.mArray;

				if(index < 0)
					index += arr.length;

				if(index < 0 || index >= arr.length)
					return tryMM({return new MDRuntimeException(startTraceback(), "Invalid array index: {}", RS.mInt);});

				arr[index] = *RT;
				return;

			case MDValue.Type.Table:
				if(RS.mType == MDValue.Type.Null)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign a table with a key of type 'null'");});

				MDTable table = RD.mTable;
				MDValue* val = (*RS in table);

				if(val is null)
				{
					MDValue* method = getMM(*RD, MM.IndexAssign);

					if(method.mType == MDValue.Type.Function)
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
				{
					if(RT.mType == MDValue.Type.Null)
						table[*RS] = *RT;
					else
						*val = *RT;
				}
				
				return;

			case MDValue.Type.Instance:
				if(RS.mType != MDValue.Type.String)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign an instance with a key of type '{}'", RS.typeString());});

				MDString k = RS.mString;
				MDValue* val = RD.mInstance.getField(k);

				if(val is null)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to add a member '{}' to a class instance", RS.toString());});

				*val = RT;
				return;

			case MDValue.Type.Class:
				if(RS.mType != MDValue.Type.String)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign a class with a key of type '{}'", RS.typeString());});

				RD.mClass[RS.mString] = *RT;
				return;

			case MDValue.Type.Namespace:
				if(RS.mType != MDValue.Type.String)
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign a namespace with a key of type '{}'", RS.typeString());});

				RD.mNamespace[RS.mString] = *RT;
				return;

			default:
				return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to index assign a value of type '{}'", RD.typeString());});
		}
	}
	
	protected final MDValue operatorSlice(MDValue* src, MDValue* lo, MDValue* hi)
	{
		MDValue tryMM(MDRuntimeException delegate() ex)
		{
			MDValue* method = getMM(*src, MM.Slice);

			if(method.mType != MDValue.Type.Function)
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
				MDArray arr = src.mArray;
				int loIndex;
				int hiIndex;

				if(lo.mType == MDValue.Type.Null && hi.mType == MDValue.Type.Null)
					return *src;

				if(lo.mType == MDValue.Type.Null)
					loIndex = 0;
				else if(lo.mType == MDValue.Type.Int)
				{
					loIndex = lo.mInt;

					if(loIndex < 0)
						loIndex += arr.length;
				}
				else
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice an array with a '{}'", lo.typeString());});

				if(hi.mType == MDValue.Type.Null)
					hiIndex = arr.length;
				else if(hi.mType == MDValue.Type.Int)
				{
					hiIndex = hi.mInt;

					if(hiIndex < 0)
						hiIndex += arr.length;
				}
				else
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice an array with a '{}'", hi.typeString());});

				if(loIndex > hiIndex || loIndex < 0 || loIndex > arr.length || hiIndex < 0 || hiIndex > arr.length)
					return tryMM({return new MDRuntimeException(startTraceback(), "Invalid slice indices [{} .. {}] (array length = {})", loIndex, hiIndex, arr.length);});

				return MDValue(arr[loIndex .. hiIndex]);

			case MDValue.Type.String:
				MDString str = src.mString;
				int loIndex;
				int hiIndex;

				if(lo.mType == MDValue.Type.Null && hi.mType == MDValue.Type.Null)
					return *src;

				if(lo.mType == MDValue.Type.Null)
					loIndex = 0;
				else if(lo.mType == MDValue.Type.Int)
				{
					loIndex = lo.mInt;

					if(loIndex < 0)
						loIndex += str.length;
				}
				else
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice a string with a '{}'", lo.typeString());});

				if(hi.mType == MDValue.Type.Null)
					hiIndex = str.length;
				else if(hi.mType == MDValue.Type.Int)
				{
					hiIndex = hi.mInt;

					if(hiIndex < 0)
						hiIndex += str.length;
				}
				else
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice a string with a '{}'", hi.typeString());});

				if(loIndex > hiIndex || loIndex < 0 || loIndex > str.length || hiIndex < 0 || hiIndex > str.length)
					return tryMM({return new MDRuntimeException(startTraceback(), "Invalid slice indices [{} .. {}] (string length = {})", loIndex, hiIndex, str.length);});

				return MDValue(str[loIndex .. hiIndex]);

			default:
				return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice a value of type '{}'", src.typeString());});
		}
	}
	
	protected final void operatorSliceAssign(MDValue* RD, MDValue* lo, MDValue* hi, MDValue* RS)
	{
		void tryMM(MDRuntimeException delegate() ex)
		{
			MDValue* method = getMM(*RD, MM.SliceAssign);

			if(method.mType != MDValue.Type.Function)
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
				MDArray arr = RD.mArray;
				int loIndex;
				int hiIndex;

				if(lo.mType == MDValue.Type.Null)
					loIndex = 0;
				else if(lo.mType == MDValue.Type.Int)
				{
					loIndex = lo.mInt;

					if(loIndex < 0)
						loIndex += arr.length;
				}
				else
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice assign an array with a '{}'", lo.typeString());});

				if(hi.mType == MDValue.Type.Null)
					hiIndex = arr.length;
				else if(hi.mType == MDValue.Type.Int)
				{
					hiIndex = hi.mInt;

					if(hiIndex < 0)
						hiIndex += arr.length;
				}
				else
					return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice assign an array with a '{}'", hi.typeString());});

				if(loIndex > hiIndex || loIndex < 0 || loIndex > arr.length || hiIndex < 0 || hiIndex > arr.length)
					return tryMM({return new MDRuntimeException(startTraceback(), "Invalid slice indices [{} .. {}] (array length = {})", loIndex, hiIndex, arr.length);});

				if(RS.mType == MDValue.Type.Array)
				{
					if((hiIndex - loIndex) != RS.mArray.length)
						throw new MDRuntimeException(startTraceback(), "Array slice assign lengths do not match ({} and {})", hiIndex - loIndex, RS.mArray.length);

					arr[loIndex .. hiIndex] = RS.mArray;
				}
				else
					arr[loIndex .. hiIndex] = *RS;
				break;

			default:
				return tryMM({return new MDRuntimeException(startTraceback(), "Attempting to slice assign a value of type '{}'", RD.typeString());});
		}
	}
	
	protected final MDValue lookupMethod(MDValue* RS, MDString methodName)
	{
		MDValue* v;

		switch(RS.type)
		{
			case MDValue.Type.Instance:
				v = RS.mInstance[methodName];

				if(v is null)
					throwRuntimeException("Attempting to access nonexistent member '{}' from class instance", methodName);

				break;

			case MDValue.Type.Table:
				v = RS.mTable[MDValue(methodName)];

				if(v.mType == MDValue.Type.Function)
					break;

				goto default;

			case MDValue.Type.Namespace:
				v = RS.mNamespace[methodName];

				if(v is null)
					throwRuntimeException("Attempting to access nonexistent member '{}' from namespace '{}'", methodName, RS.mNamespace.nameString);

				break;

			case MDValue.Type.Class:
				v = RS.mClass[methodName];

				if(v is null)
					throwRuntimeException("Attempting to access nonexistent member '{}' from class '{}'", methodName, RS.mClass.getName());

				break;

			default:
				MDNamespace metatable = mContext.getMetatable(RS.mType);

				if(metatable is null)
					throwRuntimeException("No metatable for type '{}'", RS.typeString());

				v = metatable[methodName];

				if(v is null)
					throwRuntimeException("No implementation of method '{}' for type '{}'", methodName, RS.typeString());

				break;
		}
		
		return *v;
	}
	
	protected final MDValue operatorCat(MDValue[] vals)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("Cat");

		if(vals[0].mType == MDValue.Type.Array)
			return MDValue(MDArray.concat(vals));
		else if(vals[0].mType == MDValue.Type.String || vals[0].mType == MDValue.Type.Char)
		{
			uint badIndex;
			MDString newStr = MDString.concat(vals, badIndex);

			if(newStr is null)
				throwRuntimeException("Cannot list concatenate a '{}' and a '{}' (index: {})", vals[0].typeString(), vals[badIndex].typeString(), badIndex);

			return MDValue(newStr);
		}
		else
		{
			MDValue* method = getMM(vals[0], MM.Cat);

			if(method.mType == MDValue.Type.Function)
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
	
	protected final void operatorCatAssign(MDValue* dest, MDValue[] vals)
	{
		debug(TIMINGS) scope _profiler_ = new Profiler("CatEq");

		if(dest.mType == MDValue.Type.Array)
			MDArray.concatEq(dest.mArray, vals);
		else if(dest.mType == MDValue.Type.String || dest.mType == MDValue.Type.Char)
		{
			uint badIndex;
			MDString newStr = MDString.concatEq(*dest, vals, badIndex);

			if(newStr is null)
				throwRuntimeException("Cannot append a '{}' (index: {}) to a '{}'", vals[badIndex].typeString(), badIndex, dest.typeString());

			*dest = newStr;
		}
		else
		{
			MDValue* method = getMM(*dest, MM.CatEq);

			if(method.mType != MDValue.Type.Function)
				throwRuntimeException("Cannot append values to a '{}'", dest.typeString());

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
		bool isReturning = false;
		size_t stackBase = mCurrentAR.base;
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
						assert((stackBase + (index & ~Instruction.locMask)) < mStack.length, "invalid based stack index");

						if(environment)
							*environment = mCurrentAR.env;

						return &mStack[stackBase + (index & ~Instruction.locMask)];

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
						assert(idx.mType == MDValue.Type.String, "trying to get a non-string global");
						MDString name = idx.mString;

						MDValue* glob = null;
						MDValue* src = &mStack[stackBase];

						switch(src.type)
						{
							case MDValue.Type.Table:
								MDValue* v = src.mTable[*idx];

								if(v.mType == MDValue.Type.Null)
									break;

								glob = v;
								break;

							case MDValue.Type.Instance:  glob = src.mInstance[name]; break;
							case MDValue.Type.Class:     glob = src.mClass[name]; break;
							case MDValue.Type.Namespace: glob = src.mNamespace[name]; break;
							default: break;
						}

						if(glob is null)
						{
							MDNamespace ns = mCurrentAR.env;

							if(src.mType == MDValue.Type.Namespace && ns is src.mNamespace)
								ns = ns.mParent;

							for( ; ns !is null; ns = ns.mParent)
							{
								glob = ns[name];

								if(glob !is null)
								{
									if(environment)
										*environment = ns;

									return glob;
								}
							}

							throwRuntimeException("Attempting to get nonexistent global '{}'", name);
						}
						else if(environment)
							*environment = mStack[stackBase];

						return glob;
				}
			}

			while(true)
			{
				Instruction i = *mCurrentAR.pc;
				mCurrentAR.pc++;

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
						mStack[stackBase + i.rd] = &mStack[stackBase + i.rs];
						break;
						
					case Op.LoadConst:
						debug(TIMINGS) scope _profiler_ = new Profiler("LoadConst");
						mStack[stackBase + i.rd] = constTable[i.rs & ~Instruction.locMask];
						break;
						
					case Op.CondMove:
						debug(TIMINGS) scope _profiler_ = new Profiler("CondMove");

						MDValue* RD = get(i.rd);

						if(RD.mType == MDValue.Type.Null)
							*RD = *get(i.rs);
						break;

					case Op.LoadBool:
						debug(TIMINGS) scope _profiler_ = new Profiler("LoadBool");

						*get(i.rd) = cast(bool)i.rs;
						break;
	
					case Op.LoadNull:
						debug(TIMINGS) scope _profiler_ = new Profiler("LoadNull");

						get(i.rd).setNull();
						break;

					case Op.LoadNulls:
						debug(TIMINGS) scope _profiler_ = new Profiler("LoadNulls");

						MDValue* v = &mStack[stackBase + i.rd];

						for(int j = 0; j < i.imm; j++, v++)
							v.setNull();
						break;
	
					case Op.NewGlobal:
						debug(TIMINGS) scope _profiler_ = new Profiler("NewGlobal");

						RS = *get(i.rs);
						MDString name = constTable[i.rt & ~Instruction.locMask].mString;

						MDNamespace env = mCurrentAR.env;
						MDValue* val = env[name];

						if(val !is null)
							throwRuntimeException("Attempting to create global '{}' that already exists", RT.toString());

						env[name] = RS;
						break;

					// Logical and Control Flow
					case Op.Import:
						debug(TIMINGS) scope _profiler_ = new Profiler("Import");
						assert(mStackIndex == mCurrentAR.savedTop, "import: stack index not at top");

						RS = get(i.rs);

						if(RS.mType != MDValue.Type.String)
							throwRuntimeException("Import expression must be a string value, not '{}'", RS.typeString());

						try
							mStack[stackBase + i.rd] = mContext.importModule(RS.as!(dchar[]), this);
						catch(MDRuntimeException e)
							throw e;
						catch(MDException e)
							throw new MDRuntimeException(startTraceback(), &e.value);
						break;

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
									cmpValue = (cast(int)RS.mBool - cast(int)RT.mBool);
									break;
									
								case MDValue.Type.Int:
									int i1 = RS.mInt;
									int i2 = RT.mInt;
									cmpValue = i1 < i2 ? -1 : i1 > i2 ? 1 : 0;
									break;

								case MDValue.Type.Float:
									mdfloat f1 = RS.mFloat;
									mdfloat f2 = RT.mFloat;
									cmpValue = f1 < f2 ? -1 : f1 > f2 ? 1 : 0;
									break;

								case MDValue.Type.Char:
									uint i1 = RS.mChar;
									uint i2 = RT.mChar;
									cmpValue = i1 < i2 ? -1 : i1 > i2 ? 1 : 0;
									break;

								default:
									MDObject o1 = RS.mObj;
									MDObject o2 = RT.mObj;

									if(o1 is o2)
										cmpValue = 0;
									else
									{
										MDValue* method = getMM(RS, MM.Cmp);

										if(method.mType == MDValue.Type.Function)
										{
											mNativeCallDepth++;

											scope(exit)
												mNativeCallDepth--;

											uint funcReg = push(method);
											push(RS);
											push(RT);
											call(funcReg, 2, 1);
											MDValue ret = pop();

											if(ret.mType != MDValue.Type.Int)
												throwRuntimeException("opCmp is expected to return an int, not '{}', for type '{}'", ret.typeString(), RS.typeString());

											cmpValue = ret.mInt;
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

						if(auto ptr = (RS in t.offsets))
							offset = *ptr;
						else
							offset = t.defaultOffset;

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
						MDValue* idx = &mStack[stackBase + i.rd];
						MDValue* hi = &mStack[stackBase + i.rd + 1];
						MDValue* step = &mStack[stackBase + i.rd + 2];
						
						if(idx.mType != MDValue.Type.Int || hi.mType != MDValue.Type.Int || step.mType != MDValue.Type.Int)
							throwRuntimeException("Numeric for loop low, high, and step values must be integers");

						int intIdx = idx.mInt;
						int intHi = hi.mInt;
						int intStep = step.mInt;

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
						int idx = mStack[stackBase + i.rd].mInt;
						int hi = mStack[stackBase + i.rd + 1].mInt;
						int step = mStack[stackBase + i.rd + 2].mInt;

						if(step > 0)
						{
							if(idx < hi)
							{
								mStack[stackBase + i.rd + 3] = idx;
								mStack[stackBase + i.rd] = idx + step;
								mCurrentAR.pc += i.imm;
							}
						}
						else
						{
							if(idx >= hi)
							{
								mStack[stackBase + i.rd + 3] = idx;
								mStack[stackBase + i.rd] = idx + step;
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
						MDValue src = mStack[stackBase + rd];

						if(src.mType != MDValue.Type.Function)
						{
							MDValue* apply = getMM(src, MM.Apply);

							if(apply.mType != MDValue.Type.Function)
								throwRuntimeException("No implementation of {} for type '{}'", MetaNames[MM.Apply], src.typeString());

							mNativeCallDepth++;

							scope(exit)
								mNativeCallDepth--;

							mStack[stackBase + rd + 2] = mStack[stackBase + rd + 1];
							mStack[stackBase + rd + 1] = src;
							mStack[stackBase + rd] = *apply;

							call(rd, 2, 3);
						}

						mStack[stackBase + funcReg + 2] = mStack[stackBase + rd + 2];
						mStack[stackBase + funcReg + 1] = mStack[stackBase + rd + 1];
						mStack[stackBase + funcReg] = mStack[stackBase + rd];

						call(funcReg, 2, i.imm);
						mStackIndex = mCurrentAR.savedTop;

						if(mStack[stackBase + funcReg].mType != MDValue.Type.Null)
						{
							mStack[stackBase + rd + 2] = mStack[stackBase + funcReg];

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
						else if(isReturning)
						{
							if(mTRIndex > 0)
							{
								while(mCurrentTR.actRecord is mARIndex)
								{
									TryRecord tr = *mCurrentTR;
									popTR();

									if(!tr.isCatch)
									{
										mCurrentAR.pc = tr.pc;
										goto _exceptionRetry;
									}
								}
							}
	
							close(0);
							callEpilogue(true);
							--depth;
	
							if(depth == 0)
								return;
	
							isReturning = false;
							constTable = mCurrentAR.func.script.func.mConstants;
							stackBase = mCurrentAR.base;
						}
						break;
	
					case Op.Throw:
						debug(TIMINGS) scope _profiler_ = new Profiler("Throw");

						throwRuntimeException(get(i.rs));
						break;

					// Function Calling
					case Op.Method:
						debug(TIMINGS) scope _profiler_ = new Profiler("Method");

						Instruction call = *mCurrentAR.pc;
						mCurrentAR.pc++;
						assert(i.rd == call.rd, "Op.Method");

						MDString methodName = constTable[i.rt].mString;

						RS = *get(i.rs);
						mStack[stackBase + i.rd + 1] = RS;
						mStack[stackBase + i.rd] = lookupMethod(&RS, methodName);

						if(call.opcode == Op.Call)
						{
							int funcReg = call.rd;
							int numParams = call.rs - 1;
							int numResults = call.rt - 1;
	
							if(numParams == -1)
								numParams = mStackIndex - stackBase - funcReg - 1;
							else
								mStackIndex = funcReg + numParams + 1;
	
							if(callPrologue(funcReg, numResults, numParams) == true)
							{
								depth++;
								constTable = mCurrentAR.func.script.func.mConstants;
								stackBase = mCurrentAR.base;
							}
							else
							{
								if(numResults >= 0)
									mStackIndex = mCurrentAR.savedTop;
							}
						}
						else
						{
							assert(call.opcode == Op.Tailcall, "Op.Method invalid call opcode");
							close(0);

							int funcReg = call.rd;
							int numParams = call.rs - 1;
	
							if(numParams == -1)
								numParams = mStackIndex - stackBase - funcReg - 1;
							else
								mStackIndex = funcReg + numParams + 1;

							funcReg += stackBase;
	
							int destReg = mCurrentAR.funcSlot;
	
							for(int j = 0; j < numParams + 1; j++)
								mStack[destReg + j] = mStack[funcReg + j];

							int numReturns = mCurrentAR.numReturns;
	
							popAR();

							{
								scope(failure)
									--depth;

								if(callPrologue(destReg - mCurrentAR.base, numReturns, numParams) == false)
									--depth;
							}
	
							if(depth == 0)
								return;

							constTable = mCurrentAR.func.script.func.mConstants;
							stackBase = mCurrentAR.base;
						}
						
						break;

					case Op.Precall:
						debug(TIMINGS) scope _profiler_ = new Profiler("Precall");

						if(i.rt == 1)
							RS = *get(i.rs, &mStack[stackBase + i.rd + 1]);
						else
							RS = *get(i.rs);

						if(i.rd != i.rs)
							mStack[stackBase + i.rd] = RS;

						Instruction call = *mCurrentAR.pc;
						mCurrentAR.pc++;

						if(call.opcode == Op.Call)
						{
							int funcReg = call.rd;
							int numParams = call.rs - 1;
							int numResults = call.rt - 1;

							if(numParams == -1)
								numParams = mStackIndex - stackBase - funcReg - 1;
							else
								mStackIndex = funcReg + numParams + 1;

							if(callPrologue(funcReg, numResults, numParams) == true)
							{
								depth++;
								constTable = mCurrentAR.func.script.func.mConstants;
								stackBase = mCurrentAR.base;
							}
							else
							{
								if(numResults >= 0)
									mStackIndex = mCurrentAR.savedTop;
							}
						}
						else
						{
							assert(call.opcode == Op.Tailcall, "Op.Precall invalid call opcode");
							close(0);

							int funcReg = call.rd;
							int numParams = call.rs - 1;
	
							if(numParams == -1)
								numParams = mStackIndex - stackBase - funcReg - 1;
							else
								mStackIndex = funcReg + numParams + 1;
	
							funcReg += stackBase;
	
							int destReg = mCurrentAR.funcSlot;
	
							for(int j = 0; j < numParams + 1; j++)
								mStack[destReg + j] = mStack[funcReg + j];

							int numReturns = mCurrentAR.numReturns;

							popAR();

							{
								scope(failure)
									--depth;

								if(callPrologue(destReg - mCurrentAR.base, numReturns, numParams) == false)
									--depth;
							}

							if(depth == 0)
								return;

							constTable = mCurrentAR.func.script.func.mConstants;
							stackBase = mCurrentAR.base;
						}
						
						break;

					case Op.Ret:
						debug(TIMINGS) scope _profiler_ = new Profiler("Ret");

						int numResults = i.imm - 1;
						int firstResult = stackBase + i.rd;

						if(numResults == -1)
						{
							saveResults(mStack[firstResult .. mStackIndex]);
							mStackIndex = mCurrentAR.savedTop;
						}
						else
							saveResults(mStack[firstResult .. firstResult + numResults]);

						isReturning = true;

						if(mTRIndex > 0)
						{
							while(mCurrentTR.actRecord is mARIndex)
							{
								TryRecord tr = *mCurrentTR;
								popTR();
	
								if(!tr.isCatch)
								{
									mCurrentAR.pc = tr.pc;
									goto _exceptionRetry;
								}
							}
						}

						close(0);
						callEpilogue(true);
						--depth;

						if(depth == 0)
							return;

						isReturning = false;
						constTable = mCurrentAR.func.script.func.mConstants;
						stackBase = mCurrentAR.base;
						break;

					case Op.Vararg:
						debug(TIMINGS) scope _profiler_ = new Profiler("Vararg");

						int numNeeded = i.imm - 1;
						int numVarargs = stackBase - mCurrentAR.vargBase;
						uint dest = stackBase + i.rd;
	
						if(numNeeded == -1)
						{
							numNeeded = numVarargs;
							mStackIndex = dest + numVarargs;
							checkStack(mStackIndex);
						}

						uint src = mCurrentAR.vargBase;

						for(uint index = 0; index < numNeeded; index++)
						{
							if(index < numVarargs)
								mStack[dest] = mStack[src];
							else
								mStack[dest].setNull();

							src++;
							dest++;
						}

						debug(STACKINDEX) Stdout.formatln("Op.Vararg set stack index to {}", mStackIndex);
						break;

					case Op.Yield:
						if(mNativeCallDepth > 0)
							throwRuntimeException("Attempting to yield across native / metamethod call boundary");

						uint firstValue = stackBase + i.rd;

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

						uint sliceBegin = stackBase + i.rd + 1;
						int numElems = i.rs - 1;

						if(numElems == -1)
						{
							mStack[stackBase + i.rd].mArray.setBlock(i.rt, mStack[sliceBegin .. mStackIndex]);
							mStackIndex = mCurrentAR.savedTop;
							
							debug(STACKINDEX) Stdout.formatln("SetArray set mStackIndex to {}", mStackIndex);
						}
						else
							mStack[stackBase + i.rd].mArray.setBlock(i.rt, mStack[sliceBegin .. sliceBegin + numElems]);

						break;

					case Op.Cat:
						int numElems = i.rt - 1;
						MDValue[] vals;

						if(numElems == -1)
						{
							vals = mStack[stackBase + i.rs .. mStackIndex];
							mStackIndex = mCurrentAR.savedTop;
							debug(STACKINDEX) Stdout.formatln("Op.Cat set mStackIndex to {}", mStackIndex);
						}
						else
							vals = mStack[stackBase + i.rs .. stackBase + i.rs + numElems];
							
						*get(i.rd) = operatorCat(vals);
						break;

					case Op.CatEq:
						int numElems = i.rt - 1;
						MDValue[] vals;
						
						if(numElems == -1)
						{
							vals = mStack[stackBase + i.rs .. mStackIndex];
							mStackIndex = mCurrentAR.savedTop;
						}
						else
							vals = mStack[stackBase + i.rs .. stackBase + i.rs + numElems];
							
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
						*get(i.rd) = operatorSlice(&mStack[stackBase + i.rs], &mStack[stackBase + i.rs + 1], &mStack[stackBase + i.rs + 2]);
						break;

					case Op.SliceAssign:
						debug(TIMINGS) scope _profiler_ = new Profiler("SliceAssign");
						operatorSliceAssign(&mStack[stackBase + i.rd], &mStack[stackBase + i.rd + 1], &mStack[stackBase + i.rd + 2], get(i.rs));
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
						mStack[stackBase + i.rd] = new MDArray(i.imm);
						break;

					case Op.NewTable:
						debug(TIMINGS) scope _profiler_ = new Profiler("NewTable");
						mStack[stackBase + i.rd] = new MDTable();
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

						if(RT.mType == MDValue.Type.Null)
							*get(i.rd) = new MDClass(RS.as!(dchar[]), null);
						else if(RT.mType != MDValue.Type.Class)
							throwRuntimeException("Attempted to derive a class from a value of type '{}'", RT.typeString());
						else
							*get(i.rd) = new MDClass(RS.as!(dchar[]), RT.mClass);

						break;
						
					case Op.Coroutine:
						debug(TIMINGS) scope _profiler_ = new Profiler("Coroutine");
						
						RS = *get(i.rs);

						if(RS.mType != MDValue.Type.Function)
							throwRuntimeException("Coroutines must be created with a script function, not '{}'", RS.typeString());

						*get(i.rd) = new MDState(mContext, RS.mFunction);
						break;
						
					case Op.Namespace:
						debug(TIMINGS) scope _profiler_ = new Profiler("Namespace");

						RS = *get(i.rs);
						RT = *get(i.rt);

						if(RT.mType == MDValue.Type.Null)
							*get(i.rd) = new MDNamespace(RS.as!(dchar[]), null);
						else if(RT.mType != MDValue.Type.Namespace)
							throwRuntimeException("Attempted to use a '{}' as a parent namespace for namespace '{}'", RT.typeString(), RS.toString());
						else
							*get(i.rd) = new MDNamespace(RS.as!(dchar[]), RT.mNamespace);

						break;
						
					// Class stuff
					case Op.As:
						debug(TIMINGS) scope _profiler_ = new Profiler("As");

						RS = *get(i.rs);
						RT = *get(i.rt);

						if(RS.mType != MDValue.Type.Instance || RT.mType != MDValue.Type.Class)
							throwRuntimeException("Attempted to perform 'as' on '{}' and '{}'; must be 'instance' and 'class'",
								RS.typeString(), RT.typeString());

						if(RS.mInstance.castToClass(RT.mClass))
							*get(i.rd) = RS;
						else
							get(i.rd).setNull();

						break;
						
					case Op.Super:
						debug(TIMINGS) scope _profiler_ = new Profiler("Super");

						RS = *get(i.rs);

						if(RS.mType == MDValue.Type.Instance)
							*get(i.rd) = RS.mInstance.getClass().superClass();
						else if(RS.mType == MDValue.Type.Class)
							*get(i.rd) = RS.mClass.superClass();
						else
							throwRuntimeException("Can only get superclass of classes and instances, not '{}'", RS.typeString());

						break;

					case Op.ClassOf:
						debug(TIMINGS) scope _profiler_ = new Profiler("ClassOf");

						RS = *get(i.rs);

						if(RS.mType == MDValue.Type.Instance)
							*get(i.rd) = RS.mInstance.getClass();
						else
							throwRuntimeException("Can only get class of instances, not '{}'", RS.typeString());

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
						throwRuntimeException("Unimplemented opcode \"{}\"", i.toString());
				}
			}
		}
		catch(MDException e)
		{
			while(depth > 0)
			{
				mContext.mTraceback ~= getDebugLocation();

				while(mCurrentTR.actRecord is mARIndex)
				{
					TryRecord tr = *mCurrentTR;
					popTR();

					if(tr.isCatch)
					{
						mStack[stackBase + tr.catchVarSlot] = e.value;

						for(int i = stackBase + tr.catchVarSlot + 1; i < mStackIndex; i++)
							mStack[i].setNull();

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

				callEpilogue(false);

				if(depth > 0)
				{
					constTable = mCurrentAR.func.script.func.mConstants;
					stackBase = mCurrentAR.base;
				}
			}

			throw e;
		}
	}
}
