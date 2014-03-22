
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
		and directories.)");
			docFields(&doc, _globalFuncs);
		croc_ex_doc_pop(&doc, -1);
		croc_ex_doc_finish(&doc);
#endif
		croc_popTop(t);
	}
}