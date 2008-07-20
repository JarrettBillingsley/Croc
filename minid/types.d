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

module minid.types;

version(MDRestrictedCoro) {} else
	import tango.core.Thread;

import tango.text.convert.Layout;

import minid.alloc;
import minid.hash;
import minid.opcodes;
import minid.utils;

debug import tango.text.convert.Format;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

/**
The native signed integer type on this platform.  This is the same as ptrdiff_t but with a better name.
*/
public alias ptrdiff_t word;

/**
The native unsigned integer type on this platform.  This is the same as uword but with a better name.
*/
public alias size_t uword;

/**
The underlying D type used to store the MiniD 'int' type. Defaults to the native word-sized signed integer
type (ptrdiff_t).  If you define the MDForceLongInts version, it will force MiniD to use 64-bit integers
even on 32-bit platforms.  If you define the MDForceShortInts version, it will force MiniD to use 32-bit
integers even on 64-bit platforms.
*/
version(MDForceLongInts)
{
	version(MDForceShortInts)
	{
		pragma(msg, "The 'MDForceLongInts' and 'MDForceShortInts' versions are mutually exclusive.");
		pragma(msg, "Please define one or the other (or neither), not both.\n");
		static assert(false, "FAILCOPTER.");
	}

	public alias long mdint;
}
else version(MDForceShortInts)
	public alias int mdint;
else
	public alias word mdint;

static assert(mdint.sizeof >= 4, "mdint must be at least 32 bits");
static assert((cast(mdint)-1) < (cast(mdint)0), "mdint must be signed");

/**
The underlying D type used to store the MiniD 'float' type.  Defaults to 'double'.
*/
public alias double mdfloat;

/**
The current version of MiniD.
*/
public const uint MiniDVersion = MakeVersion!(2, 0);

/**
An alias for the type signature of a native function.  It is defined as uword function(MDThread*, uword).
*/
public alias uword function(MDThread*, uword) NativeFunc;

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
An exception type representing a compilation error.  The message will be in the form "filename(line:column):
error message".  Again, you can't directly instantiate this exception type.
*/
final class MDCompileException : MDException
{
	/**
	Indicates whether the compiler threw this at the end of the file or not.  If this is
	true, this might be because the compiler ran out of input, in which case the code could
	be made to compile by adding more code.
	*/
	public bool atEOF = false;
	
	/**
	Indicates whether the compiler threw this because of a statement that consisted of a no-effect expression.
	If true, the code might be able to be compiled and evaluated as an expression.
	*/
	public bool solitaryExpression = false;

	package this(char[] msg)
	{
		super(msg);
	}
}

/**
This is a semi-internal exception type.  Normally you won't need to know about it or catch it.  This is
thrown when a coroutine (thread) needs to be halted.  It should never propagate out of the coroutine.
The only time you might encounter it is if, in the middle of a native MiniD function, one of these
is thrown, you might be able to catch it and clean up some resources, but you should rethrow it.

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
A string constant indicating the level of coroutine support compiled in.  Is one of "Restricted",
"Normal", or "Extended".
*/
version(MDRestrictedCoro)
{
	version(MDExtendedCoro)
	{
		pragma(msg, "The 'MDRestrictedCoro' and 'MDExtendedCoro' versions are mutually exclusive.");
		pragma(msg, "Please define one or the other (or neither), not both.\n");
		static assert(false, "FAILCOPTER.");
	}

	const char[] MDCoroSupport = "Restricted";
}
else version(MDExtendedCoro)
	const char[] MDCoroSupport = "Extended";
else
	const char[] MDCoroSupport = "Normal";

// ================================================================================================================================================
// Package
// ================================================================================================================================================

package template isValidMDValueType(T)
{
	static if(is(T == typedef) || is(T == enum))
		const isValidMDValueType = isValidMDValueType!(realType!(T));
	else
		const isValidMDValueType =
			is(T == bool) ||
			isIntType!(T) ||
			isFloatType!(T) ||
			isCharType!(T) ||
			is(T == MDString*) ||
			is(T == MDTable*) ||
			is(T == MDArray*) ||
			is(T == MDFunction*) ||
			is(T == MDObject*) ||
			is(T == MDNamespace*) ||
			is(T == MDThread*) ||
			is(T == MDBaseObject*) ||
			is(T == MDValue) ||
			is(T == MDValue*);
}

align(1) struct MDValue
{
	enum Type
	{
		// Value Types
		Null,
		Bool,
		Int,
		Float,
		Char,

		// Reference Types
		String,
		Table,
		Array,
		Function,
		Object,
		Namespace,
		Thread,
		NativeObj,

		// Internal types
		Upvalue,
		FuncDef,
		ArrayData
	}

	package static dchar[] typeString(MDValue.Type t)
	{
		switch(t)
		{
			case Type.Null: return "null";
			case Type.Bool: return "bool";
			case Type.Int: return "int";
			case Type.Float: return "float";
			case Type.Char: return "char";

			case Type.String: return "string";
			case Type.Table: return "table";
			case Type.Array: return "array";
			case Type.Function: return "function";
			case Type.Object: return "object";
			case Type.Namespace: return "namespace";
			case Type.Thread: return "thread";
			case Type.NativeObj: return "nativeobj";

			case Type.Upvalue: return "upvalue";
			case Type.FuncDef: return "funcdef";
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
		package MDObject* mObject;
		package MDNamespace* mNamespace;
		package MDThread* mThread;
		package MDNativeObj* mNativeObj;
	}

	package static MDValue opCall(T)(T t)
	{
		MDValue ret = void;
		ret = t;
		return ret;
	}
	
	/*
	Returns true if this and the other value are exactly the same type and the same value.  The semantics
	of this are exactly the same as the 'is' expression in MiniD.
	*/
	package int opEquals(ref MDValue other)
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
	
	package void opAssign(MDObject* src)
	{
		type = Type.Object;
		mObject = src;
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
	
	debug char[] toString()
	{
		switch(type)
		{
			case Type.Null:      return "null";
			case Type.Bool:      return Format("{}", mBool);
			case Type.Int:       return Format("{}", mInt);
			case Type.Float:     return Format("{}", mFloat);
			case Type.Char:      return Format("'{}'", mChar);
			case Type.String:    return Format("\"{}\"", mString.toString32());
			case Type.Table:     return Format("table {:X8}", cast(void*)mTable);
			case Type.Array:     return Format("array {:X8}", cast(void*)mArray);
			case Type.Function:  return Format("function {:X8}", cast(void*)mFunction);
			case Type.Object:    return Format("object {:X8}", cast(void*)mObject);
			case Type.Namespace: return Format("namespace {:X8}", cast(void*)mNamespace);
			case Type.Thread:    return Format("thread {:X8}", cast(void*)mThread);
			case Type.NativeObj: return Format("nativeobj {:X8}", cast(void*)mNativeObj);
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

align(1) struct MDBaseObject
{
	mixin MDObjectMixin!(MDValue.Type.Null);
}

align(1) struct MDString
{
	mixin MDObjectMixin!(MDValue.Type.String);
	package uword hash;
	package uword length;

	package dchar[] toString32()
	{
		return (cast(dchar*)(this + 1))[0 .. this.length];
	}
}

align(1) struct MDTable
{
	mixin MDObjectMixin!(MDValue.Type.Table);
	package Hash!(MDValue, MDValue) data;
}

align(1) struct MDArrayData
{
	mixin MDObjectMixin!(MDValue.Type.ArrayData);
	package uword length;

	package MDValue[] toArray()
	{
		return (cast(MDValue*)(this + 1))[0 .. length];
	}
}

align(1) struct MDArray
{
	mixin MDObjectMixin!(MDValue.Type.Array);
	package MDArrayData* data;
	package MDValue[] slice;
	package bool isSlice;
}

align(1) struct MDFunction
{
	mixin MDObjectMixin!(MDValue.Type.Function);
	package bool isNative;
	package MDNamespace* environment;
	package MDString* name;
	package uword numUpvals;
	package MDTable* attrs;

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

align(1) struct MDObject
{
	mixin MDObjectMixin!(MDValue.Type.Object);
	package MDString* name;
	package MDObject* proto;
	package MDNamespace* fields;
	package MDTable* attrs;
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

align(1) struct MDNamespace
{
	mixin MDObjectMixin!(MDValue.Type.Namespace);
	package Hash!(MDString*, MDValue) data;
	package MDNamespace* parent;
	package MDString* name;
	package MDTable* attrs;
}

package alias uword AbsStack;
package alias uword RelStack;

align(1) struct ActRecord
{
	package AbsStack base;
	package AbsStack savedTop;
	package AbsStack vargBase;
	package AbsStack returnSlot;
	package MDFunction* func;
	package Instruction* pc;
	package word numReturns;
	package MDObject* proto;
	package uword numTailcalls;
	package uword firstResult;
	package uword numResults;
}

align(1) struct TryRecord
{
	package bool isCatch;
	package RelStack catchVarSlot;
	package uword actRecord;
	package Instruction* pc;
}

align(1) struct MDThread
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

	static dchar[][5] StateStrings =
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

	version(MDExtendedCoro) {} else
	{
		package uword savedCallDepth;
		package uword nativeCallDepth = 0;
	}

	version(MDRestrictedCoro) {} else
	{
		// References a Fiber object
		package MDNativeObj* coroFiber;

		package Fiber getFiber()
		{
			assert(coroFiber !is null);
			return cast(Fiber)cast(void*)coroFiber.obj;
		}
	}
}

align(1) struct MDNativeObj
{
	mixin MDObjectMixin!(MDValue.Type.NativeObj);
	package Object obj;
}

align(1) struct Location
{
	// yes, these are 32 bits
	package int line = 1;
	package int column = 1;
	public MDString* fileName;

	public static Location opCall(MDString* fileName, int line = 1, int column = 1)
	{
		Location l;
		l.fileName = fileName;
		l.line = line;
		l.column = column;
		return l;
	}

// 	public char[] toString()
// 	{
// 		if(line == -1 && column == -1)
// 			return Format("{}(native)", fileName);
// 		else
// 			return Format("{}({}:{})", fileName, line, column);
// 	}
}

align(1) struct MDUpval
{
	mixin MDObjectMixin!(MDValue.Type.Upvalue);

	package MDValue* value;
	package MDValue closedValue;
	package MDUpval* next;
	package MDUpval* prev;
}

// The integral members of this struct are fixed at 32 bits for possible cross-platform serialization.
align(1) struct MDFuncDef
{
	mixin MDObjectMixin!(MDValue.Type.FuncDef);

	package Location location;
	package bool isVararg;
	package MDString* name;
	package uint numParams;
	package uint[] paramMasks; // TODO: make this short
	package uint numUpvals;
	package uint stackSize;
	package MDFuncDef*[] innerFuncs;
	package MDValue[] constants;
	package Instruction[] code;

	package bool isPure;
	package MDFunction* cachedFunc;

	align(1) struct SwitchTable
	{
		package Hash!(MDValue, word) offsets;
		package int defaultOffset = -1; // yes, this is 32 bit, it's fixed that size
	}

	package SwitchTable[] switchTables;

	// Debug info.
	package uint[] lineInfo;
	package MDString*[] upvalNames;

	align(1) struct LocVarDesc
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
	package Hash!(dchar[], MDString*) stringTab;
	package MDString*[] metaStrings;
	package Location[] traceback;
	package MDValue exception;
	package bool isThrowing;

	// The following members point into the D heap.
	package MDNativeObj*[Object] nativeObjs;
	package Layout!(dchar) formatter;

	version(MDRestrictedCoro) {} else
	{
		version(MDPoolFibers)
			package bool[Fiber] fiberPool;
	}
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

package const dchar[][] MetaNames =
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
	MM.And:  MM.And_r,
	MM.Cat:  MM.Cat_r,
	MM.Div:  MM.Div_r,
	MM.Mod:  MM.Mod_r,
	MM.Mul:  MM.Mul_r,
	MM.Or:   MM.Or_r,
	MM.Shl:  MM.Shl_r,
	MM.Shr:  MM.Shr_r,
	MM.Sub:  MM.Sub_r,
	MM.UShr: MM.UShr_r,
	MM.Xor:  MM.Xor_r,
	
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