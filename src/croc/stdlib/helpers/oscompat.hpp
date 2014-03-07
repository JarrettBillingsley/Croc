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
		Append = O_CREAT | O_APPEND,
		MustNotExist = O_CREAT | O_EXCL
	};

	enum class Whence : DWORD
	{
		Begin = SEEK_SET,
		Current = SEEK_CUR,
		End = SEEK_END
	};
#endif

	namespace oscompat
	{
	// Most of these functions have some kind of "invalid" return value. If that's returned, then the error message will
	// be sitting on top of the thread's stack.

	// Misc OS stuff
	void pushSystemErrorMsg(CrocThread* t);

	// File-specific stuff
	FileHandle openFile(CrocThread* t, crocstr name, FileAccess access, FileCreate create);
	bool truncate(CrocThread* t, FileHandle f, uint64_t pos);

	// Console
	FileHandle getStdin(CrocThread* t);
	FileHandle getStdout(CrocThread* t);
	FileHandle getStderr(CrocThread* t);

	// General-purpose
	int64_t read(CrocThread* t, FileHandle f, DArray<uint8_t> data);
	int64_t write(CrocThread* t, FileHandle f, DArray<uint8_t> data);
	uint64_t seek(CrocThread* t, FileHandle f, uint64_t pos, Whence whence);
	bool flush(CrocThread* t, FileHandle f);
	bool close(CrocThread* t, FileHandle f);
	}
}

#endif