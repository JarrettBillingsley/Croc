
#include <stdarg.h>

#include "croc/api.h"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/types/base.hpp"
#include "croc/util/str.hpp"

using namespace croc;

extern "C"
{
	/** Given a dotted name, looks up the value given by that name and pushes it onto the stack.

	This is to alleviate tedious repeated calls to \ref croc_field to access a chain of fields. For example, if you want
	to call the \c doctools.console.help Croc stdlib function, you can do it like so:

	\code{.c}
	croc_ex_lookup(t, "doctools.console.help");
	croc_pushNull(t);
	croc_pushGlobal(t, "math");
	croc_call(t, -3, 0); // prints out the help for the math module to the console
	\endcode

	The \c name must be properly formatted -- it can't be empty, and none of the components between periods can be
	empty.

	\returns the stack index of the pushed value. */
	word_t croc_ex_lookup(CrocThread* t, const char* name)
	{
		auto len = strlen(name);

		if(len == 0)
			croc_eh_throwStd(t, "ApiError", "The name '%s' is not formatted correctly", name);

		bool isFirst = true;
		word_t idx;

		delimiters(crocstr::n(cast(uchar*)name, len), ATODA("."), [&](crocstr segment)
		{
			if(segment.length == 0)
				croc_eh_throwStd(t, "ApiError", "The name '%s' is not formatted correctly", name);

			if(isFirst)
			{
				isFirst = false;
				idx = croc_pushStringn(t, cast(const char*)segment.ptr, segment.length);
				croc_pushGlobalStk(t);
			}
			else
			{
				croc_pushStringn(t, cast(const char*)segment.ptr, segment.length);
				croc_fieldStk(t, -2);
			}
		});

		if(croc_getStackSize(t) > cast(uword)idx + 1)
			croc_insertAndPop(t, idx);

		return idx;
	}

	/** Pushes the value of the field named \c name from the registry. Since the registry is a namespace, this will
	throw an exception if no field of that name exists in the registry.

	\returns the stack index of the pushed value. */
	word_t croc_ex_pushRegistryVar(CrocThread* t, const char* name)
	{
		croc_vm_pushRegistry(t);
		croc_field(t, -1, name);
		croc_insertAndPop(t, -2);
		return croc_getStackSize(t) - 1;
	}

	/** Expects one value on top of the stack, and assigns it to the field named \c name in the registry. Pops the
	value. */
	void croc_ex_setRegistryVar(CrocThread* t, const char* name)
	{
		croc_vm_pushRegistry(t);
		croc_swapTop(t);
		croc_fielda(t, -2, name);
		croc_popTop(t);
	}

	/** Very similar to \ref croc_eh_throwStd, except instead of being limited to the standard exception types, you can
	throw any exception type given by \c exName. This uses \ref croc_ex_lookup to look up \c exName, so you can use a
	dotted name here too.

	\returns a dummy value like \ref croc_eh_throw. */
	word_t croc_ex_throwNamedException(CrocThread* t, const char* exName, const char* fmt, ...)
	{
		va_list args;
		va_start(args, fmt);
		croc_ex_vthrowNamedException(t, exName, fmt, args);
		va_end(args);
		return 0;
	}

	/** Same as \ref croc_ex_throwNamedException, but takes a \c va_list instead of variadic arguments.

	\returns a dummy value like \ref croc_eh_throw. */
	word_t croc_ex_vthrowNamedException(CrocThread* t, const char* exName, const char* fmt, va_list args)
	{
		croc_ex_lookup(t, exName);
		croc_pushNull(t);
		croc_vpushFormat(t, fmt, args);
		croc_call(t, -3, 1);
		return croc_eh_throw(t);
	}

	/** Given a C stdio \c FILE*, creates a new Croc \c stream.NativeStream instance which will read from or write to
	that \c FILE*, and pushes that instance.

	\param f is the \c FILE* to wrap. It will be flushed before creating the instance. <b>Do not use this \c FILE* at
		the same time Croc is using it!</b> The \c NativeStream uses an unbuffered, lower-level OS interface to access
		the underlying file, and C's stdio functions can make weird things happen because of buffering.
	\param mode will be passed as the mode parameter to the \c NativeStream constructor. This is a string which defines
		what script code can do with it: if the character \c 'r' is in the string, the stream will be readable; \c 'w'
		makes it writable; \c 's' makes it seekable; and \c 'c' makes it closable.

	\returns the stack index of the pushed value. */
	word_t croc_ex_CFileToNativeStream(CrocThread* t, FILE* f, const char* mode)
	{
		auto ret = croc_ex_lookup(t, "stream.NativeStream");
		croc_pushNull(t);

		auto h = oscompat::fromCFile(t, f);

		if(h == oscompat::InvalidHandle)
			oscompat::throwOSEx(t);

		croc_pushNativeobj(t, cast(void*)cast(uword)h);
		croc_pushString(t, mode);
		croc_call(t, ret, 1);
		return ret;
	}

	/** \returns nonzero if the value in slot \c index is an instance of the \c HaltException standard exception type.
	You shouldn't really catch halt exceptions, so if you use \ref croc_tryCall or \ref croc_tryMethodCall and they
	caught an exception, you should test if it was a halt exception and rethrow it if so. */
	int croc_ex_isHaltException(CrocThread* t, word_t index)
	{
		index = croc_absIndex(t, index);
		croc_eh_pushStd(t, "HaltException");
		auto ret = croc_isInstanceOf(t, index, -1);
		croc_popTop(t);
		return ret;
	}
}