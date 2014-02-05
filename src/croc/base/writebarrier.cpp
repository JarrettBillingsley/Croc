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
			for(auto n: o->data.modifiedNodes())
			{
				if(IS_KEY_MODIFIED(n))
					VALUE_CALLBACK(n->key);

				if(IS_VAL_MODIFIED(n))
					VALUE_CALLBACK(n->value);

				CLEAR_BOTH_MODIFIED(n);
			}
		}
		else
		{
			for(auto n: o->data)
			{
				VALUE_CALLBACK(n->key);
				VALUE_CALLBACK(n->value);
			}
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

			for(auto n: o->data.modifiedNodes())
			{
				if(IS_KEY_MODIFIED(n))
					COND_CALLBACK(n->key);

				if(IS_VAL_MODIFIED(n))
					VALUE_CALLBACK(n->value);

				CLEAR_BOTH_MODIFIED(n);
			}
		}
		else
		{
			COND_CALLBACK(o->parent);
			COND_CALLBACK(o->root);
			COND_CALLBACK(o->name);

			for(auto n: o->data)
			{
				callback(n->key);
				VALUE_CALLBACK(n->value);
			}
		}
	}

	void visitArray(Array* o, WBCallback callback, bool isModifyPhase)
	{
		auto vals = o->toDArray();

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

		for(auto &f: o->innerFuncs)
			COND_CALLBACK(f);

		for(auto &val: o->constants)
			VALUE_CALLBACK(val);

		for(auto &st: o->switchTables)
			for(auto n: st.offsets)
				VALUE_CALLBACK(n->key);

		for(auto &name: o->upvalNames)
			COND_CALLBACK(name);

		for(auto &desc: o->locVarDescs)
			COND_CALLBACK(desc.name);

		COND_CALLBACK(o->environment);
		COND_CALLBACK(o->cachedFunc);
	}

	void visitClass(Class* o, WBCallback callback, bool isModifyPhase)
	{
		if(isModifyPhase)
		{
			if(!o->visitedOnce)
			{
				o->visitedOnce = true;
				COND_CALLBACK(o->name);
			}

			for(auto n: o->fields.modifiedNodes())
			{
				COND_CALLBACK(n->key);
				VALUE_CALLBACK(n->value);
			}

			for(auto n: o->methods.modifiedNodes())
			{
				COND_CALLBACK(n->key);
				VALUE_CALLBACK(n->value);
			}

			for(auto n: o->hiddenFields.modifiedNodes())
			{
				COND_CALLBACK(n->key);
				VALUE_CALLBACK(n->value);
			}
		}
		else
		{
			COND_CALLBACK(o->name);

			for(auto n: o->fields)
			{
				COND_CALLBACK(n->key);
				VALUE_CALLBACK(n->value);
			}

			for(auto n: o->methods)
			{
				COND_CALLBACK(n->key);
				VALUE_CALLBACK(n->value);
			}

			for(auto n: o->hiddenFields)
			{
				COND_CALLBACK(n->key);
				VALUE_CALLBACK(n->value);
			}
		}
	}

	void visitInstance(Instance* o, WBCallback callback, bool isModifyPhase)
	{
		if(isModifyPhase)
		{
			if(!o->visitedOnce)
			{
				o->visitedOnce = true;
				COND_CALLBACK(o->parent);
			}

			for(auto n: o->fields.modifiedNodes())
			{
				COND_CALLBACK(n->key);
				VALUE_CALLBACK(n->value);
			}

			if(o->hiddenFields)
			{
				for(auto n: o->hiddenFields->modifiedNodes())
				{
					COND_CALLBACK(n->key);
					VALUE_CALLBACK(n->value);
				}
			}
		}
		else
		{
			COND_CALLBACK(o->parent);

			for(auto n: o->fields)
			{
				COND_CALLBACK(n->key);
				VALUE_CALLBACK(n->value);
			}

			if(o->hiddenFields)
			{
				for(auto n: *o->hiddenFields)
				{
					COND_CALLBACK(n->key);
					VALUE_CALLBACK(n->value);
				}
			}
		}
	}

	void visitThread(Thread* o, WBCallback callback, bool isRoots)
	{
		if(isRoots)
		{
			for(auto &ar: o->actRecs.slice(0, o->arIndex))
				COND_CALLBACK(ar.func);

			for(auto &val: o->stack.slice(0, o->stackIndex))
				VALUE_CALLBACK(val);

			// I guess this can't _hurt_..
			o->stack.slice(o->stackIndex, o->stack.length).fill(Value::nullValue);

			for(auto &val: o->results.slice(0, o->resultIndex))
				VALUE_CALLBACK(val);

			for(auto puv = &o->upvalHead; *puv != nullptr; puv = &(*puv)->nextuv)
				callback(cast(GCObject*)*puv);
		}
		else
		{
			COND_CALLBACK(o->coroFunc);
			COND_CALLBACK(o->hookFunc);
		}
	}

	void visitUpval(Upval* o, WBCallback callback)
	{
		VALUE_CALLBACK(*o->value);
	}

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

		for(auto mt: vm->metaTabs)
			COND_CALLBACK(mt);

		for(auto ms: vm->metaStrings)
			callback(ms);

		COND_CALLBACK(vm->exception);
		callback(vm->registry);
		callback(vm->unhandledEx);

		for(auto n: vm->refTab)
			callback(n->value);

		callback(vm->location);

		for(auto n: vm->stdExceptions)
		{
			callback(n->key);
			callback(n->value);
		}
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
				DBGPRINT("%p %d %03x %d\n", cast(void*)o, o->type, GCOBJ_COLOR(o), o->refCount);
				assert(false);
		}
	}
}