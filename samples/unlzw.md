module unlzw

function main(vararg)
{
	if(#vararg < 2)
	{
		writeln("Usage: mdcl unlzw.md inputFile outputFile")
		return
	}
	
	local input = io.inFile(vararg[0])
	local output = io.outFile(vararg[1])
	local dict = {}
	local code
	
	for(code = 0; code < 128; code++)
		dict[code] = toString(toChar(code))
	
	local shortCount = input.readInt()
	
	local k = input.readShort()
	output.writeChars(dict[k])
	shortCount--
	
	local w = dict[k]
	local fchar = w[0]
	local entry
	
	for( ; shortCount > 0; shortCount--)
	{
		k = input.readShort()
	
		if(k in dict)
			entry = dict[k]
		else
			entry = w ~ fchar
	
		output.writeChars(entry)
	
		fchar = entry[0]
		dict[code] = w ~ fchar
		code++
		w = entry
	}
	
	output.flush()
	
	input.close()
	output.close()
}