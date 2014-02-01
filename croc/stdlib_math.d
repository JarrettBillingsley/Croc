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

module croc.stdlib_math;

import tango.math.GammaFunction;
import tango.math.IEEE;
import tango.math.Math;
import tango.math.random.Kiss;

alias tango.math.IEEE.isInfinity ieee_isInfinity;
alias tango.math.IEEE.isNaN ieee_isNaN;
alias tango.math.Math.abs math_abs;
alias tango.math.Math.acos math_acos;
alias tango.math.Math.asin math_asin;
alias tango.math.Math.atan math_atan;
alias tango.math.Math.atan2 math_atan2;
alias tango.math.Math.cbrt math_cbrt;
alias tango.math.Math.ceil math_ceil;
alias tango.math.Math.cos math_cos;
alias tango.math.Math.E math_E;
alias tango.math.Math.exp math_exp;
alias tango.math.Math.floor math_floor;
alias tango.math.Math.hypot math_hypot;
alias tango.math.Math.log math_log;
alias tango.math.Math.log10 math_log10;
alias tango.math.Math.log2 math_log2;
alias tango.math.Math.PI math_PI;
alias tango.math.Math.pow math_pow;
alias tango.math.Math.round math_round;
alias tango.math.Math.sin math_sin;
alias tango.math.Math.sqrt math_sqrt;
alias tango.math.Math.tan math_tan;
alias tango.math.Math.trunc math_trunc;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_library;
import croc.types;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initMathLib(CrocThread* t)
{
	makeModule(t, "math", function uword(CrocThread* t)
	{
		pushFloat(t, math_E);              newGlobal(t, "e");
		pushFloat(t, math_PI);             newGlobal(t, "pi");
		pushFloat(t, crocfloat.nan);       newGlobal(t, "nan");
		pushFloat(t, crocfloat.infinity);  newGlobal(t, "infinity");
		pushInt(t, crocint.sizeof);        newGlobal(t, "intSize");
		pushInt(t, crocint.min);           newGlobal(t, "intMin");
		pushInt(t, crocint.max);           newGlobal(t, "intMax");
		pushInt(t, crocfloat.sizeof);      newGlobal(t, "floatSize");
		pushFloat(t, crocfloat.min);       newGlobal(t, "floatMin");
		pushFloat(t, crocfloat.max);       newGlobal(t, "floatMax");

		registerGlobals(t, _globalFuncs);
		return 0;
	});

	importModule(t, "math");

	version(CrocBuiltinDocs)
	{
		scope doc = new CrocDoc(t, __FILE__);
		doc.push(Docs("module", "math",
		`This is a basic math library, providing many of the functions which are available in D or C99. If you pass an
		integer where a floating point number would be needed, it will be converted to a float automatically. `));

		docFields(t, doc, _globalFuncDocs);
		doc.pop(-1);
	}

	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

const RegisterFunc[] _globalFuncs =
[
	{"abs",    &_abs,    maxParams: 1  },
	{"sin",    &_sin,    maxParams: 1  },
	{"cos",    &_cos,    maxParams: 1  },
	{"tan",    &_tan,    maxParams: 1  },
	{"asin",   &_asin,   maxParams: 1  },
	{"acos",   &_acos,   maxParams: 1  },
	{"atan",   &_atan,   maxParams: 1  },
	{"atan2",  &_atan2,  maxParams: 2  },
	{"sqrt",   &_sqrt,   maxParams: 1  },
	{"cbrt",   &_cbrt,   maxParams: 1  },
	{"pow",    &_pow,    maxParams: 2  },
	{"exp",    &_exp,    maxParams: 1  },
	{"ln",     &_ln,     maxParams: 1  },
	{"log2",   &_log2,   maxParams: 1  },
	{"log10",  &_log10,  maxParams: 1  },
	{"hypot",  &_hypot,  maxParams: 2  },
	{"lgamma", &_lgamma, maxParams: 1  },
	{"gamma",  &_gamma,  maxParams: 1  },
	{"ceil",   &_ceil,   maxParams: 1  },
	{"floor",  &_floor,  maxParams: 1  },
	{"round",  &_round,  maxParams: 1  },
	{"trunc",  &_trunc,  maxParams: 1  },
	{"isNan",  &_isNan,  maxParams: 1  },
	{"isInf",  &_isInf,  maxParams: 1  },
	{"sign",   &_sign,   maxParams: 1  },
	{"rand",   &_rand,   maxParams: 2  },
	{"frand",  &_frand,  maxParams: 2  },
	{"max",    &_max                   },
	{"min",    &_min                   },
];

uword _abs(CrocThread* t)
{
	checkNumParam(t, 1);

	if(isInt(t, 1))
		pushInt(t, math_abs(getInt(t, 1)));
	else
		pushFloat(t, math_abs(getFloat(t, 1)));

	return 1;
}

uword _sin(CrocThread* t)
{
	pushFloat(t, math_sin(checkNumParam(t, 1)));
	return 1;
}

uword _cos(CrocThread* t)
{
	pushFloat(t, math_cos(checkNumParam(t, 1)));
	return 1;
}

uword _tan(CrocThread* t)
{
	pushFloat(t, math_tan(checkNumParam(t, 1)));
	return 1;
}

uword _asin(CrocThread* t)
{
	pushFloat(t, math_asin(checkNumParam(t, 1)));
	return 1;
}

uword _acos(CrocThread* t)
{
	pushFloat(t, math_acos(checkNumParam(t, 1)));
	return 1;
}

uword _atan(CrocThread* t)
{
	pushFloat(t, math_atan(checkNumParam(t, 1)));
	return 1;
}

uword _atan2(CrocThread* t)
{
	pushFloat(t, math_atan2(checkNumParam(t, 1), checkNumParam(t, 2)));
	return 1;
}

uword _sqrt(CrocThread* t)
{
	pushFloat(t, math_sqrt(checkNumParam(t, 1)));
	return 1;
}

uword _cbrt(CrocThread* t)
{
	pushFloat(t, math_cbrt(checkNumParam(t, 1)));
	return 1;
}

uword _pow(CrocThread* t)
{
	auto base = checkNumParam(t, 1);
	auto exp = checkNumParam(t, 2);

	if(isInt(t, 2))
		pushFloat(t, math_pow(cast(real)base, cast(uint)getInt(t, 2)));
	else
		pushFloat(t, math_pow(base, exp));

	return 1;
}

uword _exp(CrocThread* t)
{
	pushFloat(t, math_exp(checkNumParam(t, 1)));
	return 1;
}

uword _ln(CrocThread* t)
{
	pushFloat(t, math_log(checkNumParam(t, 1)));
	return 1;
}

uword _log2(CrocThread* t)
{
	pushFloat(t, math_log2(checkNumParam(t, 1)));
	return 1;
}

uword _log10(CrocThread* t)
{
	pushFloat(t, math_log10(checkNumParam(t, 1)));
	return 1;
}

uword _hypot(CrocThread* t)
{
	pushFloat(t, math_hypot(checkNumParam(t, 1), checkNumParam(t, 2)));
	return 1;
}

uword _lgamma(CrocThread* t)
{
	pushFloat(t, logGamma(checkNumParam(t, 1)));
	return 1;
}

uword _gamma(CrocThread* t)
{
	pushFloat(t, .gamma(checkNumParam(t, 1)));
	return 1;
}

uword _ceil(CrocThread* t)
{
	pushFloat(t, math_ceil(checkNumParam(t, 1)));
	return 1;
}

uword _floor(CrocThread* t)
{
	pushFloat(t, math_floor(checkNumParam(t, 1)));
	return 1;
}

uword _round(CrocThread* t)
{
	pushInt(t, cast(crocint)math_round(checkNumParam(t, 1)));
	return 1;
}

uword _trunc(CrocThread* t)
{
	pushInt(t, cast(crocint)math_trunc(checkNumParam(t, 1)));
	return 1;
}

uword _isNan(CrocThread* t)
{
	pushBool(t, cast(bool)ieee_isNaN(checkNumParam(t, 1)));
	return 1;
}

uword _isInf(CrocThread* t)
{
	pushBool(t, cast(bool)ieee_isInfinity(checkNumParam(t, 1)));
	return 1;
}

uword _sign(CrocThread* t)
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

uword _rand(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	// uint is the return type of Kiss.toInt
	static if(uint.sizeof < crocint.sizeof)
	{
		crocint num = Kiss.instance.toInt();
		num |= (cast(ulong)Kiss.instance.toInt()) << 32;
	}
	else
		crocint num = Kiss.instance.toInt();

	switch(numParams)
	{
		case 0:
			pushInt(t, num);
			break;

		case 1:
			auto max = checkIntParam(t, 1);

			if(max == 0)
				throwStdException(t, "RangeError", "Maximum value may not be 0");

			pushInt(t, cast(uword)num % max);
			break;

		default:
			auto lo = checkIntParam(t, 1);
			auto hi = checkIntParam(t, 2);

			if(hi == lo)
				throwStdException(t, "ValueError", "Low and high values must be different");

			pushInt(t, (cast(uword)num % (hi - lo)) + lo);
			break;
	}

	return 1;
}

uword _frand(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	auto num = cast(crocfloat)Kiss.instance.toInt() / uint.max;

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

uword _max(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	switch(numParams)
	{
		case 0:
			throwStdException(t, "ParamError", "At least one parameter required");

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

uword _min(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	switch(numParams)
	{
		case 0:
			throwStdException(t, "ParamError", "At least one parameter required");

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

const Docs[] _globalFuncDocs =
[
	{kind: "variable", name: "e",
	extra: [Extra("protection", "global")],
	docs:
	`The constant \tt{e} (2.7182818...).`},

	{kind: "variable", name: "pi",
	extra: [Extra("protection", "global")],
	docs:
	`The constant \tt{pi} (3.1415926...).`},

	{kind: "variable", name: "nan",
	extra: [Extra("protection", "global")],
	docs:
	`A value which means "not a number". This is returned by some math functions to indicate that the result is
	nonsensical.`},

	{kind: "variable", name: "infinity",
	extra: [Extra("protection", "global")],
	docs:
	`Positive infinity. This (and its negative) is returned by some of the math functions and math operations to
	indicate that the result is too big to fit into a floating point number. `},

	{kind: "variable", name: "intSize",
	extra: [Extra("protection", "global")],
	docs:
	`The size, in bytes, of the Croc \tt{int} type. By default, this is 8. Nonstandard implementations may differ.`},

	{kind: "variable", name: "intMin",
	extra: [Extra("protection", "global")],
	docs:
	`The smallest (most negative) number the Croc \tt{int} type can hold.`},

	{kind: "variable", name: "intMax",
	extra: [Extra("protection", "global")],
	docs:
	`The largest (most positive) number the Croc \tt{int} type can hold.`},

	{kind: "variable", name: "floatSize",
	extra: [Extra("protection", "global")],
	docs:
	`The size, in bytes, of the Croc \tt{float} type. By default, this is 8. Nonstandard implementations may differ.`},

	{kind: "variable", name: "floatMin",
	extra: [Extra("protection", "global")],
	docs:
	`The smallest positive non-zero number the Croc \tt{float} type can hold.`},

	{kind: "variable", name: "floatMax",
	extra: [Extra("protection", "global")],
	docs:
	`The largest positive non-infinity number the Croc \tt{float} type can hold.`},

	{kind: "function", name: "abs",
	params: [Param("n", "int|float")],
	docs:
	`\returns the absolute value of the number. The returned value will be the same type as was passed in.`},

	{kind: "function", name: "sin",
	params: [Param("n", "int|float")],
	docs:
	`\returns the sine of the angle, which is assumed to be in radians. Always returns a \tt{float}.`},

	{kind: "function", name: "cos",
	params: [Param("n", "int|float")],
	docs:
	`\returns the cosine of the angle, which is assumed to be in radians. Always returns a \tt{float}.`},

	{kind: "function", name: "tan",
	params: [Param("n", "int|float")],
	docs:
	`\returns the tangent of the angle, which is assumed to be in radians. Always returns a \tt{float}.`},

	{kind: "function", name: "asin",
	params: [Param("n", "int|float")],
	docs:
	`\returns the inverse sine of the number. Always returns a \tt{float}. Returns \link{nan} if the input is outside
	the range [-1.0, 1.0].`},

	{kind: "function", name: "acos",
	params: [Param("n", "int|float")],
	docs:
	`\returns the inverse cosine of the number. Always returns a \tt{float}. Returns \link{nan} if the input is outside
	the range [-1.0, 1.0].`},

	{kind: "function", name: "atan",
	params: [Param("n", "int|float")],
	docs:
	`\returns the inverse tangent of the number. Always returns a \tt{float} in the range [-pi / 2, pi / 2]. This works
	for all inputs in the range (-infinity, infinity).`},

	{kind: "function", name: "atan2",
	params: [Param("y", "int|float"), Param("x", "int|float")],
	docs:
	`Normally, when you use the inverse tangent, you pass it \tt{y/x}, given that \tt{y} and \tt{x} are coordinates on a
	Cartesian plane. However, this causes information about which quadrant the result should be in to be lost. Thus,
	\link{atan} will map two different angles to the same return value. \tt{atan2} allows you to pass in the two values
	separately, and so it is able to determine which quadrant the result should be in. The return value will then be in
	the range [-pi, pi]. This works for all inputs in the range (-infinity, infinity). The result when both inputs are 0
	is 0.`},

	{kind: "function", name: "sqrt",
	params: [Param("n", "int|float")],
	docs:
	`\returns the square root of the input. Returns \tt{-\link{nan}} if a number less than 0 is given. The result is
	always a float.`},

	{kind: "function", name: "cbrt",
	params: [Param("n", "int|float")],
	docs:
	`\returns the cube root of the input. The result is always a float. This works for all inputs in the range
	(-infinity, infinity).`},

	{kind: "function", name: "pow",
	params: [Param("base", "int|float"), Param("power", "int|float")],
	docs:
	`\returns \tt{base} raised to the \tt{power} power. Fractional and negative powers are legal as well. Always returns
	a float.`},

	{kind: "function", name: "exp",
	params: [Param("n", "int|float")],
	docs:
	`\returns \em{e}\sup{n}. Always returns a float.`},

	{kind: "function", name: "ln",
	params: [Param("n", "int|float")],
	docs:
	`\returns the natural logarithm of \tt{n}. This is the inverse of \link{exp}. Always returns a float.`},

	{kind: "function", name: "log2",
	params: [Param("n", "int|float")],
	docs:
	`\returns the base-2 logarithm of \tt{n}. This is the inverse if 2\sup{n}. Always returns a float.`},

	{kind: "function", name: "log10",
	params: [Param("n", "int|float")],
	docs:
	`\returns the base-10 logarithm of \tt{n}. This is the inverse if 10\sup{n}. Always returns a float.`},

	{kind: "function", name: "hypot",
	params: [Param("dx", "int|float"), Param("dy", "int|float")],
	docs:
	`\returns the length of the hypotenuse of a right triangle given sides of length \tt{dx} and \tt{dy}. This is the
	same as calculating sqrt(x\sup{2} + y\sup{2}).`},

	{kind: "function", name: "gamma",
	params: [Param("n", "int|float")],
	docs:
	`\returns the gamma function of the input. The gamma function is like factorial (!) function but extended to all
	real numbers. This function is slightly different from factorial in that if you pass it an integer \tt{n}, you will
	get \tt{(n - 1)!}. So \tt{math.gamma(5)} gives \tt{4! = 24}.`},

	{kind: "function", name: "lgamma",
	params: [Param("n", "int|float")],
	docs:
	`\returns the natural log of the \link{gamma} function of the input.`},

	{kind: "function", name: "ceil",
	params: [Param("n", "int|float")],
	docs:
	`\returns the next integer closer to positive infinity than the input. If the input is already an integer, returns
	that. Always returns a float.`},

	{kind: "function", name: "floor",
	params: [Param("n", "int|float")],
	docs:
	`\returns the next integer closer to negative infinity than the input. If the input is already an integer, returns
	that. Always returns a float.`},

	{kind: "function", name: "round",
	params: [Param("n", "int|float")],
	docs:
	`\returns input rounded to the nearest integer. Always returns an int.`},

	{kind: "function", name: "trunc",
	params: [Param("n", "int|float")],
	docs:
	`\returns the integral part of the number, simply discarding any digits after the decimal point. Always returns an
	int.`},

	{kind: "function", name: "isNan",
	params: [Param("n", "int|float")],
	docs:
	`\returns \tt{true} if the input is \link{nan}, and \tt{false} otherwise.`},

	{kind: "function", name: "isInf",
	params: [Param("n", "int|float")],
	docs:
	`\returns \tt{true} if the input is positive or negative infinity, and \tt{false} otherwise.`},

	{kind: "function", name: "sign",
	params: [Param("n", "int|float")],
	docs:
	`\returns an integer representing the sign of the number. If \tt{n < 0}, returns -1; if \tt{n > 0}, returns 1; and
	if \tt{n == 0}, returns 0.`},

	{kind: "function", name: "rand",
	params: [Param("a", "int", "null"), Param("b", "int", "null")],
	docs:
	`\returns a random integer.

	If no parameters are given, the value will be a random integer in the range [-2\sup{63}, 2\sup{63}).

	If one parameter is given, it will act as the upper noninclusive bound on the values returned, so \tt{math.rand(10)}
	will return integers in the range [0, 10). Passing a single negative number, such as \tt{math.rand(-10)} won't work
	properly; instead use \tt{-math.rand(10)} to get numbers in the range (-10, 0].

	If two parameters are given, the first is the lower inclusive bound, and the second is the upper noninclusive bound.
	So \tt{math.rand(-10, -5)} will return numbers in the range [-10, -5).

	\throws[exceptions.RangeError] if only one parameter is passed, and it is 0.
	\throws[exceptions.ValueError] if two parameters are passed, and they are equal.`},

	{kind: "function", name: "frand",
	params: [Param("a", "int|float", "null"), Param("b", "int|float", "null")],
	docs:
	`\returns a random float.

	If no parameters are given, the value will be a random float in the range [0.0, 1.0]. Note that the upper bound is
	inclusive!

	If one parameter is given, it will act as the upper \em{inclusive} bound on the values returned, so
	\tt{math.frand(10)} will return floats in the range [0.0, 10.0]. Passing a single negative number, such as
	\tt{math.frand(-10)} \em{does} work properly and will give numbers in the range [-10.0, 0.0].

	If two parameters are given, the first is the lower bound and the second the upper, both inclusive. So
	\tt{math.frand(-10, -5)} will return numbers in the range [-10.0, -5.0].`},

	{kind: "function", name: "max",
	params: [Param("vararg", "vararg")],
	docs:
	`\returns the largest value of its parameters. Note that this is a generic function; the parameters don't have to be
	numbers, they can be any comparable type.

	\throws[exceptions.ParamError] if no parameters are passed.`},

	{kind: "function", name: "min",
	params: [Param("vararg", "vararg")],
	docs:
	`\returns the smallest value of its parameters. Note that this is a generic function; the parameters don't have to
	be numbers, they can be any comparable type.

	\throws[exceptions.ParamError] if no parameters are passed.`},
];