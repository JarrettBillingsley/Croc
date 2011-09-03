/******************************************************************************
This module contains the 'regexp' standard library.

License:
Copyright (c) 2007 ideage lsina@126.com
and Copyright (c) 2008 Jarrett Billingsley

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

module croc.stdlib_regexp;

import tango.text.Regex;
import tango.text.Util;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.types;
import croc.utils;

private alias RegExpT!(char) Regexd;

struct RegexpLib
{
	public static void init(CrocThread* t)
	{
		makeModule(t, "regexp", function uword(CrocThread* t)
		{
			RegexpObj.init(t);

				pushString(t, r"\w+([\-+.]\w+)*@\w+([\-.]\w+)*\.\w+([\-.]\w+)*");
			newGlobal(t, "email");

				pushString(t, r"(([h|H][t|T]|[f|F])[t|T][p|P]([s|S]?)\:\/\/|~/|/)?([\w]+:\w+@)?(([a-zA-Z]{1}([\w\-]+\.)+([\w]{2,5}))(:[\d]{1,5})?)?((/?\w+/)+|/?)(\w+\.[\w]{3,4})?([,]\w+)*((\?\w+=\w+)?(&\w+=\w+)*([,]\w*)*)?");
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

		importModuleNoNS(t, "regexp");
	}

	static struct RegexpObj
	{
	static:
		enum Fields
		{
			regex,
			global
		}

		public void init(CrocThread* t)
		{
			CreateClass(t, "Regexp", (CreateClass* c)
			{
				c.method("constructor", 2, &constructor);
				c.method("test", 1, &test);
				c.method("search", 1, &search);
				c.method("match", 1, &match);
				c.method("pre", 0,&pre);
				c.method("post", 0,&post);
				c.method("find", 1, &find);
				c.method("split", 1, &split);
				c.method("replace", 2, &replace);

					newFunction(t, &iterator, "Regexp.iterator");
				c.method("opApply", 1, &opApply, 1);
			});

			newFunction(t, &allocator, "Regexp.allocator");
			setAllocator(t, -2);

			newGlobal(t, "Regexp");
		}

		uword allocator(CrocThread* t)
		{
			newInstance(t, 0, Fields.max + 1);

			dup(t);
			pushNull(t);
			rotateAll(t, 3);
			methodCall(t, 2, "constructor", 0);
			return 1;
		}

		private Regex getThis(CrocThread* t)
		{
			bool dummy = void;
			return getThis(t, dummy);
		}

		private Regex getThis(CrocThread* t, out bool isGlobal)
		{
			checkInstParam(t, 0, "Regexp");
			getExtraVal(t, 0, Fields.global);
			isGlobal = getBool(t, -1);
			pop(t);
			getExtraVal(t, 0, Fields.regex);
			auto ret = cast(Regex)cast(void*)getNativeObj(t, -1);
			pop(t);
			return ret;
		}

		public uword constructor(CrocThread* t)
		{
			checkInstParam(t, 0, "Regexp");

			auto pat = checkStringParam(t, 1);
			auto attrs = optStringParam(t, 2, "");

			pushNativeObj(t, safeCode(t, new Regex(pat, attrs))); setExtraVal(t, 0, Fields.regex);
			pushBool(t, attrs.locate('g') != attrs.length);       setExtraVal(t, 0, Fields.global);

			return 0;
		}

		public uword test(CrocThread* t)
		{
			auto numParams = stackSize(t) - 1;
			auto rex = getThis(t);

			if(numParams > 0)
			{
				auto str = checkStringParam(t, 1);
				pushBool(t, safeCode(t, rex.test(str)));
			}
			else
				pushBool(t, safeCode(t, rex.test()));

			return 1;
		}

		public uword match(CrocThread* t)
		{
			auto numParams = stackSize(t) - 1;
			bool isGlobal = void;
			auto rex = getThis(t, isGlobal);

			if(numParams == 0)
				pushString(t, safeCode(t, rex.match(0)));
			else if(isInt(t, 1))
				pushString(t, safeCode(t, rex.match(cast(uword)getInt(t, 1))));
			else
			{
				auto src = checkStringParam(t, 1);
				auto matches = newArray(t, 0);

				if(isGlobal)
				{
					for(auto cont = safeCode(t, rex.test(src)); cont; cont = safeCode(t, rex.test()))
					{
						pushString(t, rex.match(0));
						cateq(t, matches, 1);
					}
				}
				else
				{
					if(safeCode(t, rex.test(src)))
					{
						pushString(t, rex.match(0));
						cateq(t, matches, 1);
					}
				}
			}

			return 1;
		}

		public uword search(CrocThread* t)
		{
			auto rex = getThis(t);
			auto str = checkStringParam(t, 1);
			safeCode(t, rex.search(str));
			dup(t, 0);
			return 1;
		}

		public uword pre(CrocThread* t)
		{
			auto rex = getThis(t);
			pushString(t, safeCode(t, rex.pre()));
			return 1;
		}

		public uword post(CrocThread* t)
		{
			auto rex = getThis(t);
			pushString(t, safeCode(t, rex.post()));
			return 1;
		}

		public uword replace(CrocThread* t)
		{
			auto rex = getThis(t);
			auto src = checkStringParam(t, 1);

			if(isString(t, 2))
			{
				auto rep = getString(t, 2);
				pushString(t, safeCode(t, rex.replaceAll(src, rep)));
			}
			else
			{
				checkParam(t, 2, CrocValue.Type.Function);

				pushString(t, safeCode(t, rex.replaceAll(src, delegate char[](Regex m)
				{
					auto reg = dup(t, 2);
					pushNull(t);
					dup(t, 0);
					rawCall(t, reg, 1);

					if(!isString(t, -1))
					{
						pushTypeString(t, -1);
						throwException(t, "replacement function should return a 'string', not a '{}'", getString(t, -1));
					}

					auto ret = getString(t, -1);
					pop(t);
					return ret;
				})));
			}

			return 1;
		}

		public uword split(CrocThread* t)
		{
			auto rex = getThis(t);
			auto str = checkStringParam(t, 1);

			auto ret = newArray(t, 0);
			uword lastStart = 0;
			char[] tmp = str;

			foreach(r; rex.search(str))
			{
				tmp = rex.pre();

				pushString(t, tmp[lastStart .. $]);
				cateq(t, ret, 1);

				lastStart = r.match(0).ptr - str.ptr;
				tmp = rex.post();
			}

			pushString(t, tmp);
			cateq(t, ret, 1);

			return 1;
		}

		public uword find(CrocThread* t)
		{
			auto rex = getThis(t);
			auto str = checkStringParam(t, 1);

			uword pos = str.length;

			if(safeCode(t, rex.test(str)))
				pos = safeCode(t, rex.match(0)).ptr - str.ptr;

			pushInt(t, pos);
			return 1;
		}

		uword iterator(CrocThread* t)
		{
			auto rex = getThis(t);
			auto idx = getInt(t, 1) + 1;

			if(!safeCode(t, rex.test()))
				return 0;

			pushInt(t, idx);
			dup(t, 0);
			return 2;
		}

		public uword opApply(CrocThread* t)
		{
			checkInstParam(t, 0, "Regexp");
			getUpval(t, 0);
			dup(t, 0);
			pushInt(t, -1);
			return 3;
		}
	}
}