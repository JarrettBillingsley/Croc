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

struct Serializer
{
private:
	MDThread* t;
	IWriter mOutput;
	Hash!(MDBaseObject*, uword) mObjTable;
	uword mObjIndex;

	enum
	{
		Backref = -1
	}

public:
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

	void writeGraph(word value)
	{
		auto v = *getValue(t, value);

		commonSerialize
		({
			serializeValue(v);
		});
		
		mOutput.flush();
	}

	void writeModule(word idx)
	{
		assert(false);
	}
	
	void writeFunction(word idx)
	{
		assert(false);
	}

private:
	void commonSerialize(void delegate() dg)
	{
		auto size = stackSize(t);

		mObjTable.clear(t.vm.alloc);
		mObjIndex = 1;

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
			numBytes = (bsr(cast(uint)(v & 0xFFFF_FFFF)) / 8) + 1;

		mOutput.put(cast(ubyte)(neg ? numBytes | 0x80 : numBytes));

		while(v)
		{
			mOutput.put(cast(ubyte)(v & 0xFF));
			v >>>= 8;
		}
	}

	void serializeValue(MDValue v)
	{
		switch(v.type)
		{
			case MDValue.Type.Null:      serializeNull();          break;
			case MDValue.Type.Bool:      serializeBool(v.mBool);   break;
			case MDValue.Type.Int:       serializeInt(v.mInt);     break;
			case MDValue.Type.Float:     serializeFloat(v.mFloat); break;
			case MDValue.Type.Char:      serializeChar(v.mChar);   break;

			case MDValue.Type.String:    if(!alreadyWritten(v)) serializeString(v.mString);       break;
			case MDValue.Type.Table:     if(!alreadyWritten(v)) serializeTable(v.mTable);         break;
			case MDValue.Type.Array:     if(!alreadyWritten(v)) serializeArray(v.mArray);         break;
			case MDValue.Type.Function:  if(!alreadyWritten(v)) serializeFunction(v.mFunction);   break;
			case MDValue.Type.Class:     if(!alreadyWritten(v)) serializeClass(v.mClass);         break;
			case MDValue.Type.Instance:  if(!alreadyWritten(v)) serializeInstance(v.mInstance);   break;
			case MDValue.Type.Namespace: if(!alreadyWritten(v)) serializeNamespace(v.mNamespace); break;
			case MDValue.Type.Thread:    if(!alreadyWritten(v)) serializeThread(v.mThread);       break;
			case MDValue.Type.WeakRef:   if(!alreadyWritten(v)) serializeWeakref(v.mWeakRef);     break;
			case MDValue.Type.NativeObj: if(!alreadyWritten(v)) serializeNativeObj(v.mNativeObj); break;

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
		tag(MDValue.Type.String);

		auto data = v.toString();
		integer(data.length);
		mOutput.buffer.append(data.ptr, data.length * char.sizeof);
	}

	void serializeTable(MDTable* v)
	{
		tag(MDValue.Type.Table);
		integer(v.data.length);

		foreach(ref key, ref val; v.data)
		{
			serializeValue(key);
			serializeValue(val);
		}
	}

	void serializeArray(MDArray* v)
	{
		tag(MDValue.Type.Array);

		if(!alreadyWritten(cast(MDBaseObject*)v.data))
			serializeArrayData(v.data);

		integer(cast(uword)(v.slice.ptr - v.data.toArray().ptr));
		integer(v.slice.length);
		mOutput.put(v.isSlice);
	}

	void serializeArrayData(MDArrayData* v)
	{
		tag(MDValue.Type.ArrayData);
		integer(v.length);

		foreach(ref val; v.toArray())
			serializeValue(val);
	}

	void serializeFunction(MDFunction* v) { assert(false); }
	void serializeClass(MDClass* v) { assert(false); }
	void serializeInstance(MDInstance* v) { assert(false); }

	void serializeNamespace(MDNamespace* v)
	{
		tag(MDValue.Type.Namespace);
		
		if(!alreadyWritten(MDValue(v.name)))
			serializeString(v.name);
		
		if(v.parent is null)
			serializeNull();
		else if(!alreadyWritten(cast(MDBaseObject*)v.parent))
			serializeNamespace(v.parent);

		integer(v.data.length);

		foreach(key, ref val; v.data)
		{
			if(!alreadyWritten(MDValue(key)))
				serializeString(key);

			serializeValue(val);
		}
	}

	void serializeThread(MDThread* v) { assert(false); }
	void serializeWeakref(MDWeakRef* v) { assert(false); }
	void serializeNativeObj(MDNativeObj* v) { assert(false); }

	uword objIndex(MDBaseObject* v)
	{
		if(auto idx = mObjTable.lookup(v))
			return *idx;
		else
			return 0;
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
		if(auto r = objIndex(v))
		{
			writeRef(r);
			return true;
		}

		addObject(v);
		return false;
	}
}

struct Deserializer
{
private:
	MDThread* t;
	IReader mInput;
	MDBaseObject*[] mObjTable;

public:
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
	
	word readGraph()
	{
		commonDeserialize
		({
			deserializeValue();
		});

		return stackSize(t) - 1;
	}

	word readModule()
	{
		assert(false);
	}

	word readFunction()
	{
		assert(false);
	}

private:
	void commonDeserialize(void delegate() dg)
	{
		auto size = stackSize(t);
		t.vm.alloc.resizeArray(mObjTable, 0);

		scope(exit)
		{
			setStackSize(t, size);
			t.vm.alloc.resizeArray(mObjTable, 0);
		}

		dg();
	}

	byte tag()
	{
		byte ret = void;
		mInput.get(ret);
		return ret;
	}

	long integer()
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

	void deserializeValue()
	{
		switch(tag())
		{
			case MDValue.Type.Null:      deserializeNull();  break;
			case MDValue.Type.Bool:      deserializeBool();  break;
			case MDValue.Type.Int:       deserializeInt();   break;
			case MDValue.Type.Float:     deserializeFloat(); break;
			case MDValue.Type.Char:      deserializeChar();  break;

			case MDValue.Type.String:    deserializeString();    break;
			case MDValue.Type.Table:     deserializeTable();     break;
			case MDValue.Type.Array:     deserializeArray();     break;
			case MDValue.Type.Function:  deserializeFunction();  break;
			case MDValue.Type.Class:     deserializeClass();     break;
			case MDValue.Type.Instance:  deserializeInstance();  break;
			case MDValue.Type.Namespace: deserializeNamespace(); break;
			case MDValue.Type.Thread:    deserializeThread();    break;
			case MDValue.Type.WeakRef:   deserializeWeakref();   break;
			case MDValue.Type.NativeObj: deserializeNativeObj(); break;

			case Serializer.Backref: push(t, MDValue(mObjTable[cast(uword)integer() - 1])); break;

			default: throwException(t, "Malformed data");
		}
	}

	void deserializeNull()
	{
		pushNull(t);
	}

	void deserializeBool()
	{
		bool v = void;
		mInput.get(v);
		pushBool(t, v);
	}

	void deserializeInt()
	{
		pushInt(t, integer());
	}

	void deserializeFloat()
	{
		mdfloat v = void;
		mInput.get(v);
		pushFloat(t, v);
	}

	void deserializeChar()
	{
		pushChar(t, cast(dchar)integer());
	}

	void deserializeString()
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
		auto arr = t.vm.alloc.allocate!(MDArray);
		addObject(cast(MDBaseObject*)arr);

		auto data = deserializeArrayData();

		arr.data = data;

		auto lo = cast(uword)integer();
		auto hi = cast(uword)integer();
		arr.slice = data.toArray()[lo .. hi];

		mInput.get(arr.isSlice);

		pushArray(t, arr);
	}

	MDArrayData* deserializeArrayData()
	{
		switch(tag())
		{
			case MDValue.Type.ArrayData: break;
			case Serializer.Backref: return cast(MDArrayData*)mObjTable[cast(uword)integer() - 1];
			default: throwException(t, "Malformed data");
		}

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

	void deserializeFunction() { assert(false); }
	void deserializeClass() { assert(false); }
	void deserializeInstance() { assert(false); }

	void deserializeNamespace()
	{
		switch(tag())
		{
			case MDValue.Type.String: deserializeString(); break;
			case Serializer.Backref: push(t, MDValue(mObjTable[cast(uword)integer() - 1])); break;
			default: throwException(t, "Malformed data");
		}

		auto ns = namespace.create(t.vm.alloc, getStringObj(t, -1));
		addObject(cast(MDBaseObject*)ns);

		pushNamespace(t, ns);
		insertAndPop(t, -2);

		switch(tag())
		{
			case MDValue.Type.Null:
				ns.parent = null;
				break;

			case MDValue.Type.Namespace:
				deserializeNamespace();
				ns.parent = getNamespace(t, -1);
				pop(t);
				break;

			case Serializer.Backref:
				ns.parent = cast(MDNamespace*)mObjTable[cast(uword)integer() - 1];
				break;

			default:
				throwException(t, "Malformed data");
		}

		auto len = cast(uword)integer();

		for(uword i = 0; i < len; i++)
		{
			switch(tag())
			{
				case MDValue.Type.String: deserializeString(); break;
				case Serializer.Backref: push(t, MDValue(mObjTable[cast(uword)integer() - 1])); break;
				default: throwException(t, "Malformed data");
			}

			deserializeValue();
			fielda(t, -3);
		}
	}

	void deserializeThread() { assert(false); }
	void deserializeWeakref() { assert(false); }
	void deserializeNativeObj() { assert(false); }

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