module benchmark.binarytrees;

// n = 16, 94.764 sec

local function BottomUpTree(item, depth)
{
	if(depth > 0)
	{
		local i = item + item;
		--depth;

		local left = BottomUpTree(i - 1, depth);
		local right = BottomUpTree(i, depth);

		return [item, left, right];
	}
	else
		return [item];
}

local function ItemCheck(tree)
{
	if(#tree == 3)
		return tree[0] + ItemCheck(tree[1]) - ItemCheck(tree[2]);
	else
		return tree[0];
}
	
local args = [vararg];
local n = 12;

if(#args > 0)
{
	try
		n = toInt(args[0]);
	catch(e) {}
}

local time = os.microTime();

	local mindepth = 4;
	local maxdepth = mindepth + 2;
	
	if(maxdepth < n)
		maxdepth = n;

	{
		local stretchdepth = maxdepth + 1;
		local stretchtree = BottomUpTree(0, stretchdepth);
		writefln("stretch tree of depth %d\t check: %d", stretchdepth, ItemCheck(stretchtree));
	}
	
	local longlivedtree = BottomUpTree(0, maxdepth);

	for(local depth = mindepth; depth <= maxdepth; depth += 2)
	{
		local iterations = 1 << (maxdepth - depth + mindepth);
		local check = 0;
	
		for(local i = 1; i <= iterations; ++i)
			check += ItemCheck(BottomUpTree(1, depth)) + ItemCheck(BottomUpTree(-1, depth));
	
		writefln("%d\t trees of depth %d\t check: %d", iterations * 2, depth, check);
	}
	
	writefln("long lived tree of depth %d\t check: %d", maxdepth, ItemCheck(longlivedtree));
	
time = os.microTime() - time;
writefln("Took ", time / 1000000.0, " sec");