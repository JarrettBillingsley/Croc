module opcodes;

enum Op : uint
{
	Move,
	LoadConst,
	LoadBool,
	LoadNull,
	Add,
	Sub,
	Cat,
	Mul,
	Div,
	Mod,
	Length,
	Close,
	Closure,
	NewTable,
	NewArray,
	Index,
	IndexAssign,
	GetGlobal,
	SetGlobal,
	GetUpvalue,
	SetUpvalue
}

template Mask(uint length)
{
	const uint Mask = ~((~0) << length);
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

	const uint rdSize = 8;
	const uint rdMax = (1 << rdSize) - 1;
	const uint rdPos = rs1Pos + rs1Size;
	const uint rdMask = 0b11111111;

	const uint opcodeSize = 6;
	const uint opcodeMask = 0b111111;
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

void fooo()
{
	Instruction i;

	i.rs2 = 4;
}