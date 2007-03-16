module ackermann;

local function Ack(M, N)
{
	if(M == 0)
		return N + 1;

	if(N == 0)
		return Ack(M - 1, 1);

	return Ack(M - 1, Ack(M, (N - 1)));
}

local args = [vararg];
local n = 1;

if(#args > 0)
{
	n = toInt(args[0]);

	if(n < 1)
		n = 1;
}

writefln("n = ", n);
writefln("Ack(3, ", n, "): ", Ack(3, n));
