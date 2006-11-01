local t = { };
t[4] = "hi";
t["hi"] = 5;

writefln(t[4]);

/*class Test
{
	mData = [4, 5, 6];
	
	method opApply(extra)
	{
		function iterator(this, index)
		{
			++index;
			
			if(index >= #this.mData)
				return;
				
			return index, this.mData[index];
		}
		
		function iterator_reverse(this, index)
		{
			--index;
			
			if(index < 0)
				return;
				
			return index, this.mData[index];
		}

		if(isString(extra) && extra == "reverse")
			return iterator_reverse, this, #this.mData;
		else
			return iterator, this, -1;
	}
}

local t = Test();

foreach(local k, local v; t)
	writefln("t[", k, "] = ", v);
	
writefln();

foreach(local k, local v; t, "reverse")
	writefln("t[", k, "] = ", v);
	
t =
{
	fork = 5,
	knife = 10,
	spoon = "hi"
};

writefln();

foreach(local k, local v; t)
	writefln("t[", k, "] = ", v);
	
t = [5, 10, "hi"];

writefln();

foreach(local k, local v; t)
	writefln("t[", k, "] = ", v);

writefln();

foreach(local k, local v; t, "reverse")
	writefln("t[", k, "] = ", v);
	
writefln();

local s = "hello";

foreach(local k, local v; s)
	writefln("s[", k, "] = ", v);
	
writefln();

foreach(local k, local v; s, "reverse")
	writefln("s[", k, "] = ", v);*/

/*local a = array.new(10);

for(local i = 0; i < 10; ++i)
	a[i] = function() { return i; };

for(local i = 0; i < #a; ++i)
	writefln(a[i]());*/


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