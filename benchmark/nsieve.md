module benchmark.nsieve;

// n = 9, 14.772 sec

local function nsieve(m)
{
	local isPrime = array.new(m, true);
	local count = 0;

	for(local i = 2; i < m; ++i)
	{
		if(isPrime[i])
		{
			for(local k = i + i; k < m; k += i)
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

	for(local i = 0; i < 3; ++i)
	{
		local m = 10000 << (n - i);
		writefln("Primes up to %8d %8d", m, nsieve(m));
	}
	
time = os.microTime() - time;
writefln("Took ", time / 1000000.0, " sec");