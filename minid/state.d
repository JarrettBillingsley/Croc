module minid.state;

import minid.types;
import minid.opcodes;

alias MDValue* StackVal;

class MDGlobalState
{
	MDState mMainThread;
	MDUpval* mUpvalHead;
	MDTable[] mBasicTypeMT;
	
	public this()
	{
		mMainThread = new MDState();
		mBasicTypeMT = new MDTable[MDValue.Type.max + 1];
	}

	public void setMetatable(MDValue.Type type, MDTable table)
	{
		switch(type)
		{
			case MDValue.Type.None:
			case MDValue.Type.Null:
			case MDValue.Type.Table:
			case MDValue.Type.UserData:
				throw new MDException("Cannot set global metatable for type '%s'", MDValue.typeString(type));

			case MDValue.Type.Bool:
			case MDValue.Type.Int:
			case MDValue.Type.Float:
			case MDValue.Type.String:
			case MDValue.Type.Array:
			case MDValue.Type.Function:
				mBasicTypeMT[type] = table;
				return;
		}
	}
}

class MDState
{
	struct ActRecord
	{
		uint base;
		uint top;
		MDClosure func;
		Instruction* savedPC;
		uint numReturns;
	}
	
	ActRecord[] mActRecs;
	ActRecord* mCurrentAR;

	Instruction* mSavedPC;

	MDValue[] mStack;
	StackVal mFreeStack;
	
	MDTable mGlobals;
	
	MDUpval* mUpvalHead;
	
	public this()
	{
		mActRecs = new ActRecord[10];
		mCurrentAR = &mActRecs[0];
		
		mStack = new MDValue[20];
		mFreeStack = &mStack[0];
		
		mGlobals = new MDTable();
	}
	
	package StackVal getBasedStack(uint offset)
	{
		assert((mCurrentAR.base + offset) < mStack.length, "invalid based stack index");
		return &mStack[mCurrentAR.base + offset];
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
	
	package MDValue* getUpvalue(uint num)
	{
		assert(mCurrentAR.func.isNative() == false, "cannot get upval from native function");
		return mCurrentAR.func.script.upvals[num].value;
	}
}