module cheapconcurrency

// n = 3000, 3.566 sec (very good, and on my desktop at that!!)
// on my laptop: 1.128 sec!!

local function link(n)
{
	if(n > 1)
	{
		local cofunc = coroutine link
		cofunc(n - 1)
		yield()

		while(true)
			yield(cofunc() + 1)
	}
	else
	{
		while(true)
			yield(1)
	}
}

function main(N)
{
	local n = 3000

	if(isString(N))
		try n = toInt(N); catch(e) {}

	local timer = time.Timer()
	timer.start()

	local cofunc = coroutine link
	cofunc(500)
	local count = 0

	for(i : 0 .. n)
		count += cofunc()

	writeln(count)

	timer.stop()
	writefln("Took {} sec", timer.seconds())
}