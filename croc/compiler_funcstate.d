/******************************************************************************
This module contains the codegen backend. Whereas croc.compiler_codegen holds
the AST visitor, this holds the "FuncState" class which is used to keep track
of a function definition as it's being built.

Theoretically this class could be swapped out for another, allowing multiple
codegen backends. Practically, some stuff would probably have to be abstracted
even more than it is already.

License:
Copyright (c) 2011 Jarrett Billingsley

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

module croc.compiler_funcstate;

import tango.io.Stdout;
debug import tango.text.convert.Format;

import croc.api_interpreter;
import croc.api_stack;
import croc.base_alloc;
import croc.base_hash;
import croc.base_opcodes;
import croc.compiler_ast;
import croc.compiler_types;
import croc.types;
import croc.types_funcdef;

// debug = REGPUSHPOP;
// debug = VARACTIVATE;
debug = SHOWME;
debug = EXPSTACKCHECK;
// debug = WRITECODE;

private Op AstTagToOpcode(AstTag tag)
{
	switch(tag)
	{
		case AstTag.AddAssignStmt: return Op.AddEq;
		case AstTag.SubAssignStmt: return Op.SubEq;
		case AstTag.MulAssignStmt: return Op.MulEq;
		case AstTag.DivAssignStmt: return Op.DivEq;
		case AstTag.ModAssignStmt: return Op.ModEq;

		case AstTag.AndAssignStmt: return Op.AndEq;
		case AstTag.OrAssignStmt: return Op.OrEq;
		case AstTag.XorAssignStmt: return Op.XorEq;
		case AstTag.ShlAssignStmt: return Op.ShlEq;
		case AstTag.ShrAssignStmt: return Op.ShrEq;
		case AstTag.UShrAssignStmt: return Op.UShrEq;

		case AstTag.CatExp: return Op.Cat;
		case AstTag.CatAssignStmt: return Op.CatEq;

		case AstTag.IncStmt: return Op.Inc;
		case AstTag.DecStmt: return Op.Dec;

		case AstTag.AddExp: return Op.Add;
		case AstTag.SubExp: return Op.Sub;
		case AstTag.MulExp: return Op.Mul;
		case AstTag.DivExp: return Op.Div;
		case AstTag.ModExp: return Op.Mod;

		case AstTag.AndExp: return Op.And;
		case AstTag.OrExp: return Op.Or;
		case AstTag.XorExp: return Op.Xor;
		case AstTag.ShlExp: return Op.Shl;
		case AstTag.ShrExp: return Op.Shr;
		case AstTag.UShrExp: return Op.UShr;

		case AstTag.AsExp: return Op.As;
		case AstTag.InExp: return Op.In;
		case AstTag.Cmp3Exp: return Op.Cmp3;

		case AstTag.NegExp: return Op.Neg;
		case AstTag.NotExp: return Op.Not;
		case AstTag.ComExp: return Op.Com;
		case AstTag.CoroutineExp: return Op.Coroutine;
		case AstTag.DotSuperExp: return Op.SuperOf;
		default: assert(false);
	}
}

enum ExpType
{
	Const,       // index = const: CTIdx
	Local,       // index = reg: RegIdx
	Temporary = Local,
	NewLocal,    // index = reg: RegIdx
	Upval,       // index = uv: UpvalIdx
	Global,      // index = name: CTIdx
	NewGlobal,   // index = name: CTIdx
	Index,       // index = op: RegOrCTIdx, index2 = idx: RegOrCTIdx
	Field,       // index = op: RegOrCTIdx, index2 = fieldName: RegOrCTIdx
	Slice,       // index = base: RegIdx
	Vararg,      // index = inst: InstIdx
	VarargIndex, // index = op: RegOrCTIdx
	VarargSlice, // index = inst: InstIdx
	Length,      // index = op: RegOrCTIdx
	Call,        // index = inst: InstIdx
	Yield,       // index = inst: InstIdx
	NeedsDest,   // index = inst: InstIdx
	Conflict,    // (no ops)
}

struct Exp
{
private:
	static const Exp _Empty = {type: ExpType.Local, index: 0, index2: 0, regAfter: 0};
	static const Exp* Empty = &_Empty;

	ExpType type;
	uint index, index2;
	uint regAfter; // Points to first free reg after this exp. When we pop exps, we set the freeReg pointer to the regAfter of the exp on the new stack top

	bool isMultRet()
	{
		 return type == ExpType.Call || type == ExpType.Yield || type == ExpType.Vararg || type == ExpType.VarargSlice;
	}

	bool isSource()
	{
		return type == ExpType.Local || type == ExpType.Const;
	}

	bool isDest()
	{
		return type == ExpType.Local || type == ExpType.NewLocal || type == ExpType.Upval || type == ExpType.Global || type == ExpType.NewGlobal
			|| type == ExpType.Index || type == ExpType.Field || type == ExpType.Slice || type == ExpType.VarargIndex || type == ExpType.Length;
	}

	bool hasSideEffects()
	{
		return type == ExpType.Index || type == ExpType.Field || type == ExpType.Slice || type == ExpType.VarargIndex || type == ExpType.VarargSlice
			|| type == ExpType.Length || type == ExpType.Call || type == ExpType.Yield;
	}

	debug private char[] toString()
	{
		static const char[][] typeNames =
		[
			ExpType.Const:       "Const",
			ExpType.Local:       "Local/Temp",
			ExpType.NewLocal:    "NewLocal",
			ExpType.Upval:       "Upval",
			ExpType.Global:      "Global",
			ExpType.NewGlobal:   "NewGlobal",
			ExpType.Index:       "Index",
			ExpType.Field:       "Field",
			ExpType.Slice:       "Slice",
			ExpType.Vararg:      "Vararg",
			ExpType.VarargIndex: "VarargIndex",
			ExpType.VarargSlice: "VarargSlice",
			ExpType.Length:      "Length",
			ExpType.Call:        "Call",
			ExpType.Yield:       "Yield",
			ExpType.NeedsDest:   "NeedsDest",
			ExpType.Conflict:    "Conflict",
		];

		return Format("{}: {}, {}, regAfter {}", typeNames[cast(uint)type], index, index2, regAfter);
	}
}

private const uint NoJump = Instruction.NoJump;

struct InstRef
{
	uint trueList = NoJump;
	uint falseList = NoJump;
private:
	debug bool inverted = false;
}

struct Scope
{
private:
	Scope* enclosing;
	Scope* breakScope;
	Scope* continueScope;
	uint breaks = NoJump;
	uint continues = NoJump;
	char[] name;
	uint varStart = 0;
	uint regStart = 0;
	uint firstFreeReg = 0;
	bool hasUpval = false;
	uword ehlevel = 0;
}

struct SwitchDesc
{
private:
	Hash!(CrocValue, int) offsets;
	int defaultOffset = -1;
	uint switchPC;
	SwitchDesc* prev;
}

struct ForDesc
{
private:
	uint baseReg;
	uint beginJump;
	uint beginLoop;
}

struct MethodCallDesc
{
private:
	uint baseReg;
	uint baseExp;
}

struct UpvalDesc
{
private:
	bool isUpvalue;
	uint index;
	char[] name;
}

struct LocVarDesc
{
private:
	char[] name;
	uint pcStart;
	uint pcEnd;
	uint reg;

	CompileLoc location;
	bool isActive;
}

final class FuncState
{
private:
	ICompiler c;
	CrocThread* t;
	FuncState mParent;
	Scope* mScope;
	uint mFreeReg = 0;
	Exp[] mExpStack;
	uword mExpSP = 0;
	uword mTryCatchDepth = 0;

	CompileLoc mLocation;
	bool mIsVararg;
	char[] mName;
	uint mNumParams;
	uint[] mParamMasks;

	UpvalDesc[] mUpvals;
	uint mStackSize;
	CrocFuncDef*[] mInnerFuncs;
	CrocValue[] mConstants;
	Instruction[] mCode;

	uint mNamespaceReg = 0;

	SwitchDesc* mSwitch;
	SwitchDesc[] mSwitchTables;
	uint[] mLineInfo;
	LocVarDesc[] mLocVars;

	uword mDummyNameCounter = 0;

	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

package:

	this(ICompiler c, CompileLoc location, char[] name, FuncState parent = null)
	{
		this.c = c;
		this.t = c.thread;

		mLocation = location;
		mName = name;
		mParent = parent;
	}

	~this()
	{
		t.vm.alloc.freeArray(mExpStack);
		t.vm.alloc.freeArray(mParamMasks);
		t.vm.alloc.freeArray(mUpvals);
		t.vm.alloc.freeArray(mInnerFuncs);
		t.vm.alloc.freeArray(mConstants);
		t.vm.alloc.freeArray(mCode);
		t.vm.alloc.freeArray(mLineInfo);
		t.vm.alloc.freeArray(mLocVars);

		for(auto s = mSwitch; s !is null; s = s.prev)
			s.offsets.clear(*c.alloc);

		foreach(ref s; mSwitchTables)
			s.offsets.clear(*c.alloc);

		t.vm.alloc.freeArray(mSwitchTables);
	}

	void setVararg(bool isVararg)
	{
		mIsVararg = isVararg;
	}

	bool isVararg()
	{
		return mIsVararg;
	}

	void setNumParams(uint numParams)
	{
		mNumParams = numParams;
	}

	FuncState parent()
	{
		return mParent;
	}

	// ---------------------------------------------------------------------------
	// Debugging

	debug void printExpStack()
	{
		Stdout.formatln("Expression Stack");
		Stdout.formatln("----------------");

		for(word i = mExpSP - 1; i >= 0; i--)
			Stdout.formatln("{}: {}", i, mExpStack[i].toString());

		Stdout.formatln("");
	}

	debug void checkExpStackEmpty()
	{
		assert(mExpSP == 0, (printExpStack(), "Exp stack is not empty"));
	}

	// ---------------------------------------------------------------------------
	// Scopes

	void pushScope(ref Scope s)
	{
		if(mScope)
		{
			s.enclosing = mScope;
			s.breakScope = mScope.breakScope;
			s.continueScope = mScope.continueScope;
			s.ehlevel = mScope.ehlevel;
		}
		else
		{
			// leave these all in here, have to initialize void-initialized scopes
			s.enclosing = null;
			s.breakScope = null;
			s.continueScope = null;
			s.ehlevel = 0;
		}

		s.breaks = NoJump;
		s.continues = NoJump;
		s.varStart = cast(uint)mLocVars.length;
		s.regStart = mFreeReg;
		s.firstFreeReg = mFreeReg;
		s.hasUpval = false;
		s.name = null;

		mScope = &s;
	}

	void popScope(ref CompileLoc loc)
	{
		assert(mScope !is null, "scope underflow");

		auto prev = mScope.enclosing;

		closeScopeUpvals(loc);
		deactivateLocals(mScope.varStart, mScope.regStart);
		mFreeReg = mScope.regStart;
		mScope = prev;
	}

	void setBreakable()
	{
		mScope.breakScope = mScope;
	}

	void setContinuable()
	{
		mScope.continueScope = mScope;
	}

	void setScopeName(char[] name)
	{
		mScope.name = name;
	}

	void closeScopeUpvals(ref CompileLoc loc)
	{
		if(mScope.hasUpval)
		{
			codeClose(loc, mScope.regStart);
			mScope.hasUpval = false;
		}
	}

	// ---------------------------------------------------------------------------
	// Locals

	void addParam(Identifier ident, uint typeMask)
	{
		insertLocal(ident);
		mParamMasks.append(c.alloc, typeMask);
	}

	uint insertLocal(Identifier ident)
	{
		uint dummy = void;
		auto index = searchLocal(ident.name, dummy);

		if(index != -1)
		{
			auto l = mLocVars[index].location;
			c.semException(ident.location, "Local '{}' conflicts with previous definition at {}({}:{})", ident.name, l.file, l.line, l.col);
		}

		t.vm.alloc.resizeArray(mLocVars, mLocVars.length + 1);

		with(mLocVars[$ - 1])
		{
			name = ident.name;
			location = ident.location;
			reg = pushRegister();
			isActive = false;
		}

		return mLocVars[$ - 1].reg;
	}

	void activateLocals(uint num)
	{
		for(word i = mLocVars.length - 1; i >= cast(word)(mLocVars.length - num); i--)
		{
			debug(VARACTIVATE)
			{
				auto l = mLocVars[i].location;
				Stdout.formatln("activating {} {}({}:{}) reg {}", mLocVars[i].name, l.file, l.line, l.col, mLocVars[i].reg);
			}

			mLocVars[i].isActive = true;
			mLocVars[i].pcStart = here();
		}

		mScope.firstFreeReg = mLocVars[mLocVars.length - 1].reg + 1;
	}

	// ---------------------------------------------------------------------------
	// Switches

	void beginSwitch(ref SwitchDesc s, ref CompileLoc loc)
	{
		auto cond = getExp(-1);
		assert(cond.isSource());
		s.switchPC = codeRD(loc, Op.Switch, 0);
		codeRC(cond);
		s.prev = mSwitch;
		mSwitch = &s;
		pop();
	}

	void endSwitch()
	{
		assert(mSwitch !is null, "endSwitch - no switch to end");

		auto prev = mSwitch.prev;

		if(mSwitch.offsets.length > 0 || mSwitch.defaultOffset == -1)
		{
			mSwitchTables.append(c.alloc, *mSwitch);
			auto switchIdx = mSwitchTables.length - 1;

			if(switchIdx > Instruction.MaxSwitchTable)
				c.semException(mLocation, "Too many switches");

			setRD(mSwitch.switchPC, switchIdx);
		}
		else
		{
			// Happens when all the cases are dynamic and there is a default -- no need to add a switch table then
			setOpcode(mSwitch.switchPC, Op.Jmp);
			setRD(mSwitch.switchPC, 1);
			setJumpOffset(mSwitch.switchPC, mSwitch.defaultOffset);
		}

		mSwitch = prev;
	}

	void addCase(ref CompileLoc loc, Expression v)
	{
		assert(mSwitch !is null);

		CrocValue val = void;

		if(v.isNull())
			val = CrocValue.nullValue;
		else if(v.isBool())
			val = v.asBool();
		else if(v.isInt())
			val = v.asInt();
		else if(v.isFloat())
			val = v.asFloat();
		else if(v.isChar())
			val = v.asChar();
		else if(v.isString())
			val = createString(t, v.asString()); // this is safe, since v's string value is already held by the compiler's string table
		else
			assert(false, "addCase invalid type: " ~ v.toString());

		if(mSwitch.offsets.lookup(val) !is null)
		{
			.pushString(t, "Duplicate case value '");
			.push(t, val);
			pushToString(t, -1);
			insertAndPop(t, -2);
			.pushChar(t, '\'');
			cat(t, 3);
			c.semException(loc, getString(t, -1));
		}

		*mSwitch.offsets.insert(*c.alloc, val) = jumpDiff(mSwitch.switchPC, here());
	}

	void addDefault(ref CompileLoc loc)
	{
		assert(mSwitch !is null);
		assert(mSwitch.defaultOffset == -1);

		mSwitch.defaultOffset = jumpDiff(mSwitch.switchPC, here());
	}

	// ---------------------------------------------------------------------------
	// Numeric for/foreach loops

	ForDesc beginFor(CompileLoc loc, void delegate() dg)
	{
		return beginForImpl(loc, dg, Op.For, 3);
	}

	ForDesc beginForeach(CompileLoc loc, void delegate() dg, uint containerSize)
	{
		return beginForImpl(loc, dg, Op.Foreach, containerSize);
	}

	ForDesc beginForImpl(CompileLoc loc, void delegate() dg, Op opcode, uint containerSize)
	{
		ForDesc ret;
		ret.baseReg = mFreeReg;
		pushNewLocals(3);
		dg();
		assign(loc, 3, containerSize);
		insertDummyLocal(loc, "__hidden{}");
		insertDummyLocal(loc, "__hidden{}");
		insertDummyLocal(loc, "__hidden{}");
		ret.beginJump = codeRD(loc, opcode, ret.baseReg); codeImm(NoJump);
		ret.beginLoop = here();
		return ret;
	}

	void endFor(CompileLoc loc, ForDesc desc)
	{
		endForImpl(loc, desc, Op.ForLoop, 0);
	}

	void endForeach(CompileLoc loc, ForDesc desc, uint indLength)
	{
		endForImpl(loc, desc, Op.ForeachLoop, indLength);
	}

	void endForImpl(CompileLoc loc, ForDesc desc, Op opcode, uint indLength)
	{
		closeScopeUpvals(loc);
		patchContinuesToHere();
		patchJumpToHere(desc.beginJump);

		uint j = codeRD(loc, opcode, desc.baseReg);

		if(opcode == Op.ForeachLoop)
			codeUImm(indLength);

		codeImm(NoJump);

		patchJumpTo(j, desc.beginLoop);
		patchBreaksToHere();
	}

	// ---------------------------------------------------------------------------
	// Basic expression stack manipulation

	void pop(uword num = 1)
	{
		assert(num != 0);
		assert(mExpSP >= num, "exp stack underflow");

		mExpSP -= num;

		if(mExpSP == 0)
			mFreeReg = mScope.firstFreeReg;
		else
			mFreeReg = mExpStack[mExpSP - 1].regAfter;
	}

	void dup()
	{
		assert(mExpSP > 0);
		pushExp(ExpType.init, 0);
		mExpStack[mExpSP - 1] = mExpStack[mExpSP - 2];
	}

	// ---------------------------------------------------------------------------
	// Expression stack pushes

	void pushNull()
	{
		pushConst(addNullConst());
	}

	void pushBool(bool value)
	{
		pushConst(addBoolConst(value));
	}

	void pushInt(crocint value)
	{
		pushConst(addIntConst(value));
	}

	void pushFloat(crocfloat value)
	{
		pushConst(addFloatConst(value));
	}

	void pushChar(dchar value)
	{
		pushConst(addCharConst(value));
	}

	void pushString(char[] value)
	{
		pushConst(addStringConst(value));
	}

	void pushNewGlobal(Identifier name)
	{
		pushExp(ExpType.NewGlobal, addStringConst(name.name));
	}

	void pushThis()
	{
		pushExp(ExpType.Local, 0);
	}

	void pushVar(Identifier name)
	{
		auto e = pushExp();

		ExpType varType = ExpType.Local;

		ExpType searchVar(FuncState s, bool isOriginal = true)
		{
			uint findUpval()
			{
				for(int i = 0; i < s.mUpvals.length; i++)
				{
					if(s.mUpvals[i].name == name.name)
					{
						if((s.mUpvals[i].isUpvalue && varType == ExpType.Upval) || (!s.mUpvals[i].isUpvalue && varType == ExpType.Local))
							return i;
					}
				}

				UpvalDesc ud = void;

				ud.name = name.name;
				ud.isUpvalue = (varType == ExpType.Upval);
				ud.index = e.index;

				s.mUpvals.append(c.alloc, ud);

				if(s.mUpvals.length > Instruction.MaxUpvalue)
					c.semException(s.mLocation, "Too many upvalues");

				return s.mUpvals.length - 1;
			}

			if(s is null)
			{
				e.index = addStringConst(name.name);
				varType = ExpType.Global;
				return ExpType.Global;
			}

			uint reg;
			auto index = s.searchLocal(name.name, reg);

			if(index == -1)
			{
				if(searchVar(s.mParent, false) == ExpType.Global)
					return ExpType.Global;

				e.index = findUpval();
				varType = ExpType.Upval;
				return ExpType.Upval;
			}
			else
			{
				e.index = reg;
				varType = ExpType.Local;

				if(!isOriginal)
				{
					for(auto sc = s.mScope; sc !is null; sc = sc.enclosing)
					{
						if(sc.regStart <= reg)
						{
							sc.hasUpval = true;
							break;
						}
					}
				}

				return ExpType.Local;
			}
		}

		e.type = searchVar(this);
	}

	void pushVararg(ref CompileLoc loc)
	{
		auto reg = pushRegister();
		pushExp(ExpType.Vararg, codeRD(loc, Op.Vararg, reg));
		codeUImm(0);
	}

	void pushVargLen(ref CompileLoc loc)
	{
		pushExp(ExpType.NeedsDest, codeRD(loc, Op.VargLen, 0));
	}

	void pushClosure(FuncState fs)
	{
		auto reg = pushRegister();
		pushExp(ExpType.Temporary, reg);
		codeClosure(fs, reg);
	}

	void pushTable(ref CompileLoc loc)
	{
		auto reg = pushRegister();
		pushExp(ExpType.Temporary, reg);
		codeRD(loc, Op.NewTable, reg);
	}

	void pushArray(ref CompileLoc loc, uword length)
	{
		auto reg = pushRegister();
		pushExp(ExpType.Temporary, reg);
		codeRD(loc, Op.NewArray, reg);
		codeUImm(addIntConst(length));
	}

	void pushNewLocals(uword num)
	{
		for(auto reg = mFreeReg; num; num--, reg++)
			pushExp(ExpType.NewLocal, checkRegOK(reg));
	}

	// ---------------------------------------------------------------------------
	// Expression stack pops

	void popToNothing()
	{
		if(mExpSP == 0)
			return;

		auto src = getExp(-1);

		if(src.type == ExpType.Call || src.type == ExpType.Yield)
			setMultRetReturns(src.index, 1);

		pop();
	}

	void assign(ref CompileLoc loc, uword numLhs, uword numRhs)
	{
		assert(mExpSP >= numRhs + 1);
		debug if(mExpStack[mExpSP - numRhs - 1].type == ExpType.Conflict) assert(mExpSP >= numLhs + numRhs + 1);

		Exp[] lhs, rhs;
		auto conflict = prepareAssignment(loc, numLhs, numRhs, lhs, rhs);
		assert(lhs.length == rhs.length);

		foreach_reverse(ref l; lhs)
			popMoveTo(loc, l); // pops top

		pop(lhs.length + (conflict ? 1 : 0));
	}

	void arraySet(ref CompileLoc loc, uword numItems, uword block)
	{
		debug(EXPSTACKCHECK) assert(numItems > 0);
		debug(EXPSTACKCHECK) assert(mExpSP >= numItems + 1);

		auto arr = &mExpStack[mExpSP - numItems - 1];
		auto items = mExpStack[mExpSP - numItems .. mExpSP];

		debug(EXPSTACKCHECK) assert(arr.type == ExpType.Temporary);

		auto arg = prepareArgList(loc, items);

		codeRD(loc, Op.SetArray, arr.index);
		codeUImm(arg);
		codeUImm(block);

		pop(numItems + 1); // all items and array
	}

	void arrayAppend(ref CompileLoc loc)
	{
		debug(EXPSTACKCHECK) assert(mExpSP >= 2);

		auto arr = getExp(-2);
		auto item = getExp(-1);

		debug(EXPSTACKCHECK) assert(arr.type == ExpType.Temporary);
		debug(EXPSTACKCHECK) assert(item.isSource());

		codeRD(loc, Op.Append, arr.index);
		codeRC(item);

		pop(2);
	}

	void customParamFail(ref CompileLoc loc, uint paramIdx)
	{
		auto msg = getExp(-1);
		debug(EXPSTACKCHECK) assert(msg.isSource());

		codeRD(loc, Op.CustomParamFail, paramIdx);
		codeRC(msg);

		pop();
	}

	void objParamFail(ref CompileLoc loc, uint paramIdx)
	{
		codeRD(loc, Op.ObjParamFail, paramIdx);
	}

	uint checkObjParam(ref CompileLoc loc, uint paramIdx)
	{
		auto type = getExp(-1);
		debug(EXPSTACKCHECK) assert(type.isSource());
		
		auto ret = codeRD(loc, Op.CheckObjParam, paramIdx);
		codeRC(type);
		codeImm(NoJump);

		pop();
		return ret;
	}

	uint codeIsTrue(ref CompileLoc loc, bool isTrue = true)
	{
		auto src = getExp(-1);
		debug(EXPSTACKCHECK) assert(src.isSource());

		auto ret = codeRD(loc, Op.IsTrue, isTrue);
		codeRC(src);
		codeImm(NoJump);

		pop();
		return ret;
	}

	uint codeCmp(ref CompileLoc loc, Comparison type)
	{
		return commonCmpJump(loc, Op.Cmp, type);
	}

	uint codeSwitchCmp(ref CompileLoc loc)
	{
		return commonCmpJump(loc, Op.SwitchCmp, 0);
	}

	uint codeEquals(ref CompileLoc loc, bool isTrue)
	{
		return commonCmpJump(loc, Op.Equals, isTrue);
	}

	uint codeIs(ref CompileLoc loc, bool isTrue)
	{
		return commonCmpJump(loc, Op.Is, isTrue);
	}

	void codeThrow(ref CompileLoc loc, bool rethrowing)
	{
		auto src = getExp(-1);
		debug(EXPSTACKCHECK) assert(src.isSource());
		
		codeRD(loc, Op.Throw, rethrowing ? 1 : 0);
		codeRC(src);

		pop();
	}

	void saveRets(ref CompileLoc loc, uint numRets)
	{
		if(numRets == 0)
		{
			codeRD(loc, Op.SaveRets, 0);
			codeUImm(1);
			return;
		}

		assert(mExpSP >= numRets);
		auto rets = mExpStack[mExpSP - numRets .. mExpSP];
		auto arg = prepareArgList(loc, rets);
		uint first = rets[0].index;
		codeRD(loc, Op.SaveRets, first);
		codeUImm(arg);
		pop(numRets);
	}

	// ---------------------------------------------------------------------------
	// Other codegen funcs

	void paramCheck(ref CompileLoc loc)
	{
		codeRD(loc, Op.CheckParams, 0);
	}

	void reflexOp(ref CompileLoc loc, AstTag type, uint operands)
	{
		assert(mExpSP >= operands + 1);

		auto opcode = AstTagToOpcode(type);
		auto lhs = getExp(-operands - 1);
		auto ops = mExpStack[mExpSP - operands .. mExpSP];

		debug(EXPSTACKCHECK) assert(lhs.type == ExpType.Local);

		codeRD(loc, opcode, lhs.index);

		if(operands == 0)
		{
			// inc, dec
		}
		else if(operands == 1)
		{
			// addeq, subeq, muleq, diveq, modeq, andeq, oreq, xoreq, shleq, shreq, ushreq
			debug(EXPSTACKCHECK) assert(ops[0].isSource());
			codeRC(&ops[0]);
		}
		else
		{
			// cateq
			debug(EXPSTACKCHECK) foreach(ref op; ops) assert(op.type == ExpType.Temporary);
			codeRC(&ops[0]);
			codeUImm(operands);
		}

		if(operands)
			pop(operands);
	}

	void resolveAssignmentConflicts(ref CompileLoc loc, uword numVals)
	{
		uint numTemps = 0;

		for(int i = (mExpSP - numVals) + 1; i < mExpSP; i++)
		{
			auto index = mExpStack[i].index;
			uint reloc = uint.max;

			for(int j = mExpSP - numVals; j < i; j++)
			{
				auto e = &mExpStack[j];

				if(e.index == index || e.index2 == index)
				{
					if(reloc == uint.max)
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
			pushExp(ExpType.Conflict);
	}

	void flushSideEffects(ref CompileLoc loc)
	{
		auto e = getExp(-1);

		if(e.hasSideEffects())
			toSource(loc);
	}

	void toSource(ref CompileLoc loc)
	{
		auto e = *getExp(-1);

		if(e.type == ExpType.Const || e.type == ExpType.Local)
			return;
		else
		{
			pop();

			switch(e.type)
			{
				case ExpType.NewLocal:
					assert(mFreeReg == e.index);
					pushRegister();
					pushExp(ExpType.Temporary, e.index);
					return;

				case ExpType.Call:
				case ExpType.Yield:
					assert(mFreeReg == getRD(e.index));
					// fall through
				default:
					auto reg = pushRegister();
					moveToReg(loc, reg, e);
					pushExp(ExpType.Temporary, reg);
					return;
			}
		}
	}

	void toTemporary(ref CompileLoc loc)
	{
		toSource(loc);
		auto e = *getExp(-1);

		if(e.type == ExpType.Const || e.index != mFreeReg)
		{
			pop();
			auto reg = pushRegister();
			moveToReg(loc, reg, e);
			pushExp(ExpType.Temporary, reg);
		}
	}

	void newClass(ref CompileLoc loc)
	{
		auto name = getExp(-2);
		auto base = getExp(-1);

		debug(EXPSTACKCHECK) assert(name.isSource());
		debug(EXPSTACKCHECK) assert(base.isSource());

		auto i = codeRD(loc, Op.Class, 0);
		codeRC(name);
		codeRC(base);
		pop(2);
		pushExp(ExpType.NeedsDest, i);
	}

	void newNamespace(ref CompileLoc loc)
	{
		auto name = getExp(-2);
		auto base = getExp(-1);

		debug(EXPSTACKCHECK) assert(name.type == ExpType.Const);
		debug(EXPSTACKCHECK) assert(base.isSource());

		auto i = codeRD(loc, Op.Namespace, 0);
		codeUImm(name.index);
		codeRC(base);
		pop(2);
		pushExp(ExpType.NeedsDest, i);
	}

	void newNamespaceNP(ref CompileLoc loc)
	{
		auto name = getExp(-1);
		debug(EXPSTACKCHECK) assert(name.type == ExpType.Const);
		auto i = codeRD(loc, Op.NamespaceNP, 0);
		codeUImm(name.index);

		pop();
		pushExp(ExpType.NeedsDest, i);
	}

	void field()
	{
		auto op = *getExp(-2);
		auto name = *getExp(-1);

		debug(EXPSTACKCHECK) assert(op.isSource());
		debug(EXPSTACKCHECK) assert(name.isSource());

		pop(2);
		mFreeReg = name.regAfter;
		pushExp(ExpType.Field, packRegOrConst(op), packRegOrConst(name));
	}

	void index()
	{
		auto op = *getExp(-2);
		auto idx = *getExp(-1);

		debug(EXPSTACKCHECK) assert(op.isSource());
		debug(EXPSTACKCHECK) assert(idx.isSource());

		pop(2);
		mFreeReg = idx.regAfter;
		pushExp(ExpType.Index, packRegOrConst(op), packRegOrConst(idx));
	}

	void varargIndex()
	{
		auto idx = *getExp(-1);

		debug(EXPSTACKCHECK) assert(idx.isSource());

		pop();
		mFreeReg = idx.regAfter;
		pushExp(ExpType.VarargIndex, packRegOrConst(idx));
	}

	void varargSlice(ref CompileLoc loc)
	{
		auto lo = *getExp(-2);
		auto hi = *getExp(-1);

		debug(EXPSTACKCHECK) assert(lo.type == ExpType.Temporary);
		debug(EXPSTACKCHECK) assert(hi.type == ExpType.Temporary);

		pop(2);
		mFreeReg = hi.regAfter;
		pushExp(ExpType.VarargSlice, codeRD(loc, Op.VargSlice, lo.index));
		codeUImm(0);
	}

	void length()
	{
		auto op = *getExp(-1);

		debug(EXPSTACKCHECK) assert(op.isSource());

		pop();
		mFreeReg = op.regAfter;
		pushExp(ExpType.Length, packRegOrConst(op));
	}

	void slice()
	{
		auto base = *getExp(-3);
		auto lo = *getExp(-2);
		auto hi = *getExp(-1);

		debug(EXPSTACKCHECK) assert(base.type == ExpType.Temporary);
		debug(EXPSTACKCHECK) assert(lo.type == ExpType.Temporary);
		debug(EXPSTACKCHECK) assert(hi.type == ExpType.Temporary);

		pop(3);
		mFreeReg = hi.regAfter;
		pushExp(ExpType.Slice, base.index);
	}

	void binOp(ref CompileLoc loc, AstTag type, uint numOps = 2)
	{
		assert(mExpSP >= numOps);
		assert(numOps >= 2);

		auto ops = mExpStack[mExpSP - numOps .. mExpSP];
		uint inst = codeRD(loc, AstTagToOpcode(type), 0);

		if(numOps > 2)
		{
			// cat
			debug(EXPSTACKCHECK) foreach(ref op; ops) assert(op.type == ExpType.Temporary);
			codeRC(&ops[0]);
			codeUImm(numOps);
		}
		else
		{
			// everything else
			debug(EXPSTACKCHECK) foreach(ref op; ops) assert(op.isSource());
			codeRC(&ops[0]);
			codeRC(&ops[1]);
		}

		pop(numOps);
		pushExp(ExpType.NeedsDest, inst);
	}

	void unOp(ref CompileLoc loc, AstTag type)
	{
		auto src = getExp(-1);
		debug(EXPSTACKCHECK) assert(src.isSource());

		auto inst = codeRD(loc, AstTagToOpcode(type), 0);
		codeRC(src);
		pop();
		pushExp(ExpType.NeedsDest, inst);
	}

	MethodCallDesc beginMethodCall()
	{
		MethodCallDesc ret;
		ret.baseReg = mFreeReg;
		ret.baseExp = mExpSP;
		return ret;
	}

	void updateMethodCall(ref MethodCallDesc desc, uint num)
	{
		assert(mFreeReg <= desc.baseReg + num);
		assert(mExpSP == desc.baseExp + num);

		if(mFreeReg < desc.baseReg + num)
		{
			for(int i = mFreeReg; i < desc.baseReg + num; i++)
				pushRegister();

			mExpStack[desc.baseExp + num - 1].regAfter = mFreeReg;
		}

		assert(mFreeReg == desc.baseReg + num);
	}

	void pushMethodCall(ref CompileLoc loc, bool isSuperCall, ref MethodCallDesc desc)
	{
		// desc.baseExp holds obj, baseExp + 1 holds method name. assert they're both sources
		// everything after that is args. assert they're all in registers

		auto obj = &mExpStack[desc.baseExp];
		auto name = &mExpStack[desc.baseExp + 1];

		debug(EXPSTACKCHECK) assert(obj.isSource());
		debug(EXPSTACKCHECK) assert(name.isSource());

		auto args = mExpStack[desc.baseExp + 2 .. mExpSP];
		auto numArgs = prepareArgList(loc, args);
		numArgs = numArgs == 0 ? 0 : numArgs + 1;

		pop(args.length + 2);
		assert(mExpSP == desc.baseExp);
		assert(mFreeReg == desc.baseReg);

		auto inst = codeRD(loc, isSuperCall ? Op.SuperMethod : Op.Method, desc.baseReg);

		if(!isSuperCall)
			codeRC(obj);

		codeRC(name);
		codeUImm(numArgs);
		codeUImm(0);

		pushExp(ExpType.Call, inst);
	}

	void pushCall(ref CompileLoc loc, uword numArgs)
	{
		assert(mExpSP >= numArgs + 2);

		auto func = *getExp(-numArgs - 2);
		auto context = *getExp(-numArgs - 1);

		debug(EXPSTACKCHECK) assert(func.type == ExpType.Temporary);
		debug(EXPSTACKCHECK) assert(context.type == ExpType.Temporary);

		auto args = mExpStack[mExpSP - numArgs .. mExpSP];
		auto derp = prepareArgList(loc, args);
		derp = derp == 0 ? 0 : derp + 1;
		pop(args.length + 2);
		
		auto inst = codeRD(loc, Op.Call, func.index);
		codeUImm(derp);
		codeUImm(0);
		pushExp(ExpType.Call, inst);
	}

	void pushYield(ref CompileLoc loc, uword numArgs)
	{
		assert(mExpSP >= numArgs);
		uint inst;

		if(numArgs == 0)
		{
			inst = codeRD(loc, Op.Yield, 0);
			codeUImm(1);
			codeUImm(0);
		}
		else
		{
			auto args = mExpStack[mExpSP - numArgs .. mExpSP];
			auto derp = prepareArgList(loc, args);
			auto base = args[0].index;
			pop(args.length);
			
			inst = codeRD(loc, Op.Yield, base);
			codeUImm(derp);
			codeUImm(0);
		}

		pushExp(ExpType.Yield, inst);
	}

	void makeTailcall()
	{
		auto e = getExp(-1);

		debug(EXPSTACKCHECK) assert(e.type == ExpType.Call);

		switch(getOpcode(e.index))
		{
			case Op.Call: setOpcode(e.index, Op.TailCall); break;
			case Op.Method: setOpcode(e.index, Op.TailMethod); break;
			case Op.SuperMethod: setOpcode(e.index, Op.TailSuperMethod); break;
			default: assert(false);
		}
	}

	void beginNamespace(ref CompileLoc loc)
	{
		assert(mNamespaceReg == 0);

		auto e = getExp(-1);

		debug(EXPSTACKCHECK) assert(e.type == ExpType.NeedsDest);
		mNamespaceReg = checkRegOK(mFreeReg);
		toSource(loc);
	}

	void endNamespace()
	{
		assert(mNamespaceReg != 0);
		mNamespaceReg = 0;
	}

	// ---------------------------------------------------------------------------
	// Control flow

	uint here()
	{
		return mCode.length;
	}

	private void patchJumpTo(uint src, uint dest)
	{
		setJumpOffset(src, jumpDiff(src, dest));
	}

	void patchJumpToHere(uint src)
	{
		patchJumpTo(src, here());
	}

	void patchListTo(uint j, uint dest)
	{
		for(uint next = void; j != NoJump; j = next)
		{
			next = getJumpOffset(j);
			patchJumpTo(j, dest);
		}
	}

	void patchContinuesTo(uint dest)
	{
		patchListTo(mScope.continues, dest);
		mScope.continues = NoJump;
	}

	void patchBreaksToHere()
	{
		patchListTo(mScope.breaks, here());
		mScope.breaks = NoJump;
	}

	void patchContinuesToHere()
	{
		patchContinuesTo(here());
	}

	void patchTrueToHere(ref InstRef i)
	{
		patchListTo(i.trueList, here());
		i.trueList = NoJump;
	}

	void patchFalseToHere(ref InstRef i)
	{
		patchListTo(i.falseList, here());
		i.falseList = NoJump;
	}

	void catToTrue(ref InstRef i, uint j)
	{
		if(i.trueList == NoJump)
			i.trueList = j;
		else
		{
			auto idx = i.trueList;

			while(true)
			{
				auto next = getJumpOffset(idx);

				if(next is NoJump)
					break;
				else
					idx = next;
			}

			setJumpOffset(idx, j);
		}
	}

	void catToFalse(ref InstRef i, uint j)
	{
		if(i.falseList == NoJump)
			i.falseList = j;
		else
		{
			auto idx = i.falseList;

			while(true)
			{
				auto next = getJumpOffset(idx);

				if(next is NoJump)
					break;
				else
					idx = next;
			}

			setJumpOffset(idx, j);
		}
	}

	void invertJump(ref InstRef i)
	{
		debug assert(!i.inverted);
		debug i.inverted = true;

		auto j = i.trueList;
		assert(j !is NoJump);
		i.trueList = getJumpOffset(j);
		setJumpOffset(j, i.falseList);
		i.falseList = j;

		if(getOpcode(j) == Op.Cmp)
		{
			switch(cast(Comparison)getRD(j))
			{
				case Comparison.LT: setRD(j, Comparison.GE); break;
				case Comparison.LE: setRD(j, Comparison.GT); break;
				case Comparison.GT: setRD(j, Comparison.LE); break;
				case Comparison.GE: setRD(j, Comparison.LT); break;
				default: assert(false);
			}
		}
		else
			setRD(j, !getRD(j));
	}

	void jumpTo(ref CompileLoc loc, uint dest)
	{
		auto j = codeRD(loc, Op.Jmp, true);
		codeImm(NoJump);
		setJumpOffset(j, jumpDiff(j, dest));
	}

	uint makeJump(ref CompileLoc loc)
	{
		auto ret = codeRD(loc, Op.Jmp, true);
		codeImm(NoJump);
		return ret;
	}

	uint codeCatch(ref CompileLoc loc, ref Scope s)
	{
		pushScope(s);
		mScope.ehlevel++;
		mTryCatchDepth++;
		auto ret = codeRD(loc, Op.PushCatch, checkRegOK(mFreeReg));
		codeImm(NoJump);
		return ret;
	}

	uint popCatch(ref CompileLoc loc, ref CompileLoc catchLoc, uint catchBegin)
	{
		codeRD(loc, Op.PopCatch, 0);
		auto ret = makeJump(loc);
		patchJumpToHere(catchBegin);
		popScope(catchLoc);
		mTryCatchDepth--;
		return ret;
	}

	uint codeFinally(ref CompileLoc loc, ref Scope s)
	{
		pushScope(s);
		mScope.ehlevel++;
		mTryCatchDepth++;
		auto ret = codeRD(loc, Op.PushFinally, checkRegOK(mFreeReg));
		codeImm(NoJump);
		return ret;
	}

	void popFinally(ref CompileLoc loc, ref CompileLoc finallyLoc, uint finallyBegin)
	{
		codeRD(loc, Op.PopFinally, 0);
		patchJumpToHere(finallyBegin);
		popScope(finallyLoc);
		mTryCatchDepth--;
	}

	bool inTryCatch()
	{
		return mTryCatchDepth > 0;
	}

	void codeContinue(ref CompileLoc loc, char[] name)
	{
		bool anyUpvals = false;
		Scope* continueScope = void;

		if(name.length == 0)
		{
			if(mScope.continueScope is null)
				c.semException(loc, "No continuable control structure");

			continueScope = mScope.continueScope;
			anyUpvals = continueScope.hasUpval;
		}
		else
		{
			for(continueScope = mScope; continueScope !is null; continueScope = continueScope.enclosing)
			{
				anyUpvals |= continueScope.hasUpval;

				if(continueScope.name == name)
					break;
			}

			if(continueScope is null)
				c.semException(loc, "No continuable control structure of that name");

			if(continueScope.continueScope !is continueScope)
				c.semException(loc, "Cannot continue control structure of that name");
		}

		if(anyUpvals)
			codeClose(loc, continueScope.regStart);

		auto diff = mScope.ehlevel - continueScope.ehlevel;

		if(diff > 0)
			codeRD(loc, Op.Unwind, diff);

		auto cont = continueScope.continues;
		continueScope.continues = codeRD(loc, Op.Jmp, true);
		codeImm(cont);
	}

	void codeBreak(ref CompileLoc loc, char[] name)
	{
		bool anyUpvals = false;
		Scope* breakScope = void;

		if(name.length == 0)
		{
			if(mScope.breakScope is null)
				c.semException(loc, "No breakable control structure");

			breakScope = mScope.breakScope;
			anyUpvals = breakScope.hasUpval;
		}
		else
		{
			for(breakScope = mScope; breakScope !is null; breakScope = breakScope.enclosing)
			{
				anyUpvals |= breakScope.hasUpval;

				if(breakScope.name == name)
					break;
			}

			if(breakScope is null)
				c.semException(loc, "No breakable control structure of that name");

			if(breakScope.breakScope !is breakScope)
				c.semException(loc, "Cannot break control structure of that name");
		}

		if(anyUpvals)
			codeClose(loc, breakScope.regStart);

		auto diff = mScope.ehlevel - breakScope.ehlevel;

		if(diff > 0)
			codeRD(loc, Op.Unwind, diff);

		auto br = breakScope.breaks;
		breakScope.breaks = codeRD(loc, Op.Jmp, true);
		codeImm(br);
	}

	void defaultReturn(ref CompileLoc loc)
	{
		saveRets(loc, 0);
		codeRet(loc);
	}

	void codeRet(ref CompileLoc loc)
	{
		codeRD(loc, Op.Ret, 0);
	}

	void codeUnwind(ref CompileLoc loc)
	{
		codeRD(loc, Op.Unwind, mTryCatchDepth);
	}

	void codeEndFinal(ref CompileLoc loc)
	{
		codeRD(loc, Op.EndFinal, 0);
	}

	// ================================================================================================================================================
	// Private
	// ================================================================================================================================================

private:

	// ---------------------------------------------------------------------------
	// Exp handling

	Exp* pushExp(ExpType type = ExpType.init, uint index = 0, uint index2 = 0)
	{
		if(mExpSP >= mExpStack.length)
		{
			if(mExpStack.length == 0)
				c.alloc.resizeArray(mExpStack, 10);
			else
				c.alloc.resizeArray(mExpStack, mExpStack.length * 2);
		}

		auto ret = &mExpStack[mExpSP++];
		ret.type = type;
		ret.index = index;
		ret.index2 = index2;
		ret.regAfter = mFreeReg;
		return ret;
	}

	Exp* getExp(int idx)
	{
		assert(idx < 0);
		assert(mExpSP >= -idx);
		return &mExpStack[mExpSP + idx];
	}

	uint packRegOrConst(ref Exp e)
	{
		if(e.type == ExpType.Local)
			return e.index;
		else
			return e.index + Instruction.MaxRegister + 1;
	}

	Exp unpackRegOrConst(uint idx)
	{
		if(idx > Instruction.MaxRegister)
			return Exp(ExpType.Const, idx - Instruction.MaxRegister - 1);
		else
			return Exp(ExpType.Local, idx);
	}

	// ---------------------------------------------------------------------------
	// Register manipulation

	uint pushRegister()
	{
		checkRegOK(mFreeReg);

		debug(REGPUSHPOP) Stdout.formatln("push {}", mFreeReg);
		mFreeReg++;

		if(mFreeReg > mStackSize)
			mStackSize = mFreeReg;

		return mFreeReg - 1;
	}

	uint checkRegOK(uint reg)
	{
		if(reg > Instruction.MaxRegister)
			c.semException(mLocation, "Too many registers");

		return reg;
	}

	// ---------------------------------------------------------------------------
	// Internal local stuff

	uint insertDummyLocal(CompileLoc loc, char[] fmt)
	{
		pushFormat(c.thread, fmt, mDummyNameCounter++);
		auto str = c.newString(getString(c.thread, -1));
		.pop(c.thread);
		return insertLocal(new(c) Identifier(c, loc, str));
	}

	int searchLocal(char[] name, out uint reg)
	{
		for(int i = mLocVars.length - 1; i >= 0; i--)
		{
			if(mLocVars[i].isActive && mLocVars[i].name == name)
			{
				reg = mLocVars[i].reg;
				return i;
			}
		}

		return -1;
	}

	void deactivateLocals(uint varStart, uint regTo)
	{
		for(word i = mLocVars.length - 1; i >= cast(word)varStart; i--)
		{
			if(mLocVars[i].reg >= regTo && mLocVars[i].isActive)
			{
				debug(VARACTIVATE) Stdout.formatln("deactivating {} {} reg {}", mLocVars[i].name, mLocVars[i].location.toString(), mLocVars[i].reg);
				mLocVars[i].isActive = false;
				mLocVars[i].pcEnd = here();
			}
		}
	}

	void codeClose(ref CompileLoc loc, uint reg)
	{
		codeRD(loc, Op.Close, reg);
	}

	// ---------------------------------------------------------------------------
	// Constants

	void pushConst(uint index)
	{
		pushExp(ExpType.Const, index);
	}

	uint addNullConst()
	{
		return addConst(CrocValue.nullValue);
	}

	uint addBoolConst(bool b)
	{
		return addConst(CrocValue(b));
	}

	uint addIntConst(crocint x)
	{
		return addConst(CrocValue(x));
	}

	uint addFloatConst(crocfloat x)
	{
		return addConst(CrocValue(x));
	}

	uint addCharConst(dchar x)
	{
		return addConst(CrocValue(x));
	}

	uint addStringConst(char[] s)
	{
		return addConst(CrocValue(createString(t, s)));
	}

	uint addConst(CrocValue v)
	{
		foreach(i, ref con; mConstants)
			if(con == v)
				return i;

		mConstants.append(c.alloc, v);

		if(mConstants.length > Instruction.MaxConstant)
			c.semException(mLocation, "Too many constants");

		return mConstants.length - 1;
	}

	// ---------------------------------------------------------------------------
	// Codegen helpers

	void setMultRetReturns(uint index, uint num)
	{
		switch(getOpcode(index))
		{
			case Op.Vararg, Op.VargSlice: setUImm(index + 1, num); break;
			case Op.Call, Op.Yield:       setUImm(index + 2, num); break;
			case Op.SuperMethod:          setUImm(index + 3, num); break;
			case Op.Method:               setUImm(index + 4, num); break;
			case Op.TailCall, Op.TailSuperMethod, Op.TailMethod: break; // these don't care about the number of returns at all
			default: assert(false);
		}
	}

	void setJumpOffset(uint i, int offs)
	{
		if(offs != NoJump && (offs < Instruction.MaxJumpBackward || offs > Instruction.MaxJumpForward))
			c.semException(mLocation, "Code is too big to perform jump, consider splitting function");

		switch(getOpcode(i))
		{
			case Op.For, Op.ForLoop, Op.Foreach, Op.PushCatch, Op.PushFinally, Op.Jmp: setImm(i + 1, offs); break;
			case Op.ForeachLoop, Op.IsTrue, Op.CheckObjParam:                          setImm(i + 2, offs); break;
			case Op.Cmp, Op.SwitchCmp, Op.Equals, Op.Is:                               setImm(i + 3, offs); break;
			default: assert(false);
		}
	}

	int getJumpOffset(uint i)
	{
		switch(getOpcode(i))
		{
			case Op.For, Op.ForLoop, Op.Foreach, Op.PushCatch, Op.PushFinally, Op.Jmp: return getImm(i + 1);
			case Op.ForeachLoop, Op.IsTrue, Op.CheckObjParam:                          return getImm(i + 2);
			case Op.Cmp, Op.SwitchCmp, Op.Equals, Op.Is:                               return getImm(i + 3);
			default: assert(false);
		}
	}

	int jumpDiff(uint srcIndex, uint dest)
	{
		switch(getOpcode(srcIndex))
		{
			case Op.For, Op.ForLoop, Op.Foreach, Op.PushCatch, Op.PushFinally, Op.Jmp, Op.Switch: return dest - (srcIndex + 2);
			case Op.ForeachLoop, Op.IsTrue, Op.CheckObjParam:                                     return dest - (srcIndex + 3);
			case Op.Cmp, Op.SwitchCmp, Op.Equals, Op.Is:                                          return dest - (srcIndex + 4);
			default: assert(false);
		}
	}

	uint prepareArgList(ref CompileLoc loc, Exp[] items)
	{
		if(items.length == 0)
			return 1;

		debug(EXPSTACKCHECK) foreach(ref i; items[0 .. $ - 1]) assert(i.type == ExpType.Temporary);

		if(items[$ - 1].isMultRet())
		{
			multRetToRegs(loc, -1);
			return 0;
		}
		else
		{
			debug(EXPSTACKCHECK) assert(items[$ - 1].type == ExpType.Temporary);
			return items.length + 1;
		}
	}

	bool prepareAssignment(ref CompileLoc loc, uint numLhs, uint numRhs, out Exp[] lhs, out Exp[] rhs)
	{
		debug { auto check = mExpSP - (numLhs + numRhs); if(mExpStack[mExpSP - numRhs - 1].type == ExpType.Conflict) check--; }
		assert(numLhs >= numRhs);

		rhs = mExpStack[mExpSP - numRhs .. mExpSP];

// 		debug(EXPSTACKCHECK) foreach(ref i; rhs[0 .. $ - 1]) assert(i.isSource(), (printExpStack(), "poop"));

		if(rhs.length > 0 && rhs[$ - 1].isMultRet())
		{
			multRetToRegs(loc, numLhs - numRhs + 1);

			for(uint i = numRhs, idx = rhs[$ - 1].index; i < numLhs; i++, idx++)
				pushExp(ExpType.Local, checkRegOK(idx));
		}
		else
		{
// 			debug(EXPSTACKCHECK) assert(rhs[$ - 1].isSource());

			for(uint i = numRhs; i < numLhs; i++)
				pushNull();
		}

		// Could have changed size and/or pointer could have been invalidated
		rhs = mExpStack[mExpSP - numLhs .. mExpSP];

		bool ret;

		if(mExpStack[mExpSP - numLhs - 1].type == ExpType.Conflict)
		{
			lhs = mExpStack[mExpSP - numLhs - 1 - numLhs .. mExpSP - numLhs - 1];
			ret = true;
		}
		else
		{
			lhs = mExpStack[mExpSP - numLhs - numLhs .. mExpSP - numLhs];
			ret = false;
		}

		assert(check == (mExpSP - (numLhs + numLhs) - (ret ? 1 : 0)), Format("oh noes: {} {}", check, mExpSP - (numLhs + numLhs) - (ret ? 1 : 0)));
		debug(EXPSTACKCHECK) foreach(ref i; lhs) assert(i.isDest());
		return ret;
	}

	void multRetToRegs(ref CompileLoc loc, int num)
	{
		auto src = getExp(-1);

		switch(src.type)
		{
			case ExpType.Vararg, ExpType.VarargSlice, ExpType.Call, ExpType.Yield:
				setMultRetReturns(src.index, num + 1);
				break;

			default:
				assert(false, (printExpStack(), "poop"));
		}

		src.type = ExpType.Temporary;
		src.index = getRD(src.index);
	}

	void popMoveTo(ref CompileLoc loc, ref Exp dest)
	{
		if(dest.type == ExpType.Local || dest.type == ExpType.NewLocal)
			moveToReg(loc, dest.index, *getExp(-1));
		else
		{
			toSource(loc);

			switch(dest.type)
			{
				case ExpType.Upval:       codeRD(loc, Op.SetUpval,  getExp(-1)); codeUImm(dest.index); break;
				case ExpType.Global:      codeRD(loc, Op.SetGlobal, getExp(-1)); codeUImm(dest.index); break;
				case ExpType.NewGlobal:   codeRD(loc, Op.NewGlobal, getExp(-1)); codeUImm(dest.index); break;
				case ExpType.Slice:       codeRD(loc, Op.SliceAssign, dest.index); codeRC(getExp(-1)); break;
				case ExpType.Index:       codeRD(loc, Op.IndexAssign, &unpackRegOrConst(dest.index)); codeRC(&unpackRegOrConst(dest.index2)); codeRC(getExp(-1)); break;
				case ExpType.Field:       codeRD(loc, Op.FieldAssign, &unpackRegOrConst(dest.index)); codeRC(&unpackRegOrConst(dest.index2)); codeRC(getExp(-1)); break;
				case ExpType.VarargIndex: codeRD(loc, Op.VargIndexAssign, 0); codeRC(&unpackRegOrConst(dest.index)); codeRC(getExp(-1)); break;
				case ExpType.Length:      codeRD(loc, Op.LengthAssign, &unpackRegOrConst(dest.index)); codeRC(getExp(-1)); break;
				default: assert(false);
			}
		}

		pop();
	}

	void moveToReg(ref CompileLoc loc, uint reg, ref Exp src)
	{
		switch(src.type)
		{
			case ExpType.Const:
			case ExpType.Local:
			case ExpType.NewLocal:    codeRD(loc, Op.Move, reg); codeRC(&src); break;
			case ExpType.Upval:       codeRD(loc, Op.GetUpval, reg); codeUImm(src.index);
			case ExpType.Global:      codeRD(loc, Op.GetGlobal, reg); codeUImm(src.index); break;
			case ExpType.Index:       codeRD(loc, Op.Index, reg); codeRC(&unpackRegOrConst(src.index)); codeRC(&unpackRegOrConst(src.index2)); break;
			case ExpType.Field:       codeRD(loc, Op.Field, reg); codeRC(&unpackRegOrConst(src.index)); codeRC(&unpackRegOrConst(src.index2)); break;
			case ExpType.Slice:       codeRD(loc, Op.Slice, reg); codeRC(&src); break;
			case ExpType.Vararg:      setRD(src.index, reg); setMultRetReturns(src.index, 2);break;
			case ExpType.VarargIndex: codeRD(loc, Op.VargIndex, reg); codeRC(&unpackRegOrConst(src.index)); break;
			case ExpType.Length:      codeRD(loc, Op.Length, reg); codeRC(&unpackRegOrConst(src.index)); break;
			case ExpType.VarargSlice:
			case ExpType.Call:
			case ExpType.Yield:       setMultRetReturns(src.index, 2); codeMove(loc, reg, getRD(src.index)); break;
			case ExpType.NeedsDest:   setRD(src.index, reg); break;
			default: assert(false);
		}
	}
	
	void codeClosure(FuncState fs, uint destReg)
	{
		t.vm.alloc.resizeArray(mInnerFuncs, mInnerFuncs.length + 1);

		if(mInnerFuncs.length > Instruction.MaxInnerFunc)
			c.semException(mLocation, "Too many inner functions");

		auto loc = fs.mLocation;

		if(mNamespaceReg > 0)
			codeMove(loc, destReg, mNamespaceReg);

		codeRD(loc, mNamespaceReg > 0 ? Op.ClosureWithEnv : Op.Closure, destReg);
		codeUImm(mInnerFuncs.length - 1);
		mInnerFuncs[$ - 1] = fs.toFuncDef();
	}

	void codeMove(ref CompileLoc loc, uint dest, uint src)
	{
		if(dest != src)
		{
			codeRD(loc, Op.Move, dest);
			codeRC(&Exp(ExpType.Local, src));
		}
	}

	uint commonCmpJump(ref CompileLoc loc, Op opcode, uint rd)
	{
		auto src1 = getExp(-2);
		auto src2 = getExp(-1);
		debug(EXPSTACKCHECK) assert(src1.isSource());
		debug(EXPSTACKCHECK) assert(src2.isSource());

		auto ret = codeRD(loc, opcode, rd);
		codeRC(src1);
		codeRC(src2);
		codeImm(NoJump);

		pop(2);
		return ret;
	}

	// ---------------------------------------------------------------------------
	// Raw codegen funcs

	uint codeRD(ref CompileLoc loc, Op opcode, uint dest)
	{
		assert(opcode <= Op.max);
		assert(dest <= Instruction.rdMax);
		
		debug(WRITECODE) Stdout.newline.format("({}:{})[{}] {} RD {}", loc.line, loc.col, mCode.length, OpNames[opcode], dest);

		Instruction i = void;
		i.uimm =
			(cast(ushort)(opcode << Instruction.opcodeShift) & Instruction.opcodeMask) |
			(cast(ushort)(dest << Instruction.rdShift) & Instruction.rdMask);

		return addInst(loc.line, i);
	}

	uint codeRD(ref CompileLoc loc, Op opcode, Exp* dest)
	{
		assert(opcode <= Op.max);
		assert(dest.isSource());

		if(dest.type == ExpType.Const)
		{
			codeRD(loc, Op.Move, checkRegOK(mFreeReg));
			codeUImm(dest.index);
			return codeRD(loc, opcode, mFreeReg);
		}
		else
			return codeRD(loc, opcode, dest.index);
	}

	void codeImm(int imm)
	{
		assert(imm == Instruction.NoJump || (imm >= -Instruction.immMax && imm <= Instruction.immMax));

		debug(WRITECODE) Stdout.format(", IMM {}", imm);

		Instruction i = void;
		i.imm = cast(short)imm;
		addInst(i);
	}

	void codeUImm(uint uimm)
	{
		assert(uimm <= Instruction.uimmMax);

		debug(WRITECODE) Stdout.format(", UIMM {}", uimm);

		Instruction i = void;
		i.uimm = cast(ushort)uimm;
		addInst(i);
	}

	void codeRC(Exp* src)
	{
		assert(src.isSource());
		Instruction i = void;

		if(src.type == ExpType.Local)
		{
			assert(src.index <= Instruction.MaxRegister);
			debug(WRITECODE) Stdout.format(", r{}", src.index);
			i.uimm = cast(ushort)src.index;
		}
		else
		{
			assert(src.index <= Instruction.MaxConstant);
			debug(WRITECODE) Stdout.format(", c{}", src.index);
			i.uimm = cast(ushort)src.index | Instruction.constBit;
		}

		addInst(i);
	}

	uint addInst(uint line, Instruction i)
	{
		mLineInfo.append(c.alloc, line);
		mCode.append(c.alloc, i);
		return mCode.length - 1;
	}

	void addInst(Instruction i)
	{
		assert(mLineInfo.length);
		addInst(mLineInfo[$ - 1], i);
	}

	void setOpcode(uint index, uint opcode)
	{
		assert(opcode <= Instruction.opcodeMax);
		mCode[index].uimm &= ~Instruction.opcodeMask;
		mCode[index].uimm |= (opcode << Instruction.opcodeShift) & Instruction.opcodeMask;
	}

	void setRD(uint index, uint val)
	{
		assert(val <= Instruction.rdMax);
		mCode[index].uimm &= ~Instruction.rdMask;
		mCode[index].uimm |= (val << Instruction.rdShift) & Instruction.rdMask;
	}

	void setImm(uint index, int val)
	{
		assert(val == Instruction.NoJump || (val >= -Instruction.immMax && val <= Instruction.immMax));
		mCode[index].imm = cast(short)val;
	}

	void setUImm(uint index, uint val)
	{
		assert(val <= Instruction.uimmMax);
		mCode[index].uimm = cast(ushort)val;
	}

	uint getOpcode(uint index)
	{
		return mixin(Instruction.GetOpcode("mCode[index]"));
	}

	uint getRD(uint index)
	{
		return mixin(Instruction.GetRD("mCode[index]"));
	}

	int getImm(uint index)
	{
		return mCode[index].imm;
	}

	// ---------------------------------------------------------------------------
	// Conversion to function definition

	package CrocFuncDef* toFuncDef()
	{
		debug(SHOWME)
		{
			showMe();
			Stdout.flush;
		}

		auto ret = funcdef.create(*c.alloc);
		push(t, CrocValue(ret));

		ret.locFile = createString(t, mLocation.file);
		ret.locLine = mLocation.line;
		ret.locCol = mLocation.col;
		ret.isVararg = mIsVararg;
		ret.name = createString(t, mName);
		ret.numParams = mNumParams;
		ret.paramMasks = mParamMasks;
		mParamMasks = null;
		ret.numUpvals = mUpvals.length;

		c.alloc.resizeArray(ret.upvals, mUpvals.length);

		foreach(i, ref uv; mUpvals)
		{
			ret.upvals[i].isUpvalue = uv.isUpvalue;
			ret.upvals[i].index = uv.index;
		}

		ret.stackSize = mStackSize + 1;

		ret.innerFuncs = mInnerFuncs;
		mInnerFuncs = null;

		if(ret.innerFuncs.length > 0)
			insertAndPop(t, -1 - ret.innerFuncs.length);

		ret.constants = mConstants;
		mConstants = null;
		ret.code = mCode;
		mCode = null;

		c.alloc.resizeArray(ret.switchTables, mSwitchTables.length);

		foreach(i, ref s; mSwitchTables)
		{
			ret.switchTables[i].offsets = s.offsets;
			s.offsets = typeof(s.offsets).init;
			ret.switchTables[i].defaultOffset = s.defaultOffset;
		}

		// Debug info
		ret.lineInfo = mLineInfo;
		mLineInfo = null;

		c.alloc.resizeArray(ret.upvalNames, mUpvals.length);

		foreach(i, ref u; mUpvals)
			ret.upvalNames[i] = createString(t, u.name);

		c.alloc.resizeArray(ret.locVarDescs, mLocVars.length);

		foreach(i, ref var; mLocVars)
		{
			ret.locVarDescs[i].name = createString(t, var.name);
			ret.locVarDescs[i].pcStart = var.pcStart;
			ret.locVarDescs[i].pcEnd = var.pcEnd;
			ret.locVarDescs[i].reg = var.reg;
		}

		return ret;
	}

	debug(SHOWME) package void showMe()
	{
		Stdout.formatln("Function at {}({}:{}) (guessed name: {})", mLocation.file, mLocation.line, mLocation.col, mName);
		Stdout.formatln("Num params: {} Vararg: {} Stack size: {}", mNumParams, mIsVararg, mStackSize);

		foreach(i, m; mParamMasks)
			Stdout.formatln("\tParam {} mask: {:b}", i, m);

		foreach(i, s; mInnerFuncs)
			Stdout.formatln("\tInner Func {}: {}", i, s.name.toString());

		foreach(i, ref t; mSwitchTables)
		{
			Stdout.formatln("\tSwitch Table {}", i);

			foreach(k, v; t.offsets)
				Stdout.formatln("\t\t{} => {}", k.toString(), v);

			Stdout.formatln("\t\tDefault: {}", t.defaultOffset);
		}

		foreach(v; mLocVars)
			Stdout.formatln("\tLocal {} (at {}({}:{}), reg {}, PC {}-{})", v.name, v.location.file, v.location.line, v.location.col, v.reg, v.pcStart, v.pcEnd);

		foreach(i, u; mUpvals)
			Stdout.formatln("\tUpvalue {}: {} : {} ({})", i, u.name, u.index, u.isUpvalue ? "upval" : "local");

		foreach(i, c; mConstants)
		{
			switch(c.type)
			{
				case CrocValue.Type.Null:   Stdout.formatln("\tConst {}: null", i); break;
				case CrocValue.Type.Bool:   Stdout.formatln("\tConst {}: {}", i, c.mBool); break;
				case CrocValue.Type.Int:    Stdout.formatln("\tConst {}: {}", i, c.mInt); break;
				case CrocValue.Type.Float:  Stdout.formatln("\tConst {}: {:f6}f", i, c.mFloat); break;
				case CrocValue.Type.Char:   Stdout.formatln("\tConst {}: '{}'", i, c.mChar); break;
				case CrocValue.Type.String: Stdout.formatln("\tConst {}: \"{}\"", i, c.mString.toString()); break;
				default: assert(false);
			}
		}

		auto pc = mCode.ptr;
		auto end = pc + mCode.length;
		uword insOffset = 0;

		while(pc < end)
			disasm(pc, insOffset);
	}

	void disasm(ref Instruction* pc, ref uword insOffset)
	{
		Instruction nextIns()
		{
			insOffset++;
			return *pc++;
		}

		uint getOpcode(Instruction i) { return mixin(Instruction.GetOpcode("i")); }
		uint getRD(Instruction i) { return mixin(Instruction.GetRD("i")); }

		void rd(Instruction i)    { Stdout.format(" r{}", getRD(i)); }
		void rdimm(Instruction i) { Stdout.format(" {}",  getRD(i)); }

		void rc(bool comma = true)
		{
			if(comma)
				Stdout(",");

			auto i = nextIns();

			if(i.uimm & Instruction.constBit)
				Stdout.format(" c{}", i.uimm & ~Instruction.constBit);
			else
				Stdout.format(" r{}", i.uimm);
		}

		void imm()  { Stdout.format(", {}", nextIns().imm);  }
		void uimm() { Stdout.format(", {}", nextIns().uimm); }

		Stdout.format("\t[{,3}:{,4}] ", insOffset, mLineInfo[insOffset]);
		auto i = nextIns();

		switch(getOpcode(i))
		{
			// (__)
			case Op.PopCatch:    Stdout("popcatch"); goto _1;
			case Op.PopFinally:  Stdout("popfinal"); goto _1;
			case Op.EndFinal:    Stdout("endfinal"); goto _1;
			case Op.Ret:         Stdout("ret"); goto _1;
			case Op.CheckParams: Stdout("checkparams"); goto _1;
			_1: break;

			// (rd)
			case Op.Inc:          Stdout("inc"); goto _2;
			case Op.Dec:          Stdout("dec"); goto _2;
			case Op.VargLen:      Stdout("varglen"); goto _2;
			case Op.NewTable:     Stdout("newtab"); goto _2;
			case Op.Close:        Stdout("close"); goto _2;
			case Op.ObjParamFail: Stdout("objparamfail"); goto _2;
			_2: rd(i); break;

			// (rdimm)
			case Op.Unwind: Stdout("unwind"); goto _3;
			_3: rdimm(i); break;

			// (rd, rs)
			case Op.Neg: Stdout("neg"); goto _4;
			case Op.Com: Stdout("com"); goto _4;
			case Op.Not: Stdout("not"); goto _4;
			case Op.AddEq:  Stdout("addeq"); goto _4;
			case Op.SubEq:  Stdout("subeq"); goto _4;
			case Op.MulEq:  Stdout("muleq"); goto _4;
			case Op.DivEq:  Stdout("diveq"); goto _4;
			case Op.ModEq:  Stdout("modeq"); goto _4;
			case Op.AndEq:  Stdout("andeq"); goto _4;
			case Op.OrEq:   Stdout("oreq"); goto _4;
			case Op.XorEq:  Stdout("xoreq"); goto _4;
			case Op.ShlEq:  Stdout("shleq"); goto _4;
			case Op.ShrEq:  Stdout("shreq"); goto _4;
			case Op.UShrEq: Stdout("ushreq"); goto _4;
			case Op.Move:            Stdout("mov"); goto _4;
			case Op.VargIndex:       Stdout("vargidx"); goto _4;
			case Op.Length:          Stdout("len"); goto _4;
			case Op.LengthAssign:    Stdout("lena"); goto _4;
			case Op.Append:          Stdout("append"); goto _4;
			case Op.Coroutine:       Stdout("coroutine"); goto _4;
			case Op.SuperOf:         Stdout("superof"); goto _4;
			case Op.CustomParamFail: Stdout("customparamfail"); goto _4;
			case Op.Slice:           Stdout("slice"); goto _4;
			case Op.SliceAssign:     Stdout("slicea"); goto _4;
			_4: rd(i); rc(); break;

			// (rd, imm)
			case Op.For:         Stdout("for"); goto _5;
			case Op.ForLoop:     Stdout("forloop"); goto _5;
			case Op.Foreach:     Stdout("foreach"); goto _5;
			case Op.PushCatch:   Stdout("pushcatch"); goto _5;
			case Op.PushFinally: Stdout("pushfinal"); goto _5;
			_5: rd(i); imm(); break;

			// (rd, uimm)
			case Op.Vararg: Stdout("vararg"); goto _6a;
			case Op.SaveRets: Stdout("saverets"); goto _6a;
			case Op.VargSlice: Stdout("vargslice"); goto _6a;
			case Op.Closure: Stdout("closure"); goto _6a;
			case Op.ClosureWithEnv: Stdout("closurewenv"); goto _6a;
			case Op.GetUpval: Stdout("getu"); goto _6a;
			case Op.SetUpval: Stdout("setu"); goto _6a;
			_6a: rd(i); uimm(); break;

			case Op.NewGlobal: Stdout("newg"); goto _6b;
			case Op.GetGlobal: Stdout("getg"); goto _6b;
			case Op.SetGlobal: Stdout("setg"); goto _6b;
			case Op.NewArray: Stdout("newarr"); goto _6b;
			case Op.NamespaceNP: Stdout("namespacenp"); goto _6b;
			_6b: rd(i); Stdout.format(", c{}", nextIns().uimm); break;

			// (rdimm, rs)
			case Op.Throw: if(getRD(i)) { Stdout("re"); } Stdout("throw"); rc(false); break;
			case Op.Switch: Stdout("switch"); goto _7;
			_7: rdimm(i); rc(); break;

			// (rdimm, imm)
			case Op.Jmp: if(getRD(i) == 0) { Stdout("nop"); } else { Stdout("jmp"); imm(); } break;

			// (rd, rs, rt)
			case Op.Add:  Stdout("add"); goto _8;
			case Op.Sub:  Stdout("sub"); goto _8;
			case Op.Mul:  Stdout("mul"); goto _8;
			case Op.Div:  Stdout("div"); goto _8;
			case Op.Mod:  Stdout("mod"); goto _8;
			case Op.Cmp3: Stdout("cmp3"); goto _8;
			case Op.And:  Stdout("and"); goto _8;
			case Op.Or:   Stdout("or"); goto _8;
			case Op.Xor:  Stdout("xor"); goto _8;
			case Op.Shl:  Stdout("shl"); goto _8;
			case Op.Shr:  Stdout("shr"); goto _8;
			case Op.UShr: Stdout("ushr"); goto _8;
			case Op.Index:       Stdout("idx"); goto _8;
			case Op.IndexAssign: Stdout("idxa"); goto _8;
			case Op.In:          Stdout("in"); goto _8;
			case Op.Class:       Stdout("class"); goto _8;
			case Op.As:          Stdout("as"); goto _8;
			case Op.Field:       Stdout("field"); goto _8;
			case Op.FieldAssign: Stdout("fielda"); goto _8;
			_8: rd(i); rc(); rc(); break;

			// (__, rs, rt)
			case Op.VargIndexAssign: Stdout("vargidxa"); rc(false); rc(); break;

			// (rd, rs, uimm)
			case Op.Cat:   Stdout("cat"); goto _9;
			case Op.CatEq: Stdout("cateq"); goto _9;
			_9: rd(i); rc(); uimm(); break;

			// (rd, rs, imm)
			case Op.CheckObjParam: Stdout("checkobjparam"); rd(i); rc(); imm(); break;

			// (rd, uimm, imm)
			case Op.ForeachLoop: Stdout("foreachloop"); rd(i); uimm(); imm(); break;

			// (rd, uimm, uimm)
			case Op.Call:     Stdout("call"); goto _10;
			case Op.TailCall: Stdout("tcall"); rd(i); uimm(); nextIns(); break;
			case Op.Yield:    Stdout("yield"); goto _10;
			case Op.SetArray: Stdout("setarray"); goto _10;
			_10: rd(i); uimm(); uimm(); break;

			// (rd, uimm, rt)
			case Op.Namespace: Stdout("namespace"); rd(i); Stdout.format(", c{}", nextIns().uimm); rc(); break;

			// (rdimm, rs, imm)
			case Op.IsTrue: if(getRD(i)) { Stdout("istrue"); } else { Stdout("isfalse"); } rc(false); imm(); break;

			// (rdimm, rs, rt, imm)
			case Op.Cmp:
				switch(cast(Comparison)getRD(i))
				{
					case Comparison.LT: Stdout("jlt"); goto _11;
					case Comparison.LE: Stdout("jle"); goto _11;
					case Comparison.GT: Stdout("jgt"); goto _11;
					case Comparison.GE: Stdout("jge"); goto _11;
					default: assert(false);
				}

			case Op.Equals: if(getRD(i)) { Stdout("je"); } else { Stdout("jne"); } goto _11;
			case Op.Is: if(getRD(i)) { Stdout("jis"); } else { Stdout("jnis"); } goto _11;
			_11: rc(false); rc(); imm(); break;

			// (__, rs, rt, imm)
			case Op.SwitchCmp: Stdout("swcmp"); rc(false); rc(); imm(); break;

			// (rd, rt, uimm, uimm)
			case Op.SuperMethod:     Stdout("smethod"); rd(i); rc(); uimm(); uimm(); break;
			case Op.TailSuperMethod: Stdout("tsmethod"); rd(i); rc(); uimm(); nextIns(); break;

			// (rd, rs, rt, uimm, uimm)
			case Op.Method:     Stdout("method"); rd(i); rc(); rc(); uimm(); uimm(); break;
			case Op.TailMethod: Stdout("tmethod"); rd(i); rc(); rc(); uimm(); nextIns(); break;

			default: assert(false);
		}

		Stdout.newline;
	}
}