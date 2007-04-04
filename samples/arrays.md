module arrays;

function compareArr(a1, a2)
{
	foreach(i, val; a1)
		if(val != a2[i])
			return false;

	return true;
}

function test()
{
	local size = 100000;
	local l1 = array.range(size);
	local l2 = l1.dup();
	local l3 = [];

	l2.reverse();

	while(#l2 > 0)
	{
		l3 ~= l2[-1];
		l2.length(#l2 - 1);
	}

	while(#l3 > 0)
	{
		l2 ~= l3[-1];
		l3.length(#l3 - 1);
	}

	l1.reverse();

	if(compareArr(l1, l2))
		return #l1;

	return false;
}

local args = [vararg];
local n;

if(#args > 0)
	n = toInt(args[0]);
else
	n = 1;

for(local i = 0; i < n; ++i)
{
	if(!test())
	{
		writefln("failed");
		return;
	}
}

writefln("oki doki");