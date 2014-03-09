
#include "croc/compiler/builder.hpp"
#include <functional>

#include "croc/api.h"
#include "croc/base/opcodes.hpp"
#include "croc/compiler/ast.hpp"
#include "croc/compiler/types.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

/*
any = any, duh
src = Local|Const
multret = Call|Yield|Vararg|VarargSlice
args = ((n-1)*Temp Temp|multret)?
dst = anything but Const, Vararg, VarargSlice, Call, Yield, NeedsDest, or Conflict
*/

namespace croc
{
	namespace
	{
		Op AstTagToOpcode(AstTag tag)
		{
			switch(tag)
			{
				// Unary
				case AstTag_NegExp:         return Op_Neg;
				case AstTag_NotExp:         return Op_Not;
				case AstTag_ComExp:         return Op_Com;
				case AstTag_DotSuperExp:    return Op_SuperOf;

				// Binary
				case AstTag_AddExp:         return Op_Add;
				case AstTag_SubExp:         return Op_Sub;
				case AstTag_MulExp:         return Op_Mul;
				case AstTag_DivExp:         return Op_Div;
				case AstTag_ModExp:         return Op_Mod;
				case AstTag_AndExp:         return Op_And;
				case AstTag_OrExp:          return Op_Or;
				case AstTag_XorExp:         return Op_Xor;
				case AstTag_ShlExp:         return Op_Shl;
				case AstTag_ShrExp:         return Op_Shr;
				case AstTag_UShrExp:        return Op_UShr;
				case AstTag_Cmp3Exp:        return Op_Cmp3;

				// Reflex
				case AstTag_AddAssignStmt:  return Op_AddEq;
				case AstTag_SubAssignStmt:  return Op_SubEq;
				case AstTag_MulAssignStmt:  return Op_MulEq;
				case AstTag_DivAssignStmt:  return Op_DivEq;
				case AstTag_ModAssignStmt:  return Op_ModEq;
				case AstTag_AndAssignStmt:  return Op_AndEq;
				case AstTag_OrAssignStmt:   return Op_OrEq;
				case AstTag_XorAssignStmt:  return Op_XorEq;
				case AstTag_ShlAssignStmt:  return Op_ShlEq;
				case AstTag_ShrAssignStmt:  return Op_ShrEq;
				case AstTag_UShrAssignStmt: return Op_UShrEq;

				default: assert(false); return Op_Neg; // dummy
			}
		}
	}
#ifndef NDEBUG
	const char* expTypeToString(ExpType type)
	{
		switch(type)
		{
			case ExpType::Const:       return "Const";
			case ExpType::Local:       return "Local/Temp";
			case ExpType::NewLocal:    return "NewLocal";
			case ExpType::Upval:       return "Upval";
			case ExpType::Global:      return "Global";
			case ExpType::NewGlobal:   return "NewGlobal";
			case ExpType::Index:       return "Index";
			case ExpType::Field:       return "Field";
			case ExpType::Slice:       return "Slice";
			case ExpType::Vararg:      return "Vararg";
			case ExpType::VarargIndex: return "VarargIndex";
			case ExpType::VarargSlice: return "VarargSlice";
			case ExpType::Length:      return "Length";
			case ExpType::Call:        return "Call";
			case ExpType::Yield:       return "Yield";
			case ExpType::NeedsDest:   return "NeedsDest";
			case ExpType::Conflict:    return "Conflict";
			default: assert(false); return nullptr; // dummy
		}
	}
#endif
	// =================================================================================================================
	// Misc

	FuncBuilder::~FuncBuilder()
	{
		mExpStack.free(c.mem());

		for(auto &s: mInProgressSwitches.slice(0, mSwitchIdx))
			s.offsets.clear(c.mem());

		mInProgressSwitches.free(c.mem());

		for(auto &s: mSwitchTables)
			s.offsets.clear(c.mem());
	}

	void FuncBuilder::setVararg(bool isVararg)
	{
		mIsVararg = isVararg;
	}

	bool FuncBuilder::isVararg()
	{
		return mIsVararg;
	}

	void FuncBuilder::setNumParams(uword numParams)
	{
		mNumParams = numParams;
	}

	FuncBuilder* FuncBuilder::parent()
	{
		return mParent;
	}

	// =================================================================================================================
	// Debugging
#ifndef NDEBUG
	void FuncBuilder::printExpStack()
	{
		printf("Expression Stack\n");
		printf("----------------\n");

		for(uword i = mExpSP - 1; cast(word)i >= 0; i--)
		{
			printf("%" CROC_SIZE_T_FORMAT ": ", i);
			mExpStack[i].print();
		}

		printf("\n");
	}

	void FuncBuilder::checkExpStackEmpty()
	{
		if(mExpSP != 0)
		{
			printExpStack();
			assert(false);
		}
	}
#endif
	// =================================================================================================================
	// Scopes

	void FuncBuilder::pushScope(Scope& s)
	{
		if(mScope)
		{
			s.enclosing = mScope;
			s.breakScope = mScope->breakScope;
			s.continueScope = mScope->continueScope;
			s.ehlevel = mScope->ehlevel;
		}
		else
		{
			// leave these all in here, have to initialize void-initialized scopes
			s.enclosing = nullptr;
			s.breakScope = nullptr;
			s.continueScope = nullptr;
			s.ehlevel = 0;
		}

		s.breaks = INST_NO_JUMP;
		s.continues = INST_NO_JUMP;
		s.varStart = mLocVars.length();
		s.regStart = mFreeReg;
		s.firstFreeReg = mFreeReg;
		s.hasUpval = false;
		s.name = crocstr();

		mScope = &s;
	}

	void FuncBuilder::popScope(CompileLoc loc)
	{
		assert(mScope != nullptr);

		auto prev = mScope->enclosing;

		closeScopeUpvals(loc);
		deactivateLocals(mScope->varStart, mScope->regStart);
		mFreeReg = mScope->regStart;
		mScope = prev;
	}

	void FuncBuilder::setBreakable()
	{
		mScope->breakScope = mScope;
	}

	void FuncBuilder::setContinuable()
	{
		mScope->continueScope = mScope;
	}

	void FuncBuilder::setScopeName(crocstr name)
	{
		mScope->name = name;
	}

	void FuncBuilder::closeScopeUpvals(CompileLoc loc)
	{
		if(mScope->hasUpval)
		{
			codeClose(loc, mScope->regStart);
			mScope->hasUpval = false;
		}
	}

	// =================================================================================================================
	// Locals

	void FuncBuilder::addParam(Identifier* ident, uword typeMask)
	{
		insertLocal(ident);
		mParamMasks.add(typeMask);
	}

	uword FuncBuilder::insertLocal(Identifier* ident)
	{
		uword dummy;
		auto index = searchLocal(ident->name, dummy);

		if(index != -1)
		{
			auto l = mLocVars[index].location;
			c.semException(ident->location,
				"Local '%s' conflicts with previous definition at %s(%" CROC_SIZE_T_FORMAT ":%" CROC_SIZE_T_FORMAT ")",
				ident->name.ptr, l.file.ptr, l.line, l.col);
		}

		LocVarDesc lv {};
		lv.name = ident->name;
		lv.location = ident->location;
		lv.reg = pushRegister();
		lv.isActive = false;
		mLocVars.add(lv);
		return lv.reg;
	}

	void FuncBuilder::activateLocals(uword num)
	{
		for(uword i = mLocVars.length() - 1; cast(word)i >= cast(word)(mLocVars.length() - num); i--)
		{
			DEBUG_VARACTIVATE(
			{
				auto l = mLocVars[i].location;
				printf("activating %s %s(%u:%u) reg %u", mLocVars[i].name, l.file, l.line, l.col, mLocVars[i].reg);
			});

			mLocVars[i].isActive = true;
			mLocVars[i].pcStart = here();
		}

		mScope->firstFreeReg = mLocVars[mLocVars.length() - 1].reg + 1;

		if(mExpSP > 0 && getExp(-1).regAfter < mScope->firstFreeReg)
			getExp(-1).regAfter = mScope->firstFreeReg;
	}

	// =================================================================================================================
	// Switches

	// [src] => []
	void FuncBuilder::beginSwitch(CompileLoc loc)
	{
		auto &cond = getExp(-1);
		assert(cond.isSource());

		if(mSwitchIdx >= mInProgressSwitches.length)
		{
			if(mInProgressSwitches.length == 0)
				mInProgressSwitches = DArray<SwitchDesc>::alloc(c.mem(), 4);
			else
				mInProgressSwitches.resize(c.mem(), mInProgressSwitches.length * 2);
		}

		auto &s = mInProgressSwitches[mSwitchIdx++];
		s = SwitchDesc();
		s.switchPC = codeRD(loc, Op_Switch, 0);
		codeRC(cond);
		pop();
	}

	void FuncBuilder::endSwitch()
	{
		assert(mSwitchIdx > 0);

		auto &s = mInProgressSwitches[mSwitchIdx - 1];

		if(s.offsets.length() > 0 || s.defaultOffset == -1)
		{
			mSwitchTables.add(s);
			auto switchIdx = mSwitchTables.length() - 1;

			if(switchIdx > INST_MAX_SWITCH_TABLE)
				c.semException(mLocation, "Too many switches");

			setRD(s.switchPC, switchIdx);
		}
		else
		{
			// Happens when all the cases are dynamic and there is a default -- no need to add a switch table then
			setOpcode(s.switchPC, Op_Jmp);
			setRD(s.switchPC, 1);
			setJumpOffset(s.switchPC, s.defaultOffset);
		}

		mSwitchIdx--;
	}

	void FuncBuilder::addCase(CompileLoc loc, Expression* v)
	{
		assert(mSwitchIdx > 0);

		Value val;

		if(v->isNull())
			val = Value::nullValue;
		else if(v->isBool())
			val = Value::from(v->asBool());
		else if(v->isInt())
			val = Value::from(v->asInt());
		else if(v->isFloat())
			val = Value::from(v->asFloat());
		else if(v->isString())
			val = Value::from(String::create(t->vm, v->asString()));
		else
			assert(false);

		auto &s = mInProgressSwitches[mSwitchIdx - 1];

		if(s.offsets.lookup(val) != nullptr)
		{
			croc_pushString(*t, "Duplicate case value '");
			push(t, val);
			croc_pushToString(*t, -1);
			croc_insertAndPop(*t, -2);
			croc_pushString(*t, "'");
			croc_cat(*t, 3);
			c.semException(loc, croc_getString(*t, -1));
		}

		*s.offsets.insert(c.mem(), val) = jumpDiff(s.switchPC, here());
	}

	void FuncBuilder::addDefault()
	{
		assert(mSwitchIdx > 0);
		auto &s = mInProgressSwitches[mSwitchIdx - 1];
		assert(s.defaultOffset == -1);
		s.defaultOffset = jumpDiff(s.switchPC, here());
	}

	// =================================================================================================================
	// Numeric for/foreach loops

	ForDesc FuncBuilder::beginFor(CompileLoc loc, std::function<void()> dg)
	{
		return beginForImpl(loc, dg, Op_For, 3);
	}

	ForDesc FuncBuilder::beginForeach(CompileLoc loc, std::function<void()> dg, uword containerSize)
	{
		return beginForImpl(loc, dg, Op_Foreach, containerSize);
	}

	ForDesc FuncBuilder::beginForImpl(CompileLoc loc, std::function<void()> dg, Op opcode, uword containerSize)
	{
		ForDesc ret {};
		ret.baseReg = mFreeReg;
		pushNewLocals(3);
		dg();
		assign(loc, 3, containerSize);
		insertDummyLocal(loc, CROC_INTERNAL_NAME("hidden%u"));
		insertDummyLocal(loc, CROC_INTERNAL_NAME("hidden%u"));
		insertDummyLocal(loc, CROC_INTERNAL_NAME("hidden%u"));
		activateLocals(3);

		ret.beginJump = codeRD(loc, opcode, ret.baseReg); codeImm(INST_NO_JUMP);
		ret.beginLoop = here();
		return ret;
	}

	void FuncBuilder::endFor(CompileLoc loc, ForDesc desc)
	{
		endForImpl(loc, desc, Op_ForLoop, 0);
	}

	void FuncBuilder::endForeach(CompileLoc loc, ForDesc desc, uword indLength)
	{
		endForImpl(loc, desc, Op_ForeachLoop, indLength);
	}

	void FuncBuilder::endForImpl(CompileLoc loc, ForDesc desc, Op opcode, uword indLength)
	{
		closeScopeUpvals(loc);
		patchContinuesToHere();
		patchJumpToHere(desc.beginJump);

		uword j = codeRD(loc, opcode, desc.baseReg);

		if(opcode == Op_ForeachLoop)
			codeUImm(indLength);

		codeImm(INST_NO_JUMP);

		patchJumpTo(j, desc.beginLoop);
		patchBreaksToHere();
	}

	// =================================================================================================================
	// Basic expression stack manipulation

	// [any] => []
	void FuncBuilder::pop(uword num)
	{
		assert(num != 0);
		assert(mExpSP >= num);

		mExpSP -= num;

		if(mExpSP == 0)
			mFreeReg = mScope->firstFreeReg;
		else
			mFreeReg = mExpStack[mExpSP - 1].regAfter;
	}

	// [any] => [any any]
	void FuncBuilder::dup()
	{
		assert(mExpSP > 0);
		pushExp(ExpType::Const, 0); // dummy
		mExpStack[mExpSP - 1] = mExpStack[mExpSP - 2];
	}

	// =================================================================================================================
	// Expression stack pushes

	// [] => [Const]
	void FuncBuilder::pushNull()
	{
		pushConst(addNullConst());
	}

	// [] => [Const]
	void FuncBuilder::pushBool(bool value)
	{
		pushConst(addBoolConst(value));
	}

	// [] => [Const]
	void FuncBuilder::pushInt(crocint value)
	{
		pushConst(addIntConst(value));
	}

	// [] => [Const]
	void FuncBuilder::pushFloat(crocfloat value)
	{
		pushConst(addFloatConst(value));
	}

	// [] => [Const]
	void FuncBuilder::pushString(crocstr value)
	{
		pushConst(addStringConst(value));
	}

	// [] => [NewGlobal]
	void FuncBuilder::pushNewGlobal(Identifier* name)
	{
		pushExp(ExpType::NewGlobal, addStringConst(name->name));
	}

	// [] => [Local]
	void FuncBuilder::pushThis()
	{
		pushExp(ExpType::Local, 0);
	}

	void FuncBuilder::addUpval(Identifier* name, Exp& e)
	{
		// See if we already have a desc
		uword i = 0;
		for(auto &uv: mUpvals)
		{
			if(uv.name == name->name)
			{
				if((  uv.isUpvalue && e.type == ExpType::Upval) ||
					(!uv.isUpvalue && e.type == ExpType::Local))
				{
					e.index = i;
					e.type = ExpType::Upval;
					return;
				}
			}

			i++;
		}

		// Nope, add a new one
		UpvalDesc ud {};

		ud.name = name->name;
		ud.isUpvalue = (e.type == ExpType::Upval);
		ud.index = e.index;

		mUpvals.add(ud);

		if(mUpvals.length() > INST_MAX_UPVALUE)
			c.semException(mLocation, "Too many upvalues");

		e.index = mUpvals.length() - 1;
		e.type = ExpType::Upval;
	}

	void FuncBuilder::searchVar(FuncBuilder* fb, Identifier* name, Exp& e, bool isOriginal)
	{
		if(fb == nullptr)
		{
			// Got all the way up to the top without finding anything, it's global
			e.type = ExpType::Global;
			return;
		}

		uword reg;
		auto index = fb->searchLocal(name->name, reg);

		if(index == -1)
		{
			// No local in this function; see if it's in an enclosing one
			searchVar(fb->mParent, name, e, false);

			if(e.type == ExpType::Global)
				return;

			// There's a local in an enclosing function, so let's add an upval to it
			fb->addUpval(name, e);
		}
		else
		{
			// Found it, just a regular local
			e.index = reg;
			e.type = ExpType::Local;

			if(!isOriginal)
			{
				// If we're in an enclosing function, that means this local will be used as an upval
				for(auto sc = fb->mScope; sc != nullptr; sc = sc->enclosing)
				{
					if(sc->regStart <= reg)
					{
						sc->hasUpval = true;
						break;
					}
				}
			}
		}
	}

	// [] => [Local|Upval|Global]
	void FuncBuilder::pushVar(Identifier* name)
	{
		auto &e = pushExp();
		e.type = ExpType::Local;
		searchVar(this, name, e);

		if(e.type == ExpType::Global)
			e.index = addStringConst(name->name);
	}

	// [] => [Vararg]
	void FuncBuilder::pushVararg(CompileLoc loc)
	{
		auto reg = pushRegister();
		pushExp(ExpType::Vararg, codeRD(loc, Op_Vararg, reg));
		codeUImm(0);
	}

	// [] => [NeedsDest]
	void FuncBuilder::pushVargLen(CompileLoc loc)
	{
		pushExp(ExpType::NeedsDest, codeRD(loc, Op_VargLen, 0));
	}

	// [] => [NeedsDest|Temp]
	void FuncBuilder::pushClosure(FuncBuilder* fb)
	{
		mInnerFuncs.add(nullptr);

		if(mInnerFuncs.length() > INST_MAX_INNER_FUNC)
			c.semException(mLocation, "Too many inner functions");

		auto loc = fb->mLocation;

		if(mNamespaceReg == 0)
			pushExp(ExpType::NeedsDest, codeRD(loc, Op_Closure, 0));
		else
		{
			auto reg = pushRegister();
			pushExp(ExpType::Temporary, reg);
			codeMove(loc, reg, mNamespaceReg);
			codeRD(loc, Op_ClosureWithEnv, reg);
		}

		codeUImm(mInnerFuncs.length() - 1);
		mInnerFuncs.last() = fb->toFuncDef();
	}

	// [] => [Temp]
	void FuncBuilder::pushTable(CompileLoc loc)
	{
		auto reg = pushRegister();
		pushExp(ExpType::Temporary, reg);
		codeRD(loc, Op_NewTable, reg);
	}

	// [] => [Temp]
	void FuncBuilder::pushArray(CompileLoc loc, uword length)
	{
		auto reg = pushRegister();
		pushExp(ExpType::Temporary, reg);
		codeRD(loc, Op_NewArray, reg);
		codeUImm(addIntConst(length));
	}

	// [] => [n*NewLocal]
	// (each one has a successive register number)
	void FuncBuilder::pushNewLocals(uword num)
	{
		for(auto reg = mFreeReg; num > 0; num--, reg++)
			pushExp(ExpType::NewLocal, checkRegOK(reg));
	}

	// =================================================================================================================
	// Expression stack pops

	// [any] => []
	// [] => []
	// If there's something on the stack, and it's a call or yield, sets its number of returns to 0.
	void FuncBuilder::popToNothing()
	{
		if(mExpSP == 0)
			return;

		auto &src = getExp(-1);

		if(src.type == ExpType::Call || src.type == ExpType::Yield)
			setMultRetReturns(src.index, 1);

		pop();
	}

	// [numLhs*dst Conflict? (numRhs-1)*src src|multret] => []
	// (NOTE: not really srcs on the rhs. just... non-side-effecting.. things? except for last?)
	void FuncBuilder::assign(CompileLoc loc, uword numLhs, uword numRhs)
	{
		assert(mExpSP >= numRhs + 1);
#ifndef NDEBUG
		if(mExpStack[mExpSP - numRhs - 1].type == ExpType::Conflict) assert(mExpSP >= numLhs + numRhs + 1);
#endif
		auto lhs = DArray<Exp>();
		auto rhs = DArray<Exp>();
		auto conflict = prepareAssignment(numLhs, numRhs, lhs, rhs);
		assert(lhs.length == rhs.length);

		for(auto &l: lhs.reverse())
			popMoveTo(loc, l); // pops top

		pop(lhs.length + (conflict ? 1 : 0));
	}

	// [Temp args] => []
	void FuncBuilder::arraySet(CompileLoc loc, uword numItems, uword block)
	{
		DEBUG_EXPSTACKCHECK(assert(numItems > 0);)
		DEBUG_EXPSTACKCHECK(assert(mExpSP >= numItems + 1);)

		auto &arr = mExpStack[mExpSP - numItems - 1];
		auto items = mExpStack.slice(mExpSP - numItems, mExpSP);

		DEBUG_EXPSTACKCHECK(assert(arr.type == ExpType::Temporary);)

		auto arg = prepareArgList(items);

		codeRD(loc, Op_SetArray, arr.index);
		codeUImm(arg);
		codeUImm(block);

		pop(numItems + 1); // all items and array
	}

	// [Temp src] => []
	void FuncBuilder::arrayAppend(CompileLoc loc)
	{
		DEBUG_EXPSTACKCHECK(assert(mExpSP >= 2);)

		auto &arr = getExp(-2);
		auto &item = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(arr.type == ExpType::Temporary);)
		DEBUG_EXPSTACKCHECK(assert(item.isSource());)

		codeRD(loc, Op_Append, arr.index);
		codeRC(item);

		pop(2);
	}

	// [src] => []
	void FuncBuilder::customParamFail(CompileLoc loc, uword paramIdx)
	{
		auto &msg = getExp(-1);
		DEBUG_EXPSTACKCHECK(assert(msg.isSource());)

		codeRD(loc, Op_CustomParamFail, paramIdx);
		codeRC(msg);

		pop();
	}

	// [src] => []
	void FuncBuilder::assertFail(CompileLoc loc)
	{
		auto &msg = getExp(-1);
		DEBUG_EXPSTACKCHECK(assert(msg.isSource());)

		codeRD(loc, Op_AssertFail, msg);
		pop();
	}

	// [src] => []
	uword FuncBuilder::checkObjParam(CompileLoc loc, uword paramIdx)
	{
		auto &type = getExp(-1);
		DEBUG_EXPSTACKCHECK(assert(type.isSource());)

		auto ret = codeRD(loc, Op_CheckObjParam, paramIdx);
		codeRC(type);
		codeImm(INST_NO_JUMP);

		pop();
		return ret;
	}

	// [src] => []
	uword FuncBuilder::codeIsTrue(CompileLoc loc, bool isTrue)
	{
		auto &src = getExp(-1);
		DEBUG_EXPSTACKCHECK(assert(src.isSource());)

		auto ret = codeRD(loc, Op_IsTrue, isTrue);
		codeRC(src);
		codeImm(INST_NO_JUMP);

		pop();
		return ret;
	}

	// [src src] => []
	uword FuncBuilder::codeCmp(CompileLoc loc, Comparison type)
	{
		return commonCmpJump(loc, Op_Cmp, type);
	}

	// [src src] => []
	uword FuncBuilder::codeSwitchCmp(CompileLoc loc)
	{
		return commonCmpJump(loc, Op_SwitchCmp, 0);
	}

	// [src src] => []
	uword FuncBuilder::codeEquals(CompileLoc loc, bool isTrue)
	{
		return commonCmpJump(loc, Op_Equals, isTrue);
	}

	// [src src] => []
	uword FuncBuilder::codeIs(CompileLoc loc, bool isTrue)
	{
		return commonCmpJump(loc, Op_Is, isTrue);
	}

	// [src src] => []
	uword FuncBuilder::codeIn(CompileLoc loc, bool isTrue)
	{
		return commonCmpJump(loc, Op_In, isTrue);
	}

	// [src] => []
	void FuncBuilder::codeThrow(CompileLoc loc, bool rethrowing)
	{
		auto &src = getExp(-1);
		DEBUG_EXPSTACKCHECK(assert(src.isSource());)

		codeRD(loc, Op_Throw, rethrowing ? 1 : 0);
		codeRC(src);

		pop();
	}

	// [args] => []
	void FuncBuilder::saveRets(CompileLoc loc, uword numRets)
	{
		if(numRets == 0)
		{
			codeRD(loc, Op_SaveRets, 0);
			codeUImm(1);
			return;
		}

		assert(mExpSP >= numRets);
		auto rets = mExpStack.slice(mExpSP - numRets, mExpSP);
		auto arg = prepareArgList(rets);
		uword first = rets[0].index;
		codeRD(loc, Op_SaveRets, first);
		codeUImm(arg);
		pop(numRets);
	}

	// [Local Const src] => []
	void FuncBuilder::addClassField(CompileLoc loc, bool isOverride)
	{
		auto &cls = getExp(-3);
		auto &name = getExp(-2);
		auto &src = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(cls.type == ExpType::Local);)
		DEBUG_EXPSTACKCHECK(assert(name.type == ExpType::Const);)
		DEBUG_EXPSTACKCHECK(assert(src.isSource());)

		codeRD(loc, Op_AddMember, cls);
		codeRC(name);
		codeRC(src);
		codeUImm(0 | (isOverride ? 2 : 0));

		pop(3);
	}

	// [Local Const src] => []
	void FuncBuilder::addClassMethod(CompileLoc loc, bool isOverride)
	{
		auto &cls = getExp(-3);
		auto &name = getExp(-2);
		auto &src = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(cls.type == ExpType::Local);)
		DEBUG_EXPSTACKCHECK(assert(name.type == ExpType::Const);)
		DEBUG_EXPSTACKCHECK(assert(src.isSource());)

		codeRD(loc, Op_AddMember, cls);
		codeRC(name);
		codeRC(src);
		codeUImm(1 | (isOverride ? 2 : 0));

		pop(3);
	}

	// =================================================================================================================
	// Other codegen funcs

	void FuncBuilder::objParamFail(CompileLoc loc, uword paramIdx)
	{
		codeRD(loc, Op_ObjParamFail, paramIdx);
	}

	void FuncBuilder::paramCheck(CompileLoc loc)
	{
		codeRD(loc, Op_CheckParams, 0);
	}

	// [Temp]
	void FuncBuilder::incDec(CompileLoc loc, AstTag type)
	{
		assert(type == AstTag_IncStmt || type == AstTag_DecStmt);
		assert(mExpSP >= 1);
		auto &op = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(op.type == ExpType::Local);)

		codeRD(loc, type == AstTag_IncStmt ? Op_Inc : Op_Dec, op.index);
	}

	// [Temp src] => [Temp]
	void FuncBuilder::reflexOp(CompileLoc loc, AstTag type)
	{
		assert(mExpSP >= 2);

		auto &lhs = getExp(-2);
		auto &op = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(lhs.type == ExpType::Local);)
		DEBUG_EXPSTACKCHECK(assert(op.isSource());)

		codeRD(loc, AstTagToOpcode(type), lhs.index);
		codeRC(op);
		pop(1);
	}

	// [Temp operands*Temp] => [Temp]
	void FuncBuilder::concatEq(CompileLoc loc, uword operands)
	{
		assert(operands >= 1);
		assert(mExpSP >= operands + 1);

		auto &lhs = getExp(-operands - 1);
		auto ops = mExpStack.slice(mExpSP - operands, mExpSP);

		DEBUG_EXPSTACKCHECK(assert(lhs.type == ExpType::Local);)
		DEBUG_EXPSTACKCHECK(for(auto &op: ops) assert(op.type == ExpType::Temporary);)

		codeRD(loc, Op_CatEq, lhs.index);
		codeRC(ops[0]);
		codeUImm(operands);
		pop(operands);
	}

	// [n*any] => [n*any]
	// [n*any] => [n*any Conflict] (in this case the values on the stack may have been changed)
	void FuncBuilder::resolveAssignmentConflicts(CompileLoc loc, uword numVals)
	{
		uword numTemps = 0;

		for(uword i = (mExpSP - numVals) + 1; i < mExpSP; i++)
		{
			if(mExpStack[i].type != ExpType::Local)
				continue;

			auto index = mExpStack[i].index;
			uword reloc = cast(uword)-1;

			for(uword j = mExpSP - numVals; j < i; j++)
			{
				auto &e = mExpStack[j];

				if(e.index == index || e.index2 == index)
				{
					if(reloc == cast(uword)-1)
					{
						numTemps++;
						reloc = pushRegister();
						codeMove(loc, reloc, index);
					}

					if(e.index == index)
						e.index = reloc;

					if(e.index2 == index)
						e.index2 = reloc;
				}
			}
		}

		if(numTemps > 0)
			pushExp(ExpType::Conflict);
	}

	// [any] => [Local|Const]
	void FuncBuilder::toSource(CompileLoc loc)
	{
		Exp e = getExp(-1);

		if(e.type != ExpType::Const && e.type != ExpType::Local)
		{
			pop();

			switch(e.type)
			{
				case ExpType::NewLocal:
					assert(mFreeReg == e.index);
					pushRegister();
					pushExp(ExpType::Temporary, e.index);
					return;

				case ExpType::Call:
				case ExpType::Yield:
					assert(mFreeReg == getRD(e.index));
					// fall through
				default:
					auto reg = pushRegister();
					moveToReg(loc, reg, e);
					pushExp(ExpType::Temporary, reg);
					return;
			}
		}
	}

	// [any] => [Temp]
	void FuncBuilder::toTemporary(CompileLoc loc)
	{
		toSource(loc);
		Exp e = getExp(-1);

		if(e.type == ExpType::Const || e.index != mFreeReg)
		{
			pop();
			auto reg = pushRegister();
			moveToReg(loc, reg, e);
			pushExp(ExpType::Temporary, reg);
		}
	}

	// [src Temp*nbase] => [NeedsDest]
	void FuncBuilder::newClass(CompileLoc loc, uword numBases)
	{
		auto &name = getExp(-numBases - 1);

		DEBUG_EXPSTACKCHECK(assert(name.isSource());)
		DEBUG_EXPSTACKCHECK(for(int i = -numBases; i < 0; i++) assert(getExp(i).type == ExpType::Temporary);)

		auto i = codeRD(loc, Op_Class, 0);
		codeRC(name);

		if(numBases > 0)
			codeRC(getExp(-numBases));
		else
		{
			auto derp = Exp(ExpType::Local, 0);
			codeRC(derp);
		}

		codeUImm(numBases);
		pop(numBases + 1);
		pushExp(ExpType::NeedsDest, i);
	}

	// [Const src] => [NeedsDest]
	void FuncBuilder::newNamespace(CompileLoc loc)
	{
		auto &name = getExp(-2);
		auto &base = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(name.type == ExpType::Const);)
		DEBUG_EXPSTACKCHECK(assert(base.isSource());)

		auto i = codeRD(loc, Op_Namespace, 0);
		codeUImm(name.index);
		codeRC(base);
		pop(2);
		pushExp(ExpType::NeedsDest, i);
	}

	// [Const] => [NeedsDest]
	void FuncBuilder::newNamespaceNP(CompileLoc loc)
	{
		auto &name = getExp(-1);
		DEBUG_EXPSTACKCHECK(assert(name.type == ExpType::Const);)
		auto i = codeRD(loc, Op_NamespaceNP, 0);
		codeUImm(name.index);

		pop();
		pushExp(ExpType::NeedsDest, i);
	}

	// [src src] => [Field]
	void FuncBuilder::field()
	{
		Exp op = getExp(-2);
		Exp name = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(op.isSource());)
		DEBUG_EXPSTACKCHECK(assert(name.isSource());)

		pop(2);
		mFreeReg = name.regAfter;
		pushExp(ExpType::Field, packRegOrConst(op), packRegOrConst(name));
	}

	// [src src] => [Index]
	void FuncBuilder::index()
	{
		Exp op = getExp(-2);
		Exp idx = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(op.isSource());)
		DEBUG_EXPSTACKCHECK(assert(idx.isSource());)

		pop(2);
		mFreeReg = idx.regAfter;
		pushExp(ExpType::Index, packRegOrConst(op), packRegOrConst(idx));
	}

	// [src] => [VarargIndex]
	void FuncBuilder::varargIndex()
	{
		Exp idx = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(idx.isSource());)

		pop();
		mFreeReg = idx.regAfter;
		pushExp(ExpType::VarargIndex, packRegOrConst(idx));
	}

	// [Temp Temp] => [VarargSlice]
	void FuncBuilder::varargSlice(CompileLoc loc)
	{
		Exp lo = getExp(-2);
		Exp hi = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(lo.type == ExpType::Temporary);)
		DEBUG_EXPSTACKCHECK(assert(hi.type == ExpType::Temporary);)

		pop(2);
		mFreeReg = hi.regAfter;
		pushExp(ExpType::VarargSlice, codeRD(loc, Op_VargSlice, lo.index));
		codeUImm(0);
	}

	// [src] => [Length]
	void FuncBuilder::length()
	{
		Exp op = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(op.isSource());)

		pop();
		mFreeReg = op.regAfter;
		pushExp(ExpType::Length, packRegOrConst(op));
	}

	// [Temp Temp Temp] => [Slice]
	void FuncBuilder::slice()
	{
		Exp base = getExp(-3);
		Exp lo = getExp(-2);
		Exp hi = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(base.type == ExpType::Temporary);)
		DEBUG_EXPSTACKCHECK(assert(lo.type == ExpType::Temporary);)
		DEBUG_EXPSTACKCHECK(assert(hi.type == ExpType::Temporary);)
#ifdef NDEBUG
		(void)lo;
#endif
		pop(3);
		mFreeReg = hi.regAfter;
		pushExp(ExpType::Slice, base.index);
	}

	// [src src] => [NeedsDest]
	void FuncBuilder::binOp(CompileLoc loc, AstTag type)
	{
		assert(mExpSP >= 2);

		auto &op1 = getExp(-2);
		auto &op2 = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(op1.isSource());)
		DEBUG_EXPSTACKCHECK(assert(op2.isSource());)

		uword inst = codeRD(loc, AstTagToOpcode(type), 0);
		codeRC(op1);
		codeRC(op2);
		pop(2);
		pushExp(ExpType::NeedsDest, inst);
	}

	// [numOps*Temp] => [NeedsDest]
	void FuncBuilder::concat(CompileLoc loc, uword numOps)
	{
		assert(mExpSP >= numOps);
		assert(numOps >= 2);

		auto ops = mExpStack.slice(mExpSP - numOps, mExpSP);
		DEBUG_EXPSTACKCHECK(for(auto &op: ops) assert(op.type == ExpType::Temporary);)

		uword inst = codeRD(loc, Op_Cat, 0);
		codeRC(ops[0]);
		codeUImm(numOps);
		pop(numOps);
		pushExp(ExpType::NeedsDest, inst);
	}

	// [src] => [NeedsDest]
	void FuncBuilder::unOp(CompileLoc loc, AstTag type)
	{
		auto &src = getExp(-1);
		DEBUG_EXPSTACKCHECK(assert(src.isSource());)

		auto inst = codeRD(loc, AstTagToOpcode(type), 0);
		codeRC(src);
		pop();
		pushExp(ExpType::NeedsDest, inst);
	}

	MethodCallDesc FuncBuilder::beginMethodCall()
	{
		MethodCallDesc ret {};
		ret.baseReg = mFreeReg;
		ret.baseExp = mExpSP;
		return ret;
	}

	void FuncBuilder::updateMethodCall(MethodCallDesc& desc, uword num)
	{
		assert(mFreeReg <= desc.baseReg + num);
		assert(mExpSP == desc.baseExp + num);

		if(mFreeReg < desc.baseReg + num)
		{
			for(uword i = mFreeReg; i < desc.baseReg + num; i++)
				pushRegister();

			mExpStack[desc.baseExp + num - 1].regAfter = mFreeReg;
		}

		assert(mFreeReg == desc.baseReg + num);
	}

	// [src src args] => [Call]
	void FuncBuilder::pushMethodCall(CompileLoc loc, MethodCallDesc& desc)
	{
		// desc.baseExp holds obj, baseExp + 1 holds method name. assert they're both sources
		// everything after that is args. assert they're all in registers

		auto &obj = mExpStack[desc.baseExp];
		auto &name = mExpStack[desc.baseExp + 1];

		DEBUG_EXPSTACKCHECK(assert(obj.isSource());)
		DEBUG_EXPSTACKCHECK(assert(name.isSource());)

		auto args = mExpStack.slice(desc.baseExp + 2, mExpSP);
		auto numArgs = prepareArgList(args);
		numArgs = numArgs == 0 ? 0 : numArgs + 1;

		pop(args.length + 2);
		assert(mExpSP == desc.baseExp);
		assert(mFreeReg == desc.baseReg);

		auto inst = codeRD(loc, Op_Method, desc.baseReg);

		codeRC(obj);
		codeRC(name);
		codeUImm(numArgs);
		codeUImm(0);

		pushExp(ExpType::Call, inst);
	}

	// [Temp Temp args] => [Call]
	void FuncBuilder::pushCall(CompileLoc loc, uword numArgs)
	{
		assert(mExpSP >= numArgs + 2);

		Exp func = getExp(-numArgs - 2);
		Exp context = getExp(-numArgs - 1);

		DEBUG_EXPSTACKCHECK(assert(func.type == ExpType::Temporary);)
		DEBUG_EXPSTACKCHECK(assert(context.type == ExpType::Temporary);)
#ifdef NDEBUG
		(void)context;
#endif
		auto args = mExpStack.slice(mExpSP - numArgs, mExpSP);
		auto derp = prepareArgList(args);
		derp = derp == 0 ? 0 : derp + 1;
		pop(args.length + 2);

		auto inst = codeRD(loc, Op_Call, func.index);
		codeUImm(derp);
		codeUImm(0);
		pushExp(ExpType::Call, inst);
	}

	// [args] => [Yield]
	void FuncBuilder::pushYield(CompileLoc loc, uword numArgs)
	{
		assert(mExpSP >= numArgs);
		uword inst;

		if(numArgs == 0)
		{
			inst = codeRD(loc, Op_Yield, 0);
			codeUImm(1);
			codeUImm(0);
		}
		else
		{
			auto args = mExpStack.slice(mExpSP - numArgs, mExpSP);
			auto derp = prepareArgList(args);
			auto base = args[0].index;
			pop(args.length);

			inst = codeRD(loc, Op_Yield, base);
			codeUImm(derp);
			codeUImm(0);
		}

		pushExp(ExpType::Yield, inst);
	}

	// [Call] => [Call] (changes opcode of call instruction to tailcall variant)
	void FuncBuilder::makeTailcall()
	{
		auto &e = getExp(-1);

		DEBUG_EXPSTACKCHECK(assert(e.type == ExpType::Call);)

		switch(getOpcode(e.index))
		{
			case Op_Call: setOpcode(e.index, Op_TailCall); break;
			case Op_Method: setOpcode(e.index, Op_TailMethod); break;
			default: assert(false);
		}
	}

	// [NeedsDest]
	NamespaceDesc FuncBuilder::beginNamespace(CompileLoc loc)
	{
		NamespaceDesc ret(mNamespaceReg);
		auto &e = getExp(-1);
#ifdef NDEBUG
		(void)e;
#endif
		DEBUG_EXPSTACKCHECK(assert(e.type == ExpType::NeedsDest);)
		mNamespaceReg = checkRegOK(mFreeReg);
		toSource(loc);

		return ret;
	}

	void FuncBuilder::endNamespace(NamespaceDesc& desc)
	{
		mNamespaceReg = desc.prevReg;
	}

	// =================================================================================================================
	// Control flow

	uword FuncBuilder::here()
	{
		return mCode.length();
	}

	void FuncBuilder::patchJumpToHere(uword src)
	{
		patchJumpTo(src, here());
	}

	void FuncBuilder::patchContinuesTo(uword dest)
	{
		patchListTo(mScope->continues, dest);
		mScope->continues = INST_NO_JUMP;
	}

	void FuncBuilder::patchBreaksToHere()
	{
		patchListTo(mScope->breaks, here());
		mScope->breaks = INST_NO_JUMP;
	}

	void FuncBuilder::patchContinuesToHere()
	{
		patchContinuesTo(here());
	}

	void FuncBuilder::patchTrueToHere(InstRef& i)
	{
		patchListTo(i.trueList, here());
		i.trueList = INST_NO_JUMP;
	}

	void FuncBuilder::patchFalseToHere(InstRef& i)
	{
		patchListTo(i.falseList, here());
		i.falseList = INST_NO_JUMP;
	}

	void FuncBuilder::catToTrue(InstRef& i, uword j)
	{
		if(i.trueList == INST_NO_JUMP)
			i.trueList = j;
		else
		{
			auto idx = i.trueList;

			while(true)
			{
				auto next = getJumpOffset(idx);

				if(next == INST_NO_JUMP)
					break;
				else
					idx = next;
			}

			setJumpOffset(idx, j);
		}
	}

	void FuncBuilder::catToFalse(InstRef& i, uword j)
	{
		if(i.falseList == INST_NO_JUMP)
			i.falseList = j;
		else
		{
			auto idx = i.falseList;

			while(true)
			{
				auto next = getJumpOffset(idx);

				if(next == INST_NO_JUMP)
					break;
				else
					idx = next;
			}

			setJumpOffset(idx, j);
		}
	}

	void FuncBuilder::invertJump(InstRef& i)
	{
#ifndef NDEBUG
		assert(!i.inverted);
		i.inverted = true;
#endif
		auto j = i.trueList;
		assert(j != INST_NO_JUMP);
		i.trueList = getJumpOffset(j);
		setJumpOffset(j, i.falseList);
		i.falseList = j;

		if(getOpcode(j) == Op_Cmp)
		{
			switch(cast(Comparison)getRD(j))
			{
				case Comparison_LT: setRD(j, Comparison_GE); break;
				case Comparison_LE: setRD(j, Comparison_GT); break;
				case Comparison_GT: setRD(j, Comparison_LE); break;
				case Comparison_GE: setRD(j, Comparison_LT); break;
				default: assert(false);
			}
		}
		else
			setRD(j, !getRD(j));
	}

	void FuncBuilder::jumpTo(CompileLoc loc, uword dest)
	{
		auto j = codeRD(loc, Op_Jmp, true);
		codeImm(INST_NO_JUMP);
		setJumpOffset(j, jumpDiff(j, dest));
	}

	uword FuncBuilder::makeJump(CompileLoc loc)
	{
		auto ret = codeRD(loc, Op_Jmp, true);
		codeImm(INST_NO_JUMP);
		return ret;
	}

	uword FuncBuilder::codeCatch(CompileLoc loc, Scope& s)
	{
		pushScope(s);
		mScope->ehlevel++;
		mTryCatchDepth++;
		auto ret = codeRD(loc, Op_PushCatch, checkRegOK(mFreeReg));
		codeImm(INST_NO_JUMP);
		return ret;
	}

	uword FuncBuilder::popCatch(CompileLoc loc, CompileLoc catchLoc, uword catchBegin)
	{
		codeRD(loc, Op_PopEH, 0);
		auto ret = makeJump(loc);
		patchJumpToHere(catchBegin);
		popScope(catchLoc);
		mTryCatchDepth--;
		return ret;
	}

	uword FuncBuilder::codeFinally(CompileLoc loc, Scope& s)
	{
		pushScope(s);
		mScope->ehlevel++;
		mTryCatchDepth++;
		auto ret = codeRD(loc, Op_PushFinally, checkRegOK(mFreeReg));
		codeImm(INST_NO_JUMP);
		return ret;
	}

	void FuncBuilder::popFinally(CompileLoc loc, CompileLoc finallyLoc, uword finallyBegin)
	{
		codeRD(loc, Op_PopEH, 0);
		patchJumpToHere(finallyBegin);
		popScope(finallyLoc);
		mTryCatchDepth--;
	}

	bool FuncBuilder::inTryCatch()
	{
		return mTryCatchDepth > 0;
	}

	void FuncBuilder::codeContinue(CompileLoc loc, crocstr name)
	{
		bool anyUpvals = false;
		Scope* continueScope;

		if(name.length == 0)
		{
			if(mScope->continueScope == nullptr)
				c.semException(loc, "No continuable control structure");

			continueScope = mScope->continueScope;
			anyUpvals = continueScope->hasUpval;
		}
		else
		{
			for(continueScope = mScope; continueScope != nullptr; continueScope = continueScope->enclosing)
			{
				anyUpvals |= continueScope->hasUpval;

				if(continueScope->name == name)
					break;
			}

			if(continueScope == nullptr)
				c.semException(loc, "No continuable control structure of that name");

			if(continueScope->continueScope != continueScope)
				c.semException(loc, "Cannot continue control structure of that name");
		}

		if(anyUpvals)
			codeClose(loc, continueScope->regStart);

		auto diff = mScope->ehlevel - continueScope->ehlevel;

		if(diff > 0)
			codeRD(loc, Op_Unwind, diff);

		auto cont = continueScope->continues;
		continueScope->continues = codeRD(loc, Op_Jmp, true);
		codeImm(cont);
	}

	void FuncBuilder::codeBreak(CompileLoc loc, crocstr name)
	{
		bool anyUpvals = false;
		Scope* breakScope;

		if(name.length == 0)
		{
			if(mScope->breakScope == nullptr)
				c.semException(loc, "No breakable control structure");

			breakScope = mScope->breakScope;
			anyUpvals = breakScope->hasUpval;
		}
		else
		{
			for(breakScope = mScope; breakScope != nullptr; breakScope = breakScope->enclosing)
			{
				anyUpvals |= breakScope->hasUpval;

				if(breakScope->name == name)
					break;
			}

			if(breakScope == nullptr)
				c.semException(loc, "No breakable control structure of that name");

			if(breakScope->breakScope != breakScope)
				c.semException(loc, "Cannot break control structure of that name");
		}

		if(anyUpvals)
			codeClose(loc, breakScope->regStart);

		auto diff = mScope->ehlevel - breakScope->ehlevel;

		if(diff > 0)
			codeRD(loc, Op_Unwind, diff);

		auto br = breakScope->breaks;
		breakScope->breaks = codeRD(loc, Op_Jmp, true);
		codeImm(br);
	}

	void FuncBuilder::defaultReturn(CompileLoc loc)
	{
		saveRets(loc, 0);
		codeRet(loc);
	}

	void FuncBuilder::codeRet(CompileLoc loc)
	{
		codeRD(loc, Op_Ret, 0);
	}

	void FuncBuilder::codeUnwind(CompileLoc loc)
	{
		codeRD(loc, Op_Unwind, mTryCatchDepth);
	}

	void FuncBuilder::codeEndFinal(CompileLoc loc)
	{
		codeRD(loc, Op_EndFinal, 0);
	}

	// =================================================================================================================
	// Private
	// =================================================================================================================

	// =================================================================================================================
	// Exp handling

	Exp& FuncBuilder::pushExp(ExpType type, uword index, uword index2)
	{
		if(mExpSP >= mExpStack.length)
		{
			if(mExpStack.length == 0)
				mExpStack.resize(c.mem(), 10);
			else
				mExpStack.resize(c.mem(), mExpStack.length * 2);
		}

		auto ret = &mExpStack[mExpSP++];
		ret->type = type;
		ret->index = index;
		ret->index2 = index2;
		ret->regAfter = mFreeReg;
		return *ret;
	}

	Exp& FuncBuilder::getExp(int idx)
	{
		assert(idx < 0);
		assert(mExpSP >= cast(uword)-idx);
		return mExpStack[mExpSP + idx];
	}

	uword FuncBuilder::packRegOrConst(Exp& e)
	{
		if(e.type == ExpType::Local)
			return e.index;
		else
			return e.index + INST_MAX_REGISTER + 1;
	}

	Exp FuncBuilder::unpackRegOrConst(uword idx)
	{
		if(idx > INST_MAX_REGISTER)
			return Exp(ExpType::Const, idx - INST_MAX_REGISTER - 1);
		else
			return Exp(ExpType::Local, idx);
	}

	// =================================================================================================================
	// Register manipulation

	uword FuncBuilder::pushRegister()
	{
		checkRegOK(mFreeReg);

		DEBUG_REGPUSHPOP(printf("push %u\n", mFreeReg);)
		mFreeReg++;

		if(mFreeReg > mStackSize)
			mStackSize = mFreeReg;

		return mFreeReg - 1;
	}

	uword FuncBuilder::checkRegOK(uword reg)
	{
		if(reg > INST_MAX_REGISTER)
			c.semException(mLocation, "Too many registers");

		return reg;
	}

	// =================================================================================================================
	// Internal local stuff

	uword FuncBuilder::insertDummyLocal(CompileLoc loc, const char* fmt)
	{
		croc_pushFormat(*t, fmt, mDummyNameCounter++);
		auto str = c.newString(croc_getString(*t, -1));
		croc_popTop(*t);
		return insertLocal(new(c) Identifier(loc, str));
	}

	int FuncBuilder::searchLocal(crocstr name, uword& reg)
	{
		for(uword i = mLocVars.length() - 1; cast(word)i >= 0; i--)
		{
			if(mLocVars[i].isActive && mLocVars[i].name == name)
			{
				reg = mLocVars[i].reg;
				return i;
			}
		}

		return -1;
	}

	void FuncBuilder::deactivateLocals(uword varStart, uword regTo)
	{
		for(uword i = mLocVars.length() - 1; cast(word)i >= cast(word)varStart; i--)
		{
			if(mLocVars[i].reg >= regTo && mLocVars[i].isActive)
			{
				DEBUG_VARACTIVATE(printf("deactivating %s %s(%u:%u) reg %u\n",
					mLocVars[i].name, mLocVars[i].location.file, mLocVars[i].location.line, mLocVars[i].location.col,
					mLocVars[i].reg);)

				mLocVars[i].isActive = false;
				mLocVars[i].pcEnd = here();
			}
		}
	}

	void FuncBuilder::codeClose(CompileLoc loc, uword reg)
	{
		codeRD(loc, Op_Close, reg);
	}

	// =================================================================================================================
	// Constants

	void FuncBuilder::pushConst(uword index)
	{
		pushExp(ExpType::Const, index);
	}

	uword FuncBuilder::addNullConst()
	{
		return addConst(Value::nullValue);
	}

	uword FuncBuilder::addBoolConst(bool b)
	{
		return addConst(Value::from(b));
	}

	uword FuncBuilder::addIntConst(crocint x)
	{
		return addConst(Value::from(x));
	}

	uword FuncBuilder::addFloatConst(crocfloat x)
	{
		return addConst(Value::from(x));
	}

	uword FuncBuilder::addStringConst(crocstr s)
	{
		return addConst(Value::from(String::create(t->vm, s)));
	}

	uword FuncBuilder::addConst(Value v)
	{
		uword i = 0;

		for(auto &con: mConstants)
		{
			if(con == v)
				return i;

			i++;
		}

		mConstants.add(v);

		if(mConstants.length() > INST_MAX_CONSTANT)
			c.semException(mLocation, "Too many constants");

		return mConstants.length() - 1;
	}

	// =================================================================================================================
	// Codegen helpers

	void FuncBuilder::setMultRetReturns(uword index, uword num)
	{
		switch(getOpcode(index))
		{
			case Op_Vararg:
			case Op_VargSlice:  setUImm(index + 1, num); break;

			case Op_Call:
			case Op_Yield:      setUImm(index + 2, num); break;

			case Op_Method:     setUImm(index + 4, num); break;

			case Op_TailCall:
			case Op_TailMethod: break; // these don't care about the number of returns at all

			default: assert(false);
		}
	}

	void FuncBuilder::setJumpOffset(uword i, int offs)
	{
		if(offs != INST_NO_JUMP && (offs < INST_MAX_JUMP_BACKWARD || offs > INST_MAX_JUMP_FORWARD))
			c.semException(mLocation, "Code is too big to perform jump, consider splitting function");

		switch(getOpcode(i))
		{
			case Op_For:
			case Op_ForLoop:
			case Op_Foreach:
			case Op_PushCatch:
			case Op_PushFinally:
			case Op_Jmp:           setImm(i + 1, offs); break;

			case Op_ForeachLoop:
			case Op_IsTrue:
			case Op_CheckObjParam: setImm(i + 2, offs); break;

			case Op_Cmp:
			case Op_SwitchCmp:
			case Op_Equals:
			case Op_Is:
			case Op_In:            setImm(i + 3, offs); break;

			default: assert(false);
		}
	}

	int FuncBuilder::getJumpOffset(uword i)
	{
		switch(getOpcode(i))
		{
			case Op_For:
			case Op_ForLoop:
			case Op_Foreach:
			case Op_PushCatch:
			case Op_PushFinally:
			case Op_Jmp:           return getImm(i + 1);

			case Op_ForeachLoop:
			case Op_IsTrue:
			case Op_CheckObjParam: return getImm(i + 2);

			case Op_Cmp:
			case Op_SwitchCmp:
			case Op_Equals:
			case Op_Is:
			case Op_In:            return getImm(i + 3);

			default: assert(false); return 0; // dummy
		}
	}

	int FuncBuilder::jumpDiff(uword srcIndex, uword dest)
	{
		switch(getOpcode(srcIndex))
		{
			case Op_For:
			case Op_ForLoop:
			case Op_Foreach:
			case Op_PushCatch:
			case Op_PushFinally:
			case Op_Jmp:
			case Op_Switch:        return dest - (srcIndex + 2);

			case Op_ForeachLoop:
			case Op_IsTrue:
			case Op_CheckObjParam: return dest - (srcIndex + 3);

			case Op_Cmp:
			case Op_SwitchCmp:
			case Op_Equals:
			case Op_Is:
			case Op_In:            return dest - (srcIndex + 4);

			default: assert(false); return 0; // dummy
		}
	}

	void FuncBuilder::patchJumpTo(uword src, uword dest)
	{
		setJumpOffset(src, jumpDiff(src, dest));
	}

	void FuncBuilder::patchListTo(word j, uword dest)
	{
		for(uword next; j != INST_NO_JUMP; j = next)
		{
			next = getJumpOffset(j);
			patchJumpTo(j, dest);
		}
	}

	uword FuncBuilder::prepareArgList(DArray<Exp> items)
	{
		if(items.length == 0)
			return 1;

		DEBUG_EXPSTACKCHECK(for(auto &i: items.slice(0, items.length - 1)) assert(i.type == ExpType::Temporary);)

		if(items[items.length - 1].isMultRet())
		{
			multRetToRegs(-1);
			return 0;
		}
		else
		{
			DEBUG_EXPSTACKCHECK(assert(items[items.length - 1].type == ExpType::Temporary);)
			return items.length + 1;
		}
	}

	bool FuncBuilder::prepareAssignment(uword numLhs, uword numRhs, DArray<Exp>& lhs, DArray<Exp>& rhs)
	{
#ifndef NDEBUG
		auto check = mExpSP - (numLhs + numRhs);

		if(mExpStack[mExpSP - numRhs - 1].type == ExpType::Conflict)
			check--;
#endif
		assert(numLhs >= numRhs);

		rhs = mExpStack.slice(mExpSP - numRhs, mExpSP);

// 		DEBUG_EXPSTACKCHECK(foreach(ref i; rhs[0 .. $ - 1]) assert(i.isSource(), (printExpStack(), "poop"));)

		if(rhs.length > 0 && rhs[rhs.length - 1].isMultRet())
		{
			multRetToRegs(numLhs - numRhs + 1);

			for(uword i = numRhs, idx = rhs[rhs.length - 1].index + 1; i < numLhs; i++, idx++)
				pushExp(ExpType::Local, checkRegOK(idx));
		}
		else
		{
// 			DEBUG_EXPSTACKCHECK(assert(rhs[$ - 1].isSource());)

			for(uword i = numRhs; i < numLhs; i++)
				pushNull();
		}

		// Could have changed size and/or pointer could have been invalidated
		rhs = mExpStack.slice(mExpSP - numLhs, mExpSP);

		bool ret;

		if(mExpStack[mExpSP - numLhs - 1].type == ExpType::Conflict)
		{
			lhs = mExpStack.slice(mExpSP - numLhs - 1 - numLhs, mExpSP - numLhs - 1);
			ret = true;
		}
		else
		{
			lhs = mExpStack.slice(mExpSP - numLhs - numLhs, mExpSP - numLhs);
			ret = false;
		}

#ifndef NDEBUG
		if(check != (mExpSP - (numLhs + numLhs) - (ret ? 1 : 0)))
		{
			printf("oh noes: %" CROC_SIZE_T_FORMAT " %" CROC_SIZE_T_FORMAT "\n", check, mExpSP - (numLhs + numLhs) - (ret ? 1 : 0));
			assert(false);
		}
#endif
		DEBUG_EXPSTACKCHECK(for(auto &i: lhs) assert(i.isDest());)
		return ret;
	}

	void FuncBuilder::multRetToRegs(int num)
	{
		auto &src = getExp(-1);

		switch(src.type)
		{
			case ExpType::Vararg:
			case ExpType::VarargSlice:
			case ExpType::Call:
			case ExpType::Yield:
				setMultRetReturns(src.index, num + 1);
				break;

			default:
				assert(false);
		}

		src.type = ExpType::Temporary;
		src.index = getRD(src.index);
	}

	void FuncBuilder::popMoveTo(CompileLoc loc, Exp& dest)
	{
		if(dest.type == ExpType::Local || dest.type == ExpType::NewLocal)
			moveToReg(loc, dest.index, getExp(-1));
		else
		{
			toSource(loc);

			switch(dest.type)
			{
				case ExpType::Upval:
					codeRD(loc, Op_SetUpval,  getExp(-1));
					codeUImm(dest.index);
					break;

				case ExpType::Global:
					codeRD(loc, Op_SetGlobal, getExp(-1));
					codeUImm(dest.index);
					break;

				case ExpType::NewGlobal:
					codeRD(loc, Op_NewGlobal, getExp(-1));
					codeUImm(dest.index);
					break;

				case ExpType::Slice:
					codeRD(loc, Op_SliceAssign, dest.index);
					codeRC(getExp(-1));
					break;

				case ExpType::Index: {
					auto d1 = unpackRegOrConst(dest.index);
					auto d2 = unpackRegOrConst(dest.index2);
					codeRD(loc, Op_IndexAssign, d1);
					codeRC(d2);
					codeRC(getExp(-1));
					break;
				}
				case ExpType::Field: {
					auto d1 = unpackRegOrConst(dest.index);
					auto d2 = unpackRegOrConst(dest.index2);
					codeRD(loc, Op_FieldAssign, d1);
					codeRC(d2);
					codeRC(getExp(-1));
					break;
				}
				case ExpType::VarargIndex: {
					codeRD(loc, Op_VargIndexAssign, 0);
					auto d = unpackRegOrConst(dest.index);
					codeRC(d);
					codeRC(getExp(-1));
					break;
				}
				case ExpType::Length: {
					auto d = unpackRegOrConst(dest.index);
					codeRD(loc, Op_LengthAssign, d);
					codeRC(getExp(-1));
					break;
				}
				default: assert(false);
			}
		}

		pop();
	}

	void FuncBuilder::moveToReg(CompileLoc loc, uword reg, Exp& src)
	{
		switch(src.type)
		{
			case ExpType::Const:
				codeRD(loc, Op_Move, reg);
				codeRC(src);
				break;

			case ExpType::Local:
			case ExpType::NewLocal:
				codeMove(loc, reg, src.index);
				break;

			case ExpType::Upval:
				codeRD(loc, Op_GetUpval, reg);
				codeUImm(src.index);
				break;

			case ExpType::Global:
				codeRD(loc, Op_GetGlobal, reg);
				codeUImm(src.index);
				break;

			case ExpType::Index: {
				codeRD(loc, Op_Index, reg);
				auto s1 = unpackRegOrConst(src.index);
				auto s2 = unpackRegOrConst(src.index2);
				codeRC(s1);
				codeRC(s2);
				break;
			}
			case ExpType::Field: {
				codeRD(loc, Op_Field, reg);
				auto s1 = unpackRegOrConst(src.index);
				auto s2 = unpackRegOrConst(src.index2);
				codeRC(s1);
				codeRC(s2);
				break;
			}
			case ExpType::Slice: {
				codeRD(loc, Op_Slice, reg);
				auto s = Exp(ExpType::Temporary, src.index);
				codeRC(s);
				break;
			}
			case ExpType::Vararg:
				setRD(src.index, reg);
				setMultRetReturns(src.index, 2);
				break;

			case ExpType::VarargIndex: {
				codeRD(loc, Op_VargIndex, reg);
				auto s = unpackRegOrConst(src.index);
				codeRC(s);
				break;
			}
			case ExpType::Length: {
				codeRD(loc, Op_Length, reg);
				auto s = unpackRegOrConst(src.index);
				codeRC(s);
				break;
			}
			case ExpType::VarargSlice:
			case ExpType::Call:
			case ExpType::Yield:
				setMultRetReturns(src.index, 2);
				codeMove(loc, reg, getRD(src.index));
				break;

			case ExpType::NeedsDest:
				setRD(src.index, reg);
				break;

			default: assert(false);
		}
	}

	void FuncBuilder::codeMove(CompileLoc loc, uword dest, uword src)
	{
		if(dest != src)
		{
			auto derp = Exp(ExpType::Local, src);
			codeRD(loc, Op_Move, dest);
			codeRC(derp);
		}
	}

	uword FuncBuilder::commonCmpJump(CompileLoc loc, Op opcode, uword rd)
	{
		auto &src1 = getExp(-2);
		auto &src2 = getExp(-1);
		DEBUG_EXPSTACKCHECK(assert(src1.isSource());)
		DEBUG_EXPSTACKCHECK(assert(src2.isSource());)

		auto ret = codeRD(loc, opcode, rd);
		codeRC(src1);
		codeRC(src2);
		codeImm(INST_NO_JUMP);

		pop(2);
		return ret;
	}

	// =================================================================================================================
	// Raw codegen funcs

	uword FuncBuilder::codeRD(CompileLoc loc, Op opcode, uword dest)
	{
		assert(opcode < Op_NUM_OPCODES);
		assert(dest <= INST_RD_MAX);

		DEBUG_WRITECODE(printf("(%u:%u)[%u] %s RD %u", loc.line, loc.col, mCode.length(), OpNames[opcode], dest);)

		Instruction i;
		i.uimm =
			(cast(uint16_t)(opcode << INST_OPCODE_SHIFT) & INST_OPCODE_MASK) |
			(cast(uint16_t)(dest << INST_RD_SHIFT) & INST_RD_MASK);

		return addInst(loc.line, i);
	}

	uword FuncBuilder::codeRD(CompileLoc loc, Op opcode, Exp& dest)
	{
		assert(opcode <= Op_NUM_OPCODES);
		assert(dest.isSource());

		if(dest.type == ExpType::Const)
		{
			codeRD(loc, Op_Move, checkRegOK(mFreeReg));
			codeUImm(dest.index | INST_CONSTBIT);
			return codeRD(loc, opcode, mFreeReg);
		}
		else
			return codeRD(loc, opcode, dest.index);
	}

	void FuncBuilder::codeImm(int imm)
	{
		assert(imm == INST_NO_JUMP || (imm >= -INST_IMM_MAX && imm <= INST_IMM_MAX));

		DEBUG_WRITECODE(printf(", IMM %d", imm);)

		Instruction i;
		i.imm = cast(int16_t)imm;
		addInst(i);
	}

	void FuncBuilder::codeUImm(uword uimm)
	{
		assert(uimm <= INST_UIMM_MAX);

		DEBUG_WRITECODE(printf(", UIMM %u", uimm);)

		Instruction i;
		i.uimm = cast(uint16_t)uimm;
		addInst(i);
	}

	void FuncBuilder::codeRC(Exp& src)
	{
		assert(src.isSource());
		Instruction i;

		if(src.type == ExpType::Local)
		{
			assert(src.index <= INST_MAX_REGISTER);
			DEBUG_WRITECODE(printf(", r%u", src.index);)
			i.uimm = cast(uint16_t)src.index;
		}
		else
		{
			assert(src.index <= INST_MAX_CONSTANT);
			DEBUG_WRITECODE(printf(", c%u", src.index);)
			i.uimm = cast(uint16_t)src.index | INST_CONSTBIT;
		}

		addInst(i);
	}

	uword FuncBuilder::addInst(uword line, Instruction i)
	{
		mLineInfo.add(line);
		mCode.add(i);
		return mCode.length() - 1;
	}

	void FuncBuilder::addInst(Instruction i)
	{
		assert(mLineInfo.length());
		addInst(mLineInfo.last(), i);
	}

	void FuncBuilder::setOpcode(uword index, uword opcode)
	{
		assert(opcode <= INST_OPCODE_MAX);
		mCode[index].uimm &= ~INST_OPCODE_MASK;
		mCode[index].uimm |= (opcode << INST_OPCODE_SHIFT) & INST_OPCODE_MASK;
	}

	void FuncBuilder::setRD(uword index, uword val)
	{
		assert(val <= INST_RD_MAX);
		mCode[index].uimm &= ~INST_RD_MASK;
		mCode[index].uimm |= (val << INST_RD_SHIFT) & INST_RD_MASK;
	}

	void FuncBuilder::setImm(uword index, int val)
	{
		assert(val == INST_NO_JUMP || (val >= -INST_IMM_MAX && val <= INST_IMM_MAX));
		mCode[index].imm = cast(int16_t)val;
	}

	void FuncBuilder::setUImm(uword index, uword val)
	{
		assert(val <= INST_UIMM_MAX);
		mCode[index].uimm = cast(uint16_t)val;
	}

	uword FuncBuilder::getOpcode(uword index)
	{
		return INST_GET_OPCODE(mCode[index]);
	}

	uword FuncBuilder::getRD(uword index)
	{
		return INST_GET_RD(mCode[index]);
	}

	int FuncBuilder::getImm(uword index)
	{
		return mCode[index].imm;
	}

	// =================================================================================================================
	// Conversion to function definition

	Funcdef* FuncBuilder::toFuncDef()
	{
		DEBUG_SHOWME({
			showMe();
			fflush(stdout);
		})

		auto ret = Funcdef::create(c.mem());
		push(t, Value::from(ret));

		ret->locFile = String::create(t->vm, mLocation.file);
		ret->locLine = mLocation.line;
		ret->locCol = mLocation.col;
		ret->isVararg = mIsVararg;
		ret->name = String::create(t->vm, mName);
		ret->numParams = mNumParams;
		ret->paramMasks = mParamMasks.toArrayView().dup(c.mem());

		ret->upvals.resize(c.mem(), mUpvals.length());

		uword i = 0;
		for(auto &uv: mUpvals)
		{
			ret->upvals[i].isUpval = uv.isUpvalue;
			ret->upvals[i].index = uv.index;
			i++;
		}

		ret->stackSize = mStackSize + 1;
		ret->innerFuncs = mInnerFuncs.toArrayView().dup(c.mem());

		if(ret->innerFuncs.length > 0)
			croc_insertAndPop(*t, -1 - ret->innerFuncs.length);

		ret->constants = mConstants.toArrayView().dup(c.mem());
		ret->code = mCode.toArrayView().dup(c.mem());
		ret->switchTables.resize(c.mem(), mSwitchTables.length());

		i = 0;
		for(auto &s: mSwitchTables)
		{
			ret->switchTables[i].offsets = s.offsets;
			ret->switchTables[i].defaultOffset = s.defaultOffset;
			i++;
		}

		mSwitchTables.reset();

		// Debug info
		ret->lineInfo = mLineInfo.toArrayView().dup(c.mem());
		ret->upvalNames.resize(c.mem(), mUpvals.length());

		i = 0;
		for(auto &u: mUpvals)
		{
			ret->upvalNames[i] = String::create(t->vm, u.name);
			i++;
		}

		mUpvals.reset();
		ret->locVarDescs.resize(c.mem(), mLocVars.length());

		i = 0;
		for(auto &var: mLocVars)
		{
			ret->locVarDescs[i].name = String::create(t->vm, var.name);
			ret->locVarDescs[i].pcStart = var.pcStart;
			ret->locVarDescs[i].pcEnd = var.pcEnd;
			ret->locVarDescs[i].reg = var.reg;
			i++;
		}

		mLocVars.reset();
		return ret;
	}

#ifdef SHOWME
	void FuncBuilder::showMe()
	{
		printf("Function at %s(%u:%u) (guessed name: %s)\n", mLocation.file, mLocation.line, mLocation.col, mName);
		printf("Num params: %u Vararg: %u Stack size: %u\n", mNumParams, mIsVararg, mStackSize);

		uword i = 0;
		for(auto m: mParamMasks)
			printf("\tParam %u mask: %x\n", i++, m);

		i = 0;
		for(auto s: mInnerFuncs)
			printf("\tInner Func %u: %s\n", i++, s->name->toCString());

		i = 0;
		for(auto &t: mSwitchTables)
		{
			printf("\tSwitch Table %u\n", i++);

			for(auto node: t.offsets)
			{
				push(t, node->key);
				croc_pushToString(*t, -1);
				printf("\t\t%s => %d\n", croc_getString(*t, -1), v);
				croc_pop(*t, 2);
			}

			printf("\t\tDefault: %d\n", t.defaultOffset);
		}

		for(auto &v: mLocVars)
			printf("\tLocal %s (at %s(%u:%u), reg %u, PC %u-%u)\n", v.name, v.location.file, v.location.line,
				v.location.col, v.reg, v.pcStart, v.pcEnd);

		i = 0;
		for(auto &u: mUpvals)
			printf("\tUpvalue %u: %s : %u (%s)\n", i++, u.name, u.index, u.isUpvalue ? "upval" : "local");

		i = 0;
		for(auto &c: mConstants)
		{
			switch(c.type)
			{
				case CrocType_Null:   printf("\tConst %u: nullptr\n", i); break;
				case CrocType_Bool:   printf("\tConst %u: %s\n", i, c.mBool ? "true" : "false"); break;
				case CrocType_Int:    printf("\tConst %u: %" CROC_INTEGER_FORMAT "\n", i, c.mInt); break;
				case CrocType_Float:  printf("\tConst %u: %ff\n", i, c.mFloat); break;
				case CrocType_String: printf("\tConst %u: \"%s\"\n", i, c.mString->toCString()); break;
				default: assert(false);
			}

			i++;
		}

		auto pc = mCode.ptr;
		auto end = pc + mCode.length();
		uword insOffset = 0;

		while(pc < end)
			disasm(pc, insOffset, lineInfo.toArrayView());
	}

	void disasm(Instruction*& pc, uword& insOffset, DArray<uint32_t> lineInfo)
	{
		auto nextIns = [&insOffset, &pc]()
		{
			insOffset++;
			return *pc++;
		};

		auto rd =    [](Instruction i) { printf(" r%u", INST_GET_RD(i)); };
		auto rdimm = [](Instruction i) { printf(" %u",  INST_GET_RD(i)); };

		auto rcNoComma = [&nextIns]()
		{
			auto i = nextIns();

			if(i.uimm & INST_CONSTBIT)
				printf(" c%u", i.uimm & ~INST_CONSTBIT);
			else
				printf(" r%u", i.uimm);
		};

		auto rc = [&rcNoComma]()
		{
			printf(",");
			rcNoComma();
		};

		auto imm =  [&nextIns]() { printf(", %d", nextIns().imm);  };
		auto uimm = [&nextIns]() { printf(", %u", nextIns().uimm); };

		printf("\t[%3u:%4u] ", insOffset, lineInfo[insOffset]);
		auto i = nextIns();

		switch(INST_GET_OPCODE(i))
		{
			// (__)
			case Op_PopEH:    printf("popeh"); goto _1;
			// case Op_PopEH2:  printf("popeh"); goto _1;
			case Op_EndFinal:    printf("endfinal"); goto _1;
			case Op_Ret:         printf("ret"); goto _1;
			case Op_CheckParams: printf("checkparams"); goto _1;
			_1: break;

			// (rd)
			case Op_Inc:          printf("inc"); goto _2;
			case Op_Dec:          printf("dec"); goto _2;
			case Op_VargLen:      printf("varglen"); goto _2;
			case Op_NewTable:     printf("newtab"); goto _2;
			case Op_Close:        printf("close"); goto _2;
			case Op_ObjParamFail: printf("objparamfail"); goto _2;
			case Op_AssertFail:   printf("assertfail"); goto _2;
			_2: rd(i); break;

			// (rdimm)
			case Op_Unwind: printf("unwind"); goto _3;
			_3: rdimm(i); break;

			// (rd, rs)
			case Op_Neg: printf("neg"); goto _4;
			case Op_Com: printf("com"); goto _4;
			case Op_Not: printf("not"); goto _4;
			case Op_AddEq:  printf("addeq"); goto _4;
			case Op_SubEq:  printf("subeq"); goto _4;
			case Op_MulEq:  printf("muleq"); goto _4;
			case Op_DivEq:  printf("diveq"); goto _4;
			case Op_ModEq:  printf("modeq"); goto _4;
			case Op_AndEq:  printf("andeq"); goto _4;
			case Op_OrEq:   printf("oreq"); goto _4;
			case Op_XorEq:  printf("xoreq"); goto _4;
			case Op_ShlEq:  printf("shleq"); goto _4;
			case Op_ShrEq:  printf("shreq"); goto _4;
			case Op_UShrEq: printf("ushreq"); goto _4;
			case Op_Move:            printf("mov"); goto _4;
			case Op_VargIndex:       printf("vargidx"); goto _4;
			case Op_Length:          printf("len"); goto _4;
			case Op_LengthAssign:    printf("lena"); goto _4;
			case Op_Append:          printf("append"); goto _4;
			case Op_SuperOf:         printf("superof"); goto _4;
			case Op_CustomParamFail: printf("customparamfail"); goto _4;
			case Op_Slice:           printf("slice"); goto _4;
			case Op_SliceAssign:     printf("slicea"); goto _4;
			_4: rd(i); rc(); break;

			// (rd, imm)
			case Op_For:         printf("for"); goto _5;
			case Op_ForLoop:     printf("forloop"); goto _5;
			case Op_Foreach:     printf("foreach"); goto _5;
			case Op_PushCatch:   printf("pushcatch"); goto _5;
			case Op_PushFinally: printf("pushfinal"); goto _5;
			_5: rd(i); imm(); break;

			// (rd, uimm)
			case Op_Vararg: printf("vararg"); goto _6a;
			case Op_SaveRets: printf("saverets"); goto _6a;
			case Op_VargSlice: printf("vargslice"); goto _6a;
			case Op_Closure: printf("closure"); goto _6a;
			case Op_ClosureWithEnv: printf("closurewenv"); goto _6a;
			case Op_GetUpval: printf("getu"); goto _6a;
			case Op_SetUpval: printf("setu"); goto _6a;
			_6a: rd(i); uimm(); break;

			case Op_NewGlobal: printf("newg"); goto _6b;
			case Op_GetGlobal: printf("getg"); goto _6b;
			case Op_SetGlobal: printf("setg"); goto _6b;
			case Op_NewArray: printf("newarr"); goto _6b;
			case Op_NamespaceNP: printf("namespacenp"); goto _6b;
			_6b: rd(i); printf(", c%u", nextIns().uimm); break;

			// (rdimm, rs)
			case Op_Throw: if(INST_GET_RD(i)) { printf("re"); } printf("throw"); rcNoComma(); break;
			case Op_Switch: printf("switch"); goto _7;
			_7: rdimm(i); rc(); break;

			// (rdimm, imm)
			case Op_Jmp: if(INST_GET_RD(i) == 0) { printf("nop"); } else { printf("jmp"); imm(); } break;

			// (rd, rs, rt)
			case Op_Add:  printf("add"); goto _8;
			case Op_Sub:  printf("sub"); goto _8;
			case Op_Mul:  printf("mul"); goto _8;
			case Op_Div:  printf("div"); goto _8;
			case Op_Mod:  printf("mod"); goto _8;
			case Op_Cmp3: printf("cmp3"); goto _8;
			case Op_And:  printf("and"); goto _8;
			case Op_Or:   printf("or"); goto _8;
			case Op_Xor:  printf("xor"); goto _8;
			case Op_Shl:  printf("shl"); goto _8;
			case Op_Shr:  printf("shr"); goto _8;
			case Op_UShr: printf("ushr"); goto _8;
			case Op_Index:       printf("idx"); goto _8;
			case Op_IndexAssign: printf("idxa"); goto _8;
			case Op_Field:       printf("field"); goto _8;
			case Op_FieldAssign: printf("fielda"); goto _8;
			_8: rd(i); rc(); rc(); break;

			// (__, rs, rt)
			case Op_VargIndexAssign: printf("vargidxa"); rcNoComma(); rc(); break;

			// (rd, rs, uimm)
			case Op_Cat:   printf("cat"); goto _9;
			case Op_CatEq: printf("cateq"); goto _9;
			_9: rd(i); rc(); uimm(); break;

			// (rd, rs, imm)
			case Op_CheckObjParam: printf("checkobjparam"); rd(i); rc(); imm(); break;

			// (rd, uimm, imm)
			case Op_ForeachLoop: printf("foreachloop"); rd(i); uimm(); imm(); break;

			// (rd, uimm, uimm)
			case Op_Call:     printf("call"); goto _10;
			case Op_TailCall: printf("tcall"); rd(i); uimm(); nextIns(); break;
			case Op_Yield:    printf("yield"); goto _10;
			case Op_SetArray: printf("setarray"); goto _10;
			_10: rd(i); uimm(); uimm(); break;

			// (rd, uimm, rt)
			case Op_Namespace: printf("namespace"); rd(i); printf(", c%u", nextIns().uimm); rc(); break;

			// (rdimm, rs, imm)
			case Op_IsTrue: if(INST_GET_RD(i)) { printf("istrue"); } else { printf("isfalse"); } rcNoComma(); imm(); break;

			// (rdimm, rs, rt, imm)
			case Op_Cmp:
				switch(cast(Comparison)INST_GET_RD(i))
				{
					case Comparison_LT: printf("jlt"); goto _11;
					case Comparison_LE: printf("jle"); goto _11;
					case Comparison_GT: printf("jgt"); goto _11;
					case Comparison_GE: printf("jge"); goto _11;
					default: assert(false);
				}

			case Op_Equals: if(INST_GET_RD(i)) { printf("je"); } else { printf("jne"); } goto _11;
			case Op_Is: if(INST_GET_RD(i)) { printf("jis"); } else { printf("jnis"); } goto _11;
			case Op_In: if(INST_GET_RD(i)) { printf("jin"); } else { printf("jnin"); } goto _11;
			_11: rcNoComma(); rc(); imm(); break;

			// (__, rs, rt, imm)
			case Op_SwitchCmp: printf("swcmp"); rcNoComma(); rc(); imm(); break;

			// (rd, rs, rt, uimm)
			case Op_AddMember: printf("addmember"); goto _12;
			case Op_Class:     printf("class"); goto _12;
			_12: rd(i); rc(); rc(); uimm(); break;

			// (rd, rs, rt, uimm, uimm)
			case Op_Method:     printf("method"); rd(i); rc(); rc(); uimm(); uimm(); break;
			case Op_TailMethod: printf("tmethod"); rd(i); rc(); rc(); uimm(); nextIns(); break;

			default: assert(false);
		}

		printf("\n");
	}
#endif
}