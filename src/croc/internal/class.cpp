
#include "croc/api.h"
#include "croc/internal/basic.hpp"
#include "croc/internal/class.hpp"
#include "croc/types.hpp"

namespace croc
{
	Value superOfImpl(Thread* t, Value v)
	{
		if(v.type == CrocType_Instance)
			return Value::from(v.mInstance->parent);
		else if(v.type == CrocType_Namespace)
		{
			if(auto p = v.mNamespace->parent)
				return Value::from(p);
			else
				return Value::nullValue;
		}
		else
		{
			pushTypeStringImpl(t, v);
			croc_eh_throwStd(*t, "TypeError",
				"Can only get super of classes, instances, and namespaces, not values of type '{}'",
				croc_getString(*t, -1));
		}

		assert(false);
	}

	void classDeriveImpl(Thread* t, Class* c, Class* base)
	{
		freezeImpl(t, base);

		if(base->finalizer)
			croc_eh_throwStd(*t, "ValueError", "Attempting to derive from class '{}' which has a finalizer",
				base->name->toCString());

		const char* which;

		if(auto conflict = Class::derive(t->vm->mem, c, base, which))
		{
			croc_eh_throwStd(*t, "ValueError",
				"Attempting to derive {} '{}' from class '{}', but it already exists in the new class '{}'",
				which, conflict->key->toCString(), base->name->toCString(), c->name->toCString());
		}
	}

	void freezeImpl(Thread* t, Class* c)
	{
		if(c->isFrozen)
			return;

		if(auto ctor = c->getMethod(t->vm->ctorString))
		{
			if(ctor->value.type != CrocType_Function)
			{
				pushTypeStringImpl(t, ctor->value);
				croc_eh_throwStd(*t, "TypeError", "Class constructor must be of type 'function', not '{}'",
					croc_getString(*t, -1));
			}

			c->constructor = &ctor->value;
		}

		if(auto finalizer = c->getMethod(t->vm->finalizerString))
		{
			if(finalizer->value.type != CrocType_Function)
			{
				pushTypeStringImpl(t, finalizer->value);
				croc_eh_throwStd(*t, "TypeError", "Class finalizer must be of type 'function', not '{}'",
					croc_getString(*t, -1));
			}

			c->finalizer = &finalizer->value;
		}

		c->freeze();
	}
}