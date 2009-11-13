/******************************************************************************
This module contains the 'time' standard library.

License:
Copyright (c) 2008 Jarrett Billingsley

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

module minid.timelib;

import tango.core.Thread;
import tango.text.locale.Convert;
import tango.text.locale.Core;
import tango.time.chrono.Gregorian;
import tango.time.Clock;
import tango.time.StopWatch;
import tango.time.Time;
import tango.time.WallClock;
import Utf = tango.text.convert.Utf;

import minid.ex;
import minid.interpreter;
import minid.types;
import minid.utils;

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

struct TimeLib
{
static:
	version(Windows)
	{
		ulong performanceFreq;

		static this()
		{
			if(!QueryPerformanceFrequency(&performanceFreq))
				performanceFreq = 0x7fffffffffffffffL;
		}
	}

	public void init(MDThread* t)
	{
		makeModule(t, "time", function uword(MDThread* t, uword numParams)
		{
			Timer.init(t);
			newFunction(t, &microTime,  "microTime");  newGlobal(t, "microTime");
			newFunction(t, &dateString, "dateString"); newGlobal(t, "dateString");
			newFunction(t, &dateTime,   "dateTime");   newGlobal(t, "dateTime");
			newFunction(t, &culture,    "culture");    newGlobal(t, "culture");
			newFunction(t, &timestamp,  "timestamp");  newGlobal(t, "timestamp");
			newFunction(t, &timex,      "timex");      newGlobal(t, "timex");
			newFunction(t, &sleep,      "sleep");      newGlobal(t, "sleep");
			newFunction(t, &compare,    "compare");    newGlobal(t, "compare");

			return 0;
		});

		importModuleNoNS(t, "time");
	}

	uword microTime(MDThread* t, uword numParams)
	{
		version(Windows)
		{
			ulong time;
			QueryPerformanceCounter(&time);
			pushInt(t, cast(mdint)((time * 1_000_000) / performanceFreq));
		}
		else
		{
			timeval tv;
			gettimeofday(&tv, null);
			pushInt(t, cast(mdint)(tv.tv_sec * 1_000_000L + tv.tv_usec));
		}

		return 1;
	}

	uword dateString(MDThread* t, uword numParams)
	{
		char[] format = numParams > 0 ? GetFormat(t, 1) : "G";

		Time time = void;

		if(numParams > 1 && !isNull(t, 2))
			time = TableToTime(t, 2);
		else if(format == "R")
			time = Clock.now;
		else
			time = WallClock.now;

		Culture culture = null;

		if(numParams > 2)
		{
			auto name = StrToCulture(t, 1);
			culture = safeCode(t, Culture.getCulture(name));
		}

		char[40] buffer;
		auto ret = safeCode(t, formatDateTime(buffer, time, format, culture));

		pushString(t, ret);
		return 1;
	}
	
	uword dateTime(MDThread* t, uword numParams)
	{
		bool useGMT = false;
		word tab;

		if(numParams == 0)
			tab = newTable(t);
		else if(isBool(t, 1))
		{
			useGMT = getBool(t, 1);

			if(numParams > 1)
			{
				checkParam(t, 2, MDValue.Type.Table);
				tab = 2;
			}
			else
				tab = newTable(t);
		}
		else
		{
			checkParam(t, 1, MDValue.Type.Table);
			tab = 1;
		}

		DateTimeToTable(t, useGMT ? Clock.toDate : WallClock.toDate, tab);
		dup(t, tab);
		return 1;
	}

	uword culture(MDThread* t, uword numParams)
	{
		pushString(t, Culture.current.name);

		if(numParams > 0)
		{
			auto name = StrToCulture(t, 1);
			Culture.current = safeCode(t, Culture.getCulture(name));
		}

		return 1;
	}
	
	uword compare(MDThread* t, uword numParams)
	{
		checkParam(t, 1, MDValue.Type.Table);
		checkParam(t, 2, MDValue.Type.Table);
		auto t1 = TableToTime(t, 1);
		auto t2 = TableToTime(t, 2);
		pushInt(t, cast(mdint)t1.opCmp(t2));
		return 1;
	}

	// longest possible is 5 chars * 4 bytes per char = 20 bytes?
	char[] StrToCulture(MDThread* t, word slot)
	{
		checkStringParam(t, slot);

		if(len(t, slot) != 5)
			throwException(t, "Culture name {} is not supported.", getString(t, slot));

		return getString(t, slot);
	}

	char[] GetFormat(MDThread* t, word slot)
	{
		auto s = checkStringParam(t, slot);

		if(s.length == 1)
		{
			switch(s[0])
			{
				case 'd':
				case 'D':
				case 't':
				case 'T':
				case 'g':
				case 'G':
				case 'M':
				case 'R':
				case 's':
				case 'Y': return s;

				default:
					break;
			}
		}

		throwException(t, "invalid format string");
		assert(false);
	}

	Time TableToTime(MDThread* t, word tab)
	{
		auto year = field(t, tab, "year");
		auto month = field(t, tab, "month");
		auto day = field(t, tab, "day");
		auto hour = field(t, tab, "hour");
		auto min = field(t, tab, "min");
		auto sec = field(t, tab, "sec");

		if(!isInt(t, year) || !isInt(t, month) || !isInt(t, day))
			throwException(t, "year, month, and day fields in time table must exist and must be integers");

		Time time = void;

		if(isInt(t, hour) && isInt(t, min) && isInt(t, sec))
		{
			time = Gregorian.generic.toTime(cast(uint)getInt(t, year), cast(uint)getInt(t, month), cast(uint)getInt(t, day),
				cast(uint)getInt(t, hour), cast(uint)getInt(t, min), cast(uint)getInt(t, sec), 0, 0);
		}
		else
			time = Gregorian.generic.toTime(cast(uint)getInt(t, year), cast(uint)getInt(t, month), cast(uint)getInt(t, day), 0, 0, 0, 0, 0);

		pop(t, 6);

		return time;
	}

	void DateTimeToTable(MDThread* t, DateTime time, word dest)
	{
		pushInt(t, time.date.year);    fielda(t, dest, "year");
		pushInt(t, time.date.month);   fielda(t, dest, "month");
		pushInt(t, time.date.day);     fielda(t, dest, "day");
		pushInt(t, time.time.hours);   fielda(t, dest, "hour");
		pushInt(t, time.time.minutes); fielda(t, dest, "min");
		pushInt(t, time.time.seconds); fielda(t, dest, "sec");
	}

	uword timestamp(MDThread* t, uword numParams)
	{
		pushInt(t, cast(mdint)(Clock.now - Time.epoch1970).seconds);
		return 1;
	}

	uword timex(MDThread* t, uword numParams)
	{
		checkParam(t, 1, MDValue.Type.Function);
		pushNull(t);
		insert(t, 2);

		StopWatch w;
		w.start();
		rawCall(t, 1, 0);
		pushFloat(t, w.stop());

		return 1;
	}

	uword sleep(MDThread* t, uword numParams)
	{
		auto dur = checkNumParam(t, 1);
		
		if(dur < 0)
			throwException(t, "Invalid sleep duration: {}", dur);

		Thread.sleep(dur);
		return 0;
	}

	static struct Timer
	{
	static:
		align(1) struct Members
		{
			protected StopWatch mWatch;
			protected mdfloat mTime = 0;
		}

		void init(MDThread* t)
		{
			CreateClass(t, "Timer", (CreateClass* c)
			{
				c.method("start", &start);
				c.method("stop", &stop);
				c.method("seconds", &seconds);
				c.method("millisecs", &millisecs);
				c.method("microsecs", &microsecs);
			});

			newFunction(t, &allocator, "Timer.allocator");
			setAllocator(t, -2);

			newGlobal(t, "Timer");
		}

		private Members* getThis(MDThread* t)
		{
			return checkInstParam!(Members)(t, 0, "Timer");
		}

		uword allocator(MDThread* t, uword numParams)
		{
			newInstance(t, 0, 0, Members.sizeof);
			*(cast(Members*)getExtraBytes(t, -1).ptr) = Members.init;
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
}