local function foo()
{
	writefln("hi ", 4, ", ", 5);
}

foo();

writefln();

local t =
{
	x = 5,
	y = 4.5,
	
	function foo(this)
	{
		writefln("foo: ", this.x, ", ", this.y);
	}
};

t:foo();

writefln();

/*Foo = { };

table.setMeta(Foo, { opIndex = Foo });

function Foo:bar()
{
	io.writefln("Foo.bar!");
}

function Foo:new()
{
	local t = { };
	table.setMeta(t, this);
	return t;
}

local f = Foo:new();

f:bar();*/

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

/*local function thrower(x)
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
			io.writefln("tryCatch: ", i);
			thrower(i);
		}
	}
	catch(e)
	{
		io.writefln("tryCatch caught: ", e);
		throw e;
	}
	finally
	{
		io.writefln("tryCatch finally");
	}
}

try
{
	tryCatch(2);
	tryCatch(5);
}
catch(e)
{
	io.writefln("caught: ", e);
}*/

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

//arr:sort();

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