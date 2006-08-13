module minid.vm;

import minid.types;
import minid.opcodes;
import minid.state;

class MDVM
{
	public this()
	{
		
	}

	protected static void doArithmetic(MDState s, uint dest, MDValue* src1, MDValue* src2, Op type)
	{
		if(src2 is null)
		{
			assert(type == Op.Neg, "invalid arith");

			if(src1.isNum())
			{
				if(src1.isFloat())
				{
					s.getBasedStack(dest).value = -src1.asFloat();
					return;
				}
				else
				{
					s.getBasedStack(dest).value = -src1.asInt();
					return;
				}
			}
			else
			{
				MDValue* method = s.getMM(src1, MM.Neg);
				
				if(!method.isFunction())
					throw new MDRuntimeException("Cannot perform arithmetic on a '%s'", src1.typeString());
			
				uint funcSlot = s.push(method);
				s.push(src1);
				s.call(funcSlot, 1, 1);
				s.popToSlot(dest);
			}
		}

		if(src1.isNum() && src2.isNum())
		{
			if(src1.isFloat() || src2.isFloat())
			{
				switch(type)
				{
					case Op.Add: s.getBasedStack(dest).value = src1.asFloat() + src2.asFloat(); return;
					case Op.Sub: s.getBasedStack(dest).value = src1.asFloat() - src2.asFloat(); return;
					case Op.Mul: s.getBasedStack(dest).value = src1.asFloat() * src2.asFloat(); return;
					case Op.Div: s.getBasedStack(dest).value = src1.asFloat() / src2.asFloat(); return;
					case Op.Mod: s.getBasedStack(dest).value = src1.asFloat() % src2.asFloat(); return;
				}
			}
			else
			{
				switch(type)
				{
					case Op.Add: s.getBasedStack(dest).value = src1.asInt() + src2.asInt(); return;
					case Op.Sub: s.getBasedStack(dest).value = src1.asInt() - src2.asInt(); return;
					case Op.Mul: s.getBasedStack(dest).value = src1.asInt() * src2.asInt(); return;
					case Op.Div: s.getBasedStack(dest).value = src1.asInt() / src2.asInt(); return;
					case Op.Mod: s.getBasedStack(dest).value = src1.asInt() % src2.asInt(); return;
				}
			}
		}
		else
		{
			MM mmType;

			switch(type)
			{
				case Op.Add: mmType = MM.Add; break;
				case Op.Sub: mmType = MM.Sub; break;
				case Op.Mul: mmType = MM.Mul; break;
				case Op.Div: mmType = MM.Div; break;
				case Op.Mod: mmType = MM.Mod; break;
			}

			MDValue* method = s.getMM(src1, mmType);

			if(!method.isFunction())
			{
				method = s.getMM(src2, mmType);

				if(!method.isFunction())
					throw new MDRuntimeException("Cannot perform arithmetic on a '%s' and a '%s'", src1.typeString(), src2.typeString());
			}

			uint funcSlot = s.push(method);
			s.push(src1);
			s.push(src2);
			s.call(funcSlot, 2, 1);
			s.popToSlot(dest);
		}
	}
	
	protected static void doBitArith(MDState s, uint dest, MDValue* src1, MDValue* src2, Op type)
	{
		if(src2 is null)
		{
			assert(type == Op.Com, "invalid bit arith");
			
			if(src1.isInt())
			{
				s.getBasedStack(dest).value = ~src1.asInt();
				return;
			}
			else
			{
				MDValue* method = s.getMM(src1, MM.Com);
				
				if(!method.isFunction())
					throw new MDRuntimeException("Cannot perform bitwise arithmetic on a '%s'", src1.typeString());
			
				uint funcSlot = s.push(method);
				s.push(src1);
				s.call(funcSlot, 1, 1);
				s.popToSlot(dest);
			}
		}

		if(src1.isInt() && src2.isInt())
		{
			switch(type)
			{
				case Op.And:  s.getBasedStack(dest).value = src1.asInt() & src2.asInt(); return;
				case Op.Or:   s.getBasedStack(dest).value = src1.asInt() | src2.asInt(); return;
				case Op.Xor:  s.getBasedStack(dest).value = src1.asInt() ^ src2.asInt(); return;
				case Op.Shl:  s.getBasedStack(dest).value = src1.asInt() << src2.asInt(); return;
				case Op.Shr:  s.getBasedStack(dest).value = src1.asInt() >> src2.asInt(); return;
				case Op.UShr: s.getBasedStack(dest).value = src1.asInt() >>> src2.asInt(); return;
			}
		}
		else
		{
			MM mmType;

			switch(type)
			{
				case Op.And:  mmType = MM.And; break;
				case Op.Or:   mmType = MM.Or; break;
				case Op.Xor:  mmType = MM.Xor; break;
				case Op.Shl:  mmType = MM.Shl; break;
				case Op.Shr:  mmType = MM.Shr; break;
				case Op.UShr: mmType = MM.UShr; break;
			}

			MDValue* method = s.getMM(src1, mmType);

			if(!method.isFunction())
			{
				method = s.getMM(src2, mmType);

				if(!method.isFunction())
					throw new MDRuntimeException("Cannot perform bitwise arithmetic on a '%s' and a '%s'", src1.typeString(), src2.typeString());
			}

			uint funcSlot = s.push(method);
			s.push(src1);
			s.push(src2);
			s.call(funcSlot, 2, 1);
			s.popToSlot(dest);
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
					doArithmetic(s, i.rd, getCR1(), getCR2(), opcode);
					break;

				case Op.Neg:
					doArithmetic(s, i.rd, getCR1(), null, opcode);
					break;

				case Op.And:
				case Op.Or:
				case Op.Xor:
				case Op.Shl:
				case Op.Shr:
				case Op.UShr:
					doBitArith(s, i.rd, getCR1(), getCR2(), opcode);
					break;
					
				case Op.Com:
					doBitArith(s, i.rd, getCR1(), null, opcode);
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

				case Op.NewArray:
					s.getBasedStack(i.rd).value = new MDArray(i.imm);
					break;

				case Op.NewTable:
					s.getBasedStack(i.rd).value = new MDTable();
					break;
					
				case Op.SetArray:
					// Since this instruction is only generated for array constructors,
					// there is really no reason to check for type correctness for the dest.

					uint sliceBegin = i.rd + 1;
					
					if(i.rs1 == 0)
						s.getBasedStack(i.rd).asArray().setBlock(i.rs2, s.sliceStack(sliceBegin, -1));
					else
						s.getBasedStack(i.rd).asArray().setBlock(i.rs2, s.sliceStack(sliceBegin, sliceBegin + i.rs1));
						
					break;
					
				case Op.SwitchInt:
					int offset = s.switchInt(i.rd, i.imm);
					
					if(offset == -1)
						throw new MDRuntimeException("Switch without default");
						
					pc += offset;
					break;

				case Op.SwitchString:
					int offset = s.switchString(i.rd, i.imm);

					if(offset == -1)
						throw new MDRuntimeException("Switch without default");
						
					pc += offset;
					break;
					
				case Op.Vararg:
					int numNeeded = i.rs1 - 1;
					int numVarargs = s.getNumVarargs();
					
					if(numNeeded == -1)
					{
						// multiple returns
						numNeeded = numVarargs;
						s.needStackSlots(numNeeded);
					}

					uint src = s.getVarargBase();
					uint dest = s.getBase() + i.rd;

					for(uint index = 0; index < numNeeded; index++)
					{
						if(index < numVarargs)
							s.copyAbsStack(dest, src);
						else
							s.getAbsStack(dest).setNull();
							
						src++;
						dest++;
					}
					break;
					
				case Op.Close:
					s.close(i.rd);
					break;
					
				case Op.Foreach:
					Instruction jump = *pc;
					pc++;

					uint rd = i.rd;
					uint funcReg = rd + 3;

					s.copyBasedStack(funcReg + 2, rd + 2);
					s.copyBasedStack(funcReg + 1, rd + 1);
					s.copyBasedStack(funcReg, rd);
					
					s.call(funcReg, 2, i.imm);
					
					if(s.getBasedStack(funcReg).isNull() == false)
					{
						s.copyBasedStack(rd + 2, funcReg);
						
						assert(jump.opcode == Op.Je && jump.rd == 1, "invalid 'foreach' jump");

						pc += jump.immBiased;
					}
					else
					
					break;

				case Op.Cat:
				case Op.Closure:

				case Op.Index:
				case Op.IndexAssign:
				case Op.Method:

				case Op.Call:
				case Op.Ret:

				case Op.EndFinal:
				case Op.PopCatch:
				case Op.PopFinally:
				case Op.PushCatch:
				case Op.PushFinally:
				case Op.Throw:
					assert(false, "unimplemented instruction");

				case Op.Je:
				case Op.Jle:
				case Op.Jlt:
					assert(false, "lone conditional jump instruction");
			}
		}
	}
}