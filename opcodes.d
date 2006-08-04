module opcodes;

enum Op : uint
{
	Add,
	And,
	Call,
	Cat,
	Close,
	Closure,
	Cmp,
	Com,
	Div,
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
	Move,
	Mul,
	Neg,
	NewArray,
	NewTable,
	Not,
	Or,
	PopCatch,
	PopFinally,
	PushCatch,
	PushFinally,
	Ret,
	SetGlobal,
	SetUpvalue,
	Shl,
	Shr,
	Sub,
	SwitchInt,
	SwitchString,
	Throw,
	UShr,
	Vararg,
	Xor
}

/*
Add...............R: dest, src, src
And...............R: dest, src, src
Call..............R: register of func, num params + 1, num results + 1 (both, 0 = use all to end of stack)
Cat...............R: dest, src, src
Close.............I: reg start, n/a
Closure...........I: dest, index of funcdef
Cmp...............R: n/a, src, src
Com...............R: dest, src, n/a
Div...............R: dest, src, src
Foreach...........I: base reg, num indices
GetGlobal.........I: dest, const index of global name
GetUpvalue........I: dest, upval index
Index.............R: dest, src table/array, src index
IndexAssign.......R: dest table/array, src index, src
Is................R: n/a, src, src
IsTrue............R: n/a, src, n/a
Je................J: isTrue, branch offset
Jle...............J: isTrue, branch offset
Jlt...............J: isTrue, branch offset
Jmp...............J: 0 = jump / 1 = don't (nop), branch offset
Length............R: dest, src, n/a
LoadBool..........R: dest, 1/0, n/a
LoadConst.........I: dest, const index
LoadNull..........R: dest, n/a, n/a
Method............R: base reg, table to index, method index
Mod...............R: dest, src, src
Move..............R: dest, src, n/a
Mul...............R: dest, src, src
Neg...............R: dest, src, n/a
NewArray..........I: dest, size
NewTable..........I: dest, n/a
Not...............R: dest, src, n/a
Or................R: dest, src, src
PopCatch..........?
PopFinally........?
PushCatch.........?
PushFinally.......?
Ret...............I: base reg, num rets + 1 (0 = return all to end of stack)
SetGlobal.........I: src, const index of global name
SetUpvalue........I: src, upval index
Shl...............R: dest, src, src
Shr...............R: dest, src, src
Sub...............R: dest, src, src
SwitchInt.........I: src, index of switch table
SwitchString......I: src, index of switch table
Throw.............I: src, n/a
UShr..............R: dest, src, src
Vararg............I: base reg, num rets + 1 (0 = return all to end of stack)
Xor...............R: dest, src, src
*/

template Mask(uint length)
{
	const uint Mask = (1 << length) - 1;
}

struct Instruction
{
	const uint rs2Size = 9;
	const uint rs2Max = (1 << rs2Size) - 1;
	const uint rs2Mask = Mask!(rs2Size);
	const uint rs2Pos = 0;

	const uint rs1Size = 9;
	const uint rs1Max = (1 << rs1Size) - 1;
	const uint rs1Mask = Mask!(rs1Size);
	const uint rs1Pos = rs2Pos + rs2Size;
	
	const uint immSize = rs1Size + rs2Size;
	const uint immMax = (1 << immSize) - 1;
	const uint immMask = Mask!(immSize);
	const uint immPos = rs2Pos;
	const uint immBias = (immMax + 1) / 2;

	const uint rdSize = 8;
	const uint rdMax = (1 << rdSize) - 1;
	const uint rdMask = Mask!(rdSize);
	const uint rdPos = rs1Pos + rs1Size;

	const uint opcodeSize = 6;
	const uint opcodeMask = Mask!(opcodeSize);
	const uint opcodePos = rdPos + rdSize;
	
	const uint constBit = 1 << (rs2Size - 1);

	uint data;
	
	uint rs2()
	{
		return (data >> rs2Pos)	& rs2Mask;
	}
	
	uint rs2(uint value)
	{
		data = (data & ~(rs2Mask << rs2Pos)) | ((value & rs2Mask) << rs2Pos);
		return value;
	}
	
	uint rs1()
	{
		return (data >> rs1Pos)	& rs1Mask;
	}
	
	uint rs1(uint value)
	{
		data = (data & ~(rs1Mask << rs1Pos)) | ((value & rs1Mask) << rs1Pos);
		return value;
	}
	
	uint imm()
	{
		return (data >> immPos)	& immMask;
	}
	
	uint imm(uint value)
	{
		data = (data & ~(immMask << immPos)) | ((value & immMask) << immPos);
		return value;
	}
	
	uint rd()
	{
		return (data >> rdPos)	& rdMask;
	}
	
	uint rd(uint value)
	{
		data = (data & ~(rdMask << rdPos)) | ((value & rdMask) << rdPos);
		return value;
	}
	
	uint opcode()
	{
		return (data >> opcodePos)	& opcodeMask;
	}
	
	uint opcode(uint value)
	{
		data = (data & ~(opcodeMask << opcodePos)) | ((value & opcodeMask) << opcodePos);
		return value;
	}
}