
#include "croc/api.h"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/types/base.hpp"
#include "croc/util/utf.hpp"

#ifndef _WIN32
#include <dirent.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/time.h>

#include "croc/util/str.hpp"
#endif

namespace croc
{
	namespace oscompat
	{
	// =================================================================================================================
	// Error handling
	void throwIOEx(CrocThread* t)
	{
		croc_eh_pushStd(t, "IOException");
		croc_pushNull(t);
		croc_moveToTop(t, -3);
		croc_call(t, -3, 1);
		croc_eh_throw(t);
	}

	void throwOSEx(CrocThread* t)
	{
		croc_eh_pushStd(t, "OSException");
		croc_pushNull(t);
		croc_moveToTop(t, -3);
		croc_call(t, -3, 1);
		croc_eh_throw(t);
	}

#ifdef _WIN32
	extern "C" int _fileno(FILE* f);
	extern "C" int _get_osfhandle(int h);
	extern "C" FILE* _popen(const char* cmd, const char* mode);
	extern "C" int _pclose(FILE* p);

	namespace
	{
		wstring _utf8ToUtf16z(Memory& mem, crocstr src, wstring localBuf, wstring& heapBuf)
		{
			heapBuf = wstring();
			auto size16 = fastUtf8GetUtf16Size(src);
			auto ret = wstring();
			auto remaining = custring();

			if(size16 + 1 > localBuf.length) // +1 cause we need to put the terminating 0
			{
				heapBuf = wstring::alloc(mem, size16 + 1);
				ret = Utf8ToUtf16(src, heapBuf, remaining);
			}
			else
				ret = Utf8ToUtf16(src, localBuf, remaining);

			assert(ret.length == size16);
			assert(remaining.length == 0);
			ret.ptr[ret.length] = 0;
			return ret;
		}

		bool _pushUtf16toUtf8(CrocThread* t, cwstring src)
		{
			auto &mem = Thread::from(t)->vm->mem;
			auto size8 = fastUtf16GetUtf8Size(src);
			auto out = mcrocstr::alloc(mem, size8);
			cwstring remaining;
			mcrocstr output;

			if(Utf16ToUtf8(src, out, remaining, output) == UtfError_OK)
			{
				assert(output.length == out.length);
				assert(remaining.length == 0);
				pushCrocstr(t, out);
				out.free(mem);
				return true;
			}
			else
			{
				out.free(mem);
				return false;
			}
		}

		cwstring _getNextUtf16z(const wchar*& ptr)
		{
			auto start = ptr;
			auto len = 0;

			while(*ptr++)
				len++;

			return cwstring::n(start, len);
		}

		FileType _attrsToType(DWORD attrs)
		{
			return
				(attrs & FILE_ATTRIBUTE_DIRECTORY) ? FileType::Dir :
				(attrs & FILE_ATTRIBUTE_REPARSE_POINT) ? FileType::Link :
				(attrs & FILE_ATTRIBUTE_DEVICE) ? FileType::Other :
				FileType::File;
		}

		const uint64_t UnixEpochDiff = 11644473600000000LL;

		Time _filetimeToTime(FILETIME time)
		{
			ULARGE_INTEGER inttime;
			inttime.HighPart = time.dwHighDateTime;
			inttime.LowPart = time.dwLowDateTime;
			return cast(Time)((inttime.QuadPart / 10) - UnixEpochDiff);
		}

		FILETIME _timeToFiletime(Time time)
		{
			time += UnixEpochDiff;
			time *= 10;
			ULARGE_INTEGER inttime;
			inttime.QuadPart = time;
			FILETIME ret;
			ret.dwHighDateTime = inttime.HighPart;
			ret.dwLowDateTime = inttime.LowPart;
			return ret;
		}

		void _toWindowsPath(wstring s)
		{
			for(auto &c: s)
			{
				if(c == '/')
					c = '\\';
			}
		}

		void toCommonPath(wstring s)
		{
			for(auto &c: s)
			{
				if(c == '\\')
					c = '/';
			}
		}
	}

	void pushSystemErrorMsg(CrocThread* t)
	{
		auto errCode = GetLastError();

		LPCWSTR msg16;
		auto size16 = FormatMessageW(
			FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
			nullptr, errCode, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), cast(LPWSTR)&msg16, 0, nullptr);

		if(size16 == 0)
			croc_pushString(t, "<error formatting system message>");
		else
		{
			// Get rid of \r\n
			if(size16 >= 2)
				size16 -= 2;

			if(!_pushUtf16toUtf8(t, cwstring::n(cast(const wchar*)msg16, size16)))
				croc_pushString(t, "<error formatting system message>");

			LocalFree(cast(HLOCAL)msg16);
		}
	}

	// =================================================================================================================
	// File streams

	FileHandle openFile(CrocThread* t, crocstr name, FileAccess access, FileCreate create)
	{
		auto &mem = Thread::from(t)->vm->mem;

		// Convert name to UTF-16, the best encoding
		wchar buf[512];
		wstring heapBuf;
		auto name16 = _utf8ToUtf16z(mem, name, wstring::n(buf, sizeof(buf) / sizeof(wchar)), heapBuf);
		_toWindowsPath(name16);

		// Open it!
		auto ret = CreateFileW(cast(LPCWSTR)name16.ptr, cast(DWORD)access, 0,
			nullptr, cast(DWORD)create, FILE_ATTRIBUTE_NORMAL, nullptr);

		heapBuf.free(mem);

		if(ret == INVALID_HANDLE_VALUE)
			pushSystemErrorMsg(t);
		else
			SetLastError(ERROR_SUCCESS); // Some of the file open modes set the error even if successful?! silly

		return ret;
	}

	bool truncate(CrocThread* t, FileHandle f)
	{
		if(SetEndOfFile(f) == 0)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		return true;
	}

	FileHandle fromCFile(CrocThread* t, FILE* f)
	{
		if(fflush(f) != EOF)
		{
			auto fd = _fileno(f);

			if(fd != -1 && fd != -2) // -2 is for stdout/stderr which aren't mapped to output streams..?
			{
				auto h = cast(HANDLE)cast(uword)_get_osfhandle(fd);

				if(h != INVALID_HANDLE_VALUE)
				{
					if(isValidHandle(h))
						return h;

					croc_pushString(t, "Invalid file handle");
					return InvalidHandle;
				}
			}
		}

		pushSystemErrorMsg(t);
		return InvalidHandle;
	}

	// =================================================================================================================
	// Console streams

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

	// =================================================================================================================
	// General-purpose streams

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

	_retry:
		if(!ReadFile(f, cast(LPVOID)data.ptr, cast(DWORD)data.length, &bytesRead, nullptr))
		{
			if(GetLastError() == ERROR_BROKEN_PIPE)
			{
				SetLastError(ERROR_SUCCESS);
				return 0;
			}

			pushSystemErrorMsg(t);
			return -1;
		}

		if(GetLastError() == ERROR_OPERATION_ABORTED)
		{
			SetLastError(ERROR_SUCCESS);
			goto _retry;
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
		// Ignore failed flushes on file types that don't support them
		if(!FlushFileBuffers(f) && GetLastError() != ERROR_INVALID_HANDLE)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		SetLastError(ERROR_SUCCESS);
		return true;
	}

	bool close(CrocThread* t, FileHandle f)
	{
		auto ret = CloseHandle(f);

		if(!ret)
			pushSystemErrorMsg(t);

		return ret;
	}

	// =================================================================================================================
	// Environment variables

	bool getEnv(CrocThread* t, crocstr name)
	{
		auto &mem = Thread::from(t)->vm->mem;

		// Convert name to UTF-16
		wchar buf[32];
		wstring nameBuf;
		auto name16 = _utf8ToUtf16z(mem, name, wstring::n(buf, sizeof(buf) / sizeof(wchar)), nameBuf);

		// Get the env var value
		auto valSize16 = GetEnvironmentVariableW(cast(LPCWSTR)name16.ptr, nullptr, 0);

		if(valSize16 == 0)
		{
			nameBuf.free(mem);

			if(GetLastError() == ERROR_ENVVAR_NOT_FOUND)
			{
				SetLastError(ERROR_SUCCESS);
				return false;
			}
			else
			{
				pushSystemErrorMsg(t);
				throwOSEx(t);
			}
		}

		auto val16 = wstring::alloc(mem, valSize16);
		auto failed = GetEnvironmentVariableW(cast(LPCWSTR)name16.ptr, cast(LPWSTR)val16.ptr, valSize16) == 0;
		nameBuf.free(mem);

		if(failed)
		{
			val16.free(mem);
			pushSystemErrorMsg(t);
			throwOSEx(t);
		}

		// Convert it to UTF-8
		auto ok = _pushUtf16toUtf8(t, val16.slice(0, val16.length - 1)); // strip trailing \0 from value
		val16.free(mem);

		if(!ok)
			croc_eh_throwStd(t, "UnicodeError", "Error transcoding environment variable to UTF-8");

		return true;
	}

	void setEnv(CrocThread* t, crocstr name, crocstr val)
	{
		auto &mem = Thread::from(t)->vm->mem;
		wchar buf1[32], buf2[128];
		wstring nameBuf, valBuf;
		auto name16 = _utf8ToUtf16z(mem, name, wstring::n(buf1, sizeof(buf1) / sizeof(wchar)), nameBuf);
		BOOL ok;

		if(val.length)
		{
			auto val16 = _utf8ToUtf16z(mem, val, wstring::n(buf2, sizeof(buf2) / sizeof(wchar)), valBuf);
			ok = SetEnvironmentVariableW(cast(LPCWSTR)name16.ptr, cast(LPCWSTR)val16.ptr);
			valBuf.free(mem);
		}
		else
			ok = SetEnvironmentVariableW(cast(LPCWSTR)name16.ptr, nullptr);

		nameBuf.free(mem);

		if(!ok)
		{
			pushSystemErrorMsg(t);
			throwOSEx(t);
		}
	}

	void getAllEnvVars(CrocThread* t)
	{
		auto env = cast(const wchar*)GetEnvironmentStringsW();

		if(env == nullptr)
		{
			pushSystemErrorMsg(t);
			throwOSEx(t);
		}

		croc_table_new(t, 0);

		for(auto line = _getNextUtf16z(env); line.length != 0; line = _getNextUtf16z(env))
		{
			uword splitPos = 0;

			for( ; splitPos < line.length; splitPos++)
			{
				if(line[splitPos] == '=')
					break;
			}

			if(!_pushUtf16toUtf8(t, line.slice(0, splitPos)) || !_pushUtf16toUtf8(t, line.sliceToEnd(splitPos + 1)))
			{
				FreeEnvironmentStringsW(cast(LPWSTR)env);
				croc_eh_throwStd(t, "UnicodeError", "Error transcoding environment variable to UTF-8");
			}

			croc_idxa(t, -3);
		}

		FreeEnvironmentStringsW(cast(LPWSTR)env);
	}

	// =================================================================================================================
	// FS stuff

	bool listDir(CrocThread* t, crocstr path, bool includeHidden, std::function<bool(FileType)> dg)
	{
		pushCrocstr(t, path);

		if(path.length > 0 && path[path.length - 1] == '/')
			croc_pushString(t, "*");
		else
			croc_pushString(t, "/*");

		croc_cat(t, 2);
		path = getCrocstr(t, -1);

		auto &mem = Thread::from(t)->vm->mem;
		wchar pathBuf[512];
		wstring pathHeapBuf;
		auto path16 = _utf8ToUtf16z(mem, path, wstring::n(pathBuf, sizeof(pathBuf) / sizeof(wchar)), pathHeapBuf);
		croc_popTop(t);
		_toWindowsPath(path16);
		WIN32_FIND_DATAW data;
		auto dir = FindFirstFileW(cast(LPCWSTR)path16.ptr, &data);
		pathHeapBuf.free(mem);

		if(dir == INVALID_HANDLE_VALUE)
		{
			// Just an empty dir?
			if(GetLastError() == ERROR_FILE_NOT_FOUND)
			{
				SetLastError(ERROR_SUCCESS);
				return true;
			}

			pushSystemErrorMsg(t);
			return false;
		}

		auto slot = croc_pushNull(t);
		auto failed = tryCode(Thread::from(t), slot, [&]
		{
			while(true)
			{
				if(!_pushUtf16toUtf8(t, cwstring::n(cast(const wchar*)data.cFileName, wcslen(data.cFileName))))
					croc_eh_throwStd(t, "UnicodeError", "Error converting filename to UTF-8");

				auto name = getCrocstr(t, -1);

				if(name != ATODA(".") && name != ATODA(".."))
				{
					if(includeHidden || (data.dwFileAttributes & (FILE_ATTRIBUTE_SYSTEM | FILE_ATTRIBUTE_HIDDEN)) == 0)
					{
						if(!dg(_attrsToType(data.dwFileAttributes)))
						{
							croc_popTop(t);
							break;
						}
					}
				}

				croc_popTop(t);

				if(!FindNextFileW(dir, &data))
				{
					if(GetLastError() == ERROR_NO_MORE_FILES)
					{
						SetLastError(ERROR_SUCCESS);
						return;
					}

					pushSystemErrorMsg(t);
					throwOSEx(t);
				}
			}
		});

		FindClose(dir);

		if(failed)
			croc_eh_rethrow(t);

		assert(croc_getStackSize(t) - 1 == cast(uword)slot);
		croc_popTop(t);
		return true;
	}

	bool pushCurrentDir(CrocThread* t)
	{
		auto len = GetCurrentDirectoryW(0, nullptr);

		if(len == 0)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		auto &mem = Thread::from(t)->vm->mem;
		auto tmp = wstring::alloc(mem, len);

		if(GetCurrentDirectoryW(len, cast(LPWSTR)tmp.ptr) == 0)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		for(auto &c: tmp)
		{
			if(c == '\\')
				c = '/';
		}

		_pushUtf16toUtf8(t, tmp.slice(0, tmp.length - 1)); // slice off terminating 0
		tmp.free(mem);
		return true;
	}

	bool changeDir(CrocThread* t, crocstr path)
	{
		auto &mem = Thread::from(t)->vm->mem;
		wchar buf[512];
		wstring heapBuf;
		auto path16 = _utf8ToUtf16z(mem, path, wstring::n(buf, sizeof(buf) / sizeof(wchar)), heapBuf);
		_toWindowsPath(path16);
		auto ok = SetCurrentDirectoryW(cast(LPCWSTR)path16.ptr);
		heapBuf.free(mem);

		if(ok)
			return true;
		else
		{
			pushSystemErrorMsg(t);
			return false;
		}
	}

	bool makeDir(CrocThread* t, crocstr path)
	{
		auto &mem = Thread::from(t)->vm->mem;
		wchar buf[512];
		wstring heapBuf;
		auto path16 = _utf8ToUtf16z(mem, path, wstring::n(buf, sizeof(buf) / sizeof(wchar)), heapBuf);
		_toWindowsPath(path16);
		auto ok = CreateDirectoryW(cast(LPCWSTR)path16.ptr, nullptr) != 0;
		heapBuf.free(mem);

		if(ok)
			return true;
		else
		{
			pushSystemErrorMsg(t);
			return false;
		}
	}

	bool removeDir(CrocThread* t, crocstr path)
	{
		auto &mem = Thread::from(t)->vm->mem;
		wchar buf[512];
		wstring heapBuf;
		auto path16 = _utf8ToUtf16z(mem, path, wstring::n(buf, sizeof(buf) / sizeof(wchar)), heapBuf);
		_toWindowsPath(path16);
		auto ok = RemoveDirectoryW(cast(LPCWSTR)path16.ptr) != 0;
		heapBuf.free(mem);

		if(ok)
			return true;
		else
		{
			pushSystemErrorMsg(t);
			return false;
		}
	}

	bool getInfo(CrocThread* t, crocstr name, FileInfo* info)
	{
		auto &mem = Thread::from(t)->vm->mem;
		wchar buf[512];
		wstring heapBuf;
		auto name16 = _utf8ToUtf16z(mem, name, wstring::n(buf, sizeof(buf) / sizeof(wchar)), heapBuf);
		_toWindowsPath(name16);

		WIN32_FILE_ATTRIBUTE_DATA data;
		auto ret = GetFileAttributesExW(cast(LPCWSTR)name16.ptr, GetFileExInfoStandard, &data);
		heapBuf.free(mem);

		if(ret && info != nullptr)
		{
			info->size = (cast(uint64_t)data.nFileSizeHigh << 32) + data.nFileSizeLow;
			info->type = _attrsToType(data.dwFileAttributes);
			info->created = _filetimeToTime(data.ftCreationTime);
			info->modified = _filetimeToTime(data.ftLastWriteTime);
			info->accessed = _filetimeToTime(data.ftLastAccessTime);
		}

		return cast(bool)ret;
	}

	bool copyFromTo(CrocThread* t, crocstr from, crocstr to, bool force)
	{
		auto &mem = Thread::from(t)->vm->mem;
		wchar buf1[512], buf2[512];
		wstring heapBuf1, heapBuf2;
		auto from16 = _utf8ToUtf16z(mem, from, wstring::n(buf1, sizeof(buf1) / sizeof(wchar)), heapBuf1);
		auto to16 = _utf8ToUtf16z(mem, to, wstring::n(buf2, sizeof(buf2) / sizeof(wchar)), heapBuf2);
		_toWindowsPath(from16);
		_toWindowsPath(to16);

		auto ok = CopyFileW(cast(LPCWSTR)from16.ptr, cast(LPCWSTR)to16.ptr, !force);
		heapBuf1.free(mem);
		heapBuf2.free(mem);

		if(!ok)
			pushSystemErrorMsg(t);

		return cast(bool)ok;
	}

	bool moveFromTo(CrocThread* t, crocstr from, crocstr to, bool force)
	{
		auto &mem = Thread::from(t)->vm->mem;
		wchar buf1[512], buf2[512];
		wstring heapBuf1, heapBuf2;
		auto from16 = _utf8ToUtf16z(mem, from, wstring::n(buf1, sizeof(buf1) / sizeof(wchar)), heapBuf1);
		auto to16 = _utf8ToUtf16z(mem, to, wstring::n(buf2, sizeof(buf2) / sizeof(wchar)), heapBuf2);
		_toWindowsPath(from16);
		_toWindowsPath(to16);

		auto ok = MoveFileExW(cast(LPCWSTR)from16.ptr, cast(LPCWSTR)to16.ptr,
			MOVEFILE_COPY_ALLOWED | MOVEFILE_WRITE_THROUGH | (force ? MOVEFILE_REPLACE_EXISTING : 0));
		heapBuf1.free(mem);
		heapBuf2.free(mem);

		if(!ok)
			pushSystemErrorMsg(t);

		return cast(bool)ok;
	}

	bool remove(CrocThread* t, crocstr path)
	{
		auto &mem = Thread::from(t)->vm->mem;
		wchar buf[512];
		wstring heapBuf;
		auto path16 = _utf8ToUtf16z(mem, path, wstring::n(buf, sizeof(buf) / sizeof(wchar)), heapBuf);
		_toWindowsPath(path16);

		auto attrs = GetFileAttributesW(cast(LPCWSTR)path16.ptr);

		if(attrs == INVALID_FILE_ATTRIBUTES)
		{
			heapBuf.free(mem);
			pushSystemErrorMsg(t);
			return false;
		}

		auto ok = (attrs & FILE_ATTRIBUTE_DIRECTORY) ?
			RemoveDirectoryW(cast(LPCWSTR)path16.ptr) :
			DeleteFileW(cast(LPCWSTR)path16.ptr);
		heapBuf.free(mem);

		if(!ok)
			pushSystemErrorMsg(t);

		return cast(bool)ok;
	}

	// =================================================================================================================
	// Time

	bool timeInitialized = false;
	uint64_t perfCounterFreq;

	void initTime()
	{
		if(!timeInitialized)
		{
			timeInitialized = true;
			// This only fails on pre-XP/2000 systems lol
			QueryPerformanceFrequency(cast(PLARGE_INTEGER)&perfCounterFreq);
		}
	}

	uint64_t microTime()
	{
		uint64_t ret;
		QueryPerformanceCounter(cast(PLARGE_INTEGER)&ret);
		return (ret * 1000000) / perfCounterFreq;
	}

	Time sysTime()
	{
		FILETIME ret;
		GetSystemTimeAsFileTime(&ret);
		return _filetimeToTime(ret);
	}

	DateTime timeToDateTime(Time t, bool isLocal)
	{
		auto ft = _timeToFiletime(t);
		SYSTEMTIME st;

		if(isLocal)
		{
			FILETIME local;
			FileTimeToLocalFileTime(&ft, &local);
			FileTimeToSystemTime(&local, &st);
		}
		else
			FileTimeToSystemTime(&ft, &st);

		DateTime ret;
		ret.year = st.wYear;
		ret.month = st.wMonth;
		ret.day = st.wDay;
		ret.hour = st.wHour;
		ret.min = st.wMinute;
		ret.sec = st.wSecond;
		ret.msec = st.wMilliseconds;
		return ret;
	}

	Time dateTimeToTime(DateTime t, bool isLocal)
	{
		SYSTEMTIME st;
		st.wYear = t.year;
		st.wMonth = t.month;
		st.wDay = t.day;
		st.wHour = t.hour;
		st.wMinute = t.min;
		st.wSecond = t.sec;
		st.wMilliseconds = t.msec;

		FILETIME ft;
		SystemTimeToFileTime(&st, &ft);

		if(isLocal)
		{
			FILETIME utc;
			LocalFileTimeToFileTime(&ft, &utc);
			return _filetimeToTime(utc);
		}
		else
			return _filetimeToTime(ft);
	}

	// =================================================================================================================
	// Threading

	void sleep(uword msec)
	{
		Sleep(msec);
	}

	// =================================================================================================================
	// Threading

	ProcessHandle openProcess(CrocThread* t, crocstr cmd, FileAccess access)
	{
		if(auto ret = _popen(cast(const char*)cmd.ptr, access == FileAccess::Read ? "rb" : "wb"))
			return ret;

		croc_pushString(t, strerror(errno));
		throwOSEx(t);
		return nullptr; // dummy
	}

	FileHandle getProcessStream(CrocThread* t, ProcessHandle p)
	{
		return fromCFile(t, p);
	}

	int closeProcess(CrocThread* t, ProcessHandle p)
	{
		auto ret = _pclose(p);

		if(ret != -1)
			return ret;

		croc_pushString(t, strerror(errno));
		throwOSEx(t);
		return 0; // dummy
	}

#else
	namespace
	{
		FileType _statsToType(struct stat& stats)
		{
			return (stats.st_mode & S_IFDIR) ? FileType::Dir :
				(stats.st_mode & S_IFREG) ? FileType::File :
				FileType::Other;
		}

		Time timetToTime(time_t time)
		{
			return (cast(Time)time) * 1000;
		}

		time_t TimetoTimet(Time time)
		{
			return cast(time_t)(time / 1000);
		}
	}

	void pushSystemErrorMsg(CrocThread* t)
	{
		croc_pushString(t, strerror(errno));
	}

	// =================================================================================================================
	// File streams

	FileHandle openFile(CrocThread* t, crocstr name, FileAccess access, FileCreate create)
	{
		auto ret = open(cast(const char*)name.ptr, cast(int)create | cast(int)access | O_LARGEFILE, 0666);

		if(ret == -1)
		{
			pushSystemErrorMsg(t);
			return InvalidHandle;
		}

		return ret;
	}

	bool truncate(CrocThread* t, FileHandle f)
	{
		auto pos = lseek(f, 0, SEEK_CUR);

		if(pos == -1 || ftruncate(f, pos) == -1)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		return true;
	}

	FileHandle fromCFile(CrocThread* t, FILE* f)
	{
		auto ret = fileno(f);

		if(ret == -1)
		{
			pushSystemErrorMsg(t);
			return InvalidHandle;
		}

		return ret;
	}

	// =================================================================================================================
	// Console streams

	FileHandle getStdin(CrocThread* t)
	{
		(void)t;
		return STDIN_FILENO;
	}

	FileHandle getStdout(CrocThread* t)
	{
		(void)t;
		return STDOUT_FILENO;
	}

	FileHandle getStderr(CrocThread* t)
	{
		(void)t;
		return STDERR_FILENO;
	}

	// =================================================================================================================
	// General-purpose streams

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

	int64_t read(CrocThread* t, FileHandle f, DArray<uint8_t> data)
	{
		auto bytesRead = ::read(f, data.ptr, data.length);

		if(bytesRead == -1)
			pushSystemErrorMsg(t);

		return bytesRead;
	}

	int64_t write(CrocThread* t, FileHandle f, DArray<uint8_t> data)
	{
		auto bytesWritten = ::write(f, data.ptr, data.length);

		if(bytesWritten == -1)
			pushSystemErrorMsg(t);

		return bytesWritten;
	}

	uint64_t seek(CrocThread* t, FileHandle f, uint64_t pos, Whence whence)
	{
		auto newPos = lseek(f, pos, cast(int)whence);

		if(newPos == -1)
			pushSystemErrorMsg(t);

		return cast(uint64_t)newPos;
	}

	bool flush(CrocThread* t, FileHandle f)
	{
		// Ignore failed fsyncs on file types that don't support them
		if(fsync(f) == -1 && errno != EROFS && errno != EINVAL)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		errno = 0;
		return true;
	}

	bool close(CrocThread* t, FileHandle f)
	{
		if(::close(f) == -1)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		return true;
	}

	// =================================================================================================================
	// Environment variables

	bool getEnv(CrocThread* t, crocstr name)
	{
		auto val = getenv(cast(const char*)name.ptr);

		if(val == nullptr)
			return false;

		croc_pushString(t, val);
		return true;
	}

	void setEnv(CrocThread* t, crocstr name, crocstr val)
	{
		auto ok = (val.length == 0) ?
			unsetenv(cast(const char*)name.ptr) :
			setenv(cast(const char*)name.ptr, cast(const char*)val.ptr, true);

		if(ok == -1)
		{
			pushSystemErrorMsg(t);
			throwOSEx(t);
		}
	}

	void getAllEnvVars(CrocThread* t)
	{
		croc_table_new(t, 0);

		for(auto pvarLine = environ; *pvarLine != nullptr; pvarLine++)
		{
			auto varLine = atoda(*pvarLine);
			auto eqPos = strLocateChar(varLine, '=');

			croc_pushStringn(t, cast(const char*)varLine.ptr, eqPos);
			eqPos++;
			croc_pushStringn(t, cast(const char*)(varLine.ptr + eqPos), varLine.length - eqPos);
			croc_idxa(t, -3);
		}
	}

	// =================================================================================================================
	// FS stuff

	bool listDir(CrocThread* t, crocstr path, bool includeHidden, std::function<bool(FileType)> dg)
	{
		auto pathSlot = pushCrocstr(t, path);

		if(path.length > 0 && path[path.length - 1] != '/')
		{
			pushCrocstr(t, ATODA("/"));
			croc_cat(t, 2);
			path = getCrocstr(t, pathSlot);
		}

		auto dir = opendir(cast(const char*)path.ptr);

		if(dir == nullptr)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		auto slot = croc_pushNull(t);
		auto failed = tryCode(Thread::from(t), slot, [&]
		{
			while(true)
			{
				errno = 0;
				auto entry = readdir(dir);

				if(entry == nullptr)
				{
					if(errno == 0)
						break;
					else
					{
						pushSystemErrorMsg(t);
						throwOSEx(t);
					}
				}

				croc_dup(t, pathSlot);
				croc_pushString(t, entry->d_name);
				croc_cat(t, 2);
				auto realName = getCrocstr(t, -1);

				struct stat statBuf;

				if(lstat(cast(const char*)realName.ptr, &statBuf) == -1)
				{
					pushSystemErrorMsg(t);
					croc_pushFormat(t, "could not stat '%s': ", cast(const char*)realName.ptr);
					croc_swapTop(t);
					croc_cat(t, 2);
					throwOSEx(t);
				}

				bool cont = true;

				if(realName != ATODA(".") && realName != ATODA(".."))
				{
					if(includeHidden || (realName.length && realName[0] != '.'))
						cont = dg(_statsToType(statBuf));
				}

				croc_popTop(t);

				if(!cont)
					break;
			}
		});

		closedir(dir);

		if(failed)
			croc_eh_rethrow(t);

		assert(croc_getStackSize(t) - 1 == cast(uword)slot);
		croc_pop(t, 2); // EH null and path
		return true;
	}

	bool pushCurrentDir(CrocThread* t)
	{
		auto t_ = Thread::from(t);
		auto buf = DArray<char>::alloc(t_->vm->mem, 256);

		while(getcwd(buf.ptr, buf.length) == nullptr)
		{
			if(errno == ERANGE)
				buf.resize(t_->vm->mem, buf.length * 2);
			else
			{
				buf.free(t_->vm->mem);
				pushSystemErrorMsg(t);
				return false;
			}
		}

		auto slice = buf.slice(0, strlen(cast(const char*)buf.ptr)).template as<const uchar>();

		uword cpLen;
		auto ok = verifyUtf8(slice, cpLen);

		if(ok == UtfError_OK)
			push(t_, Value::from(String::createUnverified(t_->vm, slice, cpLen)));

		buf.free(t_->vm->mem);

		if(ok != UtfError_OK)
			croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

		return true;
	}

	bool changeDir(CrocThread* t, crocstr path)
	{
		if(chdir(cast(const char*)path.ptr) == -1)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		return true;
	}

	bool makeDir(CrocThread* t, crocstr path)
	{
		if(mkdir(cast(const char*)path.ptr, 0777) == -1)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		return true;
	}

	bool removeDir(CrocThread* t, crocstr path)
	{
		if(rmdir(cast(const char*)path.ptr) == -1)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		return true;
	}

	bool getInfo(CrocThread* t, crocstr name, FileInfo* info)
	{
		struct stat statBuf;

		if(lstat(cast(const char*)name.ptr, &statBuf) == -1)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		if(info)
		{
			info->size = statBuf.st_size;
			info->type = _statsToType(statBuf);
			info->created = timetToTime(statBuf.st_ctime);
			info->modified = timetToTime(statBuf.st_mtime);
			info->accessed = timetToTime(statBuf.st_atime);
		}

		return true;
	}

	bool copyFromTo(CrocThread* t, crocstr from, crocstr to, bool force)
	{
		bool ret = true;
		auto srcfd = open(cast(const char*)from.ptr, O_RDONLY, cast(int)FileCreate::OpenExisting);

		if(srcfd == -1)
		{
			pushSystemErrorMsg(t);
			croc_pushFormat(t, "Error opening source file '%s': ", cast(const char*)from.ptr);
			croc_swapTop(t);
			croc_cat(t, 2);
			ret = false;
		}
		else
		{
			struct stat srcStat, dstStat;

			if(fstat(srcfd, &srcStat) == -1)
			{
				pushSystemErrorMsg(t);
				ret = false;
			}
			else if(!S_ISREG(srcStat.st_mode))
			{
				croc_pushString(t, "source file is not a regular file");
				ret = false;
			}
			else
			{
				auto dstfd = open(cast(const char*)to.ptr,
					O_WRONLY | cast(int)(force ? FileCreate::CreateIfNeeded : FileCreate::MustNotExist),
					srcStat.st_mode & (S_IRWXU | S_IRWXG | S_IRWXO));

				if(dstfd == -1)
				{
					pushSystemErrorMsg(t);
					croc_pushFormat(t, "Error opening destination file '%s': ", cast(const char*)to.ptr);
					croc_swapTop(t);
					croc_cat(t, 2);
					ret = false;
				}
				else
				{
					if(fstat(dstfd, &dstStat) == -1)
					{
						pushSystemErrorMsg(t);
						ret = false;
					}
					else if(!S_ISREG(dstStat.st_mode))
					{
						croc_pushString(t, "destination file is not a regular file");
						ret = false;
					}
					else
					{
						auto mem = Thread::from(t)->vm->mem;
						auto buffer = DArray<uint8_t>::alloc(mem, 65536);

						while(true)
						{
							auto bytesRead = ::read(srcfd, buffer.ptr, buffer.length);

							if(bytesRead == -1)
							{
								pushSystemErrorMsg(t);
								ret = false;
								break;
							}
							else if(bytesRead == 0)
								break;

							auto srcPtr = buffer.ptr;
							auto bytesLeft = bytesRead;

							while(bytesLeft)
							{
								auto bytesWritten = ::write(dstfd, srcPtr, bytesLeft);

								if(bytesWritten == -1)
								{
									pushSystemErrorMsg(t);
									ret = false;
									goto _breakOuter;
								}

								bytesLeft -= bytesWritten;
								srcPtr += bytesWritten;
							}
						}

					_breakOuter:;
					}

					::close(dstfd);
				}
			}

			::close(srcfd);
		}

		return ret;
	}

	bool moveFromTo(CrocThread* t, crocstr from, crocstr to, bool force)
	{
		if(!force)
		{
			if(getInfo(t, to, nullptr))
				return false;

			croc_popTop(t); // when getInfo returns false, it leaves the error message on the stack
		}

		if(rename(cast(const char*)from.ptr, cast(const char*)to.ptr) == -1)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		return true;
	}

	bool remove(CrocThread* t, crocstr path)
	{
		if(::remove(cast(const char*)path.ptr) == -1)
		{
			pushSystemErrorMsg(t);
			return false;
		}

		return true;
	}

	// =================================================================================================================
	// Time

	void initTime()
	{
		// do nothing!
	}

	uint64_t microTime()
	{
		timeval time;
		gettimeofday(&time, nullptr);
		return (time.tv_sec * 1000000) + time.tv_usec;
	}

	Time sysTime()
	{
		timeval time;
		gettimeofday(&time, nullptr);
		return timetToTime(time.tv_sec);
	}

	DateTime timeToDateTime(Time time, bool isLocal)
	{
		struct tm result;
		auto secs = TimetoTimet(time);

		auto ok = isLocal ? localtime_r(&secs, &result) : gmtime_r(&secs, &result);

		// Only time this happens is with overflow, so..
		if(ok == nullptr)
		{
			secs = 0;
			isLocal ? localtime_r(&secs, &result) : gmtime_r(&secs, &result);
		}

		DateTime ret;
		ret.year = result.tm_year + 1900;
		ret.month = result.tm_mon + 1; // since it goes from [0 .. 11]
		ret.day = result.tm_mday;
		ret.hour = result.tm_hour;
		ret.min = result.tm_min;
		ret.sec = result.tm_sec;
		ret.msec = 0;
		return ret;
	}

	Time dateTimeToTime(DateTime time, bool isLocal)
	{
		struct tm tmtime;
		memset(&tmtime, 0, sizeof(struct tm));
		tmtime.tm_year = time.year - 1900;
		tmtime.tm_mon = time.month - 1; // since it goes from [0 .. 11]
		tmtime.tm_mday = time.day;
		tmtime.tm_hour = time.hour;
		tmtime.tm_min = time.min;
		tmtime.tm_sec = time.sec;
		tmtime.tm_isdst = -1;

		time_t ret = -1;

		if(isLocal)
			ret = mktime(&tmtime);
		else
		{
			if(mktime(&tmtime) != -1) // to fill in tm_yday
			{
				ret =
					tmtime.tm_sec + tmtime.tm_min * 60 + tmtime.tm_hour * 3600 + tmtime.tm_yday * 86400 +
					(tmtime.tm_year - 70) * 31536000 + ((tmtime.tm_year - 69) / 4) * 86400 -
					((tmtime.tm_year - 1) / 100) * 86400 + ((tmtime.tm_year+299) / 400) * 86400;
			}
		}

		if(ret == -1)
			return 0;
		else
			return timetToTime(ret);
	}

	// =================================================================================================================
	// Threading

	void sleep(uword msec)
	{
		timespec wanted, remaining;

		if(msec == 0)
			msec = 1;

		wanted.tv_sec = msec / 1000;
		wanted.tv_nsec = (msec % 1000) * 1000000;

		while(nanosleep(&wanted, &remaining) == -1)
		{
			if(errno == EINTR)
				wanted = remaining;
			else
				break; // hrm
		}
	}
#endif
	}
}