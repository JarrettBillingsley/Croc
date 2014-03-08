
#include <limits>
#include <cmath>
#include <stdlib.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
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

#define MATHFUNC(name) word_t _##name(CrocThread* t) { croc_pushFloat(t, name(croc_ex_checkNumParam(t, 1))); return 1; }
	MATHFUNC(sin)
	MATHFUNC(cos)
	MATHFUNC(tan)
	MATHFUNC(asin)
	MATHFUNC(acos)
	MATHFUNC(atan)
	MATHFUNC(sqrt)
	MATHFUNC(cbrt)
	MATHFUNC(exp)
	MATHFUNC(lgamma)
	MATHFUNC(ceil)
	MATHFUNC(floor)
	MATHFUNC(round)
	MATHFUNC(trunc)
	MATHFUNC(log10)
	MATHFUNC(log2)
#undef MATHFUNC
#define MATHFUNC(name) word_t _##name(CrocThread* t) { croc_pushFloat(t, name(croc_ex_checkNumParam(t, 1), croc_ex_checkNumParam(t, 2))); return 1; }
	MATHFUNC(atan2)
	MATHFUNC(pow)
	MATHFUNC(hypot)
#undef MATHFUNC
#define MATHFUNC(name, real) word_t _##name(CrocThread* t) { croc_pushFloat(t, real(croc_ex_checkNumParam(t, 1))); return 1; }
	MATHFUNC(ln, log)
	MATHFUNC(gamma, tgamma)
#undef MATHFUNC
#define MATHFUNC(name) word_t _i##name(CrocThread* t)  { croc_pushInt(t, cast(crocint)name(croc_ex_checkNumParam(t, 1))); return 1; }
	MATHFUNC(ceil)
	MATHFUNC(floor)
	MATHFUNC(round)
	MATHFUNC(trunc)
#undef MATHFUNC
#define MATHFUNC(name, real) word_t _##name(CrocThread* t) { croc_pushBool(t, real(croc_ex_checkNumParam(t, 1))); return 1; }
	MATHFUNC(isNan, std::isnan)
	MATHFUNC(isInf, std::isinf)
#undef MATHFUNC

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

				if(max == 0)
					croc_eh_throwStd(t, "RangeError", "Maximum value may not be 0");

				croc_pushInt(t, cast(uint64_t)num % max);
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

	const CrocRegisterFunc _globalFuncs[] =
	{
		{"abs",     1, &_abs   },
		{"sin",     1, &_sin   },
		{"cos",     1, &_cos   },
		{"tan",     1, &_tan   },
		{"asin",    1, &_asin  },
		{"acos",    1, &_acos  },
		{"atan",    1, &_atan  },
		{"atan2",   2, &_atan2 },
		{"sqrt",    1, &_sqrt  },
		{"cbrt",    1, &_cbrt  },
		{"pow",     2, &_pow   },
		{"exp",     1, &_exp   },
		{"ln",      1, &_ln    },
		{"log2",    1, &_log2  },
		{"log10",   1, &_log10 },
		{"hypot",   2, &_hypot },
		{"lgamma",  1, &_lgamma},
		{"gamma",   1, &_gamma },
		{"ceil",    1, &_ceil  },
		{"floor",   1, &_floor },
		{"round",   1, &_round },
		{"trunc",   1, &_trunc },
		{"iceil",   1, &_iceil },
		{"ifloor",  1, &_ifloor},
		{"iround",  1, &_iround},
		{"itrunc",  1, &_itrunc},
		{"isNan",   1, &_isNan },
		{"isInf",   1, &_isInf },
		{"sign",    1, &_sign  },
		{"rand",    2, &_rand  },
		{"frand",   2, &_frand },
		{"max",    -1, &_max   },
		{"min",    -1, &_min   },
		{nullptr, 0, nullptr}
	};

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

		croc_ex_registerGlobals(t, _globalFuncs);
		return 0;
	}
	}

	void initMathLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "math", &loader);
		croc_ex_import(t, "math");
	}
}