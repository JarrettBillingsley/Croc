/******************************************************************************
This module contains a lot of type definitions for types used throughout the
library. Not much in here is public.

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

module croc.types;

version(CrocExtendedCoro)
	import tango.core.Thread;

import tango.text.convert.Format;
import tango.text.convert.Layout;

import croc.base_alloc;
import croc.base_hash;
import croc.base_opcodes;
import croc.utils;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

/**
The native signed integer type on this platform. This is the same as ptrdiff_t but with a better name.
*/
public alias ptrdiff_t word;

/**
The native unsigned integer type on this platform. This is the same as size_t but with a better name.
*/
public alias size_t uword;

/**
The underlying D type used to store the Croc 'int' type. Defaults to 'long' (64-bit signed integer). If you
change it, you will end up with a (probably?) functional but nonstandard implementation.
*/
public alias long crocint;

static assert((cast(crocint)-1) < (cast(crocint)0), "crocint must be signed");

/**
The underlying D type used to store the Croc 'float' type. Defaults to 'double'. If you change it, you will end
up with a functional but nonstandard implementation.
*/
public alias double crocfloat;

/**
The current version of Croc as a 32-bit integer. The upper 16 bits are the major, and the lower 16 are
the minor.
*/
public const uint CrocVersion = MakeVersion!(2, 1);

/**
An alias for the type signature of a native function. It is defined as uword function(CrocThread*, uword).
*/
public alias uword function(CrocThread*) NativeFunc;

/**
*/
class CrocThrowable : Exception
{
	package this(char[] msg)
	{
		super(msg);
	}
}

/**
The Croc exception type. This is the type that is thrown whenever you throw an exception from within
Croc, or when you use the throwException API call. You can't directly instantiate this class, though,
since it would be bad if you did (the interpreter needs to keep track of some internal state, which
throwException does). See throwException and catchException in croc.interpreter for more info
on Croc exception handling.
*/
final class CrocException : CrocThrowable
{
	package this(char[] msg)
	{
		super(msg);
	}
}

/**
*/
final class CrocError : CrocThrowable
{
	package this(char[] msg)
	{
		super(msg);
	}
}

/**
This is a semi-internal exception type. Normally you won't need to know about it or catch it. This is
thrown when a coroutine (thread) needs to be halted. It should never propagate out of the coroutine.
The only time you might encounter it is if, in the middle of a native Croc function, one of these
is thrown, you might be able to catch it and clean up some resources, but you must rethrow it in that
case, unless you want the interpreter to be in a horrible state.

Like the other exception types, you can't instantiate this directly, but you can halt threads with the
"haltThread" function in croc.interpreter.
*/
final class CrocHaltException : CrocThrowable
{
	package this()
	{
		super("Croc interpreter halted");
	}
}

/**
A string constant indicating the level of coroutine support compiled in. Is either "Normal" or "Extended".
*/
version(CrocExtendedCoro)
	const char[] CrocCoroSupport = "Extended";
else
	const char[] CrocCoroSupport = "Normal";

// ================================================================================================================================================
// Package
// ================================================================================================================================================

/**
*/
align(1) struct CrocValue
{
	// If this changes, grep ORDER CROCVALUE TYPE

	/**
	The enumeration of all the types of values in Croc.
	*/
	enum Type : uint
	{
		/** */
		Null,       // 0
		/** ditto */
		Bool,
		/** ditto */
		Int,
		/** ditto */
		Float,
		/** ditto */
		Char,

		/** ditto */
		String,     // 5
		/** ditto */
		Table,
		/** ditto */
		Array,
		/** ditto */
		Memblock,
		/** ditto */
		Function,
		/** ditto */
		Class,      // 10
		/** ditto */
		Instance,
		/** ditto */
		Namespace,
		/** ditto */
		Thread,
		/** ditto */
		NativeObj,
		/** ditto */
		WeakRef,    // 15
		/** ditto */
		FuncDef,

		// Internal types
		Upvalue
	}

	package static const char[][] typeStrings =
	[
		Type.Null:      "null",
		Type.Bool:      "bool",
		Type.Int:       "int",
		Type.Float:     "float",
		Type.Char:      "char",

		Type.String:    "string",
		Type.Table:     "table",
		Type.Array:     "array",
		Type.Memblock:  "memblock",
		Type.Function:  "function",
		Type.Class:     "class",
		Type.Instance:  "instance",
		Type.Namespace: "namespace",
		Type.Thread:    "thread",
		Type.NativeObj: "nativeobj",
		Type.WeakRef:   "weakref",
		Type.FuncDef:   "funcdef",

		Type.Upvalue:   "upvalue"
	];

	package static CrocValue nullValue = { type : Type.Null, mInt : 0 };

	package Type type = Type.Null;

	union
	{
		package bool mBool;
		package crocint mInt;
		package crocfloat mFloat;
		package dchar mChar;

 		package CrocBaseObject* mBaseObj;
		package CrocString* mString;
		package CrocTable* mTable;
		package CrocArray* mArray;
		package CrocMemblock* mMemblock;
		package CrocFunction* mFunction;
		package CrocClass* mClass;
		package CrocInstance* mInstance;
		package CrocNamespace* mNamespace;
		package CrocThread* mThread;
		package CrocNativeObj* mNativeObj;
		package CrocWeakRef* mWeakRef;
		package CrocFuncDef* mFuncDef;
	}

	package static CrocValue opCall(T)(T t)
	{
		CrocValue ret = void;
		ret = t;
		return ret;
	}

	package int opEquals(CrocValue other)
	{
		if(this.type != other.type)
			return false;

		switch(this.type)
		{
			case Type.Null: return true;
			case Type.Bool: return this.mBool == other.mBool;
			case Type.Int: return this.mInt == other.mInt;
			case Type.Float: return this.mFloat == other.mFloat;
			case Type.Char: return this.mChar == other.mChar;
			default: return (this.mBaseObj is other.mBaseObj);
		}
	}

	package bool isFalse()
	{
		return (type == Type.Null) || (type == Type.Bool && mBool == false) ||
			(type == Type.Int && mInt == 0) || (type == Type.Float && mFloat == 0.0) || (type == Type.Char && mChar != 0);
	}

	package void opAssign(bool src)
	{
		type = Type.Bool;
		mBool = src;
	}

	package void opAssign(crocint src)
	{
		type = Type.Int;
		mInt = src;
	}

	package void opAssign(crocfloat src)
	{
		type = Type.Float;
		mFloat = src;
	}

	package void opAssign(dchar src)
	{
		type = Type.Char;
		mChar = src;
	}

	package void opAssign(CrocString* src)
	{
		type = Type.String;
		mString = src;
	}

	package void opAssign(CrocTable* src)
	{
		type = Type.Table;
		mTable = src;
	}

	package void opAssign(CrocArray* src)
	{
		type = Type.Array;
		mArray = src;
	}
	
	package void opAssign(CrocMemblock* src)
	{
		type = Type.Memblock;
		mMemblock = src;
	}

	package void opAssign(CrocFunction* src)
	{
		type = Type.Function;
		mFunction = src;
	}

	package void opAssign(CrocClass* src)
	{
		type = Type.Class;
		mClass = src;
	}

	package void opAssign(CrocInstance* src)
	{
		type = Type.Instance;
		mInstance = src;
	}

	package void opAssign(CrocNamespace* src)
	{
		type = Type.Namespace;
		mNamespace = src;
	}

	package void opAssign(CrocThread* src)
	{
		type = Type.Thread;
		mThread = src;
	}

	package void opAssign(CrocNativeObj* src)
	{
		type = Type.NativeObj;
		mNativeObj = src;
	}

	package void opAssign(CrocWeakRef* src)
	{
		type = Type.WeakRef;
		mWeakRef = src;
	}

	package void opAssign(CrocFuncDef* src)
	{
		type = Type.FuncDef;
		mFuncDef = src;
	}

	package void opAssign(CrocBaseObject* src)
	{
		type = src.mType;
		mBaseObj = src;
	}

	package bool isObject()
	{
		return type >= Type.String;
	}

	package GCObject* toGCObject()
	{
		assert(isObject());
		return cast(GCObject*)mBaseObj;
	}

	// This isn't really used anywhere except in debugging messages, I think.
	char[] toString()
	{
		switch(type)
		{
			case Type.Null:      return "null";
			case Type.Bool:      return Format("{}", mBool);
			case Type.Int:       return Format("{}", mInt);
			case Type.Float:     return Format("{}", mFloat);
			case Type.Char:      return Format("'{}'", mChar);

			case Type.String:    return Format("\"{}\"", mString.toString());
			case Type.Table:     return Format("table {:X8}", cast(void*)mTable);
			case Type.Array:     return Format("array {:X8}", cast(void*)mArray);
			case Type.Memblock:  return Format("memblock {:X8}", cast(void*)mMemblock);
			case Type.Function:  return Format("function {:X8}", cast(void*)mFunction);
			case Type.Class:     return Format("class {:X8}", cast(void*)mClass);
			case Type.Instance:  return Format("instance {:X8}", cast(void*)mInstance);
			case Type.Namespace: return Format("namespace {:X8}", cast(void*)mNamespace);
			case Type.Thread:    return Format("thread {:X8}", cast(void*)mThread);
			case Type.NativeObj: return Format("nativeobj {:X8}", cast(void*)mNativeObj);
			case Type.WeakRef:   return Format("weakref {:X8}", cast(void*)mWeakRef);
			case Type.FuncDef:   return Format("funcdef {:X8}", cast(void*)mFuncDef);

			default: assert(false);
		}
	}

	hash_t toHash()
	{
		switch(type)
		{
			case Type.Null:   return 0;
			case Type.Bool:   return typeid(typeof(mBool)).getHash(&mBool);
			case Type.Int:    return typeid(typeof(mInt)).getHash(&mInt);
			case Type.Float:  return typeid(typeof(mFloat)).getHash(&mFloat);
			case Type.Char:   return typeid(typeof(mChar)).getHash(&mChar);
			case Type.String: return mString.hash;
			default:          return cast(hash_t)cast(void*)mBaseObj;
		}
	}
}

template CrocObjectMixin(uint type)
{
	mixin GCMixin;
	package CrocValue.Type mType = cast(CrocValue.Type)type;
}

struct CrocBaseObject
{
	mixin CrocObjectMixin!(CrocValue.Type.Null);
}

struct CrocString
{
	mixin CrocObjectMixin!(CrocValue.Type.String);
	package uword hash;
	package uword length;
	package uword cpLength;

	package char[] toString()
	{
		return (cast(char*)(this + 1))[0 .. this.length];
	}

	package alias hash toHash;
}

struct CrocTable
{
	mixin CrocObjectMixin!(CrocValue.Type.Table);
	package Hash!(CrocValue, CrocValue) data;
	package CrocTable* nextTab; // used during collection
}

struct CrocArray
{
	mixin CrocObjectMixin!(CrocValue.Type.Array);
	package uword length;
	package CrocValue[] data;

	package CrocValue[] toArray()
	{
		return data[0 .. this.length];
	}
}

struct CrocMemblock
{
	mixin CrocObjectMixin!(CrocValue.Type.Memblock);

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
		TypeCode.v:   { TypeCode.v,   1, "v"   },
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

	package void[] data;
	package uword itemLength;
	package TypeStruct* kind;
	package bool ownData;
}

struct CrocFunction
{
	mixin CrocObjectMixin!(CrocValue.Type.Function);
	package bool isNative;
	package CrocNamespace* environment;
	package CrocString* name;
	package uword numUpvals;
	package uword numParams;
	package uword maxParams;

	union
	{
		package CrocFuncDef* scriptFunc;
		package NativeFunc nativeFunc;
	}

	package CrocValue[] nativeUpvals()
	{
		return (cast(CrocValue*)(this + 1))[0 .. numUpvals];
	}

	package CrocUpval*[] scriptUpvals()
	{
		return (cast(CrocUpval**)(this + 1))[0 .. numUpvals];
	}

	static assert((CrocFuncDef*).sizeof == NativeFunc.sizeof);
}

struct CrocClass
{
	mixin CrocObjectMixin!(CrocValue.Type.Class);
	package CrocString* name;
	package CrocClass* parent;
	package CrocNamespace* fields;
	package CrocFunction* allocator;
	package CrocFunction* finalizer;
	package bool hasInstances;
}

struct CrocInstance
{
	mixin CrocObjectMixin!(CrocValue.Type.Instance);
	package CrocClass* parent;
	package CrocNamespace* fields;
	package uword numValues;
	package uword extraBytes;

	package CrocValue[] extraValues()
	{
		return (cast(CrocValue*)(this + 1))[0 .. numValues];
	}
	
	package void[] extraData()
	{
		return ((cast(void*)(this + 1)) + (numValues * CrocValue.sizeof))[0 .. extraBytes];
	}
}

struct CrocNamespace
{
	mixin CrocObjectMixin!(CrocValue.Type.Namespace);
	package Hash!(CrocString*, CrocValue) data;
	package CrocNamespace* parent;
	package CrocString* name;
}

package alias uword AbsStack;
package alias uword RelStack;

struct ActRecord
{
	package AbsStack base;
	package AbsStack savedTop;
	package AbsStack vargBase;
	package AbsStack returnSlot;
	package CrocFunction* func;
	package Instruction* pc;
	package word numReturns;
	package CrocClass* proto;
	package uword numTailcalls;
	package uword firstResult;
	package uword numResults;
	package uword unwindCounter = 0;
	package Instruction* unwindReturn = null;
}

struct TryRecord
{
	package bool isCatch;
	package RelStack slot;
	package uword actRecord;
	package Instruction* pc;
}

struct CrocThread
{
	mixin CrocObjectMixin!(CrocValue.Type.Thread);

	public enum State
	{
		Initial,
		Waiting,
		Running,
		Suspended,
		Dead
	}

	public enum Hook : ubyte
	{
		Call = 1,
		Ret = 2,
		TailRet = 4,
		Delay = 8,
		Line = 16
	}

	static char[][5] StateStrings =
	[
		State.Initial: "initial",
		State.Waiting: "waiting",
		State.Running: "running",
		State.Suspended: "suspended",
		State.Dead: "dead"
	];

	package TryRecord[] tryRecs;
	package TryRecord* currentTR;
	package uword trIndex = 0;

	package ActRecord[] actRecs;
	package ActRecord* currentAR;
	package uword arIndex = 0;

	package CrocValue[] stack;
	package AbsStack stackIndex;
	package AbsStack stackBase;

	package CrocValue[] results;
	package uword resultIndex = 0;

	package CrocUpval* upvalHead;

	package CrocVM* vm;
	package bool shouldHalt = false;

	package CrocFunction* coroFunc;
	package State state = State.Initial;
	package uword numYields;

	package ubyte hooks;
	package bool hooksEnabled = true;
	package uint hookDelay;
	package uint hookCounter;
	package CrocFunction* hookFunc;

	version(CrocExtendedCoro)
	{
		// References a Fiber object
		package CrocNativeObj* coroFiber;

		package Fiber getFiber()
		{
			assert(coroFiber !is null);
			return cast(Fiber)cast(void*)coroFiber.obj;
		}
	}
	else
	{
		package uword savedCallDepth;
	}

	package uword nativeCallDepth = 0;
}

struct CrocNativeObj
{
	mixin CrocObjectMixin!(CrocValue.Type.NativeObj);
	package Object obj;
}

struct CrocWeakRef
{
	mixin CrocObjectMixin!(CrocValue.Type.WeakRef);
	package CrocBaseObject* obj;
}

struct Location
{
	enum Type
	{
		Unknown = -2,
		Native = -1,
		Script = 0
	}

	public CrocString* file;
	// yes, these are 32 bits
	package int line = 1;
	package int col = 1;

	public static Location opCall(CrocString* file, int line = 1, int col = 1)
	{
		Location l = void;
		l.file = file;
		l.line = line;
		l.col = col;
		return l;
	}
}

// The integral members of this struct are fixed at 32 bits for possible cross-platform serialization.
struct CrocFuncDef
{
	mixin CrocObjectMixin!(CrocValue.Type.FuncDef);

	package Location location;
	package bool isVararg;
	package CrocString* name;
	package uint numParams;
	package uint[] paramMasks;
	package uint numUpvals;
	package uint stackSize;
	package CrocFuncDef*[] innerFuncs;
	package CrocValue[] constants;
	package Instruction[] code;

	package CrocNamespace* environment;
	package CrocFunction* cachedFunc;

	struct SwitchTable
	{
		package Hash!(CrocValue, int) offsets;
		package int defaultOffset = -1; // yes, this is 32 bit, it's fixed that size
	}

	package SwitchTable[] switchTables;

	// Debug info.
	package uint[] lineInfo;
	package CrocString*[] upvalNames;

	struct LocVarDesc
	{
		package CrocString* name;
		package uint pcStart;
		package uint pcEnd;
		package uint reg;
	}

	package LocVarDesc[] locVarDescs;
}

struct CrocUpval
{
	mixin CrocObjectMixin!(CrocValue.Type.Upvalue);

	package CrocValue* value;
	package CrocValue closedValue;
	package CrocUpval* nextuv;
}

// please don't align(1) this struct, it'll mess up the D GC when it tries to look inside for pointers.
struct CrocVM
{
	package Allocator alloc;

	// These are all GC roots
	package CrocNamespace* globals;
	package CrocThread* mainThread;
	package CrocNamespace*[] metaTabs;
	package CrocString*[] metaStrings;
	package Location[] traceback;
	package CrocValue exception;
	package CrocNamespace* registry;
	package Hash!(ulong, CrocBaseObject*) refTab;
	package CrocClass* object;
	package CrocClass* throwable;

	// Others
	package Hash!(char[], CrocString*) stringTab;
	package Hash!(CrocBaseObject*, CrocWeakRef*) weakRefTab;
	package CrocTable* toBeNormalized; // linked list of tables to be normalized
	package ulong currentRef;
	package CrocString* ctorString;
	package CrocThread* curThread;
	package bool isThrowing;

	// The following members point into the D heap.
	package CrocNativeObj*[Object] nativeObjs;
	package Layout!(char) formatter;
	package char[] exMsg;

	version(CrocExtendedCoro)
		version(CrocPoolFibers)
			package bool[Fiber] fiberPool;
}

package enum MM
{
	Add,
	Add_r,
	AddEq,
	And,
	And_r,
	AndEq,
	Apply,
	Call,
	Cat,
	Cat_r,
	CatEq,
	Cmp,
	Com,
	Dec,
	Div,
	Div_r,
	DivEq,
	Equals,
	Field,
	FieldAssign,
	In,
	Inc,
	Index,
	IndexAssign,
	Length,
	LengthAssign,
	Method,
	Mod,
	Mod_r,
	ModEq,
	Mul,
	Mul_r,
	MulEq,
	Neg,
	Or,
	Or_r,
	OrEq,
	Shl,
	Shl_r,
	ShlEq,
	Shr,
	Shr_r,
	ShrEq,
	Slice,
	SliceAssign,
	Sub,
	Sub_r,
	SubEq,
	ToString,
	UShr,
	UShr_r,
	UShrEq,
	Xor,
	Xor_r,
	XorEq
}

package const char[][] MetaNames =
[
	MM.Add:          "opAdd",
	MM.Add_r:        "opAdd_r",
	MM.AddEq:        "opAddAssign",
	MM.And:          "opAnd",
	MM.And_r:        "opAnd_r",
	MM.AndEq:        "opAndAssign",
	MM.Apply:        "opApply",
	MM.Call:         "opCall",
	MM.Cat:          "opCat",
	MM.Cat_r:        "opCat_r",
	MM.CatEq:        "opCatAssign",
	MM.Cmp:          "opCmp",
	MM.Com:          "opCom",
	MM.Dec:          "opDec",
	MM.Div:          "opDiv",
	MM.Div_r:        "opDiv_r",
	MM.DivEq:        "opDivAssign",
	MM.Equals:       "opEquals",
	MM.Field:        "opField",
	MM.FieldAssign:  "opFieldAssign",
	MM.In:           "opIn",
	MM.Inc:          "opInc",
	MM.Index:        "opIndex",
	MM.IndexAssign:  "opIndexAssign",
	MM.Length:       "opLength",
	MM.LengthAssign: "opLengthAssign",
	MM.Method:       "opMethod",
	MM.Mod:          "opMod",
	MM.Mod_r:        "opMod_r",
	MM.ModEq:        "opModAssign",
	MM.Mul:          "opMul",
	MM.Mul_r:        "opMul_r",
	MM.MulEq:        "opMulAssign",
	MM.Neg:          "opNeg",
	MM.Or:           "opOr",
	MM.Or_r:         "opOr_r",
	MM.OrEq:         "opOrAssign",
	MM.Shl:          "opShl",
	MM.Shl_r:        "opShl_r",
	MM.ShlEq:        "opShlAssign",
	MM.Shr:          "opShr",
	MM.Shr_r:        "opShr_r",
	MM.ShrEq:        "opShrAssign",
	MM.Slice:        "opSlice",
	MM.SliceAssign:  "opSliceAssign",
	MM.Sub:          "opSub",
	MM.Sub_r:        "opSub_r",
	MM.SubEq:        "opSubAssign",
	MM.ToString:     "toString",
	MM.UShr:         "opUShr",
	MM.UShr_r:       "opUShr_r",
	MM.UShrEq:       "opUShrAssign",
	MM.Xor:          "opXor",
	MM.Xor_r:        "opXor_r",
	MM.XorEq:        "opXorAssign",
];

package const MM[] MMRev =
[
	MM.Add:  MM.Add_r,
	MM.Sub:  MM.Sub_r,
	MM.Mul:  MM.Mul_r,
	MM.Div:  MM.Div_r,
	MM.Mod:  MM.Mod_r,
	MM.Cat:  MM.Cat_r,
	MM.And:  MM.And_r,
	MM.Or:   MM.Or_r,
	MM.Xor:  MM.Xor_r,
	MM.Shl:  MM.Shl_r,
	MM.Shr:  MM.Shr_r,
	MM.UShr: MM.UShr_r,

	MM.max:  cast(MM)-1
];

package const bool[] MMCommutative =
[
	MM.Add: true,
	MM.Mul: true,
	MM.And: true,
	MM.Or:  true,
	MM.Xor: true,

	MM.max: false
];