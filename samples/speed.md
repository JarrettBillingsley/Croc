module speed;

/*
Taken from the Io speed test.
Both the Python and the MiniD tests were done on my laptop.

Python localAccesses       := 10.00
Python localSets           := 14.29

Python slotAccesses        := 10.00
Python slotSets            := 7.63

Python blockActivations    := 2.56
Python instantiations      := 2.43
Python version := "2.5.0 final 0"

// values in millions per second

MiniD localAccesses      := 17.19
MiniD localSets          := 27.39

MiniD slotAccesses       := 5.10
MiniD slotSets           := 4.88

MiniD blockActivations   := 2.32
MiniD instantiations     := 0.32
MiniD version pre-1.0

// values in millions per second

On my desktop.

Python localAccesses       := 15.87
Python localSets           := 16.13

Python slotAccesses        := 5.32
Python slotSets            := 5.32

Python blockActivations    := 1.78
Python instantiations      := 1.73
Python version := "2.5.0 final 0"

// values in millions per second

MiniD localAccesses      := 20.18
MiniD localSets          := 22.90

MiniD slotAccesses       := 2.76
MiniD slotSets           := 2.83

MiniD blockActivations   := 1.59
MiniD instantiations     := 0.10
MiniD version pre-1.0

// values in millions per second
*/

local oneMillion = 10_000_000; // 2 + 2 = 5 for large values of 2

class Tester
{
	t1;
	x;

	function foo()
	{
		return 1;
	}

	function beginTimer()
	{
		this.t1 = os.microTime();
	}

	function endTimer(s)
	{
		local mps = toFloat(oneMillion) / ((os.microTime() - this.t1));
		writefln("MiniD %s := %0.2f", s, mps);
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

		writefln("MiniD version pre-1.0");
		writefln();
		writefln("// values in millions per second");
		writefln();
	}
}

Tester().test();
