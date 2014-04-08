
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/types/base.hpp"
#include "croc/util/str.hpp"

using namespace croc;

extern "C"
{
	/** Expects an environment namespace on top of the stack and a string of code containing zero or more statements
	under it. Compiles the code and instantiates the funcdef. Pops the environment and source, and replaces them with
	the resulting function closure.

	\returns the stack index of the resulting closure. */
	word_t croc_ex_loadStringWithEnvStk(CrocThread* t_, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(_, -2, String, "code");
		API_CHECK_PARAM(__, -1, Namespace, "environment");
		(void)_;
		(void)__;
		croc_dup(t_, -2);
		croc_compiler_compileStmtsEx(t_, name ? name : "<loaded from string>");
		croc_swapTop(t_);
		croc_function_newScriptWithEnv(t_, -2);
		croc_insertAndPop(t_, -3);
		return croc_getStackSize(t_) - 1;
	}

	/** Like \ref croc_ex_loadStringWithEnvStk but also calls the resulting function, leaving nothing on the stack. */
	void croc_ex_runStringWithEnvStk(CrocThread* t, const char* name)
	{
		croc_ex_loadStringWithEnvStk(t, name);
		croc_pushNull(t);
		croc_call(t, -2, 0);
	}

	/** Expects an environment namespace on top of the stack and a string of code containing an expression under it.
	Compiles and runs the expression, returning \c numReturns values which replace the code and environment.

	\returns the number of values that were returned from the expression. */
	uword_t croc_ex_evalWithEnvStk(CrocThread* t_, word_t numReturns)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(_, -2, String, "code");
		API_CHECK_PARAM(__, -1, Namespace, "environment");
		(void)_;
		(void)__;
		croc_dup(t_, -2);
		croc_compiler_compileExprEx(t_, "<loaded by eval>");
		croc_swapTop(t_);
		croc_function_newScriptWithEnv(t_, -2);
		croc_insertAndPop(t_, -3);
		croc_pushNull(t_);
		return croc_call(t_, -2, numReturns);
	}

	/** Imports the module \c moduleName, and then calls the Croc \c modules.runMain function on the resulting module.

	\param numParams is how many parameters you want to pass to the module's \c main function. There should be this many
		values on the stack, and they will be popped. */
	void croc_ex_runModule(CrocThread* t_, const char* moduleName, uword_t numParams)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(numParams);
		croc_ex_importNS(t_, moduleName);
		croc_pushNull(t_);
		croc_ex_lookup(t_, "modules.runMain");
		croc_swapTopWith(t_, -3);
		croc_rotate(t_, numParams + 3, 3);
		croc_call(t_, -3 - numParams, 0);
	}
}