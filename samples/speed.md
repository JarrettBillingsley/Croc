module speed;

/*
Taken from the Io speed test.
On my desktop.

Python localAccesses       := 24.63
Python localSets           := 26.60

Python slotAccesses        := 8.65
Python slotSets            := 8.43

Python blockActivations    := 2.83
Python instantiations      := 2.67
Python version := "2.5.0 final 0"

// values in millions per second

MiniD localAccesses      := 29.68
MiniD localSets          := 35.94

MiniD slotAccesses       := 4.41
MiniD slotSets           := 4.19

MiniD blockActivations   := 1.74
MiniD instantiations     := 0.50
MiniD version 2 beta

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
		this.x = 1;

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
		this.testLocals();
		this.testSetLocals();
		writefln();
		this.testSlot();
		this.testSetSlot();
		writefln();
		this.testBlock();
		this.testInstantiations();

		writefln("MiniD version 2 beta");
		writefln();
		writefln("// values in millions per second");
		writefln();
	}
}

Tester().test();
