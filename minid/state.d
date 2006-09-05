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
		Instruction* pc;
		uint numReturns;
	}
	
	struct TryRecord
	{
		bool isCatch;
		uint catchVarSlot;
		uint actRecord;
		Instruction* pc;
	}
	
	protected TryRecord[] mTryRecs;
	protected TryRecord* mCurrentTR;
	protected uint mTRIndex = 0;

	protected ActRecord[] mActRecs;
	protected ActRecord* mCurrentAR;
	protected uint mARIndex = 0;

	protected MDValue[] mStack;
	protected uint mStackIndex = 0;

	protected MDTable mGlobals;
	protected MDUpval* mUpvalHead;

	// ===================================================================================
	// Public members
	// ===================================================================================

	public this()
	{
		mTryRecs = new TryRecord[10];
		mCurrentTR = &mTryRecs[0];

		mActRecs = new ActRecord[10];
		mCurrentAR = &mActRecs[0];

		mStack = new MDValue[20];

		mGlobals = new MDTable();
	}

	public uint pushNull()
	{
		MDValue v;
		v.setNull();
		return push(&v);
	}
	
	public uint push(T)(T value)
	{
		static if(is(T : char[]) ||
					is(T : wchar[]) ||
					is(T : dchar[]))
		{
			MDValue val;
			val.value = new MDString(value);
		}
		else static if(is(T : bool) ||
						is(T : int) ||
						is(T : float) ||
						is(T : MDObject))
		{
			MDValue val;
			val.value = value;
		}
		else static if(is(T : MDValue*))
		{
			alias value val;
		}
		else
		{
			// An interesting way to report errors, since static assert doesn't show the "call stack"
			MDStatePush_InvalidArgumentType();
			//static assert(false, "MDState.push() - invalid argument type");
		}

		if(mStackIndex >= mStack.length)
			stackSize = mStack.length * 2;

		mStack[mStackIndex].value = val;
		mStackIndex++;

		debug(STACKINDEX) writefln("push() set mStackIndex to ", mStackIndex, " (pushed %s)", val.toString());

		return mStackIndex - 1 - mCurrentAR.base;
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
				throw new MDRuntimeException(this, "Attempting to call a value of type '%s'", func.typeString());

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

			int actualReturns;

			try
			{
				actualReturns = closure.native.func(this);
			}
			catch(MDException e)
			{
				callEpilogue(0, 0);
				throw e;
			}

			callEpilogue(getBasedStackIndex() - actualReturns, actualReturns);
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
					debug(STACKINDEX) writefln("call() adjusted for too many args and set mStackIndex to ", mStackIndex);
				}

				needStackSlots(funcDef.mStackSize);
			}

			pushAR();
			
			mCurrentAR.base = base;
			mCurrentAR.vargBase = vargBase;
			mCurrentAR.funcSlot = slot;
			mCurrentAR.func = closure;
			mCurrentAR.pc = funcDef.mCode.ptr;
			mCurrentAR.numReturns = numReturns;

			for(int i = base + funcDef.mStackSize; i >= mStackIndex; i--)
				getAbsStack(i).setNull();

			mStackIndex = base + funcDef.mStackSize;
			mCurrentAR.savedTop = mStackIndex;

			debug(STACKINDEX) writefln("call() set mStackIndex to ", mStackIndex, " (local stack size = ", funcDef.mStackSize, ")");

			try
			{
				execute();
			}
			catch(MDException e)
			{
				callEpilogue(0, 0);
				throw e;
			}
		}
	}
	
	public void setGlobal(T)(char[] name, T value)
	{
		MDValue key;
		key.value = new MDString(name);

		static if(is(T : char[]) ||
					is(T : wchar[]) ||
					is(T : dchar[]))
		{
			MDValue val;
			val.value = new MDString(value);
			mGlobals[&key] = &val;
		}
		else static if(is(T : bool) ||
						is(T : int) ||
						is(T : float) ||
						is(T : MDObject))
		{
			MDValue val;
			val.value = value;
			mGlobals[&key] = &val;
		}
		else static if(is(T : MDValue*))
		{
			mGlobals[&key] = value;
		}
		else
		{
			// An interesting way to report errors, since static assert doesn't show the "call stack"
			MDStateSetGlobal_InvalidArgumentType();
			//static assert(false, "MDState.setGlobal() - invalid argument type");
		}
	}
	
	public uint numParams()
	{
		return getBasedStackIndex();
	}
	
	public bool isNullParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");
		
		return getBasedStack(index).isNull();
	}
	
	public bool isBoolParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");
		
		return getBasedStack(index).isBool();
	}
	
	public bool isIntParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");
		
		return getBasedStack(index).isInt();
	}
	
	public bool isFloatParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");

		return getBasedStack(index).isFloat();
	}
	
	public bool isStringParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");
		
		return getBasedStack(index).isString();
	}
	
	public MDValue getParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");
			
		return *getBasedStack(index);
	}

	public bool getBoolParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isBool() == false)
			badParamError(index, mCurrentAR.func.toString(), "expected 'bool' but got '" ~ val.typeString() ~ "'");
			
		return val.asBool();
	}
	
	public int getIntParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isInt() == false)
			badParamError(index, mCurrentAR.func.toString(), "expected 'int' but got '" ~ val.typeString() ~ "'");
			
		return val.asInt();
	}
	
	public float getFloatParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isFloat() == false)
			badParamError(index, mCurrentAR.func.toString(), "expected 'float' but got '" ~ val.typeString() ~ "'");
			
		return val.asFloat();
	}

	public char[] getStringParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isString() == false)
			badParamError(index, mCurrentAR.func.toString(), "expected 'string' but got '" ~ val.typeString() ~ "'");
			
		return val.asString.asUTF8();
	}
	
	public wchar[] getWStringParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isString() == false)
			badParamError(index, mCurrentAR.func.toString(), "expected 'string' but got '" ~ val.typeString() ~ "'");
			
		return val.asString.asUTF16();
	}
	
	public dchar[] getDStringParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isString() == false)
			badParamError(index, mCurrentAR.func.toString(), "expected 'string' but got '" ~ val.typeString() ~ "'");

		return val.asString.asUTF32();
	}
	
	public MDArray getArrayParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isArray() == false)
			badParamError(index, mCurrentAR.func.toString(), "expected 'array' but got '" ~ val.typeString() ~ "'");

		return val.asArray();
	}

	public MDTable getTableParam(uint index)
	{
		if(index >= numParams())
			badParamError(index, mCurrentAR.func.toString(), "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isTable() == false)
			badParamError(index, mCurrentAR.func.toString(), "expected 'table' but got '" ~ val.typeString() ~ "'");

		return val.asTable();
	}
	
	public MDValue[] getAllParams()
	{
		if(numParams() == 0)
			return null;
			
		MDValue[] params = new MDValue[numParams()];
		params[] = mStack[mCurrentAR.base .. mStackIndex];
		
		return params;
	}

	// ===================================================================================
	// Package members
	// ===================================================================================

	package Location getDebugLocation()
	{
		if(mCurrentAR.func.isNative())
			return Location(mCurrentAR.func.native.name, -1, -1);
		else
		{
			MDFuncDef fd = mCurrentAR.func.script.func;

			int line = -1;
			uint instructionIndex = mCurrentAR.pc - fd.mCode.ptr - 1;

			if(instructionIndex < fd.mLineInfo.length)
				line = fd.mLineInfo[instructionIndex];

			return Location(mCurrentAR.func.script.func.mGuessedName, line);
		}
	}

	package void badParamError(uint index, char[] funcName, char[] msg)
	{
		throw new MDRuntimeException(this, "Bad argument ", index + 1, ": ", msg);
	}

	package void callEpilogue(uint resultSlot, int numResults)
	{
		resultSlot = getBasedIndex(resultSlot);

		uint destSlot = mCurrentAR.funcSlot;
		int numExpRets = mCurrentAR.numReturns;

		bool isMultRet = false;

		if(numExpRets == -1)
		{
			isMultRet = true;
			numExpRets = numResults;
		}

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

		if(isMultRet)
			mStackIndex = destSlot;
		else
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
				throw new MDRuntimeException(this, "Script call stack overflow");
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
	
	package void pushTR()
	{
		if(mTRIndex >= mTryRecs.length)
		{
			try
			{
				mTryRecs.length = mTryRecs.length * 2;
			}
			catch
			{
				throw new MDRuntimeException(this, "Script catch/finally stack overflow");
			}
		}

		mTRIndex++;
		mCurrentTR = &mTryRecs[mTRIndex];
		mCurrentTR.actRecord = mARIndex;
	}
	
	package void popTR()
	{
		mTRIndex--;

		assert(mTRIndex != uint.max, "Script catch/finally stack underflow");

		mCurrentTR = &mTryRecs[mTRIndex];
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
			throw new MDRuntimeException(this, "MiniD stack overflow");
		}

		MDValue* oldBase = oldStack.ptr;
		MDValue* newBase = mStack.ptr;
		
		for(MDUpval* uv = mUpvalHead; uv !is null; uv = uv.next)
			uv.value = (uv.value - oldBase) + newBase;
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
		
		if(dest != src)
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
		StackVal slot = getBasedStack(num);

		for(MDUpval* uv = mUpvalHead; uv !is null && uv.value >= slot; uv = uv.next)
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
			throw new MDRuntimeException(this, "Attempting to perform an integral switch on a value of type '%s'", src.typeString());

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
			throw new MDRuntimeException(this, "Attempting to perform a string switch on a value of type '%s'", src.typeString());

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

		return t[&MetaStrings[method]];
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
					throw new MDRuntimeException(s, "Attempting to index a '%s'", table.typeString());
			}

			if(method.isFunction())
			{
				uint funcSlot = s.push(method);
				s.push(table);
				s.push(key);
				s.call(funcSlot, 2, 1);
				s.copyBasedStack(dest, funcSlot);
				return;
			}

			// Follow the chain
			table = method;
		}

		throw new MDRuntimeException(s, "Metatable circular dependency or chain too deep");
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
					table.asTable()[key] = value;
					return;
				}
			}
			else
			{
				method = s.getMM(table, MM.IndexAssign);

				if(method.isNull())
					throw new MDRuntimeException(s, "Attempting to index a '%s'", table.typeString());
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

		throw new MDRuntimeException(s, "Metatable circular dependency or chain too deep");
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
					throw new MDRuntimeException(s, "Cannot perform arithmetic on a '%s'", src1.typeString());

				uint funcSlot = s.push(method);
				s.push(src1);
				s.call(funcSlot, 1, 1);
				s.copyBasedStack(dest, funcSlot);
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
					throw new MDRuntimeException(s, "Cannot perform arithmetic on a '%s' and a '%s'", src1.typeString(), src2.typeString());
			}

			uint funcSlot = s.push(method);
			s.push(src1);
			s.push(src2);
			s.call(funcSlot, 2, 1);
			s.copyBasedStack(dest, funcSlot);
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
					throw new MDRuntimeException(s, "Cannot perform bitwise arithmetic on a '%s'", src1.typeString());

				uint funcSlot = s.push(method);
				s.push(src1);
				s.call(funcSlot, 1, 1);
				s.copyBasedStack(dest, funcSlot);
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
					throw new MDRuntimeException(s, "Cannot perform bitwise arithmetic on a '%s' and a '%s'",
						src1.typeString(), src2.typeString());
			}

			uint funcSlot = s.push(method);
			s.push(src1);
			s.push(src2);
			s.call(funcSlot, 2, 1);
			s.copyBasedStack(dest, funcSlot);
		}
	}

	public void execute()
	{
		//Instruction* pc = mCurrentAR.pc;
		MDException currentException = null;

		_exceptionRetry:

		try
		{
			while(true)
			{
				Instruction i = *mCurrentAR.pc;
				mCurrentAR.pc++;
				
				MDValue cr1temp;
				MDValue cr2temp;
	
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
						Instruction jump = *mCurrentAR.pc;
						mCurrentAR.pc++;

						int cmpValue = getCR1().opCmp(getCR2());

						if(jump.rd == 1)
						{
							switch(jump.opcode)
							{
								case Op.Je:  if(cmpValue == 0) mCurrentAR.pc += jump.imm; break;
								case Op.Jle: if(cmpValue <= 0) mCurrentAR.pc += jump.imm; break;
								case Op.Jlt: if(cmpValue < 0)  mCurrentAR.pc += jump.imm; break;
								default: assert(false, "invalid 'cmp' jump");
							}
						}
						else
						{
							switch(jump.opcode)
							{
								case Op.Je:  if(cmpValue != 0) mCurrentAR.pc += jump.imm; break;
								case Op.Jle: if(cmpValue > 0)  mCurrentAR.pc += jump.imm; break;
								case Op.Jlt: if(cmpValue >= 0) mCurrentAR.pc += jump.imm; break;
								default: assert(false, "invalid 'cmp' jump");
							}
						}
	
						break;
	
					case Op.Is:
						Instruction jump = *mCurrentAR.pc;
						mCurrentAR.pc++;
	
						assert(jump.opcode == Op.Je, "invalid 'is' jump");
	
						bool cmpValue = getCR1().rawEquals(getCR2());
	
						if(jump.rd == 1)
						{
							if(cmpValue is true)
								mCurrentAR.pc += jump.imm;
						}
						else
						{
							if(cmpValue is false)
								mCurrentAR.pc += jump.imm;
						}
	
						break;
	
					case Op.IsTrue:
						Instruction jump = *mCurrentAR.pc;
						mCurrentAR.pc++;
	
						assert(jump.opcode == Op.Je, "invalid 'istrue' jump");
	
						bool cmpValue = !getCR1().isFalse();
	
						if(jump.rd == 1)
						{
							if(cmpValue is true)
								mCurrentAR.pc += jump.imm;
						}
						else
						{
							if(cmpValue is false)
								mCurrentAR.pc += jump.imm;
						}
	
						break;
	
					case Op.Jmp:
						mCurrentAR.pc += i.imm;
						break;
	
					case Op.Length:
						StackVal src = getBasedStack(i.rs1);
						MDValue* method = getMM(src, MM.Length);
						
						if(method.isFunction())
						{
							uint funcReg = push(method);
							push(src);

							call(funcReg, 1, 1);
							copyBasedStack(i.rd, funcReg);
						}
						else
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
						getBasedStack(i.rd).value = getEnvironment()[index];
						break;
	
					case Op.SetGlobal:
						MDValue* index = getConst(i.imm);
						assert(index.isString(), "trying to get a non-string global");
						getEnvironment()[index] = getBasedStack(i.rd);
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
							throw new MDRuntimeException(this, "Switch without default");
	
						mCurrentAR.pc += offset;
						break;
	
					case Op.SwitchString:
						int offset = switchString(i.rd, i.imm);
	
						if(offset == -1)
							throw new MDRuntimeException(this, "Switch without default");
	
						mCurrentAR.pc += offset;
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
						Instruction jump = *mCurrentAR.pc;
						mCurrentAR.pc++;
	
						uint rd = i.rd;
						uint funcReg = rd + 3;
	
						copyBasedStack(funcReg + 2, rd + 2);
						copyBasedStack(funcReg + 1, rd + 1);
						copyBasedStack(funcReg, rd);
	
						call(funcReg, 2, i.imm);
	
						if(getBasedStack(funcReg).isNull() == false)
						{
							copyBasedStack(rd + 2, funcReg);
	
							assert(jump.opcode == Op.Je && jump.rd == 1, "invalid 'foreach' jump " ~ jump.toString());
	
							mCurrentAR.pc += jump.imm;
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
									throw new MDRuntimeException(this, "Cannot concatenate a '%s' and a '%s'",
										src1.typeString(), src2.typeString());
							}
	
							uint funcSlot = push(method);
							push(src1);
							push(src2);
							call(funcSlot, 2, 1);
							copyBasedStack(i.rd, funcSlot);
						}
	
						break;
	
					case Op.Closure:
						MDFuncDef newDef = getInnerFunc(i.imm);
						MDClosure n = new MDClosure(this, newDef);
	
						for(int index = 0; index < newDef.mNumUpvals; index++)
						{
							if(mCurrentAR.pc.opcode == Op.Move)
								n.script.upvals[index] = findUpvalue(mCurrentAR.pc.rs1);
							else
							{
								assert(mCurrentAR.pc.opcode == Op.GetUpvalue, "invalid closure upvalue op");
								n.script.upvals[index] = getUpvalueRef(mCurrentAR.pc.imm);
							}
	
							mCurrentAR.pc++;
						}
	
						getBasedStack(i.rd).value = n;
						break;
	
					case Op.Index:
						StackVal src = getBasedStack(i.rs1);
	
						if(src.isArray())
						{
							MDValue* idx = getCR2();
	
							if(idx.isInt() == false)
								throw new MDRuntimeException(this, "Attempt to access an array with a '%s'", idx.typeString());
	
							MDValue* val = src.asArray[idx.asInt];
	
							if(val is null)
								throw new MDRuntimeException(this, "Invalid array index: ", idx.asInt());
	
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
								throw new MDRuntimeException(this, "Attempt to access an array with a '%s'", idx.typeString());
	
							MDValue* val = dest.asArray()[idx.asInt];
	
							if(val is null)
								throw new MDRuntimeException(this, "Invalid array index: ", idx.asInt());
	
							val.value = getCR2();
						}
						else
							setIndexed(this, getBasedStack(i.rd), getCR1(), getCR2());
	
						break;
	
					case Op.Method:
						StackVal src = getCR1();
						getBasedStack(i.rd + 1).value = src;
						getIndexed(this, i.rd, src, getCR2());
						break;
	
					case Op.Call:
						int funcReg = i.rd;
						int numParams = i.rs1 - 1;
						int numResults = i.rs2 - 1;
	
						if(numParams == -1)
							numParams = getBasedStackIndex() - funcReg - 1;
	
						call(funcReg, numParams, numResults);
						break;
	
					case Op.Ret:
						int numResults = i.imm - 1;
	
						close(0);
						callEpilogue(i.rd, numResults);
						return;
						
					case Op.PushCatch:
						pushTR();
						
						mCurrentTR.isCatch = true;
						mCurrentTR.catchVarSlot = i.rd;
						mCurrentTR.pc = mCurrentAR.pc + i.imm;
						break;
	
					case Op.PushFinally:
						pushTR();
						
						mCurrentTR.isCatch = false;
						mCurrentTR.pc = mCurrentAR.pc + i.imm;
						break;
						
					case Op.PopCatch:
						if(mCurrentTR.isCatch == false)
							throw new MDRuntimeException(this, "'catch' popped out of order");
	
						popTR();
						break;
	
					case Op.PopFinally:
						if(mCurrentTR.isCatch == true)
							throw new MDRuntimeException(this, "'finally' popped out of order");
	
						currentException = null;

						popTR();
						break;
	
					case Op.EndFinal:
						if(currentException !is null)
							throw currentException;
						
						break;
	
					case Op.Throw:
						throw new MDRuntimeException(this, getCR1());
	
					case Op.Je:
					case Op.Jle:
					case Op.Jlt:
						assert(false, "lone conditional jump instruction");
				}
			}
		}
		catch(MDException e)
		{
			while(mCurrentTR.actRecord is mARIndex)
			{
				TryRecord tr = *mCurrentTR;
				popTR();

				if(tr.isCatch)
				{
					getBasedStack(tr.catchVarSlot).value = e.value;
					
					for(int i = getBasedIndex(tr.catchVarSlot + 1); i < mStackIndex; i++)
						getAbsStack(i).setNull();
						
					currentException = null;

					mCurrentAR.pc = tr.pc;
					goto _exceptionRetry;
				}
				else
				{
					currentException = e;
					
					mCurrentAR.pc = tr.pc;
					goto _exceptionRetry;
				}
			}
			
			throw e;
		}
	}
}