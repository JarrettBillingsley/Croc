module ackermann

local function Ack(M, N)
	if(M == 0)
		return N + 1
	else if(N == 0)
		return Ack(M - 1, 1)
	else
		return Ack(M - 1, Ack(M, (N - 1)))

local n = 1

if(#vararg > 0)
{
	n = toInt(vararg[0])

	if(n < 1)
		n = 1
}

writefln("n = ", n)
writefln("Ack(3, ", n, "): ", Ack(3, n))
