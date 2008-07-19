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

3.  Look for .md and .mdm.  If found, create closure with new namespace ace env, call.
	if it succeeds, put that namespace in the owning namespace.

4.  Look for custom loader.  If founc, call with new namespace as param, and if it succeeds, put ns in owning ns.

5.  [Optional] Look for dynlib, same procedure as 4.
*/

void main()
{
	scope(exit) Stdout.flush;

	auto vm = new MDVM;
	auto t = openVM(vm);
	
	uword memSize;

	{
		scope c = new Compiler(t);
		c.testParse(`samples\simple.md`);
		memSize = bytesAllocated(vm);
	}
	
	Stdout.formatln("Compilation used {} bytes of non-GC'ed memory", memSize - bytesAllocated(vm));

// 	// This is all stdlib crap!
// 	newNamespace(t, "array");
// 	newFunction(t, &arrayToString, "array.toString");
// 	fielda(t, -2, "toString");
// 	setTypeMT(t, MDValue.Type.Array);
// 	newFunction(t, &microTime, "microTime");
// 	newGlobal(t, "microTime");
// 	Timer.init(t);
//
// 		auto funcReg = loadFunc(t, `samples\simple.md`);
// 		pushNull(t);
// 		rawCall(t, funcReg, 0);

	Stdout.newline.format("MiniD using {} bytes before GC, ", bytesAllocated(vm)).flush;
	gc(vm);
	Stdout.formatln("{} bytes after.", bytesAllocated(vm)).flush;

	closeVM(vm);
	delete vm;
}

uword arrayToString(MDThread* t, uword numParams)
{
	auto buf = StrBuffer(t);
	buf.addChar('[');

	auto length = len(t, 0);

	for(uword i = 0; i < length; i++)
	{
		pushInt(t, i);
		idx(t, 0);

		if(isString(t, -1))
		{
			// this is GC-safe since the string is stored in the array
			auto s = getString(t, -1);
			pop(t);
			buf.addChar('"');
			buf.addString(s);
			buf.addChar('"');
		}
		else if(isChar(t, -1))
		{
			auto c = getChar(t, -1);
			pop(t);
			buf.addChar('\'');
			buf.addChar(c);
			buf.addChar('\'');
		}
		else
		{
			pushToString(t, -1, true);
			insert(t, -2);
			pop(t);
			buf.addTop();
		}

		if(i < length - 1)
			buf.addString(", ");
	}

	buf.addChar(']');
	buf.finish();

	return 1;
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