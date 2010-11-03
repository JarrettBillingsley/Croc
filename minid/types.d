/******************************************************************************
This module contains a lot of type definitions for types used throughout the
library.  Not much in here is public.

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

module minid.types;

version(MDExtendedCoro)
	import tango.core.Thread;

import tango.text.convert.Layout;

import minid.alloc;
import minid.hash;
import minid.opcodes;
import minid.utils;

import tango.text.convert.Format;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

/**
The native signed integer type on this platform.  This is the same as ptrdiff_t but with a better name.
*/
public alias ptrdiff_t word;

/**
The native unsigned integer type on this platform.  This is the same as size_t but with a better name.
*/
public alias size_t uword;

/**
The underlying D type used to store the MiniD 'int' type.  Defaults to 'long' (64-bit signed integer).  If you
change it, you will end up with a (probably?) functional but nonstandard implementation.
*/
public alias long mdint;

static assert((cast(mdint)-1) < (cast(mdint)0), "mdint must be signed");

/**
The underlying D type used to store the MiniD 'float' type.  Defaults to 'double'.  If you change it, you will end
up with a functional but nonstandard implementation.
*/
public alias double mdfloat;

/**
The current version of MiniD as a 32-bit integer.  The upper 16 bits are the major, and the lower 16 are
the minor.
*/
public const uint MiniDVersion = MakeVersion!(2, 1);

/**
An alias for the type signature of a native function.  It is defined as uword function(MDThread*, uword).
*/
public alias uword function(MDThread*) NativeFunc;

/**
The MiniD exception type.  This is the type that is thrown whenever you throw an exception from within
MiniD, or when you use the throwException API call.  You can't directly instantiate this class, though,
since it would be bad if you did (the interpreter needs to keep track of some internal state, which
throwException does).  See throwException and catchException in minid.interpreter for more info
on MiniD exception handling.
*/
class MDException : Exception
{
	package this(char[] msg)
	{
		super(msg);
	}
}

/**
This is a semi-internal exception type.  Normally you won't need to know about it or catch it.  This is
thrown when a coroutine (thread) needs to be halted.  It should never propagate out of the coroutine.
The only time you might encounter it is if, in the middle of a native MiniD function, one of these
is thrown, you might be able to catch it and clean up some resources, but you must rethrow it in that
case, unless you want the interpreter to be in a horrible state.

Like the other exception types, you can't instantiate this directly, but you can halt threads with the
"haltThread" function in minid.interpreter.
*/
final class MDHaltException : Exception
{
	package this()
	{
		super("MiniD interpreter halted");
	}
}

/**
A string constant indicating the level of coroutine support compiled in.  Is either "Normal" or "Extended".
*/
version(MDExtendedCoro)
	const char[] MDCoroSupport = "Extended";
else
	const char[] MDCoroSupport = "Normal";

// ================================================================================================================================================
// Package
// ================================================================================================================================================

/**
*/
align(1) struct MDValue
{
	/**
	The enumeration of all the types of values in MiniD.
	*/
	enum Type : uint
	{
		/** */
		Null, // 0
		/** ditto */
		Bool,
		/** ditto */
		Int,
		/** ditto */
		Float,
		/** ditto */
		Char,

		/** ditto */
		String, // 5
		/** ditto */
		Table,
		/** ditto */
		Array,
		/** ditto */
		Function,
		/** ditto */
		Class,
		/** ditto */
		Instance, // 10
		/** ditto */
		Namespace,
		/** ditto */
		Thread,
		/** ditto */
		NativeObj,
		/** ditto */
		WeakRef,

		// Internal types
		Upvalue, // 15
		FuncDef,
		ArrayData
	}

	package static char[] typeString(MDValue.Type t)
	{
		switch(t)
		{
			case Type.Null:      return "null";
			case Type.Bool:      return "bool";
			case Type.Int:       return "int";
			case Type.Float:     return "float";
			case Type.Char:      return "char";

			case Type.String:    return "string";
			case Type.Table:     return "table";
			case Type.Array:     return "array";
			case Type.Function:  return "function";
			case Type.Class:     return "class";
			case Type.Instance:  return "instance";
			case Type.Namespace: return "namespace";
			case Type.Thread:    return "thread";
			case Type.NativeObj: return "nativeobj";
			case Type.WeakRef:   return "weakref";

			case Type.Upvalue:   return "upvalue";
			case Type.FuncDef:   return "funcdef";
			case Type.ArrayData: return "arraydata";

			default: assert(false);
		}
	}

	package static MDValue nullValue = { type : Type.Null, mInt : 0 };

	package Type type = Type.Null;

	union
	{
		package bool mBool;
		package mdint mInt;
		package mdfloat mFloat;
		package dchar mChar;

 		package MDBaseObject* mBaseObj;
		package MDString* mString;
		package MDTable* mTable;
		package MDArray* mArray;
		package MDFunction* mFunction;
		package MDClass* mClass;
		package MDInstance* mInstance;
		package MDNamespace* mNamespace;
		package MDThread* mThread;
		package MDNativeObj* mNativeObj;
		package MDWeakRef* mWeakRef;
	}

	package static MDValue opCall(T)(T t)
	{
		MDValue ret = void;
		ret = t;
		return ret;
	}

	package int opEquals(MDValue other)
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
	
	package void opAssign(mdint src)
	{
		type = Type.Int;
		mInt = src;
	}
	
	package void opAssign(mdfloat src)
	{
		type = Type.Float;
		mFloat = src;
	}
	
	package void opAssign(dchar src)
	{
		type = Type.Char;
		mChar = src;
	}
	
	package void opAssign(MDString* src)
	{
		type = Type.String;
		mString = src;
	}
	
	package void opAssign(MDTable* src)
	{
		type = Type.Table;
		mTable = src;
	}
	
	package void opAssign(MDArray* src)
	{
		type = Type.Array;
		mArray = src;
	}

	package void opAssign(MDFunction* src)
	{
		type = Type.Function;
		mFunction = src;
	}
	
	package void opAssign(MDClass* src)
	{
		type = Type.Class;
		mClass = src;
	}
	
	package void opAssign(MDInstance* src)
	{
		type = Type.Instance;
		mInstance = src;
	}

	package void opAssign(MDNamespace* src)
	{
		type = Type.Namespace;
		mNamespace = src;
	}

	package void opAssign(MDThread* src)
	{
		type = Type.Thread;
		mThread = src;
	}
	
	package void opAssign(MDNativeObj* src)
	{
		type = Type.NativeObj;
		mNativeObj = src;
	}
	
	package void opAssign(MDWeakRef* src)
	{
		type = Type.WeakRef;
		mWeakRef = src;
	}

	package void opAssign(MDBaseObject* src)
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
			case Type.Function:  return Format("function {:X8}", cast(void*)mFunction);
			case Type.Class:     return Format("class {:X8}", cast(void*)mClass);
			case Type.Instance:  return Format("instance {:X8}", cast(void*)mInstance);
			case Type.Namespace: return Format("namespace {:X8}", cast(void*)mNamespace);
			case Type.Thread:    return Format("thread {:X8}", cast(void*)mThread);
			case Type.NativeObj: return Format("nativeobj {:X8}", cast(void*)mNativeObj);
			case Type.WeakRef:   return Format("weakref {:X8}", cast(void*)mWeakRef);
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

template MDObjectMixin(uint type)
{
	mixin GCMixin;
	package MDValue.Type mType = cast(MDValue.Type)type;
}

struct MDBaseObject
{
	mixin MDObjectMixin!(MDValue.Type.Null);
}

struct MDString
{
	mixin MDObjectMixin!(MDValue.Type.String);
	package uword hash;
	package uword length;
	package uword cpLength;

	package char[] toString()
	{
		return (cast(char*)(this + 1))[0 .. this.length];
	}
	
	package alias hash toHash;
}

struct MDTable
{
	mixin MDObjectMixin!(MDValue.Type.Table);
	package Hash!(MDValue, MDValue) data;
	package MDTable* nextTab; // used during collection
}

struct MDArrayData
{
	mixin MDObjectMixin!(MDValue.Type.ArrayData);
	package uword length;

	package MDValue[] toArray()
	{
		return (cast(MDValue*)(this + 1))[0 .. length];
	}
}

struct MDArray
{
	mixin MDObjectMixin!(MDValue.Type.Array);
	package MDArrayData* data;
	package MDValue[] slice;
	package bool isSlice;
}

struct MDFunction
{
	mixin MDObjectMixin!(MDValue.Type.Function);
	package bool isNative;
	package MDNamespace* environment;
	package MDString* name;
	package uword numUpvals;
	package uword numParams;

	union
	{
		package MDFuncDef* scriptFunc;
		package NativeFunc nativeFunc;
	}

	package MDValue[] nativeUpvals()
	{
		return (cast(MDValue*)(this + 1))[0 .. numUpvals];
	}

	package MDUpval*[] scriptUpvals()
	{
		return (cast(MDUpval**)(this + 1))[0 .. numUpvals];
	}

	static assert((MDFuncDef*).sizeof == NativeFunc.sizeof);
}

struct MDClass
{
	mixin MDObjectMixin!(MDValue.Type.Class);
	package MDString* name;
	package MDClass* parent;
	package MDNamespace* fields;
	package MDFunction* allocator;
	package MDFunction* finalizer;
}

struct MDInstance
{
	mixin MDObjectMixin!(MDValue.Type.Instance);
	package MDClass* parent;
	package MDNamespace* fields;
	package MDFunction* finalizer;
	package uword numValues;
	package uword extraBytes;

	package MDValue[] extraValues()
	{
		return (cast(MDValue*)(this + 1))[0 .. numValues];
	}
	
	package void[] extraData()
	{
		return ((cast(void*)(this + 1)) + (numValues * MDValue.sizeof))[0 .. extraBytes];
	}
}

struct MDNamespace
{
	mixin MDObjectMixin!(MDValue.Type.Namespace);
	package Hash!(MDString*, MDValue) data;
	package MDNamespace* parent;
	package MDString* name;
}

package alias uword AbsStack;
package alias uword RelStack;

struct ActRecord
{
	package AbsStack base;
	package AbsStack savedTop;
	package AbsStack vargBase;
	package AbsStack returnSlot;
	package MDFunction* func;
	package Instruction* pc;
	package word numReturns;
	package MDClass* proto;
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

struct MDThread
{
	mixin MDObjectMixin!(MDValue.Type.Thread);

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

	package MDValue[] stack;
	package AbsStack stackIndex;
	package AbsStack stackBase;

	package MDValue[] results;
	package uword resultIndex = 0;

	package MDUpval* upvalHead;

	package MDVM* vm;
	package bool shouldHalt = false;

	package MDFunction* coroFunc;
	package State state = State.Initial;
	package uword numYields;

	package ubyte hooks;
	package bool hooksEnabled = true;
	package uint hookDelay;
	package uint hookCounter;
	package MDFunction* hookFunc;

	version(MDExtendedCoro)
	{
		// References a Fiber object
		package MDNativeObj* coroFiber;

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

struct MDNativeObj
{
	mixin MDObjectMixin!(MDValue.Type.NativeObj);
	package Object obj;
}

struct MDWeakRef
{
	mixin MDObjectMixin!(MDValue.Type.WeakRef);
	package MDBaseObject* obj;
}

struct Location
{
	enum Type
	{
		Unknown = -2,
		Native = -1,
		Script = 0
	}

	public MDString* file;
	// yes, these are 32 bits
	package int line = 1;
	package int col = 1;

	public static Location opCall(MDString* file, int line = 1, int col = 1)
	{
		Location l = void;
		l.file = file;
		l.line = line;
		l.col = col;
		return l;
	}
}

struct MDUpval
{
	mixin MDObjectMixin!(MDValue.Type.Upvalue);

	package MDValue* value;
	package MDValue closedValue;
	package MDUpval* nextuv;
}

// The integral members of this struct are fixed at 32 bits for possible cross-platform serialization.
struct MDFuncDef
{
	mixin MDObjectMixin!(MDValue.Type.FuncDef);

	package Location location;
	package bool isVararg;
	package MDString* name;
	package uint numParams;
	package ushort[] paramMasks;
	package uint numUpvals;
	package uint stackSize;
	package MDFuncDef*[] innerFuncs;
	package MDValue[] constants;
	package Instruction[] code;

	package bool isPure;
	package MDFunction* cachedFunc;

	struct SwitchTable
	{
		package Hash!(MDValue, int) offsets;
		package int defaultOffset = -1; // yes, this is 32 bit, it's fixed that size
	}

	package SwitchTable[] switchTables;

	// Debug info.
	package uint[] lineInfo;
	package MDString*[] upvalNames;

	struct LocVarDesc
	{
		package MDString* name;
		package uint pcStart;
		package uint pcEnd;
		package uint reg;
	}

	package LocVarDesc[] locVarDescs;
}

// please don't align(1) this struct, it'll mess up the D GC when it tries to look inside for pointers.
struct MDVM
{
	package Allocator alloc;

	package MDNamespace* globals;
	package MDThread* mainThread;
	package MDNamespace*[] metaTabs;
	package Hash!(char[], MDString*) stringTab;
	package MDString*[] metaStrings;
	package MDString* ctorString;
	package Location[] traceback;
	package MDValue exception;
	package bool isThrowing;
	package MDThread* curThread;
	package Hash!(MDBaseObject*, MDWeakRef*) weakRefTab;
	package MDNamespace* registry;
	package Hash!(ulong, MDBaseObject*) refTab;
	package ulong currentRef;
	package MDTable* toBeNormalized; // linked list of tables to be normalized

	// The following members point into the D heap.
	package MDNativeObj*[Object] nativeObjs;
	package Layout!(char) formatter;
	package char[] exMsg;

	version(MDExtendedCoro)
		version(MDPoolFibers)
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