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

import minid.func;
import minid.funcdef;
import minid.hash;
import minid.interpreter;
import minid.namespace;
import minid.opcodes;
import minid.string;
import minid.types;
import minid.utils;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void serializeGraph(MDThread* t, word idx, word intrans, IWriter output)
{
	auto s = Serializer(t, output);
	s.writeGraph(idx, intrans);
}

void serializeGraph(MDThread* t, word idx, word intrans, OutputStream output)
{
	auto s = Serializer(t, output);
	s.writeGraph(idx, intrans);
}

struct Serializer
{
private:
	MDThread* t;
	IWriter mOutput;
	Hash!(MDBaseObject*, uword) mObjTable;
	uword mObjIndex;
	word mIntrans;

	enum
	{
		Backref = -1,
		Intransient = -2
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

	void writeGraph(word value, word intrans)
	{
		if(opis(t, value, intrans))
			throwException(t, "Object to serialize is the same as the intransients table");

		if(!isTable(t, intrans))
		{
			pushTypeString(t, intrans);
			throwException(t, "Intransients table must be a table, not '{}'", getString(t, -1));
		}

		mIntrans = absIndex(t, intrans);
		auto v = *getValue(t, value);

		commonSerialize
		({
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
		// check to see if it's an intransient value
		push(t, v);
		idx(t, mIntrans);

		if(!isNull(t, -1))
		{
			tag(Intransient);
			serialize(*getValue(t, -1));
			pop(t);
			return;
		}

		pop(t);

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

		assert(v.value is &v.closedValue, "FFFFFFFUUUUUUUUUU");

		tag(MDValue.Type.Upvalue);
		serialize(v.closedValue);
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

	void serializeClass(MDClass* v) { assert(false); }
	void serializeInstance(MDInstance* v) { assert(false); }

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

	void serializeThread(MDThread* v) { assert(false); }

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

	void serializeNativeObj(MDNativeObj* v) { assert(false); }

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

word deserializeGraph(MDThread* t, word intrans, InputStream input)
{
	auto d = Deserializer(t, input);
	return d.readGraph(intrans);
}

struct Deserializer
{
private:
	MDThread* t;
	IReader mInput;
	MDBaseObject*[] mObjTable;
	word mIntrans;

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

	word readGraph(word intrans)
	{
		if(!isTable(t, intrans))
		{
			pushTypeString(t, intrans);
			throwException(t, "Intransients table must be a table, not '{}'", getString(t, -1));
		}
		
		mIntrans = absIndex(t, intrans);

		commonDeserialize
		({
			deserializeValue();
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

			return ret;
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
			case MDValue.Type.NativeObj: deserializeNativeObjImpl(); break;

			case Serializer.Backref:     push(t, MDValue(mObjTable[cast(uword)integer()])); break;
			case Serializer.Intransient: deserializeValue(); idx(t, mIntrans); break;

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
		else if(tmp == Serializer.Intransient)
		{
			deserializeValue();
			idx(t, mIntrans);

			if(.type(t, -1) != type)
				throwException(t, "Invalid invariant table");

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

	void deserializeClassImpl() { assert(false); }
	
	void deserializeInstance()
	{
		if(checkObjTag(MDValue.Type.Instance))
			deserializeInstanceImpl();
	}

	void deserializeInstanceImpl() { assert(false); }

	void deserializeNamespace()
	{
		if(checkObjTag(MDValue.Type.Namespace))
			deserializeNamespaceImpl();
	}

	void deserializeNamespaceImpl()
	{
		deserializeString();
		auto ns = namespace.create(t.vm.alloc, getStringObj(t, -1));
		addObject(cast(MDBaseObject*)ns);
		pushNamespace(t, ns);
		insertAndPop(t, -2);

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

	void deserializeThreadImpl() { assert(false); }

	void deserializeWeakref()
	{
		if(checkObjTag(MDValue.Type.WeakRef))
			deserializeWeakrefImpl();
	}

	void deserializeWeakrefImpl()
	{
		bool isNull;
		mInput.get(isNull);

		if(isNull)
		{
			auto wr = t.vm.alloc.allocate!(MDWeakRef);
			wr.obj = null;
			push(t, MDValue(cast(MDBaseObject*)wr));
		}
		else
		{
			deserializeValue();
			pushWeakRef(t, -1);
			insertAndPop(t, -2);
		}
	}

	void deserializeNativeObj()
	{
		if(checkObjTag(MDValue.Type.NativeObj))
			deserializeNativeObjImpl();
	}

	void deserializeNativeObjImpl() { assert(false); }

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