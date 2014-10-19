
#include <limits>
#include <cmath>
#include <stdlib.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{
const StdlibRegisterInfo _abs_info =
{
	Docstr(DFunc("abs") DParam("v", "int|float")
	R"(\returns the absolute value of the number. The returned value will be the same type as was passed in.)"),

	"abs", 1
};

word_t _abs(CrocThread* t)
{
	croc_ex_checkNumParam(t, 1);

	if(croc_isInt(t, 1))
	{
		auto v = croc_getInt(t, 1);
		croc_pushInt(t, v < 0 ? -v : v);
	}
	else
	{
		auto v = croc_getFloat(t, 1);
		croc_pushFloat(t, v < 0 ? -v : v);
	}

	return 1;
}

#define MATHFUNC1(NAME)\
	word_t _##NAME(CrocThread* t)\
	{ croc_pushFloat(t, NAME(croc_ex_checkNumParam(t, 1))); return 1; }

#define MATHFUNC2(NAME)\
	word_t _##NAME(CrocThread* t)\
	{ croc_pushFloat(t, NAME(croc_ex_checkNumParam(t, 1), croc_ex_checkNumParam(t, 2))); return 1; }

#define MATHFUNCRENAME(NAME, REALNAME)\
	word_t _##NAME(CrocThread* t)\
	{ croc_pushFloat(t, REALNAME(croc_ex_checkNumParam(t, 1))); return 1; }

#define IMATHFUNC(NAME)\
	word_t _i##NAME(CrocThread* t)\
	{ croc_pushInt(t, cast(crocint)NAME(croc_ex_checkNumParam(t, 1))); return 1; }

#define BOOLMATHFUNC(NAME, REALNAME)\
	word_t _##NAME(CrocThread* t)\
	{ croc_pushBool(t, REALNAME(croc_ex_checkNumParam(t, 1))); return 1; }

const StdlibRegisterInfo _sin_info =
{
	Docstr(DFunc("sin") DParam("v", "int|float")
	R"(\returns the sine of the angle, which is assumed to be in radians. Always returns a \tt{float}.)"),
	"sin", 1
};

MATHFUNC1(sin)

const StdlibRegisterInfo _cos_info =
{
	Docstr(DFunc("cos") DParam("v", "int|float")
	R"(\returns the cosine of the angle, which is assumed to be in radians. Always returns a \tt{float}.)"),
	"cos", 1
};

MATHFUNC1(cos)

const StdlibRegisterInfo _tan_info =
{
	Docstr(DFunc("tan") DParam("v", "int|float")
	R"(\returns the tangent of the angle, which is assumed to be in radians. Always returns a \tt{float}.)"),
	"tan", 1
};

MATHFUNC1(tan)

const StdlibRegisterInfo _asin_info =
{
	Docstr(DFunc("asin") DParam("v", "int|float")
	R"(\returns the inverse sine of the number. Always returns a \tt{float}. Returns \link{nan} if the input is outside
	the range [-1.0, 1.0].)"),
	"asin", 1
};

MATHFUNC1(asin)

const StdlibRegisterInfo _acos_info =
{
	Docstr(DFunc("acos") DParam("v", "int|float")
	R"(\returns the inverse cosine of the number. Always returns a \tt{float}. Returns \link{nan} if the input is
	outside the range [-1.0, 1.0].)"),
	"acos", 1
};

MATHFUNC1(acos)

const StdlibRegisterInfo _atan_info =
{
	Docstr(DFunc("atan") DParam("v", "int|float")
	R"(\returns the inverse tangent of the number. Always returns a \tt{float} in the range [-pi / 2, pi / 2]. This
	works for all inputs in the range (-infinity, infinity).)"),
	"atan", 1
};

MATHFUNC1(atan)

const StdlibRegisterInfo _atan2_info =
{
	Docstr(DFunc("atan2") DParam("dy", "int|float") DParam("dx", "int|float")
	R"(\returns the inverse tangent, extended to all four quadrants by passing the x and y distances separately.

	Normally, when you use the inverse tangent, you pass it \tt{dy/dx}, given that \tt{dy} and \tt{dx} are coordinates
	on a Cartesian plane. The problem is that this causes information about which quadrant the result should be in to be
	lost. Because of this, \link{atan} will map two different angles to the same return value. \tt{atan2} allows you to
	pass in the two values separately, so it can determine which quadrant the result should be in. The return value will
	then be in the range [-pi, pi]. This works for all inputs in the range (-infinity, infinity). The result when both
	inputs are 0 is 0.)"),
	"atan2", 2
};

MATHFUNC2(atan2)

const StdlibRegisterInfo _sqrt_info =
{
	Docstr(DFunc("sqrt") DParam("v", "int|float")
	R"(\returns the square root of the input. Returns \tt{-\link{nan}} if a number less than 0 is given. The result is
	always a float.)"),
	"sqrt", 1
};

MATHFUNC1(sqrt)

const StdlibRegisterInfo _cbrt_info =
{
	Docstr(DFunc("cbrt") DParam("v", "int|float")
	R"(\returns the cube root of the input. The result is always a float. This works for all inputs in the range
	(-infinity, infinity).)"),
	"cbrt", 1
};

MATHFUNC1(cbrt)

const StdlibRegisterInfo _pow_info =
{
	Docstr(DFunc("pow") DParam("base", "int|float") DParam("exp", "int|float")
	R"(\returns \tt{base} raised to the \tt{exp} power. Fractional and negative powers are legal as well. Always returns
	a float.)"),
	"pow", 2
};

MATHFUNC2(pow)

const StdlibRegisterInfo _exp_info =
{
	Docstr(DFunc("exp") DParam("v", "int|float")
	R"(\returns \em{e}\sup{v}. Always returns a float.)"),
	"exp", 1
};

MATHFUNC1(exp)

const StdlibRegisterInfo _ln_info =
{
	Docstr(DFunc("ln") DParam("v", "int|float")
	R"(\returns the natural logarithm of \tt{v}. This is the inverse of \link{exp}. Always returns a float.)"),
	"ln", 1
};

MATHFUNCRENAME(ln, log)

const StdlibRegisterInfo _log2_info =
{
	Docstr(DFunc("log2") DParam("v", "int|float")
	R"(\returns the base-2 logarithm of \tt{v}. This is the inverse if 2\sup{v}. Always returns a float.)"),
	"log2", 1
};

MATHFUNC1(log2)

const StdlibRegisterInfo _log10_info =
{
	Docstr(DFunc("log10") DParam("v", "int|float")
	R"(\returns the base-10 logarithm of \tt{v}. This is the inverse if 10\sup{v}. Always returns a float.)"),
	"log10", 1
};

MATHFUNC1(log10)

const StdlibRegisterInfo _hypot_info =
{
	Docstr(DFunc("hypot") DParam("dx", "int|float") DParam("dy", "int|float")
	R"(\returns the length of the hypotenuse of a right triangle given sides of length \tt{dx} and \tt{dy}. This is the
	same as calculating sqrt(x\sup{2} + y\sup{2}).)"),
	"hypot", 2
};

MATHFUNC2(hypot)

const StdlibRegisterInfo _gamma_info =
{
	Docstr(DFunc("gamma") DParam("v", "int|float")
	R"(\returns the gamma function of the input. Always returns a float.

	The gamma function is like factorial (!) function but extended to all real numbers. This function is slightly
	different from factorial in that if you pass it an integer \tt{v}, you will get \tt{(v - 1)!}. So \tt{math.gamma(5)}
	gives \tt{4! = 24}.)"),
	"gamma", 1
};

MATHFUNCRENAME(gamma, tgamma)

const StdlibRegisterInfo _lgamma_info =
{
	Docstr(DFunc("lgamma") DParam("v", "int|float")
	R"(\returns the natural log of the \link{gamma} function of the input.)"),
	"lgamma", 1
};

MATHFUNC1(lgamma)

const StdlibRegisterInfo _ceil_info =
{
	Docstr(DFunc("ceil") DParam("v", "int|float")
	R"(\returns \tt{v} rounded up to the next integer closer to infinity, or if \tt{v} is already a whole number,
	returns it unmodified. \b{Always returns a float.} See \link{iceil} for a version that returns an int.)"),
	"ceil", 1
};

MATHFUNC1(ceil)

const StdlibRegisterInfo _floor_info =
{
	Docstr(DFunc("floor") DParam("v", "int|float")
	R"(\returns \tt{v} rounded down to the next integer closer to negative infinity, or if \tt{v} is already a whole
	number, returns it unmodified. \b{Always returns a float.} See \link{ifloor} for a version that returns an int.)"),
	"floor", 1
};

MATHFUNC1(floor)

const StdlibRegisterInfo _round_info =
{
	Docstr(DFunc("round") DParam("v", "int|float")
	R"(\returns \tt{v} rounded to the nearest integer, or if \tt{v} is already a whole number, returns it unmodified.
	\b{Always returns a float.} See \link{iround} for a version that returns an int.)"),
	"round", 1
};

MATHFUNC1(round)

const StdlibRegisterInfo _trunc_info =
{
	Docstr(DFunc("trunc") DParam("v", "int|float")
	R"(\returns the whole number part of the value, discarding the digits after the decimal point. \b{Always returns a
	float.} See \link{itrunc} for a version that returns an int.)"),
	"trunc", 1
};

MATHFUNC1(trunc)

const StdlibRegisterInfo _iceil_info =
{
	Docstr(DFunc("iceil") DParam("v", "int|float")
	R"(These functions operate the same as \link{ceil}, \link{floor}, \link{round}, and \link{trunc}, except the value
	is cast to an integer before being returned.)"),
	"iceil", 1
};

IMATHFUNC(ceil)

const StdlibRegisterInfo _ifloor_info =
{
	Docstr(DFunc("ifloor") DParam("v", "int|float")
	R"(ditto)"),
	"ifloor", 1
};

IMATHFUNC(floor)

const StdlibRegisterInfo _iround_info =
{
	Docstr(DFunc("iround") DParam("v", "int|float")
	R"(ditto)"),
	"iround", 1
};

IMATHFUNC(round)

const StdlibRegisterInfo _itrunc_info =
{
	Docstr(DFunc("itrunc") DParam("v", "int|float")
	R"(ditto)"),
	"itrunc", 1
};

IMATHFUNC(trunc)

const StdlibRegisterInfo _isNan_info =
{
	Docstr(DFunc("isNan") DParam("v", "int|float")
	R"(\returns \tt{true} if the input is \link{nan}, and \tt{false} otherwise.)"),
	"isNan", 1
};

BOOLMATHFUNC(isNan, std::isnan)

const StdlibRegisterInfo _isInf_info =
{
	Docstr(DFunc("isInf") DParam("v", "int|float")
	R"(\returns \tt{true} if the input is positive or negative infinity, and \tt{false} otherwise.)"),
	"isInf", 1
};

BOOLMATHFUNC(isInf, std::isinf)

const StdlibRegisterInfo _sign_info =
{
	Docstr(DFunc("sign") DParam("v", "int|float")
	R"(\returns an integer representing the sign of the number. If \tt{v < 0}, returns -1; if \tt{v > 0}, returns 1; and
	if \tt{v == 0}, returns 0.)"),

	"sign", 1
};

word_t _sign(CrocThread* t)
{
	croc_ex_checkNumParam(t, 1);

	if(croc_isInt(t, 1))
	{
		auto val = croc_getInt(t, 1);

		if(val < 0)
			croc_pushInt(t, -1);
		else if(val > 0)
			croc_pushInt(t, 1);
		else
			croc_pushInt(t, 0);
	}
	else
	{
		auto val = croc_getFloat(t, 1);

		if(val < 0)
			croc_pushInt(t, -1);
		else if(val > 0)
			croc_pushInt(t, 1);
		else
			croc_pushInt(t, 0);
	}

	return 1;
}

const StdlibRegisterInfo _rand_info =
{
	Docstr(DFunc("rand") DParamD("a", "int", "null") DParamD("b", "int", "null")
	R"(\returns a random integer.

	If no parameters are given, the value will be a random integer in the range [-2\sup{63}, 2\sup{63}).

	If one parameter is given, if it's positive, it will act as the upper noninclusive bound on the values returned, so
	\tt{math.rand(10)} will return integers in the range [0, 10). If it's negative, it will act as the lower
	noninclusive bound on the values returned, so \tt{math.rand(-10)} will return integers in the range (-10, 0].

	If two parameters are given, the first is the lower inclusive bound, and the second is the upper noninclusive bound.
	So \tt{math.rand(-10, -5)} will return numbers in the range [-10, -5).

	\throws[RangeError] if only one parameter is passed, and it is 0.
	\throws[ValueError] if two parameters are passed, and they are equal.)"),

	"rand", 2
};

word_t _rand(CrocThread* t)
{
	auto &rng = Thread::from(t)->vm->rng;
	crocint num = cast(crocint)rng.next64();

	switch(croc_getStackSize(t) - 1)
	{
		case 0:
			croc_pushInt(t, num);
			break;

		case 1: {
			auto max = croc_ex_checkIntParam(t, 1);

			if(max > 0)
				croc_pushInt(t, cast(uint64_t)num % max);
			else if(max < 0)
				croc_pushInt(t, -(cast(uint64_t)num % -max));
			else
				croc_eh_throwStd(t, "RangeError", "Maximum value may not be 0");
			break;
		}
		default:
			auto lo = croc_ex_checkIntParam(t, 1);
			auto hi = croc_ex_checkIntParam(t, 2);

			if(hi == lo)
				croc_eh_throwStd(t, "ValueError", "Low and high values must be different");

			croc_pushInt(t, (cast(uint64_t)num % (hi - lo)) + lo);
			break;
	}

	return 1;
}

const StdlibRegisterInfo _frand_info =
{
	Docstr(DFunc("frand") DParamD("a", "int|float", "null") DParamD("b", "int|float", "null")
	R"(\returns a random float.

	If no parameters are given, the value will be a random float in the range [0.0, 1.0]. Note that the upper bound is
	inclusive!

	If one parameter is given, if it's positive, it will act as the upper \em{inclusive} bound on the values returned,
	so \tt{math.frand(10)} will return floats in the range [0.0, 10.0]. If it's negative, it will act as the lower
	inclusive bound, so \tt{math.frand(-10)} will return  numbers in the range [-10.0, 0.0].

	If two parameters are given, the first is the lower bound and the second the upper, both inclusive. So
	\tt{math.frand(-10, -5)} will return numbers in the range [-10.0, -5.0].)"),

	"frand", 2
};

word_t _frand(CrocThread* t)
{
	auto &rng = Thread::from(t)->vm->rng;
	auto num = rng.nextf52();

	switch(croc_getStackSize(t) - 1)
	{
		case 0:
			croc_pushFloat(t, num);
			break;

		case 1:
			croc_pushFloat(t, num * croc_ex_checkNumParam(t, 1));
			break;

		default:
			auto lo = croc_ex_checkNumParam(t, 1);
			auto hi = croc_ex_checkNumParam(t, 2);

			croc_pushFloat(t, (num * (hi - lo)) + lo);
			break;
	}

	return 1;
}

const StdlibRegisterInfo _max_info =
{
	Docstr(DFunc("max") DVararg
	R"(\returns the largest value of its parameters. Note that this is a generic function; the parameters don't have to
	be numbers, they can be any comparable type.

	\throws[ParamError] if no parameters are passed.)"),

	"max", -1
};

word_t _max(CrocThread* t)
{
	auto numParams = croc_getStackSize(t) - 1;
	switch(numParams)
	{
		case 0:
			croc_eh_throwStd(t, "ParamError", "At least one parameter required");

		case 1:
			break;

		case 2:
			if(croc_cmp(t, 1, 2) > 0)
				croc_popTop(t);
			break;

		default:
			word m = 1;

			for(uword i = 2; i <= numParams; i++)
				if(croc_cmp(t, i, m) > 0)
					m = i;

			croc_dup(t, m);
			break;
	}

	return 1;
}

const StdlibRegisterInfo _min_info =
{
	Docstr(DFunc("min") DVararg
	R"(\returns the smallest value of its parameters. Note that this is a generic function; the parameters don't have to
	be numbers, they can be any comparable type.

	\throws[ParamError] if no parameters are passed.)"),

	"min", -1
};

word_t _min(CrocThread* t)
{
	auto numParams = croc_getStackSize(t) - 1;
	switch(numParams)
	{
		case 0:
			croc_eh_throwStd(t, "ParamError", "At least one parameter required");

		case 1:
			break;

		case 2:
			if(croc_cmp(t, 1, 2) < 0)
				croc_popTop(t);
			break;

		default:
			word m = 1;

			for(uword i = 2; i <= numParams; i++)
				if(croc_cmp(t, i, m) < 0)
					m = i;

			croc_dup(t, m);
			break;
	}

	return 1;
}

const StdlibRegister _globalFuncs[] =
{
	_DListItem(_abs),
	_DListItem(_sin),
	_DListItem(_cos),
	_DListItem(_tan),
	_DListItem(_asin),
	_DListItem(_acos),
	_DListItem(_atan),
	_DListItem(_atan2),
	_DListItem(_sqrt),
	_DListItem(_cbrt),
	_DListItem(_pow),
	_DListItem(_exp),
	_DListItem(_ln),
	_DListItem(_log2),
	_DListItem(_log10),
	_DListItem(_hypot),
	_DListItem(_gamma),
	_DListItem(_lgamma),
	_DListItem(_ceil),
	_DListItem(_floor),
	_DListItem(_round),
	_DListItem(_trunc),
	_DListItem(_iceil),
	_DListItem(_ifloor),
	_DListItem(_iround),
	_DListItem(_itrunc),
	_DListItem(_isNan),
	_DListItem(_isInf),
	_DListItem(_sign),
	_DListItem(_rand),
	_DListItem(_frand),
	_DListItem(_max),
	_DListItem(_min),
	_DListEnd
};

#ifdef CROC_BUILTIN_DOCS
const char* _constDocs[] =
{
	DVar("e")
	R"(The constant \tt{e} (2.7182818...).)",

	DVar("pi")
	R"(The constant \tt{pi} (3.1415926...).)",

	DVar("nan")
	R"(A value which means "not a number". This is returned by some math functions to indicate that the result is
	nonsensical.)",

	DVar("infinity")
	R"(Positive infinity. This (and its negative) is returned by some of the math functions and math operations to
	indicate that the result is too big to fit into a floating point number. )",

	DVar("intSize")
	R"(The size, in bytes, of the Croc \tt{int} type. By default, this is 8. Nonstandard implementations may differ.)",

	DVar("intMin")
	R"(The smallest (most negative) number the Croc \tt{int} type can hold.)",

	DVar("intMax")
	R"(The largest (most positive) number the Croc \tt{int} type can hold.)",

	DVar("floatSize")
	R"(The size, in bytes, of the Croc \tt{float} type. By default, this is 8. Nonstandard implementations may
	differ.)",

	DVar("floatMin")
	R"(The smallest positive non-zero number the Croc \tt{float} type can hold.)",

	DVar("floatMax")
	R"(The largest positive non-infinity number the Croc \tt{float} type can hold.)",

	nullptr
};
#endif

word loader(CrocThread* t)
{
	croc_pushFloat(t, 2.718281828459045235360287471352);            croc_newGlobal(t, "e");
	croc_pushFloat(t, 3.141592653589793238462643383279);            croc_newGlobal(t, "pi");
	croc_pushFloat(t, std::numeric_limits<crocfloat>::quiet_NaN()); croc_newGlobal(t, "nan");
	croc_pushFloat(t, std::numeric_limits<crocfloat>::infinity());  croc_newGlobal(t, "infinity");
	croc_pushInt(t,   sizeof(crocint));                             croc_newGlobal(t, "intSize");
	croc_pushInt(t,   std::numeric_limits<crocint>::min());         croc_newGlobal(t, "intMin");
	croc_pushInt(t,   std::numeric_limits<crocint>::max());         croc_newGlobal(t, "intMax");
	croc_pushInt(t,   sizeof(crocfloat));                           croc_newGlobal(t, "floatSize");
	croc_pushFloat(t, std::numeric_limits<crocfloat>::min());       croc_newGlobal(t, "floatMin");
	croc_pushFloat(t, std::numeric_limits<crocfloat>::max());       croc_newGlobal(t, "floatMax");

	registerGlobals(t, _globalFuncs);
	return 0;
}
}

void initMathLib(CrocThread* t)
{
	registerModule(t, "math", &loader);
	croc_pushGlobal(t, "math");
#ifdef CROC_BUILTIN_DOCS
	CrocDoc doc;
	croc_ex_doc_init(t, &doc, __FILE__);
	croc_ex_doc_push(&doc,
	DModule("math")
	R"(Math functions. What more is there to say?)");
		croc_ex_docFields(&doc, _constDocs);
		docFields(&doc, _globalFuncs);
	croc_ex_doc_pop(&doc, -1);
	croc_ex_doc_finish(&doc);
#endif
	croc_popTop(t);
}
}