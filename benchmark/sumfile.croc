module benchmark.sumfile;

// ummm I don't know how to get the input file for this.
function main()
{
	local timer = time.Timer()
	timer.start()

		local sum = 0

		foreach(line; io.stdin)
			sum += toInt(line)

		writeln(sum)

	timer.stop()
	writefln("Took {} sec", timer.seconds())
}