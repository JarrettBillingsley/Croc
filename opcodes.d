module opcodes;

enum Op : uint
{
	Add,
	Call,
	Cat,
	Close,
	Closure,
	Cmp,
	Div,
	Foreach,
	GetGlobal,
	GetUpvalue,
	Index,
	IndexAssign,
	Je,
	Jle,
	Jlt,
	Jmp,
	Length,
	LoadBool,
	LoadConst,
	LoadNull,
	Mod,
	Move,
	Mul,
	Neg,
	NewArray,
	NewTable,
	Not,
	PopCatch,
	PopFinally,
	PushCatch,
	PushFinally,
	Ret,
	SetGlobal,
	SetUpvalue,
	Sub,
	SwitchInt,
	SwitchString,
	Throw,
	Vararg
}

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