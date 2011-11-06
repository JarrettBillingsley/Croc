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

import croc.base_metamethods;

enum Comparison
{
	LT,
	LE,
	GT,
	GE
}

enum Op
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

	LAST_MM_OPCODE = UShrEq,

	Neg,
	Com,

	Inc,
	Dec,

	Move,
	NewGlobal,
	GetGlobal,
	SetGlobal,
	GetUpval,
	SetUpval,

	Not,
	Cmp3,
	Cmp,
	SwitchCmp,
	Equals,
	Is,
	In,
	IsTrue,
	Jmp,
	Switch,
	Close,
	For,
	ForLoop,
	Foreach,
	ForeachLoop,

	PushCatch,
	PushFinally,
	PopCatch,
	PopFinally,
	EndFinal,
	Throw,

	Method,
	TailMethod,
	SuperMethod,
	TailSuperMethod,
	Call,
	TailCall,
	SaveRets,
	Ret,
	Unwind,

	Vararg,
	VargLen,
	VargIndex,
	VargIndexAssign,
	VargSlice,

	Yield,

	CheckParams,
	CheckObjParam,
	ObjParamFail,
	CustomParamFail,
	AssertFail,

	Length,
	LengthAssign,
	Append,
	SetArray,
	Cat,
	CatEq,
	Index,
	IndexAssign,
	Field,
	FieldAssign,
	Slice,
	SliceAssign,

	NewArray,
	NewTable,
	Closure,
	ClosureWithEnv,
	Class,
	Coroutine,
	Namespace,
	NamespaceNP,

	As,
	SuperOf
}

static assert(Op.Add == MM.Add && Op.LAST_MM_OPCODE == MM.LAST_OPCODE_MM, "MMs and opcodes are out of sync!");

// Make sure we don't add too many instructions!
static assert(Op.max <= Instruction.opcodeMax, "Too many primary opcodes");

const char[][] OpNames =
[
	Op.Add: "Add",
	Op.Sub: "Sub",
	Op.Mul: "Mul",
	Op.Div: "Div",
	Op.Mod: "Mod",
	Op.AddEq: "AddEq",
	Op.SubEq: "SubEq",
	Op.MulEq: "MulEq",
	Op.DivEq: "DivEq",
	Op.ModEq: "ModEq",
	Op.And: "And",
	Op.Or: "Or",
	Op.Xor: "Xor",
	Op.Shl: "Shl",
	Op.Shr: "Shr",
	Op.UShr: "UShr",
	Op.AndEq: "AndEq",
	Op.OrEq: "OrEq",
	Op.XorEq: "XorEq",
	Op.ShlEq: "ShlEq",
	Op.ShrEq: "ShrEq",
	Op.UShrEq: "UShrEq",
	Op.Neg: "Neg",
	Op.Com: "Com",
	Op.Inc: "Inc",
	Op.Dec: "Dec",
	Op.Move: "Move",
	Op.NewGlobal: "NewGlobal",
	Op.GetGlobal: "GetGlobal",
	Op.SetGlobal: "SetGlobal",
	Op.GetUpval: "GetUpval",
	Op.SetUpval: "SetUpval",
	Op.Not: "Not",
	Op.Cmp3: "Cmp3",
	Op.Cmp: "Cmp",
	Op.SwitchCmp: "SwitchCmp",
	Op.Equals: "Equals",
	Op.Is: "Is",
	Op.IsTrue: "IsTrue",
	Op.Jmp: "Jmp",
	Op.Switch: "Switch",
	Op.Close: "Close",
	Op.For: "For",
	Op.ForLoop: "ForLoop",
	Op.Foreach: "Foreach",
	Op.ForeachLoop: "ForeachLoop",
	Op.PushCatch: "PushCatch",
	Op.PushFinally: "PushFinally",
	Op.PopCatch: "PopCatch",
	Op.PopFinally: "PopFinally",
	Op.EndFinal: "EndFinal",
	Op.Throw: "Throw",
	Op.Method: "Method",
	Op.TailMethod: "TailMethod",
	Op.SuperMethod: "SuperMethod",
	Op.TailSuperMethod: "TailSuperMethod",
	Op.Call: "Call",
	Op.TailCall: "TailCall",
	Op.SaveRets: "SaveRets",
	Op.Ret: "Ret",
	Op.Unwind: "Unwind",
	Op.Vararg: "Vararg",
	Op.VargLen: "VargLen",
	Op.VargIndex: "VargIndex",
	Op.VargIndexAssign: "VargIndexAssign",
	Op.VargSlice: "VargSlice",
	Op.Yield: "Yield",
	Op.CheckParams: "CheckParams",
	Op.CheckObjParam: "CheckObjParam",
	Op.ObjParamFail: "ObjParamFail",
	Op.CustomParamFail: "CustomParamFail",
	Op.AssertFail: "AssertFail",
	Op.Length: "Length",
	Op.LengthAssign: "LengthAssign",
	Op.Append: "Append",
	Op.SetArray: "SetArray",
	Op.Cat: "Cat",
	Op.CatEq: "CatEq",
	Op.Index: "Index",
	Op.IndexAssign: "IndexAssign",
	Op.Field: "Field",
	Op.FieldAssign: "FieldAssign",
	Op.Slice: "Slice",
	Op.SliceAssign: "SliceAssign",
	Op.In: "In",
	Op.NewArray: "NewArray",
	Op.NewTable: "NewTable",
	Op.Closure: "Closure",
	Op.ClosureWithEnv: "ClosureWithEnv",
	Op.Class: "Class",
	Op.Coroutine: "Coroutine",
	Op.Namespace: "Namespace",
	Op.NamespaceNP: "NamespaceNP",
	Op.As: "As",
	Op.SuperOf: "SuperOf"
];

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
	const ushort Mask = (1 << length) - 1;
}

align(1) struct Instruction
{
	const ushort constBit =  0b1000_0000_0000_0000;

    //  31      23        14       6      0
	// |rs       |rt       |rd      |op    |

	const uint   opcodeSize = 7;
	const uint   opcodeShift = 0;
	const ushort opcodeMask = Mask!(opcodeSize) << opcodeShift;
	const uint   opcodeMax = (1 << opcodeSize) - 1;

	const uint   rdSize = 9;
	const uint   rdShift = opcodeShift + opcodeSize;
	const ushort rdMask = Mask!(rdSize) << rdShift;
	const uint   rdMax = (1 << rdSize) - 1;

	const uint immSize = 16;
	const int  immMax = (1 << (immSize - 1)) - 1;
	const uint uimmMax = (1 << immSize) - 1;

	const uint MaxRegister = rdMax;
	const uint MaxConstant = uimmMax;
	const uint MaxUpvalue = uimmMax;
	const int  MaxJumpForward = immMax;
	const int  MaxJumpBackward = -immMax;
	const int  NoJump = MaxJumpBackward - 1;
	const uint MaxEHDepth = rdMax;
	const uint MaxSwitchTable = rdMax;
	const uint MaxInnerFunc = uimmMax;

	const uint ArraySetFields = 30;
	const uint MaxArrayFields = ArraySetFields * uimmMax;

	static char[] GetOpcode(char[] n) { return "(" ~ n ~ ".uimm & Instruction.opcodeMask) >> Instruction.opcodeShift"; }
	static char[] GetRD(char[] n) { return "(" ~ n ~ ".uimm & Instruction.rdMask) >> Instruction.rdShift"; }

	union
	{
		short imm;
		ushort uimm;
	}
}

static assert(Instruction.sizeof == 2);