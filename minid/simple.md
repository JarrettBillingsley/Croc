class StringStream
{
	mSource = "";
	mIndex = 0;
	
	method constructor(source)
	{
		if(typeof(source) != "string")
			throw "StringStream.constructor() -- Expected string argument";
			
		this.mSource = source;
	}
	
	method readChar()
	{
		if(this.mIndex >= #this.mSource)
			return null;
		
		local ret = this.mSource:slice(this.mIndex, this.mIndex + 1);
		++this.mIndex;

		return ret;
	}
	
	method eof()
	{
		return this.mIndex >= #this.mSource;
	}
}

class ConsoleOutStream
{
	method write(vararg)
	{
		local args = [vararg];
		
		for(local i = 0; i < #args; ++i)
			writefln(args[i]);
	}
}

class CompressDict
{
	mData = {};
	mNextCode = 128;

	method constructor()
	{
		for(local i = 0; i < 128; ++i)
			this.mData[string.fromChar(i)] = i;
	}
	
	method has(key)
	{
		return this.mData[key] !is null;
	}

	method lookup(key)
	{
		return this.mData[key];
	}

	method addCode(key)
	{
		this.mData[key] = this.mNextCode;
		++this.mNextCode;
	}
}

function compress(input, output)
{
	local dict = CompressDict();
	local w = "";

	do
	{
		local k = input:readChar();

		if(dict:has(w ~ k))
			w ~= k;
		else
		{
			output:write(dict:lookup(w));
			dict:addCode(w ~ k);
			w = k;
		}

	} while(!input:eof())
}

local t = { };
t["hi"] = 4;
writefln(t["hi"]);
t["a"] = 5;
writefln(t["a"]);

local var = string.fromChar;
writefln(t[var('a')]);

throw "end";

local in = StringStream(`
Nevertheless, a few are to be feared; and foremost among these is the
Malmignatte, the terror of the Corsican peasantry.  I have seen her
settle in the furrows, lay out her web and rush boldly at insects larger
than herself; I have admired her garb of black velvet speckled with
carmine-red; above all, I have heard most disquieting stories told about
her.  Around Ajaccio and Bonifacio, her bite is reputed very dangerous,
sometimes mortal.  The countryman declares this for a fact and the doctor
does not always dare deny it.  In the neighbourhood of Pujaud, not far
from Avignon, the harvesters speak with dread of _Theridion lugubre_, {1}
first observed by Leon Dufour in the Catalonian mountains; according to
them, her bite would lead to serious accidents.  The Italians have
bestowed a bad reputation on the Tarantula, who produces convulsions and
frenzied dances in the person stung by her.  To cope with 'tarantism,'
the name given to the disease that follows on the bite of the Italian
Spider, you must have recourse to music, the only efficacious remedy, so
they tell us.  Special tunes have been noted, those quickest to afford
relief.  There is medical choreography, medical music.  And have we not
the tarentella, a lively and nimble dance, bequeathed to us perhaps by
the healing art of the Calabrian peasant?

Must we take these queer things seriously or laugh at them?  From the
little that I have seen, I hesitate to pronounce an opinion.  Nothing
tells us that the bite of the Tarantula may not provoke, in weak and very
impressionable people, a nervous disorder which music will relieve;
nothing tells us that a profuse perspiration, resulting from a very
energetic dance, is not likely to diminish the discomfort by diminishing
the cause of the ailment.  So far from laughing, I reflect and enquire,
when the Calabrian peasant talks to me of his Tarantula, the Pujaud
reaper of his _Theridion lugubre_, the Corsican husbandman of his
Malmignatte.  Those Spiders might easily deserve, at least partly, their
terrible reputation.

The most powerful Spider in my district, the Black-bellied Tarantula,
will presently give us something to think about, in this connection.  It
is not my business to discuss a medical point, I interest myself
especially in matters of instinct; but, as the poison-fangs play a
leading part in the huntress' manoeuvres of war, I shall speak of their
effects by the way.  The habits of the Tarantula, her ambushes, her
artifices, her methods of killing her prey: these constitute my subject.
I will preface it with an account by Leon Dufour, {2} one of those
accounts in which I used to delight and which did much to bring me into
closer touch with the insect.  The Wizard of the Landes tells us of the
ordinary Tarantula, that of the Calabrias, observed by him in Spain:
 `);
 
local out = ConsoleOutStream();

compress(in, out);

/*writefln();

local function outer()
{
	local x = 3;

	local function inner()
	{
		++x;
		writefln("inner x: ", x);
	}

	writefln("outer x: ", x);
	inner();
	writefln("outer x: ", x);

	return inner;
}

local func = outer();
func();

writefln();

local function thrower(x)
{
	if(x >= 3)
		throw "Sorry, x is too big for me!";
}

local function tryCatch(iterations)
{
	try
	{
		for(local i = 0; i < iterations; ++i)
		{
			writefln("tryCatch: ", i);
			thrower(i);
		}
	}
	catch(e)
	{
		writefln("tryCatch caught: ", e);
		throw e;
	}
	finally
	{
		writefln("tryCatch finally");
	}
}

try
{
	tryCatch(2);
	tryCatch(5);
}
catch(e)
{
	writefln("caught: ", e);
}

writefln();

function arrayIterator(array, index)
{
	++index;

	if(index >= #array)
		return null;

	return index, array[index];
}

function pairs(container)
{
	return arrayIterator, container, -1;
}

local arr = [3, 5, 7];

arr:sort();

foreach(local i, local v; pairs(arr))
	writefln("arr[", i, "] = ", v);

arr ~= ["foo", "far"];

writefln();

foreach(local i, local v; pairs(arr))
	writefln("arr[", i, "] = ", v);

writefln();

local function vargs(vararg)
{
	local args = [vararg];

	writefln("num varargs: ", #args);

	for(local i = 0; i < #args; ++i)
		writefln("args[", i, "] = ", args[i]);
}

vargs();

writefln();

vargs(2, 3, 5, "foo", "bar");

writefln();

for(local switchVar = 0; switchVar < 11; ++switchVar)
{
	switch(switchVar)
	{
		case 1, 2, 3:
			writefln("small");
			break;

		case 4, 5, 6:
			writefln("medium");
			break;
			
		case 7, 8, 9:
			writefln("large");
			break;
			
		default:
			writefln("out of range");
			break;
	}
}

writefln();

local stringArray = ["hi", "bye", "foo"];

foreach(local i, local v; pairs(stringArray))
{
	switch(v)
	{
		case "hi":
			writefln("switched to hi");
			break;
			
		case "bye":
			writefln("switched to bye");
			break;
			
		default:
			writefln("switched to something else");
			break;
	}
}*/