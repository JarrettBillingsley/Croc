#ifndef CROC_TYPES_HPP
#define CROC_TYPES_HPP

#include <stddef.h>

#include "croc/base/darray.hpp"
#include "croc/base/deque.hpp"
#include "croc/base/hash.hpp"
#include "croc/base/memory.hpp"
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

	enum Location
	{
		Location_Unknown = 0,
		Location_Native = -1,
		Location_Script = -2
	};

	// Forward decls :P
	struct VM;
	struct String;
	struct Weakref;
	struct Table;
	struct Namespace;
	struct Array;
	struct Memblock;
	struct Function;
	struct Funcdef;
	struct Class;
	struct Instance;
	struct Thread;
	struct Upval;

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
			void* mNativeobj;

			GCObject* mGCObj;

			String* mString;
			Weakref* mWeakref;

			Table* mTable;
			Namespace* mNamespace;
			Array* mArray;
			Memblock* mMemblock;
			Function* mFunction;
			Funcdef* mFuncdef;
			Class* mClass;
			Instance* mInstance;
			Thread* mThread;

			Upval* mUpval;
		};

		static const Value nullValue;

		bool operator==(const Value& other) const
		{
			return this->type == other.type &&
				(this->type == CrocType_Null ||
					this->mInt == other.mInt); // NONPORTABLE
		}

		inline bool operator!=(const Value& other) const
		{
			return !(*this == other);
		}

		inline bool isFalse() const
		{
			// ORDER CROCTYPE
			return type <= CrocType_Float && mInt == 0; // NONPORTABLE
		}

		hash_t toHash() const;

		// ORDER CROCTYPE
		inline bool isValType() const
		{
			return type <  CrocType_FirstRefType;
		}

		// ORDER CROCTYPE
		inline bool isRefType() const
		{
			return type >= CrocType_FirstRefType;
		}

		// ORDER CROCTYPE
		inline bool isGCObject() const
		{
			return type >= CrocType_FirstGCType;
		}

		inline GCObject* toGCObject() const
		{
			assert(isGCObject());
			return mGCObj;
		}

		inline void setGCObject(GCObject* v)
		{
			this->mGCObj = v;
			this->type = v->type;
		}

#define MAKE_SET(name, nativetype)\
	inline void set##name(nativetype v)\
	{\
		type = CrocType_##name;\
		m##name = v;\
	}

		MAKE_SET(Bool, bool)
		MAKE_SET(Int, crocint)
		MAKE_SET(Float, crocfloat)
		MAKE_SET(Nativeobj, void*)

		MAKE_SET(String, String*)
		MAKE_SET(Weakref, Weakref*)

		MAKE_SET(Table, Table*)
		MAKE_SET(Namespace, Namespace*)
		MAKE_SET(Array, Array*)
		MAKE_SET(Memblock, Memblock*)
		MAKE_SET(Function, Function*)
		MAKE_SET(Funcdef, Funcdef*)
		MAKE_SET(Class, Class*)
		MAKE_SET(Instance, Instance*)
		MAKE_SET(Thread, Thread*)
#undef MAKE_SET
	};

	struct String : public GCObject
	{
		// acyclic
		uword hash;
		uword length;
		uword cpLength;

		inline const char* toString() const
		{
			return cast(const char*)(this + 1);
		}

		inline DArray<const char> toDArray() const
		{
			return DArray<const char>::n(toString(), length);
		}

		inline hash_t toHash() const
		{
			return hash;
		}
	};

	enum Privacy
	{
		Privacy_Public,
		Privacy_Protected,
		Privacy_Private
	};

	struct FieldValue
	{
		Value value;
		Class* proto;
		Privacy privacy;
	};

	typedef HashNode<String*, FieldValue> FieldHashNode;
	typedef Hash<String*, FieldValue, MethodHasher, FieldHashNode> FieldHash;

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
		AbsStack firstResult;
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

	extern const char* ThreadStateStrings[5];

	struct Weakref : public GCObject
	{
		// acyclic
		GCObject* obj;
	};

	struct Table : public GCObject
	{
		typedef HashNode<Value, Value> NodeType;
		typedef Hash<Value, Value, MethodHasher, NodeType> HashType;

		HashType data;
	};

	struct Namespace : public GCObject
	{
		typedef HashNode<String*, Value> NodeType;
		typedef Hash<String*, Value, MethodHasher, NodeType> HashType;

		HashType data;
		Namespace* parent;
		Namespace* root;
		String* name;
		bool visitedOnce;
	};

	struct Array : public GCObject
	{
		struct Slot
		{
			Value value;
			bool modified;

			bool operator==(const Slot& other) const
			{
				return value == other.value;
			}
		};

		uword length;
		DArray<Slot> data;

		inline DArray<Slot> toArray()
		{
			return DArray<Slot>::n(data.ptr, length);
		}
	};

	struct Memblock : public GCObject
	{
		// acyclic
		DArray<uint8_t> data;
		bool ownData;
	};

	struct Function : public GCObject
	{
		bool isNative;
		Namespace* environment;
		String* name;
		uword numUpvals;
		uword numParams;
		uword maxParams;

		union
		{
			Funcdef* scriptFunc;
			CrocNativeFunc nativeFunc;

			// TODO:
			// static assert((CrocFuncdef*).sizeof == NativeFunc.sizeof);
		};

		inline DArray<Value>  nativeUpvals() const
		{
			return DArray<Value>::n(cast(Value*)(this + 1), numUpvals);
		}

		inline DArray<Upval*> scriptUpvals() const
		{
			return DArray<Upval*>::n(cast(Upval**)(this + 1), numUpvals);
		}
	};

	// The integral members of this struct are fixed at 32 bits for possible cross-platform serialization.
	struct Funcdef : public GCObject
	{
		String* locFile;
		int32_t locLine;
		int32_t locCol;
		bool isVararg;
		String* name;
		uint32_t numParams;
		DArray<uint32_t> paramMasks;
		uint32_t numUpvals;

		struct UpvalDesc
		{
			bool isUpval;
			uint32_t index;
		};

		DArray<UpvalDesc> upvals;
		uint32_t stackSize;
		DArray<Funcdef*> innerFuncs;
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
		DArray<String*> upvalNames;

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
		String* name;
		Class* parent;
		bool isFrozen;
		bool visitedOnce;
		FieldHash methods;
		FieldHash fields;
		FieldValue* constructor;
		FieldValue* finalizer;
	};

	struct Instance : public GCObject
	{
		Class* parent;
		bool visitedOnce;
		FieldHash fields;
	};

	struct Thread : public GCObject
	{
		// used by allThreads list
		Thread* next;
		Thread* prev;

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

		Upval* upvalHead;

		VM* vm;
		bool shouldHalt;

		Function* coroFunc;
		CrocThreadState state;
		uword numYields;

		uint8_t hooks;
		bool hooksEnabled;
		uint32_t hookDelay;
		uint32_t hookCounter;
		Function* hookFunc;

		uword savedCallDepth;
		uword nativeCallDepth;
	};

	struct Upval : public GCObject
	{
		Value* value;
		Value closedValue;
		Upval* nextuv;
	};

	struct VM
	{
		Memory mem;

		// These are all GC roots -----------
		Namespace* globals;
		Thread* mainThread;
		DArray<Namespace*> metaTabs;
		DArray<String*> metaStrings;
		Instance* exception;
		Namespace* registry;
		Hash<uint64_t, GCObject*> refTab;
		CrocThread* allThreads;

		// These point to "special" runtime classes
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
		Hash<GCObject*, Weakref*> weakrefTab;
		uint64_t currentRef;
		String* ctorString; // also stored in metaStrings, don't have to scan it as a root
		String* finalizerString; // also stored in metaStrings, don't have to scan it as a root
		Thread* curThread;
		bool isThrowing;
	};
}
#endif