
#include "croc/api.h"
#include "croc/internal/basic.hpp"
#include "croc/internal/class.hpp"
#include "croc/types.hpp"

namespace croc
{
	void classDeriveImpl(Thread* t, Class* c, Class* base)
	{
		freezeImpl(t, base);

		if(base->finalizer)
			croc_eh_throwStd(*t, "ValueError", "Attempting to derive from class '%s' which has a finalizer",
				base->name->toCString());

		const char* which;

		if(auto conflict = Class::derive(t->vm->mem, c, base, which))
		{
			croc_eh_throwStd(*t, "ValueError",
				"Attempting to derive %s '%s' from class '%s', but it already exists in the new class '%s'",
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
				croc_eh_throwStd(*t, "TypeError", "Class constructor must be of type 'function', not '%s'",
					croc_getString(*t, -1));
			}

			c->constructor = &ctor->value;
		}

		if(auto finalizer = c->getMethod(t->vm->finalizerString))
		{
			if(finalizer->value.type != CrocType_Function)
			{
				pushTypeStringImpl(t, finalizer->value);
				croc_eh_throwStd(*t, "TypeError", "Class finalizer must be of type 'function', not '%s'",
					croc_getString(*t, -1));
			}

			c->finalizer = &finalizer->value;
		}

		c->freeze();
	}
}