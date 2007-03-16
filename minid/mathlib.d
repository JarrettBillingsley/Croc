/******************************************************************************
License:
Copyright (c) 2007 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module minid.mathlib;

import minid.types;

import math = std.math;
import random = std.random;

class MathLib
{
	this(MDNamespace namespace)
	{
		namespace.addList
		(
			"e"d,        std.math.E,
			"pi"d,       std.math.PI,
			"nan"d,      float.nan,
			"infinity"d, float.infinity,
			"abs"d,      new MDClosure(namespace, &abs,     "math.abs"),
			"sin"d,      new MDClosure(namespace, &sin,     "math.sin"),
			"cos"d,      new MDClosure(namespace, &cos,     "math.cos"),
			"tan"d,      new MDClosure(namespace, &tan,     "math.tan"),
			"asin"d,     new MDClosure(namespace, &asin,    "math.asin"),
			"acos"d,     new MDClosure(namespace, &acos,    "math.acos"),
			"atan"d,     new MDClosure(namespace, &atan,    "math.atan"),
			"atan2"d,    new MDClosure(namespace, &atan2,   "math.atan2"),
			"sqrt"d,     new MDClosure(namespace, &sqrt,    "math.sqrt"),
			"cbrt"d,     new MDClosure(namespace, &cbrt,    "math.cbrt"),
			"pow"d,      new MDClosure(namespace, &pow,     "math.pow"),
			"exp"d,      new MDClosure(namespace, &exp,     "math.exp"),
			"ln"d,       new MDClosure(namespace, &ln,      "math.ln"),
			"log2"d,     new MDClosure(namespace, &log2,    "math.log2"),
			"log10"d,    new MDClosure(namespace, &log10,   "math.log10"),
			"hypot"d,    new MDClosure(namespace, &hypot,   "math.hypot"),
			"lgamma"d,   new MDClosure(namespace, &lgamma,  "math.lgamma"),
			"gamma"d,    new MDClosure(namespace, &gamma,   "math.gamma"),
			"ceil"d,     new MDClosure(namespace, &ceil,    "math.ceil"),
			"floor"d,    new MDClosure(namespace, &floor,   "math.floor"),
			"round"d,    new MDClosure(namespace, &round,   "math.round"),
			"trunc"d,    new MDClosure(namespace, &trunc,   "math.trunc"),
			"isNan"d,    new MDClosure(namespace, &isNan,   "math.isNan"),
			"isInf"d,    new MDClosure(namespace, &isInf,   "math.isInf"),
			"sign"d,     new MDClosure(namespace, &sign,    "math.sign"),
			"rand"d,     new MDClosure(namespace, &rand,    "math.rand")
		);
	}

	static int getInt(MDState s, uint i)
	{
		if(s.isParam!("int")(i))
			return s.getIntParam(i);
		else
			s.throwRuntimeException("Expected 'int', not '%s'", s.getParam(i).typeString());
	}
	
	static float getFloat(MDState s, uint i)
	{
		if(s.isParam!("int")(i))
			return s.getIntParam(i);
		else if(s.isParam!("float")(i))
			return s.getFloatParam(i);
		else
			s.throwRuntimeException("Expected 'int' or 'float', not '%s'", s.getParam(i).typeString());
	}

	int abs(MDState s)
	{
		if(s.isParam!("int")(0))
			s.push(math.abs(s.getIntParam(0)));
		else if(s.isParam!("float")(0))
			s.push(math.abs(s.getFloatParam(0)));
		else
			s.throwRuntimeException("Expected 'int' or 'float', not '%s'", s.getParam(0).typeString());
			
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
		if(s.isParam!("int")(0))
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
		
		if(s.isParam!("int")(1))
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
				s.push(cast(uint)random.rand() % s.getIntParam(0));
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

public void init()
{
	MDNamespace namespace = new MDNamespace("math"d, MDGlobalState().globals);
	new MathLib(namespace);
	MDGlobalState().setGlobal("math"d, namespace);
}