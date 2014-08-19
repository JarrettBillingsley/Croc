
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
		croc_ex_throwNamedException(t, "PcreException", "Cannot find the libpcre shared library");

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
		croc_ex_throwNamedException(t, "PcreException",
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
		croc_eh_throwStd(t, "ValueError", "No more matches");

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
	Docstr(DFunc("constructor")
	R"()"),

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
		croc_ex_throwNamedException(t, "PcreException", "Error studying regex: %s", error);
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
	R"()"),

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
	R"()"),

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
	R"()"),

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
	Docstr(DFunc("test")
	R"()"),

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
		croc_ex_throwNamedException(t, "PcreException", "PCRE Error matching against string (code %d)", numGroups);
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
	Docstr(DFunc("search")
	R"()"),

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
	Docstr(DFunc("match")
	R"()"),

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
	Docstr(DFunc("pre")
	R"()"),

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
	Docstr(DFunc("post")
	R"()"),

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
	Docstr(DFunc("preMatchPost")
	R"()"),

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
	Docstr(DFunc("matchBegin")
	R"()"),

	"matchBegin", 1
};

word_t Regex_matchBegin(CrocThread* t)
{
	auto numParams = croc_getStackSize(t) - 1;
	getThis(t);
	auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
	croc_pushInt(t, range.lo);
	return 1;
}

const StdlibRegisterInfo Regex_matchEnd_info =
{
	Docstr(DFunc("matchEnd")
	R"()"),

	"matchEnd", 1
};

word_t Regex_matchEnd(CrocThread* t)
{
	auto numParams = croc_getStackSize(t) - 1;
	getThis(t);
	auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
	croc_pushInt(t, range.hi);
	return 1;
}

const StdlibRegisterInfo Regex_matchBeginEnd_info =
{
	Docstr(DFunc("matchBeginEnd")
	R"()"),

	"matchBeginEnd", 1
};

word_t Regex_matchBeginEnd(CrocThread* t)
{
	auto numParams = croc_getStackSize(t) - 1;
	getThis(t);
	auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
	croc_pushInt(t, range.lo);
	croc_pushInt(t, range.hi);
	return 2;
}

const StdlibRegisterInfo Regex_find_info =
{
	Docstr(DFunc("find")
	R"()"),

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
	Docstr(DFunc("split")
	R"()"),

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
	Docstr(DFunc("replace")
	R"()"),

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
	Docstr(DFunc("iterator")
	R"()"),

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
	R"()"),

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

// =====================================================================================================================
// Regex loader

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

void initRegexClass(CrocThread* t)
{
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
}

// =====================================================================================================================
// Loader

word loader(CrocThread* t)
{
	croc_pushGlobal(t, "Throwable");
	croc_class_new(t, "PcreException", 1);
	croc_newGlobal(t, "PcreException");

	loadPCRESharedLib(t);

	// Check that we have an appropriate libpcre, first..
	{
		auto vers = atoda(pcre_version());
		vers = vers.slice(0, strLocateChar(vers, ' '));
		auto dotPos = strLocateChar(vers, '.');

		auto major = strtol(cast(const char*)vers.ptr, nullptr, 10);
		auto minor = strtol(cast(const char*)vers.ptr + dotPos + 1, nullptr, 10);

		if(minor < 4 || major < 7)
		{
			croc_ex_throwNamedException(t, "PcreException", "Your PCRE library is only version %.*s. You need 7.4 or higher.",
				cast(int)vers.length, vers.ptr);
		}

		int haveUtf8;
		pcre_config(PCRE_CONFIG_UTF8, &haveUtf8);

		if(!haveUtf8)
			croc_ex_throwNamedException(t, "PcreException", "Your PCRE library was not built with UTF-8 support.");
	}

	initRegexClass(t);

	croc_pushString(t, R"x(\w+([\-+.]\w+)*@\w+([\-.]\w+)*\.\w+([\-.]\w+)*)x");
	croc_newGlobal(t, "email");

	croc_pushString(t,
		R"x((([h|H][t|T]|[f|F])[t|T][p|P]([s|S]?)\:\/\/|~/|/)?([\w]+:\w+@)?(([a-zA-Z]{1}([\w\-]+\.)+([\w]{2)x"
		R"x(,5}))(:[\d]{1,5})?)?((/?\w+/)+|/?)(\w+\.[\w]{3,4})?([,]\w+)*((\?\w+=\w+)?(&\w+=\w+)*([,]\w*)*)?)x");
	croc_newGlobal(t, "url");

	croc_pushString(t, R"x(^[a-zA-Z_]+$)x");                        croc_newGlobal(t, "alpha");
	croc_pushString(t, R"x(^\s+$)x");                               croc_newGlobal(t, "space");
	croc_pushString(t, R"x(^\d+$)x");                               croc_newGlobal(t, "digit");
	croc_pushString(t, R"x(^[0-9A-Fa-f]+$)x");                      croc_newGlobal(t, "hexdigit");
	croc_pushString(t, R"x(^[0-7]+$)x");                            croc_newGlobal(t, "octdigit");
	croc_pushString(t, R"x(^[\(\)\[\]\.,;=<>\+\-\*/&\^]+$)x");      croc_newGlobal(t, "symbol");

	croc_pushString(t, R"x(^((1-)?\d{3}-)?\d{3}-\d{4}$)x");         croc_newGlobal(t, "usPhone");
	croc_pushString(t, R"x(^\d{5}$)x");                             croc_newGlobal(t, "usZip");

	return 0;
}
}

void initPcreLib(CrocThread* t)
{
	croc_ex_makeModule(t, "pcre", &loader);
}
#endif
}