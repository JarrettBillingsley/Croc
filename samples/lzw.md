module lzw;

local args = [vararg];

if(#args < 2)
{
	writefln("Usage: mdcl lzw.md inputFile outputFile");
	return;
}

local input = io.File(args[0], io.FileMode.In);
local output = io.File(args[1], io.FileMode.OutNew);
local dict = {};
local w = "";
local code;

for(code = 0; code < 128; code++)
	dict[toString(toChar(code))] = code;

do
{
	local k = input.readChar();

	local wk = w ~ k;

	if(wk in dict)
		w = wk;
	else
	{
		output.writeShort(dict[w]);
		dict[wk] = code;
		code++;
		w = toString(k);
	}
} while(!input.eof())

input.close();
output.close();