
#include <ctype.h>
#include <string.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"
#include "croc/util/str.hpp"

namespace croc
{
	namespace
	{
	bool isAbsolute(crocstr path)
	{
		return
#ifdef _WIN32
		(path.length >= 2 && path[1] == ':' && (toupper(path[0]) >= 'A' && toupper(path[0]) <= 'Z')) ||
#endif
		(path.length && path[0] == '/');
	}

DBeginList(_globalFuncs)
	Docstr(DFunc("normalize") DParam("path", "string")
	R"(Normalize a path by removing redundant '.' and '..' segments, and removing consecutive slashes.

	On Windows, additionally any drive letter is capitalized and all backslashes are converted to forward slashes.

	Any '..' segments in absolute paths which would go above the root directory are also removed. '..' segments at the
	beginning of relative paths, however, are preserved.

	Any trailing slash is also preserved, but none is added if there is none to begin with.

	This function only does its work by string manipulation; the actual filesystem is never consulted.

	\returns the normalized path.)"),

	"normalize", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		auto origPath = getCrocstr(t, 1);

		auto mb = croc_memblock_new(t, origPath.length);
		auto path = mcrocstr::n(cast(uchar*)croc_memblock_getData(t, -1), origPath.length);
		path.slicea(origPath);

		auto initialStack = croc_getStackSize(t);
		bool isAbsolute = false;

#ifdef _WIN32
		// On windows, if there is a drive letter, uppercase it and skip it. Then convert \ to /.
		if(path.length >= 2 && path[1] == ':')
		{
			if(path[0] >= 'a' && path[0] <= 'z')
				path[0] = toupper(path[0]);

			pushCrocstr(t, path.slice(0, 2));
			path = path.sliceToEnd(2);
			isAbsolute = true;
		}

		for(auto &c: path)
		{
			if(c == '\\')
				c = '/';
		}
#endif

		if(path.length == 0)
		{
			if(isAbsolute) // only way this can be true is on windows with drive letter
			{
				croc_pushChar(t, '/');
				croc_cat(t, 2);
			}
			else
				croc_dup(t, 1);

			return 1;
		}

		if(path[0] == '/')
		{
			isAbsolute = true;
			path = path.sliceToEnd(1);
		}

		bool trailingSlash = false;

		if(path.length && path[path.length - 1] == '/')
		{
			trailingSlash = true;
			path = path.slice(0, path.length - 1);
		}


		auto joiner = pushCrocstr(t, ATODA("/"));
		croc_pushNull(t);
		uword numRealItems = 0;

		delimiters(path, ATODA("/"), [&](crocstr segment)
		{
			if(segment == ATODA(".."))
			{
				if(numRealItems > 0)
				{
					croc_popTop(t);
					numRealItems--;
				}
				else if(!isAbsolute)
					pushCrocstr(t, ATODA(".."));
				// otherwise, ignore it as it means going above root
			}
			else if(segment.length && segment != ATODA("."))
			{
				pushCrocstr(t, segment);
				numRealItems++;
			}
		});

		croc_methodCall(t, joiner, "vjoin", 1);

		if(isAbsolute)
		{
			pushCrocstr(t, ATODA("/"));
			croc_swapTop(t);
		}

		if(trailingSlash && croc_len(t, -1) > 0)
			pushCrocstr(t, ATODA("/"));

		croc_cat(t, croc_getStackSize(t) - initialStack);
		croc_lenai(t, mb, 0); // just for fun
		return 1;
	}

DListSep()
	Docstr(DFunc("toAbsolute") DParam("path", "string")
	R"(Converts a relative path \tt{path} to an absolute one (one defined from the root of the filesystem or drive).
	Also normalizes the path.

	\param[path] is the path to convert. If it is absolute already, it will be returned normalized. If not, it's assumed
		to be relative to the current working directory.

	\returns the absolute, normalized path.)"),

	"toAbsolute", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		auto path = getCrocstr(t, 1);

		if(isAbsolute(path))
		{
			croc_pushGlobal(t, "normalize");
			croc_pushNull(t);
			croc_dup(t, 1);
			return croc_call(t, -3, 1);
		}

		if(!oscompat::pushCurrentDir(t))
			oscompat::throwOSEx(t);

		auto base = getCrocstr(t, -1);

		if(base.length && base[base.length - 1] != '/')
		{
			pushCrocstr(t, ATODA("/"));
			croc_dup(t, 1);
			croc_cat(t, 3);
		}
		else
		{
			croc_dup(t, 1);
			croc_cat(t, 2);
		}

		croc_pushGlobal(t, "normalize");
		croc_pushNull(t);
		croc_dup(t, -3);
		return croc_call(t, -3, 1);
	}

DListSep()
	Docstr(DFunc("isAbsolute") DParam("path", "string")
	R"(\returns a bool of whether or not \tt{path} represents an absolute path.)"),

	"isAbsolute", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		croc_pushBool(t, isAbsolute(getCrocstr(t, 1)));
		return 1;
	}

DListSep()
	Docstr(DFunc("join") DParam("part1", "string") DVararg
	R"(Joins together several pieces of paths into a single path. Can be called with only one parameter.

	All the arguments must be strings, and each one will have any leading or trailing slash removed (but only one slash
	from each end). Any pieces which are empty after removing slashes will be ignored.

	The pieces will be joined together with a forward slash.)"),

	"join", -1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		auto stackSize = croc_getStackSize(t);

		for(uword i = 2; i < stackSize; i++)
			croc_ex_checkParam(t, i, CrocType_String);

		auto joiner = pushCrocstr(t, ATODA("/"));
		croc_pushNull(t);

		for(uword i = 1; i < stackSize; i++)
		{
			auto segment = getCrocstr(t, i);

			if(segment.length && (segment[0] == '/' || segment[0] == '\\'))
				segment = segment.sliceToEnd(1);

			if(segment.length && (segment[segment.length - 1] == '/' || segment[segment.length - 1] == '\\'))
				segment = segment.slice(0, segment.length - 1);

			if(segment.length)
				pushCrocstr(t, segment);
		}

		return croc_methodCall(t, joiner, "vjoin", 1);
	}

DListSep()
	Docstr(DFunc("splitAtLastSep") DParam("path", "string")
	R"(Splits a path at the last separator (or the second to last if the last is the last character in \tt{path}),
	returning two values: the part of the path up to and including the separator, and the part after it.

	The separator can be a forward slash or a backslash.

	If there is no separator, returns the empty string as the first part, and \tt{path} as the second.

	\examples

	\tt{file.splitAtLastSep("foo/bar")} will return \tt{"foo/", "bar"}.

	\tt{file.splitAtLastSep("baz")} will return \tt{"", "baz"}.

	\tt{file.splitAtLastSep("/")} will return \tt{"", "/"}, since the slash is at the end of the string.)"),

	"splitAtLastSep", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		auto path = getCrocstr(t, 1);

		auto slashPos = strRLocateChar(path, '/');

		if(slashPos == path.length)
			slashPos = strRLocateChar(path, '\\');

		if(slashPos == path.length)
		{
		_empty:
			pushCrocstr(t, crocstr());
			croc_dup(t, 1);
			return 2;
		}
		else if(slashPos == path.length - 1)
		{
			if(slashPos == 0)
				goto _empty;

			slashPos = strRLocateChar(path, '/', slashPos - 1);

			if(slashPos == path.length)
				slashPos = strRLocateChar(path, '\\', slashPos - 1);

			if(slashPos == path.length)
				goto _empty;
		}

		pushCrocstr(t, path.slice(0, slashPos + 1));
		pushCrocstr(t, path.sliceToEnd(slashPos + 1));
		return 2;
	}

DListSep()
	Docstr(DFunc("nameAndExt") DParam("filename", "string")
	R"(Given a \tt{filename}, splits it into a name component (everything before the last period) and an extension
	(everything after the last period).

	If there is no period, the extension will be the empty string.

	If the only period is at the beginning of the name, it will not be treated as an extension but rather as part of the
	name.

	\examples

	\tt{file.nameAndExt("foo.txt")} will return \tt{"foo", "txt"}.

	\tt{file.nameAndExt("bar")} will return \tt{"bar", ""}.

	\tt{file.nameAndExt(".hidden")} will return \tt{".hidden", ""})"),

	"nameAndExt", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		auto path = getCrocstr(t, 1);
		auto dotPos = strRLocateChar(path, '.');

		if(dotPos == path.length || dotPos == 0)
		{
			croc_dup(t, 1);
			pushCrocstr(t, ATODA(""));
		}
		else
		{
			pushCrocstr(t, path.slice(0, dotPos));
			pushCrocstr(t, path.sliceToEnd(dotPos + 1));
		}

		return 2;
	}
DEndList()

	word loader(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);
		return 0;
	}
	}

	void initPathLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "path", &loader);
		croc_ex_importNS(t, "path");
#ifdef CROC_BUILTIN_DOCS
		CrocDoc doc;
		croc_ex_doc_init(t, &doc, __FILE__);
		croc_ex_doc_push(&doc,
		DModule("path")
		R"(This module provides a set of string manipulation functions for dealing with file paths. This module is safe
		as it does not modify the filesystem, though it may read it to do its work.)");
			docFields(&doc, _globalFuncs);
		croc_ex_doc_pop(&doc, -1);
		croc_ex_doc_finish(&doc);
#endif
		croc_popTop(t);
	}
}