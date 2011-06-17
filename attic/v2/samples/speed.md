module speed;

/*
Taken from the Io speed test.
On my desktop.

Python reflIntMath       := 12.32
Python reflFloatMath     := 8.65

Python intMath           := 12.79
Python floatMath         := 8.65

Python localAccesses     := 26.60
Python localSets         := 24.63

Python slotAccesses      := 9.71
Python slotSets          := 8.65

Python blockActivations  := 2.99
Python instantiations    := 2.64
Python version           := "2.5.0 final 0"

// values in millions per second

MiniD reflIntMath        := 21.35
MiniD reflFloatMath      := 21.24

MiniD intMath            := 13.85
MiniD floatMath          := 12.71

MiniD localAccesses      := 38.08
MiniD localSets          := 41.84

MiniD slotAccesses       := 5.03
MiniD slotSets           := 4.96

MiniD blockActivations   := 1.98
MiniD instantiations     := 0.45

MiniD version            := "1.0"

// values in millions per second
*/

local oneMillion = 1_000_000 // 2 + 2 = 5 for large values of 2
local t1

local function foo() return;

local object Tester
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
			Tester.clone(); Tester.clone(); Tester.clone(); Tester.clone()
			Tester.clone(); Tester.clone(); Tester.clone(); Tester.clone()
		}

		:endTimer("instantiations\t")
	}

	function test()
	{
// 		writefln()
// 		:testReflIntMath()
// 		:testReflFloatMath()
// 		writefln()
// 		:testIntMath()
// 		:testFloatMath()
// 		writefln()
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
		writefln()
	}
}

function main()
	Tester.test()
