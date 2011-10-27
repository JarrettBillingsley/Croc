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

import croc.base_alloc;
import croc.base_hash;
import croc.base_opcodes;
import croc.compiler_ast;
import croc.compiler_types;
import croc.types;

// debug = REGPUSHPOP;
// debug = VARACTIVATE;
// debug = WRITECODE;
debug = SHOWME;

private Op1 AstTagToOpcode1(AstTag tag)
{
	switch(tag)
	{
		case AstTag.NegExp:
		case AstTag.NotExp:
		case AstTag.ComExp: return Op1.UnOp;

		case AstTag.AddExp:
		case AstTag.SubExp:
		case AstTag.MulExp:
		case AstTag.DivExp:
		case AstTag.ModExp:
		case AstTag.Cmp3Exp: return Op1.BinOp;

		case AstTag.AddAssignStmt:
		case AstTag.SubAssignStmt:
		case AstTag.MulAssignStmt:
		case AstTag.DivAssignStmt:
		case AstTag.ModAssignStmt: return Op1.ReflBinOp;

		case AstTag.AndExp:
		case AstTag.OrExp:
		case AstTag.XorExp:
		case AstTag.ShlExp:
		case AstTag.ShrExp:
		case AstTag.UShrExp: return Op1.BitOp;

		case AstTag.AndAssignStmt:
		case AstTag.OrAssignStmt:
		case AstTag.XorAssignStmt:
		case AstTag.ShlAssignStmt:
		case AstTag.ShrAssignStmt:
		case AstTag.UShrAssignStmt: return Op1.ReflBitOp;

		case AstTag.IncStmt:
		case AstTag.DecStmt: return Op1.CrementOp;

		case AstTag.LTExp:
		case AstTag.LEExp:
		case AstTag.GTExp:
		case AstTag.GEExp: return Op1.Cmp;

		case AstTag.EqualExp:
		case AstTag.NotEqualExp: return Op1.Equals;

		case AstTag.IsExp:
		case AstTag.NotIsExp: return Op1.Is;

		case AstTag.AsExp: return Op1.As;
		case AstTag.InExp: return Op1.In;
		case AstTag.CatExp: return Op1.Cat;
		case AstTag.CoroutineExp: return Op1.New;
		case AstTag.DotSuperExp: return Op1.SuperOf;

		case AstTag.CatAssignStmt: return Op1.CatEq;
		case AstTag.CondAssignStmt: return Op1.Move;
		default: assert(false);
	}
}

private Op2 AstTagToOpcode2(AstTag tag)
{
	switch(tag)
	{
		case AstTag.NegExp: return Op2.Neg;
		case AstTag.NotExp: return Op2.Not;
		case AstTag.ComExp: return Op2.Com;

		case AstTag.AddExp: return Op2.Add;
		case AstTag.SubExp: return Op2.Sub;
		case AstTag.MulExp: return Op2.Mul;
		case AstTag.DivExp: return Op2.Div;
		case AstTag.ModExp: return Op2.Mod;
		case AstTag.Cmp3Exp: return Op2.Cmp3;
		
		case AstTag.AddAssignStmt: return Op2.AddEq;
		case AstTag.SubAssignStmt: return Op2.SubEq;
		case AstTag.MulAssignStmt: return Op2.MulEq;
		case AstTag.DivAssignStmt: return Op2.DivEq;
		case AstTag.ModAssignStmt: return Op2.ModEq;

		case AstTag.AndExp: return Op2.And;
		case AstTag.OrExp: return Op2.Or;
		case AstTag.XorExp: return Op2.Xor;
		case AstTag.ShlExp: return Op2.Shl;
		case AstTag.ShrExp: return Op2.Shr;
		case AstTag.UShrExp: return Op2.UShr;

		case AstTag.AndAssignStmt: return Op2.AndEq;
		case AstTag.OrAssignStmt: return Op2.OrEq;
		case AstTag.XorAssignStmt: return Op2.XorEq;
		case AstTag.ShlAssignStmt: return Op2.ShlEq;
		case AstTag.ShrAssignStmt: return Op2.ShrEq;
		case AstTag.UShrAssignStmt: return Op2.UShrEq;

		case AstTag.IncStmt: return Op2.Inc;
		case AstTag.DecStmt: return Op2.Dec;

		case AstTag.CoroutineExp: return Op2.Coroutine;

		default: return cast(Op2)-1;
	}
}

const uint NoJump = Instruction.NoJump;

struct InstRef
{
	uint trueList = NoJump;
	uint falseList = NoJump;
	debug bool inverted = false;
}

enum ExpType
{
	Const,
	Local, // also functions as Temporary
	NewLocal,
	Upval,
	Global,
	NewGlobal,
	Index,
	Field,
	Slice,
	Vararg,
	VarargIndex,
	VarargSlice,
	Length,
	Call,
	Yield,
	NeedsDest,
	Source,
	SaveRets,
	Conflict,
}

struct Exp
{
	ExpType type;
	uint index, index2;
	uint regAfter; // Points to first free reg after this exp. When we pop exps, we set the freeReg pointer to the regAfter of the exp on the new stack top

	debug char[] toString()
	{
		static const char[][] typeNames =
		[
			ExpType.Const:       "Const",
			ExpType.Local:       "Local",
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
			ExpType.Source:      "Source",
			ExpType.SaveRets:    "SaveRets",
			ExpType.Conflict:    "Conflict",
		];

		return Format("{}: {}, {}, regAfter {}", typeNames[cast(uint)type], index, index2, regAfter);
	}
}

struct Scope
{
	package Scope* enclosing;
	package Scope* breakScope;
	package Scope* continueScope;
	package uint breaks = NoJump;
	package uint continues = NoJump;
	package char[] name;
	package ushort varStart = 0;
	package ushort regStart = 0;
	package bool hasUpval = false;
	package uword ehlevel = 0;
}

struct SwitchDesc
{
	package Hash!(CrocValue, int) offsets;
	package int defaultOffset = -1;
	package uint switchPC;
	package SwitchDesc* prev;
}

struct UpvalDesc
{
	package bool isUpvalue;
	package uint index;
	package char[] name;
}

struct LocVarDesc
{
	package char[] name;
	package uint pcStart;
	package uint pcEnd;
	package uint reg;

	package CompileLoc location;
	package bool isActive;
}

final class FuncState
{
	package ICompiler c;
	package CrocThread* t;
	package FuncState mParent;
	package Scope* mScope;
	package ushort mFreeReg = 0;
	package Exp[] mExpStack;
	package uword mExpSP = 0;
	package uword mTryCatchDepth = 0;

	package CompileLoc mLocation;
	package bool mIsVararg;
	package char[] mName;
	package uint mNumParams;
	package uint[] mParamMasks;

	package UpvalDesc[] mUpvals;
	package uint mStackSize;
	package CrocFuncDef*[] mInnerFuncs;
	package CrocValue[] mConstants;
	package Instruction[] mCode;

	package uint mNamespaceReg = 0;

	package SwitchDesc* mSwitch;
	package SwitchDesc[] mSwitchTables;
	package uint[] mLineInfo;
	package LocVarDesc[] mLocVars;

	package this(ICompiler c, CompileLoc location, char[] name, FuncState parent = null)
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

	// ---------------------------------------------------------------------------
	// Debugging

	debug package void printExpStack()
	{
		Stdout.formatln("Expression Stack");
		Stdout.formatln("----------------");

		for(int i = 0; i < mExpSP; i++)
			Stdout.formatln("{}: {}", i, mExpStack[i].toString());

		Stdout.formatln("");
	}

	debug public void checkExpStackEmpty()
	{
		assert(mExpSP == 0, "Exp stack is not empty");
	}

	// ---------------------------------------------------------------------------
	// Scopes

	package void pushScope(ref Scope s)
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
		s.varStart = cast(ushort)mLocVars.length;
		s.regStart = mFreeReg;
		s.hasUpval = false;
		s.name = null;

		mScope = &s;
	}

	package void popScope(uint line)
	{
		assert(mScope !is null, "scope underflow");

		auto prev = mScope.enclosing;

		closeScopeUpvals(line);

		deactivateLocals(mScope.varStart, mScope.regStart);
		assert(mFreeReg == mScope.regStart, "popScope - Unfreed registers");
		mScope = prev;
	}

	package void setBreakable()
	{
		mScope.breakScope = mScope;
	}

	package void setContinuable()
	{
		mScope.continueScope = mScope;
	}

	package void setScopeName(char[] name)
	{
		mScope.name = name;
	}

	package void closeScopeUpvals(uint line)
	{
		if(mScope.hasUpval)
		{
			codeClose(line,mScope.regStart);
			mScope.hasUpval = false;
		}
	}

	// ---------------------------------------------------------------------------
	// Locals

	package int searchLocal(char[] name, out uint reg)
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

	package uint insertLocal(Identifier ident)
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

	package void activateLocals(uint num)
	{
		for(word i = mLocVars.length - 1; i >= cast(word)(mLocVars.length - num); i--)
		{
			debug(VARACTIVATE)
			{
				auto l = mLocVars[i].location;
				Stdout.formatln("activating {} {}({}:{}) reg {}", mLocVars[i].name, l.file, l.line, l.col, mLocVars[i].reg);
			}

			mLocVars[i].isActive = true;
			mLocVars[i].pcStart = mCode.length;
		}
	}

	package void deactivateLocals(uint varStart, uint regTo)
	{
		for(word i = mLocVars.length - 1; i >= cast(word)varStart; i--)
		{
			if(mLocVars[i].reg >= regTo && mLocVars[i].isActive)
			{
				debug(VARACTIVATE) Stdout.formatln("deactivating {} {} reg {}", mLocVars[i].name, mLocVars[i].location.toString(), mLocVars[i].reg);
				popRegister(mLocVars[i].reg);
				mLocVars[i].isActive = false;
				mLocVars[i].pcEnd = mCode.length;
			}
		}
	}

	package void codeClose(uint line, ushort reg)
	{
		codeI(line, Op1.Close, reg, 0);
	}

	package uint tagLocal(uint val)
	{
		if(val > Instruction.MaxRegisters)
			c.semException(mLocation, "Too many locals");

		return val;
	}

	package uint tagConst(uint val)
	{
// 		if((val & ~Instruction.constBit) >= Instruction.MaxConstants)
		// TODO: large constants
		if((val & ~Instruction.constBit) >= 250)
			c.semException(mLocation, "Too many constants");

		return val | Instruction.constBit;
	}

	package bool isLocalTag(uint val)
	{
		return (val & Instruction.constBit) == 0;
	}

	package bool isConstTag(uint val)
	{
		return (val & Instruction.constBit) != 0;
	}

	// ---------------------------------------------------------------------------
	// Switches

	package void beginSwitch(ref SwitchDesc s, uint line, uint srcReg)
	{
		s.switchPC = codeR(line, Op1.Switch, 0, srcReg, 0);
		s.prev = mSwitch;
		mSwitch = &s;
	}

	package void endSwitch()
	{
		assert(mSwitch !is null, "endSwitch - no switch to end");

		auto prev = mSwitch.prev;

		if(mSwitch.offsets.length > 0 || mSwitch.defaultOffset == -1)
		{
			mSwitchTables.append(c.alloc, *mSwitch);
			auto switchIdx = mSwitchTables.length - 1;

			if(switchIdx > Instruction.MaxSwitchTables)
				c.semException(mLocation, "Too many switches");

			setRT(mCode[mSwitch.switchPC], switchIdx);
		}
		else
		{
			// Happens when all the cases are dynamic and there is a default -- no need to add a switch table then
			setOpcode(mCode[mSwitch.switchPC], Op1.Jmp);
			setRD(mCode[mSwitch.switchPC], 1);
			setImm(mCode[mSwitch.switchPC], mSwitch.defaultOffset);
		}

		mSwitch = prev;
	}

	package void addCase(CompileLoc location, Expression v)
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
			val = createString(t, v.asString());
		else
			assert(false, "addCase invalid type: " ~ v.toString());

		if(mSwitch.offsets.lookup(val) !is null)
		{
			.pushString(t, "Duplicate case value '");
			push(t, val);
			pushToString(t, -1);
			insertAndPop(t, -2);
			.pushChar(t, '\'');
			cat(t, 3);
			c.semException(location, getString(t, -1));
		}

		*mSwitch.offsets.insert(*c.alloc, val) = here() - mSwitch.switchPC - 1;
	}

	package void addDefault(CompileLoc location)
	{
		assert(mSwitch !is null);
		assert(mSwitch.defaultOffset == -1);

		mSwitch.defaultOffset = mCode.length - mSwitch.switchPC - 1;
	}

	// ---------------------------------------------------------------------------
	// Register manipulation

	package uint nextRegister()
	{
		return mFreeReg;
	}

	package uint pushRegister()
	{
		debug(REGPUSHPOP) Stdout.formatln("push {}", mFreeReg);
		mFreeReg++;

		if(mFreeReg > Instruction.MaxRegisters)
			c.semException(mLocation, "Too many registers");

		if(mFreeReg > mStackSize)
			mStackSize = mFreeReg;

		return mFreeReg - 1;
	}

	package void popRegister(uint r)
	{
		mFreeReg--;
		debug(REGPUSHPOP) Stdout.formatln("pop {}, {}", mFreeReg, r);

		assert(mFreeReg >= 0, "temp reg underflow");
		assert(mFreeReg == r, (pushFormat(c.thread, "reg not freed in order (popping {}, free reg is {})", r, mFreeReg), getString(t, -1)));
	}

	package uint resolveAssignmentConflicts(uint line, uint numVals)
	{
		uint numTemps = 0;

		for(int i = mExpSP - numVals + 1; i < mExpSP; i++)
		{
			auto index = &mExpStack[i];
			uint reloc = uint.max;

			for(int j = mExpSP - numVals; j < i; j++)
			{
				auto e = &mExpStack[j];

				if(e.index == index.index || e.index2 == index.index)
				{
					if(reloc == uint.max)
					{
						numTemps++;
						reloc = pushRegister();
						codeR(line, Op1.Move, reloc, index.index, 0);
					}

					if(e.index == index.index)
						e.index = reloc;

					if(e.index2 == index.index)
						e.index2 = reloc;
				}
			}
		}

		return numTemps;
	}

	package void popAssignmentConflicts(uint num)
	{
		mFreeReg -= num;
	}

	// ---------------------------------------------------------------------------
	// Basic expression stack manipulation

	protected Exp* pushExp()
	{
		if(mExpSP >= mExpStack.length)
		{
			if(mExpStack.length == 0)
				c.alloc.resizeArray(mExpStack, 10);
			else
				c.alloc.resizeArray(mExpStack, mExpStack.length * 2);
		}

		auto ret = &mExpStack[mExpSP++];

		ret.isTempReg = false;
		ret.isTempReg2 = false;
		ret.isTempReg3 = false;

		return ret;
	}

	protected Exp* popExp()
	{
		mExpSP--;
		assert(mExpSP >= 0, "exp stack underflow");
		return &mExpStack[mExpSP];
	}

	public void dup()
	{
		auto src = &mExpStack[mExpSP - 1];
		auto dest = pushExp();
		*dest = *src;
	}

	// ---------------------------------------------------------------------------
	// Expression stack pushes

	public void pushNull()
	{
		pushConst(codeNullConst());
	}

	public void pushBool(bool value)
	{
		pushConst(codeBoolConst(value));
	}

	public void pushInt(crocint value)
	{
		pushConst(codeIntConst(value));
	}

	public void pushFloat(crocfloat value)
	{
		pushConst(codeFloatConst(value));
	}

	public void pushChar(dchar value)
	{
		pushConst(codeCharConst(value));
	}

	public void pushString(char[] value)
	{
		pushConst(codeStringConst(value));
	}

	public void pushConst(uint index)
	{
		auto e = pushExp();
		e.type = ExpType.Const;
		e.index = index;
	}

	public void pushNewGlobal(Identifier name)
	{
		auto e = pushExp();
		e.type = ExpType.NewGlobal;
		e.index = codeStringConst(name.name);
	}

	public void pushThis()
	{
		auto e = pushExp();
		e.type = ExpType.Local;
		e.index = tagLocal(0);
	}

	public void pushVar(Identifier name)
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
				ud.index = tagLocal(e.index);

				s.mUpvals.append(c.alloc, ud);

				if(mUpvals.length > Instruction.MaxUpvalues)
					c.semException(mLocation, "Too many upvalues");

				return s.mUpvals.length - 1;
			}

			if(s is null)
			{
				e.index = codeStringConst(name.name);
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
				e.index = tagLocal(reg);
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

	public void pushVararg()
	{
		auto e = pushExp();
		e.type = ExpType.Vararg;
	}

	public void pushVargLen(uint line)
	{
		auto e = pushExp();
		e.type = ExpType.NeedsDest;
		e.index = codeR(line, Op1.Vararg, 0, 0, 0);
		codeR(line, Op2.VargLen, 0, 0, 0);
	}

	public void pushVargSlice(uint line, uint reg)
	{
		auto e = pushExp();
		e.type = ExpType.SlicedVararg;
		e.index = codeI(line, Op1.Vararg, reg, 0);
		codeR(line, Op2.VargSlice, 0, 0, 0);
		e.index2 = reg;
	}

	public void pushTempReg(uint idx)
	{
		auto e = pushExp();
		e.type = ExpType.Src;
		e.index = idx;
		e.isTempReg = true;
	}

	public void pushCall(uint line, uint firstReg, uint numRegs)
	{
		auto e = pushExp();
		e.type = ExpType.Call;
		e.index = codeR(line, Op1.Call, firstReg, numRegs, 0);
		e.index2 = firstReg;
		e.isTempReg2 = true;
	}

	public void pushYield(uint line, uint firstReg, uint numRegs)
	{
		auto e = pushExp();
		e.type = ExpType.Yield;
		e.index = codeR(line, Op1.Yield, firstReg, numRegs, 0);
		e.index2 = firstReg;
	}

	public void pushSlice(uint line, uint reg)
	{
		auto e = pushExp();
		e.index = pushRegister();

		assert(e.index == reg, "push slice reg wrong");

		e.isTempReg = true;
		e.index2 = pushRegister();
		e.isTempReg2 = true;
		e.index3 = pushRegister();
		e.isTempReg3 = true;
		e.type = ExpType.Sliced;
	}

	public void pushSource(uint line)
	{
		dup();
		topToSource(line, false);
	}

	public void pushBinOp(uint line, AstTag type, uint rs, uint rt)
	{
		Exp* dest = pushExp();
		dest.type = ExpType.NeedsDest;
		dest.index = codeR(line, AstTagToOpcode1(type), 0, rs, rt);

		auto second = AstTagToOpcode2(type);

		if(second != -1)
			codeR(line, second, 0, 0, 0);
	}

	// ---------------------------------------------------------------------------
	// Expression stack pops

	public void popToNothing()
	{
		if(mExpSP == 0)
			return;

		auto src = popExp();

		if(src.type == ExpType.Call || src.type == ExpType.Yield)
			setRT(mCode[src.index], 1);

		freeExpTempRegs(*src);
	}

	public void popAssign(uint line)
	{
		auto src = popExp();
		auto dest = popExp();

		switch(dest.type)
		{
			case ExpType.Local:
				moveTo(line, dest.index, src);
				return;

			case ExpType.Upval:
				toSource(line, src);
				codeI(line, Op1.SetUpval, src.index, dest.index);
				break;

			case ExpType.Global:
				toSource(line, src);
				codeI(line, Op1.SetGlobal, src.index, dest.index);
				break;

			case ExpType.NewGlobal:
				toSource(line, src);
				codeI(line, Op1.NewGlobal, src.index, dest.index);
				break;

			case ExpType.Indexed:
				toSource(line, src);
				codeR(line, Op1.IndexAssign, dest.index, dest.index2, src.index);
				break;

			case ExpType.Field:
				toSource(line, src);
				codeR(line, Op1.FieldAssign, dest.index, dest.index2, src.index);
				break;

			case ExpType.IndexedVararg:
				toSource(line, src);
				codeR(line, Op1.Vararg, 0, dest.index, src.index);
				codeR(line, Op2.VargIndexAssign, 0, 0, 0);
				break;

			case ExpType.Sliced:
				toSource(line, src);
				codeR(line, Op1.SliceAssign, dest.index, src.index, 0);
				break;

			case ExpType.Length:
				toSource(line, src);
				codeR(line, Op1.LengthAssign, dest.index, src.index, 0);
				break;

			default:
				assert(false, "popAssign switch");
		}

		freeExpTempRegs(*src);
		freeExpTempRegs(*dest);
	}

	public void popMoveTo(uint line, uint dest)
	{
		auto src = popExp();
		moveTo(line, dest, src);
	}

	public void popToRegisters(uint line, uint reg, int num)
	{
		auto src = popExp();

		switch(src.type)
		{
			case ExpType.Vararg:
				codeI(line, Op1.Vararg, reg, num + 1);
				codeR(line, Op2.GetVarargs, 0, 0, 0);
				break;

			case ExpType.SlicedVararg:
				assert(src.index2 == reg, "pop to regs - trying to pop sliced varargs to different reg");
				setUImm(mCode[src.index], num + 1);
				break;

			case ExpType.Call, ExpType.Yield:
				assert(src.index2 == reg, "pop to regs - trying to pop func call or yield to different reg");
				setRT(mCode[src.index], num + 1);
				freeExpTempRegs(*src);
				break;

			default:
				assert(false, "pop to regs switch");
		}
	}

	public void popReflexOp(uint line, AstTag type, uint rd, uint rs, uint rt = 0)
	{
		auto dest = pushExp();
		dest.type = ExpType.NeedsDest;
		dest.index = codeR(line, AstTagToOpcode1(type), rd, rs, rt);

		auto second = AstTagToOpcode2(type);

		if(second != -1)
			codeR(line, second, 0, 0, 0);

		popAssign(line);
	}

	public void popMoveFromReg(uint line, uint srcReg)
	{
		auto dest = popExp();

		switch(dest.type)
		{
			case ExpType.Local:
				if(dest.index != srcReg)
					codeR(line, Op1.Move, dest.index, srcReg, 0);
				break;

			case ExpType.Upval:
				codeI(line, Op1.SetUpval, srcReg, dest.index);
				break;

			case ExpType.Global:
				codeI(line, Op1.SetGlobal, srcReg, dest.index);
				break;

			case ExpType.NewGlobal:
				codeI(line, Op1.NewGlobal, srcReg, dest.index);
				break;

			case ExpType.Indexed:
				codeR(line, Op1.IndexAssign, dest.index, dest.index2, srcReg);
				freeExpTempRegs(*dest);
				break;

			case ExpType.Field:
				codeR(line, Op1.FieldAssign, dest.index, dest.index2, srcReg);
				freeExpTempRegs(*dest);
				break;

			case ExpType.IndexedVararg:
				codeR(line, Op1.Vararg, 0, dest.index, srcReg);
				codeR(line, Op2.VargIndexAssign, 0, 0, 0);
				freeExpTempRegs(*dest);
				break;

			case ExpType.Sliced:
				codeR(line, Op1.SliceAssign, dest.index, srcReg, 0);
				freeExpTempRegs(*dest);
				break;

			case ExpType.Length:
				codeR(line, Op1.LengthAssign, dest.index, srcReg, 0);
				freeExpTempRegs(*dest);
				break;

			default:
				assert(false);
		}
	}

	public void popField(uint line)
	{
		assert(mExpSP > 1, "pop field from nothing");

		auto index = popExp();
		auto e = &mExpStack[mExpSP - 1];

		toSource(line, e);
		toSource(line, index);

		e.index2 = index.index;
		e.isTempReg2 = index.isTempReg;
		e.type = ExpType.Field;
	}

	public void popIndex(uint line)
	{
		assert(mExpSP > 1, "pop index from nothing");

		auto index = popExp();
		auto e = &mExpStack[mExpSP - 1];

		toSource(line, e);
		toSource(line, index);

		e.index2 = index.index;
		e.isTempReg2 = index.isTempReg;
		e.type = ExpType.Indexed;
	}

	public void popVargIndex(uint line)
	{
		assert(mExpSP > 0, "pop varg index from nothing");

		auto e = &mExpStack[mExpSP - 1];
		toSource(line, e);
		e.type = ExpType.IndexedVararg;
	}

	public void popSource(uint line, out Exp n)
	{
		n = *popExp();
		toSource(line, &n);
	}

	// ---------------------------------------------------------------------------
	// Other codegen funcs

	public void unOp(uint line, AstTag type)
	{
		auto src = popExp();
		toSource(line, src);

		uint pc = codeR(line, AstTagToOpcode1(type), 0, src.index, 0);

		auto second = AstTagToOpcode2(type);

		if(second != -1)
			codeR(line, second, 0, 0, 0);

		freeExpTempRegs(*src);

		auto dest = pushExp();
		dest.type = ExpType.NeedsDest;
		dest.index = pc;
	}

	public void topToLength(uint line)
	{
		topToSource(line);
		mExpStack[mExpSP - 1].type = ExpType.Length;
	}

	public void topToSource(uint line, bool cleanup = true)
	{
		toSource(line, &mExpStack[mExpSP - 1], cleanup);
	}

	protected void toSource(uint line, Exp* e, bool cleanup = true)
	{
		Exp temp;
		temp.type = ExpType.Src;

		switch(e.type)
		{
			case ExpType.Const:
				temp.index = tagConst(e.index);
				break;

			case ExpType.Local:
				temp.index = e.index;
				break;

			case ExpType.Upval:
				if(cleanup)
					freeExpTempRegs(*e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeI(line, Op1.GetUpval, temp.index, e.index);
				break;

			case ExpType.Global:
				if(cleanup)
					freeExpTempRegs(*e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeI(line, Op1.GetGlobal, temp.index, e.index);
				break;

			case ExpType.Indexed:
				if(cleanup)
					freeExpTempRegs(*e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op1.Index, temp.index, e.index, e.index2);
				break;

			case ExpType.Field:
				if(cleanup)
					freeExpTempRegs(*e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op1.Field, temp.index, e.index, e.index2);
				break;

			case ExpType.IndexedVararg:
				if(cleanup)
					freeExpTempRegs(*e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op1.Vararg, temp.index, e.index, 0);
				codeR(line, Op2.VargIndex, 0, 0, 0);
				break;

			case ExpType.Sliced:
				if(cleanup)
					freeExpTempRegs(*e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op1.Slice, temp.index, e.index, 0);
				break;

			case ExpType.Length:
				if(cleanup)
					freeExpTempRegs(*e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op1.Length, temp.index, e.index, 0);
				break;

			case ExpType.NeedsDest:
				temp.index = pushRegister();
				setRD(mCode[e.index], temp.index);
				temp.isTempReg = true;
				break;

			case ExpType.Call, ExpType.Yield:
				setRT(mCode[e.index], 2);
				temp.index = e.index2;
				temp.isTempReg = e.isTempReg2;
				break;

			case ExpType.Src:
				temp = *e;
				break;

			case ExpType.Vararg:
				temp.index = pushRegister();
				codeI(line, Op1.Vararg, temp.index, 2);
				codeR(line, Op2.GetVarargs, 0, 0, 0);
				temp.isTempReg = true;
				break;

			case ExpType.SlicedVararg:
				if(cleanup)
					freeExpTempRegs(*e);

				codeI(line, Op1.Vararg, e.index, 2);
				codeR(line, Op2.VargSlice, 0, 0, 0);
				temp.index = e.index;
				break;

			default:
				assert(false, "toSource switch");
		}

		*e = temp;
	}

	public void moveTo(uint line, uint dest, Exp* src)
	{
		switch(src.type)
		{
			case ExpType.Const:
				assert(isLocalTag(dest));
				codeI(line, Op1.LoadConst, dest, src.index);
				break;

			case ExpType.Local:
				if(dest != src.index)
					codeR(line, Op1.Move, dest, src.index, 0);
				break;

			case ExpType.Upval:
				codeI(line, Op1.GetUpval, dest, src.index);
				freeExpTempRegs(*src);
				break;

			case ExpType.Global:
				codeI(line, Op1.GetGlobal, dest, src.index);
				freeExpTempRegs(*src);
				break;

			case ExpType.Indexed:
				codeR(line, Op1.Index, dest, src.index, src.index2);
				freeExpTempRegs(*src);
				break;

			case ExpType.Field:
				codeR(line, Op1.Field, dest, src.index, src.index2);
				freeExpTempRegs(*src);
				break;

			case ExpType.IndexedVararg:
				codeR(line, Op1.Vararg, dest, src.index, 0);
				codeR(line, Op2.VargIndex, 0, 0, 0);
				freeExpTempRegs(*src);
				break;

			case ExpType.Sliced:
				codeR(line, Op1.Slice, dest, src.index, 0);
				freeExpTempRegs(*src);
				break;

			case ExpType.Length:
				codeR(line, Op1.Length, dest, src.index, 0);
				freeExpTempRegs(*src);
				break;

			case ExpType.Vararg:
				if(isLocalTag(dest))
				{
					codeI(line, Op1.Vararg, dest, 2);
					codeR(line, Op2.GetVarargs, 0, 0, 0);
				}
				else
				{
					assert(!isConstTag(dest), "moveTo vararg dest is const");
					uint tempReg = pushRegister();
					codeI(line, Op1.Vararg, tempReg, 2);
					codeR(line, Op2.GetVarargs, 0, 0 ,0);
					codeR(line, Op1.Move, dest, tempReg, 0);
					popRegister(tempReg);
				}
				break;

			case ExpType.SlicedVararg:
				setUImm(mCode[src.index], 2);

				if(dest != src.index2)
					codeR(line, Op1.Move, dest, src.index2, 0);
				break;

			case ExpType.Call, ExpType.Yield:
				setRT(mCode[src.index], 2);

				if(dest != src.index2)
					codeR(line, Op1.Move, dest, src.index2, 0);

				freeExpTempRegs(*src);
				break;

			case ExpType.NeedsDest:
				setRD(mCode[src.index], dest);
				break;

			case ExpType.Src:
				if(dest != src.index)
					codeR(line, Op1.Move, dest, src.index, 0);

				freeExpTempRegs(*src);
				break;

			default:
				assert(false, "moveTo switch");
		}
	}

	public void makeTailcall()
	{
		assert(getOpcode(mCode[$ - 1]) == Op1.Call, "need call to make tailcall");
		setOpcode(mCode[$ - 1], Op1.Tailcall);
	}

	public void codeClosure(FuncState fs, uint destReg)
	{
		if(mInnerFuncs.length > Instruction.MaxInnerFuncs)
			c.semException(mLocation, "Too many inner functions");

		auto line = fs.mLocation.line;
		
		if(mNamespaceReg > 0)
			codeR(line, Op1.Move, destReg, mNamespaceReg, 0);

		codeI(line, Op1.New, destReg, mInnerFuncs.length);
		codeR(line, mNamespaceReg > 0 ? Op2.ClosureWithEnv : Op2.Closure, 0, 0, 0);

		foreach(ref ud; fs.mUpvals)
			codeI(line, Op1.Move, ud.isUpvalue ? 1 : 0, ud.index);

		auto fd = fs.toFuncDef();
		t.vm.alloc.resizeArray(mInnerFuncs, mInnerFuncs.length + 1);
		mInnerFuncs[$ - 1] = fd;
	}
	
	public void beginNamespace(uint reg)
	{
		assert(mNamespaceReg == 0);
		mNamespaceReg = reg;
	}
	
	public void endNamespace()
	{
		assert(mNamespaceReg != 0);
		mNamespaceReg = 0;
	}

	// ---------------------------------------------------------------------------
	// Control flow

	public uint here()
	{
		return mCode.length;
	}

	public void patchJumpTo(uint src, uint dest)
	{
		setImm(mCode[src], dest - src - 1);
	}

	public void patchJumpToHere(uint src)
	{
		patchJumpTo(src, here());
	}

	package void patchListTo(uint j, uint dest)
	{
		for(uint next = void; j != NoJump; j = next)
		{
			next = getImm(mCode[j]);
			patchJumpTo(j, dest);
		}
	}

	public void patchContinuesTo(uint dest)
	{
		patchListTo(mScope.continues, dest);
		mScope.continues = NoJump;
	}

	public void patchBreaksToHere()
	{
		patchListTo(mScope.breaks, here());
		mScope.breaks = NoJump;
	}

	public void patchContinuesToHere()
	{
		patchContinuesTo(here());
	}

	public void patchTrueToHere(ref InstRef i)
	{
		patchListTo(i.trueList, here());
		i.trueList = NoJump;
	}

	public void patchFalseToHere(ref InstRef i)
	{
		patchListTo(i.falseList, here());
		i.falseList = NoJump;
	}
	
	public void catToTrue(ref InstRef i, uint j)
	{
		if(i.trueList == NoJump)
			i.trueList = j;
		else
		{
			auto idx = i.trueList;

			while(true)
			{
				auto next = getImm(mCode[idx]);

				if(next is NoJump)
					break;
				else
					idx = next;
			}

			setImm(mCode[idx], j);
		}
	}

	public void catToFalse(ref InstRef i, uint j)
	{
		if(i.falseList == NoJump)
			i.falseList = j;
		else
		{
			auto idx = i.falseList;

			while(true)
			{
				auto next = getImm(mCode[idx]);

				if(next is NoJump)
					break;
				else
					idx = next;
			}

			setImm(mCode[idx], j);
		}
	}

	public void invertJump(ref InstRef i)
	{
		debug assert(!i.inverted);
		debug i.inverted = true;

		auto j = i.trueList;
		assert(j !is NoJump);
		i.trueList = getImm(mCode[j]);
		setImm(mCode[j], i.falseList);
		i.falseList = j;
		setRD(mCode[j], !getRD(mCode[j]));
	}

	public void codeJump(uint line, uint dest)
	{
		codeJ(line, Op1.Jmp, true, dest - here() - 1);
	}

	public uint makeJump(uint line, uint type = Op1.Jmp, bool isTrue = true)
	{
		return codeJ(line, type, isTrue, NoJump);
	}

	public uint makeFor(uint line, uint baseReg)
	{
		return codeJ(line, Op1.For, baseReg, NoJump);
	}

	public uint makeForLoop(uint line, uint baseReg)
	{
		return codeJ(line, Op1.ForLoop, baseReg, NoJump);
	}

	public uint makeForeach(uint line, uint baseReg)
	{
		return codeJ(line, Op1.Foreach, baseReg, NoJump);
	}

	public uint codeCatch(uint line, ref Scope s, out uint checkReg)
	{
		pushScope(s);
		checkReg = mFreeReg;
		mScope.ehlevel++;
		mTryCatchDepth++;
		auto ret = codeJ(line, Op1.PushEH, mFreeReg, NoJump);
		codeR(line, Op2.Catch, 0, 0, 0);
		return ret;
	}

	public uint codeFinally(uint line, ref Scope s)
	{
		pushScope(s);
		mScope.ehlevel++;
		mTryCatchDepth++;
		auto ret = codeJ(line, Op1.PushEH, mFreeReg, NoJump);
		codeR(line, Op2.Finally, 0, 0, 0);
		return ret;
	}

	public void endCatchScope(uint line)
	{
		popScope(line);
		mTryCatchDepth--;
	}

	public void endFinallyScope(uint line)
	{
		popScope(line);
		mTryCatchDepth--;
	}

	public bool inTryCatch()
	{
		return mTryCatchDepth > 0;
	}

	public void codeContinue(CompileLoc location, char[] name)
	{
		bool anyUpvals = false;
		Scope* continueScope = void;

		if(name.length == 0)
		{
			if(mScope.continueScope is null)
				c.semException(location, "No continuable control structure");

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
				c.semException(location, "No continuable control structure of that name");

			if(continueScope.continueScope !is continueScope)
				c.semException(location, "Cannot continue control structure of that name");
		}

		if(anyUpvals)
			codeClose(location.line, continueScope.regStart);

		auto diff = mScope.ehlevel - continueScope.ehlevel;

		if(diff > 0)
			codeI(location.line, Op1.Unwind, 0, diff);

		continueScope.continues = codeJ(location.line, Op1.Jmp, 1, continueScope.continues);
	}

	public void codeBreak(CompileLoc location, char[] name)
	{
		bool anyUpvals = false;
		Scope* breakScope = void;

		if(name.length == 0)
		{
			if(mScope.breakScope is null)
				c.semException(location, "No breakable control structure");

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
				c.semException(location, "No breakable control structure of that name");

			if(breakScope.breakScope !is breakScope)
				c.semException(location, "Cannot break control structure of that name");
		}

		if(anyUpvals)
			codeClose(location.line, breakScope.regStart);

		auto diff = mScope.ehlevel - breakScope.ehlevel;

		if(diff > 0)
			codeI(location.line, Op1.Unwind, 0, diff);

		breakScope.breaks = codeJ(location.line, Op1.Jmp, 1, breakScope.breaks);
	}

	// ---------------------------------------------------------------------------
	// Constants

	public int codeConst(CrocValue v)
	{
		foreach(i, ref con; mConstants)
			if(con == v)
				return i;

		mConstants.append(c.alloc, v);

		if(mConstants.length >= Instruction.MaxConstants)
			c.semException(mLocation, "Too many constants");

		return mConstants.length - 1;
	}

	public int codeNullConst()
	{
		return codeConst(CrocValue.nullValue);
	}

	public int codeBoolConst(bool b)
	{
		return codeConst(CrocValue(b));
	}

	public int codeIntConst(crocint x)
	{
		return codeConst(CrocValue(x));
	}

	public int codeFloatConst(crocfloat x)
	{
		return codeConst(CrocValue(x));
	}

	public int codeCharConst(dchar x)
	{
		return codeConst(CrocValue(x));
	}

	public int codeStringConst(char[] s)
	{
		return codeConst(CrocValue(createString(t, s)));
	}

	public void codeNulls(uint line, uint reg, uint num)
	{
		codeI(line, Op1.LoadNulls, reg, num);
	}

	// ---------------------------------------------------------------------------
	// Raw codegen funcs

	package uint codeR(uint line, uint opcode, uint dest, uint src1, uint src2)
	{
		Instruction i = void;
		i.data =
			((opcode << Instruction.opcodeShift) & Instruction.opcodeMask) |
			((dest << Instruction.rdShift) & Instruction.rdMask) |
			((src1 << Instruction.rsShift) & Instruction.rsMask) |
			((src2 << Instruction.rtShift) & Instruction.rtMask);

		debug(WRITECODE) Stdout.formatln("R {} {} {} {}", opcode, dest, src1, src2).flush;

		mLineInfo.append(c.alloc, line);
		mCode.append(c.alloc, i);
		return mCode.length - 1;
	}

	package uint codeI(uint line, uint opcode, uint dest, uint imm)
	{
		Instruction i = void;
		i.data =
			((opcode << Instruction.opcodeShift) & Instruction.opcodeMask) |
			((dest << Instruction.rdShift) & Instruction.rdMask) |
			((imm << Instruction.immShift) & Instruction.immMask);

		debug(WRITECODE) Stdout.formatln("I {} {} {}", opcode, dest, imm).flush;

		mLineInfo.append(c.alloc, line);
		mCode.append(c.alloc, i);
		return mCode.length - 1;
	}

	package uint codeJ(uint line, uint opcode, uint dest, int offs)
	{
		// TODO: put this somewhere else. codeJ can be called with MaxJump which is an invalid value.
// 		if(offs < Instruction.MaxJumpBackward || offs > Instruction.MaxJumpForward)
// 			assert(false, "jump too large");

		Instruction i = void;
		i.data =
			((opcode << Instruction.opcodeShift) & Instruction.opcodeMask) |
			((dest << Instruction.rdShift) & Instruction.rdMask) |
			((*(cast(uint*)&offs) << Instruction.immShift) & Instruction.immMask);

		debug(WRITECODE) Stdout.formatln("J {} {} {}", opcode, dest, offs).flush;

		mLineInfo.append(c.alloc, line);
		mCode.append(c.alloc, i);
		return mCode.length - 1;
	}
	
	package void setOpcode(ref Instruction inst, uint opcode)
	{
		assert(opcode <= Instruction.opcodeMax);
		inst.data &= ~Instruction.opcodeMask;
		inst.data |= (opcode << Instruction.opcodeShift) & Instruction.opcodeMask;
	}
	
	package void setRD(ref Instruction inst, uint val)
	{
		assert(val <= Instruction.rdMax);
		inst.data &= ~Instruction.rdMask;
		inst.data |= (val << Instruction.rdShift) & Instruction.rdMask;
	}
	
	package void setRS(ref Instruction inst, uint val)
	{
		assert(val <= Instruction.rsMax);
		inst.data &= ~Instruction.rsMask;
		inst.data |= (val << Instruction.rsShift) & Instruction.rsMask;
	}

	package void setRT(ref Instruction inst, uint val)
	{
		assert(val <= Instruction.rtMax);
		inst.data &= ~Instruction.rtMask;
		inst.data |= (val << Instruction.rtShift) & Instruction.rtMask;
	}
	
	package void setImm(ref Instruction inst, int val)
	{
		assert(val == Instruction.NoJump || (val >= -Instruction.immMax && val <= Instruction.immMax));
		inst.data &= ~Instruction.immMask;
		inst.data |= (*(cast(uint*)&val) << Instruction.immShift) & Instruction.immMask;
	}

	package void setUImm(ref Instruction inst, uint val)
	{
		assert(val <= Instruction.uimmMax);
		inst.data &= ~Instruction.immMask;
		inst.data |= (val << Instruction.immShift) & Instruction.immMask;
	}

	package uint getOpcode(ref Instruction inst)
	{
		return (inst.data & Instruction.opcodeMask) >> Instruction.opcodeShift;
	}

	package uint getRD(ref Instruction inst)
	{
		return (inst.data & Instruction.rdMask) >> Instruction.rdShift;
	}

	package uint getRS(ref Instruction inst)
	{
		return (inst.data & Instruction.rsMask) >> Instruction.rsShift;
	}

	package uint getRT(ref Instruction inst)
	{
		return (inst.data & Instruction.rtMask) >> Instruction.rtShift;
	}

	package int getImm(ref Instruction inst)
	{
		static assert((Instruction.immShift + Instruction.immSize) == Instruction.sizeof * 8, "Immediate must be at top of instruction word");
		return (*cast(int*)&inst.data) >> Instruction.immShift;
	}

	package uint getUImm(ref Instruction inst)
	{
		static assert((Instruction.immShift + Instruction.immSize) == Instruction.sizeof * 8, "Immediate must be at top of instruction word");
		return inst.data >>> Instruction.immShift;
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

	debug(SHOWME) public void showMe()
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
			return *pc++;;
		}

		char[] cr(uint v)
		{
			if(isConstTag(v))
				return Format("c{}", v & ~Instruction.constBit);
			else
				return Format("r{}", v);
		}

		void leader()
		{
			Stdout.format("\t[{,3}:{,4}] ", insOffset, mLineInfo[insOffset]);
		}

		void commonNullary(Instruction i)   { Stdout.formatln(" r{}",         getRD(i)); }
		void commonUnary(Instruction i)     { Stdout.formatln(" r{}, {}",     getRD(i), cr(getRS(i))); }
		void commonBinary(Instruction i)    { Stdout.formatln(" r{}, {}, {}", getRD(i), cr(getRS(i)), cr(getRT(i))); }
		void commonUImm(Instruction i)      { Stdout.formatln(" r{}, {}",     getRD(i), getUImm(i)); }
		void commonImm(Instruction i)       { Stdout.formatln(" r{}, {}",     getRD(i), getImm(i)); }
		void commonUImmConst(Instruction i) { Stdout.formatln(" r{}, c{}",    getRD(i), getUImm(i)); }
		void commonCompare(Instruction i)   { Stdout.formatln(" {}, {}",      cr(getRS(i)), cr(getRT(i))); }

		void condJump()
		{
			leader();
			auto i = nextIns();

			switch(getOpcode(i))
			{
				case Op2.Je:  Stdout((getRD(i) == 0) ? "jne" : "je"); break;
				case Op2.Jle: Stdout((getRD(i) == 0) ? "jgt" : "jle"); break;
				case Op2.Jlt: Stdout((getRD(i) == 0) ? "jge" : "jlt"); break;
				default: assert(false);
			}

			Stdout.formatln(" {}", getImm(i));
		}
		
		void commonClosure(Instruction ins)
		{
			auto num = mInnerFuncs[getUImm(ins)].numUpvals;

			for(uword i = 0; i < num; i++)
			{
				ins = nextIns();
				
				assert(getOpcode(ins) == Op1.Move);

				if(getRD(ins) == 0)
					Stdout.formatln("\t\tr{}", getUImm(ins));
				else
					Stdout.formatln("\t\tupvalue {}", getUImm(ins));
			}
		}

		leader();
		auto i = nextIns();

		_outerSwitch: switch(getOpcode(i))
		{
			case Op1.UnOp:
				auto two = nextIns();
				switch(getOpcode(two))
				{
					case Op2.Neg: Stdout("neg"); break;
					case Op2.Com: Stdout("com"); break;
					case Op2.Not: Stdout("not"); break;
					default: assert(false);
				}
				commonUnary(i);
				break;

			case Op1.BinOp:
				auto two = nextIns();
				switch(getOpcode(two))
				{
					case Op2.Add:  Stdout("add");  break;
					case Op2.Sub:  Stdout("sub");  break;
					case Op2.Mul:  Stdout("mul");  break;
					case Op2.Div:  Stdout("div");  break;
					case Op2.Mod:  Stdout("mod");  break;
					case Op2.Cmp3: Stdout("cmp3"); break;
					default: assert(false);
				}
				commonBinary(i);
				break;

			case Op1.ReflBinOp:
				auto two = nextIns();
				switch(getOpcode(two))
				{
					case Op2.AddEq: Stdout("addeq"); break;
					case Op2.SubEq: Stdout("subeq"); break;
					case Op2.MulEq: Stdout("muleq"); break;
					case Op2.DivEq: Stdout("diveq"); break;
					case Op2.ModEq: Stdout("modeq"); break;
					default: assert(false);
				}
				commonUnary(i);
				break;

			case Op1.BitOp:
				auto two = nextIns();
				switch(getOpcode(two))
				{
					case Op2.And:  Stdout("and");  break;
					case Op2.Or:   Stdout("or");   break;
					case Op2.Xor:  Stdout("xor");  break;
					case Op2.Shl:  Stdout("shl");  break;
					case Op2.Shr:  Stdout("shr");  break;
					case Op2.UShr: Stdout("ushr"); break;
					default: assert(false);
				}
				commonBinary(i);
				break;

			case Op1.ReflBitOp:
				auto two = nextIns();
				switch(getOpcode(two))
				{
					case Op2.AndEq:  Stdout("andeq");  break;
					case Op2.OrEq:   Stdout("oreq");   break;
					case Op2.XorEq:  Stdout("xoreq");  break;
					case Op2.ShlEq:  Stdout("shleq");  break;
					case Op2.ShrEq:  Stdout("shreq");  break;
					case Op2.UShrEq: Stdout("ushreq"); break;
					default: assert(false);
				}
				commonUnary(i);
				break;

			case Op1.CrementOp:
				auto two = nextIns();
				switch(getOpcode(two))
				{
					case Op2.Inc: Stdout("inc"); break;
					case Op2.Dec: Stdout("dec"); break;
					default: assert(false);
				}
				commonNullary(i);
				break;

			case Op1.Move:          Stdout("mov");    commonUnary(i);     break;
			case Op1.LoadConst:     Stdout("lc");     commonUImmConst(i); break;
			case Op1.LoadNulls:     Stdout("lnulls"); commonUImm(i);      break;
			case Op1.NewGlobal:     Stdout("newg");   commonUImmConst(i); break;
			case Op1.GetGlobal:     Stdout("getg");   commonUImmConst(i); break;
			case Op1.SetGlobal:     Stdout("setg");   commonUImmConst(i); break;
			case Op1.GetUpval:      Stdout("getu");   commonUImm(i);      break;
			case Op1.SetUpval:      Stdout("setu");   commonUImm(i);      break;

			case Op1.Cmp:           Stdout("cmp");    commonCompare(i); condJump(); break;
			case Op1.Equals:        Stdout("equals"); commonCompare(i); condJump(); break;
			case Op1.SwitchCmp:     Stdout("swcmp");  commonCompare(i); condJump(); break;
			case Op1.Is:            Stdout("is");     commonCompare(i); condJump(); break;

			case Op1.IsTrue:        Stdout.formatln("istrue {}", cr(getRS(i))); condJump(); break;
			case Op1.ForeachLoop:   Stdout("foreachloop");   commonUImm(i); condJump();     break;
			case Op1.CheckObjParam: Stdout("checkobjparam"); commonCompare(i); condJump();  break;

			case Op1.Jmp:           if(getRD(i) == 0) Stdout("nop").newline; else Stdout.formatln("jmp {}", getImm(i)); break;
			case Op1.Switch:        Stdout.formatln("switch {}, {}", cr(getRS(i)), getRT(i)); break;
			case Op1.For:           Stdout("for");     commonImm(i); break;
			case Op1.ForLoop:       Stdout("forloop"); commonImm(i); break;
			case Op1.Foreach:       Stdout("foreach"); commonImm(i); break;

			case Op1.PushEH:
				auto two = nextIns();
				switch(getOpcode(two))
				{
					case Op2.Catch:   Stdout("pushcatch"); break;
					case Op2.Finally: Stdout("pushfinal"); break;
					default: assert(false);
				}
				commonImm(i);
				break;

			case Op1.PopEH:
				auto two = nextIns();
				switch(getOpcode(two))
				{
					case Op2.Catch:   Stdout("popcatch").newline; break;
					case Op2.Finally: Stdout("popfinal").newline; break;
					default: assert(false);
				}
				break;

			case Op1.EndFinal:    Stdout("endfinal").newline; break;
			case Op1.Throw:       Stdout.formatln("{}throw {}", getRT(i) ? "re" : "", cr(getRS(i))); break;
			case Op1.Unwind:      Stdout.formatln("unwind {}", getUImm(i)); break;
			case Op1.Method:      Stdout("method"); commonBinary(i); break;
			case Op1.MethodNC:    Stdout("methodnc"); commonBinary(i); break;
			case Op1.SuperMethod: Stdout("smethod"); commonBinary(i); break;
			case Op1.Call:        Stdout.formatln("call r{}, {}, {}", getRD(i), getRS(i), getRT(i)); break;
			case Op1.Tailcall:    Stdout.formatln("tcall r{}, {}", getRD(i), getRS(i)); break;
			case Op1.Yield:       Stdout.formatln("yield r{}, {}, {}", getRD(i), getRS(i), getRT(i)); break;
			case Op1.SaveRets:    Stdout("saverets"); commonUImm(i); break;
			case Op1.Ret:         Stdout("ret").newline; break;
			case Op1.Close:       Stdout("close"); commonNullary(i); break;

			case Op1.Vararg:
				auto two = nextIns();
				switch(getOpcode(two))
				{
					case Op2.GetVarargs:      Stdout("vararg"); commonUImm(i); break;
					case Op2.VargLen:         Stdout("varglen"); commonNullary(i); break;
					case Op2.VargIndex:       Stdout("vargidx"); commonUnary(i); break;
					case Op2.VargIndexAssign: Stdout("vargidxa"); commonUnary(i); break;
					case Op2.VargSlice:       Stdout("vargslice"); commonUImm(i); break;
					default: assert(false);
				}
				break;

			case Op1.CheckParams: Stdout("checkparams").newline; break;

			case Op1.ParamFail:
				auto two = nextIns();
				switch(getOpcode(two))
				{
					case Op2.ObjParamFail:    Stdout.formatln("objparamfail {}", cr(getRS(i))); break;
					case Op2.CustomParamFail: Stdout("customparamfail"); commonCompare(i); break;
					default: assert(false);
				}
				break;

			case Op1.Length:       Stdout("len"); commonUnary(i); break;
			case Op1.LengthAssign: Stdout("lena"); commonUnary(i); break;

			case Op1.Array:
				auto two = nextIns();
				switch(getOpcode(two))
				{
					case Op2.Append: Stdout("append"); commonUnary(i); break;
					case Op2.Set:    Stdout.formatln("setarray r{}, {}, block {}", getRD(i), getRS(i), getRT(i)); break;
					default: assert(false);
				}
				break;

			case Op1.Cat:         Stdout.formatln("cat r{}, r{}, {}", getRD(i), getRS(i), getRT(i)); break;
			case Op1.CatEq:       Stdout.formatln("cateq r{}, r{}, {}", getRD(i), getRS(i), getRT(i)); break;
			case Op1.Index:       Stdout("idx"); commonBinary(i); break;
			case Op1.IndexAssign: Stdout("idxa"); commonBinary(i); break;
			case Op1.Slice:       Stdout("slice"); commonUnary(i); break;
			case Op1.SliceAssign: Stdout("slicea"); commonUnary(i); break;
			case Op1.In:          Stdout("in"); commonBinary(i); break;

			case Op1.New:
				auto two = nextIns();
				switch(getOpcode(two))
				{
					case Op2.Array:          Stdout("newarr"); commonImm(i); break;
					case Op2.Table:          Stdout("newtab"); commonNullary(i); break;
					case Op2.Class:          Stdout("class"); commonBinary(i); break;
					case Op2.Coroutine:      Stdout("coroutine"); commonUnary(i); break;
					case Op2.Namespace:      Stdout("namespace"); commonBinary(i); break;
					case Op2.NamespaceNP:    Stdout("namespacenp"); commonUnary(i); break;
					case Op2.Closure:        Stdout("closure"); commonUImm(i); commonClosure(i); break;
					case Op2.ClosureWithEnv: Stdout("closurewenv"); commonUImm(i); commonClosure(i); break;
					default: assert(false);
				}
				break;

			case Op1.As:          Stdout("as"); commonBinary(i); break;
			case Op1.SuperOf:     Stdout("superof"); commonUnary(i); break;
			case Op1.Field:       Stdout("field"); commonBinary(i); break;
			case Op1.FieldAssign: Stdout("fielda"); commonBinary(i); break;
			default: Stdout.formatln("??? opcode = {}", getOpcode(i));
		}
	}
}