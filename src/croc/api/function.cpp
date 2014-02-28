
#include "croc/api.h"
#include "croc/internal/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

namespace croc
{
extern "C"
{
	word_t croc_function_newWithEnv(CrocThread* t_, const char* name, word_t maxParams, CrocNativeFunc func, uword_t numUpvals)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(numUpvals + 1);
		API_CHECK_PARAM(env, -1, Namespace, "environment");
		croc_gc_maybeCollect(t_);

		if(maxParams < 0)
			maxParams = -2;

		auto f = Function::create(t->vm->mem, env, String::create(t->vm, atoda(name)), maxParams, func, numUpvals);
		f->nativeUpvals().slicea(t->stack.slice(t->stackIndex - 1 - numUpvals, t->stackIndex - 1));
		croc_pop(t_, numUpvals + 1); // upvals and env.
		return push(t, Value::from(f));
	}

	word_t croc_function_newScript(CrocThread* t_, word_t funcdef)
	{
		funcdef = croc_absIndex(t_, funcdef);
		croc_pushCurEnvironment(t_);
		return croc_function_newScriptWithEnv(t_, funcdef);
	}

	word_t croc_function_newScriptWithEnv(CrocThread* t_, word_t funcdef)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		funcdef = croc_absIndex(t_, funcdef);
		API_CHECK_PARAM(def, funcdef, Funcdef, "funcdef");

		if(def->upvals.length > 0)
			croc_eh_throwStd(t_, "ValueError", "%s - Function definition may not have any upvalues", __FUNCTION__);

		API_CHECK_PARAM(env, -1, Namespace, "environment");
		croc_gc_maybeCollect(t_);

		if(auto ret = Function::create(t->vm->mem, env, def))
		{
			croc_popTop(t_);
			return push(t, Value::from(ret));
		}
		else
		{
			croc_pushToString(t_, funcdef);
			return croc_eh_throwStd(t_, "RuntimeError",
				"%s - Attempting to instantiate %s with a different namespace than was associated with it",
				__FUNCTION__, croc_getString(t_, -1));
		}
	}

	word_t croc_function_pushEnv(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");
		return push(t, Value::from(f->environment));
	}

	void croc_function_setEnv(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(ns, -1, Namespace, "environment");
		API_CHECK_PARAM(f, func, Function, "func");

		if(!f->isNative)
			croc_eh_throwStd(t_, "ValueError", "%s - Cannot change the environment of a script function", __FUNCTION__);

		f->setEnvironment(t->vm->mem, ns);
		croc_popTop(t_);
	}

	word croc_function_pushDef(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");

		if(f->isNative)
			return croc_pushNull(t_);
		else
			return push(t, Value::from(f->scriptFunc));
	}

	const char* croc_function_getName(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");
		return f->name->toCString();
	}

	const char* croc_function_getNamen(CrocThread* t_, word_t func, uword_t* len)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");
		*len = f->name->length;
		return f->name->toCString();
	}

	uword_t croc_function_getNumParams(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");
		return f->numParams - 1;
	}

	uword_t croc_function_getMaxParams(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");
		return f->maxParams - 1;
	}

	int croc_function_isVararg(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");
		return f->isVararg();
	}

	int croc_function_isNative(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");
		return f->isNative;
	}
}
}