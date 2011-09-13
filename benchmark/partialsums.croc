module benchmark.partialsums

// n = 2,500,000, 21.74 sec
// on laptop, 13.996 sec

function main(N)
{
	local n = 2_500_000

	if(isString(N))
		try n = toInt(N); catch(e) {}

	local timer = time.Timer()
	timer.start()

		local a1 = 1.0
		local a2 = 0.0
		local a3 = 0.0
		local a4 = 0.0
		local a5 = 0.0
		local a6 = 0.0
		local a7 = 0.0
		local a8 = 0.0
		local a9 = 0.0
		local alt = 1.0
		local sqrt = math.sqrt
		local sin = math.sin
		local cos = math.cos
		local pow = math.pow

		for(local k = 1.0; k <= n; k += 1.0)
		{
			local k2 = k * k
			local sk = sin(k)
			local ck = cos(k)
			local k3 = k2 * k

			a1 += pow(2.0 / 3.0, k)
			a2 += 1.0 / sqrt(k)
			a3 += 1.0 / (k2 + k)

			// Flint Hills
			a4 += 1.0 / (k3 * sk * sk)

			// Cookson Hills
			a5 += 1.0 / (k3 * ck * ck)

			// Harmonic
			a6 += 1.0 / k

			// Riemann zeta
			a7 += 1.0 / k2

			// Alternating harmonic
			a8 += alt / k

			// Gregory
			a9 += alt / (k + k - 1)

			alt = -alt
		}

		writefln("{:9}\t(2/3)^k", a1)
		writefln("{:9}\tk^-0.5", a2)
		writefln("{:9}\t1/k(k+1)", a3)
		writefln("{:9}\tFlint Hills", a4)
		writefln("{:9}\tCookson Hills", a5)
		writefln("{:9}\tHarmonic", a6)
		writefln("{:9}\tRiemann Zeta", a7)
		writefln("{:9}\tAlternating Harmonic", a8)
		writefln("{:9}\tGregory", a9)

	timer.stop()
	writefln("Took {} secs", timer.seconds())
}