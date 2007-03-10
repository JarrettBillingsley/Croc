/******************************************************************************
License:
Copyright (c) 2007 Jarrett Billingsley

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

module minid.oslib;

import minid.types;

import std.perf;

version(Windows)
{
	import std.c.windows.windows;
}
else
{
	import std.c.linux.linux;

	extern (C)
	{
		struct timeval
		{
			int tv_sec;
			int tv_usec;
		}

		struct timezone
		{
			int tz_minuteswest;
			int tz_dsttime;
		}

		private void gettimeofday(timeval *tv, timezone *tz);
	}
}

class OSLib
{
	this(MDNamespace namespace)
	{
		perfCounterClass = new MDPerfCounterClass();

		version(Windows)
		{
			if(!QueryPerformanceFrequency(&performanceFreq))
				performanceFreq = 0x7fffffffffffffffL;
		}

		namespace.addList
		(
			"PerfCounter"d,       perfCounterClass,
			"microTime"d,         new MDClosure(namespace, &microTime, "os.microTime")
		);
	}

	version(Windows) long performanceFreq;

	int microTime(MDState s)
	{
		version(Windows)
		{
			long time;
			QueryPerformanceCounter(&time);

			if(time < 0x8637BD05AF6L)
				s.push((time * 1000000) / performanceFreq);
			else
				s.push((time / performanceFreq) * 1000000);
		}
		else
		{
			// Let's just assume that most other OSes besides Windows support gettimeofday()...
			timeval tv;
			timezone tz;
			gettimeofday(&tv, &tz);
			s.push(tv_usec);
		}
		
		return 1;
	}

	MDPerfCounterClass perfCounterClass;

	static class MDPerfCounterClass : MDClass
	{
		public this()
		{
			super("PerfCounter", null);

			mMethods.addList
			(
				"start"d,     new MDClosure(mMethods, &start,     "PerfCounter.start"),
				"stop"d,      new MDClosure(mMethods, &stop,      "PerfCounter.stop"),
				"period"d,    new MDClosure(mMethods, &period,    "PerfCounter.period"),
				"seconds"d,   new MDClosure(mMethods, &seconds,   "PerfCounter.seconds"),
				"millisecs"d, new MDClosure(mMethods, &millisecs, "PerfCounter.millisecs"),
				"microsecs"d, new MDClosure(mMethods, &microsecs, "PerfCounter.microsecs")
			);
		}

		public MDPerfCounter newInstance()
		{
			return new MDPerfCounter(this);
		}
		
		public int start(MDState s)
		{
			MDPerfCounter i = cast(MDPerfCounter)s.getContext().asInstance();
			i.start();
			return 0;
		}
		
		public int stop(MDState s)
		{
			MDPerfCounter i = cast(MDPerfCounter)s.getContext().asInstance();
			i.stop();
			return 0;
		}
		
		public int period(MDState s)
		{
			MDPerfCounter i = cast(MDPerfCounter)s.getContext().asInstance();
			s.push(i.period());
			return 1;
		}
		
		public int seconds(MDState s)
		{
			MDPerfCounter i = cast(MDPerfCounter)s.getContext().asInstance();
			s.push(i.seconds());
			return 1;
		}
		
		public int millisecs(MDState s)
		{
			MDPerfCounter i = cast(MDPerfCounter)s.getContext().asInstance();
			s.push(i.millisecs());
			return 1;
		}
		
		public int microsecs(MDState s)
		{
			MDPerfCounter i = cast(MDPerfCounter)s.getContext().asInstance();
			s.push(i.microsecs());
			return 1;
		}
	}

	static class MDPerfCounter : MDInstance
	{
		protected PerformanceCounter mCounter;

		public this(MDClass owner)
		{
			super(owner);
			mCounter = new PerformanceCounter();
		}
		
		public void start()
		{
			mCounter.start();
		}
		
		public void stop()
		{
			mCounter.stop();
		}
		
		public int period()
		{
			return mCounter.periodCount();
		}
		
		public float seconds()
		{
			return mCounter.microseconds() / 1000000.0;
		}
		
		public float millisecs()
		{
			return mCounter.microseconds() / 1000.0;
		}
		
		public float microsecs()
		{
			return mCounter.microseconds();
		}
	}
}

public void init()
{
	MDNamespace namespace = new MDNamespace("os"d, MDGlobalState().globals);
	new OSLib(namespace);
	MDGlobalState().setGlobal("os"d, namespace);
}