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

import math = tango.math.Math;
import tango.math.GammaFunction;
import tango.math.Random;
import tango.math.IEEE;

import minid.ex;
import minid.interpreter;
import minid.types;

struct MathLib
{
static:
	public void init(MDThread* t)
	{
		pushGlobal(t, "modules");
		field(t, -1, "customLoaders");
		
		newFunction(t, function uword(MDThread* t, uword numParams)
		{
			pushFloat(t, math.E);           newGlobal(t, "e");
			pushFloat(t, math.PI);          newGlobal(t, "pi");
			pushFloat(t, mdfloat.nan);      newGlobal(t, "nan");
			pushFloat(t, mdfloat.infinity); newGlobal(t, "infinity");

			pushInt(t, mdint.sizeof);       newGlobal(t, "intSize");
			pushInt(t, mdint.min);          newGlobal(t, "intMin");
			pushInt(t, mdint.max);          newGlobal(t, "intMax");

			pushInt(t, mdfloat.sizeof);     newGlobal(t, "floatSize");
			pushFloat(t, mdfloat.min);      newGlobal(t, "floatMin");
			pushFloat(t, mdfloat.max);      newGlobal(t, "floatMax");

// 			newFunction(t, &abs, "abs");       newGlobal(t, "abs");
// 			newFunction(t, &sin, "sin");       newGlobal(t, "sin");
// 			newFunction(t, &cos, "cos");       newGlobal(t, "cos");
// 			newFunction(t, &tan, "tan");       newGlobal(t, "tan");
// 			newFunction(t, &asin, "asin");     newGlobal(t, "asin");
// 			newFunction(t, &acos, "acos");     newGlobal(t, "acos");
// 			newFunction(t, &atan, "atan");     newGlobal(t, "atan");
// 			newFunction(t, &atan2, "atan2");   newGlobal(t, "atan2");
// 			newFunction(t, &sqrt, "sqrt");     newGlobal(t, "sqrt");
// 			newFunction(t, &cbrt, "cbrt");     newGlobal(t, "cbrt");
// 			newFunction(t, &pow, "pow");       newGlobal(t, "pow");
// 			newFunction(t, &exp, "exp");       newGlobal(t, "exp");
// 			newFunction(t, &ln, "ln");         newGlobal(t, "ln");
// 			newFunction(t, &log2, "log2");     newGlobal(t, "log2");
// 			newFunction(t, &log10, "log10");   newGlobal(t, "log10");
// 			newFunction(t, &hypot, "hypot");   newGlobal(t, "hypot");
// 			newFunction(t, &lgamma, "lgamma"); newGlobal(t, "lgamma");
// 			newFunction(t, &gamma, "gamma");   newGlobal(t, "gamma");
// 			newFunction(t, &ceil, "ceil");     newGlobal(t, "ceil");
// 			newFunction(t, &floor, "floor");   newGlobal(t, "floor");
// 			newFunction(t, &round, "round");   newGlobal(t, "round");
// 			newFunction(t, &trunc, "trunc");   newGlobal(t, "trunc");
// 			newFunction(t, &isNan, "isNan");   newGlobal(t, "isNan");
// 			newFunction(t, &isInf, "isInf");   newGlobal(t, "isInf");
// 			newFunction(t, &sign, "sign");     newGlobal(t, "sign");
// 			newFunction(t, &rand, "rand");     newGlobal(t, "rand");
// 			newFunction(t, &frand, "frand");   newGlobal(t, "frand");
// 			newFunction(t, &max, "max");       newGlobal(t, "max");
// 			newFunction(t, &min, "min");       newGlobal(t, "min");

			return 0;
		}, "math");

		fielda(t, -2, "math");
		pop(t);

		importModule(t, "math");
	}

/+
	mdfloat getFloat(MDState s, uint i)
	{
		if(s.isParam!("int")(i))
			return s.getParam!(int)(i);
		else if(s.isParam!("float")(i))
			return s.getParam!(mdfloat)(i);
		else
			s.throwRuntimeException("Expected 'int' or 'float', not '{}'", s.getParam(i).typeString());
	}

	int abs(MDState s, uint numParams)
	{
		if(s.isParam!("int")(0))
			s.push(math.abs(s.getParam!(int)(0)));
		else if(s.isParam!("float")(0))
			s.push(math.abs(s.getParam!(mdfloat)(0)));
		else
			s.throwRuntimeException("Expected 'int' or 'float', not '{}'", s.getParam(0u).typeString());

		return 1;
	}
	
	int sin(MDState s, uint numParams)
	{
		s.push(math.sin(getFloat(s, 0)));
		return 1;
	}
	
	int cos(MDState s, uint numParams)
	{
		s.push(math.cos(getFloat(s, 0)));
		return 1;
	}
	
	int tan(MDState s, uint numParams)
	{
		s.push(math.tan(getFloat(s, 0)));
		return 1;
	}
	
	int asin(MDState s, uint numParams)
	{
		s.push(math.asin(getFloat(s, 0)));
		return 1;
	}
	
	int acos(MDState s, uint numParams)
	{
		s.push(math.acos(getFloat(s, 0)));
		return 1;
	}
	
	int atan(MDState s, uint numParams)
	{
		s.push(math.atan(getFloat(s, 0)));
		return 1;
	}
	
	int atan2(MDState s, uint numParams)
	{
		s.push(math.atan2(getFloat(s, 0), getFloat(s, 1)));
		return 1;
	}
	
	int sqrt(MDState s, uint numParams)
	{
		s.push(math.sqrt(getFloat(s, 0)));
		return 1;
	}
	
	int cbrt(MDState s, uint numParams)
	{
		s.push(math.cbrt(getFloat(s, 0)));
		return 1;
	}
	
	int exp(MDState s, uint numParams)
	{
		s.push(math.exp(getFloat(s, 0)));
		return 1;
	}
	
	int ln(MDState s, uint numParams)
	{
		s.push(math.log(getFloat(s, 0)));
		return 1;
	}
	
	int log2(MDState s, uint numParams)
	{
		s.push(math.log2(getFloat(s, 0)));
		return 1;
	}
	
	int log10(MDState s, uint numParams)
	{
		s.push(math.log10(getFloat(s, 0)));
		return 1;
	}
	
	int hypot(MDState s, uint numParams)
	{
		s.push(math.hypot(getFloat(s, 0), getFloat(s, 1)));
		return 1;
	}
	
	int lgamma(MDState s, uint numParams)
	{
		s.push(logGamma(getFloat(s, 0)));
		return 1;
	}

	int gamma(MDState s, uint numParams)
	{
		s.push(.gamma(getFloat(s, 0)));
		return 1;
	}
	
	int ceil(MDState s, uint numParams)
	{
		s.push(math.ceil(getFloat(s, 0)));
		return 1;
	}
	
	int floor(MDState s, uint numParams)
	{
		s.push(math.floor(getFloat(s, 0)));
		return 1;
	}
	
	int round(MDState s, uint numParams)
	{
		s.push(cast(int)math.round(getFloat(s, 0)));
		return 1;
	}
	
	int trunc(MDState s, uint numParams)
	{
		s.push(cast(int)math.trunc(getFloat(s, 0)));
		return 1;
	}
	
	int isNan(MDState s, uint numParams)
	{
		s.push(cast(bool)math.isNaN(getFloat(s, 0)));
		return 1;
	}

	int isInf(MDState s, uint numParams)
	{
		s.push(cast(bool)math.isInfinity(getFloat(s, 0)));
		return 1;
	}
	
	int sign(MDState s, uint numParams)
	{
		if(s.isParam!("int")(0))
		{
			int val = s.getParam!(int)(0);

			if(val < 0)
				s.push(-1);
			else if(val > 0)
				s.push(1);
			else
				s.push(0);
		}
		else
		{
			mdfloat val = s.getParam!(mdfloat)(0);

			if(val < 0)
				s.push(-1);
			else if(val > 0)
				s.push(1);
			else
				s.push(0);
		}
		
		return 1;
	}
	
	int pow(MDState s, uint numParams)
	{
		mdfloat base = getFloat(s, 0);
		
		if(s.isParam!("int")(1))
			s.push(math.pow(cast(real)base, s.getParam!(int)(1)));
		else
			s.push(math.pow(base, getFloat(s, 1)));
			
		return 1;
	}

	int rand(MDState s, uint numParams)
	{
		uint num = Random.shared.next();

		switch(numParams)
		{
			case 0:
				s.push(cast(int)num);
				break;

			case 1:
				auto max = s.getParam!(int)(0);

				if(max == 0)
					s.throwRuntimeException("Maximum value may not be 0");

				s.push(cast(uint)num % max);
				break;

			default:
				int lo = s.getParam!(int)(0);
				int hi = s.getParam!(int)(1);
				
				if(hi == lo)
					s.throwRuntimeException("Low and high values must be different");

				s.push(cast(int)(num % (hi - lo)) + lo);
				break;
		}
		
		return 1;
	}
	
	int frand(MDState s, uint numParams)
	{
		auto num = cast(mdfloat)Random.shared.next() / uint.max;

		switch(numParams)
		{
			case 0:
				s.push(num);
				break;

			case 1:
				s.push(num * s.getParam!(mdfloat)(0));
				break;

			default:
				auto lo = s.getParam!(mdfloat)(0);
				auto hi = s.getParam!(mdfloat)(1);

				s.push((num * (hi - lo)) + lo);
				break;
		}
		
		return 1;
	}
	
	int max(MDState s, uint numParams)
	{
		switch(numParams)
		{
			case 0:
				s.throwRuntimeException("At least one parameter required");
				
			case 1:
				break;
				
			case 2:
				if(s.cmp(s.getParam(0u), s.getParam(1u)) > 0)
					s.pop();
				break;

			default:
				auto m = s.getParam(0u);

				for(uint i = 1; i < numParams; i++)
				{
					auto v = s.getParam(i);

					if(s.cmp(v, m) > 0)
						m = v;
				}
				
				s.push(m);
				break;
		}
		
		return 1;
	}
	
	int min(MDState s, uint numParams)
	{
		switch(numParams)
		{
			case 0:
				s.throwRuntimeException("At least one parameter required");

			case 1:
				break;

			case 2:
				if(s.cmp(s.getParam(0u), s.getParam(1u)) < 0)
					s.pop();
				break;

			default:
				auto m = s.getParam(0u);

				for(uint i = 1; i < numParams; i++)
				{
					auto v = s.getParam(i);

					if(s.cmp(v, m) < 0)
						m = v;
				}

				s.push(m);
				break;
		}

		return 1;
	}
+/
}