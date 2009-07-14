module lzw

function main(vararg)
{
	if(#vararg < 2)
	{
		writeln("Usage: mdcl lzw.md inputFile outputFile")
		return
	}
	
	local input = io.inFile(vararg[0])
	local output = io.outFile(vararg[1])
	local dict = {}
	local w = ""
	local code

	for(code = 0; code < 128; code++)
		dict[toString(toChar(code))] = code
	
	local shortCount = 0
	output.writeInt(0)

	for(i: 0 .. input.size())
	{
		local k = input.readChar()

		local wk = w ~ k

		if(wk in dict)
			w = wk
		else
		{
			output.writeShort(dict[w])
			shortCount++
			dict[wk] = code
			code++
			w = toString(k)
		}
	}
	
	if(#w > 0)
	{
		output.writeShort(dict[w])
		shortCount++
	}

	output.flush()
	output.position(0)
	output.writeInt(shortCount)
	
	input.close()
	output.close()
}