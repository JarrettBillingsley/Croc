module lmarkov

// Markov Chain Program in MiniD 2

// The length of a gram.  This shouldn't be less than 2.
local N = 3

// How many words of output to generate.
local MAXGEN = 10000

local NOWORD = '\n'

local wordRE = regexp.compile(@"(\w+)")

function allwords(f) =
	coroutine function()
	{
		yield()

		foreach(line; f)
			foreach(m; wordRE.search(line))
				yield(m.match())
	}

function prefix(words) = words.reduce(function(x, y) = x ~ y)

function analyze(input, N)
{
	local statetab = {}
	
	function insert(index, value)
		if(local a = statetab[index])
			a ~= value
		else
			statetab[index] = [value]
	
	// build table
	local words = array.new(N)
	
	foreach(word; allwords(input))
	{
		words.fill(NOWORD)
	
		foreach(c; word)
		{
			insert(prefix(words), c.toLower())
	
			for(i: 0 .. #words - 1)
				words[i] = words[i + 1]
	
			words[-1] = c.toLower()
		}
	
		insert(prefix(words), NOWORD)
	}
	
	return statetab
}

function generate(statetab, N)
{
	local words = array.new(N)

	// generate text
	for(i: 0 .. MAXGEN)
	{
		words.fill(NOWORD)
	
		for(c: 0 .. 20)
		{
			local list = statetab[prefix(words)]
	
			// choose a random item from list
			local nextword = list[math.rand(#list)]
		
			if(nextword == NOWORD)
				break
		
			write(nextword)
		
			for(j: 0 .. #words - 1)
				words[j] = words[j + 1]
		
			words[-1] = nextword
		}
		
		write(' ')
	
		if(i > 0 && i % 10 == 0)
			writeln()
	}
}