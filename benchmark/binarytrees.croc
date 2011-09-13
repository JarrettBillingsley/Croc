module benchmark.binarytrees

// n = 16, 94.764 sec

local function BottomUpTree(item, depth)
	if(depth == 0)
		return [item]
	else
	{
		local i = item + item
		depth--
		return [item, BottomUpTree(i - 1, depth), (BottomUpTree(i, depth))]
	}

local function ItemCheck(tree)
	if(#tree == 3)
		return tree[0] + ItemCheck(tree[1]) - ItemCheck(tree[2])
	else
		return tree[0]

function main(N)
{
	local n = 16

	if(isString(N))
		try n = toInt(N); catch(e) {}

	local timer = time.Timer()
	timer.start()

	local mindepth = 4
	local maxdepth = math.max(mindepth + 2, n)

	local stretchdepth = maxdepth + 1
	writefln("stretch tree of depth {}\t check: {}", stretchdepth, ItemCheck(BottomUpTree(0, stretchdepth)))

	local longlivedtree = BottomUpTree(0, maxdepth)
	local iterations = 1 << maxdepth

	for(depth: mindepth .. stretchdepth, 2)
	{
		local check = 0

		for(i: 0 .. iterations)
			check += ItemCheck(BottomUpTree(1, depth)) + ItemCheck(BottomUpTree(-1, depth))

		writefln("{}\t trees of depth {}\t check: {}", iterations * 2, depth, check)
		iterations >>= 2
	}

	writefln("long lived tree of depth {}\t check: {}", maxdepth, ItemCheck(longlivedtree))

	timer.stop()
	writefln("Took {} sec", timer.seconds())
}