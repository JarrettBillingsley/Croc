
#include <string.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
	void _DateTimeToTable(CrocThread* t, oscompat::DateTime time, word dest)
	{
		croc_pushInt(t, time.year);  croc_fielda(t, dest, "year");
		croc_pushInt(t, time.month); croc_fielda(t, dest, "month");
		croc_pushInt(t, time.day);   croc_fielda(t, dest, "day");
		croc_pushInt(t, time.hour);  croc_fielda(t, dest, "hour");
		croc_pushInt(t, time.min);   croc_fielda(t, dest, "min");
		croc_pushInt(t, time.sec);   croc_fielda(t, dest, "sec");
		croc_pushInt(t, time.msec);  croc_fielda(t, dest, "msec");
	}

	void _TableToDateTime(CrocThread* t, word src, oscompat::DateTime& time)
	{
		auto year =  croc_field(t, src, "year");
		auto month = croc_field(t, src, "month");
		auto day =   croc_field(t, src, "day");
		auto hour =  croc_field(t, src, "hour");
		auto min =   croc_field(t, src, "min");
		auto sec =   croc_field(t, src, "sec");
		auto msec =  croc_field(t, src, "msec");

		if(!croc_isInt(t, year) || !croc_isInt(t, month) || !croc_isInt(t, day))
			croc_eh_throwStd(t, "ValueError",
				"year, month, and day fields in time table must exist and must be integers");

		time.year = cast(uint16_t)croc_getInt(t, year);
		time.month = cast(uint16_t)croc_getInt(t, month);
		time.day = cast(uint16_t)croc_getInt(t, day);

		if(croc_isInt(t, hour) && croc_isInt(t, min) && croc_isInt(t, sec))
		{
			time.hour = cast(uint16_t)croc_getInt(t, hour);
			time.min = cast(uint16_t)croc_getInt(t, min);
			time.sec = cast(uint16_t)croc_getInt(t, sec);
		}
		else
		{
			time.hour = time.min = time.sec = 0;
		}

		if(croc_isInt(t, msec))
			time.msec = cast(uint16_t)croc_getInt(t, msec);
		else
			time.msec = 0;

		croc_pop(t, 7);
	}

#ifdef CROC_BUILTIN_DOCS
const char* ModuleDocs =
DModule("time")
R"(This module covers two broad use cases: timing how long something takes, and getting the real (clock) time.
These two cases are treated separately as different OSes offer differing levels of resolution and accuracy
depending on how you want to deal with time.

This module doesn't go into complex things like dealing with timezones, calendars other than Gregorian, complex
international time and date formatting etc. These things would be much better dealt with through an
internationalization library.)";
#endif

DBeginList(_globalFuncs)
	Docstr(DFunc("microTime")
	R"(\returns an integer which is a microseond-accurate count of some kind. The values returned by this function can
	be used to accurately measure how long something takes, like so:

\code
local start = time.microTime()
doSomethingThatTakesAWhile()
local end = time.microTime()
writefln("Took {} milliseconds", (end - start) / 1000.0)
\endcode

	The times returned by this function are not necessarily synchronized to any external time source. That is, don't
	assume the values returned mean something like "this many seconds since the computer turned on". You should only
	use values from this function to time things like shown above.

	\see \link{Timer} for a simple class that wraps this in a simpler interface.)"),

	"microTime", 0, [](CrocThread* t) -> word_t
	{
		croc_pushInt(t, cast(crocint)oscompat::microTime());
		return 1;
	}

DListSep()
	Docstr(DFunc("timex") DParamAny("f")
	R"(Given any callable value \tt{f}, calls \tt{f} and measures how long it takes to complete.

	\returns an integer representing the elapsed time in microseconds.)"),

	"timex", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);
		croc_dup(t, 1);
		croc_pushNull(t);
		auto start = oscompat::microTime();
		croc_call(t, -2, 0);
		auto end = oscompat::microTime();
		croc_pushInt(t, cast(crocint)(end - start));
		return 1;
	}

DListSep()
	Docstr(DFunc("clockTime")
	R"(\returns an integer which is a count of the number of microseconds since the Unix epoch (1 Jan 1970).
	\b{Important:} just because this function returns microseconds does not mean it is actually accurate to the
	microsecond!

	Since this time is relative to an external reference, it's good for things like timestamps or displaying the time to
	the user. These sorts of times rarely need true microsecond accuracy anyway.

	To convert a raw clock time into separate date and time components (month, day, hours, minutes etc.) see
	\link{timeToTableLocal} and \link{timeToTableUTC}.)"),

	"clockTime", 0, [](CrocThread* t) -> word_t
	{
		croc_pushInt(t, cast(crocint)oscompat::sysTime());
		return 1;
	}

DListSep()
	Docstr(DFunc("timeToTableUTC") DParamD("time", "int", "null") DParamD("ret", "table", "null")
	R"(Converts a clock time (such as returned from \link{clockTime}) into a table which holds the the date and time
	according to the Gregorian calendar. The time components given will be in UTC time. For local time, see
	\link{timeToTableLocal}.

	\param[time] is the time to convert. If you pass nothing or null for this parameter, the current clock time will be
		used instead.
	\param[ret] is an optional result table. If you pass a table for this parameter, the time components will be
		inserted into this table. Otherwise, a new table object will be allocated and returned.

	\returns a table (or \tt{ret} if it was passed) containing the following fields:

	\dlist
		\li{\tt{"year"}}: the year.
		\li{\tt{"month"}}: the month, 1-12.
		\li{\tt{"day"}}: the day, 1-31.
		\li{\tt{"hour"}}: the hour, 0-23.
		\li{\tt{"min"}}: the minute, 0-59.
		\li{\tt{"sec"}}: the second, 0-60. Yes, 60, because of leap seconds.
		\li{\tt{"msec"}}: the milliseconds, 0-999.
	\endlist)"),

	"timeToTableUTC", 1, [](CrocThread* t) -> word_t
	{
		auto time = croc_ex_optParam(t, 1, CrocType_Int) ? cast(oscompat::Time)croc_getInt(t, 1) : oscompat::sysTime();
		auto ret = croc_ex_optParam(t, 2, CrocType_Table) ? 2 : croc_table_new(t, 0);
		_DateTimeToTable(t, oscompat::timeToDateTime(time, false), ret);
		croc_dup(t, ret);
		return 1;
	}

DListSep()
	Docstr(DFunc("timeToTableLocal") DParamD("time", "int", "null") DParamD("ret", "table", "null")
	R"(Just like \link{timeToTableUTC}, except the fields in the returned table will be calculated according to the
	local timezone instead of UTC.)"),

	"timeToTableLocal", 1, [](CrocThread* t) -> word_t
	{
		auto time = croc_ex_optParam(t, 1, CrocType_Int) ? cast(oscompat::Time)croc_getInt(t, 1) : oscompat::sysTime();
		auto ret = croc_ex_optParam(t, 2, CrocType_Table) ? 2 : croc_table_new(t, 0);
		_DateTimeToTable(t, oscompat::timeToDateTime(time, true), ret);
		croc_dup(t, ret);
		return 1;
	}

DListSep()
	Docstr(DFunc("timeFromTableUTC") DParam("tab", "table")
	R"(The inverse of \link{timeToTableUTC}, converts a table with the appropriate fields into a integer clock time
	value. The time components of the table are interpreted as being in UTC.

	\param[tab] should contain the date and time to be converted, in a similar format as returned from
		\link{timeToTableUTC}. The table must have integer fields \tt{"year"}, \tt{"month"}, and \tt{"day"}. The other
		fields are optional, but if you give one of \tt{"hour"}, \tt{"min"}, or \tt{"sec"}, you must give them all.

		These are the valid sets of fields \tt{tab} may have, and how they are interpreted:

		\blist
			\li Just \tt{"year"}, \tt{"month"}, and \tt{"day"}: interpreted as 00:00:00.000 on the given date.
			\li The above, plus \tt{"hour"}, \tt{"min"}, and \tt{"sec"}: interpreted as HH:MM:SS.000 on the given date.
			\li The above, plus \tt{"msec"}: the full, millisecond-accurate time and date.
		\endlist

	\returns an integer of the same kind returned from \link{clockTime}.

	\throws[ValueError] if \tt{tab} is invalid in any way.)"),

	"timeFromTableUTC", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_Table);
		oscompat::DateTime dt;
		_TableToDateTime(t, 1, dt);
		croc_pushInt(t, cast(crocint)oscompat::dateTimeToTime(dt, false));
		return 1;
	}

DListSep()
	Docstr(DFunc("timeFromTableLocal") DParam("tab", "table")
	R"(The inverse of \link{timeToTableLocal}. This works just like \link{timeFromTableUTC} except it interprets the
	time components of \tt{tab} as local time instead of UTC.)"),

	"timeFromTableLocal", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_Table);
		oscompat::DateTime dt;
		_TableToDateTime(t, 1, dt);
		croc_pushInt(t, cast(crocint)oscompat::dateTimeToTime(dt, true));
		return 1;
	}
DEndList()

#ifdef CROC_BUILTIN_DOCS
const char* TimerClassDocs =
DClass("Timer")
R"(A small helper class which acts like a stopwatch. You can start it, and it will count time up from that point. When
you stop it, it will add the elapsed time between the start and stop calls to its accumulated time. You can then start
and stop it again as many times as you want.

This wraps the \link{microTime} function so it gives microsecond-precise timings.

\examples

\code
local t = time.Timer()
t.start()
somethingThatTakes100Microseconds()
t.stop()
writeln(t.time()) // prints 100
t.start()
somethingThatTakes300Microseconds()
t.stop()
writeln(t.time()) // prints 400
t.reset()
writeln(t.time()) // prints 0
\endcode)";
#endif

DBeginList(_TimerMethodFuncs)
	Docstr(DFunc("start")
	R"(Starts the timer, or if it's already running, does nothing.)"),

	"start", 0, [](CrocThread* t) -> word_t
	{
		croc_field(t, 0, "_running");

		if(!croc_isTrue(t, -1))
		{
			croc_pushBool(t, true);
			croc_fielda(t, 0, "_running");
			croc_pushInt(t, cast(crocint)oscompat::microTime());
			croc_fielda(t, 0, "_start");
		}

		return 0;
	}

DListSep()
	Docstr(DFunc("stop")
	R"(Stops the timer, or if it's not running, does nothing.)"),

	"stop", 0, [](CrocThread* t) -> word_t
	{
		auto end = cast(crocint)oscompat::microTime();
		croc_field(t, 0, "_running");

		if(croc_isTrue(t, -1))
		{
			croc_pushBool(t, false);
			croc_fielda(t, 0, "_running");
			croc_field(t, 0, "_start");
			croc_field(t, 0, "_total");
			croc_pushInt(t, (end - croc_getInt(t, -2)) + croc_getInt(t, -1));
			croc_fielda(t, 0, "_total");
		}

		return 0;
	}

DListSep()
	Docstr(DFunc("reset")
	R"(Stops the timer and resets its accumulated time to 0.)"),

	"reset", 0, [](CrocThread* t) -> word_t
	{
		croc_pushBool(t, false);
		croc_fielda(t, 0, "_running");
		croc_pushInt(t, 0);
		croc_fielda(t, 0, "_total");
		return 0;
	}

DListSep()
	Docstr(DFunc("time")
	R"(\returns the total time elapsed on this timer. If this timer is running, returns the accumulated time plus any
	time since the last call to \link{start}. If this timer is stopped, just returns the total accumulated time.)"),

	"time", 0, [](CrocThread* t) -> word_t
	{
		auto now = cast(crocint)oscompat::microTime();

		croc_field(t, 0, "_running");

		if(croc_isTrue(t, -1))
		{
			croc_field(t, 0, "_start");
			croc_field(t, 0, "_total");
			croc_pushInt(t, (now - croc_getInt(t, -2)) + croc_getInt(t, -1));
		}
		else
		{
			croc_field(t, 0, "_total");
		}

		return 1;
	}
DEndList()

	word loader(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);

		croc_class_new(t, "Timer", 0);
			croc_pushBool(t, false); croc_class_addField(t, -2, "_running");
			croc_pushInt(t, 0);      croc_class_addField(t, -2, "_start");
			croc_pushInt(t, 0);      croc_class_addField(t, -2, "_total");
			registerMethods(t, _TimerMethodFuncs);
		croc_newGlobal(t, "Timer");

		return 0;
	}
	}

	void initTimeLib(CrocThread* t)
	{
		oscompat::initTime();
		croc_ex_makeModule(t, "time", &loader);
		croc_ex_importNS(t, "time");
#ifdef CROC_BUILTIN_DOCS
		CrocDoc doc;
		croc_ex_doc_init(t, &doc, __FILE__);
		croc_ex_doc_push(&doc, ModuleDocs);
			docFields(&doc, _globalFuncs);

			croc_field(t, -1, "Timer");
			croc_ex_doc_push(&doc, TimerClassDocs);
				docFields(&doc, _TimerMethodFuncs);
			croc_ex_doc_pop(&doc, -1);
			croc_popTop(t);
		croc_ex_doc_pop(&doc, -1);
		croc_ex_doc_finish(&doc);
#endif
		croc_popTop(t);
	}
}