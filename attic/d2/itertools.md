module itertools

function chain(vararg)
{
	local args = [vararg]

	return coroutine function()
	{
		foreach(arg; args)
			foreach(v; arg)
				yield(v)
	}
}

function count(n = 0) =
	coroutine function()
	{
		while(true)
		{
			yield(n)
			n++
		}
	}

function izip(vararg)
{
	if(#vararg == 0)
		return \-> null

	local args = [vararg]
	local n = #args
	local lengths = args.map(\x -> #x)
	local temp = array.new(n)

	local function iterator(index)
	{
		index++

		for(i: 0 .. n)
		{
			if(index >= lengths[i])
				return

			temp[i] = args[i][index]
		}

		return index, temp.expand()
	}

	return iterator, null, -1
}

function generator(x, extra = null) =
	coroutine function()
	{
		local iterFunc = x
		local state, idx

		if(!isFunction(iterFunc) && !isThread(iterFunc))
		{
			iterFunc, state, idx = x.opApply(extra)

			if(!isFunction(iterFunc) && !isThread(iterFunc))
				throw "aghl"
		}

		local rets = [idx]

		if(isFunction(iterFunc))
		{
			rets.set(iterFunc(with state, rets[0]))

			while(#rets && rets[0] !is null)
			{
				yield(rets.expand())
				rets.set(iterFunc(with state, rets[0]))
			}
		}
		else
		{
			if(!iterFunc.isInitial())
				throw "not initial omfg"

			rets.set(iterFunc(with state, rets[0]))

			while(!iterFunc.isDead())
			{
				yield(rets.expand())
				rets.set(iterFunc(with state, rets[0]))
			}
		}
	}

function repeat(x, times)
	if(times is null)
		return function(index) { return index + 1, x }, null, -1
	else
	{
		local function iterator(index)
		{
			index++

			if(index >= times)
				return

			return index, x
		}

		return iterator, null, -1
	}

function iter(callable, sentinel)
{
	local function iterator(index)
	{
		index++

		local ret = this()

		if(ret is sentinel)
			return

		return index, ret
	}

	return iterator, callable, -1
}

function imap(func, vararg)
{
	local iterables = [vararg].apply(generator)
	local args = array.new(#iterables)

	local function iterator(index)
	{
		local dummy

		for(i: 0 .. #args)
		{
			dummy, args[i] = iterables[i]()

			if(iterables[i].isDead())
				return
		}

		return index + 1, func(args.expand())
	}

	return iterator, null, -1
}