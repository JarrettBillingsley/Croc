module factorial

// See if you can figure out what this means.  I sure as hell can't.
function Y(g) = (function a(f) = f(f))(function(f) = g(function(x) = f(f)(x)))

// factorial without recursion
function F(f) = function(n) = n == 0 ? 1 : n * f(n - 1)

global factorial = Y(F) // factorial is the fixed point of F

function main()
{
	// now test it
	for(i: 1 .. 10)
		writefln(i, "! = ", factorial(i))
}