module test;

global x = 5;

global function foo()
{
	return "foo";
}

local function bar()
{
	return "bar";
}

global function opCall()
{
	writefln("BRRING BRRING I HAVE AN IMPORTANT CALL");
}