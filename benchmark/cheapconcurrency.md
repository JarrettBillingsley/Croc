module benchmark.cheapconcurrency;

// n = 3000, 3.566 sec (very good, and on my desktop at that!!)
// on my laptop: 1.128 sec!!

local n = 3000;

if(#vararg > 0)
	try n = toInt(vararg[0]); catch(e) {}

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

local timer = os.PerfCounter();
timer.start();

	local cofunc = coroutine link;
	cofunc(500);
	local count = 0;

	for(i : 0 .. n)
		count += cofunc();

	writefln(count);

timer.stop();
writefln("Took ", timer.seconds(), " sec");