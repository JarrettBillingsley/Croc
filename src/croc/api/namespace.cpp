
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/basic.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	namespace
	{
		word_t newNamespaceInternal(Thread* t, const char* name, Namespace* parent)
		{
			croc_gc_maybeCollect(*t);
			return push(t, Value::from(Namespace::create(t->vm->mem, String::create(t->vm, atoda(name)), parent)));
		}
	}

	/** Creates and pushes a new namespace object whose parent namespace will be set to the current function's
	environment (or the global namespace if there is no current function).

	This is the same behavior as <tt>namespace name {}</tt> in Croc (though it doesn't actually declare the namespace;
	you'll have to store it somewhere, like in a global).

	\param name is the name that the namespace will be given.
	\returns the stack index of the pushed value. */
	word_t croc_namespace_new(CrocThread* t_, const char* name)
	{
		auto t = Thread::from(t_);
		return newNamespaceInternal(t, name, getEnv(t));
	}

	/** Creates and pushes a new namespace object whose parent is in slot \c parent.

	\param parent should be either a namespace or null, in which case the new namespace will have no parent.
	\param name is the name that the namespace will be given.
	\returns the stack index of the pushed value. */
	word_t croc_namespace_newWithParent(CrocThread* t_, word_t parent, const char* name)
	{
		auto t = Thread::from(t_);

		if(croc_isNull(t_, parent))
			return newNamespaceInternal(t, name, nullptr);
		else if(croc_isNamespace(t_, parent))
			return newNamespaceInternal(t, name, getNamespace(t, parent));
		else
			API_PARAM_TYPE_ERROR(parent, "parent", "null|namespace");

		assert(false);
		return 0; // dummy
	}

	/** Creates and pushes a new namespace object without a parent.

	\param name is the name that the namespace will be given.
	\returns the stack index of the pushed value. */
	word_t croc_namespace_newNoParent(CrocThread* t_, const char* name)
	{
		auto t = Thread::from(t_);
		return newNamespaceInternal(t, name, nullptr);
	}

	/** Removes all key-value pairs from the namespace in slot \c ns. */
	void croc_namespace_clear(CrocThread* t_, word_t ns)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(n, ns, Namespace, "ns");
		n->clear(t->vm->mem);
	}

	/** Pushes the "full name" of the namespace in slot \c ns, which is the name of the namespace and all its parents,
	separated by dots.

	\returns the stack index of the pushed value. */
	word_t croc_namespace_pushFullName(CrocThread* t_, word_t ns)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(n, ns, Namespace, "ns");
		return pushFullNamespaceName(t, n);
	}
}