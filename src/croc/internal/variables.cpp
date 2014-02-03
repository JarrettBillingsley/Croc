
#include "croc/internal/variables.hpp"
#include "croc/types.hpp"

namespace croc
{
	Value* getGlobalImpl(Thread* t, String* name, Namespace* env)
	{
		if(auto glob = env->get(name))
			return glob;

		if(env->root)
		{
			if(auto glob = env->root->get(name))
				return glob;
		}

		// TODO:ex
		(void)t;
		// throwStdException(t, "NameError", "Attempting to get a nonexistent global '{}'", name.toString());
		assert(false);
	}

	void setGlobalImpl(Thread* t, String* name, Namespace* env, Value* val)
	{
		if(env->setIfExists(t->vm->mem, name, val))
			return;

		if(env->root && env->root->setIfExists(t->vm->mem, name, val))
			return;

		// TODO:ex
		// throwStdException(t, "NameError", "Attempting to set a nonexistent global '{}'", name.toString());
		assert(false);
	}

	void newGlobalImpl(Thread* t, String* name, Namespace* env, Value* val)
	{
		if(env->contains(name))
			assert(false); // TODO:ex
			// throwStdException(t, "NameError", "Attempting to create global '{}' that already exists", name.toString());

		env->set(t->vm->mem, name, val);
	}
}