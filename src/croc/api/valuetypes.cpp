
#include <cstdio>
#include <stdarg.h>

#include "croc/api.h"
#include "croc/types/base.hpp"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"

using namespace croc;

extern "C"
{
	/** Pushes a null onto the stack. \returns the stack index of the pushed value. */
	word_t croc_pushNull(CrocThread* t)                 { return push(Thread::from(t), Value::nullValue);         }
	/** Pushes a bool onto the stack with the given truth value. \returns the stack index of the pushed value. */
	word_t croc_pushBool(CrocThread* t, int v)          { return push(Thread::from(t), Value::from(cast(bool)v)); }
	/** Pushes an int onto the stack with the given value. \returns the stack index of the pushed value. */
	word_t croc_pushInt(CrocThread* t, crocint_t v)     { return push(Thread::from(t), Value::from(v));           }
	/** Pushes a float onto the stack with the given value. \returns the stack index of the pushed value. */
	word_t croc_pushFloat(CrocThread* t, crocfloat_t v) { return push(Thread::from(t), Value::from(v));           }

	/** Pushes a string onto the stack with the given value. The string length will be determined with \c strlen. Croc
	makes its own copy of string data, so you don't need to keep the data you passed around.

	The string must be valid UTF-8, or an exception will be thrown. (ASCII is valid UTF-8 by design.)

	\returns the stack index of the pushed value. */
	word_t croc_pushString(CrocThread* t_, const char* v)
	{
		auto t = Thread::from(t_);
		return push(t, Value::from(String::create(t->vm, atoda(v))));
	}

	/** Just like \ref croc_pushString, but you give the length of the string instead of having it determined with \c
	strlen.

	\param v is a pointer to the string.
	\param len is the length of the string data <em>in bytes</em>.
	\returns the stack index of the pushed value. */
	word_t croc_pushStringn(CrocThread* t_, const char* v, uword_t len)
	{
		auto t = Thread::from(t_);
		return push(t, Value::from(String::create(t->vm, crocstr::n(cast(const unsigned char*)v, len))));
	}

	/** Similar to \ref croc_pushString, but instead of throwing an exception for invalid text encoding, returns a
	boolean value indicating whether or not pushing was successful.

	This way you can deallocate buffers if the string is not valid and throw your own exception (or handle it however).

	\returns nonzero if the string was successfully pushed, or 0 if it failed (in which case the stack is unchanged). */
	int croc_tryPushString(CrocThread* t_, const char* v)
	{
		auto t = Thread::from(t_);

		if(auto s = String::tryCreate(t->vm, atoda(v)))
		{
			push(t, Value::from(s));
			return true;
		}

		return false;
	}

	/** Just like \ref croc_tryPushString, but you give the length of the string instead of having it determined with
	\c strlen.

	\param v is a pointer to the string.
	\param len is the length of the string data <em>in bytes</em>.
	\returns nonzero if the string was successfully pushed, or 0 if it failed (in which case the stack is unchanged). */
	int croc_tryPushStringn(CrocThread* t_, const char* v, uword_t len)
	{
		auto t = Thread::from(t_);

		if(auto s = String::tryCreate(t->vm, crocstr::n(cast(const unsigned char*)v, len)))
		{
			push(t, Value::from(s));
			return true;
		}

		return false;
	}

	/** Pushes a one-codepoint-long string which contains the given codepoint \c c.

	\returns the stack index of the pushed value. */
	word_t croc_pushChar(CrocThread* t_, crocchar_t c)
	{
		auto t = Thread::from(t_);
		uchar outbuf[4];
		auto buf = ustring::n(outbuf, 4);
		ustring s;

		if(encodeUtf8Char(buf, c, s) != UtfError_OK)
			croc_eh_throwStd(t_, "UnicodeError", "Invalid Unicode codepoint U+%.6x", cast(uint32_t)c);

		return push(t, Value::from(String::createUnverified(t->vm, s, 1)));
	}

	/** Pushes a formatted string onto the stack. This uses \c vsnprintf internally, so it uses the same formatting
	specifiers as the \c printf family. You don't have to worry about dealing with the length of the output string or
	anything; it'll be automatically determined for you.

	\returns the stack index of the pushed value. */
	word_t croc_pushFormat(CrocThread* t, const char* fmt, ...)
	{
		va_list args;
		va_start(args, fmt);
		auto ret = croc_vpushFormat(t, fmt, args);
		va_end(args);
		return ret;
	}

	/** Same as \ref croc_pushFormat, but takes a \c va_list instead of variadic arguments. */
	word_t croc_vpushFormat(CrocThread* t_, const char* fmt, va_list args)
	{
		auto t = Thread::from(t_);
		va_list argsDup;
		va_copy(argsDup, args);
		auto len = vsnprintf(cast(char*)t->vm->formatBuf, CROC_FORMAT_BUF_SIZE, fmt, argsDup);
		word_t ret = 0;

		if(len >= 0 && len < CROC_FORMAT_BUF_SIZE)
			ret = croc_pushStringn(t_, cast(const char*)t->vm->formatBuf, len);
		else
		{
			auto arr = ustring::alloc(t->vm->mem, len + 1); // +1 for terminating \0
			vsnprintf(cast(char*)arr.ptr, len, fmt, args);

			uword_t cpLen;
			auto ok = verifyUtf8(arr, cpLen);

			if(ok == UtfError_OK)
				ret = push(t, Value::from(String::createUnverified(t->vm, arr, cpLen)));

			arr.free(t->vm->mem);

			if(ok != UtfError_OK)
				croc_eh_throwStd(t_, "UnicodeError", "Invalid UTF-8 sequence");
		}

		croc_gc_maybeCollect(t_);
		return ret;
	}

	/** Pushes a nativeobj onto the stack. \returns the stack index of the pushed value. */
	word_t croc_pushNativeobj(CrocThread* t, void* o)
	{
		return push(Thread::from(t), Value::from(o));
	}

	/** Pushes a thread \c o onto \c t's stack. It is an error if the threads belong to different VMs.

	\returns the stack index of the pushed value. */
	word_t croc_pushThread(CrocThread* t, CrocThread* o)
	{
		auto t_ = Thread::from(t);
		auto o_ = Thread::from(o);

		if(t_->vm != o_->vm)
			croc_eh_throwStd(t, "ApiError", "%s - Threads belong to different VMs", __FUNCTION__);

		return push(t_, Value::from(o_));
	}

	/** \returns the bool at the given \c slot (1 for true, 0 for false), or throws an exception if it isn't one. */
	int croc_getBool(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, Bool, "slot");
		return ret;
	}

	/** \returns the int at the given \c slot, or throws an exception if it isn't one. */
	crocint_t croc_getInt(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, Int, "slot");
		return ret;
	}

	/** \returns the float at the given \c slot, or throws an exception if it isn't one. */
	crocfloat_t croc_getFloat(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, Float, "slot");
		return ret;
	}

	/** If the given \c slot contains an int, returns that int cast to a \ref crocfloat_t; if it contains a float,
	returns that value; and if it's any other type, throws an exception. */
	crocfloat_t croc_getNum(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		auto v = getValue(t, slot);

		if(v->type == CrocType_Int)
			return v->mInt;
		else if(v->type == CrocType_Float)
			return v->mFloat;
		else
		{
			croc_pushTypeString(t_, slot);
			croc_eh_throwStd(t_, "TypeError",
				"%s - expected 'int' or 'float' but got '%s'", __FUNCTION__, croc_getString(t_, -1));
			assert(false);
			return 0.0; // dummy
		}
	}

	/** If the given \c slot contains a string, and that string is exactly one codepoint long, returns the codepoint.
	Otherwise, throws an exception. */
	crocchar_t croc_getChar(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(str, slot, String, "slot");

		if(str->cpLength != 1)
			croc_eh_throwStd(t_, "ValueError", "%s - string must be one codepoint long", __FUNCTION__);

		auto ptr = str->toUString();
		return fastDecodeUtf8Char(ptr);
	}

	/** \returns a pointer to the string in the given \c slot, or throws an exception if it isn't one.

	Since Croc strings can contain embedded NUL (codepoint 0) characters, you may be missing the entire string's data
	with this function. If you really need the whole string, use \ref croc_getStringn.

	<b>The string returned from this points into Croc's memory. Do not modify this string, and do not store the pointer
	unless you know it won't be collected!</b> */
	const char* croc_getString(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, String, "slot");
		return ret->toCString();
	}

	/** Like \ref croc_getString, but returns the length of the string in bytes through the \c len parameter.

	<b>The string returned from this points into Croc's memory. Do not modify this string, and do not store the pointer
	unless you know it won't be collected!</b> */
	const char* croc_getStringn(CrocThread* t_, word_t slot, uword_t* len)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, String, "slot");
		auto str = ret->toDArray();
		*len = str.length;
		return cast(const char*)str.ptr;
	}

	/** \returns the nativeobj at the given \c slot, or throws an exception if it isn't one. */
	void* croc_getNativeobj(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, Nativeobj, "slot");
		return ret;
	}

	/** \returns the thread at the given \c slot, or throws an exception if it isn't one.

	<b>The pointer returned from this points into Croc's memory. Do not modify it, and do not store the pointer unless
	you know it won't be collected! The only thread that will never be collected is the VM's main thread. If you want to
	keep a thread around, use the native reference mechanism (\ref croc_ref_create).</b>*/
	CrocThread* croc_getThread(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, Thread, "slot");
		return *ret;
	}
}