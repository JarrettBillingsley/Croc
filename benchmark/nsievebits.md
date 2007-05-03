module benchmark.nsievebits;

// n = 11, 155 sec
// laptop, 107.87 sec

function primes(n)
{
	local count = 0;
	local size = 10000 << n;

	local flags = array.new(size / 32 + 1, -1);

	for(prime : 2 .. size + 1)
	{
		local offset = prime / 32;
		local mask = 1 << (prime % 32);

		if((flags[offset] & mask) != 0)
		{
			++count;

			for(i : prime + prime .. size + 1, prime)
			{
				offset = i / 32;
				mask = 1 << (i % 32);
				
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