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

import tango.text.convert.Format;
import tango.text.convert.Layout;

import croc.base_alloc;
import croc.base_hash;
import croc.base_deque;
import croc.base_opcodes;
import croc.utils;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

/**
The native signed integer type on this platform. This is the same as ptrdiff_t but with a better name.
*/
alias ptrdiff_t word;

/**
The native unsigned integer type on this platform. This is the same as size_t but with a better name.
*/
alias size_t uword;

/**
The underlying D type used to store the Croc 'int' type. Defaults to 'long' (64-bit signed integer). If you
change it, you will end up with a (probably?) functional but nonstandard implementation.
*/
alias long crocint;

static assert((cast(crocint)-1) < (cast(crocint)0), "crocint must be signed");

/**
The underlying D type used to store the Croc 'float' type. Defaults to 'double'. If you change it, you will end
up with a functional but nonstandard implementation.
*/
alias double crocfloat;

/**
The current version of Croc as a 32-bit integer. The upper 16 bits are the major, and the lower 16 are
the minor.
*/
const uint CrocVersion = MakeVersion!(0, 1);

/**
An alias for the type signature of a native function. It is defined as uword function(CrocThread*, uword).
*/
alias uword function(CrocThread*) NativeFunc;

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
This is a rarely-thrown exception type. This is only thrown in fairly severe circumstances, and these
situations are not meant to be recoverable. Even closing the VM that threw one may not be possible.

Currently there is only one situation in which this is thrown: if a finalizable class instance is in
a garbage cycle. There is no way to determine finalization order in this case and therefore no correct
way to proceed. Finalizable classes should be designed in such a way as to avoid reference cycles.
*/
final class CrocFatalException : Exception
{
	package this(char[] msg)
	{
		super(msg);
	}
}

// ================================================================================================================================================
// Package
// ================================================================================================================================================

package:

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
		// Value
		Null,       // 0
		Bool,       // 1
		Int,        // 2
		Float,      // 3
		Char,       // 4

		// Quasi-value (GC'ed but still value)
		NativeObj,  // 5
		String,     // 6
		WeakRef,    // 7

		// Ref
		Table,      // 8
		Namespace,  // 9
		Array,      // 10
		Memblock,   // 11
		Function,   // 12
		FuncDef,    // 13
		Class,      // 14
		Instance,   // 15
		Thread,     // 16

		// Internal
		Upvalue,    // 17

		// Other
		FirstGCType = Type.NativeObj,
		FirstRefType = Type.Table,
		FirstUserType = Type.Null,
		LastUserType = Type.Thread
	}

package:
	static const char[][] typeStrings =
	[
		Type.Null:      "null",
		Type.Bool:      "bool",
		Type.Int:       "int",
		Type.Float:     "float",
		Type.Char:      "char",

		Type.NativeObj: "nativeobj",
		Type.String:    "string",
		Type.WeakRef:   "weakref",

		Type.Table:     "table",
		Type.Namespace: "namespace",
		Type.Array:     "array",
		Type.Memblock:  "memblock",
		Type.Function:  "function",
		Type.FuncDef:   "funcdef",
		Type.Class:     "class",
		Type.Instance:  "instance",
		Type.Thread:    "thread",

		Type.Upvalue:   "upvalue"
	];

	static CrocValue nullValue = { type : Type.Null, mInt : 0 };

	Type type = Type.Null;

	union
	{
		bool mBool;
		crocint mInt;
		crocfloat mFloat;
		dchar mChar;

		CrocBaseObject* mBaseObj;
		CrocString* mString;
		CrocTable* mTable;
		CrocArray* mArray;
		CrocMemblock* mMemblock;
		CrocFunction* mFunction;
		CrocClass* mClass;
		CrocInstance* mInstance;
		CrocNamespace* mNamespace;
		CrocThread* mThread;
		CrocNativeObj* mNativeObj;
		CrocWeakRef* mWeakRef;
		CrocFuncDef* mFuncDef;
	}

	static CrocValue opCall(T)(T t)
	{
		CrocValue ret = void;
		ret = t;
		return ret;
	}

	int opEquals(CrocValue other)
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

	bool isFalse()
	{
		return
			(type == Type.Null) ||
			(type == Type.Bool && mBool == false) ||
			(type == Type.Int && mInt == 0) ||
			(type == Type.Float && mFloat == 0.0) ||
			(type == Type.Char && mChar == 0);
	}

	void opAssign(bool src)
	{
		type = Type.Bool;
		mBool = src;
	}

	void opAssign(crocint src)
	{
		type = Type.Int;
		mInt = src;
	}

	void opAssign(crocfloat src)
	{
		type = Type.Float;
		mFloat = src;
	}

	void opAssign(dchar src)
	{
		type = Type.Char;
		mChar = src;
	}

	void opAssign(CrocString* src)
	{
		type = Type.String;
		mString = src;
	}

	void opAssign(CrocTable* src)
	{
		type = Type.Table;
		mTable = src;
	}

	void opAssign(CrocArray* src)
	{
		type = Type.Array;
		mArray = src;
	}

	void opAssign(CrocMemblock* src)
	{
		type = Type.Memblock;
		mMemblock = src;
	}

	void opAssign(CrocFunction* src)
	{
		type = Type.Function;
		mFunction = src;
	}

	void opAssign(CrocClass* src)
	{
		type = Type.Class;
		mClass = src;
	}

	void opAssign(CrocInstance* src)
	{
		type = Type.Instance;
		mInstance = src;
	}

	void opAssign(CrocNamespace* src)
	{
		type = Type.Namespace;
		mNamespace = src;
	}

	void opAssign(CrocThread* src)
	{
		type = Type.Thread;
		mThread = src;
	}

	void opAssign(CrocNativeObj* src)
	{
		type = Type.NativeObj;
		mNativeObj = src;
	}

	void opAssign(CrocWeakRef* src)
	{
		type = Type.WeakRef;
		mWeakRef = src;
	}

	void opAssign(CrocFuncDef* src)
	{
		type = Type.FuncDef;
		mFuncDef = src;
	}

	void opAssign(CrocBaseObject* src)
	{
		type = src.mType;
		mBaseObj = src;
	}

	bool isValType()
	{
		return type < Type.FirstRefType;
	}

	bool isRefType()
	{
		return type >= Type.FirstRefType;
	}

	bool isGCObject()
	{
		return type >= Type.FirstGCType;
	}

	GCObject* toGCObject()
	{
		assert(isGCObject());
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
	mixin GCObjectMembers;
package:
	CrocValue.Type mType = cast(CrocValue.Type)type;
}

struct CrocBaseObject
{
	mixin CrocObjectMixin!(CrocValue.Type.Null);
}

struct CrocString
{
	mixin CrocObjectMixin!(CrocValue.Type.String);
package:
	uword hash;
	uword length;
	uword cpLength;

	char[] toString()
	{
		return (cast(char*)(this + 1))[0 .. this.length];
	}

	alias hash toHash;
	static const bool ACYCLIC = true;
}

struct CrocTable
{
	mixin CrocObjectMixin!(CrocValue.Type.Table);
package:
	Hash!(CrocValue, CrocValue, true) data;
}

struct CrocArray
{
	mixin CrocObjectMixin!(CrocValue.Type.Array);
package:
	uword length;

	struct Slot
	{
		CrocValue value;
		bool modified;
		int opEquals(Slot other) { return value == other.value; }
	}

	Slot[] data;

	Slot[] toArray()
	{
		return data[0 .. this.length];
	}
}

struct CrocMemblock
{
	mixin CrocObjectMixin!(CrocValue.Type.Memblock);

package:
	ubyte[] data;
	bool ownData;

	static const bool ACYCLIC = true;
}

struct CrocFunction
{
	mixin CrocObjectMixin!(CrocValue.Type.Function);
package:
	bool isNative;
	CrocNamespace* environment;
	CrocString* name;
	uword numUpvals;
	uword numParams;
	uword maxParams;

	union
	{
		CrocFuncDef* scriptFunc;
		NativeFunc nativeFunc;

		static assert((CrocFuncDef*).sizeof == NativeFunc.sizeof);
	}

	CrocValue[] nativeUpvals()
	{
		return (cast(CrocValue*)(this + 1))[0 .. numUpvals];
	}

	CrocUpval*[] scriptUpvals()
	{
		return (cast(CrocUpval**)(this + 1))[0 .. numUpvals];
	}
}

struct FieldValue
{
	CrocValue value;
	CrocClass* proto;
	bool isPublic;
}

struct CrocClass
{
	mixin CrocObjectMixin!(CrocValue.Type.Class);
package:
	CrocString* name;
	CrocClass* parent;
	bool isFrozen;
	bool visitedOnce;
	Hash!(CrocString*, FieldValue, true) methods;
	Hash!(CrocString*, FieldValue, true) fields;
	CrocFunction* finalizer;
}

struct CrocInstance
{
	mixin CrocObjectMixin!(CrocValue.Type.Instance);
package:
	CrocClass* parent;
	bool visitedOnce;
	Hash!(CrocString*, FieldValue, true) fields;
}

struct CrocNamespace
{
	mixin CrocObjectMixin!(CrocValue.Type.Namespace);
package:
	Hash!(CrocString*, CrocValue, true) data;
	CrocNamespace* parent;
	CrocString* name;
	bool visitedOnce;
}

alias uword AbsStack;
alias uword RelStack;

struct ActRecord
{
package:
	AbsStack base;
	AbsStack savedTop;
	AbsStack vargBase;
	AbsStack returnSlot;
	CrocFunction* func;
	Instruction* pc;
	word numReturns;
	CrocClass* proto;
	uword numTailcalls;
	uword firstResult;
	uword numResults;
	uword unwindCounter = 0;
	Instruction* unwindReturn = null;
}

struct TryRecord
{
package:
	bool isCatch;
	RelStack slot;
	uword actRecord;
	Instruction* pc;
}

struct CrocThread
{
	mixin CrocObjectMixin!(CrocValue.Type.Thread);

public:
	enum State
	{
		Initial,
		Waiting,
		Running,
		Suspended,
		Dead
	}

	enum Hook : ubyte
	{
		Call = 1,
		Ret = 2,
		TailRet = 4,
		Delay = 8,
		Line = 16
	}

package:
	static char[][5] StateStrings =
	[
		State.Initial: "initial",
		State.Waiting: "waiting",
		State.Running: "running",
		State.Suspended: "suspended",
		State.Dead: "dead"
	];

	TryRecord[] tryRecs;
	TryRecord* currentTR;
	uword trIndex = 0;

	ActRecord[] actRecs;
	ActRecord* currentAR;
	uword arIndex = 0;

	CrocValue[] stack;
	AbsStack stackIndex;
	AbsStack stackBase;

	CrocValue[] results;
	uword resultIndex = 0;

	CrocUpval* upvalHead;

	CrocVM* vm;
	bool shouldHalt = false;

	CrocFunction* coroFunc;
	State state = State.Initial;
	uword numYields;

	ubyte hooks;
	bool hooksEnabled = true;
	uint hookDelay;
	uint hookCounter;
	CrocFunction* hookFunc;

	uword savedCallDepth;
	uword nativeCallDepth = 0;
}

struct CrocNativeObj
{
	mixin CrocObjectMixin!(CrocValue.Type.NativeObj);
package:
	Object obj;
	static const bool ACYCLIC = true;
}

struct CrocWeakRef
{
	mixin CrocObjectMixin!(CrocValue.Type.WeakRef);
package:
	CrocBaseObject* obj;
	static const bool ACYCLIC = true;
}

enum CrocLocation
{
	Unknown = 0,
	Native = -1,
	Script = -2
}

// The integral members of this struct are fixed at 32 bits for possible cross-platform serialization.
struct CrocFuncDef
{
	mixin CrocObjectMixin!(CrocValue.Type.FuncDef);

package:
	CrocString* locFile;
	int locLine = 1;
	int locCol = 1;
	bool isVararg;
	CrocString* name;
	uint numParams;
	uint[] paramMasks;
	uint numUpvals;

	struct UpvalDesc
	{
		bool isUpvalue;
		uint index;
	}

	UpvalDesc[] upvals;
	uint stackSize;
	CrocFuncDef*[] innerFuncs;
	CrocValue[] constants;
	Instruction[] code;

	CrocNamespace* environment;
	CrocFunction* cachedFunc;

	struct SwitchTable
	{
		Hash!(CrocValue, int) offsets;
		int defaultOffset = -1; // yes, this is 32 bit, it's fixed that size
	}

	SwitchTable[] switchTables;

	// Debug info.
	uint[] lineInfo;
	CrocString*[] upvalNames;

	struct LocVarDesc
	{
		CrocString* name;
		uint pcStart;
		uint pcEnd;
		uint reg;
	}

	LocVarDesc[] locVarDescs;
}

struct CrocUpval
{
	mixin CrocObjectMixin!(CrocValue.Type.Upvalue);
package:
	CrocValue* value;
	CrocValue closedValue;
	CrocUpval* nextuv;
}

// please don't align(1) this struct, it'll mess up the D GC when it tries to look inside for pointers.
struct CrocVM
{
package:
	Allocator alloc;

	// These are all GC roots -----------
	CrocNamespace* globals;
	CrocThread* mainThread;
	CrocNamespace*[] metaTabs;
	CrocString*[] metaStrings;
	CrocInstance* exception;
	CrocNamespace* registry;
	Hash!(ulong, CrocBaseObject*) refTab;

	// These point to "special" runtime classes
	CrocClass* object;
	CrocClass* throwable;
	CrocClass* location;
	Hash!(CrocString*, CrocClass*) stdExceptions;
	// ----------------------------------

	// GC stuff
	ubyte oldRootIdx;
	Deque!(GCObject*)[2] roots;
	Deque!(GCObject*) cycleRoots;
	Deque!(GCObject*) toFree;
	Deque!(CrocInstance*) toFinalize;
	bool inGCCycle;

	// Others
	Hash!(char[], CrocString*) stringTab;
	Hash!(CrocBaseObject*, CrocWeakRef*) weakRefTab;
	Hash!(CrocThread*, bool) allThreads;
	ulong currentRef;
	CrocString* ctorString; // also stored in metaStrings, don't have to scan it as a root
	CrocThread* curThread;
	bool isThrowing;

	// The following members point into the D heap.
	CrocNativeObj*[Object] nativeObjs;
	Layout!(char) formatter;
	CrocException dexception;
}