module benchmark.cheapconcurrency;

// n = 3000, 3.566 sec (very good, and on my desktop at that!!)

function link(n)
{
	if(n > 1)
	{
		local cofunc = coroutine link;
		cofunc(n - 1);
		yield();

		while(true)
			yield(cofunc() + 1);
	}
	else
	{
		while(true)
			yield(1);
	}
}

local args = [vararg];
local n = 3000;

if(#args > 0)
{
	try
		n = toInt(args[0]);
	catch(e) {}
}

local time = os.microTime();

local cofunc = coroutine link;
cofunc(500);
local count = 0;

for(local i = 1; i <= n; i++)
	count += cofunc();
	
writefln(count);

time = os.microTime() - time;
writefln("Took ", time / 1000000.0, " sec");