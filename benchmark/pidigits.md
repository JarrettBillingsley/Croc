module benchmark.pidigits;

// Broken, need a bigInt representation

function Next(z)
{
	return (3 * z[0] + z[1]) / (3 * z[2] + z[3]);
}

function Safe(z, n)
{
	return n == ((4 * z[0] + z[1]) / (4 * z[2] + z[3]));
}

function Comp(a, b)
{
	return [a[0] * b[0] + a[1] * b[2],
			a[0] * b[1] + a[1] * b[3],
			a[2] * b[0] + a[3] * b[2],
			a[2] * b[1] + a[3] * b[3]];
}

function Prod(z, n)
{
	return Comp([10, -10 * n, 0, 1], z);
}

function Cons(z, k)
{
	return Comp(z, [k, 4 * k + 2, 0, 2 * k + 1]);
}

function Digit(k, z, n, Row, Col)
{
	if(n > 0)
	{
		local y = Next(z);
		
		if(Safe(z, y))
		{
			if(Col == 10)
			{
				writef("\t:", 10 + Row, "\n", y);
				return Digit(k, Prod(z, y), n - 1, 10 + Row, 1);
			}
			else
			{
				writef(y);
				return Digit(k, Prod(z, y), n - 1, Row, Col + 1);
			}
		}
		else
		{
			return Digit(k + 1, Cons(z, k), n, Row, Col);
		}
	}
	else
	{
		writef(" ".repeat(10 - Col));
		writefln("\t:", Row + Col);
	}
}

function Digits(n)
{
	return Digit(1, [1, 0, 0, 1], n, 0, 0);
}

local args = [vararg];
local n = 2500;

if(#args > 0)
{
	try
		n = toInt(args[0]);
	catch(e) {}
}

local time = os.microTime();

 Digits(n);

time = os.microTime() - time;
writefln("Took ", time / 1000000.0, " sec");