
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{
#include "croc/stdlib/modules.croc.hpp"
}

void initModulesLib(CrocThread* t)
{
	croc_table_new(t, 1);
		croc_function_new(t, "_setfenv", 2, [](CrocThread* t) -> word_t
		{
			croc_dup(t, 2);
			croc_function_setEnv(t, 1);
			return 0;
		}, 0);
		croc_fielda(t, -2, "_setfenv");

		croc_array_new(t, 0);
		for(auto addon = croc_vm_includedAddons(); *addon != nullptr; addon++)
		{
			croc_pushString(t, *addon);
			croc_cateq(t, -2, 1);
		}
		croc_fielda(t, -2, "IncludedAddons");

		croc_function_new(t, "_existsTime", 1, [](CrocThread* t) -> word_t
		{
			croc_ex_checkParam(t, 1, CrocType_String);
			oscompat::FileInfo info;

			if(oscompat::getInfo(t, getCrocstr(t, 1), &info))
			{
				croc_pushBool(t, true);
				croc_pushInt(t, cast(crocint_t)info.modified);
				return 2;
			}
			else
			{
				croc_pushBool(t, false);
				return 1;
			}
		}, 0);
		croc_fielda(t, -2, "_existsTime");

		croc_function_new(t, "_getFileContents", 1, [](CrocThread* t) -> word_t
		{
			croc_ex_checkParam(t, 1, CrocType_String);
			auto name = getCrocstr(t, 1);
			auto f = oscompat::openFile(t, name, oscompat::FileAccess::Read, oscompat::FileCreate::OpenExisting);

			if(f == oscompat::InvalidHandle)
			{
				croc_pushFormat(t, "Error opening '%.*s' for reading: ", cast(int)name.length, name.ptr);
				croc_swapTop(t);
				croc_cat(t, 2);
				oscompat::throwIOEx(t);
			}

			auto size = oscompat::seek(t, f, 0, oscompat::Whence::End);

			if(size == cast(uint64_t)-1)
				oscompat::throwIOEx(t);

			if(oscompat::seek(t, f, 0, oscompat::Whence::Begin) == cast(uint64_t)-1)
				oscompat::throwIOEx(t);

			croc_memblock_new(t, size);
			auto ptr = cast(uint8_t*)croc_memblock_getData(t, -1);
			uword_t offset = 0;
			uword_t remaining = size;

			while(remaining > 0)
			{
				auto bytesRead = oscompat::read(t, f, DArray<uint8_t>::n(ptr + offset, remaining));

				if(bytesRead == 0)
					croc_eh_throwStd(t, "IOException", "Unexpected end of file");

				offset += bytesRead;
				remaining -= bytesRead;
			}

			return 1;
		}, 0);
		croc_fielda(t, -2, "_getFileContents");
	croc_newGlobal(t, "_modulestmp");

	registerModuleFromString(t, "modules", modules_croc_text, "modules.croc");

	croc_vm_pushGlobals(t);
	croc_pushString(t, "_modulestmp");
	croc_removeKey(t, -2);
	croc_popTop(t);
}
}