module minid.state;

import minid.types;
import minid.opcodes;

import std.stdio;

alias MDValue* StackVal;

//debug = STACKINDEX;

class MDGlobalState
{
	public static MDGlobalState instance;
	private MDState mMainThread;
	private MDTable[] mBasicTypeMT;

	public static MDGlobalState opCall()
	{
		debug if(instance is null)
			throw new MDException("MDGlobalState is not initialized");

		return instance;
	}

	public static void initialize()
	{
		instance = new MDGlobalState();
	}

	public this()
	{
		if(instance !is null)
			throw new MDException("MDGlobalState is a singleton and cannot be created more than once");

		mMainThread = new MDState();
		mBasicTypeMT = new MDTable[MDValue.Type.max + 1];

		instance = this;
	}

	public MDTable getMetatable(MDValue.Type type)
	{
		return mBasicTypeMT[cast(uint)type];
	}

	public void setMetatable(MDValue.Type type, MDTable table)
	{
		debug switch(type)
		{
			case MDValue.Type.Null:
			case MDValue.Type.Table:
			case MDValue.Type.UserData:
				throw new MDException("Cannot set global metatable for type '%s'", MDValue.typeString(type));

			default:
				break;
		}

		mBasicTypeMT[type] = table;
	}

	public MDState mainThread()
	{
		return mMainThread;
	}
}

class MDState
{
	struct ActRecord
	{
		uint base;
		uint savedTop;
		uint vargBase;
		uint funcSlot;
		MDClosure func;
		Instruction* savedPC;
		uint numReturns;
	}

	/*protected*/ ActRecord[] mActRecs;
	/*protected*/ ActRecord* mCurrentAR;
	/*protected*/ uint mARIndex = 0;

	///*protected*/ Instruction* mSavedPC;

	/*protected*/ MDValue[] mStack;
	/*protected*/ uint mStackIndex = 0;

	/*protected*/ MDTable mGlobals;
	/*protected*/ MDUpval* mUpvalHead;

	// ===================================================================================
	// Public members
	// ===================================================================================

	public this()
	{
		mActRecs = new ActRecord[10];
		mCurrentAR = &mActRecs[0];

		mStack = new MDValue[20];

		mGlobals = new MDTable();
	}

	public uint push(MDValue* val)
	{
		if(mStackIndex >= mStack.length)
			stackSize = mStack.length * 2;

		mStack[mStackIndex].value = val;
		mStackIndex++;
		
		debug(STACKINDEX) writefln("push() set mStackIndex to ", mStackIndex);

		return mStackIndex - 1;
	}

	public uint push(MDValue val)
	{
		return push(&val);
	}

	public uint push(MDString val)
	{
		MDValue v;
		v.value = val;
		return push(&v);
	}

	public uint push(MDUserData val)
	{
		MDValue v;
		v.value = val;
		return push(&v);
	}

	public uint push(MDClosure val)
	{
		MDValue v;
		v.value = val;
		return push(&v);
	}

	public uint push(MDTable val)
	{
		MDValue v;
		v.value = val;
		return push(&v);
	}

	public uint push(MDArray val)
	{
		MDValue v;
		v.value = val;
		return push(&v);
	}

	public uint push(int val)
	{
		MDValue v;
		v.value = val;
		return push(&v);
	}

	public uint push(float val)
	{
		MDValue v;
		v.value = val;
		return push(&v);
	}

	public void popToSlot(uint slot)
	{
		slot = getBasedIndex(slot);
		
		assert(mStackIndex > 0, "Stack underflow");

		mStackIndex--;
		
		debug(STACKINDEX) writefln("popToSlot() set mStackIndex to ", mStackIndex);

		if(slot != mStackIndex)
			mStack[slot].value = &mStack[mStackIndex];
	}

	public void call(uint slot, int numParams, int numReturns)
	{
		slot = getBasedIndex(slot);

		if(numParams == -1)
			numParams = mStackIndex - slot - 1;

		assert(numParams >= 0, "negative num params in call");

		StackVal func = getAbsStack(slot);

		if(!func.isFunction())
		{
			MDValue* method = getMM(func, MM.Call);

			if(!method.isFunction())
				throw new MDRuntimeException("Attempting to call a value of type '%s'", func.typeString());

			needStackSlots(1);

			for(int i = mStackIndex; i > slot; i--)
				copyAbsStack(i, i - 1);

			mStackIndex++;
			
			debug(STACKINDEX) writefln("call() got the call MM and set mStackIndex to ", mStackIndex);

			// func stack reference may have been invalidated by needStackSlots
			func = getAbsStack(slot);
			func.value = method;
		}

		MDClosure closure = func.asFunction();
		
		mCurrentAR.savedTop = mStackIndex;

		if(closure.isNative())
		{
			// Native function
			needStackSlots(20);

			mStackIndex = slot + 1 + numParams;
			
			debug(STACKINDEX) writefln("call called a native func and set mStackIndex to ", mStackIndex);

			pushAR();

			mCurrentAR.base = slot + 1;
			mCurrentAR.vargBase = 0;
			mCurrentAR.funcSlot = slot;
			mCurrentAR.func = closure;
			mCurrentAR.numReturns = numReturns;

			int actualReturns = closure.native.func(this);

			callEpilogue(mStackIndex - actualReturns, actualReturns);
		}
		else
		{
			// Script function
			MDFuncDef funcDef = closure.script.func;
			mStackIndex = slot + numParams + 1;

			uint base;
			uint vargBase;

			if(funcDef.mIsVararg)
			{
				if(numParams < funcDef.mNumParams)
				{
					needStackSlots(funcDef.mNumParams - numParams);

					for(int i = funcDef.mNumParams - numParams; i > 0; i--)
					{
						mStack[mStackIndex].setNull();
						mStackIndex++;
					}
					
					numParams = funcDef.mNumParams;
				}
				
				/*
				f(x, y, vararg):

				f()
				   0 1    2    3
				=> f null null null
				   f           vb

				f(1)
				   0 1 2    3
				=> f 1 null 1
				   f        v
				            b

				f(1, 2)
				   0 1 2 3 4
				=> f 1 2 1 2
				   f     v
				         b

				f(1, 2, 3)
				   0 1 2 3 4 5
				=> f 1 2 3 1 2
				   f     v b
				*/

				vargBase = slot + funcDef.mNumParams + 1;

				mStackIndex = slot + numParams + 1;

				needStackSlots(funcDef.mStackSize);

				debug(STACKINDEX) writefln("call() adjusted the varargs and set mStackIndex to ", mStackIndex);

				uint paramSlot = slot + 1;
				base = mStackIndex;

				for(int i = 0; i < funcDef.mNumParams; i++)
				{
					copyAbsStack(mStackIndex, paramSlot);
					getAbsStack(paramSlot).setNull();
					paramSlot++;
					mStackIndex++;
				}
				
				debug(STACKINDEX) writefln("call() copied the regular args for a vararg and set mStackIndex to ", mStackIndex);
			}
			else
			{
				base = slot + 1;

				if(mStackIndex > base + funcDef.mNumParams)
				{
					mStackIndex = base + funcDef.mNumParams;
					debug(STACKINDEX) writefln("call() adjusted for unpassed args and set mStackIndex to ", mStackIndex);
				}

				needStackSlots(funcDef.mStackSize);
			}

			pushAR();

			mCurrentAR.base = base;
			mCurrentAR.vargBase = vargBase;
			mCurrentAR.funcSlot = slot;
			mCurrentAR.func = closure;
			mCurrentAR.savedPC = funcDef.mCode.ptr;
			mCurrentAR.numReturns = numReturns;

			for(int i = base + funcDef.mStackSize; i >= mStackIndex; i--)
				getAbsStack(i).setNull();

			mStackIndex = base + funcDef.mStackSize;
			mCurrentAR.savedTop = mStackIndex;

			debug(STACKINDEX) writefln("call() set mStackIndex to ", mStackIndex, " (local stack size = ", funcDef.mStackSize, ")");

			execute();
		}
	}

	public void setGlobal(char[] name, MDClosure val)
	{
		MDValue key;
		key.value = new MDString(name);
		MDValue value;
		value.value = val;
		mGlobals[key] = value;
	}

	// ===================================================================================
	// Package members
	// ===================================================================================

	package void callEpilogue(uint resultSlot, int numResults)
	{
		resultSlot = getBasedIndex(resultSlot);

		uint destSlot = mCurrentAR.funcSlot;
		uint numExpRets = mCurrentAR.numReturns;

		popAR();

		if(numExpRets <= numResults)
		{
			while(numExpRets > 0)
			{
				copyAbsStack(destSlot, resultSlot);

				destSlot++;
				resultSlot++;
				numExpRets--;
			}
		}
		else
		{
			while(numResults > 0)
			{
				copyAbsStack(destSlot, resultSlot);

				destSlot++;
				resultSlot++;
				numResults--;
				numExpRets--;
			}

			while(numExpRets > 0)
			{
				getAbsStack(destSlot).setNull();
				destSlot++;
				numExpRets--;
			}
		}

		mStackIndex = mCurrentAR.savedTop;
		
		debug(STACKINDEX) writefln("callEpilogue() set mStackIndex to ", mStackIndex);
	}

	package void pushAR()
	{
		if(mARIndex >= mActRecs.length)
		{
			try
			{
				mActRecs.length = mActRecs.length * 2;
			}
			catch
			{
				throw new MDRuntimeException("Script call stack overflow");
			}
		}

		mARIndex++;
		mCurrentAR = &mActRecs[mARIndex];
	}

	package void popAR()
	{
		mARIndex--;

		assert(mARIndex != uint.max, "Script call stack underflow");

		mCurrentAR = &mActRecs[mARIndex];
	}

	package void stackSize(uint length)
	{
		MDValue[] oldStack = mStack;

		try
		{
			mStack.length = length;
		}
		catch
		{
			throw new MDRuntimeException("MiniD stack overflow");
		}

		MDValue* oldBase = oldStack.ptr;
		MDValue* newBase = mStack.ptr;
		
		for(MDUpval* uv = mUpvalHead; uv !is null; uv = uv.next)
			uv.value = (uv.value - oldBase) + newBase;

		//mStackPtr = &mStack[mStackIndex];
	}

	package void close(uint index)
	{
		StackVal base = getBasedStack(index);

		for(MDUpval* uv = mUpvalHead; uv !is null && uv.value >= base; uv = mUpvalHead)
		{
			mUpvalHead = uv.next;

			if(uv.prev)
				uv.prev.next = uv.next;

			if(uv.next)
				uv.next.prev = uv.prev;

			uv.closedValue.value = uv.value;
			uv.value = &uv.closedValue;
		}
	}

	// This should only be used for Op.SetArray, really.  Since this returns a slice of
	// the actual stack, which can move around, the reference shouldn't really be kept
	// for long.
	package MDValue[] sliceStack(uint lo, int num)
	{
		debug if(num != -1)
			assert(lo <= mStack.length && (lo + num) <= mStack.length, "invalid slice stack params");
		else
			assert(lo <= mStack.length, "invalid slice stack params");

		if(num == -1)
		{
			MDValue[] ret = mStack[lo .. mStackIndex];
			mStackIndex = mCurrentAR.savedTop;
			
			debug(STACKINDEX) writefln("sliceStack() set mStackIndex to ", mStackIndex);
			return ret;
		}
		else
			return mStack[lo .. lo + num];
	}

	package void needStackSlots(uint howMany)
	{
		if(mStack.length - mStackIndex >= howMany)
			return;

		stackSize = howMany + mStackIndex;
	}

	package void copyBasedStack(uint dest, uint src)
	{
		assert((mCurrentAR.base + dest) < mStack.length, "invalid based stack dest index");
		mStack[mCurrentAR.base + dest].value = getBasedStack(src);
	}

	package void copyAbsStack(uint dest, uint src)
	{
		assert(dest < mStack.length && src < mStack.length, "invalid copyAbsStack indices");
		mStack[dest].value = &mStack[src];
	}

	package StackVal getBasedStack(uint offset)
	{
		assert((mCurrentAR.base + offset) < mStack.length, "invalid based stack index");
		return &mStack[mCurrentAR.base + offset];
	}

	package StackVal getAbsStack(uint offset)
	{
		assert(offset < mStack.length, "invalid getAbsStack stack index");
		return &mStack[offset];
	}

	package uint getBasedIndex(uint offset)
	{
		assert((mCurrentAR.base + offset) < mStack.length, "invalid based index");
		return mCurrentAR.base + offset;
	}

	package MDValue* getConst(uint num)
	{
		assert(mCurrentAR.func.isNative() == false, "cannot get constant from native function");
		return &mCurrentAR.func.script.func.mConstants[num];
	}

	package MDTable getEnvironment()
	{
		return mCurrentAR.func.environment();
	}

	package MDTable getGlobals()
	{
		return mGlobals;
	}

	package Instruction* getSavedPC()
	{
		return mCurrentAR.savedPC;
	}

	package void savePC(Instruction* pc)
	{
		mCurrentAR.savedPC = pc;
	}

	package MDFuncDef getInnerFunc(uint num)
	{
		assert(mCurrentAR.func.isNative() == false, "cannot get inner func from native function");
		MDFuncDef def = mCurrentAR.func.script.func;
		assert(num < def.mInnerFuncs.length, "invalid inner func index");
		return def.mInnerFuncs[num];
	}

	package MDValue* getUpvalue(uint num)
	{
		return getUpvalueRef(num).value;
	}

	package MDUpval* getUpvalueRef(uint num)
	{
		assert(mCurrentAR.func.isNative() == false, "cannot get upval from native function");
		return mCurrentAR.func.script.upvals[num];
	}

	package MDUpval* findUpvalue(uint num)
	{
		MDUpval* uv = mUpvalHead;
		StackVal slot = getBasedStack(num);

		for( ; uv !is null && uv.value >= slot; uv = uv.next)
		{
			if(uv.value is slot)
				return uv;
		}

		MDUpval* ret = new MDUpval;
		ret.value = slot;

		if(mUpvalHead !is null)
		{
			ret.next = mUpvalHead;
			ret.next.prev = ret;
		}

		mUpvalHead = ret;

		return ret;
	}

	package int getNumVarargs()
	{
		return mCurrentAR.base - mCurrentAR.vargBase;
	}

	package int getVarargBase()
	{
		return mCurrentAR.vargBase;
	}

	package int getBase()
	{
		return mCurrentAR.base;
	}

	package int getBasedStackIndex()
	{
		return mStackIndex - mCurrentAR.base;
	}

	// Returns -1 on invalid switch (no case and no default)
	package int switchInt(uint stackSlot, uint table)
	{
		assert(mCurrentAR.func.isNative() == false, "cannot switch in native function");

		StackVal src = getBasedStack(stackSlot);

		if(src.isInt() == false)
			throw new MDRuntimeException("Attempting to perform an integral switch on a value of type '%s'", src.typeString());

		auto t = &mCurrentAR.func.script.func.mSwitchTables[table];

		assert(t.isString == false, "int switch on a string table");

		int* ptr = (src.asInt() in t.intOffsets);

		if(ptr is null)
			return t.defaultOffset;
		else
			return *ptr;
	}

	// Returns -1 on invalid switch (no case and no default)
	package int switchString(uint stackSlot, uint table)
	{
		assert(mCurrentAR.func.isNative() == false, "cannot switch in native function");

		StackVal src = getBasedStack(stackSlot);

		if(src.isString() == false)
			throw new MDRuntimeException("Attempting to perform a string switch on a value of type '%s'", src.typeString());

		auto t = &mCurrentAR.func.script.func.mSwitchTables[table];

		assert(t.isString == true, "string switch on an int table");

		int* ptr = (src.asString().mData in t.stringOffsets);

		if(ptr is null)
			return t.defaultOffset;
		else
			return *ptr;
	}

	package MDValue* getMM(MDValue* obj, MM method)
	{
		MDTable t;

		switch(obj.type)
		{
			case MDValue.Type.Table:
				t = obj.asTable().metatable;
				break;

			case MDValue.Type.UserData:
				t = obj.asUserData().metatable;
				break;

			default:
				t = MDGlobalState().getMetatable(obj.type);
				break;
		}

		if(t is null)
			return &MDValue.nullValue;

		return t[MetaStrings[method]];
	}

	// ===================================================================================
	// Interpreter
	// ===================================================================================

	protected const uint metaMethodLoop = 100;

	protected static void getIndexed(MDState s, uint dest, StackVal table, MDValue* key)
	{
		for(uint i = 0; i < metaMethodLoop; i++)
		{
			MDValue* method;

			if(table.isTable())
			{
				MDValue* result = table.asTable[key];

				if(result.isNull() == false)
				{
					s.getBasedStack(dest).value = result;
					return;
				}
				else
				{
					method = s.getMM(table, MM.Index);

					if(method.isNull())
					{
						s.getBasedStack(dest).value = result;
						return;
					}
				}
			}
			else
			{
				method = s.getMM(table, MM.Index);

				if(method.isNull())
					throw new MDRuntimeException("Attempting to index a '%s'", table.typeString());
			}

			if(method.isFunction())
			{
				uint funcSlot = s.push(method);
				s.push(table);
				s.push(key);
				s.call(funcSlot, 2, 1);
				s.popToSlot(dest);
				return;
			}

			// Follow the chain
			table = method;
		}

		throw new MDRuntimeException("Metatable circular dependency or chain too deep");
	}

	protected static void setIndexed(MDState s, StackVal table, MDValue* key, MDValue* value)
	{
		for(uint i = 0; i < metaMethodLoop; i++)
		{
			MDValue* method;

			if(table.isTable())
			{
				method = s.getMM(table, MM.IndexAssign);

				if(method.isNull())
				{
					table.asTable()[*key] = value;
					return;
				}
			}
			else
			{
				method = s.getMM(table, MM.IndexAssign);

				if(method.isNull())
					throw new MDRuntimeException("Attempting to index a '%s'", table.typeString());
			}

			if(method.isFunction())
			{
				uint funcSlot = s.push(method);
				s.push(table);
				s.push(key);
				s.push(value);
				s.call(funcSlot, 3, 0);
				return;
			}

			// Follow the chain
			table = method;
		}

		throw new MDRuntimeException("Metatable circular dependency or chain too deep");
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

	public void execute()
	{
		Instruction* pc = getSavedPC();

		while(true)
		{
			Instruction i = *pc;
			pc++;

			MDValue* getCR1()
			{
				uint val = i.rs1;

				if(val & Instruction.constBit)
					return getConst(val & ~Instruction.constBit);
				else
					return getBasedStack(val);
			}

			MDValue* getCR2()
			{
				uint val = i.rs2;

				if(val & Instruction.constBit)
					return getConst(val & ~Instruction.constBit);
				else
					return getBasedStack(val);
			}

			Op opcode = cast(Op)i.opcode;

			switch(opcode)
			{
				case Op.Add:
				case Op.Sub:
				case Op.Mul:
				case Op.Div:
				case Op.Mod:
					doArithmetic(this, i.rd, getCR1(), getCR2(), opcode);
					break;

				case Op.Neg:
					doArithmetic(this, i.rd, getCR1(), null, opcode);
					break;

				case Op.And:
				case Op.Or:
				case Op.Xor:
				case Op.Shl:
				case Op.Shr:
				case Op.UShr:
					doBitArith(this, i.rd, getCR1(), getCR2(), opcode);
					break;

				case Op.Com:
					doBitArith(this, i.rd, getCR1(), null, opcode);
					break;

				case Op.Move:
					getBasedStack(i.rd).value = getBasedStack(i.rs1);
					break;

				case Op.Not:
					if(getBasedStack(i.rs1).isFalse())
						getBasedStack(i.rd).value = true;
					else
						getBasedStack(i.rd).value = false;

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
					getBasedStack(i.rd).value = cast(int)getBasedStack(i.rs1).length;
					break;

				case Op.LoadBool:
					getBasedStack(i.rd).value = (i.rs1 == 1) ? true : false;
					break;

				case Op.LoadNull:
					getBasedStack(i.rd).setNull();
					break;

				case Op.LoadConst:
					getBasedStack(i.rd).value = getConst(i.imm);
					break;

				case Op.GetGlobal:
					MDValue* index = getConst(i.imm);
					assert(index.isString(), "trying to get a non-string global");
					getBasedStack(i.rd).value = getEnvironment()[*index];
					break;

				case Op.SetGlobal:
					MDValue* index = getConst(i.imm);
					assert(index.isString(), "trying to get a non-string global");
					getEnvironment()[*index] = getBasedStack(i.rd);
					break;

				case Op.GetUpvalue:
					getBasedStack(i.rd).value = getUpvalue(i.imm);
					break;

				case Op.SetUpvalue:
					getUpvalue(i.imm).value = getBasedStack(i.rd);
					break;

				case Op.NewArray:
					getBasedStack(i.rd).value = new MDArray(i.imm);
					break;

				case Op.NewTable:
					getBasedStack(i.rd).value = new MDTable();
					break;

				case Op.SetArray:
					// Since this instruction is only generated for array constructors,
					// there is really no reason to check for type correctness for the dest.

					// sliceStack resets the top-of-stack.

					uint sliceBegin = getBase() + i.rd + 1;
					int numElems = i.rs1 - 1;

					getBasedStack(i.rd).asArray().setBlock(i.rs2, sliceStack(sliceBegin, numElems));

					break;

				case Op.SwitchInt:
					int offset = switchInt(i.rd, i.imm);

					if(offset == -1)
						throw new MDRuntimeException("Switch without default");

					pc += offset;
					break;

				case Op.SwitchString:
					int offset = switchString(i.rd, i.imm);

					if(offset == -1)
						throw new MDRuntimeException("Switch without default");

					pc += offset;
					break;

				case Op.Vararg:
					int numNeeded = i.rs1 - 1;
					int numVarargs = getNumVarargs();

					if(numNeeded == -1)
						numNeeded = numVarargs;

					needStackSlots(numNeeded);

					uint src = getVarargBase();
					uint dest = getBasedIndex(i.rd);

					for(uint index = 0; index < numNeeded; index++)
					{
						if(index < numVarargs)
							copyAbsStack(dest + index, src);
						else
							getAbsStack(dest + index).setNull();

						src++;
					}
					
					mStackIndex = dest + numVarargs;
					break;

				case Op.Close:
					close(i.rd);
					break;

				case Op.Foreach:
					Instruction jump = *pc;
					pc++;

					uint rd = i.rd;
					uint funcReg = rd + 3;

					copyBasedStack(funcReg + 2, rd + 2);
					copyBasedStack(funcReg + 1, rd + 1);
					copyBasedStack(funcReg, rd);

					call(funcReg, 2, i.imm);

					if(getBasedStack(funcReg).isNull() == false)
					{
						copyBasedStack(rd + 2, funcReg);

						assert(jump.opcode == Op.Je && jump.rd == 1, "invalid 'foreach' jump");

						pc += jump.immBiased;
					}

					break;

				case Op.Cat:
					StackVal src1 = getCR1();
					StackVal src2 = getCR2();

					if(src1.isArray() && src2.isArray())
						getBasedStack(i.rd).value = src1.asArray() ~ src2.asArray();
					else if(src1.isString() && src2.isString())
						getBasedStack(i.rd).value = src1.asString() ~ src2.asString();
					else
					{
						MDValue* method = getMM(src1, MM.Cat);

						if(!method.isFunction())
						{
							method = getMM(src2, MM.Cat);

							if(!method.isFunction())
								throw new MDRuntimeException("Cannot concatenate a '%s' and a '%s'", src1.typeString(), src2.typeString());
						}

						uint funcSlot = push(method);
						push(src1);
						push(src2);
						call(funcSlot, 2, 1);
						popToSlot(i.rd);
					}

					break;

				case Op.Closure:
					MDFuncDef newDef = getInnerFunc(i.imm);
					MDClosure n = new MDClosure(this, newDef);

					for(int index = 0; index < newDef.mNumUpvals; index++)
					{
						if(pc.opcode == Op.Move)
							n.script.upvals[index] = findUpvalue(i.rs2);
						else
						{
							assert(pc.opcode == Op.GetUpvalue, "invalid closure upvalue op");
							n.script.upvals[index] = getUpvalueRef(i.rs2);
						}

						pc++;
					}

					getBasedStack(i.rd).value = n;
					break;

				case Op.Index:
					StackVal src = getBasedStack(i.rs1);

					if(src.isArray())
					{
						MDValue* idx = getCR2();

						if(idx.isInt() == false)
							throw new MDRuntimeException("Attempt to access an array with a '%s'", idx.typeString());

						MDValue* val = src.asArray[idx.asInt];

						if(val is null)
							throw new MDRuntimeException("Invalid array index: ", idx.asInt());

						getBasedStack(i.rd).value = val;
					}
					else
						getIndexed(this, i.rd, getBasedStack(i.rs1), getCR2());

					break;

				case Op.IndexAssign:
					StackVal dest = getBasedStack(i.rd);

					if(dest.isArray())
					{
						MDValue* idx = getCR1();

						if(idx.isInt() == false)
							throw new MDRuntimeException("Attempt to access an array with a '%s'", idx.typeString());

						MDValue* val = dest.asArray()[idx.asInt];

						if(val is null)
							throw new MDRuntimeException("Invalid array index: ", idx.asInt());

						val.value = getCR2();
					}
					else
						setIndexed(this, getBasedStack(i.rd), getCR1(), getCR2());

					break;

				case Op.Method:
					copyBasedStack(i.rd + 1, i.rs1);
					getIndexed(this, i.rd, getBasedStack(i.rs1), getCR2());
					break;

				case Op.Call:
					int funcReg = i.rd;
					int numParams = i.rs1 - 1;
					int numResults = i.rs2 - 1;

					if(numParams == -1)
						numParams = getBasedStackIndex() - funcReg - 1;

					savePC(pc);
					call(funcReg, numParams, numResults);
					break;

				case Op.Ret:
					int numResults = i.imm - 1;

					close(0);
					callEpilogue(i.rd, numResults);
					return;

				case Op.EndFinal:
				case Op.PopCatch:
				case Op.PopFinally:
				case Op.PushCatch:
				case Op.PushFinally:
				case Op.Throw:
					throw new MDException("Unimplemented instruction %s", i.toString());

				case Op.Je:
				case Op.Jle:
				case Op.Jlt:
					assert(false, "lone conditional jump instruction");
			}
		}
	}
}
