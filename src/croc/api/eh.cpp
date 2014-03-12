
#include <stdio.h>
#include <stdlib.h>

#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
extern "C"
{
	word_t croc_eh_throw(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		throwImpl(t, t->stack[t->stackIndex - 1], false);
		return 0; // dummy
	}

	word_t croc_eh_rethrow(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		throwImpl(t, t->stack[t->stackIndex - 1], true);
		return 0; // dummy
	}

	word_t croc_eh_pushStd(CrocThread* t_, const char* exName)
	{
		auto t = Thread::from(t_);
		auto ex = t->vm->stdExceptions.lookup(String::create(t->vm, atoda(exName)));

		if(ex == nullptr)
		{
			auto check = t->vm->stdExceptions.lookup(String::create(t->vm, ATODA("ApiError")));

			if(check == nullptr)
			{
				fprintf(stderr, "Fatal -- exception thrown before exception library was loaded");
				abort();
			}

			croc_eh_throwStd(*t, "NameError", "Unknown standard exception type '%s'", exName);
		}

		return push(t, Value::from(*ex));
	}

	word_t croc_eh_throwStd(CrocThread* t, const char* exName, const char* fmt, ...)
	{
		va_list args;
		va_start(args, fmt);
		croc_eh_vthrowStd(t, exName, fmt, args);
		va_end(args);
		return 0; // dummy
	}

	word_t croc_eh_vthrowStd(CrocThread* t, const char* exName, const char* fmt, va_list args)
	{
		croc_eh_pushStd(t, exName);
		croc_pushNull(t);
		croc_vpushFormat(t, fmt, args);
		croc_call(t, -3, 1);
		croc_eh_throw(t);
		return 0; // dummy
	}

	word_t croc_eh_pushLocationClass(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		return push(t, Value::from(t->vm->location));
	}

	word_t croc_eh_pushLocationObject(CrocThread* t_, const char* file, int line, int col)
	{
		auto t = Thread::from(t_);
		auto ret = push(t, Value::from(t->vm->location));
		croc_pushNull(t_);
		croc_pushString(t_, file);
		croc_pushInt(t_, line);
		croc_pushInt(t_, col);
		croc_call(t_, ret, 1);
		return ret;
	}

	void croc_eh_setUnhandledExHandler(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(func, -1, Function, "handler");
		auto old = t->vm->unhandledEx;
		t->vm->unhandledEx = func;
		t->stack[t->stackIndex - 1] = Value::from(old);
	}
}
}