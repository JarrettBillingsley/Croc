module speed;

/*
Taken from the Io speed test.
On my desktop.

Python reflIntMath       := 13.93
Python reflFloatMath     := 9.69

Python intMath           := 14.58
Python floatMath         := 11.42

Python localAccesses     := 26.74
Python localSets         := 29.07

Python slotAccesses      := 11.85
Python slotSets          := 10.68

Python blockActivations  := 3.55
Python instantiations    := 3.68
Python version           := "2.6.2 final 0"

// values in millions per second

MiniD reflIntMath        := 29.55
MiniD reflFloatMath      := 27.54

MiniD intMath            := 21.40
MiniD floatMath          := 23.69

MiniD localAccesses      := 34.16
MiniD localSets          := 35.48

MiniD slotAccesses       := 12.78
MiniD slotSets           := 12.34

MiniD blockActivations   := 3.33
MiniD instantiations     := 1.61

MiniD version            := "2.0"

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
		writefln("MiniD {} := {:f2}", s, mps)
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
		writeln()
		:testIntMath()
		:testFloatMath()
		writeln()
		:testLocals()
		:testSetLocals()
		writeln()
		:testSlot()
		:testSetSlot()
		writeln()
		:testBlock()
		:testInstantiations()

		writeln()
		writeln("MiniD version\t\t := \"2.0\"")
		writeln()
		writeln("// values in millions per second")
	}
}

function main()
	Tester.test()