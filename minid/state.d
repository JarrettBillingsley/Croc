module minid.state;

import minid.types;
import minid.opcodes;

alias MDValue* StackVal;

class MDGlobalState
{
	public static MDGlobalState instance;
	
	public static MDGlobalState opCall()
	{
		debug if(instance is null)
			throw new MDException("MDGlobalState is not initialized");

		return instance;
	}

	MDState mMainThread;
	MDUpval* mUpvalHead;
	MDTable[] mBasicTypeMT;

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