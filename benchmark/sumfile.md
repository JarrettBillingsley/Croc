module benchmark.sumfile;

// ummm I don't know how to get the input file for this.

local time = os.microTime();

	local sum = 0;
	
	foreach(line; io.stdin)
		sum += toInt(line);
		
	writefln(sum);
	
time = os.microTime() - time;
writefln("Took ", time / 1000000.0, " sec");