module samples.antimatroids

// Reverse search for generating all antimatroids over k elements
// D. Eppstein, UC Irvine, 17 Jun 2006

// number of antimatroids with k labeled elements, k = 0, 1, 2, ...:
// 1, 1, 3, 22, 485, 59386

// Ported from Python to MiniD 2 (original code can be found at http://11011110.livejournal.com/58994.html)
// MiniD beats the pants off of Python on an Athlon 64 X2 4600+; 11 sec compared to almost 19 sec

local nelements = 5
local nsets = 1 << nelements
local top = 1 << (nsets - 1)
local singletons = [1 << (1 << i) for i in 0 .. nelements].reduce(\x, y -> x + y)
local all = (1 << nsets) - 1

local function bitsIter(idx)
{
	if(idx == 0)
		return

	local b = idx & ~(idx - 1)
	return idx & ~b, b
}

local function bits(x)
	return bitsIter, null, x

local function isPower(x)
{
	local nbits = 0

	foreach(b; bits(x))
	{
		nbits++

		if(nbits > 1)
			return false
	}

	return nbits
}

local logs = {[1 << i] = i for i in 0 .. nsets}
local preds = {}
local succs = {}
local supersets = {}
local subsets = {}

for(i: 0 .. nsets)
{
	local p = 0

	foreach(b; bits(i))
		p |= 1 << (i ^ b)

	preds[1 << i] = p
	local s = 0

	foreach(b; bits((nsets - 1) ^ i))
		s |= 1 << (i ^ b)

	succs[1 << i] = s
	s = 0

	for(j: 0 .. nsets)
		if((i & j) == i)
			s |= 1 << j

	supersets[i] = s
	s = 0

	for(j: 0 .. nsets)
		if((i & j) == j)
			s |= 1 << j

	subsets[i] = s
}

local excludes = {}

for(i: 0 .. nelements)
{
	local x = 0

	for(j: 0 .. nsets)
		if(((1 << i) & j) == 0)
			x |= (1 << j)

	excludes[1 << i] = x
}

/// Does b have a single predecessor in S?
local function singlePred(S, b) = isPower(preds[b] & S)

local function powersetbetween(lb, ub, S)
{
	local between = supersets[lb] & subsets[ub]
	return between == (between & S)
}

/// Add one set to S to form a larger antimatroid.
local function parent(S)
{
	if(S == all)
		return null

	local ub = nsets - 1
	local pos = ub
	local lb = 0
	local b = 0

	while(true)
	{
		// Invariant: not powersetbetween(lb,ub), lb subset pos subset ub
		// and either powersetbetween(pos,ub) or powersetbetween(pos|b,ub)

		// First test whether there is a powerset above pos.
		// if so, we can step downwards one step safely.
		if(powersetbetween(pos, ub, S))
		{
			foreach(b2; bits(pos & ~lb))
			{
				b = b2

				if(S & (1 << (pos & ~b2)))
					break
			}

			pos &= ~b
			continue
		}

		// Here with powersetbetween(pos|b,ub) but not powersetbetween(pos,ub).
		// If the top subset not containing b, ub&~b, is in S,
		// then we can restrict to a smaller subfamily.
		if((S & (1 << (ub & ~b))) != 0)
		{
			lb = pos
			pos = ub & ~b
			ub = pos
			continue
		}

		// Here with ub &~ b not part of S.
		// So if u is the union of the non-b supersets of pos,
		// it is missing some element q, and we can safely add u|q.
		local temp = 0

		foreach(b2; bits(S & supersets[pos] & subsets[ub] & excludes[b]))
			temp = b2

		local u = logs[temp]

		foreach(b2; bits(ub & ~u & ~b))
			return S | (1 << (u | b2))
	}
}

/// Do successors of b have another predecessor in S &~ b?
local function succsOk(S, b)
{
	foreach(q; bits(succs[b] & S))
		if(singlePred(S, q))
			return false

	return true
}

local stack = [all]
local nantimatroids = 0

local timer = time.Timer()
timer.start()

while(#stack)
{
	local x = stack.pop()
	nantimatroids++

	foreach(b; bits(x))
	    if(b != top && singlePred(x, b) && succsOk(x, b) && parent(x & ~b) == x)
	        stack ~= (x & ~b);
}

timer.stop()

writeln(nantimatroids)
writefln("Took {:f3} seconds", timer.seconds())