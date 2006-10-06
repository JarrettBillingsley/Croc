// returns the number of days in a given month and year
function daysInMonth(month, year)
{
	local daysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
	local d = daysInMonth[month];
   
	// check for leap year
	if(month == 2)
	{
		if((year % 4) == 0)
		{
			if((year % 100) == 0)
			{
				if((year % 400) == 0)
					d = 29;
			}
			else
				d = 29;
		}
	}

	return d;
}

// returns the day of week integer and the name of the week
function dayOfWeek(dd, mm, yy)
{
	local days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

	local mmx = mm;

	if(mm == 1)
	{
		mmx = 13;
		--yy;
	}

	if(mm == 2)
	{
		mmx = 14;
		--yy;
	}

	local val8 = dd + (mmx * 2) + (((mmx + 1) * 3) / 5) + yy + (yy / 4) - (yy / 100) + (yy / 400) + 2;
	local val9 = val8 / 7;
	local dw = val8 - (val9 * 7);

	return dw, days[dw];
}

// given a string date of '2006-12-31' breaks it down to integer yy, mm and dd
function getDateParts(dateStr)
{
	local parts = [0, 0, 0];

	if(dateStr !is null)
	{
		local begin = 0;
		local idx = 0;
		
		for(local i = 0; i < #dateStr; ++i)
		{
			if(dateStr[i] == '-')
			{
				parts[idx] = dateStr:slice(begin, i):toInt();
				++idx;
				begin = i + 1;
			}
		}
	}

	return parts[0], parts[1], parts[2];
}

function arrayIterator(array, index)
{
	++index;

	if(index >= #array)
		return null;

	return index, array[index];
}

function pairs(container)
{
	if(typeof(container) == "array")
		return arrayIterator, container, -1;
}

function showCalendar(cdate)
{
	local out = "";

	local yy, mm, dd = getDateParts(cdate);
	local month_days = daysInMonth(mm, yy);
	local day_week = dayOfWeek(1, mm, yy);

    // day in which the calendar day start.. 1=Sunday, 2="Monday"
	local day_start = 1;

	local days_of_week = [["Sun", 0], ["Mon", 1], ["Tue", 2], ["Wed", 3], ["Thu", 4], ["Fri", 5], ["Sat", 6]];
	local days_of_week_ordered = [];
	
	for(local k = 0; k < 7; ++k)
	{
		p = k + day_start;

		if(p >= 7)
			p -= 7;

		local v = { };
		v.dayname = days_of_week[p][0];
		v.daynum = days_of_week[p][1];
		days_of_week_ordered ~= v;
	}

	out = "<h3>" ~ cdate ~ "</h3>";
	out ~= "<table border='1' width='80%' cellspacing='2' cellpadding='5'>";

	out ~= "<tr>";
	
	foreach(local k, local v; pairs(days_of_week_ordered))
	{
		out ~= "<td>" ~ v.dayname ~ "</td>";

		if(day_week == v.daynum)
			d = - k + 2;
	}

	out ~= "</tr>";

	while(d < month_days)
	{
		out ~= "<tr>";

		foreach(local k, local v; pairs(days_of_week))
		{
			if(d >= 1 && d <= month_days)
			{
				if(d == dd)
					out ~= "<td bgcolor='#FFFF99'>" ~ d ~ "</td>";
				else
					out ~= "<td>" ~ toString(d) ~ "</td>";
			}
			else
				out ~= "<td> </td>";

			++d;
		}

		out ~=  "</tr>";
	}

	out ~= "</table>";

	writefln(out);
}

showCalendar("2006-4-5");

/*writefln();

local function outer()
{
	local x = 3;

	local function inner()
	{
		++x;
		writefln("inner x: ", x);
	}

	writefln("outer x: ", x);
	inner();
	writefln("outer x: ", x);

	return inner;
}

local func = outer();
func();

writefln();

local function thrower(x)
{
	if(x >= 3)
		throw "Sorry, x is too big for me!";
}

local function tryCatch(iterations)
{
	try
	{
		for(local i = 0; i < iterations; ++i)
		{
			writefln("tryCatch: ", i);
			thrower(i);
		}
	}
	catch(e)
	{
		writefln("tryCatch caught: ", e);
		throw e;
	}
	finally
	{
		writefln("tryCatch finally");
	}
}

try
{
	tryCatch(2);
	tryCatch(5);
}
catch(e)
{
	writefln("caught: ", e);
}

writefln();

function arrayIterator(array, index)
{
	++index;

	if(index >= #array)
		return null;

	return index, array[index];
}

function pairs(container)
{
	return arrayIterator, container, -1;
}

local arr = [3, 5, 7];

arr:sort();

foreach(local i, local v; pairs(arr))
	writefln("arr[", i, "] = ", v);

arr ~= ["foo", "far"];

writefln();

foreach(local i, local v; pairs(arr))
	writefln("arr[", i, "] = ", v);

writefln();

local function vargs(vararg)
{
	local args = [vararg];

	writefln("num varargs: ", #args);

	for(local i = 0; i < #args; ++i)
		writefln("args[", i, "] = ", args[i]);
}

vargs();

writefln();

vargs(2, 3, 5, "foo", "bar");

writefln();

for(local switchVar = 0; switchVar < 11; ++switchVar)
{
	switch(switchVar)
	{
		case 1, 2, 3:
			writefln("small");
			break;

		case 4, 5, 6:
			writefln("medium");
			break;
			
		case 7, 8, 9:
			writefln("large");
			break;
			
		default:
			writefln("out of range");
			break;
	}
}

writefln();

local stringArray = ["hi", "bye", "foo"];

foreach(local i, local v; pairs(stringArray))
{
	switch(v)
	{
		case "hi":
			writefln("switched to hi");
			break;
			
		case "bye":
			writefln("switched to bye");
			break;
			
		default:
			writefln("switched to something else");
			break;
	}
}*/