/******************************************************************************
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

module minid.regexplib;

import tango.text.Regex;
import tango.text.Util;

import minid.ex;
import minid.interpreter;
import minid.types;
import minid.utils;

private alias RegExpT!(char) Regexd;

struct RegexpLib
{
	public static void init(MDThread* t)
	{
		pushGlobal(t, "modules");
		field(t, -1, "customLoaders");
		
		newFunction(t, function uword(MDThread* t, uword numParams)
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

// 			"compile"d,    new MDClosure(lib, &regexpLib.compile, "regexp.compile"),
// 			"test"d,       new MDClosure(lib, &test,              "regexp.test"),
// 			"replace"d,    new MDClosure(lib, &regexpLib.replace, "regexp.replace"),
// 			"split"d,      new MDClosure(lib, &split,             "regexp.split"),
// 			"match"d,      new MDClosure(lib, &match,             "regexp.match")

			return 0;
		}, "regexp");

		fielda(t, -2, "regexp");
		pop(t);

		importModule(t, "regexp");
	}

// 	static uword test(MDThread* t, uword numParams)
// 	{
// 		auto pattern = s.getParam!(MDString)(0).mData;
// 		auto src = s.getParam!(MDString)(1).mData;
// 		dchar[] attributes = "";
// 
// 		if(numParams > 2)
// 			attributes = s.getParam!(MDString)(2).mData;
// 
// 		scope rx = s.safeCode(Regexd(pattern, attributes));
// 		s.push(s.safeCode(cast(bool)rx.test(src)));
// 		return 1;
// 	}
// 
// 	uword replace(MDThread* t, uword numParams)
// 	{
// 		auto pattern = s.getParam!(MDString)(0).mData;
// 		auto src = s.getParam!(MDString)(1).mData;
// 		dchar[] attributes = "";
// 
// 		if(numParams > 3)
// 			attributes = s.getParam!(MDString)(3).mData;
// 			
// 		scope rx = s.safeCode(Regexd(pattern, attributes));
// 
// 		if(s.isParam!("string")(2))
// 		{
// 			auto rep = s.getParam!(MDString)(2).mData;
// 			s.push(s.safeCode(rx.replaceAll(src, rep)));
// 		}
// 		else
// 		{
// 			auto rep = s.getParam!(MDClosure)(2);
// 			scope temp = regexpClass.nativeClone();
// 
// 			s.push(s.safeCode(rx.replaceAll(src, (Regexd m)
// 			{
// 				temp.mRegexp = m;
// 				s.callWith(rep, 1, s.getContext(), temp);
// 				return s.pop!(MDString).mData;
// 			})));
// 		}
// 
// 		return 1;
// 	}
// 
// 	static uword split(MDThread* t, uword numParams)
// 	{
// 		auto pattern = s.getParam!(MDString)(0).mData;
// 		auto src = s.getParam!(MDString)(1).mData;
// 		dchar[] attributes = "";
// 
// 		if(numParams > 2)
// 			attributes = s.getParam!(MDString)(2).mData;
// 
// 		scope rx = s.safeCode(Regexd(pattern, attributes));
// 		s.push(MDArray.fromArray(s.safeCode(rx.split(src))));
// 		return 1;
// 	}
// 
// 	static uword match(MDThread* t, uword numParams)
// 	{
// 		auto pattern = s.getParam!(MDString)(0).mData;
// 		auto src = s.getParam!(MDString)(1).mData;
// 		dchar[] attributes = "";
// 
// 		if(numParams > 2)
// 			attributes = s.getParam!(MDString)(2).mData;
// 
// 		bool global = false;
// 		
// 		foreach(c; attributes)
// 		{
// 			if(c is 'g')
// 			{
// 				global = true;
// 				break;
// 			}
// 		}
// 		
// 		scope r = s.safeCode(Regexd(pattern, attributes));
// 		dchar[][] matches;
// 
// 		if(global)
// 		{
// 			for(auto cont = s.safeCode(r.test(src)); cont; cont = s.safeCode(r.test()))
// 				matches ~= r.match(0);
// 		}
// 		else
// 		{
// 			if(s.safeCode(r.test(src)))
// 				matches ~= r.match(0);
// 		}
// 
// 		s.push(MDArray.fromArray(matches));
// 		return 1;
// 	}
// 
// 	uword compile(MDThread* t, uword numParams)
// 	{
// 		auto pattern = s.getParam!(MDString)(0).mData;
// 		dchar[] attributes = "";
// 
// 		if(numParams > 1)
// 			attributes = s.getParam!(MDString)(1).mData;
// 
// 		s.push(s.safeCode(regexpClass.nativeClone(pattern, attributes)));
// 		return 1;
// 	}
//
	static struct RegexpObj
	{
	static:
		enum Members
		{
			regex,
			global
		}

		public void init(MDThread* t)
		{
			CreateObject(t, "Regexp", (CreateObject* o)
			{
				o.method("clone", &clone);
				o.method("test", &test);
				o.method("search", &search);
				o.method("match", &match);
				o.method("pre", &pre);
				o.method("post", &post);
				o.method("find", &find);
				o.method("split", &split);
				o.method("replace", &replace);

					newFunction(t, &iterator, "Regexp.iterator");
				o.method("opApply", &apply, 1);
			});
			
			newGlobal(t, "Regexp");
		}
		
		private Regex getThis(MDThread* t)
		{
			bool dummy = void;
			return getThis(t, dummy);
		}

		private Regex getThis(MDThread* t, out bool isGlobal)
		{
			checkObjParam(t, 0, "Regexp");
			pushExtraVal(t, 0, Members.global);
			isGlobal = getBool(t, -1);
			pop(t);
			pushExtraVal(t, 0, Members.regex);
			auto ret = cast(Regex)cast(void*)getNativeObj(t, -1);
			pop(t);
			return ret;
		}

		public uword clone(MDThread* t, uword numParams)
		{
			auto pat = checkStringParam(t, 1);
			auto attrs = optStringParam(t, 2, "");

			pushGlobal(t, "Regexp");
			auto ret = newObject(t, -1, null, 2);

			pushNativeObj(t, new Regex(pat, attrs));
			setExtraVal(t, ret, Members.regex);

			pushBool(t, attrs.locate('g') != attrs.length);
			setExtraVal(t, ret, Members.global);
			
			return 1;
		}

		public uword test(MDThread* t, uword numParams)
		{
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

		public uword match(MDThread* t, uword numParams)
		{
			bool isGlobal = void;
			auto rex = getThis(t, isGlobal);

			if(numParams == 0)
				pushString(t, safeCode(t, rex.match(0)));
			else if(isInt(t, 1))
				pushString(t, safeCode(t, rex.match(getInt(t, 1))));
			else
			{
				auto src = checkStringParam(t, 1);
				auto matches = newArray(t, 0);

				if(isGlobal)
				{
					for(auto cont = safeCode(t, rex.test(src)); cont; cont = safeCode(t, rex.test()))
					{
						dup(t, matches);
						pushString(t, rex.match(0));
						cateq(t, 1);
					}
				}
				else
				{
					if(safeCode(t, rex.test(src)))
					{
						dup(t, matches);
						pushString(t, rex.match(0));
						cateq(t, 1);
					}
				}
			}

			return 1;
		}

		public uword search(MDThread* t, uword numParams)
		{
			auto rex = getThis(t);
			auto str = checkStringParam(t, 1);
			safeCode(t, rex.search(str));
			dup(t, 0);
			return 1;
		}

		public uword pre(MDThread* t, uword numParams)
		{
			auto rex = getThis(t);
			pushString(t, safeCode(t, rex.pre()));
			return 1;
		}

		public uword post(MDThread* t, uword numParams)
		{
			auto rex = getThis(t);
			pushString(t, safeCode(t, rex.post()));
			return 1;
		}

		public uword replace(MDThread* t, uword numParams)
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
				checkParam(t, 2, MDValue.Type.Function);

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

		public uword split(MDThread* t, uword numParams)
		{
			auto rex = getThis(t);
			auto str = checkStringParam(t, 1);

			auto ret = newArray(t, 0);
			uword lastStart = 0;
			char[] tmp = str;

	        foreach(r; rex.search(str))
	        {
	            tmp = rex.pre();
	            
	            dup(t, ret);
	            pushString(t, tmp[lastStart .. $]);
	            cateq(t, 1);

	            lastStart = r.match(0).ptr - str.ptr;
	            tmp = rex.post();
	        }

			dup(t, ret);
			pushString(t, tmp);
			cateq(t, 1);

			return 1;
		}

		public uword find(MDThread* t, uword numParams)
		{
			auto rex = getThis(t);
			auto str = checkStringParam(t, 1);

			uword pos = str.length;

			if(safeCode(t, rex.test(str)))
				pos = safeCode(t, rex.match(0)).ptr - str.ptr;

			pushInt(t, pos);
			return 1;
		}

		uword iterator(MDThread* t, uword numParams)
		{
			auto rex = getThis(t);
			auto idx = getInt(t, 1) + 1;

			if(!safeCode(t, rex.test()))
				return 0;
				
			pushInt(t, idx);
			dup(t, 0);
			return 2;
		}

		public uword apply(MDThread* t, uword numParams)
		{
			getUpval(t, 0);
			dup(t, 0);
			pushInt(t, -1);
			return 3;
		}
	}
}