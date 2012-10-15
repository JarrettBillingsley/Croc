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
	Namespace,
	NamespaceNP,

	As,
	SuperOf,
	AddField,
	AddMethod
}

static assert(Op.Add == MM.Add && Op.LAST_MM_OPCODE == MM.LAST_OPCODE_MM, "MMs and opcodes are out of sync!");

// Make sure we don't add too many instructions!
static assert(Op.max <= Instruction.opcodeMax, "Too many opcodes");

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
	Op.Namespace: "Namespace",
	Op.NamespaceNP: "NamespaceNP",
	Op.As: "As",
	Op.SuperOf: "SuperOf",
	Op.AddField: "AddField",
	Op.AddMethod: "AddMethod"
];

/*
Instruction format is variable length. Each instruction is composed of between 1 and 5 shorts.

First component is rd/op (lower 7 bits are op, upper 9 are rd), followed by 0-4 additional shorts, each of which can be
either a const-tagged reg/const index, or a signed/unsigned immediate.

Const-tagging: if the top bit is set, the lower 15 bits are an index into the constant table. If the top bit is clear,
the lower 9 bits are a local index.

rd = dest reg [0 .. 511]
rdimm = rd as immediate [0 .. 511]
rs = src reg [0 .. 511] or src const [0 .. 32,767]
rt = src reg [0 .. 511] or src const [0 .. 32,767]
imm = signed 16-bit immediate [-32,767 .. 32,767]
uimm = unsigned 16-bit immediate [0 .. 65,535]

Note that -32,768 is not a valid value for signed immediates -- this value is reserved for use by the codegen phase.

ONE SHORT:

(__)
	popcatch:    pop EH frame
	popfinal:    pop EH frame, set currentException to null
	endfinal:    rethrow any in-flight exception, or continue unwinding if doing so
	ret:         return
	checkparams: check params against param masks
(rd)
	inc:          rd++
	dec:          rd--
	varglen:      rd = #vararg
	newtab:       rd = {}
	close:        close open upvals down to and including rd
	objparamfail: give an error about parameter rd not being of an acceptable type
(rdimm)
	unwind: unwind rdimm number of EH frames

TWO SHORTS:

(rd, rs)
	addeq, subeq, muleq, diveq, modeq, andeq, oreq, xoreq, shleq, shreq, ushreq: rd op= rs
	neg, com, not:   rd = op rs
	mov:             rd = rs
	vargidx:         rd = vararg[rs]
	len:             rd = #rs
	lena:            #rd = rs
	append:          rd.append(rs)
	superof:         rd = rs.superof
	customparamfail: give error message about parameter rd not satisfying the constraint whose name is in rs
	slice:           rd = rs[rs + 1 .. rs + 2]
	slicea:          rd[rd + 1 .. rd + 2] = rs
(rd, imm)
	for:       prepare a numeric for loop with base register rd, then jump by imm
	forloop:   update a numeric for loop with base register rd, then jump by imm if we should keep going
	foreach:   prepare a foreach loop with base register rd, then jump by imm
	pushcatch: push EH catch frame with catch register rd and catch code offset of imm
	pushfinal: push EH finally frame with slot rd and finally code offset of imm
(rd, uimm)
	vararg:      regs[rd .. rd + uimm] = vararg
	saverets:    save uimm returns starting at rd
	vargslice:   regs[rd .. rd + uimm] = vararg[rd .. rd + 1]
	closure:     rd = newclosure(uimm)
	closurewenv: rd = newclosure(uimm, env: rd)
	newg:        newglobal(constTable[uimm]); setglobal(constTable[uimm], rd)
	getg:        rd = getglobal(constTable[uimm])
	setg:        setglobal(constTable[uimm], rd)
	getu:        rd = upvals[uimm]
	setu:        upvals[uimm] = rd
	newarr:      rd = array.new(constTable[uimm])
	namespacenp: rd = namespace constTable[uimm] : null {}
(rdimm, rs)
	throw:  throw the value in rs; rd == 0 means normal throw, rd == 1 means rethrow
	switch: switch on the value in rs using switch table index rd
(rdimm, imm)
	jmp: if rd == 1, jump by imm, otherwise no-op

THREE SHORTS:

(rd, rs, rt)
	add, sub, mul, div, mod, cmp3, and, or, xor, shl, shr, ushr: rd = rs op rt
	idx:    rd = rs[rt]
	idxa:   rd[rs] = rt
	in:     rd = rs in rt
	class:  rd = class rs : rt {}
	as:     rd = rs as rt
	field:  rd = rs.(rt)
	fielda: rd.(rs) = rt
(__, rs, rt)
	vargidxa: vararg[rs] = rt
(rd, rs, uimm)
	cat:   rd = rs ~ rs + 1 ~ ... ~ rs + uimm
	cateq: rd ~= rs ~ rs + 1 ~ ... ~ rs + uimm
(rd, rs, imm)
	checkobjparam: if(!isInstance(regs[rd]) || regs[rd] as rs) jump by imm
(rd, uimm, imm)
	foreachloop: update the foreach loop with base reg rd and uimm indices, and if we should go again, jump by imm
(rd, uimm1, uimm2)
	call:     regs[rd .. rd + uimm2] = rd(regs[rd + 1 .. rd + uimm1])
	tcall:    return rd(regs[rd + 1 .. rd + uimm1]) // uimm2 is unused, but this makes codegen easier by not having to change the instruction's size
	yield:    regs[rd .. rd + uimm2] = yield(regs[rd .. rd + uimm1])
	setarray: rd.setBlock(uimm2, regs[rd + 1 .. rd + 1 + uimm1])
(rd, uimm, rt)
	namespace: rd = namespace constTable[uimm] : rt {}
(rdimm, rs, imm)
	istrue: if the truth value of rs matches the truth value in rd, jump by imm

FOUR SHORTS:

(rdimm, rs, rt, imm)
	cmp:    if rs <=> rt matches the comparison type in rd, jump by imm
	equals: if((rs == rt) == rd) jump by imm
	is:     if((rs is rt) == rd) jump by imm
(__, rs, rt, imm)
	swcmp: if(switchcmp(rs, rt)) jump by imm
(rd, rt, uimm1, uimm2)
	smethod:  method supercall. works same as method, but lookup is based on the proto instead of a value.
	tsmethod: same as above, but does a tailcall. uimm2 is unused, but this makes codegen easier
(rd, rs, rt, uimm)
	addfield: add field named rs to class in rd with value rt. last uimm is 0 for private, nonzero for public.
	addmethod: add method named rs to class in rd with value rt. last uimm is 0 for private, nonzero for public.

FIVE SHORTS:

(rd, rs, rt, uimm1, uimm2)
	method:  rd is base reg, rs is object, rt is method name, uimm1 is number of params, uimm2 is number of expected returns.
	tmethod: same as above, but does a tailcall. uimm2 is unused, but this makes codegen easier
*/

template Mask(uint length)
{
	const ushort Mask = (1 << length) - 1;
}

align(1) struct Instruction
{
	const ushort constBit =  0b1000_0000_0000_0000;

    //  15        6     0
	// |rd       |op     |

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