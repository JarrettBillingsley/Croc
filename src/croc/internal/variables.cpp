
#include "croc/api.h"
#include "croc/internal/variables.hpp"
#include "croc/types.hpp"

namespace croc
{
	Value getGlobalImpl(Thread* t, String* name, Namespace* env)
	{
		if(auto glob = env->get(name))
			return *glob;

		if(env->root)
		{
			if(auto glob = env->root->get(name))
				return *glob;
		}

		croc_eh_throwStd(*t, "NameError", "Attempting to get a nonexistent global '{}'", name->toCString());
		assert(false);
	}

	void setGlobalImpl(Thread* t, String* name, Namespace* env, Value val)
	{
		if(env->setIfExists(t->vm->mem, name, val))
			return;

		if(env->root && env->root->setIfExists(t->vm->mem, name, val))
			return;

		croc_eh_throwStd(*t, "NameError", "Attempting to set a nonexistent global '{}'", name->toCString());
		assert(false);
	}

	void newGlobalImpl(Thread* t, String* name, Namespace* env, Value val)
	{
		if(env->contains(name))
			croc_eh_throwStd(*t, "NameError", "Attempting to create global '{}' that already exists", name->toCString());

		env->set(t->vm->mem, name, val);
	}
}