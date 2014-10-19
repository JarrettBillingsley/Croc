
#include <string.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{
#include "croc/stdlib/stream.croc.hpp"

word_t _addHiddenFields(CrocThread* t)
{
	croc_pushNull(t);        croc_class_addHField(t, 1, "handle");
	croc_pushBool(t, false); croc_class_addHField(t, 1, "closed");
	croc_pushBool(t, false); croc_class_addHField(t, 1, "readable");
	croc_pushBool(t, false); croc_class_addHField(t, 1, "writable");
	croc_pushBool(t, false); croc_class_addHField(t, 1, "seekable");
	croc_pushBool(t, false); croc_class_addHField(t, 1, "closable");
	croc_pushBool(t, false); croc_class_addHField(t, 1, "dirty");
	croc_dup(t, 1);
	return 1;
}

word_t _hidden(CrocThread* t)
{
	if(croc_isValidIndex(t, 2))
	{
		croc_hfieldaStk(t, 0);
		return 0;
	}
	else
	{
		croc_hfieldStk(t, 0);
		return 1;
	}
}

word_t _nativeStreamCtor(CrocThread* t)
{
	auto handle = cast(oscompat::FileHandle)cast(uword)croc_getNativeobj(t, 2);
	auto caps = croc_getString(t, 3);

	if(!oscompat::isValidHandle(handle))
		croc_eh_throwStd(t, "TypeError", "Given stream handle is invalid");

	croc_dup(t, 2);                                 croc_hfielda(t, 1, "handle");
	croc_pushBool(t, strchr(caps, 'c') != nullptr); croc_hfielda(t, 1, "closable");
	croc_pushBool(t, strchr(caps, 'r') != nullptr); croc_hfielda(t, 1, "readable");
	croc_pushBool(t, strchr(caps, 'w') != nullptr); croc_hfielda(t, 1, "writable");
	croc_pushBool(t, strchr(caps, 's') != nullptr); croc_hfielda(t, 1, "seekable");
	return 0;
}

word_t _nativeStreamRead(CrocThread* t)
{
	auto handle = cast(oscompat::FileHandle)cast(uword)croc_getNativeobj(t, 1);
	auto offset = cast(uword)croc_getInt(t, 3);
	auto size = cast(uword)croc_getInt(t, 4);
	auto dest = cast(uint8_t*)croc_memblock_getData(t, 2) + offset;

	auto initial = size;

	while(size > 0)
	{
		auto numRead = oscompat::read(t, handle, DArray<uint8_t>::n(dest, size));

		if(numRead == -1)
			oscompat::throwIOEx(t);

		if(numRead == 0)
			break; // EOF
		else if(cast(uword)numRead < size)
		{
			size -= numRead;
			break;
		}

		size -= numRead;
		dest += numRead;
	}

	croc_pushInt(t, initial - size);
	return 1;
}

word_t _nativeStreamWrite(CrocThread* t)
{
	auto handle = cast(oscompat::FileHandle)cast(uword)croc_getNativeobj(t, 1);
	auto offset = cast(uword)croc_getInt(t, 3);
	auto size = cast(uword)croc_getInt(t, 4);
	auto src = cast(uint8_t*)croc_memblock_getData(t, 2) + offset;

	auto initial = size;

	while(size > 0)
	{
		auto numWritten = oscompat::write(t, handle, DArray<uint8_t>::n(src, size));

		if(numWritten == -1)
			oscompat::throwIOEx(t);
		else if(numWritten == 0)
		{
			croc_pushGlobal(t, "EOFException");
			croc_pushNull(t);
			croc_call(t, -2, 1);
			croc_eh_throw(t);
		}

		size -= numWritten;
		src += numWritten;
	}

	croc_pushInt(t, initial);
	return 1;
}

word_t _nativeStreamSeek(CrocThread* t)
{
	auto handle = cast(oscompat::FileHandle)cast(uword)croc_getNativeobj(t, 1);
	auto offset = croc_getInt(t, 2);
	auto whence = croc_getString(t, 3);
	auto realWhence =
		whence[0] == 'b' ? oscompat::Whence::Begin :
		whence[0] == 'c' ? oscompat::Whence::Current :
							oscompat::Whence::End;

	auto offs = oscompat::seek(t, handle, offset, realWhence);

	if(offs == cast(uint64_t)-1)
		oscompat::throwIOEx(t);

	croc_pushInt(t, cast(crocint)offs);
	return 1;
}

word_t _nativeStreamFlush(CrocThread* t)
{
	auto handle = cast(oscompat::FileHandle)cast(uword)croc_getNativeobj(t, 1);

	if(!oscompat::flush(t, handle))
		oscompat::throwIOEx(t);

	return 0;
}

word_t _nativeStreamClose(CrocThread* t)
{
	auto handle = cast(oscompat::FileHandle)cast(uword)croc_getNativeobj(t, 1);

	if(!oscompat::close(t, handle))
		oscompat::throwIOEx(t);

	return 0;
}

const CrocRegisterFunc _funcs[] =
{
	{"addHiddenFields",   1, &_addHiddenFields  },
	{"hidden",            2, &_hidden           },
	{"nativeStreamCtor",  3, &_nativeStreamCtor },
	{"nativeStreamRead",  4, &_nativeStreamRead },
	{"nativeStreamWrite", 4, &_nativeStreamWrite},
	{"nativeStreamSeek",  3, &_nativeStreamSeek },
	{"nativeStreamFlush", 1, &_nativeStreamFlush},
	{"nativeStreamClose", 1, &_nativeStreamClose},
	{nullptr, 0, nullptr}
};
}

void initStreamLib(CrocThread* t)
{
	croc_table_new(t, 0);
		croc_ex_registerFields(t, _funcs);
	croc_newGlobal(t, "_streamtmp");

	registerModuleFromString(t, "stream", stream_croc_text, "stream.croc");

	croc_vm_pushGlobals(t);
	croc_pushString(t, "_streamtmp");
	croc_removeKey(t, -2);
	croc_popTop(t);
}
}