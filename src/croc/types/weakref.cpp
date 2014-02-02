
#include "croc/base/writebarrier.hpp"
#include "croc/types/weakref.hpp"

namespace croc
{
	namespace weakref
	{
		// Create a new weakref object. Weak reference objects that refer to the same object are reused. Thus,
		// if two weak references are identical, they refer to the same object.
		Weakref* create(VM* vm, GCObject* obj)
		{
			if(auto r = vm->weakrefTab.lookup(obj))
				return *r;

			auto ret = ALLOC_OBJ(vm->mem, Weakref);
			ret->obj = obj;
			*vm->weakrefTab.insert(vm->mem, obj) = ret;
			return ret;
		}

		Value makeref(VM* vm, Value val)
		{
			if(val.isValType() || val.type == CrocType_Upval)
				return val;
			else
				return Value::from(create(vm, val.mGCObj));
		}

		// Free a weak reference object.
		void free(VM* vm, Weakref* r)
		{
			if(r->obj != nullptr)
			{
				auto b = vm->weakrefTab.remove(r->obj);
				assert(b);
			}

			FREE_OBJ(vm->mem, Weakref, r);
		}

		GCObject* getObj(Weakref* r)
		{
			return r->obj;
		}
	}
}