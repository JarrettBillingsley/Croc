#ifndef CROC_TYPES_HPP
#define CROC_TYPES_HPP

#include <stddef.h>

#include "croc/base/alloc.hpp"
#include "croc/base/darray.hpp"
#include "croc/base/deque.hpp"
#include "croc/base/hash.hpp"
#include "croc/base/opcodes.hpp"
#include "croc/base/sanity.hpp"

namespace croc
{
	// ========================================
	// Basic poops

	// Convenience aliases
	typedef ptrdiff_t word;
	typedef size_t uword;
	typedef crocint_t crocint;
	typedef crocfloat_t crocfloat;
	typedef crocchar_t crocchar;

	enum Location
	{
		Location_Unknown = 0,
		Location_Native = -1,
		Location_Script = -2
	};

	// Forward decls :P
	struct VM;
	struct String;
	struct WeakRef;
	struct Table;
	struct Namespace;
	struct Array;
	struct Memblock;
	struct Function;
	struct FuncDef;
	struct Class;
	struct Instance;
	struct Thread;
	struct Upvalue;

	// ========================================
	// Value

	struct Value
	{
		CrocType type;

		union
		{
			bool mBool;
			crocint mInt;
			crocfloat mFloat;
			crocchar mChar;
			void* mNativeObj;

			GCObject* mGCObj;

			String* mString;
			WeakRef* mWeakRef;

			Table* mTable;
			Namespace* mNamespace;
			Array* mArray;
			Memblock* mMemblock;
			Function* mFunction;
			FuncDef* mFuncDef;
			Class* mClass;
			Instance* mInstance;
			Thread* mThread;
		};

		static const Value nullValue;

		bool operator==(const Value& other) const;
		inline bool operator!=(const Value& other) const { return !(*this == other); }
		bool isFalse() const;
		hash_t toHash() const;

		inline bool isValType() const  { return type <  CrocType_FirstRefType; }
		inline bool isRefType() const  { return type >= CrocType_FirstRefType; }
		inline bool isGCObject() const { return type >= CrocType_FirstGCType;  }

		inline GCObject* toGCObject() const
		{
			assert(isGCObject());
			return mGCObj;
		}

#define MAKE_SET(name, nativetype) inline void operator=(nativetype v) { type = CrocType_##name; m##name = v; }
		MAKE_SET(Bool, bool)
		MAKE_SET(Int, crocint)
		MAKE_SET(Float, crocfloat)
		MAKE_SET(Char, crocchar)
		inline void setNativeObj(void* v) { type = CrocType_NativeObj; mNativeObj = v; }

		inline void operator=(GCObject* v) { this->mGCObj = v; this->type = v->mType; }

		MAKE_SET(String, String*)
		MAKE_SET(WeakRef, WeakRef*)

		MAKE_SET(Table, Table*)
		MAKE_SET(Namespace, Namespace*)
		MAKE_SET(Array, Array*)
		MAKE_SET(Memblock, Memblock*)
		MAKE_SET(Function, Function*)
		MAKE_SET(FuncDef, FuncDef*)
		MAKE_SET(Class, Class*)
		MAKE_SET(Instance, Instance*)
		MAKE_SET(Thread, Thread*)
#undef MAKE_SET
	};

#define OBJ_HEADER(Name, Acyclic) static const bool ACYCLIC = Acyclic; Name() { mType = CrocType_##Name; }

	struct String : public GCObject
	{
		OBJ_HEADER(String, true)
		uword hash;
		uword length;
		uword cpLength;

		inline const char* toString() const { return cast(const char*)(this + 1); }
		inline DArray<const char> toDArray() const { return DArray<const char>(toString(), length); }
		inline hash_t toHash() const { return hash; }
	};

	struct WeakRef : public GCObject
	{
		OBJ_HEADER(WeakRef, true)
		GCObject* obj;
	};

	struct Table : public GCObject
	{
		OBJ_HEADER(Table, false)
		Hash<Value, Value, MethodHasher, HashNodeWithModified<Value, Value> > data;
		typedef HashNodeWithModified<Value, Value> Node;
	};

	struct Namespace : public GCObject
	{
		OBJ_HEADER(Namespace, false)
		Hash<String*, Value, MethodHasher, HashNodeWithModified<String*, Value> > data;
		typedef HashNodeWithModified<String*, Value> Node;
		Namespace* parent;
		String* name;
		bool visitedOnce;
	};

	struct Array : public GCObject
	{
		OBJ_HEADER(Array, false)
		uword length;

		struct Slot
		{
			Value value;
			bool modified;
			bool operator==(const Slot& other) const { return value == other.value; }

			Slot():
				value(),
				modified(false)
			{}
		};

		DArray<Slot> data;

		inline DArray<Slot> toArray() { return DArray<Slot>(data.ptr, length); }
	};

	struct Memblock : public GCObject
	{
		OBJ_HEADER(Memblock, true)
		DArray<uint8_t> data;
		bool ownData;
	};

	struct Function : public GCObject
	{
		OBJ_HEADER(Function, false)
		bool isNative;
		Namespace* environment;
		String* name;
		uword numUpvalues;
		uword numParams;
		uword maxParams;

		union
		{
			FuncDef* scriptFunc;
			CrocNativeFunc nativeFunc;

			// TODO:
			// static assert((CrocFuncDef*).sizeof == NativeFunc.sizeof);
		};

		inline DArray<Value>    nativeUpvalues() const { return DArray<Value>(cast(Value*)(this + 1), numUpvalues); }
		inline DArray<Upvalue*> scriptUpvalues() const { return DArray<Upvalue*>(cast(Upvalue**)(this + 1), numUpvalues); }
	};

	// The integral members of this struct are fixed at 32 bits for possible cross-platform serialization.
	struct FuncDef : public GCObject
	{
		OBJ_HEADER(FuncDef, false)
		String* locFile;
		int32_t locLine;
		int32_t locCol;
		bool isVararg;
		String* name;
		uint32_t numParams;
		DArray<uint32_t> paramMasks;
		uint32_t numUpvalues;

		struct UpvalueDesc
		{
			bool isUpvalue;
			uint32_t index;
		};

		DArray<UpvalueDesc> upvalues;
		uint32_t stackSize;
		DArray<FuncDef*> innerFuncs;
		DArray<Value> constants;
		DArray<Instruction> code;

		Namespace* environment;
		Function* cachedFunc;

		struct SwitchTable
		{
			Hash<Value, int32_t, MethodHasher> offsets;
			int32_t defaultOffset;
		};

		DArray<SwitchTable> switchTables;

		// Debug info.
		DArray<uint32_t> lineInfo;
		DArray<String*> upvalueNames;

		struct LocVarDesc
		{
			String* name;
			uint32_t pcStart;
			uint32_t pcEnd;
			uint32_t reg;
		};

		DArray<LocVarDesc> locVarDescs;
	};

	struct Class : public GCObject
	{
		OBJ_HEADER(Class, false)
		String* name;
		Class* parent;
		Namespace* fields;
		Function* allocator;
		Function* finalizer;
		bool allocatorSet;
		bool finalizerSet;
	};

	struct Instance : public GCObject
	{
		OBJ_HEADER(Instance, false)
		Class* parent;
		Namespace* fields;
		uword numValues;
		uword extraBytes;

		inline DArray<Value>   extraValues() const { return DArray<Value>(cast(Value*)(this + 1), numValues); }
		inline DArray<uint8_t> extraData()   const { return DArray<uint8_t>(cast(uint8_t*)((cast(char*)(this + 1)) + (numValues * sizeof(Value))), extraBytes); }
	};

	typedef uword AbsStack;
	typedef uword RelStack;

	struct ActRecord
	{
		AbsStack base;
		AbsStack savedTop;
		AbsStack vargBase;
		AbsStack returnSlot;
		Function* func;
		Instruction* pc;
		word numReturns;
		Class* proto;
		uword numTailcalls;
		uword firstResult;
		uword numResults;
		uword unwindCounter;
		Instruction* unwindReturn;
	};

	struct TryRecord
	{
		bool isCatch;
		RelStack slot;
		uword actRecord;
		Instruction* pc;
	};

	struct Thread : public GCObject
	{
		OBJ_HEADER(Thread, false)

		enum State
		{
			State_Initial,
			State_Waiting,
			State_Running,
			State_Suspended,
			State_Dead
		};

		enum Hook
		{
			Hook_Call = 1,
			Hook_Ret = 2,
			Hook_TailRet = 4,
			Hook_Delay = 8,
			Hook_Line = 16
		};

		static const char* StateStrings[5];

		DArray<TryRecord> tryRecs;
		TryRecord* currentTR;
		uword trIndex;

		DArray<ActRecord> actRecs;
		ActRecord* currentAR;
		uword arIndex;

		DArray<Value> stack;
		AbsStack stackIndex;
		AbsStack stackBase;

		DArray<Value> results;
		uword resultIndex;

		Upvalue* upvalueHead;

		VM* vm;
		bool shouldHalt;

		Function* coroFunc;
		State state;
		uword numYields;

		uint8_t hooks;
		bool hooksEnabled;
		uint32_t hookDelay;
		uint32_t hookCounter;
		Function* hookFunc;

		uword savedCallDepth;
		uword nativeCallDepth;
	};

	struct Upvalue : public GCObject
	{
		OBJ_HEADER(Upvalue, false)
		Value* value;
		Value closedValue;
		Upvalue* nextuv;
	};

	struct VM
	{
		Allocator alloc;

		// These are all GC roots -----------
		Namespace* globals;
		Thread* mainThread;
		DArray<Namespace*> metaTabs;
		DArray<String*> metaStrings;
		Instance* exception;
		Namespace* registry;
		Hash<uint64_t, GCObject*> refTab;

		// These point to "special" runtime classes
		Class* object;
		Class* throwable;
		Class* location;
		Hash<String*, Class*, MethodHasher> stdExceptions;
		// ----------------------------------

		// GC stuff
		uint8_t oldRootIdx;
		Deque roots[2];
		Deque cycleRoots;
		Deque toFree;
		Deque toFinalize;
		bool inGCCycle;

		// Others
		Hash<DArray<const char>, String*, DefaultHasher, HashNodeWithHash<DArray<const char>, String*> > stringTab;
		Hash<GCObject*, WeakRef*> weakRefTab;
		Hash<Thread*, bool> allThreads;
		uint64_t currentRef;
		String* ctorString; // also stored in metaStrings, don't have to scan it as a root
		Thread* curThread;
		bool isThrowing;
	};
}
#endif