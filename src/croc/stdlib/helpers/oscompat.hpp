#ifndef CROC_STDLIB_HELPERS_OSCOMPAT_HPP
#define CROC_STDLIB_HELPERS_OSCOMPAT_HPP

#ifdef _WIN32
#include "windows.h"
#else
#include "unistd.h"
#endif

#include "croc/types/base.hpp"

namespace croc
{
	namespace oscompat
	{
#ifdef _WIN32
	typedef HANDLE FileHandle;
	const FileHandle InvalidHandle = INVALID_HANDLE_VALUE;

	enum class FileAccess : DWORD
	{
		Read = GENERIC_READ,
		Write = GENERIC_WRITE,
		ReadWrite = GENERIC_READ | GENERIC_WRITE
	};

	enum class FileCreate : DWORD
	{
		OpenExisting = OPEN_EXISTING,
		CreateIfNeeded = CREATE_ALWAYS,
		Append = OPEN_ALWAYS,
		MustNotExist = CREATE_NEW
	};

	enum class Whence : DWORD
	{
		Begin = FILE_BEGIN,
		Current = FILE_CURRENT,
		End = FILE_END
	};
#else
	typedef int FileHandle;
	const FileHandle InvalidHandle = -1;

	enum class FileAccess
	{
		Read = O_RDONLY,
		Write = O_WRONLY,
		ReadWrite = O_RDWR
	};

	enum class FileCreate
	{
		OpenExisting = 0,
		CreateIfNeeded = O_CREAT | O_TRUNC,
		Append = O_CREAT,
		MustNotExist = O_CREAT | O_EXCL
	};

	enum class Whence : DWORD
	{
		Begin = SEEK_SET,
		Current = SEEK_CUR,
		End = SEEK_END
	};
#endif

	static_assert(sizeof(FileHandle) <= sizeof(void*), "Can't fit file handle into a nativeobj");

	enum class FileType
	{
		File,
		Dir,
		Other
	};

	typedef int64_t Time;

	struct DateTime
	{
		uint16_t year, month, day, hour, min, sec, msec;
	};

	struct FileInfo
	{
		FileType type;
		uint64_t size;
		Time created;
		Time modified;
		Time accessed;
	};

	// Most of these functions have some kind of "invalid" return value. If that's returned, then the error message will
	// be sitting on top of the thread's stack.

	// Error handling
	void pushSystemErrorMsg(CrocThread* t);
	void throwIOEx(CrocThread* t);
	void throwOSEx(CrocThread* t);

	// File streams
	FileHandle openFile(CrocThread* t, crocstr name, FileAccess access, FileCreate create);
	bool truncate(CrocThread* t, FileHandle f);

	// Console streams
	FileHandle getStdin(CrocThread* t);
	FileHandle getStdout(CrocThread* t);
	FileHandle getStderr(CrocThread* t);

	// General-purpose streams
	bool isValidHandle(FileHandle f);
	int64_t read(CrocThread* t, FileHandle f, DArray<uint8_t> data);
	int64_t write(CrocThread* t, FileHandle f, DArray<uint8_t> data);
	uint64_t seek(CrocThread* t, FileHandle f, uint64_t pos, Whence whence);
	bool flush(CrocThread* t, FileHandle f);
	bool close(CrocThread* t, FileHandle f);

	// Environment variables
	bool getEnv(CrocThread* t, crocstr name);
	void setEnv(CrocThread* t, crocstr name, crocstr val);
	void getAllEnvVars(CrocThread* t);

	// FS stuff
	bool listDir(CrocThread* t, crocstr path, bool includeHidden, std::function<bool(FileType)> dg);
	bool pushCurrentDir(CrocThread* t);
	bool changeDir(CrocThread* t, crocstr path);
	bool makeDir(CrocThread* t, crocstr path);
	bool removeDir(CrocThread* t, crocstr path);
	bool getInfo(CrocThread* t, crocstr name, FileInfo* info);
	bool copyFromTo(CrocThread* t, crocstr from, crocstr to, bool force);
	bool moveFromTo(CrocThread* t, crocstr from, crocstr to, bool force);
	bool remove(CrocThread* t, crocstr path);
	}
}

#endif