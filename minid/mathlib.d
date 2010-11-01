/******************************************************************************
This module contains the 'math' standard library.

License:
Copyright (c) 2008 Jarrett Billingsley

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
import ieee = tango.math.IEEE;
import tango.math.random.Kiss;

import minid.ex;
import minid.interpreter;
import minid.types;

private void register(MDThread* t, char[] name, NativeFunc func, uword numUpvals = 0)
{
	newFunction(t, func, name, numUpvals);
	newGlobal(t, name);
}

struct MathLib
{
static:
	public void init(MDThread* t)
	{
		makeModule(t, "math", function uword(MDThread* t, uword numParams)
		{
			pushFloat(t, math.E);              newGlobal(t, "e");
			pushFloat(t, math.PI);             newGlobal(t, "pi");
			pushFloat(t, mdfloat.nan);         newGlobal(t, "nan");
			pushFloat(t, mdfloat.infinity);    newGlobal(t, "infinity");

			pushInt(t, mdint.sizeof);          newGlobal(t, "intSize");
			pushInt(t, mdint.min);             newGlobal(t, "intMin");
			pushInt(t, mdint.max);             newGlobal(t, "intMax");

			pushInt(t, mdfloat.sizeof);        newGlobal(t, "floatSize");
			pushFloat(t, mdfloat.min);         newGlobal(t, "floatMin");
			pushFloat(t, mdfloat.max);         newGlobal(t, "floatMax");
			
			register(t, "abs", &abs);
			register(t, "sin", &sin);
			register(t, "cos", &cos);
			register(t, "tan", &tan);
			register(t, "asin", &asin);
			register(t, "acos", &acos);
			register(t, "atan", &atan);
			register(t, "atan2", &atan2);
			register(t, "sqrt", &sqrt);
			register(t, "cbrt", &cbrt);
			register(t, "pow", &pow);
			register(t, "exp", &exp);
			register(t, "ln", &ln);
			register(t, "log2", &log2);
			register(t, "log10", &log10);
			register(t, "hypot", &hypot);
			register(t, "lgamma", &lgamma);
			register(t, "gamma", &gamma);
			register(t, "ceil", &ceil);
			register(t, "floor", &floor);
			register(t, "round", &round);
			register(t, "trunc", &trunc);
			register(t, "isNan", &isNan);
			register(t, "isInf", &isInf);
			register(t, "sign", &sign);
			register(t, "rand", &rand);
			register(t, "frand", &frand);
			register(t, "max", &max);
			register(t, "min", &min);

			return 0;
		});

		importModuleNoNS(t, "math");
	}

	uword abs(MDThread* t, uword numParams)
	{
		checkNumParam(t, 1);

		if(isInt(t, 1))
			pushInt(t, math.abs(getInt(t, 1)));
		else
			pushFloat(t, math.abs(getFloat(t, 1)));

		return 1;
	}

	uword sin(MDThread* t, uword numParams)
	{
		pushFloat(t, math.sin(checkNumParam(t, 1)));
		return 1;
	}

	uword cos(MDThread* t, uword numParams)
	{
		pushFloat(t, math.cos(checkNumParam(t, 1)));
		return 1;
	}

	uword tan(MDThread* t, uword numParams)
	{
		pushFloat(t, math.tan(checkNumParam(t, 1)));
		return 1;
	}

	uword asin(MDThread* t, uword numParams)
	{
		pushFloat(t, math.asin(checkNumParam(t, 1)));
		return 1;
	}

	uword acos(MDThread* t, uword numParams)
	{
		pushFloat(t, math.acos(checkNumParam(t, 1)));
		return 1;
	}

	uword atan(MDThread* t, uword numParams)
	{
		pushFloat(t, math.atan(checkNumParam(t, 1)));
		return 1;
	}

	uword atan2(MDThread* t, uword numParams)
	{
		pushFloat(t, math.atan2(checkNumParam(t, 1), checkNumParam(t, 2)));
		return 1;
	}

	uword sqrt(MDThread* t, uword numParams)
	{
		pushFloat(t, math.sqrt(checkNumParam(t, 1)));
		return 1;
	}

	uword cbrt(MDThread* t, uword numParams)
	{
		pushFloat(t, math.cbrt(checkNumParam(t, 1)));
		return 1;
	}

	uword exp(MDThread* t, uword numParams)
	{
		pushFloat(t, math.exp(checkNumParam(t, 1)));
		return 1;
	}

	uword ln(MDThread* t, uword numParams)
	{
		pushFloat(t, math.log(checkNumParam(t, 1)));
		return 1;
	}

	uword log2(MDThread* t, uword numParams)
	{
		pushFloat(t, math.log2(checkNumParam(t, 1)));
		return 1;
	}

	uword log10(MDThread* t, uword numParams)
	{
		pushFloat(t, math.log10(checkNumParam(t, 1)));
		return 1;
	}

	uword hypot(MDThread* t, uword numParams)
	{
		pushFloat(t, math.hypot(checkNumParam(t, 1), checkNumParam(t, 2)));
		return 1;
	}

	uword lgamma(MDThread* t, uword numParams)
	{
		pushFloat(t, logGamma(checkNumParam(t, 1)));
		return 1;
	}

	uword gamma(MDThread* t, uword numParams)
	{
		pushFloat(t, .gamma(checkNumParam(t, 1)));
		return 1;
	}

	uword ceil(MDThread* t, uword numParams)
	{
		pushFloat(t, math.ceil(checkNumParam(t, 1)));
		return 1;
	}

	uword floor(MDThread* t, uword numParams)
	{
		pushFloat(t, math.floor(checkNumParam(t, 1)));
		return 1;
	}

	uword round(MDThread* t, uword numParams)
	{
		pushInt(t, cast(mdint)math.round(checkNumParam(t, 1)));
		return 1;
	}

	uword trunc(MDThread* t, uword numParams)
	{
		pushInt(t, cast(mdint)math.trunc(checkNumParam(t, 1)));
		return 1;
	}

	uword isNan(MDThread* t, uword numParams)
	{
		pushBool(t, cast(bool)ieee.isNaN(checkNumParam(t, 1)));
		return 1;
	}

	uword isInf(MDThread* t, uword numParams)
	{
		pushBool(t, cast(bool)ieee.isInfinity(checkNumParam(t, 1)));
		return 1;
	}

	uword sign(MDThread* t, uword numParams)
	{
		checkNumParam(t, 1);

		if(isInt(t, 1))
		{
			auto val = getInt(t, 1);

			if(val < 0)
				pushInt(t, -1);
			else if(val > 0)
				pushInt(t, 1);
			else
				pushInt(t, 0);
		}
		else
		{
			auto val = getFloat(t, 1);

			if(val < 0)
				pushInt(t, -1);
			else if(val > 0)
				pushInt(t, 1);
			else
				pushInt(t, 0);
		}

		return 1;
	}

	uword pow(MDThread* t, uword numParams)
	{
		auto base = checkNumParam(t, 1);
		auto exp = checkNumParam(t, 2);

		if(isInt(t, 2))
			pushFloat(t, math.pow(cast(real)base, cast(uint)getInt(t, 2)));
		else
			pushFloat(t, math.pow(base, exp));

		return 1;
	}

	uword rand(MDThread* t, uword numParams)
	{
		// uint is the return type of Kiss.toInt
		static if(uint.sizeof < mdint.sizeof)
		{
			mdint num = Kiss.instance.toInt();
			num |= (cast(ulong)Kiss.instance.toInt()) << 32;
		}
		else
			mdint num = Kiss.instance.toInt();

		switch(numParams)
		{
			case 0:
				pushInt(t, num);
				break;

			case 1:
				auto max = checkIntParam(t, 1);

				if(max == 0)
					throwException(t, "Maximum value may not be 0");

				pushInt(t, cast(uword)num % max);
				break;

			default:
				auto lo = checkIntParam(t, 1);
				auto hi = checkIntParam(t, 2);

				if(hi == lo)
					throwException(t, "Low and high values must be different");

				pushInt(t, (cast(uword)num % (hi - lo)) + lo);
				break;
		}

		return 1;
	}

	uword frand(MDThread* t, uword numParams)
	{
		auto num = cast(mdfloat)Kiss.instance.toInt() / uint.max;

		switch(numParams)
		{
			case 0:
				pushFloat(t, num);
				break;

			case 1:
				pushFloat(t, num * checkNumParam(t, 1));
				break;

			default:
				auto lo = checkNumParam(t, 1);
				auto hi = checkNumParam(t, 2);

				pushFloat(t, (num * (hi - lo)) + lo);
				break;
		}

		return 1;
	}

	uword max(MDThread* t, uword numParams)
	{
		switch(numParams)
		{
			case 0:
				throwException(t, "At least one parameter required");

			case 1:
				break;

			case 2:
				if(cmp(t, 1, 2) > 0)
					pop(t);
				break;

			default:
				word m = 1;

				for(uword i = 2; i <= numParams; i++)
					if(cmp(t, i, m) > 0)
						m = i;

				dup(t, m);
				break;
		}

		return 1;
	}

	uword min(MDThread* t, uword numParams)
	{
		switch(numParams)
		{
			case 0:
				throwException(t, "At least one parameter required");

			case 1:
				break;

			case 2:
				if(cmp(t, 1, 2) < 0)
					pop(t);
				break;

			default:
				word m = 1;

				for(uword i = 2; i <= numParams; i++)
					if(cmp(t, i, m) < 0)
						m = i;

				dup(t, m);
				break;
		}


		return 1;
	}
}