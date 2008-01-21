/******************************************************************************
License:
Copyright (c) 2007 Jarrett Billingsley

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

module minid.opcodes;

import tango.io.Stdout;

const uint MaxRegisters = Instruction.rsMax;
const uint MaxConstants = Instruction.rsMax;
const uint MaxUpvalues = Instruction.rsMax;

enum Op : uint
{
	Add,
	AddEq,
	And,
	AndEq,
	Append,
	As,
	Call,
	Cat,
	CatEq,
	Close,
	Closure,
	CondMove,
	Coroutine,
	Cmp,
	Cmp3,
	Com,
	Dec,
	Div,
	DivEq,
	EndFinal,
	Field,
	FieldAssign,
	For,
	Foreach,
	ForLoop,
	Import,
	In,
	Inc,
	Index,
	IndexAssign,
	Is,
	IsTrue,
	Je,
	Jle,
	Jlt,
	Jmp,
	Length,
	LengthAssign,
	LoadBool,
	LoadConst,
	LoadNull,
	LoadNulls,
	Method,
	MethodNC,
	Mod,
	ModEq,
	Move,
	MoveLocal,
	Mul,
	MulEq,
	Namespace,
	Neg,
	NewArray,
	NewGlobal,
	NewTable,
	Not,
	NotIn,
	Object,
	Or,
	OrEq,
	PopCatch,
	PopFinally,
	Precall,
	PushCatch,
	PushFinally,
	Ret,
	SetArray,
	SetAttrs,
	Shl,
	ShlEq,
	Shr,
	ShrEq,
	Slice,
	SliceAssign,
	Sub,
	SubEq,
	SuperMethod,
	SuperOf,
	Switch,
	SwitchCmp,
	Tailcall,
	Throw,
	UShr,
	UShrEq,
	Vararg,
	VargIndex,
	VargIndexAssign,
	VargLen,
	VargSlice,
	Xor,
	XorEq,
	Yield
}

// Make sure we don't add too many instructions!
static assert(Op.max <= Instruction.opcodeMax);

/*
Add...............R: dest, src, src
AddEq.............R: dest, src, n/a
And...............R: dest, src, src
AndEq.............R: dest, src, n/a
Append............R: dest, src, n/a
As................R: dest, src, src class
Call..............R: register of func, num params + 1, num results + 1 (both, 0 = use all to end of stack)
Cat...............R: dest, src, num values + 1 (0 = use all to end of stack)
CatEq.............R: dest, src, num values + 1 (0 = use all to end of stack)
Close.............I: reg start, n/a
Closure...........R: dest, index of funcdef, attrs reg + 1 (0 means no attrs)
CondMove..........R: dest, src, n/a
Coroutine.........R: dest, src, n/a
Cmp...............R: n/a, src, src
Cmp3..............R: dest, src, src
Com...............R: dest, src, n/a
Dec...............R: dest, n/a, n/a
Div...............R: dest, src, src
DivEq.............R: dest, src, n/a
EndFinal..........I: n/a, n/a
Field.............R: dest, src, index
FieldAssign.......R: dest, index, src
For...............J: base reg, branch offset
Foreach...........I: base reg, num indices
ForLoop...........J: base reg, branch offset
Import............R: dest, name src, n/a
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
LoadBool..........R: dest, 1/0, n/a
LoadConst.........R: dest local, src const, n/a
LoadNull..........I: dest, n/a
LoadNulls.........I: dest, num regs
Method............R: base reg, object to index, method name
MethodNC..........R: base reg, object to index, method name
Mod...............R: dest, src, src
ModEq.............R: dest, src, n/a
Move..............R: dest, src, n/a
MoveLocal.........R: dest local, src local, n/a
Mul...............R: dest, src, src
MulEq.............R: dest, src, n/a
Namespace.........R: dest, name const index, parent namespace
Neg...............R: dest, src, n/a
NewArray..........I: dest, size
NewGlobal.........R: n/a, src, const index of global name
NewTable..........I: dest, n/a
Not...............R: dest, src, n/a
NotIn.............R: dest, src value, src object
Object............R: dest, name const index, proto object
Or................R: dest, src, src
OrEq..............R: dest, src, n/a
PopCatch..........I: n/a, n/a
PopFinally........I: n/a, n/a
Precall...........R: dest, src, lookup (0 = no, 1 = yes)
PushCatch.........J: exception reg, branch offset
PushFinally.......J: n/a, branch offset
Ret...............I: base reg, num rets + 1 (0 = return all to end of stack)
SetArray..........R: dest, num fields + 1 (0 = set all to end of stack), block offset
SetAttrs..........R: dest, src, n/a
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
Throw.............R: n/a, src, n/a
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
	const uint locMaskSize = 2;
	const uint locMask = Mask!(locMaskSize) << (16 - locMaskSize);
	
	const uint locLocal =  0;
	const uint locConst =  0b01 << (16 - locMaskSize);
	const uint locUpval =  0b10 << (16 - locMaskSize);
	const uint locGlobal = 0b11 << (16 - locMaskSize);

	const uint opcodeSize = 16;
	const uint opcodeMax = (1 << opcodeSize) - 1;

	const uint rdSize = 16;
	const uint rdMax = (1 << (rdSize - locMaskSize)) - 1;

	const uint rsSize = 16;
	const uint rsMax = (1 << (rsSize - locMaskSize)) - 1;

	const uint rtSize = 16;
	const uint rtMax = (1 << (rtSize - locMaskSize)) - 1;

	const uint immSize = rsSize + rtSize;
	const uint immMax = (1 << immSize) - 1;

	const uint arraySetFields = 30;

	ushort opcode;
	ushort rd;

	union
	{
		struct
		{
			ushort rs;
			ushort rt;
		}

		uint uimm;
		int imm;
	}

	char[] toString()
	{
		char[] cr(uint v)
		{
			uint loc = v & locMask;
			uint val = v & ~locMask;

			if(loc == locLocal)
				return Stdout.layout.convert("r{}", val);
			else if(loc == locConst)
				return Stdout.layout.convert("c{}", val);
			else if(loc == locUpval)
				return Stdout.layout.convert("u{}", val);
			else
				return Stdout.layout.convert("g{}", val);
		}

		switch(opcode)
		{
			case Op.Add:             return Stdout.layout.convert("add {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.AddEq:           return Stdout.layout.convert("addeq {}, {}", cr(rd), cr(rs));
			case Op.And:             return Stdout.layout.convert("and {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.AndEq:           return Stdout.layout.convert("andeq {}, {}", cr(rd), cr(rs));
			case Op.Append:          return Stdout.layout.convert("append {}, {}", cr(rd), cr(rs));
			case Op.As:              return Stdout.layout.convert("as {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.Call:            return Stdout.layout.convert("call r{}, {}, {}", rd, rs, rt);
			case Op.Cat:             return Stdout.layout.convert("cat {}, r{}, {}", cr(rd), rs, rt);
			case Op.CatEq:           return Stdout.layout.convert("cateq {}, r{}, {}", cr(rd), rs, rt);
			case Op.Close:           return Stdout.layout.convert("close r{}", rd);
			case Op.Closure:         return Stdout.layout.convert("closure {}, {}, {}", cr(rd), rs, rt);
			case Op.CondMove:        return Stdout.layout.convert("cmov {}, {}", cr(rd), cr(rs));
			case Op.Coroutine:       return Stdout.layout.convert("coroutine {}, {}", cr(rd), cr(rs));
			case Op.Cmp:             return Stdout.layout.convert("cmp {}, {}", cr(rs), cr(rt));
			case Op.Cmp3:            return Stdout.layout.convert("cmp3 {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.Com:             return Stdout.layout.convert("com {}, {}", cr(rd), cr(rs));
			case Op.Div:             return Stdout.layout.convert("div {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.DivEq:           return Stdout.layout.convert("diveq {}, {}", cr(rd), cr(rs));
			case Op.EndFinal:        return "endfinal";
			case Op.Field:           return Stdout.layout.convert("field {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.FieldAssign:     return Stdout.layout.convert("fielda {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.For:             return Stdout.layout.convert("for {}, {}", cr(rd), imm);
			case Op.Foreach:         return Stdout.layout.convert("foreach r{}, {}", rd, uimm);
			case Op.ForLoop:         return Stdout.layout.convert("forloop {}, {}", cr(rd), imm);
			case Op.Import:          return Stdout.layout.convert("import r{}, {}", rd, cr(rs));
			case Op.In:              return Stdout.layout.convert("in {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.Index:           return Stdout.layout.convert("idx {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.IndexAssign:     return Stdout.layout.convert("idxa {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.Is:              return Stdout.layout.convert("is {}, {}", cr(rs), cr(rt));
			case Op.IsTrue:          return Stdout.layout.convert("istrue {}", cr(rs));
			case Op.Je:              return Stdout.layout.convert((rd == 0) ? "jne {}" : "je {}", imm);
			case Op.Jle:             return Stdout.layout.convert((rd == 0) ? "jgt {}" : "jle {}", imm);
			case Op.Jlt:             return Stdout.layout.convert((rd == 0) ? "jge {}" : "jlt {}", imm);
			case Op.Jmp:             return (rd == 0) ? "nop" : Stdout.layout.convert("jmp {}", imm);
			case Op.Length:          return Stdout.layout.convert("len {}, {}", cr(rd), cr(rs));
			case Op.LengthAssign:    return Stdout.layout.convert("lena {}, {}", cr(rd), cr(rs));
			case Op.LoadBool:        return Stdout.layout.convert("lb {}, {}", cr(rd), rs);
			case Op.LoadConst:       return Stdout.layout.convert("lc {}, {}", cr(rd), cr(rs));
			case Op.LoadNull:        return Stdout.layout.convert("lnull {}", cr(rd));
			case Op.LoadNulls:       return Stdout.layout.convert("lnulls r{}, {}", rd, uimm);
			case Op.Method:          return Stdout.layout.convert("method r{}, {}, {}", rd, cr(rs), cr(rt));
			case Op.MethodNC:        return Stdout.layout.convert("methodnc r{}, {}, {}", rd, cr(rs), cr(rt));
			case Op.Mod:             return Stdout.layout.convert("mod {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.ModEq:           return Stdout.layout.convert("modeq {}, {}", cr(rd), cr(rs));
			case Op.Move:            return Stdout.layout.convert("mov {}, {}", cr(rd), cr(rs));
			case Op.MoveLocal:       return Stdout.layout.convert("movl {}, {}", cr(rd), cr(rs));
			case Op.Mul:             return Stdout.layout.convert("mul {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.MulEq:           return Stdout.layout.convert("muleq {}, {}", cr(rd), cr(rs));
			case Op.Namespace:       return Stdout.layout.convert("namespace {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.Neg:             return Stdout.layout.convert("neg {}, {}", cr(rd), cr(rs));
			case Op.NewArray:        return Stdout.layout.convert("newarr r{}, {}", rd, imm);
			case Op.NewGlobal:       return Stdout.layout.convert("newg {}, {}", cr(rs), cr(rt));
			case Op.NewTable:        return Stdout.layout.convert("newtab r{}", rd);
			case Op.Not:             return Stdout.layout.convert("not {}, {}", cr(rd), cr(rs));
			case Op.NotIn:           return Stdout.layout.convert("notin {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.Object:          return Stdout.layout.convert("object {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.Or:              return Stdout.layout.convert("or {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.OrEq:            return Stdout.layout.convert("oreq {}, {}", cr(rd), cr(rs));
			case Op.PopCatch:        return "popcatch";
			case Op.PopFinally:      return "popfinally";
			case Op.Precall:         return Stdout.layout.convert("precall r{}, {}, {}", rd, cr(rs), rt);
			case Op.PushCatch:       return Stdout.layout.convert("pushcatch r{}, {}", rd, imm);
			case Op.PushFinally:     return Stdout.layout.convert("pushfinal {}", imm);
			case Op.Ret:             return Stdout.layout.convert("ret r{}, {}", rd, uimm);
			case Op.SetArray:        return Stdout.layout.convert("setarray r{}, {}, block {}", rd, rs, rt);
			case Op.SetAttrs:        return Stdout.layout.convert("setattrs r{}, r{}", rd, rs);
			case Op.Shl:             return Stdout.layout.convert("shl {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.ShlEq:           return Stdout.layout.convert("shleq {}, {}", cr(rd), cr(rs));
			case Op.Shr:             return Stdout.layout.convert("shr {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.ShrEq:           return Stdout.layout.convert("shreq {}, {}", cr(rd), cr(rs));
			case Op.Slice:           return Stdout.layout.convert("slice {}, r{}", cr(rd), rs);
			case Op.SliceAssign:     return Stdout.layout.convert("slicea r{}, {}", rd, cr(rs));
			case Op.Sub:             return Stdout.layout.convert("sub {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.SubEq:           return Stdout.layout.convert("subeq {}, {}", cr(rd), cr(rs));
			case Op.SuperMethod:     return Stdout.layout.convert("smethod r{}, {}, {}", rd, cr(rs), cr(rt));
			case Op.SuperOf:         return Stdout.layout.convert("superof {}, {}", cr(rd), cr(rs));
			case Op.Switch:          return Stdout.layout.convert("switch {}, {}", cr(rs), rt);
			case Op.SwitchCmp:       return Stdout.layout.convert("swcmp {}, {}", cr(rs), cr(rt));
			case Op.Tailcall:        return Stdout.layout.convert("tcall r{}, {}", rd, rs);
			case Op.Throw:           return Stdout.layout.convert("throw {}", cr(rs));
			case Op.UShr:            return Stdout.layout.convert("ushr {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.UShrEq:          return Stdout.layout.convert("ushreq {}, {}", cr(rd), cr(rs));
			case Op.Vararg:          return Stdout.layout.convert("varg r{}, {}", rd, uimm);
			case Op.VargIndex:       return Stdout.layout.convert("vargidx {}, {}", cr(rd), cr(rs));
			case Op.VargIndexAssign: return Stdout.layout.convert("vargidxa {}, {}", cr(rd), cr(rs));
			case Op.VargLen:         return Stdout.layout.convert("varglen {}", cr(rd));
			case Op.VargSlice:       return Stdout.layout.convert("vargslice r{}, {}", rd, uimm);
			case Op.Xor:             return Stdout.layout.convert("xor {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.XorEq:           return Stdout.layout.convert("xoreq {}, {}", cr(rd), cr(rs));
			case Op.Yield:           return Stdout.layout.convert("yield r{}, {}, {}", rd, rs, rt);
			default:                 return Stdout.layout.convert("??? opcode = ", opcode);
		}
	}
	
	private const bool SerializeAsChunk = true;
}

static assert(Instruction.sizeof == 8);