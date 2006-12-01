module minid.opcodes;

import string = std.string;

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
	Close,
	Closure,
	Cmp,
	Com,
	Div,
	DivEq,
	EndFinal,
	Foreach,
	GetGlobal,
	GetUpvalue,
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
	Method,
	Mod,
	ModEq,
	Move,
	Mul,
	MulEq,
	Neg,
	NewArray,
	NewTable,
	Not,
	Or,
	OrEq,
	PopCatch,
	PopFinally,
	PushCatch,
	PushFinally,
	Ret,
	SetArray,
	SetGlobal,
	SetUpvalue,
	Shl,
	ShlEq,
	Shr,
	ShrEq,
	Sub,
	SubEq,
	SwitchInt,
	SwitchString,
	Tailcall,
	Throw,
	UShr,
	UShrEq,
	Vararg,
	Xor,
	XorEq
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
Cat...............R: dest, src, num values + 1 (0 = use all to end of stack);
CatEq.............R: dest, src, n/a
Class.............R: dest, name const index, base class reg
Close.............I: reg start, n/a
Closure...........I: dest, index of funcdef
Cmp...............R: n/a, src, src
Com...............R: dest, src, n/a
Div...............R: dest, src, src
DivEq.............R: dest, src, n/a
EndFinal..........I: n/a, n/a
Foreach...........I: base reg, num indices
GetGlobal.........I: dest, const index of global name
GetUpvalue........I: dest, upval index
Index.............R: dest, src table/array, src index
IndexAssign.......R: dest table/array, dest index, src
Is................R: n/a, src, src
IsTrue............R: n/a, src, n/a
Je................J: isTrue, branch offset
Jle...............J: isTrue, branch offset
Jlt...............J: isTrue, branch offset
Jmp...............J: 1 = jump / 0 = don't (nop), branch offset
Length............R: dest, src, n/a
LoadBool..........R: dest, 1/0, n/a
LoadConst.........I: dest, const index
LoadNull..........I: dest, num regs
Method............R: base reg, table to index, method index
Mod...............R: dest, src, src
ModEq.............R: dest, src, n/a
Move..............R: dest, src, n/a
Mul...............R: dest, src, src
MulEq.............R: dest, src, n/a
Neg...............R: dest, src, n/a
NewArray..........I: dest, size
NewTable..........I: dest, n/a
Not...............R: dest, src, n/a
Or................R: dest, src, src
OrEq..............R: dest, src, n/a
PopCatch..........I: n/a, n/a
PopFinally........I: n/a, n/a
PushCatch.........J: exception reg, branch offset
PushFinally.......J: n/a, branch offset
Ret...............I: base reg, num rets + 1 (0 = return all to end of stack)
SetArray..........R: dest, num fields + 1 (0 = set all to end of stack), block offset
SetGlobal.........R: n/a, src, const index of global name
SetUpvalue........R: n/a, src, upval index
Shl...............R: dest, src, src
ShlEq.............R: dest, src, n/a
Shr...............R: dest, src, src
ShrEq.............R: dest, src, n/a
Sub...............R: dest, src, src
SubEq.............R: dest, src, n/a
SwitchInt.........I: src, index of switch table
SwitchString......I: src, index of switch table
Tailcall..........R: Register of func, num params + 1, n/a (0 params = use all to end of stack)
Throw.............R: n/a, src, n/a
UShr..............R: dest, src, src
UShrEq............R: dest, src, n/a
Vararg............I: base reg, num rets + 1 (0 = return all to end of stack)
Xor...............R: dest, src, src
XorEq.............R: dest, src, n/a
*/

template Mask(uint length)
{
	const uint Mask = (1 << length) - 1;
}

align(1) struct Instruction
{
	const uint rs2Size = 16;
	const uint rs2Max = (1 << rs2Size) - 1;

	const uint rs1Size = 16;
	const uint rs1Max = (1 << rs1Size) - 1;

	const uint immSize = rs1Size + rs2Size;
	const uint immMax = (1 << immSize) - 1;

	const uint rdSize = 16;
	const uint rdMax = (1 << rdSize) - 1;

	const uint opcodeSize = 16;
	const uint opcodeMax = (1 << opcodeSize) - 1;
	
	const uint constBit = 1 << (rs1Size - 1);
	const uint constMax = rs1Max >> 1; // have to account for the top bit

	const uint arraySetFields = 30;

	ushort opcode;
	ushort rd;

	union
	{
		struct
		{
			ushort rs1;
			ushort rs2;
		}

		uint uimm;
		int imm;
	}

	import std.stdio;
	
	char[] toString()
	{
		char[] cr(uint v)
		{
			if(v & constBit)
				return string.format("c%s", v & ~constBit);
			else
				return string.format("r%s", v);
		}

		switch(opcode)
		{
			case Op.Add:           return string.format("add r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.AddEq:         return string.format("addeq r%s, %s", rd, cr(rs1));
			case Op.And:           return string.format("and r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.AndEq:         return string.format("andeq r%s, %s", rd, cr(rs1));
			case Op.As:            return string.format("as r%s, r%s, r%s", rd, rs1, rs2);
			case Op.Call:          return string.format("call r%s, %s, %s", rd, rs1, rs2);
			case Op.Cat:           return string.format("cat r%s, r%s, %s", rd, rs1, rs2);
			case Op.CatEq:         return string.format("cateq r%s, %s", rd, cr(rs1));
			case Op.Class:         return string.format("class r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.Close:         return string.format("close r%s", rd);
			case Op.Closure:       return string.format("closure r%s, %s", rd, uimm);
			case Op.Cmp:           return string.format("cmp %s, %s", cr(rs1), cr(rs2));
			case Op.Com:           return string.format("com r%s, %s", rd, cr(rs1));
			case Op.Div:           return string.format("div r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.DivEq:         return string.format("diveq r%s, %s", rd, cr(rs1));
			case Op.EndFinal:      return "endfinal";
			case Op.Foreach:       return string.format("foreach r%s, %s", rd, uimm);
			case Op.GetGlobal:     return string.format("getg r%s, c%s", rd, uimm);
			case Op.GetUpvalue:    return string.format("getu r%s, %s", rd, uimm);
			case Op.Index:         return string.format("idx r%s, r%s, %s", rd, rs1, cr(rs2));
			case Op.IndexAssign:   return string.format("idxa r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.Is:            return string.format("is %s, %s", cr(rs1), cr(rs2));
			case Op.IsTrue:        return string.format("istrue %s", cr(rs1));

			case Op.Je:
				if(rd == 0)
					return string.format("jne %s", imm);
				else
					return string.format("je %s", imm);
			case Op.Jle:
				if(rd == 0)
					return string.format("jgt %s", imm);
				else
					return string.format("jle %s", imm);
			case Op.Jlt:
				if(rd == 0)
					return string.format("jge %s", imm);
				else
					return string.format("jlt %s", imm);
			case Op.Jmp:
				if(rd == 0)
					return "nop";
				else
					return string.format("jmp %s", imm);

			case Op.Length:        return string.format("len r%s, %s", rd, cr(rs1));
			case Op.LoadBool:      return string.format("lb r%s, %s", rd, rs1);
			case Op.LoadConst:     return string.format("lc r%s, c%s", rd, uimm);
			case Op.LoadNull:      return string.format("lnull r%s, %s", rd, uimm);
			case Op.Method:        return string.format("method r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.Mod:           return string.format("mod r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.ModEq:         return string.format("modeq r%s, %s", rd, cr(rs1));
			case Op.Move:          return string.format("mov r%s, r%s", rd, rs1);
			case Op.Mul:           return string.format("mul r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.MulEq:         return string.format("muleq r%s, %s", rd, cr(rs1));
			case Op.Neg:           return string.format("neg r%s, %s", rd, cr(rs1));
			case Op.NewArray:      return string.format("newarr r%s, %s", rd, imm);
			case Op.NewTable:      return string.format("newtab r%s", rd);
			case Op.Not:           return string.format("not r%s, %s", rd, cr(rs1));
			case Op.Or:            return string.format("or r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.OrEq:          return string.format("oreq r%s, %s", rd, cr(rs1));
			case Op.PopCatch:      return "popcatch";
			case Op.PopFinally:    return "popfinally";
			case Op.PushCatch:     return string.format("pushcatch r%s, %s", rd, imm);
			case Op.PushFinally:   return string.format("pushfinal %s", imm);
			case Op.Ret:           return string.format("ret r%s, %s", rd, uimm);
			case Op.SetArray:      return string.format("setarray r%s, %s, block %s", rd, rs1, rs2);
			case Op.SetGlobal:     return string.format("setg %s, c%s", cr(rs1), rs2);
			case Op.SetUpvalue:    return string.format("setu %s, c%s", cr(rs1), rs2);
			case Op.Shl:           return string.format("shl r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.ShlEq:         return string.format("shleq r%s, %s", rd, cr(rs1));
			case Op.Shr:           return string.format("shr r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.ShrEq:         return string.format("shreq r%s, %s", rd, cr(rs1));
			case Op.Sub:           return string.format("sub r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.SubEq:         return string.format("subeq r%s, %s", rd, cr(rs1));
			case Op.SwitchInt:     return string.format("iswitch r%s, %s", rd, uimm);
			case Op.SwitchString:  return string.format("sswitch r%s, %s", rd, uimm);
			case Op.Tailcall:      return string.format("tcall r%s, %s", rd, rs1);
			case Op.Throw:         return string.format("throw %s", cr(rs1));
			case Op.UShr:          return string.format("ushr r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.UShrEq:        return string.format("ushreq r%s, %s", rd, cr(rs1));
			case Op.Vararg:        return string.format("varg r%s, %s", rd, uimm);
			case Op.Xor:           return string.format("xor r%s, %s, %s", rd, cr(rs1), cr(rs2));
			case Op.XorEq:         return string.format("xoreq r%s, %s", rd, cr(rs1));
			default:               return string.format("??? opcode = ", opcode);
		}
	}
}

static assert(Instruction.sizeof == 8);