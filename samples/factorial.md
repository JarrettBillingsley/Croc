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
writefln(3, "! = ", factorial(3));
writefln(4, "! = ", factorial(4));
writefln(5, "! = ", factorial(5));
writefln(6, "! = ", factorial(6));
writefln(7, "! = ", factorial(7));