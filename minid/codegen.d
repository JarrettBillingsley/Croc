/******************************************************************************
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

module minid.codegen;

// debug = REGPUSHPOP;
// debug = VARACTIVATE;
// debug = WRITECODE;
// debug = SHOWME;
// debug = PRINTEXPSTACK;

debug import tango.io.Stdout;
debug import tango.text.convert.Format;

import minid.alloc;
import minid.ast;
import minid.astvisitor;
import minid.compilertypes;
import minid.func;
import minid.funcdef;
import minid.hash;
import minid.interpreter;
import minid.opcodes;
import minid.string;
import minid.types;
import minid.utils;

private Op AstTagToOpcode(AstTag tag)
{
	switch(tag)
	{
		case AstTag.AddAssignStmt: return Op.AddEq;
		case AstTag.SubAssignStmt: return Op.SubEq;
		case AstTag.CatAssignStmt: return Op.CatEq;
		case AstTag.MulAssignStmt: return Op.MulEq;
		case AstTag.DivAssignStmt: return Op.DivEq;
		case AstTag.ModAssignStmt: return Op.ModEq;
		case AstTag.OrAssignStmt: return Op.OrEq;
		case AstTag.XorAssignStmt: return Op.XorEq;
		case AstTag.AndAssignStmt: return Op.AndEq;
		case AstTag.ShlAssignStmt: return Op.ShlEq;
		case AstTag.ShrAssignStmt: return Op.ShrEq;
		case AstTag.UShrAssignStmt: return Op.UShrEq;
		case AstTag.CondAssignStmt: return Op.CondMove;
		case AstTag.OrExp: return Op.Or;
		case AstTag.XorExp: return Op.Xor;
		case AstTag.AndExp: return Op.And;
		case AstTag.EqualExp: return Op.Cmp;
		case AstTag.NotEqualExp: return Op.Cmp;
		case AstTag.IsExp: return Op.Is;
		case AstTag.NotIsExp: return Op.Is;
		case AstTag.LTExp: return Op.Cmp;
		case AstTag.LEExp: return Op.Cmp;
		case AstTag.GTExp: return Op.Cmp;
		case AstTag.GEExp: return Op.Cmp;
		case AstTag.Cmp3Exp: return Op.Cmp3;
		case AstTag.AsExp: return Op.As;
		case AstTag.InExp: return Op.In;
		case AstTag.NotInExp: return Op.NotIn;
		case AstTag.ShlExp: return Op.Shl;
		case AstTag.ShrExp: return Op.Shr;
		case AstTag.UShrExp: return Op.UShr;
		case AstTag.AddExp: return Op.Add;
		case AstTag.SubExp: return Op.Sub;
		case AstTag.CatExp: return Op.Cat;
		case AstTag.MulExp: return Op.Mul;
		case AstTag.DivExp: return Op.Div;
		case AstTag.ModExp: return Op.Mod;
		case AstTag.NegExp: return Op.Neg;
		case AstTag.NotExp: return Op.Not;
		case AstTag.ComExp: return Op.Com;
		case AstTag.CoroutineExp: return Op.Coroutine;
		default: assert(false);
	}
}

const uint NoJump = uint.max;

struct InstRef
{
	uint trueList = NoJump;
	uint falseList = NoJump;
	debug bool inverted = false;
}

enum ExpType
{
	Null,
	True,
	False,
	Const,
	Var,
	NewGlobal,
	Indexed,
	IndexedVararg,
	Field,
	Sliced,
	SlicedVararg,
	Length,
	Vararg,
	Call,
	Yield,
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
			ExpType.Null: "Null",
			ExpType.True: "True",
			ExpType.False: "False",
			ExpType.Const: "Const",
			ExpType.Var: "Var",
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
	package ushort varStart = 0;
	package ushort regStart = 0;
	package bool hasUpval = false;
}

struct SwitchDesc
{
	package Hash!(MDValue, int) offsets;
	package int defaultOffset = -1;
	package uint switchPC;
	package SwitchDesc* prev;
}

private void append(T)(ref T[] arr, Allocator* alloc, ref T item)
{
	alloc.resizeArray(arr, arr.length + 1);
	arr[$ - 1] = item;
}

final class FuncState
{
	package ICompiler c;
	package MDThread* t;
	package FuncState mParent;
	package Scope* mScope;
	package ushort mFreeReg = 0;
	package Exp[] mExpStack;
	package uword mExpSP = 0;

	package CompileLoc mLocation;
	package bool mIsVararg;
	package char[] mName;
	package uint mNumParams;
	package ushort[] mParamMasks;

	struct UpvalDesc
	{
		package bool isUpvalue;
		package uint index;
		package char[] name;
	}

	package UpvalDesc[] mUpvals;
	package uint mStackSize;
	package MDFuncDef*[] mInnerFuncs;
	package MDValue[] mConstants;
	package Instruction[] mCode;
	
	// Purity starts off true, and if any accesses to upvalues or globals occur, it goes false.
	// Also goes false if any nested func is impure.
	package bool mIsPure = true;
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
		}
		else
			s.enclosing = null;

		s.breaks = NoJump;
		s.continues = NoJump;
		s.varStart = cast(ushort)mLocVars.length;
		s.regStart = mFreeReg;
		s.hasUpval = false;

		mScope = &s;
	}

	package void popScope(uint line)
	{
		assert(mScope !is null, "scope underflow");

		auto prev = mScope.enclosing;

		if(mScope.hasUpval)
			codeClose(line, mScope.regStart);

		deactivateLocals(mScope.varStart, mScope.regStart);
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
			c.exception(ident.location, "Local '{}' conflicts with previous definition at {}({}:{})", ident.name, l.file, l.line, l.col);
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
			codeI(line, Op.Close, mScope.regStart, 0);
	}

	package void codeClose(uint line, ushort reg)
	{
		codeI(line, Op.Close, reg, 0);
	}

	package uint tagLocal(uint val)
	{
		if((val & ~Instruction.locMask) > MaxRegisters)
			c.exception(mLocation, "Too many locals");

		return (val & ~Instruction.locMask) | Instruction.locLocal;
	}

	package uint tagConst(uint val)
	{
		if((val & ~Instruction.locMask) >= MaxConstants)
			c.exception(mLocation, "Too many constants");

		return (val & ~Instruction.locMask) | Instruction.locConst;
	}

	package uint tagUpval(uint val)
	{
		if((val & ~Instruction.locMask) >= MaxUpvalues)
			c.exception(mLocation, "Too many upvalues");

		return (val & ~Instruction.locMask) | Instruction.locUpval;
	}

	package uint tagGlobal(uint val)
	{
		if((val & ~Instruction.locMask) >= MaxConstants)
			c.exception(mLocation, "Too many constants");

		return (val & ~Instruction.locMask) | Instruction.locGlobal;
	}
	
	package bool isLocalTag(uint val)
	{
		return ((val & Instruction.locMask) == Instruction.locLocal);
	}
	
	package bool isConstTag(uint val)
	{
		return ((val & Instruction.locMask) == Instruction.locConst);
	}
	
	package bool isUpvalTag(uint val)
	{
		return ((val & Instruction.locMask) == Instruction.locUpval);
	}

	package bool isGlobalTag(uint val)
	{
		return ((val & Instruction.locMask) == Instruction.locGlobal);
	}

	// ---------------------------------------------------------------------------
	// Switches

	package void beginSwitch(ref SwitchDesc s, uint line, uint srcReg)
	{
		s.switchPC = codeR(line, Op.Switch, 0, srcReg, 0);
		s.prev = mSwitch;
		mSwitch = &s;
	}

	package void endSwitch()
	{
		assert(mSwitch !is null, "endSwitch - no switch to end");
		
		auto prev = mSwitch.prev;

		mSwitchTables.append(c.alloc, *mSwitch);
		mCode[mSwitch.switchPC].rt = cast(ushort)(mSwitchTables.length - 1);

		mSwitch = prev;
	}

	package void addCase(CompileLoc location, Expression v)
	{
		assert(mSwitch !is null);

		MDValue val = void;

		if(v.isNull())
			val = MDValue.nullValue;
		else if(v.isBool())
			val = v.asBool();
		else if(v.isInt())
			val = v.asInt();
		else if(v.isFloat())
			val = v.asFloat();
		else if(v.isChar())
			val = v.asChar();
		else if(v.isString())
			val = string.create(t.vm, v.asString());
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
			c.exception(location, getString(t, -1));
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

		if(mFreeReg > MaxRegisters)
			c.exception(mLocation, "Too many registers");

		if(mFreeReg > mStackSize)
			mStackSize = mFreeReg;

		return mFreeReg - 1;
	}
	
	package void popRegister(uint r)
	{
		mFreeReg--;
		debug(REGPUSHPOP) Stdout.formatln("pop {}, {}", mFreeReg, r);

		assert(mFreeReg >= 0, "temp reg underflow");
		assert(mFreeReg == r, "reg not freed in order");
	}

	package uint resolveAssignmentConflicts(uint line, uint numVals)
	{
		uint numTemps = 0;

		for(int i = mExpSP - numVals + 1; i < mExpSP; i++)
		{
			auto index = &mExpStack[i];
			uint reloc = uint.max;

			// TODO: debug this, this doesn't look right.
			for(int j = mExpSP - numVals; j < i; j++)
			{
				auto e = &mExpStack[j];

				if(e.index == index.index || e.index2 == index.index)
				{
					if(reloc == uint.max)
					{
						numTemps++;
						reloc = pushRegister();

						if(isLocalTag(index.index))
							codeR(line, Op.MoveLocal, reloc, index.index, 0);
						else
							codeR(line, Op.Move, reloc, index.index, 0);
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
		pushExp().type = ExpType.Null;
	}

	public void pushBool(bool value)
	{
		auto e = pushExp();

		if(value)
			e.type = ExpType.True;
		else
			e.type = ExpType.False;
	}

	public void pushInt(mdint value)
	{
		pushConst(codeIntConst(value));
	}

	public void pushFloat(mdfloat value)
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
		e.index = tagConst(index);
	}

	public void pushNewGlobal(Identifier name)
	{
		auto e = pushExp();
		e.type = ExpType.NewGlobal;
		e.index = tagConst(codeStringConst(name.name));
	}

	public void pushThis()
	{
		auto e = pushExp();
		e.type = ExpType.Var;
		e.index = tagLocal(0);
	}

	public void pushVar(Identifier name)
	{
		auto e = pushExp();

		const Local = 0;
		const Upvalue = 1;
		const Global = 2;

		auto varType = Local;

		int searchVar(FuncState s, bool isOriginal = true)
		{
			uint findUpval()
			{
				for(int i = 0; i < s.mUpvals.length; i++)
				{
					if(s.mUpvals[i].name == name.name)
					{
						if((s.mUpvals[i].isUpvalue && varType == Upvalue) || (!s.mUpvals[i].isUpvalue && varType == Local))
							return i;
					}
				}

				UpvalDesc ud = void;

				ud.name = name.name;
				ud.isUpvalue = (varType == Upvalue);
				ud.index = tagLocal(e.index);

				s.mUpvals.append(c.alloc, ud);

				if(mUpvals.length >= MaxUpvalues)
					c.exception(mLocation, "Too many upvalues in function");

				return s.mUpvals.length - 1;
			}

			if(s is null)
			{
				varType = Global;
				return Global;
			}

			uint reg;
			auto index = s.searchLocal(name.name, reg);

			if(index == -1)
			{
				if(searchVar(s.mParent, false) == Global)
					return Global;

				e.index = tagUpval(findUpval());
				varType = Upvalue;
				return Upvalue;
			}
			else
			{
				varType = Local;
				e.index = tagLocal(reg);

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

				return Local;
			}
		}

		if(searchVar(this) == Global)
			e.index = tagGlobal(codeStringConst(name.name));
			
		if(varType == Upvalue || varType == Global)
			mIsPure = false;

		e.type = ExpType.Var;
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
		e.index = codeR(line, Op.VargLen, 0, 0, 0);
	}

	public void pushVargSlice(uint line, uint reg)
	{
		auto e = pushExp();
		e.type = ExpType.SlicedVararg;
		e.index = codeI(line, Op.VargSlice, reg, 0);
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
		e.index = codeR(line, Op.Call, firstReg, numRegs, 0);
		e.index2 = firstReg;
		e.isTempReg2 = true;
	}

	public void pushYield(uint line, uint firstReg, uint numRegs)
	{
		auto e = pushExp();
		e.type = ExpType.Yield;
		e.index = codeR(line, Op.Yield, firstReg, numRegs, 0);
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
	
	public void pushBinOp(uint line, Op type, uint rs, uint rt)
	{
		Exp* dest = pushExp();
		dest.type = ExpType.NeedsDest;
		dest.index = codeR(line, type, 0, rs, rt);
	}

	// ---------------------------------------------------------------------------
	// Expression stack pops
	
	public void popToNothing()
	{
		if(mExpSP == 0)
			return;

		auto src = popExp();

		if(src.type == ExpType.Call || src.type == ExpType.Yield)
			mCode[src.index].rt = 1;

		freeExpTempRegs(*src);
	}

	public void popAssign(uint line)
	{
		auto src = popExp();
		auto dest = popExp();

		switch(dest.type)
		{
			case ExpType.Var:
				moveTo(line, dest.index, src);
				break;

			case ExpType.NewGlobal:
				toSource(line, src);

				codeR(line, Op.NewGlobal, 0, src.index, dest.index);

				freeExpTempRegs(*src);
				freeExpTempRegs(*dest);
				break;

			case ExpType.Indexed:
				toSource(line, src);

				codeR(line, Op.IndexAssign, dest.index, dest.index2, src.index);

				freeExpTempRegs(*src);
				freeExpTempRegs(*dest);
				break;

			case ExpType.Field:
				toSource(line, src);

				codeR(line, Op.FieldAssign, dest.index, dest.index2, src.index);

				freeExpTempRegs(*src);
				freeExpTempRegs(*dest);
				break;

			case ExpType.IndexedVararg:
				toSource(line, src);

				codeR(line, Op.VargIndexAssign, 0, dest.index, src.index);
				freeExpTempRegs(*src);
				freeExpTempRegs(*dest);
				break;

			case ExpType.Sliced:
				toSource(line, src);

				codeR(line, Op.SliceAssign, dest.index, src.index, 0);

				freeExpTempRegs(*src);
				freeExpTempRegs(*dest);
				break;

			case ExpType.Length:
				toSource(line, src);

				codeR(line, Op.LengthAssign, dest.index, src.index, 0);

				freeExpTempRegs(*src);
				freeExpTempRegs(*dest);
				break;
				
			default:
				assert(false, "popAssign switch");
		}
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
				codeI(line, Op.Vararg, reg, num + 1);
				break;

			case ExpType.SlicedVararg:
				assert(src.index2 == reg, "pop to regs - trying to pop sliced varargs to different reg");
				mCode[src.index].rt = cast(ushort)(num + 1);
				break;

			case ExpType.Call, ExpType.Yield:
				assert(src.index2 == reg, "pop to regs - trying to pop func call or yield to different reg");
				mCode[src.index].rt = cast(ushort)(num + 1);
				freeExpTempRegs(*src);
				break;

			default:
				assert(false, "pop to regs switch");
		}
	}

	public void popReflexOp(uint line, Op type, uint rd, uint rs, uint rt = 0)
	{
		auto dest = pushExp();
		dest.type = ExpType.NeedsDest;
		dest.index = codeR(line, type, rd, rs, rt);

		popAssign(line);
	}

	public void popMoveFromReg(uint line, uint srcReg)
	{
		auto dest = popExp();
		
		switch(dest.type)
		{
			case ExpType.Var:
				if(dest.index != srcReg)
				{
					if(isLocalTag(dest.index))
						codeR(line, Op.MoveLocal, dest.index, srcReg, 0);
					else
						codeR(line, Op.Move, dest.index, srcReg, 0);
				}
				break;
				
			case ExpType.NewGlobal:
				codeR(line, Op.NewGlobal, 0, srcReg, dest.index);
				break;

			case ExpType.Indexed:
				codeR(line, Op.IndexAssign, dest.index, dest.index2, srcReg);
				freeExpTempRegs(*dest);
				break;

			case ExpType.Field:
				codeR(line, Op.FieldAssign, dest.index, dest.index2, srcReg);
				freeExpTempRegs(*dest);
				break;

			case ExpType.IndexedVararg:
				codeR(line, Op.VargIndexAssign, 0, dest.index, srcReg);
				freeExpTempRegs(*dest);
				break;

			case ExpType.Sliced:
				codeR(line, Op.SliceAssign, dest.index, srcReg, 0);
				freeExpTempRegs(*dest);
				break;

			case ExpType.Length:
				codeR(line, Op.LengthAssign, dest.index, srcReg, 0);
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

	public void unOp(uint line, Op type)
	{
		auto src = popExp();
		toSource(line, src);

		uint pc = codeR(line, type, 0, src.index, 0);
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
			case ExpType.Null:
				temp.index = tagConst(codeNullConst());
				break;

			case ExpType.True:
				temp.index = tagConst(codeBoolConst(true));
				break;

			case ExpType.False:
				temp.index = tagConst(codeBoolConst(false));
				break;

			case ExpType.Const:
				temp.index = e.index;
				break;

			case ExpType.Var:
				temp.index = e.index;
				break;

			case ExpType.Indexed:
				if(cleanup)
					freeExpTempRegs(*e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op.Index, temp.index, e.index, e.index2);
				break;

			case ExpType.Field:
				if(cleanup)
					freeExpTempRegs(*e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op.Field, temp.index, e.index, e.index2);
				break;

			case ExpType.IndexedVararg:
				if(cleanup)
					freeExpTempRegs(*e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op.VargIndex, temp.index, e.index, 0);
				break;

			case ExpType.Sliced:
				if(cleanup)
					freeExpTempRegs(*e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op.Slice, temp.index, e.index, 0);
				break;

			case ExpType.Length:
				if(cleanup)
					freeExpTempRegs(*e);

				temp.index = pushRegister();
				temp.isTempReg = true;
				codeR(line, Op.Length, temp.index, e.index, 0);
				break;

			case ExpType.NeedsDest:
				temp.index = pushRegister();
				mCode[e.index].rd = cast(ushort)temp.index;
				temp.isTempReg = true;
				break;

			case ExpType.Call, ExpType.Yield:
				mCode[e.index].rt = 2;
				temp.index = e.index2;
				temp.isTempReg = e.isTempReg2;
				break;

			case ExpType.Src:
				temp = *e;
				break;

			case ExpType.Vararg:
				temp.index = pushRegister();
				codeI(line, Op.Vararg, temp.index, 2);
				temp.isTempReg = true;
				break;

			case ExpType.SlicedVararg:
				if(cleanup)
					freeExpTempRegs(*e);

				codeI(line, Op.VargSlice, e.index, 2);
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
			case ExpType.Null:
				codeR(line, Op.LoadNull, dest, 0, 0);
				break;

			case ExpType.True:
				codeR(line, Op.LoadBool, dest, 1, 0);
				break;

			case ExpType.False:
				codeR(line, Op.LoadBool, dest, 0, 0);
				break;

			case ExpType.Const:
				if(isLocalTag(dest))
					codeR(line, Op.LoadConst, dest, src.index, 0);
				else
					codeR(line, Op.Move, dest, src.index, 0);
				break;

			case ExpType.Var:
				if(dest != src.index)
				{
					if(isLocalTag(dest) && isLocalTag(src.index))
						codeR(line, Op.MoveLocal, dest, src.index, 0);
					else
						codeR(line, Op.Move, dest, src.index, 0);
				}
				break;

			case ExpType.Indexed:
				codeR(line, Op.Index, dest, src.index, src.index2);
				freeExpTempRegs(*src);
				break;

			case ExpType.Field:
				codeR(line, Op.Field, dest, src.index, src.index2);
				freeExpTempRegs(*src);
				break;

			case ExpType.IndexedVararg:
				codeR(line, Op.VargIndex, dest, src.index, 0);
				freeExpTempRegs(*src);
				break;

			case ExpType.Sliced:
				codeR(line, Op.Slice, dest, src.index, 0);
				freeExpTempRegs(*src);
				break;

			case ExpType.Length:
				codeR(line, Op.Length, dest, src.index, 0);
				freeExpTempRegs(*src);
				break;

			case ExpType.Vararg:
				if(isLocalTag(dest))
					codeI(line, Op.Vararg, dest, 2);
				else
				{
					assert(!isConstTag(dest), "moveTo vararg dest is const");
					uint tempReg = pushRegister();
					codeI(line, Op.Vararg, tempReg, 2);
					codeR(line, Op.Move, dest, tempReg, 0);
					popRegister(tempReg);
				}
				break;
				
			case ExpType.SlicedVararg:
				mCode[src.index].uimm = 2;
				
				if(dest != src.index2)
				{
					if(isLocalTag(dest) && isLocalTag(src.index2))
						codeR(line, Op.MoveLocal, dest, src.index2, 0);
					else
						codeR(line, Op.Move, dest, src.index2, 0);
				}
				break;

			case ExpType.Call, ExpType.Yield:
				mCode[src.index].rt = 2;

				if(dest != src.index2)
				{
					if(isLocalTag(dest) && isLocalTag(src.index2))
						codeR(line, Op.MoveLocal, dest, src.index2, 0);
					else
						codeR(line, Op.Move, dest, src.index2, 0);
				}

				freeExpTempRegs(*src);
				break;

			case ExpType.NeedsDest:
				mCode[src.index].rd = cast(ushort)dest;
				break;

			case ExpType.Src:
				if(dest != src.index)
				{
					if(isLocalTag(dest) && isLocalTag(src.index))
						codeR(line, Op.MoveLocal, dest, src.index, 0);
					else
						codeR(line, Op.Move, dest, src.index, 0);
				}

				freeExpTempRegs(*src);
				break;

			default:
				assert(false, "moveTo switch");
		}
	}

	public void makeTailcall()
	{
		assert(mCode[$ - 1].opcode == Op.Call, "need call to make tailcall");
		mCode[$ - 1].opcode = Op.Tailcall;
	}
	
	public void codeClosure(FuncState fs, uint destReg)
	{
		if(!fs.mIsPure)
			mIsPure = false;

		auto line = fs.mLocation.line;
		codeR(line, Op.Closure, destReg, mInnerFuncs.length, 0);

		foreach(ref ud; fs.mUpvals)
			codeR(line, Op.Move, ud.isUpvalue ? 1 : 0, ud.index, 0);

		auto fd = fs.toFuncDef();
		t.vm.alloc.resizeArray(mInnerFuncs, mInnerFuncs.length + 1);
		mInnerFuncs[$ - 1] = fd;
	}

	// ---------------------------------------------------------------------------
	// Control flow

	public uint here()
	{
		return mCode.length;
	}

	public void patchJumpTo(uint src, uint dest)
	{
		mCode[src].imm = dest - src - 1;
	}

	public void patchJumpToHere(uint src)
	{
		patchJumpTo(src, here());
	}

	package void patchListTo(uint j, uint dest)
	{
		uint next = void;

		for( ; j != NoJump; j = next)
		{
			next = mCode[j].uimm;
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
		mScope.continues = NoJump;
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
		auto pc = &i.trueList;
		uint* next = null;

		for( ; *pc !is NoJump; pc = next)
			next = &mCode[*pc].uimm;

		*pc = j;
	}
	
	public void catToFalse(ref InstRef i, uint j)
	{
		auto pc = &i.falseList;
		uint* next = null;

		for( ; *pc !is NoJump; pc = next)
			next = &mCode[*pc].uimm;

		*pc = j;
	}

	public void invertJump(ref InstRef i)
	{
		debug assert(!i.inverted);
		debug i.inverted = true;

		auto j = i.trueList;
		assert(j !is NoJump);
		i.trueList = mCode[j].uimm;
		mCode[j].uimm = i.falseList;
		i.falseList = j;
		mCode[j].rd = !mCode[j].rd;
	}

	public void codeJump(uint line, uint dest)
	{
		codeJ(line, Op.Jmp, true, dest - here() - 1);
	}

	public uint makeJump(uint line, Op type = Op.Jmp, bool isTrue = true)
	{
		return codeJ(line, type, isTrue, NoJump);
	}

	public uint makeFor(uint line, uint baseReg)
	{
		return codeJ(line, Op.For, baseReg, NoJump);
	}

	public uint makeForLoop(uint line, uint baseReg)
	{
		return codeJ(line, Op.ForLoop, baseReg, NoJump);
	}

	public uint codeCatch(uint line, out uint checkReg)
	{
		checkReg = mFreeReg;
		return codeJ(line, Op.PushCatch, mFreeReg, NoJump);
	}

	public uint codeFinally(uint line)
	{
		return codeJ(line, Op.PushFinally, 0, NoJump);
	}

	public void codeContinue(CompileLoc location)
	{
		if(mScope.continueScope is null)
			c.exception(location, "No continuable control structure");

		if(mScope.continueScope.hasUpval)
			codeClose(location.line, mScope.continueScope.regStart);

		mScope.continueScope.continues = codeJ(location.line, Op.Jmp, 1, mScope.continueScope.continues);
	}

	public void codeBreak(CompileLoc location)
	{
		if(mScope.breakScope is null)
			c.exception(location, "No breakable control structure");

		if(mScope.breakScope.hasUpval)
			codeClose(location.line, mScope.breakScope.regStart);

		mScope.breakScope.breaks = codeJ(location.line, Op.Jmp, 1, mScope.breakScope.breaks);
	}

	// ---------------------------------------------------------------------------
	// Constants

	public int codeConst(MDValue v)
	{
		foreach(i, ref con; mConstants)
			if(con == v)
				return i;

		mConstants.append(c.alloc, v);

		if(mConstants.length >= MaxConstants)
			c.exception(mLocation, "Too many constants in function");

		return mConstants.length - 1;
	}

	public int codeNullConst()
	{
		return codeConst(MDValue.nullValue);
	}

	public int codeBoolConst(bool b)
	{
		return codeConst(MDValue(b));
	}

	public int codeIntConst(mdint x)
	{
		return codeConst(MDValue(x));
	}

	public int codeFloatConst(mdfloat x)
	{
		return codeConst(MDValue(x));
	}

	public int codeCharConst(dchar x)
	{
		return codeConst(MDValue(x));
	}

	public int codeStringConst(char[] s)
	{
		return codeConst(MDValue(string.create(t.vm, s)));
	}

	public void codeNulls(uint line, uint reg, uint num)
	{
		codeI(line, Op.LoadNulls, reg, num);
	}

	// ---------------------------------------------------------------------------
	// Raw codegen funcs
	
	package uint codeR(uint line, Op opcode, uint dest, uint src1, uint src2)
	{
		Instruction i = void;
		i.opcode = opcode;
		i.rd = cast(ushort)dest;
		i.rs = cast(ushort)src1;
		i.rt = cast(ushort)src2;

		debug(WRITECODE) Stdout.formatln(i.toString());

		mLineInfo.append(c.alloc, line);
		mCode.append(c.alloc, i);
		return mCode.length - 1;
	}

	package uint codeI(uint line, Op opcode, uint dest, uint imm)
	{
		Instruction i = void;
		i.opcode = opcode;
		i.rd = cast(ushort)dest;
		i.uimm = imm;

		debug(WRITECODE) Stdout.formatln(i.toString());

		mLineInfo.append(c.alloc, line);
		mCode.append(c.alloc, i);
		return mCode.length - 1;
	}

	package uint codeJ(uint line, Op opcode, uint dest, int offs)
	{
		Instruction i = void;
		i.opcode = opcode;
		i.rd = cast(ushort)dest;
		i.imm = offs;

		debug(WRITECODE) Stdout.formatln(i.toString());

		mLineInfo.append(c.alloc, line);
		mCode.append(c.alloc, i);
		return mCode.length - 1;
	}

	// ---------------------------------------------------------------------------
	// Conversion to function definition

	package MDFuncDef* toFuncDef()
	{
		debug(SHOWME)
		{
			showMe();
			Stdout.flush;
		}

		auto ret = funcdef.create(*c.alloc);
		pushFuncDef(t, ret);

		ret.location.file = string.create(t.vm, mLocation.file);
		ret.location.line = mLocation.line;
		ret.location.col = mLocation.col;
		ret.isVararg = mIsVararg;
		ret.name = string.create(t.vm, mName);
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

		ret.isPure = mIsPure;

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
			ret.upvalNames[i] = string.create(t.vm, u.name);

		c.alloc.resizeArray(ret.locVarDescs, mLocVars.length);

		foreach(i, ref var; mLocVars)
		{
			ret.locVarDescs[i].name = string.create(t.vm, var.name);
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
				case MDValue.Type.Null:   Stdout.formatln("\tConst {}: null", i); break;
				case MDValue.Type.Bool:   Stdout.formatln("\tConst {}: {}", i, c.mBool); break;
				case MDValue.Type.Int:    Stdout.formatln("\tConst {}: {}", i, c.mInt); break;
				case MDValue.Type.Float:  Stdout.formatln("\tConst {}: {:f6}f", i, c.mFloat); break;
				case MDValue.Type.Char:   Stdout.formatln("\tConst {}: '{}'", i, c.mChar); break;
				case MDValue.Type.String: Stdout.formatln("\tConst {}: \"{}\"", i, c.mString.toString()); break;
				default: assert(false);
			}
		}

		foreach(i, inst; mCode)
			Stdout.formatln("\t[{,3}:{,4}] {}", i, mLineInfo[i], inst.toString());
	}
}

class Codegen : Visitor
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
				fs.codeI(d.code.endLocation.line, Op.Ret, 0, 1);
			fs.popScope(d.code.endLocation.line);
		}

		auto def = fs_.toFuncDef();
		pushFunction(c.thread, func.create(*c.alloc, c.thread.vm.globals, def));
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
				foreach(stmt; m.statements)
					visit(stmt);

				fs.codeI(m.endLocation.line, Op.Ret, 0, 1);
			fs.popScope(m.endLocation.line);
			
			assert(fs.mExpSP == 0, "module - not all expressions have been popped");
		}
		finally
		{
			debug(PRINTEXPSTACK)
				fs.printExpStack();
		}

		auto def = fs_.toFuncDef();
		pushFunction(c.thread, func.create(*c.alloc, c.thread.vm.globals, def));
		insertAndPop(c.thread, -2);

		return m;
	}

	public override ObjectDef visit(ObjectDef d)
	{
		visit(d.baseObject);
		Exp base;
		fs.popSource(d.location.line, base);
		fs.freeExpTempRegs(base);

		auto destReg = fs.pushRegister();
		auto nameConst = d.name is null ? fs.tagConst(fs.codeNullConst()) : fs.tagConst(fs.codeStringConst(d.name.name));
		fs.codeR(d.location.line, Op.Object, destReg, nameConst, base.index);

		foreach(ref field; d.fields)
		{
			auto index = fs.tagConst(fs.codeStringConst(field.name));

			visit(field.initializer);
			Exp val;
			fs.popSource(field.initializer.endLocation.line, val);
			fs.codeR(field.initializer.endLocation.line, Op.FieldAssign, destReg, index, val.index);
			fs.freeExpTempRegs(val);
		}

		fs.pushTempReg(destReg);
		return d;
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
				fs.codeI(d.code.endLocation.line, Op.Ret, 0, 1);
			fs.popScope(d.code.endLocation.line);
		}

		auto destReg = fs.pushRegister();
		fs.codeClosure(inner, destReg);

		fs.pushTempReg(destReg);
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
			fs.codeI(s.def.code.location.line, Op.CheckParams, 0, 0);

		foreach(idx, ref p; s.def.params)
		{
			foreach(t; p.objectTypes)
			{
				visit(t);
				Exp src;
				fs.popSource(t.endLocation.line, src);
				fs.freeExpTempRegs(src);
				fs.codeR(t.endLocation.line, Op.CheckObjParam, 0, fs.tagLocal(idx), src.index);
			}
		}
		
		return s;
	}

	public override ImportStmt visit(ImportStmt s)
	{
		foreach(i, sym; s.symbols)
		{
			if(s.importName !is null && sym.name == s.importName.name)
			{
				auto loc = s.importName.location;
				c.exception(sym.location, "Variable '{}' conflicts with previous definition at {}({}:{})", sym.name, loc.file, loc.line, loc.col);
			}

			foreach(sym2; s.symbols[0 .. i])
			{
				if(sym.name == sym2.name)
				{
					auto loc = sym2.location;
					c.exception(sym.location, "Variable '{}' conflicts with previous definition at {}({}:{})", sym.name, loc.file, loc.line, loc.col);
				}
			}
		}

		if(s.importName is null)
		{
			auto firstReg = fs.nextRegister();

			foreach(sym; s.symbols)
				fs.pushRegister();

			// push then pop to ensure the stack size is set correctly.
			auto importReg = fs.pushRegister();
			fs.popRegister(importReg);

			visit(s.expr);
			Exp src;
			fs.popSource(s.location.line, src);
			fs.freeExpTempRegs(src);

			fs.codeR(s.location.line, Op.Import, importReg, src.index, 0);

			for(int reg = firstReg + s.symbols.length - 1; reg >= cast(int)firstReg; reg--)
				fs.popRegister(reg);

			foreach(i, sym; s.symbols)
			{
				fs.codeR(s.location.line, Op.Field, firstReg + i, importReg, fs.tagConst(fs.codeStringConst(sym.name)));
				fs.insertLocal(s.symbolNames[i]);
			}

			fs.activateLocals(s.symbols.length);
		}
		else
		{
			auto importReg = fs.nextRegister();

			visit(s.expr);
			Exp src;
			fs.popSource(s.location.line, src);
			fs.freeExpTempRegs(src);

			fs.codeR(s.location.line, Op.Import, importReg, src.index, 0);

			fs.insertLocal(s.importName);
			fs.activateLocals(1);

			auto firstReg = fs.nextRegister();

			foreach(i, sym; s.symbols)
			{
				fs.codeR(s.location.line, Op.Field, firstReg + i, importReg, fs.tagConst(fs.codeStringConst(sym.name)));
				fs.insertLocal(s.symbolNames[i]);
			}

			fs.activateLocals(s.symbols.length);
		}
		
		return s;
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
	
	public override OtherDecl visit(OtherDecl d)
	{
		if(d.protection == Protection.Local)
		{
			fs.insertLocal(d.name);
			fs.activateLocals(1);
			fs.pushVar(d.name);
		}
		else
		{
			assert(d.protection == Protection.Global);
			fs.pushNewGlobal(d.name);
		}

		visit(d.expr);
		fs.popAssign(d.endLocation.line);
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
					c.exception(n.location, "Variable '{}' conflicts with previous definition at {}({}:{})", n.name, loc.file, loc.line, loc.col);
				}
			}
		}

		if(d.protection == Protection.Global)
		{
			if(d.initializer)
			{
				if(d.names.length == 1)
				{
					fs.pushNewGlobal(d.names[0]);
					visit(d.initializer);
					fs.popAssign(d.initializer.endLocation.line);
				}
				else
				{
					d.initializer.checkMultRet(c);

					foreach(n; d.names)
						fs.pushNewGlobal(n);

					auto reg = fs.nextRegister();
					visit(d.initializer);
					fs.popToRegisters(d.endLocation.line, reg, d.names.length);

					for(int r = reg + d.names.length - 1; r >= cast(int)reg; r--)
						fs.popMoveFromReg(d.endLocation.line, r);
				}
			}
			else
			{
				foreach(n; d.names)
				{
					fs.pushNewGlobal(n);
					fs.pushNull();
					fs.popAssign(n.location.line);
				}
			}
		}
		else
		{
			assert(d.protection == Protection.Local);

			if(d.initializer)
			{
				if(d.names.length == 1)
				{
					auto destReg = fs.nextRegister();
					visit(d.initializer);
					fs.popMoveTo(d.location.line, destReg);
					fs.insertLocal(d.names[0]);
				}
				else
				{
					auto destReg = fs.nextRegister();
					d.initializer.checkMultRet(c);
					visit(d.initializer);
					fs.popToRegisters(d.location.line, destReg, d.names.length);

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
		Scope scop = void;
		fs.pushScope(scop);
		
		InstRef i = void;

		if(s.condVar !is null)
		{
			auto destReg = fs.nextRegister();
			visit(s.condition);
			fs.popMoveTo(s.location.line, destReg);
			fs.insertLocal(s.condVar.name);
			fs.activateLocals(1);

			i = codeCondition(s.condVar);
		}
		else
			i = codeCondition(s.condition);

		fs.invertJump(i);
		fs.patchTrueToHere(i);
		visit(s.ifBody);

		if(s.elseBody)
		{
			fs.popScope(s.ifBody.endLocation.line);

			auto j = fs.makeJump(s.elseBody.location.line);
			fs.patchFalseToHere(i);

			fs.pushScope(scop);
				visit(s.elseBody);
			fs.popScope(s.endLocation.line);

			fs.patchJumpToHere(j);
		}
		else
		{
			fs.popScope(s.ifBody.endLocation.line);
			fs.patchFalseToHere(i);
		}

		return s;
	}
	
	public override WhileStmt visit(WhileStmt s)
	{
		auto beginLoop = fs.here();

		Scope scop = void;
		fs.pushScope(scop);

		if(s.condition.isConstant && s.condition.isTrue)
		{
			if(s.condVar !is null)
			{
				fs.setBreakable();
				fs.setContinuable();

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
			visit(s.code);
			fs.patchContinuesTo(beginLoop);
			fs.closeUpvals(s.endLocation.line);
			fs.codeJump(s.endLocation.line, beginLoop);
			fs.patchBreaksToHere();

			fs.popScope(s.endLocation.line);
			fs.patchFalseToHere(cond);
		}

		return s;
	}
	
	public override DoWhileStmt visit(DoWhileStmt s)
	{
		auto beginLoop = fs.here();
		Scope scop = void;
		fs.pushScope(scop);
		
		fs.setBreakable();
		fs.setContinuable();
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
		auto baseReg = fs.nextRegister();

		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();
			fs.setContinuable();

			auto loIndex = fs.nextRegister();
			visit(s.lo);
			fs.popMoveTo(s.lo.location.line, loIndex);
			fs.pushRegister();

			auto hiIndex = fs.nextRegister();
			visit(s.hi);
			fs.popMoveTo(s.hi.location.line, hiIndex);
			fs.pushRegister();

			auto stepIndex = fs.nextRegister();
			visit(s.step);
			fs.popMoveTo(s.step.location.line, stepIndex);
			fs.pushRegister();

			auto beginJump = fs.makeFor(s.location.line, baseReg);
			auto beginLoop = fs.here();

			fs.insertLocal(s.index);
			fs.activateLocals(1);

			visit(s.code);

			fs.closeUpvals(s.endLocation.line);
			fs.patchContinuesToHere();

			fs.patchJumpToHere(beginJump);

			auto gotoBegin = fs.makeForLoop(s.endLocation.line, baseReg);
			fs.patchJumpTo(gotoBegin, beginLoop);

			fs.patchBreaksToHere();
		fs.popScope(s.endLocation.line);

		fs.popRegister(stepIndex);
		fs.popRegister(hiIndex);
		fs.popRegister(loIndex);

		return s;
	}
	
	public override ForeachStmt visit(ForeachStmt s)
	{
		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();
			fs.setContinuable();

			auto baseReg = fs.nextRegister();
			auto generator = fs.nextRegister();
			visit(s.container[0]);
			
			uint invState = void;
			uint control = void;

			if(s.container.length == 3)
			{
				fs.popMoveTo(s.container[0].location.line, generator);
				fs.pushRegister();

				invState = fs.nextRegister();
				visit(s.container[1]);
				fs.popMoveTo(s.container[1].location.line, invState);
				fs.pushRegister();

				control = fs.nextRegister();
				visit(s.container[2]);
				fs.popMoveTo(s.container[2].location.line, control);
				fs.pushRegister();
			}
			else if(s.container.length == 2)
			{
				fs.popMoveTo(s.container[0].location.line, generator);
				fs.pushRegister();

				invState = fs.nextRegister();
				visit(s.container[1]);

				if(s.container[1].isMultRet())
				{
					fs.popToRegisters(s.container[1].location.line, invState, 2);
					fs.pushRegister();
					control = fs.pushRegister();
				}
				else
				{
					fs.popMoveTo(s.container[1].location.line, invState);
					fs.pushRegister();
					control = fs.pushRegister();
					fs.codeNulls(s.container[1].location.line, control, 1);
				}
			}
			else
			{
				if(s.container[0].isMultRet())
				{
					fs.popToRegisters(s.container[0].location.line, generator, 3);
					fs.pushRegister();
					invState = fs.pushRegister();
					control = fs.pushRegister();
				}
				else
				{
					fs.popMoveTo(s.container[0].location.line, generator);
					fs.pushRegister();
					invState = fs.pushRegister();
					control = fs.pushRegister();
					fs.codeNulls(s.container[0].endLocation.line, invState, 2);
				}
			}

			auto beginJump = fs.makeJump(s.location.line);
			auto beginLoop = fs.here();

			foreach(i; s.indices)
				fs.insertLocal(i);

			fs.activateLocals(s.indices.length);
			visit(s.code);

			fs.patchJumpToHere(beginJump);
			fs.closeUpvals(s.endLocation.line);
			fs.patchContinuesToHere();
			fs.codeI(s.endLocation.line, Op.Foreach, baseReg, s.indices.length);
			
			auto gotoBegin = fs.makeJump(s.endLocation.line, Op.Je);
			fs.patchJumpTo(gotoBegin, beginLoop);
			fs.patchBreaksToHere();
		fs.popScope(s.endLocation.line);

		fs.popRegister(control);
		fs.popRegister(invState);
		fs.popRegister(generator);

		return s;
	}
	
	public override SwitchStmt visit(SwitchStmt s)
	{
		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();

			visit(s.condition);
			Exp src1;
			fs.popSource(s.location.line, src1);

			foreach(caseStmt; s.cases)
			{
				foreach(ref c; caseStmt.conditions)
				{
					if(!c.exp.isConstant)
					{
						visit(c.exp);
						Exp src2;
						fs.popSource(c.exp.location.line, src2);
						fs.freeExpTempRegs(src2);

						fs.codeR(c.exp.location.line, Op.SwitchCmp, 0, src1.index, src2.index);
						c.dynJump = fs.makeJump(c.exp.location.line, Op.Je, true);
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

		return s;
	}
	
	public override CaseStmt visit(CaseStmt s)
	{
		foreach(c; s.conditions)
		{
			if(c.exp.isConstant)
				fs.addCase(c.exp.location, c.exp);
			else
				fs.patchJumpToHere(c.dynJump);
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
		fs.codeContinue(s.location);
		return s;
	}

	public override BreakStmt visit(BreakStmt s)
	{
		fs.codeBreak(s.location);
		return s;
	}
	
	public override ReturnStmt visit(ReturnStmt s)
	{
		if(s.exprs.length == 0)
		{
			fs.codeI(s.location.line, Op.Ret, 0, 1);
			return s;
		}

		auto firstReg = fs.nextRegister();

		if(s.exprs.length == 1 && (s.exprs[0].type == AstTag.CallExp || s.exprs[0].type == AstTag.MethodCallExp))
		{
			visit(s.exprs[0]);
			fs.popToRegisters(s.endLocation.line, firstReg, -1);
			fs.makeTailcall();
			fs.codeI(s.endLocation.line, Op.Ret, firstReg, 0);
		}
		else
		{
			codeGenListToNextReg(s.exprs);

			if(s.exprs[$ - 1].isMultRet())
				fs.codeI(s.endLocation.line, Op.Ret, firstReg, 0);
			else
				fs.codeI(s.endLocation.line, Op.Ret, firstReg, s.exprs.length + 1);
		}

		return s;
	}
	
	public override TryStmt visit(TryStmt s)
	{
		if(s.finallyBody)
		{
			auto pushFinally = fs.codeFinally(s.location.line);

			if(s.catchBody)
			{
				uint checkReg1;
				auto pushCatch = fs.codeCatch(s.location.line, checkReg1);

				visit(s.tryBody);

				fs.codeI(s.tryBody.endLocation.line, Op.PopCatch, 0, 0);
				fs.codeI(s.tryBody.endLocation.line, Op.PopFinally, 0, 0);
				auto jumpOverCatch = fs.makeJump(s.tryBody.endLocation.line);
				fs.patchJumpToHere(pushCatch);

				Scope scop = void;
				fs.pushScope(scop);
					auto checkReg2 = fs.insertLocal(s.catchVar);

					assert(checkReg1 == checkReg2, "catch var register is not right");

					fs.activateLocals(1);
					visit(s.catchBody);
				fs.popScope(s.catchBody.endLocation.line);

				fs.codeI(s.catchBody.endLocation.line, Op.PopFinally, 0, 0);
				fs.patchJumpToHere(jumpOverCatch);
				fs.patchJumpToHere(pushFinally);

				visit(s.finallyBody);

				fs.codeI(s.finallyBody.endLocation.line, Op.EndFinal, 0, 0);
			}
			else
			{
				visit(s.tryBody);
				fs.codeI(s.tryBody.endLocation.line, Op.PopFinally, 0, 0);

				fs.patchJumpToHere(pushFinally);

				visit(s.finallyBody);
				fs.codeI(s.finallyBody.endLocation.line, Op.EndFinal, 0, 0);
			}
		}
		else
		{
			assert(s.catchBody !is null);

			uint checkReg1;
			auto pushCatch = fs.codeCatch(s.location.line, checkReg1);

			visit(s.tryBody);

			fs.codeI(s.tryBody.endLocation.line, Op.PopCatch, 0, 0);
			auto jumpOverCatch = fs.makeJump(s.tryBody.endLocation.line);
			fs.patchJumpToHere(pushCatch);

			Scope scop = void;
			fs.pushScope(scop);
				auto checkReg2 = fs.insertLocal(s.catchVar);

				assert(checkReg1 == checkReg2, "catch var register is not right");

				fs.activateLocals(1);
				visit(s.catchBody);
			fs.popScope(s.catchBody.endLocation.line);

			fs.patchJumpToHere(jumpOverCatch);
		}

		return s;
	}
	
	public override ThrowStmt visit(ThrowStmt s)
	{
		visit(s.exp);
		Exp src;
		fs.popSource(s.location.line, src);
		fs.freeExpTempRegs(src);
		fs.codeR(s.endLocation.line, Op.Throw, 0, src.index, 0);
		return s;
	}
	
	public override AssignStmt visit(AssignStmt s)
	{
		foreach(exp; s.lhs)
			exp.checkLHS(c);

		if(s.lhs.length == 1)
		{
			visit(s.lhs[0]);
			visit(s.rhs);
			fs.popAssign(s.endLocation.line);
		}
		else
		{
			s.rhs.checkMultRet(c);

			foreach(dest; s.lhs)
				visit(dest);

			auto numTemps = fs.resolveAssignmentConflicts(s.lhs[$ - 1].location.line, s.lhs.length);
			auto RHSReg = fs.nextRegister();
			
			visit(s.rhs);
			
			fs.popToRegisters(s.endLocation.line, RHSReg, s.lhs.length);
			fs.popAssignmentConflicts(numTemps);

			for(int reg = RHSReg + s.lhs.length - 1; reg >= cast(int)RHSReg; reg--)
				fs.popMoveFromReg(s.endLocation.line, reg);
		}
		
		return s;
	}

	public OpAssignStmt visitOpAssign(OpAssignStmt s)
	{
		visit(s.lhs);
		fs.pushSource(s.lhs.endLocation.line);

		Exp src1;
		fs.popSource(s.lhs.endLocation.line, src1);
		visit(s.rhs);
		Exp src2;
		fs.popSource(s.endLocation.line, src2);

		fs.freeExpTempRegs(src2);
		fs.freeExpTempRegs(src1);

		fs.popReflexOp(s.endLocation.line, AstTagToOpcode(s.type), src1.index, src2.index);

		return s;
	}

	public override AddAssignStmt visit(AddAssignStmt s)   { if(s.lhs.type != AstTag.ThisExp) s.lhs.checkLHS(c); return visitOpAssign(s); }
	public override SubAssignStmt visit(SubAssignStmt s)   { if(s.lhs.type != AstTag.ThisExp) s.lhs.checkLHS(c); return visitOpAssign(s); }
	public override MulAssignStmt visit(MulAssignStmt s)   { if(s.lhs.type != AstTag.ThisExp) s.lhs.checkLHS(c); return visitOpAssign(s); }
	public override DivAssignStmt visit(DivAssignStmt s)   { if(s.lhs.type != AstTag.ThisExp) s.lhs.checkLHS(c); return visitOpAssign(s); }
	public override ModAssignStmt visit(ModAssignStmt s)   { if(s.lhs.type != AstTag.ThisExp) s.lhs.checkLHS(c); return visitOpAssign(s); }
	public override ShlAssignStmt visit(ShlAssignStmt s)   { if(s.lhs.type != AstTag.ThisExp) s.lhs.checkLHS(c); return visitOpAssign(s); }
	public override ShrAssignStmt visit(ShrAssignStmt s)   { if(s.lhs.type != AstTag.ThisExp) s.lhs.checkLHS(c); return visitOpAssign(s); }
	public override UShrAssignStmt visit(UShrAssignStmt s) { if(s.lhs.type != AstTag.ThisExp) s.lhs.checkLHS(c); return visitOpAssign(s); }
	public override XorAssignStmt visit(XorAssignStmt s)   { if(s.lhs.type != AstTag.ThisExp) s.lhs.checkLHS(c); return visitOpAssign(s); }
	public override OrAssignStmt visit(OrAssignStmt s)     { if(s.lhs.type != AstTag.ThisExp) s.lhs.checkLHS(c); return visitOpAssign(s); }
	public override AndAssignStmt visit(AndAssignStmt s)   { if(s.lhs.type != AstTag.ThisExp) s.lhs.checkLHS(c); return visitOpAssign(s); }
	public override CondAssignStmt visit(CondAssignStmt s) { s.lhs.checkLHS(c); return visitOpAssign(s); }
	
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
		fs.popReflexOp(s.endLocation.line, Op.CatEq, src1.index, firstReg, s.operands.length);
		
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

		fs.popReflexOp(s.endLocation.line, Op.Inc, src.index, 0);

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

		fs.popReflexOp(s.endLocation.line, Op.Dec, src.index, 0);

		return s;
	}
	
	public override FuncEnvStmt visit(FuncEnvStmt s)
	{
		Exp exp;
		
		fs.pushVar(s.funcName);
		fs.popSource(s.location.line, exp);
		fs.freeExpTempRegs(exp);
		auto funcIdx = exp.index;

		fs.pushVar(s.envName);
		fs.popSource(s.location.line, exp);
		fs.freeExpTempRegs(exp);
		auto envIdx = exp.index;
		
		fs.codeR(s.endLocation.line, Op.SetEnv, funcIdx, envIdx, 0);
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
		auto i = fs.makeJump(e.op1.endLocation.line, Op.Jmp);

		fs.patchFalseToHere(c);

		visit(e.op2);
		fs.popMoveTo(e.endLocation.line, temp);
		fs.patchJumpToHere(i);

		fs.pushTempReg(temp);
		
		return e;
	}

	public override OrOrExp visit(OrOrExp e)
	{
		auto temp = fs.pushRegister();
		visit(e.op1);
		fs.popMoveTo(e.op1.endLocation.line, temp);
		fs.codeR(e.op1.endLocation.line, Op.IsTrue, 0, temp, 0);
		auto i = fs.makeJump(e.op1.endLocation.line, Op.Je);
		visit(e.op2);
		fs.popMoveTo(e.endLocation.line, temp);
		fs.patchJumpToHere(i);
		fs.pushTempReg(temp);
		
		return e;
	}
	
	public override AndAndExp visit(AndAndExp e)
	{
		auto temp = fs.pushRegister();
		visit(e.op1);
		fs.popMoveTo(e.op1.endLocation.line, temp);
		fs.codeR(e.op1.endLocation.line, Op.IsTrue, 0, temp, 0);
		auto i = fs.makeJump(e.op1.endLocation.line, Op.Je, false);
		visit(e.op2);
		fs.popMoveTo(e.endLocation.line, temp);
		fs.patchJumpToHere(i);
		fs.pushTempReg(temp);
		
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

		fs.pushBinOp(e.endLocation.line, AstTagToOpcode(e.type), src1.index, src2.index);

		return e;
	}
	
	public override BinaryExp visit(OrExp e)    { return visitBinExp(e); }
	public override BinaryExp visit(XorExp e)   { return visitBinExp(e); }
	public override BinaryExp visit(AndExp e)   { return visitBinExp(e); }
	public override BinaryExp visit(AsExp e)    { return visitBinExp(e); }
	public override BinaryExp visit(InExp e)    { return visitBinExp(e); }
	public override BinaryExp visit(NotInExp e) { return visitBinExp(e); }
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
		fs.pushBinOp(e.endLocation.line, Op.Cat, firstReg, e.operands.length);
		
		return e;
	}

	public BinaryExp visitComparisonExp(BinaryExp e)
	{
		auto temp = fs.pushRegister();
		auto i = codeCondition(e);
		fs.pushBool(false);
		fs.popMoveTo(e.endLocation.line, temp);
		auto j = fs.makeJump(e.endLocation.line, Op.Jmp);
		fs.patchTrueToHere(i);
		fs.pushBool(true);
		fs.popMoveTo(e.endLocation.line, temp);
		fs.patchJumpToHere(j);
		fs.pushTempReg(temp);

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
		fs.unOp(e.endLocation.line, AstTagToOpcode(e.type));
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
		return e;
	}

	public override VargLenExp visit(VargLenExp e)
	{
		if(!fs.mIsVararg)
			c.exception(e.location, "'vararg' cannot be used in a non-variadic function");

		fs.pushVargLen(e.endLocation.line);
		return e;
	}
	
	public override DotExp visit(DotExp e)
	{
		visit(e.op);
		fs.topToSource(e.endLocation.line);
		visit(e.name);
		fs.popField(e.endLocation.line);
		return e;
	}
	
	public override DotSuperExp visit(DotSuperExp e)
	{
		visit(e.op);
		fs.unOp(e.endLocation.line, Op.SuperOf);
		return e;
	}
	
	public override MethodCallExp visit(MethodCallExp e)
	{
		auto funcReg = fs.nextRegister();
		Exp src;

		if(e.isSuperCall)
			fs.pushThis();
		else
			visit(e.op);

		fs.popSource(e.location.line, src);
		fs.freeExpTempRegs(src);
		assert(fs.nextRegister() == funcReg);

		fs.pushRegister();

		Exp meth;
		visit(e.method);
		fs.popSource(e.method.endLocation.line, meth);
		fs.freeExpTempRegs(meth);

		auto thisReg = fs.nextRegister();

		if(e.context)
		{
			assert(!e.isSuperCall);
			visit(e.context);
			fs.popMoveTo(e.context.endLocation.line, thisReg);
		}

		fs.pushRegister();

		codeGenListToNextReg(e.args);

		Op opcode = void;

		if(e.context is null)
			opcode = e.isSuperCall ? Op.SuperMethod : Op.Method;
		else
			opcode = Op.MethodNC;

		fs.codeR(e.endLocation.line, opcode, funcReg, src.index, meth.index);
		fs.popRegister(thisReg);

		if(e.args.length == 0)
			fs.pushCall(e.endLocation.line, funcReg, 2);
		else if(e.args[$ - 1].isMultRet())
			fs.pushCall(e.endLocation.line, funcReg, 0);
		else
			fs.pushCall(e.endLocation.line, funcReg, e.args.length + 2);

		return e;
	}
	
	public override CallExp visit(CallExp e)
	{
		auto funcReg = fs.nextRegister();

		visit(e.op);
		fs.popMoveTo(e.op.endLocation.line, funcReg);

		assert(fs.nextRegister() == funcReg);

		fs.pushRegister();
		auto thisReg = fs.nextRegister();

		if(e.context)
			visit(e.context);
		else
			fs.pushNull();

		fs.popMoveTo(e.op.endLocation.line, thisReg);
		fs.pushRegister();

		codeGenListToNextReg(e.args);

		fs.popRegister(thisReg);

		if(e.args.length == 0)
			fs.pushCall(e.endLocation.line, funcReg, 2);
		else if(e.args[$ - 1].isMultRet())
			fs.pushCall(e.endLocation.line, funcReg, 0);
		else
			fs.pushCall(e.endLocation.line, funcReg, e.args.length + 2);

		return e;
	}
	
	public override IndexExp visit(IndexExp e)
	{
		visit(e.op);
		fs.topToSource(e.endLocation.line);
		visit(e.index);
		fs.popIndex(e.endLocation.line);
		return e;
	}
	
	public override VargIndexExp visit(VargIndexExp e)
	{
		if(!fs.mIsVararg)
			c.exception(e.location, "'vararg' cannot be used in a non-variadic function");

		visit(e.index);
		fs.popVargIndex(e.endLocation.line);
		
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
		return e;
	}
	
	public override VargSliceExp visit(VargSliceExp e)
	{
		if(!fs.mIsVararg)
			c.exception(e.location, "'vararg' cannot be used in a non-variadic function");

		auto reg = fs.nextRegister();
		Expression[2] list;
		list[0] = e.loIndex;
		list[1] = e.hiIndex;
		codeGenListToNextReg(list[]);
		fs.pushVargSlice(e.endLocation.line, reg);
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
			c.exception(e.location, "'vararg' cannot be used in a non-variadic function");

		fs.pushVararg();
		return e;
	}
	
	public override FuncLiteralExp visit(FuncLiteralExp e)
	{
		visit(e.def);
		return e;
	}
	
	public override ObjectLiteralExp visit(ObjectLiteralExp e)
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
		
		return e;
	}
	
	public override RawNamespaceExp visit(RawNamespaceExp e)
	{
		auto nameIdx = fs.codeStringConst(e.name.name);

		if(e.parent is null)
		{
			auto exp = fs.pushExp();
			exp.type = ExpType.NeedsDest;
			exp.index = fs.codeR(e.location.line, Op.NamespaceNP, 0, nameIdx, 0);
		}
		else
		{
			visit(e.parent);
			Exp src;
			fs.popSource(e.location.line, src);
			fs.freeExpTempRegs(src);
			auto exp = fs.pushExp();
			exp.type = ExpType.NeedsDest;
			exp.index = fs.codeR(e.location.line, Op.Namespace, 0, nameIdx, src.index);
		}

		return e;
	}

	public override TableCtorExp visit(TableCtorExp e)
	{
		auto destReg = fs.pushRegister();
		fs.codeI(e.location.line, Op.NewTable, destReg, 0);

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

			fs.codeR(field.value.endLocation.line, Op.IndexAssign, destReg, idx.index, val.index);
		}

		fs.pushTempReg(destReg);

		return e;
	}

	public override ArrayCtorExp visit(ArrayCtorExp e)
	{
		if(e.values.length > ArrayCtorExp.maxFields)
			c.exception(e.location, "Array constructor has too many fields (more than {})", ArrayCtorExp.maxFields);

		static uword min(uword a, uword b)
		{
			return (a > b) ? b : a;
		}

		auto destReg = fs.pushRegister();

		if(e.values.length > 0 && e.values[$ - 1].isMultRet())
			fs.codeI(e.location.line, Op.NewArray, destReg, e.values.length - 1);
		else
			fs.codeI(e.location.line, Op.NewArray, destReg, e.values.length);

		if(e.values.length > 0)
		{
			uword index = 0;
			uword fieldsLeft = e.values.length;
			uword block = 0;

			while(fieldsLeft > 0)
			{
				auto numToDo = min(fieldsLeft, Instruction.arraySetFields);
				codeGenListToNextReg(e.values[index .. index + numToDo]);
				fieldsLeft -= numToDo;

				if(fieldsLeft == 0 && e.values[$ - 1].isMultRet())
					fs.codeR(e.endLocation.line, Op.SetArray, destReg, 0, block);
				else
					fs.codeR(e.values[index + numToDo - 1].endLocation.line, Op.SetArray, destReg, numToDo + 1, block);

				index += numToDo;
				block++;
			}
		}

		fs.pushTempReg(destReg);
		
		return e;
	}

	public override AppendStmt visit(AppendStmt s)
	{
		visit(s.arrayName);
		fs.pushSource(s.arrayName.endLocation.line);

		Exp src1;
		fs.popSource(s.arrayName.endLocation.line, src1);
		visit(s.value);
		Exp src2;
		fs.popSource(s.endLocation.line, src2);

		fs.freeExpTempRegs(src2);
		fs.freeExpTempRegs(src1);

		fs.popReflexOp(s.endLocation.line, Op.Append, src1.index, src2.index);

		return s;
	}
	
	public override YieldExp visit(YieldExp e)
	{
		auto firstReg = fs.nextRegister();

		codeGenListToNextReg(e.args);

		if(e.args.length == 0)
			fs.pushYield(e.endLocation.line, firstReg, 1);
		else if(e.args[$ - 1].isMultRet())
			fs.pushYield(e.endLocation.line, firstReg, 0);
		else
			fs.pushYield(e.endLocation.line, firstReg, e.args.length + 1);
			
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
// 				if(auto be = cast(BinaryExp)e)
// 				{
					auto temp = fs.nextRegister();
					visit(e);
					fs.popMoveTo(e.endLocation.line, temp);

					fs.codeR(e.endLocation.line, Op.IsTrue, 0, temp, 0);

					InstRef ret;
					ret.trueList = fs.makeJump(e.endLocation.line, Op.Je);
					return ret;
// 				}
// 				else if(auto ue = cast(UnExp)e)
// 				{
// 					auto temp = fs.nextRegister();
// 					visit(e);
// 					fs.popMoveTo(ue.endLocation.line, temp);
// 
// 					fs.codeR(ue.endLocation.line, Op.IsTrue, 0, temp, 0);
// 
// 					InstRef ret;
// 					ret.trueList = fs.makeJump(ue.endLocation.line, Op.Je);
// 					return ret;
// 				}
// 				else if(auto pe = cast(PrimaryExp)e)
// 				{
// 					auto temp = fs.nextRegister();
// 					visit(e);
// 					fs.popMoveTo(pe.endLocation.line, temp);
//
// 					fs.codeR(pe.endLocation.line, Op.IsTrue, 0, temp, 0);
//
// 					InstRef ret;
// 					ret.trueList = fs.makeJump(pe.endLocation.line, Op.Je);
// 					return ret;
// 				}
//
// 				c.exception(e.location, "{} cannot be used as a condition", e.niceString());
		}

// 		assert(false);
	}
	
	package InstRef codeCondition(CondExp e)
	{
		auto c = codeCondition(e.cond);
		fs.invertJump(c);
		fs.patchTrueToHere(c);

		auto left = codeCondition(e.op1);
		fs.invertJump(left);
		fs.patchTrueToHere(left);

		auto trueJump = fs.makeJump(e.op1.endLocation.line, Op.Jmp, true);

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

		fs.codeR(e.endLocation.line, AstTagToOpcode(e.type), 0, src1.index, src2.index);

		InstRef ret;
		ret.trueList = fs.makeJump(e.endLocation.line, Op.Je, e.type == AstTag.EqualExp || e.type == AstTag.IsExp);
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

		fs.codeR(e.endLocation.line, Op.Cmp, 0, src1.index, src2.index);

		InstRef ret;

		switch(e.type)
		{
			case AstTag.LTExp: ret.trueList = fs.makeJump(e.endLocation.line, Op.Jlt, true); break;
			case AstTag.LEExp: ret.trueList = fs.makeJump(e.endLocation.line, Op.Jle, true); break;
			case AstTag.GTExp: ret.trueList = fs.makeJump(e.endLocation.line, Op.Jle, false); break;
			case AstTag.GEExp: ret.trueList = fs.makeJump(e.endLocation.line, Op.Jlt, false); break;
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

		fs.codeR(e.endLocation.line, Op.IsTrue, 0, src.index, 0);

		InstRef ret;
		ret.trueList = fs.makeJump(e.endLocation.line, Op.Je, true);
		return ret;
	}

	package InstRef codeCondition(ThisExp e)
	{
		visit(e);

		Exp src;
		fs.popSource(e.endLocation.line, src);
		fs.freeExpTempRegs(src);

		fs.codeR(e.endLocation.line, Op.IsTrue, 0, src.index, 0);

		InstRef ret;
		ret.trueList = fs.makeJump(e.endLocation.line, Op.Je, true);
		return ret;
	}

	package InstRef codeCondition(ParenExp e)
	{
		auto temp = fs.nextRegister();
		visit(e.exp);
		fs.popMoveTo(e.endLocation.line, temp);
		fs.codeR(e.endLocation.line, Op.IsTrue, 0, temp, 0);
		
		InstRef ret;
		ret.trueList = fs.makeJump(e.endLocation.line, Op.Je, true);
		return ret;
	}
}