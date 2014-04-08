
#include <stdio.h>
#include <stdlib.h>

#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** Throws the value on top of the stack as an exception. It must be an \c instance to be throwable.

	\returns a dummy value (this function doesn't actually return) so that you can use it like so:

	\code{.c}
	if(blah blah)
		return 1;
	else
		return croc_eh_throw(t);
	\endcode

	This can avoid having to put dummy returns in native functions that end by throwing an exception. */
	word_t croc_eh_throw(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		throwImpl(t, t->stack[t->stackIndex - 1], false);
		return 0; // dummy
	}

	/** Rethrows the value on top of the stack as an exception. The only difference between this and \ref croc_eh_throw
	is that this will not modify the exception's traceback info (if any).

	You will most likely use this after catching an exception with \ref croc_tryCall or \ref croc_tryMethodCall, like
	so:

	\code{.c}
	// do some stuff here which needs to be cleaned up
	result = croc_tryCall(t, 3, 1);
	// do some stuff here to clean up

	if(result < 0)
		croc_eh_rethrow(t);
	\endcode

	In this way, you can imitate the behavior of "finally" blocks in native code.

	\returns a dummy value like \ref croc_eh_throw. */
	word_t croc_eh_rethrow(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		throwImpl(t, t->stack[t->stackIndex - 1], true);
		return 0; // dummy
	}

	/** Pushes one of the standard exception classes (as defined in the Croc \c exceptions module) onto the stack.

	\param exName is the name of the class you want.
	\returns the stack index of the newly-pushed class. */
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

	/** A convenience function for throwing one of the standard exception types. This basically pushes the standard
	exception class, pushes the formatted parameters, instantiates the class, and throws the resulting instance. For
	example:

	\code{.c}
	croc_eh_throwStd(t, "RangeError", "The value '%d' must be between 0 and 100", val);
	\endcode

	\param exName is the name of the standard exception class that you want to throw.
	\param fmt is the format string. This works just like \c printf and will call \ref croc_vpushFormat internally.
	\returns a dummy value like \ref croc_eh_throw. */
	word_t croc_eh_throwStd(CrocThread* t, const char* exName, const char* fmt, ...)
	{
		va_list args;
		va_start(args, fmt);
		croc_eh_vthrowStd(t, exName, fmt, args);
		va_end(args);
		return 0; // dummy
	}

	/** Just like \ref croc_eh_throwStd but takes a \c va_list instead of variadic arguments.
	\returns a dummy value like \ref croc_eh_throw. */
	word_t croc_eh_vthrowStd(CrocThread* t, const char* exName, const char* fmt, va_list args)
	{
		croc_eh_pushStd(t, exName);
		croc_pushNull(t);
		croc_vpushFormat(t, fmt, args);
		croc_call(t, -3, 1);
		croc_eh_throw(t);
		return 0; // dummy
	}

	/** Pushes the \c Location class as defined in the Croc \c exceptions module.
	\returns the stack index of the newly-pushed class. */
	word_t croc_eh_pushLocationClass(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		return push(t, Value::from(t->vm->location));
	}

	/** Pushes an instance of the \c Location class, passing the given values to the constructor.

	\param file is the location's filename.
	\param line is the line number, or 0 to mean a line couldn't be determined.
	\param col is either > 0 to mean the column number in a compiler location, or <= 0 to mean something else. The
		values of the \ref CrocLocation enum can be used for this.
	\returns the stack index of the newly-pushed instance. */
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

	/** Sets the function which will be called if an exception is thrown outside of any exception handling frame.

	This can occur if an error occurs in native code outside any EH frames, such as at the top level of your program.
	For example, this would cause an unhandled exception:

	\code{.c}
	CrocThread* t = croc_vm_openDefault();
	croc_cat(t, 10); // throws an ApiError, but there is no EH frame to catch it!
	\endcode

	When an unhandled exception occurs, all threads that were running or waiting will be dead, and the unhandled
	exception handler will be called on the main thread with the offending exception as its only parameter. When the
	unhandled exception handler returns, the C \c abort() function is called. If you don't want this to happen, you'll
	have to set your own unhandled exception handler which uses \c longjmp to jump somewhere else. Better yet, set up
	an EH frame around the top level of your code using \ref croc_tryCall so you can handle exceptions properly.

	By default there is a handler set up which simply prints out the offending exception and traceback.

	This function expects the new handler function to be on top of the stack. It will set this function as the unhandled
	exception handler, and will replace the value on top of the stack with the previous handler.*/
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