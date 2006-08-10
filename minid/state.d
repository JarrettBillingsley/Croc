module minid.state;

import minid.types;
import minid.opcodes;

alias MDValue* StackVal;

class MDGlobalState
{
	MDState mMainThread;
	MDUpval* mUpvalHead;
	MDTable[] mBasicTypeMT;
}

class MDState
{
	MDGlobalState mGlobal;
	
	struct ActRecord
	{
		StackVal base;
		StackVal top;
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

	}
	
	public StackVal getBasedStack(uint offset)
	{
		StackVal ret = mCurrentAR.base + offset;
		assert(ret <= mFreeStack, "invalid based stack index");
		return ret;
	}

	public MDValue* getConst(uint num)
	{
		assert(mCurrentAR.func.isNative() == false, "cannot get constant from native function");
		return &mCurrentAR.func.script.func.mConstants[num];
	}
}