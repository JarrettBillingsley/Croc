module samples.arrays

function test()
{
	local l1 = array.range(100000)
	local l2 = l1.dup()
	local l3 = []

	l2.reverse()

	while(#l2 > 0)
		l3 ~= l2.pop()

	while(#l3 > 0)
		l2 ~= l3.pop()

	l1.reverse()

	for(i : 0 .. #l1)
		if(l1[i] != l2[i])
			return false

	return #l1
}

function main(N)
{
	local n = 1

	if(isString(N))
		n = toInt(N)

	for(i : 0 .. n)
	{
		if(!test())
		{
			writeln("failed")
			return
		}
	}

	writeln("oki doki")
}