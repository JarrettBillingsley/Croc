module test;

import tango.io.Stdout;
debug import tango.stdc.stdarg; // To make tango-user-base-debug.lib link correctly

import minid.api;

import minid.ast;
import minid.compiler;
import minid.lexer;

// TODO: Object finalizers...

/*
Import:

1.  See if already loaded.

2.  See if that name is taken.

3.  Look for .md and .mdm.  If found, create closure with new namespace env, call.
	if it succeeds, put that namespace in the owning namespace.

4.  Look for custom loader.  If found, call with name of module to get loader func.
	call that with new namespace as env, and if it succeeds, put ns in owning ns.

5.  [Optional] Look for dynlib, same procedure as 4.
*/

void main()
{
	scope(exit) Stdout.flush;

	auto vm = new MDVM;
	auto t = openVM(vm);
	loadStdlibs(t);

	// This is all stdlib crap!
	newFunction(t, &microTime, "microTime");
	newGlobal(t, "microTime");
	Timer.init(t);

		importModule(t, "samples.simple");

	Stdout.newline.format("MiniD using {} bytes before GC, ", bytesAllocated(vm)).flush;
	gc(vm);
	Stdout.formatln("{} bytes after.", bytesAllocated(vm)).flush;

	closeVM(vm);
	delete vm;
}

private extern(Windows) int QueryPerformanceFrequency(ulong* frequency);
private extern(Windows) int QueryPerformanceCounter(ulong* count);
ulong performanceFreq;

static this()
{
	if(!QueryPerformanceFrequency(&performanceFreq))
		performanceFreq = 0x7fffffffffffffffL;
}

uword microTime(MDThread* t, uword numParams)
{
	ulong time;
	QueryPerformanceCounter(&time);

	if(time < 0x8637BD05AF6L)
		pushInt(t, cast(mdint)((time * 1_000_000) / performanceFreq));
	else
		pushInt(t, cast(mdint)((time / performanceFreq) * 1_000_000));

	return 1;
}

import tango.time.StopWatch;
struct Timer
{
static:
	private Members* getThis(MDThread* t)
	{
		return checkObjParam!(Members)(t, 0, "Timer");
	}

	void init(MDThread* t)
	{
		CreateObject(t, "Timer", (CreateObject* o)
		{
			o.method("clone", &clone);
			o.method("start", &start);
			o.method("stop", &stop);
			o.method("seconds", &seconds);
			o.method("millisecs", &millisecs);
			o.method("microsecs", &microsecs);
		});

		newGlobal(t, "Timer");
	}

	struct Members
	{
		protected StopWatch mWatch;
		protected mdfloat mTime = 0;
	}

	uword clone(MDThread* t, uword numParams)
	{
		newObject(t, 0, null, 0, Members.sizeof);
		*getMembers!(Members)(t, -1) = Members.init;
		return 1;
	}

	uword start(MDThread* t, uword numParams)
	{
		getThis(t).mWatch.start();
		return 0;
	}

	uword stop(MDThread* t, uword numParams)
	{
		auto members = getThis(t);
		members.mTime = members.mWatch.stop();
		return 0;
	}

	uword seconds(MDThread* t, uword numParams)
	{
		pushFloat(t, getThis(t).mTime);
		return 1;
	}

	uword millisecs(MDThread* t, uword numParams)
	{
		pushFloat(t, getThis(t).mTime * 1_000);
		return 1;
	}

	uword microsecs(MDThread* t, uword numParams)
	{
		pushFloat(t, getThis(t).mTime * 1_000_000);
		return 1;
	}
}