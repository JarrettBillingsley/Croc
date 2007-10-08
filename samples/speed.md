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

local oneMillion = 5_000_00; // 2 + 2 = 5 for large values of 2
local t1;

class Tester
{
	x;

	function foo()
	{
		return 1;
	}

	function beginTimer()
	{
		t1 = os.microTime();
	}

	function endTimer(s)
	{
		local mps = toFloat(oneMillion) / ((os.microTime() - t1));
		writefln("MiniD {} := {}", s, mps);
	}
	
	function testIntMath()
	{
		this.beginTimer();
		local x = 0;
		local y = 5;
		local z = 10;

		for(i: 0 .. oneMillion / 8)
		{
			x = y + z; x = y + z; x = y + z; x = y + z;
			x = y + z; x = y + z; x = y + z; x = y + z;
		}

		this.endTimer("intMath\t\t");
	}

	function testFloatMath()
	{
		this.beginTimer();
		local x = 0.0;
		local y = 5.0;
		local z = 10.0;

		for(i: 0 .. oneMillion / 8)
		{
			x = y + z; x = y + z; x = y + z; x = y + z;
			x = y + z; x = y + z; x = y + z; x = y + z;
		}

		this.endTimer("floatMath\t\t");
	}

	function testReflIntMath()
	{
		this.beginTimer();
		local x = 0;
		local y = 5;

		for(i: 0 .. oneMillion / 8)
		{
			x += y; x += y; x += y; x += y;
			x += y; x += y; x += y; x += y;
		}

		this.endTimer("reflIntMath\t");
	}

	function testReflFloatMath()
	{
		this.beginTimer();
		local x = 0.0;
		local y = 5.0;

		for(i: 0 .. oneMillion / 8)
		{
			x += y; x += y; x += y; x += y;
			x += y; x += y; x += y; x += y;
		}

		this.endTimer("reflFloatMath\t");
	}

	function testLocals()
	{
		this.beginTimer();
		local v = 1;
		local y;

		for(i : 0 .. oneMillion / 8)
		{
			y = v; y = v;  y = v; y = v;
			y = v; y = v;  y = v; y = v;
		}

		this.endTimer("localAccesses\t");
	}

	function testSetLocals()
	{
		this.beginTimer();
		local v = 1;

		for(i : 0 .. oneMillion / 8)
		{
			v = 1; v = 2; v = 3; v = 4;
			v = 1; v = 2; v = 3; v = 4;
		}

		this.endTimer("localSets\t\t");
	}

	function testSlot()
	{
		this.beginTimer();
		this.x = 1;
		local y;

		for(i : 0 .. oneMillion / 8)
		{
			y = this.x; y = this.x; y = this.x; y = this.x;
			y = this.x; y = this.x; y = this.x; y = this.x;
		}

		this.endTimer("slotAccesses\t");
	}

	function testSetSlot()
	{
		this.beginTimer();

		for(i : 0 .. oneMillion / 8)
		{
			this.x = 1; this.x = 2; this.x = 3; this.x = 4;
			this.x = 1; this.x = 2; this.x = 3; this.x = 4;
		}

		this.endTimer("slotSets\t\t");
	}

	function testBlock()
	{
		this.beginTimer();

		for(i : 0 .. oneMillion / 8)
		{
			this.foo(); this.foo(); this.foo(); this.foo();
			this.foo(); this.foo(); this.foo(); this.foo();
		}

		this.endTimer("blockActivations\t");
	}

	function testInstantiations()
	{
		this.beginTimer();

		for(i : 0 .. oneMillion / 8)
		{
			Tester(); Tester(); Tester(); Tester();
			Tester(); Tester(); Tester(); Tester();
		}

		this.endTimer("instantiations\t");
	}

	function test()
	{
		writefln();
		this.testReflIntMath();
		this.testReflFloatMath();
		writefln();
		this.testIntMath();
		this.testFloatMath();
		writefln();
		this.testLocals();
		this.testSetLocals();
		writefln();
		this.testSlot();
		this.testSetSlot();
		writefln();
		this.testBlock();
		this.testInstantiations();
		
		writefln();
		writefln("MiniD version\t\t := \"1.0\"");
		writefln();
		writefln("// values in millions per second");
		writefln();
	}
}


Tester().test();
