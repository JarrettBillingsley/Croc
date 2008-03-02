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

import tango.stdc.stdlib;
import tango.stdc.stringz;
import tango.sys.Environment;
import tango.text.locale.Convert;
import tango.text.locale.Core;
import tango.time.Time;
import tango.time.StopWatch;
import tango.time.WallClock;
import tango.time.chrono.Gregorian;

version(Windows)
{
	private extern(Windows) int QueryPerformanceFrequency(ulong* frequency);
	private extern(Windows) int QueryPerformanceCounter(ulong* count);
}
else version(Posix)
{
	import tango.stdc.posix.sys.time;
}
else
	static assert(false, "No valid platform defined");

final class OSLib
{
static:
	private MDValue YearString;
	private MDValue MonthString;
	private MDValue DayString;
	private MDValue HourString;
	private MDValue MinString;
	private MDValue SecString;
	version(Windows) ulong performanceFreq;

	static this()
	{
		YearString = new MDString("year"d);
		MonthString = new MDString("month"d);
		DayString = new MDString("day"d);
		HourString = new MDString("hour"d);
		MinString = new MDString("min"d);
		SecString = new MDString("sec"d);

		version(Windows)
		{
			if(!QueryPerformanceFrequency(&performanceFreq))
				performanceFreq = 0x7fffffffffffffffL;
		}
	}

	public void init(MDContext context)
	{
		context.setModuleLoader("os", context.newClosure(function int(MDState s, uint numParams)
		{
			auto perfCounterClass = new MDPerfCounterClass(s.context.globals.get!(MDObject)("Object"d));

			auto lib = s.getParam!(MDNamespace)(1);

			lib.addList
			(
				"PerfCounter"d,  perfCounterClass,
				"microTime"d,    new MDClosure(lib, &microTime,  "os.microTime"),
				"system"d,       new MDClosure(lib, &system,     "os.system"),
				"getEnv"d,       new MDClosure(lib, &getEnv,     "os.getEnv"),
				"dateString"d,   new MDClosure(lib, &dateString, "os.dateString"),
				"dateTime"d,     new MDClosure(lib, &dateTime,   "os.dateTime"),
				"culture"d,      new MDClosure(lib, &culture,    "os.culture")
			);

			return 0;
		}, "os"));
		
		context.importModule("os");
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
			s.push(tv.tv_sec * 1_000_000L + tv.tv_usec);
		}
		
		return 1;
	}
	
	int system(MDState s, uint numParams)
	{
		if(numParams == 0)
			s.push(.system(null) ? true : false);
		else
			s.push(.system(toStringz(s.getParam!(char[])(0))));

		return 1;
	}

	int getEnv(MDState s, uint numParams)
	{
		if(numParams == 0)
			s.push(Environment.get());
		else
		{
			char[] def = null;
			
			if(numParams > 1)
				def = s.getParam!(char[])(1);

			char[] val = Environment.get(s.getParam!(char[])(0), def);
			
			if(val is null)
				s.pushNull();
			else
				s.push(val);
		}
		
		return 1;
	}

	int dateString(MDState s, uint numParams)
	{
		Time time;
		char[40] buffer;
		char[] format = "G";
		Culture culture = null;

		if(numParams > 0)
			format = s.getParam!(char[])(0);

		if(numParams > 1 && !s.isParam!("null")(1))
			time = TableToTime(s, s.getParam!(MDTable)(1));
		else
			time = WallClock.now;

		if(numParams > 2)
			culture = s.safeCode(Culture.getCulture(s.getParam!(char[])(2)));

		s.push(s.safeCode(formatDateTime(buffer, time, format, culture)));
		return 1;
	}
	
	int dateTime(MDState s, uint numParams)
	{
		MDTable t = null;
		
		if(numParams > 0)
			t = s.getParam!(MDTable)(0);

		s.push(DateTimeToTable(s, WallClock.toDate, t));
		return 1;
	}
	
	int culture(MDState s, uint numParams)
	{
		s.push(Culture.current.name);

		if(numParams > 0)
			Culture.current = s.safeCode(Culture.getCulture(s.getParam!(char[])(0)));

		return 1;
	}

	Time TableToTime(MDState s, MDTable tab)
	{
		MDValue table = MDValue(tab);
		Time time;

		with(s)
		{
			MDValue year = idx(table, YearString);
			MDValue month = idx(table, MonthString);
			MDValue day = idx(table, DayString);
			MDValue hour = idx(table, HourString);
			MDValue min = idx(table, MinString);
			MDValue sec = idx(table, SecString);

			if(!year.isInt() || !month.isInt() || !day.isInt())
				s.throwRuntimeException("year, month, and day fields in time table must exist and must be integers");

			if(hour.isInt() && min.isInt() && sec.isInt())
				time = Gregorian.generic.toTime(year.as!(int), month.as!(int), day.as!(int), hour.as!(int), min.as!(int), sec.as!(int), 0, 0);
			else
				time = Gregorian.generic.toTime(year.as!(int), month.as!(int), day.as!(int), 0, 0, 0, 0, 0);
		}

		return time;
	}

	MDTable DateTimeToTable(MDState s, DateTime time, MDTable dest)
	{
		if(dest is null)
			dest = new MDTable();

		MDValue table = dest;

		with(s)
		{
			idxa(table, YearString, MDValue(time.date.year));
			idxa(table, MonthString, MDValue(time.date.month));
			idxa(table, DayString, MDValue(time.date.day));
			idxa(table, HourString, MDValue(time.time.hours));
			idxa(table, MinString, MDValue(time.time.minutes));
			idxa(table, SecString, MDValue(time.time.seconds));
		}
		
		return dest;
	}

	static class MDPerfCounterClass : MDObject
	{
		static class MDPerfCounter : MDObject
		{
			protected StopWatch mWatch;
			protected mdfloat mTime = 0;
			
			public this(MDObject owner)
			{
				super("PerfCounter", owner);
			}
		}

		public this(MDObject owner)
		{
			super("PerfCounter", owner);

			mFields.addList
			(
				"clone"d,     new MDClosure(mFields, &clone,     "PerfCounter.clone"),
				"start"d,     new MDClosure(mFields, &start,     "PerfCounter.start"),
				"stop"d,      new MDClosure(mFields, &stop,      "PerfCounter.stop"),
				"seconds"d,   new MDClosure(mFields, &seconds,   "PerfCounter.seconds"),
				"millisecs"d, new MDClosure(mFields, &millisecs, "PerfCounter.millisecs"),
				"microsecs"d, new MDClosure(mFields, &microsecs, "PerfCounter.microsecs")
			);
		}

		public int clone(MDState s, uint numParams)
		{
			s.push(new MDPerfCounter(this));
			return 1;
		}

		public int start(MDState s, uint numParams)
		{
			s.getContext!(MDPerfCounter).mWatch.start();
			return 0;
		}

		public int stop(MDState s, uint numParams)
		{
			auto self = s.getContext!(MDPerfCounter);
			self.mTime = self.mWatch.stop();
			return 0;
		}

		public int seconds(MDState s, uint numParams)
		{
			s.push(s.getContext!(MDPerfCounter).mTime);
			return 1;
		}

		public int millisecs(MDState s, uint numParams)
		{
			s.push(s.getContext!(MDPerfCounter).mTime * 1_000);
			return 1;
		}

		public int microsecs(MDState s, uint numParams)
		{
			s.push(s.getContext!(MDPerfCounter).mTime * 1_000_000);
			return 1;
		}
	}
}