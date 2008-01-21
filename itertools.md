module itertools

function chain(vararg)
{
	local args = [vararg]

	return coroutine function()
	{
		yield()

		for(i: 0 .. #args)
			foreach(v; args[i])
				yield(v)
	}
}

function count(n = 0)
{
	return coroutine function()
	{
		yield()
		
		while(true)
		{
			yield(n)
			n++
		}
	}
}

function izip(vararg)
{
	if(#vararg == 0)
		return function() = null
		
	local args = [vararg]
	local n = #args
	local lengths = args.map(function(x) = #x)
	local temp = array.new(n)

	local function iterator(index)
	{
		index++

		for(i: 0 .. n)
		{
			if(index >= lengths[i])
				return;

			temp[i] = args[i][index]
		}
		
		return index, temp.expand()
	}
	
	return iterator, null, -1
}

function generator(x, extra = null)
{
	return coroutine function()
	{
		yield()

		local iterFunc, state, idx = x.opApply(extra)

		local function loop(idx0, vararg)
		{
			if(idx0 is null)
				return;
				
			yield(idx0, vararg)
			
			return loop(iterFunc(with state, idx0))
		}

		loop(iterFunc(with state, idx))
	}
}

function repeat(x, times)
{
	if(times is null)
		return function(index) { return index + 1, x }, null, -1
	else
	{
		local function iterator(index)
		{
			index++

			if(index >= times)
				return;

			return index, x
		}

		return iterator, null, -1
	}
}

function iter(callable, sentinel)
{
	local function iterator(index)
	{
		index++
		
		local ret = callable()

		if(ret is sentinel)
			return;

		return index, ret
	}

	return iterator, null, -1
}

function imap(func, vararg)
{
	local iterables = [vararg].apply(generator).each(function(i, v) v())
	local args = array.new(#iterables)

	local function iterator(index)
	{
		local dummy

		for(i: 0 .. #args)
		{
			dummy, args[i] = iterables[i]()

			if(iterables[i].isDead())
				return;
		}

		return index + 1, func(args.expand())
	}

	return iterator, null, -1
}