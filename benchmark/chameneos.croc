module benchmark.chameneos

// n = 1_000_000, 15.816 sec (meh)
// laptop: 10.398

local N = 1_000_000

local first, second
local blue = 1
local red = 2
local yellow = 3
local faded = 4

local function meet(me)
{
	while(second)
		yield()

	local other = first

	if(other)
	{
		first = null
		second = me
	}
	else
	{
		local n = N - 1

		if(n < 0)
			return

		N = n
		first = me

		do
		{
			yield()
			other = second
		} while(!other)

		second = null

		yield()
	}

	return other
}

local function creature(color) =
	coroutine function()
	{
		local me = color

		for(met : 0 .. 1_000_000_001)
		{
			local other = meet(me)

			if(!other)
				return met

			if(me != other)
			{
				if(me == blue)
				{
					if(other == red)
						me = yellow
					else
						me = red
				}
				else if(me == red)
				{
					if(other == blue)
						me = yellow
					else
						me = blue
				}
				else
				{
					if(other == blue)
						me = red
					else
						me = blue
				}
			}
		}
	}

local function schedule(threads)
{
	local numThreads = #threads
	local meetings = 0

	while(true)
	{
		for(i : 0 .. numThreads)
		{
			local thr = threads[i]

			if(!thr)
				return meetings

			if(!thr.isDead())
			{
				local met = thr()

				if(met)
				{
					meetings += met
					threads[i] = null
				}
			}
		}
	}
}

function main(n)
{
	if(isString(n))
		try N = toInt(n); catch(e) {}

	local timer = time.Timer()
	timer.start()

	local threads =
	[
		creature(blue),
		creature(red),
		creature(yellow),
		creature(blue)
	]

	writeln((schedule(threads)))

	timer.stop()
	writefln("Took {} sec", timer.seconds())
}