/******************************************************************************
This module contains the enumeration of Croc bytecode opcodes, as well as
the definition of bytecode instructions (and some constants related to it).

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

module croc.base_opcodes;

import tango.text.convert.Format;

import croc.base_metamethods;

// enum Op : ushort
// {
// 	Add,
// 	AddEq,
// 	And,
// 	AndEq,
// 	Append,
// 	As,
// 	Call,
// 	Cat,
// 	CatEq,
// 	CheckObjParam,
// 	CheckParams,
// 	Class,
// 	Close,
// 	Closure,
// 	Coroutine,
// 	Cmp,
// 	Cmp3,
// 	Com,
// 	CustomParamFail,
// 	Dec,
// 	Div,
// 	DivEq,
// 	EndFinal,
// 	Equals,
// 	Field,
// 	FieldAssign,
// 	For,
// 	Foreach,
// 	ForeachLoop,
// 	ForLoop,
// 	In,
// 	Inc,
// 	Index,
// 	IndexAssign,
// 	Is,
// 	IsTrue,
// 	Je,
// 	Jle,
// 	Jlt,
// 	Jmp,
// 	Length,
// 	LengthAssign,
// 	LoadConst,
// 	LoadNulls,
// 	Method,
// 	MethodNC,
// 	Mod,
// 	ModEq,
// 	Move,
// 	Mul,
// 	MulEq,
// 	Namespace,
// 	NamespaceNP,
// 	Neg,
// 	NewArray,
// 	NewGlobal,
// 	NewTable,
// 	Not,
// 	ObjParamFail,
// 	Or,
// 	OrEq,
// 	PopCatch,
// 	PopFinally,
// 	PushCatch,
// 	PushFinally,
// 	Ret,
// 	SaveRets,
// 	SetArray,
// 	Shl,
// 	ShlEq,
// 	Shr,
// 	ShrEq,
// 	Slice,
// 	SliceAssign,
// 	Sub,
// 	SubEq,
// 	SuperMethod,
// 	SuperOf,
// 	Switch,
// 	SwitchCmp,
// 	Tailcall,
// 	Throw,
// 	Unwind,
// 	UShr,
// 	UShrEq,
// 	Vararg,
// 	VargIndex,
// 	VargIndexAssign,
// 	VargLen,
// 	VargSlice,
// 	Xor,
// 	XorEq,
// 	Yield
// }

enum Op1
{
	UnOp, //
	BinOp, //
	ReflBinOp, //
	BitOp, //
	ReflBitOp, //
	CrementOp, //

	Move,
	LoadConst,
	LoadNulls,
	NewGlobal,
	GetGlobal,
	SetGlobal,
	GetUpval,
	SetUpval,

	Cmp, //
	Equals, //
	SwitchCmp, //
	Is, //
	IsTrue, //
	Jmp,
	Switch,
	For,
	ForLoop,
	Foreach,
	ForeachLoop, //

	PushEH, //
	PopEH, //
	EndFinal,
	Throw,
	Unwind,

	Method, //
	MethodNC, //
	SuperMethod, //
	Call,
	Tailcall,
	Yield,
	SaveRets,
	Ret,
	Close,
	Vararg, //
	CheckParams,
	CheckObjParam, //
	ParamFail, //

	Length,
	LengthAssign,
	Array, //
	Cat,
	CatEq,
	Index,
	IndexAssign,
	Slice,
	SliceAssign,
	In,

	New, //

	As,
	SuperOf,
	Field,
	FieldAssign
}

enum Op2
{
	// BinOp
	Add = MM.Add,
	Sub = MM.Sub,
	Mul = MM.Mul,
	Div = MM.Div,
	Mod = MM.Mod,
	Cmp3 = MM.Cmp,

	// UnOp
	Neg = MM.Neg,
	Com = MM.Com,

	// ReflBinOp
	AddEq = MM.AddEq,
	SubEq = MM.SubEq,
	MulEq = MM.MulEq,
	DivEq = MM.DivEq,
	ModEq = MM.ModEq,

	// BitOp
	And = MM.And,
	Or = MM.Or,
	Xor = MM.Xor,
	Shl = MM.Shl,
	Shr = MM.Shr,
	UShr = MM.UShr,

	// ReflBitOp
	AndEq = MM.AndEq,
	OrEq = MM.OrEq,
	XorEq = MM.XorEq,
	ShlEq = MM.ShlEq,
	ShrEq = MM.ShrEq,
	UShrEq = MM.UShrEq,

	// CrementOp
	Inc = MM.Inc,
	Dec = MM.Dec,

	// Also UnOp
	Not = MM.LAST_OPCODE_MM + 1,

	// Comparisons
	Je,
	Jle,
	Jlt,

	// PushEH, PopEH
	Catch,
	Finally,

	// Vararg
	GetVarargs,
	VargLen,
	VargIndex,
	VargIndexAssign,
	VargSlice,

	// ParamFail
	ObjParamFail,
	CustomParamFail,

	// Array
	Append,
	Set,

	// New
	Array,
	Table,
	Class,
	Coroutine,
	Namespace,
	NamespaceNP,
	Closure,
	ClosureWithEnv
}

// Make sure we don't add too many instructions!
static assert(Op1.max <= Instruction.opcodeMax, "Too many primary opcodes");
static assert(Op2.max <= Instruction.opcodeMax, "Too many secondary opcodes");

/*
Add...............R: dest, src, src
AddEq.............R: dest, src, n/a
And...............R: dest, src, src
AndEq.............R: dest, src, n/a
Append............R: dest, src, n/a
As................R: dest, src, src class
Call..............R: register of func, num params + 1, num results + 1 (both, 0 = use all to end of stack)
Cat...............R: dest, src, num values (NOT variadic)
CatEq.............R: dest, src, num values (NOT variadic)
CheckObjParam.....R: n/a, index of parameter, object type
CheckParams.......I: n/a, n/a
Class.............R: dest, name const index, base class
Close.............I: reg start, n/a
Closure...........R: dest, index of funcdef, environment (0 = use current function's environment)
Coroutine.........R: dest, src, n/a
Cmp...............R: n/a, src, src
Cmp3..............R: dest, src, src
Com...............R: dest, src, n/a
CustomParamFail...R: n/a, src, condition string
Dec...............R: dest, n/a, n/a
Div...............R: dest, src, src
DivEq.............R: dest, src, n/a
EndFinal..........I: n/a, n/a
Equals............R: n/a, src, src
Field.............R: dest, src, index
FieldAssign.......R: dest, index, src
For...............J: base reg, branch offset
Foreach...........J: base reg, branch offset
ForeachLoop.......I: base reg, num indices
ForLoop...........J: base reg, branch offset
In................R: dest, src value, src object
Inc...............R: dest, n/a, n/a
Index.............R: dest, src object, src index
IndexAssign.......R: dest object, dest index, src
Is................R: n/a, src, src
IsTrue............R: n/a, src, n/a
Je................J: isTrue, branch offset
Jle...............J: isTrue, branch offset
Jlt...............J: isTrue, branch offset
Jmp...............J: 1 = jump / 0 = don't (nop), branch offset
Length............R: dest, src, n/a
LengthAssign......R: dest, src, n/a
LoadConst.........R: dest local, src const, n/a
LoadNulls.........I: dest, num regs
Method............R: base reg, object to index, method name
Mod...............R: dest, src, src
ModEq.............R: dest, src, n/a
Move..............R: dest, src, n/a
Mul...............R: dest, src, src
MulEq.............R: dest, src, n/a
Namespace.........R: dest, name const index, parent namespace
NamespaceNP.......R: dest, name const index, n/a
Neg...............R: dest, src, n/a
NewArray..........I: dest, size
NewGlobal.........R: n/a, src, const index of global name
NewTable..........I: dest, n/a
Not...............R: dest, src, n/a
ObjParamFail......R: n/a, src, n/a
Or................R: dest, src, src
OrEq..............R: dest, src, n/a
PopCatch..........I: n/a, n/a
PopFinally........I: n/a, n/a
PushCatch.........J: exception reg, branch offset
PushFinally.......J: base reg, branch offset
Ret...............I: n/a, n/a
SaveRets..........I: base reg, num rets + 1 (0 = save all to end of stack)
SetArray..........R: dest, num fields + 1 (0 = set all to end of stack), block offset
Shl...............R: dest, src, src
ShlEq.............R: dest, src, n/a
Shr...............R: dest, src, src
ShrEq.............R: dest, src, n/a
Slice.............R: dest, src, n/a (indices are at src + 1 and src + 2)
SliceAssign.......R: dest, src, n/a (indices are at dest + 1 and dest + 2)
Sub...............R: dest, src, src
SubEq.............R: dest, src, n/a
SuperMethod.......R: base reg, object to index, method name
SuperOf...........R: dest, src, n/a
Switch............R: n/a, src, index of switch table
SwitchCmp.........R: n/a, src, src
Tailcall..........R: Register of func, num params + 1, n/a (0 params = use all to end of stack)
Throw.............R: n/a, src, 0 = not rethrowing, 1 = rethrowing
Unwind............I: n/a, number of levels
UShr..............R: dest, src, src
UShrEq............R: dest, src, n/a
Vararg............I: base reg, num rets + 1 (0 = return all to end of stack)
VargIndex.........R: dest, idx, n/a
VargIndexAssign...R: n/a, idx, src
VargLen...........R: dest, n/a, n/a
VargSlice.........I: base reg, num rets + 1 (0 = return all to end of stack; indices are at base reg and base reg + 1)
Xor...............R: dest, src, src
XorEq.............R: dest, src, n/a
Yield.............R: register of first yielded value, num values + 1, num results + 1 (both, 0 = to end of stack)
*/

template Mask(uint length)
{
	const uint Mask = (1 << length) - 1;
}

align(1) struct Instruction
{
	const uint constBit =  0b1_00000000;

    //  31      23        14       6      0
	// |rs       |rt       |rd      |op    |

	const uint opcodeSize = 6;
	const uint opcodeShift = 0;
	const uint opcodeMask = Mask!(opcodeSize) << opcodeShift;
	const uint opcodeMax = (1 << opcodeSize) - 1;

	const uint rdSize = 8;
	const uint rdShift = opcodeShift + opcodeSize;
	const uint rdMask = Mask!(rdSize) << rdShift;
	const uint rdMax = (1 << rdSize) - 1;

	const uint rtSize = 9;
	const uint rtShift = rdShift + rdSize;
	const uint rtMask = Mask!(rtSize) << rtShift;
	const uint rtMax = (1 << rtSize) - 1;

	const uint rsSize = 9;
	const uint rsShift = rtShift + rtSize;
	const uint rsMask = Mask!(rsSize) << rsShift;
	const uint rsMax = (1 << rsSize) - 1;

	const uint immSize = rsSize + rtSize;
	const uint immShift = rtShift;
	const uint immMask = rsMask | rtMask;
	const int  immMax = (1 << (immSize - 1)) - 1;
	const uint uimmMax = (1 << immSize) - 1;

	const uint MaxRegisters = rdMax - 1;
	const uint MaxConstants = uimmMax - 1;
	const uint MaxUpvalues = uimmMax - 1;
	const int  MaxJumpForward = immMax;
	const int  MaxJumpBackward = -immMax;
	const int  NoJump = MaxJumpBackward - 1;
	const uint MaxSwitchTables = rtMax - 1;
	const uint MaxInnerFuncs = uimmMax - 1;

	const uint ArraySetFields = 30;

	uint data;

// 	char[] toString()
// 	{//
// 		switch(opcode)
// 		{
// 			case Op.Field:           return Format("field {}, {}, {}", cr(rd), cr(rs), cr(rt));
// 			case Op.FieldAssign:     return Format("fielda {}, {}, {}", cr(rd), cr(rs), cr(rt));
// 			default:                 return Format("??? opcode = {}", opcode);
// 		}
// 	}
}

static assert(Instruction.sizeof == 4);
