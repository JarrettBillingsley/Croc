/******************************************************************************
This module contains the enumeration of MiniD bytecode opcodes, as well as
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

module minid.opcodes;

import std.string;

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
	Class,
	Close,
	Closure,
	Coroutine,
	Cmp,
	Cmp3,
	Com,
	Dec,
	Div,
	DivEq,
	EndFinal,
	Equals,
	Field,
	FieldAssign,
	For,
	Foreach,
	ForeachLoop,
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
	ObjParamFail,
	Or,
	OrEq,
	PopCatch,
	PopFinally,
	PushCatch,
	PushFinally,
	Ret,
	SaveRets,
	SetArray,
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
	Unwind,
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
CheckObjParam.....R: dest, index of parameter, object type
CheckParams.......I: n/a, n/a
Class.............R: dest, name const index, base class
Close.............I: reg start, n/a
Closure...........R: dest, index of funcdef, environment (0 = use current function's environment)
Coroutine.........R: dest, src, n/a
Cmp...............R: n/a, src, src
Cmp3..............R: dest, src, src
Com...............R: dest, src, n/a
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
Throw.............R: n/a, src, n/a
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

	string toString()
	{
		string cr(uint v)
		{
			uint loc = v & locMask;
			uint val = v & ~locMask;

			if(loc == locLocal)
				return format("r%s", val);
			else if(loc == locConst)
				return format("c%s", val);
			else if(loc == locUpval)
				return format("u%s", val);
			else
				return format("g%s", val);
		}

		switch(opcode)
		{
			case Op.Add:             return format("add %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.AddEq:           return format("addeq %s, %s", cr(rd), cr(rs));
			case Op.And:             return format("and %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.AndEq:           return format("andeq %s, %s", cr(rd), cr(rs));
			case Op.Append:          return format("append %s, %s", cr(rd), cr(rs));
			case Op.As:              return format("as %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.Call:            return format("call r%s, %s, %s", rd, rs, rt);
			case Op.Cat:             return format("cat %s, r%s, %s", cr(rd), rs, rt);
			case Op.CatEq:           return format("cateq %s, r%s, %s", cr(rd), rs, rt);
			case Op.CheckObjParam:   return format("checkobjparm r%s, r%s, %s", rd, rs, cr(rt));
			case Op.CheckParams:     return "checkparams";
			case Op.Class:           return format("class %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.Close:           return format("close r%s", rd);
			case Op.Closure:         return rt == 0 ? format("closure %s, %s", cr(rd), rs) : format("closure %s, %s, r%s", cr(rd), rs, rt);
			case Op.Coroutine:       return format("coroutine %s, %s", cr(rd), cr(rs));
			case Op.Cmp:             return format("cmp %s, %s", cr(rs), cr(rt));
			case Op.Cmp3:            return format("cmp3 %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.Com:             return format("com %s, %s", cr(rd), cr(rs));
			case Op.Dec:             return format("dec %s", cr(rd));
			case Op.Div:             return format("div %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.DivEq:           return format("diveq %s, %s", cr(rd), cr(rs));
			case Op.EndFinal:        return "endfinal";
			case Op.Equals:          return format("equals %s, %s", cr(rs), cr(rt));
			case Op.Field:           return format("field %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.FieldAssign:     return format("fielda %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.For:             return format("for %s, %s", cr(rd), imm);
			case Op.Foreach:         return format("foreach r%s, %s", rd, imm);
			case Op.ForeachLoop:     return format("foreachloop r%s, %s", rd, uimm);
			case Op.ForLoop:         return format("forloop %s, %s", cr(rd), imm);
			case Op.Import:          return format("import r%s, %s", rd, cr(rs));
			case Op.In:              return format("in %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.Inc:             return format("inc %s", cr(rd));
			case Op.Index:           return format("idx %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.IndexAssign:     return format("idxa %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.Is:              return format("is %s, %s", cr(rs), cr(rt));
			case Op.IsTrue:          return format("istrue %s", cr(rs));
			case Op.Je:              return format((rd == 0) ? "jne %s" : "je %s", imm);
			case Op.Jle:             return format((rd == 0) ? "jgt %s" : "jle %s", imm);
			case Op.Jlt:             return format((rd == 0) ? "jge %s" : "jlt %s", imm);
			case Op.Jmp:             return (rd == 0) ? "nop" : format("jmp %s", imm);
			case Op.Length:          return format("len %s, %s", cr(rd), cr(rs));
			case Op.LengthAssign:    return format("lena %s, %s", cr(rd), cr(rs));
			case Op.LoadBool:        return format("lb %s, %s", cr(rd), rs);
			case Op.LoadConst:       return format("lc %s, %s", cr(rd), cr(rs));
			case Op.LoadNull:        return format("lnull %s", cr(rd));
			case Op.LoadNulls:       return format("lnulls r%s, %s", rd, uimm);
			case Op.Method:          return format("method r%s, %s, %s", rd, cr(rs), cr(rt));
			case Op.MethodNC:        return format("methodnc r%s, %s, %s", rd, cr(rs), cr(rt));
			case Op.Mod:             return format("mod %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.ModEq:           return format("modeq %s, %s", cr(rd), cr(rs));
			case Op.Move:            return format("mov %s, %s", cr(rd), cr(rs));
			case Op.MoveLocal:       return format("movl %s, %s", cr(rd), cr(rs));
			case Op.Mul:             return format("mul %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.MulEq:           return format("muleq %s, %s", cr(rd), cr(rs));
			case Op.Namespace:       return format("namespace %s, c%s, %s", cr(rd), rs, cr(rt));
			case Op.NamespaceNP:     return format("namespacenp %s, c%s", cr(rd), rs);
			case Op.Neg:             return format("neg %s, %s", cr(rd), cr(rs));
			case Op.NewArray:        return format("newarr r%s, %s", rd, imm);
			case Op.NewGlobal:       return format("newg %s, %s", cr(rs), cr(rt));
			case Op.NewTable:        return format("newtab r%s", rd);
			case Op.Not:             return format("not %s, %s", cr(rd), cr(rs));
			case Op.NotIn:           return format("notin %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.ObjParamFail:    return format("objparamfail %s", cr(rs));
			case Op.Or:              return format("or %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.OrEq:            return format("oreq %s, %s", cr(rd), cr(rs));
			case Op.PopCatch:        return "popcatch";
			case Op.PopFinally:      return "popfinally";
			case Op.PushCatch:       return format("pushcatch r%s, %s", rd, imm);
			case Op.PushFinally:     return format("pushfinal r%s, %s", rd, imm);
			case Op.Ret:             return "ret";
			case Op.SaveRets:        return format("saverets r%s, %s", rd, uimm);
			case Op.SetArray:        return format("setarray r%s, %s, block %s", rd, rs, rt);
			case Op.Shl:             return format("shl %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.ShlEq:           return format("shleq %s, %s", cr(rd), cr(rs));
			case Op.Shr:             return format("shr %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.ShrEq:           return format("shreq %s, %s", cr(rd), cr(rs));
			case Op.Slice:           return format("slice %s, r%s", cr(rd), rs);
			case Op.SliceAssign:     return format("slicea r%s, %s", rd, cr(rs));
			case Op.Sub:             return format("sub %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.SubEq:           return format("subeq %s, %s", cr(rd), cr(rs));
			case Op.SuperMethod:     return format("smethod r%s, %s, %s", rd, cr(rs), cr(rt));
			case Op.SuperOf:         return format("superof %s, %s", cr(rd), cr(rs));
			case Op.Switch:          return format("switch %s, %s", cr(rs), rt);
			case Op.SwitchCmp:       return format("swcmp %s, %s", cr(rs), cr(rt));
			case Op.Tailcall:        return format("tcall r%s, %s", rd, rs);
			case Op.Throw:           return format("throw %s", cr(rs));
			case Op.Unwind:          return format("unwind %s", uimm);
			case Op.UShr:            return format("ushr %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.UShrEq:          return format("ushreq %s, %s", cr(rd), cr(rs));
			case Op.Vararg:          return format("varg r%s, %s", rd, uimm);
			case Op.VargIndex:       return format("vargidx %s, %s", cr(rd), cr(rs));
			case Op.VargIndexAssign: return format("vargidxa %s, %s", cr(rd), cr(rs));
			case Op.VargLen:         return format("varglen %s", cr(rd));
			case Op.VargSlice:       return format("vargslice r%s, %s", rd, uimm);
			case Op.Xor:             return format("xor %s, %s, %s", cr(rd), cr(rs), cr(rt));
			case Op.XorEq:           return format("xoreq %s, %s", cr(rd), cr(rs));
			case Op.Yield:           return format("yield r%s, %s, %s", rd, rs, rt);
			default:                 return format("??? opcode = %s", opcode);
		}
	}
}

static assert(Instruction.sizeof == 8);