/******************************************************************************
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
		pushGlobal(t, "modules");
		field(t, -1, "customLoaders");
		
		newFunction(t, function uword(MDThread* t, uword numParams)
		{
			Timer.init(t);
			newFunction(t, &microTime,  "microTime");  newGlobal(t, "microTime");
			newFunction(t, &dateString, "dateString"); newGlobal(t, "dateString");
			newFunction(t, &dateTime,   "dateTime");   newGlobal(t, "dateTime");
			newFunction(t, &culture,    "culture");    newGlobal(t, "culture");
			newFunction(t, &timestamp,  "timestamp");  newGlobal(t, "timestamp");

			return 0;
		}, "time");

		fielda(t, -2, "time");
		pop(t);

		importModule(t, "time");
	}
	
	uword microTime(MDThread* t, uword numParams)
	{
		version(Windows)
		{
			ulong time;
			QueryPerformanceCounter(&time);
		
			if(time < 0x8637BD05AF6L)
				pushInt(t, cast(mdint)((time * 1_000_000) / performanceFreq));
			else
				pushInt(t, cast(mdint)((time / performanceFreq) * 1_000_000));
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
			char[24] buf = void;
			auto name = StrToCulture(t, 1, buf);
			culture = safeCode(t, Culture.getCulture(name));
		}

		char[40] buffer;
		auto ret = safeCode(t, formatDateTime(buffer, time, format, culture));

		dchar[40] outbuf;
		uint ate = 0;
		pushString(t, Utf.toString32(ret, outbuf, &ate));
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
		CultureToStr(t, Culture.current.name);

		if(numParams > 0)
		{
			char[24] buf = void;
			auto name = StrToCulture(t, 1, buf);
			Culture.current = safeCode(t, Culture.getCulture(name));
		}

		return 1;
	}

	// longest possible is 5 chars * 4 bytes per char = 20 bytes?
	char[] StrToCulture(MDThread* t, word slot, char[24] outbuf)
	{
		checkStringParam(t, slot);

		if(len(t, slot) != 5)
			throwException(t, "Culture name {} is not supported.", getString(t, slot));

		uint ate = 0;
		return Utf.toString(getString(t, slot), outbuf, &ate);
	}

	word CultureToStr(MDThread* t, char[] culture)
	{
		// eh, let's be safe..
		dchar[8] buf;
		uint ate = 0;
		return pushString(t, Utf.toString32(culture, buf, &ate));
	}
	
	char[] GetFormat(MDThread* t, word slot)
	{
		switch(checkStringParam(t, slot))
		{
			case "d": return "d";
			case "D": return "D";
			case "t": return "t";
			case "T": return "T";
			case "g": return "g";
			case "G": return "G";
			case "M": return "M";
			case "R": return "R";
			case "s": return "s";
			case "Y": return "Y";

			default:
				throwException(t, "invalid format string");
		}
		
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
			time = Gregorian.generic.toTime(getInt(t, year), getInt(t, month), getInt(t, day), getInt(t, hour), getInt(t, min), getInt(t, sec), 0, 0);
		else
			time = Gregorian.generic.toTime(getInt(t, year), getInt(t, month), getInt(t, day), 0, 0, 0, 0, 0);
			
		pop(t, 6);

		return time;
	}

	void DateTimeToTable(MDThread* t, DateTime time, word dest)
	{
// 		dest = absIndex(t, dest);
// 
// 		if(isNull(t, dest))
// 		{
// 			newTable(t);
// 			swap(t, dest);
// 			pop(t);
// 		}
// 
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

	static struct Timer
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
}