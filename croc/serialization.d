/******************************************************************************
This module contains functions for serializing and deserializing compiled Croc
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

module croc.serialization;

import tango.core.BitManip;
import tango.core.Exception;
import tango.io.model.IConduit;

// This import violates layering. STUPID SERIALIZATION LIB.
import croc.ex;

import croc.api_interpreter;
import croc.api_stack;
import croc.base_hash;
import croc.types;
import croc.types_function;
import croc.types_instance;
import croc.utils;
import croc.vm;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void serializeGraph(CrocThread* t, word idx, word trans, OutputStream output)
{
	auto s = Serializer(t, output);
	s.writeGraph(idx, trans);
}

word deserializeGraph(CrocThread* t, word trans, InputStream input)
{
	auto d = Deserializer(t, input);
	return d.readGraph(trans);
}

void serializeModule(CrocThread* t, word idx, char[] name, OutputStream output)
{
	append(t, output, (&FileHeader.init)[0 .. 1]);
	put!(uword)(t, output, name.length);
	append(t, output, name);
	auto s = Serializer(t, output);
	idx = absIndex(t, idx);
	newTable(t);
	s.writeGraph(idx, -1);
	pop(t);
}

void deserializeModule(CrocThread* t, out char[] name, InputStream input)
{
	FileHeader fh = void;
	readExact(t, input, (&fh)[0 .. 1]);

	if(fh != FileHeader.init)
		throwStdException(t, "ValueException", "Serialized module header mismatch");

	uword len = void;
	get!(uword)(t, input, len);
	name = new char[](len);
	readExact(t, input, name);
	newTable(t);
	auto d = Deserializer(t, input);
	auto ret = d.readGraph(-1);
	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

align(1) struct FileHeader
{
	uint magic = FOURCC!("Croc");
	uint _version = CrocVersion;
	ubyte platformBits = uword.sizeof * 8;

	version(BigEndian)
		ubyte endianness = 1;
	else
		ubyte endianness = 0;

	ubyte intSize = crocint.sizeof;
	ubyte floatSize = crocfloat.sizeof;

	ubyte[4] _padding;
}

static assert(FileHeader.sizeof == 16);

struct Serializer
{
private:
	CrocThread* t;
	OutputStream mOutput;
	Hash!(CrocBaseObject*, uword) mObjTable;
	uword mObjIndex;
	CrocTable* mTrans;
	CrocInstance* mStream;
	CrocFunction* mSerializeFunc;

	enum
	{
		Backref = -1,
		Transient = -2
	}

	static Serializer opCall(CrocThread* t, OutputStream output)
	{
		Serializer ret;
		ret.t = t;
		ret.mOutput = output;
		return ret;
	}

	static class Goober
	{
		Serializer* s;
		this(Serializer* s) { this.s = s; }
	}

	static uword serializeFunc(CrocThread* t)
	{
		if(!isValidIndex(t, 1))
			throwStdException(t, "ParamException", "Expected at least one parameter");

		getUpval(t, 0);
		auto g = cast(Goober)getNativeObj(t, -1);
		g.s.serialize(*getValue(t, 1));
		return 0;
	}

	void writeGraph(word value, word trans)
	{
		if(opis(t, value, trans))
			throwStdException(t, "ValueException", "Object to serialize is the same as the transients table");

		if(!isTable(t, trans))
		{
			pushTypeString(t, trans);
			throwStdException(t, "TypeException", "Transients table must be a table, not '{}'", getString(t, -1));
		}

		mTrans = getTable(t, trans);
		auto v = *getValue(t, value);

		auto size = stackSize(t);

		mObjTable.clear(t.vm.alloc);
		mObjIndex = 0;

		scope(exit)
		{
			setStackSize(t, size);
			mObjTable.clear(t.vm.alloc);
		}

		// we leave these on the stack so they won't be collected, but we get 'real' references
		// to them so we can push them in opSerialize callbacks.
		importModuleNoNS(t, "stream");
		lookup(t, "stream.OutStream");
		pushNull(t);
		pushNativeObj(t, cast(Object)mOutput);
		pushBool(t, false);
		rawCall(t, -4, 1);
		mStream = getInstance(t, -1);

			pushNativeObj(t, new Goober(this));
		newFunction(t, 1, &serializeFunc, "serialize", 1);
		mSerializeFunc = getFunction(t, -1);

		serialize(v);

		mOutput.flush();
	}

	void tag(byte v)
	{
		put(t, mOutput, v);
	}

	void integer(long v)
	{
		if(v == 0)
		{
			put!(byte)(t, mOutput, 0);
			return;
		}
		else if(v == long.min)
		{
			// this is special-cased since -long.min == long.min!
			put(t, mOutput, cast(byte)0xFF);
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

		put(t, mOutput, cast(ubyte)(neg ? numBytes | 0x80 : numBytes));

		while(v)
		{
			put(t, mOutput, cast(ubyte)(v & 0xFF));
			v >>>= 8;
		}
	}

	void serialize(CrocValue v)
	{
		// check to see if it's an transient value
		push(t, CrocValue(mTrans));
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
			case CrocValue.Type.Null:      serializeNull();                  break;
			case CrocValue.Type.Bool:      serializeBool(v.mBool);           break;
			case CrocValue.Type.Int:       serializeInt(v.mInt);             break;
			case CrocValue.Type.Float:     serializeFloat(v.mFloat);         break;
			case CrocValue.Type.Char:      serializeChar(v.mChar);           break;
			case CrocValue.Type.String:    serializeString(v.mString);       break;
			case CrocValue.Type.Table:     serializeTable(v.mTable);         break;
			case CrocValue.Type.Array:     serializeArray(v.mArray);         break;
			case CrocValue.Type.Memblock:  serializeMemblock(v.mMemblock);   break;
			case CrocValue.Type.Function:  serializeFunction(v.mFunction);   break;
			case CrocValue.Type.Class:     serializeClass(v.mClass);         break;
			case CrocValue.Type.Instance:  serializeInstance(v.mInstance);   break;
			case CrocValue.Type.Namespace: serializeNamespace(v.mNamespace); break;
			case CrocValue.Type.Thread:    serializeThread(v.mThread);       break;
			case CrocValue.Type.WeakRef:   serializeWeakRef(v.mWeakRef);     break;
			case CrocValue.Type.NativeObj: serializeNativeObj(v.mNativeObj); break;
			case CrocValue.Type.FuncDef:   serializeFuncDef(v.mFuncDef);     break;

			case CrocValue.Type.Upvalue:   serializeUpval(cast(CrocUpval*)v.mBaseObj);         break;

			default: assert(false);
		}
	}

	void serializeNull()
	{
		tag(CrocValue.Type.Null);
	}

	void serializeBool(bool v)
	{
		tag(CrocValue.Type.Bool);
		put(t, mOutput, v);
	}

	void serializeInt(crocint v)
	{
		tag(CrocValue.Type.Int);
		integer(v);
	}

	void serializeFloat(crocfloat v)
	{
		tag(CrocValue.Type.Float);
		put(t, mOutput, v);
	}

	void serializeChar(dchar v)
	{
		tag(CrocValue.Type.Char);
		integer(v);
	}

	void serializeString(CrocString* v)
	{
		if(alreadyWritten(cast(CrocBaseObject*)v))
			return;

		tag(CrocValue.Type.String);
		auto data = v.toString();
		integer(data.length);
		append(t, mOutput, data);
	}

	void serializeTable(CrocTable* v)
	{
		if(alreadyWritten(cast(CrocBaseObject*)v))
			return;

		tag(CrocValue.Type.Table);
		integer(v.data.length);

		foreach(ref key, ref val; v.data)
		{
			serialize(key);
			serialize(val);
		}
	}

	void serializeArray(CrocArray* v)
	{
		if(alreadyWritten(cast(CrocBaseObject*)v))
			return;

		tag(CrocValue.Type.Array);
		integer(v.length);

		foreach(ref slot; v.toArray())
			serialize(slot.value);
	}

	void serializeMemblock(CrocMemblock* v)
	{
		if(alreadyWritten(cast(CrocBaseObject*)v))
			return;

		if(!v.ownData)
			throwStdException(t, "ValueException", "Attempting to serialize a memblock which does not own its data");

		tag(CrocValue.Type.Memblock);
		integer(v.data.length);
		append(t, mOutput, v.data);
	}

	void serializeFunction(CrocFunction* v)
	{
		if(alreadyWritten(cast(CrocBaseObject*)v))
			return;

		tag(CrocValue.Type.Function);

		if(v.isNative)
		{
			push(t, CrocValue(v));
			throwStdException(t, "ValueException", "Attempting to serialize a native function '{}'", funcName(t, -1));
		}

		// we do this first so we can allocate it at the beginning of deserialization
		integer(v.numUpvals);
		integer(v.maxParams);

		serialize(CrocValue(v.name));
		serialize(CrocValue(cast(CrocBaseObject*)v.scriptFunc));

		if(v.environment is t.vm.globals)
			put(t, mOutput, false);
		else
		{
			put(t, mOutput, true);
			serialize(CrocValue(v.environment));
		}

		foreach(val; v.scriptUpvals)
			serialize(CrocValue(cast(CrocBaseObject*)val));
	}

	void serializeUpval(CrocUpval* v)
	{
		if(alreadyWritten(cast(CrocBaseObject*)v))
			return;

		tag(CrocValue.Type.Upvalue);
		serialize(*v.value);
	}

	void serializeFuncDef(CrocFuncDef* v)
	{
		if(alreadyWritten(cast(CrocBaseObject*)v))
			return;

		tag(CrocValue.Type.FuncDef);
		serialize(CrocValue(v.locFile));
		integer(v.locLine);
		integer(v.locCol);
		put(t, mOutput, v.isVararg);
		serialize(CrocValue(v.name));
		integer(v.numParams);
		integer(v.paramMasks.length);

		foreach(mask; v.paramMasks)
			integer(mask);

		integer(v.numUpvals);

		integer(v.upvals.length);

		foreach(ref uv; v.upvals)
		{
			put(t, mOutput, uv.isUpvalue);
			integer(uv.index);
		}

		integer(v.stackSize);
		integer(v.innerFuncs.length);

		foreach(func; v.innerFuncs)
			serialize(CrocValue(cast(CrocBaseObject*)func));

		integer(v.constants.length);

		foreach(ref val; v.constants)
			serialize(val);

		integer(v.code.length);
		append(t, mOutput, v.code);

		if(auto e = v.environment)
		{
			put(t, mOutput, true);
			serialize(CrocValue(e));
		}
		else
			put(t, mOutput, false);

		if(auto f = v.cachedFunc)
		{
			put(t, mOutput, true);
			serialize(CrocValue(f));
		}
		else
			put(t, mOutput, false);

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
		append(t, mOutput, v.lineInfo);
		integer(v.upvalNames.length);

		foreach(name; v.upvalNames)
			serialize(CrocValue(name));

		integer(v.locVarDescs.length);

		foreach(ref desc; v.locVarDescs)
		{
			serialize(CrocValue(desc.name));
			integer(desc.pcStart);
			integer(desc.pcEnd);
			integer(desc.reg);
		}
	}

	void serializeClass(CrocClass* v)
	{
		if(alreadyWritten(cast(CrocBaseObject*)v))
			return;

		if(v.finalizer)
		{
			push(t, CrocValue(v));
			pushToString(t, -1);
			throwStdException(t, "ValueException", "Attempting to serialize '{}', which has a finalizer", getString(t, -1));
		}

		tag(CrocValue.Type.Class);
		serialize(CrocValue(v.name));

		if(v.parent)
		{
			put(t, mOutput, true);
			serialize(CrocValue(v.parent));
		}
		else
			put(t, mOutput, false);

		// TODO: this
		assert(false);
	}

	void serializeInstance(CrocInstance* v)
	{
		if(alreadyWritten(cast(CrocBaseObject*)v))
			return;

		tag(CrocValue.Type.Instance);
		serialize(CrocValue(v.parent));

		push(t, CrocValue(v));

		if(hasField(t, -1, "opSerialize"))
		{
			field(t, -1, "opSerialize");

			if(isFunction(t, -1))
			{
				put(t, mOutput, true);
				pop(t);
				pushNull(t);
				push(t, CrocValue(mStream));
				push(t, CrocValue(mSerializeFunc));
				methodCall(t, -4, "opSerialize", 0);
				return;
			}
			else if(isBool(t, -1))
			{
				if(!getBool(t, -1))
				{
					pushToString(t, -2, true);
					throwStdException(t, "ValueException", "Attempting to serialize '{}', whose opSerialize field is 'false'", getString(t, -1));
				}

				pop(t);
				// fall out, serialize literally.
			}
			else
			{
				pushToString(t, -2, true);
				pushTypeString(t, -2);
				throwStdException(t, "TypeException", "Attempting to serialize '{}', whose opSerialize is a '{}', not a bool or function", getString(t, -2), getString(t, -1));
			}
		}

		pop(t);
		put(t, mOutput, false);

		if(v.parent.finalizer)
		{
			push(t, CrocValue(v));
			pushToString(t, -1, true);
			throwStdException(t, "ValueException", "Attempting to serialize '{}', whose class has a finalizer", getString(t, -1));
		}

		// TODO: this
		assert(false);
	}

	void serializeNamespace(CrocNamespace* v)
	{
		if(alreadyWritten(cast(CrocBaseObject*)v))
			return;

		tag(CrocValue.Type.Namespace);
		serialize(CrocValue(v.name));

		if(v.parent is null)
			put(t, mOutput, false);
		else
		{
			put(t, mOutput, true);
			serialize(CrocValue(v.parent));
		}

		integer(v.data.length);

		foreach(key, ref val; v.data)
		{
			serialize(CrocValue(key));
			serialize(val);
		}
	}

	void serializeThread(CrocThread* v)
	{
    	if(alreadyWritten(cast(CrocBaseObject*)v))
    		return;

    	if(t is v)
    		throwStdException(t, "ValueException", "Attempting to serialize the currently-executing thread");

    	if(v.nativeCallDepth > 0)
    		throwStdException(t, "ValueException", "Attempting to serialize a thread with at least one native or metamethod call on its call stack");

		tag(CrocValue.Type.Thread);

		integer(v.savedCallDepth);
		integer(v.arIndex);

		foreach(ref rec; v.actRecs[0 .. v.arIndex])
		{
			integer(rec.base);
			integer(rec.savedTop);
			integer(rec.vargBase);
			integer(rec.returnSlot);

			if(rec.func is null)
				put(t, mOutput, false);
			else
			{
				put(t, mOutput, true);
				serialize(CrocValue(rec.func));
				uword diff = rec.pc - rec.func.scriptFunc.code.ptr;
				integer(diff);
			}

			integer(rec.numReturns);

			if(rec.proto)
			{
				put(t, mOutput, true);
				serialize(CrocValue(rec.proto));
			}
			else
				put(t, mOutput, false);

			integer(rec.numTailcalls);
			integer(rec.firstResult);
			integer(rec.numResults);
			integer(rec.unwindCounter);

			if(rec.unwindReturn)
			{
				put(t, mOutput, true);
				uword diff = rec.unwindReturn - rec.func.scriptFunc.code.ptr;
				integer(diff);
			}
			else
				put(t, mOutput, false);
		}

		integer(v.trIndex);

		foreach(ref rec; v.tryRecs[0 .. v.trIndex])
		{
			put(t, mOutput, rec.isCatch);
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

		put(t, mOutput, v.shouldHalt);

		if(v.coroFunc)
		{
			put(t, mOutput, true);
			serialize(CrocValue(v.coroFunc));
		}
		else
			put(t, mOutput, false);

		integer(v.state);
		integer(v.numYields);

		// TODO: hooks?!

		for(auto uv = t.upvalHead; uv !is null; uv = uv.nextuv)
		{
			assert(uv.value !is &uv.closedValue);
			serialize(CrocValue(cast(CrocBaseObject*)uv));
			uword diff = uv.value - v.stack.ptr;
			integer(diff);
		}

		tag(CrocValue.Type.Null);
	}

	void serializeWeakRef(CrocWeakRef* v)
	{
		if(alreadyWritten(cast(CrocBaseObject*)v))
			return;

		tag(CrocValue.Type.WeakRef);

		if(v.obj is null)
			put(t, mOutput, true);
		else
		{
			put(t, mOutput, false);
			serialize(CrocValue(v.obj));
		}
	}

	void serializeNativeObj(CrocNativeObj* v)
	{
		throwStdException(t, "TypeException", "Attempting to serialize a nativeobj. Please use the transients table.");
	}

	void writeRef(uword idx)
	{
		tag(Backref);
		integer(idx);
	}

	void addObject(CrocBaseObject* v)
	{
		*mObjTable.insert(t.vm.alloc, v) = mObjIndex++;
	}

	bool alreadyWritten(CrocValue v)
	{
		return alreadyWritten(v.mBaseObj);
	}

	bool alreadyWritten(CrocBaseObject* v)
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

struct Deserializer
{
private:
	CrocThread* t;
	InputStream mInput;
	CrocBaseObject*[] mObjTable;
	CrocTable* mTrans;
	CrocInstance* mStream;
	CrocFunction* mDeserializeFunc;

	static Deserializer opCall(CrocThread* t, InputStream input)
	{
		Deserializer ret;
		ret.t = t;
		ret.mInput = input;
		return ret;
	}

	static class Goober
	{
		Deserializer* d;
		this(Deserializer* d) { this.d = d; }
	}

	static uword deserializeFunc(CrocThread* t)
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
			throwStdException(t, "TypeException", "Transients table must be a table, not '{}'", getString(t, -1));
		}

		mTrans = getTable(t, trans);

		auto size = stackSize(t);
		t.vm.alloc.resizeArray(mObjTable, 0);

		disableGC(t.vm);

		scope(failure)
			setStackSize(t, size);

		scope(exit)
		{
			t.vm.alloc.resizeArray(mObjTable, 0);
			enableGC(t.vm);
		}

		// we leave these on the stack so they won't be collected, but we get 'real' references
		// to them so we can push them in opSerialize callbacks.
		importModuleNoNS(t, "stream");
		lookup(t, "stream.InStream");
		pushNull(t);
		pushNativeObj(t, cast(Object)mInput);
		pushBool(t, false);
		rawCall(t, -4, 1);
		mStream = getInstance(t, -1);

			pushNativeObj(t, new Goober(this));
		newFunction(t, 0, &deserializeFunc, "deserialize", 1);
		mDeserializeFunc = getFunction(t, -1);

		deserializeValue();
		insertAndPop(t, -3);
		maybeGC(t);

		return stackSize(t) - 1;
	}

	byte tag()
	{
		byte ret = void;
		get(t, mInput, ret);
		return ret;
	}

	long integer()()
	{
		byte v = void;
		get(t, mInput, v);

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
				get(t, mInput, v);
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
			case CrocValue.Type.Null:      deserializeNullImpl();      break;
			case CrocValue.Type.Bool:      deserializeBoolImpl();      break;
			case CrocValue.Type.Int:       deserializeIntImpl();       break;
			case CrocValue.Type.Float:     deserializeFloatImpl();     break;
			case CrocValue.Type.Char:      deserializeCharImpl();      break;
			case CrocValue.Type.String:    deserializeStringImpl();    break;
			case CrocValue.Type.Table:     deserializeTableImpl();     break;
			case CrocValue.Type.Array:     deserializeArrayImpl();     break;
			case CrocValue.Type.Memblock:  deserializeMemblockImpl();  break;
			case CrocValue.Type.Function:  deserializeFunctionImpl();  break;
			case CrocValue.Type.Class:     deserializeClassImpl();     break;
			case CrocValue.Type.Instance:  deserializeInstanceImpl();  break;
			case CrocValue.Type.Namespace: deserializeNamespaceImpl(); break;
			case CrocValue.Type.Thread:    deserializeThreadImpl();    break;
			case CrocValue.Type.WeakRef:   deserializeWeakrefImpl();   break;
			case CrocValue.Type.FuncDef:   deserializeFuncDefImpl();   break;
			case CrocValue.Type.Upvalue:   deserializeUpvalImpl();     break;

			case Serializer.Backref:     push(t, CrocValue(mObjTable[cast(uword)integer()])); break;

			case Serializer.Transient:
				push(t, CrocValue(mTrans));
				deserializeValue();
				idx(t, -2);
				insertAndPop(t, -2);
				break;

			default: throwStdException(t, "ValueException", "Malformed data");
		}
	}

	void checkTag(byte type)
	{
		if(tag() != type)
			throwStdException(t, "ValueException", "Malformed data");
	}

	void deserializeNull()
	{
		checkTag(CrocValue.Type.Null);
		deserializeNullImpl();
	}

	void deserializeNullImpl()
	{
		pushNull(t);
	}

	void deserializeBool()
	{
		checkTag(CrocValue.Type.Bool);
		deserializeBoolImpl();
	}

	void deserializeBoolImpl()
	{
		bool v = void;
		get(t, mInput, v);
		pushBool(t, v);
	}

	void deserializeInt()
	{
		checkTag(CrocValue.Type.Int);
		deserializeIntImpl();
	}

	void deserializeIntImpl()
	{
		pushInt(t, integer());
	}

	void deserializeFloat()
	{
		checkTag(CrocValue.Type.Float);
		deserializeFloatImpl();
	}

	void deserializeFloatImpl()
	{
		crocfloat v = void;
		get(t, mInput, v);
		pushFloat(t, v);
	}

	void deserializeChar()
	{
		checkTag(CrocValue.Type.Char);
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
			push(t, CrocValue(ret));
			return false;
		}
		else if(tmp == Serializer.Transient)
		{
			push(t, CrocValue(mTrans));
			deserializeValue();
			idx(t, -2);
			insertAndPop(t, -2);

			if(.type(t, -1) != type)
				throwStdException(t, "ValueException", "Invalid transient table");

			return false;
		}
		else
			throwStdException(t, "ValueException", "Malformed data");

		assert(false);
	}

	void deserializeString()
	{
		if(checkObjTag(CrocValue.Type.String))
			deserializeStringImpl();
	}

	void deserializeStringImpl()
	{
		auto len = integer();

		auto data = t.vm.alloc.allocArray!(char)(cast(uword)len);
		scope(exit) t.vm.alloc.freeArray(data);

		readExact(t, mInput, data);
		pushString(t, data);
		addObject(getValue(t, -1).mBaseObj);
	}

	void deserializeTable()
	{
		if(checkObjTag(CrocValue.Type.Table))
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
		if(checkObjTag(CrocValue.Type.Array))
			deserializeArrayImpl();
	}

	void deserializeArrayImpl()
	{
		auto arr = t.vm.alloc.allocate!(CrocArray);
		addObject(cast(CrocBaseObject*)arr);

		auto len = integer();
		auto v = newArray(t, cast(uword)len);

		for(uword i = 0; i < len; i++)
		{
			deserializeValue();
			idxai(t, v, cast(crocint)i);
		}
	}

	void deserializeMemblock()
	{
		if(checkObjTag(CrocValue.Type.Memblock))
			deserializeMemblockImpl();
	}

	void deserializeMemblockImpl()
	{
		newMemblock(t, cast(uword)integer());
  		addObject(getValue(t, -1).mBaseObj);
  		insertAndPop(t, -2);
  		readExact(t, mInput, getMemblock(t, -1).data);
	}

	void deserializeFunction()
	{
		if(checkObjTag(CrocValue.Type.Function))
			deserializeFunctionImpl();
	}

	void deserializeFunctionImpl()
	{
		auto numUpvals = cast(uword)integer();
		auto func = t.vm.alloc.allocate!(CrocFunction)(func.ScriptClosureSize(numUpvals));
		addObject(cast(CrocBaseObject*)func);
		// Future Me: if this causes some kind of horrible bug down the road, feel free to come back in time
		// and beat the shit out of me. But since you haven't yet, I'm guessing that it doesn't. So ha.
		func.maxParams = cast(uword)integer();

		func.isNative = false;
		func.numUpvals = numUpvals;
		deserializeString();
		func.name = getStringObj(t, -1);
		pop(t);
		deserializeFuncDef();
		func.scriptFunc = getValue(t, -1).mFuncDef;
		pop(t);

		bool haveEnv;
		get(t, mInput, haveEnv);

		if(haveEnv)
			deserializeNamespace();
		else
			pushGlobal(t, "_G");

		func.environment = getNamespace(t, -1);
		pop(t);

		foreach(ref val; func.scriptUpvals())
		{
			deserializeUpval();
			val = cast(CrocUpval*)getValue(t, -1).mBaseObj;
			pop(t);
		}

		push(t, CrocValue(func));
	}

	void deserializeUpval()
	{
		if(checkObjTag(CrocValue.Type.Upvalue))
			deserializeUpvalImpl();
	}

	void deserializeUpvalImpl()
	{
		auto uv = t.vm.alloc.allocate!(CrocUpval)();
		addObject(cast(CrocBaseObject*)uv);
		uv.value = &uv.closedValue;
		deserializeValue();
		uv.closedValue = *getValue(t, -1);
		pop(t);
		push(t, CrocValue(cast(CrocBaseObject*)uv));
	}

	void deserializeFuncDef()
	{
		if(checkObjTag(CrocValue.Type.FuncDef))
			deserializeFuncDefImpl();
	}

	void deserializeFuncDefImpl()
	{
		auto def = t.vm.alloc.allocate!(CrocFuncDef);
		addObject(cast(CrocBaseObject*)def);

		deserializeString();
		def.locFile = getStringObj(t, -1);
		pop(t);
		integer(def.locLine);
		integer(def.locCol);
		get(t, mInput, def.isVararg);
		deserializeString();
		def.name = getStringObj(t, -1);
		pop(t);
		integer(def.numParams);
		t.vm.alloc.resizeArray(def.paramMasks, cast(uword)integer());

		foreach(ref mask; def.paramMasks)
			integer(mask);

		integer(def.numUpvals);

		t.vm.alloc.resizeArray(def.upvals, cast(uword)integer());

		foreach(ref uv; def.upvals)
		{
			get(t, mInput, uv.isUpvalue);
			integer(uv.index);
		}

		integer(def.stackSize);
		t.vm.alloc.resizeArray(def.innerFuncs, cast(uword)integer());

		foreach(ref func; def.innerFuncs)
		{
			deserializeFuncDef();
			func = getValue(t, -1).mFuncDef;
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
		readExact(t, mInput, def.code);

		bool haveEnvironment;
		get(t, mInput, haveEnvironment);

		if(haveEnvironment)
		{
			deserializeNamespace();
			def.environment = getNamespace(t, -1);
			pop(t);
		}
		else
			def.environment = null;

		bool haveCached;
		get(t, mInput, haveCached);

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
		readExact(t, mInput, def.lineInfo);

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

		push(t, CrocValue(cast(CrocBaseObject*)def));
	}

	void deserializeClass()
	{
		if(checkObjTag(CrocValue.Type.Class))
			deserializeClassImpl();
	}

	void deserializeClassImpl()
	{
    	auto cls = t.vm.alloc.allocate!(CrocClass)();
    	addObject(cast(CrocBaseObject*)cls);

    	deserializeString();
		cls.name = getStringObj(t, -1);
		pop(t);

		bool haveParent;
		get(t, mInput, haveParent);

		if(haveParent)
		{
			deserializeClass();
			cls.parent = getClass(t, -1);
			pop(t);
		}
		else
			cls.parent = null;

		deserializeNamespace();
		// TODO: this
		assert(false);

		/* pop(t);

		assert(!cls.parent || cls.fields.parent);

		push(t, CrocValue(cls)); */
	}

	void deserializeInstance()
	{
		if(checkObjTag(CrocValue.Type.Instance))
			deserializeInstanceImpl();
	}

	void deserializeInstanceImpl()
	{
		deserializeClass();
		auto parent = getClass(t, -1);
		auto inst = t.vm.alloc.allocate!(CrocInstance)(instance.InstanceSize(parent));
		pop(t);
		addObject(cast(CrocBaseObject*)inst);

		bool isSpecial;
		get(t, mInput, isSpecial);

		if(isSpecial)
		{
			push(t, CrocValue(inst));

			if(!hasMethod(t, -1, "opDeserialize"))
			{
				pushToString(t, -1, true);
				throwStdException(t, "ValueException", "'{}' was serialized with opSerialize, but does not have a matching opDeserialize", getString(t, -1));
			}

			pushNull(t);
			push(t, CrocValue(mStream));
			push(t, CrocValue(mDeserializeFunc));
			methodCall(t, -4, "opDeserialize", 0);
		}
		else
		{
			// TODO: this
			assert(false);
		}

		push(t, CrocValue(inst));
	}

	void deserializeNamespace()
	{
		if(checkObjTag(CrocValue.Type.Namespace))
			deserializeNamespaceImpl();
	}

	void deserializeNamespaceImpl()
	{
		auto ns = t.vm.alloc.allocate!(CrocNamespace);
		addObject(cast(CrocBaseObject*)ns);

		deserializeString();
		ns.name = getStringObj(t, -1);
		pop(t);
		push(t, CrocValue(ns));

		bool haveParent;
		get(t, mInput, haveParent);

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
		if(checkObjTag(CrocValue.Type.Thread))
			deserializeThreadImpl();
	}

	void deserializeThreadImpl()
	{
		auto ret = t.vm.alloc.allocate!(CrocThread);
		addObject(cast(CrocBaseObject*)ret);
		ret.vm = t.vm;
		integer(ret.savedCallDepth);
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
			get(t, mInput, haveFunc);

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
			get(t, mInput, haveProto);

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
			get(t, mInput, haveUnwindRet);

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
			get(t, mInput, rec.isCatch);
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

		get(t, mInput, ret.shouldHalt);

		bool haveCoroFunc;
		get(t, mInput, haveCoroFunc);

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

			auto uv = cast(CrocUpval*)getValue(t, -1).mBaseObj;
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
		if(checkObjTag(CrocValue.Type.WeakRef))
			deserializeWeakrefImpl();
	}

	void deserializeWeakrefImpl()
	{
		auto wr = t.vm.alloc.allocate!(CrocWeakRef);
		wr.obj = null;
		addObject(cast(CrocBaseObject*)wr);

		bool isNull;
		get(t, mInput, isNull);

		if(!isNull)
		{
			deserializeValue();
			wr.obj = getValue(t, -1).mBaseObj;
			pop(t);
			*t.vm.weakRefTab.insert(t.vm.alloc, wr.obj) = wr;
		}

		push(t, CrocValue(wr));
	}

	void addObject(CrocBaseObject* v)
	{
		t.vm.alloc.resizeArray(mObjTable, mObjTable.length + 1);
		mObjTable[$ - 1] = v;
	}
}

void get(T)(CrocThread* t, InputStream i, ref T ret)
{
	if(i.read(cast(void[])(&ret)[0 .. 1]) != T.sizeof)
		throwStdException(t, "IOException", "End of stream while reading");
}

void put(T)(CrocThread* t, OutputStream o, T val)
{
	if(o.write(cast(void[])(&val)[0 .. 1]) != T.sizeof)
		throwStdException(t, "IOException", "End of stream while writing");
}

void readExact(CrocThread* t, InputStream i, void[] dest)
{
	if(i.read(dest) != dest.length)
		throwStdException(t, "IOException", "End of stream while reading");
}

void append(CrocThread* t, OutputStream o, void[] val)
{
	if(o.write(val) != val.length)
		throwStdException(t, "IOException", "End of stream while writing");
}