
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
	oscompat::FileCreate checkModeParam(CrocThread* t, word_t slot, crocchar_t def)
	{
		auto mode = croc_ex_optCharParam(t, slot, def);

		switch(mode)
		{
			case 'e': return oscompat::FileCreate::OpenExisting;
			case 'a': return oscompat::FileCreate::Append;
			case 'c': return oscompat::FileCreate::CreateIfNeeded;
			case 'x': return oscompat::FileCreate::MustNotExist;
			default:
				croc_eh_throwStd(t, "ValueError", "Unknown open mode '%c'", mode);
				return oscompat::FileCreate::OpenExisting; // dummy
		}
	}

	void pushNativeStream(CrocThread* t, oscompat::FileHandle f, const char* mode)
	{
		croc_ex_lookup(t, "stream.NativeStream");
		croc_pushNull(t);
		croc_pushNativeobj(t, cast(void*)f);
		croc_pushString(t, mode);
		croc_call(t, -4, 1);
	}

	word_t commonOpenWritable(CrocThread* t, bool readable)
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		auto name = getCrocstr(t, 1);
		auto createMode = checkModeParam(t, 2, readable ? 'e' : 'c');
		auto f = oscompat::openFile(t, name, readable ? oscompat::FileAccess::ReadWrite : oscompat::FileAccess::Write,
			createMode);

		if(f == oscompat::InvalidHandle)
		{
			croc_pushFormat(t, "Error opening '%.*s' for %swriting: ",
				cast(int)name.length, name.ptr, readable ? "reading and " : "");
			croc_swapTop(t);
			croc_cat(t, 2);
			oscompat::throwIOEx(t);
		}

		pushNativeStream(t, f, readable ? "rwsc" : "wsc");

		if(createMode == oscompat::FileCreate::Append)
		{
			croc_dupTop(t);
			croc_pushNull(t);
			croc_pushInt(t, 0);
			croc_pushChar(t, 'e');
			croc_methodCall(t, -4, "seek", 0);
		}

		return 1;
	}

	void pushFileTypeString(CrocThread* t, oscompat::FileType type)
	{
		switch(type)
		{
			case oscompat::FileType::File:  croc_pushString(t, "file");  break;
			case oscompat::FileType::Dir:   croc_pushString(t, "dir");   break;
			case oscompat::FileType::Other: croc_pushString(t, "other"); break;
		}
	}

DBeginList(_globalFuncs)
	Docstr(DFunc("inFile") DParam("name", "string")
	R"(Open an existing file for reading.

	\param[name] is the name of the file to open.

	\returns a \link{stream.NativeStream} object which represents the file. It will be readable, seekable, and closable.
		The file is completely unbuffered!

	\throws[OSException] if the file could not be opened for some reason.)"),

	"inFile", 1, [](CrocThread* t) -> word_t
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

		pushNativeStream(t, f, "rsc");
		return 1;
	}

DListSep()
	Docstr(DFunc("outFile") DParam("name", "string") DParamD("mode", "string", "\"c\"")
	R"(Opens a file for writing.

	\param[name] is the name of the file to open.
	\param[mode] describes how the file should be opened. It must be a one-character string, and it must be one of the
		following values:

		\dlist
			\li{\tt{"e"}} means the specified file must already exist, and an exception will be thrown if not. If the
				file was opened successfully, the contents will not be modified, and the file position will be at the
				beginning.
			\li{\tt{"x"}} is the opposite of \tt{"e"}: the file must \em{not} already exist, and a new file will be
				created.
			\li{\tt{"c"}} will create the file if it doesn't exist, or if it does exist, it will open it and truncate
				its contents. This is the default mode if you don't pass anything for the \tt{mode} parameter.
			\li{\tt{"a"}} ("append") will create the file if it doesn't exist, or if it does exist, it will open it and
				then seek to the end of the file, leaving the existing contents intact. Unlike the C stdio \tt{"a"} mode
				or the POSIX \tt{O_APPEND} mode, this will allow you to seek freely and writes will not always go to the
				end of the file.
		\endlist

	\returns a \link{stream.NativeStream} object which represents the file. It will be writable, seekable, and closable.
		The file is completely unbuffered!

	\throws[OSException] if the file could not be opened for some reason.)"),

	"outFile", 2, [](CrocThread* t) -> word_t
	{
		return commonOpenWritable(t, false);
	}

DListSep()
	Docstr(DFunc("inoutFile") DParam("name", "string") DParamD("mode", "string", "\"e\"")
	R"(Just like \link{outFile}, except the file will also be readable. Furthermore, the mode defaults to \tt{"e"}.)"),

	"inoutFile", 2, [](CrocThread* t) -> word_t
	{
		return commonOpenWritable(t, true);
	}

DListSep()
	Docstr(DFunc("readTextFile") DParam("name", "string") DParamD("encoding", "string", "utf-8")
		DParamD("errors", "string", "strict")
	R"(Reads the contents of a text file, decoding it according to the given \tt{encoding}, and returns the entire file
	contents as a string.

	\param[name] is the name of the file to read.
	\param[encoding] is the text encoding to use, as found in the \link{text} library.
	\param[errors] is how malformed text should be read, as specified by the \link{text} library.

	\returns the decoded contents of the file.)"),

	"readTextFile", 3, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		auto haveEncoding = croc_ex_optParam(t, 2, CrocType_String);
		auto haveErrors = croc_ex_optParam(t, 3, CrocType_String);

		// local f = inFile(name)
		auto f = croc_pushGlobal(t, "inFile");
		croc_pushNull(t);
		croc_dup(t, 1);
		croc_call(t, f, 1);

		// local data = f.readAll()
		auto data = croc_dup(t, f);
		croc_pushNull(t);
		croc_methodCall(t, data, "readAll", 1);

		// f.close()
		croc_dup(t, f);
		croc_pushNull(t);
		croc_methodCall(t, -2, "close", 0);

		// return text.getCodec(encoding).decode(data, errors)
		croc_pushGlobal(t, "text");
		croc_pushNull(t);
		if(haveEncoding)
			croc_dup(t, 2);
		else
			croc_pushString(t, "utf-8");
		croc_methodCall(t, -3, "getCodec", 1);
		croc_pushNull(t);
		croc_dup(t, data);
		if(haveErrors)
			croc_dup(t, 3);
		else
			croc_pushString(t, "strict");
		return croc_methodCall(t, -4, "decode", 1);
	}

DListSep()
	Docstr(DFunc("truncate") DParam("file", "instance")
	R"(Given an open, writable file \tt{file}, truncates the contents of the file so the current position in the file
	becomes the end of the file.

	If you've wrapped the given file in some kind of buffering stream, be sure to flush it before calling this!

	\param[file] should be an instance of \link{stream.NativeStream} or some class like it which has a hidden field
	named \tt{"native"}. This field should contain a nativeobj which is the system-dependent file handle. This handle
	should obviously be for a file and not some other kind of object!

	\throws[ValueError] if \tt{file} has no hidden field \tt{"handle"}, or if the \tt{"handle"} hidden field does not
		name a valid file handle.
	\throws[TypeError] if the \tt{"handle"} hidden field is not a nativeobj.
	\throws[IOException] if \tt{file} could not be truncated for some reason (either because it was invalid or for some
		other reason).)"),

	"truncate", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_Instance);

		if(!croc_hasHField(t, 1, "handle"))
			croc_eh_throwStd(t, "ValueError", "File object has no 'handle' hidden field");

		croc_hfield(t, 1, "handle");

		if(!croc_isNativeobj(t, -1))
			croc_eh_throwStd(t, "TypeError", "File object's 'handle' hidden field is not a nativeobj");

		auto handle = croc_getNativeobj(t, -1);

		if(!oscompat::isValidHandle(handle))
			croc_eh_throwStd(t, "ValueError", "File object's handle is invalid");

		if(!oscompat::truncate(t, handle))
			oscompat::throwIOEx(t);

		return 0;
	}

DListSep()
	Docstr(DFunc("writeTextFile") DParam("name", "string") DParam("data", "string")
		DParamD("encoding", "string", "utf-8") DParamD("errors", "string", "strict")
	R"(Writes the contents of the string \tt{data} to the file \tt{name}, encoding it with \tt{encoding}.

	If a file named \tt{name} already exists, it will be replaced, and if it doesn't, it will be created. This is just
	like the \tt{"c"} mode for \link{outFile}.

	\param[name] is the name of the file to write.
	\param[data] is the string which will be written out as the file's data.
	\param[encoding] is the text encoding to use, as found in the \link{text} library.
	\param[errors] is how malformed text should be read, as specified by the \link{text} library.)"),

	"writeTextFile", 4, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		croc_ex_checkParam(t, 2, CrocType_String);
		auto haveEncoding = croc_ex_optParam(t, 3, CrocType_String);
		auto haveErrors = croc_ex_optParam(t, 4, CrocType_String);

		// local f = outFile(name, 'c')
		auto f = croc_pushGlobal(t, "outFile");
		croc_pushNull(t);
		croc_dup(t, 1);
		croc_pushChar(t, 'c');
		croc_call(t, f, 1);

		// f.writeExact(text.getCodec(encoding).encode(data, errors))
		croc_dup(t, f);
		croc_pushNull(t);
		croc_pushGlobal(t, "text");
		croc_pushNull(t);
		if(haveEncoding)
			croc_dup(t, 3);
		else
			croc_pushString(t, "utf-8");
		croc_methodCall(t, -3, "getCodec", 1);
		croc_pushNull(t);
		croc_dup(t, 2);
		if(haveErrors)
			croc_dup(t, 4);
		else
			croc_pushString(t, "strict");
		croc_methodCall(t, -4, "encode", 1);
		croc_methodCall(t, -3, "writeExact", 0);

		// f.close()
		croc_dup(t, f);
		croc_pushNull(t);
		croc_methodCall(t, -2, "close", 0);

		return 0;
	}

DListSep()
	Docstr(DFunc("readMemblock") DParam("name", "string")
	R"(\returns the entire contents of the file \tt{name} as a memblock.)"),

	"readMemblock", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);

		// local f = inFile(name)
		auto f = croc_pushGlobal(t, "inFile");
		croc_pushNull(t);
		croc_dup(t, 1);
		croc_call(t, f, 1);

		// local ret = f.readAll()
		auto data = croc_dup(t, f);
		croc_pushNull(t);
		croc_methodCall(t, data, "readAll", 1);

		// f.close()
		croc_dup(t, f);
		croc_pushNull(t);
		croc_methodCall(t, -2, "close", 0);

		// return ret
		return 1;
	}

DListSep()
	Docstr(DFunc("writeMemblock") DParam("name", "string") DParam("data", "memblock")
	R"(Writes the contents of the memblock \tt{data} to the file \tt{name}.

	If a file named \tt{name} already exists, it will be replaced, and if it doesn't, it will be created. This is just
	like the \tt{"c"} mode for \link{outFile}.

	\param[name] is the name of the file to write.
	\param[data] is the memblock which will be written out as the file's data.)"),

	"writeMemblock", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		croc_ex_checkParam(t, 2, CrocType_Memblock);

		// local f = outFile(name, 'c')
		auto f = croc_pushGlobal(t, "outFile");
		croc_pushNull(t);
		croc_dup(t, 1);
		croc_pushChar(t, 'c');
		croc_call(t, f, 1);

		// f.writeExact(data)
		croc_dup(t, f);
		croc_pushNull(t);
		croc_dup(t, 2);
		croc_methodCall(t, -3, "writeExact", 0);

		// f.close()
		croc_dup(t, f);
		croc_pushNull(t);
		croc_methodCall(t, -2, "close", 0);

		return 0;
	}

DListSep()
	Docstr(DFunc("listDir") DParam("path", "string") DParam("listHidden", "bool") DParam("cb", "function")
	R"(List the contents of the directory given by \tt{path}, caling \tt{cb} once for each entry in the directory.

	\param[path] is the path to the directory to list.
	\param[listHidden] controls whether or not hidden and system files are included in the listing.
	\param[cb] is the callback function which will be called once for each directory entry. It will be passed two
		parameters: the first is the name of the entry, and the second is a string indicating what kind of entry it is.
		This string will be one of \tt{"file"} for regular files, \tt{"dir"} for directories, and \tt{"other"} for other
		kinds of files (such as devices, special files, symlinks etc.).

		This function can also optionally return a boolean \tt{false} to halt the directory listing.

	\throws[OSException] if there was some kind of error listing the directory.)"),

	"listDir", 3, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		auto listHidden = croc_ex_checkBoolParam(t, 2);
		croc_ex_checkParam(t, 3, CrocType_Function);

		auto ok = oscompat::listDir(t, getCrocstr(t, 1), listHidden, [&](oscompat::FileType type)
		{
			croc_dup(t, 3);
			croc_pushNull(t);
			croc_dup(t, -3);
			pushFileTypeString(t, type);

			croc_call(t, -4, 1);
			auto ret = croc_isBool(t, -1) ? croc_getBool(t, -1) : true;
			croc_popTop(t);
			return ret;
		});

		if(!ok)
			oscompat::throwOSEx(t);

		return 0;
	}

DListSep()
	Docstr(DFunc("getDirListing") DParam("path", "string") DParam("listHidden", "bool") DParam("kinds", "string")
	R"(An alternative method of getting a directory listing, this returns the directory's contents as an array of
	strings.

	\param[path] is the path to the directory to list.
	\param[listHidden] controls whether or not hidden and system files are included in the listing.
	\param[kinds] is a string which controls which kinds of directory entries are included in the resulting array. It
		must contain some combination of one or more of the following characters:

		\dlist
			\li{\tt{'f'}} means regular files will be included.
			\li{\tt{'d'}} means directories will be included. Their names will have a trailing slash ('/').
			\li{\tt{'o'}} means other kinds of entries will be included. They will look the same as normal filenames.
		\endlist

	\returns an array of strings of directory entry names.

	\throws[ValueError] if \tt{kinds} doesn't contain at least one of the specified characters.)"),

	"getDirListing", 3, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		auto listHidden = croc_ex_checkBoolParam(t, 2);
		croc_ex_checkParam(t, 3, CrocType_String);

		bool listFiles = false;
		bool listDirs = false;
		bool listOther = false;

		for(auto c: getCrocstr(t, 3))
		{
			switch(c)
			{
				case 'f': listFiles = true; break;
				case 'd': listDirs = true; break;
				case 'o': listOther = true; break;
				default: break;
			}
		}

		if(!listFiles && !listDirs && !listOther)
			croc_eh_throwStd(t, "ValueError", "'kinds' parameter must contain at least one of 'f', 'd', and 'o'");

		auto ret = croc_array_new(t, 0);

		auto ok = oscompat::listDir(t, getCrocstr(t, 1), listHidden, [&](oscompat::FileType type)
		{
			switch(type)
			{
				case oscompat::FileType::File:
					if(listFiles)
					{
						croc_dupTop(t);
						croc_cateq(t, ret, 1);
					}
					break;

				case oscompat::FileType::Dir:
					if(listDirs)
					{
						croc_dupTop(t);
						croc_pushString(t, "/");
						croc_cat(t, 2);
						croc_cateq(t, ret, 1);
					}
					break;

				case oscompat::FileType::Other:
					if(listOther)
					{
						croc_dupTop(t);
						croc_cateq(t, ret, 1);
					}
					break;
			}

			return true;
		});

		if(!ok)
			oscompat::throwOSEx(t);

		return 1;
	}

DListSep()
	Docstr(DFunc("currentDir")
	R"(\returns the current working directory as an absolute path string.)"),

	"currentDir", 0, [](CrocThread* t) -> word_t
	{
		if(!oscompat::pushCurrentDir(t))
			oscompat::throwOSEx(t);

		return 1;
	}

DListSep()
	Docstr(DFunc("changeDir") DParam("path", "string")
	R"(Changes the current working directory to \tt{path}.

	\throws[OSException] if \tt{path} is an invalid directory to change to.)"),

	"changeDir", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);

		if(!oscompat::changeDir(t, getCrocstr(t, 1)))
			oscompat::throwOSEx(t);

		return 0;
	}

DListSep()
	Docstr(DFunc("makeDir") DParam("path", "string")
	R"(Creates a new directory named \tt{path}.

	\throws[OSException] if \tt{path} is invalid or cannot be created.)"),

	"makeDir", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);

		if(!oscompat::makeDir(t, getCrocstr(t, 1)))
			oscompat::throwOSEx(t);

		return 0;
	}

DListSep()
	Docstr(DFunc("removeDir") DParam("path", "string")
	R"(Removes the directory named \tt{path}. The directory must be empty before it can be removed.

	\throws[OSException] if \tt{path} is invalid cannot be removed.)"),

	"removeDir", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);

		if(!oscompat::removeDir(t, getCrocstr(t, 1)))
			oscompat::throwOSEx(t);

		return 0;
	}

DListSep()
	Docstr(DFunc("exists") DParam("path", "string")
	R"(\returns a bool saying whether or not there is an accessible file or directory named \tt{path}. The key word here
	is "accessible". If you try to test the existence of a file you don't have permissions to access, this function will
	return false rather than throw an exception.)"),

	"exists", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		croc_pushBool(t, oscompat::getInfo(t, getCrocstr(t, 1), nullptr));
		return 1;
	}

DListSep()
	Docstr(DFunc("attrs") DParam("path", "string") DParamD("tab", "table", "null")
	R"(Get info on a file or directory at \tt{path} and return it as a table.

	\param[path] is the file or directory you're interested in.
	\param[tab] is an optional table which will be filled with the attributes. If you pass nothing to this parameter,
		this function will create a new table and return that. This parameter is provided so you can get the attributes
		of several files in a row without having to allocate a new table each time.

	\returns either a new table or \tt{tab} if passed. The table will have the following fields:
		\dlist
			\li{\tt{"type"}} is a string indicating whether it's a file (\tt{"file"}), directory (\tt{"dir"}), or
				something else (\tt{"other"}).
			\li{\tt{"size"}} is an integer representing the size, in bytes, of the file. Meaningless for non-files.
			\li{\tt{"created"}} is an integer representing the time of creation as measured in microseconds since
				midnight on January 1, 1970.
			\li{\tt{"modified"}} is an integer representing the last time it was modified, measured the same way.
			\li{\tt{"accessed"}} is an integer representing the last time it was accessed, measured the same way.
		\endlist

	The three time fields are in a format compatible with that used by the \link{time} library.

	\throws[OSException] if the attributes could not be retrieved.)"),

	"attrs", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		auto name = getCrocstr(t, 1);
		auto ret = croc_ex_optParam(t, 2, CrocType_Table) ? 2 : croc_table_new(t, 0);

		oscompat::FileInfo info;

		if(!oscompat::getInfo(t, name, &info))
		{
			croc_pushFormat(t, "Error getting attributes for '%.*s': ", cast(int)name.length, name.ptr);
			oscompat::pushSystemErrorMsg(t);
			croc_cat(t, 2);
			oscompat::throwOSEx(t);
		}

		pushFileTypeString(t, info.type);              croc_fielda(t, ret, "type");
		croc_pushInt(t, cast(crocint_t)info.size);     croc_fielda(t, ret, "size");
		croc_pushInt(t, cast(crocint_t)info.created);  croc_fielda(t, ret, "created");
		croc_pushInt(t, cast(crocint_t)info.modified); croc_fielda(t, ret, "modified");
		croc_pushInt(t, cast(crocint_t)info.accessed); croc_fielda(t, ret, "accessed");

		croc_dup(t, ret);
		return 1;
	}

#define MAKE_THINGER(ONE_LINE_OF_CODE)\
	[](CrocThread* t) -> word_t\
	{\
		croc_ex_checkParam(t, 1, CrocType_String);\
		auto name = getCrocstr(t, 1);\
\
		oscompat::FileInfo info;\
\
		if(!oscompat::getInfo(t, name, &info))\
		{\
			croc_pushFormat(t, "Error getting attributes for '%.*s': ", cast(int)name.length, name.ptr);\
			oscompat::pushSystemErrorMsg(t);\
			croc_cat(t, 2);\
			oscompat::throwOSEx(t);\
		}\
\
		ONE_LINE_OF_CODE;\
		return 1;\
	}

DListSep()
	Docstr(DFunc("fileType") DParam("path", "string")
	R"(Like \link{attrs}, but gets only the file type.

	\throws[OSException] if \tt{path} could not be accessed.)"),

	"fileType", 1, MAKE_THINGER(pushFileTypeString(t, info.type))

DListSep()
	Docstr(DFunc("fileSize") DParam("path", "string")
	R"(Like \link{attrs}, but gets only the file size.

	\throws[OSException] if \tt{path} could not be accessed.)"),

	"fileSize", 1, MAKE_THINGER(croc_pushInt(t, cast(crocint_t)info.size))

DListSep()
	Docstr(DFunc("created") DParam("path", "string")
	R"(Like \link{attrs}, but gets only the creation time.

	\throws[OSException] if \tt{path} could not be accessed.)"),

	"created", 1, MAKE_THINGER(croc_pushInt(t, cast(crocint_t)info.created))

DListSep()
	Docstr(DFunc("modified") DParam("path", "string")
	R"(Like \link{attrs}, but gets only the file modification time.

	\throws[OSException] if \tt{path} could not be accessed.)"),

	"modified", 1, MAKE_THINGER(croc_pushInt(t, cast(crocint_t)info.modified))

DListSep()
	Docstr(DFunc("accessed") DParam("path", "string")
	R"(Like \link{attrs}, but gets only the file access time.

	\throws[OSException] if \tt{path} could not be accessed.)"),

	"accessed", 1, MAKE_THINGER(croc_pushInt(t, cast(crocint_t)info.accessed))

DListSep()
	Docstr(DFunc("copyFromTo") DParam("from", "string") DParam("to", "string") DParamD("force", "bool", "false")
	R"(Copies a file named by \tt{from} to the path named by \tt{to}. The function is named this way to remind you of
	the order of the arguments.

	If a file named \tt{to} already exists, the \tt{force} parameter determines what happens. If \tt{force} is
	\tt{false} (the default), an exception is thrown. If \tt{force} is \tt{true}, the file at \tt{to} is replaced by
	a copy of the file at \tt{from}.

	\throws[OSException] if \tt{from} could not be copied to \tt{to}.)"),

	"copyFromTo", 3, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		croc_ex_checkParam(t, 2, CrocType_String);
		auto force = croc_ex_optBoolParam(t, 3, false);

		if(!oscompat::copyFromTo(t, getCrocstr(t, 1), getCrocstr(t, 2), force))
			oscompat::throwOSEx(t);

		return 0;
	}

DListSep()
	Docstr(DFunc("moveFromTo") DParam("from", "string") DParam("to", "string") DParamD("force", "bool", "false")
	R"(Moves a file or directory named by \tt{from} to the path named by \tt{to}. The function is named this way to
	remind you of the order of the arguments.

	This function lets you move directories as well as files, and you can also use it to rename files and directories
	(by simply moving them to another name in the same parent directory).

	If a file or directory named \tt{to} already exists, the \tt{force} parameter determines what happens. If \tt{force}
	is \tt{false} (the default), an exception is thrown. If \tt{force} is \tt{true}, the file or directory at \tt{to} is
	replaced by the file or directory at \tt{from}.

	\throws[OSException] if \tt{from} could not be moved to \tt{to}.)"),

	"moveFromTo", 3, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		croc_ex_checkParam(t, 2, CrocType_String);
		auto force = croc_ex_optBoolParam(t, 3, false);

		if(!oscompat::moveFromTo(t, getCrocstr(t, 1), getCrocstr(t, 2), force))
			oscompat::throwOSEx(t);

		return 0;
	}

DListSep()
	Docstr(DFunc("remove") DParam("path", "string")
	R"(Removes the file or directory at \tt{path} entirely. This is an irreversible operation, so be careful!

	If \tt{path} is a directory, it must be empty.

	\throws[OSException] if \tt{path} could not be removed.)"),

	"remove", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);

		if(!oscompat::remove(t, getCrocstr(t, 1)))
			oscompat::throwOSEx(t);

		return 0;
	}
DEndList()

	word loader(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);
		return 0;
	}
	}

	void initFileLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "file", &loader);
		croc_ex_importNS(t, "file");
#ifdef CROC_BUILTIN_DOCS
		CrocDoc doc;
		croc_ex_doc_init(t, &doc, __FILE__);
		croc_ex_doc_push(&doc,
		DModule("file")
		R"(This module provides access to the host file system. With it you can read, write, create, and delete files
		and directories.

		You should use paths with forward slashes ('/') to separate the directories for the best cross-platform
		compatibility. This library will translate forward slash paths to backslash paths internally on Windows, but
		even on Windows it will always return forward slash paths.)");
			docFields(&doc, _globalFuncs);
		croc_ex_doc_pop(&doc, -1);
		croc_ex_doc_finish(&doc);
#endif
		croc_popTop(t);
	}
}