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

module croc.stdlib_time;

import tango.time.chrono.Gregorian;
import tango.time.Clock;
import tango.time.StopWatch;
import tango.time.Time;
import tango.time.WallClock;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_library;
import croc.types;
import croc.utils;

version(Windows)
{
private:
	extern(Windows) int QueryPerformanceFrequency(ulong* frequency);
	extern(Windows) int QueryPerformanceCounter(ulong* count);
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

	crocint _getTime()
	{
		version(Windows)
		{
			ulong time;
			QueryPerformanceCounter(&time);
			return cast(crocint)((time * 1_000_000) / performanceFreq);
		}
		else
		{
			timeval tv;
			gettimeofday(&tv, null);
			return cast(crocint)(tv.tv_sec * 1_000_000L + tv.tv_usec);
		}
	}

	void init(CrocThread* t)
	{
		makeModule(t, "time", function uword(CrocThread* t)
		{
			Timer.init(t);
			newFunction(t, 0, &microTime,  "microTime");  newGlobal(t, "microTime");
			newFunction(t, 2, &dateTime,   "dateTime");   newGlobal(t, "dateTime");
			newFunction(t, 0, &timestamp,  "timestamp");  newGlobal(t, "timestamp");
			newFunction(t,    &timex,      "timex");      newGlobal(t, "timex");
			newFunction(t, 2, &compare,    "compare");    newGlobal(t, "compare");

			return 0;
		});

		importModuleNoNS(t, "time");
	}

	uword microTime(CrocThread* t)
	{
		pushInt(t, _getTime());
		return 1;
	}

	uword dateTime(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		bool useGMT = false;
		word tab;

		if(numParams == 0)
			tab = newTable(t);
		else if(isBool(t, 1))
		{
			useGMT = getBool(t, 1);

			if(numParams > 1)
			{
				checkParam(t, 2, CrocValue.Type.Table);
				tab = 2;
			}
			else
				tab = newTable(t);
		}
		else
		{
			checkParam(t, 1, CrocValue.Type.Table);
			tab = 1;
		}

		DateTimeToTable(t, useGMT ? Clock.toDate : WallClock.toDate, tab);
		dup(t, tab);
		return 1;
	}

	uword compare(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Table);
		checkParam(t, 2, CrocValue.Type.Table);
		auto t1 = TableToTime(t, 1);
		auto t2 = TableToTime(t, 2);
		pushInt(t, cast(crocint)t1.opCmp(t2));
		return 1;
	}

	Time TableToTime(CrocThread* t, word tab)
	{
		auto year = field(t, tab, "year");
		auto month = field(t, tab, "month");
		auto day = field(t, tab, "day");
		auto hour = field(t, tab, "hour");
		auto min = field(t, tab, "min");
		auto sec = field(t, tab, "sec");

		if(!isInt(t, year) || !isInt(t, month) || !isInt(t, day))
			throwStdException(t, "ValueException", "year, month, and day fields in time table must exist and must be integers");

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

	void DateTimeToTable(CrocThread* t, DateTime time, word dest)
	{
		pushInt(t, time.date.year);    fielda(t, dest, "year");
		pushInt(t, time.date.month);   fielda(t, dest, "month");
		pushInt(t, time.date.day);     fielda(t, dest, "day");
		pushInt(t, time.time.hours);   fielda(t, dest, "hour");
		pushInt(t, time.time.minutes); fielda(t, dest, "min");
		pushInt(t, time.time.seconds); fielda(t, dest, "sec");
	}

	uword timestamp(CrocThread* t)
	{
		pushInt(t, cast(crocint)(Clock.now - Time.epoch1970).seconds);
		return 1;
	}

	uword timex(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Function);
		pushNull(t);
		insert(t, 2);

		StopWatch w;
		w.start();
		rawCall(t, 1, 0);
		pushFloat(t, w.stop());

		return 1;
	}

	static struct Timer
	{
	static:
		const Start = "Timer_start";
		const Time = "Timer_time";

		void init(CrocThread* t)
		{
			CreateClass(t, "Timer", (CreateClass* c)
			{
				pushInt(t, 0); c.field("_start");
				pushInt(t, 0); c.field("_time");
				c.method("start",       0, &start);
				c.method("stop",        0, &stop);
				c.method("seconds",     0, &seconds);
				c.method("millisecs",   0, &millisecs);
				c.method("microsecs",   0, &microsecs);
			});

			newGlobal(t, "Timer");
		}

		uword start(CrocThread* t)
		{
			pushInt(t, _getTime());
			fielda(t, 0, Start);
			return 0;
		}

		uword stop(CrocThread* t)
		{
			auto end = _getTime();
			field(t, 0, Start);
			pushInt(t, end - getInt(t, -1));
			fielda(t, 0, Time);
			return 0;
		}

		uword seconds(CrocThread* t)
		{
			field(t, 0, Time);
			pushFloat(t, getInt(t, -1) / 1_000_000.0);
			return 1;
		}

		uword millisecs(CrocThread* t)
		{
			field(t, 0, Time);
			pushFloat(t, getInt(t, -1) / 1_000.0);
			return 1;
		}

		uword microsecs(CrocThread* t)
		{
			field(t, 0, Time);
			return 1;
		}
	}
}