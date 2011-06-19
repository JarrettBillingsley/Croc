/******************************************************************************
A binding to libpcre, a Perl-Compatible Regular Expressions library.  This
library will dynamically load libpcre at runtime so there's nothing you need
to link (besides libdl on posix).  This requires at least libpcre 7.4, and it
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
import tango.text.Util;
import Int = tango.text.convert.Integer;

import croc.api;

struct PcreLib
{
	public static void init(CrocThread* t)
	{
		makeModule(t, "pcre", function uword(CrocThread* t)
		{
			// Check that we have an appropriate libpcre, first..
			{
				auto vers = fromStringz(pcre_version());
				auto major = Int.parse(vers[0 .. vers.locate('.')]);
				auto minor = Int.parse(vers[vers.locate('.') + 1 .. vers.locate(' ')]);

				if(minor < 4 || major < 7)
					throwException(t, "Your PCRE library is only version {}.  You need 7.4 or higher.", vers[0 .. vers.locate(' ')]);

				word ret;
				pcre_config(PCRE_CONFIG_UTF8, &ret);

				if(!ret)
					throwException(t, "Your PCRE library was not built with UTF-8 support.");
			}

			importModule(t, "hash");
			pop(t);

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
	struct Members
	{
		char[] subject;
		pcre* re;
		pcre_extra* extra;
		word[] groupIdx;
		uword numGroups;
		uword nextStart;
	}

	enum Fields
	{
		names,
		subject
	}

	public void init(CrocThread* t)
	{
		CreateClass(t, "Regex", (CreateClass* c)
		{
			c.method("constructor",   &constructor);
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
		fielda(t, -2, "opIndex");

		newFunction(t, &allocator, "Regex.allocator");
		setAllocator(t, -2);

		newFunction(t, &finalizer, "Regex.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "Regex");
	}

	// -------------------------------------------------------------------------------------------------------------------------------------------------------
	// Allocator and Finalizer

	uword allocator(CrocThread* t)
	{
		newInstance(t, 0, Fields.max + 1, Members.sizeof);
		*(cast(Members*)getExtraBytes(t, -1).ptr) = Members.init;

		dup(t);
		pushNull(t);
		rotateAll(t, 3);
		methodCall(t, 2, "constructor", 0);
		return 1;
	}

	uword finalizer(CrocThread* t)
	{
		auto memb = cast(Members*)getExtraBytes(t, 0).ptr;

		freeArray(t, memb.groupIdx);

		if(memb.extra !is null)
		{
			(*pcre_free)(memb.extra);
			memb.extra = null;
		}

		if(memb.re !is null)
		{
			(*pcre_free)(memb.re);
			memb.re = null;
		}
		
		return 0;
	}

	// -------------------------------------------------------------------------------------------------------------------------------------------------------
	// Internal Functions

	private Members* getThis(CrocThread* t)
	{
		auto ret = checkInstParam!(Members)(t, 0, "Regex");

		if(ret.re is null)
			throwException(t, "Attempting to call method on an uninitialized Regex instance");

		return ret;
	}

	private word parseAttrs(char[] attrs)
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

	private void setSubject(CrocThread* t, Members* memb, word str)
	{
		dup(t, str);
		setExtraVal(t, 0, Fields.subject);
		memb.subject = getString(t, str);
		memb.numGroups = 0;
		memb.nextStart = 0;
	}

	private pcre* compilePattern(CrocThread* t, char[] pat, word attrs)
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
			throwException(t, "Error compiling regex at character {}: {}", errorOffset, fromStringz(error));

		return re;
	}

	private word getNameTable(CrocThread* t, pcre* re, pcre_extra* extra)
	{
		word numNames;
		word nameEntrySize;
		char* nameTable;

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
	
	private word[] getGroupRange(CrocThread* t, Members* memb, word group)
	{
		if(memb.numGroups == 0)
			throwException(t, "No more matches");

		auto gi = memb.groupIdx;

		if(group == -1)
		{
			// get whole regex match (group 0)
			return gi[0 .. 2];
		}
		else if(isInt(t, group))
		{
			// get indexed regex match
			auto i = getInt(t, group);

			if(i < 0 || i >= memb.numGroups)
				throwException(t, "Invalid group index {} (have {} groups)", i, memb.numGroups);

			i *= 2;

			return gi[cast(uword)i .. cast(uword)i + 2];
		}
		else if(isString(t, group))
		{
			// get named regex match
			getExtraVal(t, 0, Fields.names);
			dup(t, group);
			idx(t, -2);

			if(isNull(t, -1))
				throwException(t, "Invalid group name '{}'", getString(t, group));

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

	public uword constructor(CrocThread* t)
	{
		auto memb = checkInstParam!(Members)(t, 0, "Regex");

		if(memb.re !is null)
			throwException(t, "Attempting to call constructor on an already-initialized Regex");

		auto pat = checkStringParam(t, 1);
		auto attrs = parseAttrs(optStringParam(t, 2, ""));
		auto re = compilePattern(t, pat, attrs);

		char* error;
		auto extra = pcre_study(re, 0, &error);

		if(error !is null)
		{
			(*pcre_free)(re);
			throwException(t, "Error studying regex: {}", fromStringz(error));
		}

		memb.re = re;
		memb.extra = extra;

		word numGroups;
		pcre_fullinfo(re, extra, PCRE_INFO_CAPTURECOUNT, &numGroups);
		memb.groupIdx = allocArray!(word)(t, (numGroups + 1) * 3);

		getNameTable(t, re, extra);
		setExtraVal(t, 0, Fields.names);

		return 0;
	}

	public uword numGroups(CrocThread* t)
	{
		auto memb = getThis(t);
		pushInt(t, memb.numGroups);
		return 1;
	}

	public uword groupNames(CrocThread* t)
	{
		getThis(t);

		pushGlobal(t, "hash");
		pushNull(t);
		getExtraVal(t, 0, Fields.names);
		methodCall(t, -3, "keys", 1);

		return 1;
	}

	public uword test(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto memb = getThis(t);

		if(numParams > 0)
		{
			checkStringParam(t, 1);
			setSubject(t, memb, 1);
		}
		else if(memb.nextStart == memb.subject.length)
		{
			pushBool(t, false);
			return 1;
		}

    	auto numGroups = pcre_exec
		(
			memb.re,
			memb.extra,
			memb.subject.ptr,
			memb.subject.length,
			memb.nextStart,
			PCRE_NO_UTF8_CHECK, // all Croc strings are valid UTF-8
			memb.groupIdx.ptr,
			memb.groupIdx.length
		);

		if(numGroups == PCRE_ERROR_NOMATCH)
		{
			// done
			memb.numGroups = 0;
			memb.nextStart = memb.subject.length;
			pushBool(t, false);
		}
		else if(numGroups < 0)
			throwException(t, "PCRE Error matching against string (code {})", numGroups);
		else
		{
			memb.numGroups = numGroups;
			memb.nextStart = memb.groupIdx[1];
			pushBool(t, true);
		}

		return 1;
	}

	public uword search(CrocThread* t)
	{
		auto memb = getThis(t);
		checkStringParam(t, 1);
		setSubject(t, memb, 1);
		dup(t, 0);
		return 1;
	}

	public uword match(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto memb = getThis(t);
		auto range = getGroupRange(t, memb, numParams == 0 ? -1 : 1);
		pushString(t, memb.subject[range[0] .. range[1]]);
		return 1;
	}

	public uword pre(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto memb = getThis(t);
		auto range = getGroupRange(t, memb, numParams == 0 ? -1 : 1);
		pushString(t, memb.subject[0 .. range[0]]);
		return 1;
	}

	public uword post(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto memb = getThis(t);
		auto range = getGroupRange(t, memb, numParams == 0 ? -1 : 1);
		pushString(t, memb.subject[range[1] .. $]);
		return 1;
	}

	public uword preMatchPost(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto memb = getThis(t);
		auto range = getGroupRange(t, memb, numParams == 0 ? -1 : 1);
		pushString(t, memb.subject[0 .. range[0]]);
		pushString(t, memb.subject[range[0] .. range[1]]);
		pushString(t, memb.subject[range[1] .. $]);
		return 3;
	}

	public uword matchBegin(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto memb = getThis(t);
		auto range = getGroupRange(t, memb, numParams == 0 ? -1 : 1);
		pushInt(t, range[0]);
		return 1;
	}

	public uword matchEnd(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto memb = getThis(t);
		auto range = getGroupRange(t, memb, numParams == 0 ? -1 : 1);
		pushInt(t, range[1]);
		return 1;
	}

	public uword matchBeginEnd(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto memb = getThis(t);
		auto range = getGroupRange(t, memb, numParams == 0 ? -1 : 1);
		pushInt(t, range[0]);
		pushInt(t, range[1]);
		return 2;
	}

	public uword replace(CrocThread* t)
	{
		auto memb = getThis(t);
		auto str = checkStringParam(t, 1);
		setSubject(t, memb, 1);
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

		if(isString(t, 2))
		{
			while(test())
			{
				buf.addString(str[start .. memb.groupIdx[0]]);
				dup(t, 2);
				buf.addTop();
				start = memb.groupIdx[1];
				tmp = str[start .. $];
			}
		}
		else if(isFunction(t, 2))
		{
			while(test())
			{
				buf.addString(str[start .. memb.groupIdx[0]]);

				dup(t, 2);
				pushNull(t);
				dup(t, 0);
				rawCall(t, -3, 1);

				if(!isString(t, -1))
				{
					pushTypeString(t, -1);
					throwException(t, "replacement function should return a 'string', not a '{}'", getString(t, -1));
				}

				buf.addTop();
				start = memb.groupIdx[1];
				tmp = str[start .. $];
			}
		}
		else
			paramTypeError(t, 2, "string|function");

		buf.addString(tmp);
		buf.finish();

		return 1;
	}

	public uword split(CrocThread* t)
	{
		auto memb = getThis(t);
		auto str = checkStringParam(t, 1);
		setSubject(t, memb, 1);

		auto ret = newArray(t, 0);
		uword start = 0;
		char[] tmp = str;

		dup(t, 0);

		foreach(word v; foreachLoop(t, 1))
		{
			pushString(t, str[start .. memb.groupIdx[0]]);
			cateq(t, ret, 1);
			start = memb.groupIdx[1];
			tmp = str[start .. $];
		}

		pushString(t, tmp);
		cateq(t, ret, 1);

		return 1;
	}

	public uword find(CrocThread* t)
	{
		auto memb = getThis(t);
		checkStringParam(t, 1);

		auto pos = len(t, 1);

		dup(t, 0);
		pushNull(t);
		dup(t, 1);
		methodCall(t, -3, "test", 1);

		if(getBool(t, -1))
			pos = uniByteIdxToCP(memb.subject, memb.groupIdx[0]);

		pushInt(t, pos);
		return 1;
	}

	uword iterator(CrocThread* t)
	{
		auto memb = getThis(t);
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

	public uword opApply(CrocThread* t)
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
	public this(char[] msg)
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

static this()
{
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
		throw new LoaderException("Cannot load PCRE because libpcre is missing");
}

}