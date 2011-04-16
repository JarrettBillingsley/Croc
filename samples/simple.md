module samples.simple

namespace Sandbox : null
{
	write = write
	writeln = writeln
	writef = writef
	writefln = writefln
}

local x = "hello \" there"
local y = @"hello "" there"
local z = @'hello " there'

writeln$ x is y
writeln$ y is z

writeln$ x