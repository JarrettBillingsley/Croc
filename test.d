module test;

import tango.io.Stdout;
debug import tango.stdc.stdarg; // To make tango-user-base-debug.lib link correctly

import minid.api;
import minid.bind;

// version = TestArc;

version(TestArc)
	import arc_wrap.all;

void main()
{
	scope(exit) Stdout.flush;

	MDVM vm;
	auto t = openVM(&vm);
	loadStdlibs(t);

	version(TestArc)
		ArcLib.init(t);

	WrapGlobals!
	(
		WrapType!
		(
			Base, "Base",
			WrapCtors!(void function(int, int)),
			WrapMethod!(Base.overrideMe),
			WrapProperty!(Base.x)
		),
		
		WrapType!(S, "S", WrapProperty!(S.w)),

		WrapFunc!(foob),
		WrapFunc!(freep)
	)(t);

	try
	{
		version(TestArc)
			importModule(t, "samples.arctest");
		else
			importModule(t, "samples.simple");
			
		pushNull(t);
		lookup(t, "modules.runMain");
		swap(t, -3);
		rawCall(t, -3, 0);
	}
	catch(MDException e)
	{
		auto ex = catchException(t);
		Stdout.formatln("Error: {}", e);

		auto tb = getTraceback(t);
		Stdout.formatln("{}", getString(t, tb));
		
		if(e.info)
			Stdout.formatln("D Traceback: {}", e.info);
	}
	catch(Exception e)
	{
		Stdout.formatln("Bad error ({}, {}): {}", e.file, e.line, e);
		
		if(e.info)
			Stdout.formatln("D Traceback: {}", e.info);

		return;
	}

	Stdout.newline.format("MiniD using {} bytes before GC, ", bytesAllocated(&vm)).flush;
	gc(t);
	Stdout.formatln("{} bytes after.", bytesAllocated(&vm)).flush;

	closeVM(&vm);
}

class Base
{
	int mX, mY;

	this(int x, int y)
	{
		mX = x;
		mY = y;
	}
	
	void overrideMe(int x)
	{
		Stdout.formatln("Base overrideMe {}", x);
	}
	
	int x() { return mX; }
	void x(int x) { mX = x; }
}

struct S
{
	int x, y;
	private int z;
	
	int w() { return 5; }
}

void foob(Base b)
{
	b.overrideMe(3);
}

Base freep()
{
	return new Base(1, 5);
}