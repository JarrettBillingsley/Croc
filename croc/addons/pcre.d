/******************************************************************************
A binding to libpcre, a Perl-Compatible Regular Expressions library. This
library will dynamically load libpcre at runtime so there's nothing you need
to link (besides libdl on posix). This requires at least libpcre 7.4, and it
must have been compiled with UTF-8 support (this will be checked at load-time).

License:
Copyright (c) 2009 Jarrett Billingsley
Portions of this module were borrowed from Sean Kerr's codebox.text.Regex module.

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module croc.addons.pcre;

version(CrocAllAddons)
	version = CrocPcreAddon;

version(CrocPcreAddon)
{

import tango.stdc.stdlib;
import tango.stdc.stringz;
import tango.sys.Environment;
import tango.sys.SharedLib;
import tango.text.convert.Integer;
import tango.text.Util;

alias tango.text.convert.Integer.parse Int_parse;

import croc.api;
import croc.ex_library;
import croc.utf;

struct PcreLib
{
	static void init(CrocThread* t)
	{
		makeModule(t, "pcre", function uword(CrocThread* t)
		{
			CreateClass(t, "PcreException", "exceptions.Exception", (CreateClass*) {});
			newGlobal(t, "PcreException");

			loadPCRE(t);

			// Check that we have an appropriate libpcre, first..
			{
				auto vers = fromStringz(pcre_version());
				auto major = Int_parse(vers[0 .. vers.locate('.')]);
				auto minor = Int_parse(vers[vers.locate('.') + 1 .. vers.locate(' ')]);

				if(minor < 4 || major < 7)
					throwStdException(t, "Exception", "Your PCRE library is only version {}. You need 7.4 or higher.", vers[0 .. vers.locate(' ')]);

				word ret;
				pcre_config(PCRE_CONFIG_UTF8, &ret);

				if(!ret)
					throwStdException(t, "Exception", "Your PCRE library was not built with UTF-8 support.");
			}

			importModuleNoNS(t, "hash");

			RegexObj.init(t);

				pushString(t, r"\w+([\-+.]\w+)*@\w+([\-.]\w+)*\.\w+([\-.]\w+)*");
			newGlobal(t, "email");

				pushString(t,
					r"(([h|H][t|T]|[f|F])[t|T][p|P]([s|S]?)\:\/\/|~/|/)?([\w]+:\w+@)?(([a-zA-Z]{1}([\w\-]+\.)+([\w]{2"
					r",5}))(:[\d]{1,5})?)?((/?\w+/)+|/?)(\w+\.[\w]{3,4})?([,]\w+)*((\?\w+=\w+)?(&\w+=\w+)*([,]\w*)*)?");
			newGlobal(t, "url");

			pushString(t, r"^[a-zA-Z_]+$");                        newGlobal(t, "alpha");
			pushString(t, r"^\s+$");                               newGlobal(t, "space");
			pushString(t, r"^\d+$");                               newGlobal(t, "digit");
			pushString(t, r"^[0-9A-Fa-f]+$");                      newGlobal(t, "hexdigit");
			pushString(t, r"^[0-7]+$");                            newGlobal(t, "octdigit");
			pushString(t, r"^[\(\)\[\]\.,;=<>\+\-\*/&\^]+$");      newGlobal(t, "symbol");

			pushString(t, "^[\u4e00-\u9fa5]+$");                   newGlobal(t, "chinese");
			pushString(t, r"\d{3}-\d{8}|\d{4}-\d{7}");             newGlobal(t, "cnPhone");
			pushString(t, r"^((\(\d{2,3}\))|(\d{3}\-))?13\d{9}$"); newGlobal(t, "cnMobile");
			pushString(t, r"^\d{6}$");                             newGlobal(t, "cnZip");
			pushString(t, r"\d{15}|\d{18}");                       newGlobal(t, "cnIDcard");

			pushString(t, r"^((1-)?\d{3}-)?\d{3}-\d{4}$");         newGlobal(t, "usPhone");
			pushString(t, r"^\d{5}$");                             newGlobal(t, "usZip");

			return 0;
		});
	}
}

// libpcre says that some things should be a C 'int'.
// A C int, I presume, will be a native word, usually, so I've used 'word' where it says 'int'.
struct RegexObj
{
static:
	struct PtrStruct
	{
		pcre* re;
		pcre_extra* extra;
	}

	alias word[] GroupIdxType;

	const Ptrs = "Regex__ptrs";
	const Names = "Regex__names";
	const GroupIdx = "Regex__groupIdx";
	const Subject = "Regex__subject";
	const NumGroups = "Regex__numGroups";
	const NextStart = "Regex__nextStart";

	void init(CrocThread* t)
	{
		CreateClass(t, "Regex", (CreateClass* c)
		{
			pushNull(t);   c.field("__ptrs");      // memblock
			pushNull(t);   c.field("__names");     // table
			pushNull(t);   c.field("__groupIdx");  // memblock
			pushNull(t);   c.field("__subject");   // string
			pushInt(t, 0); c.field("__numGroups"); // int
			pushInt(t, 0); c.field("__nextStart"); // int

			c.method("constructor",   &constructor);
			c.method("finalizer",     &finalizer);
			c.method("numGroups",     &numGroups);
			c.method("groupNames",    &groupNames);
			c.method("test",          &test);
			c.method("search",        &search);
			c.method("pre",           &pre);
			c.method("match",         &match);
			c.method("post",          &post);
			c.method("preMatchPost",  &preMatchPost);
			c.method("matchBegin",    &matchBegin);
			c.method("matchEnd",      &matchEnd);
			c.method("matchBeginEnd", &matchBeginEnd);
			c.method("find",          &find);
			c.method("split",         &split);
			c.method("replace",       &replace);

				newFunction(t, &iterator, "Regex.iterator");
			c.method("opApply", &opApply, 1);
		});

		field(t, -1, "match");
		addMethod(t, -2, "opIndex");

		newGlobal(t, "Regex");
	}

	// -------------------------------------------------------------------------------------------------------------------------------------------------------
	// Finalizer

	uword finalizer(CrocThread* t)
	{
		field(t, 0, Ptrs);
		auto ptrs = cast(PtrStruct*)getMemblockData(t, -1).ptr;

		if(ptrs.extra !is null)
		{
			(*pcre_free)(ptrs.extra);
			ptrs.extra = null;
		}

		if(ptrs.re !is null)
		{
			(*pcre_free)(ptrs.re);
			ptrs.re = null;
		}

		return 0;
	}

	// -------------------------------------------------------------------------------------------------------------------------------------------------------
	// Internal Functions

	PtrStruct* getThis(CrocThread* t)
	{
		field(t, 0, Ptrs);

		if(isNull(t, -1))
			throwStdException(t, "StateException", "Attempting to call method on an uninitialized Regex instance");

		return cast(PtrStruct*)getMemblockData(t, -1).ptr;
	}

	word parseAttrs(char[] attrs)
	{
		word ret = 0;

		if(attrs.locate('i') != attrs.length)
			ret |= PCRE_CASELESS;

		if(attrs.locate('s') != attrs.length)
			ret |= PCRE_DOTALL;

		if(attrs.locate('m') != attrs.length)
			ret |= PCRE_MULTILINE;

		return ret | PCRE_NEWLINE_ANY | PCRE_UTF8;
	}

	void setSubject(CrocThread* t, word str)
	{
		dup(t, str);   fielda(t, 0, Subject);
		pushInt(t, 0); fielda(t, 0, NumGroups);
		pushInt(t, 0); fielda(t, 0, NextStart);
	}

	pcre* compilePattern(CrocThread* t, char[] pat, word attrs)
	{
		auto tmp = allocArray!(char)(t, pat.length + 1);
		tmp[0 .. pat.length] = pat[];
		tmp[$ - 1] = '\0';

		scope(exit)
			freeArray(t, tmp);

		char* error;
		word errorOffset;
		auto re = pcre_compile(tmp.ptr, attrs, &error, &errorOffset, null);

		if(error !is null)
			throwNamedException(t, "PcreException", "Error compiling regex at character {}: {}", errorOffset, fromStringz(error));

		return re;
	}

	word getNameTable(CrocThread* t, pcre* re, pcre_extra* extra)
	{
		word numNames = void;
		word nameEntrySize = void;
		char* nameTable = void;

		pcre_fullinfo(re, extra, PCRE_INFO_NAMECOUNT, &numNames);
		pcre_fullinfo(re, extra, PCRE_INFO_NAMEENTRYSIZE, &nameEntrySize);
		pcre_fullinfo(re, extra, PCRE_INFO_NAMETABLE, &nameTable);

		auto ret = newTable(t);

		for(uword i = 0; i < numNames; i++)
		{
			pushString(t, fromStringz(nameTable + 2));
			pushInt(t, (nameTable[0] << 8) | nameTable[1]);
			idxa(t, -3);
			nameTable += nameEntrySize;
		}

		return ret;
	}

	word[] getGroupRange(CrocThread* t, word group)
	{
		field(t, 0, NumGroups);
		auto numGroups = getInt(t, -1);
		pop(t);

		if(numGroups == 0)
			throwStdException(t, "ValueException", "No more matches");

		field(t, 0, GroupIdx);
		auto gi = cast(GroupIdxType)getMemblockData(t, -1);
		pop(t);

		if(group == -1)
		{
			// get whole regex match (group 0)
			return gi[0 .. 2];
		}
		else if(isInt(t, group))
		{
			// get indexed regex match
			auto i = getInt(t, group);

			if(i < 0 || i >= numGroups)
				throwStdException(t, "RangeException", "Invalid group index {} (have {} groups)", i, numGroups);

			i *= 2;

			return gi[cast(uword)i .. cast(uword)i + 2];
		}
		else if(isString(t, group))
		{
			// get named regex match
			field(t, 0, Names);
			dup(t, group);
			idx(t, -2);

			if(isNull(t, -1))
				throwStdException(t, "NameException", "Invalid group name '{}'", getString(t, group));

			auto i = cast(uword)getInt(t, -1);
			pop(t, 2);
			i *= 2;

			return gi[i .. i + 2];
		}
		else
			paramTypeError(t, group, "int|string");

		assert(false);
	}

	// -------------------------------------------------------------------------------------------------------------------------------------------------------
	// Methods

	uword constructor(CrocThread* t)
	{
		field(t, 0, Ptrs);

		if(!isNull(t, -1))
			throwStdException(t, "StateException", "Attempting to call constructor on an already-initialized Regex");

		auto pat = checkStringParam(t, 1);
		auto attrs = parseAttrs(optStringParam(t, 2, ""));
		auto re = compilePattern(t, pat, attrs);

		char* error;
		auto extra = pcre_study(re, 0, &error);

		if(error !is null)
		{
			(*pcre_free)(re);
			throwNamedException(t, "PcreException", "Error studying regex: {}", fromStringz(error));
		}

		newMemblock(t, PtrStruct.sizeof);
		auto ptrs = cast(PtrStruct*)getMemblockData(t, -1).ptr;
		ptrs.re = re;
		ptrs.extra = extra;
		fielda(t, 0, Ptrs);

		word numGroups;
		pcre_fullinfo(re, extra, PCRE_INFO_CAPTURECOUNT, &numGroups);

		newMemblock(t, word.sizeof * ((numGroups + 1) * 3));
		fielda(t, 0, GroupIdx);

		getNameTable(t, re, extra);
		fielda(t, 0, Names);

		return 0;
	}

	uword numGroups(CrocThread* t)
	{
		getThis(t);
		field(t, 0, NumGroups);
		return 1;
	}

	uword groupNames(CrocThread* t)
	{
		getThis(t);

		pushGlobal(t, "hash");
		pushNull(t);
		field(t, 0, Names);
		methodCall(t, -3, "keys", 1);

		return 1;
	}

	uword test(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto ptrs = getThis(t);

		if(numParams > 0)
		{
			checkStringParam(t, 1);
			setSubject(t, 1);
		}

		field(t, 0, NextStart);
		auto nextStart = cast(word)getInt(t, -1);
		field(t, 0, Subject);
		auto subject = getString(t, -1);
		pop(t, 2);

		if(nextStart == subject.length)
		{
			pushBool(t, false);
			return 1;
		}

		field(t, 0, GroupIdx);
		auto groupIdx = cast(GroupIdxType)getMemblockData(t, -1);
		pop(t);

    	auto numGroups = pcre_exec
		(
			ptrs.re,
			ptrs.extra,
			subject.ptr,
			subject.length,
			nextStart,
			PCRE_NO_UTF8_CHECK, // all Croc strings are valid UTF-8
			groupIdx.ptr,
			groupIdx.length
		);

		if(numGroups == PCRE_ERROR_NOMATCH)
		{
			// done
			pushInt(t, 0);              fielda(t, 0, NumGroups);
			pushInt(t, subject.length); fielda(t, 0, NextStart);
			pushBool(t, false);
		}
		else if(numGroups < 0)
			throwNamedException(t, "PcreException", "PCRE Error matching against string (code {})", numGroups);
		else
		{
			pushInt(t, numGroups);   fielda(t, 0, NumGroups);
			pushInt(t, groupIdx[1]); fielda(t, 0, NextStart);
			pushBool(t, true);
		}

		return 1;
	}

	uword search(CrocThread* t)
	{
		getThis(t);
		checkStringParam(t, 1);
		setSubject(t, 1);
		dup(t, 0);
		return 1;
	}

	uword match(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		getThis(t);
		auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
		field(t, 0, Subject);
		auto subject = getString(t, -1);
		pushString(t, subject[range[0] .. range[1]]);
		return 1;
	}

	uword pre(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		getThis(t);
		auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
		field(t, 0, Subject);
		auto subject = getString(t, -1);
		pushString(t, subject[0 .. range[0]]);
		return 1;
	}

	uword post(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		getThis(t);
		auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
		field(t, 0, Subject);
		auto subject = getString(t, -1);
		pushString(t, subject[range[1] .. $]);
		return 1;
	}

	uword preMatchPost(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		getThis(t);
		auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
		field(t, 0, Subject);
		auto subject = getString(t, -1);
		pushString(t, subject[0 .. range[0]]);
		pushString(t, subject[range[0] .. range[1]]);
		pushString(t, subject[range[1] .. $]);
		return 3;
	}

	uword matchBegin(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		getThis(t);
		auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
		pushInt(t, range[0]);
		return 1;
	}

	uword matchEnd(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		getThis(t);
		auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
		pushInt(t, range[1]);
		return 1;
	}

	uword matchBeginEnd(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		getThis(t);
		auto range = getGroupRange(t, numParams == 0 ? -1 : 1);
		pushInt(t, range[0]);
		pushInt(t, range[1]);
		return 2;
	}

	uword replace(CrocThread* t)
	{
		getThis(t);
		auto str = checkStringParam(t, 1);
		setSubject(t, 1);
		checkAnyParam(t, 2);

		bool test()
		{
			dup(t, 0);
			pushNull(t);
			methodCall(t, -2, "test", 1);
			auto ret = getBool(t, -1);
			pop(t);
			return ret;
		}

		auto buf = StrBuffer(t);
		uword start = 0;
		char[] tmp = str;

		field(t, 0, GroupIdx);
		auto groupIdx = cast(GroupIdxType)getMemblockData(t, -1);
		pop(t);

		if(isString(t, 2))
		{
			while(test())
			{
				buf.addString(str[start .. groupIdx[0]]);
				dup(t, 2);
				buf.addTop();
				start = groupIdx[1];
				tmp = str[start .. $];
			}
		}
		else if(isFunction(t, 2))
		{
			while(test())
			{
				buf.addString(str[start .. groupIdx[0]]);

				dup(t, 2);
				pushNull(t);
				dup(t, 0);
				rawCall(t, -3, 1);

				if(!isString(t, -1))
				{
					pushTypeString(t, -1);
					throwStdException(t, "TypeException", "replacement function should return a 'string', not a '{}'", getString(t, -1));
				}

				buf.addTop();
				start = groupIdx[1];
				tmp = str[start .. $];
			}
		}
		else
			paramTypeError(t, 2, "string|function");

		buf.addString(tmp);
		buf.finish();

		return 1;
	}

	uword split(CrocThread* t)
	{
		getThis(t);
		auto str = checkStringParam(t, 1);
		setSubject(t, 1);
		field(t, 0, GroupIdx);
		auto groupIdx = cast(GroupIdxType)getMemblockData(t, -1);
		pop(t);

		auto ret = newArray(t, 0);
		uword start = 0;
		char[] tmp = str;

		dup(t, 0);

		foreach(word v; foreachLoop(t, 1))
		{
			pushString(t, str[start .. groupIdx[0]]);
			cateq(t, ret, 1);
			start = groupIdx[1];
			tmp = str[start .. $];
		}

		pushString(t, tmp);
		cateq(t, ret, 1);

		return 1;
	}

	uword find(CrocThread* t)
	{
		getThis(t);
		checkStringParam(t, 1);

		auto pos = len(t, 1);

		dup(t, 0);
		pushNull(t);
		dup(t, 1);
		methodCall(t, -3, "test", 1);

		if(getBool(t, -1))
		{
			field(t, 0, Subject);
			auto subject = getString(t, -1);
			field(t, 0, GroupIdx);
			auto groupIdx = cast(GroupIdxType)getMemblockData(t, -1);
			pop(t, 2);
			pos = utf8ByteIdxToCP(subject, groupIdx[0]);
		}

		pushInt(t, pos);
		return 1;
	}

	uword iterator(CrocThread* t)
	{
		getThis(t);
		auto idx = checkIntParam(t, 1) + 1;

		dup(t, 0);
		pushNull(t);
		methodCall(t, -2, "test", 1);

		if(getBool(t, -1) == false)
			return 0;

		pushInt(t, idx);
		dup(t, 0);
		return 2;
	}

	uword opApply(CrocThread* t)
	{
		getThis(t);
		getUpval(t, 0);
		dup(t, 0);
		pushInt(t, -1);
		return 3;
	}
}

// -------------------------------------------------------------------------------------------------------------------------------------------------------
// Shared lib loading stuff

private:

enum : word
{
	PCRE_MAJOR = 7,
	PCRE_MINOR = 4
}

const char[] PCRE_PRERELEASE = "";
const char[] PCRE_DATE       = "2007-09-21";

enum : word
{
	PCRE_CASELESS        = 0x00000001,
	PCRE_MULTILINE       = 0x00000002,
	PCRE_DOTALL          = 0x00000004,
	PCRE_EXTENDED        = 0x00000008,
	PCRE_ANCHORED        = 0x00000010,
	PCRE_DOLLAR_ENDONLY  = 0x00000020,
	PCRE_EXTRA           = 0x00000040,
	PCRE_NOTBOL          = 0x00000080,
	PCRE_NOTEOL          = 0x00000100,
	PCRE_UNGREEDY        = 0x00000200,
	PCRE_NOTEMPTY        = 0x00000400,
	PCRE_UTF8            = 0x00000800,
	PCRE_NO_AUTO_CAPTURE = 0x00001000,
	PCRE_NO_UTF8_CHECK   = 0x00002000,
	PCRE_AUTO_CALLOUT    = 0x00004000,
	PCRE_PARTIAL         = 0x00008000,
	PCRE_DFA_SHORTEST    = 0x00010000,
	PCRE_DFA_RESTART     = 0x00020000,
	PCRE_FIRSTLINE       = 0x00040000,
	PCRE_DUPNAMES        = 0x00080000,
	PCRE_NEWLINE_CR      = 0x00100000,
	PCRE_NEWLINE_LF      = 0x00200000,
	PCRE_NEWLINE_CRLF    = 0x00300000,
	PCRE_NEWLINE_ANY     = 0x00400000,
	PCRE_NEWLINE_ANYCRLF = 0x00500000,
	PCRE_BSR_ANYCRLF     = 0x00800000,
	PCRE_BSR_UNICODE     = 0x01000000,

	PCRE_ERROR_NOMATCH        =  -1,
	PCRE_ERROR_NULL           =  -2,
	PCRE_ERROR_BADOPTION      =  -3,
	PCRE_ERROR_BADMAGIC       =  -4,
	PCRE_ERROR_UNKNOWN_OPCODE =  -5,
	PCRE_ERROR_UNKNOWN_NODE   =  -5,
	PCRE_ERROR_NOMEMORY       =  -6,
	PCRE_ERROR_NOSUBSTRING    =  -7,
	PCRE_ERROR_MATCHLIMIT     =  -8,
	PCRE_ERROR_CALLOUT        =  -9,
	PCRE_ERROR_BADUTF8        = -10,
	PCRE_ERROR_BADUTF8_OFFSET = -11,
	PCRE_ERROR_PARTIAL        = -12,
	PCRE_ERROR_BADPARTIAL     = -13,
	PCRE_ERROR_INTERNAL       = -14,
	PCRE_ERROR_BADCOUNT       = -15,
	PCRE_ERROR_DFA_UITEM      = -16,
	PCRE_ERROR_DFA_UCOND      = -17,
	PCRE_ERROR_DFA_UMLIMIT    = -18,
	PCRE_ERROR_DFA_WSSIZE     = -19,
	PCRE_ERROR_DFA_RECURSE    = -20,
	PCRE_ERROR_RECURSIONLIMIT = -21,
	PCRE_ERROR_NULLWSLIMIT    = -22,
	PCRE_ERROR_BADNEWLINE     = -23,

	PCRE_INFO_OPTIONS        =  0,
	PCRE_INFO_SIZE           =  1,
	PCRE_INFO_CAPTURECOUNT   =  2,
	PCRE_INFO_BACKREFMAX     =  3,
	PCRE_INFO_FIRSTBYTE      =  4,
	PCRE_INFO_FIRSTCHAR      =  4,
	PCRE_INFO_FIRSTTABLE     =  5,
	PCRE_INFO_LASTLITERAL    =  6,
	PCRE_INFO_NAMEENTRYSIZE  =  7,
	PCRE_INFO_NAMECOUNT      =  8,
	PCRE_INFO_NAMETABLE      =  9,
	PCRE_INFO_STUDYSIZE      = 10,
	PCRE_INFO_DEFAULT_TABLES = 11,
	PCRE_INFO_OKPARTIAL      = 12,
	PCRE_INFO_JCHANGED       = 13,
	PCRE_INFO_HASCRORLF      = 14,

	PCRE_CONFIG_UTF8                   = 0,
	PCRE_CONFIG_NEWLINE                = 1,
	PCRE_CONFIG_LINK_SIZE              = 2,
	PCRE_CONFIG_POSIX_MALLOC_THRESHOLD = 3,
	PCRE_CONFIG_MATCH_LIMIT            = 4,
	PCRE_CONFIG_STACKRECURSE           = 5,
	PCRE_CONFIG_UNICODE_PROPERTIES     = 6,
	PCRE_CONFIG_MATCH_LIMIT_RECURSION  = 7,
	PCRE_CONFIG_BSR                    = 8,

	PCRE_EXTRA_STUDY_DATA            = 0x0001,
	PCRE_EXTRA_MATCH_LIMIT           = 0x0002,
	PCRE_EXTRA_CALLOUT_DATA          = 0x0004,
	PCRE_EXTRA_TABLES                = 0x0008,
	PCRE_EXTRA_MATCH_LIMIT_RECURSION = 0x0010
}

struct pcre {}

struct pcre_callout_block
{
	word   _version;
	word   callout_number;
	word*  offset_vector;
	char* subject;
	word   subject_length;
	word   start_match;
	word   current_position;
	word   capture_top;
	word   capture_last;
	void* callout_data;
	word   pattern_position;
	word   next_item_length;
}

struct pcre_extra
{
	ulong  flags;
	void*  study_data;
	ulong  match_limit;
	void*  callout_data;
	ubyte* tables;
	ulong  match_limit_recursion;
}

extern(C)
{
	pcre* function(char*, word, char**, word*, ubyte*)                                   pcre_compile;
	pcre* function(char*, word, word*, char**, word*, ubyte*)                            pcre_compile2;
	word function(word, void*)                                                           pcre_config;
	word function(pcre*, char*)                                                          pcre_copy_named_substring;
	word function(char*, word*, word, word, char*, word)                                 pcre_copy_substring;
	word function(pcre*, pcre_extra*, char*, word, word, word, word*, word, word*, word) pcre_dfa_exec;
	word function(pcre*, pcre_extra*, char*, word, word, word, word*, word)              pcre_exec;
	void function(char*)                                                                 pcre_free_substring;
	void function(char**)                                                                pcre_free_substring_list;
	word function(pcre*, pcre_extra*, word, void*)                                       pcre_fullinfo;
	word function(pcre*, char*, word*, word, char*, char**)                              pcre_get_named_substring;
	word function(pcre*, char*)                                                          pcre_get_stringnumber;
	word function(pcre*, char*, char**, char**)                                          pcre_get_stringtable_entries;
	word function(char*, word*, word, word, char**)                                      pcre_get_substring;
	word function(char*, word*, word, char***)                                           pcre_get_substring_list;
	word function(pcre*, word*, word*)                                                   pcre_info;
	ubyte* function()                                                                    pcre_maketables;
	word function(pcre*, word)                                                           pcre_refcount;
	pcre_extra* function(pcre*, word, char**)                                            pcre_study;
	char* function()                                                                     pcre_version;
	void function(void*)*                                                                pcre_free;
}

class LoaderException : Exception
{
	this(char[] msg)
	{
		super(msg);
	}
}

void bind(T)(ref T varref, char[] name, SharedLib lib)
{
	auto symbol = lib.getSymbol(toStringz(name));

	if(symbol)
	{
		auto ptr = cast(void**)&varref;
		*ptr = symbol;
	}
	else
		throw new LoaderException("Unknown symbol '" ~ name ~ "'");
}

SharedLib load(char[][] paths)
{
	SharedLib lib;

	foreach(path; paths)
	{
		try
			lib = SharedLib.load(path);
		catch(SharedLibException e)
		{
			try
				lib = SharedLib.load(Environment.cwd ~ path);
			catch (SharedLibException e) {}
		}

		if(lib !is null)
			break;
	}

	return lib;
}

void loadPCRE(CrocThread* t)
{
	if(pcre_compile !is null)
		return;

	version(linux)
		char[][] path = ["libpcre.so.3", "libpcre.so"];
	else version(Win32)
		char[][] path = ["libpcre.dll", "pcre.dll"];
	else version (darwin)
		char[][] path = ["/usr/lib/libpcre.dylib", "libpcre.dylib"];

	auto libpcre = load(path);

	if(libpcre !is null)
	{
		bind(pcre_compile, "pcre_compile", libpcre);
		bind(pcre_compile2, "pcre_compile2", libpcre);
		bind(pcre_config, "pcre_config", libpcre);
		bind(pcre_copy_named_substring, "pcre_copy_named_substring", libpcre);
		bind(pcre_copy_substring, "pcre_copy_substring", libpcre);
		bind(pcre_dfa_exec, "pcre_dfa_exec", libpcre);
		bind(pcre_exec, "pcre_exec", libpcre);
		bind(pcre_free_substring, "pcre_free_substring", libpcre);
		bind(pcre_free_substring_list, "pcre_free_substring_list", libpcre);
		bind(pcre_fullinfo, "pcre_fullinfo", libpcre);
		bind(pcre_get_named_substring, "pcre_get_named_substring", libpcre);
		bind(pcre_get_stringnumber, "pcre_get_stringnumber", libpcre);
		bind(pcre_get_stringtable_entries, "pcre_get_stringtable_entries", libpcre);
		bind(pcre_get_substring, "pcre_get_substring", libpcre);
		bind(pcre_get_substring_list, "pcre_get_substring_list", libpcre);
		bind(pcre_info, "pcre_info", libpcre);
		bind(pcre_maketables, "pcre_maketables", libpcre);
		bind(pcre_refcount, "pcre_refcount", libpcre);
		bind(pcre_study, "pcre_study", libpcre);
		bind(pcre_version, "pcre_version", libpcre);
		bind(pcre_free, "pcre_free", libpcre);
	}
	else
		throwStdException(t, "Exception", "Cannot find the libpcre shared library");
}

}