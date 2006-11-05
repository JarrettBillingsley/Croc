module minid.state;

import minid.types;
import minid.opcodes;

import std.stdio;
import std.stdarg;

alias MDValue* StackVal;

//debug = STACKINDEX;
//debug = CALLEPILOGUE;

// Some type traits stuff.

template isStringType(T)
{
	const bool isStringType = is(T : char[]) || is(T : wchar[]) || is(T : dchar[]);
}

template isCharType(T)
{
	const bool isCharType = is(T == char) || is(T == wchar) || is(T == dchar);
}

template isIntType(T)
{
	const bool isIntType = is(T : int);
}

template isFloatType(T)
{
	const bool isFloatType = is(T == float) || is(T == double) || is(T == real);
}

private void putInValue(T)(MDValue* dest, T src)
{
	static if(isCharType!(T))
	{
		dest.value = cast(dchar)src;
	}
	else static if(isStringType!(T) || isFloatType!(T) || is(T == bool) || is(T : MDObject))
	{
		dest.value = src;
	}
	else static if(isIntType!(T))
	{
		dest.value = cast(int)src;
	}
	else static if(is(T : MDValue))
	{
		dest.value = &src;
	}
	else static if(is(T : MDValue*))
	{
		dest.value = src;
	}
	else
	{
		// I do this because static assert won't show the template instantiation "call stack."
		pragma(msg, "putInValue() - Invalid argument type ");
		ARGUMENT_ERROR(T);
	}
}

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
			case MDValue.Type.Userdata:
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

	protected Location[] mTraceback;

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

	debug final public void printStack()
	{
		writefln();
		writefln("-----Stack Dump-----");
		for(uint i = 0; i < mStackIndex; i++)
			writefln(i, ": ", mStack[i].toString());

		writefln();
	}
	
	debug final public void printCallStack()
	{
		writefln();
		writefln("-----Call Stack-----");
		
		for(int i = mARIndex; i > 0; i--)
		{
			with(mActRecs[i])
			{
				writefln("Record ", func.toString());
				writefln("\tBase: ", base);
				writefln("\tSaved Top: ", savedTop);
				writefln("\tVararg Base: ", vargBase);
				writefln("\tFunc Slot: ", funcSlot);
				writefln("\tNum Returns: ", numReturns);
			}
		}
		writefln();
	}

	public uint pushNull()
	{
		MDValue v;
		v.setNull();
		return push(&v);
	}
	
	public uint push(T)(T value)
	{
		needStackSlots(1);
			
		MDValue val;
		putInValue(&val, value);
		mStack[mStackIndex].value = &val;

		mStackIndex++;

		debug(STACKINDEX) writefln("push() set mStackIndex to ", mStackIndex);//, " (pushed %s)", val.toString());

		return mStackIndex - 1 - mCurrentAR.base;
	}
	
	public void easyCall(T...)(MDClosure func, uint numReturns, T params)
	{
		//uint funcReg = push(func);
		uint funcReg = mStackIndex;

		foreach(param; params)
			push(param);

		directCall(func, funcReg, numReturns, funcReg, params.length);

		//call(funcReg, params.length, numReturns);
	}

	public void call(uint slot, int numParams, int numReturns)
	{
		slot = getBasedIndex(slot);

		if(numParams == -1)
			numParams = mStackIndex - slot - 1;
			
		assert(numParams >= 0, "negative num params in call");

		StackVal func = getAbsStack(slot);

		if(func.isClass())
		{
			pushAR();

			*mCurrentAR = mActRecs[mARIndex - 1];
			mCurrentAR.base = slot;
			mCurrentAR.numReturns = numReturns;
			mCurrentAR.funcSlot = slot;

			MDInstance n = func.asClass().newInstance();
			
			MDValue* ctor = n.getCtor();

			if(!ctor.isNull())
			{
				getAbsStack(slot).value = n;
				directCall(ctor.asFunction(), slot, 0, slot, numParams + 1);
			}
			
			getAbsStack(slot).value = n;
			callEpilogue(0, 1);
		}
		else if(func.isFunction())
		{
			MDClosure closure = func.asFunction();
			directCall(closure, slot, numReturns, slot + 1, numParams);
		}
		else
		{
			MDValue* method = getMM(func, MM.Call);

			if(!method.isFunction())
				throw new MDRuntimeException(this, "Attempting to call a value of type '%s'", func.typeString());

			directCall(method.asFunction(), slot, numReturns, slot, numParams + 1);
		}
	}

	public void setGlobal(T)(dchar[] name, T value)
	{
		MDValue key;
		key.value = new MDString(name);

		static if(isCharType!(T))
		{
			MDValue val;
			val.value = cast(dchar)value;
			mGlobals[&key] = &val;
		}
		else static if(isIntType!(T))
		{
			MDValue val;
			val.value = cast(int)value;
			mGlobals[&key] = &val;
		}
		else static if(isStringType!(T) || is(T : bool) || is(T : float) || is(T : MDObject))
		{
			MDValue val;
			val.value = value;
			mGlobals[&key] = &val;
		}
		else static if(is(T : MDValue))
		{
			mGlobals[&key] = &value;
		}
		else static if(is(T : MDValue*))
		{
			mGlobals[&key] = value;
		}
		else
		{
			pragma(msg, "setGlobal() - Invalid argument type ");
			ARGUMENT_ERROR(T);
		}
	}

	public MDValue* getGlobal(dchar[] name)
	{
		MDValue key;
		key.value = new MDString(name);
		return mGlobals[&key];
	}
	
	public void setUpvalue(T)(uint index, T value)
	{
		if(!mCurrentAR.func)
			throw new MDRuntimeException(this, "MDState.setUpvalue() - No function to set upvalue");

		if(mCurrentAR.func.isNative() == false)
			throw new MDRuntimeException(this, "MDState.setUpvalue() cannot be used on a non-native function");

		if(index >= mCurrentAR.func.native.upvals.length)
			throw new MDRuntimeException(this, "MDState.setUpvalue() - Invalid upvalue index: ", index);

		static if(isCharType!(T))
		{
			MDValue val;
			val.value = cast(dchar)value;
			mCurrentAR.func.native.upvals[index] = val;
		}
		else static if(isIntType!(T))
		{
			MDValue val;
			val.value = cast(int)value;
			mCurrentAR.func.native.upvals[index] = val;
		}
		else static if(isStringType!(T) || is(T : bool) || is(T : float) || is(T : MDObject))
		{
			MDValue val;
			val.value = value;
			mCurrentAR.func.native.upvalues[index] = val;
		}
		else static if(is(T : MDValue))
		{
			mCurrentAR.func.native.upvals[index] = value;
		}
		else static if(is(T : MDValue*))
		{
			mCurrentAR.func.native.upvals[index] = *value;
		}
		else
		{
			pragma(msg, "setUpvalue() - Invalid argument type ");
			ARGUMENT_ERROR(T);
		}
	}

	public MDValue* getUpvalue(uint index)
	{
		if(mCurrentAR.func)
		{
			if(mCurrentAR.func.isNative() == false)
				throw new MDRuntimeException(this, "MDState.getUpvalue() cannot be used on a non-native function");
				
			if(index >= mCurrentAR.func.native.upvals.length)
				throw new MDRuntimeException(this, "MDState.getUpvalue() - Invalid upvalue index: ", index);
		}
		else
			throw new MDRuntimeException(this, "MDState.getUpvalue() - No function to get upvalue");

		return &mCurrentAR.func.native.upvals[index];
	}

	public uint numParams()
	{
		return getBasedStackIndex();
	}

	public bool isParam(char[] type)(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
			
		static if(type == "null")          return getBasedStack(index).isNull();
		else static if(type == "bool")     return getBasedStack(index).isBool();
		else static if(type == "int")      return getBasedStack(index).isInt();
		else static if(type == "float")    return getBasedStack(index).isFloat();
		else static if(type == "char")     return getBasedStack(index).isChar();
		else static if(type == "string")   return getBasedStack(index).isString();
		else static if(type == "table")    return getBasedStack(index).isTable();
		else static if(type == "array")    return getBasedStack(index).isArray();
		else static if(type == "function") return getBasedStack(index).isFunction();
		else static if(type == "userdata") return getBasedStack(index).isUserdata();
		else static if(type == "class")    return getBasedStack(index).isClass();
		else static if(type == "instance") return getBasedStack(index).isInstance();
		else static if(type == "delegate") return getBasedStack(index).isDelegate();
		else ERROR_MDState_IsParam_InvalidType();
	}
	
	/*public T getTypeParam(T)(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
			
		MDValue* val = getBasedStack(index);

		static if(isCharType!(T))
		{
			if(val.isChar() == false)
				badParamError(this, index, "expected 'char' but got '%s'", val.typeString());
				
			return cast(T)val.asChar();
		}
		else static if(isIntType!(T))
		{
			if(val.isInt() == false)
				badParamError(this, index, "expected 'int' but got '%s'", val.typeString());
				
			return cast(T)val.asInt();
		}
		else static if(is(T : float))
		{
			if(val.isFloat() == false)
				badParamError(this, index, "expected 'float' but got '%s'", val.typeString());
	
			return cast(T)val.asFloat();
		}
		else static if(is(T : char[]))
		{
			if(val.isString() == false)
				badParamError(this, index, "expected 'string' but got '%s'", val.typeString());
	
			return val.asString.asUTF8();
		}
		else static if(is(T : wchar[]))
		{
			if(val.isString() == false)
				badParamError(this, index, "expected 'string' but got '%s'", val.typeString());
	
			return val.asString.asUTF16();
		}
		else static if(is(T : dchar[]))
		{
			if(val.isString() == false)
				badParamError(this, index, "expected 'string' but got '%s'", val.typeString());
	
			return val.asString.asUTF32();
		}
	}*/

	public MDValue getParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
			
		return *getBasedStack(index);
	}
	
	public bool getBoolParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isBool() == false)
			badParamError(this, index, "expected 'bool' but got '%s'", val.typeString());
			
		return val.asBool();
	}
	
	public int getIntParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isInt() == false)
			badParamError(this, index, "expected 'int' but got '%s'", val.typeString());
			
		return val.asInt();
	}
	
	public float getFloatParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isFloat() == false)
			badParamError(this, index, "expected 'float' but got '%s'", val.typeString());

		return val.asFloat();
	}
	
	public dchar getCharParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isChar() == false)
			badParamError(this, index, "expected 'char' but got '%s'", val.typeString());
			
		return val.asChar();
	}

	public MDString getStringParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isString() == false)
			badParamError(this, index, "expected 'string' but got '%s'", val.typeString());

		return val.asString();
	}

	public MDArray getArrayParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isArray() == false)
			badParamError(this, index, "expected 'array' but got '%s'", val.typeString());

		return val.asArray();
	}

	public MDTable getTableParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isTable() == false)
			badParamError(this, index, "expected 'table' but got '%s'", val.typeString());

		return val.asTable();
	}

	public MDClosure getClosureParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isFunction() == false)
			badParamError(this, index, "expected 'function' but got '%s'", val.typeString());

		return val.asFunction();
	}

	public MDUserdata getUserdataParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isUserdata() == false)
			badParamError(this, index, "expected 'userdata' but got '%s'", val.typeString());

		return val.asUserdata();
	}

	public MDClass getClassParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isClass() == false)
			badParamError(this, index, "expected 'class' but got '%s'", val.typeString());

		return val.asClass();
	}
	
	public MDInstance getInstanceParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isInstance() == false)
			badParamError(this, index, "expected 'instance' but got '%s'", val.typeString());

		return val.asInstance();
	}

	public MDInstance getInstanceParam(uint index, MDClass type)
	{
		assert(type !is null, "getInstanceParam wants a non-null type!");

		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isInstance() == false)
			badParamError(this, index, "expected 'instance' but got '%s'", val.typeString());

		MDInstance i = val.asInstance();

		if(i.castToClass(type) == false)
			badParamError(this, index, "expected instance of class '%s' but got instance of class '%s'", type.getName(), i.getClass().getName());

		return i;
	}
	
	public MDDelegate getDelegateParam(uint index)
	{
		if(index >= numParams())
			badParamError(this, index, "not enough parameters");
		
		MDValue* val = getBasedStack(index);

		if(val.isDelegate() == false)
			badParamError(this, index, "expected 'delegate' but got '%s'", val.typeString());

		return val.asDelegate();
	}

	public MDValue[] getAllParams()
	{
		if(numParams() == 0)
			return null;
			
		MDValue[] params = new MDValue[numParams()];
		params[] = mStack[mCurrentAR.base .. mStackIndex];

		return params;
	}
	
	public MDValue[] getParams(int lo, int hi)
	{
		int numParams = numParams();

		if(lo < 0)
			lo = numParams + lo + 1;

		if(hi < 0)
			hi = numParams + hi + 1;

		if(lo > hi || lo < 0 || lo > numParams || hi < 0 || hi > numParams)
			throw new MDRuntimeException(this, "Invalid getParams indices (", lo, " .. ", hi, ") (num params = ", numParams, ")");

		MDValue[] params = new MDValue[hi - lo];
		params[] = mStack[mCurrentAR.base + lo .. mCurrentAR.base + hi];

		return params;
	}
	
	public char[] getTracebackString()
	{
		if(mTraceback.length == 0)
			return "";
			
		char[] ret = string.format("Traceback: ", mTraceback[0].toString());
		
		foreach(inout Location l; mTraceback[1 .. $])
			ret = string.format("%s\n\tat ", ret, l.toString());

		mTraceback.length = 0;
		
		return ret;
	}

	// ===================================================================================
	// Package members
	// ===================================================================================
	
	package void directCall(MDClosure closure, uint returnSlot, uint numReturns, uint paramSlot, uint numParams)
	{
		if(closure.isNative())
		{
			// Native function
			needStackSlots(20);

			mStackIndex = paramSlot + numParams;

			debug(STACKINDEX) writefln("directCall called a native func '%s'", closure.toString(), " and set mStackIndex to ", mStackIndex);

			pushAR();

			mCurrentAR.base = paramSlot;
			mCurrentAR.vargBase = 0;
			mCurrentAR.funcSlot = returnSlot;
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
			mStackIndex = paramSlot + numParams;

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

				vargBase = paramSlot + funcDef.mNumParams;

				mStackIndex = paramSlot + numParams;

				needStackSlots(funcDef.mStackSize);

				debug(STACKINDEX) writefln("directCall adjusted the varargs and set mStackIndex to ", mStackIndex);

				uint oldParamSlot = paramSlot;
				base = mStackIndex;

				for(int i = 0; i < funcDef.mNumParams; i++)
				{
					copyAbsStack(mStackIndex, oldParamSlot);
					getAbsStack(oldParamSlot).setNull();
					oldParamSlot++;
					mStackIndex++;
				}
				
				debug(STACKINDEX) writefln("directCall copied the regular args for a vararg and set mStackIndex to ", mStackIndex);
			}
			else
			{
				base = paramSlot;

				if(mStackIndex > base + funcDef.mNumParams)
				{
					mStackIndex = base + funcDef.mNumParams;
					debug(STACKINDEX) writefln("directCall adjusted for too many args and set mStackIndex to ", mStackIndex);
				}

				needStackSlots(funcDef.mStackSize);
			}

			pushAR();

			mCurrentAR.base = base;
			mCurrentAR.vargBase = vargBase;
			mCurrentAR.funcSlot = returnSlot;
			mCurrentAR.func = closure;
			mCurrentAR.pc = funcDef.mCode.ptr;
			mCurrentAR.numReturns = numReturns;
			
			mStackIndex = base + funcDef.mStackSize;
			
			debug(STACKINDEX) writefln("directCall of function '%s'", closure.toString(), " set mStackIndex to ", mStackIndex, " (local stack size = ", funcDef.mStackSize, ", base = ", base, ")");

			for(int i = base + funcDef.mStackSize; i >= 0 && i >= mStackIndex; i--)
				getAbsStack(i).setNull();

			mCurrentAR.savedTop = mStackIndex;

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

	package Location startTraceback()
	{
		mTraceback.length = 0;
		
		Location ret = getDebugLocation();
		mTraceback ~= ret;
		
		return ret;
	}

	package Location getDebugLocation()
	{
		if(mCurrentAR.func is null)
			return Location("<no debug location available>", 0, 0);

		if(mCurrentAR.func.isNative())
			return Location(mCurrentAR.func.native.name, -1, -1);
		else
		{
			MDFuncDef fd = mCurrentAR.func.script.func;

			int line = -1;
			uint instructionIndex = mCurrentAR.pc - fd.mCode.ptr - 1;

			if(instructionIndex < fd.mLineInfo.length)
				line = fd.mLineInfo[instructionIndex];

			return Location(mCurrentAR.func.script.func.mGuessedName, line, instructionIndex);
		}
	}

	static package void badParamError(MDState s, uint index, ...)
	{
		throw new MDRuntimeException(s, "Bad argument ", index + 1, ": %s", vformat(_arguments, _argptr));
	}

	package void callEpilogue(uint resultSlot, int numResults)
	{
		debug(CALLEPILOGUE) printCallStack();

		resultSlot = getBasedIndex(resultSlot);

		debug(CALLEPILOGUE) writefln("callEpilogue for function ", mCurrentAR.func.toString());
		debug(CALLEPILOGUE) writefln("\tResult slot: ", resultSlot, "\n\tNum results: ", numResults);

		uint destSlot = mCurrentAR.funcSlot;
		int numExpRets = mCurrentAR.numReturns;
		
		debug(CALLEPILOGUE) writefln("\tDest slot: ", destSlot, "\n\tNum expected results: ", numExpRets);

		bool isMultRet = false;

		if(numResults == -1)
			numResults = mStackIndex - resultSlot;

		if(numExpRets == -1)
		{
			isMultRet = true;
			numExpRets = numResults;
			debug(CALLEPILOGUE) writefln("\tNum multi rets: ", numExpRets);
		}
		
		popAR();

		if(numExpRets <= numResults)
		{
			while(numExpRets > 0)
			{
				copyAbsStack(destSlot, resultSlot);
				debug(CALLEPILOGUE) writefln("\tvalue: ", getAbsStack(destSlot).toString());

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
				debug(CALLEPILOGUE) writefln("\tvalue: ", getAbsStack(destSlot).toString());

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

		debug(STACKINDEX) writefln("callEpilogue() set mStackIndex to ", mStackIndex, isMultRet? " (multret)" : "");
	}

	package void pushAR()
	{
		if(mARIndex >= mActRecs.length - 1)
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
		if(mTRIndex >= mTryRecs.length - 1)
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
		MDValue* oldBase = mStack.ptr;

		try
		{
			mStack.length = length;
		}
		catch
		{
			throw new MDRuntimeException(this, "Script value stack overflow");
		}

		MDValue* newBase = mStack.ptr;

		if(oldBase !is newBase)
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
		if(mStack.length - mStackIndex >= howMany + 1)
			return;

		stackSize = howMany + 1 + mStackIndex;
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
	
	package MDValue* getInternalUpvalue(uint num)
	{
		if(mCurrentAR.func.isNative())
			return &mCurrentAR.func.native.upvals[num];
		else
			return getUpvalueRef(num).value;
	}

	package MDUpval* getUpvalueRef(uint num)
	{
		assert(mCurrentAR.func.isNative() == false, "cannot get upval ref from native function");
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
		int value;

		if(src.isInt() == false)
		{
			if(src.isChar() == false)
				throw new MDRuntimeException(this, "Attempting to perform an integral switch on a value of type '%s'", src.typeString());
			
			value = cast(int)src.asChar();
		}
		else
			value = src.asInt();

		auto t = &mCurrentAR.func.script.func.mSwitchTables[table];

		assert(t.isString == false, "int switch on a string table");

		int* ptr = (value in t.intOffsets);

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
				MDValue* m = obj.asTable[&MetaStrings[method]];

				if(m.isNull() == false)
					return m;

				goto default;

			case MDValue.Type.Instance:
				return obj.asInstance[&MetaStrings[method]];

			case MDValue.Type.Userdata:
				t = obj.asUserdata().metatable;
				break;

			case MDValue.Type.Delegate:
				if(method == MM.Call)
					return obj.asDelegate().getCaller();

				goto default;

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

	protected void indexAssign(MDValue* dest, MDValue* key, MDValue* value)
	{
		MDValue* method = getMM(dest, MM.IndexAssign);

		if(method.isNull() == false)
		{
			if(method.isFunction() == false && method.isDelegate() == false)
				throw new MDRuntimeException(this, "Invalid opIndexAssign metamethod for type '%s'", dest.typeString());

			uint funcSlot = push(method);
			push(dest);
			push(key);
			push(value);
			call(funcSlot, 3, 0);
			return;
		}
		
		switch(dest.type)
		{
			case MDValue.Type.Array:
				if(key.isInt() == false)
					throw new MDRuntimeException(this, "Attempting to access an array with a '%s'", key.typeString());

				MDValue* val = dest.asArray[key.asInt];
	
				if(val is null)
					throw new MDRuntimeException(this, "Invalid array index: ", key.asInt());
	
				val.value = value;
				break;

			case MDValue.Type.Table:
				dest.asTable()[key] = value;
				break;

			case MDValue.Type.Instance:
				MDValue* val = dest.asInstance[key];

				if(val.isFunction())
					throw new MDRuntimeException(this, "Attempting to change method '%s' of class instance", key.toString());

				if(val is &MDValue.nullValue)
					throw new MDRuntimeException(this, "Attempting to add a member '%s' to a class instance", key.toString());

				dest.asInstance()[key] = value;
				break;

			case MDValue.Type.Class:
				dest.asClass()[key] = value;
				break;
				
			default:
				throw new MDRuntimeException(this, "Attempting to index assign a value of type '%s'", dest.typeString());
				break;
		}
	}
	
	protected void index(uint dest, MDValue* src, MDValue* key)
	{
		MDValue* method = getMM(src, MM.Index);

		if(method.isNull() == false)
		{
			if(method.isFunction() == false && method.isDelegate() == false)
				throw new MDRuntimeException(this, "Invalid opIndex metamethod for type '%s'", src.typeString());

			uint funcSlot = push(method);
			push(src);
			push(key);
			call(funcSlot, 2, 1);
			copyBasedStack(dest, funcSlot);

			return;
		}
		
		switch(src.type)
		{
			case MDValue.Type.Array:
				if(key.isInt() == false)
					throw new MDRuntimeException(this, "Attempting to access an array with a '%s'", key.typeString());
	
				if(key.asInt() < 0 || key.asInt() >= src.asArray.length)
					throw new MDRuntimeException(this, "Invalid array index: ", key.asInt());
	
				getBasedStack(dest).value = src.asArray[key.asInt];
				break;

			case MDValue.Type.String:
				if(key.isInt() == false)
					throw new MDRuntimeException(this, "Attempting to access a string with a '%s'", key.typeString());
					
				if(key.asInt() < 0 || key.asInt() >= src.asString.length)
					throw new MDRuntimeException(this, "Invalid string index: ", key.asInt());
					
				getBasedStack(dest).value = src.asString[key.asInt];
				break;

			case MDValue.Type.Table:
				getBasedStack(dest).value = src.asTable[key];
				break;

			case MDValue.Type.Instance:
				MDValue* v = src.asInstance[key];
				
				if(v is &MDValue.nullValue)
					throw new MDRuntimeException(this, "Attempting to access nonexistant member '%s' from class instance", key.toString());

				getBasedStack(dest).value = v;
				break;

			case MDValue.Type.Class:
				getBasedStack(dest).value = src.asClass[key];
				break;
				
			default:
				throw new MDRuntimeException(this, "Attempting to index a value of type '%s'", src.typeString());
				break;
		}
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

				if(!method.isFunction() && !method.isDelegate())
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
					case Op.Mod: s.getBasedStack(dest).value = src1.asInt() % src2.asInt(); return;

					case Op.Div:
						if(src2.asInt() == 0)
							throw new MDRuntimeException(s, "Integer divide by zero");

						s.getBasedStack(dest).value = src1.asInt() / src2.asInt(); return;
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

			if(!method.isFunction() && !method.isDelegate())
			{
				//method = s.getMM(src2, mmType);

				//if(!method.isFunction())
					throw new MDRuntimeException(s, "Cannot perform arithmetic on a '%s' and a '%s'", src1.typeString(), src2.typeString());
					
				//mNextThis = *src2;
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

				if(!method.isFunction() && !method.isDelegate())
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

			if(!method.isFunction() && !method.isDelegate())
			{
				//method = s.getMM(src2, mmType);

				//if(!method.isFunction())
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
						
						if(method.isFunction() || method.isDelegate())
						{
							uint funcReg = push(method);
							push(src);

							call(funcReg, 1, 1);
							copyBasedStack(i.rd, funcReg);
						}
						else
							getBasedStack(i.rd).value = cast(int)src.length;

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
						MDValue* index = getConst(i.rs2);
						assert(index.isString(), "trying to get a non-string global");
						getEnvironment()[index] = getCR1();
						break;
	
					case Op.GetUpvalue:
						getBasedStack(i.rd).value = getInternalUpvalue(i.imm);
						break;
	
					case Op.SetUpvalue:
						getInternalUpvalue(i.rs2).value = getCR1();
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
						MDValue src = *getBasedStack(rd);

						if(!src.isFunction() && !src.isDelegate())
						{
							MDValue* apply = getMM(&src, MM.Apply);
							
							if(apply.isNull())
								throw new MDRuntimeException(this, "No implementation of opApply for type '%s'", src.typeString());

							copyBasedStack(rd + 2, rd + 1);
							getBasedStack(rd + 1).value = src;
							getBasedStack(rd).value = apply;
							
							call(rd, 2, 3);
						}
						
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
	
						if(src1.isArray())
						{
							if(src2.isArray())
								getBasedStack(i.rd).value = src1.asArray() ~ src2.asArray();
							else
								getBasedStack(i.rd).value = src1.asArray() ~ src2;
								
							break;
						}
						
						if(src1.isString())
						{
							if(src2.isString())
							{
								getBasedStack(i.rd).value = src1.asString() ~ src2.asString();
								break;
							}
							else if(src2.isChar())
							{
								getBasedStack(i.rd).value = src1.asString() ~ src2.asChar();
								break;
							}
						}
						
						if(src1.isChar())
						{
							if(src2.isString())
							{
								getBasedStack(i.rd).value = src1.asChar() ~ src2.asString();
								break;
							}
							else if(src2.isChar())
							{
								dchar[2] data;
								data[0] = src1.asChar();
								data[1] = src2.asChar();

								getBasedStack(i.rd).value = data;
								break;
							}
						}

						MDValue* method = getMM(src1, MM.Cat);

						if(!method.isFunction() && !method.isDelegate())
						{
							//method = getMM(src2, MM.Cat);

							//if(!method.isFunction())
								throw new MDRuntimeException(this, "Cannot concatenate a '%s' and a '%s'",
									src1.typeString(), src2.typeString());
						}

						uint funcSlot = push(method);
						push(src1);
						push(src2);
						call(funcSlot, 2, 1);
						copyBasedStack(i.rd, funcSlot);
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
						index(i.rd, getCR1(), getCR2());
						break;
	
					case Op.IndexAssign:
						indexAssign(getBasedStack(i.rd), getCR1(), getCR2());
						break;
	
					case Op.Method:
						StackVal src = getCR1();
						
						getBasedStack(i.rd + 1).value = src;

						if(src.isInstance())
						{
							MDValue* v = src.asInstance[getCR2()];
							
							if(v is &MDValue.nullValue)
								throw new MDRuntimeException(this, "Attempting to access nonexistant member '%s' from class instance", getCR2().toString());

							getBasedStack(i.rd).value = v;
							break;
						}

						if(src.isTable())
						{
							MDValue* val = src.asTable[getCR2()];

							if(val.isFunction() || val.isDelegate())
							{
								getBasedStack(i.rd).value = val;
								break;
							}
						}

						MDTable metatable = MDGlobalState().getMetatable(src.type);

						if(metatable is null)
							throw new MDRuntimeException(this, "No metatable for type '%s'", src.typeString());

						getBasedStack(i.rd).value = metatable[getCR2()];
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
						
					case Op.Class:
						StackVal base = getCR2();

						if(base.isNull())
							getBasedStack(i.rd).value = new MDClass(this, getCR1().asString.asUTF32(), null);
						else if(!base.isClass())
							throw new MDRuntimeException(this, "Attempted to derive a class from a value of type '%s'", base.typeString());
						else
							getBasedStack(i.rd).value = new MDClass(this, getCR1().asString.asUTF32(), base.asClass());

						break;
						
					case Op.As:
						StackVal src = getBasedStack(i.rs1);
						StackVal cls = getBasedStack(i.rs2);
      
						if(!src.isInstance() || !cls.isClass())
							throw new MDRuntimeException(this, "Attempted to perform 'as' on '%s' and '%s'; must be 'instance' and 'class'",
								src.typeString(), cls.typeString());
								
						if(src.asInstance().castToClass(cls.asClass()))
							getBasedStack(i.rd).value = src;
						else
							getBasedStack(i.rd).setNull();
							
						break;

					case Op.Je:
					case Op.Jle:
					case Op.Jlt:
						assert(false, "lone conditional jump instruction");
						
					default:
						throw new MDRuntimeException(this, "Unimplemented opcode \"%s\"", i.toString());
				}
			}
		}
		catch(MDException e)
		{
			mTraceback ~= getDebugLocation();

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