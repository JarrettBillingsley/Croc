#ifndef CROC_BASE_METAMETHODS_HPP
#define CROC_BASE_METAMETHODS_HPP

#include "croc/base/sanity.hpp"

namespace croc
{
	// The first several values of this enumeration are the same as the opcodes for
	// their corresponding instructions, so that the metamethods can be looked up
	// quickly without needing an opcode-to-MM translation table.
	// LAST_OPCODE_MM is the last metamethod type which is like this.

#define METAMETHOD_LIST(X)\
	X(MM_Add,          "opAdd",          MM_Add_r,  true ),\
	X(MM_Sub,          "opSub",          MM_Sub_r,  false),\
	X(MM_Mul,          "opMul",          MM_Mul_r,  true ),\
	X(MM_Div,          "opDiv",          MM_Div_r,  false),\
	X(MM_Mod,          "opMod",          MM_Mod_r,  false),\
	X(MM_AddEq,        "opAddAssign",    -1,        false),\
	X(MM_SubEq,        "opSubAssign",    -1,        false),\
	X(MM_MulEq,        "opMulAssign",    -1,        false),\
	X(MM_DivEq,        "opDivAssign",    -1,        false),\
	X(MM_ModEq,        "opModAssign",    -1,        false),\
	X(MM_And,          "opAnd",          MM_And_r,  true ),\
	X(MM_Or,           "opOr",           MM_Or_r,   true ),\
	X(MM_Xor,          "opXor",          MM_Xor_r,  true ),\
	X(MM_Shl,          "opShl",          MM_Shl_r,  false),\
	X(MM_Shr,          "opShr",          MM_Shr_r,  false),\
	X(MM_UShr,         "opUShr",         MM_UShr_r, false),\
	X(MM_AndEq,        "opAndAssign",    -1,        false),\
	X(MM_OrEq,         "opOrAssign",     -1,        false),\
	X(MM_XorEq,        "opXorAssign",    -1,        false),\
	X(MM_ShlEq,        "opShlAssign",    -1,        false),\
	X(MM_ShrEq,        "opShrAssign",    -1,        false),\
	X(MM_UShrEq,       "opUShrAssign",   -1,        false),\
	\
	X(MM_Neg,          "opNeg",          -1,        false),\
	X(MM_Com,          "opCom",          -1,        false),\
	X(MM_Inc,          "opInc",          -1,        false),\
	X(MM_Dec,          "opDec",          -1,        false),\
	X(MM_Add_r,        "opAdd_r",        -1,        false),\
	X(MM_Sub_r,        "opSub_r",        -1,        false),\
	X(MM_Mul_r,        "opMul_r",        -1,        false),\
	X(MM_Div_r,        "opDiv_r",        -1,        false),\
	X(MM_Mod_r,        "opMod_r",        -1,        false),\
	X(MM_And_r,        "opAnd_r",        -1,        false),\
	X(MM_Or_r,         "opOr_r",         -1,        false),\
	X(MM_Xor_r,        "opXor_r",        -1,        false),\
	X(MM_Shl_r,        "opShl_r",        -1,        false),\
	X(MM_Shr_r,        "opShr_r",        -1,        false),\
	X(MM_UShr_r,       "opUShr_r",       -1,        false),\
	X(MM_Cat,          "opCat",          MM_Cat_r,  false),\
	X(MM_CatEq,        "opCatAssign",    -1,        false),\
	X(MM_Cat_r,        "opCat_r",        -1,        false),\
	X(MM_Index,        "opIndex",        -1,        false),\
	X(MM_IndexAssign,  "opIndexAssign",  -1,        false),\
	X(MM_Slice,        "opSlice",        -1,        false),\
	X(MM_SliceAssign,  "opSliceAssign",  -1,        false),\
	X(MM_Field,        "opField",        -1,        false),\
	X(MM_FieldAssign,  "opFieldAssign",  -1,        false),\
	X(MM_Length,       "opLength",       -1,        false),\
	X(MM_LengthAssign, "opLengthAssign", -1,        false),\
	X(MM_Cmp,          "opCmp",          -1,        false),\
	X(MM_Equals,       "opEquals",       -1,        false),\
	X(MM_Call,         "opCall",         -1,        false),\
	X(MM_Method,       "opMethod",       -1,        false),\
	X(MM_Apply,        "opApply",        -1,        false),\
	X(MM_In,           "opIn",           -1,        false),\
	X(MM_ToString,     "toString",       -1,        false)

#define POOP(x, _, __, ___) x
	typedef enum Metamethod
	{
		METAMETHOD_LIST(POOP),
		MM_LAST_OPCODE_MM = MM_UShrEq
	} Metamethod;
#undef POOP

	extern const char* MetaNames[];
	extern const Metamethod MMRev[];
	extern const bool MMCommutative[];
}
#endif
