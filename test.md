module test

function foo()
	writeln("foo!")
	
function square(x) = x * x

function main()
{
	writeln("O hai, this is MiniD.")
	foo()
	writefln("The square of {} is {}.", 5, square(5))
}