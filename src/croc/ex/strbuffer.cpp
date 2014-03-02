
#include "croc/api.h"
#include "croc/internal/apichecks.hpp"
#include "croc/types.hpp"

namespace croc
{
extern "C"
{
	namespace
	{
	void addPiece(CrocStrBuffer* b)
	{
		if(croc_isNull(b->t, b->slot))
		{
			croc_array_new(b->t, 0);
			croc_swapTopWith(b->t, b->slot);
			croc_popTop(b->t);
		}

		croc_cateq(b->t, b->slot, 1);
	}

	void flush(CrocStrBuffer* b)
	{
		if(b->pos == 0)
			return;

		croc_pushStringn(b->t, b->data, b->pos);
		b->pos = 0;
		addPiece(b);
	}
	}

	void croc_ex_buffer_init(CrocThread* t, CrocStrBuffer* b)
	{
		b->t = t;
		b->slot = 0;
		croc_ex_buffer_start(b);
	}

	void croc_ex_buffer_addChar(CrocStrBuffer* b, crocchar_t c)
	{
		assert(b->slot != 0);
		assert(b->buffer == 0);

		char outbuf_[4];
		auto outbuf = DArray<char>::n(outbuf_, 4);
		DArray<char> s;

		if(encodeUtf8Char(outbuf, c, s) != UtfError_OK)
			croc_eh_throwStd(b->t, "UnicodeError", "Invalid character U+%.6x", cast(unsigned int)c);

		if(b->pos + s.length - 1 >= CROC_STR_BUFFER_DATA_LENGTH)
			flush(b);

		DArray<char>::n(b->data + b->pos, s.length).slicea(s);
		b->pos += s.length;
	}

	void croc_ex_buffer_addString(CrocStrBuffer* b, const char* s)
	{
		croc_ex_buffer_addStringn(b, s, strlen(s));
	}

	void croc_ex_buffer_addStringn(CrocStrBuffer* b, const char* s, uword_t len)
	{
		assert(b->slot != 0);
		assert(b->buffer == 0);

		if(len > (CROC_STR_BUFFER_DATA_LENGTH - b->pos))
		{
			flush(b);

			if(len > CROC_STR_BUFFER_DATA_LENGTH)
			{
				croc_pushString(b->t, s);
				addPiece(b);
				return;
			}
		}

		DArray<char>::n(b->data + b->pos, len).slicea(DArray<char>::n(cast(char*)s, len));
		b->pos += len;
	}

	void croc_ex_buffer_addTop(CrocStrBuffer* b)
	{
		assert(b->slot != 0);
		assert(b->buffer == 0);
		auto t = Thread::from(b->t);
		API_CHECK_PARAM(s, -1, String, "new piece");

		auto str = s->toDArray();

		if(str.length > (CROC_STR_BUFFER_DATA_LENGTH - b->pos))
		{
			if(str.length > CROC_STR_BUFFER_DATA_LENGTH)
			{
				flush(b);
				addPiece(b);
				return;
			}

			flush(b);
		}

		DArray<char>::n(b->data + b->pos, str.length).slicea(DArray<char>::n(cast(char*)str.ptr, str.length));
		b->pos += str.length;
		croc_popTop(b->t);
	}

	word_t croc_ex_buffer_finish(CrocStrBuffer* b)
	{
		assert(b->slot != 0);
		assert(b->buffer == 0);
		auto t = b->t;

		if(croc_getStackSize(b->t) - 1 != cast(uword)b->slot)
			croc_eh_throwStd(t, "ApiError",
				"Stack is not in the same configuration as when croc_ex_buffer_start was called");

		if(croc_isNull(t, b->slot))
		{
			croc_popTop(t);
			croc_pushStringn(t, b->data, b->pos);
		}
		else
		{
			flush(b);
			croc_pushString(t, "");
			croc_pushNull(t);
			croc_moveToTop(t, b->slot);
			croc_methodCall(t, b->slot, "join", 1);
		}

		auto ret = b->slot;
		b->slot = 0;
		return ret;
	}

	void croc_ex_buffer_start(CrocStrBuffer* b)
	{
		assert(b->slot == 0);
		b->slot = croc_pushNull(b->t);
		b->pos = 0;
		b->buffer = 0;
	}

	char* croc_ex_buffer_prepare(CrocStrBuffer* b, uword_t size)
	{
		assert(b->slot != 0);
		assert(b->buffer == 0);

		if(size <= CROC_STR_BUFFER_DATA_LENGTH)
		{
			if(size > (CROC_STR_BUFFER_DATA_LENGTH - b->pos))
				flush(b);

			b->buffer = -size;
			return b->data + b->pos;
		}
		else
		{
			b->buffer = croc_memblock_new(b->t, size);
			return croc_memblock_getData(b->t, -1);
		}
	}

	void croc_ex_buffer_addPrepared(CrocStrBuffer* b)
	{
		assert(b->slot != 0);
		assert(b->buffer != 0);

		if(b->buffer > 0)
		{
			if(croc_getStackSize(b->t) - 1 != cast(uword)b->buffer)
				croc_eh_throwStd(b->t, "ApiError",
					"Stack is not in the same configuration as when croc_ex_buffer_prepare was called");

			uword_t size;
			auto ptr = croc_memblock_getDatan(b->t, -1, &size);
			croc_pushStringn(b->t, ptr, size);
			croc_swapTop(b->t);
			croc_popTop(b->t);
			b->buffer = 0;
			croc_ex_buffer_addTop(b);
		}
		else
		{
			b->pos += -b->buffer;
			b->buffer = 0;
		}
	}
}
}