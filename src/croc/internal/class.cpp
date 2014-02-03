
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
			// TODO:ex
			(void)t;
			// typeString(t, v);
			// throwStdException(t, "TypeError", "Can only get super of classes, instances, and namespaces, not values of type '{}'", getString(t, -1));
		}

		assert(false);
	}

	void classDeriveImpl(Thread* t, Class* c, Class* base)
	{
		freezeImpl(t, base);

		if(base->finalizer)
			assert(false); // TODO:ex
			// throwStdException(t, "ValueError", "Attempting to derive from class '{}' which has a finalizer", base.name.toString());

		const char* which;

		if(auto conflict = Class::derive(t->vm->mem, c, base, which))
		{
			(void)conflict;
			assert(false); // TODO:ex
			// throwStdException(t, "ValueError", "Attempting to derive {} '{}' from class '{}', but it already exists in the new class '{}'",
			// 	which, conflict.key.toString(), base.name.toString(), c.name.toString());
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
				assert(false); // TODO:ex
				// typeString(t, &ctor.value);
				// throwStdException(t, "TypeError", "Class constructor must be of type 'function', not '{}'", getString(t, -1));
			}

			c->constructor = &ctor->value;
		}

		if(auto finalizer = c->getMethod(t->vm->finalizerString))
		{
			if(finalizer->value.type != CrocType_Function)
			{
				assert(false); // TODO:ex
				// typeString(t, &finalizer.value);
				// throwStdException(t, "TypeError", "Class finalizer must be of type 'function', not '{}'", getString(t, -1));
			}

			c->finalizer = &finalizer->value;
		}

		c->freeze();
	}
}