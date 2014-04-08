
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** Creates and pushes a new native function closure, expecting the environment on top of the stack and any upvals
	below that. The environment namespace and any upvals are popped and the function is pushed in their place.

	\param name is the name to give the function.
	\param maxParams is the maximum allowable parameters (after the 'this' parameter), or -1 to make it variadic.
	\param func is the native function itself.
	\param numUpvals is how many upvalues will be associated with this closure. There must be this many values on the
		stack under the environment namespace on top.

	\returns the stack index of the pushed value. */
	word_t croc_function_newWithEnv(CrocThread* t_, const char* name, word_t maxParams, CrocNativeFunc func,
		uword_t numUpvals)
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

	/** Creates and pushes a new script function closure from the function definition in slot \c funcdef, and uses the
	current function environment (or the globals if there is none) as the closure's environment.

	There is no way to create a script closure through the native API from a funcdef which has upvalues. Also, it is an
	error to create a closure with a different environment namespace than it was instantiated with initially.

	\returns the stack index of the pushed value. */
	word_t croc_function_newScript(CrocThread* t_, word_t funcdef)
	{
		funcdef = croc_absIndex(t_, funcdef);
		croc_pushCurEnvironment(t_);
		return croc_function_newScriptWithEnv(t_, funcdef);
	}

	/** Same as \ref croc_function_newScript, but expects the environment namespace on top of the stack. It will be
	popped and the function will be pushed in its place.

	\returns the stack index of the pushed value. */
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

	/** Pushes the environment namespace of the function at slot \c func.

	\returns the stack index of the pushed value. */
	word_t croc_function_pushEnv(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");
		return push(t, Value::from(f->environment));
	}

	/** Sets the environment namespace of the \a native function closure at slot \c func. Expects the new environment on
	top of the stack, and pops it.

	You cannot set the environment namespace of script closures. */
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

	/** Pushes the funcdef of the function closure at \c func, or pushes \c null if \c func is a native function.

	\returns the stack index of the pushed value. */
	word croc_function_pushDef(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");

		if(f->isNative)
			return croc_pushNull(t_);
		else
			return push(t, Value::from(f->scriptFunc));
	}

	/** \returns the number of \a non-variadic parameters that the function at \c func takes. */
	uword_t croc_function_getNumParams(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");
		return f->numParams - 1;
	}

	/** \returns the maximum number of parameters that the function at \c func can be called with. For variadic
	functions, this will be an absurdly large number. */
	uword_t croc_function_getMaxParams(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");
		return f->maxParams - 1;
	}

	/** \returns nonzero if the function at \c func is variadic. */
	int croc_function_isVararg(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");
		return f->isVararg();
	}

	/** \returns nonzero if the function at \c func is native. */
	int croc_function_isNative(CrocThread* t_, word_t func)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(f, func, Function, "func");
		return f->isNative;
	}
}