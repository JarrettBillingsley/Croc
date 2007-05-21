module unlzw;

local args = [vararg];

if(#args < 2)
{
	writefln("Usage: mdcl unlzw.md inputFile outputFile");
	return;
}

local input = io.File(args[0], io.FileMode.In);
local output = io.File(args[1], io.FileMode.OutNew);
local dict = {};
local code;

for(code = 0; code < 128; code++)
	dict[code] = toString(toChar(code));

local k = input.readShort();
output.writeChars(dict[k]);

local w = dict[k];
local fchar = w[0];
local entry;

do
{
	k = input.readShort();

	if(k in dict)
		entry = dict[k];
	else
		entry = w ~ fchar;

	output.writeChars(entry);

	fchar = entry[0];
	dict[code] = w ~ fchar;
	code++;
	w = entry;
} while(!input.eof())

input.close();
output.close();