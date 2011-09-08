/******************************************************************************
This module contains the simple serialization functions, used to dump compiled
modules to files. Might go.

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

module croc.serialization_simple;

import tango.core.Exception;
import tango.io.model.IConduit;

import croc.api_interpreter;
import croc.api_stack;
import croc.base_opcodes;
import croc.types;
import croc.types_funcdef;
import croc.utils;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

/**
Serializes the function object at the given index into the provided writer as a module. Serializing a function as a module
outputs the platform-dependent Croc module header before outputting the function, so that upon subsequent loads of the module,
the platform can be correctly detected.

Params:
	idx = The stack index of the function object to serialize. The function must be a script function with no upvalues.
	s = The writer object to be used to serialize the function.
*/
void serializeModule(CrocThread* t, word idx, OutputStream s)
{
	auto func = getFuncDef(t, idx);

	if(func is null)
	{
		pushTypeString(t, idx);
		throwStdException(t, "TypeException", "serializeModule - 'funcdef' expected, not '{}'", getString(t, -1));
	}

	if(func.numUpvals > 0)
		throwStdException(t, "ValueException", "serializeModule - function '{}' is not eligible for serialization", func.name.toString());

	serializeAsModule(func, s);
}

/**
Inverse of the above, which means it expects for there to be a module header at the beginning of the stream. If the module
header of the stream does not match the module header for the platform that is loading the module, the load will fail.
A closure of the deserialized function is created with the current environment as its environment and is pushed onto the
given thread's stack.

Params:
	s = The reader object that holds the data stream from which the function will be deserialized.
*/
word deserializeModule(CrocThread* t, InputStream s)
{
	return push(t, CrocValue(deserializeAsModule(t, s)));
}

/**
Same as serializeModule but does not output the module header.
*/
void serializeFunction(CrocThread* t, word idx, OutputStream s)
{
	auto func = getFunction(t, idx);

	if(func is null)
	{
		pushTypeString(t, idx);
		throwStdException(t, "TypeException", "serializeFunction - 'function' expected, not '{}'", getString(t, -1));
	}

	if(func.isNative || func.scriptFunc.numUpvals > 0)
		throwStdException(t, "ValueException", "serializeFunction - function '{}' is not eligible for serialization", func.name.toString());

	serialize(func.scriptFunc, s);
}

/**
Same as deserializeModule but does not expect for there to be a module header.
*/
word deserializeFunction(CrocThread* t, InputStream s)
{
	return push(t, CrocValue(deserialize(t, s)));
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

void get(T)(InputStream i, ref T ret)
{
	if(i.read(cast(void[])(&ret)[0 .. 1]) != T.sizeof)
		throw new IOException("End of stream while reading");
}

void put(T)(OutputStream o, T val)
{
	if(o.write(cast(void[])(&val)[0 .. 1]) != T.sizeof)
		throw new IOException("End of stream while writing");
}

void readExact(InputStream i, void[] dest)
{
	if(i.read(dest) != dest.length)
		throw new IOException("End of stream while reading");
}

void append(OutputStream o, void[] val)
{
	if(o.write(val) != val.length)
		throw new IOException("End of stream while writing");
}

align(1) struct FileHeader
{
	uint magic = FOURCC!("MinD");
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

void serializeAsModule(CrocFuncDef* fd, OutputStream s)
{
	append(s, (&FileHeader.init)[0 .. 1]);
	serialize(fd, s);
}

CrocFuncDef* deserializeAsModule(CrocThread* t, InputStream s)
{
	FileHeader fh = void;
	readExact(s, (&fh)[0 .. 1]);

	if(fh != FileHeader.init)
		throwStdException(t, "ValueException", "Serialized module header mismatch");

	return deserialize(t, s);
}

void serialize(CrocFuncDef* fd, OutputStream s)
{
	put(s, fd.location.line);
	put(s, fd.location.col);
	Serialize(s, fd.location.file);

	put(s, fd.isVararg);
	Serialize(s, fd.name);
	put(s, fd.numParams);
	Serialize(s, fd.paramMasks);
	put(s, fd.numUpvals);
	put(s, fd.stackSize);

	Serialize(s, fd.constants);
	Serialize(s, fd.code);
	Serialize(s, fd.lineInfo);

	Serialize(s, fd.upvalNames);

	put(s, fd.locVarDescs.length);

	foreach(ref desc; fd.locVarDescs)
	{
		Serialize(s, desc.name);
		put(s, desc.pcStart);
		put(s, desc.pcEnd);
		put(s, desc.reg);
	}

	put(s, fd.switchTables.length);

	foreach(ref st; fd.switchTables)
	{
		put(s, st.offsets.length);

		foreach(ref k, v; st.offsets)
		{
			Serialize(s, k);
			put(s, v);
		}

		put(s, st.defaultOffset);
	}

	put(s, fd.innerFuncs.length);

	foreach(inner; fd.innerFuncs)
		serialize(inner, s);
}

CrocFuncDef* deserialize(CrocThread* t, InputStream s)
{
	auto vm = t.vm;

	auto ret = funcdef.create(vm.alloc);

	get(s, ret.location.line);
	get(s, ret.location.col);
	Deserialize(t, s, ret.location.file);

	get(s, ret.isVararg);
	Deserialize(t, s, ret.name);
	get(s, ret.numParams);
	Deserialize(t, s, ret.paramMasks);
	get(s, ret.numUpvals);
	get(s, ret.stackSize);

	Deserialize(t, s, ret.constants);
	Deserialize(t, s, ret.code);

	Deserialize(t, s, ret.lineInfo);
	Deserialize(t, s, ret.upvalNames);

	uword len = void;
	get(s, len);
	ret.locVarDescs = vm.alloc.allocArray!(CrocFuncDef.LocVarDesc)(len);

	foreach(ref desc; ret.locVarDescs)
	{
		Deserialize(t, s, desc.name);
		get(s, desc.pcStart);
		get(s, desc.pcEnd);
		get(s, desc.reg);
	}

	get(s, len);
	ret.switchTables = vm.alloc.allocArray!(CrocFuncDef.SwitchTable)(len);

	foreach(ref st; ret.switchTables)
	{
		get(s, len);

		for(uword i = 0; i < len; i++)
		{
			CrocValue key = void;
			word value = void;

			Deserialize(t, s, key);
			get(s, value);

			*st.offsets.insert(vm.alloc, key) = value;
		}

		get(s, st.defaultOffset);
	}

	get(s, len);
	ret.innerFuncs = vm.alloc.allocArray!(CrocFuncDef*)(len);

	foreach(ref inner; ret.innerFuncs)
		inner = deserialize(t, s);

	return ret;
}

void Serialize(OutputStream s, CrocString* val)
{
	auto data = val.toString();
	put(s, data.length);
	append(s, data);
}

void Serialize(OutputStream s, ushort[] val)
{
	put(s, val.length);
	append(s, val);
}

void Serialize(OutputStream s, CrocValue[] val)
{
	put(s, val.length);

	foreach(ref v; val)
		Serialize(s, v);
}

void Serialize(OutputStream s, Instruction[] val)
{
	put(s, val.length);
	append(s, val);
}

void Serialize(OutputStream s, uint[] val)
{
	put(s, val.length);
	append(s, val);
}

void Serialize(OutputStream s, CrocString*[] val)
{
	put(s, val.length);

	foreach(v; val)
		Serialize(s, v);
}

void Serialize(OutputStream s, ref CrocValue val)
{
	put(s, cast(uint)val.type);

	switch(val.type)
	{
		case CrocValue.Type.Null:   break;
		case CrocValue.Type.Bool:   put(s, val.mBool); break;
		case CrocValue.Type.Int:    put(s, val.mInt); break;
		case CrocValue.Type.Float:  put(s, val.mFloat); break;
		case CrocValue.Type.Char:   put(s, val.mChar); break;
		case CrocValue.Type.String: Serialize(s, val.mString); break;
		default: assert(false, "Serialize(CrocValue)");
	}
}

void Deserialize(CrocThread* t, InputStream s, ref CrocString* val)
{
	uword len = void;
	get(s, len);

	auto data = t.vm.alloc.allocArray!(char)(len);
	scope(exit) t.vm.alloc.freeArray(data);
	
	readExact(s, data);
	val = createString(t, data);
}

void Deserialize(CrocThread* t, InputStream s, ref ushort[] val)
{
	uword len = void;
	get(s, len);

	val = t.vm.alloc.allocArray!(ushort)(len);
	readExact(s, val);
}

void Deserialize(CrocThread* t, InputStream s, ref CrocValue[] val)
{
	uword len = void;
	get(s, len);

	val = t.vm.alloc.allocArray!(CrocValue)(len);

	foreach(ref v; val)
		Deserialize(t, s, v);
}

void Deserialize(CrocThread* t, InputStream s, ref Instruction[] val)
{
	uword len = void;
	get(s, len);

	val = t.vm.alloc.allocArray!(Instruction)(len);
	readExact(s, val);
}

void Deserialize(CrocThread* t, InputStream s, ref uint[] val)
{
	uword len = void;
	get(s, len);

	val = t.vm.alloc.allocArray!(uint)(len);
	readExact(s, val);
}

void Deserialize(CrocThread* t, InputStream s, ref CrocString*[] val)
{
	uword len = void;
	get(s, len);

	val = t.vm.alloc.allocArray!(CrocString*)(len);

	foreach(ref v; val)
		Deserialize(t, s, v);
}

void Deserialize(CrocThread* t, InputStream s, ref CrocValue val)
{
	uint type = void;
	get(s, type);
	val.type = cast(CrocValue.Type)type;

	switch(val.type)
	{
		case CrocValue.Type.Null:   break;
		case CrocValue.Type.Bool:   get(s, val.mBool); break;
		case CrocValue.Type.Int:    get(s, val.mInt); break;
		case CrocValue.Type.Float:  get(s, val.mFloat); break;
		case CrocValue.Type.Char:   get(s, val.mChar); break;
		case CrocValue.Type.String: Deserialize(t, s, val.mString); break;
		default: assert(false, "Deserialize(CrocValue)");
	}
}