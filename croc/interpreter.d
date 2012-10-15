/******************************************************************************
WIP

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

module croc.interpreter;

import tango.core.Tuple;
import tango.text.convert.Integer;
import tango.text.convert.Utf;

alias tango.text.convert.Integer.format Integer_format;
alias tango.text.convert.Utf.isValid Utf_isValid;
alias tango.text.convert.Utf.toString Utf_toString;

import tango.stdc.string;

import croc.api_debug;
import croc.api_interpreter;
import croc.api_stack;
import croc.base_alloc;
import croc.base_gc;
import croc.base_metamethods;
import croc.base_opcodes;
import croc.base_writebarrier;
import croc.types;
import croc.types_array;
import croc.types_class;
import croc.types_function;
import croc.types_instance;
import croc.types_memblock;
import croc.types_namespace;
import croc.types_string;
import croc.types_table;
import croc.types_thread;
import croc.utils;
import croc.vm;

// ================================================================================================================================================
// Package
// ================================================================================================================================================

package:

const FinalizeLoopLimit = 1000;

// Free all objects.
void freeAll(CrocVM* vm)
{
	gcCycle(vm, GCCycleType.BeginCleanup);

	auto limit = 0;

	do
	{
		limit++;

		if(limit > FinalizeLoopLimit)
			throw new Exception("Failed to clean up - you've got an awful lot of finalizable trash or something's broken.");

		runFinalizers(vm.mainThread);
		gcCycle(vm, GCCycleType.ContinueCleanup);
	} while(!vm.toFinalize.isEmpty())

	gcCycle(vm, GCCycleType.FinishCleanup);

	if(!vm.toFinalize.isEmpty())
		throw new Exception("Did you stick a finalizable object in a global metatable or something? I think you did. Stop doing that.");
}

void runFinalizers(CrocThread* t)
{
	auto alloc = &t.vm.alloc;
	auto modBuffer = &alloc.modBuffer;
	auto decBuffer = &alloc.decBuffer;

	disableGC(t.vm);

	// FINALIZE. Go through the finalize buffer, setting reference count to 1, running the finalizer, and setting it to finalized. At this point, the
	// object may have been resurrected but we can't really tell unless we make the write barrier more complicated. Or something. So we just queue
	// a decrement for it and put it on the modified buffer. It'll get deallocated the next time around.
	foreach(i; t.vm.toFinalize)
	{
		// debug Stdout.formatln("Taking {} off toFinalize", i).flush;

		auto size = stackSize(t);

		try
		{
			push(t, CrocValue(i.parent.finalizer));
			push(t, CrocValue(i));
			commonCall(t, t.stackIndex - 2, 0, callPrologue(t, t.stackIndex - 2, 0, 1, null));
		}
		catch(CrocException e)
		{
			catchException(t);
			getStdException(t, "FinalizerError");
			pushNull(t);
			pushFormat(t, "Error finalizing instance of class '{}'", i.parent.name.toString());
			rawCall(t, -3, 1);
			swap(t);
			fielda(t, -2, "cause");
			throwException(t);
		}

		i.gcflags |= GCFlags.Finalized;
		decBuffer.add(*alloc, cast(GCObject*)i);
	}

	enableGC(t.vm);

	t.vm.toFinalize.reset();
}

// ============================================================================
// Function Calling

CrocNamespace* getEnv(CrocThread* t, uword depth = 0)
{
	if(t.arIndex == 0)
		return t.vm.globals;
	else if(depth == 0)
		return t.currentAR.func.environment;

	for(word idx = t.arIndex - 1; idx >= 0; idx--)
	{
		if(depth == 0)
			return t.actRecs[cast(uword)idx].func.environment;
		else if(depth <= t.actRecs[cast(uword)idx].numTailcalls)
			throwStdException(t, "RuntimeException", "Attempting to get environment of function whose activation record was overwritten by a tail call");

		depth -= (t.actRecs[cast(uword)idx].numTailcalls + 1);
	}

	return t.vm.globals;
}

uword commonCall(CrocThread* t, AbsStack slot, word numReturns, bool isScript)
{
	t.nativeCallDepth++;
	scope(exit) t.nativeCallDepth--;

	if(isScript)
		execute(t);

	uword ret;

	if(numReturns == -1)
		ret = t.stackIndex - slot;
	else
	{
		t.stackIndex = slot + numReturns;
		ret = numReturns;
	}

	maybeGC(t);

	return ret;
}

bool commonMethodCall(CrocThread* t, AbsStack slot, CrocValue* self, CrocValue* lookup, CrocString* methodName, word numReturns, uword numParams)
{
	CrocClass* proto;
	auto method = lookupMethod(t, lookup, methodName, proto);

	// Idea is like this:

	// If we're calling the real method, the object is moved to the 'this' slot and the method takes its place.

	// If we're calling opMethod, the object is left where it is (or the custom context is moved to its place),
	// the method name goes where the context was, and we use callPrologue2 with a closure that's not on the stack.

	if(method.type != CrocValue.Type.Null)
	{
		// don't change the fucking order of these statements. self could point to slot.
		t.stack[slot + 1] = *self;
		t.stack[slot] = method;

		return callPrologue(t, slot, numReturns, numParams, proto);
	}
	else
	{
		auto mm = getMM(t, lookup, MM.Method, proto);

		if(mm is null)
		{
			typeString(t, lookup);
			throwStdException(t, "MethodException", "No implementation of method '{}' or {} for type '{}'", methodName.toString(), MetaNames[MM.Method], getString(t, -1));
		}

		t.stack[slot] = *self;
		t.stack[slot + 1] = methodName;

		return callPrologue2(t, mm, slot, numReturns, slot, numParams + 1, proto);
	}
}

CrocValue lookupMethod(CrocThread* t, CrocValue* v, CrocString* name, out CrocClass* proto)
{
	switch(v.type)
	{
		case CrocValue.Type.Class:
			if(auto ret = classobj.getMethod(v.mClass, name))
			{
				if(!ret.value.isPublic && ret.value.proto !is t.currentAR.proto)
					throwStdException(t, "MethodException", "Attempting to call private method '{}' from outside class '{}'", name.toString(), ret.value.proto.name.toString());

				proto = ret.value.proto;
				return ret.value.value;
			}
			else
				return CrocValue.nullValue;

		case CrocValue.Type.Instance:
			return getInstanceMethod(t, v.mInstance, name, proto);

		case CrocValue.Type.Namespace:
			if(auto ret = namespace.get(v.mNamespace, name))
				return *ret;
			else
				return CrocValue.nullValue;

		case CrocValue.Type.Table:
			if(auto ret = table.get(v.mTable, CrocValue(name)))
				return *ret;
			// fall through
		default:
			return getGlobalMetamethod(t, v.type, name);
	}
}

CrocValue getInstanceMethod(CrocThread* t, CrocInstance* inst, CrocString* name, out CrocClass* proto)
{
	if(auto ret = instance.getMethod(inst, name))
	{
		if(!ret.isPublic && ret.proto !is t.currentAR.proto)
			throwStdException(t, "MethodException", "Attempting to call private method '{}' from outside class '{}'", name.toString(), ret.proto.name.toString());

		proto = ret.proto;
		return ret.value;
	}
	else
		return CrocValue.nullValue;
}

CrocValue getGlobalMetamethod(CrocThread* t, CrocValue.Type type, CrocString* name)
{
	if(auto mt = getMetatable(t, type))
	{
		if(auto ret = namespace.get(mt, name))
			return *ret;
	}

	return CrocValue.nullValue;
}

CrocFunction* getMM(CrocThread* t, CrocValue* obj, MM method)
{
	CrocClass* dummy = void;
	return getMM(t, obj, method, dummy);
}

CrocFunction* getMM(CrocThread* t, CrocValue* obj, MM method, out CrocClass* proto)
{
	auto name = t.vm.metaStrings[method];
	CrocValue ret = void;

	if(obj.type == CrocValue.Type.Instance)
		ret = getInstanceMethod(t, obj.mInstance, name, proto);
	else
		ret = getGlobalMetamethod(t, obj.type, name);

	if(ret.type == CrocValue.Type.Function)
		return ret.mFunction;

	return null;
}

template tryMMParams(int numParams, int n = 1)
{
	static if(n <= numParams)
		const char[] tryMMParams = (n > 1 ? ", " : "") ~ "CrocValue* src" ~ n.stringof ~ tryMMParams!(numParams, n + 1);
	else
		const char[] tryMMParams = "";
}

template tryMMSaves(int numParams, int n = 1)
{
	static if(n <= numParams)
		const char[] tryMMSaves = "\tauto srcsave" ~ n.stringof ~ " = *src" ~ n.stringof ~ ";\n" ~ tryMMSaves!(numParams, n + 1);
	else
		const char[] tryMMSaves = "";
}

template tryMMPushes(int numParams, int n = 1)
{
	static if(n <= numParams)
		const char[] tryMMPushes = "\tpush(t, srcsave" ~ n.stringof ~ ");\n" ~ tryMMPushes!(numParams, n + 1);
	else
		const char[] tryMMPushes = "";
}

template tryMMImpl(int numParams, bool hasDest)
{
	const char[] tryMMImpl =
	"bool tryMM(CrocThread* t, MM mm, " ~ (hasDest? "CrocValue* dest, " : "") ~ tryMMParams!(numParams) ~ ")\n"
	"{\n"
	"	CrocClass* proto = null;"
	"	auto method = getMM(t, src1, mm, proto);\n"
	"\n"
	"	if(method is null)\n"
	"		return false;\n"
	"\n"
	~
	(hasDest?
		"	bool shouldLoad = void;\n"
		"	savePtr(t, dest, shouldLoad);\n"
	:
		"")
	~
	"\n"
	~ tryMMSaves!(numParams) ~
	"\n"
	"	auto funcSlot = push(t, CrocValue(method));\n"
	~ tryMMPushes!(numParams) ~
	"	commonCall(t, funcSlot + t.stackBase, " ~ (hasDest ? "1" : "0") ~ ", callPrologue(t, funcSlot + t.stackBase, " ~ (hasDest ? "1" : "0") ~ ", " ~ numParams.stringof ~ ", proto));\n"
	~
	(hasDest?
		"	if(shouldLoad)\n"
		"		loadPtr(t, dest);\n"
		"	*dest = t.stack[t.stackIndex - 1];\n"
		"	pop(t);\n"
	:
		"")
	~
	"	return true;\n"
	"}";
}

template tryMM(int numParams, bool hasDest)
{
	static assert(numParams > 0, "Need at least one param");
	mixin(tryMMImpl!(numParams, hasDest));
}

bool callPrologue(CrocThread* t, AbsStack slot, word numReturns, uword numParams, CrocClass* proto)
{
	assert(numParams > 0);
	auto func = &t.stack[slot];

	switch(func.type)
	{
		case CrocValue.Type.Function:
			return callPrologue2(t, func.mFunction, slot, numReturns, slot + 1, numParams, proto);

		case CrocValue.Type.Class:
			auto cls = func.mClass;
			auto inst = instance.create(t.vm, cls);

			// call any constructor
			auto ctor = classobj.getMethod(cls, t.vm.ctorString);

			if(ctor !is null)
			{
				if(ctor.value.value.type != CrocValue.Type.Function)
				{
					typeString(t, &ctor.value.value);
					throwStdException(t, "TypeException", "class constructor expected to be a 'function', not '{}'", getString(t, -1));
				}

				t.nativeCallDepth++;
				scope(exit) t.nativeCallDepth--;
				t.stack[slot] = ctor.value.value.mFunction;
				t.stack[slot + 1] = inst;

				// do this instead of rawCall so the proto is set correctly
				if(callPrologue(t, slot, 0, numParams, cls))
					execute(t);
			}

			t.stack[slot] = inst;

			if(numReturns == -1)
				t.stackIndex = slot + 1;
			else
			{
				if(numReturns > 1)
					t.stack[slot + 1 .. slot + numReturns] = CrocValue.nullValue;

				if(t.arIndex == 0)
				{
					t.state = CrocThread.State.Dead;
					t.shouldHalt = false;
					t.stackIndex = slot + numReturns;

					if(t is t.vm.mainThread)
						t.vm.curThread = t;
				}
				else if(t.currentAR.savedTop < slot + numReturns)
					t.stackIndex = slot + numReturns;
				else
					t.stackIndex = t.currentAR.savedTop;
			}

			return false;

		case CrocValue.Type.Thread:
			auto thread = func.mThread;

			if(thread is t)
				throwStdException(t, "RuntimeException", "Thread attempting to resume itself");

			if(thread is t.vm.mainThread)
				throwStdException(t, "RuntimeException", "Attempting to resume VM's main thread");

			if(thread.state != CrocThread.State.Initial && thread.state != CrocThread.State.Suspended)
				throwStdException(t, "StateException", "Attempting to resume a {} coroutine", CrocThread.StateStrings[thread.state]);

			auto ar = pushAR(t);

			ar.base = slot;
			ar.savedTop = t.stackIndex;
			ar.vargBase = slot;
			ar.returnSlot = slot;
			ar.func = null;
			ar.pc = null;
			ar.numReturns = numReturns;
			ar.proto = null;
			ar.numTailcalls = 0;
			ar.firstResult = 0;
			ar.numResults = 0;
			ar.unwindCounter = 0;
			ar.unwindReturn = null;

			t.stackIndex = slot;

			uword numRets = void;

			try
			{
				if(thread.state == CrocThread.State.Initial)
				{
					checkStack(thread, cast(AbsStack)(numParams + 1));
					thread.stack[1 .. 1 + numParams] = t.stack[slot + 1 .. slot + 1 + numParams];
					thread.stackIndex += numParams;
				}
				else
				{
					// Get rid of 'this'
					numParams--;
					saveResults(thread, t, slot + 2, numParams);
				}

				auto savedState = t.state;
				t.state = CrocThread.State.Waiting;

				scope(exit)
				{
					t.state = savedState;
					t.vm.curThread = t;
				}

				numRets = resume(thread, numParams);
			}
			catch(CrocException e)
			{
				callEpilogue(t, false);
				continueTraceback(t, CrocValue(t.vm.exception));
				throw e;
			}
			// Don't have to handle halt exceptions; they can't propagate out of a thread

			saveResults(t, thread, thread.stackIndex - numRets, numRets);
			thread.stackIndex -= numRets;

			callEpilogue(t, true);
			return false;

		default:
			auto method = getMM(t, func, MM.Call, proto);

			if(method is null)
			{
				typeString(t, func);
				throwStdException(t, "TypeException", "No implementation of {} for type '{}'", MetaNames[MM.Call], getString(t, -1));
			}

			t.stack[slot + 1] = *func;
			*func = method;
			return callPrologue2(t, method, slot, numReturns, slot + 1, numParams, proto);
	}
}

bool callPrologue2(CrocThread* t, CrocFunction* func, AbsStack returnSlot, word numReturns, AbsStack paramSlot, word numParams, CrocClass* proto)
{
	const char[] wrapEH =
		"catch(CrocException e)
		{
			callEpilogue(t, false);
			throw e;
		}
		catch(CrocHaltException e)
		{
			unwindEH(t);
			callEpilogue(t, false);
			throw e;
		}";


	if(numParams > func.maxParams)
		throwStdException(t, "ParamException", "Function {} expected at most {} parameters but was given {}", func.name.toString(), func.maxParams - 1, numParams - 1);

	if(!func.isNative)
	{
		// Script function
		auto funcDef = func.scriptFunc;
		auto ar = pushAR(t);

		if(funcDef.isVararg && numParams > func.numParams)
		{
			// In this case, we move the formal parameters after the varargs and null out where the formal
			// params used to be.
			ar.base = paramSlot + numParams;
			ar.vargBase = paramSlot + func.numParams;

			checkStack(t, ar.base + funcDef.stackSize - 1);

			auto oldParams = t.stack[paramSlot .. paramSlot + func.numParams];
			t.stack[ar.base .. ar.base + func.numParams] = oldParams;
			oldParams[] = CrocValue.nullValue;

			// For nulling out the stack.
			numParams = func.numParams;
		}
		else
		{
			// In this case, everything is where it needs to be already.
			ar.base = paramSlot;
			ar.vargBase = paramSlot;

			checkStack(t, ar.base + funcDef.stackSize - 1);

			// If we have too few params, the extra param slots will be nulled out.
		}

		// Null out the stack frame after the parameters.
		t.stack[ar.base + numParams .. ar.base + funcDef.stackSize] = CrocValue.nullValue;

		// Fill in the rest of the activation record.
		ar.returnSlot = returnSlot;
		ar.func = func;
		ar.pc = funcDef.code.ptr;
		ar.numReturns = numReturns;
		ar.firstResult = 0;
		ar.numResults = 0;
		ar.proto = proto is null ? null : proto;
		ar.numTailcalls = 0;
		ar.savedTop = ar.base + funcDef.stackSize;
		ar.unwindCounter = 0;
		ar.unwindReturn = null;

		// Set the stack indices.
		t.stackBase = ar.base;
		t.stackIndex = ar.savedTop;

		// Call any hook.
		mixin(
		"if(t.hooks & CrocThread.Hook.Call)
		{
			try
				callHook(t, CrocThread.Hook.Call);
		" ~ wrapEH ~ "
		}");

		return true;
	}
	else
	{
		// Native function
		t.stackIndex = paramSlot + numParams;
		checkStack(t, t.stackIndex);

		auto ar = pushAR(t);

		ar.base = paramSlot;
		ar.vargBase = paramSlot;
		ar.returnSlot = returnSlot;
		ar.func = func;
		ar.numReturns = numReturns;
		ar.firstResult = 0;
		ar.numResults = 0;
		ar.savedTop = t.stackIndex;
		ar.proto = proto is null ? null : proto;
		ar.numTailcalls = 0;
		ar.unwindCounter = 0;
		ar.unwindReturn = null;

		t.stackBase = ar.base;

		uword actualReturns = void;

		mixin("try
		{
			if(t.hooks & CrocThread.Hook.Call)
				callHook(t, CrocThread.Hook.Call);

			t.nativeCallDepth++;
			scope(exit) t.nativeCallDepth--;

			auto savedState = t.state;
			t.state = CrocThread.State.Running;
			t.vm.curThread = t;
			scope(exit) t.state = savedState;

			actualReturns = func.nativeFunc(t);
		}" ~ wrapEH);

		saveResults(t, t, t.stackIndex - actualReturns, actualReturns);
		callEpilogue(t, true);
		return false;
	}
}

void callEpilogue(CrocThread* t, bool needResults)
{
	if(t.hooks & CrocThread.Hook.Ret)
		callReturnHooks(t);

	auto destSlot = t.currentAR.returnSlot;
	auto numExpRets = t.currentAR.numReturns;
	auto results = loadResults(t);

	bool isMultRet = false;

	if(numExpRets == -1)
	{
		isMultRet = true;
		numExpRets = results.length;
	}

	popAR(t);

	if(needResults)
	{
		t.numYields = results.length;

		auto stk = t.stack;

		if(numExpRets <= results.length)
			stk[destSlot .. destSlot + numExpRets] = results[0 .. numExpRets];
		else
		{
			stk[destSlot .. destSlot + results.length] = results[];
			stk[destSlot + results.length .. destSlot + numExpRets] = CrocValue.nullValue;
		}
	}
	else
		t.numYields = 0;

	if(t.arIndex == 0)
	{
		t.state = CrocThread.State.Dead;
		t.shouldHalt = false;
		t.stackIndex = destSlot + numExpRets;

		if(t is t.vm.mainThread)
			t.vm.curThread = t;
	}
	else if(needResults && (isMultRet || t.currentAR.savedTop < destSlot + numExpRets)) // last case happens in native -> native calls
		t.stackIndex = destSlot + numExpRets;
	else
		t.stackIndex = t.currentAR.savedTop;
}

void saveResults(CrocThread* t, CrocThread* from, AbsStack first, uword num)
{
	if(num == 0)
		return;

	if((t.results.length - t.resultIndex) < num)
	{
		auto newLen = t.results.length * 2;

		if(newLen - t.resultIndex < num)
			newLen = t.resultIndex + num;

		t.vm.alloc.resizeArray(t.results, newLen);
	}

	assert(t.currentAR.firstResult is 0 && t.currentAR.numResults is 0);

	auto tmp = from.stack[first .. first + num];
	t.results[t.resultIndex .. t.resultIndex + num] = tmp;
	t.currentAR.firstResult = t.resultIndex;
	t.currentAR.numResults = num;

	t.resultIndex += num;
}

CrocValue[] loadResults(CrocThread* t)
{
	auto first = t.currentAR.firstResult;
	auto num = t.currentAR.numResults;
	auto ret = t.results[first .. first + num];
	t.currentAR.firstResult = 0;
	t.currentAR.numResults = 0;
	t.resultIndex -= num;
	return ret;
}

void unwindEH(CrocThread* t)
{
	while(t.trIndex > 0 && t.currentTR.actRecord >= t.arIndex)
		popTR(t);
}

// ============================================================================
// Implementations

word toStringImpl(CrocThread* t, CrocValue v, bool raw)
{
	// ORDER CROCVALUE TYPE
	if(v.type <= CrocValue.Type.String)
	{
		char[80] buffer = void;

		switch(v.type)
		{
			case CrocValue.Type.Null:  return pushString(t, "null");
			case CrocValue.Type.Bool:  return pushString(t, v.mBool ? "true" : "false");
			case CrocValue.Type.Int:   return pushString(t, Integer_format(buffer, v.mInt));
			case CrocValue.Type.Float:
				uword pos = 0;

				auto size = t.vm.formatter.convert((char[] s)
				{
					if(pos + s.length > buffer.length)
						s.length = buffer.length - pos;

					buffer[pos .. pos + s.length] = s[];
					pos += s.length;
					return cast(uint)s.length; // the cast is there to make things work on x64 :P
				}, "{}", v.mFloat);

				return pushString(t, buffer[0 .. pos]);

			case CrocValue.Type.Char:
				auto inbuf = v.mChar;

				if(!Utf_isValid(inbuf))
					throwStdException(t, "UnicodeException", "Character '{:X}' is not a valid Unicode codepoint", cast(uint)inbuf);

				uint ate = 0;
				return pushString(t, Utf_toString((&inbuf)[0 .. 1], buffer, &ate));

			case CrocValue.Type.String:
				return push(t, v);

			default: assert(false);
		}
	}

	if(!raw)
	{
		CrocClass* proto;
		if(auto method = getMM(t, &v, MM.ToString, proto))
		{
			auto funcSlot = push(t, CrocValue(method));
			push(t, v);
			commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 1, proto));

			if(t.stack[t.stackIndex - 1].type != CrocValue.Type.String)
			{
				typeString(t, &t.stack[t.stackIndex - 1]);
				throwStdException(t, "TypeException", "toString was supposed to return a string, but returned a '{}'", getString(t, -1));
			}

			return stackSize(t) - 1;
		}
	}

	switch(v.type)
	{
		case CrocValue.Type.Function:
			auto f = v.mFunction;

			if(f.isNative)
				return pushFormat(t, "native {} {}", CrocValue.typeStrings[CrocValue.Type.Function], f.name.toString());
			else
			{
				auto sf = f.scriptFunc;
				return pushFormat(t, "script {} {}({}({}:{}))", CrocValue.typeStrings[CrocValue.Type.Function], f.name.toString(), sf.locFile.toString(), sf.locLine, sf.locCol);
			}

		case CrocValue.Type.Class:    return pushFormat(t, "{} {} (0x{:X8})", CrocValue.typeStrings[CrocValue.Type.Class], v.mClass.name.toString(), cast(void*)v.mClass);
		case CrocValue.Type.Instance: return pushFormat(t, "{} of {} (0x{:X8})", CrocValue.typeStrings[CrocValue.Type.Instance], v.mInstance.parent.name.toString(), cast(void*)v.mInstance);

		case CrocValue.Type.Namespace:
			if(raw)
				goto default;

			pushString(t, CrocValue.typeStrings[CrocValue.Type.Namespace]);
			pushChar(t, ' ');
			pushNamespaceNamestring(t, v.mNamespace);

			auto slot = t.stackIndex - 3;
			catImpl(t, slot, slot, 3);
			pop(t, 2);
			return slot - t.stackBase;

		case CrocValue.Type.FuncDef:
			auto d = v.mFuncDef;
			return pushFormat(t, "{} {}({}({}:{}))", CrocValue.typeStrings[CrocValue.Type.FuncDef], d.name.toString(), d.locFile.toString(), d.locLine, d.locCol);

		default:
			return pushFormat(t, "{} 0x{:X8}", CrocValue.typeStrings[v.type], cast(void*)v.mBaseObj);
	}
}

bool inImpl(CrocThread* t, CrocValue* item, CrocValue* container)
{
	switch(container.type)
	{
		case CrocValue.Type.String:
			if(item.type == CrocValue.Type.Char)
				return string.contains(container.mString, item.mChar);
			else if(item.type == CrocValue.Type.String)
				return string.contains(container.mString, item.mString.toString());
			else
			{
				typeString(t, item);
				throwStdException(t, "TypeException", "Can only use characters to look in strings, not '{}'", getString(t, -1));
			}

		case CrocValue.Type.Table:
			return table.contains(container.mTable, *item);

		case CrocValue.Type.Array:
			return array.contains(container.mArray, *item);

		case CrocValue.Type.Namespace:
			if(item.type != CrocValue.Type.String)
			{
				typeString(t, item);
				throwStdException(t, "TypeException", "Can only use strings to look in namespaces, not '{}'", getString(t, -1));
			}

			return namespace.contains(container.mNamespace, item.mString);

		default:
			CrocClass* proto;
			auto method = getMM(t, container, MM.In, proto);

			if(method is null)
			{
				typeString(t, container);
				throwStdException(t, "TypeException", "No implementation of {} for type '{}'", MetaNames[MM.In], getString(t, -1));
			}

			auto containersave = *container;
			auto itemsave = *item;

			auto funcSlot = push(t, CrocValue(method));
			push(t, containersave);
			push(t, itemsave);
			commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 2, proto));

			auto ret = !t.stack[t.stackIndex - 1].isFalse();
			pop(t);
			return ret;
	}
}

void idxImpl(CrocThread* t, AbsStack dest, CrocValue* container, CrocValue* key)
{
	switch(container.type)
	{
		case CrocValue.Type.Array:
			if(key.type != CrocValue.Type.Int)
			{
				typeString(t, key);
				throwStdException(t, "TypeException", "Attempting to index an array with a '{}'", getString(t, -1));
			}

			auto index = key.mInt;
			auto arr = container.mArray;

			if(index < 0)
				index += arr.length;

			if(index < 0 || index >= arr.length)
				throwStdException(t, "BoundsException", "Invalid array index {} (length is {})", key.mInt, arr.length);

			t.stack[dest] = arr.toArray()[cast(uword)index].value;
			return;

		case CrocValue.Type.Memblock:
			if(key.type != CrocValue.Type.Int)
			{
				typeString(t, key);
				throwStdException(t, "TypeException", "Attempting to index a memblock with a '{}'", getString(t, -1));
			}

			auto index = key.mInt;
			auto mb = container.mMemblock;

			if(index < 0)
				index += mb.data.length;

			if(index < 0 || index >= mb.data.length)
				throwStdException(t, "BoundsException", "Invalid memblock index {} (length is {})", key.mInt, mb.data.length);

			t.stack[dest] = cast(crocint)mb.data[cast(uword)index];
			return;

		case CrocValue.Type.String:
			if(key.type != CrocValue.Type.Int)
			{
				typeString(t, key);
				throwStdException(t, "TypeException", "Attempting to index a string with a '{}'", getString(t, -1));
			}

			auto index = key.mInt;
			auto str = container.mString;

			if(index < 0)
				index += str.cpLength;

			if(index < 0 || index >= str.cpLength)
				throwStdException(t, "BoundsException", "Invalid string index {} (length is {})", key.mInt, str.cpLength);

			t.stack[dest] = string.charAt(str, cast(uword)index);
			return;

		case CrocValue.Type.Table:
			return tableIdxImpl(t, dest, container, key);

		default:
			if(tryMM!(2, true)(t, MM.Index, &t.stack[dest], container, key))
				return;

			typeString(t, container);
			throwStdException(t, "TypeException", "Attempting to index a value of type '{}'", getString(t, -1));
	}
}

void tableIdxImpl(CrocThread* t, AbsStack dest, CrocValue* container, CrocValue* key)
{
	if(auto v = table.get(container.mTable, *key))
		t.stack[dest] = *v;
	else
		t.stack[dest] = CrocValue.nullValue;
}

void idxaImpl(CrocThread* t, AbsStack container, CrocValue* key, CrocValue* value)
{
	switch(t.stack[container].type)
	{
		case CrocValue.Type.Array:
			if(key.type != CrocValue.Type.Int)
			{
				typeString(t, key);
				throwStdException(t, "TypeException", "Attempting to index-assign an array with a '{}'", getString(t, -1));
			}

			auto index = key.mInt;
			auto arr = t.stack[container].mArray;

			if(index < 0)
				index += arr.length;

			if(index < 0 || index >= arr.length)
				throwStdException(t, "BoundsException", "Invalid array index {} (length is {})", key.mInt, arr.length);

			array.idxa(t.vm.alloc, arr, cast(uword)index, *value);
			return;

		case CrocValue.Type.Memblock:
			if(key.type != CrocValue.Type.Int)
			{
				typeString(t, key);
				throwStdException(t, "TypeException", "Attempting to index-assign a memblock with a '{}'", getString(t, -1));
			}

			auto index = key.mInt;
			auto mb = t.stack[container].mMemblock;

			if(index < 0)
				index += mb.data.length;

			if(index < 0 || index >= mb.data.length)
				throwStdException(t, "BoundsException", "Invalid memblock index {} (length is {})", key.mInt, mb.data.length);

			if(value.type != CrocValue.Type.Int)
			{
				typeString(t, value);
				throwStdException(t, "TypeException", "Attempting to index-assign a value of type '{}' into a memblock", getString(t, -1));
			}

			mb.data[cast(uword)index] = cast(ubyte)value.mInt;
			return;

		case CrocValue.Type.Table:
			return tableIdxaImpl(t, container, key, value);

		default:
			if(tryMM!(3, false)(t, MM.IndexAssign, &t.stack[container], key, value))
				return;

			typeString(t, &t.stack[container]);
			throwStdException(t, "TypeException", "Attempting to index-assign a value of type '{}'", getString(t, -1));
	}
}

void tableIdxaImpl(CrocThread* t, AbsStack container, CrocValue* key, CrocValue* value)
{
	if(key.type == CrocValue.Type.Null)
		throwStdException(t, "TypeException", "Attempting to index-assign a table with a key of type 'null'");

	table.idxa(t.vm.alloc, t.stack[container].mTable, *key, *value);
}

word commonField(CrocThread* t, AbsStack container, bool raw)
{
	auto slot = t.stackIndex - 1;
	fieldImpl(t, slot, &t.stack[container], t.stack[slot].mString, raw);
	return stackSize(t) - 1;
}

void commonFielda(CrocThread* t, AbsStack container, bool raw)
{
	auto slot = t.stackIndex - 2;
	fieldaImpl(t, container, t.stack[slot].mString, &t.stack[slot + 1], raw);
	pop(t, 2);
}

void fieldImpl(CrocThread* t, AbsStack dest, CrocValue* container, CrocString* name, bool raw)
{
	switch(container.type)
	{
		case CrocValue.Type.Table:
			// This is right, tables do not distinguish between field access and indexing.
			return tableIdxImpl(t, dest, container, &CrocValue(name));

		case CrocValue.Type.Class:
			auto c = container.mClass;
			auto v = classobj.getField(c, name);

			if(v is null)
			{
				v = classobj.getMethod(c, name);

				if(v is null)
					throwStdException(t, "FieldException", "Attempting to access nonexistent field '{}' from class '{}'", name.toString(), c.name.toString());
			}

			if(!v.value.isPublic && t.currentAR.proto !is v.value.proto)
				throwStdException(t, "FieldException", "Attempting to access private field '{}' from outside class '{}'", name.toString(), v.value.proto.name.toString());

			return t.stack[dest] = v.value.value;

		case CrocValue.Type.Instance:
			auto i = container.mInstance;

			if(auto v = instance.getField(i, name))
			{
				if(!v.value.isPublic && t.currentAR.proto !is v.value.proto)
					throwStdException(t, "FieldException", "Attempting to access private field '{}' from outside class '{}'", name.toString(), v.value.proto.name.toString());

				return t.stack[dest] = v.value.value;
			}
			else if(!raw && tryMM!(2, true)(t, MM.Field, &t.stack[dest], container, &CrocValue(name)))
				return;
			else
				throwStdException(t, "FieldException", "Attempting to access nonexistent field '{}' from instance of class '{}'", name.toString(), i.parent.name.toString());

		case CrocValue.Type.Namespace:
			auto v = namespace.get(container.mNamespace, name);

			if(v is null)
			{
				toStringImpl(t, *container, false);
				throwStdException(t, "FieldException", "Attempting to access nonexistent field '{}' from '{}'", name.toString(), getString(t, -1));
			}

			return t.stack[dest] = *v;

		default:
			if(!raw && tryMM!(2, true)(t, MM.Field, &t.stack[dest], container, &CrocValue(name)))
				return;

			typeString(t, container);
			throwStdException(t, "TypeException", "Attempting to access field '{}' from a value of type '{}'", name.toString(), getString(t, -1));
	}
}

void fieldaImpl(CrocThread* t, AbsStack container, CrocString* name, CrocValue* value, bool raw)
{
	switch(t.stack[container].type)
	{
		case CrocValue.Type.Table:
			// This is right, tables do not distinguish between field access and indexing.
			return tableIdxaImpl(t, container, &CrocValue(name), value);

		case CrocValue.Type.Class:
			auto c = t.stack[container].mClass;

			if(auto slot = classobj.getField(c, name))
			{
				if(!slot.value.isPublic && t.currentAR.proto !is slot.value.proto)
					throwStdException(t, "FieldException", "Attempting to access private field '{}' from outside class '{}'", name.toString(), slot.value.proto.name.toString());

				classobj.setField(t.vm.alloc, c, slot, value);
			}
			else if(auto slot = classobj.getMethod(c, name))
			{
				if(!slot.value.isPublic && t.currentAR.proto !is slot.value.proto)
					throwStdException(t, "FieldException", "Attempting to access private method '{}' from outside class '{}'", name.toString(), slot.value.proto.name.toString());

				if(c.isFrozen)
					throwStdException(t, "FieldException", "Attempting to change method '{}' in class '{}' after it has been frozen", name.toString(), c.name.toString());

				classobj.setMethod(t.vm.alloc, c, slot, value);
			}
			else
				throwStdException(t, "FieldException", "Attempting to assign to nonexistent field '{}' in class '{}'", name.toString(), c.name.toString());

			return;

		case CrocValue.Type.Instance:
			auto i = t.stack[container].mInstance;

			if(auto slot = instance.getField(i, name))
			{
				if(!slot.value.isPublic && t.currentAR.proto !is slot.value.proto)
					throwStdException(t, "FieldException", "Attempting to access private field '{}' from outside class '{}'", name.toString(), slot.value.proto.name.toString());

				instance.setField(t.vm.alloc, i, slot, value);
			}
			else if(!raw && tryMM!(3, false)(t, MM.FieldAssign, &t.stack[container], &CrocValue(name), value))
				return;
			else
				throwStdException(t, "FieldException", "Attempting to assign to nonexistent field '{}' in instance of class '{}'", name.toString(), i.parent.name.toString());
			return;

		case CrocValue.Type.Namespace:
			return namespace.set(t.vm.alloc, t.stack[container].mNamespace, name, value);

		default:
			if(!raw && tryMM!(3, false)(t, MM.FieldAssign, &t.stack[container], &CrocValue(name), value))
				return;

			typeString(t, &t.stack[container]);
			throwStdException(t, "TypeException", "Attempting to assign field '{}' into a value of type '{}'", name.toString(), getString(t, -1));
	}
}

crocint compareImpl(CrocThread* t, CrocValue* a, CrocValue* b)
{
	if(a.type == CrocValue.Type.Int)
	{
		if(b.type == CrocValue.Type.Int)
			return Compare3(a.mInt, b.mInt);
		else if(b.type == CrocValue.Type.Float)
			return Compare3(cast(crocfloat)a.mInt, b.mFloat);
	}
	else if(a.type == CrocValue.Type.Float)
	{
		if(b.type == CrocValue.Type.Int)
			return Compare3(a.mFloat, cast(crocfloat)b.mInt);
		else if(b.type == CrocValue.Type.Float)
			return Compare3(a.mFloat, b.mFloat);
	}

	if(a.type == b.type)
	{
		switch(a.type)
		{
			case CrocValue.Type.Null:   return 0;
			case CrocValue.Type.Bool:   return (cast(crocint)a.mBool - cast(crocint)b.mBool);
			case CrocValue.Type.Char:   return Compare3(a.mChar, b.mChar);
			case CrocValue.Type.String: return (a.mString is b.mString) ? 0 : string.compare(a.mString, b.mString);
			default: break;
		}
	}

	CrocClass* proto;
	if(a.type == b.type || b.type != CrocValue.Type.Instance)
	{
		if(auto method = getMM(t, a, MM.Cmp, proto))
			return commonCompare(t, method, a, b, proto);
		else if(auto method = getMM(t, b, MM.Cmp, proto))
			return -commonCompare(t, method, b, a, proto);
	}
	else
	{
		if(auto method = getMM(t, b, MM.Cmp, proto))
			return -commonCompare(t, method, b, a, proto);
		else if(auto method = getMM(t, a, MM.Cmp, proto))
			return commonCompare(t, method, a, b, proto);
	}

	auto bsave = *b;
	typeString(t, a);
	typeString(t, &bsave);
	throwStdException(t, "TypeException", "Can't compare types '{}' and '{}'", getString(t, -2), getString(t, -1));
	assert(false);
}

crocint commonCompare(CrocThread* t, CrocFunction* method, CrocValue* a, CrocValue* b, CrocClass* proto)
{
	auto asave = *a;
	auto bsave = *b;

	auto funcReg = push(t, CrocValue(method));
	push(t, asave);
	push(t, bsave);
	commonCall(t, funcReg + t.stackBase, 1, callPrologue(t, funcReg + t.stackBase, 1, 2, proto));

	auto ret = *getValue(t, -1);
	pop(t);

	if(ret.type != CrocValue.Type.Int)
	{
		typeString(t, &ret);
		throwStdException(t, "TypeException", "{} is expected to return an int, but '{}' was returned instead", MetaNames[MM.Cmp], getString(t, -1));
	}

	return ret.mInt;
}

bool switchCmpImpl(CrocThread* t, CrocValue* a, CrocValue* b)
{
	if(a.type != b.type)
		return false;

	if(a.opEquals(*b))
		return true;

	CrocClass* proto;

	if(a.type == CrocValue.Type.Instance)
	{
		if(auto method = getMM(t, a, MM.Cmp, proto))
			return commonCompare(t, method, a, b, proto) == 0;
		else if(auto method = getMM(t, b, MM.Cmp, proto))
			return commonCompare(t, method, b, a, proto) == 0;
	}

	return false;
}

bool equalsImpl(CrocThread* t, CrocValue* a, CrocValue* b)
{
	if(a.type == CrocValue.Type.Int)
	{
		if(b.type == CrocValue.Type.Int)
			return a.mInt == b.mInt;
		else if(b.type == CrocValue.Type.Float)
			return (cast(crocfloat)a.mInt) == b.mFloat;
	}
	else if(a.type == CrocValue.Type.Float)
	{
		if(b.type == CrocValue.Type.Int)
			return a.mFloat == (cast(crocfloat)b.mInt);
		else if(b.type == CrocValue.Type.Float)
			return a.mFloat == b.mFloat;
	}

	if(a.type == b.type)
	{
		switch(a.type)
		{
			case CrocValue.Type.Null:   return true;
			case CrocValue.Type.Bool:   return a.mBool == b.mBool;
			case CrocValue.Type.Char:   return a.mChar == b.mChar;
			case CrocValue.Type.String: return a.mString is b.mString;
			default: break;
		}
	}

	CrocClass* proto;
	if(a.type == b.type || b.type != CrocValue.Type.Instance)
	{
		if(auto method = getMM(t, a, MM.Equals, proto))
			return commonEquals(t, method, a, b, proto);
		else if(auto method = getMM(t, b, MM.Equals, proto))
			return commonEquals(t, method, b, a, proto);
	}
	else
	{
		if(auto method = getMM(t, b, MM.Equals, proto))
			return commonEquals(t, method, b, a, proto);
		else if(auto method = getMM(t, a, MM.Equals, proto))
			return commonEquals(t, method, a, b, proto);
	}

	auto bsave = *b;
	typeString(t, a);
	typeString(t, &bsave);
	throwStdException(t, "TypeException", "Can't compare types '{}' and '{}' for equality", getString(t, -2), getString(t, -1));
	assert(false);
}

bool commonEquals(CrocThread* t, CrocFunction* method, CrocValue* a, CrocValue* b, CrocClass* proto)
{
	auto asave = *a;
	auto bsave = *b;

	auto funcReg = push(t, CrocValue(method));
	push(t, asave);
	push(t, bsave);
	commonCall(t, funcReg + t.stackBase, 1, callPrologue(t, funcReg + t.stackBase, 1, 2, proto));

	auto ret = *getValue(t, -1);
	pop(t);

	if(ret.type != CrocValue.Type.Bool)
	{
		typeString(t, &ret);
		throwStdException(t, "TypeException", "{} is expected to return a bool, but '{}' was returned instead", MetaNames[MM.Equals], getString(t, -1));
	}

	return ret.mBool;
}

void lenImpl(CrocThread* t, AbsStack dest, CrocValue* src)
{
	switch(src.type)
	{
		case CrocValue.Type.String:    return t.stack[dest] = cast(crocint)src.mString.cpLength;
		case CrocValue.Type.Table:     return t.stack[dest] = cast(crocint)table.length(src.mTable);
		case CrocValue.Type.Array:     return t.stack[dest] = cast(crocint)src.mArray.length;
		case CrocValue.Type.Memblock:  return t.stack[dest] = cast(crocint)src.mMemblock.data.length;
		case CrocValue.Type.Namespace: return t.stack[dest] = cast(crocint)namespace.length(src.mNamespace);

		default:
			if(tryMM!(1, true)(t, MM.Length, &t.stack[dest], src))
				return;

			typeString(t, src);
			throwStdException(t, "TypeException", "Can't get the length of a '{}'", getString(t, -1));
	}
}

void lenaImpl(CrocThread* t, AbsStack dest, CrocValue* len)
{
	switch(t.stack[dest].type)
	{
		case CrocValue.Type.Array:
			if(len.type != CrocValue.Type.Int)
			{
				typeString(t, len);
				throwStdException(t, "TypeException", "Attempting to set the length of an array using a length of type '{}'", getString(t, -1));
			}

			auto l = len.mInt;

			if(l < 0 || l > uword.max)
				throwStdException(t, "RangeException", "Invalid length ({})", l);

			return array.resize(t.vm.alloc, t.stack[dest].mArray, cast(uword)l);

		case CrocValue.Type.Memblock:
			if(len.type != CrocValue.Type.Int)
			{
				typeString(t, len);
				throwStdException(t, "TypeException", "Attempting to set the length of a memblock using a length of type '{}'", getString(t, -1));
			}

			auto mb = t.stack[dest].mMemblock;

			if(!mb.ownData)
				throwStdException(t, "ValueException", "Attempting to resize a memblock which does not own its data");

			auto l = len.mInt;

			if(l < 0 || l > uword.max)
				throwStdException(t, "RangeException", "Invalid length ({})", l);

			return memblock.resize(t.vm.alloc, mb, cast(uword)l);

		default:
			if(tryMM!(2, false)(t, MM.LengthAssign, &t.stack[dest], len))
				return;

			typeString(t, &t.stack[dest]);
			throwStdException(t, "TypeException", "Can't set the length of a '{}'", getString(t, -1));
	}
}

void sliceImpl(CrocThread* t, AbsStack dest, CrocValue* src, CrocValue* lo, CrocValue* hi)
{
	switch(src.type)
	{
		case CrocValue.Type.Array:
			auto arr = src.mArray;
			crocint loIndex = void;
			crocint hiIndex = void;

			if(lo.type == CrocValue.Type.Null && hi.type == CrocValue.Type.Null)
				return t.stack[dest] = *src;

			if(!correctIndices(loIndex, hiIndex, lo, hi, arr.length))
			{
				auto hisave = *hi;
				typeString(t, lo);
				typeString(t, &hisave);
				throwStdException(t, "TypeException", "Attempting to slice an array with indices of type '{}' and '{}'", getString(t, -2), getString(t, -1));
			}

			if(!validIndices(loIndex, hiIndex, arr.length))
				throwStdException(t, "BoundsException", "Invalid slice indices [{} .. {}] (array length = {})", loIndex, hiIndex, arr.length);

			return t.stack[dest] = array.slice(t.vm.alloc, arr, cast(uword)loIndex, cast(uword)hiIndex);

		case CrocValue.Type.Memblock:
			auto mb = src.mMemblock;
			crocint loIndex = void;
			crocint hiIndex = void;

			if(lo.type == CrocValue.Type.Null && hi.type == CrocValue.Type.Null)
				return t.stack[dest] = *src;

			if(!correctIndices(loIndex, hiIndex, lo, hi, mb.data.length))
			{
				auto hisave = *hi;
				typeString(t, lo);
				typeString(t, &hisave);
				throwStdException(t, "TypeException", "Attempting to slice a memblock with indices of type '{}' and '{}'", getString(t, -2), getString(t, -1));
			}

			if(!validIndices(loIndex, hiIndex, mb.data.length))
				throwStdException(t, "BoundsException", "Invalid slice indices [{} .. {}] (memblock length = {})", loIndex, hiIndex, mb.data.length);

			return t.stack[dest] = memblock.slice(t.vm.alloc, mb, cast(uword)loIndex, cast(uword)hiIndex);

		case CrocValue.Type.String:
			auto str = src.mString;
			crocint loIndex = void;
			crocint hiIndex = void;

			if(lo.type == CrocValue.Type.Null && hi.type == CrocValue.Type.Null)
				return t.stack[dest] = *src;

			if(!correctIndices(loIndex, hiIndex, lo, hi, str.cpLength))
			{
				auto hisave = *hi;
				typeString(t, lo);
				typeString(t, &hisave);
				throwStdException(t, "TypeException", "Attempting to slice a string with indices of type '{}' and '{}'", getString(t, -2), getString(t, -1));
			}

			if(!validIndices(loIndex, hiIndex, str.cpLength))
				throwStdException(t, "BoundsException", "Invalid slice indices [{} .. {}] (string length = {})", loIndex, hiIndex, str.cpLength);

			return t.stack[dest] = string.slice(t.vm, str, cast(uword)loIndex, cast(uword)hiIndex);

		default:
			if(tryMM!(3, true)(t, MM.Slice, &t.stack[dest], src, lo, hi))
				return;

			typeString(t, src);
			throwStdException(t, "TypeException", "Attempting to slice a value of type '{}'", getString(t, -1));
	}
}

void sliceaImpl(CrocThread* t, CrocValue* container, CrocValue* lo, CrocValue* hi, CrocValue* value)
{
	switch(container.type)
	{
		case CrocValue.Type.Array:
			auto arr = container.mArray;
			crocint loIndex = void;
			crocint hiIndex = void;

			if(!correctIndices(loIndex, hiIndex, lo, hi, arr.length))
			{
				auto hisave = *hi;
				typeString(t, lo);
				typeString(t, &hisave);
				throwStdException(t, "TypeException", "Attempting to slice-assign an array with indices of type '{}' and '{}'", getString(t, -2), getString(t, -1));
			}

			if(!validIndices(loIndex, hiIndex, arr.length))
				throwStdException(t, "BoundsException", "Invalid slice-assign indices [{} .. {}] (array length = {})", loIndex, hiIndex, arr.length);

			if(value.type == CrocValue.Type.Array)
			{
				if((hiIndex - loIndex) != value.mArray.length)
					throwStdException(t, "RangeException", "Array slice-assign lengths do not match (destination is {}, source is {})", hiIndex - loIndex, value.mArray.length);

				return array.sliceAssign(t.vm.alloc, arr, cast(uword)loIndex, cast(uword)hiIndex, value.mArray);
			}
			else
			{
				typeString(t, value);
				throwStdException(t, "TypeException", "Attempting to slice-assign a value of type '{}' into an array", getString(t, -1));
			}

		default:
			if(tryMM!(4, false)(t, MM.SliceAssign, container, lo, hi, value))
				return;

			typeString(t, container);
			throwStdException(t, "TypeException", "Attempting to slice-assign a value of type '{}'", getString(t, -1));
	}
}

void binOpImpl(CrocThread* t, MM operation, AbsStack dest, CrocValue* RS, CrocValue* RT)
{
	crocfloat f1 = void;
	crocfloat f2 = void;

	if(RS.type == CrocValue.Type.Int)
	{
		if(RT.type == CrocValue.Type.Int)
		{
			auto i1 = RS.mInt;
			auto i2 = RT.mInt;

			switch(operation)
			{
				case MM.Add: return t.stack[dest] = i1 + i2;
				case MM.Sub: return t.stack[dest] = i1 - i2;
				case MM.Mul: return t.stack[dest] = i1 * i2;

				case MM.Div:
					if(i2 == 0)
						throwStdException(t, "ValueException", "Integer divide by zero");

					return t.stack[dest] = i1 / i2;

				case MM.Mod:
					if(i2 == 0)
						throwStdException(t, "ValueException", "Integer modulo by zero");

					return t.stack[dest] = i1 % i2;

				default:
					assert(false);
			}
		}
		else if(RT.type == CrocValue.Type.Float)
		{
			f1 = RS.mInt;
			f2 = RT.mFloat;
			goto _float;
		}
	}
	else if(RS.type == CrocValue.Type.Float)
	{
		if(RT.type == CrocValue.Type.Int)
		{
			f1 = RS.mFloat;
			f2 = RT.mInt;
			goto _float;
		}
		else if(RT.type == CrocValue.Type.Float)
		{
			f1 = RS.mFloat;
			f2 = RT.mFloat;

			_float:
			switch(operation)
			{
				case MM.Add: return t.stack[dest] = f1 + f2;
				case MM.Sub: return t.stack[dest] = f1 - f2;
				case MM.Mul: return t.stack[dest] = f1 * f2;
				case MM.Div: return t.stack[dest] = f1 / f2;
				case MM.Mod: return t.stack[dest] = f1 % f2;

				default:
					assert(false);
			}
		}
	}

	return commonBinOpMM(t, operation, dest, RS, RT);
}

void commonBinOpMM(CrocThread* t, MM operation, AbsStack dest, CrocValue* RS, CrocValue* RT)
{
	bool swap = false;
	CrocClass* proto;

	auto method = getMM(t, RS, operation, proto);

	if(method is null)
	{
		method = getMM(t, RT, MMRev[operation], proto);

		if(method !is null)
			swap = true;
		else
		{
			if(!MMCommutative[operation])
			{
				auto RTsave = *RT;
				typeString(t, RS);
				typeString(t, &RTsave);
				throwStdException(t, "TypeException", "Cannot perform the arithmetic operation '{}' on a '{}' and a '{}'", MetaNames[operation], getString(t, -2), getString(t, -1));
			}

			method = getMM(t, RS, MMRev[operation], proto);

			if(method is null)
			{
				method = getMM(t, RT, operation, proto);

				if(method is null)
				{
					auto RTsave = *RT;
					typeString(t, RS);
					typeString(t, &RTsave);
					throwStdException(t, "TypeException", "Cannot perform the arithmetic operation '{}' on a '{}' and a '{}'", MetaNames[operation], getString(t, -2), getString(t, -1));
				}

				swap = true;
			}
		}
	}

// 	bool shouldLoad = void;
// 	savePtr(t, dest, shouldLoad);

	auto RSsave = *RS;
	auto RTsave = *RT;

	auto funcSlot = push(t, CrocValue(method));

	if(swap)
	{
		push(t, RTsave);
		push(t, RSsave);
	}
	else
	{
		push(t, RSsave);
		push(t, RTsave);
	}

	commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 2, proto));

// 	if(shouldLoad)
// 		loadPtr(t, dest);

	t.stack[dest] = t.stack[t.stackIndex - 1];
	pop(t);
}

void reflBinOpImpl(CrocThread* t, MM operation, AbsStack dest, CrocValue* src)
{
	crocfloat f1 = void;
	crocfloat f2 = void;

	if(t.stack[dest].type == CrocValue.Type.Int)
	{
		if(src.type == CrocValue.Type.Int)
		{
			auto i2 = src.mInt;

			switch(operation)
			{
				case MM.AddEq: return t.stack[dest].mInt += i2;
				case MM.SubEq: return t.stack[dest].mInt -= i2;
				case MM.MulEq: return t.stack[dest].mInt *= i2;

				case MM.DivEq:
					if(i2 == 0)
						throwStdException(t, "ValueException", "Integer divide by zero");

					return t.stack[dest].mInt /= i2;

				case MM.ModEq:
					if(i2 == 0)
						throwStdException(t, "ValueException", "Integer modulo by zero");

					return t.stack[dest].mInt %= i2;

				default: assert(false);
			}
		}
		else if(src.type == CrocValue.Type.Float)
		{
			f1 = t.stack[dest].mInt;
			f2 = src.mFloat;
			goto _float;
		}
	}
	else if(t.stack[dest].type == CrocValue.Type.Float)
	{
		if(src.type == CrocValue.Type.Int)
		{
			f1 = t.stack[dest].mFloat;
			f2 = src.mInt;
			goto _float;
		}
		else if(src.type == CrocValue.Type.Float)
		{
			f1 = t.stack[dest].mFloat;
			f2 = src.mFloat;

			_float:
			t.stack[dest].type = CrocValue.Type.Float;

			switch(operation)
			{
				case MM.AddEq: return t.stack[dest].mFloat = f1 + f2;
				case MM.SubEq: return t.stack[dest].mFloat = f1 - f2;
				case MM.MulEq: return t.stack[dest].mFloat = f1 * f2;
				case MM.DivEq: return t.stack[dest].mFloat = f1 / f2;
				case MM.ModEq: return t.stack[dest].mFloat = f1 % f2;

				default: assert(false);
			}
		}
	}

	if(tryMM!(2, false)(t, operation, &t.stack[dest], src))
		return;

	auto srcsave = *src;
	typeString(t, &t.stack[dest]);
	typeString(t, &srcsave);
	throwStdException(t, "TypeException", "Cannot perform the reflexive arithmetic operation '{}' on a '{}' and a '{}'", MetaNames[operation], getString(t, -2), getString(t, -1));
}

void negImpl(CrocThread* t, AbsStack dest, CrocValue* src)
{
	if(src.type == CrocValue.Type.Int)
		return t.stack[dest] = -src.mInt;
	else if(src.type == CrocValue.Type.Float)
		return t.stack[dest] = -src.mFloat;

	if(tryMM!(1, true)(t, MM.Neg, &t.stack[dest], src))
		return;

	typeString(t, src);
	throwStdException(t, "TypeException", "Cannot perform negation on a '{}'", getString(t, -1));
}

void binaryBinOpImpl(CrocThread* t, MM operation, AbsStack dest, CrocValue* RS, CrocValue* RT)
{
	if(RS.type == CrocValue.Type.Int && RT.type == CrocValue.Type.Int)
	{
		switch(operation)
		{
			case MM.And:  return t.stack[dest] = RS.mInt & RT.mInt;
			case MM.Or:   return t.stack[dest] = RS.mInt | RT.mInt;
			case MM.Xor:  return t.stack[dest] = RS.mInt ^ RT.mInt;
			case MM.Shl:  return t.stack[dest] = RS.mInt << RT.mInt;
			case MM.Shr:  return t.stack[dest] = RS.mInt >> RT.mInt;
			case MM.UShr: return t.stack[dest] = RS.mInt >>> RT.mInt;
			default: assert(false);
		}
	}

	return commonBinOpMM(t, operation, dest, RS, RT);
}

void reflBinaryBinOpImpl(CrocThread* t, MM operation, AbsStack dest, CrocValue* src)
{
	if(t.stack[dest].type == CrocValue.Type.Int && src.type == CrocValue.Type.Int)
	{
		switch(operation)
		{
			case MM.AndEq:  return t.stack[dest].mInt &= src.mInt;
			case MM.OrEq:   return t.stack[dest].mInt |= src.mInt;
			case MM.XorEq:  return t.stack[dest].mInt ^= src.mInt;
			case MM.ShlEq:  return t.stack[dest].mInt <<= src.mInt;
			case MM.ShrEq:  return t.stack[dest].mInt >>= src.mInt;
			case MM.UShrEq: return t.stack[dest].mInt >>>= src.mInt;
			default: assert(false);
		}
	}

	if(tryMM!(2, false)(t, operation, &t.stack[dest], src))
		return;

	auto srcsave = *src;
	typeString(t, &t.stack[dest]);
	typeString(t, &srcsave);
	throwStdException(t, "TypeException", "Cannot perform reflexive binary operation '{}' on a '{}' and a '{}'", MetaNames[operation], getString(t, -2), getString(t, -1));
}

void comImpl(CrocThread* t, AbsStack dest, CrocValue* src)
{
	if(src.type == CrocValue.Type.Int)
		return t.stack[dest] = ~src.mInt;

	if(tryMM!(1, true)(t, MM.Com, &t.stack[dest], src))
		return;

	typeString(t, src);
	throwStdException(t, "TypeException", "Cannot perform bitwise complement on a '{}'", getString(t, -1));
}

void incImpl(CrocThread* t, AbsStack dest)
{
	if(t.stack[dest].type == CrocValue.Type.Int)
		t.stack[dest].mInt++;
	else if(t.stack[dest].type == CrocValue.Type.Float)
		t.stack[dest].mFloat++;
	else
	{
		if(tryMM!(1, false)(t, MM.Inc, &t.stack[dest]))
			return;

		typeString(t, &t.stack[dest]);
		throwStdException(t, "TypeException", "Cannot increment a '{}'", getString(t, -1));
	}
}

void decImpl(CrocThread* t, AbsStack dest)
{
	if(t.stack[dest].type == CrocValue.Type.Int)
		t.stack[dest].mInt--;
	else if(t.stack[dest].type == CrocValue.Type.Float)
		t.stack[dest].mFloat--;
	else
	{
		if(tryMM!(1, false)(t, MM.Dec, &t.stack[dest]))
			return;

		typeString(t, &t.stack[dest]);
		throwStdException(t, "TypeException", "Cannot decrement a '{}'", getString(t, -1));
	}
}

void catImpl(CrocThread* t, AbsStack dest, AbsStack firstSlot, uword num)
{
	auto slot = firstSlot;
	auto endSlot = slot + num;
	auto endSlotm1 = endSlot - 1;
	auto stack = t.stack;

// 	bool shouldLoad = void;
// 	savePtr(t, dest, shouldLoad);

	while(slot < endSlotm1)
	{
		CrocFunction* method = null;
		CrocClass* proto = null;
		bool swap = false;

		switch(stack[slot].type)
		{
			case CrocValue.Type.String, CrocValue.Type.Char:
				uword len = 0;
				uword idx = slot;

				for(; idx < endSlot; idx++)
				{
					if(stack[idx].type == CrocValue.Type.String)
						len += stack[idx].mString.length;
					else if(stack[idx].type == CrocValue.Type.Char)
					{
						if(!Utf_isValid(stack[idx].mChar))
							throwStdException(t, "UnicodeException", "Attempting to concatenate an invalid character (\\U{:x8})", cast(uint)stack[idx].mChar);

						len += charLen(stack[idx].mChar);
					}
					else
						break;
				}

				if(idx > (slot + 1))
				{
					stringConcat(t, stack[slot], stack[slot + 1 .. idx], len);
					slot = idx - 1;
				}

				if(slot == endSlotm1)
					break; // to exit function

				if(stack[slot + 1].type == CrocValue.Type.Array)
					goto array;
				else if(stack[slot + 1].type == CrocValue.Type.Instance)
					goto cat_r;
				else
				{
					typeString(t, &stack[slot + 1]);
					throwStdException(t, "TypeException", "Can't concatenate 'string|char' and '{}'", getString(t, -1));
				}

			case CrocValue.Type.Array:
				array:
				uword idx = slot + 1;
				uword len = stack[slot].type == CrocValue.Type.Array ? stack[slot].mArray.length : 1;

				for(; idx < endSlot; idx++)
				{
					if(stack[idx].type == CrocValue.Type.Array)
						len += stack[idx].mArray.length;
					else if(stack[idx].type == CrocValue.Type.Instance)
					{
						method = getMM(t, &stack[idx], MM.Cat_r, proto);

						if(method is null)
							len++;
						else
							break;
					}
					else
						len++;
				}

				if(idx > (slot + 1))
				{
					arrayConcat(t, stack[slot .. idx], len);
					slot = idx - 1;
				}

				if(slot == endSlotm1)
					break; // to exit function

				assert(method !is null);
				goto cat_r;

			case CrocValue.Type.Instance:
				if(stack[slot + 1].type == CrocValue.Type.Array)
				{
					method = getMM(t, &stack[slot], MM.Cat, proto);

					if(method is null)
						goto array;
				}

				if(method is null)
				{
					method = getMM(t, &stack[slot], MM.Cat, proto);

					if(method is null)
						goto cat_r;
				}

				goto common_mm;

			default:
				// Basic
				if(stack[slot + 1].type == CrocValue.Type.Array)
					goto array;
				else
				{
					method = getMM(t, &stack[slot], MM.Cat, proto);

					if(method is null)
						goto cat_r;
					else
						goto common_mm;
				}

			cat_r:
				if(method is null)
				{
					method = getMM(t, &stack[slot + 1], MM.Cat_r, proto);

					if(method is null)
						goto error;
				}

				swap = true;
				// fall through

			common_mm:
				assert(method !is null);

				auto src1save = stack[slot];
				auto src2save = stack[slot + 1];

				auto funcSlot = push(t, CrocValue(method));

				if(swap)
				{
					push(t, src2save);
					push(t, src1save);
				}
				else
				{
					push(t, src1save);
					push(t, src2save);
				}

				commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 2, proto));

				// stack might have changed.
				stack = t.stack;

				slot++;
				stack[slot] = stack[t.stackIndex - 1];
				pop(t);
				continue;

			error:
				typeString(t, &t.stack[slot]);
				typeString(t, &stack[slot + 1]);
				throwStdException(t, "TypeException", "Can't concatenate '{}' and '{}'", getString(t, -2), getString(t, -1));
		}

		break;
	}

// 	if(shouldLoad)
// 		loadPtr(t, dest);

	t.stack[dest] = stack[slot];
}

void arrayConcat(CrocThread* t, CrocValue[] vals, uword len)
{
	if(vals.length == 2 && vals[0].type == CrocValue.Type.Array)
	{
		if(vals[1].type == CrocValue.Type.Array)
			return vals[1] = array.cat(t.vm.alloc, vals[0].mArray, vals[1].mArray);
		else
			return vals[1] = array.cat(t.vm.alloc, vals[0].mArray, &vals[1]);
	}

	auto ret = array.create(t.vm.alloc, len);

	uword i = 0;

	foreach(ref v; vals)
	{
		if(v.type == CrocValue.Type.Array)
		{
			auto a = v.mArray;
			array.sliceAssign(t.vm.alloc, ret, i, i + a.length, a);
			i += a.length;
		}
		else
		{
			array.idxa(t.vm.alloc, ret, i, v);
			i++;
		}
	}

	vals[$ - 1] = ret;
}

void stringConcat(CrocThread* t, CrocValue first, CrocValue[] vals, uword len)
{
	auto tmpBuffer = t.vm.alloc.allocArray!(char)(len);
	scope(exit) t.vm.alloc.freeArray(tmpBuffer);
	uword i = 0;

	void add(ref CrocValue v)
	{
		char[] s = void;

		if(v.type == CrocValue.Type.String)
			s = v.mString.toString();
		else
		{
			dchar[1] inbuf = void;
			inbuf[0] = v.mChar;
			char[4] outbuf = void;
			uint ate = 0;
			s = Utf_toString(inbuf, outbuf, &ate);
		}

		tmpBuffer[i .. i + s.length] = s[];
		i += s.length;
	}

	add(first);

	foreach(ref v; vals)
		add(v);

	vals[$ - 1] = createString(t, tmpBuffer);
}

void catEqImpl(CrocThread* t, AbsStack dest, AbsStack firstSlot, uword num)
{
	assert(num >= 1);

	auto slot = firstSlot;
	auto endSlot = slot + num;
	auto stack = t.stack;

	switch(t.stack[dest].type)
	{
		case CrocValue.Type.String, CrocValue.Type.Char:
			uword len = void;

			if(t.stack[dest].type == CrocValue.Type.Char)
			{
				if(!Utf_isValid(t.stack[dest].mChar))
					throwStdException(t, "UnicodeException", "Attempting to concatenate an invalid character (\\U{:x8})", t.stack[dest].mChar);

				len = charLen(t.stack[dest].mChar);
			}
			else
				len = t.stack[dest].mString.length;

			for(uword idx = slot; idx < endSlot; idx++)
			{
				if(stack[idx].type == CrocValue.Type.String)
					len += stack[idx].mString.length;
				else if(stack[idx].type == CrocValue.Type.Char)
				{
					if(!Utf_isValid(stack[idx].mChar))
						throwStdException(t, "UnicodeException", "Attempting to concatenate an invalid character (\\U{:x8})", cast(uint)stack[idx].mChar);

					len += charLen(stack[idx].mChar);
				}
				else
				{
					typeString(t, &stack[idx]);
					throwStdException(t, "TypeException", "Can't append a '{}' to a 'string/char'", getString(t, -1));
				}
			}

			auto first = t.stack[dest];
// 			bool shouldLoad = void;
// 			savePtr(t, dest, shouldLoad);

			stringConcat(t, first, stack[slot .. endSlot], len);

// 			if(shouldLoad)
// 				loadPtr(t, dest);

			t.stack[dest] = stack[endSlot - 1];
			return;

		case CrocValue.Type.Array:
			return arrayAppend(t, t.stack[dest].mArray, stack[slot .. endSlot]);

		default:
			CrocClass* proto;
			auto method = getMM(t, &t.stack[dest], MM.CatEq, proto);

			if(method is null)
			{
				typeString(t, &t.stack[dest]);
				throwStdException(t, "TypeException", "Can't append to a value of type '{}'", getString(t, -1));
			}

// 			bool shouldLoad = void;
// 			savePtr(t, dest, shouldLoad);

			checkStack(t, t.stackIndex);

// 			if(shouldLoad)
// 				loadPtr(t, dest);

			for(auto i = t.stackIndex; i > firstSlot; i--)
				t.stack[i] = t.stack[i - 1];

			t.stack[firstSlot] = t.stack[dest];

			t.nativeCallDepth++;
			scope(exit) t.nativeCallDepth--;

			if(callPrologue2(t, method, firstSlot, 0, firstSlot, num + 1, proto))
				execute(t);
			return;
	}
}

void arrayAppend(CrocThread* t, CrocArray* a, CrocValue[] vals)
{
	uword len = a.length;

	foreach(ref val; vals)
	{
		if(val.type == CrocValue.Type.Array)
			len += val.mArray.length;
		else
			len++;
	}

	uword i = a.length;
	array.resize(t.vm.alloc, a, len);

	foreach(ref v; vals)
	{
		if(v.type == CrocValue.Type.Array)
		{
			auto arr = v.mArray;
			array.sliceAssign(t.vm.alloc, a, i, i + arr.length, arr);
			i += arr.length;
		}
		else
		{
			array.idxa(t.vm.alloc, a, i, v);
			i++;
		}
	}
}

word pushTraceback(CrocThread* t)
{
	auto ret = newArray(t, 0);

	foreach_reverse(ref ar; t.actRecs[0 .. t.arIndex])
	{
		pushDebugLoc(t, &ar);
		cateq(t, ret, 1);

		if(ar.numTailcalls > 0)
		{
			pushFormat(t, "<{} tailcall{}>", ar.numTailcalls, ar.numTailcalls == 1 ? "" : "s");
			pushLocationObject(t, getString(t, -1), -1, CrocLocation.Script);
			cateq(t, ret, 1);
			pop(t);
		}
	}

	return ret;
}

void continueTraceback(CrocThread* t, CrocValue ex)
{
	push(t, ex);
	field(t, -1, "traceback");
	pushTraceback(t);
	cateq(t, -2, 1);
	pop(t, 2);
}

void throwImpl(CrocThread* t, CrocValue ex, bool rethrowing = false)
{
	if(!rethrowing)
	{
		if(!asImpl(t, &ex, &CrocValue(t.vm.throwable)))
		{
			typeString(t, &ex);
			throwStdException(t, "TypeException", "Attempting to throw a '{}'; must be an instance of a class derived from Throwable", getString(t, -1));
		}

		push(t, CrocValue(ex));
		field(t, -1, "location");
		field(t, -1, "col");

		if(getInt(t, -1) == CrocLocation.Unknown)
		{
			pop(t, 2);

			pushTraceback(t);

			if(len(t, -1) > 0)
				idxi(t, -1, 0);
			else
				pushDebugLoc(t);

			fielda(t, -3, "location");
			fielda(t, -2, "traceback");
		}
		else
			pop(t, 2);

		auto size = stackSize(t);

		try
			toStringImpl(t, ex, false);
		catch(CrocException e)
		{
			catchException(t);
			setStackSize(t, size);
			toStringImpl(t, ex, true);
		}

		// dup'ing since we're removing the only Croc reference and handing it off to D
		auto msg = getString(t, -1).dup;
		pop(t, 2);

		if(t.vm.dexception is null)
			t.vm.dexception = new CrocException(null);

		t.vm.dexception.msg = msg;
	}

	t.vm.exception = ex.mInstance;
	t.vm.isThrowing = true;
	throw t.vm.dexception;
}

bool asImpl(CrocThread* t, CrocValue* o, CrocValue* p)
{
	if(p.type != CrocValue.Type.Class)
	{
		typeString(t, p);
		throwStdException(t, "TypeException", "Attempting to use 'as' with a '{}' instead of a 'class' as the type", getString(t, -1));
	}

	return o.type == CrocValue.Type.Instance && instance.derivesFrom(o.mInstance, p.mClass);
}

CrocValue superOfImpl(CrocThread* t, CrocValue* v)
{
	if(v.type == CrocValue.Type.Class)
	{
		if(auto p = v.mClass.parent)
			return CrocValue(p);
		else
			return CrocValue.nullValue;
	}
	else if(v.type == CrocValue.Type.Instance)
		return CrocValue(v.mInstance.parent);
	else if(v.type == CrocValue.Type.Namespace)
	{
		if(auto p = v.mNamespace.parent)
			return CrocValue(p);
		else
			return CrocValue.nullValue;
	}
	else
	{
		typeString(t, v);
		throwStdException(t, "TypeException", "Can only get super of classes, instances, and namespaces, not values of type '{}'", getString(t, -1));
	}

	assert(false);
}

// ============================================================================
// Helper functions

CrocValue* getGlobalImpl(CrocThread* t, CrocString* name, CrocNamespace* env)
{
	if(auto glob = namespace.get(env, name))
		return glob;

	auto ns = env;
	for(; ns.parent !is null; ns = ns.parent){}

	if(ns !is env)
	{
		if(auto glob = namespace.get(ns, name))
			return glob;
	}

	throwStdException(t, "NameException", "Attempting to get a nonexistent global '{}'", name.toString());
	assert(false);
}

void setGlobalImpl(CrocThread* t, CrocString* name, CrocNamespace* env, CrocValue* val)
{
	if(namespace.setIfExists(t.vm.alloc, env, name, val))
		return;

	auto ns = env;
	for(; ns.parent !is null; ns = ns.parent){}

	if(ns !is env && namespace.setIfExists(t.vm.alloc, ns, name, val))
		return;

	throwStdException(t, "NameException", "Attempting to set a nonexistent global '{}'", name.toString());
	assert(false);
}

void newGlobalImpl(CrocThread* t, CrocString* name, CrocNamespace* env, CrocValue* val)
{
	if(namespace.contains(env, name))
		throwStdException(t, "NameException", "Attempting to create global '{}' that already exists", name.toString());

	namespace.set(t.vm.alloc, env, name, val);
}

void savePtr(CrocThread* t, ref CrocValue* ptr, out bool shouldLoad)
{
	if(ptr >= t.stack.ptr && ptr < t.stack.ptr + t.stack.length)
	{
		shouldLoad = true;
		ptr = cast(CrocValue*)(cast(uword)ptr - cast(uword)t.stack.ptr);
	}
}

void loadPtr(CrocThread* t, ref CrocValue* ptr)
{
	ptr = cast(CrocValue*)(cast(uword)ptr + cast(uword)t.stack.ptr);
}

CrocNamespace* getMetatable(CrocThread* t, CrocValue.Type type)
{
	// ORDER CROCVALUE TYPE
	assert(type >= CrocValue.Type.FirstUserType && type <= CrocValue.Type.LastUserType);
	return t.vm.metaTabs[type];
}

bool correctIndices(out crocint loIndex, out crocint hiIndex, CrocValue* lo, CrocValue* hi, uword len)
{
	if(lo.type == CrocValue.Type.Null)
		loIndex = 0;
	else if(lo.type == CrocValue.Type.Int)
	{
		loIndex = lo.mInt;

		if(loIndex < 0)
			loIndex += len;
	}
	else
		return false;

	if(hi.type == CrocValue.Type.Null)
		hiIndex = len;
	else if(hi.type == CrocValue.Type.Int)
	{
		hiIndex = hi.mInt;

		if(hiIndex < 0)
			hiIndex += len;
	}
	else
		return false;

	return true;
}

bool validIndices(crocint lo, crocint hi, uword len)
{
	return lo >= 0 && hi <= len && lo <= hi;
}

uword charLen(dchar c)
{
	dchar[1] inbuf = void;
	inbuf[0] = c;
	char[4] outbuf = void;
	uint ate = 0;
	return Utf_toString(inbuf, outbuf, &ate).length;
}

word pushNamespaceNamestring(CrocThread* t, CrocNamespace* ns)
{
	uword namespaceName(CrocNamespace* ns)
	{
		if(ns.name.cpLength == 0)
			return 0;

		uword n = 0;

		if(ns.parent)
		{
			auto ret = namespaceName(ns.parent);

			if(ret > 0)
			{
				pushChar(t, '.');
				n = ret + 1;
			}
		}

		push(t, CrocValue(ns.name));
		return n + 1;
	}

	auto x = namespaceName(ns);

	if(x == 0)
		return pushString(t, "");
	else
	{
		auto slot = t.stackIndex - x;
		catImpl(t, slot, slot, x);

		if(x > 1)
			pop(t, x - 1);

		return slot - t.stackBase;
	}
}

word typeString(CrocThread* t, CrocValue* v)
{
	switch(v.type)
	{
		case CrocValue.Type.Null,
			CrocValue.Type.Bool,
			CrocValue.Type.Int,
			CrocValue.Type.Float,
			CrocValue.Type.Char,
			CrocValue.Type.String,
			CrocValue.Type.Table,
			CrocValue.Type.Array,
			CrocValue.Type.Memblock,
			CrocValue.Type.Function,
			CrocValue.Type.Namespace,
			CrocValue.Type.Thread,
			CrocValue.Type.WeakRef,
			CrocValue.Type.FuncDef:

			return pushString(t, CrocValue.typeStrings[v.type]);

		case CrocValue.Type.Class:
			// LEAVE ME UP HERE PLZ, don't inline, thx. (WHY, ME?!? WHY CAN'T I INLINE THIS FFFFF) (maybe cause v could point to the stack and we don't know what order DMD does shit in)
			auto n = v.mClass.name.toString();
			return pushFormat(t, "{} {}", CrocValue.typeStrings[CrocValue.Type.Class], n);

		case CrocValue.Type.Instance:
			// don't inline me either.
			auto n = v.mInstance.parent.name.toString();
			return pushFormat(t, "{} of {}", CrocValue.typeStrings[CrocValue.Type.Instance], n);

		case CrocValue.Type.NativeObj:
			pushString(t, CrocValue.typeStrings[CrocValue.Type.NativeObj]);
			pushChar(t, ' ');

			if(auto o = v.mNativeObj.obj)
				pushString(t, o.classinfo.name);
			else
				pushString(t, "(??? null)");

			auto slot = t.stackIndex - 3;
			catImpl(t, slot, slot, 3);
			pop(t, 2);
			return slot - t.stackBase;

		default: assert(false);
	}
}

// ============================================================================
// Coroutines

void yieldImpl(CrocThread* t, AbsStack firstValue, word numValues, word numReturns)
{
	auto ar = pushAR(t);

	assert(t.arIndex > 1);
	*ar = t.actRecs[t.arIndex - 2];

	ar.func = null;
	ar.returnSlot = firstValue;
	ar.numReturns = numReturns;
	ar.firstResult = 0;
	ar.numResults = 0;

	if(numValues == -1)
		t.numYields = t.stackIndex - firstValue;
	else
	{
		t.stackIndex = firstValue + numValues;
		t.numYields = numValues;
	}

	t.state = CrocThread.State.Suspended;
}

uword resume(CrocThread* t, uword numParams)
{
	try
	{
		if(t.state == CrocThread.State.Initial)
		{
			push(t, CrocValue(t.coroFunc));
			insert(t, 1);
			auto result = callPrologue(t, cast(AbsStack)1, -1, numParams, null);
			assert(result == true, "resume callPrologue must return true");
			execute(t);
		}
		else
		{
			callEpilogue(t, true);
			execute(t, t.savedCallDepth);
		}
	}
	catch(CrocHaltException e)
	{
		assert(t.arIndex == 0);
		assert(t.upvalHead is null);
		assert(t.resultIndex == 0);
		assert(t.trIndex == 0);
		assert(t.nativeCallDepth == 0);
	}

	return t.numYields;
}

// ============================================================================
// Interpreter State

ActRecord* pushAR(CrocThread* t)
{
	if(t.arIndex >= t.actRecs.length)
		t.vm.alloc.resizeArray(t.actRecs, t.actRecs.length * 2);

	t.currentAR = &t.actRecs[t.arIndex];
	t.arIndex++;
	return t.currentAR;
}

void popAR(CrocThread* t)
{
	t.arIndex--;
	t.currentAR.func = null;
	t.currentAR.proto = null;

	if(t.arIndex > 0)
	{
		t.currentAR = &t.actRecs[t.arIndex - 1];
		t.stackBase = t.currentAR.base;
	}
	else
	{
		t.currentAR = null;
		t.stackBase = 0;
	}
}

TryRecord* pushTR(CrocThread* t)
{
	if(t.trIndex >= t.tryRecs.length)
		t.vm.alloc.resizeArray(t.tryRecs, t.tryRecs.length * 2);

	t.currentTR = &t.tryRecs[t.trIndex];
	t.trIndex++;
	return t.currentTR;
}

final void popTR(CrocThread* t)
{
	t.trIndex--;

	if(t.trIndex > 0)
		t.currentTR = &t.tryRecs[t.trIndex - 1];
	else
		t.currentTR = null;
}

void close(CrocThread* t, AbsStack index)
{
	auto base = &t.stack[index];

	for(auto uv = t.upvalHead; uv !is null && uv.value >= base; uv = t.upvalHead)
	{
		t.upvalHead = uv.nextuv;
		uv.closedValue = *uv.value;
		uv.value = &uv.closedValue;
	}
}

CrocUpval* findUpvalue(CrocThread* t, uword num)
{
	auto slot = &t.stack[t.currentAR.base + num];
	auto puv = &t.upvalHead;

	for(auto uv = *puv; uv !is null && uv.value >= slot; puv = &uv.nextuv, uv = *puv)
		if(uv.value is slot)
			return uv;

	auto ret = t.vm.alloc.allocate!(CrocUpval)();
	ret.value = slot;
	ret.nextuv = *puv;
	*puv = ret;
	return ret;
}

// ============================================================================
// Debugging

void callHook(CrocThread* t, CrocThread.Hook hook)
{
	if(!t.hooksEnabled || !t.hookFunc)
		return;

	auto savedTop = t.stackIndex;
	t.hooksEnabled = false;

	auto slot = push(t, CrocValue(t.hookFunc));
	push(t, CrocValue(t));

	switch(hook)
	{
		case CrocThread.Hook.Call:    pushString(t, "call"); break;
		case CrocThread.Hook.Ret:     pushString(t, "ret"); break;
		case CrocThread.Hook.TailRet: pushString(t, "tailret"); break;
		case CrocThread.Hook.Delay:   pushString(t, "delay"); break;
		case CrocThread.Hook.Line:    pushString(t, "line"); break;
		default: assert(false);
	}

	try
		commonCall(t, t.stackBase + slot, 0, callPrologue(t, t.stackBase + slot, 0, 1, null));
	finally
	{
		t.hooksEnabled = true;
		t.stackIndex = savedTop;
	}
}

void callReturnHooks(CrocThread* t)
{
	if(!t.hooksEnabled)
		return;

	callHook(t, CrocThread.Hook.Ret);

	if(!t.currentAR.func.isNative)
	{
		while(t.currentAR.numTailcalls > 0)
		{
			t.currentAR.numTailcalls--;
			callHook(t, CrocThread.Hook.TailRet);
		}
	}
}

// ============================================================================
// Main interpreter loop

void execute(CrocThread* t, uword depth = 1)
{
	CrocException currentException = null;
	CrocValue* RS;
	CrocValue* RT;

	_exceptionRetry:
	t.state = CrocThread.State.Running;
	t.vm.curThread = t;

	_reentry:
	auto stackBase = t.stackBase;
	auto constTable = t.currentAR.func.scriptFunc.constants;
	auto env = t.currentAR.func.environment;
	auto upvals = t.currentAR.func.scriptUpvals();
	auto pc = &t.currentAR.pc;

	try
	{
		const char[] GetRS = "if((*pc).uimm & Instruction.constBit) RS = &constTable[(*pc).uimm & ~Instruction.constBit]; else RS = &t.stack[stackBase + (*pc).uimm]; (*pc)++;";
		const char[] GetRT = "if((*pc).uimm & Instruction.constBit) RT = &constTable[(*pc).uimm & ~Instruction.constBit]; else RT = &t.stack[stackBase + (*pc).uimm]; (*pc)++;";
		const char[] GetRTAndrt = "auto rt = (*pc).uimm; if(rt & Instruction.constBit) RT = &constTable[rt & ~Instruction.constBit]; else RT = &t.stack[stackBase + rt]; (*pc)++;";
		const char[] GetUImm = "((*pc)++).uimm";
		const char[] GetImm = "((*pc)++).imm";

		Instruction* oldPC = null;

		_interpreterLoop: while(true)
		{
			if(t.shouldHalt)
				throw new CrocHaltException;

			pc = &t.currentAR.pc;
			Instruction* i = (*pc)++;

			if(t.hooksEnabled && t.hooks)
			{
				if(t.hooks & CrocThread.Hook.Delay)
				{
					assert(t.hookCounter > 0);
					t.hookCounter--;

					if(t.hookCounter == 0)
					{
						t.hookCounter = t.hookDelay;
						callHook(t, CrocThread.Hook.Delay);
					}
				}

				if(t.hooks & CrocThread.Hook.Line)
				{
					auto curPC = t.currentAR.pc - 1;

					// when oldPC is null, it means we've either just started executing this func,
					// or we've come back from a yield, or we've just caught an exception, or something
					// like that.
					// When curPC < oldPC, we've jumped back, like to the beginning of a loop.

					if(curPC is t.currentAR.func.scriptFunc.code.ptr || curPC < oldPC || pcToLine(t.currentAR, curPC) != pcToLine(t.currentAR, curPC - 1))
						callHook(t, CrocThread.Hook.Line);
				}
			}

			oldPC = *pc;

			auto opcode = mixin(Instruction.GetOpcode("i"));
			auto rd = mixin(Instruction.GetRD("i"));

			switch(opcode)
			{
				// ====================================================================
				// These opcodes match up with the MM enum to avoid a second lookup.

				// Binary Arithmetic
				case Op.Add:
				case Op.Sub:
				case Op.Mul:
				case Op.Div:
				case Op.Mod: mixin(GetRS); mixin(GetRT); binOpImpl(t, cast(MM)opcode, stackBase + rd, RS, RT); break;

				// Reflexive Arithmetic
				case Op.AddEq:
				case Op.SubEq:
				case Op.MulEq:
				case Op.DivEq:
				case Op.ModEq: mixin(GetRS); reflBinOpImpl(t, cast(MM)opcode, stackBase + rd, RS); break;

				// Binary Bitwise
				case Op.And:
				case Op.Or:
				case Op.Xor:
				case Op.Shl:
				case Op.Shr:
				case Op.UShr: mixin(GetRS); mixin(GetRT); binaryBinOpImpl(t, cast(MM)opcode, stackBase + rd, RS, RT); break;

				// Reflexive Bitwise
				case Op.AndEq:
				case Op.OrEq:
				case Op.XorEq:
				case Op.ShlEq:
				case Op.ShrEq:
				case Op.UShrEq: mixin(GetRS); reflBinaryBinOpImpl(t, cast(MM)opcode, stackBase + rd, RS); break;

				// ====================================================================
				// From here on, there is no correlation between Op and MM.

				// Unary ops
				case Op.Neg: mixin(GetRS); negImpl(t, stackBase + rd, RS); break;
				case Op.Com: mixin(GetRS); comImpl(t, stackBase + rd, RS); break;

				// Crements
				case Op.Inc: incImpl(t, stackBase + rd); break;
				case Op.Dec: decImpl(t, stackBase + rd); break;

				// Data Transfer
				case Op.Move: mixin(GetRS); t.stack[stackBase + rd] = *RS; break;

				case Op.NewGlobal: newGlobalImpl(t, constTable[mixin(GetUImm)].mString, env, &t.stack[stackBase + rd]); break;
				case Op.GetGlobal: t.stack[stackBase + rd] = *getGlobalImpl(t, constTable[mixin(GetUImm)].mString, env); break;
				case Op.SetGlobal: setGlobalImpl(t, constTable[mixin(GetUImm)].mString, env, &t.stack[stackBase + rd]); break;

				case Op.GetUpval:  t.stack[stackBase + rd] = *upvals[mixin(GetUImm)].value; break;
				case Op.SetUpval:  auto uv = upvals[mixin(GetUImm)]; mixin(writeBarrier!("t.vm.alloc", "uv")); *uv.value = t.stack[stackBase + rd]; break;

				// Logical and Control Flow
				case Op.Not:  mixin(GetRS); t.stack[stackBase + rd] = RS.isFalse(); break;
				case Op.Cmp3: mixin(GetRS); mixin(GetRT); t.stack[stackBase + rd] = compareImpl(t, RS, RT); break;

				case Op.Cmp:
					mixin(GetRS);
					mixin(GetRT);
					auto jump = mixin(GetImm);

					auto cmpValue = compareImpl(t, RS, RT);

					switch(cast(Comparison)rd)
					{
						case Comparison.LT: if(cmpValue < 0) (*pc) += jump; break;
						case Comparison.LE: if(cmpValue <= 0) (*pc) += jump; break;
						case Comparison.GT: if(cmpValue > 0) (*pc) += jump; break;
						case Comparison.GE: if(cmpValue >= 0) (*pc) += jump; break;
						default: assert(false, "invalid cmp comparison type");
					}
					break;

				case Op.SwitchCmp:
					mixin(GetRS);
					mixin(GetRT);
					auto jump = mixin(GetImm);

					if(switchCmpImpl(t, RS, RT))
						(*pc) += jump;
					break;

				case Op.Equals:
					mixin(GetRS);
					mixin(GetRT);
					auto jump = mixin(GetImm);

					if(equalsImpl(t, RS, RT) == cast(bool)rd)
						(*pc) += jump;
					break;

				case Op.Is:
					mixin(GetRS);
					mixin(GetRT);
					auto jump = mixin(GetImm);

					if(RS.opEquals(RT) == rd)
						(*pc) += jump;

					break;

				case Op.In:
					mixin(GetRS);
					mixin(GetRT);
					auto jump = mixin(GetImm);

					if(inImpl(t, RS, RT) == cast(bool)rd)
						(*pc) += jump;
					break;

				case Op.IsTrue:
					mixin(GetRS);
					auto jump = mixin(GetImm);

					if(RS.isFalse() != cast(bool)rd)
						(*pc) += jump;

					break;

				case Op.Jmp:
					// If we ever change the format of this opcode, check that it's the same length as Switch (codegen can turn Switch into Jmp)!
					auto jump = mixin(GetImm);

					if(rd != 0)
						(*pc) += jump;
					break;

				case Op.Switch:
					// If we ever change the format of this opcode, check that it's the same length as Jmp (codegen can turn Switch into Jmp)!
					auto st = &t.currentAR.func.scriptFunc.switchTables[rd];
					mixin(GetRS);

					if(auto ptr = st.offsets.lookup(*RS))
						(*pc) += *ptr;
					else
					{
						if(st.defaultOffset == -1)
							throwStdException(t, "SwitchError", "Switch without default");

						(*pc) += st.defaultOffset;
					}
					break;

				case Op.Close: close(t, stackBase + rd); break;

				case Op.For:
					auto jump = mixin(GetImm);
					auto idx = &t.stack[stackBase + rd];
					auto hi = idx + 1;
					auto step = hi + 1;

					if(idx.type != CrocValue.Type.Int || hi.type != CrocValue.Type.Int || step.type != CrocValue.Type.Int)
						throwStdException(t, "TypeException", "Numeric for loop low, high, and step values must be integers");

					auto intIdx = idx.mInt;
					auto intHi = hi.mInt;
					auto intStep = step.mInt;

					if(intStep == 0)
						throwStdException(t, "ValueException", "Numeric for loop step value may not be 0");

					if(intIdx > intHi && intStep > 0 || intIdx < intHi && intStep < 0)
						intStep = -intStep;

					if(intStep < 0)
						*idx = intIdx + intStep;

					*step = intStep;
					(*pc) += jump;
					break;

				case Op.ForLoop:
					auto jump = mixin(GetImm);
					auto idx = t.stack[stackBase + rd].mInt;
					auto hi = t.stack[stackBase + rd + 1].mInt;
					auto step = t.stack[stackBase + rd + 2].mInt;

					if(step > 0)
					{
						if(idx < hi)
						{
							t.stack[stackBase + rd + 3] = idx;
							t.stack[stackBase + rd] = idx + step;
							(*pc) += jump;
						}
					}
					else
					{
						if(idx >= hi)
						{
							t.stack[stackBase + rd + 3] = idx;
							t.stack[stackBase + rd] = idx + step;
							(*pc) += jump;
						}
					}
					break;

				case Op.Foreach:
					auto jump = mixin(GetImm);
					auto src = &t.stack[stackBase + rd];

					if(src.type != CrocValue.Type.Function && src.type != CrocValue.Type.Thread)
					{
						CrocClass* proto;
						auto method = getMM(t, src, MM.Apply, proto);

						if(method is null)
						{
							typeString(t, src);
							throwStdException(t, "TypeException", "No implementation of {} for type '{}'", MetaNames[MM.Apply], getString(t, -1));
						}

						t.stack[stackBase + rd + 2] = t.stack[stackBase + rd + 1];
						t.stack[stackBase + rd + 1] = *src;
						t.stack[stackBase + rd] = method;

						t.stackIndex = stackBase + rd + 3;
						commonCall(t, stackBase + rd, 3, callPrologue(t, stackBase + rd, 3, 2, proto));
						t.stackIndex = t.currentAR.savedTop;

						src = &t.stack[stackBase + rd];

						if(src.type != CrocValue.Type.Function && src.type != CrocValue.Type.Thread)
						{
							typeString(t, src);
							throwStdException(t, "TypeException", "Invalid iterable type '{}' returned from opApply", getString(t, -1));
						}
					}

					if(src.type == CrocValue.Type.Thread && src.mThread.state != CrocThread.State.Initial)
						throwStdException(t, "StateException", "Attempting to iterate over a thread that is not in the 'initial' state");

					(*pc) += jump;
					break;

				case Op.ForeachLoop:
					auto numIndices = mixin(GetUImm);
					auto jump = mixin(GetImm);

					auto funcReg = rd + 3;

					t.stack[stackBase + funcReg + 2] = t.stack[stackBase + rd + 2];
					t.stack[stackBase + funcReg + 1] = t.stack[stackBase + rd + 1];
					t.stack[stackBase + funcReg] = t.stack[stackBase + rd];

					t.stackIndex = stackBase + funcReg + 3;
					commonCall(t, stackBase + funcReg, numIndices, callPrologue(t, stackBase + funcReg, numIndices, 2, null));
					t.stackIndex = t.currentAR.savedTop;

					auto src = &t.stack[stackBase + rd];

					if(src.type == CrocValue.Type.Function)
					{
						if(t.stack[stackBase + funcReg].type != CrocValue.Type.Null)
						{
							t.stack[stackBase + rd + 2] = t.stack[stackBase + funcReg];
							(*pc) += jump;
						}
					}
					else
					{
						if(src.mThread.state != CrocThread.State.Dead)
							(*pc) += jump;
					}
					break;

				// Exception Handling
				case Op.PushCatch, Op.PushFinally:
					auto offs = mixin(GetImm);
					auto tr = pushTR(t);
					tr.isCatch = opcode == Op.PushCatch;
					tr.slot = cast(RelStack)rd;
					tr.pc = (*pc) + offs;
					tr.actRecord = t.arIndex;
					break;

				case Op.PopCatch: popTR(t); break;

				case Op.PopFinally:
					currentException = null;
					popTR(t);
					break;

				case Op.EndFinal:
					if(currentException !is null)
						throw currentException;

					if(t.currentAR.unwindReturn !is null)
						goto _commonEHUnwind;

					break;

				case Op.Throw: mixin(GetRS); throwImpl(t, *RS, cast(bool)rd); break;

				// Function Calling
			{
				bool isScript = void;
				word numResults = void;
				uword numParams = void;

				const char[] AdjustParams =
				"if(numParams == 0)
					numParams = t.stackIndex - (stackBase + rd + 1);
				else
				{
					numParams--;
					t.stackIndex = stackBase + rd + 1 + numParams;
				}";

				case Op.Method, Op.TailMethod:
					// These two opcodes have one more value
					mixin(GetRS);

				case Op.SuperMethod, Op.TailSuperMethod:
					mixin(GetRT);
					numParams = mixin(GetUImm);
					numResults = mixin(GetUImm) - 1;

					if(opcode == Op.TailMethod || opcode == Op.TailSuperMethod)
						numResults = -1; // the second uimm is a dummy for these opcodes

					if(RT.type != CrocValue.Type.String)
					{
						typeString(t, RT);
						throwStdException(t, "TypeException", "Attempting to get a method with a non-string name (type '{}' instead)", getString(t, -1));
					}

					CrocValue* self = void;
					CrocValue lookup = void;

					if(opcode == Op.Method || opcode == Op.TailMethod)
					{
						self = RS;
						lookup = *RS;
					}
					else
					{
						if(t.currentAR.proto is null || t.currentAR.proto.parent is null)
							throwStdException(t, "CallException", "Attempting to perform a supercall in a function where there is no super class");

						self = &t.stack[stackBase];
						lookup = CrocValue(t.currentAR.proto.parent);

						if(self.type != CrocValue.Type.Instance && self.type != CrocValue.Type.Class)
						{
							typeString(t, self);
							throwStdException(t, "TypeException", "Attempting to perform a supercall in a function where 'this' is a '{}', not an 'instance' or 'class'", getString(t, -1));
						}
					}

					mixin(AdjustParams);
					isScript = commonMethodCall(t, stackBase + rd, self, &lookup, RT.mString, numResults, numParams);

					if(opcode == Op.Method || opcode == Op.SuperMethod)
						goto _commonCall;
					else
						goto _commonTailcall;

				case Op.Call, Op.TailCall:
					numParams = mixin(GetUImm);
					numResults = mixin(GetUImm) - 1;

					if(opcode == Op.TailCall)
						numResults = -1; // second uimm is a dummy

					mixin(AdjustParams);

					auto self = &t.stack[stackBase + rd + 1];
					CrocClass* proto = void;

					if(self.type == CrocValue.Type.Instance)
						proto = self.mInstance.parent;
					else if(self.type == CrocValue.Type.Class)
						proto = self.mClass;
					else
						proto = null;

					isScript = callPrologue(t, stackBase + rd, numResults, numParams, proto);

					if(opcode == Op.TailCall)
						goto _commonTailcall;

					// fall through
				_commonCall:
					maybeGC(t);

					if(isScript)
					{
						depth++;
						goto _reentry;
					}
					else
					{
						if(numResults >= 0)
							t.stackIndex = t.currentAR.savedTop;
					}
					break;

				_commonTailcall:
					maybeGC(t);

					if(isScript)
					{
						auto prevAR = t.currentAR - 1;
						close(t, prevAR.base);

						auto diff = cast(ptrdiff_t)(t.currentAR.returnSlot - prevAR.returnSlot);

						auto tc = prevAR.numTailcalls + 1;
						t.currentAR.numReturns = prevAR.numReturns;
						*prevAR = *t.currentAR;
						prevAR.numTailcalls = tc;
						prevAR.base -= diff;
						prevAR.savedTop -= diff;
						prevAR.vargBase -= diff;
						prevAR.returnSlot -= diff;

						popAR(t);

						//memmove(&t.stack[prevAR.returnSlot], &t.stack[prevAR.returnSlot + diff], (prevAR.savedTop - prevAR.returnSlot) * CrocValue.sizeof);

						for(auto idx = prevAR.returnSlot; idx < prevAR.savedTop; idx++)
							t.stack[idx] = t.stack[idx + diff];

						goto _reentry;
					}

					// Do nothing for native calls. The following return instruction will catch it.
					break;
			}

				case Op.SaveRets:
					auto numResults = mixin(GetUImm);
					auto firstResult = stackBase + rd;

					if(numResults == 0)
					{
						saveResults(t, t, firstResult, t.stackIndex - firstResult);
						t.stackIndex = t.currentAR.savedTop;
					}
					else
						saveResults(t, t, firstResult, numResults - 1);
					break;

				case Op.Ret:
					unwindEH(t);
					close(t, stackBase);
					callEpilogue(t, true);

					depth--;

					if(depth == 0)
						return;

					goto _reentry;

				case Op.Unwind:
					t.currentAR.unwindReturn = (*pc);
					t.currentAR.unwindCounter = rd;

					// fall through
				_commonEHUnwind:
					while(t.currentAR.unwindCounter > 0)
					{
						assert(t.trIndex > 0);
						assert(t.currentTR.actRecord is t.arIndex);

						auto tr = *t.currentTR;
						popTR(t);
						close(t, t.stackBase + tr.slot);
						t.currentAR.unwindCounter--;

						if(!tr.isCatch)
						{
							// finally in the middle of an unwind
							(*pc) = tr.pc;
							continue _interpreterLoop;
						}
					}

					(*pc) = t.currentAR.unwindReturn;
					t.currentAR.unwindReturn = null;
					break;

				case Op.Vararg:
					uword numNeeded = mixin(GetUImm);
					auto numVarargs = stackBase - t.currentAR.vargBase;
					auto dest = stackBase + rd;

					if(numNeeded == 0)
					{
						numNeeded = numVarargs;
						t.stackIndex = dest + numVarargs;
						checkStack(t, t.stackIndex);
					}
					else
						numNeeded--;

					auto src = t.currentAR.vargBase;

					if(numNeeded <= numVarargs)
						memmove(&t.stack[dest], &t.stack[src], numNeeded * CrocValue.sizeof);
					else
					{
						memmove(&t.stack[dest], &t.stack[src], numVarargs * CrocValue.sizeof);
						t.stack[dest + numVarargs .. dest + numNeeded] = CrocValue.nullValue;
					}

					break;

				case Op.VargLen: t.stack[stackBase + rd] = cast(crocint)(stackBase - t.currentAR.vargBase); break;

				case Op.VargIndex:
					mixin(GetRS);

					auto numVarargs = stackBase - t.currentAR.vargBase;

					if(RS.type != CrocValue.Type.Int)
					{
						typeString(t, RS);
						throwStdException(t, "TypeException", "Attempting to index 'vararg' with a '{}'", getString(t, -1));
					}

					auto index = RS.mInt;

					if(index < 0)
						index += numVarargs;

					if(index < 0 || index >= numVarargs)
						throwStdException(t, "BoundsException", "Invalid 'vararg' index: {} (only have {})", index, numVarargs);

					t.stack[stackBase + rd] = t.stack[t.currentAR.vargBase + cast(uword)index];
					break;

				case Op.VargIndexAssign:
					mixin(GetRS);
					mixin(GetRT);

					auto numVarargs = stackBase - t.currentAR.vargBase;

					if(RS.type != CrocValue.Type.Int)
					{
						typeString(t, RS);
						throwStdException(t, "TypeException", "Attempting to index 'vararg' with a '{}'", getString(t, -1));
					}

					auto index = RS.mInt;

					if(index < 0)
						index += numVarargs;

					if(index < 0 || index >= numVarargs)
						throwStdException(t, "BoundsException", "Invalid 'vararg' index: {} (only have {})", index, numVarargs);

					t.stack[t.currentAR.vargBase + cast(uword)index] = *RT;
					break;

				case Op.VargSlice:
					uint numNeeded = mixin(GetUImm);
					auto numVarargs = stackBase - t.currentAR.vargBase;

					crocint lo = void;
					crocint hi = void;

					auto loSrc = &t.stack[stackBase + rd];
					auto hiSrc = &t.stack[stackBase + rd + 1];

					if(!correctIndices(lo, hi, loSrc, hiSrc, numVarargs))
					{
						typeString(t, &t.stack[stackBase + rd]);
						typeString(t, &t.stack[stackBase + rd + 1]);
						throwStdException(t, "TypeException", "Attempting to slice 'vararg' with '{}' and '{}'", getString(t, -2), getString(t, -1));
					}

					if(lo > hi || lo < 0 || lo > numVarargs || hi < 0 || hi > numVarargs)
						throwStdException(t, "BoundsException", "Invalid vararg slice indices [{} .. {}]", lo, hi);

					auto sliceSize = cast(uword)(hi - lo);
					auto src = t.currentAR.vargBase + cast(uword)lo;
					auto dest = stackBase + cast(uword)rd;

					if(numNeeded == 0)
					{
						numNeeded = sliceSize;
						t.stackIndex = dest + sliceSize;
						checkStack(t, t.stackIndex);
					}
					else
						numNeeded--;

					if(numNeeded <= sliceSize)
						memmove(&t.stack[dest], &t.stack[src], numNeeded * CrocValue.sizeof);
					else
					{
						memmove(&t.stack[dest], &t.stack[src], sliceSize * CrocValue.sizeof);
						t.stack[dest + sliceSize .. dest + numNeeded] = CrocValue.nullValue;
					}
					break;

				case Op.Yield:
					auto numParams = cast(word)mixin(GetUImm) - 1;
					auto numResults = cast(word)mixin(GetUImm) - 1;

					if(t is t.vm.mainThread)
						throwStdException(t, "RuntimeException", "Attempting to yield out of the main thread");

					if(t.nativeCallDepth > 0)
						throwStdException(t, "RuntimeException", "Attempting to yield across native / metamethod call boundary");

					t.savedCallDepth = depth;
					yieldImpl(t, stackBase + rd, numParams, numResults);
					return;

				case Op.CheckParams:
					auto val = &t.stack[stackBase];

					foreach(idx, mask; t.currentAR.func.scriptFunc.paramMasks)
					{
						if(!(mask & (1 << val.type)))
						{
							typeString(t, val);

							if(idx == 0)
								throwStdException(t, "TypeException", "'this' parameter: type '{}' is not allowed", getString(t, -1));
							else
								throwStdException(t, "TypeException", "Parameter {}: type '{}' is not allowed", idx, getString(t, -1));
						}

						val++;
					}
					break;

				case Op.CheckObjParam:
					auto RD = &t.stack[stackBase + rd];
					mixin(GetRS);
					auto jump = mixin(GetImm);

					if(RD.type != CrocValue.Type.Instance)
						(*pc) += jump;
					else
					{
						if(RS.type != CrocValue.Type.Class)
						{
							typeString(t, RS);

							if(rd == 0)
								throwStdException(t, "TypeException", "'this' parameter: instance type constraint type must be 'class', not '{}'", getString(t, -1));
							else
								throwStdException(t, "TypeException", "Parameter {}: instance type constraint type must be 'class', not '{}'", rd, getString(t, -1));
						}

						if(instance.derivesFrom(RD.mInstance, RS.mClass))
							(*pc) += jump;
					}
					break;

				case Op.ObjParamFail:
					typeString(t, &t.stack[stackBase + rd]);

					if(rd == 0)
						throwStdException(t, "TypeException", "'this' parameter: type '{}' is not allowed", getString(t, -1));
					else
						throwStdException(t, "TypeException", "Parameter {}: type '{}' is not allowed", rd, getString(t, -1));

					break;

				case Op.CustomParamFail:
					typeString(t, &t.stack[stackBase + rd]);
					mixin(GetRS);

					if(rd == 0)
						throwStdException(t, "TypeException", "'this' parameter: type '{}' does not satisfy constraint '{}'", getString(t, -1), RS.mString.toString());
					else
						throwStdException(t, "TypeException", "Parameter {}: type '{}' does not satisfy constraint '{}'", rd, getString(t, -1), RS.mString.toString());
					break;

				case Op.AssertFail:
					auto msg = t.stack[stackBase + rd];

					if(msg.type != CrocValue.Type.String)
					{
						typeString(t, &msg);
						throwStdException(t, "AssertError", "Assertion failed, but the message is a '{}', not a 'string'", getString(t, -1));
					}

					throwStdException(t, "AssertError", "{}", msg.mString.toString());
					assert(false);

				// Array and List Operations
				case Op.Length:       mixin(GetRS); lenImpl(t, stackBase + rd, RS);  break;
				case Op.LengthAssign: mixin(GetRS); lenaImpl(t, stackBase + rd, RS); break;
				case Op.Append:       mixin(GetRS); array.append(t.vm.alloc, t.stack[stackBase + rd].mArray, RS); break;

				case Op.SetArray:
					auto numVals = mixin(GetUImm);
					auto block = mixin(GetUImm);
					auto sliceBegin = stackBase + rd + 1;
					auto a = t.stack[stackBase + rd].mArray;

					if(numVals == 0)
					{
						array.setBlock(t.vm.alloc, a, block, t.stack[sliceBegin .. t.stackIndex]);
						t.stackIndex = t.currentAR.savedTop;
					}
					else
						array.setBlock(t.vm.alloc, a, block, t.stack[sliceBegin .. sliceBegin + numVals - 1]);

					break;

				case Op.Cat:
					auto rs = mixin(GetUImm);
					auto numVals = mixin(GetUImm);
					catImpl(t, stackBase + rd, stackBase + rs, numVals);
					maybeGC(t);
					break;

				case Op.CatEq:
					auto rs = mixin(GetUImm);
					auto numVals = mixin(GetUImm);
					catEqImpl(t, stackBase + rd, stackBase + rs, numVals);
					maybeGC(t);
					break;

				case Op.Index:       mixin(GetRS); mixin(GetRT); idxImpl(t, stackBase + rd, RS, RT);  break;
				case Op.IndexAssign: mixin(GetRS); mixin(GetRT); idxaImpl(t, stackBase + rd, RS, RT); break;

				case Op.Field:
					mixin(GetRS);
					mixin(GetRT);

					if(RT.type != CrocValue.Type.String)
					{
						typeString(t, RT);
						throwStdException(t, "TypeException", "Field name must be a string, not a '{}'", getString(t, -1));
					}

					fieldImpl(t, stackBase + rd, RS, RT.mString, false);
					break;

				case Op.FieldAssign:
					mixin(GetRS);
					mixin(GetRT);

					if(RS.type != CrocValue.Type.String)
					{
						typeString(t, RS);
						throwStdException(t, "TypeException", "Field name must be a string, not a '{}'", getString(t, -1));
					}

					fieldaImpl(t, stackBase + rd, RS.mString, RT, false);
					break;

				case Op.Slice:
					auto rs = mixin(GetUImm);
					auto base = &t.stack[stackBase + rs];
					sliceImpl(t, stackBase + rd, base, base + 1, base + 2);
					break;

				case Op.SliceAssign:
					mixin(GetRS);
					auto base = &t.stack[stackBase + rd];
					sliceaImpl(t, base, base + 1, base + 2, RS);
					break;

				// Value Creation
				case Op.NewArray:
					auto size = cast(uword)constTable[mixin(GetUImm)].mInt;
					t.stack[stackBase + rd] = array.create(t.vm.alloc, size);
					maybeGC(t);
					break;

				case Op.NewTable:
					t.stack[stackBase + rd] = table.create(t.vm.alloc);
					maybeGC(t);
					break;

				case Op.Closure, Op.ClosureWithEnv:
					auto closureIdx = mixin(GetUImm);
					auto newDef = t.currentAR.func.scriptFunc.innerFuncs[closureIdx];
					auto funcEnv = opcode == Op.Closure ? env : t.stack[stackBase + rd].mNamespace;
					auto n = func.create(t.vm.alloc, funcEnv, newDef);

					if(n is null)
					{
						CrocValue def = newDef;
						toStringImpl(t, def, false);
						throwStdException(t, "RuntimeException", "Attempting to instantiate {} with a different namespace than was associated with it", getString(t, -1));
					}

					auto uvTable = newDef.upvals;

					foreach(id, ref uv; n.scriptUpvals())
					{
						if(uvTable[id].isUpvalue)
							uv = upvals[uvTable[id].index];
						else
							uv = findUpvalue(t, uvTable[id].index);
					}

					t.stack[stackBase + rd] = n;
					maybeGC(t);
					break;

				case Op.Class:
					mixin(GetRS);
					mixin(GetRTAndrt);

					if(rt & Instruction.constBit && RT.type == CrocValue.Type.Null)
						t.stack[stackBase + rd] = classobj.create(t.vm.alloc, RS.mString, t.vm.object);
					else
					{
						if(RT.type != CrocValue.Type.Class)
						{
							typeString(t, RT);
							throwStdException(t, "TypeException", "Attempting to derive a class from a value of type '{}'", getString(t, -1));
						}
						else
							t.stack[stackBase + rd] = classobj.create(t.vm.alloc, RS.mString, RT.mClass);
					}

					maybeGC(t);
					break;

				case Op.Namespace:
					auto name = constTable[mixin(GetUImm)].mString;
					mixin(GetRT);

					if(RT.type == CrocValue.Type.Null)
						t.stack[stackBase + rd] = namespace.create(t.vm.alloc, name);
					else if(RT.type != CrocValue.Type.Namespace)
					{
						typeString(t, RT);
						push(t, CrocValue(name));
						throwStdException(t, "TypeException", "Attempted to use a '{}' as a parent namespace for namespace '{}'", getString(t, -2), getString(t, -1));
					}
					else
						t.stack[stackBase + rd] = namespace.create(t.vm.alloc, name, RT.mNamespace);

					maybeGC(t);
					break;

				case Op.NamespaceNP:
					auto name = constTable[mixin(GetUImm)].mString;
					t.stack[stackBase + rd] = namespace.create(t.vm.alloc, name, env);
					maybeGC(t);
					break;

				// Class stuff
				case Op.As:
					mixin(GetRS);
					mixin(GetRT);

					if(asImpl(t, RS, RT))
						t.stack[stackBase + rd] = *RS;
					else
						t.stack[stackBase + rd] = CrocValue.nullValue;
					break;

				case Op.SuperOf:
					mixin(GetRS);
					t.stack[stackBase + rd] = superOfImpl(t, RS);
					break;

				case Op.AddField:
					auto cls = &t.stack[stackBase + rd];
					mixin(GetRS);
					mixin(GetRT);
					auto isPublic = cast(bool)mixin(GetUImm);

					// should be guaranteed this by codegen
					assert(cls.type == CrocValue.Type.Class && RS.type == CrocValue.Type.String);

					if(!classobj.addField(t.vm.alloc, cls.mClass, RS.mString, RT, isPublic))
					{
						auto name = RS.mString.toString();
						auto clsName = cls.mClass.name.toString();
						throwStdException(t, "FieldException", "Attempting to add a field '{}' which already exists to class '{}'", name, clsName);
					}
					break;

				case Op.AddMethod:
					auto cls = &t.stack[stackBase + rd];
					mixin(GetRS);
					mixin(GetRT);
					auto isPublic = cast(bool)mixin(GetUImm);

					// should be guaranteed this by codegen
					assert(cls.type == CrocValue.Type.Class && RS.type == CrocValue.Type.String);

					if(!classobj.addMethod(t.vm.alloc, cls.mClass, RS.mString, RT, isPublic))
					{
						auto name = RS.mString.toString();
						auto clsName = cls.mClass.name.toString();
						throwStdException(t, "FieldException", "Attempting to add a method '{}' which already exists to class '{}'", name, clsName);
					}
					break;

				default:
					throwStdException(t, "VMError", "Unimplemented opcode {}", OpNames[cast(uword)opcode]);
			}
		}
	}
	catch(CrocException e)
	{
		t.currentAR.unwindCounter = 0;
		t.currentAR.unwindReturn = null;

		while(depth > 0)
		{
			if(t.trIndex > 0 && t.currentTR.actRecord is t.arIndex)
			{
				auto tr = *t.currentTR;
				popTR(t);

				auto base = t.stackBase + tr.slot;
				close(t, base);

				// remove any results that may have been saved
				loadResults(t);

				if(tr.isCatch)
				{
					t.stack[base] = t.vm.exception;
					t.vm.exception = null;
					t.vm.isThrowing = false;
					currentException = null;

					t.stack[base + 1 .. t.stackIndex] = CrocValue.nullValue;
					t.currentAR.pc = tr.pc;
				}
				else
				{
					currentException = e;
					t.currentAR.pc = tr.pc;
				}

				goto _exceptionRetry;
			}

			close(t, t.stackBase);
			callEpilogue(t, false);
			depth--;
		}

		throw e;
	}
	catch(CrocHaltException e)
	{
		while(depth > 0)
		{
			close(t, t.stackBase);
			callEpilogue(t, false);
			depth--;
		}

		unwindEH(t);
		throw e;
	}
}