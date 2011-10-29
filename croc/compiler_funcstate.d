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

// TODO: abstract codegen enough that these can be made private
package Op1 AstTagToOpcode1(AstTag tag)
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

package Op2 AstTagToOpcode2(AstTag tag)
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
	VarargSlice, // index = lo: RegOrCTIdx, index2 = hi: RegOrCTIdx
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

package const uint NoJump = Instruction.NoJump;

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

package:
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

package:
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

package:
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
			mLocVars[i].pcStart = mCode.length;
		}

		mScope.firstFreeReg = mLocVars[mLocVars.length - 1].reg + 1;
	}

private:
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
				mLocVars[i].pcEnd = mCode.length;
			}
		}
	}

	void codeClose(ref CompileLoc loc, uint reg)
	{
		codeI(loc, Op1.Close, reg, 0);
	}

	uint tagLocal(uint val)
	{
		if(val > Instruction.MaxRegisters)
			c.semException(mLocation, "Too many locals");

		return val;
	}

	uint tagConst(uint val)
	{
		return val | Instruction.constBit;
	}

	bool isLocalTag(uint val)
	{
		return (val & Instruction.constBit) == 0;
	}

	bool isConstTag(uint val)
	{
		return (val & Instruction.constBit) != 0;
	}

	// ---------------------------------------------------------------------------
	// Switches

package:
	void beginSwitch(ref SwitchDesc s, ref CompileLoc loc)
	{
		auto cond = getExp(-1);
		assert(cond.isSource());
		s.switchPC = codeR(loc, Op1.Switch, 0, cond, Exp.Empty);
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

		*mSwitch.offsets.insert(*c.alloc, val) = here() - mSwitch.switchPC - 1;
	}

	void addDefault(ref CompileLoc loc)
	{
		assert(mSwitch !is null);
		assert(mSwitch.defaultOffset == -1);

		mSwitch.defaultOffset = mCode.length - mSwitch.switchPC - 1;
	}

	// ---------------------------------------------------------------------------
	// Numeric for/foreach loops

	ForDesc beginFor(CompileLoc loc, void delegate() dg)
	{
		return beginForImpl(loc, dg, Op1.For, 3);
	}

	ForDesc beginForeach(CompileLoc loc, void delegate() dg, uint containerSize)
	{
		return beginForImpl(loc, dg, Op1.Foreach, containerSize);
	}

	ForDesc beginForImpl(CompileLoc loc, void delegate() dg, Op1 opcode, uint containerSize)
	{
		ForDesc ret;
		ret.baseReg = mFreeReg;
		pushNewLocals(3);
		dg();
		assign(loc, 3, containerSize);
		insertDummyLocal(loc, "__hidden{}");
		insertDummyLocal(loc, "__hidden{}");
		insertDummyLocal(loc, "__hidden{}");
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
		closeScopeUpvals(loc);
		patchContinuesToHere();
		patchJumpToHere(desc.beginJump);

		uint j;

		if(opcode == Op1.ForLoop)
			j = codeJ(loc, opcode, desc.baseReg, NoJump);
		else
			j = codeIMulti(loc, opcode, Op2.Je, desc.baseReg, indLength);

		patchJumpTo(j, desc.beginLoop);
		patchBreaksToHere();

		mFreeReg = desc.baseReg;
	}

	// ---------------------------------------------------------------------------
	// Register manipulation

private:
	uint nextRegister()
	{
		return mFreeReg;
	}

	uint pushRegister()
	{
		debug(REGPUSHPOP) Stdout.formatln("push {}", mFreeReg);
		mFreeReg++;

		if(mFreeReg > Instruction.MaxRegisters)
			c.semException(mLocation, "Too many registers");

		if(mFreeReg > mStackSize)
			mStackSize = mFreeReg;

		return mFreeReg - 1;
	}

	void popRegister(uint r)
	{
		mFreeReg--;
		debug(REGPUSHPOP) Stdout.formatln("pop {}, {}", mFreeReg, r);

		assert(mFreeReg >= 0, "temp reg underflow");
		assert(mFreeReg == r, (pushFormat(c.thread, "reg not freed in order (popping {}, free reg is {})", r, mFreeReg), getString(t, -1)));
	}

	// ---------------------------------------------------------------------------
	// Basic expression stack manipulation

private:
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

package:
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

package:
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

	private void pushConst(uint index)
	{
		pushExp(ExpType.Const, index);
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
				ud.index = tagLocal(e.index);

				s.mUpvals.append(c.alloc, ud);

				if(s.mUpvals.length > Instruction.MaxUpvalues)
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

	void pushVararg(ref CompileLoc loc)
	{
		auto reg = pushRegister();
		pushExp(ExpType.Vararg, codeIMulti(loc, Op1.Vararg, Op2.GetVarargs, reg, 0));
	}

	void pushVargLen(ref CompileLoc loc)
	{
		pushExp(ExpType.NeedsDest, codeIMulti(loc, Op1.Vararg, Op2.VargLen, 0, 0));
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
		codeIMulti(loc, Op1.New, Op2.Table, reg, 0);
	}

	void pushArray(ref CompileLoc loc, uword length)
	{
		auto reg = pushRegister();
		pushExp(ExpType.Temporary, reg);
		codeIMulti(loc, Op1.New, Op2.Array, reg, length);
	}

	void pushNewLocals(uword num)
	{
		auto reg = mFreeReg;

		for(; num; num--, reg++)
			pushExp(ExpType.NewLocal, reg);
	}

	// ---------------------------------------------------------------------------
	// Expression stack pops

package:
	void popToNothing()
	{
		if(mExpSP == 0)
			return;

		auto src = getExp(-1);

		if(src.type == ExpType.Call || src.type == ExpType.Yield)
			setRT(mCode[src.index], 1);

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
		codeRMulti(loc, Op1.Array, Op2.Set, arr.index, arg, block);
		pop(numItems + 1); // all items and array
	}

	void arrayAppend(ref CompileLoc loc)
	{
		debug(EXPSTACKCHECK) assert(mExpSP >= 2);

		auto arr = getExp(-2);
		auto item = getExp(-1);

		debug(EXPSTACKCHECK) assert(arr.type == ExpType.Temporary);
		debug(EXPSTACKCHECK) assert(item.isSource());

		codeRMulti(loc, Op1.Array, Op2.Append, arr.index, item, Exp.Empty);
		pop(2);
	}

	void customParamFail(ref CompileLoc loc, uint paramIdx)
	{
		auto msg = getExp(-1);
		debug(EXPSTACKCHECK) assert(msg.isSource());
		codeRMulti(loc, Op1.ParamFail, Op2.CustomParamFail, 0, &Exp(ExpType.Local, paramIdx), msg);
		pop();
	}
	
	void objParamFail(ref CompileLoc loc, uint paramIdx)
	{
		codeRMulti(loc, Op1.ParamFail, Op2.ObjParamFail, 0, paramIdx, 0);
	}

	uint checkObjParam(ref CompileLoc loc, uint paramIdx)
	{
		auto type = getExp(-1);
		debug(EXPSTACKCHECK) assert(type.isSource());
		auto ret = codeRJump(loc, Op1.CheckObjParam, Op2.Je, true, 0, &Exp(ExpType.Local, paramIdx), type);
		pop();
		return ret;
	}

	uint codeIsTrue(ref CompileLoc loc, bool isTrue = true)
	{
		auto src = getExp(-1);
		debug(EXPSTACKCHECK) assert(src.isSource());
		auto ret = codeRJump(loc, Op1.CheckObjParam, Op2.Je, isTrue, 0, src, Exp.Empty);
		pop();
		return ret;
	}

	private uint commonCmpJump(ref CompileLoc loc, Op1 opcode, Op2 opcode2, bool isTrue)
	{
		auto src1 = getExp(-2);
		auto src2 = getExp(-1);
		debug(EXPSTACKCHECK) assert(src1.isSource());
		debug(EXPSTACKCHECK) assert(src2.isSource());
		auto ret = codeRJump(loc, opcode, opcode2, isTrue, 0, src1, src2);
		pop(2);
		return ret;
	}

	uint codeCmp(ref CompileLoc loc, Op2 type, bool isTrue)
	{
		return commonCmpJump(loc, Op1.Cmp, type, isTrue);
	}

	uint codeSwitchCmp(ref CompileLoc loc)
	{
		return commonCmpJump(loc, Op1.SwitchCmp, Op2.Je, true);
	}

	uint codeEquals(ref CompileLoc loc, bool isTrue)
	{
		return commonCmpJump(loc, Op1.Equals, Op2.Je, isTrue);
	}

	uint codeIs(ref CompileLoc loc, bool isTrue)
	{
		return commonCmpJump(loc, Op1.Is, Op2.Je, isTrue);
	}

	void codeThrow(ref CompileLoc loc, bool rethrowing)
	{
		auto src = getExp(-1);
		debug(EXPSTACKCHECK) assert(src.isSource());
		codeR(loc, Op1.Throw, 0, src, &Exp(ExpType.Local, rethrowing ? 1 : 0));
		pop();
	}

	void saveRets(ref CompileLoc loc, uint numRets)
	{
		if(numRets == 0)
		{
			codeI(loc, Op1.SaveRets, 0, 1);
			return;
		}

		assert(mExpSP >= numRets);
		auto rets = mExpStack[mExpSP - numRets .. mExpSP];
		auto arg = prepareArgList(loc, rets);
		uint first = rets[0].index;
		codeI(loc, Op1.SaveRets, first, arg);
		pop(numRets);
	}

	private uint prepareArgList(ref CompileLoc loc, Exp[] items)
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

	private bool prepareAssignment(ref CompileLoc loc, uint numLhs, uint numRhs, out Exp[] lhs, out Exp[] rhs)
	{
		debug { auto check = mExpSP - (numLhs + numRhs); if(mExpStack[mExpSP - numRhs - 1].type == ExpType.Conflict) check--; }
		assert(numLhs >= numRhs);

		rhs = mExpStack[mExpSP - numRhs .. mExpSP];

// 		debug(EXPSTACKCHECK) foreach(ref i; rhs[0 .. $ - 1]) assert(i.isSource(), (printExpStack(), "poop"));

		if(rhs.length > 0 && rhs[$ - 1].isMultRet())
		{
			multRetToRegs(loc, numLhs - numRhs + 1);

			for(uint i = numRhs, idx = rhs[$ - 1].index; i < numLhs; i++, idx++)
				pushExp(ExpType.Local, idx);
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

	private void multRetToRegs(ref CompileLoc loc, int num)
	{
		auto src = getExp(-1);

		switch(src.type)
		{
			case ExpType.Vararg, ExpType.VarargSlice:
				setUImm(mCode[src.index], num + 1);
				break;

			case ExpType.Call, ExpType.Yield:
				setRT(mCode[src.index], num + 1);
				break;

			default:
				assert(false, (printExpStack(), "poop"));
		}

		src.type = ExpType.Temporary;
		src.index = getRD(mCode[src.index]);
	}

	private void popMoveTo(ref CompileLoc loc, ref Exp dest)
	{
		if(dest.type == ExpType.Local || dest.type == ExpType.NewLocal)
			moveToReg(loc, dest.index, *getExp(-1));
		else
		{
			toSource(loc);

			switch(dest.type)
			{
				case ExpType.Upval:       codeI(loc, Op1.SetUpval,    getExp(-1), dest.index); break;
				case ExpType.Global:      codeI(loc, Op1.SetGlobal,   getExp(-1), dest.index); break;
				case ExpType.NewGlobal:   codeI(loc, Op1.NewGlobal,   getExp(-1), dest.index); break;
				case ExpType.Slice:       codeR(loc, Op1.SliceAssign, dest.index, getExp(-1), Exp.Empty); break;
				case ExpType.Index:       codeR(loc, Op1.IndexAssign, &unpackRegOrConst(dest.index), &unpackRegOrConst(dest.index2), getExp(-1)); break;
				case ExpType.Field:       codeR(loc, Op1.FieldAssign, &unpackRegOrConst(dest.index), &unpackRegOrConst(dest.index2), getExp(-1)); break;
				case ExpType.VarargIndex: codeRMulti(loc, Op1.Vararg, Op2.VargIndexAssign, 0, &unpackRegOrConst(dest.index), getExp(-1)); break;
				case ExpType.Length:      codeR(loc, Op1.LengthAssign, 0, &unpackRegOrConst(dest.index), getExp(-1)); break;
				default: assert(false);
			}
		}

		pop();
	}

	// ---------------------------------------------------------------------------
	// Other codegen funcs

	private void moveToReg(ref CompileLoc loc, uint reg, ref Exp src)
	{
		switch(src.type)
		{
			case ExpType.Const:       codeI(loc, Op1.LoadConst, reg, src.index); break;
			case ExpType.Local:
			case ExpType.NewLocal:    codeMove(loc, reg, src.index); break;
			case ExpType.Upval:       codeI(loc, Op1.GetUpval, reg, src.index); break;
			case ExpType.Global:      codeI(loc, Op1.GetGlobal, reg, src.index); break;
			case ExpType.Index:       codeR(loc, Op1.Index, reg, &unpackRegOrConst(src.index), &unpackRegOrConst(src.index2)); break;
			case ExpType.Field:       codeR(loc, Op1.Field, reg, &unpackRegOrConst(src.index), &unpackRegOrConst(src.index2)); break;
			case ExpType.Slice:       codeR(loc, Op1.Slice, reg, src.index, 0); break;
			case ExpType.Vararg:      setRD(mCode[src.index], reg); setUImm(mCode[src.index], 2); break;
			case ExpType.VarargIndex: codeRMulti(loc, Op1.Vararg, Op2.VargIndex, reg, &unpackRegOrConst(src.index), Exp.Empty); break;
			case ExpType.VarargSlice: codeIMulti(loc, Op1.Vararg, Op2.VargSlice, src.index, 2); codeMove(loc, reg, src.index); break;
			case ExpType.Length:      codeR(loc, Op1.Length, reg, &unpackRegOrConst(src.index), Exp.Empty); break;
			case ExpType.Call:        codeMove(loc, reg, getRD(mCode[src.index])); setUImm(mCode[src.index], 2); break;
			case ExpType.Yield:       codeMove(loc, reg, getRD(mCode[src.index])); setUImm(mCode[src.index], 2); break;
			case ExpType.NeedsDest:   setRD(mCode[src.index], reg); break;
			default: assert(false);
		}
	}

	private uint packRegOrConst(ref Exp e)
	{
		if(e.type == ExpType.Local)
			return e.index;
		else
			return e.index + Instruction.rsrtConstMax + 1;
	}

	private Exp unpackRegOrConst(uint idx)
	{
		if(idx > Instruction.rsrtConstMax)
			return Exp(ExpType.Const, idx - Instruction.rsrtConstMax - 1);
		else
			return Exp(ExpType.Local, idx);
	}

package:
	void paramCheck(ref CompileLoc loc)
	{
		codeI(loc, Op1.CheckParams, 0, 0);	
	}

	void reflexOp(ref CompileLoc loc, AstTag type, uint operands)
	{
		assert(mExpSP >= operands + 1);

		auto lhs = getExp(-operands - 1);
		auto ops = mExpStack[mExpSP - operands .. mExpSP];

		debug(EXPSTACKCHECK) assert(lhs.type == ExpType.Local);
		debug(EXPSTACKCHECK) foreach(ref op; ops) assert(op.isSource());

		if(operands == 0)
			codeRMulti(loc, AstTagToOpcode1(type), AstTagToOpcode2(type), lhs.index, 0, 0);
		else if(operands == 1)
			codeRMulti(loc, AstTagToOpcode1(type), AstTagToOpcode2(type), lhs.index, &ops[0], Exp.Empty);
		else
			codeRMulti(loc, AstTagToOpcode1(type), AstTagToOpcode2(type), lhs.index, &ops[0], &Exp(ExpType.Local, operands));

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
					assert(mFreeReg == getRD(mCode[e.index]));
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

		if(e.type == ExpType.Const)
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

		auto i = codeRMulti(loc, Op1.New, Op2.Class, 0, name, base);
		pop(2);
		pushExp(ExpType.NeedsDest, i);
	}

	void newNamespace(ref CompileLoc loc)
	{
		auto name = getExp(-2);
		auto base = getExp(-1);

		debug(EXPSTACKCHECK) assert(name.isSource());
		debug(EXPSTACKCHECK) assert(base.isSource());

		auto i = codeRMulti(loc, Op1.New, Op2.Namespace, 0, name, base);
		pop(2);
		pushExp(ExpType.NeedsDest, i);
	}

	void newNamespaceNP(ref CompileLoc loc)
	{
		auto name = getExp(-1);

		debug(EXPSTACKCHECK) assert(name.isSource());

		auto i = codeRMulti(loc, Op1.New, Op2.NamespaceNP, 0, name, Exp.Empty);
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

	void varargSlice()
	{
		auto lo = *getExp(-2);
		auto hi = *getExp(-1);

		debug(EXPSTACKCHECK) assert(lo.type == ExpType.Temporary);
		debug(EXPSTACKCHECK) assert(hi.type == ExpType.Temporary);

		pop(2);
		mFreeReg = hi.regAfter;
		pushExp(ExpType.VarargSlice, lo.index);
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
		uint inst;

		if(numOps > 2)
		{
			debug(EXPSTACKCHECK) foreach(ref op; ops) assert(op.type == ExpType.Temporary);
			inst = codeRMulti(loc, AstTagToOpcode1(type), AstTagToOpcode2(type), 0, ops[0].index, numOps);
		}
		else
		{
			debug(EXPSTACKCHECK) foreach(ref op; ops) assert(op.isSource());
			inst = codeRMulti(loc, AstTagToOpcode1(type), AstTagToOpcode2(type), 0, &ops[0], &ops[1]);
		}

		pop(numOps);
		pushExp(ExpType.NeedsDest, inst);
	}
	
	void unOp(ref CompileLoc loc, AstTag type)
	{
		auto src = getExp(-1);

		debug(EXPSTACKCHECK) assert(src.isSource());

		auto inst = codeRMulti(loc, AstTagToOpcode1(type), AstTagToOpcode2(type), 0, src, Exp.Empty);
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

		codeR(loc, isSuperCall ? Op1.SuperMethod : Op1.Method, desc.baseReg, obj, name);
		pushExp(ExpType.Call, codeR(loc, Op1.Call, desc.baseReg, numArgs, 0));
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

		pushExp(ExpType.Call, codeR(loc, Op1.Call, func.index, derp, 0));
	}

	void pushYield(ref CompileLoc loc, uword numArgs)
	{
		assert(mExpSP >= numArgs);

		if(numArgs == 0)
			pushExp(ExpType.Yield, codeR(loc, Op1.Yield, mFreeReg, 1, 0));
		else
		{
			auto args = mExpStack[mExpSP - numArgs .. mExpSP];
			auto derp = prepareArgList(loc, args);
			auto base = args[0].index;
			pop(args.length);
			pushExp(ExpType.Yield, codeR(loc, Op1.Yield, base, derp, 0));
		}
	}

	package void makeTailcall()
	{
		auto e = getExp(-1);
		debug(EXPSTACKCHECK) assert(e.type == ExpType.Call);
		assert(getOpcode(mCode[e.index]) == Op1.Call);
		setOpcode(mCode[e.index], Op1.Tailcall);
	}

	package void codeClosure(FuncState fs, uint destReg)
	{
		t.vm.alloc.resizeArray(mInnerFuncs, mInnerFuncs.length + 1);

		if(mInnerFuncs.length > Instruction.MaxInnerFuncs)
			c.semException(mLocation, "Too many inner functions");

		auto loc = fs.mLocation;

		if(mNamespaceReg > 0)
			codeR(loc, Op1.Move, destReg, mNamespaceReg, 0);

		codeIMulti(loc, Op1.New, mNamespaceReg > 0 ? Op2.ClosureWithEnv : Op2.Closure, destReg, mInnerFuncs.length - 1);

		foreach(ref ud; fs.mUpvals)
			codeI(loc, Op1.Move, ud.isUpvalue ? 1 : 0, ud.index);

		mInnerFuncs[$ - 1] = fs.toFuncDef();
	}

	package void beginNamespace(ref CompileLoc loc)
	{
		assert(mNamespaceReg == 0);

		auto e = getExp(-1);

		debug(EXPSTACKCHECK) assert(e.type == ExpType.NeedsDest);
		mNamespaceReg = mFreeReg;
		toSource(loc);
	}

	package void endNamespace()
	{
		assert(mNamespaceReg != 0);
		mNamespaceReg = 0;
	}

	// ---------------------------------------------------------------------------
	// Control flow

	package uint here()
	{
		return mCode.length;
	}

	package void patchJumpTo(uint src, uint dest)
	{
		setImm(mCode[src], dest - src - 1);
	}

	package void patchJumpToHere(uint src)
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

	package void patchContinuesTo(uint dest)
	{
		patchListTo(mScope.continues, dest);
		mScope.continues = NoJump;
	}

	package void patchBreaksToHere()
	{
		patchListTo(mScope.breaks, here());
		mScope.breaks = NoJump;
	}

	package void patchContinuesToHere()
	{
		patchContinuesTo(here());
	}

	package void patchTrueToHere(ref InstRef i)
	{
		patchListTo(i.trueList, here());
		i.trueList = NoJump;
	}

	package void patchFalseToHere(ref InstRef i)
	{
		patchListTo(i.falseList, here());
		i.falseList = NoJump;
	}
	
	package void catToTrue(ref InstRef i, uint j)
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

	package void catToFalse(ref InstRef i, uint j)
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

	package void invertJump(ref InstRef i)
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

	package void codeJump(ref CompileLoc loc, uint dest)
	{
		codeJ(loc, Op1.Jmp, true, dest - here() - 1);
	}

	package uint makeJump(ref CompileLoc loc, uint type = Op1.Jmp, bool isTrue = true)
	{
		return codeJ(loc, type, isTrue, NoJump);
	}

	package uint codeCatch(ref CompileLoc loc, ref Scope s)
	{
		pushScope(s);
		mScope.ehlevel++;
		mTryCatchDepth++;
		return codeJMulti(loc, Op1.PushEH, Op2.Catch, mFreeReg, NoJump);
	}
	
	package uint popCatch(ref CompileLoc loc, ref CompileLoc catchLoc, uint catchBegin)
	{
		codeIMulti(loc, Op1.PopEH, Op2.Catch, 0, 0);
		auto ret = makeJump(loc);
		patchJumpToHere(catchBegin);
		popScope(catchLoc);
		mTryCatchDepth--;
		return ret;
	}

	package uint codeFinally(ref CompileLoc loc, ref Scope s)
	{
		pushScope(s);
		mScope.ehlevel++;
		mTryCatchDepth++;
		return codeJMulti(loc, Op1.PushEH, Op2.Finally, mFreeReg, NoJump);
	}

	package void popFinally(ref CompileLoc loc, ref CompileLoc finallyLoc, uint finallyBegin)
	{
		codeIMulti(loc, Op1.PopEH, Op2.Finally, 0, 0);
		patchJumpToHere(finallyBegin);
		popScope(finallyLoc);
		mTryCatchDepth--;
	}

	package void endFinallyScope(ref CompileLoc loc)
	{
		popScope(loc);
		mTryCatchDepth--;
	}

	package bool inTryCatch()
	{
		return mTryCatchDepth > 0;
	}

	package void codeContinue(ref CompileLoc loc, char[] name)
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
			codeI(loc, Op1.Unwind, 0, diff);

		continueScope.continues = codeJ(loc, Op1.Jmp, 1, continueScope.continues);
	}

	package void codeBreak(ref CompileLoc loc, char[] name)
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
			codeI(loc, Op1.Unwind, 0, diff);

		breakScope.breaks = codeJ(loc, Op1.Jmp, 1, breakScope.breaks);
	}

	package void defaultReturn(ref CompileLoc loc)
	{
		codeI(loc, Op1.SaveRets, 0, 1);
		codeI(loc, Op1.Ret, 0, 0);
	}
	
	package void codeRet(ref CompileLoc loc)
	{
		codeI(loc, Op1.Ret, 0, 0);
	}
	
	package void codeUnwind(ref CompileLoc loc)
	{
		codeI(loc, Op1.Unwind, 0, mTryCatchDepth);
	}
	
	package void codeMove(ref CompileLoc loc, uint dest, uint src)
	{
		if(dest != src)
			codeR(loc, Op1.Move, dest, src, 0);
	}
	
	package void codeEndFinal(ref CompileLoc loc)
	{
		codeI(loc, Op1.EndFinal, 0, 0);
	}

	// ---------------------------------------------------------------------------
	// Constants

	package int addConst(CrocValue v)
	{
		foreach(i, ref con; mConstants)
			if(con == v)
				return i;

		mConstants.append(c.alloc, v);

		if(mConstants.length > Instruction.MaxConstants)
			c.semException(mLocation, "Too many constants");

		return mConstants.length - 1;
	}

	package int addNullConst()
	{
		return addConst(CrocValue.nullValue);
	}

	package int addBoolConst(bool b)
	{
		return addConst(CrocValue(b));
	}

	package int addIntConst(crocint x)
	{
		return addConst(CrocValue(x));
	}

	package int addFloatConst(crocfloat x)
	{
		return addConst(CrocValue(x));
	}

	package int addCharConst(dchar x)
	{
		return addConst(CrocValue(x));
	}

	package int addStringConst(char[] s)
	{
		return addConst(CrocValue(createString(t, s)));
	}

	package void codeNulls(ref CompileLoc loc, uint reg, uint num)
	{
		codeI(loc, Op1.LoadNulls, reg, num);
	}

	// ---------------------------------------------------------------------------
	// Raw codegen funcs

private:
	uint codeR(ref CompileLoc loc, Op1 opcode, uint dest, uint src1, uint src2)
	{
		Instruction i = void;
		i.data =
			((opcode << Instruction.opcodeShift) & Instruction.opcodeMask) |
			((dest << Instruction.rdShift) & Instruction.rdMask) |
			((src1 << Instruction.rsShift) & Instruction.rsMask) |
			((src2 << Instruction.rtShift) & Instruction.rtMask);

		return addInst(loc.line, i);
	}
	
	uint codeR(ref CompileLoc loc, Op1 opcode, uint dest, Exp* src1, Exp* src2)
	{
		auto rs = encodeRSRT(src1);
		auto rt = encodeRSRT(src2);

		auto ret = codeR(loc, opcode, dest, rs, rt);

		if(rs == Instruction.rsMax)
			addInst(loc.line, Instruction(src1.index));

		if(rt == Instruction.rtMax)
			addInst(loc.line, Instruction(src2.index));

		return ret;
	}

	uint codeR(ref CompileLoc loc, Op1 opcode, Exp* dest, Exp* src1, Exp* src2)
	{
		if(dest.type == ExpType.Const)
		{
			codeI(loc, Op1.LoadConst, mFreeReg, dest.index);
			return codeR(loc, opcode, mFreeReg, src1, src2);
		}
		else
			return codeR(loc, opcode, dest.index, src1, src2);
	}

	uint codeRMulti(ref CompileLoc loc, Op1 opcode, Op2 opcode2, uint dest, uint src1, uint src2)
	{
		if(opcode2 == -1)
			return codeR(loc, opcode, dest, src1, src2);
			
		auto ret = codeR(loc, opcode, dest, src1, src2);
		codeSecond(loc, opcode2);
		return ret;
	}

	uint codeRMulti(ref CompileLoc loc, Op1 opcode, Op2 opcode2, uint dest, Exp* src1, Exp* src2)
	{
		if(opcode2 == -1)
			return codeR(loc, opcode, dest, src1, src2);

		auto rs = encodeRSRT(src1);
		auto rt = encodeRSRT(src2);

		auto ret = codeR(loc, opcode, dest, rs, rt);
		codeSecond(loc, opcode2);

		if(rs == Instruction.rsMax)
			addInst(loc.line, Instruction(src1.index));

		if(rt == Instruction.rtMax)
			addInst(loc.line, Instruction(src2.index));

		return ret;
	}

	uint codeRJump(ref CompileLoc loc, Op1 opcode, Op2 opcode2, bool isTrue, uint dest, Exp* src1, Exp* src2)
	{
		auto rs = encodeRSRT(src1);
		auto rt = encodeRSRT(src2);

		codeR(loc, opcode, dest, rs, rt);
		auto ret = makeJump(loc, opcode2, isTrue);

		if(rs == Instruction.rsMax)
			addInst(loc.line, Instruction(src1.index));

		if(rt == Instruction.rtMax)
			addInst(loc.line, Instruction(src2.index));

		return ret;
	}

	uint encodeRSRT(Exp* src)
	{
		assert(src.isSource());

		if(src.type == ExpType.Local)
		{
			assert(src.index <= Instruction.MaxRegisters);
			return src.index;
		}
		else
		{
			if(src.index > Instruction.rsrtConstMax)
			{
				assert(src.index <= Instruction.MaxConstants);
				return Instruction.rsMax;
			}
			else
				return tagConst(src.index);
		}
	}

	uint codeI(ref CompileLoc loc, Op1 opcode, uint dest, uint imm)
	{
		Instruction i = void;
		i.data =
			((opcode << Instruction.opcodeShift) & Instruction.opcodeMask) |
			((dest << Instruction.rdShift) & Instruction.rdMask) |
			((imm << Instruction.immShift) & Instruction.immMask);

		return addInst(loc.line, i);
	}

	uint codeI(ref CompileLoc loc, Op1 opcode, Exp* dest, uint imm)
	{
		if(dest.type == ExpType.Const)
		{
			codeI(loc, Op1.LoadConst, mFreeReg, dest.index);
			return codeI(loc, opcode, mFreeReg, imm);
		}
		else
			return codeI(loc, opcode, dest.index, imm);
	}

	uint codeIMulti(ref CompileLoc loc, Op1 opcode, Op2 opcode2, uint dest, uint imm)
	{
		if(opcode2 == -1)
			return codeI(loc, opcode, dest, imm);

		auto ret = codeI(loc, opcode, dest, imm);
		codeSecond(loc, opcode2);
		return ret;
	}

	uint codeJ(ref CompileLoc loc, uint opcode, uint dest, int offs)
	{
		// TODO: put this somewhere else. codeJ can be called with MaxJump which is an invalid value.
// 		if(offs < Instruction.MaxJumpBackward || offs > Instruction.MaxJumpForward)
// 			assert(false, "jump too large");

		Instruction i = void;
		i.data =
			((opcode << Instruction.opcodeShift) & Instruction.opcodeMask) |
			((dest << Instruction.rdShift) & Instruction.rdMask) |
			((*(cast(uint*)&offs) << Instruction.immShift) & Instruction.immMask);

		return addInst(loc.line, i);
	}

	uint codeJMulti(ref CompileLoc loc, uint opcode, Op2 opcode2, uint dest, int offs)
	{
		if(opcode2 == -1)
			return codeJ(loc, opcode, dest, offs);

		auto ret = codeJ(loc, opcode, dest, offs);
		codeSecond(loc, opcode2);
		return ret;
	}

	uint codeSecond(ref CompileLoc loc, Op2 opcode)
	{
		Instruction i = void;
		i.data = (opcode << Instruction.opcodeShift) & Instruction.opcodeMask;
		return addInst(loc.line, i);
	}

	uint addInst(uint line, Instruction i)
	{
		mLineInfo.append(c.alloc, line);
		mCode.append(c.alloc, i);
		return mCode.length - 1;
	}

	void setOpcode(ref Instruction inst, uint opcode)
	{
		assert(opcode <= Instruction.opcodeMax);
		inst.data &= ~Instruction.opcodeMask;
		inst.data |= (opcode << Instruction.opcodeShift) & Instruction.opcodeMask;
	}

	void setRD(ref Instruction inst, uint val)
	{
		assert(val <= Instruction.rdMax);
		inst.data &= ~Instruction.rdMask;
		inst.data |= (val << Instruction.rdShift) & Instruction.rdMask;
	}

	void setRS(ref Instruction inst, uint val)
	{
		assert(val <= Instruction.rsMax);
		inst.data &= ~Instruction.rsMask;
		inst.data |= (val << Instruction.rsShift) & Instruction.rsMask;
	}

	void setRT(ref Instruction inst, uint val)
	{
		assert(val <= Instruction.rtMax);
		inst.data &= ~Instruction.rtMask;
		inst.data |= (val << Instruction.rtShift) & Instruction.rtMask;
	}

	void setImm(ref Instruction inst, int val)
	{
		assert(val == Instruction.NoJump || (val >= -Instruction.immMax && val <= Instruction.immMax));
		inst.data &= ~Instruction.immMask;
		inst.data |= (*(cast(uint*)&val) << Instruction.immShift) & Instruction.immMask;
	}

	void setUImm(ref Instruction inst, uint val)
	{
		assert(val <= Instruction.uimmMax);
		inst.data &= ~Instruction.immMask;
		inst.data |= (val << Instruction.immShift) & Instruction.immMask;
	}

	uint getOpcode(ref Instruction inst)
	{
		return mixin(Instruction.GetOpcode("inst"));;
	}

	uint getRD(ref Instruction inst)
	{
		return mixin(Instruction.GetRD("inst"));
	}

	uint getRS(ref Instruction inst)
	{
		return mixin(Instruction.GetRS("inst"));
	}

	uint getRT(ref Instruction inst)
	{
		return mixin(Instruction.GetRT("inst"));
	}

	int getImm(ref Instruction inst)
	{
		static assert((Instruction.immShift + Instruction.immSize) == Instruction.sizeof * 8, "Immediate must be at top of instruction word");
		return mixin(Instruction.GetImm("inst"));
	}

	uint getUImm(ref Instruction inst)
	{
		static assert((Instruction.immShift + Instruction.immSize) == Instruction.sizeof * 8, "Immediate must be at top of instruction word");
		return mixin(Instruction.GetUImm("inst"));
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
			return *pc++;;
		}

		char[] cr(uint v)
		{
			if(isConstTag(v))
			{
				if(v == Instruction.rsMax)
					return Format("c{}", nextIns().data);
				else
					return Format("c{}", v & ~Instruction.constBit);
			}
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

			case Op1.Jmp:           if(getRD(i) == 0) Stdout("nop").newline; else { Stdout("jmp"); commonImm(i); }; break; // THIS IS WRONG
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
					case Op2.Array:          Stdout("newarr"); commonUImm(i); break;
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