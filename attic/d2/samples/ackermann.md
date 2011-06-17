module ackermann

local function Ack(M, N)
	if(M == 0)
		return N + 1
	else if(N == 0)
		return Ack(M - 1, 1)
	else
		return Ack(M - 1, Ack(M, (N - 1)))

function main(N)
{
	local n = 1

	if(isString(N))
	{
		n = toInt(N)

		if(n < 1)
			n = 1
	}

	writeln("n = ", n)
	writeln("Ack(3, ", n, "): ", Ack(3, n))
}