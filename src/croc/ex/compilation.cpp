
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/types/base.hpp"
#include "croc/util/str.hpp"

using namespace croc;

extern "C"
{
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

	void croc_ex_runStringWithEnvStk(CrocThread* t, const char* name)
	{
		croc_ex_loadStringWithEnvStk(t, name);
		croc_pushNull(t);
		croc_call(t, -2, 0);
	}

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