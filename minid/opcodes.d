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

import string = std.string;
import std.stream;

const uint MaxRegisters = Instruction.rsMax;
const uint MaxConstants = Instruction.rsMax;
const uint MaxUpvalues = Instruction.rsMax;

enum Op : uint
{
	Add,
	AddEq,
	And,
	AndEq,
	As,
	Call,
	Cat,
	CatEq,
	Class,
	ClassOf,
	Close,
	Closure,
	CondMove,
	Coroutine,
	Cmp,
	Cmp3,
	Com,
	Div,
	DivEq,
	EndFinal,
	For,
	Foreach,
	ForLoop,
	In,
	Index,
	IndexAssign,
	Is,
	IsTrue,
	Je,
	Jle,
	Jlt,
	Jmp,
	Length,
	LoadBool,
	LoadConst,
	LoadNull,
	LoadNulls,
	Method,
	Mod,
	ModEq,
	Move,
	MoveLocal,
	Mul,
	MulEq,
	Neg,
	NewArray,
	NewGlobal,
	NewTable,
	Not,
	NotIn,
	Or,
	OrEq,
	PopCatch,
	PopFinally,
	Precall,
	PushCatch,
	PushFinally,
	Ret,
	SetArray,
	Shl,
	ShlEq,
	Shr,
	ShrEq,
	Slice,
	SliceAssign,
	Sub,
	SubEq,
	Super,
	Switch,
	SwitchCmp,
	Tailcall,
	Throw,
	UShr,
	UShrEq,
	Vararg,
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
As................R: dest, src, src class
Call..............R: register of func, num params + 1, num results + 1 (both, 0 = use all to end of stack)
Cat...............R: dest, src, num values + 1 (0 = use all to end of stack)
CatEq.............R: dest, src, num values + 1 (0 = use all to end of stack)
Class.............R: dest, name const index, base class reg
ClassOf...........R: dest, src, n/a
Close.............I: reg start, n/a
Closure...........I: dest, index of funcdef
CondMove..........R: dest, src, n/a
Coroutine.........R: dest, src, n/a
Cmp...............R: n/a, src, src
Cmp3..............R: dest, src, src
Com...............R: dest, src, n/a
Div...............R: dest, src, src
DivEq.............R: dest, src, n/a
EndFinal..........I: n/a, n/a
For...............J: base reg, branch offset
Foreach...........I: base reg, num indices
ForLoop...........J: base reg, branch offset
In................R: dest, src value, src object
Index.............R: dest, src object, src index
IndexAssign.......R: dest object, dest index, src
Is................R: n/a, src, src
IsTrue............R: n/a, src, n/a
Je................J: isTrue, branch offset
Jle...............J: isTrue, branch offset
Jlt...............J: isTrue, branch offset
Jmp...............J: 1 = jump / 0 = don't (nop), branch offset
Length............R: dest, src, n/a
LoadBool..........R: dest, 1/0, n/a
LoadConst.........R: dest local, src const, n/a
LoadNull..........I: dest, n/a
LoadNulls.........I: dest, num regs
Method............R: base reg, object to index, const index of method name
Mod...............R: dest, src, src
ModEq.............R: dest, src, n/a
Move..............R: dest, src, n/a
MoveLocal.........R: dest local, src local, n/a
Mul...............R: dest, src, src
MulEq.............R: dest, src, n/a
Neg...............R: dest, src, n/a
NewArray..........I: dest, size
NewGlobal.........R: n/a, src, const index of global name
NewTable..........I: dest, n/a
Not...............R: dest, src, n/a
NotIn.............R: dest, src value, src object
Or................R: dest, src, src
OrEq..............R: dest, src, n/a
PopCatch..........I: n/a, n/a
PopFinally........I: n/a, n/a
Precall...........R: dest, src, lookup (0 = no, 1 = yes)
PushCatch.........J: exception reg, branch offset
PushFinally.......J: n/a, branch offset
Ret...............I: base reg, num rets + 1 (0 = return all to end of stack)
SetArray..........R: dest, num fields + 1 (0 = set all to end of stack), block offset
Shl...............R: dest, src, src
ShlEq.............R: dest, src, n/a
Shr...............R: dest, src, src
ShrEq.............R: dest, src, n/a
Slice.............R: dest, src, n/a (indices are at src + 1 and src + 2)
SliceAssign.......R: dest, src, n/a (indices are at dest + 1 and dest + 2)
Sub...............R: dest, src, src
SubEq.............R: dest, src, n/a
Super.............R: dest, src, n/a
Switch............R: n/a, src, index of switch table
SwitchCmp.........R: n/a, src, src
Tailcall..........R: Register of func, num params + 1, n/a (0 params = use all to end of stack)
Throw.............R: n/a, src, n/a
UShr..............R: dest, src, src
UShrEq............R: dest, src, n/a
Vararg............I: base reg, num rets + 1 (0 = return all to end of stack)
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

	import std.stdio;
	
	char[] toString()
	{
		char[] cr(uint v)
		{
			uint loc = v & locMask;
			uint val = v & ~locMask;

			if(loc == locLocal)
				return string.format("r%s", val);
			else if(loc == locConst)
				return string.format("c%s", val);
			else if(loc == locUpval)
				return string.format("u%s", val);
			else
				return string.format("g%s", val);
		}

		switch(opcode)
		{
			case Op.Add:           return string.format("add %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.AddEq:         return string.format("addeq %s, %s", cr(rd), cr(rs));
			case Op.And:           return string.format("and %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.AndEq:         return string.format("andeq %s, %s", cr(rd), cr(rs));
			case Op.As:            return string.format("as %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.Call:          return string.format("call r%s, %s, %s", rd, rs, rt);
			case Op.Cat:           return string.format("cat %s, r%s, %s", cr(rd), rs, rt);
			case Op.CatEq:         return string.format("cateq %s, r%s, %s", cr(rd), rs, rt);
			case Op.Class:         return string.format("class %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.ClassOf:       return string.format("classof %s, %s", cr(rd), cr(rs));
			case Op.Close:         return string.format("close r%s", rd);
			case Op.Closure:       return string.format("closure %s, %s", cr(rd), uimm);
			case Op.CondMove:      return string.format("cmov %s, %s", cr(rd), cr(rs));
			case Op.Coroutine:     return string.format("coroutine %s, %s", cr(rd), cr(rs));
			case Op.Cmp:           return string.format("cmp %s, %s", cr(rs), cr(rt));
			case Op.Cmp3:          return string.format("cmp3 %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.Com:           return string.format("com %s, %s", cr(rd), cr(rs));
			case Op.Div:           return string.format("div %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.DivEq:         return string.format("diveq %s, %s", cr(rd), cr(rs));
			case Op.EndFinal:      return "endfinal";
			case Op.For:           return string.format("for %s, %s", cr(rd), imm);
			case Op.Foreach:       return string.format("foreach r%s, %s", rd, uimm);
			case Op.ForLoop:       return string.format("forloop %s, %s", cr(rd), imm);
			case Op.In:            return string.format("in %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.Index:         return string.format("idx %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.IndexAssign:   return string.format("idxa %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.Is:            return string.format("is %s, %s", cr(rs), cr(rt));
			case Op.IsTrue:        return string.format("istrue %s", cr(rs));
			case Op.Je:            return string.format((rd == 0) ? "jne %s" : "je % s", imm);
			case Op.Jle:           return string.format((rd == 0) ? "jgt %s" : "jle % s", imm);
			case Op.Jlt:           return string.format((rd == 0) ? "jge %s" : "jlt % s", imm);
			case Op.Jmp:           return (rd == 0) ? "nop" : string.format("jmp %s", imm);
			case Op.Length:        return string.format("len %s, %s", cr(rd), cr(rs));
			case Op.LoadBool:      return string.format("lb %s, %s", cr(rd), rs);
			case Op.LoadConst:     return string.format("lc %s, %s", cr(rd), cr(rs));
			case Op.LoadNull:      return string.format("lnull %s", cr(rd));
			case Op.LoadNulls:     return string.format("lnulls r%s, %s", rd, uimm);
			case Op.Method:        return string.format("method r%s, %s, c%s", rd, cr(rs), rt);
			case Op.Mod:           return string.format("mod %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.ModEq:         return string.format("modeq %s, %s", cr(rd), cr(rs));
			case Op.Move:          return string.format("mov %s, %s", cr(rd), cr(rs));
			case Op.MoveLocal:     return string.format("movl %s, %s", cr(rd), cr(rs));
			case Op.Mul:           return string.format("mul %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.MulEq:         return string.format("muleq %s, %s", cr(rd), cr(rs));
			case Op.Neg:           return string.format("neg %s, %s", cr(rd), cr(rs));
			case Op.NewArray:      return string.format("newarr r%s, %s", rd, imm);
			case Op.NewGlobal:     return string.format("newg %s, %s", cr(rs), cr(rt));
			case Op.NewTable:      return string.format("newtab r%s", rd);
			case Op.Not:           return string.format("not %s, %s", cr(rd), cr(rs));
			case Op.NotIn:         return string.format("notin %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.Or:            return string.format("or %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.OrEq:          return string.format("oreq %s, %s", cr(rd), cr(rs));
			case Op.PopCatch:      return "popcatch";
			case Op.PopFinally:    return "popfinally";
			case Op.Precall:       return string.format("precall r%s, %s, %s", rd, cr(rs), rt);
			case Op.PushCatch:     return string.format("pushcatch r%s, %s", rd, imm);
			case Op.PushFinally:   return string.format("pushfinal %s", imm);
			case Op.Ret:           return string.format("ret r%s, %s", rd, uimm);
			case Op.SetArray:      return string.format("setarray r%s, %s, block %s", rd, rs, rt);
			case Op.Shl:           return string.format("shl %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.ShlEq:         return string.format("shleq %s, %s", cr(rd), cr(rs));
			case Op.Shr:           return string.format("shr %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.ShrEq:         return string.format("shreq %s, %s", cr(rd), cr(rs));
			case Op.Slice:         return string.format("slice %s, r%s", cr(rd), rs);
			case Op.SliceAssign:   return string.format("slicea r%s, %s", rd, cr(rs));
			case Op.Super:         return string.format("super %s, %s", cr(rd), cr(rs));
			case Op.Sub:           return string.format("sub %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.SubEq:         return string.format("subeq %s, %s", cr(rd), cr(rs));
			case Op.Switch:        return string.format("switch %s, %s", cr(rs), rt);
			case Op.SwitchCmp:     return string.format("swcmp %s, %s", cr(rs), cr(rt));
			case Op.Tailcall:      return string.format("tcall r%s, %s", rd, rs);
			case Op.Throw:         return string.format("throw %s", cr(rs));
			case Op.UShr:          return string.format("ushr %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.UShrEq:        return string.format("ushreq %s, %s", cr(rd), cr(rs));
			case Op.Vararg:        return string.format("varg r%s, %s", rd, uimm);
			case Op.Xor:           return string.format("xor %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.XorEq:         return string.format("xoreq %s, %s", cr(rd), cr(rs));
			case Op.Yield:         return string.format("yield r%s, %s, %s", rd, rs, rt);
			default:               return string.format("??? opcode = ", opcode);
		}
	}
	
	void serialize(Stream s)
	{
		s.writeExact(this, Instruction.sizeof);
	}
	
	static Instruction deserialize(Stream s)
	{
		Instruction ret;
		s.readExact(&ret, Instruction.sizeof);
		return ret;
	}
	
	private const bool SerializeAsChunk = true;
}

static assert(Instruction.sizeof == 8);