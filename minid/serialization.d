/******************************************************************************
This module contains functions for serializing and deserializing compiled MiniD
functions and modules.

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

module minid.serialization;

import tango.core.BitManip;
import tango.io.protocol.Reader;
import tango.io.protocol.Writer;

import minid.ex;
import minid.func;
import minid.funcdef;
import minid.hash;
import minid.instance;
import minid.interpreter;
import minid.namespace;
import minid.opcodes;
import minid.streamlib;
import minid.string;
import minid.types;
import minid.utils;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

struct SerializationLib
{
static:
	void init(MDThread* t)
	{
		makeModule(t, "serialization", function uword(MDThread* t, uword numParams)
		{
			importModuleNoNS(t, "stream");

			newFunction(t, &serializeGraph,   "serializeGraph");   newGlobal(t, "serializeGraph");
			newFunction(t, &deserializeGraph, "deserializeGraph"); newGlobal(t, "deserializeGraph");
			return 0;
		});
	}

	uword serializeGraph(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		checkParam(t, 2, MDValue.Type.Table);
		checkAnyParam(t, 3);

		lookup(t, "stream.OutStream");
		OutputStream stream;

		if(as(t, 3, -1))
		{
			pop(t);
			stream = OutStreamObj.getOpenStream(t, 3);
		}
		else
		{
			pop(t);
			lookup(t, "stream.InoutStream");

			if(as(t, 3, -1))
			{
				pop(t);
				stream = InoutStreamObj.getOpenConduit(t, 3);
			}
			else
				paramTypeError(t, 3, "stream.OutStream|stream.InoutStream");
		}

		safeCode(t, .serializeGraph(t, 1, 2, stream));
		return 0;
	}

	uword deserializeGraph(MDThread* t, uword numParams)
	{
		checkParam(t, 1, MDValue.Type.Table);
		checkAnyParam(t, 2);

		lookup(t, "stream.InStream");
		InputStream stream;

		if(as(t, 2, -1))
		{
			pop(t);
			stream = InStreamObj.getOpenStream(t, 2);
		}
		else
		{
			pop(t);
			lookup(t, "stream.InoutStream");

			if(as(t, 2, -1))
			{
				pop(t);
				stream = InoutStreamObj.getOpenConduit(t, 2);
			}
			else
				paramTypeError(t, 2, "stream.OutStream|stream.InoutStream");
		}

		safeCode(t, .deserializeGraph(t, 1, stream));
		return 1;
	}
}

void serializeGraph(MDThread* t, word idx, word trans, OutputStream output)
{
	auto s = Serializer(t, output);
	s.writeGraph(idx, trans);
}

struct Serializer
{
private:
	MDThread* t;
	IWriter mOutput;
	Hash!(MDBaseObject*, uword) mObjTable;
	uword mObjIndex;
	MDTable* mTrans;
	MDInstance* mStream;
	MDFunction* mSerializeFunc;

	enum
	{
		Backref = -1,
		Transient = -2
	}

	static Serializer opCall(MDThread* t, IWriter output)
	{
		Serializer ret;
		ret.t = t;
		ret.mOutput = output;
		return ret;
	}

	static Serializer opCall(MDThread* t, OutputStream output)
	{
		return opCall(t, new Writer(output));
	}

	static class Goober
	{
		Serializer* s;
		this(Serializer* s) { this.s = s; }
	}

	static uword serializeFunc(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		getUpval(t, 0);
		auto g = cast(Goober)getNativeObj(t, -1);
		g.s.serialize(*getValue(t, 1));
		return 0;
	}

	void writeGraph(word value, word trans)
	{
		if(opis(t, value, trans))
			throwException(t, "Object to serialize is the same as the transients table");

		if(!isTable(t, trans))
		{
			pushTypeString(t, trans);
			throwException(t, "Transients table must be a table, not '{}'", getString(t, -1));
		}

		mTrans = getTable(t, trans);
		auto v = *getValue(t, value);

		commonSerialize
		({
			// we leave these on the stack so they won't be collected, but we get 'real' references
			// to them so we can push them in opSerialize callbacks.
			importModuleNoNS(t, "stream");
			lookup(t, "stream.OutStream");
			pushNull(t);
			pushNativeObj(t, cast(Object)mOutput.buffer());
			pushBool(t, false);
			rawCall(t, -4, 1);
			mStream = getInstance(t, -1);

				pushNativeObj(t, new Goober(this));
			newFunction(t, &serializeFunc, "serialize", 1);
			mSerializeFunc = getFunction(t, -1);

			serialize(v);
		});

		mOutput.flush();
	}

// 	void writeModule(word idx)
// 	void writeFunction(word idx)

	void commonSerialize(void delegate() dg)
	{
		auto size = stackSize(t);

		mObjTable.clear(t.vm.alloc);
		mObjIndex = 0;

		scope(exit)
		{
			setStackSize(t, size);
			mObjTable.clear(t.vm.alloc);
		}

		dg();
	}

	void tag(byte v)
	{
		mOutput.put(v);
	}

	void integer(long v)
	{
		if(v == 0)
		{
			mOutput.put(cast(byte)0);
			return;
		}
		else if(v == long.min)
		{
			// this is special-cased since -long.min == long.min!
			mOutput.put(cast(byte)0xFF);
			return;
		}

		int numBytes = void;
		bool neg = v < 0;

		if(neg)
			v = -v;

		if(v & 0xFFFF_FFFF_0000_0000)
			numBytes = (bsr(cast(uint)(v >>> 32)) / 8) + 5;
		else
			numBytes = (bsr(cast(uint)v) / 8) + 1;

		mOutput.put(cast(ubyte)(neg ? numBytes | 0x80 : numBytes));

		while(v)
		{
			mOutput.put(cast(ubyte)(v & 0xFF));
			v >>>= 8;
		}
	}

	void serialize(MDValue v)
	{
		// check to see if it's an transient value
		pushTable(t, mTrans);
		push(t, v);
		idx(t, -2);

		if(!isNull(t, -1))
		{
			tag(Transient);
			serialize(*getValue(t, -1));
			pop(t, 2);
			return;
		}

		pop(t, 2);

		// serialize it
		switch(v.type)
		{
			case MDValue.Type.Null:      serializeNull();                  break;
			case MDValue.Type.Bool:      serializeBool(v.mBool);           break;
			case MDValue.Type.Int:       serializeInt(v.mInt);             break;
			case MDValue.Type.Float:     serializeFloat(v.mFloat);         break;
			case MDValue.Type.Char:      serializeChar(v.mChar);           break;
			case MDValue.Type.String:    serializeString(v.mString);       break;
			case MDValue.Type.Table:     serializeTable(v.mTable);         break;
			case MDValue.Type.Array:     serializeArray(v.mArray);         break;
			case MDValue.Type.Function:  serializeFunction(v.mFunction);   break;
			case MDValue.Type.Class:     serializeClass(v.mClass);         break;
			case MDValue.Type.Instance:  serializeInstance(v.mInstance);   break;
			case MDValue.Type.Namespace: serializeNamespace(v.mNamespace); break;
			case MDValue.Type.Thread:    serializeThread(v.mThread);       break;
			case MDValue.Type.WeakRef:   serializeWeakRef(v.mWeakRef);     break;
			case MDValue.Type.NativeObj: serializeNativeObj(v.mNativeObj); break;

			case MDValue.Type.ArrayData: serializeArrayData(cast(MDArrayData*)v.mBaseObj); break;
			case MDValue.Type.Upvalue:   serializeUpval(cast(MDUpval*)v.mBaseObj);         break;
			case MDValue.Type.FuncDef:   serializeFuncDef(cast(MDFuncDef*)v.mBaseObj);     break;

			default: assert(false);
		}
	}

	void serializeNull()
	{
		tag(MDValue.Type.Null);
	}

	void serializeBool(bool v)
	{
		tag(MDValue.Type.Bool);
		mOutput.put(v);
	}

	void serializeInt(mdint v)
	{
		tag(MDValue.Type.Int);
		integer(v);
	}

	void serializeFloat(mdfloat v)
	{
		tag(MDValue.Type.Float);
		mOutput.put(v);
	}

	void serializeChar(dchar v)
	{
		tag(MDValue.Type.Char);
		integer(v);
	}

	void serializeString(MDString* v)
	{
		if(alreadyWritten(cast(MDBaseObject*)v))
			return;

		tag(MDValue.Type.String);
		auto data = v.toString();
		integer(data.length);
		mOutput.buffer.append(data.ptr, data.length * char.sizeof);
	}

	void serializeTable(MDTable* v)
	{
		if(alreadyWritten(cast(MDBaseObject*)v))
			return;

		tag(MDValue.Type.Table);
		integer(v.data.length);

		foreach(ref key, ref val; v.data)
		{
			serialize(key);
			serialize(val);
		}
	}

	void serializeArray(MDArray* v)
	{
		if(alreadyWritten(cast(MDBaseObject*)v))
			return;

		tag(MDValue.Type.Array);
		serialize(MDValue(cast(MDBaseObject*)v.data));
		integer(cast(uword)(v.slice.ptr - v.data.toArray().ptr));
		integer(v.slice.length);
		mOutput.put(v.isSlice);
	}

	void serializeArrayData(MDArrayData* v)
	{
		if(alreadyWritten(cast(MDBaseObject*)v))
			return;

		tag(MDValue.Type.ArrayData);
		integer(v.length);

		foreach(ref val; v.toArray())
			serialize(val);
	}

	void serializeFunction(MDFunction* v)
	{
		if(alreadyWritten(cast(MDBaseObject*)v))
			return;

		tag(MDValue.Type.Function);

		if(v.isNative)
		{
			pushFunction(t, v);
			throwException(t, "Attempting to persist a native function '{}'", funcName(t, -1));
		}

		// we do this first so we can allocate it at the beginning of deserialization
		integer(v.numUpvals);

		serialize(MDValue(v.name));
		serialize(MDValue(cast(MDBaseObject*)v.scriptFunc));

		if(v.environment is t.vm.globals)
			mOutput.put(false);
		else
		{
			mOutput.put(true);
			serialize(MDValue(v.environment));
		}

		foreach(val; v.scriptUpvals)
			serialize(MDValue(cast(MDBaseObject*)val));
	}

	void serializeUpval(MDUpval* v)
	{
		if(alreadyWritten(cast(MDBaseObject*)v))
			return;

		tag(MDValue.Type.Upvalue);
		serialize(*v.value);
	}

	void serializeFuncDef(MDFuncDef* v)
	{
		if(alreadyWritten(cast(MDBaseObject*)v))
			return;

		tag(MDValue.Type.FuncDef);
		serialize(MDValue(v.location.file));
		integer(v.location.line);
		integer(v.location.col);
		mOutput.put(v.isVararg);
		serialize(MDValue(v.name));
		integer(v.numParams);
		integer(v.paramMasks.length);

		foreach(mask; v.paramMasks)
			integer(mask);

		integer(v.numUpvals);
		integer(v.stackSize);
		integer(v.innerFuncs.length);

		foreach(func; v.innerFuncs)
			serialize(MDValue(cast(MDBaseObject*)func));

		integer(v.constants.length);

		foreach(ref val; v.constants)
			serialize(val);

		integer(v.code.length);
		mOutput.buffer.append(v.code.ptr, v.code.length * Instruction.sizeof);

		mOutput.put(v.isPure);

		if(auto f = v.cachedFunc)
		{
			mOutput.put(true);
			serialize(MDValue(f));
		}
		else
			mOutput.put(false);

		integer(v.switchTables.length);

		foreach(ref st; v.switchTables)
		{
			integer(st.offsets.length);

			foreach(ref k, v; st.offsets)
			{
				serialize(k);
				integer(v);
			}

			integer(st.defaultOffset);
		}

		integer(v.lineInfo.length);
		mOutput.buffer.append(v.lineInfo.ptr, v.lineInfo.length * uint.sizeof);
		integer(v.upvalNames.length);

		foreach(name; v.upvalNames)
			serialize(MDValue(name));

		integer(v.locVarDescs.length);

		foreach(ref desc; v.locVarDescs)
		{
			serialize(MDValue(desc.name));
			integer(desc.pcStart);
			integer(desc.pcEnd);
			integer(desc.reg);
		}
	}

	void serializeClass(MDClass* v)
	{
		if(alreadyWritten(cast(MDBaseObject*)v))
			return;

		if(v.allocator || v.finalizer)
		{
			push(t, MDValue(v));
			pushToString(t, -1);
			throwException(t, "Attempting to serialize '{}', which has an allocator or finalizer", getString(t, -1));
		}

		tag(MDValue.Type.Class);
		serialize(MDValue(v.name));

		if(v.parent)
		{
			mOutput.put(true);
			serialize(MDValue(v.parent));
		}
		else
			mOutput.put(false);

		assert(v.fields !is null);
		serialize(MDValue(v.fields));
	}

	void serializeInstance(MDInstance* v)
	{
		if(alreadyWritten(cast(MDBaseObject*)v))
			return;

		tag(MDValue.Type.Instance);
		integer(v.numValues);
		integer(v.extraBytes);
		serialize(MDValue(v.parent));

		pushInstance(t, v);

		if(hasField(t, -1, "opSerialize"))
		{
			field(t, -1, "opSerialize");

			if(isFunction(t, -1))
			{
				mOutput.put(true);
				pop(t);
				pushNull(t);
				pushInstance(t, mStream);
				pushFunction(t, mSerializeFunc);
				methodCall(t, -4, "opSerialize", 0);
				return;
			}
			else if(isBool(t, -1))
			{
				if(!getBool(t, -1))
				{
					pushToString(t, -2, true);
					throwException(t, "Attempting to serialize '{}', whose opSerialize field is 'false'", getString(t, -1));
				}

				pop(t);
				// fall out, serialize literally.
			}
			else
			{
				pushToString(t, -2, true);
				pushTypeString(t, -2);
				throwException(t, "Attempting to serialize '{}', whose opSerialize is a '{}', not a bool or function", getString(t, -2), getString(t, -1));
			}
		}

		pop(t);
		mOutput.put(false);

		if(v.finalizer || v.numValues || v.extraBytes)
		{
			push(t, MDValue(v));
			pushToString(t, -1, true);
			throwException(t, "Attempting to serialize '{}', which has a finalizer, extra values, or extra bytes", getString(t, -1));
		}

		if(v.parent.allocator || v.parent.finalizer)
		{
			push(t, MDValue(v));
			pushToString(t, -1, true);
			throwException(t, "Attempting to serialize '{}', whose class has an allocator or finalizer", getString(t, -1));
		}

		if(v.fields)
		{
			mOutput.put(true);
			serialize(MDValue(v.fields));
		}
		else
			mOutput.put(false);
	}

	void serializeNamespace(MDNamespace* v)
	{
		if(alreadyWritten(cast(MDBaseObject*)v))
			return;

		tag(MDValue.Type.Namespace);
		serialize(MDValue(v.name));

		if(v.parent is null)
			mOutput.put(false);
		else
		{
			mOutput.put(true);
			serialize(MDValue(v.parent));
		}

		integer(v.data.length);

		foreach(key, ref val; v.data)
		{
			serialize(MDValue(key));
			serialize(val);
		}
	}

	void serializeThread(MDThread* v)
	{
    	if(alreadyWritten(cast(MDBaseObject*)v))
    		return;

    	if(t is v)
    		throwException(t, "Attempting to serialize the currently-executing thread");

    	if(v.nativeCallDepth > 0)
    		throwException(t, "Attempting to serialize a thread with at least one native or metamethod call on its call stack");

		tag(MDValue.Type.Thread);

		version(MDExtendedCoro)
		{
			mOutput.put(true);
		}
		else
		{
			mOutput.put(false);
			integer(v.savedCallDepth);
		}

		integer(v.arIndex);

		foreach(ref rec; v.actRecs[0 .. v.arIndex])
		{
			integer(rec.base);
			integer(rec.savedTop);
			integer(rec.vargBase);
			integer(rec.returnSlot);

			if(rec.func is null)
				mOutput.put(false);
			else
			{
				mOutput.put(true);
				serialize(MDValue(rec.func));
				uword diff = rec.pc - rec.func.scriptFunc.code.ptr;
				integer(diff);
			}

			integer(rec.numReturns);

			if(rec.proto)
			{
				mOutput.put(true);
				serialize(MDValue(rec.proto));
			}
			else
				mOutput.put(false);

			integer(rec.numTailcalls);
			integer(rec.firstResult);
			integer(rec.numResults);
			integer(rec.unwindCounter);

			if(rec.unwindReturn)
			{
				mOutput.put(true);
				uword diff = rec.unwindReturn - rec.func.scriptFunc.code.ptr;
				integer(diff);
			}
			else
				mOutput.put(false);
		}

		integer(v.trIndex);

		foreach(ref rec; v.tryRecs[0 .. v.trIndex])
		{
			mOutput.put(rec.isCatch);
			integer(rec.slot);
			integer(rec.actRecord);

			uword diff = rec.pc - v.actRecs[rec.actRecord].func.scriptFunc.code.ptr;
			integer(diff);
		}

		integer(v.stackIndex);
		uword stackTop;

		if(v.arIndex > 0)
			stackTop = v.currentAR.savedTop;
		else
			stackTop = v.stackIndex;

		integer(stackTop);

		foreach(ref val; v.stack[0 .. stackTop])
			serialize(val);

		integer(v.stackBase);
		integer(v.resultIndex);

		foreach(ref val; v.results[0 .. v.resultIndex])
			serialize(val);

		mOutput.put(v.shouldHalt);

		if(v.coroFunc)
		{
			mOutput.put(true);
			serialize(MDValue(v.coroFunc));
		}
		else
			mOutput.put(false);

		integer(v.state);
		integer(v.numYields);

		// TODO: hooks?!

		for(auto uv = t.upvalHead; uv !is null; uv = uv.nextuv)
		{
			assert(uv.value !is &uv.closedValue);
			serialize(MDValue(cast(MDBaseObject*)uv));
			uword diff = uv.value - v.stack.ptr;
			integer(diff);
		}

		tag(MDValue.Type.Null);
	}

	void serializeWeakRef(MDWeakRef* v)
	{
		if(alreadyWritten(cast(MDBaseObject*)v))
			return;

		tag(MDValue.Type.WeakRef);

		if(v.obj is null)
			mOutput.put(true);
		else
		{
			mOutput.put(false);
			serialize(MDValue(v.obj));
		}
	}

	void serializeNativeObj(MDNativeObj* v)
	{
		throwException(t, "Attempting to serialize a nativeobj.  Please use the transients table.");
	}

	void writeRef(uword idx)
	{
		tag(Backref);
		integer(idx);
	}

	void addObject(MDBaseObject* v)
	{
		*mObjTable.insert(t.vm.alloc, v) = mObjIndex++;
	}

	bool alreadyWritten(MDValue v)
	{
		return alreadyWritten(v.mBaseObj);
	}

	bool alreadyWritten(MDBaseObject* v)
	{
		if(auto idx = mObjTable.lookup(v))
		{
			writeRef(*idx);
			return true;
		}

		addObject(v);
		return false;
	}
}

word deserializeGraph(MDThread* t, word trans, InputStream input)
{
	auto d = Deserializer(t, input);
	return d.readGraph(trans);
}

struct Deserializer
{
private:
	MDThread* t;
	IReader mInput;
	MDBaseObject*[] mObjTable;
	MDTable* mTrans;
	MDInstance* mStream;
	MDFunction* mDeserializeFunc;

	static Deserializer opCall(MDThread* t, IReader input)
	{
		Deserializer ret;
		ret.t = t;
		ret.mInput = input;
		return ret;
	}

	static Deserializer opCall(MDThread* t, InputStream input)
	{
		return opCall(t, new Reader(input));
	}

	static class Goober
	{
		Deserializer* d;
		this(Deserializer* d) { this.d = d; }
	}

	static uword deserializeFunc(MDThread* t, uword numParams)
	{
		getUpval(t, 0);
		auto g = cast(Goober)getNativeObj(t, -1);
		g.d.deserializeValue();
		return 1;
	}

	word readGraph(word trans)
	{
		if(!isTable(t, trans))
		{
			pushTypeString(t, trans);
			throwException(t, "Transients table must be a table, not '{}'", getString(t, -1));
		}

		mTrans = getTable(t, trans);

		commonDeserialize
		({
			// we leave these on the stack so they won't be collected, but we get 'real' references
			// to them so we can push them in opSerialize callbacks.
			importModuleNoNS(t, "stream");
			lookup(t, "stream.InStream");
			pushNull(t);
			pushNativeObj(t, cast(Object)mInput.buffer());
			pushBool(t, false);
			rawCall(t, -4, 1);
			mStream = getInstance(t, -1);

				pushNativeObj(t, new Goober(this));
			newFunction(t, &deserializeFunc, "deserialize", 1);
			mDeserializeFunc = getFunction(t, -1);

			deserializeValue();
			insertAndPop(t, -3);
		});

		return stackSize(t) - 1;
	}

// 	word readModule()
// 	{
// 	}
//
// 	word readFunction()
// 	{
// 	}

	void commonDeserialize(void delegate() dg)
	{
		auto size = stackSize(t);
		t.vm.alloc.resizeArray(mObjTable, 0);
		auto oldLimit = t.vm.alloc.gcLimit;
		t.vm.alloc.gcLimit = typeof(oldLimit).max;

		scope(failure)
			setStackSize(t, size);

		scope(exit)
		{
			t.vm.alloc.resizeArray(mObjTable, 0);
			t.vm.alloc.gcLimit = oldLimit;
		}

		dg();
		maybeGC(t);
	}

	byte tag()
	{
		byte ret = void;
		mInput.get(ret);
		return ret;
	}

	long integer()()
	{
		byte v = void;
		mInput.get(v);

		if(v == 0)
			return 0;
		else if(v == 0xFF)
			return long.min;
		else
		{
			bool neg = (v & 0x80) != 0;

			if(neg)
				v &= ~0x80;

			auto numBytes = v;
			long ret = 0;

			for(int shift = 0; numBytes; numBytes--, shift += 8)
			{
				mInput.get(v);
				ret |= v << shift;
			}

			return neg ? -ret : ret;
		}
	}

	void integer(T)(ref T x)
	{
		x = cast(T)integer();	
	}

	void deserializeValue()
	{
		switch(tag())
		{
			case MDValue.Type.Null:      deserializeNullImpl();      break;
			case MDValue.Type.Bool:      deserializeBoolImpl();      break;
			case MDValue.Type.Int:       deserializeIntImpl();       break;
			case MDValue.Type.Float:     deserializeFloatImpl();     break;
			case MDValue.Type.Char:      deserializeCharImpl();      break;
			case MDValue.Type.String:    deserializeStringImpl();    break;
			case MDValue.Type.Table:     deserializeTableImpl();     break;
			case MDValue.Type.Array:     deserializeArrayImpl();     break;
			case MDValue.Type.Function:  deserializeFunctionImpl();  break;
			case MDValue.Type.Class:     deserializeClassImpl();     break;
			case MDValue.Type.Instance:  deserializeInstanceImpl();  break;
			case MDValue.Type.Namespace: deserializeNamespaceImpl(); break;
			case MDValue.Type.Thread:    deserializeThreadImpl();    break;
			case MDValue.Type.WeakRef:   deserializeWeakrefImpl();   break;
			case MDValue.Type.Upvalue:   deserializeUpvalImpl();     break;

			case Serializer.Backref:     push(t, MDValue(mObjTable[cast(uword)integer()])); break;

			case Serializer.Transient:
				pushTable(t, mTrans);
				deserializeValue();
				idx(t, -2);
				insertAndPop(t, -2);
				break;

			default: throwException(t, "Malformed data");
		}
	}

	void checkTag(byte type)
	{
		if(tag() != type)
			throwException(t, "Malformed data");
	}

	void deserializeNull()
	{
		checkTag(MDValue.Type.Null);
		deserializeNullImpl();
	}

	void deserializeNullImpl()
	{
		pushNull(t);
	}

	void deserializeBool()
	{
		checkTag(MDValue.Type.Bool);
		deserializeBoolImpl();
	}

	void deserializeBoolImpl()
	{
		bool v = void;
		mInput.get(v);
		pushBool(t, v);
	}
	
	void deserializeInt()
	{
		checkTag(MDValue.Type.Int);
		deserializeIntImpl();
	}

	void deserializeIntImpl()
	{
		pushInt(t, integer());
	}
	
	void deserializeFloat()
	{
		checkTag(MDValue.Type.Float);
		deserializeFloatImpl();
	}

	void deserializeFloatImpl()
	{
		mdfloat v = void;
		mInput.get(v);
		pushFloat(t, v);
	}
	
	void deserializeChar()
	{
		checkTag(MDValue.Type.Char);
		deserializeCharImpl();
	}

	void deserializeCharImpl()
	{
		pushChar(t, cast(dchar)integer());
	}

	bool checkObjTag(byte type)
	{
		auto tmp = tag();

		if(tmp == type)
			return true;
		else if(tmp == Serializer.Backref)
		{
			auto ret = mObjTable[cast(uword)integer()];
			assert(ret.mType == type);
			push(t, MDValue(ret));
			return false;
		}
		else if(tmp == Serializer.Transient)
		{
			pushTable(t, mTrans);
			deserializeValue();
			idx(t, -2);
			insertAndPop(t, -2);

			if(.type(t, -1) != type)
				throwException(t, "Invalid transient table");

			return false;
		}
		else
			throwException(t, "Malformed data");

		assert(false);
	}

	void deserializeString()
	{
		if(checkObjTag(MDValue.Type.String))
			deserializeStringImpl();
	}

	void deserializeStringImpl()
	{
		auto len = integer();

		auto data = t.vm.alloc.allocArray!(char)(cast(uword)len);
		scope(exit) t.vm.alloc.freeArray(data);

		mInput.buffer.readExact(data.ptr, cast(uword)len * char.sizeof);
		pushString(t, data);
		addObject(getValue(t, -1).mBaseObj);
	}

	void deserializeTable()
	{
		if(checkObjTag(MDValue.Type.Table))
			deserializeTableImpl();
	}

	void deserializeTableImpl()
	{
		auto len = integer();

		auto v = newTable(t);
		addObject(getValue(t, -1).mBaseObj);

		for(uword i = 0; i < len; i++)
		{
			deserializeValue();
			deserializeValue();
			idxa(t, v);
		}
	}

	void deserializeArray()
	{
		if(checkObjTag(MDValue.Type.Array))
			deserializeArrayImpl();
	}

	void deserializeArrayImpl()
	{
		auto arr = t.vm.alloc.allocate!(MDArray);
		addObject(cast(MDBaseObject*)arr);

		arr.data = deserializeArrayData();

		auto lo = cast(uword)integer();
		auto hi = cast(uword)integer();
		arr.slice = arr.data.toArray()[lo .. hi];
		mInput.get(arr.isSlice);

		pushArray(t, arr);
	}

	MDArrayData* deserializeArrayData()
	{
		if(checkObjTag(MDValue.Type.ArrayData))
			return deserializeArrayDataImpl();
		else
		{
			auto ad = cast(MDArrayData*)getValue(t, -1).mBaseObj;
			pop(t);
			return ad;
		}
	}

	MDArrayData* deserializeArrayDataImpl()
	{
		auto len = cast(uword)integer();
		auto data = t.vm.alloc.allocate!(MDArrayData)(MDArrayData.sizeof + (MDValue.sizeof * len));
		addObject(cast(MDBaseObject*)data);

		data.length = len;

		foreach(ref val; data.toArray())
		{
			deserializeValue();
			val = *getValue(t, -1);
			pop(t);
		}

		return data;
	}

	void deserializeFunction()
	{
		if(checkObjTag(MDValue.Type.Function))
			deserializeFunctionImpl();
	}

	void deserializeFunctionImpl()
	{
		auto numUpvals = cast(uword)integer();
		auto func = t.vm.alloc.allocate!(MDFunction)(func.ScriptClosureSize(numUpvals));
		addObject(cast(MDBaseObject*)func);

		func.isNative = false;
		func.numUpvals = numUpvals;
		deserializeString();
		func.name = getStringObj(t, -1);
		pop(t);
		deserializeFuncDef();
		func.scriptFunc = cast(MDFuncDef*)getValue(t, -1).mBaseObj;
		pop(t);

		bool haveEnv;
		mInput.get(haveEnv);

		if(haveEnv)
			deserializeNamespace();
		else
			pushGlobal(t, "_G");

		func.environment = getNamespace(t, -1);
		pop(t);

		foreach(ref val; func.scriptUpvals())
		{
			deserializeUpval();
			val = cast(MDUpval*)getValue(t, -1).mBaseObj;
			pop(t);
		}

		pushFunction(t, func);
	}

	void deserializeUpval()
	{
		if(checkObjTag(MDValue.Type.Upvalue))
			deserializeUpvalImpl();
	}

	void deserializeUpvalImpl()
	{
		auto uv = t.vm.alloc.allocate!(MDUpval)();
		addObject(cast(MDBaseObject*)uv);
		uv.value = &uv.closedValue;
		deserializeValue();
		uv.closedValue = *getValue(t, -1);
		pop(t);
		push(t, MDValue(cast(MDBaseObject*)uv));
	}

	void deserializeFuncDef()
	{
		if(checkObjTag(MDValue.Type.FuncDef))
			deserializeFuncDefImpl();
	}

	void deserializeFuncDefImpl()
	{
		auto def = t.vm.alloc.allocate!(MDFuncDef);
		addObject(cast(MDBaseObject*)def);

		deserializeString();
		def.location.file = getStringObj(t, -1);
		pop(t);
		integer(def.location.line);
		integer(def.location.col);
		mInput.get(def.isVararg);
		deserializeString();
		def.name = getStringObj(t, -1);
		pop(t);
		integer(def.numParams);
		t.vm.alloc.resizeArray(def.paramMasks, cast(uword)integer());

		foreach(ref mask; def.paramMasks)
			integer(mask);

		integer(def.numUpvals);
		integer(def.stackSize);
		t.vm.alloc.resizeArray(def.innerFuncs, cast(uword)integer());

		foreach(ref func; def.innerFuncs)
		{
			deserializeFuncDef();
			func = cast(MDFuncDef*)getValue(t, -1).mBaseObj;
			pop(t);
		}

		t.vm.alloc.resizeArray(def.constants, cast(uword)integer());

		foreach(ref val; def.constants)
		{
			deserializeValue();
			val = *getValue(t, -1);
			pop(t);
		}

		t.vm.alloc.resizeArray(def.code, cast(uword)integer());
		mInput.buffer.readExact(def.code.ptr, def.code.length * Instruction.sizeof);
		mInput.get(def.isPure);

		bool haveCached;
		mInput.get(haveCached);
		
		if(haveCached)
		{
			deserializeFunction();
			def.cachedFunc = getFunction(t, -1);
			pop(t);
		}
		else
			def.cachedFunc = null;

		t.vm.alloc.resizeArray(def.switchTables, cast(uword)integer());

		foreach(ref st; def.switchTables)
		{
			auto numOffsets = cast(uword)integer();

			for(uword i = 0; i < numOffsets; i++)
			{
				deserializeValue();
				integer(*st.offsets.insert(t.vm.alloc, *getValue(t, -1)));
				pop(t);
			}

			integer(st.defaultOffset);
		}

		t.vm.alloc.resizeArray(def.lineInfo, cast(uword)integer());
		mInput.buffer.readExact(def.lineInfo.ptr, def.lineInfo.length * uint.sizeof);

		t.vm.alloc.resizeArray(def.upvalNames, cast(uword)integer());

		foreach(ref name; def.upvalNames)
		{
			deserializeString();
			name = getStringObj(t, -1);
			pop(t);
		}

		t.vm.alloc.resizeArray(def.locVarDescs, cast(uword)integer());

		foreach(ref desc; def.locVarDescs)
		{
			deserializeString();
			desc.name = getStringObj(t, -1);
			pop(t);
			integer(desc.pcStart);
			integer(desc.pcEnd);
			integer(desc.reg);
		}

		push(t, MDValue(cast(MDBaseObject*)def));
	}

	void deserializeClass()
	{
		if(checkObjTag(MDValue.Type.Class))
			deserializeClassImpl();
	}

	void deserializeClassImpl()
	{
    	auto cls = t.vm.alloc.allocate!(MDClass)();
    	addObject(cast(MDBaseObject*)cls);

    	deserializeString();
		cls.name = getStringObj(t, -1);
		pop(t);

		bool haveParent;
		mInput.get(haveParent);

		if(haveParent)
		{
			deserializeClass();
			cls.parent = getClass(t, -1);
			pop(t);
		}
		else
			cls.parent = null;

		deserializeNamespace();
		cls.fields = getNamespace(t, -1);
		pop(t);

		assert(!cls.parent || cls.fields.parent);

		pushClass(t, cls);
	}

	void deserializeInstance()
	{
		if(checkObjTag(MDValue.Type.Instance))
			deserializeInstanceImpl();
	}

	void deserializeInstanceImpl()
	{
		auto numValues = cast(uword)integer();
		auto extraBytes = cast(uword)integer();

		// if it was custom-allocated, we can't necessarily do this.
		// well, can we?  I mean technically, a custom allocator can't do anything *terribly* weird,
		// like using malloc.. and besides, we wouldn't know what params to call it with.
		// I suppose we can assume that if a class writer is providing an opDeserialize method, they're
		// going to expect this.
		auto inst = t.vm.alloc.allocate!(MDInstance)(instance.InstanceSize(numValues, extraBytes));
		inst.numValues = numValues;
		inst.extraBytes = extraBytes;
		inst.extraValues()[] = MDValue.nullValue;
		addObject(cast(MDBaseObject*)inst);

		deserializeClass();
		inst.parent = getClass(t, -1);
		// TODO: this isn't necessarily right, if the class's finalizer changed.  how should we handle this?
		inst.finalizer = inst.parent.finalizer;
		pop(t);

		bool isSpecial;
		mInput.get(isSpecial);

		if(isSpecial)
		{
			pushInstance(t, inst);

			if(!hasMethod(t, -1, "opDeserialize"))
			{
				pushToString(t, -1, true);
				throwException(t, "'{}' was serialized with opSerialize, but does not have a matching opDeserialize", getString(t, -1));
			}

			pushNull(t);
			pushInstance(t, mStream);
			pushFunction(t, mDeserializeFunc);
			methodCall(t, -4, "opDeserialize", 0);
		}
		else
		{
			assert(numValues == 0 && extraBytes == 0);

			bool haveFields;
			mInput.get(haveFields);

			if(haveFields)
			{
				deserializeNamespace();
				inst.fields = getNamespace(t, -1);
				pop(t);
			}
		}

		pushInstance(t, inst);
	}

	void deserializeNamespace()
	{
		if(checkObjTag(MDValue.Type.Namespace))
			deserializeNamespaceImpl();
	}

	void deserializeNamespaceImpl()
	{
		auto ns = t.vm.alloc.allocate!(MDNamespace);
		addObject(cast(MDBaseObject*)ns);

		deserializeString();
		ns.name = getStringObj(t, -1);
		pop(t);
		pushNamespace(t, ns);

		bool haveParent;
		mInput.get(haveParent);

		if(haveParent)
		{
			deserializeNamespace();
			ns.parent = getNamespace(t, -1);
			pop(t);
		}
		else
			ns.parent = null;

		auto len = cast(uword)integer();

		for(uword i = 0; i < len; i++)
		{
			deserializeString();
			deserializeValue();
			fielda(t, -3);
		}
	}

	void deserializeThread()
	{
		if(checkObjTag(MDValue.Type.Thread))
			deserializeThreadImpl();
	}

	void deserializeThreadImpl()
	{
		auto ret = t.vm.alloc.allocate!(MDThread);
		addObject(cast(MDBaseObject*)ret);
		ret.vm = t.vm;

		bool isExtended;
		mInput.get(isExtended);

		version(MDExtendedCoro)
		{
			if(!isExtended)
				throwException(t, "Attempting to deserialize a non-extended coroutine, but extended coroutine support was compiled in");

			// not sure how to handle deserialization of extended coros yet..
			// the issue is that we have to somehow create a ThreadFiber object and have it resume from where
			// it yielded...?  is that even possible?
			throwException(t, "AGH I don't know how to deserialize extended coros");
		}
		else
		{
			if(isExtended)
				throwException(t, "Attempting to deserialize an extended coroutine, but extended coroutine support was not compiled in");

			integer(ret.savedCallDepth);
		}

		integer(ret.arIndex);
		t.vm.alloc.resizeArray(ret.actRecs, ret.arIndex < 10 ? 10 : ret.arIndex);

		if(ret.arIndex > 0)
			ret.currentAR = &ret.actRecs[ret.arIndex - 1];
		else
			ret.currentAR = null;

		foreach(ref rec; ret.actRecs[0 .. ret.arIndex])
		{
			integer(rec.base);
			integer(rec.savedTop);
			integer(rec.vargBase);
			integer(rec.returnSlot);

			bool haveFunc;
			mInput.get(haveFunc);

			if(haveFunc)
			{
				deserializeFunction();
				rec.func = getFunction(t, -1);
				pop(t);

				uword diff;
				integer(diff);
				rec.pc = rec.func.scriptFunc.code.ptr + diff;
			}
			else
			{
				rec.func = null;
				rec.pc = null;
			}

			integer(rec.numReturns);

			bool haveProto;
			mInput.get(haveProto);

			if(haveProto)
			{
				deserializeClass();
				rec.proto = getClass(t, -1);
				pop(t);
			}
			else
				rec.proto = null;

			integer(rec.numTailcalls);
			integer(rec.firstResult);
			integer(rec.numResults);
			integer(rec.unwindCounter);

			bool haveUnwindRet;
			mInput.get(haveUnwindRet);

			if(haveUnwindRet)
			{
				uword diff;
				integer(diff);
				rec.unwindReturn = rec.func.scriptFunc.code.ptr + diff;
			}
			else
				rec.unwindReturn = null;
		}

		integer(ret.trIndex);
		t.vm.alloc.resizeArray(ret.tryRecs, ret.trIndex < 10 ? 10 : ret.trIndex);

		if(ret.trIndex > 0)
			ret.currentTR = &ret.tryRecs[ret.trIndex - 1];
		else
			ret.currentTR = null;

		foreach(ref rec; ret.tryRecs[0 .. ret.trIndex])
		{
			mInput.get(rec.isCatch);
			integer(rec.slot);
			integer(rec.actRecord);

			uword diff;
			integer(diff);
			rec.pc = ret.actRecs[rec.actRecord].func.scriptFunc.code.ptr + diff;
		}

		integer(ret.stackIndex);

		uword stackTop;
		integer(stackTop);
		t.vm.alloc.resizeArray(ret.stack, stackTop < 20 ? 20 : stackTop);

		foreach(ref val; ret.stack[0 .. stackTop])
		{
			deserializeValue();
			val = *getValue(t, -1);
			pop(t);
		}

		integer(ret.stackBase);
		integer(ret.resultIndex);
		t.vm.alloc.resizeArray(ret.results, ret.resultIndex < 8 ? 8 : ret.resultIndex);

		foreach(ref val; ret.results[0 .. ret.resultIndex])
		{
			deserializeValue();
			val = *getValue(t, -1);
			pop(t);
		}

		mInput.get(ret.shouldHalt);

		bool haveCoroFunc;
		mInput.get(haveCoroFunc);

		if(haveCoroFunc)
		{
			deserializeFunction();
			ret.coroFunc = getFunction(t, -1);
			pop(t);
		}
		else
			ret.coroFunc = null;

		integer(ret.state);
		integer(ret.numYields);

		// TODO: hooks?!

		auto next = &t.upvalHead;

		while(true)
		{
			deserializeValue();

			if(isNull(t, -1))
			{
				pop(t);
				break;
			}

			auto uv = cast(MDUpval*)getValue(t, -1).mBaseObj;
			pop(t);
			
			uword diff;
			integer(diff);
			
			uv.value = ret.stack.ptr + diff;
			*next = uv;
			next = &uv.nextuv;
		}

		*next = null;

		pushThread(t, ret);
	}

	void deserializeWeakref()
	{
		if(checkObjTag(MDValue.Type.WeakRef))
			deserializeWeakrefImpl();
	}

	void deserializeWeakrefImpl()
	{
		auto wr = t.vm.alloc.allocate!(MDWeakRef);
		wr.obj = null;
		addObject(cast(MDBaseObject*)wr);

		bool isNull;
		mInput.get(isNull);

		if(!isNull)
		{
			deserializeValue();
			wr.obj = getValue(t, -1).mBaseObj;
			pop(t);
			*t.vm.weakRefTab.insert(t.vm.alloc, wr.obj) = wr;
		}
		
		pushWeakRefObj(t, wr);
	}

	void addObject(MDBaseObject* v)
	{
		t.vm.alloc.resizeArray(mObjTable, mObjTable.length + 1);
		mObjTable[$ - 1] = v;
	}
}

/**
Serializes the function object at the given index into the provided writer as a module.  Serializing a function as a module
outputs the platform-dependent MiniD module header before outputting the function, so that upon subsequent loads of the module,
the platform can be correctly detected.

Params:
	idx = The stack index of the function object to serialize.  The function must be a script function with no upvalues.
	s = The writer object to be used to serialize the function.
*/
void serializeModule(MDThread* t, word idx, IWriter s)
{
	auto func = getFunction(t, idx);

	if(func is null)
	{
		pushTypeString(t, idx);
		throwException(t, "serializeModule - 'function' expected, not '{}'", getString(t, -1));
	}

	if(func.isNative || func.scriptFunc.numUpvals > 0)
		throwException(t, "serializeModule - function '{}' is not eligible for serialization", func.name.toString());

	serializeAsModule(func.scriptFunc, s);
}

/**
Inverse of the above, which means it expects for there to be a module header at the beginning of the stream.  If the module
header of the stream does not match the module header for the platform that is loading the module, the load will fail.
A closure of the deserialized function is created with the current environment as its environment and is pushed onto the
given thread's stack.

Params:
	s = The reader object that holds the data stream from which the function will be deserialized.
*/
word deserializeModule(MDThread* t, IReader s)
{
	auto def = deserializeAsModule(t, s);
	pushEnvironment(t);
	pushFunction(t, func.create(t.vm.alloc, getNamespace(t, -1), def));
	insertAndPop(t, -2);
	return stackSize(t) - 1;
}

/**
Same as serializeModule but does not output the module header.
*/
void serializeFunction(MDThread* t, word idx, IWriter s)
{
	auto func = getFunction(t, idx);

	if(func is null)
	{
		pushTypeString(t, idx);
		throwException(t, "serializeFunction - 'function' expected, not '{}'", getString(t, -1));
	}

	if(func.isNative || func.scriptFunc.numUpvals > 0)
		throwException(t, "serializeFunction - function '{}' is not eligible for serialization", func.name.toString());

	serialize(func.scriptFunc, s);
}

/**
Same as deserializeModule but does not expect for there to be a module header.
*/
word deserializeFunction(MDThread* t, IReader s)
{
	auto def = deserialize(t, s);
	pushEnvironment(t);
	pushFunction(t, func.create(t.vm.alloc, getNamespace(t, -1), def));
	insertAndPop(t, -2);
	return stackSize(t) - 1;
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

align(1) struct FileHeader
{
	uint magic = FOURCC!("MinD");
	uint _version = MiniDVersion;
	ubyte platformBits = uword.sizeof * 8;

	version(BigEndian)
		ubyte endianness = 1;
	else
		ubyte endianness = 0;

	ubyte intSize = mdint.sizeof;
	ubyte floatSize = mdfloat.sizeof;

	ubyte[4] _padding;
}

static assert(FileHeader.sizeof == 16);

void serializeAsModule(MDFuncDef* fd, IWriter s)
{
	s.buffer.append(&FileHeader.init, FileHeader.sizeof);
	serialize(fd, s);
}

MDFuncDef* deserializeAsModule(MDThread* t, IReader s)
{
	FileHeader fh = void;
	s.buffer.readExact(&fh, FileHeader.sizeof);

	if(fh != FileHeader.init)
		throwException(t, "Serialized module header mismatch");

	return deserialize(t, s);
}

void serialize(MDFuncDef* fd, IWriter s)
{
	s.put(fd.location.line);
	s.put(fd.location.col);
	Serialize(s, fd.location.file);

	s.put(fd.isVararg);
	Serialize(s, fd.name);
	s.put(fd.numParams);
	Serialize(s, fd.paramMasks);
	s.put(fd.numUpvals);
	s.put(fd.stackSize);

	Serialize(s, fd.constants);
	Serialize(s, fd.code);
	s.put(fd.isPure);
	Serialize(s, fd.lineInfo);

	Serialize(s, fd.upvalNames);

	s.put(fd.locVarDescs.length);

	foreach(ref desc; fd.locVarDescs)
	{
		Serialize(s, desc.name);
		s.put(desc.pcStart);
		s.put(desc.pcEnd);
		s.put(desc.reg);
	}

	s.put(fd.switchTables.length);

	foreach(ref st; fd.switchTables)
	{
		s.put(st.offsets.length);

		foreach(ref k, v; st.offsets)
		{
			Serialize(s, k);
			s.put(v);
		}

		s.put(st.defaultOffset);
	}

	s.put(fd.innerFuncs.length);

	foreach(inner; fd.innerFuncs)
		serialize(inner, s);
}

MDFuncDef* deserialize(MDThread* t, IReader s)
{
	auto vm = t.vm;

	auto ret = funcdef.create(vm.alloc);

	s.get(ret.location.line);
	s.get(ret.location.col);
	Deserialize(t, s, ret.location.file);

	s.get(ret.isVararg);
	Deserialize(t, s, ret.name);
	s.get(ret.numParams);
	Deserialize(t, s, ret.paramMasks);
	s.get(ret.numUpvals);
	s.get(ret.stackSize);

	Deserialize(t, s, ret.constants);
	Deserialize(t, s, ret.code);
	s.get(ret.isPure);

	Deserialize(t, s, ret.lineInfo);
	Deserialize(t, s, ret.upvalNames);

	uword len = void;
	s.get(len);
	ret.locVarDescs = vm.alloc.allocArray!(MDFuncDef.LocVarDesc)(len);

	foreach(ref desc; ret.locVarDescs)
	{
		Deserialize(t, s, desc.name);
		s.get(desc.pcStart);
		s.get(desc.pcEnd);
		s.get(desc.reg);
	}

	s.get(len);
	ret.switchTables = vm.alloc.allocArray!(MDFuncDef.SwitchTable)(len);

	foreach(ref st; ret.switchTables)
	{
		s.get(len);

		for(uword i = 0; i < len; i++)
		{
			MDValue key = void;
			word value = void;

			Deserialize(t, s, key);
			s.get(value);

			*st.offsets.insert(vm.alloc, key) = value;
		}

		s.get(st.defaultOffset);
	}

	s.get(len);
	ret.innerFuncs = vm.alloc.allocArray!(MDFuncDef*)(len);

	foreach(ref inner; ret.innerFuncs)
		inner = deserialize(t, s);

	return ret;
}

void Serialize(IWriter s, MDString* val)
{
	auto data = val.toString();
	s.put(data.length);
	s.buffer.append(data.ptr, data.length * char.sizeof);
}

void Serialize(IWriter s, ushort[] val)
{
	s.put(val.length);
	s.buffer.append(val.ptr, val.length * ushort.sizeof);
}

void Serialize(IWriter s, MDValue[] val)
{
	s.put(val.length);

	foreach(ref v; val)
		Serialize(s, v);
}

void Serialize(IWriter s, Instruction[] val)
{
	s.put(val.length);
	s.buffer.append(val.ptr, val.length * Instruction.sizeof);
}

void Serialize(IWriter s, uint[] val)
{
	s.put(val.length);
	s.buffer.append(val.ptr, val.length * uint.sizeof);
}

void Serialize(IWriter s, MDString*[] val)
{
	s.put(val.length);

	foreach(v; val)
		Serialize(s, v);
}

void Serialize(IWriter s, ref MDValue val)
{
	s.put(cast(uint)val.type);

	switch(val.type)
	{
		case MDValue.Type.Null:   break;
		case MDValue.Type.Bool:   s.put(val.mBool); break;
		case MDValue.Type.Int:    s.put(val.mInt); break;
		case MDValue.Type.Float:  s.put(val.mFloat); break;
		case MDValue.Type.Char:   s.put(val.mChar); break;
		case MDValue.Type.String: Serialize(s, val.mString); break;
		default: assert(false, "Serialize(MDValue)");
	}
}

void Deserialize(MDThread* t, IReader s, ref MDString* val)
{
	uword len = void;
	s.get(len);

	auto data = t.vm.alloc.allocArray!(char)(len);
	scope(exit) t.vm.alloc.freeArray(data);

	s.buffer.readExact(data.ptr, len * char.sizeof);
	val = createString(t, data);
}

void Deserialize(MDThread* t, IReader s, ref ushort[] val)
{
	uword len = void;
	s.get(len);

	val = t.vm.alloc.allocArray!(ushort)(len);
	s.buffer.readExact(val.ptr, len * ushort.sizeof);
}

void Deserialize(MDThread* t, IReader s, ref MDValue[] val)
{
	uword len = void;
	s.get(len);

	val = t.vm.alloc.allocArray!(MDValue)(len);

	foreach(ref v; val)
		Deserialize(t, s, v);
}

void Deserialize(MDThread* t, IReader s, ref Instruction[] val)
{
	uword len = void;
	s.get(len);

	val = t.vm.alloc.allocArray!(Instruction)(len);
	s.buffer.readExact(val.ptr, len * Instruction.sizeof);
}

void Deserialize(MDThread* t, IReader s, ref uint[] val)
{
	uword len = void;
	s.get(len);

	val = t.vm.alloc.allocArray!(uint)(len);
	s.buffer.readExact(val.ptr, len * uint.sizeof);
}

void Deserialize(MDThread* t, IReader s, ref MDString*[] val)
{
	uword len = void;
	s.get(len);

	val = t.vm.alloc.allocArray!(MDString*)(len);

	foreach(ref v; val)
		Deserialize(t, s, v);
}

void Deserialize(MDThread* t, IReader s, ref MDValue val)
{
	uint type = void;
	s.get(type);
	val.type = cast(MDValue.Type)type;

	switch(val.type)
	{
		case MDValue.Type.Null:   break;
		case MDValue.Type.Bool:   s.get(val.mBool); break;
		case MDValue.Type.Int:    s.get(val.mInt); break;
		case MDValue.Type.Float:  s.get(val.mFloat); break;
		case MDValue.Type.Char:   s.get(val.mChar); break;
		case MDValue.Type.String: Deserialize(t, s, val.mString); break;
		default: assert(false, "Deserialize(MDValue)");
	}
}