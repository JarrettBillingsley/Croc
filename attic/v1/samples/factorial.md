module factorial;

function Y(g)
{
	local a = function(f) f(f);

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
function F(f)
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
for(i: 3 .. 18)
	writefln(i, "! = ", factorial(i));