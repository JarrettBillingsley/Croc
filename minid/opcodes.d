/******************************************************************************
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

module minid.opcodes;

import tango.text.convert.Format;

const uint MaxRegisters = Instruction.rsMax;
const uint MaxConstants = Instruction.rsMax;
const uint MaxUpvalues = Instruction.rsMax;

enum Op : ushort
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
	CheckObjParam,
	CheckParams,
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
	NamespaceNP,
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
	SetEnv,
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
Cat...............R: dest, src, num values (NOT variadic)
CatEq.............R: dest, src, num values (NOT variadic)
CheckObjParam.....R: n/a, index of parameter, object type
CheckParams.......I: n/a, n/a
Close.............I: reg start, n/a
Closure...........R: dest, index of funcdef, n/a
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
NamespaceNP.......R: dest, name const index, n/a
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
SetEnv............R: dest, src, n/a
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

	Op opcode;
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
				return Format.convert("r{}", val);
			else if(loc == locConst)
				return Format.convert("c{}", val);
			else if(loc == locUpval)
				return Format.convert("u{}", val);
			else
				return Format.convert("g{}", val);
		}

		switch(opcode)
		{
			case Op.Add:             return Format.convert("add {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.AddEq:           return Format.convert("addeq {}, {}", cr(rd), cr(rs));
			case Op.And:             return Format.convert("and {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.AndEq:           return Format.convert("andeq {}, {}", cr(rd), cr(rs));
			case Op.Append:          return Format.convert("append {}, {}", cr(rd), cr(rs));
			case Op.As:              return Format.convert("as {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.Call:            return Format.convert("call r{}, {}, {}", rd, rs, rt);
			case Op.Cat:             return Format.convert("cat {}, r{}, {}", cr(rd), rs, rt);
			case Op.CatEq:           return Format.convert("cateq {}, r{}, {}", cr(rd), rs, rt);
			case Op.CheckObjParam:   return Format.convert("checkobjparm r{}, {}", rs, cr(rt));
			case Op.CheckParams:     return "checkparams";
			case Op.Close:           return Format.convert("close r{}", rd);
			case Op.Closure:         return Format.convert("closure {}, {}", cr(rd), rs);
			case Op.CondMove:        return Format.convert("cmov {}, {}", cr(rd), cr(rs));
			case Op.Coroutine:       return Format.convert("coroutine {}, {}", cr(rd), cr(rs));
			case Op.Cmp:             return Format.convert("cmp {}, {}", cr(rs), cr(rt));
			case Op.Cmp3:            return Format.convert("cmp3 {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.Com:             return Format.convert("com {}, {}", cr(rd), cr(rs));
			case Op.Dec:             return Format.convert("dec {}", cr(rd));
			case Op.Div:             return Format.convert("div {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.DivEq:           return Format.convert("diveq {}, {}", cr(rd), cr(rs));
			case Op.EndFinal:        return "endfinal";
			case Op.Field:           return Format.convert("field {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.FieldAssign:     return Format.convert("fielda {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.For:             return Format.convert("for {}, {}", cr(rd), imm);
			case Op.Foreach:         return Format.convert("foreach r{}, {}", rd, uimm);
			case Op.ForLoop:         return Format.convert("forloop {}, {}", cr(rd), imm);
			case Op.Import:          return Format.convert("import r{}, {}", rd, cr(rs));
			case Op.In:              return Format.convert("in {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.Inc:             return Format.convert("inc {}", cr(rd));
			case Op.Index:           return Format.convert("idx {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.IndexAssign:     return Format.convert("idxa {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.Is:              return Format.convert("is {}, {}", cr(rs), cr(rt));
			case Op.IsTrue:          return Format.convert("istrue {}", cr(rs));
			case Op.Je:              return Format.convert((rd == 0) ? "jne {}" : "je {}", imm);
			case Op.Jle:             return Format.convert((rd == 0) ? "jgt {}" : "jle {}", imm);
			case Op.Jlt:             return Format.convert((rd == 0) ? "jge {}" : "jlt {}", imm);
			case Op.Jmp:             return (rd == 0) ? "nop" : Format.convert("jmp {}", imm);
			case Op.Length:          return Format.convert("len {}, {}", cr(rd), cr(rs));
			case Op.LengthAssign:    return Format.convert("lena {}, {}", cr(rd), cr(rs));
			case Op.LoadBool:        return Format.convert("lb {}, {}", cr(rd), rs);
			case Op.LoadConst:       return Format.convert("lc {}, {}", cr(rd), cr(rs));
			case Op.LoadNull:        return Format.convert("lnull {}", cr(rd));
			case Op.LoadNulls:       return Format.convert("lnulls r{}, {}", rd, uimm);
			case Op.Method:          return Format.convert("method r{}, {}, {}", rd, cr(rs), cr(rt));
			case Op.MethodNC:        return Format.convert("methodnc r{}, {}, {}", rd, cr(rs), cr(rt));
			case Op.Mod:             return Format.convert("mod {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.ModEq:           return Format.convert("modeq {}, {}", cr(rd), cr(rs));
			case Op.Move:            return Format.convert("mov {}, {}", cr(rd), cr(rs));
			case Op.MoveLocal:       return Format.convert("movl {}, {}", cr(rd), cr(rs));
			case Op.Mul:             return Format.convert("mul {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.MulEq:           return Format.convert("muleq {}, {}", cr(rd), cr(rs));
			case Op.Namespace:       return Format.convert("namespace {}, c{}, {}", cr(rd), rs, cr(rt));
			case Op.NamespaceNP:     return Format.convert("namespacenp {}, c{}", cr(rd), rs);
			case Op.Neg:             return Format.convert("neg {}, {}", cr(rd), cr(rs));
			case Op.NewArray:        return Format.convert("newarr r{}, {}", rd, imm);
			case Op.NewGlobal:       return Format.convert("newg {}, {}", cr(rs), cr(rt));
			case Op.NewTable:        return Format.convert("newtab r{}", rd);
			case Op.Not:             return Format.convert("not {}, {}", cr(rd), cr(rs));
			case Op.NotIn:           return Format.convert("notin {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.Object:          return Format.convert("object {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.Or:              return Format.convert("or {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.OrEq:            return Format.convert("oreq {}, {}", cr(rd), cr(rs));
			case Op.PopCatch:        return "popcatch";
			case Op.PopFinally:      return "popfinally";
			case Op.Precall:         return Format.convert("precall r{}, {}, {}", rd, cr(rs), rt);
			case Op.PushCatch:       return Format.convert("pushcatch r{}, {}", rd, imm);
			case Op.PushFinally:     return Format.convert("pushfinal {}", imm);
			case Op.Ret:             return Format.convert("ret r{}, {}", rd, uimm);
			case Op.SetArray:        return Format.convert("setarray r{}, {}, block {}", rd, rs, rt);
			case Op.SetEnv:          return Format.convert("setenv {}, {}", cr(rd), cr(rs));
			case Op.Shl:             return Format.convert("shl {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.ShlEq:           return Format.convert("shleq {}, {}", cr(rd), cr(rs));
			case Op.Shr:             return Format.convert("shr {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.ShrEq:           return Format.convert("shreq {}, {}", cr(rd), cr(rs));
			case Op.Slice:           return Format.convert("slice {}, r{}", cr(rd), rs);
			case Op.SliceAssign:     return Format.convert("slicea r{}, {}", rd, cr(rs));
			case Op.Sub:             return Format.convert("sub {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.SubEq:           return Format.convert("subeq {}, {}", cr(rd), cr(rs));
			case Op.SuperMethod:     return Format.convert("smethod r{}, {}, {}", rd, cr(rs), cr(rt));
			case Op.SuperOf:         return Format.convert("superof {}, {}", cr(rd), cr(rs));
			case Op.Switch:          return Format.convert("switch {}, {}", cr(rs), rt);
			case Op.SwitchCmp:       return Format.convert("swcmp {}, {}", cr(rs), cr(rt));
			case Op.Tailcall:        return Format.convert("tcall r{}, {}", rd, rs);
			case Op.Throw:           return Format.convert("throw {}", cr(rs));
			case Op.UShr:            return Format.convert("ushr {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.UShrEq:          return Format.convert("ushreq {}, {}", cr(rd), cr(rs));
			case Op.Vararg:          return Format.convert("varg r{}, {}", rd, uimm);
			case Op.VargIndex:       return Format.convert("vargidx {}, {}", cr(rd), cr(rs));
			case Op.VargIndexAssign: return Format.convert("vargidxa {}, {}", cr(rd), cr(rs));
			case Op.VargLen:         return Format.convert("varglen {}", cr(rd));
			case Op.VargSlice:       return Format.convert("vargslice r{}, {}", rd, uimm);
			case Op.Xor:             return Format.convert("xor {}, {}, {}", cr(rd), cr(rs), cr(rt));
			case Op.XorEq:           return Format.convert("xoreq {}, {}", cr(rd), cr(rs));
			case Op.Yield:           return Format.convert("yield r{}, {}, {}", rd, rs, rt);
			default:                 return Format.convert("??? opcode = {}", opcode);
		}
	}
	
	private const bool SerializeAsChunk = true;
}

static assert(Instruction.sizeof == 8);