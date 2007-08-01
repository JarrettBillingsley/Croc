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
import minid.utils;

import tango.util.time.StopWatch;

version(Windows)
{
	private extern(Windows) int QueryPerformanceFrequency(ulong* frequency);
	private extern(Windows) int QueryPerformanceCounter(ulong* count);
}
else version(Unix)
{
	import tango.stdc.posix.sys.time;
}
else version(linux)
{
	import tango.stdc.posix.sys.time;
}
else
	static assert(false, "No valid platform defined");

class OSLib
{
	private static OSLib lib;
	
	static this()
	{
		lib = new OSLib();
	}
	
	private MDPerfCounterClass perfCounterClass;
	version(Windows) ulong performanceFreq;
	
	private this()
	{
		perfCounterClass = new MDPerfCounterClass();
		
		if(!QueryPerformanceFrequency(&performanceFreq))
			performanceFreq = 0x7fffffffffffffffL;
	}

	public static void init(MDContext context)
	{
		MDNamespace namespace = new MDNamespace("os"d, context.globals.ns);

		namespace.addList
		(
			"PerfCounter"d,  lib.perfCounterClass,
			"microTime"d,    new MDClosure(namespace, &lib.microTime, "os.microTime")
		);
		
		context.globals["os"d] = namespace;
	}

	int microTime(MDState s, uint numParams)
	{
		version(Windows)
		{
			ulong time;
			QueryPerformanceCounter(&time);

			if(time < 0x8637BD05AF6L)
				s.push((time * 1_000_000) / performanceFreq);
			else
				s.push((time / performanceFreq) * 1_000_000);
		}
		else
		{
			timeval tv;
			gettimeofday(&tv, null);
			s.push(cast(ulong)(tv.tv_sec * 1_000_000L) + cast(ulong)tv.tv_usec);
		}
		
		return 1;
	}

	static class MDPerfCounterClass : MDClass
	{
		public this()
		{
			super("PerfCounter", null);

			mMethods.addList
			(
				"start"d,     new MDClosure(mMethods, &start,     "PerfCounter.start"),
				"stop"d,      new MDClosure(mMethods, &stop,      "PerfCounter.stop"),
				"seconds"d,   new MDClosure(mMethods, &seconds,   "PerfCounter.seconds"),
				"millisecs"d, new MDClosure(mMethods, &millisecs, "PerfCounter.millisecs"),
				"microsecs"d, new MDClosure(mMethods, &microsecs, "PerfCounter.microsecs")
			);
		}

		public MDPerfCounter newInstance()
		{
			return new MDPerfCounter(this);
		}
		
		public int start(MDState s, uint numParams)
		{
			MDPerfCounter i = s.getContext!(MDPerfCounter);
			i.start();
			return 0;
		}
		
		public int stop(MDState s, uint numParams)
		{
			MDPerfCounter i = s.getContext!(MDPerfCounter);
			i.stop();
			return 0;
		}
		
		public int seconds(MDState s, uint numParams)
		{
			MDPerfCounter i = s.getContext!(MDPerfCounter);
			s.push(i.seconds());
			return 1;
		}
		
		public int millisecs(MDState s, uint numParams)
		{
			MDPerfCounter i = s.getContext!(MDPerfCounter);
			s.push(i.millisecs());
			return 1;
		}
		
		public int microsecs(MDState s, uint numParams)
		{
			MDPerfCounter i = s.getContext!(MDPerfCounter);
			s.push(i.microsecs());
			return 1;
		}
	}

	static class MDPerfCounter : MDInstance
	{
		protected StopWatch mWatch;
		protected mdfloat mTime = 0;

		public this(MDClass owner)
		{
			super(owner);
		}
		
		public final void start()
		{
			mWatch.start();
		}

		public final void stop()
		{
			mTime = mWatch.stop();
		}

		public final mdfloat seconds()
		{
			return mTime;
		}

		public final mdfloat millisecs()
		{
			return mTime * 1000;
		}

		public final mdfloat microsecs()
		{
			return mTime * 1000000;
		}
	}
}