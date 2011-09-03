module benchmark.nsieve

// n = 9, 13.79 sec
// laptop: 7.718 sec (rather nice)

function nsieve(m)
{
	local isPrime = array.new(m, true)
	local count = 0

	for(i: 2 .. m)
	{
		if(isPrime[i])
		{
			for(k : i + i .. m, i)
				isPrime[k] = false

			count++
		}
	}

	return count
}

function main(N)
{
	local n = 9

	if(isString(N))
		try n = toInt(N); catch(e) {}

	local timer = time.Timer()
	timer.start()

		for(i: 0 .. 3)
		{
			local m = 10000 << (n - i)
			writefln("Primes up to {,8} {,8}", m, nsieve(m))
		}

	timer.stop()
	writefln("Took {} sec", timer.seconds())
}