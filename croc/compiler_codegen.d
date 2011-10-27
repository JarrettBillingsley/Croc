/******************************************************************************
This module defines an AST visitor which performs code generation on an AST
that has already been semantic'ed.

License:
Copyright (c) 2008 Jarrett Billingsley

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

module croc.compiler_codegen;

// debug = REGPUSHPOP;
// debug = VARACTIVATE;
// debug = WRITECODE;
debug = SHOWME;
// debug = PRINTEXPSTACK;

import tango.io.Stdout;
debug import tango.text.convert.Format;

import croc.api_interpreter;
import croc.api_stack;
import croc.base_alloc;
import croc.base_hash;
import croc.base_opcodes;
import croc.compiler_ast;
import croc.compiler_astvisitor;
import croc.compiler_types;
import croc.types;
import croc.types_funcdef;
import croc.types_function;
import croc.types_string;
import croc.utils;

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
	Local,
	NewGlobal,
	Upval,
	Global,
	Indexed,
	Field,
	Sliced,
	Vararg,
	IndexedVararg,
	SlicedVararg,
	Length,
	Call,
	Yield, // ?
	NeedsDest,
	Src
}

struct Exp
{
	ExpType type;

	uint index;
	uint index2;
	uint index3;

	bool isTempReg;
	bool isTempReg2;
	bool isTempReg3;

	debug char[] toString()
	{
		static const char[][] typeNames =
		[
			ExpType.Const: "Const",
			ExpType.NewGlobal: "NewGlobal",
			ExpType.Indexed: "Indexed",
			ExpType.IndexedVararg: "IndexedVararg",
			ExpType.Field: "Field",
			ExpType.Sliced: "Sliced",
			ExpType.SlicedVararg: "SlicedVararg",
			ExpType.Length: "Length",
			ExpType.Vararg: "Vararg",
			ExpType.Call: "Call",
			ExpType.Yield: "Yield",
			ExpType.NeedsDest: "NeedsDest",
			ExpType.Src: "Src"
		];

		return Format("{} ({}, {}, {}) : ({}, {}, {})", typeNames[cast(uint)type], index, index2, index3, isTempReg, isTempReg2, isTempReg3);
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

	struct UpvalDesc
	{
		package bool isUpvalue;
		package uint index;
		package char[] name;
	}

	package UpvalDesc[] mUpvals;
	package uint mStackSize;
	package CrocFuncDef*[] mInnerFuncs;
	package CrocValue[] mConstants;
	package Instruction[] mCode;

	package uint mNamespaceReg = 0;

	package SwitchDesc* mSwitch;
	package SwitchDesc[] mSwitchTables;
	package uint[] mLineInfo;

	struct LocVarDesc
	{
		package char[] name;
		package uint pcStart;
		package uint pcEnd;
		package uint reg;

		package CompileLoc location;
		package bool isActive;
	}

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
	// Misc

	debug package void printExpStack()
	{
		Stdout.formatln("Expression Stack");
		Stdout.formatln("----------------");

		for(int i = 0; i < mExpSP; i++)
			Stdout.formatln("{}: {}", i, mExpStack[i].toString());

		Stdout.formatln("");
	}

	// ---------------------------------------------------------------------------
	// Scopes, variables

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

		if(mScope.hasUpval)
			codeClose(line, mScope.regStart);

		deactivateLocals(mScope.varStart, mScope.regStart);
		// also set mFreeReg to mScope.regStart? maybe? or just check that it is
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

	package void closeUpvals(uint line)
	{
		if(mScope.hasUpval)
		{
			codeClose(line);
			mScope.hasUpval = false;
		}
	}

	package void codeClose(uint line)
	{
		if(mScope.hasUpval)
			codeI(line, Op1.Close, mScope.regStart, 0);
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
	
	public void freeExpTempRegs(ref Exp e)
	{
		if(e.isTempReg3)
			popRegister(e.index3);

		if(e.isTempReg2)
			popRegister(e.index2);

		if(e.isTempReg)
			popRegister(e.index);

		e.isTempReg = false;
		e.isTempReg2 = false;
		e.isTempReg3 = false;
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

scope class Codegen : Visitor
{
	private FuncState fs;

	this(ICompiler c)
	{
		super(c);
	}

	alias Visitor.visit visit;

	public void codegenStatements(FuncDef d)
	{
		scope fs_ = new FuncState(c, d.location, d.name.name, null);

		{
			fs = fs_;
			scope(exit)
				fs = null;

			fs.mIsVararg = d.isVararg;
			fs.mNumParams = d.params.length;

			Scope scop = void;
			fs.pushScope(scop);
				foreach(ref p; d.params)
				{
					fs.insertLocal(p.name);
					fs.mParamMasks.append(c.alloc, p.typeMask);
				}

				fs.activateLocals(d.params.length);

				visit(d.code);
				fs.codeI(d.code.endLocation.line, Op1.SaveRets, 0, 1);
				fs.codeI(d.code.endLocation.line, Op1.Ret, 0, 0);
			fs.popScope(d.code.endLocation.line);
		}

		auto def = fs_.toFuncDef();
		push(c.thread, CrocValue(def));
		insertAndPop(c.thread, -2);
	}

	public override Module visit(Module m)
	{
		scope fs_ = new FuncState(c, m.location, c.newString("<top-level>"), null);

		try
		{
			fs = fs_;
			scope(exit)
				fs = null;

			fs.mNumParams = 1;
			fs.insertLocal(new(c) Identifier(c, m.location, c.newString("this")));
			fs.activateLocals(1);

			Scope scop = void;
			fs.pushScope(scop);
				visit(m.statements);

				if(m.decorator)
				{
					visitDecorator(m.decorator, { fs.pushThis(); });
					fs.popToNothing();
				}

				fs.codeI(m.endLocation.line, Op1.SaveRets, 0, 1);
				fs.codeI(m.endLocation.line, Op1.Ret, 0, 0);
			fs.popScope(m.endLocation.line);

			assert(fs.mExpSP == 0, "module - not all expressions have been popped");
		}
		finally
		{
			debug(PRINTEXPSTACK)
				fs.printExpStack();
		}

		auto def = fs_.toFuncDef();
		push(c.thread, CrocValue(def));
		insertAndPop(c.thread, -2);

		return m;
	}

	public override ClassDef visit(ClassDef d)
	{
		auto reg = classDefBegin(d);
		classDefEnd(d, reg);
		fs.pushTempReg(reg);

		/*
		classDefBegin(d); // leaves local containing class on the stack
		classDefEnd(d); // still leaves it
		*/

		return d;
	}

	public uint classDefBegin(ClassDef d)
	{
		Exp base;

		if(d.baseClass)
			visit(d.baseClass);
		else
			fs.pushNull();

		fs.popSource(d.location.line, base);
		fs.freeExpTempRegs(base);

		auto destReg = fs.pushRegister();
		auto nameConst = fs.tagConst(fs.codeStringConst(d.name.name));

		fs.codeR(d.location.line, Op1.New, destReg, nameConst, base.index);
		fs.codeR(d.location.line, Op2.Class, 0, 0, 0);

		/*
		fs.pushStringConst(d.name.name);

		if(d.baseClass)
		{
			visit(d.baseClass);
			fs.toSource(d.baseClass.location);
		}
		else
		{
			fs.pushNull();
			fs.toSource(d.location);
		}

		fs.newClass();
		*/

		return destReg;
	}

	public void classDefEnd(ClassDef d, uint destReg)
	{
		foreach(ref field; d.fields)
		{
			auto index = fs.tagConst(fs.codeStringConst(field.name));

			visit(field.initializer);
			Exp val;
			fs.popSource(field.initializer.endLocation.line, val);
			fs.codeR(field.initializer.endLocation.line, Op1.FieldAssign, destReg, index, val.index);
			fs.freeExpTempRegs(val);
		}

		/*
		foreach(ref field; d.fields)
		{
			fs.dup();
			fs.pushStringConst(field.name);
			fs.toSource();
			fs.field(field.name.location);
			visit(field.initializer);
			fs.toSource();
			fs.assign(field.name.location, 1, 1);
		}
		*/
	}

	public override NamespaceDef visit(NamespaceDef d)
	{
		auto reg = namespaceDefBegin(d);
		namespaceDefEnd(d, reg);
		fs.pushTempReg(reg);

		/*
		namespaceDefBegin(d);
		namespaceDefEnd(d);
		*/

		return d;
	}

	public uint namespaceDefBegin(NamespaceDef d)
	{
		auto destReg = fs.pushRegister();
		auto nameConst = fs.codeStringConst(d.name.name);

		if(d.parent is null)
		{
			fs.codeR(d.location.line, Op1.New, destReg, nameConst, 0);
			fs.codeR(d.location.line, Op2.NamespaceNP, 0, 0, 0);
		}
		else
		{
			visit(d.parent);
			Exp src;
			fs.popSource(d.location.line, src);
			fs.freeExpTempRegs(src);
			fs.codeR(d.location.line, Op1.New, destReg, nameConst, src.index);
			fs.codeR(d.location.line, Op2.Namespace, 0, 0, 0);
		}

		fs.beginNamespace(destReg);

		/*
		fs.pushStringConst(d.name.name);

		if(d.parent)
		{
			visit(d.parent);
			fs.toSource(d.parent.location);
			fs.newNamespace();
		}
		else
			fs.newNamespaceNP();
		
		fs.beginNamespace();
		*/

		return destReg;
	}

	public void namespaceDefEnd(NamespaceDef d, uint destReg)
	{
		foreach(ref field; d.fields)
		{
			auto index = fs.tagConst(fs.codeStringConst(field.name));

			visit(field.initializer);
			Exp val;
			fs.popSource(field.initializer.endLocation.line, val);
			fs.codeR(field.initializer.endLocation.line, Op1.FieldAssign, destReg, index, val.index);
			fs.freeExpTempRegs(val);
		}

		fs.endNamespace();

		/*
		foreach(ref field; d.fields)
		{
			fs.dup();
			fs.pushStringConst(field.name);
			fs.toSource();
			fs.field(field.name.location);
			visit(field.initializer);
			fs.toSource();
			fs.assign(field.name.location, 1, 1);
		}
		
		fs.endNamespace();
		*/
	}

	public override FuncDef visit(FuncDef d)
	{
		scope inner = new FuncState(c, d.location, d.name.name, fs);

		{
			fs = inner;
			scope(exit)
				fs = fs.mParent;

			fs.mIsVararg = d.isVararg;
			fs.mNumParams = d.params.length;

			Scope scop = void;
			fs.pushScope(scop);
				foreach(ref p; d.params)
				{
					fs.insertLocal(p.name);
					fs.mParamMasks.append(c.alloc, p.typeMask);
				}

				fs.activateLocals(d.params.length);

				visit(d.code);
				fs.codeI(d.code.endLocation.line, Op1.SaveRets, 0, 1);
				fs.codeI(d.code.endLocation.line, Op1.Ret, 0, 0);
			fs.popScope(d.code.endLocation.line);
		}

		auto destReg = fs.pushRegister();
		fs.codeClosure(inner, destReg);

		fs.pushTempReg(destReg);

		/*
		scope inner = new FuncState(c, d.location, d.name.name, fs);

		{
			fs = inner;
			scope(exit)
				fs = fs.mParent;

			fs.mIsVararg = d.isVararg;
			fs.mNumParams = d.params.length;

			Scope scop = void;
			fs.pushScope(scop);
				foreach(ref p; d.params)
					fs.addParam(p.name, p.typeMask);

				fs.activateLocals(d.params.length);

				visit(d.code);

				// fs.finalReturn(d.code.endLocation); or something?
				fs.codeI(d.code.endLocation, Op1.SaveRets, 0, 1);
				fs.codeI(d.code.endLocation, Op1.Ret, 0, 0);
			fs.popScope(d.code.endLocation);
		}

		fs.newClosure(inner);
		*/
		return d;
	}

	public override TypecheckStmt visit(TypecheckStmt s)
	{
		alias FuncDef.TypeMask TypeMask;
		bool needParamCheck = false;

		foreach(ref p; s.def.params)
		{
			if(p.typeMask != TypeMask.Any)
			{
				needParamCheck = true;
				break;
			}
		}

		if(needParamCheck)
			fs.codeI(s.def.code.location.line, Op1.CheckParams, 0, 0);
		
		/*
		if(s.def.params.any((ref Param p) { return p.typeMask != TypeMask.Any; }))
			fs.paramCheck(s.def.code.location);
		*/

		foreach(idx, ref p; s.def.params)
		{
			if(p.classTypes.length > 0)
			{
				InstRef success;

				foreach(t; p.classTypes)
				{
					visit(t);
					Exp src;
					fs.popSource(t.endLocation.line, src);
					fs.freeExpTempRegs(src);
					fs.codeR(t.endLocation.line, Op1.CheckObjParam, 0, fs.tagLocal(idx), src.index);
					fs.catToTrue(success, fs.makeJump(t.endLocation.line, Op2.Je));
				}

				fs.codeR(p.classTypes[$ - 1].endLocation.line, Op1.ParamFail, 0, fs.tagLocal(idx), 0);
				fs.codeR(p.classTypes[$ - 1].endLocation.line, Op2.ObjParamFail, 0, 0, 0);

				fs.patchTrueToHere(success);

				/*
				InstRef success;

				foreach(t; p.classTypes)
				{
					visit(t);
					fs.toSource(t.endLocation);
					fs.catToTrue(success, fs.checkObjParam(t.endLocation, idx));
				}

				fs.objParamFail(p.classTypes[$ - 1].endLocation, idx);
				fs.patchTrueToHere(success);
				*/
			}
			else if(p.customConstraint)
			{
				auto con = p.customConstraint;
				visit(con);
				Exp src;
				fs.popSource(con.endLocation.line, src);
				fs.freeExpTempRegs(src);
				fs.codeR(con.endLocation.line, Op1.IsTrue, 0, src.index, 0);
				InstRef success;
				fs.catToTrue(success, fs.makeJump(con.endLocation.line, Op2.Je));

				dottedNameToString(con.as!(CallExp).op);
				fs.codeR(con.endLocation.line, Op1.ParamFail, 0, fs.tagLocal(idx), fs.tagConst(fs.codeStringConst(getString(fs.t, -1))));
				fs.codeR(con.endLocation.line, Op2.CustomParamFail, 0, 0, 0);
				pop(fs.t);
				fs.patchTrueToHere(success);

				/*
				InstRef success;

				auto con = p.customConstraint;
				visit(con);
				fs.toSource(con.endLocation);
				fs.catToTrue(success, fs.isTrue(con.endLocation));

				dottedNameToString(con.as!(CallExp).op);
				fs.pushStringConst(getString(fs.t, -1));
				fs.toSource();
				fs.customParamFail(con.endLocation, idx);
				pop(fs.t);
				fs.patchTrueToHere(success);
				*/
			}
		}

		return s;
	}

	public word dottedNameToString(Expression exp)
	{
		int work(Expression exp)
		{
			if(auto n = exp.as!(IdentExp))
			{
				pushString(fs.t, n.name.name);
				return 1;
			}
			else if(auto n = exp.as!(DotExp))
			{
				auto ret = work(n.op);
				pushString(fs.t, ".");
				pushString(fs.t, n.name.as!(StringExp).value);
				return ret + 2;
			}
			else
				assert(false);
		}

		return cat(fs.t, work(exp));
	}

	public override ImportStmt visit(ImportStmt s)
	{
		assert(false);
	}

	public override ScopeStmt visit(ScopeStmt s)
	{
		Scope scop = void;
		fs.pushScope(scop);
		visit(s.statement);
		fs.popScope(s.endLocation.line);
		return s;
	}

	public override ExpressionStmt visit(ExpressionStmt s)
	{
		debug auto freeRegCheck = fs.mFreeReg;
		visit(s.expr);
		fs.popToNothing();
		debug assert(fs.mFreeReg == freeRegCheck, "not all regs freed");
		return s;
	}

	public void visitDecorator(Decorator d, void delegate() obj)
	{
		uword genArgs()
		{
			auto firstReg = fs.nextRegister();

			if(d.nextDec)
			{
				visitDecorator(d.nextDec, obj);
				fs.popMoveTo(d.nextDec.endLocation.line, firstReg);
			}
			else
			{
				obj();
				fs.popMoveTo(d.location.line, firstReg);
			}

			fs.pushRegister();
			codeGenListToNextReg(d.args);
			fs.popRegister(firstReg);

			if(d.args.length == 0)
				return 3;
			else if(d.args[$ - 1].isMultRet())
				return 0;
			else
				return d.args.length + 3;
				
			/*
			if(d.nextDec)
			{
				visitDecorator(d.nextDec, obj);
				fs.toSource(d.nextDec.endLocation);
			}
			else
			{
				obj();
				fs.toSource(d.location);
			}
			
			codeGenList(d.args);
			return d.args.length + 1; // 1 for nextDec/obj
			*/
		}

		if(auto dot = d.func.as!(DotExp))
		{
			if(d.context !is null)
				c.semException(d.location, "'with' is disallowed on method calls");
			visitMethodCall(d.location, d.endLocation, false, dot.op, dot.name, &genArgs);
		}
		else
			visitCall(d.endLocation, d.func, d.context, &genArgs);
	}

	public override FuncDecl visit(FuncDecl d)
	{
		if(d.protection == Protection.Local)
		{
			fs.insertLocal(d.def.name);
			fs.activateLocals(1);
			fs.pushVar(d.def.name);
		}
		else
		{
			assert(d.protection == Protection.Global);
			fs.pushNewGlobal(d.def.name);
		}

		visit(d.def);
		fs.popAssign(d.endLocation.line);

		if(d.decorator)
		{
			fs.pushVar(d.def.name);
			visitDecorator(d.decorator, { fs.pushVar(d.def.name); });
			fs.popAssign(d.endLocation.line);
		}

		/*
		if(d.protection == Protection.Local)
		{
			fs.insertLocal(d.def.name);
			fs.activateLocals(1);
			fs.pushVar(d.def.name);
		}
		else
		{
			assert(d.protection == Protection.Global);
			fs.pushNewGlobal(d.def.name);
		}

		visit(d.def);
		fs.assign(d.endLocation.line, 1, 1);

		if(d.decorator)
		{
			fs.pushVar(d.def.name);
			visitDecorator(d.decorator, { fs.pushVar(d.def.name); });
			fs.assign(d.endLocation.line, 1, 1);
		}
		*/

		return d;
	}

	public override ClassDecl visit(ClassDecl d)
	{
		if(d.protection == Protection.Local)
		{
			fs.insertLocal(d.def.name);
			fs.activateLocals(1);
			fs.pushVar(d.def.name);
		}
		else
		{
			assert(d.protection == Protection.Global);
			fs.pushNewGlobal(d.def.name);
		}

		// put empty class in d.name
		auto reg = classDefBegin(d.def);
		fs.pushTempReg(reg);
		fs.popAssign(d.location.line);

		// evaluate rest of decl
		auto checkReg = fs.pushRegister();
		assert(checkReg == reg, "register failcopter");
		classDefEnd(d.def, reg);
		fs.popRegister(reg);

		if(d.decorator)
		{
			// reassign decorated class into name
			fs.pushVar(d.def.name);
			visitDecorator(d.decorator, { fs.pushVar(d.def.name); });
			fs.popAssign(d.endLocation.line);
		}

		/*
		if(d.protection == Protection.Local)
		{
			fs.insertLocal(d.def.name);
			fs.activateLocals(1);
			fs.pushVar(d.def.name);
		}
		else
		{
			assert(d.protection == Protection.Global);
			fs.pushNewGlobal(d.def.name);
		}

		// put empty class in d.name
		classDefBegin(d.def);
		fs.assign(d.location, 1, 1);

		// evaluate rest of decl
		fs.pushVar(d.def.name);
		fs.toSource(d.def.location);
		classDefEnd(d.def);
		fs.pop();

		if(d.decorator)
		{
			// reassign decorated class into name
			fs.pushVar(d.def.name);
			visitDecorator(d.decorator, { fs.pushVar(d.def.name); });
			fs.assign(d.endLocation, 1, 1);
		}
		*/

		/*
		if(d.protection == Protection.Local)
		{
			fs.insertLocal(d.def.name);
			fs.activateLocals(1);
			fs.pushVar(d.def.name);
		}
		else
		{
			assert(d.protection == Protection.Global);
			fs.pushNewGlobal(d.def.name);
		}

		visit(d.def);
		fs.assign(d.endLocation.line, 1, 1);

		if(d.decorator)
		{
			fs.pushVar(d.def.name);
			visitDecorator(d.decorator, { fs.pushVar(d.def.name); });
			fs.assign(d.endLocation.line, 1, 1);
		}
		*/

		return d;
	}

	public override NamespaceDecl visit(NamespaceDecl d)
	{
		if(d.protection == Protection.Local)
		{
			fs.insertLocal(d.def.name);
			fs.activateLocals(1);
			fs.pushVar(d.def.name);
		}
		else
		{
			assert(d.protection == Protection.Global);
			fs.pushNewGlobal(d.def.name);
		}

		// put empty namespace in d.name
		auto reg = namespaceDefBegin(d.def);
		fs.pushTempReg(reg);
		fs.popAssign(d.location.line);

		// evaluate rest of decl
		auto checkReg = fs.pushRegister();
		assert(checkReg == reg, "register failcopter");
		namespaceDefEnd(d.def, reg);
		fs.popRegister(reg);

		if(d.decorator)
		{
			// reassign decorated namespace into name
			fs.pushVar(d.def.name);
			visitDecorator(d.decorator, { fs.pushVar(d.def.name); });
			fs.popAssign(d.endLocation.line);
		}

		/*
		if(d.protection == Protection.Local)
		{
			fs.insertLocal(d.def.name);
			fs.activateLocals(1);
			fs.pushVar(d.def.name);
		}
		else
		{
			assert(d.protection == Protection.Global);
			fs.pushNewGlobal(d.def.name);
		}

		// put empty class in d.name
		classDefBegin(d.def);
		fs.assign(d.location, 1, 1);

		// evaluate rest of decl
		fs.pushVar(d.def.name);
		fs.toSource(d.def.location);
		classDefEnd(d.def);
		fs.pop();

		if(d.decorator)
		{
			// reassign decorated class into name
			fs.pushVar(d.def.name);
			visitDecorator(d.decorator, { fs.pushVar(d.def.name); });
			fs.assign(d.endLocation, 1, 1);
		}
		*/

		return d;
	}

	public override NamespaceDecl visit(NamespaceDecl d)
	{
		if(d.protection == Protection.Local)
		{
			fs.insertLocal(d.def.name);
			fs.activateLocals(1);
			fs.pushVar(d.def.name);
		}
		else
		{
			assert(d.protection == Protection.Global);
			fs.pushNewGlobal(d.def.name);
		}

		// put empty namespace in d.name
		namespaceDefBegin(d.def);
		fs.assign(d.location, 1, 1);

		// evaluate rest of decl
		fs.pushVar(d.def.name);
		fs.toSource(d.def.location);
		namespaceDefEnd(d.def);
		fs.pop();

		if(d.decorator)
		{
			// reassign decorated namespace into name
			fs.pushVar(d.def.name);
			visitDecorator(d.decorator, { fs.pushVar(d.def.name); });
			fs.assign(d.endLocation, 1, 1);
		}
		*/

		/*
		if(d.protection == Protection.Local)
		{
			fs.insertLocal(d.def.name);
			fs.activateLocals(1);
			fs.pushVar(d.def.name);
		}
		else
		{
			assert(d.protection == Protection.Global);
			fs.pushNewGlobal(d.def.name);
		}

		// put empty namespace in d.name
		namespaceDefBegin(d.def);
		fs.assign(d.location, 1, 1);

		// evaluate rest of decl
		fs.pushVar(d.def.name);
		fs.toSource(d.def.location);
		namespaceDefEnd(d.def);
		fs.pop();

		if(d.decorator)
		{
			// reassign decorated namespace into name
			fs.pushVar(d.def.name);
			visitDecorator(d.decorator, { fs.pushVar(d.def.name); });
			fs.assign(d.endLocation, 1, 1);
		}
		*/

		return d;
	}

	public override VarDecl visit(VarDecl d)
	{
		// Check for name conflicts within the definition
		foreach(i, n; d.names)
		{
			foreach(n2; d.names[0 .. i])
			{
				if(n.name == n2.name)
				{
					auto loc = n2.location;
					c.semException(n.location, "Variable '{}' conflicts with previous definition at {}({}:{})", n.name, loc.file, loc.line, loc.col);
				}
			}
		}

		if(d.protection == Protection.Global)
		{
			if(d.initializer.length > 0)
			{
				if(d.names.length == 1 && d.initializer.length == 1)
				{
					fs.pushNewGlobal(d.names[0]);
					visit(d.initializer[0]);
					fs.popAssign(d.initializer[0].endLocation.line);
				}
				else
				{
					foreach(n; d.names)
						fs.pushNewGlobal(n);

					auto RHSReg = fs.nextRegister();
					codeGenAssignmentList(d.initializer, d.names.length);

					for(int reg = RHSReg + d.names.length - 1; reg >= cast(int)RHSReg; reg--)
						fs.popMoveFromReg(d.endLocation.line, reg);
				}
			}
			else
			{
				foreach(n; d.names)
				{
					fs.pushNewGlobal(n);
					fs.pushNull();
					fs.popAssign(n.location.line);
					// fs.assign(n.location, 1, 1);
				}
			}
			
			/*
			foreach(n; d.names)
				fs.pushNewGlobal(n);

			codeGenList(d.initializer);
			fs.assign(d.location, d.names.length, d.initializer.length);
			*/
		}
		else
		{
			assert(d.protection == Protection.Local);

			if(d.initializer.length > 0)
			{
				if(d.names.length == 1 && d.initializer.length == 1)
				{
					auto destReg = fs.nextRegister();
					visit(d.initializer[0]);
					fs.popMoveTo(d.location.line, destReg);
					fs.insertLocal(d.names[0]);
				}
				else
				{
					auto destReg = fs.nextRegister();
					codeGenAssignmentList(d.initializer, d.names.length);

					foreach(n; d.names)
						fs.insertLocal(n);
				}
			}
			else
			{
				auto reg = fs.nextRegister();

				foreach(n; d.names)
					fs.insertLocal(n);

				fs.codeNulls(d.location.line, reg, d.names.length);
			}

			fs.activateLocals(d.names.length);

			/*
			fs.pushNewLocals(d.names.length);
			codeGenList(d.initializer);
			fs.assign(d.location, d.names.length, d.initializer.length);
			
			foreach(n; d.names)
				fs.insertLocal(n);

			fs.activateLocals(d.names.length);
			*/
		}

		return d;
	}

	public override BlockStmt visit(BlockStmt s)
	{
		foreach(st; s.statements)
			visit(st);

		return s;
	}

	public override IfStmt visit(IfStmt s)
	{
		if(s.elseBody)
			visitIf(s.location, s.endLocation, s.elseBody.location, s.condVar, s.condition, { visit(s.ifBody); }, { visit(s.elseBody); });
		else
			visitIf(s.location, s.endLocation, s.endLocation, s.condVar, s.condition, { visit(s.ifBody); }, null);

		return s;
	}

	public void visitIf(CompileLoc location, CompileLoc endLocation, CompileLoc elseLocation, IdentExp condVar, Expression condition, void delegate() genBody, void delegate() genElse)
	{
		Scope scop = void;
		fs.pushScope(scop);

		InstRef i = void;

		if(condVar !is null)
		{
			auto destReg = fs.nextRegister();
			visit(condition);
			fs.popMoveTo(location.line, destReg);
			fs.insertLocal(condVar.name);
			fs.activateLocals(1);

			i = codeCondition(condVar);
		}
		else
			i = codeCondition(condition);

		fs.invertJump(i);
		fs.patchTrueToHere(i);
		genBody();

		if(genElse !is null)
		{
			fs.popScope(elseLocation.line);

			auto j = fs.makeJump(elseLocation.line);
			fs.patchFalseToHere(i);

			fs.pushScope(scop);
				genElse();
			fs.popScope(endLocation.line);

			fs.patchJumpToHere(j);
		}
		else
		{
			fs.popScope(endLocation.line);
			fs.patchFalseToHere(i);
		}

		/*
		Scope scop = void;
		fs.pushScope(scop);

		InstRef i = void;

		if(condVar !is null)
		{
			fs.pushNewLocals(1);
			visit(condition);
			fs.assign(condition.location, 1, 1);
			fs.insertLocal(condVar.name);
			fs.activateLocals(1);

			i = codeCondition(condVar);
		}
		else
			i = codeCondition(condition);

		fs.invertJump(i);
		fs.patchTrueToHere(i);
		genBody();

		if(genElse !is null)
		{
			fs.popScope(elseLocation.line);

			auto j = fs.makeJump(elseLocation.line);
			fs.patchFalseToHere(i);

			fs.pushScope(scop);
				genElse();
			fs.popScope(endLocation.line);

			fs.patchJumpToHere(j);
		}
		else
		{
			fs.popScope(endLocation.line);
			fs.patchFalseToHere(i);
		}
		*/
	}

	public override WhileStmt visit(WhileStmt s)
	{
		auto beginLoop = fs.here();

		Scope scop = void;
		fs.pushScope(scop);

		// s.condition.isConstant && !s.condition.isTrue is handled in semantic
		if(s.condition.isConstant && s.condition.isTrue)
		{
			if(s.condVar !is null)
			{
				fs.setBreakable();
				fs.setContinuable();
				fs.setScopeName(s.name);

				auto destReg = fs.nextRegister();
				visit(s.condition);
				fs.popMoveTo(s.location.line, destReg);
				fs.insertLocal(s.condVar.name);
				fs.activateLocals(1);

				visit(s.code);
				fs.patchContinuesTo(beginLoop);
				fs.codeJump(s.endLocation.line, beginLoop);
				fs.patchBreaksToHere();
			}
			else
			{
				fs.setBreakable();
				fs.setContinuable();
				fs.setScopeName(s.name);
				visit(s.code);
				fs.patchContinuesTo(beginLoop);
				fs.codeJump(s.endLocation.line, beginLoop);
				fs.patchBreaksToHere();
			}

			fs.popScope(s.endLocation.line);
		}
		else
		{
			InstRef cond = void;

			if(s.condVar !is null)
			{
				auto destReg = fs.nextRegister();
				visit(s.condition);
				fs.popMoveTo(s.location.line, destReg);
				fs.insertLocal(s.condVar.name);
				fs.activateLocals(1);

				cond = codeCondition(s.condVar);
			}
			else
				cond = codeCondition(s.condition);

			fs.invertJump(cond);
			fs.patchTrueToHere(cond);

			fs.setBreakable();
			fs.setContinuable();
			fs.setScopeName(s.name);
			visit(s.code);
			fs.patchContinuesTo(beginLoop);
			fs.closeUpvals(s.endLocation.line);
			fs.codeJump(s.endLocation.line, beginLoop);
			fs.patchBreaksToHere();

			fs.popScope(s.endLocation.line);
			fs.patchFalseToHere(cond);
		}
		
		/*
		auto beginLoop = fs.here();

		Scope scop = void;
		fs.pushScope(scop);

		// s.condition.isConstant && !s.condition.isTrue is handled in semantic
		if(s.condition.isConstant && s.condition.isTrue)
		{
			fs.setBreakable();
			fs.setContinuable();
			fs.setScopeName(s.name);

			if(s.condVar !is null)
			{
				fs.pushNewLocals(1);
				visit(s.condition);
				fs.assign(s.condition.location, 1, 1);
				fs.insertLocal(s.condVar.name);
				fs.activateLocals(1);
			}

			visit(s.code);
			fs.patchContinuesTo(beginLoop);
			fs.codeJump(s.endLocation.line, beginLoop);
			fs.patchBreaksToHere();
			fs.popScope(s.endLocation.line);
		}
		else
		{
			InstRef cond = void;

			if(s.condVar !is null)
			{
				fs.pushNewLocals(1);
				visit(s.condition);
				fs.assign(s.condition.location, 1, 1);
				fs.insertLocal(s.condVar.name);
				fs.activateLocals(1);

				cond = codeCondition(s.condVar);
			}
			else
				cond = codeCondition(s.condition);

			fs.invertJump(cond);
			fs.patchTrueToHere(cond);

			fs.setBreakable();
			fs.setContinuable();
			fs.setScopeName(s.name);
			visit(s.code);
			fs.patchContinuesTo(beginLoop);
			fs.closeUpvals(s.endLocation.line);
			fs.codeJump(s.endLocation.line, beginLoop);
			fs.patchBreaksToHere();

			fs.popScope(s.endLocation.line);
			fs.patchFalseToHere(cond);
		}
		*/

		return s;
	}
	
	public override DoWhileStmt visit(DoWhileStmt s)
	{
		auto beginLoop = fs.here();
		Scope scop = void;
		fs.pushScope(scop);

		fs.setBreakable();
		fs.setContinuable();
		fs.setScopeName(s.name);
		visit(s.code);

		if(s.condition.isConstant && s.condition.isTrue)
		{
			fs.patchContinuesToHere();
			fs.codeJump(s.endLocation.line, beginLoop);
			fs.patchBreaksToHere();

			fs.popScope(s.endLocation.line);
		}
		else
		{
			fs.closeUpvals(s.condition.location.line);
			fs.patchContinuesToHere();

			auto cond = codeCondition(s.condition);
			fs.invertJump(cond);
			fs.patchTrueToHere(cond);
			fs.codeJump(s.endLocation.line, beginLoop);
			fs.patchBreaksToHere();

			fs.popScope(s.endLocation.line);
			fs.patchFalseToHere(cond);
		}

		return s;
	}

	public override ForStmt visit(ForStmt s)
	{
		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();
			fs.setContinuable();
			fs.setScopeName(s.name);

			foreach(init; s.init)
			{
				if(init.isDecl)
					visit(init.decl);
				else
				{
					visit(init.stmt);
					fs.popToNothing();
				}
			}

			auto beginLoop = fs.here();
			InstRef cond = void;

			if(s.condition)
			{
				cond = codeCondition(s.condition);
				fs.invertJump(cond);
				fs.patchTrueToHere(cond);
			}

			visit(s.code);

			fs.closeUpvals(s.location.line);
			fs.patchContinuesToHere();

			foreach(inc; s.increment)
			{
				visit(inc);
				fs.popToNothing();
			}

			fs.codeJump(s.endLocation.line, beginLoop);
			fs.patchBreaksToHere();
		fs.popScope(s.endLocation.line);

		if(s.condition)
			fs.patchFalseToHere(cond);

		return s;
	}

	public override ForNumStmt visit(ForNumStmt s)
	{
		visitForNum(s.location, s.endLocation, s.name, s.lo, s.hi, s.step, s.index, { visit(s.code); });
		return s;
	}

	public void visitForNum(CompileLoc location, CompileLoc endLocation, char[] name, Expression lo, Expression hi, Expression step, Identifier index, void delegate() genBody)
	{
		auto baseReg = fs.nextRegister();

		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();
			fs.setContinuable();
			fs.setScopeName(name);

			auto loIndex = fs.nextRegister();
			visit(lo);
			fs.popMoveTo(lo.location.line, loIndex);
			fs.pushRegister();

			auto hiIndex = fs.nextRegister();
			visit(hi);
			fs.popMoveTo(hi.location.line, hiIndex);
			fs.pushRegister();

			auto stepIndex = fs.nextRegister();
			visit(step);
			fs.popMoveTo(step.location.line, stepIndex);
			fs.pushRegister();

			auto beginJump = fs.makeFor(location.line, baseReg);
			auto beginLoop = fs.here();

			fs.insertLocal(index);
			fs.activateLocals(1);

			genBody();

			fs.closeUpvals(endLocation.line);
			fs.patchContinuesToHere();

			fs.patchJumpToHere(beginJump);

			auto gotoBegin = fs.makeForLoop(endLocation.line, baseReg);
			fs.patchJumpTo(gotoBegin, beginLoop);

			fs.patchBreaksToHere();
		fs.popScope(endLocation.line);

		fs.popRegister(stepIndex);
		fs.popRegister(hiIndex);
		fs.popRegister(loIndex);

		/*
		struct ForDesc
		{
			uint baseReg;
			uint beginJump;
			uint beginLoop;
		}

		ForDesc beginFor(CompileLoc loc, void delegate() dg)
		{
			return beginForImpl(loc, dg, Op1.For, 3);
		}

		ForDesc beginForeach(CompileLoc loc, void delegate() dg, uint containerSize)
		{
			return beginForImpl(loc, dg, Op1.Foreach, containerSize);
		}

		ForDesc beginForImpl(CompileLoc loc, void delegate() dg, Op1 opcode, uint containerSize);
		{
			ForDesc ret;
			ret.baseReg = mFreeReg;
			pushNewLocals(3);
			dg();
			assign(loc, 3, containerSize);
			reserveRegs(3);
			ret.beginJump = codeI(loc, opcode, ret.baseReg, NoJump);
			ret.beginLoop = here();
			return ret;
		}

		void endFor(CompileLoc loc, ForDesc desc)
		{
			endForImpl(loc, desc, Op1.ForLoop, 0);
		}

		void endForeach(CompileLoc loc, ForDesc desc, uint indLength)
		{
			endForImpl(loc, desc, Op1.ForeachLoop, indLength);
		}

		void endForImpl(CompileLoc loc, ForDesc desc, Op1 opcode, uint indLength)
		{
			closeUpvals(loc);
			patchContinuesToHere();
			patchJumpToHere(desc.beginJump);

			uint j;

			if(opcode == Op1.ForLoop)
				j = codeJ(loc, opcode, ret.baseReg, NoJump);
			else
			{
				codeI(loc, opcode, ret.baseReg, indLength);
				j = makeJump(loc, Op1.Je);
			}

			patchJumpTo(j, desc.beginLoop);
			patchBreaksToHere();

			mFreeReg = desc.baseReg;
		}

		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();
			fs.setContinuable();
			fs.setScopeName(name);

			auto forDesc = fs.beginFor(location, { visit(lo); visit(hi); visit(step); });

			fs.insertLocal(index);
			fs.activateLocals(1);
			genBody();

			fs.endFor(endLocation, forDesc);
		fs.popScope(endLocation.line);
		*/
	}

	public override ForeachStmt visit(ForeachStmt s)
	{
		visitForeach(s.location, s.endLocation, s.name, s.indices, s.container, { visit(s.code); });
		return s;
	}

	public void visitForeach(CompileLoc location, CompileLoc endLocation, char[] name, Identifier[] indices, Expression[] container, void delegate() genBody)
	{
		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();
			fs.setContinuable();
			fs.setScopeName(name);

			auto baseReg = fs.nextRegister();
			auto generator = baseReg;
			visit(container[0]);

			uint invState = void;
			uint control = void;

			if(container.length == 3)
			{
				fs.popMoveTo(container[0].location.line, generator);
				fs.pushRegister();

				invState = fs.nextRegister();
				visit(container[1]);
				fs.popMoveTo(container[1].location.line, invState);
				fs.pushRegister();

				control = fs.nextRegister();
				visit(container[2]);
				fs.popMoveTo(container[2].location.line, control);
				fs.pushRegister();
			}
			else if(container.length == 2)
			{
				fs.popMoveTo(container[0].location.line, generator);
				fs.pushRegister();

				invState = fs.nextRegister();
				visit(container[1]);

				if(container[1].isMultRet())
				{
					fs.popToRegisters(container[1].location.line, invState, 2);
					fs.pushRegister();
					control = fs.pushRegister();
				}
				else
				{
					fs.popMoveTo(container[1].location.line, invState);
					fs.pushRegister();
					control = fs.pushRegister();
					fs.codeNulls(container[1].location.line, control, 1);
				}
			}
			else
			{
				if(container[0].isMultRet())
				{
					fs.popToRegisters(container[0].location.line, generator, 3);
					fs.pushRegister();
					invState = fs.pushRegister();
					control = fs.pushRegister();
				}
				else
				{
					fs.popMoveTo(container[0].location.line, generator);
					fs.pushRegister();
					invState = fs.pushRegister();
					control = fs.pushRegister();
					fs.codeNulls(container[0].endLocation.line, invState, 2);
				}
			}

			auto beginJump = fs.makeForeach(location.line, baseReg);
			auto beginLoop = fs.here();

			foreach(i; indices)
				fs.insertLocal(i);

			fs.activateLocals(indices.length);
			genBody();

			fs.closeUpvals(endLocation.line);
			fs.patchContinuesToHere();

			fs.patchJumpToHere(beginJump);

			fs.codeI(endLocation.line, Op1.ForeachLoop, baseReg, indices.length);
			auto gotoBegin = fs.makeJump(endLocation.line, Op2.Je);

			fs.patchJumpTo(gotoBegin, beginLoop);

			fs.patchBreaksToHere();
		fs.popScope(endLocation.line);

		fs.popRegister(control);
		fs.popRegister(invState);
		fs.popRegister(generator);

		/*
		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();
			fs.setContinuable();
			fs.setScopeName(name);

			auto desc = fs.beginForeach(location, { codeGenList(container); }, container.length);

			foreach(i; indices)
				fs.insertLocal(i);

			fs.activateLocals(indices.length);
			genBody();

			fs.endForeach(endLocation, desc, indices.length);
		fs.popScope(endLocation.line);

		fs.popRegister(control);
		fs.popRegister(invState);
		fs.popRegister(generator);
		*/
	}

	public override SwitchStmt visit(SwitchStmt s)
	{
		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();
			fs.setScopeName(s.name);

			visit(s.condition);
			Exp src1;
			fs.popSource(s.condition.location.line, src1);

			foreach(caseStmt; s.cases)
			{
				if(caseStmt.highRange)
				{
					auto c = &caseStmt.conditions[0];
					auto lo = c.exp;
					auto hi = caseStmt.highRange;

					visit(lo);
					Exp src2;
					fs.popSource(lo.location.line, src2);
					fs.freeExpTempRegs(src2);

					fs.codeR(lo.location.line, Op1.Cmp, 0, src1.index, src2.index);
					auto jmp1 = fs.makeJump(lo.location.line, Op2.Jlt, true);

					visit(hi);
					src2 = Exp.init;
					fs.popSource(hi.location.line, src2);
					fs.freeExpTempRegs(src2);

					fs.codeR(hi.location.line, Op1.Cmp, 0, src1.index, src2.index);
					auto jmp2 = fs.makeJump(hi.location.line, Op2.Jle, false);

					c.dynJump = fs.makeJump(c.exp.location.line, Op1.Jmp, true);

					fs.patchJumpToHere(jmp1);
					fs.patchJumpToHere(jmp2);
				}
				else
				{
					foreach(ref c; caseStmt.conditions)
					{
						if(!c.exp.isConstant)
						{
							visit(c.exp);
							Exp src2;
							fs.popSource(c.exp.location.line, src2);
							fs.freeExpTempRegs(src2);

							fs.codeR(c.exp.location.line, Op1.SwitchCmp, 0, src1.index, src2.index);
							c.dynJump = fs.makeJump(c.exp.location.line, Op2.Je, true);
						}
					}
				}
			}

			fs.freeExpTempRegs(src1);

			SwitchDesc sdesc;
			fs.beginSwitch(sdesc, s.location.line, src1.index);

			foreach(c; s.cases)
				visit(c);

			if(s.caseDefault)
				visit(s.caseDefault);

			fs.endSwitch();
			fs.patchBreaksToHere();
		fs.popScope(s.endLocation.line);
		
		/*
		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();
			fs.setScopeName(s.name);

			visit(s.condition);
			fs.toSource();

			foreach(caseStmt; s.cases)
			{
				if(caseStmt.highRange)
				{
					auto c = &caseStmt.conditions[0];
					auto lo = c.exp;
					auto hi = caseStmt.highRange;

					fs.dup();
					visit(lo);
					fs.toSource();

					auto jmp1 = fs.codeCmp(lo.location, Op2.Jlt, true);

					fs.dup();
					visit(hi);
					fs.toSource();

					auto jmp2 = fs.codeCmp(hi.location, Op2.Jle, false);

					c.dynJump = fs.makeJump(lo.location, Op1.Jmp, true);

					fs.patchJumpToHere(jmp1);
					fs.patchJumpToHere(jmp2);
				}
				else
				{
					foreach(ref c; caseStmt.conditions)
					{
						if(!c.exp.isConstant)
						{
							fs.dup();
							visit(c.exp);
							fs.toSource();
							c.dynJump = fs.codeSwitchCmp(c.exp.location);
						}
					}
				}
			}

			SwitchDesc sdesc;
			fs.beginSwitch(sdesc, s.location); // pops the condition exp off the stack

			foreach(c; s.cases)
				visit(c);

			if(s.caseDefault)
				visit(s.caseDefault);

			fs.endSwitch();
			fs.patchBreaksToHere();
		fs.popScope(s.endLocation);
		*/

		return s;
	}

	public override CaseStmt visit(CaseStmt s)
	{
		if(s.highRange)
			fs.patchJumpToHere(s.conditions[0].dynJump);
		else
		{
			foreach(c; s.conditions)
			{
				if(c.exp.isConstant)
					fs.addCase(c.exp.location, c.exp);
				else
					fs.patchJumpToHere(c.dynJump);
			}
		}

		visit(s.code);
		return s;
	}

	public override DefaultStmt visit(DefaultStmt s)
	{
		fs.addDefault(s.location);
		visit(s.code);
		return s;
	}

	public override ContinueStmt visit(ContinueStmt s)
	{
		fs.codeContinue(s.location, s.name);
		return s;
	}

	public override BreakStmt visit(BreakStmt s)
	{
		fs.codeBreak(s.location, s.name);
		return s;
	}

	public override ReturnStmt visit(ReturnStmt s)
	{
		auto firstReg = fs.nextRegister();

		if(!fs.inTryCatch() && s.exprs.length == 1 && (s.exprs[0].type == AstTag.CallExp || s.exprs[0].type == AstTag.MethodCallExp))
		{
			visit(s.exprs[0]);
			fs.popToRegisters(s.endLocation.line, firstReg, -1);
			fs.makeTailcall();
			fs.codeI(s.endLocation.line, Op1.SaveRets, firstReg, 0);
			fs.codeI(s.endLocation.line, Op1.Ret, 0, 0);
		}
		else
		{
			codeGenListToNextReg(s.exprs);

			if(s.exprs.length == 0)
				fs.codeI(s.endLocation.line, Op1.SaveRets, 0, 1);
			else if(s.exprs[$ - 1].isMultRet())
				fs.codeI(s.endLocation.line, Op1.SaveRets, firstReg, 0);
			else
				fs.codeI(s.endLocation.line, Op1.SaveRets, firstReg, s.exprs.length + 1);

			if(fs.inTryCatch())
				fs.codeI(s.endLocation.line, Op1.Unwind, 0, fs.mTryCatchDepth);

			fs.codeI(s.endLocation.line, Op1.Ret, 0, 0);
		}

		/*
		if(!fs.inTryCatch() && s.exprs.length == 1 && (s.exprs[0].type == AstTag.CallExp || s.exprs[0].type == AstTag.MethodCallExp))
		{
			fs.pushSaveRets();
			visit(s.exprs[0]);
			fs.assign(1, 1);
			fs.makeTailcall();

			// again, finalReturn or something
			fs.codeI(s.endLocation.line, Op1.SaveRets, firstReg, 0);
			fs.codeI(s.endLocation.line, Op1.Ret, 0, 0);
		}
		else
		{
			fs.pushSaveRets();
			codeGenList(s.exprs);
			fs.assign(1, s.exprs.length);

			if(fs.inTryCatch())
				fs.codeUnwind(s.endLocation);

			fs.codeRet(s.endLocation);
		}
		*/

		return s;
	}

	public override TryCatchStmt visit(TryCatchStmt s)
	{
		uint checkReg1;
		Scope scop = void;
		auto pushCatch = fs.codeCatch(s.location.line, scop, checkReg1);

		visit(s.tryBody);

		fs.codeI(s.tryBody.endLocation.line, Op1.PopEH, 0, 0);
		fs.codeR(s.tryBody.endLocation.line, Op2.Catch, 0, 0, 0);
		auto jumpOverCatch = fs.makeJump(s.tryBody.endLocation.line);
		fs.patchJumpToHere(pushCatch);
		fs.endCatchScope(s.transformedCatch.location.line);

		fs.pushScope(scop);
			auto checkReg2 = fs.insertLocal(s.hiddenCatchVar);

			assert(checkReg1 == checkReg2, "catch var register is not right");

			fs.activateLocals(1);
			visit(s.transformedCatch);
		fs.popScope(s.transformedCatch.endLocation.line);

		fs.patchJumpToHere(jumpOverCatch);

		/*
		Scope scop = void;
		auto pushCatch = fs.codeCatch(s.location, scop);

		visit(s.tryBody);

		fs.popCatch(s.tryBody.endLocation);

		auto jumpOverCatch = fs.makeJump(s.tryBody.endLocation);
		fs.patchJumpToHere(pushCatch);
		fs.endCatchScope(s.transformedCatch.location);

		fs.pushScope(scop);
			fs.insertLocal(s.hiddenCatchVar);
			fs.activateLocals(1);
			visit(s.transformedCatch);
		fs.popScope(s.transformedCatch.endLocation);

		fs.patchJumpToHere(jumpOverCatch);
		*/

		return s;
	}

	public override TryFinallyStmt visit(TryFinallyStmt s)
	{
		Scope scop = void;
		auto pushFinally = fs.codeFinally(s.location.line, scop);

		visit(s.tryBody);

		fs.codeI(s.tryBody.endLocation.line, Op1.PopEH, 0, 0);
		fs.codeR(s.tryBody.endLocation.line, Op2.Finally, 0, 0, 0);
		fs.patchJumpToHere(pushFinally);
		fs.endFinallyScope(s.finallyBody.location.line);

		fs.pushScope(scop);
			visit(s.finallyBody);
			fs.codeI(s.finallyBody.endLocation.line, Op1.EndFinal, 0, 0);
		fs.popScope(s.finallyBody.endLocation.line);
		
		/*
		Scope scop = void;
		auto pushFinally = fs.codeFinally(s.location.line, scop);

		visit(s.tryBody);

		fs.popFinally(s.tryBody.endLocation);

		fs.patchJumpToHere(pushFinally);
		fs.endFinallyScope(s.finallyBody.location);

		fs.pushScope(scop);
			visit(s.finallyBody);
			fs.endFinal();
		fs.popScope(s.finallyBody.endLocation.line);
		*/

		return s;
	}

	public override ThrowStmt visit(ThrowStmt s)
	{
		visit(s.exp);
		Exp src;
		fs.popSource(s.location.line, src);
		fs.freeExpTempRegs(src);
		fs.codeR(s.endLocation.line, Op1.Throw, 0, src.index, s.rethrowing ? 1 : 0);

		/*
		visit(s.exp);
		fs.toSource();
		fs.codeThrow(s.endLocation, s.rethrowing);
		*/

		return s;
	}

	public override AssignStmt visit(AssignStmt s)
	{
		foreach(exp; s.lhs)
			exp.checkLHS(c);

		if(s.lhs.length == 1 && s.rhs.length == 1)
		{
			visit(s.lhs[0]);
			visit(s.rhs[0]);
			fs.popAssign(s.endLocation.line);
		}
		else
		{
			foreach(dest; s.lhs)
				visit(dest);

			auto numTemps = fs.resolveAssignmentConflicts(s.lhs[$ - 1].location.line, s.lhs.length);
			auto RHSReg = fs.nextRegister();

			codeGenAssignmentList(s.rhs, s.lhs.length);
			fs.popAssignmentConflicts(numTemps);

			for(int reg = RHSReg + s.lhs.length - 1; reg >= cast(int)RHSReg; reg--)
				fs.popMoveFromReg(s.endLocation.line, reg);
		}

		/*
		foreach(exp; s.lhs)
			exp.checkLHS(c);

		foreach(dest; s.lhs)
			visit(dest);

		fs.resolveAssignmentConflicts(s.lhs[$ - 1].location, s.lhs.length);

		codeGenList(s.rhs);
		fs.assign(s.lhs.length; s.rhs.length);
		*/

		return s;
	}

	public OpAssignStmt visitOpAssign(OpAssignStmt s)
	{
		if(s.lhs.type != AstTag.ThisExp)
			s.lhs.checkLHS(c);

		visit(s.lhs);
		fs.pushSource(s.lhs.endLocation.line);

		Exp src1;
		fs.popSource(s.lhs.endLocation.line, src1);
		visit(s.rhs);
		Exp src2;
		fs.popSource(s.endLocation.line, src2);

		fs.freeExpTempRegs(src2);
		fs.freeExpTempRegs(src1);

		fs.popReflexOp(s.endLocation.line, s.type, src1.index, src2.index);
		
		/*
		if(s.lhs.type != AstTag.ThisExp)
			s.lhs.checkLHS(c);

		visit(s.lhs);
		fs.dup();
		fs.toSource(s.lhs.endLocation);

		visit(s.rhs);
		fs.toSource(s.rhs.endLocation);

		fs.reflexOp(s.endLocation, s.type, 1);
		fs.assign(s.endLocation, 1, 1);
		*/

		return s;
	}

	public override AddAssignStmt  visit(AddAssignStmt s)  { return visitOpAssign(s); }
	public override SubAssignStmt  visit(SubAssignStmt s)  { return visitOpAssign(s); }
	public override MulAssignStmt  visit(MulAssignStmt s)  { return visitOpAssign(s); }
	public override DivAssignStmt  visit(DivAssignStmt s)  { return visitOpAssign(s); }
	public override ModAssignStmt  visit(ModAssignStmt s)  { return visitOpAssign(s); }
	public override ShlAssignStmt  visit(ShlAssignStmt s)  { return visitOpAssign(s); }
	public override ShrAssignStmt  visit(ShrAssignStmt s)  { return visitOpAssign(s); }
	public override UShrAssignStmt visit(UShrAssignStmt s) { return visitOpAssign(s); }
	public override XorAssignStmt  visit(XorAssignStmt s)  { return visitOpAssign(s); }
	public override OrAssignStmt   visit(OrAssignStmt s)   { return visitOpAssign(s); }
	public override AndAssignStmt  visit(AndAssignStmt s)  { return visitOpAssign(s); }

	public override CondAssignStmt visit(CondAssignStmt s)
	{
		visit(s.lhs);
		fs.pushSource(s.lhs.endLocation.line);
		Exp src1;
		fs.popSource(s.lhs.endLocation.line, src1);

		fs.codeR(s.lhs.endLocation.line, Op1.Is, 0, src1.index, fs.tagConst(fs.codeNullConst()));
		auto i = fs.makeJump(s.lhs.endLocation.line, Op2.Je, false);

		visit(s.rhs);
		Exp src2;
		fs.popSource(s.endLocation.line, src2);

		fs.freeExpTempRegs(src2);
		fs.freeExpTempRegs(src1);

		fs.popReflexOp(s.endLocation.line, s.type, src1.index, src2.index);

		fs.patchJumpToHere(i);

		/*
		visit(s.lhs);
		fs.dup();
		fs.toSource(s.lhs.endLocation);
		fs.pushNull();

		auto i = fs.codeIs(s.lhs.endLocation);

		visit(s.rhs);
		fs.toSource();
		
		fs.reflexOp(s.endLocation, s.type, 1);
		fs.assign(s.endLocation, 1, 1);

		fs.patchJumpToHere(i);
		*/

		return s;
	}

	public override CatAssignStmt visit(CatAssignStmt s)
	{
		assert(s.collapsed, "CatAssignStmt codeGen not collapsed");
		assert(s.operands.length >= 1, "CatAssignStmt codeGen not enough ops");

		if(s.lhs.type != AstTag.ThisExp)
			s.lhs.checkLHS(c);

		visit(s.lhs);
		fs.pushSource(s.lhs.endLocation.line);

		Exp src1;
		fs.popSource(s.lhs.endLocation.line, src1);

		auto firstReg = fs.nextRegister();
		codeGenListToNextReg(s.operands, false);

		fs.freeExpTempRegs(src1);
		fs.popReflexOp(s.endLocation.line, s.type, src1.index, firstReg, s.operands.length);

		/*
		if(s.lhs.type != AstTag.ThisExp)
			s.lhs.checkLHS(c);

		visit(s.lhs);
		fs.dup();
		fs.toSource(s.lhs.endLocation);

		codeGenList(s.operands, false);
		
		fs.reflexOp(s.endLocation, s.type, s.operands.length);
		fs.assign(s.endLocation, 1, 1);
		*/

		return s;
	}

	public override IncStmt visit(IncStmt s)
	{
		if(s.exp.type != AstTag.ThisExp)
			s.exp.checkLHS(c);

		visit(s.exp);
		fs.pushSource(s.exp.endLocation.line);

		Exp src;
		fs.popSource(s.exp.endLocation.line, src);
		fs.freeExpTempRegs(src);

		fs.popReflexOp(s.endLocation.line, s.type, src.index, 0);
		
		/*
		if(s.exp.type != AstTag.ThisExp)
			s.exp.checkLHS(c);

		visit(s.exp);
		fs.dup();
		fs.toSource(s.exp.endLocation);

		fs.reflexOp(s.endLocation.line, s.type, 0);
		fs.assign(1, 1);
		*/

		return s;
	}

	public override DecStmt visit(DecStmt s)
	{
		if(s.exp.type != AstTag.ThisExp)
			s.exp.checkLHS(c);

		visit(s.exp);
		fs.pushSource(s.exp.endLocation.line);

		Exp src;
		fs.popSource(s.exp.endLocation.line, src);
		fs.freeExpTempRegs(src);

		fs.popReflexOp(s.endLocation.line, s.type, src.index, 0);

		/*
		if(s.exp.type != AstTag.ThisExp)
			s.exp.checkLHS(c);

		visit(s.exp);
		fs.dup();
		fs.toSource(s.exp.endLocation);

		fs.reflexOp(s.endLocation.line, s.type, 0);
		fs.assign(1, 1);
		*/

		return s;
	}

	public override CondExp visit(CondExp e)
	{
		auto temp = fs.pushRegister();

		auto c = codeCondition(e.cond);
		fs.invertJump(c);
		fs.patchTrueToHere(c);

		visit(e.op1);
		fs.popMoveTo(e.op1.endLocation.line, temp);
		auto i = fs.makeJump(e.op1.endLocation.line, Op1.Jmp);

		fs.patchFalseToHere(c);

		visit(e.op2);
		fs.popMoveTo(e.endLocation.line, temp);
		fs.patchJumpToHere(i);

		fs.pushTempReg(temp);
		
		/*
		fs.pushNewLocals(1);

		auto c = codeCondition(e.cond);
		fs.invertJump(c);
		fs.patchTrueToHere(c);

		fs.dup();
		visit(e.op1);
		fs.assign(1, 1);

		auto i = fs.makeJump(e.op1.endLocation.line, Op1.Jmp);

		fs.patchFalseToHere(c);

		fs.dup();
		visit(e.op2);
		fs.assign(1, 1);

		fs.patchJumpToHere(i);
		fs.toTemporary();
		*/

		return e;
	}

	public override OrOrExp visit(OrOrExp e)
	{
		auto temp = fs.pushRegister();
		visit(e.op1);
		fs.popMoveTo(e.op1.endLocation.line, temp);
		fs.codeR(e.op1.endLocation.line, Op1.IsTrue, 0, temp, 0);
		auto i = fs.makeJump(e.op1.endLocation.line, Op2.Je);
		visit(e.op2);
		fs.popMoveTo(e.endLocation.line, temp);
		fs.patchJumpToHere(i);
		fs.pushTempReg(temp);
		
		/*
		fs.pushNewLocals(1);
		fs.dup();
		visit(e.op1);
		fs.assign(1, 1);
		fs.dup();
		auto i = fs.isTrue(e.op1.endLocation);
		fs.dup();
		visit(e.op2);
		fs.patchJumpToHere(i);
		fs.toTemporary();
		*/

		return e;
	}

	public override AndAndExp visit(AndAndExp e)
	{
		auto temp = fs.pushRegister();
		visit(e.op1);
		fs.popMoveTo(e.op1.endLocation.line, temp);
		fs.codeR(e.op1.endLocation.line, Op1.IsTrue, 0, temp, 0);
		auto i = fs.makeJump(e.op1.endLocation.line, Op2.Je, false);
		visit(e.op2);
		fs.popMoveTo(e.endLocation.line, temp);
		fs.patchJumpToHere(i);
		fs.pushTempReg(temp);

		/*
		fs.pushNewLocals(1);
		fs.dup();
		visit(e.op1);
		fs.assign(1, 1);
		fs.dup();
		auto i = fs.isTrue(e.op1.endlocation, false);
		fs.dup();
		visit(e.op2);
		fs.patchJumpToHere(i);
		fs.toTemporary();
		*/

		return e;
	}

	public BinaryExp visitBinExp(BinaryExp e)
	{
		visit(e.op1);
		Exp src1;
		fs.popSource(e.op1.endLocation.line, src1);
		visit(e.op2);
		Exp src2;
		fs.popSource(e.endLocation.line, src2);

		fs.freeExpTempRegs(src2);
		fs.freeExpTempRegs(src1);

		fs.pushBinOp(e.endLocation.line, e.type, src1.index, src2.index);

		/*
		visit(e.op1);
		fs.toSource(e.op1.endLocation);
		visit(e.op2);
		fs.toSource(e.op2.endLocation);
		fs.binOp(e.endLocation.line, e.type);
		*/

		return e;
	}

	public override BinaryExp visit(OrExp e)    { return visitBinExp(e); }
	public override BinaryExp visit(XorExp e)   { return visitBinExp(e); }
	public override BinaryExp visit(AndExp e)   { return visitBinExp(e); }
	public override BinaryExp visit(AsExp e)    { return visitBinExp(e); }
	public override BinaryExp visit(InExp e)    { return visitBinExp(e); }
	public override BinaryExp visit(NotInExp e) { assert(false); /* return visitBinExp(e); */ }
	public override BinaryExp visit(Cmp3Exp e)  { return visitBinExp(e); }
	public override BinaryExp visit(ShlExp e)   { return visitBinExp(e); }
	public override BinaryExp visit(ShrExp e)   { return visitBinExp(e); }
	public override BinaryExp visit(UShrExp e)  { return visitBinExp(e); }
	public override BinaryExp visit(AddExp e)   { return visitBinExp(e); }
	public override BinaryExp visit(SubExp e)   { return visitBinExp(e); }
	public override BinaryExp visit(MulExp e)   { return visitBinExp(e); }
	public override BinaryExp visit(DivExp e)   { return visitBinExp(e); }
	public override BinaryExp visit(ModExp e)   { return visitBinExp(e); }

	public override CatExp visit(CatExp e)
	{
		assert(e.collapsed is true, "CatExp codeGen not collapsed");
		assert(e.operands.length >= 2, "CatExp codeGen not enough ops");

		auto firstReg = fs.nextRegister();
		codeGenListToNextReg(e.operands, false);
		fs.pushBinOp(e.endLocation.line, e.type, firstReg, e.operands.length);

		/*
		codeGenList(e.operands, false);
		fs.binOp(e.endLocation.line, e.type, e.operands.length);
		*/

		return e;
	}

	public BinaryExp visitComparisonExp(BinaryExp e)
	{
		auto temp = fs.pushRegister();
		auto i = codeCondition(e);
		fs.pushBool(false);
		fs.popMoveTo(e.endLocation.line, temp);
		auto j = fs.makeJump(e.endLocation.line, Op1.Jmp);
		fs.patchTrueToHere(i);
		fs.pushBool(true);
		fs.popMoveTo(e.endLocation.line, temp);
		fs.patchJumpToHere(j);
		fs.pushTempReg(temp);
		
		/*
		fs.pushNewLocals(1);
		auto i = codeCondition(e);
		fs.dup();
		fs.pushBool(false);
		fs.assign(1, 1);
		auto j = fs.makeJump(e.endLocation.line, Op1.Jmp);
		fs.patchTrueToHere(i);
		fs.dup();
		fs.pushBool(true);
		fs.assign(1, 1);
		fs.patchJumpToHere(j);
		fs.toTemporary();
		*/

		return e;
	}

	public override BinaryExp visit(EqualExp e)    { return visitComparisonExp(e); }
	public override BinaryExp visit(NotEqualExp e) { return visitComparisonExp(e); }
	public override BinaryExp visit(IsExp e)       { return visitComparisonExp(e); }
	public override BinaryExp visit(NotIsExp e)    { return visitComparisonExp(e); }
	public override BinaryExp visit(LTExp e)       { return visitComparisonExp(e); }
	public override BinaryExp visit(LEExp e)       { return visitComparisonExp(e); }
	public override BinaryExp visit(GTExp e)       { return visitComparisonExp(e); }
	public override BinaryExp visit(GEExp e)       { return visitComparisonExp(e); }

	public UnExp visitUnExp(UnExp e)
	{
		visit(e.op);
		fs.unOp(e.endLocation.line, e.type);
		return e;
	}

	public override UnExp visit(NegExp e)       { return visitUnExp(e); }
	public override UnExp visit(NotExp e)       { return visitUnExp(e); }
	public override UnExp visit(ComExp e)       { return visitUnExp(e); }
	public override UnExp visit(CoroutineExp e) { return visitUnExp(e); }

	public override LenExp visit(LenExp e)
	{
		visit(e.op);
		fs.topToLength(e.endLocation.line);
		// fs.toLength(e.endLocation);
		return e;
	}

	public override VargLenExp visit(VargLenExp e)
	{
		if(!fs.mIsVararg)
			c.semException(e.location, "'vararg' cannot be used in a non-variadic function");

		fs.pushVargLen(e.endLocation.line);
		return e;
	}

	public override DotExp visit(DotExp e)
	{
		visit(e.op);
		fs.topToSource(e.endLocation.line);
		visit(e.name);
		fs.popField(e.endLocation.line);

		/*
		visit(e.op);
		fs.toSource(e.op.endLocation);
		visit(e.name);
		fs.toSource(e.endLocation);
		fs.field(e.endLocation);
		*/
		return e;
	}

	public override DotSuperExp visit(DotSuperExp e)
	{
		visit(e.op);
		fs.unOp(e.endLocation.line, e.type);
		return e;
	}

	public override MethodCallExp visit(MethodCallExp e)
	{
		visitMethodCall(e.location, e.endLocation, e.isSuperCall, e.op, e.method, delegate uword()
		{
			codeGenListToNextReg(e.args);

			if(e.args.length == 0)
				return 2;
			else if(e.args[$ - 1].isMultRet())
				return 0;
			else
				return e.args.length + 2;
			/*
			codeGenList(e.args);
			return e.args.length;
			*/
		});

		return e;
	}

	public void visitMethodCall(CompileLoc location, CompileLoc endLocation, bool isSuperCall, Expression op, Expression method, uword delegate() genArgs)
	{
		auto funcReg = fs.nextRegister();
		Exp src;

		if(isSuperCall)
			fs.pushThis();
		else
			visit(op);

		fs.popSource(location.line, src);
		fs.freeExpTempRegs(src);
		assert(fs.nextRegister() == funcReg);

		fs.pushRegister();

		Exp meth;
		visit(method);
		fs.popSource(method.endLocation.line, meth);
		fs.freeExpTempRegs(meth);

		auto thisReg = fs.nextRegister();

		fs.pushRegister();

		auto numArgs = genArgs();

		fs.codeR(endLocation.line, isSuperCall ? Op1.SuperMethod : Op1.Method, funcReg, src.index, meth.index);
		fs.popRegister(thisReg);
		fs.pushCall(endLocation.line, funcReg, numArgs);

		/*
		struct MethodCallDesc
		{
			uint baseReg
			uint baseExp;
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
				reserveRegs(1);

			assert(mFreeReg == desc.baseReg + num);
		}

		void pushMethodCall(CompileLoc loc, bool isSuperCall, ref MethodCallDesc desc)
		{
			// desc.baseExp holds obj, baseExp + 1 holds method name. assert they're both sources
			// everything after that is args. assert they're all in registers

			auto numArgs = mExpSP - desc.baseReg - 2;
			bool lastIsMultiret = last arg is multiret;
			pop all the args;

			codeR(loc, isSuperCall ? Op1.SuperMethod : Op1.Method, desc.baseReg, expStack[-2], expStack[-1]);
			pop(2);
			mFreeReg = desc.baseReg;

			pushCall(loc, desc.baseReg, lastIsMultiret ? 0 : numArgs + 1);

			assert(mExpSP == desc.baseExp);
			assert(mFreeReg == desc.baseReg + 1); // plus one for the call that we pushed
		}

		auto desc = fs.beginMethodCall();

		if(isSuperCall)
			fs.pushThis();
		else
			visit(op);

		fs.toSource(location);
		fs.updateMethodCall(desc, 1);

		visit(method);
		fs.toSource(method.endLocation);
		fs.updateMethodCall(desc, 2);

		genArgs();
		fs.pushMethodCall(endLocation, isSuperCall, desc);
		*/
	}

	public override CallExp visit(CallExp e)
	{
		visitCall(e.endLocation, e.op, e.context, delegate uword()
		{
			codeGenListToNextReg(e.args);

			if(e.args.length == 0)
				return 2;
			else if(e.args[$ - 1].isMultRet())
				return 0;
			else
				return e.args.length + 2;

			/*
			codeGenList(e.args);
			return e.args.length;
			*/
		});

		return e;
	}

	public void visitCall(CompileLoc endLocation, Expression op, Expression context, uword delegate() genArgs)
	{
		auto funcReg = fs.nextRegister();

		visit(op);
		fs.popMoveTo(op.endLocation.line, funcReg);

		assert(fs.nextRegister() == funcReg);

		fs.pushRegister();
		auto thisReg = fs.nextRegister();

		if(context)
			visit(context);
		else
			fs.pushNull();

		fs.popMoveTo(op.endLocation.line, thisReg);
		fs.pushRegister();

		auto numArgs = genArgs();

		fs.popRegister(thisReg);
		fs.pushCall(endLocation.line, funcReg, numArgs);

		/*
		visit(op);
		fs.toSource();
		fs.toTemporary();

		if(context)
			visit(context);
		else
			fs.pushNull();

		fs.toSource();
		fs.toTemporary();

		auto numArgs = genArgs();
		fs.pushCall(endLocation, numArgs);
		*/
	}

	public override IndexExp visit(IndexExp e)
	{
		visit(e.op);
		fs.topToSource(e.endLocation.line);
		visit(e.index);
		fs.popIndex(e.endLocation.line);
		
		/*
		visit(e.op);
		fs.toSource(e.op.endLocation);
		visit(e.index);
		fs.toSource(e.endLocation);
		fs.index(e.endLocation);
		*/
		return e;
	}

	public override VargIndexExp visit(VargIndexExp e)
	{
		if(!fs.mIsVararg)
			c.semException(e.location, "'vararg' cannot be used in a non-variadic function");

		visit(e.index);
		fs.popVargIndex(e.endLocation.line);
		
		/*
		visit(e.index);
		fs.vargIndex(e.endLocation);
		*/

		return e;
	}

	public override SliceExp visit(SliceExp e)
	{
		auto reg = fs.nextRegister();
		Expression[3] list;
		list[0] = e.op;
		list[1] = e.loIndex;
		list[2] = e.hiIndex;
		codeGenListToNextReg(list[]);
		fs.pushSlice(e.endLocation.line, reg);

		/*
		Expression[3] list;
		list[0] = e.op;
		list[1] = e.loIndex;
		list[2] = e.hiIndex;
		codeGenList(list[], false);
		fs.slice(e.endLocation);
		*/
		return e;
	}

	public override VargSliceExp visit(VargSliceExp e)
	{
		if(!fs.mIsVararg)
			c.semException(e.location, "'vararg' cannot be used in a non-variadic function");

		auto reg = fs.nextRegister();
		Expression[2] list;
		list[0] = e.loIndex;
		list[1] = e.hiIndex;
		codeGenListToNextReg(list[]);
		fs.pushVargSlice(e.endLocation.line, reg);

		/*
		Expression[2] list;
		list[0] = e.loIndex;
		list[1] = e.hiIndex;
		codeGenList(list[], false);
		fs.vargSlice(e.endLocation);
		*/
		return e;
	}

	public override IdentExp visit(IdentExp e)
	{
		fs.pushVar(e.name);
		return e;
	}

	public override ThisExp visit(ThisExp e)
	{
		fs.pushThis();
		return e;
	}

	public override NullExp visit(NullExp e)
	{
		fs.pushNull();
		return e;
	}

	public override BoolExp visit(BoolExp e)
	{
		fs.pushBool(e.value);
		return e;
	}

	public override IntExp visit(IntExp e)
	{
		fs.pushInt(e.value);
		return e;
	}

	public override FloatExp visit(FloatExp e)
	{
		fs.pushFloat(e.value);
		return e;
	}

	public override CharExp visit(CharExp e)
	{
		fs.pushChar(e.value);
		return e;
	}

	public override StringExp visit(StringExp e)
	{
		fs.pushString(e.value);
		return e;
	}

	public override VarargExp visit(VarargExp e)
	{
		if(!fs.mIsVararg)
			c.semException(e.location, "'vararg' cannot be used in a non-variadic function");

		fs.pushVararg();
		return e;
	}

	public override FuncLiteralExp visit(FuncLiteralExp e)
	{
		visit(e.def);
		return e;
	}

	public override ClassLiteralExp visit(ClassLiteralExp e)
	{
		visit(e.def);
		return e;
	}

	public override NamespaceCtorExp visit(NamespaceCtorExp e)
	{
		visit(e.def);
		return e;
	}

	public override ParenExp visit(ParenExp e)
	{
		assert(e.exp.isMultRet(), "ParenExp codeGen not multret");

		auto reg = fs.nextRegister();
		visit(e.exp);
		fs.popMoveTo(e.location.line, reg);
		auto checkReg = fs.pushRegister();

		assert(reg == checkReg, "ParenExp codeGen wrong regs");

		fs.pushTempReg(reg);
		
		/*
		visit(e.exp);
		fs.toSource();
		fs.toTemporary();
		*/

		return e;
	}

	public override TableCtorExp visit(TableCtorExp e)
	{
		auto destReg = fs.pushRegister();
		fs.codeI(e.location.line, Op1.New, destReg, 0);
		fs.codeR(e.location.line, Op2.Table, 0, 0, 0);

		foreach(ref field; e.fields)
		{
			visit(field.key);
			Exp idx;
			fs.popSource(field.key.endLocation.line, idx);
			visit(field.value);
			Exp val;
			fs.popSource(field.value.endLocation.line, val);
			fs.freeExpTempRegs(val);
			fs.freeExpTempRegs(idx);

			fs.codeR(field.value.endLocation.line, Op1.IndexAssign, destReg, idx.index, val.index);
		}

		fs.pushTempReg(destReg);
		
		/*
		fs.newTable();
		fs.toTemporary();
		
		foreach(ref field; e.fields)
		{
			fs.dup();
			visit(field.key);
			fs.toSource();
			fs.index();
			visit(field.value);
			fs.toSource();
			fs.assign(1, 1);
		}
		*/

		return e;
	}

	public override ArrayCtorExp visit(ArrayCtorExp e)
	{
		if(e.values.length > ArrayCtorExp.maxFields)
			c.semException(e.location, "Array constructor has too many fields (more than {})", ArrayCtorExp.maxFields);

		static uword min(uword a, uword b)
		{
			return (a > b) ? b : a;
		}

		auto destReg = fs.pushRegister();

		if(e.values.length > 0 && e.values[$ - 1].isMultRet())
			fs.codeI(e.location.line, Op1.New, destReg, e.values.length - 1);
		else
			fs.codeI(e.location.line, Op1.New, destReg, e.values.length);

		fs.codeR(e.location.line, Op2.Array, 0, 0, 0);

		if(e.values.length > 0)
		{
			uword index = 0;
			uword fieldsLeft = e.values.length;
			uword block = 0;

			while(fieldsLeft > 0)
			{
				auto numToDo = min(fieldsLeft, Instruction.ArraySetFields);
				codeGenListToNextReg(e.values[index .. index + numToDo]);
				fieldsLeft -= numToDo;

				if(fieldsLeft == 0 && e.values[$ - 1].isMultRet())
					fs.codeR(e.endLocation.line, Op1.Array, destReg, 0, block);
				else
					fs.codeR(e.values[index + numToDo - 1].endLocation.line, Op1.Array, destReg, numToDo + 1, block);

				fs.codeR(e.endLocation.line, Op2.Set, 0, 0, 0);

				index += numToDo;
				block++;
			}
		}

		fs.pushTempReg(destReg);

		/*
		if(e.values.length > 0 && e.values[$ - 1].isMultRet())
			fs.newArray(e.values.length - 1);
		else
			fs.newArray(e.values.length);

		fs.toTemporary();

		if(e.values.length > 0)
		{
			uword index = 0;
			uword fieldsLeft = e.values.length;
			uword block = 0;

			while(fieldsLeft > 0)
			{
				auto numToDo = min(fieldsLeft, Instruction.ArraySetFields);
				fs.dup();
				codeGenList(e.values[index .. index + numToDo]);
				fieldsLeft -= numToDo;

				if(fieldsLeft == 0 && e.values[$ - 1].isMultRet())
					fs.setArray(e.endLocation, numToDo, block, true);
				else
					fs.setArray(e.values[index + numToDo - 1].endLocation, numToDo, block, false);

				index += numToDo;
				block++;
			}
		}
		*/

		return e;
	}

	public override YieldExp visit(YieldExp e)
	{
		auto firstReg = fs.nextRegister();

		codeGenListToNextReg(e.args);

		if(e.args.length > 0 && e.args[$ - 1].isMultRet())
			fs.pushYield(e.endLocation.line, firstReg, 0);
		else
			fs.pushYield(e.endLocation.line, firstReg, e.args.length + 1);

		/*
		codeGenList(e.args);
		fs.yield(e.endLocation, e.args.length);
		*/

		return e;
	}

	public override TableComprehension visit(TableComprehension e)
	{
		auto tempReg = fs.pushRegister();
		fs.codeI(e.location.line, Op1.New, tempReg, 0);
		fs.codeR(e.location.line, Op2.Table, 0, 0, 0);

		visitForComp(e.forComp,
		{
			visit(e.key);
			Exp src1;
			fs.popSource(e.key.location.line, src1);
			visit(e.value);
			Exp src2;
			fs.popSource(e.value.location.line, src2);
			fs.freeExpTempRegs(src2);
			fs.freeExpTempRegs(src1);
			fs.codeR(e.key.location.line, Op1.IndexAssign, tempReg, src1.index, src2.index);
		});

		fs.pushTempReg(tempReg);

		/*
		fs.newTable();
		fs.toTemporary();

		visitForComp(e.forComp,
		{
			assert(the top item in fs' expStack is the table temp!);
			fs.dup();
			visit(e.key);
			fs.toSource(e.key.endLocation);
			fs.index();
			visit(e.value);
			fs.toSource(e.value.endLocation);
			fs.assign(e.value.endLocation, 1, 1);

		});
		*/
		return e;
	}

	public override ArrayComprehension visit(ArrayComprehension e)
	{
		auto tempReg = fs.pushRegister();
		fs.codeI(e.location.line, Op1.New, tempReg, 0);
		fs.codeR(e.location.line, Op2.Array, 0, 0, 0);

		visitForComp(e.forComp,
		{
			visit(e.exp);
			Exp src;
			fs.popSource(e.exp.location.line, src);
			fs.freeExpTempRegs(src);
			fs.codeR(e.exp.location.line, Op1.Array, tempReg, src.index, 0);
			fs.codeR(e.exp.location.line, Op2.Append, 0, 0, 0);
		});

		fs.pushTempReg(tempReg);

		/*
		fs.newArray(0);
		fs.toTemporary();

		visitForComp(e.forComp,
		{
			assert(expStack top is array temp!);
			fs.dup();
			visit(e.exp);
			fs.toSource(e.exp.endLocation);
			fs.append(e.exp.endLocation);
		});
		*/
		return e;
	}

	public ForComprehension visitForComp(ForComprehension e, void delegate() inner)
	{
		if(auto x = e.as!(ForeachComprehension))
			return visit(x, inner);
		else
		{
			auto x = e.as!(ForNumComprehension);
			assert(x !is null);
			return visit(x, inner);
		}
	}

	public ForeachComprehension visit(ForeachComprehension e, void delegate() inner)
	{
		auto newInner = inner;

		if(e.ifComp)
		{
			if(e.forComp)
				newInner = { visit(e.ifComp, { visitForComp(e.forComp, inner); }); };
			else
				newInner = { visit(e.ifComp, inner); };
		}
		else if(e.forComp)
			newInner = { visitForComp(e.forComp, inner); };

		visitForeach(e.location, e.endLocation, "", e.indices, e.container, newInner);
		return e;
	}

	public ForNumComprehension visit(ForNumComprehension e, void delegate() inner)
	{
		auto newInner = inner;

		if(e.ifComp)
		{
			if(e.forComp)
				newInner = { visit(e.ifComp, { visitForComp(e.forComp, inner); }); };
			else
				newInner = { visit(e.ifComp, inner); };
		}
		else if(e.forComp)
			newInner = { visitForComp(e.forComp, inner); };

		visitForNum(e.location, e.endLocation, "", e.lo, e.hi, e.step, e.index, newInner);
		return e;
	}

	public IfComprehension visit(IfComprehension e, void delegate() inner)
	{
		visitIf(e.location, e.endLocation, e.endLocation, null, e.condition, inner, null);
		return e;
	}

	public void codeGenListToNextReg(Expression[] exprs, bool allowMultRet = true)
	{
		if(exprs.length == 0)
			return;
		else if(exprs.length == 1)
		{
			auto firstReg = fs.nextRegister();
			visit(exprs[0]);

			if(allowMultRet && exprs[0].isMultRet())
				fs.popToRegisters(exprs[0].endLocation.line, firstReg, -1);
			else
				fs.popMoveTo(exprs[0].endLocation.line, firstReg);
		}
		else
		{
			auto firstReg = fs.nextRegister();
			visit(exprs[0]);
			fs.popMoveTo(exprs[0].endLocation.line, firstReg);
			fs.pushRegister();

			auto lastReg = firstReg;

			foreach(i, e; exprs[1 .. $])
			{
				lastReg = fs.nextRegister();
				visit(e);

				// has to be -2 because i _is not the index in the array_ but the _index in the slice_
				if(allowMultRet && i == exprs.length - 2 && e.isMultRet())
					fs.popToRegisters(e.endLocation.line, lastReg, -1);
				else
					fs.popMoveTo(e.endLocation.line, lastReg);

				fs.pushRegister();
			}

			for(auto i = lastReg; i >= cast(int)firstReg; i--)
				fs.popRegister(i);
		}
		
		/*
		if(e.length == 0)
			return;

		foreach(i, e; exprs[0 .. $ - 1])
		{
			visit(e);
			fs.toSource();
			fs.toTemporary();
		}

		visit(exprs[$ - 1]);

		if(!allowMultRet || !exprs[$ - 1].isMultRet())
		{
			fs.toSource();
			fs.toTemporary();
		}
		*/
	}

	public void codeGenAssignmentList(Expression[] exprs, word numSlots)
	{
		auto firstReg = fs.nextRegister();
		auto lastReg = firstReg;

		foreach(i, e; exprs[0 .. $ - 1])
		{
			lastReg = fs.nextRegister();
			visit(e);
			fs.popMoveTo(e.endLocation.line, lastReg);
			fs.pushRegister();
		}

		word extraSlots = numSlots - exprs.length;
		lastReg = fs.nextRegister();
		visit(exprs[$ - 1]);

		if(exprs[$ - 1].isMultRet())
		{
			extraSlots++;

			if(extraSlots < 0)
				extraSlots = 0;

			fs.popToRegisters(exprs[$ - 1].endLocation.line, lastReg, extraSlots);
			fs.pushRegister();
		}
		else
		{
			fs.popMoveTo(exprs[$ - 1].endLocation.line, lastReg);
			fs.pushRegister();

			if(extraSlots > 0)
				fs.codeNulls(exprs[$ - 1].endLocation.line, fs.nextRegister(), extraSlots);
		}

		for(auto i = lastReg; i >= cast(int)firstReg; i--)
			fs.popRegister(i);
			
		/*
		some of this logic will move into fs.assign()
		*/
	}

	// ---------------------------------------------------------------------------
	// Condition codegen

	package InstRef codeCondition(Expression e)
	{
		switch(e.type)
		{
			case AstTag.CondExp:     return codeCondition(e.as!(CondExp));
			case AstTag.OrOrExp:     return codeCondition(e.as!(OrOrExp));
			case AstTag.AndAndExp:   return codeCondition(e.as!(AndAndExp));
			case AstTag.EqualExp:    return codeCondition(e.as!(EqualExp));
			case AstTag.NotEqualExp: return codeCondition(e.as!(NotEqualExp));
			case AstTag.IsExp:       return codeCondition(e.as!(IsExp));
			case AstTag.NotIsExp:    return codeCondition(e.as!(NotIsExp));
			case AstTag.LTExp:       return codeCondition(e.as!(LTExp));
			case AstTag.LEExp:       return codeCondition(e.as!(LEExp));
			case AstTag.GTExp:       return codeCondition(e.as!(GTExp));
			case AstTag.GEExp:       return codeCondition(e.as!(GEExp));
			case AstTag.IdentExp:    return codeCondition(e.as!(IdentExp));
			case AstTag.ThisExp:     return codeCondition(e.as!(ThisExp));
			case AstTag.ParenExp:    return codeCondition(e.as!(ParenExp));

			default:
				auto temp = fs.nextRegister();
				visit(e);
				fs.popMoveTo(e.endLocation.line, temp);

				fs.codeR(e.endLocation.line, Op1.IsTrue, 0, temp, 0);

				InstRef ret;
				ret.trueList = fs.makeJump(e.endLocation.line, Op2.Je);

				/*
				visit(e);
				fs.toSource();
				ret.trueList = fs.isTrue(e.endLocation);
				*/
				return ret;
		}
	}

	package InstRef codeCondition(CondExp e)
	{
		auto c = codeCondition(e.cond);
		fs.invertJump(c);
		fs.patchTrueToHere(c);

		auto left = codeCondition(e.op1);
		fs.invertJump(left);
		fs.patchTrueToHere(left);

		auto trueJump = fs.makeJump(e.op1.endLocation.line, Op1.Jmp, true);

		fs.patchFalseToHere(c);
		// Done with c

		auto right = codeCondition(e.op2);
		fs.catToFalse(right, left.falseList);
		fs.catToTrue(right, trueJump);
		return right;
	}

	package InstRef codeCondition(OrOrExp e)
	{
		auto left = codeCondition(e.op1);
		fs.patchFalseToHere(left);

		auto right = codeCondition(e.op2);
		fs.catToTrue(right, left.trueList);

		return right;
	}

	package InstRef codeCondition(AndAndExp e)
	{
		auto left = codeCondition(e.op1);
		fs.invertJump(left);
		fs.patchTrueToHere(left);

		auto right = codeCondition(e.op2);
		fs.catToFalse(right, left.falseList);

		return right;
	}

	package InstRef codeEqualExpCondition(BaseEqualExp e)
	{
		visit(e.op1);
		Exp src1;
		fs.popSource(e.op1.endLocation.line, src1);
		visit(e.op2);
		Exp src2;
		fs.popSource(e.endLocation.line, src2);

		fs.freeExpTempRegs(src2);
		fs.freeExpTempRegs(src1);

		fs.codeR(e.endLocation.line, AstTagToOpcode1(e.type), 0, src1.index, src2.index);
		assert(AstTagToOpcode2(e.type) == -1);

		InstRef ret;
		ret.trueList = fs.makeJump(e.endLocation.line, Op2.Je, e.type == AstTag.EqualExp || e.type == AstTag.IsExp);
		return ret;
	}

	package InstRef codeCondition(EqualExp e)    { return codeEqualExpCondition(e); }
	package InstRef codeCondition(NotEqualExp e) { return codeEqualExpCondition(e); }
	package InstRef codeCondition(IsExp e)       { return codeEqualExpCondition(e); }
	package InstRef codeCondition(NotIsExp e)    { return codeEqualExpCondition(e); }

	package InstRef codeCmpExpCondition(BaseCmpExp e)
	{
		visit(e.op1);
		Exp src1;
		fs.popSource(e.op1.endLocation.line, src1);
		visit(e.op2);
		Exp src2;
		fs.popSource(e.endLocation.line, src2);

		fs.freeExpTempRegs(src2);
		fs.freeExpTempRegs(src1);

		fs.codeR(e.endLocation.line, Op1.Cmp, 0, src1.index, src2.index);

		InstRef ret;

		switch(e.type)
		{
			case AstTag.LTExp: ret.trueList = fs.makeJump(e.endLocation.line, Op2.Jlt, true); break;
			case AstTag.LEExp: ret.trueList = fs.makeJump(e.endLocation.line, Op2.Jle, true); break;
			case AstTag.GTExp: ret.trueList = fs.makeJump(e.endLocation.line, Op2.Jle, false); break;
			case AstTag.GEExp: ret.trueList = fs.makeJump(e.endLocation.line, Op2.Jlt, false); break;
			default: assert(false);
		}

		return ret;
	}

	package InstRef codeCondition(LTExp e) { return codeCmpExpCondition(e); }
	package InstRef codeCondition(LEExp e) { return codeCmpExpCondition(e); }
	package InstRef codeCondition(GTExp e) { return codeCmpExpCondition(e); }
	package InstRef codeCondition(GEExp e) { return codeCmpExpCondition(e); }

	package InstRef codeCondition(IdentExp e)
	{
		visit(e);

		Exp src;
		fs.popSource(e.endLocation.line, src);
		fs.freeExpTempRegs(src);

		fs.codeR(e.endLocation.line, Op1.IsTrue, 0, src.index, 0);

		InstRef ret;
		ret.trueList = fs.makeJump(e.endLocation.line, Op2.Je, true);
		return ret;
	}

	package InstRef codeCondition(ThisExp e)
	{
		visit(e);

		Exp src;
		fs.popSource(e.endLocation.line, src);
		fs.freeExpTempRegs(src);

		fs.codeR(e.endLocation.line, Op1.IsTrue, 0, src.index, 0);

		InstRef ret;
		ret.trueList = fs.makeJump(e.endLocation.line, Op2.Je, true);
		return ret;
	}

	package InstRef codeCondition(ParenExp e)
	{
		auto temp = fs.nextRegister();
		visit(e.exp);
		fs.popMoveTo(e.endLocation.line, temp);
		fs.codeR(e.endLocation.line, Op1.IsTrue, 0, temp, 0);

		InstRef ret;
		ret.trueList = fs.makeJump(e.endLocation.line, Op2.Je, true);
		return ret;
	}
}