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

import tango.io.protocol.model.IReader;
import tango.io.protocol.model.IWriter;

import minid.func;
import minid.funcdef;
import minid.interpreter;
import minid.opcodes;
import minid.string;
import minid.types;
import minid.utils;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

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