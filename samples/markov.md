module samples.markov

// Markov Chain Program in MiniD 2

// The length of a gram.  This shouldn't be less than 2.
local N = 4

// How many words of output to generate.
local MAXGEN = 10000

local NOWORD = "\n"

local wordRE = regexp.compile(@"(\w+)")

function allwords(f) =
	coroutine function()
	{
		yield()

		foreach(line; f)
			foreach(m; wordRE.search(line))
				yield(m.match())
	}

function prefix(words) = string.join(words, " ")

local statetab = {}

function insert(index, value)
	if(local a = statetab[index])
		a ~= value
	else
		statetab[index] = [value]

function main()
{
	// build table
	local words = array.new(N, NOWORD)
	
	foreach(word; allwords(io.stdin))
	{
		insert(prefix(words), word)
		
		for(i: 0 .. #words - 1)
			words[i] = words[i + 1]
	
		words[-1] = word
	}
	
	insert(prefix(words), NOWORD)
	
	// generate text
	words.fill(NOWORD)
	
	for(i: 0 .. MAXGEN)
	{
		local list = statetab[prefix(words)]
	
		// choose a random item from list
		local nextword = list[math.rand(#list)]
	
		if(nextword == NOWORD)
			return
	
		write(nextword, " ")
	
		for(j: 0 .. #words - 1)
			words[j] = words[j + 1]
	
		words[-1] = nextword
	
		if(i > 0 && i % 10 == 0)
			writeln()
	}
}