
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/util/str.hpp"
#include "croc/util/utf.hpp"

namespace croc
{
#ifndef CROC_PCRE_ADDON
void initPcreLib(CrocThread* t)
{
	croc_eh_throwStd(t, "ApiError", "Attempting to load the PCRE library, but it was not compiled in");
}
#else
namespace
{

#ifdef CROC_BUILTIN_DOCS
const char* moduleDocs = DModule("pcre")
R"(PCREs, or Perl-compatible regular expressions, are the \em{de facto} standard in regular expression text processing.
This module exposes a regular expression class which wraps the \link[http://www.pcre.org/]{libpcre} library. Not all
features are supported at this time, but more may be added in the future.

\b{Prerequisites}

This module loads libpcre dynamically when it's first imported. On Windows, this can be \tt{libpcre.dll} or
\tt{pcre.dll}; on Linux, \tt{libpcre.so.3} or \tt{libpcre.so}; and on OSX \tt{libpcre.dylib}. The shared library is
loaded from the usual places.

The loaded library must be \b{libpcre version 7.4 or higher, built with UTF-8 support.} Support for Unicode Properites
isn't necessary, just UTF-8. This library will check that the version of libpcre that was loaded meets these
requirements after loading it. If the shared library is not suitable, a \link{RuntimeError} will be thrown.

\b{Windows:} building libpcre manually is kind of a pain, and as far as I know the only project that provides binaries
of libpcre is GnuWin32, but for some reason they haven't built a version of it since 7.0 in 2007. To save you the
hassle, I've compiled a compatible DLL of 7.4, available
\link[https://github.com/JarrettBillingsley/Croc/blob/master/libpcre.dll?raw=true]{here}. (\b{Note:} you must have the
\link[http://www.microsoft.com/downloads/details.aspx?FamilyID=9b2da534-3e03-4391-8a4d-074b9f2bc1bf&displaylang=en]{VC++2008
redist installed} for this DLL to work. This is a very tiny download and fast install.)

\b{Including this library in the host}

To use this library, the host must have it compiled into it. Compile Croc with the \tt{CROC_PCRE_ADDON} option enabled
in the CMake configuration. Then, from your host, when setting up the VM use the \tt{croc_vm_loadAddons} or
\tt{croc_vm_loadAllAvailableAddons} API functions to load this library into the VM. Then from your Croc code, you can
just \tt{import pcre} to access it.
)";
#endif

// =====================================================================================================================
// A tiny slice of the PCRE 7.4 header, just enough to implement this library without any external dependencies.

struct real_pcre;
typedef struct real_pcre pcre;

typedef struct pcre_extra
{
	unsigned long int flags;
	void* study_data;
	unsigned long int match_limit;
	void* callout_data;
	const unsigned char* tables;
	unsigned long int match_limit_recursion;
} pcre_extra;

pcre* (*pcre_compile)(const char*, int, const char**, int*, const unsigned char*);
int (*pcre_config)(int, void*);
int (*pcre_exec)(const pcre*, const pcre_extra*, const char*, int, int, int, int*, int);
void (**pcre_free)(void*);
int (*pcre_fullinfo)(const pcre*, const pcre_extra*, int, void*);
pcre_extra* (*pcre_study)(const pcre*, int, const char**);
const char* (*pcre_version)(void);

#define PCRE_CONFIG_UTF8 0

#define PCRE_CASELESS      0x00000001
#define PCRE_MULTILINE     0x00000002
#define PCRE_DOTALL        0x00000004
#define PCRE_UTF8          0x00000800
#define PCRE_NO_UTF8_CHECK 0x00002000
#define PCRE_NEWLINE_ANY   0x00400000

#define PCRE_INFO_CAPTURECOUNT  2
#define PCRE_INFO_NAMEENTRYSIZE 7
#define PCRE_INFO_NAMECOUNT     8
#define PCRE_INFO_NAMETABLE     9

#define PCRE_ERROR_NOMATCH (-1)

// =====================================================================================================================
// PCRE shared lib loading

#ifdef _WIN32
const char* pcrepaths[] =
{
	"libpcre.dll",
	"pcre.dll",
	nullptr
};
#elif defined(__APPLE__) && defined(__MACH__)
const char* pcrepaths[] =
{
	"/usr/lib/libpcre.dylib",
	"libpcre.dylib",
	nullptr;
};
#else
const char* pcrepaths[] =
{
	"libpcre.so.3",
	"libpcre.so",
	nullptr;
};
#endif

void loadPCRESharedLib(CrocThread* t)
{
	if(pcre_compile != nullptr)
		return;

	auto libpcre = oscompat::openLibraryMulti(t, pcrepaths);

	if(libpcre == nullptr)
		croc_eh_throwStd(t, "OSException", "Cannot find the libpcre shared library");

	oscompat::getProc(t, libpcre, "pcre_compile", pcre_compile);
	oscompat::getProc(t, libpcre, "pcre_config", pcre_config);
	oscompat::getProc(t, libpcre, "pcre_exec", pcre_exec);
	oscompat::getProc(t, libpcre, "pcre_free", pcre_free);
	oscompat::getProc(t, libpcre, "pcre_fullinfo", pcre_fullinfo);
	oscompat::getProc(t, libpcre, "pcre_study", pcre_study);
	oscompat::getProc(t, libpcre, "pcre_version", pcre_version);
}

// =====================================================================================================================
// Regex class

#if CROC_BUILTIN_DOCS
const char* RegexDocs = DClass("Regex")
R"(Wraps a PCRE regex object.)";
#endif

const char* _Ptrs = "ptrs";
const char* _Names = "names";
const char* _GroupIdx = "groupIdx";
const char* _Subject = "subject";
const char* _NumGroups = "numGroups";
const char* _NextStart = "nextStart";

struct PtrStruct
{
	pcre* re;
	pcre_extra* extra;
};

struct PcreGroupRange
{
	int lo;
	int hi;
};

PtrStruct* getThis(CrocThread* t)
{
	croc_hfield(t, 0, _Ptrs);

	if(croc_isNull(t, -1))
		croc_eh_throwStd(t, "StateError", "Attempting to call method on an uninitialized Regex instance");

	return cast(PtrStruct*)croc_memblock_getData(t, -1);
}

word parseAttrs(crocstr attrs)
{
	int ret = 0;

	if(strLocateChar(attrs, 'i') != attrs.length)
		ret |= PCRE_CASELESS;

	if(strLocateChar(attrs, 's') != attrs.length)
		ret |= PCRE_DOTALL;

	if(strLocateChar(attrs, 'm') != attrs.length)
		ret |= PCRE_MULTILINE;

	return ret | PCRE_NEWLINE_ANY | PCRE_UTF8;
}

void setSubject(CrocThread* t, word str)
{
	croc_dup(t, str);   croc_hfielda(t, 0, _Subject);
	croc_pushInt(t, 0); croc_hfielda(t, 0, _NumGroups);
	croc_pushInt(t, 0); croc_hfielda(t, 0, _NextStart);
}

pcre* compilePattern(CrocThread* t, crocstr pat, word attrs)
{
	const char* error;
	int errorOffset;
	auto re = pcre_compile(cast(const char*)pat.ptr, attrs, &error, &errorOffset, nullptr);

	if(error != nullptr)
		croc_eh_throwStd(t, "ValueError",
			"Error compiling regex at character %d: %s", errorOffset, error);

	return re;
}

word getNameTable(CrocThread* t, pcre* re, pcre_extra* extra)
{
	int numNames;
	int nameEntrySize;
	char* nameTable;

	pcre_fullinfo(re, extra, PCRE_INFO_NAMECOUNT, &numNames);
	pcre_fullinfo(re, extra, PCRE_INFO_NAMEENTRYSIZE, &nameEntrySize);
	pcre_fullinfo(re, extra, PCRE_INFO_NAMETABLE, &nameTable);

	auto ret = croc_table_new(t, 0);

	for(int i = 0; i < numNames; i++)
	{
		croc_pushString(t, nameTable + 2);
		croc_pushInt(t, (nameTable[0] << 8) | nameTable[1]);
		croc_idxa(t, -3);
		nameTable += nameEntrySize;
	}

	return ret;
}

PcreGroupRange getGroupRange(CrocThread* t, word group)
{
	croc_hfield(t, 0, _NumGroups);
	auto numGroups = croc_getInt(t, -1);
	croc_popTop(t);

	if(numGroups == 0)
		croc_eh_throwStd(t, "StateError", "No more matches");

	croc_hfield(t, 0, _GroupIdx);
	auto gi = cast(PcreGroupRange*)croc_memblock_getData(t, -1);
	croc_popTop(t);

	if(group == -1)
	{
		// get whole regex match (group 0)
		return gi[0];
	}
	else if(croc_isInt(t, group))
	{
		// get indexed regex match
		auto i = croc_getInt(t, group);

		if(i < 0 || i >= numGroups)
			croc_eh_throwStd(t, "RangeError",
				"Invalid group index %" CROC_INTEGER_FORMAT " (have %" CROC_INTEGER_FORMAT " groups)", i, numGroups);

		return gi[cast(uword)i];
	}
	else if(croc_isString(t, group))
	{
		// get named regex match
		croc_hfield(t, 0, _Names);
		croc_dup(t, group);
		croc_idx(t, -2);

		if(croc_isNull(t, -1))
		{
			auto name = getCrocstr(t, group);
			croc_eh_throwStd(t, "NameError", "Invalid group name '%.*s'", cast(int)name.length, name.ptr);
		}

		auto i = cast(uword)croc_getInt(t, -1);
		croc_pop(t, 2);
		return gi[i];
	}
	else
		croc_ex_paramTypeError(t, group, "int|string");

	assert(false);
	return gi[0]; // dummy
}

inline crocstr checkCrocstrParam(CrocThread* t, word_t slot)
{
	crocstr ret;
	ret.ptr = cast(const uchar*)croc_ex_checkStringParamn(t, slot, &ret.length);
	return ret;
}

inline crocstr optCrocstrParam(CrocThread* t, word_t slot, const char* opt)
{
	crocstr ret;
	ret.ptr = cast(const uchar*)croc_ex_optStringParamn(t, slot, opt, &ret.length);
	return ret;
}

// =====================================================================================================================
// Regex methods

const StdlibRegisterInfo Regex_constructor_info =
{
	Docstr(DFunc("constructor") DParam("pattern", "string") DParamD("attrs", "string", "''")
	R"(Compiles a regular expression.

	\param[pattern] is the regular expression to be compiled. See the PCRE documentation for the syntax.
	\param[attrs] is a string containing attributes with which to compile this regex. It can contain any of the
	following characters, in any order:

	\dlist
		\li{\tt{'i'}} Case-insensitive. Any literal characters or character classes will match either case.
		\li{\tt{'s'}} The dot pattern will match all characters including newlines (which it normally doesn't).
		\li{\tt{'m'}} Multiline. Normally the \tt{^} and \tt{$} patterns will match the beginning and end of the string.
			With this modifier, they will match the beginning and end of each line in the subject string.
	\endlist

	\throws[StateError] if you attempt to call this constructor on an already-initialized object.
	\throws[ValueError] if the \tt{pattern} could not be compiled.)"),

	"constructor", 2
};

word_t Regex_constructor(CrocThread* t)
{
	croc_hfield(t, 0, _Ptrs);

	if(!croc_isNull(t, -1))
		croc_eh_throwStd(t, "StateError", "Attempting to call constructor on an already-initialized Regex");

	auto pat = checkCrocstrParam(t, 1);
	auto attrs = parseAttrs(optCrocstrParam(t, 2, ""));
	auto re = compilePattern(t, pat, attrs);

	const char* error;
	auto extra = pcre_study(re, 0, &error);

	if(error != nullptr)
	{
		(*pcre_free)(re);
		croc_eh_throwStd(t, "ValueError", "Error compiling regex: %s", error);
	}

	croc_memblock_new(t, sizeof(PtrStruct));
	auto ptrs = cast(PtrStruct*)croc_memblock_getData(t, -1);
	ptrs->re = re;
	ptrs->extra = extra;
	croc_hfielda(t, 0, _Ptrs);

	int numGroups;
	pcre_fullinfo(re, extra, PCRE_INFO_CAPTURECOUNT, &numGroups);

	croc_memblock_new(t, sizeof(int) * ((numGroups + 1) * 3));
	croc_hfielda(t, 0, _GroupIdx);

	getNameTable(t, re, extra);
	croc_hfielda(t, 0, _Names);

	return 0;
}

const StdlibRegisterInfo Regex_finalizer_info =
{
	Docstr(DFunc("finalizer")
	R"(Cleans up the underlying C PCRE objects.)"),

	"finalizer", 0
};

word_t Regex_finalizer(CrocThread* t)
{
	croc_hfield(t, 0, _Ptrs);

	if(!croc_isMemblock(t, -1))
		return 0;

	auto ptrs = cast(PtrStruct*)croc_memblock_getData(t, -1);

	if(ptrs->extra != nullptr)
	{
		(*pcre_free)(ptrs->extra);
		ptrs->extra = nullptr;
	}

	if(ptrs->re != nullptr)
	{
		(*pcre_free)(ptrs->re);
		ptrs->re = nullptr;
	}

	return 0;
}

const StdlibRegisterInfo Regex_numGroups_info =
{
	Docstr(DFunc("numGroups")
	R"(\returns the number of matched subgroups. This will be 0 if \link{test} returned \tt{false}, or a number greater
	than 0 otherwise.)"),

	"numGroups", 0
};

word_t Regex_numGroups(CrocThread* t)
{
	getThis(t);
	croc_hfield(t, 0, _NumGroups);
	return 1;
}

const StdlibRegisterInfo Regex_groupNames_info =
{
	Docstr(DFunc("groupNames")
	R"x(\returns an array of strings of named groups.

	Named groups are created with the \tt{"(?P<name>pattern)"} regex syntax. So, if you compiled something like
	\tt{@"(?P<lname>\\w+), (?P<fname>\\w+)"}, this function would return an array containing the strings \tt{"lname"}
	and \tt{"fname"} (though not in any particular order).)x"),

	"groupNames", 0
};

word_t Regex_groupNames(CrocThread* t)
{
	getThis(t);

	croc_pushGlobal(t, "hash");
	croc_pushNull(t);
	croc_hfield(t, 0, _Names);
	croc_methodCall(t, -3, "keys", 1);

	return 1;
}

const StdlibRegisterInfo Regex_test_info =
{
	Docstr(DFunc("test") DParamD("subject", "string", "null")
	R"(The workhorse of the regex engine, this gets the next match of the regex within the current subject string.

	\param[subject] is the optional new subject string. If you don't pass one, this will continue testing on the current
		subject string. If you do, it's the same as doing \tt{re.search(subject).test()}.

	\returns \tt{true} if a new match was found in the subject string. In this case it updates all the matches which can
		be retrieved using various other methods. Returns \tt{false} if no more matches were found.)"),

	"test", 1
};

word_t Regex_test(CrocThread* t)
{
	auto numParams = croc_getStackSize(t) - 1;
	auto ptrs = getThis(t);

	if(numParams > 0)
	{
		croc_ex_checkStringParam(t, 1);
		setSubject(t, 1);
	}

	croc_hfield(t, 0, _NextStart);
	auto nextStart = cast(uword)croc_getInt(t, -1);
	croc_hfield(t, 0, _Subject);
	auto subject = getCrocstr(t, -1);
	croc_pop(t, 2);

	if(nextStart == subject.length)
	{
		croc_pushBool(t, false);
		return 1;
	}

	croc_hfield(t, 0, _GroupIdx);
	uword groupIdxLen;
	auto groupIdx = cast(PcreGroupRange*)croc_memblock_getDatan(t, -1, &groupIdxLen);
	croc_popTop(t);

	auto numGroups = pcre_exec
	(
		ptrs->re,
		ptrs->extra,
		cast(const char*)subject.ptr,
		subject.length,
		nextStart,
		PCRE_NO_UTF8_CHECK, // all Croc strings are valid UTF-8
		cast(int*)groupIdx,
		groupIdxLen / sizeof(int)
	);

	if(numGroups == PCRE_ERROR_NOMATCH)
	{
		// done
		croc_pushInt(t, 0);              croc_hfielda(t, 0, _NumGroups);
		croc_pushInt(t, subject.length); croc_hfielda(t, 0, _NextStart);
		croc_pushBool(t, false);
	}
	else if(numGroups < 0)
		croc_eh_throwStd(t, "RuntimeError", "PCRE Error matching against string (code %d)", numGroups);
	else
	{
		croc_pushInt(t, numGroups);      croc_hfielda(t, 0, _NumGroups);
		croc_pushInt(t, groupIdx[0].hi); croc_hfielda(t, 0, _NextStart);
		croc_pushBool(t, true);
	}

	return 1;
}

const StdlibRegisterInfo Regex_search_info =
{
	Docstr(DFunc("search") DParam("subject", "string")
	R"(Sets the subject string and resets all match groups, but does not start looking for matches. You'll have to use
	\link{test} or iterate over the matches with a \tt{foreach} loop.

	\returns this regex object, to make it easier to use as the container in a \tt{foreach} loop.)"),

	"search", 1
};

word_t Regex_search(CrocThread* t)
{
	getThis(t);
	croc_ex_checkStringParam(t, 1);
	setSubject(t, 1);
	croc_dup(t, 0);
	return 1;
}

const StdlibRegisterInfo Regex_match_info =
{
	Docstr(DFunc("match") DParamD("idx", "int|string", "0")
	R"(Gets the most recent match of the regex and its subgroups within the subject string.

	\param[idx] can be the integer index of a subgroup, where index 0 is the entire regex and 1, 2, etc. are the
	subgroups in order of where they appear in the regex. Alternatively, if you've named subgroups, you can get them by
	name; only names returned from \link{groupNames} are valid.

	\returns the slice of the subject string which was matched by the given regex group.

	\throws[StateError] if there are no more matches (\link{test} returned \tt{false}).
	\throws[RangeError] if the given integral subgroup index is invalid.
	\throws[NameError] if the given string subgroup name is invalid.)"),

	"match", 1
};

word_t Regex_match(CrocThread* t)
{
	auto numParams = croc_getStackSize(t) - 1;
	getThis(t);
	auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
	croc_hfield(t, 0, _Subject);
	auto subject = getCrocstr(t, -1);
	pushCrocstr(t, subject.slice(range.lo, range.hi));
	return 1;
}

const StdlibRegisterInfo Regex_pre_info =
{
	Docstr(DFunc("pre") DParamD("idx", "int|string", "0")
	R"(Gets the slice of the subject string that comes before the given subgroup match.

	\param[idx] works just like in \link{match}.)"),

	"pre", 1
};

word_t Regex_pre(CrocThread* t)
{
	auto numParams = croc_getStackSize(t) - 1;
	getThis(t);
	auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
	croc_hfield(t, 0, _Subject);
	auto subject = getCrocstr(t, -1);
	pushCrocstr(t, subject.slice(0, range.lo));
	return 1;
}

const StdlibRegisterInfo Regex_post_info =
{
	Docstr(DFunc("post") DParamD("idx", "int|string", "0")
	R"(Gets the slice of the subject string that comes after the given subgroup match.

	\param[idx] works just like in \link{match}.)"),

	"post", 1
};

word_t Regex_post(CrocThread* t)
{
	auto numParams = croc_getStackSize(t) - 1;
	getThis(t);
	auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
	croc_hfield(t, 0, _Subject);
	auto subject = getCrocstr(t, -1);
	pushCrocstr(t, subject.sliceToEnd(range.hi));
	return 1;
}

const StdlibRegisterInfo Regex_preMatchPost_info =
{
	Docstr(DFunc("preMatchPost") DParamD("idx", "int|string", "0")
	R"(Gets three pieces of the string: the part that comes before the given subgroup match, the match itself, and the
	part that comes after. This is slightly more efficient than calling \link{pre}, \link{match}, and \link{post}
	separately if you need two or all three parts.

	\param[idx] works just like in \link{match}.
	\returns the pre, match, and post strings in that order.)"),

	"preMatchPost", 1
};

word_t Regex_preMatchPost(CrocThread* t)
{
	auto numParams = croc_getStackSize(t) - 1;
	getThis(t);
	auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
	croc_hfield(t, 0, _Subject);
	auto subject = getCrocstr(t, -1);
	pushCrocstr(t, subject.slice(0, range.lo));
	pushCrocstr(t, subject.slice(range.lo, range.hi));
	pushCrocstr(t, subject.sliceToEnd(range.hi));
	return 3;
}

const StdlibRegisterInfo Regex_matchBegin_info =
{
	Docstr(DFunc("matchBegin") DParamD("idx", "int|string", "0")
	R"(Gets the character index into the subject string where the given subgroup match begins.

	\param[idx] works just like in \link{match}.)"),

	"matchBegin", 1
};

word_t Regex_matchBegin(CrocThread* t)
{
	auto numParams = croc_getStackSize(t) - 1;
	getThis(t);
	auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
	croc_hfield(t, 0, _Subject);
	auto subject = getCrocstr(t, -1);
	croc_pushInt(t, utf8ByteIdxToCP(subject, range.lo));
	return 1;
}

const StdlibRegisterInfo Regex_matchEnd_info =
{
	Docstr(DFunc("matchEnd") DParamD("idx", "int|string", "0")
	R"(Gets the character index into the subject string where the given subgroup match ends.

	\param[idx] works just like in \link{match}.)"),

	"matchEnd", 1
};

word_t Regex_matchEnd(CrocThread* t)
{
	auto numParams = croc_getStackSize(t) - 1;
	getThis(t);
	auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
	croc_hfield(t, 0, _Subject);
	auto subject = getCrocstr(t, -1);
	croc_pushInt(t, utf8ByteIdxToCP(subject, range.hi));
	return 1;
}

const StdlibRegisterInfo Regex_matchBeginEnd_info =
{
	Docstr(DFunc("matchBeginEnd") DParamD("idx", "int|string", "0")
	R"(Gets the character indices into the subject string where the given subgroup match begins and ends.

	\param[idx] works just like in \link{match}.
	\returns the begin and end indices in that order.)"),

	"matchBeginEnd", 1
};

word_t Regex_matchBeginEnd(CrocThread* t)
{
	auto numParams = croc_getStackSize(t) - 1;
	getThis(t);
	auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
	croc_hfield(t, 0, _Subject);
	auto subject = getCrocstr(t, -1);
	croc_pushInt(t, utf8ByteIdxToCP(subject, range.lo));
	croc_pushInt(t, utf8ByteIdxToCP(subject, range.hi));
	return 2;
}

const StdlibRegisterInfo Regex_find_info =
{
	Docstr(DFunc("find") DParam("subject", "string")
	R"(Searches for the first match of this regex in the given subject string.

	This is basically the same as \tt{re.search(subject).test() ? re.matchBegin() : #subject}.

	\param[subject] will be set as the new subject string.
	\returns the index into the subject string where the first match of this regex was found, or \tt{#subject} if
	not.)"),

	"find", 1
};

word_t Regex_find(CrocThread* t)
{
	getThis(t);
	croc_ex_checkStringParam(t, 1);

	auto pos = croc_len(t, 1);

	croc_dup(t, 0);
	croc_pushNull(t);
	croc_dup(t, 1);
	croc_methodCall(t, -3, "test", 1);

	if(croc_getBool(t, -1))
	{
		croc_hfield(t, 0, _Subject);
		auto subject = getCrocstr(t, -1);
		croc_hfield(t, 0, _GroupIdx);
		auto groupIdx = cast(PcreGroupRange*)croc_memblock_getData(t, -1);
		croc_pop(t, 2);
		pos = utf8ByteIdxToCP(subject, groupIdx[0].lo);
	}

	croc_pushInt(t, pos);
	return 1;
}

const StdlibRegisterInfo Regex_split_info =
{
	Docstr(DFunc("split") DParam("subject", "string")
	R"(Splits \tt{subject} into an array of pieces, using entire matches of this regex as the delimiters.

	\param[subject] will be set as the new subject string.
	\returns the array of split-up components. This will have only one element if the regex did not match.)"),

	"split", 1
};

word_t Regex_split(CrocThread* t)
{
	getThis(t);
	auto str = checkCrocstrParam(t, 1);
	setSubject(t, 1);
	croc_hfield(t, 0, _GroupIdx);
	auto groupIdx = cast(PcreGroupRange*)croc_memblock_getData(t, -1);
	croc_popTop(t);

	auto ret = croc_array_new(t, 0);
	uword start = 0;
	auto tmp = str;

	croc_dup(t, 0);

	auto state = croc_foreachBegin(t, 1);
	while(croc_foreachNext(t, state, 1))
	{
		pushCrocstr(t, str.slice(start, groupIdx[0].lo));
		croc_cateq(t, ret, 1);
		start = groupIdx[0].hi;
		tmp = str.sliceToEnd(start);
	}
	croc_foreachEnd(t, state);

	pushCrocstr(t, tmp);
	croc_cateq(t, ret, 1);

	return 1;
}

const StdlibRegisterInfo Regex_replace_info =
{
	Docstr(DFunc("replace") DParam("subject", "string") DParam("repl", "string|function")
	R"(Perform a search-and-replace on \tt{subject} using this regex as the search term.

	\param[subject] will be set as the new subject string.
	\param[repl] can be a string, in which case any matches of this regex will be replaced with \tt{repl} verbatim.

	\tt{repl} can also be a function. In this case, it should take a single parameter which will be this regex object
	(through which it can access the match), and should return a single string to be used as the replacement.

	\returns a new string with all occurrences of this regex replaced with \tt{repl}.

	\throws[TypeError] if \tt{repl} is a function and it returns anything other than a string.)"),

	"replace", 2
};

word_t Regex_replace(CrocThread* t)
{
	getThis(t);
	auto str = checkCrocstrParam(t, 1);
	setSubject(t, 1);
	croc_ex_checkAnyParam(t, 2);

	auto test = [&]()
	{
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "test", 1);
		auto ret = croc_getBool(t, -1);
		croc_popTop(t);
		return ret;
	};

	CrocStrBuffer buf;
	croc_ex_buffer_init(t, &buf);
	uword start = 0;
	auto tmp = str;

	croc_hfield(t, 0, _GroupIdx);
	auto groupIdx = cast(PcreGroupRange*)croc_memblock_getData(t, -1);
	croc_popTop(t);

	if(croc_isString(t, 2))
	{
		while(test())
		{
			croc_ex_buffer_addStringn(&buf, cast(const char*)str.ptr + start, groupIdx[0].lo - start);
			croc_dup(t, 2);
			croc_ex_buffer_addTop(&buf);
			start = groupIdx[0].hi;
			tmp = str.sliceToEnd(start);
		}
	}
	else if(croc_isFunction(t, 2))
	{
		while(test())
		{
			croc_ex_buffer_addStringn(&buf, cast(const char*)str.ptr + start, groupIdx[0].lo - start);

			croc_dup(t, 2);
			croc_pushNull(t);
			croc_dup(t, 0);
			croc_call(t, -3, 1);

			if(!croc_isString(t, -1))
			{
				croc_pushTypeString(t, -1);
				croc_eh_throwStd(t, "TypeError", "replacement function should return a 'string', not a '%s'", croc_getString(t, -1));
			}

			croc_ex_buffer_addTop(&buf);
			start = groupIdx[0].hi;
			tmp = str.sliceToEnd(start);
		}
	}
	else
		croc_ex_paramTypeError(t, 2, "string|function");

	croc_ex_buffer_addStringn(&buf, cast(const char*)tmp.ptr, tmp.length);
	croc_ex_buffer_finish(&buf);

	return 1;
}

const StdlibRegisterInfo Regex_iterator_info =
{
	nullptr,
	"iterator", 1
};

word_t Regex_iterator(CrocThread* t)
{
	getThis(t);
	auto idx = croc_ex_checkIntParam(t, 1) + 1;

	croc_dup(t, 0);
	croc_pushNull(t);
	croc_methodCall(t, -2, "test", 1);

	if(croc_getBool(t, -1) == false)
		return 0;

	croc_pushInt(t, idx);
	croc_dup(t, 0);
	return 2;
}

const StdlibRegisterInfo Regex_opApply_info =
{
	Docstr(DFunc("opApply")
	R"x(This allows you to iterate over all the matches of this regex in the subject string with a \tt{foreach} loop. To
	set the subject string, you can use \link{search}, which conveniently returns this regex object.

	In the loop, there will be two indices: the first being the 0-based index of the match (that is, the number of times
	this regex has matched in the subject string), and the second being this regex object itself. For example:

\code
local re = pcre.Regex$ @"(\w+)\s?=\s?(\w+)"
local subject =
"foo = bar
baz= quux"

foreach(i, m; re.search(subject))
	writefln$ "{}: key = '{}', value = '{}'", i, m.match(1), m.match(2)
\endcode

	This will print out:

\verbatim
0: key = 'foo', value = 'bar'
1: key = 'baz', value = 'quux'
\endverbatim

	Note that \tt{opApply} is just defined in terms of \link{test}. You can also iterate through all matches by doing
	something like this:

\code
re.search(subject)
for(local i = 0; re.test(); i++)
	writefln$ "{}: key = '{}', value = '{}'", i, re.match(1), re.match(2)
\endcode

	Given the same regex and subject string, this will print out the same thing as the previous example.)x"),

	"opApply", 1
};

word_t Regex_opApply(CrocThread* t)
{
	getThis(t);
	croc_pushUpval(t, 0);
	croc_dup(t, 0);
	croc_pushInt(t, -1);
	return 3;
}

const StdlibRegisterInfo Regex_opIndex_info =
{
	Docstr(DFunc("opIndex") DParamD("idx", "int|string", "0")
	R"(An alias for \link{match}, so \tt{re[4]} is the same as \tt{re.match(4)}, and \tt{re['lname']} is the same as
	\tt{re.match('lname')}. You can't write \tt{re[]} for the whole match, though, since that's a full-slice, not
	indexing.)"),

	"opIndex", 1
};

const StdlibRegister Regex_methodFuncs[] =
{
	_DListItem(Regex_constructor),
	_DListItem(Regex_finalizer),
	_DListItem(Regex_numGroups),
	_DListItem(Regex_groupNames),
	_DListItem(Regex_test),
	_DListItem(Regex_search),
	_DListItem(Regex_pre),
	_DListItem(Regex_match),
	_DListItem(Regex_post),
	_DListItem(Regex_preMatchPost),
	_DListItem(Regex_matchBegin),
	_DListItem(Regex_matchEnd),
	_DListItem(Regex_matchBeginEnd),
	_DListItem(Regex_find),
	_DListItem(Regex_split),
	_DListItem(Regex_replace),
	_DListEnd
};

const StdlibRegister Regex_opApplyFunc[] =
{
	_DListItem(Regex_iterator),
	_DListItem(Regex_opApply),
	_DListEnd
};

// =====================================================================================================================
// Loader

word loader(CrocThread* t)
{
	loadPCRESharedLib(t);

	// Check that we have an appropriate libpcre, first..
	{
		auto vers = atoda(pcre_version());
		vers = vers.slice(0, strLocateChar(vers, ' '));
		auto dotPos = strLocateChar(vers, '.');

		auto major = strtol(cast(const char*)vers.ptr, nullptr, 10);
		auto minor = strtol(cast(const char*)vers.ptr + dotPos + 1, nullptr, 10);

		if(major < 7 || (major == 7 && minor < 4))
		{
			croc_eh_throwStd(t, "RuntimeError", "Your PCRE library is only version %.*s. You need 7.4 or higher.",
				cast(int)vers.length, vers.ptr);
		}

		int haveUtf8;
		pcre_config(PCRE_CONFIG_UTF8, &haveUtf8);

		if(!haveUtf8)
			croc_eh_throwStd(t, "RuntimeError", "Your PCRE library was not built with UTF-8 support.");
	}

	croc_class_new(t, "Regex", 0);
		croc_pushNull(t);   croc_class_addHField(t, -2, _Ptrs);      // memblock
		croc_pushNull(t);   croc_class_addHField(t, -2, _Names);     // table
		croc_pushNull(t);   croc_class_addHField(t, -2, _GroupIdx);  // memblock
		croc_pushNull(t);   croc_class_addHField(t, -2, _Subject);   // string
		croc_pushInt(t, 0); croc_class_addHField(t, -2, _NumGroups); // int
		croc_pushInt(t, 0); croc_class_addHField(t, -2, _NextStart); // int

		registerMethods(t, Regex_methodFuncs);
		registerMethodUV(t, Regex_opApplyFunc);

		croc_field(t, -1, "match");
		croc_class_addMethod(t, -2, "opIndex");
	croc_newGlobal(t, "Regex");

#ifdef CROC_BUILTIN_DOCS
	CrocDoc doc;
	croc_ex_doc_init(t, &doc, __FILE__);
	croc_dup(t, 0);
	croc_ex_doc_push(&doc, moduleDocs);
		croc_field(t, -1, "Regex");
			croc_ex_doc_push(&doc, RegexDocs);
			docFields(&doc, Regex_methodFuncs);
			docFieldUV(&doc, Regex_opApplyFunc);

			docField(&doc, {Regex_opIndex_info, nullptr});
			croc_ex_doc_pop(&doc, -1);
		croc_popTop(t);
	croc_ex_doc_pop(&doc, -1);
	croc_ex_doc_finish(&doc);
	croc_popTop(t);
#endif

	return 0;
}
}

void initPcreLib(CrocThread* t)
{
	croc_ex_makeModule(t, "pcre", &loader);
}
#endif
}