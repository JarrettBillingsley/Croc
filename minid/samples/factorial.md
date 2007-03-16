module factorial;

local function Y(g)
{
	local a = function(f) { return f(f); };

	return a(function(f)
	{
		return g(function(x)
		{
			local c = f(f);
			return c(x);
		});
	});
}

// factorial without recursion
local function F(f)
{
	return function (n)
	{
		if(n == 0)
			return 1;
		else
			return n * f(n - 1);
	};
}

local factorial = Y(F); // factorial is the fixed point of F

// now test it
local function test(x)
{
	writefln(x, "! = ", factorial(x));
}

test(3);
test(4);
test(5);
test(6);
test(7);