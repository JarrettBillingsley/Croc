module minid.mathlib;

import minid.state;
import minid.types;

import math = std.math;
import random = std.random;

class MathLib
{
	static int getInt(MDState s, uint i)
	{
		if(s.isIntParam(i))
			return s.getIntParam(i);
		else
			throw new MDRuntimeException(s, "Expected 'int', not '%s'", s.getParam(i).typeString());
	}
	
	static float getFloat(MDState s, uint i)
	{
		if(s.isIntParam(i))
			return s.getIntParam(i);
		else if(s.isFloatParam(i))
			return s.getFloatParam(i);
		else
			throw new MDRuntimeException(s, "Expected 'int' or 'float', not '%s'", s.getParam(i).typeString());
	}

	int abs(MDState s)
	{
		if(s.isIntParam(0))
			s.push(math.abs(s.getIntParam(0)));
		else if(s.isFloatParam(0))
			s.push(math.abs(s.getFloatParam(0)));
		else
			throw new MDRuntimeException(s, "Expected 'int' or 'float', not '%s'", s.getParam(0).typeString());
			
		return 1;
	}
	
	int sin(MDState s)
	{
		s.push(math.sin(getFloat(s, 0)));
		return 1;
	}
	
	int cos(MDState s)
	{
		s.push(math.cos(getFloat(s, 0)));
		return 1;
	}
	
	int tan(MDState s)
	{
		s.push(math.tan(getFloat(s, 0)));
		return 1;
	}
	
	int asin(MDState s)
	{
		s.push(math.asin(getFloat(s, 0)));
		return 1;
	}
	
	int acos(MDState s)
	{
		s.push(math.acos(getFloat(s, 0)));
		return 1;
	}
	
	int atan(MDState s)
	{
		s.push(math.atan(getFloat(s, 0)));
		return 1;
	}
	
	int atan2(MDState s)
	{
		s.push(math.atan2(getFloat(s, 0), getFloat(s, 1)));
		return 1;
	}
	
	int sqrt(MDState s)
	{
		s.push(math.sqrt(getFloat(s, 0)));
		return 1;
	}
	
	int cbrt(MDState s)
	{
		s.push(math.cbrt(getFloat(s, 0)));
		return 1;
	}
	
	int exp(MDState s)
	{
		s.push(math.exp(getFloat(s, 0)));
		return 1;
	}
	
	int ln(MDState s)
	{
		s.push(math.log(getFloat(s, 0)));
		return 1;
	}
	
	int log2(MDState s)
	{
		s.push(math.log2(getFloat(s, 0)));
		return 1;
	}
	
	int log10(MDState s)
	{
		s.push(math.log10(getFloat(s, 0)));
		return 1;
	}
	
	int hypot(MDState s)
	{
		s.push(math.hypot(getFloat(s, 0), getFloat(s, 1)));
		return 1;
	}
	
	int lgamma(MDState s)
	{
		s.push(math.lgamma(getFloat(s, 0)));
		return 1;
	}
	
	int gamma(MDState s)
	{
		s.push(math.tgamma(getFloat(s, 0)));
		return 1;
	}
	
	int ceil(MDState s)
	{
		s.push(math.ceil(getFloat(s, 0)));
		return 1;
	}
	
	int floor(MDState s)
	{
		s.push(math.floor(getFloat(s, 0)));
		return 1;
	}
	
	int round(MDState s)
	{
		s.push(cast(int)math.round(getFloat(s, 0)));
		return 1;
	}
	
	int trunc(MDState s)
	{
		s.push(cast(int)math.trunc(getFloat(s, 0)));
		return 1;
	}
	
	int isNan(MDState s)
	{
		s.push(cast(bool)math.isnan(getFloat(s, 0)));
		return 1;
	}

	int isInf(MDState s)
	{
		s.push(cast(bool)math.isinf(getFloat(s, 0)));
		return 1;
	}
	
	int sign(MDState s)
	{
		if(s.isIntParam(0))
		{
			int val = s.getIntParam(0);
			
			if(val < 0)
				s.push(-1);
			else if(val > 0)
				s.push(1);
			else
				s.push(0);
		}
		else
		{
			float val = s.getFloatParam(0);

			if(val < 0)
				s.push(-1);
			else if(val > 0)
				s.push(1);
			else
				s.push(0);
		}
		
		return 1;
	}
	
	int pow(MDState s)
	{
		float base = getFloat(s, 0);
		
		if(s.isIntParam(1))
			s.push(math.pow(cast(real)base, getInt(s, 1)));
		else
			s.push(math.pow(base, getFloat(s, 1)));
			
		return 1;
	}

	int rand(MDState s)
	{
		uint numParams = s.numParams();
		
		switch(numParams)
		{
			case 0:
				s.push(cast(int)random.rand());
				break;

			case 1:
				s.push(cast(int)random.rand() % s.getIntParam(0));
				break;

			default:
				int lo = s.getIntParam(0);
				int hi = s.getIntParam(1);
				
				s.push(cast(int)(random.rand() % (hi - lo)) + lo);
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
		"e",        std.math.E,
		"pi",       std.math.PI,
		"nan",      float.nan,
		"infinity", float.infinity,
		"abs",      new MDClosure(s, &lib.abs,     "math.abs"),
		"sin",      new MDClosure(s, &lib.sin,     "math.sin"),
		"cos",      new MDClosure(s, &lib.cos,     "math.cos"),
		"tan",      new MDClosure(s, &lib.tan,     "math.tan"),
		"asin",     new MDClosure(s, &lib.asin,    "math.asin"),
		"acos",     new MDClosure(s, &lib.acos,    "math.acos"),
		"atan",     new MDClosure(s, &lib.atan,    "math.atan"),
		"atan2",    new MDClosure(s, &lib.atan2,   "math.atan2"),
		"sqrt",     new MDClosure(s, &lib.sqrt,    "math.sqrt"),
		"cbrt",     new MDClosure(s, &lib.cbrt,    "math.cbrt"),
		"pow",      new MDClosure(s, &lib.pow,     "math.pow"),
		"exp",      new MDClosure(s, &lib.exp,     "math.exp"),
		"ln",       new MDClosure(s, &lib.ln,      "math.ln"),
		"log2",     new MDClosure(s, &lib.log2,    "math.log2"),
		"log10",    new MDClosure(s, &lib.log10,   "math.log10"),
		"hypot",    new MDClosure(s, &lib.hypot,   "math.hypot"),
		"lgamma",   new MDClosure(s, &lib.lgamma,  "math.lgamma"),
		"gamma",    new MDClosure(s, &lib.gamma,   "math.gamma"),
		"ceil",     new MDClosure(s, &lib.ceil,    "math.ceil"),
		"floor",    new MDClosure(s, &lib.floor,   "math.floor"),
		"round",    new MDClosure(s, &lib.round,   "math.round"),
		"trunc",    new MDClosure(s, &lib.trunc,   "math.trunc"),
		"isNan",    new MDClosure(s, &lib.isNan,   "math.isNan"),
		"isInf",    new MDClosure(s, &lib.isInf,   "math.isInf"),
		"sign",     new MDClosure(s, &lib.sign,    "math.sign"),
		"rand",     new MDClosure(s, &lib.rand,    "math.rand")
	);

	s.setGlobal("math"d, mathLib);
}