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
				"email"d,      r"\w+([-+.]\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*"d,
				"url"d,        tango.text.Regex.url,
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
		char[] pattern = s.getParam!(char[])(0);
		char[] src = s.getParam!(char[])(1);
		char[] attributes = "";

		if(numParams > 2)
			attributes = s.getParam!(char[])(2);

		s.push(s.safeCode(cast(bool)Regex(pattern, attributes).test(src)));
		return 1;
	}

	int replace(MDState s, uint numParams)
	{
		char[] pattern = s.getParam!(char[])(0);
		char[] src = s.getParam!(char[])(1);
		char[] attributes = "";

		if(numParams > 3)
			attributes = s.getParam!(char[])(3);

		if(s.isParam!("string")(2))
		{
			char[] rep = s.getParam!(char[])(2);
			s.push(s.safeCode(Regex(pattern, attributes).replace(src, rep)));
		}
		else
		{
			MDClosure rep = s.getParam!(MDClosure)(2);
			scope MDRegexp temp = regexpClass.nativeClone();

			s.push(s.safeCode(sub(src, pattern, (Regex m)
			{
				temp.constructor(m);

				s.callWith(rep, 1, s.getContext(), temp);

				return s.pop!(char[]);
			}, attributes)));
		}

		return 1;
	}

	static int split(MDState s, uint numParams)
	{
		char[] pattern = s.getParam!(char[])(0);
		char[] src = s.getParam!(char[])(1);
		char[] attributes = "";

		if(numParams > 2)
			attributes = s.getParam!(char[])(2);

		s.push(MDArray.fromArray(s.safeCode(Regex(pattern, attributes).split(src))));
		return 1;
	}

	static int match(MDState s, uint numParams)
	{
		char[] pattern = s.getParam!(char[])(0);
		char[] src = s.getParam!(char[])(1);
		char[] attributes = "";

		if(numParams > 2)
			attributes = s.getParam!(char[])(2);

		s.push(MDArray.fromArray(s.safeCode(Regex(pattern, attributes).match(src))));
		return 1;
	}

	int compile(MDState s, uint numParams)
	{
		char[] pattern = s.getParam!(char[])(0);
		char[] attributes = "";

		if(numParams > 1)
			attributes = s.getParam!(char[])(1);

		s.push(s.safeCode(regexpClass.nativeClone(pattern, attributes)));
		return 1;
	}

	static class MDRegexpClass : MDObject
	{
		MDClosure iteratorClosure;

		public this(MDObject owner)
		{
			super("Regexp", owner);

			iteratorClosure = new MDClosure(mFields, &iterator, "Regexp.iterator");

			mFields.addList
			(
				"test"d,    new MDClosure(mFields, &test,    "Regexp.test"),
				"search"d,  new MDClosure(mFields, &search,  "Regexp.search"),
				"match"d,   new MDClosure(mFields, &match,   "Regexp.match"),
				"pre"d,     new MDClosure(mFields, &pre,     "Regexp.pre"),
				"post"d,    new MDClosure(mFields, &post,    "Regexp.post"),
				"find"d,    new MDClosure(mFields, &find,    "Regexp.find"),
				"split"d,   new MDClosure(mFields, &split,   "Regexp.split"),
				"replace"d, new MDClosure(mFields, &replace, "Regexp.replace"),
				"opApply"d, new MDClosure(mFields, &apply,   "Regexp.opApply")
			);
			
			mFields["clone"d] = MDValue.nullValue;
		}

		public MDRegexp nativeClone()
		{
			return new MDRegexp(this);
		}

		protected MDRegexp nativeClone(char[] pattern, char[] attributes)
		{
			auto n = nativeClone();
			n.constructor(pattern, attributes);
			return n;
		}

		public int test(MDState s, uint numParams)
		{
			MDRegexp r = s.getContext!(MDRegexp);
			s.push(r.test(s.getParam!(char[])(0)));
			return 1;
		}

		public int match(MDState s, uint numParams)
		{
			MDRegexp r = s.getContext!(MDRegexp);

			if(numParams == 0)
				s.push(r.match(0));
			else if(s.isParam!("int")(0))
				s.push(r.match(s.getParam!(int)(0)));
			else
				s.push(MDArray.fromArray(r.match(s.getParam!(char[])(0))));

			return 1;
		}

		public int search(MDState s, uint numParams)
		{
			MDRegexp r = s.getContext!(MDRegexp);
			char[] str = s.getParam!(char[])(0);

			r.search(str);
			s.push(r);
			return 1;
		}
		
		public int pre(MDState s, uint numParams)
		{
			MDRegexp r = s.getContext!(MDRegexp);
			s.push(r.pre());
			return 1;
		}

		public int post(MDState s, uint numParams)
		{
			MDRegexp r = s.getContext!(MDRegexp);
			s.push(r.post());
			return 1;
		}

		public int replace(MDState s, uint numParams)
		{
			MDRegexp r = s.getContext!(MDRegexp);
			s.push(r.replace(s.getParam!(char[])(0), s.getParam!(char[])(1)));
			return 1;
		}

		public int split(MDState s, uint numParams)
		{
			MDRegexp r = s.getContext!(MDRegexp);
			s.push(MDArray.fromArray(r.split(s.getParam!(char[])(0))));
			return 1;
		}

		public int find(MDState s, uint numParams)
		{
			MDRegexp r = s.getContext!(MDRegexp);
			s.push(r.find(s.getParam!(char[])(0)));
			return 1;
		}

		int iterator(MDState s, uint numParams)
		{
			MDRegexp r = s.getContext!(MDRegexp);
			int index = s.getParam!(int)(0) + 1;

			if(!r.test())
				return 0;

			s.push(index);
			s.push(r);
			return 2;
		}

		public int apply(MDState s, uint numParams)
		{
			MDRegexp r = s.getContext!(MDRegexp);
			s.push(iteratorClosure);
			s.push(r);
			s.push(-1);
			return 3;
		}
	}

	static class MDRegexp : MDObject
	{
		protected Regex mRegexp;

		public this(MDObject owner)
		{
			super("Regexp", owner);
		}

		public void constructor(char[] pattern, char[] attributes)
		{
			mRegexp = new Regex(pattern, attributes);
		}

		public void constructor(Regex rxp)
		{
			mRegexp = rxp;
		}

		char[] match(uint n)
		{
			return mRegexp.match(n);
		}

		char[] pre()
		{
			return mRegexp.pre();
		}

		char[] post()
		{
			return mRegexp.post();
		}

		public bool test(char[] str)
		{
			return cast(bool)mRegexp.test(str);
		}
		
		public bool test()
		{
			return cast(bool)mRegexp.test();
		}

		int find(char[] str)
		{
			return mRegexp.find(str);
		}

		char[][] split(char[] str)
		{
			return mRegexp.split(str);
		}

		char[][] match(char[] str)
		{
			return mRegexp.match(str);
		}

		char[] replace(char[] str, char[] format)
		{
			return mRegexp.replace(str,format);
		}
		
		void search(char[] str)
		{
			mRegexp.search(str);
		}
	}
}