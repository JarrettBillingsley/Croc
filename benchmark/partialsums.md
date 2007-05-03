module benchmark.partialsums;

// n = 2,500,000, 21.74 sec
// on laptop, 13.996 sec

local args = [vararg];
local n = 2_500_000;

if(#args > 0)
{
	try
		n = toInt(args[0]);
	catch(e) {}
}

local time = os.microTime();

	local a1 = 1.0;
	local a2 = 0.0;
	local a3 = 0.0;
	local a4 = 0.0;
	local a5 = 0.0;
	local a6 = 0.0;
	local a7 = 0.0;
	local a8 = 0.0;
	local a9 = 0.0;
	local alt = 1.0;
	local sqrt = math.sqrt;
	local sin = math.sin;
	local cos = math.cos;
	local pow = math.pow;
	
	for(local k = 1.0; k <= n; k += 1.0)
	{
		local k2 = k * k;
		local sk = sin(k);
		local ck = cos(k);
		local k3 = k2 * k;

		a1 += pow(2.0 / 3.0, k);
		a2 += 1.0 / sqrt(k);
		a3 += 1.0 / (k2 + k);

		// Flint Hills
		a4 += 1.0 / (k3 * sk * sk);

		// Cookson Hills
		a5 += 1.0 / (k3 * ck * ck);
		
		// Harmonic
		a6 += 1.0 / k;
		
		// Riemann zeta
		a7 += 1.0 / k2;

		// Alternating harmonic
		a8 += alt / k;

		// Gregory
		a9 += alt / (k + k - 1);

		alt = -alt;
	}
	
	writefln("%.9f\t(2/3)^k", a1);
	writefln("%.9f\tk^-0.5", a2);
	writefln("%.9f\t1/k(k+1)", a3);
	writefln("%.9f\tFlint Hills", a4);
	writefln("%.9f\tCookson Hills", a5);
	writefln("%.9f\tHarmonic", a6);
	writefln("%.9f\tRiemann Zeta", a7);
	writefln("%.9f\tAlternating Harmonic", a8);
	writefln("%.9f\tGregory", a9);
	
time = os.microTime() - time;
writefln("Took ", time / 1000000.0, " sec");