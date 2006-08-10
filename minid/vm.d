module minid.vm;

import minid.types;
import minid.opcodes;
import minid.state;

class MDVM
{
	public this()
	{
		
	}
	
	protected static void doArithmetic(MDState s, StackVal dest, MDValue* src1, MDValue* src2, Op type)
	{
		/*if(src1.isInt())
		{
			if(src2.isInt())
			{

			}
			else if(src2.isFloat())
			{

			}
			else
				...
		}
		else if(src1.isFloat())*/
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

			switch(i.opcode)
			{
				case Op.Add:
					MDValue* src1 = getCR1();
					MDValue* src2 = getCR2();
					s.getBasedStack(i.rd);
				case Op.And:
				case Op.Call:
				case Op.Cat:
				case Op.Close:
				case Op.Closure:
				case Op.Cmp:
				case Op.Com:
				case Op.Div:
				case Op.EndFinal:
				case Op.Foreach:
				case Op.GetGlobal:
				case Op.GetUpvalue:
				case Op.Index:
				case Op.IndexAssign:
				case Op.Is:
				case Op.IsTrue:
				case Op.Je:
				case Op.Jle:
				case Op.Jlt:
				case Op.Jmp:
				case Op.Length:
				case Op.LoadBool:
				case Op.LoadConst:
				case Op.LoadNull:
				case Op.Method:
				case Op.Mod:
				case Op.Move:
				case Op.Mul:
				case Op.Neg:
				case Op.NewArray:
				case Op.NewTable:
				case Op.Not:
				case Op.Or:
				case Op.PopCatch:
				case Op.PopFinally:
				case Op.PushCatch:
				case Op.PushFinally:
				case Op.Ret:
				case Op.SetArray:
				case Op.SetGlobal:
				case Op.SetUpvalue:
				case Op.Shl:
				case Op.Shr:
				case Op.Sub:
				case Op.SwitchInt:
				case Op.SwitchString:
				case Op.Throw:
				case Op.UShr:
				case Op.Vararg:
				case Op.Xor:
			}
		}
	}
}