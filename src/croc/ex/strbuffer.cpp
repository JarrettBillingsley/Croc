
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/types/base.hpp"

using namespace croc;

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

		croc_pushStringn(b->t, cast(const char*)b->data, b->pos);
		b->pos = 0;
		addPiece(b);
	}
}

extern "C"
{
	/** Initializes a \ref CrocStrBuffer.

	Using a \c CrocStrBuffer goes something like this:

	1. Declare a \c CrocStrBuffer variable.
	2. Initialize it with this function.
	3. Add pieces to it with the various other functions.
	4. When you're done building your string, call \ref croc_ex_buffer_finish on it, which will leave the resulting
		string on top of the stack.

	So for example:

	\code{.c}
	CrocStrBuffer b;

	// Start!
	croc_ex_buffer_init(t, &b);
	croc_ex_buffer_addString(&b, "Hello");
	croc_ex_buffer_addChar(&b, ',');
	croc_pushString(t, " world!");
	croc_ex_buffer_addTop(&b);
	croc_ex_buffer_finish(&b);
	// Now there is only one more stack slot than what we started with, and it contains the string "Hello, world!".
	\endcode

	Note that \c croc_ex_buffer_init pushes a stack slot for use by the buffer which is used until
	\c croc_ex_buffer_finish is called. You shouldn't remove or modify this slot, and you shouldn't remove stack slots
	below it either (or else things will get messed up). You can, however, push and pop stack slots above this slot
	freely.
	*/
	void croc_ex_buffer_init(CrocThread* t, CrocStrBuffer* b)
	{
		b->t = t;
		b->slot = 0;
		croc_ex_buffer_start(b);
	}

	/** Adds a single Unicode codepoint to \c b. */
	void croc_ex_buffer_addChar(CrocStrBuffer* b, crocchar_t c)
	{
		assert(b->slot != 0);
		assert(b->buffer == 0);

		uchar outbuf_[4];
		auto outbuf = ustring::n(outbuf_, 4);
		ustring s;

		if(encodeUtf8Char(outbuf, c, s) != UtfError_OK)
			croc_eh_throwStd(b->t, "UnicodeError", "Invalid character U+%.6x", cast(unsigned int)c);

		if(b->pos + s.length - 1 >= CROC_STR_BUFFER_DATA_LENGTH)
			flush(b);

		ustring::n(b->data + b->pos, s.length).slicea(s);
		b->pos += s.length;
	}

	/** Adds a zero-terminated string to \c b. */
	void croc_ex_buffer_addString(CrocStrBuffer* b, const char* s)
	{
		croc_ex_buffer_addStringn(b, s, strlen(s));
	}

	/** Adds a string of length \c len to \c b. */
	void croc_ex_buffer_addStringn(CrocStrBuffer* b, const char* s, uword_t len)
	{
		assert(b->slot != 0);
		assert(b->buffer == 0);

		if(len > (CROC_STR_BUFFER_DATA_LENGTH - b->pos))
		{
			flush(b);

			if(len > CROC_STR_BUFFER_DATA_LENGTH)
			{
				croc_pushStringn(b->t, s, len);
				addPiece(b);
				return;
			}
		}

		ustring::n(b->data + b->pos, len).slicea(ustring::n(cast(uchar*)s, len));
		b->pos += len;
	}

	/** Expects a single string on top of the stack, pops it, and adds it to \c b. */
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

		ustring::n(b->data + b->pos, str.length).slicea(str);
		b->pos += str.length;
		croc_popTop(b->t);
	}

	/** Finishes building the string. The stack should be in the same configuration as it was right after the
	corresponding \ref croc_ex_buffer_init call. The bookkeeping slot is removed and the result string is pushed in its
	place.

	After this is called, the buffer can be reused to build a new string by calling \ref croc_ex_buffer_start on it.

	\returns the stack index of the result string. */
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
			croc_pushStringn(t, cast(const char*)b->data, b->pos);
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

	/** After building up a string and calling \ref croc_ex_buffer_finish on a buffer \c b, you can start building a
	new string with the same buffer object by calling this. */
	void croc_ex_buffer_start(CrocStrBuffer* b)
	{
		assert(b->slot == 0);
		b->slot = croc_pushNull(b->t);
		b->pos = 0;
		b->buffer = 0;
	}

	/** Prepares a memory area of \c size bytes for you to write raw string data into.

	When you call this function on a buffer, <b>you cannot call any of the other functions on it until you call
	\ref croc_ex_buffer_addPrepared.</b> It places the buffer into a special mode, and in addition, may push a value
	onto the stack. Just like with the buffer's bookkeeping slot, do not modify, remove, or change the position of this
	slot.

	\returns a pointer to a memory area of \c size bytes which you are expected to fill with string data.

	<b>The pointer returned from this may point into Croc's memory. Do not store the pointer! Just keep it long enough
	to fill the area with data and call \ref croc_ex_buffer_addPrepared.</b>*/
	char* croc_ex_buffer_prepare(CrocStrBuffer* b, uword_t size)
	{
		assert(b->slot != 0);
		assert(b->buffer == 0);

		if(size <= CROC_STR_BUFFER_DATA_LENGTH)
		{
			if(size > (CROC_STR_BUFFER_DATA_LENGTH - b->pos))
				flush(b);

			b->buffer = -size;
			return cast(char*)(b->data + b->pos);
		}
		else
		{
			b->buffer = croc_memblock_new(b->t, size);
			return croc_memblock_getData(b->t, -1);
		}
	}

	/** Adds the memory area that was returned by \ref croc_ex_buffer_prepare to the buffer. After calling this, the
	buffer will be back into its normal mode, and the stack slot that \ref croc_ex_buffer_prepare may have allocated
	will be gone. The stack must be in the same configuration as it was after \c croc_ex_buffer_prepare was called. */
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