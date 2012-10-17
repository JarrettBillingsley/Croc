#ifndef CROC_BASE_OPCODES_HPP
#define CROC_BASE_OPCODES_HPP

#include "croc/base/metamethods.hpp"
#include "croc/base/sanity.hpp"

namespace croc
{
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
	class:  rd = class rs : rt {} // if rt is a CONST null, inherit from Object; otherwise error
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

FIVE SHORTS:

(rd, rs, rt, uimm1, uimm2)
	method:  rd is base reg, rs is object, rt is method name, uimm1 is number of params, uimm2 is number of expected returns.
	tmethod: same as above, but does a tailcall. uimm2 is unused, but this makes codegen easier
*/

#define INSTRUCTION_LIST(X)\
	X(Add),\
	X(Sub),\
	X(Mul),\
	X(Div),\
	X(Mod),\
	X(AddEq),\
	X(SubEq),\
	X(MulEq),\
	X(DivEq),\
	X(ModEq),\
	X(And),\
	X(Or),\
	X(Xor),\
	X(Shl),\
	X(Shr),\
	X(UShr),\
	X(AndEq),\
	X(OrEq),\
	X(XorEq),\
	X(ShlEq),\
	X(ShrEq),\
	X(UShrEq),\
	X(Neg),\
	X(Com),\
	X(Inc),\
	X(Dec),\
	X(Move),\
	X(NewGlobal),\
	X(GetGlobal),\
	X(SetGlobal),\
	X(GetUpval),\
	X(SetUpval),\
	X(Not),\
	X(Cmp3),\
	X(Cmp),\
	X(SwitchCmp),\
	X(Equals),\
	X(Is),\
	X(IsTrue),\
	X(Jmp),\
	X(Switch),\
	X(Close),\
	X(For),\
	X(ForLoop),\
	X(Foreach),\
	X(ForeachLoop),\
	X(PushCatch),\
	X(PushFinally),\
	X(PopCatch),\
	X(PopFinally),\
	X(EndFinal),\
	X(Throw),\
	X(Method),\
	X(TailMethod),\
	X(SuperMethod),\
	X(TailSuperMethod),\
	X(Call),\
	X(TailCall),\
	X(SaveRets),\
	X(Ret),\
	X(Unwind),\
	X(Vararg),\
	X(VargLen),\
	X(VargIndex),\
	X(VargIndexAssign),\
	X(VargSlice),\
	X(Yield),\
	X(CheckParams),\
	X(CheckObjParam),\
	X(ObjParamFail),\
	X(CustomParamFail),\
	X(AssertFail),\
	X(Length),\
	X(LengthAssign),\
	X(Append),\
	X(SetArray),\
	X(Cat),\
	X(CatEq),\
	X(Index),\
	X(IndexAssign),\
	X(Field),\
	X(FieldAssign),\
	X(Slice),\
	X(SliceAssign),\
	X(In),\
	X(NewArray),\
	X(NewTable),\
	X(Closure),\
	X(ClosureWithEnv),\
	X(Class),\
	X(Namespace),\
	X(NamespaceNP),\
	X(As),\
	X(SuperOf)

#define POOP(x) Op_ ## x

	typedef enum Op
	{
		INSTRUCTION_LIST(POOP),
		Op_LAST_MM_OPCODE = Op_UShrEq
	} Op;

#undef POOP

	// TODO:
	// static assert(Op.Add == MM.Add && Op.LAST_MM_OPCODE == MM.LAST_OPCODE_MM, "MMs and opcodes are out of sync!");

	// Make sure we don't add too many instructions!
	// static assert(Op.max <= Instruction.opcodeMax, "Too many opcodes");

	extern const char* OpNames[];

	typedef enum Comparison
	{
		Comparison_LT,
		Comparison_LE,
		Comparison_GT,
		Comparison_GE
	} Comparison;

#define BITMASK(len) ((1 << (len)) - 1)

#define INST_CONSTBIT 0x8000

//  15        6     0
// |rd       |op     |

#define INST_OPCODE_SIZE 7
#define INST_OPCODE_SHIFT 0
#define INST_OPCODE_MASK (BITMASK(INST_OPCODE_SIZE) << INST_OPCODE_SHIFT)
#define INST_OPCODE_MAX ((1 << INST_OPCODE_SIZE) - 1)

#define INST_RD_SIZE 9
#define INST_RD_SHIFT (INST_OPCODE_SHIFT + INST_OPCODE_SIZE)
#define INST_RD_MASK (BITMASK(INST_RD_SIZE) << INST_RD_SHIFT)
#define INST_RD_MAX ((1 << INST_RD_SIZE) - 1)

#define INST_IMM_SIZE 16
#define INST_IMM_MAX ((1 << (INST_IMM_SIZE - 1)) - 1)
#define INST_UIMM_MAX ((1 << INST_IMM_SIZE) - 1)

#define INST_MAX_REGISTER INST_RD_MAX
#define INST_MAX_CONSTANT INST_UIMM_MAX
#define INST_MAX_UPVALUE INST_UIMM_MAX
#define INST_MAX_JUMP_FORWARD INST_IMM_MAX
#define INST_MAX_JUMP_BACKWARD (-INST_IMM_MAX)
#define INST_NO_JUMP (INST_MAX_JUMP_BACKWARD - 1)
#define INST_MAX_EH_DEPTH INST_RD_MAX
#define INST_MAX_SWITCH_TABLE INST_RD_MAX
#define INST_MAX_INNER_FUNC INST_UIMM_MAX

#define INST_ARRAY_SET_FIELDS 30
#define INST_MAX_ARRAY_FIELDS (INST_ARRAY_SET_FIELDS * INST_UIMM_MAX)

#define INST_GET_OPCODE(n) ((n.uimm & INST_OPCODE_MASK) >> INST_OPCODE_SHIFT)
#define INST_GET_RD(n) ((n.uimm & INST_RD_MASK) >> INST_RD_SHIFT)

	typedef union Instruction
	{
		int16_t imm;
		uint16_t uimm;
	} Instruction;

	// TODO:
	// static assert(Instruction.sizeof == 2);
}
#endif