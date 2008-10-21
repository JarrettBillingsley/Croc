module benchmark.recursive

// n = 11, 345.122 sec
// On laptop, 284.581 sec

function ack(m, n)
{
	if(m == 0)
		return n + 1

	if(n == 0)
		return ack(m - 1, 1)

	return ack(m - 1, (ack(m, n - 1)))
}

function fib(n)
{
	if(n < 2)
		return 1

	return fib(n - 2) + fib(n - 1)
}

function tak(x, y, z)
{
	if(y >= x)
		return z

	return tak(tak(x - 1, y, z), tak(y - 1, z, x), (tak(z - 1, x, y)))
}

function main(N)
{
	local n = 11
	
	if(isString(N))
	{
		writeln("F")
		n = toInt(N) //try n = toInt(N); catch(e){}
	}
	else
		writeln("G")

	local timer = time.Timer.clone()
	timer.start()

		writefln("Ack(3, {}): {}", n, ack(3, n))
		writefln("Fib({:1}): {:1}", n + 27.0, fib(n + 27.0))

		n--
		writefln("Tak({}, {}, {}): {}", 3 * n, 2 * n, n, tak(3 * n, 2 * n, n))
		writefln("Fib(3): {}", fib(3))
		writefln("Tak(3.0, 2.0, 1.0): {:1}", tak(3.0, 2.0, 1.0))

	timer.stop()
	writefln("Took {} sec", timer.seconds())
}