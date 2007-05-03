module fasta;

// laptop: n = 25,000,000, 860 sec

local IM = 139968;
local IA = 3877;
local IC = 29573;
local Last = 42.0;

local write = write;
local writeln = writeln;

function random(max)
{
	local y = (Last * IA + IC) % IM;
	Last = y;
	return (max * y) / IM;
}

function makeCumulative(arr)
{
	local sum = 0.0;
	
	for(i : 0 .. #arr)
	{
		sum += arr[i][1];
		arr[i][1] = sum;
	}
	
	return arr;
}

function selectRandom(arr)
{
	local r = random(1.0);

	if(r < arr[0][1])
		return arr[0][0];
		
	local lo = 0;
	local hi = #arr - 1;
	
	while(hi > lo + 1)
	{
		local i = (hi + lo) / 2;
		
		if(r < arr[i][1])
			hi = i;
		else
			lo = i;
	}
	
	return arr[hi][0];
}

function makeRepeatFasta(id, desc, s, n)
{
	writeln(">", id, " ", desc);

	local p = 0;
	local sn = #s;
	local s2 = s ~ s;

	for(i : 60 .. n + 1, 60)
	{
		writeln(s2[p .. p + 60]);
		p += 60;
		
		if(p > sn)
			p -= sn;
	}

	local tail = n % 60;

	if(tail > 0)
		writeln(s2[p .. p + tail]);
}

function makeRandomFasta(id, desc, arr, n)
{
	writeln(">", id, " ", desc);
	
	local f = selectRandom;

	for(i : 60 .. n + 1, 60)
	{
		writeln
		(
			f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr),
			f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr),
			f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr),
			f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr),
			f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr),
			f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), f(arr), (f(arr))
		);
	}

	local tail = n % 60;

	if(tail > 0)
	{
		for(j : 0 .. tail)
			write((f(arr)));

		writeln();
	}
}

local alu =
	"GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGG" ~
	"GAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGA" ~
	"CCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAAT" ~
	"ACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCA" ~
	"GCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGG" ~
	"AGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCC" ~
	"AGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA";

local iub = makeCumulative
([
	[ "a", 0.27 ],
	[ "c", 0.12 ],
	[ "g", 0.12 ],
	[ "t", 0.27 ],
	[ "B", 0.02 ],
	[ "D", 0.02 ],
	[ "H", 0.02 ],
	[ "K", 0.02 ],
	[ "M", 0.02 ],
	[ "N", 0.02 ],
	[ "R", 0.02 ],
	[ "S", 0.02 ],
	[ "V", 0.02 ],
	[ "W", 0.02 ],
	[ "Y", 0.02 ]
]);

local homosapiens = makeCumulative
([
	[ "a", 0.3029549426680 ],
	[ "c", 0.1979883004921 ],
	[ "g", 0.1975473066391 ],
	[ "t", 0.3015094502008 ]
]);

local args = [vararg];
local n = 25_000_000;

if(#args > 0)
{
	try
		n = toInt(args[0]);
	catch(e) {}
}

local time = os.microTime();

makeRepeatFasta("ONE", "Homo sapiens alu", alu, n * 2);
makeRandomFasta("TWO", "IUB ambiguity codes", iub, n * 3);
makeRandomFasta("THREE", "Homo sapiens frequency", homosapiens, n * 5);

writefln("Took ", (os.microTime() - time) / 1000000.0, " sec");