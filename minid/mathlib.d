module minid.mathlib;

import minid.state;
import minid.types;

import std.math;
import std.random;

class MathLib
{
	int rand(MDState s)
	{
		uint numParams = s.numParams();
		
		switch(numParams)
		{
			case 0:
				s.push(cast(int)std.random.rand());
				break;

			case 1:
				s.push(cast(int)std.random.rand() % s.getIntParam(0));
				break;
				
			default:
				int lo = s.getIntParam(0);
				int hi = s.getIntParam(1);
				
				s.push(cast(int)(std.random.rand() % (hi - lo)) + lo);
				break;
		}
		
		return 1;
	}
}

public void init(MDState s)
{
	MathLib lib = new MathLib();
	
	MDTable mathLib = MDTable.create
	(
		"rand",    new MDClosure(s, &lib.rand,    "math.rand")
	);

	s.setGlobal("math", mathLib);
}