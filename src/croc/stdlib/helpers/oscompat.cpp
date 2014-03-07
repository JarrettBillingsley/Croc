
#include "croc/api.h"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/types/base.hpp"
#include "croc/util/utf.hpp"

namespace croc
{
	namespace oscompat
	{
	void throwIOEx(CrocThread* t)
	{
		croc_eh_pushStd(t, "IOException");
		croc_pushNull(t);
		croc_moveToTop(t, -3);
		croc_call(t, -3, 1);
		croc_eh_throw(t);
	}

#ifdef _WIN32
	void pushSystemErrorMsg(CrocThread* t)
	{
		auto errCode = GetLastError();

		LPCWSTR msg16;
		auto size16 = FormatMessageW(
			FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
			nullptr, errCode, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), cast(LPWSTR)&msg16, 0, nullptr);

		if(size16 == 0)
		{
			croc_pushString(t, "<error formatting system message>");
			return;
		}

		// Get rid of \r\n
		if(size16 >= 2)
			size16 -= 2;

		auto msg16Arr = cwstring::n(cast(const wchar*)msg16, size16);
		auto size8 = fastUtf16GetUtf8Size(msg16Arr);
		auto msg8 = mcrocstr::alloc(Thread::from(t)->vm->mem, size8);
		cwstring remaining;
		mcrocstr output;
		auto ok = Utf16ToUtf8(msg16Arr, msg8, remaining, output);
		LocalFree(cast(HLOCAL)msg16);

		if(ok == UtfError_OK)
		{
			assert(output.length == size8);
			assert(remaining.length == 0);
			croc_pushStringn(t, cast(const char*)msg8.ptr, msg8.length);
		}
		else
			croc_pushString(t, "<error formatting system message>");

		msg8.free(Thread::from(t)->vm->mem);
	}

	FileHandle openFile(CrocThread* t, crocstr name, FileAccess access, FileCreate create)
	{
		// Convert name to UTF-16, the best encoding
		wchar buf[512];
		auto tmp = wstring();
		auto size16 = fastUtf8GetUtf16Size(name);
		wstring name16;
		custring remaining;

		if(size16 > 511) // -1 cause we need to put the terminating 0
		{
			tmp = wstring::alloc(Thread::from(t)->vm->mem, size16 + 1);
			name16 = Utf8ToUtf16(name, tmp, remaining);
		}
		else
			name16 = Utf8ToUtf16(name, wstring::n(buf, 512), remaining);

		assert(name16.length == size16);
		assert(remaining.length == 0);

		name16.ptr[name16.length] = 0;

		// Open it!
		auto ret = CreateFileW(cast(LPCWSTR)name16.ptr, cast(DWORD)access, 0,
			nullptr, cast(DWORD)create, FILE_ATTRIBUTE_NORMAL, nullptr);

		if(tmp.length)
			tmp.free(Thread::from(t)->vm->mem);

		if(ret == INVALID_HANDLE_VALUE)
			pushSystemErrorMsg(t);
		else
			SetLastError(ERROR_SUCCESS); // Some of the file open modes set the error even if successful?! silly

		return ret;
	}

	bool truncate(CrocThread* t, FileHandle f, uint64_t pos)
	{
		if(seek(t, f, pos, Whence::Begin) == cast(uint64_t)-1)
			return false;

		if(SetEndOfFile(f) == 0)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		return true;
	}

	FileHandle getStdin(CrocThread* t)
	{
		auto ret = GetStdHandle(STD_INPUT_HANDLE);

		if(ret == INVALID_HANDLE_VALUE)
			pushSystemErrorMsg(t);

		return ret;
	}

	FileHandle getStdout(CrocThread* t)
	{
		auto ret = GetStdHandle(STD_OUTPUT_HANDLE);

		if(ret == INVALID_HANDLE_VALUE)
			pushSystemErrorMsg(t);

		return ret;
	}

	FileHandle getStderr(CrocThread* t)
	{
		auto ret = GetStdHandle(STD_ERROR_HANDLE);

		if(ret == INVALID_HANDLE_VALUE)
			pushSystemErrorMsg(t);

		return ret;
	}

	bool isValidHandle(FileHandle f)
	{
		bool ret = true;
		DWORD dummy;

		if(!GetHandleInformation(f, &dummy))
		{
			if(GetLastError() == ERROR_INVALID_HANDLE)
				ret = false;

			SetLastError(ERROR_SUCCESS);
		}

		return ret;
	}

	int64_t read(CrocThread* t, FileHandle f, DArray<uint8_t> data)
	{
		DWORD bytesRead;

		if(!ReadFile(f, cast(LPVOID)data.ptr, cast(DWORD)data.length, &bytesRead, nullptr))
		{
			pushSystemErrorMsg(t);
			return -1;
		}

		return cast(int64_t)bytesRead;
	}

	int64_t write(CrocThread* t, FileHandle f, DArray<uint8_t> data)
	{
		DWORD bytesWritten;

		if(!WriteFile(f, cast(LPVOID)data.ptr, cast(DWORD)data.length, &bytesWritten, nullptr))
		{
			pushSystemErrorMsg(t);
			return -1;
		}

		return cast(int64_t)bytesWritten;
	}

	uint64_t seek(CrocThread* t, FileHandle f, uint64_t pos, Whence whence)
	{
		LARGE_INTEGER newPos;

		if(!SetFilePointerEx(f, *cast(LARGE_INTEGER*)&pos, &newPos, cast(DWORD)whence))
		{
			pushSystemErrorMsg(t);
			return cast(uint64_t)-1;
		}

		return *cast(uint64_t*)&newPos;
	}

	bool flush(CrocThread* t, FileHandle f)
	{
		auto ret = FlushFileBuffers(f);

		if(!ret)
			pushSystemErrorMsg(t);

		return ret;
	}

	bool close(CrocThread* t, FileHandle f)
	{
		auto ret = CloseHandle(f);

		if(!ret)
			pushSystemErrorMsg(t);

		return ret;
	}
#else
#error "Unimplemented"

	bool isValidHandle(FileHandle f)
	{
		bool ret = true;

		if(fcntl(f, F_GETFL) == -1)
		{
			if(errno == EBADF)
				ret = false;

			errno = 0;
		}

		return ret;
	}
#endif
	}
}