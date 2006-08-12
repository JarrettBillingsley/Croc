local a = foo(foo());

/*local t =
{
	x = 5,
	y = 4.5,
	
	function foo()
	{

	}
};

Foo = { };

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

f:bar();

local function outer()
{
	local x = 0;

	local function inner()
	{	
		io.writefln("inner x: ", x);
		++x;
	}

	io.writefln("outer x: ", x);
	inner();
	io.writefln("outer x: ", x);

	return inner;
}

local func = outer();
func();

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
}

local arr = [foo(bar, baz), bat[bar]];

arr:sort();

foreach(local i, local v; pairs(arr))
	io.writefln("arr[", i, "] = ", v);

arr ~= ["foo", "far"];

local function vargs(vararg)
{
	local args = [vararg];
	
	for(local i = 0; i < #args; ++i)
		io.writefln("args[", i, "] = ", args[i]);
}*/