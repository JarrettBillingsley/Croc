module minid.state;

import minid.types;
import minid.opcodes;

alias MDValue* StackVal;

class MDGlobalState
{
	public static MDGlobalState instance;
	private MDState mMainThread;
	private MDUpval* mUpvalHead;
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
		debug switch(type)
		{
			case MDValue.Type.None:
			case MDValue.Type.Null:
			case MDValue.Type.Table:
			case MDValue.Type.UserData:
				throw new MDException("Cannot get global metatable for type '%s'", MDValue.typeString(type));

			default:
				break;
		}
		
		return mBasicTypeMT[cast(uint)type];
	}

	public void setMetatable(MDValue.Type type, MDTable table)
	{
		debug switch(type)
		{
			case MDValue.Type.None:
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
		uint top;
		uint vargBase;
		MDClosure func;
		Instruction* savedPC;
		uint numReturns;
	}
	
	ActRecord[] mActRecs;
	ActRecord* mCurrentAR;

	Instruction* mSavedPC;

	MDValue[] mStack;
	StackVal mStackPtr;
	uint mStackIndex = 0;
	
	MDTable mGlobals;
	
	MDUpval* mUpvalHead;
	
	public this()
	{
		mActRecs = new ActRecord[10];
		mCurrentAR = &mActRecs[0];
		
		mStack = new MDValue[20];
		mStackPtr = mStack.ptr;

		mGlobals = new MDTable();
	}
	
	public uint push(MDValue* val)
	{
		if(mStackIndex >= mStack.length)
		{
			stackSize = mStack.length * 2;
			mStackPtr = &mStack[mStackIndex];
		}
		
		mStack[mStackIndex].value = val;
		mStackIndex++;

		return mStackIndex - 1;
	}

	public uint push(MDValue val)
	{
		return push(&val);
	}
	
	public void popToSlot(uint slot)
	{
		assert(mStackIndex > 0, "Stack underflow");
		
		mStackIndex--;
		
		if(slot != mStackIndex)
			mStack[slot].value = &mStack[mStackIndex];
	}

	public void call(uint slot, int numParams, int numReturns)
	{
		// blah
	}
	
	package void stackSize(uint length)
	{
		try
		{
			MDValue[] oldStack = mStack;
			mStack.length = length;
			
			MDValue* oldBase = oldStack.ptr;
			MDValue* newBase = mStack.ptr;

			for(MDUpval* uv = mUpvalHead; uv !is null; uv = uv.next)
				uv.value = (uv.value - oldBase) + newBase;
		}
		catch
		{
			throw new MDRuntimeException("Stack overflow");
		}
	}
	
	package void close(uint index)
	{
		StackVal base = getBasedStack(index);

		for(MDUpval* uv = mUpvalHead; uv !is null && uv.value >= base; )
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
	package MDValue[] sliceStack(uint lo, int hi)
	{
		debug if(hi != -1)
			assert(lo <= hi && hi <= mStack.length, "invalid slice stack params");

		if(hi == -1)
			return mStack[lo .. $];
		else
			return mStack[lo .. hi];
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

	package MDValue* getConst(uint num)
	{
		assert(mCurrentAR.func.isNative() == false, "cannot get constant from native function");
		return &mCurrentAR.func.script.func.mConstants[num];
	}
	
	package MDTable getEnvironment()
	{
		return mCurrentAR.func.environment();
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
		MDUpval* uv = MDGlobalState().mUpvalHead;
		StackVal slot = getBasedStack(num);

		for( ; uv !is null && uv.value >= slot; uv = uv.next)
		{
			if(uv.value is slot)
				return uv;
		}

		MDUpval* ret = new MDUpval;
		ret.value = slot;

		if(MDGlobalState().mUpvalHead !is null)
		{
			ret.next = MDGlobalState().mUpvalHead.next;
			
			if(ret.next !is null)
				ret.next.prev = ret;
		}
		
		MDGlobalState().mUpvalHead = ret;

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
}