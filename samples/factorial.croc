module factorial

// See if you can figure out what this means.  I sure as hell can't.
function Y(g) = (\f -> f(f))(\f -> g(\x -> f(f)(x)))

// factorial without recursion
function F(f) = \n -> n == 0 ? 1 : n * f(n - 1)

global factorial = Y(F) // factorial is the fixed point of F

function main()
{
	// now test it
	for(i: 1 .. 10)
		writeln(i, "! = ", factorial(i))
}