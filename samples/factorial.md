module factorial

// See if you can figure out what this means.  I sure as hell can't.
function Y(g) = (function a(f) = f(f))((function(f) = g(function(x) = f(f)(x))))

// factorial without recursion
function F(f)
{
	return function(n)
		if(n == 0)
			return 1;
		else
			return n * f(n - 1)
}

local factorial = Y(F) // factorial is the fixed point of F

// now test it
for(i: 1 .. 10)
	writefln(i, "! = ", factorial(i))