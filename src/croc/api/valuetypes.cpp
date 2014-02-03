
#include "croc/api.h"
#include "croc/types.hpp"
#include "croc/internal/stack.hpp"

namespace croc
{
extern "C"
{
	word_t croc_pushNull(CrocThread* t)                 { return push(Thread::from(t), Value::nullValue);         }
	word_t croc_pushBool(CrocThread* t, int v)          { return push(Thread::from(t), Value::from(cast(bool)v)); }
	word_t croc_pushInt(CrocThread* t, crocint_t v)     { return push(Thread::from(t), Value::from(v));           }
	word_t croc_pushFloat(CrocThread* t, crocfloat_t v) { return push(Thread::from(t), Value::from(v));           }

	word_t croc_pushString(CrocThread* t_, const char* v)
	{
		auto t = Thread::from(t_);
		return push(t, Value::from(String::create(t->vm, atoda(v))));
	}

	word_t croc_pushStringn(CrocThread* t_, const char* v, uword_t len)
	{
		auto t = Thread::from(t_);
		return push(t, Value::from(String::create(t->vm, crocstr::n(v, len))));
	}

	word_t croc_pushChar(CrocThread* t_, crocchar_t c)
	{
		auto t = Thread::from(t_);
		char outbuf[4];
		auto buf = DArray<char>::n(outbuf, 4);
		DArray<char> s;

		if(encodeUtf8Char(buf, c, s) != UtfError_OK)
			assert(false); // TODO:ex
			// throwStdException(t, "UnicodeError", "Invalid Unicode codepoint U+{:X6}", cast(uint)c);

		return push(t, Value::from(String::createUnverified(t->vm, s.toConst(), 1)));
	}

	// TODO:
	// word_t croc_pushFormat(CrocThread* t, const char* fmt, ...)
	// word_t croc_pushVFormat(CrocThread* t, const char* fmt, va_list args)

	word_t croc_pushNativeobj(CrocThread* t, void* o)
	{
		return push(Thread::from(t), Value::from(o));
	}

	word_t croc_pushThread(CrocThread* t_, CrocThread* o_)
	{
		auto t = Thread::from(t_);
		auto o = Thread::from(o_);

		if(t->vm != o->vm)
			assert(false); // TODO:ex
			// throwStdException(t, "ApiError", __FUNCTION__ " - Threads belong to different VMs");

		return push(t, Value::from(o));
	}

	int croc_getBool(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		auto v = getValue(t, slot);

		if(v->type != CrocType_Bool)
		{
			// croc_pushTypeString(t_, slot); TODO:api
			assert(false); // TODO:ex
			// throwStdException(t, "TypeError", __FUNCTION__ ~ " - expected 'bool' but got '{}'", getString(t, -1));
		}

		return v->mBool;
	}

	crocint_t croc_getInt(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		auto v = getValue(t, slot);

		if(v->type != CrocType_Int)
		{
			// croc_pushTypeString(t_, slot); TODO:api
			assert(false); // TODO:ex
			// throwStdException(t, "TypeError", __FUNCTION__ ~ " - expected 'int' but got '{}'", getString(t, -1));
		}

		return v->mInt;
	}

	crocfloat_t croc_getFloat(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		auto v = getValue(t, slot);

		if(v->type != CrocType_Float)
		{
			// croc_pushTypeString(t_, slot); TODO:api
			assert(false); // TODO:ex
			// throwStdException(t, "TypeError", __FUNCTION__ ~ " - expected 'float' but got '{}'", getString(t, -1));
		}

		return v->mFloat;
	}

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
			// croc_pushTypeString(t_, slot); TODO:api
			assert(false); // TODO:ex
			// throwStdException(t, "TypeError", __FUNCTION__ ~ " - expected 'int' or 'float' but got '{}'", getString(t, -1));
		}
	}

	crocchar_t croc_getChar(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		auto v = getValue(t, slot);

		if(v->type != CrocType_String)
		{
			// croc_pushTypeString(t_, slot); TODO:api
			assert(false); // TODO:ex
			// throwStdException(t, "TypeError", __FUNCTION__ ~ " - expected 'string' but got '{}'", getString(t, -1));
		}

		auto str = v->mString;

		if(str->cpLength != 1)
			assert(false); // TODO:ex
			// throwStdException(t, "ValueError", __FUNCTION__ ~ " - string must be one character long");

		auto ptr = str->toCString();
		return fastDecodeUtf8Char(ptr);
	}

	const char* croc_getString(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		auto v = getValue(t, slot);

		if(v->type != CrocType_String)
		{
			// croc_pushTypeString(t_, slot); TODO:api
			assert(false); // TODO:ex
			// throwStdException(t, "TypeError", __FUNCTION__ ~ " - expected 'string' but got '{}'", getString(t, -1));
		}

		return v->mString->toCString();
	}

	const char* croc_getStringn(CrocThread* t_, word_t slot, uword_t* len)
	{
		auto t = Thread::from(t_);
		auto v = getValue(t, slot);

		if(v->type != CrocType_String)
		{
			// croc_pushTypeString(t_, slot); TODO:api
			assert(false); // TODO:ex
			// throwStdException(t, "TypeError", __FUNCTION__ ~ " - expected 'string' but got '{}'", getString(t, -1));
		}

		auto str = v->mString->toDArray();
		*len = str.length;
		return str.ptr;
	}

	void* croc_getNativeobj(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		auto v = getValue(t, slot);

		if(v->type != CrocType_Nativeobj)
		{
			// croc_pushTypeString(t_, slot); TODO:api
			assert(false); // TODO:ex
			// throwStdException(t, "TypeError", __FUNCTION__ ~ " - expected 'nativeobj' but got '{}'", getString(t, -1));
		}

		return v->mNativeobj;
	}

	CrocThread* croc_getThread(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		auto v = getValue(t, slot);

		if(v->type != CrocType_Thread)
		{
			// croc_pushTypeString(t_, slot); TODO:api
			assert(false); // TODO:ex
			// throwStdException(t, "TypeError", __FUNCTION__ ~ " - expected 'thread' but got '{}'", getString(t, -1));
		}

		return *v->mThread;
	}
} // extern "C"
}