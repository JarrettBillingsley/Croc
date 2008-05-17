/******************************************************************************
License:
Copyright (c) 2007 ideage lsina@126.com
and Copyright (c) 2007 Jarrett Billingsley

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

import minid.types;
import minid.utils;

import tango.text.Regex;

private alias RegExpT!(dchar) Regexd;

final class RegexpLib
{
	private MDRegexpClass regexpClass;
	
	private this(MDObject _Object)
	{
		regexpClass = new MDRegexpClass(_Object);
	}

	public static void init(MDContext context)
	{
		context.setModuleLoader("regexp", context.newClosure(function int(MDState s, uint numParams)
		{
			auto regexpLib = new RegexpLib(s.context.globals.get!(MDObject)("Object"d));

			auto lib = s.getParam!(MDNamespace)(1);

			lib.addList
			(
				"email"d,      r"\w+([\-+.]\w+)*@\w+([\-.]\w+)*\.\w+([\-.]\w+)*"d,
				"url"d,        r"(([h|H][t|T]|[f|F])[t|T][p|P]([s|S]?)\:\/\/|~/|/)?([\w]+:\w+@)?(([a-zA-Z]{1}([\w\-]+\.)+([\w]{2,5}))(:[\d]{1,5})?)?((/?\w+/)+|/?)(\w+\.[\w]{3,4})?([,]\w+)*((\?\w+=\w+)?(&\w+=\w+)*([,]\w*)*)?",
				"alpha"d,      r"^[a-zA-Z_]+$"d,
				"space"d,      r"^\s+$"d,
				"digit"d,      r"^\d+$"d,
				"hexdigit"d,   r"^[0-9A-Fa-f]+$"d,
				"octdigit"d,   r"^[0-7]+$"d,
				"symbol"d,     r"^[\(\)\[\]\.,;=<>\+\-\*/&\^]+$"d,

				"chinese"d,    "^[\u4e00-\u9fa5]+$"d,
				"cnPhone"d,    r"\d{3}-\d{8}|\d{4}-\d{7}"d,
				"cnMobile"d,   r"^((\(\d{2,3}\))|(\d{3}\-))?13\d{9}$"d,
				"cnZip"d,      r"^\d{6}$"d,
				"cnIDcard"d,   r"\d{15}|\d{18}"d,

				"usPhone"d,    r"^((1-)?\d{3}-)?\d{3}-\d{4}$"d,
				"usZip"d,      r"^\d{5}$"d,

				"compile"d,    new MDClosure(lib, &regexpLib.compile, "regexp.compile"),
				"test"d,       new MDClosure(lib, &test,              "regexp.test"),
				"replace"d,    new MDClosure(lib, &regexpLib.replace, "regexp.replace"),
				"split"d,      new MDClosure(lib, &split,             "regexp.split"),
				"match"d,      new MDClosure(lib, &match,             "regexp.match")
			);

			return 0;
		}, "regexp"));

		context.importModule("regexp");
	}

	static int test(MDState s, uint numParams)
	{
		auto pattern = s.getParam!(MDString)(0).mData;
		auto src = s.getParam!(MDString)(1).mData;
		dchar[] attributes = "";

		if(numParams > 2)
			attributes = s.getParam!(MDString)(2).mData;

		scope rx = s.safeCode(Regexd(pattern, attributes));
		s.push(s.safeCode(cast(bool)rx.test(src)));
		return 1;
	}

	int replace(MDState s, uint numParams)
	{
		auto pattern = s.getParam!(MDString)(0).mData;
		auto src = s.getParam!(MDString)(1).mData;
		dchar[] attributes = "";

		if(numParams > 3)
			attributes = s.getParam!(MDString)(3).mData;
			
		scope rx = s.safeCode(Regexd(pattern, attributes));

		if(s.isParam!("string")(2))
		{
			auto rep = s.getParam!(MDString)(2).mData;
			s.push(s.safeCode(rx.replaceAll(src, rep)));
		}
		else
		{
			auto rep = s.getParam!(MDClosure)(2);
			scope temp = regexpClass.nativeClone();

			s.push(s.safeCode(rx.replaceAll(src, (Regexd m)
			{
				temp.mRegexp = m;
				s.callWith(rep, 1, s.getContext(), temp);
				return s.pop!(MDString).mData;
			})));
		}

		return 1;
	}

	static int split(MDState s, uint numParams)
	{
		auto pattern = s.getParam!(MDString)(0).mData;
		auto src = s.getParam!(MDString)(1).mData;
		dchar[] attributes = "";

		if(numParams > 2)
			attributes = s.getParam!(MDString)(2).mData;

		scope rx = s.safeCode(Regexd(pattern, attributes));
		s.push(MDArray.fromArray(s.safeCode(rx.split(src))));
		return 1;
	}

	static int match(MDState s, uint numParams)
	{
		auto pattern = s.getParam!(MDString)(0).mData;
		auto src = s.getParam!(MDString)(1).mData;
		dchar[] attributes = "";

		if(numParams > 2)
			attributes = s.getParam!(MDString)(2).mData;

		bool global = false;
		
		foreach(c; attributes)
		{
			if(c is 'g')
			{
				global = true;
				break;
			}
		}
		
		scope r = s.safeCode(Regexd(pattern, attributes));
		dchar[][] matches;

		if(global)
		{
			for(auto cont = s.safeCode(r.test(src)); cont; cont = s.safeCode(r.test()))
				matches ~= r.match(0);
		}
		else
		{
			if(s.safeCode(r.test(src)))
				matches ~= r.match(0);
		}

		s.push(MDArray.fromArray(matches));
		return 1;
	}

	int compile(MDState s, uint numParams)
	{
		auto pattern = s.getParam!(MDString)(0).mData;
		dchar[] attributes = "";

		if(numParams > 1)
			attributes = s.getParam!(MDString)(1).mData;

		s.push(s.safeCode(regexpClass.nativeClone(pattern, attributes)));
		return 1;
	}

	static class MDRegexpClass : MDObject
	{
		MDClosure iteratorClosure;
		
		static class MDRegexp : MDObject
		{
			protected Regexd mRegexp;
			protected bool mGlobal = false;

			public this(MDObject owner)
			{
				super("Regexp", owner);
			}
		}

		public this(MDObject owner)
		{
			super("Regexp", owner);

			iteratorClosure = new MDClosure(fields, &iterator, "Regexp.iterator");

			fields.addList
			(
				"test"d,    new MDClosure(fields, &test,    "Regexp.test"),
				"search"d,  new MDClosure(fields, &search,  "Regexp.search"),
				"match"d,   new MDClosure(fields, &match,   "Regexp.match"),
				"pre"d,     new MDClosure(fields, &pre,     "Regexp.pre"),
				"post"d,    new MDClosure(fields, &post,    "Regexp.post"),
				"find"d,    new MDClosure(fields, &find,    "Regexp.find"),
				"split"d,   new MDClosure(fields, &split,   "Regexp.split"),
				"replace"d, new MDClosure(fields, &replace, "Regexp.replace"),
				"opApply"d, new MDClosure(fields, &apply,   "Regexp.opApply")
			);
			
			fields()["clone"d] = MDValue.nullValue;
		}

		public MDRegexp nativeClone()
		{
			return new MDRegexp(this);
		}

		protected MDRegexp nativeClone(dchar[] pattern, dchar[] attributes)
		{
			auto n = nativeClone();
			n.mRegexp = Regexd(pattern, attributes);

			foreach(c; attributes)
			{
				if(c is 'g')
				{
					n.mGlobal = true;
					break;
				}
			}

			return n;
		}

		public int test(MDState s, uint numParams)
		{
			auto r = s.getContext!(MDRegexp).mRegexp;

			if(numParams > 0)
				s.push(s.safeCode(r.test(s.getParam!(MDString)(0).mData)));
			else
				s.push(s.safeCode(r.test()));

			return 1;
		}

		public int match(MDState s, uint numParams)
		{
			auto r = s.getContext!(MDRegexp).mRegexp;

			if(numParams == 0)
				s.push(s.safeCode(r.match(0)));
			if(s.isParam!("int")(0))
				s.push(s.safeCode(r.match(s.getParam!(int)(0))));
			else
			{
				auto src = s.getParam!(MDString)(0).mData;
				dchar[][] matches;

				if(s.getContext!(MDRegexp).mGlobal)
				{
					for(auto cont = s.safeCode(r.test(src)); cont; cont = s.safeCode(r.test()))
						matches ~= r.match(0);
				}
				else
				{
					if(s.safeCode(r.test(src)))
						matches ~= r.match(0);
				}

				s.push(MDArray.fromArray(matches));
			}

			return 1;
		}

		public int search(MDState s, uint numParams)
		{
			auto r = s.getContext!(MDRegexp);
			s.safeCode(r.mRegexp.search(s.getParam!(MDString)(0).mData));
			s.push(r);
			return 1;
		}
		
		public int pre(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDRegexp).mRegexp.pre()));
			return 1;
		}

		public int post(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDRegexp).mRegexp.post()));
			return 1;
		}

		public int replace(MDState s, uint numParams)
		{
			auto r = s.getContext!(MDRegexp).mRegexp;
			auto src = s.getParam!(MDString)(0).mData;

			if(s.isParam!("string")(1))
			{
				auto rep = s.getParam!(MDString)(1).mData;
				s.push(s.safeCode(r.replaceAll(src, rep)));
			}
			else
			{
				auto rep = s.getParam!(MDClosure)(2);
				scope temp = nativeClone();

				s.push(s.safeCode(r.replaceAll(src, (Regexd m)
				{
					temp.mRegexp = m;
					s.callWith(rep, 1, s.getContext(), temp);
					return s.pop!(MDString).mData;
				})));
			}

			return 1;
		}

		public int split(MDState s, uint numParams)
		{
			auto r = s.getContext!(MDRegexp).mRegexp;
			s.push(MDArray.fromArray(s.safeCode(r.split(s.getParam!(MDString)(0).mData))));
			return 1;
		}

		public int find(MDState s, uint numParams)
		{
			auto r = s.getContext!(MDRegexp).mRegexp;
			auto str = s.getParam!(MDString)(0).mData;
			
			int pos = -1;

			if(s.safeCode(r.test(str)))
				pos = s.safeCode(r.match(0)).ptr - str.ptr;

			s.push(pos);
			return 1;
		}

		int iterator(MDState s, uint numParams)
		{
			auto r = s.getContext!(MDRegexp);
			int index = s.getParam!(int)(0) + 1;

			if(!s.safeCode(r.mRegexp.test()))
				return 0;

			s.push(index);
			s.push(r);
			return 2;
		}

		public int apply(MDState s, uint numParams)
		{
			s.push(iteratorClosure);
			s.push(s.getContext!(MDRegexp));
			s.push(-1);
			return 3;
		}
	}
}