module benchmark.nsievebits

// n = 11, 155 sec
// laptop, 107.87 sec

function primes(n)
{
	local count = 0
	local size = 10000 << n

	local flags = array.new(size / 64 + 1, -1)

	for(prime: 2 .. size + 1)
	{
		local offset = prime / 64
		local mask = 1 << (prime % 64)

		if(flags[offset] & mask)
		{
			count++

			for(i: prime + prime .. size + 1, prime)
			{
				offset = i / 64
				mask = 1 << (i % 64)

				if(flags[offset] & mask)
					flags[offset] ^= mask
			}
		}
	}

	writefln("Primes up to {,8} {,8}", size, count)
}

function main(N)
{
	local n = 11

	if(isString(N))
		try n = toInt(N); catch(e) {}

	local timer = time.Timer()
	timer.start()

	    for(i: 0 .. 3)
	        primes(n - i)

	timer.stop()
	writefln("Took {} sec", timer.seconds())
}