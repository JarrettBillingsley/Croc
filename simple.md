// A Lua-like table
local t =
{
	x = 5 // int
	y = 4.5 // float
	
	function foo()
	{
		
	}
};

// A class
Foo = { };

// opIndex == __index in Lua
Foo.opIndex = Foo;

// A method
function Foo:bar()
{
	io.writefln("Foo.bar!");
}

// The a:b() is shorthand for a.b(this)
function Foo:new()
{
	local t = { };
	table.setMeta(t, this);
	return t;
}

local f = Foo:new();

// f:bar() is shorthand for f.bar(f)
f:bar();

// A Squirrel-like array
local arr = [3, 9, 2];

// This calls the global array.sort(arr), with some fancy metatable stuff.
// Lua does a similar thing with string values.
arr:sort();

// Iterate through it
foreach(local i, local v; pairs(arr))
	io.writefln("arr[", i, "] = ", v);

// Append, like in D
arr ~= ["foo", "far"];

// Multiple assignment
local x, y, z = 4, 5, 6;

local function outer()
{
	local x = 0;

	local function inner()
	{	
		// A Lua-style closure; x is an upvalue
		io.writefln("inner x: ", x);
		++x;
	}

	// When called now, inner modifies outer's x
	io.writefln("outer x: ", x);
	inner();
	io.writefln("outer x: ", x);

	// But return inner...
	return inner;
}

local func = outer();
// And now inner's x is its own value
func();

// The following mess should print:
// tryCatch: 0
// tryCatch: 1
// tryCatch finally
// tryCatch: 0
// tryCatch: 1
// tryCatch: 2
// tryCatch: 3
// tryCatch caught: Sorry, x is too big for me!
// tryCatch finally
// caught: Sorry, x is too big for me!
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