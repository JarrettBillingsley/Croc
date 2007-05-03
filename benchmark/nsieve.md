module benchmark.nsieve;

// n = 9, 13.79 sec
// laptop: 7.718 sec (rather nice)

function nsieve(m)
{
	local isPrime = array.new(m, true);
	local count = 0;

	for(i : 2 .. m)
	{
		if(isPrime[i])
		{
			for(k : i + i .. m, i)
				isPrime[k] = false;

			++count;
		}
	}

	return count;
}

local args = [vararg];
local n = 9;

if(#args > 0)
{
	try
		n = toInt(args[0]);
	catch(e) {}
}

local time = os.microTime();

	for(i : 0 .. 3)
	{
		local m = 10000 << (n - i);
		writefln("Primes up to %8d %8d", m, nsieve(m));
	}
	
time = os.microTime() - time;
writefln("Took ", time / 1000000.0, " sec");