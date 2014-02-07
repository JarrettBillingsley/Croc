
#include <math.h>

#include "croc/api.h"
#include "croc/base/opcodes.hpp"
#include "croc/base/writebarrier.hpp"
#include "croc/internal/basic.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/class.hpp"
#include "croc/internal/debug.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/interpreter.hpp"
#include "croc/internal/stack.hpp"
#include "croc/internal/thread.hpp"
#include "croc/internal/variables.hpp"
#include "croc/types.hpp"

#define GetRS()\
	do {\
		if((*pc)->uimm & INST_CONSTBIT)\
			RS = &constTable[(*pc)->uimm & ~INST_CONSTBIT];\
		else\
			RS = &t->stack[stackBase + (*pc)->uimm]; (*pc)++;\
	} while(false)

#define GetRT()\
	do {\
		if((*pc)->uimm & INST_CONSTBIT)\
			RT = &constTable[(*pc)->uimm & ~INST_CONSTBIT];\
		else\
			RT = &t->stack[stackBase + (*pc)->uimm]; (*pc)++;\
	} while(false)

#define GetUImm() (((*pc)++)->uimm)
#define GetImm() (((*pc)++)->imm)

#define AdjustParams()\
	do {\
		if(numParams == 0)\
			numParams = t->stackIndex - (stackBase + rd + 1);\
		else\
		{\
			numParams--;\
			t->stackIndex = stackBase + rd + 1 + numParams;\
		}\
	} while(false)

namespace croc
{
	namespace
	{
		void binOpImpl(Thread* t, Op operation, AbsStack dest, Value RS, Value RT)
		{
			crocfloat f1;
			crocfloat f2;

			if(RS.type == CrocType_Int)
			{
				if(RT.type == CrocType_Int)
				{
					auto i1 = RS.mInt;
					auto i2 = RT.mInt;

					switch(operation)
					{
						case Op_Add: t->stack[dest] = Value::from(i1 + i2); return;
						case Op_Sub: t->stack[dest] = Value::from(i1 - i2); return;
						case Op_Mul: t->stack[dest] = Value::from(i1 * i2); return;

						case Op_Div:
							if(i2 == 0)
								croc_eh_throwStd(*t, "ValueError", "Integer divide by zero");

							t->stack[dest] = Value::from(i1 / i2);
							return;

						case Op_Mod:
							if(i2 == 0)
								croc_eh_throwStd(*t, "ValueError", "Integer modulo by zero");

							t->stack[dest] = Value::from(i1 % i2);
							return;

						default:
							assert(false);
					}
				}
				else if(RT.type == CrocType_Float)
				{
					f1 = RS.mInt;
					f2 = RT.mFloat;
					goto _float;
				}
			}
			else if(RS.type == CrocType_Float)
			{
				if(RT.type == CrocType_Int)
				{
					f1 = RS.mFloat;
					f2 = RT.mInt;
					goto _float;
				}
				else if(RT.type == CrocType_Float)
				{
					f1 = RS.mFloat;
					f2 = RT.mFloat;

				_float:
					switch(operation)
					{
						case Op_Add: t->stack[dest] = Value::from(f1 + f2); return;
						case Op_Sub: t->stack[dest] = Value::from(f1 - f2); return;
						case Op_Mul: t->stack[dest] = Value::from(f1 * f2); return;
						case Op_Div: t->stack[dest] = Value::from(f1 / f2); return;
						case Op_Mod: t->stack[dest] = Value::from(fmod(f1, f2)); return;

						default:
							assert(false);
					}
				}
			}

			const char* name;

			switch(operation)
			{
				case Op_Add: name = "add"; break;
				case Op_Sub: name = "subtract"; break;
				case Op_Mul: name = "multiply"; break;
				case Op_Div: name = "divide"; break;
				case Op_Mod: name = "modulo"; break;
				default: assert(false);
			}

			pushTypeStringImpl(t, RS);
			pushTypeStringImpl(t, RT);
			croc_eh_throwStd(*t, "TypeError", "Attempting to %s a '%s' and a '%s'",
				name, croc_getString(*t, -2), croc_getString(*t, -1));
		}

		void reflBinOpImpl(Thread* t, Op operation, AbsStack dest, Value src)
		{
			crocfloat f1;
			crocfloat f2;

			if(t->stack[dest].type == CrocType_Int)
			{
				if(src.type == CrocType_Int)
				{
					auto i2 = src.mInt;

					switch(operation)
					{
						case Op_AddEq: t->stack[dest].mInt += i2; return;
						case Op_SubEq: t->stack[dest].mInt -= i2; return;
						case Op_MulEq: t->stack[dest].mInt *= i2; return;

						case Op_DivEq:
							if(i2 == 0)
								croc_eh_throwStd(*t, "ValueError", "Integer divide by zero");

							t->stack[dest].mInt /= i2;
							return;

						case Op_ModEq:
							if(i2 == 0)
								croc_eh_throwStd(*t, "ValueError", "Integer modulo by zero");

							t->stack[dest].mInt %= i2;
							return;

						default: assert(false);
					}
				}
				else if(src.type == CrocType_Float)
				{
					f1 = t->stack[dest].mInt;
					f2 = src.mFloat;
					goto _float;
				}
			}
			else if(t->stack[dest].type == CrocType_Float)
			{
				if(src.type == CrocType_Int)
				{
					f1 = t->stack[dest].mFloat;
					f2 = src.mInt;
					goto _float;
				}
				else if(src.type == CrocType_Float)
				{
					f1 = t->stack[dest].mFloat;
					f2 = src.mFloat;

				_float:
					t->stack[dest].type = CrocType_Float;

					switch(operation)
					{
						case Op_AddEq: t->stack[dest].mFloat = f1 + f2; return;
						case Op_SubEq: t->stack[dest].mFloat = f1 - f2; return;
						case Op_MulEq: t->stack[dest].mFloat = f1 * f2; return;
						case Op_DivEq: t->stack[dest].mFloat = f1 / f2; return;
						case Op_ModEq: t->stack[dest].mFloat = fmod(f1, f2); return;

						default: assert(false);
					}
				}
			}

			const char* name;

			switch(operation)
			{
				case Op_AddEq: name = "add"; break;
				case Op_SubEq: name = "subtract"; break;
				case Op_MulEq: name = "multiply"; break;
				case Op_DivEq: name = "divide"; break;
				case Op_ModEq: name = "modulo"; break;
				default: assert(false);
			}

			pushTypeStringImpl(t, t->stack[dest]);
			pushTypeStringImpl(t, src);
			croc_eh_throwStd(*t, "TypeError", "Attempting to %s-assign a '%s' and a '%s'",
				name, croc_getString(*t, -2), croc_getString(*t, -1));
		}

		void binaryBinOpImpl(Thread* t, Op operation, AbsStack dest, Value RS, Value RT)
		{
			if(RS.type == CrocType_Int && RT.type == CrocType_Int)
			{
				switch(operation)
				{
					case Op_And:  t->stack[dest] = Value::from(RS.mInt & RT.mInt); return;
					case Op_Or:   t->stack[dest] = Value::from(RS.mInt | RT.mInt); return;
					case Op_Xor:  t->stack[dest] = Value::from(RS.mInt ^ RT.mInt); return;
					case Op_Shl:  t->stack[dest] = Value::from(RS.mInt << RT.mInt); return;
					case Op_Shr:  t->stack[dest] = Value::from(RS.mInt >> RT.mInt); return;

					case Op_UShr:
						t->stack[dest] = Value::from(cast(crocint)(cast(uword)RS.mInt >> cast(uword)RT.mInt));
						return;

					default: assert(false);
				}
			}

			const char* name;

			switch(operation)
			{
				case Op_And:  name = "and"; break;
				case Op_Or:   name = "or"; break;
				case Op_Xor:  name = "xor"; break;
				case Op_Shl:  name = "left-shift"; break;
				case Op_Shr:  name = "right-shift"; break;
				case Op_UShr: name = "unsigned right-shift"; break;
				default: assert(false);
			}

			pushTypeStringImpl(t, RS);
			pushTypeStringImpl(t, RT);
			croc_eh_throwStd(*t, "TypeError", "Attempting to bitwise %s a '%s' and a '%s'",
				name, croc_getString(*t, -2), croc_getString(*t, -1));
		}

		void reflBinaryBinOpImpl(Thread* t, Op operation, AbsStack dest, Value src)
		{
			if(t->stack[dest].type == CrocType_Int && src.type == CrocType_Int)
			{
				switch(operation)
				{
					case Op_AndEq:  t->stack[dest].mInt &= src.mInt; return;
					case Op_OrEq:   t->stack[dest].mInt |= src.mInt; return;
					case Op_XorEq:  t->stack[dest].mInt ^= src.mInt; return;
					case Op_ShlEq:  t->stack[dest].mInt <<= src.mInt; return;
					case Op_ShrEq:  t->stack[dest].mInt >>= src.mInt; return;

					case Op_UShrEq: {
						auto tmp = cast(uword)t->stack[dest].mInt;
						tmp >>= cast(uword)src.mInt;
						t->stack[dest].mInt = cast(crocint)tmp;
						return;
					}
					default: assert(false);
				}
			}

			const char* name;

			switch(operation)
			{
				case Op_AndEq:  name = "and"; break;
				case Op_OrEq:   name = "or"; break;
				case Op_XorEq:  name = "xor"; break;
				case Op_ShlEq:  name = "left-shift"; break;
				case Op_ShrEq:  name = "right-shift"; break;
				case Op_UShrEq: name = "unsigned right-shift"; break;
				default: assert(false);
			}

			pushTypeStringImpl(t, t->stack[dest]);
			pushTypeStringImpl(t, src);
			croc_eh_throwStd(*t, "TypeError", "Attempting to bitwise %s-assign a '%s' and a '%s'",
				name, croc_getString(*t, -2), croc_getString(*t, -1));
		}
	}

	void execute(Thread* t)
	{
		Value* RS;
		Value* RT;

	_exceptionRetry:
		t->state = CrocThreadState_Running;
		t->vm->curThread = t;

	_reentry:
		auto stackBase = t->stackBase;
		auto constTable = t->currentAR->func->scriptFunc->constants;
		auto env = t->currentAR->func->environment;
		auto upvals = t->currentAR->func->scriptUpvals();
		auto pc = &t->currentAR->pc;
		Instruction* oldPC = nullptr;

		while(true)
		{
			if(t->shouldHalt)
				assert(false); // TODO:halt

			pc = &t->currentAR->pc;
			Instruction* i = (*pc)++;

			if(t->hooksEnabled && t->hooks)
			{
				if(t->hooks & CrocThreadHook_Delay)
				{
					assert(t->hookCounter > 0);
					t->hookCounter--;

					if(t->hookCounter == 0)
					{
						t->hookCounter = t->hookDelay;
						callHook(t, CrocThreadHook_Delay);
					}
				}

				if(t->hooks & CrocThreadHook_Line)
				{
					auto curPC = t->currentAR->pc - 1;

					// when oldPC is null, it means we've either just started executing this func,
					// or we've come back from a yield, or we've just caught an exception, or something
					// like that.
					// When curPC < oldPC, we've jumped back, like to the beginning of a loop.

					if(curPC == t->currentAR->func->scriptFunc->code.ptr ||
						curPC < oldPC ||
						pcToLine(t->currentAR, curPC) != pcToLine(t->currentAR, curPC - 1))
						callHook(t, CrocThreadHook_Line);
				}
			}

			oldPC = *pc;

			auto opcode = cast(Op)INST_GET_OPCODE(*i);
			auto rd = INST_GET_RD(*i);

			switch(opcode)
			{
				// Binary Arithmetic
				case Op_Add:
				case Op_Sub:
				case Op_Mul:
				case Op_Div:
				case Op_Mod: GetRS(); GetRT(); binOpImpl(t, opcode, stackBase + rd, *RS, *RT); break;

				// Reflexive Arithmetic
				case Op_AddEq:
				case Op_SubEq:
				case Op_MulEq:
				case Op_DivEq:
				case Op_ModEq: GetRS(); reflBinOpImpl(t, opcode, stackBase + rd, *RS); break;

				// Binary Bitwise
				case Op_And:
				case Op_Or:
				case Op_Xor:
				case Op_Shl:
				case Op_Shr:
				case Op_UShr: GetRS(); GetRT(); binaryBinOpImpl(t, opcode, stackBase + rd, *RS, *RT); break;

				// Reflexive Bitwise
				case Op_AndEq:
				case Op_OrEq:
				case Op_XorEq:
				case Op_ShlEq:
				case Op_ShrEq:
				case Op_UShrEq: GetRS(); reflBinaryBinOpImpl(t, opcode, stackBase + rd, *RS); break;

				// Unary ops
				case Op_Neg:
					GetRS();

					if(RS->type == CrocType_Int)
						t->stack[stackBase + rd].mInt = -RS->mInt;
					else if(RS->type == CrocType_Float)
						t->stack[stackBase + rd].mFloat = -RS->mFloat;
					else
					{
						pushTypeStringImpl(t, *RS);
						croc_eh_throwStd(*t, "TypeError", "Cannot perform negation on a '%s'", croc_getString(*t, -1));
					}
					break;

				case Op_Com:
					GetRS();

					if(RS->type == CrocType_Int)
						t->stack[stackBase + rd].mInt = ~RS->mInt;
					else
					{
						pushTypeStringImpl(t, *RS);
						croc_eh_throwStd(*t, "TypeError", "Cannot perform bitwise complement on a '%s'",
							croc_getString(*t, -1));
					}
					break;

				// Crements
				case Op_Inc: {
					auto dest = stackBase + rd;

					if(t->stack[dest].type == CrocType_Int)
						t->stack[dest].mInt++;
					else if(t->stack[dest].type == CrocType_Float)
						t->stack[dest].mFloat++;
					else
					{
						pushTypeStringImpl(t, t->stack[dest]);
						croc_eh_throwStd(*t, "TypeError", "Cannot increment a '%s'", croc_getString(*t, -1));
					}
					break;
				}
				case Op_Dec: {
					auto dest = stackBase + rd;

					if(t->stack[dest].type == CrocType_Int)
						t->stack[dest].mInt--;
					else if(t->stack[dest].type == CrocType_Float)
						t->stack[dest].mFloat--;
					else
					{
						pushTypeStringImpl(t, t->stack[dest]);
						croc_eh_throwStd(*t, "TypeError", "Cannot decrement a '%s'", croc_getString(*t, -1));
					}
					break;
				}
				// Data Transfer
				case Op_Move: GetRS(); t->stack[stackBase + rd] = *RS; break;

				case Op_NewGlobal: newGlobalImpl(t, constTable[GetUImm()].mString, env, t->stack[stackBase + rd]); break;
				case Op_GetGlobal: t->stack[stackBase + rd] = getGlobalImpl(t, constTable[GetUImm()].mString, env); break;
				case Op_SetGlobal: setGlobalImpl(t, constTable[GetUImm()].mString, env, t->stack[stackBase + rd]); break;

				case Op_GetUpval:  t->stack[stackBase + rd] = *upvals[GetUImm()]->value; break;
				case Op_SetUpval: {
					auto uv = upvals[GetUImm()];
					WRITE_BARRIER(t->vm->mem, uv);
					*uv->value = t->stack[stackBase + rd];
					break;
				}
				// Logical and Control Flow
				case Op_Not:  GetRS(); t->stack[stackBase + rd] = Value::from(RS->isFalse()); break;
				case Op_Cmp3: GetRS(); GetRT(); t->stack[stackBase + rd] = Value::from(cmpImpl(t, *RS, *RT)); break;

				case Op_Cmp: {
					GetRS();
					GetRT();
					auto jump = GetImm();

					auto cmpValue = cmpImpl(t, *RS, *RT);

					switch(cast(Comparison)rd)
					{
						case Comparison_LT: if(cmpValue < 0) (*pc) += jump; break;
						case Comparison_LE: if(cmpValue <= 0) (*pc) += jump; break;
						case Comparison_GT: if(cmpValue > 0) (*pc) += jump; break;
						case Comparison_GE: if(cmpValue >= 0) (*pc) += jump; break;
						default: assert(false);
					}
					break;
				}
				case Op_SwitchCmp: {
					GetRS();
					GetRT();
					auto jump = GetImm();

					if(switchCmpImpl(t, *RS, *RT))
						(*pc) += jump;
					break;
				}
				case Op_Equals: {
					GetRS();
					GetRT();
					auto jump = GetImm();

					if(equalsImpl(t, *RS, *RT) == cast(bool)rd)
						(*pc) += jump;
					break;
				}
				case Op_Is: {
					GetRS();
					GetRT();
					auto jump = GetImm();

					if((*RS == *RT) == cast(bool)rd)
						(*pc) += jump;

					break;
				}
				case Op_In: {
					GetRS();
					GetRT();
					auto jump = GetImm();

					if(inImpl(t, *RS, *RT) == cast(bool)rd)
						(*pc) += jump;
					break;
				}
				case Op_IsTrue: {
					GetRS();
					auto jump = GetImm();

					if(RS->isFalse() != cast(bool)rd)
						(*pc) += jump;

					break;
				}
				case Op_Jmp: {
					// If we ever change the format of this opcode, check that it's the same length as Switch (codegen can turn Switch into Jmp)!
					auto jump = GetImm();

					if(rd != 0)
						(*pc) += jump;
					break;
				}
				case Op_Switch: {
					// If we ever change the format of this opcode, check that it's the same length as Jmp (codegen can turn Switch into Jmp)!
					auto st = &t->currentAR->func->scriptFunc->switchTables[rd];
					GetRS();

					if(auto ptr = st->offsets.lookup(*RS))
						(*pc) += *ptr;
					else
					{
						if(st->defaultOffset == -1)
							croc_eh_throwStd(*t, "SwitchError", "Switch without default");

						(*pc) += st->defaultOffset;
					}
					break;
				}
				case Op_Close: closeUpvals(t, stackBase + rd); break;

				case Op_For: {
					auto jump = GetImm();
					auto idx = &t->stack[stackBase + rd];
					auto hi = idx + 1;
					auto step = hi + 1;

					if(idx->type != CrocType_Int || hi->type != CrocType_Int || step->type != CrocType_Int)
						croc_eh_throwStd(*t, "TypeError", "Numeric for loop low, high, and step values must be integers");

					auto intIdx = idx->mInt;
					auto intHi = hi->mInt;
					auto intStep = step->mInt;

					if(intStep == 0)
						croc_eh_throwStd(*t, "ValueError", "Numeric for loop step value may not be 0");

					if((intIdx > intHi && intStep > 0) || (intIdx < intHi && intStep < 0))
						intStep = -intStep;

					if(intStep < 0)
						*idx = Value::from(intIdx + intStep);

					*step = Value::from(intStep);
					(*pc) += jump;
					break;
				}
				case Op_ForLoop: {
					auto jump = GetImm();
					auto idx = t->stack[stackBase + rd].mInt;
					auto hi = t->stack[stackBase + rd + 1].mInt;
					auto step = t->stack[stackBase + rd + 2].mInt;

					if(step > 0)
					{
						if(idx < hi)
						{
							t->stack[stackBase + rd + 3] = Value::from(idx);
							t->stack[stackBase + rd] = Value::from(idx + step);
							(*pc) += jump;
						}
					}
					else
					{
						if(idx >= hi)
						{
							t->stack[stackBase + rd + 3] = Value::from(idx);
							t->stack[stackBase + rd] = Value::from(idx + step);
							(*pc) += jump;
						}
					}
					break;
				}
				case Op_Foreach: {
					auto jump = GetImm();
					auto src = t->stack[stackBase + rd];

					if(src.type != CrocType_Function && src.type != CrocType_Thread)
					{
						auto method = getMM(t, src, MM_Apply);

						if(method == nullptr)
						{
							pushTypeStringImpl(t, src);
							croc_eh_throwStd(*t, "TypeError", "No implementation of %s for type '%s'",
								MetaNames[MM_Apply], croc_getString(*t, -1));
						}

						t->stack[stackBase + rd + 2] = t->stack[stackBase + rd + 1];
						t->stack[stackBase + rd + 1] = src;
						t->stack[stackBase + rd] = Value::from(method);

						t->stackIndex = stackBase + rd + 3;
						commonCall(t, stackBase + rd, 3, callPrologue(t, stackBase + rd, 3, 2));
						t->stackIndex = t->currentAR->savedTop;

						src = t->stack[stackBase + rd];

						if(src.type != CrocType_Function && src.type != CrocType_Thread)
						{
							pushTypeStringImpl(t, src);
							croc_eh_throwStd(*t, "TypeError", "Invalid iterable type '%s' returned from opApply",
								croc_getString(*t, -1));
						}
					}

					if(src.type == CrocType_Thread && src.mThread->state != CrocThreadState_Initial)
						croc_eh_throwStd(*t, "StateError",
							"Attempting to iterate over a thread that is not in the 'initial' state");

					(*pc) += jump;
					break;
				}
				case Op_ForeachLoop: {
					auto numIndices = GetUImm();
					auto jump = GetImm();

					auto funcReg = rd + 3;

					t->stack[stackBase + funcReg + 2] = t->stack[stackBase + rd + 2];
					t->stack[stackBase + funcReg + 1] = t->stack[stackBase + rd + 1];
					t->stack[stackBase + funcReg] = t->stack[stackBase + rd];

					t->stackIndex = stackBase + funcReg + 3;
					commonCall(t, stackBase + funcReg, numIndices, callPrologue(t, stackBase + funcReg, numIndices, 2));
					t->stackIndex = t->currentAR->savedTop;

					auto src = &t->stack[stackBase + rd];

					if(src->type == CrocType_Function)
					{
						if(t->stack[stackBase + funcReg].type != CrocType_Null)
						{
							t->stack[stackBase + rd + 2] = t->stack[stackBase + funcReg];
							(*pc) += jump;
						}
					}
					else
					{
						if(src->mThread->state != CrocThreadState_Dead)
							(*pc) += jump;
					}
					break;
				}
				// Exception Handling
				case Op_PushCatch:
				case Op_PushFinally: {
					auto offs = GetImm();
					pushScriptEHFrame(t, opcode == Op_PushCatch, cast(RelStack)rd, offs);
					break;
				}
				case Op_PopEH2:
				case Op_PopEH: popEHFrame(t); break;

				case Op_EndFinal:
					if(t->vm->exception != nullptr)
						throwImpl(t, Value::from(t->vm->exception), true);

					if(t->currentAR->unwindReturn != nullptr)
						unwind(t);

					break;

				case Op_Throw:
					GetRS();
					throwImpl(t, *RS, cast(bool)rd);

					// Thread can change in throw -- if we threw past a thread resume into another thread, and the
					// exception was caught by a script handler.
					if(t != t->vm->curThread)
					{
						t = t->vm->curThread;
						goto _exceptionRetry;
					}
					else
						goto _reentry;

				// Function Calling
			{
				bool isScript;
				word numResults;
				uword numParams;

				case Op_Method:
				case Op_TailMethod:
					GetRS();
					GetRT();
					numParams = GetUImm();
					numResults = GetUImm() - 1;

					if(opcode == Op_TailMethod)
						numResults = -1; // the second uimm is a dummy for these opcodes

					if(RT->type != CrocType_String)
					{
						pushTypeStringImpl(t, *RT);
						croc_eh_throwStd(*t, "TypeError",
							"Attempting to get a method with a non-string name (type '%s' instead)",
							croc_getString(*t, -1));
					}

					AdjustParams();
					isScript = commonMethodCall(t, stackBase + rd, *RS, *RS, RT->mString, numResults, numParams);

					if(opcode == Op_Method)
						goto _commonCall;
					else
						goto _commonTailcall;

				case Op_Call:
				case Op_TailCall:
					numParams = GetUImm();
					numResults = GetUImm() - 1;

					if(opcode == Op_TailCall)
						numResults = -1; // second uimm is a dummy

					AdjustParams();

					isScript = callPrologue(t, stackBase + rd, numResults, numParams);

					if(opcode == Op_TailCall)
						goto _commonTailcall;

					// fall through
				_commonCall:
					croc_gc_maybeCollect(*t);

					if(isScript)
						goto _reentry;
					else
					{
						if(numResults >= 0)
							t->stackIndex = t->currentAR->savedTop;
					}
					break;

				_commonTailcall:
					croc_gc_maybeCollect(*t);

					if(isScript)
					{
						auto prevAR = t->currentAR - 1;
						closeUpvals(t, prevAR->base);

						auto diff = cast(word)(t->currentAR->returnSlot - prevAR->returnSlot);

						auto tc = prevAR->numTailcalls + 1;
						t->currentAR->expectedResults = prevAR->expectedResults;
						*prevAR = *t->currentAR;
						prevAR->numTailcalls = tc;
						prevAR->base -= diff;
						prevAR->savedTop -= diff;
						prevAR->vargBase -= diff;
						prevAR->returnSlot -= diff;

						popARTo(t, t->arIndex - 1);

						//memmove(&t->stack[prevAR->returnSlot], &t->stack[prevAR->returnSlot + diff], (prevAR->savedTop - prevAR->returnSlot) * sizeof(Value));

						for(auto idx = prevAR->returnSlot; idx < prevAR->savedTop; idx++)
							t->stack[idx] = t->stack[idx + diff];

						goto _reentry;
					}

					// Do nothing for native calls. The following return instruction will catch it.
					break;
			}

				case Op_SaveRets: {
					auto numResults = GetUImm();
					auto firstResult = stackBase + rd;

					if(numResults == 0)
					{
						saveResults(t, t, firstResult, t->stackIndex - firstResult);
						t->stackIndex = t->currentAR->savedTop;
					}
					else
						saveResults(t, t, firstResult, numResults - 1);
					break;
				}
				case Op_Ret:
					callEpilogue(t);

					if(t->arIndex == 0 || t->currentAR->incdNativeDepth)
						return;

					goto _reentry;

				case Op_Unwind:
					t->currentAR->unwindReturn = (*pc);
					t->currentAR->unwindCounter = rd;
					unwind(t);
					break;

				case Op_Vararg: {
					uword numNeeded = GetUImm();
					auto numVarargs = stackBase - t->currentAR->vargBase;
					auto dest = stackBase + rd;

					if(numNeeded == 0)
					{
						numNeeded = numVarargs;
						t->stackIndex = dest + numVarargs;
						checkStack(t, t->stackIndex);
					}
					else
						numNeeded--;

					auto src = t->currentAR->vargBase;

					if(numNeeded <= numVarargs)
						memmove(&t->stack[dest], &t->stack[src], numNeeded * sizeof(Value));
					else
					{
						memmove(&t->stack[dest], &t->stack[src], numVarargs * sizeof(Value));
						t->stack.slice(dest + numVarargs, dest + numNeeded).fill(Value::nullValue);
					}

					break;
				}
				case Op_VargLen:
					t->stack[stackBase + rd] = Value::from(cast(crocint)(stackBase - t->currentAR->vargBase));
					break;

				case Op_VargIndex: {
					GetRS();

					auto numVarargs = stackBase - t->currentAR->vargBase;

					if(RS->type != CrocType_Int)
					{
						pushTypeStringImpl(t, *RS);
						croc_eh_throwStd(*t, "TypeError", "Attempting to index 'vararg' with a '%s'",
							croc_getString(*t, -1));
					}

					auto index = RS->mInt;

					if(index < 0)
						index += numVarargs;

					if(index < 0 || index >= numVarargs)
						croc_eh_throwStd(*t, "BoundsError",
							"Invalid 'vararg' index: %" CROC_INTEGER_FORMAT " (only have %d)", index, numVarargs);

					t->stack[stackBase + rd] = t->stack[t->currentAR->vargBase + cast(uword)index];
					break;
				}
				case Op_VargIndexAssign: {
					GetRS();
					GetRT();

					auto numVarargs = stackBase - t->currentAR->vargBase;

					if(RS->type != CrocType_Int)
					{
						pushTypeStringImpl(t, *RS);
						croc_eh_throwStd(*t, "TypeError", "Attempting to index 'vararg' with a '%s'",
							croc_getString(*t, -1));
					}

					auto index = RS->mInt;

					if(index < 0)
						index += numVarargs;

					if(index < 0 || index >= numVarargs)
						croc_eh_throwStd(*t, "BoundsError",
							"Invalid 'vararg' index: %" CROC_INTEGER_FORMAT " (only have %d)", index, numVarargs);

					t->stack[t->currentAR->vargBase + cast(uword)index] = *RT;
					break;
				}
				case Op_VargSlice: {
					uword numNeeded = GetUImm();
					auto numVarargs = stackBase - t->currentAR->vargBase;

					crocint lo;
					crocint hi;

					auto loSrc = t->stack[stackBase + rd];
					auto hiSrc = t->stack[stackBase + rd + 1];

					if(!correctIndices(lo, hi, loSrc, hiSrc, numVarargs))
					{
						pushTypeStringImpl(t, t->stack[stackBase + rd]);
						pushTypeStringImpl(t, t->stack[stackBase + rd + 1]);
						croc_eh_throwStd(*t, "TypeError", "Attempting to slice 'vararg' with '%s' and '%s'",
							croc_getString(*t, -2), croc_getString(*t, -1));
					}

					if(lo > hi || lo < 0 || lo > numVarargs || hi < 0 || hi > numVarargs)
						croc_eh_throwStd(*t, "BoundsError",
							"Invalid vararg slice indices [%" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT "]",
							lo, hi);

					auto sliceSize = cast(uword)(hi - lo);
					auto src = t->currentAR->vargBase + cast(uword)lo;
					auto dest = stackBase + cast(uword)rd;

					if(numNeeded == 0)
					{
						numNeeded = sliceSize;
						t->stackIndex = dest + sliceSize;
						checkStack(t, t->stackIndex);
					}
					else
						numNeeded--;

					if(numNeeded <= sliceSize)
						memmove(&t->stack[dest], &t->stack[src], numNeeded * sizeof(Value));
					else
					{
						memmove(&t->stack[dest], &t->stack[src], sliceSize * sizeof(Value));
						t->stack.slice(dest + sliceSize, dest + numNeeded).fill(Value::nullValue);
					}
					break;
				}
				case Op_Yield: {
					auto numParams = cast(word)GetUImm() - 1;
					auto numResults = cast(word)GetUImm() - 1;

					if(t == t->vm->mainThread)
						croc_eh_throwStd(*t, "RuntimeError", "Attempting to yield out of the main thread");

					if(t->nativeCallDepth > 0)
						croc_eh_throwStd(*t, "RuntimeError",
							"Attempting to yield across native / metamethod call boundary");

					yieldImpl(t, stackBase + rd, numParams, numResults);
					return;
				}
				case Op_CheckParams: {
					auto val = &t->stack[stackBase];
					auto masks = t->currentAR->func->scriptFunc->paramMasks;

					for(uword idx = 0; idx < masks.length; idx++)
					{
						if(!(masks[idx] & (1 << val->type)))
						{
							pushTypeStringImpl(t, *val);

							if(idx == 0)
								croc_eh_throwStd(*t, "TypeError", "'this' parameter: type '%s' is not allowed",
									croc_getString(*t, -1));
							else
								croc_eh_throwStd(*t, "TypeError", "Parameter %u: type '%s' is not allowed",
									idx, croc_getString(*t, -1));
						}

						val++;
					}
					break;
				}
				case Op_CheckObjParam: {
					auto RD = &t->stack[stackBase + rd];
					GetRS();
					auto jump = GetImm();

					if(RD->type != CrocType_Instance)
						(*pc) += jump;
					else
					{
						if(RS->type != CrocType_Class)
						{
							pushTypeStringImpl(t, *RS);

							if(rd == 0)
								croc_eh_throwStd(*t, "TypeError",
									"'this' parameter: instance type constraint type must be 'class', not '%s'",
									croc_getString(*t, -1));
							else
								croc_eh_throwStd(*t, "TypeError",
									"Parameter %u: instance type constraint type must be 'class', not '%s'",
									rd, croc_getString(*t, -1));
						}

						if(RD->mInstance->derivesFrom(RS->mClass))
							(*pc) += jump;
					}
					break;
				}
				case Op_ObjParamFail: {
					pushTypeStringImpl(t, t->stack[stackBase + rd]);

					if(rd == 0)
						croc_eh_throwStd(*t, "TypeError", "'this' parameter: type '%s' is not allowed",
							croc_getString(*t, -1));
					else
						croc_eh_throwStd(*t, "TypeError", "Parameter %u: type '%s' is not allowed",
							rd, croc_getString(*t, -1));

					break;
				}
				case Op_CustomParamFail: {
					pushTypeStringImpl(t, t->stack[stackBase + rd]);
					GetRS();

					if(rd == 0)
						croc_eh_throwStd(*t, "TypeError", "'this' parameter: type '%s' does not satisfy constraint '%s'",
							croc_getString(*t, -1), RS->mString->toCString());
					else
						croc_eh_throwStd(*t, "TypeError", "Parameter %u: type '%s' does not satisfy constraint '%s'",
							rd, croc_getString(*t, -1), RS->mString->toCString());
					break;
				}
				case Op_AssertFail: {
					auto msg = t->stack[stackBase + rd];

					if(msg.type != CrocType_String)
					{
						pushTypeStringImpl(t, msg);
						croc_eh_throwStd(*t, "AssertError",
							"Assertion failed, but the message is a '%s', not a 'string'", croc_getString(*t, -1));
					}

					croc_eh_throwStd(*t, "AssertError", "%s", msg.mString->toCString());
					assert(false);
				}
				// Array and List Operations
				case Op_Length:       GetRS(); lenImpl(t, stackBase + rd, *RS);  break;
				case Op_LengthAssign: GetRS(); lenaImpl(t, t->stack[stackBase + rd], *RS); break;
				case Op_Append:       GetRS(); t->stack[stackBase + rd].mArray->append(t->vm->mem, *RS); break;

				case Op_SetArray: {
					auto numVals = GetUImm();
					auto block = GetUImm();
					auto sliceBegin = stackBase + rd + 1;
					auto a = t->stack[stackBase + rd].mArray;

					if(numVals == 0)
					{
						a->setBlock(t->vm->mem, block, t->stack.slice(sliceBegin, t->stackIndex));
						t->stackIndex = t->currentAR->savedTop;
					}
					else
						a->setBlock(t->vm->mem, block, t->stack.slice(sliceBegin, sliceBegin + numVals - 1));

					break;
				}
				case Op_Cat: {
					auto rs = GetUImm();
					auto numVals = GetUImm();
					catImpl(t, stackBase + rd, stackBase + rs, numVals);
					croc_gc_maybeCollect(*t);
					break;
				}
				case Op_CatEq: {
					auto rs = GetUImm();
					auto numVals = GetUImm();
					catEqImpl(t, stackBase + rd, stackBase + rs, numVals);
					croc_gc_maybeCollect(*t);
					break;
				}
				case Op_Index:       GetRS(); GetRT(); idxImpl(t, stackBase + rd, *RS, *RT);  break;
				case Op_IndexAssign: GetRS(); GetRT(); idxaImpl(t, stackBase + rd, *RS, *RT); break;

				case Op_Field: {
					GetRS();
					GetRT();

					if(RT->type != CrocType_String)
					{
						pushTypeStringImpl(t, *RT);
						croc_eh_throwStd(*t, "TypeError", "Field name must be a string, not a '%s'",
							croc_getString(*t, -1));
					}

					fieldImpl(t, stackBase + rd, *RS, RT->mString, false);
					break;
				}
				case Op_FieldAssign: {
					GetRS();
					GetRT();

					if(RS->type != CrocType_String)
					{
						pushTypeStringImpl(t, *RS);
						croc_eh_throwStd(*t, "TypeError", "Field name must be a string, not a '%s'",
							croc_getString(*t, -1));
					}

					fieldaImpl(t, stackBase + rd, RS->mString, *RT, false);
					break;
				}
				case Op_Slice: {
					auto rs = GetUImm();
					auto base = &t->stack[stackBase + rs];
					sliceImpl(t, stackBase + rd, base[0], base[1], base[2]);
					break;
				}
				case Op_SliceAssign: {
					GetRS();
					auto base = &t->stack[stackBase + rd];
					sliceaImpl(t, base[0], base[1], base[2], *RS);
					break;
				}
				// Value Creation
				case Op_NewArray: {
					auto size = cast(uword)constTable[GetUImm()].mInt;
					t->stack[stackBase + rd] = Value::from(Array::create(t->vm->mem, size));
					croc_gc_maybeCollect(*t);
					break;
				}
				case Op_NewTable: {
					t->stack[stackBase + rd] = Value::from(Table::create(t->vm->mem));
					croc_gc_maybeCollect(*t);
					break;
				}
				case Op_Closure:
				case Op_ClosureWithEnv: {
					auto closureIdx = GetUImm();
					auto newDef = t->currentAR->func->scriptFunc->innerFuncs[closureIdx];
					auto funcEnv = (opcode == Op_Closure) ? env : t->stack[stackBase + rd].mNamespace;
					auto n = Function::create(t->vm->mem, funcEnv, newDef);

					if(n == nullptr)
					{
						toStringImpl(t, Value::from(newDef), false);
						croc_eh_throwStd(*t, "RuntimeError",
							"Attempting to instantiate %s with a different namespace than was associated with it",
							croc_getString(*t, -1));
					}

					auto uvTable = newDef->upvals;
					auto newUpvals = n->scriptUpvals();

					for(uword id = 0; id < uvTable.length; id++)
					{
						if(uvTable[id].isUpval)
							newUpvals[id] = upvals[uvTable[id].index];
						else
							newUpvals[id] = findUpval(t, uvTable[id].index);
					}

					t->stack[stackBase + rd] = Value::from(n);
					croc_gc_maybeCollect(*t);
					break;
				}
				case Op_Class: {
					GetRS();
					GetRT();

					auto cls = Class::create(t->vm->mem, RS->mString);
					auto numBases = GetUImm();

					for(auto &base: DArray<Value>::n(RT, numBases))
					{
						if(base.type != CrocType_Class)
						{
							pushTypeStringImpl(t, base);
							croc_eh_throwStd(*t, "TypeError", "Attempting to derive a class from a value of type '%s'",
								croc_getString(*t, -1));
						}

						classDeriveImpl(t, cls, base.mClass);
					}

					t->stack[stackBase + rd] = Value::from(cls);
					croc_gc_maybeCollect(*t);
					break;
				}
				case Op_Namespace: {
					auto name = constTable[GetUImm()].mString;
					GetRT();

					if(RT->type == CrocType_Null)
						t->stack[stackBase + rd] = Value::from(Namespace::create(t->vm->mem, name));
					else if(RT->type == CrocType_Namespace)
						t->stack[stackBase + rd] = Value::from(Namespace::create(t->vm->mem, name, RT->mNamespace));
					else
					{
						pushTypeStringImpl(t, *RT);
						push(t, Value::from(name));
						croc_eh_throwStd(*t, "TypeError",
							"Attempted to use a '%s' as a parent namespace for namespace '%s'",
							croc_getString(*t, -2), croc_getString(*t, -1));
					}

					croc_gc_maybeCollect(*t);
					break;
				}
				case Op_NamespaceNP: {
					auto name = constTable[GetUImm()].mString;
					t->stack[stackBase + rd] = Value::from(Namespace::create(t->vm->mem, name, env));
					croc_gc_maybeCollect(*t);
					break;
				}
				case Op_SuperOf: {
					GetRS();
					t->stack[stackBase + rd] = superOfImpl(t, *RS);
					break;
				}
				case Op_AddMember: {
					auto cls = &t->stack[stackBase + rd];
					GetRS();
					GetRT();
					auto flags = GetUImm();

					// should be guaranteed this by codegen
					assert(cls->type == CrocType_Class && RS->type == CrocType_String);

					auto isMethod = (flags & 1) != 0;
					auto isOverride = (flags & 2) != 0;

					auto okay = isMethod?
						cls->mClass->addMethod(t->vm->mem, RS->mString, *RT, isOverride) :
						cls->mClass->addField(t->vm->mem, RS->mString, *RT, isOverride);

					if(!okay)
					{
						auto name = RS->mString->toCString();
						auto clsName = cls->mClass->name->toCString();

						if(isOverride)
							croc_eh_throwStd(*t, "FieldError",
								"Attempting to override %s '%s' in class '%s', but no such member already exists",
								isMethod ? "method" : "field", name, clsName);
						else
							croc_eh_throwStd(*t, "FieldError",
								"Attempting to add a %s '%s' which already exists to class '%s'",
								isMethod ? "method" : "field", name, clsName);
					}
					break;
				}
				default:
					croc_eh_throwStd(*t, "VMError", "Unimplemented opcode %s", OpNames[cast(uword)opcode]);
			}
		}
	}
}