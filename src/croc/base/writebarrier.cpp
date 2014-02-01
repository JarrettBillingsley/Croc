#include <functional>

#include "croc/base/writebarrier.hpp"
#include "croc/base/memory.hpp"
#include "croc/base/sanity.hpp"

namespace croc
{
	void writeBarrierSlow(Memory& mem, GCObject* srcObj)
	{
		mem.modBuffer.add(mem, srcObj);

		visitObj(srcObj, false, [&](GCObject* slot)
		{
			if(GCOBJ_INRC(slot))
				mem.decBuffer.add(mem, slot);
		});

		GCOBJ_LOG(srcObj);
	}

// For visiting CrocValues. Visits it only if it's an object.
#define VALUE_CALLBACK(name)\
	{if((name).isGCObject())\
	{\
		callback((name).toGCObject());\
	}}

// For visiting pointers. Visits it only if it's non-null.
#define COND_CALLBACK(name)\
	{if((name) != nullptr)\
	{\
		callback((name));\
	}}

	namespace
	{
	void visitTable(Table* o, WBCallback callback, bool isModifyPhase)
	{
		if(isModifyPhase)
		{
			HASH_FOREACH_MODIFIED(Table::HashType::NodeType, n, o->data)
			{
				if(IS_KEY_MODIFIED(n))
					VALUE_CALLBACK(n->key);

				if(IS_VAL_MODIFIED(n))
					VALUE_CALLBACK(n->value);

				CLEAR_BOTH_MODIFIED(n);
			}
			HASH_END_FOREACH
		}
		else
		{
			HASH_FOREACH(Value, key, Value, val, o->data)
			{
				VALUE_CALLBACK(*key);
				VALUE_CALLBACK(*val);
			}
			HASH_END_FOREACH
		}
	}

	void visitNamespace(Namespace* o, WBCallback callback, bool isModifyPhase)
	{
		if(isModifyPhase)
		{
			// These two slots are only set once, when the namespace is first created, and are never touched again,
			// so we only have to visit them once
			if(!o->visitedOnce)
			{
				o->visitedOnce = true;
				COND_CALLBACK(o->parent);
				COND_CALLBACK(o->root);
				COND_CALLBACK(o->name);
			}

			HASH_FOREACH_MODIFIED(Namespace::HashType::NodeType, n, o->data)
			{
				if(IS_KEY_MODIFIED(n))
					COND_CALLBACK(n->key);

				if(IS_VAL_MODIFIED(n))
					VALUE_CALLBACK(n->value);

				CLEAR_BOTH_MODIFIED(n);
			}
			HASH_END_FOREACH
		}
		else
		{
			COND_CALLBACK(o->parent);
			COND_CALLBACK(o->root);
			COND_CALLBACK(o->name);

			HASH_FOREACH(String*, key, Value, val, o->data)
			{
				callback(*key);
				VALUE_CALLBACK(*val);
			}
			HASH_END_FOREACH
		}
	}

	void visitArray(Array* o, WBCallback callback, bool isModifyPhase)
	{
		auto vals = o->toArray();

		if(isModifyPhase)
		{
			for(size_t i = 0; i < vals.length; i++)
			{
				if(!vals[i].modified)
					continue;

				VALUE_CALLBACK(vals[i].value);
				vals[i].modified = false;
			}
		}
		else
		{
			for(size_t i = 0; i < vals.length; i++)
				VALUE_CALLBACK(vals[i].value);
		}
	}

	void visitFunction(Function* o, WBCallback callback)
	{
		COND_CALLBACK(o->environment);
		COND_CALLBACK(o->name);

		if(o->isNative)
		{
			DArray<Value> uvs = o->nativeUpvals();

			for(size_t i = 0; i < uvs.length; i++)
				VALUE_CALLBACK(uvs[i]);
		}
		else
		{
			COND_CALLBACK(o->scriptFunc);

			DArray<Upval*> uvs = o->scriptUpvals();

			for(size_t i = 0; i < uvs.length; i++)
				COND_CALLBACK(uvs[i]);
		}
	}

	void visitFuncDef(Funcdef* o, WBCallback callback)
	{
		COND_CALLBACK(o->locFile);
		COND_CALLBACK(o->name);

		ARRAY_FOREACHP(Funcdef*, f, o->innerFuncs)
			COND_CALLBACK(*f);

		ARRAY_FOREACH(Value, val, o->constants)
			VALUE_CALLBACK(*val);

		ARRAY_FOREACH(Funcdef::SwitchTable, st, o->switchTables)
		{
			auto offsets = st->offsets;

			HASH_FOREACH_NODE(Funcdef::SwitchTable::OffsetsType::NodeType, n, offsets)
				VALUE_CALLBACK(n->key);
			HASH_END_FOREACH
		}

		ARRAY_FOREACHP(String*, name, o->upvalNames)
			COND_CALLBACK(*name);

		ARRAY_FOREACH(Funcdef::LocVarDesc, desc, o->locVarDescs)
			COND_CALLBACK(desc->name);

		COND_CALLBACK(o->environment);
		COND_CALLBACK(o->cachedFunc);
	}

	void visitClass(Class*, WBCallback, bool);
	void visitInstance(Instance*, WBCallback, bool);
	void visitThread(Thread*, WBCallback, bool);
	void visitUpval(Upval*, WBCallback);

	} // anon namespace

	// Visit the roots of this VM.
	void visitRoots(VM* vm, WBCallback callback)
	{
		callback(vm->globals);
		callback(vm->mainThread);

		// We visit all the threads, but the threads themselves (except the main thread, visited above) are not roots.
		// allThreads is basically a list of weakrefs to tables.
		for(Thread* t = vm->allThreads; t != nullptr; t = t->next)
			visitThread(t, callback, true);

		DArray<Namespace*>& mt = vm->metaTabs;
		size_t i;

		for(i = 0; i < mt.length; i++)
			COND_CALLBACK(mt[i]);

		DArray<String*>& ms = vm->metaStrings;

		for(i = 0; i < ms.length; i++)
			callback(ms[i]);

		if(vm->isThrowing)
			callback(vm->exception);

		callback(vm->registry);

		VM::RefTab& rt = vm->refTab;

		HASH_FOREACH(uint64_t, _, GCObject*, val, rt)
			callback(*val);
		HASH_END_FOREACH

		callback(vm->location);

		VM::ExTab& et = vm->stdExceptions;

		HASH_FOREACH(String*, k, Class*, v, et)
		{
			callback(*k);
			callback(*v);
		}
		HASH_END_FOREACH
	}

	// Dynamically dispatch the appropriate visiting method at runtime from a GCObject*.
	void visitObj(GCObject* o, bool isModifyPhase, WBCallback callback)
	{
		// Green objects have no references to other objects.
		if(GCOBJ_COLOR(o) == GCFlags_Green)
			return;

		switch(o->type)
		{
			case CrocType_Table:     visitTable    (cast(Table*)o,     callback, isModifyPhase); return;
			case CrocType_Namespace: visitNamespace(cast(Namespace*)o, callback, isModifyPhase); return;
			case CrocType_Array:     visitArray    (cast(Array*)o,     callback, isModifyPhase); return;
			case CrocType_Function:  visitFunction (cast(Function*)o,  callback);                return;
			case CrocType_Funcdef:   visitFuncDef  (cast(Funcdef*)o,   callback);                return;
			case CrocType_Class:     visitClass    (cast(Class*)o,     callback, isModifyPhase); return;
			case CrocType_Instance:  visitInstance (cast(Instance*)o,  callback, isModifyPhase); return;
			case CrocType_Thread:    visitThread   (cast(Thread*)o,    callback, false);         return;
			case CrocType_Upval:     visitUpval    (cast(Upval*)o,     callback);                return;
			default:
				//debug Stdout.formatln("{} {:b} {}", (cast(CrocBaseObject*)o).mType, o.gcflags & GCFlags.ColorMask, o.refCount).flush;
				assert(false);
		}
	}
}