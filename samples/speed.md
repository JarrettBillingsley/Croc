module speed;

/*
Taken from the Io speed test.
On my desktop.

Python reflIntMath       := 11.85
Python reflFloatMath     := 8.65

Python intMath           := 12.79
Python floatMath         := 9.14

Python localAccesses     := 26.74
Python localSets         := 24.51

Python slotAccesses      := 7.28
Python slotSets          := 8.21

Python blockActivations  := 2.76
Python instantiations    := 2.46
Python version           := "2.5.0 final 0"

// values in millions per second

MiniD reflIntMath        := 22.890733
MiniD reflFloatMath      := 22.586314

MiniD intMath            := 17.48588
MiniD floatMath          := 18.944848

MiniD localAccesses      := 38.003451
MiniD localSets          := 40.715949

MiniD slotAccesses       := 10.479171
MiniD slotSets           := 8.803344

MiniD blockActivations   := 3.809599
MiniD instantiations     := 1.265678

MiniD version            := "2.0 beta"

// values in millions per second
*/

local t1
local oneMillion = 5_000_000

local function foo() {}

local class Tester
{
	x

	function beginTimer()
		t1 = time.microTime()

	function endTimer(s)
	{
		t1 = time.microTime() - t1
		local mps = toFloat(oneMillion) / t1
		writefln("MiniD {} := {:f5}", s, mps)
	}

	function testIntMath()
	{
		:beginTimer()
		local x = 0
		local y = 5
		local z = 10

		for(i: 0 .. oneMillion / 8)
		{
			x = y + z; x = y + z; x = y + z; x = y + z
			x = y + z; x = y + z; x = y + z; x = y + z
		}

		:endTimer("intMath\t\t")
	}

	function testFloatMath()
	{
		:beginTimer()
		local x = 0.0
		local y = 5.0
		local z = 10.0

		for(i: 0 .. oneMillion / 8)
		{
			x = y + z; x = y + z; x = y + z; x = y + z
			x = y + z; x = y + z; x = y + z; x = y + z
		}

		:endTimer("floatMath\t\t")
	}

	function testReflIntMath()
	{
		:beginTimer()
		local x = 0
		local y = 5

		for(i: 0 .. oneMillion / 8)
		{
			x += y; x += y; x += y; x += y
			x += y; x += y; x += y; x += y
		}

		:endTimer("reflIntMath\t")
	}

	function testReflFloatMath()
	{
		:beginTimer()
		local x = 0.0
		local y = 5.0

		for(i: 0 .. oneMillion / 8)
		{
			x += y; x += y; x += y; x += y
			x += y; x += y; x += y; x += y
		}

		:endTimer("reflFloatMath\t")
	}

	function testLocals()
	{
		:beginTimer()
		local v = 1
		local y

		for(i : 0 .. oneMillion / 8)
		{
			y = v; y = v;  y = v; y = v
			y = v; y = v;  y = v; y = v
		}

		:endTimer("localAccesses\t")
	}

	function testSetLocals()
	{
		:beginTimer()
		local v = 1

		for(i : 0 .. oneMillion / 8)
		{
			v = 1; v = 2; v = 3; v = 4
			v = 1; v = 2; v = 3; v = 4
		}

		:endTimer("localSets\t\t")
	}

	function testSlot()
	{
		:beginTimer()
		:x = 1
		local y

		for(i : 0 .. oneMillion / 8)
		{
			y = :x; y = :x; y = :x; y = :x
			y = :x; y = :x; y = :x; y = :x
		}

		:endTimer("slotAccesses\t")
	}

	function testSetSlot()
	{
		:beginTimer()

		for(i : 0 .. oneMillion / 8)
		{
			:x = 1; :x = 2; :x = 3; :x = 4
			:x = 1; :x = 2; :x = 3; :x = 4;
		}

		:endTimer("slotSets\t\t")
	}

	function testBlock()
	{
		:beginTimer()

		for(i : 0 .. oneMillion / 8)
		{
			foo(); foo(); foo(); foo()
			foo(); foo(); foo(); foo()
		}

		:endTimer("blockActivations\t")
	}

	function testInstantiations()
	{
		:beginTimer()

		for(i : 0 .. oneMillion / 8)
		{
			Tester(); Tester(); Tester(); Tester()
			Tester(); Tester(); Tester(); Tester()
		}

		:endTimer("instantiations\t")
	}

	function test()
	{
		:testReflIntMath()
		:testReflFloatMath()
		writefln()
		:testIntMath()
		:testFloatMath()
		writefln()
		:testLocals()
		:testSetLocals()
		writefln()
		:testSlot()
		:testSetSlot()
		writefln()
		:testBlock()
		:testInstantiations()

		writefln()
		writefln("MiniD version\t\t := \"2.0 beta\"")
		writefln()
		writefln("// values in millions per second")
	}
}

function main()
	Tester.test()