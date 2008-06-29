module dtest;

import tango.io.Stdout;
debug import tango.stdc.stdarg; // To make tango-user-base-debug.lib link correctly

import minid.api;

// TODO: Object finalizers...

void main()
{
	scope(exit) Stdout.flush;

	auto vm = new MDVM;
	auto t = openVM(vm);

	// This is all stdlib crap!
	newNamespace(t, "array");
	newFunction(t, &arrayToString, "array.toString");
	fielda(t, -2, "toString");
	setTypeMT(t, MDValue.Type.Array);
	newFunction(t, &microTime, "microTime");
	newGlobal(t, "microTime");
	Timer.init(t);

	lookupCT!("Timer")(t);

		auto funcReg = loadFunc(t, `benchmark\cheapconcurrency.md`);
		pushNull(t);
		rawCall(t, funcReg, 0);

	Stdout.newline.format("MiniD using {} bytes before GC, ", bytesAllocated(vm));
	gc(vm);
	Stdout.formatln("{} bytes after.", bytesAllocated(vm));

	closeVM(vm);
	delete vm;
}

nuint arrayToString(MDThread* t, nuint numParams)
{
	auto buf = StrBuffer(t);
	buf.addChar('[');

	auto length = len(t, 0);

	for(nuint i = 0; i < length; i++)
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

nuint microTime(MDThread* t, nuint numParams)
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
	}

	struct Members
	{
		protected StopWatch mWatch;
		protected mdfloat mTime = 0;
	}

	nuint clone(MDThread* t, nuint numParams)
	{
		newObject(t, 0, null, 0, Members.sizeof);
		*getMembers!(Members)(t, -1) = Members.init;
		return 1;
	}

	nuint start(MDThread* t, nuint numParams)
	{
		getThis(t).mWatch.start();
		return 0;
	}

	nuint stop(MDThread* t, nuint numParams)
	{
		auto members = getThis(t);
		members.mTime = members.mWatch.stop();
		return 0;
	}

	nuint seconds(MDThread* t, nuint numParams)
	{
		pushFloat(t, getThis(t).mTime);
		return 1;
	}

	nuint millisecs(MDThread* t, nuint numParams)
	{
		pushFloat(t, getThis(t).mTime * 1_000);
		return 1;
	}

	nuint microsecs(MDThread* t, nuint numParams)
	{
		pushFloat(t, getThis(t).mTime * 1_000_000);
		return 1;
	}
}