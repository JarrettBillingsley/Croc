
#include "croc/compiler/ast.hpp"
#include "croc/compiler/types.hpp"

namespace croc
{
	const char* AstTagNames[AstTag_NUMBER] =
	{
#define POOP(Tag, _, __) #Tag,
		AST_LIST(POOP)
#undef POOP
	};

	const char* NiceAstTagNames[AstTag_NUMBER] =
	{
#define POOP(_, NiceName, __) NiceName,
		AST_LIST(POOP)
#undef POOP
	};

	bool Expression::hasSideEffects()
	{
		switch(type)
		{
			case AstTag_CondExp: {
				auto c = cast(CondExp*)this;
				return c->cond->hasSideEffects() || c->op1->hasSideEffects() || c->op2->hasSideEffects();
			}
			case AstTag_OrOrExp: {
				auto o = cast(OrOrExp*)this;
				return o->op1->hasSideEffects() || o->op2->hasSideEffects();
			}
			case AstTag_AndAndExp: {
				auto a = cast(AndAndExp*) this;
				return a->op1->hasSideEffects() || a->op2->hasSideEffects();
			}

			case AstTag_CallExp:
			case AstTag_MethodCallExp:
			case AstTag_YieldExp: return true;
			default:              return false;
		}
	}

	bool Expression::isMultRet()
	{
		switch(type)
		{
			case AstTag_CallExp:
			case AstTag_MethodCallExp:
			case AstTag_VarargExp:
			case AstTag_VargSliceExp:
			case AstTag_YieldExp: return true;
			default:              return false;
		}
	}

	bool Expression::isLHS()
	{
		switch(type)
		{
			case AstTag_LenExp:
			case AstTag_DotExp:
			case AstTag_IndexExp:
			case AstTag_SliceExp:
			case AstTag_IdentExp:
			case AstTag_VargIndexExp: return true;
			default:                  return false;
		}
	}

	bool Expression::isConstant()
	{
		switch(type)
		{
			case AstTag_NullExp:
			case AstTag_BoolExp:
			case AstTag_IntExp:
			case AstTag_FloatExp:
			case AstTag_StringExp: return true;
			default:               return false;
		}
	}

	bool Expression::isTrue()
	{
		switch(type)
		{
			case AstTag_NullExp:   return false;
			case AstTag_BoolExp:   return (cast(BoolExp*)this)->value;
			case AstTag_IntExp:    return (cast(IntExp*)this)->value != 0;
			case AstTag_FloatExp:  return (cast(FloatExp*)this)->value != 0.0;
			case AstTag_StringExp: return true;
			default:               return false;
		}
	}

	bool Expression::isNull()
	{
		return type == AstTag_NullExp;
	}

	bool Expression::isBool()
	{
		return type == AstTag_BoolExp;
	}

	bool Expression::isInt()
	{
		return type == AstTag_IntExp;
	}

	bool Expression::isFloat()
	{
		return type == AstTag_FloatExp;
	}

	bool Expression::isNum()
	{
		return type == AstTag_IntExp || type == AstTag_FloatExp;
	}

	bool Expression::isString()
	{
		return type == AstTag_StringExp;
	}

	bool Expression::asBool()
	{
		if(auto b = AST_AS(BoolExp, this))
			return b->value;

		assert(false);
	}

	crocint Expression::asInt()
	{
		if(auto i = AST_AS(IntExp, this))
			return i->value;

		assert(false);
	}

	crocfloat Expression::asFloat()
	{
		if(auto i = AST_AS(IntExp, this))
			return i->value;
		else if(auto f = AST_AS(FloatExp, this))
			return f->value;

		assert(false);
	}

	const char* Expression::asString()
	{
		if(auto s = AST_AS(StringExp, this))
			return s->value;

		assert(false);
	}
}