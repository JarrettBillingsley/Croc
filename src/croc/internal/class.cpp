
#include "croc/api.h"
#include "croc/internal/basic.hpp"
#include "croc/internal/class.hpp"
#include "croc/types.hpp"

namespace croc
{
	void classDeriveImpl(Thread* t, Class* c, Class* base)
	{
		// This probably shouldn't happen under normal circumstances but maybe if it's made a library function?
		if(c->isFrozen)
			croc_eh_throwStd(*t, "StateError", "Attempting to derive classes into a frozen class");

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
			if(ctor->type != CrocType_Function)
			{
				pushTypeStringImpl(t, *ctor);
				croc_eh_throwStd(*t, "TypeError", "Class constructor must be of type 'function', not '%s'",
					croc_getString(*t, -1));
			}

			c->constructor = ctor;
		}

		if(auto finalizer = c->getMethod(t->vm->finalizerString))
		{
			if(finalizer->type != CrocType_Function)
			{
				pushTypeStringImpl(t, *finalizer);
				croc_eh_throwStd(*t, "TypeError", "Class finalizer must be of type 'function', not '%s'",
					croc_getString(*t, -1));
			}

			c->finalizer = finalizer;
		}

		c->freeze(t->vm->mem);
	}
}