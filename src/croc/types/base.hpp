#ifndef CROC_TYPES_BASE_HPP
#define CROC_TYPES_BASE_HPP

#include <setjmp.h>
#include <stddef.h>

#include "croc/apitypes.h"
#include "croc/base/darray.hpp"
#include "croc/base/deque.hpp"
#include "croc/base/hash.hpp"
#include "croc/base/memory.hpp"
#include "croc/base/opcodes.hpp"
#include "croc/base/sanity.hpp"
#include "croc/util/rng.hpp"
#include "croc/util/utf.hpp"

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
	typedef DArray<const unsigned char> crocstr;
	typedef DArray<unsigned char> mcrocstr;

	const char* typeToString(CrocType type);

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
			if(this->type != other.type)
				return false;

			switch(this->type)
			{
				case CrocType_Null: return true;
				case CrocType_Bool: return this->mBool == other.mBool;
				case CrocType_Int: return this->mInt == other.mInt;
				case CrocType_Float: return this->mFloat == other.mFloat;
				default: return (this->mGCObj == other.mGCObj);
			}
		}

		inline bool operator!=(const Value& other) const
		{
			return !(*this == other);
		}

		inline bool isFalse() const
		{
			return
				(type == CrocType_Bool && mBool == false) ||
				(type == CrocType_Null) ||
				(type == CrocType_Int && mInt == 0) ||
				(type == CrocType_Float && mFloat == 0.0);
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

		static inline Value from(GCObject* v)
		{
			Value ret;
			ret.setGCObject(v);
			return ret;
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

		inline const unsigned char* toUString() const
		{
			return cast(const unsigned char*)(this + 1);
		}

		inline crocstr toDArray() const
		{
			return crocstr::n(toUString(), length);
		}

		inline void setData(crocstr data)
		{
			auto dst = DArray<char>::n(cast(char*)toCString(), length);
			auto src = DArray<char>::n(cast(char*)data.ptr, data.length);
			dst.slicea(src);
			(cast(char*)toCString())[length] = 0; // null terminate
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
		static String* tryCreate(VM* vm, crocstr data);
		static void free(VM* vm, String* s);
		crocint compare(String* other);
		bool contains(crocstr sub);
		String* slice(VM* vm, uword lo, uword hi);
	};

	struct Weakref : public GCObject
	{
		// acyclic
		GCObject* obj;

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
		inline bool contains(Value key)
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
		void idxa(Memory& mem, Value key, Value val);
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
		void set(Memory& mem, String* key, Value value);
		bool setIfExists(Memory& mem, String* key, Value value);
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
		bool contains(Value v);
		Array* cat(Memory& alloc, Array* other);
		Array* cat(Memory& alloc, Value v);
		void append(Memory& alloc, Value v);
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
		};

		inline DArray<Value> nativeUpvals() const
		{
			return DArray<Value>::n(cast(Value*)(this + 1), numUpvals);
		}

		inline DArray<Upval*> scriptUpvals() const
		{
			return DArray<Upval*>::n(cast(Upval**)(this + 1), numUpvals);
		}

		static Function* create(Memory& mem, Namespace* env, Funcdef* def);
		static Function* createPartial(Memory& mem, uword numUpvals);
		static void finishCreate(Memory& mem, Function* f, Namespace* env, Funcdef* def);
		static Function* create(Memory& mem, Namespace* env, String* name, uword numParams, CrocNativeFunc func, uword numUpvals);
		void setNativeUpval(Memory& mem, uword idx, Value val);
		void setEnvironment(Memory& mem, Namespace* ns);
		bool isVararg();
	};

	struct Funcdef : public GCObject
	{
		String* locFile;
		word locLine;
		word locCol;
		bool isVararg;
		String* name;
		uword numParams;
		DArray<uword> paramMasks;

		struct UpvalDesc
		{
			bool isUpval;
			uword index;
		};

		DArray<UpvalDesc> upvals;
		uword stackSize;
		DArray<Funcdef*> innerFuncs;
		DArray<Value> constants;
		DArray<Instruction> code;

		Namespace* environment;
		Function* cachedFunc;

		struct SwitchTable
		{
			typedef Hash<Value, word, MethodHasher> OffsetsType;
			OffsetsType offsets;
			word defaultOffset;
		};

		DArray<SwitchTable> switchTables;

		// Debug info.
		DArray<uword> lineInfo;
		DArray<String*> upvalNames;

		struct LocVarDesc
		{
			String* name;
			uword pcStart;
			uword pcEnd;
			uword reg;
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
		DArray<Array::Slot> frozenFields;
		DArray<Array::Slot> frozenHiddenFields;
		uword numInstanceFields;

		static Class* create(Memory& mem, String* name);
		static Class::HashType::NodeType* derive(Memory& mem, Class* c, Class* parent, const char*& which);
		static void free(Memory& mem, Class* c);
		void freeze(Memory& mem);

		Value* getField       (String* name);
		Value* getMethod      (String* name);
		Value* getHiddenField (String* name);
		bool setField         (Memory& mem, String* name, Value value);
		bool setMethod        (Memory& mem, String* name, Value value);
		bool setHiddenField   (Memory& mem, String* name, Value value);
		bool addField         (Memory& mem, String* name, Value value, bool isOverride);
		bool addMethod        (Memory& mem, String* name, Value value, bool isOverride);
		bool addHiddenField   (Memory& mem, String* name, Value value);
		bool removeField      (Memory& mem, String* name);
		bool removeMethod     (Memory& mem, String* name);
		bool removeHiddenField(Memory& mem, String* name);
		bool removeMember     (Memory& mem, String* name);
		bool nextField        (uword& idx, String**& key, Value*& val);
		bool nextMethod       (uword& idx, String**& key, Value*& val);
		bool nextHiddenField  (uword& idx, String**& key, Value*& val);
	};

	struct Instance : public GCObject
	{
		Class* parent;
		bool visitedOnce;
		// Points to parent->fields
		Class::HashType* fields;
		// If null, instance has no hidden fields. If not null, points to extra bytes allocated in instance where hidden
		// fields start (the index is looked up in parent->hiddenFields).
		Array::Slot* hiddenFieldsData;

		inline Value* getMethod(String* name)
		{
			return this->parent->getMethod(name);
		}

		inline Value* getField(String* name)
		{
			if(auto n = this->fields->lookupNode(name))
				return &(cast(Array::Slot*)(this + 1))[cast(uword)n->value.mInt].value;
			else
				return nullptr;
		}

		inline bool nextField(uword& idx, String**& key, Value*& val)
		{
			if(this->fields->next(idx, key, val))
			{
				val = &(cast(Array::Slot*)(this + 1))[cast(uword)val->mInt].value;
				return true;
			}

			return false;
		}

		inline Value* getHiddenField(String* name)
		{
			if(this->hiddenFieldsData)
			{
				if(auto n = this->parent->hiddenFields.lookupNode(name))
					return &this->hiddenFieldsData[cast(uword)n->value.mInt].value;
			}

			return nullptr;
		}

		inline bool nextHiddenField(uword& idx, String**& key, Value*& val)
		{
			if(this->hiddenFieldsData)
			{
				if(this->parent->hiddenFields.next(idx, key, val))
				{
					val = &this->hiddenFieldsData[cast(uword)val->mInt].value;
					return true;
				}
			}

			return false;
		}

		inline bool derivesFrom(Class* c)
		{
			return this->parent == c;
		}

		static Instance* create(Memory& mem, Class* parent);
		static Instance* createPartial(Memory& mem, uword size, bool finalizable);
		static bool finishCreate(Instance* i, Class* parent);
		bool setField(Memory& mem, String* name, Value value);
		bool setHiddenField(Memory& mem, String* name, Value value);
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
		word expectedResults;
		uword numTailcalls;
		AbsStack firstResult;
		uword numResults;
		uword unwindCounter;
		Instruction* unwindReturn;
	};

	struct ScriptEHFrame
	{
		uword actRecord;
		AbsStack slot;
		bool isCatch;
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

		DArray<ScriptEHFrame> ehFrames;
		ScriptEHFrame* currentEH;
		uword ehIndex;

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

		Thread* threadThatResumedThis;
		Function* coroFunc;
		CrocThreadState state;
		uword numYields;
		uword nativeCallDepth;
		uword savedStartARIndex;

		uint8_t hooks;
		bool hooksEnabled;
		uint32_t hookDelay;
		uint32_t hookCounter;
		Function* hookFunc;

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

	struct NativeEHFrame
	{
		Thread* t;
		uword actRecord;
		AbsStack slot;
		jmp_buf* jbuf;
	};

	enum EHStatus
	{
		EHStatus_Okay = 0,
		EHStatus_ScriptFrame = 1,
		EHStatus_NativeFrame = 2
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
		Function* unhandledEx;

		// These point to "special" runtime classes
		Class* location;
		Hash<String*, Class*> stdExceptions;
		// ----------------------------------

		// GC stuff
		uint8_t oldRootIdx;
		Deque roots[2];
		Deque cycleRoots;
		Deque toFree;
		Deque toFinalize;
		bool inGCCycle;

		// EH stuff
		DArray<NativeEHFrame> ehFrames;
		NativeEHFrame* currentEH;
		uword ehIndex;

		// Others
		Hash<crocstr, String*, MethodHasher, HashNodeWithHash<crocstr, String*> > stringTab;
		Hash<GCObject*, Weakref*> weakrefTab;
		Thread* allThreads;
		Thread* curThread;
		uint64_t currentRef;
		String* ctorString; // also stored in metaStrings, don't have to scan it as a root
		String* finalizerString; // also stored in metaStrings, don't have to scan it as a root
		unsigned char formatBuf[CROC_FORMAT_BUF_SIZE];
		RNG rng;

		inline void disableGC() { this->mem.gcDisabled++; }
		inline void enableGC()
		{
			this->mem.gcDisabled--;
			assert(this->mem.gcDisabled != cast(size_t)-1);
		}
	};
}
#endif