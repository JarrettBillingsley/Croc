module benchmark.nsievebits;

// n = 11, 155 sec

local BPC = 32;

function primes(n)
{
	local count = 0;
	local size = 10000 << n;

	local flags = array.new(size / BPC + 1, -1);

	for(prime : 2 .. size + 1)
	{
		local offset = prime / BPC;
		local mask = 1 << (prime % BPC);

		if((flags[offset] & mask) != 0)
		{
			++count;

			for(i : prime + prime .. size + 1, prime)
			{
				offset = i / BPC;
				mask = 1 << (i % BPC);
				
				if((flags[offset] & mask) != 0)
					flags[offset] = flags[offset] ^ mask;
			}
		}
	}

	writefln("Primes up to %8d %8d", size, count);
}

local args = [vararg];
local n = 11;

if(#args > 0)
{
	try
		n = toInt(args[0]);
	catch(e) {}
}

local time = os.microTime();

    for(i : 0 .. 3)
        primes(n - i);

time = os.microTime() - time;
writefln("Took ", time / 1000000.0, " sec");