/******************************************************************************
This module contains the enumeration of Croc metamethods and some data about
them used by the interpreter.

License:
Copyright (c) 2011 Jarrett Billingsley

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

module croc.base_metamethods;

// The first several values of this enumeration are also the basis for the secondary
// opcode for many multi-part instructions, so that the metamethods can be looked up
// quickly without needing an opcode-to-MM translation table.
// LAST_OPCODE_MM is the last metamethod type which is like this.
package enum MM
{
	Add,
	Sub,
	Mul,
	Div,
	Mod,

	AddEq,
	SubEq,
	MulEq,
	DivEq,
	ModEq,

	And,
	Or,
	Xor,
	Shl,
	Shr,
	UShr,

	AndEq,
	OrEq,
	XorEq,
	ShlEq,
	ShrEq,
	UShrEq,

	LAST_OPCODE_MM = UShrEq,

	Neg,
	Com,

	Inc,
	Dec,

	Add_r,
	Sub_r,
	Mul_r,
	Div_r,
	Mod_r,

	And_r,
	Or_r,
	Xor_r,
	Shl_r,
	Shr_r,
	UShr_r,

	Cat,
	CatEq,
	Cat_r,

	Index,
	IndexAssign,
	Slice,
	SliceAssign,
	Field,
	FieldAssign,
	Length,
	LengthAssign,

	Cmp,
	Equals,

	Call,
	Method,

	Apply,
	In,
	ToString,
}

package const char[][] MetaNames =
[
	MM.Add:          "opAdd",
	MM.Add_r:        "opAdd_r",
	MM.AddEq:        "opAddAssign",
	MM.And:          "opAnd",
	MM.And_r:        "opAnd_r",
	MM.AndEq:        "opAndAssign",
	MM.Apply:        "opApply",
	MM.Call:         "opCall",
	MM.Cat:          "opCat",
	MM.Cat_r:        "opCat_r",
	MM.CatEq:        "opCatAssign",
	MM.Cmp:          "opCmp",
	MM.Com:          "opCom",
	MM.Dec:          "opDec",
	MM.Div:          "opDiv",
	MM.Div_r:        "opDiv_r",
	MM.DivEq:        "opDivAssign",
	MM.Equals:       "opEquals",
	MM.Field:        "opField",
	MM.FieldAssign:  "opFieldAssign",
	MM.In:           "opIn",
	MM.Inc:          "opInc",
	MM.Index:        "opIndex",
	MM.IndexAssign:  "opIndexAssign",
	MM.Length:       "opLength",
	MM.LengthAssign: "opLengthAssign",
	MM.Method:       "opMethod",
	MM.Mod:          "opMod",
	MM.Mod_r:        "opMod_r",
	MM.ModEq:        "opModAssign",
	MM.Mul:          "opMul",
	MM.Mul_r:        "opMul_r",
	MM.MulEq:        "opMulAssign",
	MM.Neg:          "opNeg",
	MM.Or:           "opOr",
	MM.Or_r:         "opOr_r",
	MM.OrEq:         "opOrAssign",
	MM.Shl:          "opShl",
	MM.Shl_r:        "opShl_r",
	MM.ShlEq:        "opShlAssign",
	MM.Shr:          "opShr",
	MM.Shr_r:        "opShr_r",
	MM.ShrEq:        "opShrAssign",
	MM.Slice:        "opSlice",
	MM.SliceAssign:  "opSliceAssign",
	MM.Sub:          "opSub",
	MM.Sub_r:        "opSub_r",
	MM.SubEq:        "opSubAssign",
	MM.ToString:     "toString",
	MM.UShr:         "opUShr",
	MM.UShr_r:       "opUShr_r",
	MM.UShrEq:       "opUShrAssign",
	MM.Xor:          "opXor",
	MM.Xor_r:        "opXor_r",
	MM.XorEq:        "opXorAssign",
];

package const MM[] MMRev =
[
	MM.Add:  MM.Add_r,
	MM.Sub:  MM.Sub_r,
	MM.Mul:  MM.Mul_r,
	MM.Div:  MM.Div_r,
	MM.Mod:  MM.Mod_r,
	MM.Cat:  MM.Cat_r,
	MM.And:  MM.And_r,
	MM.Or:   MM.Or_r,
	MM.Xor:  MM.Xor_r,
	MM.Shl:  MM.Shl_r,
	MM.Shr:  MM.Shr_r,
	MM.UShr: MM.UShr_r,

	MM.max:  cast(MM)-1
];

package const bool[] MMCommutative =
[
	MM.Add: true,
	MM.Mul: true,
	MM.And: true,
	MM.Or:  true,
	MM.Xor: true,

	MM.max: false
];