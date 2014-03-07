
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/basic.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
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

	word_t croc_namespace_new(CrocThread* t_, const char* name)
	{
		auto t = Thread::from(t_);
		return newNamespaceInternal(t, name, getEnv(t));
	}

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

	word_t croc_namespace_newNoParent(CrocThread* t_, const char* name)
	{
		auto t = Thread::from(t_);
		return newNamespaceInternal(t, name, nullptr);
	}

	void croc_namespace_clear(CrocThread* t_, word_t ns_)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ns, ns_, Namespace, "ns");
		ns->clear(t->vm->mem);
	}

	const char* croc_namespace_getName(CrocThread* t_, word_t ns_)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ns, ns_, Namespace, "ns");
		return ns->name->toCString();
	}

	const char* croc_namespace_getNamen(CrocThread* t_, word_t ns_, uword_t* len)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ns, ns_, Namespace, "ns");
		*len = ns->name->length;
		return ns->name->toCString();
	}

	word_t croc_namespace_pushFullName(CrocThread* t_, word_t ns_)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ns, ns_, Namespace, "ns");
		return pushFullNamespaceName(t, ns);
	}
}
}