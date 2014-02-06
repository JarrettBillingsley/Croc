
#include "croc/api.h"
#include "croc/types.hpp"
#include "croc/internal/apichecks.hpp"
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
			croc_eh_throwStd(t_, "UnicodeError", "Invalid Unicode codepoint U+{:X6}", cast(uint32_t)c);

		return push(t, Value::from(String::createUnverified(t->vm, s.toConst(), 1)));
	}

	// TODO:
	// word_t croc_pushFormat(CrocThread* t, const char* fmt, ...)
	// word_t croc_vpushFormat(CrocThread* t, const char* fmt, va_list args)

	word_t croc_pushNativeobj(CrocThread* t, void* o)
	{
		return push(Thread::from(t), Value::from(o));
	}

	word_t croc_pushThread(CrocThread* t_, CrocThread* o_)
	{
		auto t = Thread::from(t_);
		auto o = Thread::from(o_);

		if(t->vm != o->vm)
			croc_eh_throwStd(t_, "ApiError", "{} - Threads belong to different VMs", __FUNCTION__);

		return push(t, Value::from(o));
	}

	int croc_getBool(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, Bool, "slot");
		return ret;
	}

	crocint_t croc_getInt(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, Int, "slot");
		return ret;
	}

	crocfloat_t croc_getFloat(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, Float, "slot");
		return ret;
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
			croc_pushTypeString(t_, slot);
			croc_eh_throwStd(t_, "TypeError", "{} - expected 'int' or 'float' but got '{}'", __FUNCTION__, croc_getString(t_, -1));
			assert(false);
		}
	}

	crocchar_t croc_getChar(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(str, slot, String, "slot");

		if(str->cpLength != 1)
			croc_eh_throwStd(t_, "ValueError", "{} - string must be one codepoint long", __FUNCTION__);

		auto ptr = str->toCString();
		return fastDecodeUtf8Char(ptr);
	}

	const char* croc_getString(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, String, "slot");
		return ret->toCString();
	}

	const char* croc_getStringn(CrocThread* t_, word_t slot, uword_t* len)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, String, "slot");
		auto str = ret->toDArray();
		*len = str.length;
		return str.ptr;
	}

	void* croc_getNativeobj(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, Nativeobj, "slot");
		return ret;
	}

	CrocThread* croc_getThread(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(ret, slot, Thread, "slot");
		return *ret;
	}
} // extern "C"
}