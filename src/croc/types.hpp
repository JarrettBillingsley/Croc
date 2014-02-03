#ifndef CROC_TYPES_HPP
#define CROC_TYPES_HPP

#include <stddef.h>

#include "croc/apitypes.h"
#include "croc/base/darray.hpp"
#include "croc/base/deque.hpp"
#include "croc/base/hash.hpp"
#include "croc/base/memory.hpp"
#include "croc/base/opcodes.hpp"
#include "croc/base/sanity.hpp"
#include "croc/utf.hpp"

namespace croc
{
	// ========================================
	// Basic poops

	// Convenience aliases
	typedef ptrdiff_t word;
	typedef size_t uword;
	typedef crocint_t crocint;
	typedef crocfloat_t crocfloat;
	typedef DArray<const char> crocstr;

	enum CrocLocation
	{
		CrocLocation_Unknown = 0,
		CrocLocation_Native = -1,
		CrocLocation_Script = -2
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
			return type == CrocType_Null || (type <= CrocType_Float && mInt == 0); // NONPORTABLE
		}

		hash_t toHash() const;

		// ORDER CROCTYPE
		inline bool isValType() const { return type <  CrocType_FirstRefType; }

		// ORDER CROCTYPE
		inline bool isRefType() const { return type >= CrocType_FirstRefType; }

		// ORDER CROCTYPE
		inline bool isGCObject() const { return type >= CrocType_FirstGCType; }

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
		static inline Value from(nativetype v)\
		{\
			Value ret;\
			ret.set(v);\
			return ret;\
		}\
		\
		inline void set(nativetype v)\
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

		inline const char* toCString() const
		{
			return cast(const char*)(this + 1);
		}

		inline crocstr toDArray() const
		{
			return crocstr::n(toCString(), length);
		}

		inline void setData(crocstr src)
		{
			DArray<char>::n(cast(char*)toCString(), length).slicea(DArray<char>::n(cast(char*)src.ptr, src.length));
		}

		inline hash_t toHash() const
		{
			return hash;
		}

		// The index is in codepoints, not byte indices.
		inline dchar charAt(uword idx)
		{
			return utf8CharAt(this->toDArray(), idx);
		}

		static String* create(VM* vm, crocstr data);
		static String* createUnverified(VM* vm, crocstr data, uword cpLen);
		static void free(VM* vm, String* s);
		crocint compare(String* other);
		bool contains(crocstr sub);
		String* slice(VM* vm, uword lo, uword hi);
	};

	struct Weakref : public GCObject
	{
		// acyclic
		GCObject* obj;

		inline GCObject* getObj()
		{
			return this->obj;
		}

		static Weakref* create(VM* vm, GCObject* obj);
		static Value makeref(VM* vm, Value val);
		static void free(VM* vm, Weakref* r);
	};

	struct Table : public GCObject
	{
		typedef Hash<Value, Value, MethodHasher> HashType;

		HashType data;

		// Get a pointer to the value of a key-value pair, or null if it doesn't exist.
		inline Value* get(Value key)
		{
			return this->data.lookup(key);
		}

		// Returns `true` if the key exists in the table.
		inline bool contains(Value& key)
		{
			return this->data.lookup(key) != nullptr;
		}

		// Get the number of key-value pairs in the table.
		inline uword length()
		{
			return this->data.length();
		}

		inline bool next(size_t& idx, Value*& key, Value*& val)
		{
			return this->data.next(idx, key, val);
		}

		static Table* create(Memory& mem, uword size = 0);
		static void free(Memory& mem, Table* t);
		Table* dup(Memory& mem);
		void idxa(Memory& mem, Value& key, Value& val);
		void clear(Memory& mem);
	};

	struct Namespace : public GCObject
	{
		typedef Hash<String*, Value> HashType;

		HashType data;
		Namespace* parent;
		Namespace* root;
		String* name;
		bool visitedOnce;

		// Get a pointer to the value of a key-value pair, or null if it doesn't exist.
		inline Value* get(String* key)
		{
			return this->data.lookup(key);
		}

		// Returns `true` if the key exists in the table.
		inline bool contains(String* key)
		{
			return this->data.lookup(key) != nullptr;
		}

		inline bool next(uword& idx, String**& key, Value*& val)
		{
			return this->data.next(idx, key, val);
		}

		inline uword length()
		{
			return this->data.length();
		}

		static Namespace* create(Memory& mem, String* name, Namespace* parent = nullptr);
		static Namespace* createPartial(Memory& mem);
		static void finishCreate(Namespace* ns, String* name, Namespace* parent);
		static void free(Memory& mem, Namespace* ns);
		void set(Memory& mem, String* key, Value* value);
		bool setIfExists(Memory& mem, String* key, Value* value);
		void remove(Memory& mem, String* key);
		void clear(Memory& mem);
	};

	struct Array : public GCObject
	{
		struct Slot
		{
			Value value;
			bool modified;
			inline bool operator==(const Slot& other) const { return value == other.value; }
		};

		uword length;
		DArray<Slot> data;

		inline DArray<Slot> toDArray()
		{
			return DArray<Slot>::n(data.ptr, length);
		}

		static Array* create(Memory& alloc, uword size);
		static void free(Memory& alloc, Array* a);

		void resize(Memory& alloc, uword newSize);
		Array* slice(Memory& alloc, uword lo, uword hi);
		void sliceAssign(Memory& alloc, uword lo, uword hi, Array* other);
		void sliceAssign(Memory& alloc, uword lo, uword hi, DArray<Value> other);
		void setBlock(Memory& alloc, uword block, DArray<Value> data);
		void fill(Memory& alloc, Value val);
		void idxa(Memory& alloc, uword idx, Value val);
		bool contains(Value& v);
		Array* cat(Memory& alloc, Array* other);
		Array* cat(Memory& alloc, Value* v);
		void append(Memory& alloc, Value* v);
	};

	struct Memblock : public GCObject
	{
		// acyclic
		DArray<uint8_t> data;
		bool ownData;

		static Memblock* create(Memory& mem, uword itemLength);
		static Memblock* createView(Memory& mem, DArray<uint8_t> data);
		static void free(Memory& mem, Memblock* m);
		void view(Memory& mem, DArray<uint8_t> data);
		void resize(Memory& mem, uword newLength);
		Memblock* slice(Memory& mem, uword lo, uword hi);
		void sliceAssign(uword lo, uword hi, Memblock* other);
		Memblock* cat(Memory& mem, Memblock* other);
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

		inline DArray<Value> nativeUpvals() const
		{
			return DArray<Value>::n(cast(Value*)(this + 1), numUpvals);
		}

		inline DArray<Upval*> scriptUpvals() const
		{
			return DArray<Upval*>::n(cast(Upval**)(this + 1), numUpvals);
		}

		// inline bool isNative()
		// {
		// 	return this->isNative;
		// }

		static Function* create(Memory& mem, Namespace* env, Funcdef* def);
		static Function* createPartial(Memory& mem, uword numUpvals);
		static void finishCreate(Memory& mem, Function* f, Namespace* env, Funcdef* def);
		static Function* create(Memory& mem, Namespace* env, String* name, CrocNativeFunc func, uword numUpvals, uword numParams);
		void setNativeUpval(Memory& mem, uword idx, Value* val);
		void setEnvironment(Memory& mem, Namespace* ns);
		bool isVararg();
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
			typedef Hash<Value, int32_t, MethodHasher> OffsetsType;
			OffsetsType offsets;
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

		static Funcdef* create(Memory& mem);
		static void free(Memory& mem, Funcdef* fd);
	};

	struct Class : public GCObject
	{
		typedef Hash<String*, Value> HashType;

		String* name;
		bool isFrozen;
		bool visitedOnce;
		HashType methods;
		HashType fields;
		HashType hiddenFields;
		Value* constructor;
		Value* finalizer;

		static Class* create(Memory& mem, String* name);
		static Class::HashType::NodeType* derive(Memory& mem, Class* c, Class* parent, const char*& which);
		static void free(Memory& mem, Class* c);

		void freeze();
		Class::HashType::NodeType* getField(String* name);
		Class::HashType::NodeType* getMethod(String* name);
		Class::HashType::NodeType* getHiddenField(String* name);
		void setMember(Memory& mem, Class::HashType::NodeType* slot, Value* value);
		bool addField(Memory& mem, String* name, Value* value, bool isOverride);
		bool addMethod(Memory& mem, String* name, Value* value, bool isOverride);
		bool addHiddenField(Memory& mem, String* name, Value* value);
		bool removeField(Memory& mem, String* name);
		bool removeMethod(Memory& mem, String* name);
		bool removeHiddenField(Memory& mem, String* name);
		bool removeMember(Memory& mem, String* name);
		bool nextField(uword& idx, String**& key, Value*& val);
		bool nextMethod(uword& idx, String**& key, Value*& val);
		bool nextHiddenField(uword& idx, String**& key, Value*& val);
	};

	struct Instance : public GCObject
	{
		Class* parent;
		bool visitedOnce;
		Class::HashType fields;
		// The way this works is that it's null to mean there are no hidden fields, and if it's not null, the Hash structure
		// and its data are appended to the end of the instance, and this points to that structure.
		Class::HashType* hiddenFields;

		inline Class::HashType::NodeType* getField(String* name)
		{
			return this->fields.lookupNode(name);
		}

		inline Class::HashType::NodeType* getMethod(String* name)
		{
			return this->parent->getMethod(name);
		}

		inline bool nextField(Instance* i, uword& idx, String**& key, Value*& val)
		{
			return i->fields.next(idx, key, val);
		}

		inline Class::HashType::NodeType* getHiddenField(Instance* i, String* name)
		{
			if(i->hiddenFields)
				return i->hiddenFields->lookupNode(name);
			else
				return nullptr;
		}

		inline bool nextHiddenField(Instance* i, uword& idx, String**& key, Value*& val)
		{
			if(i->hiddenFields)
				return i->hiddenFields->next(idx, key, val);
			else
				return false;
		}

		inline bool derivesFrom(Instance* i, Class* c)
		{
			return i->parent == c;
		}

		static Instance* create(Memory& mem, Class* parent);
		static Instance* createPartial(Memory& mem, uword size, bool finalizable);
		static bool finishCreate(Instance* i, Class* parent);
		void setField(Memory& mem, Class::HashType::NodeType* slot, Value* value);
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

	struct Thread : public GCObject
	{
		static inline Thread* from(CrocThread* t) { return cast(Thread*)t; }

		inline operator CrocThread* () const { return cast(CrocThread*)this; }

		// weak references used in the VM's allThreads list
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

		static Thread* create(VM* vm);
		static Thread* createPartial(VM* vm);
		static Thread* create(VM* vm, Function* coroFunc);
		static void free(Thread* t);
		void reset();
		void setHookFunc(Memory& mem, Function* f);
		void setCoroFunc(Memory& mem, Function* f);
	};

	struct Upval : public GCObject
	{
		Value* value;
		Value closedValue;
		Upval* nextuv;
	};

	struct VM
	{
		typedef Hash<uint64_t, GCObject*> RefTab;
		typedef Hash<String*, Class*> ExTab;

		Memory mem;

		// These are all GC roots -----------
		Namespace* globals;
		Thread* mainThread;
		DArray<Namespace*> metaTabs;
		DArray<String*> metaStrings;
		Instance* exception;
		Namespace* registry;
		RefTab refTab;

		// These point to "special" runtime classes
		Class* location;
		ExTab stdExceptions;
		// ----------------------------------

		// GC stuff
		uint8_t oldRootIdx;
		Deque roots[2];
		Deque cycleRoots;
		Deque toFree;
		Deque toFinalize;
		bool inGCCycle;

		// Others
		Hash<crocstr, String*, MethodHasher, HashNodeWithHash<crocstr, String*> > stringTab;
		Hash<GCObject*, Weakref*> weakrefTab;
		Thread* allThreads;
		uint64_t currentRef;
		String* ctorString; // also stored in metaStrings, don't have to scan it as a root
		String* finalizerString; // also stored in metaStrings, don't have to scan it as a root
		Thread* curThread;
		bool isThrowing;

		inline void disableGC() { this->mem.gcDisabled++; }
		inline void enableGC()
		{
			this->mem.gcDisabled--;
			assert(this->mem.gcDisabled != cast(size_t)-1);
		}
	};
}
#endif