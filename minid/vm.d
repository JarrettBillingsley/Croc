module minid.vm;

import minid.types;
import minid.opcodes;
import minid.state;

class MDRuntimeException : Exception
{
	public this(...)
	{
		super(vformat(_arguments, _argptr));
	}
}

class MDVM
{
	public this()
	{
		
	}

	protected static void doArithmetic(MDState s, StackVal dest, MDValue* src1, MDValue* src2, Op type)
	{
		if(src2 is null)
		{
			assert(type == Op.Neg, "invalid arith");

			if(src1.isNum())
			{
				if(src1.isFloat())
				{
					dest.value = -src1.asFloat();
					return;
				}
				else
				{
					dest.value = -src1.asInt();
					return;
				}
			}
			else
			{
				MDValue* method = s.getMM(src1, MM.Neg);
				
				if(!method.isFunction())
					throw new MDRuntimeException("Cannot perform arithmetic on a '%s'", src1.typeString());
			
				// call method
			}
		}

		if(src1.isNum() && src2.isNum())
		{
			if(src1.isFloat() || src2.isFloat())
			{
				switch(type)
				{
					case Op.Add: dest.value = src1.asFloat() + src2.asFloat(); return;
					case Op.Sub: dest.value = src1.asFloat() - src2.asFloat(); return;
					case Op.Mul: dest.value = src1.asFloat() * src2.asFloat(); return;
					case Op.Div: dest.value = src1.asFloat() / src2.asFloat(); return;
					case Op.Mod: dest.value = src1.asFloat() % src2.asFloat(); return;
				}
			}
			else
			{
				switch(type)
				{
					case Op.Add: dest.value = src1.asInt() + src2.asInt(); return;
					case Op.Sub: dest.value = src1.asInt() - src2.asInt(); return;
					case Op.Mul: dest.value = src1.asInt() * src2.asInt(); return;
					case Op.Div: dest.value = src1.asInt() / src2.asInt(); return;
					case Op.Mod: dest.value = src1.asInt() % src2.asInt(); return;
				}
			}
		}
		else
		{

		}
	}
	
	protected static void doBitArith(MDState s, StackVal dest, MDValue* src1, MDValue* src2, Op type)
	{
		if(src2 is null)
		{
			assert(type == Op.Com, "invalid bit arith");
			
			if(src1.isInt())
			{
				dest.value = ~src1.asInt();
				return;
			}
			else
			{

			}
		}

		if(src1.isInt() && src2.isInt())
		{
			switch(type)
			{
				case Op.And:  dest.value = src1.asInt() & src2.asInt(); return;
				case Op.Or:   dest.value = src1.asInt() | src2.asInt(); return;
				case Op.Xor:  dest.value = src1.asInt() ^ src2.asInt(); return;
				case Op.Shl:  dest.value = src1.asInt() << src2.asInt(); return;
				case Op.Shr:  dest.value = src1.asInt() >> src2.asInt(); return;
				case Op.UShr: dest.value = src1.asInt() >>> src2.asInt(); return;
			}
		}
		else
		{

		}
	}

	public void execute(MDState s)
	{
		Instruction* pc = s.mSavedPC;

		while(true)
		{
			Instruction i = *pc;
			pc++;

			MDValue* getCR1()
			{
				uint val = i.rs1;
				
				if(val & Instruction.constBit)
					return s.getConst(val & ~Instruction.constBit);
				else
					return s.getBasedStack(val);
			}
			
			MDValue* getCR2()
			{
				uint val = i.rs2;
				
				if(val & Instruction.constBit)
					return s.getConst(val & ~Instruction.constBit);
				else
					return s.getBasedStack(val);
			}

			Op opcode = cast(Op)i.opcode;

			switch(opcode)
			{
				case Op.Add:
				case Op.Sub:
				case Op.Mul:
				case Op.Div:
				case Op.Mod:
					doArithmetic(s, s.getBasedStack(i.rd), getCR1(), getCR2(), opcode);
					break;

				case Op.Neg:
					doArithmetic(s, s.getBasedStack(i.rd), getCR1(), null, opcode);
					break;

				case Op.And:
				case Op.Or:
				case Op.Xor:
				case Op.Shl:
				case Op.Shr:
				case Op.UShr:
					doBitArith(s, s.getBasedStack(i.rd), getCR1(), getCR2(), opcode);
					break;
					
				case Op.Com:
					doBitArith(s, s.getBasedStack(i.rd), getCR1(), null, opcode);
					break;
					
				case Op.Move:
					s.getBasedStack(i.rd).value = s.getBasedStack(i.rs1);
					break;
					
				case Op.Not:
					if(s.getBasedStack(i.rs1).isFalse())
						s.getBasedStack(i.rd).value = true;
					else
						s.getBasedStack(i.rd).value = false;
					
					break;
					
				case Op.Cmp:
					Instruction jump = *pc;
					pc++;

					int cmpValue = getCR1().opCmp(getCR2());

					if(jump.rd == 1)
					{
						switch(jump.opcode)
						{
							case Op.Je:  if(cmpValue == 0) pc += jump.immBiased; break;
							case Op.Jle: if(cmpValue <= 0) pc += jump.immBiased; break;
							case Op.Jlt: if(cmpValue < 0)  pc += jump.immBiased; break;
							default: assert(false, "invalid 'cmp' jump");
						}
					}
					else
					{
						switch(jump.opcode)
						{
							case Op.Je:  if(cmpValue != 0) pc += jump.immBiased; break;
							case Op.Jle: if(cmpValue > 0)  pc += jump.immBiased; break;
							case Op.Jlt: if(cmpValue >= 0) pc += jump.immBiased; break;
							default: assert(false, "invalid 'cmp' jump");
						}
					}

					break;

				case Op.Is:
					Instruction jump = *pc;
					pc++;
					
					assert(jump.opcode == Op.Je, "invalid 'is' jump");

					bool cmpValue = getCR1().rawEquals(getCR2());

					if(jump.rd == 1)
					{
						if(cmpValue is true)
							pc += jump.immBiased;
					}
					else
					{
						if(cmpValue is false)
							pc += jump.immBiased;
					}
					
					break;

				case Op.IsTrue:
					Instruction jump = *pc;
					pc++;
					
					assert(jump.opcode == Op.Je, "invalid 'istrue' jump");

					bool cmpValue = !getCR1().isFalse();

					if(jump.rd == 1)
					{
						if(cmpValue is true)
							pc += jump.immBiased;
					}
					else
					{
						if(cmpValue is false)
							pc += jump.immBiased;
					}
					
					break;
					
				case Op.Jmp:
					pc += i.immBiased;
					break;

				case Op.Length:
					s.getBasedStack(i.rd).value = cast(int)s.getBasedStack(i.rs1).length;
					break;
					
				case Op.LoadBool:
					s.getBasedStack(i.rd).value = (i.rs1 == 1) ? true : false;
					break;

				case Op.LoadNull:
					s.getBasedStack(i.rd).setNull();
					break;

				case Op.LoadConst:
					s.getBasedStack(i.rd).value = s.getConst(i.imm);
					break;
					
				case Op.GetGlobal:
					MDValue* index = s.getConst(i.imm);
					assert(index.isString(), "trying to get a non-string global");
					s.getBasedStack(i.rd).value = s.getEnvironment()[*index];
					break;

				case Op.SetGlobal:
					MDValue* index = s.getConst(i.imm);
					assert(index.isString(), "trying to get a non-string global");
					s.getEnvironment()[*index] = s.getBasedStack(i.rd);
					break;

				case Op.GetUpvalue:
					s.getBasedStack(i.rd).value = s.getUpvalue(i.imm);
					break;

				case Op.SetUpvalue:
					s.getUpvalue(i.imm).value = s.getBasedStack(i.rd);
					break;

				case Op.Foreach:
				case Op.Call:
				case Op.Cat:
				case Op.Close:
				case Op.Closure:
				case Op.EndFinal:
				case Op.Index:
				case Op.IndexAssign:
				case Op.Method:
				case Op.NewArray:
				case Op.NewTable:
				case Op.PopCatch:
				case Op.PopFinally:
				case Op.PushCatch:
				case Op.PushFinally:
				case Op.Ret:
				case Op.SetArray:
				case Op.SwitchInt:
				case Op.SwitchString:
				case Op.Throw:
				case Op.Vararg:

				case Op.Je:
				case Op.Jle:
				case Op.Jlt:
					assert(false, "lone conditional jump instruction");
			}
		}
	}
}