module benchmark.binarytrees;

// n = 16, 94.764 sec

function BottomUpTree(item, depth)
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

function ItemCheck(tree)
{
	if(#tree == 3)
		return tree[0] + ItemCheck(tree[1]) - ItemCheck(tree[2]);
	else
		return tree[0];
}
	
local args = [vararg];
local n = 16;

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
		writefln("stretch tree of depth {}\t check: {}", stretchdepth, ItemCheck(stretchtree));
	}

	local longlivedtree = BottomUpTree(0, maxdepth);

	for(depth : mindepth .. maxdepth + 1, 2)
	{
		local iterations = 1 << (maxdepth - depth + mindepth);
		local check = 0;

		for(i : 0 .. iterations)
			check += ItemCheck(BottomUpTree(1, depth)) + ItemCheck(BottomUpTree(-1, depth));

		writefln("{}\t trees of depth {}\t check: {}", iterations * 2, depth, check);
	}

	writefln("long lived tree of depth {}\t check: {}", maxdepth, ItemCheck(longlivedtree));
	
time = os.microTime() - time;
writefln("Took ", time / 1000000.0, " sec");