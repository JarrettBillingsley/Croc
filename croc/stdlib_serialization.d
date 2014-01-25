/******************************************************************************
This module contains the Croc 'serialization' standard library.

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

module croc.stdlib_serialization;

import tango.io.model.IConduit;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_library;
import croc.serialization;
import croc.stdlib_stream;
import croc.types;
import croc.utils;

// =====================================================================================================================
// Public
// =====================================================================================================================

public:

void initSerializationLib(CrocThread* t)
{
	newTable(t);
		newTable(t);
			pushInt(t, 254);                      fielda(t, -2, "transient");
			pushInt(t, 255);                      fielda(t, -2, "backref");

			pushInt(t, CrocValue.Type.Null);      fielda(t, -2, "null");
			pushInt(t, CrocValue.Type.Bool);      fielda(t, -2, "bool");
			pushInt(t, CrocValue.Type.Int);       fielda(t, -2, "int");
			pushInt(t, CrocValue.Type.Float);     fielda(t, -2, "float");

			pushInt(t, CrocValue.Type.NativeObj); fielda(t, -2, "nativeobj");
			pushInt(t, CrocValue.Type.String);    fielda(t, -2, "string");
			pushInt(t, CrocValue.Type.WeakRef);   fielda(t, -2, "weakref");

			pushInt(t, CrocValue.Type.Table);     fielda(t, -2, "table");
			pushInt(t, CrocValue.Type.Namespace); fielda(t, -2, "namespace");
			pushInt(t, CrocValue.Type.Array);     fielda(t, -2, "array");
			pushInt(t, CrocValue.Type.Memblock);  fielda(t, -2, "memblock");
			pushInt(t, CrocValue.Type.Function);  fielda(t, -2, "function");
			pushInt(t, CrocValue.Type.FuncDef);   fielda(t, -2, "funcdef");
			pushInt(t, CrocValue.Type.Class);     fielda(t, -2, "class");
			pushInt(t, CrocValue.Type.Instance);  fielda(t, -2, "instance");
			pushInt(t, CrocValue.Type.Thread);    fielda(t, -2, "thread");

			pushInt(t, CrocValue.Type.Upvalue);   fielda(t, -2, "upvalue");
		fielda(t, -2, "TypeTags");

		newTable(t);
			registerFields(t, _serializeFuncs);
		fielda(t, -2, "ExtraSerializeMethods");

		newTable(t);
			registerFields(t, _deserializeFuncs);
		fielda(t, -2, "ExtraDeserializeMethods");

		version(BigEndian)
			pushInt(t, 1);
		else
			pushInt(t, 0);

		fielda(t, -2, "Endianness");

		pushInt(t, uword.sizeof * 8);
		fielda(t, -2, "PlatformBits");
	newGlobal(t, "_serializationtmp");

	importModuleFromStringNoNS(t, "serialization", Code, __FILE__);

	pushGlobal(t, "_G");
	pushString(t, "_serializationtmp");
	removeKey(t, -2);
	pop(t);
}

// =====================================================================================================================
// Private
// =====================================================================================================================

private:

align(1) struct FileHeader
{
	uint magic = FOURCC!("Croc");
}

const RegisterFunc[] _serializeFuncs =
[
	{"_nativeSerializeFunction", &Ser._nativeSerializeFunction, maxParams: 1},
	{"_nativeSerializeFuncdef",  &Ser._nativeSerializeFuncdef,  maxParams: 1},
	{"_nativeSerializeClass",    &Ser._nativeSerializeClass,    maxParams: 1},
	{"_nativeSerializeInstance", &Ser._nativeSerializeInstance, maxParams: 1},
	{"_nativeSerializeThread",   &Ser._nativeSerializeThread,   maxParams: 1},
	{"_serializeUpvalue",        &Ser._serializeUpvalue,        maxParams: 1},
	{"_instSize",                &Ser._instSize,                maxParams: 1},
];

const RegisterFunc[] _deserializeFuncs =
[
	{"_deserializeNamespaceImpl", &Deser._deserializeNamespaceImpl, maxParams: 0},
	{"_deserializeFunctionImpl",  &Deser._deserializeFunctionImpl,  maxParams: 0},
	{"_deserializeFuncdefImpl",   &Deser._deserializeFuncdefImpl,   maxParams: 0},
	{"_deserializeClassImpl",     &Deser._deserializeClassImpl,     maxParams: 0},
	{"_deserializeInstanceImpl",  &Deser._deserializeInstanceImpl,  maxParams: 0},
	{"_deserializeThreadImpl",    &Deser._deserializeThreadImpl,    maxParams: 0},
	{"_deserializeUpvalueImpl",   &Deser._deserializeUpvalueImpl,   maxParams: 0},
	{"readGraph",                 &Deser._readGraph,                maxParams: 1},
];

const Code =
`module serialization

import stream: InStream, OutStream, BinaryStream
import math: intMin, intSize, floatSize
import text
import ascii
import object: bindInstMethod

local TypeTags = _serializationtmp.TypeTags

local function capital(s) =
	ascii.toUpper(s[0]) ~ s[1..]

local function addMethods(C: class, methods: table)
{
	foreach(name, func; methods)
		object.addMethod(C, name, func)

	return C
}

local SerializeMethods =
	{[type] = "_serialize" ~ capital(type)
		foreach type, _; TypeTags}

local RevTypeTags = {[v] = k foreach k, v; TypeTags}

local DeserializeMethods =
	{[tag] = "_deserialize" ~ capital(type) ~ "Impl"
		foreach tag, type; RevTypeTags}

local IntBitSize = intSize * 8

local Endianness = _serializationtmp.Endianness

local PlatformBits = _serializationtmp.PlatformBits

local ModuleFourCC = text.getCodec("ascii").encode("Croc")

// This gets bumped any time the serialization format changes.
local SerialVersion = 1

local utf8 = text.getCodec("utf-8")

/**
*/
function serializeGraph(val, transients: table|instance, output: @OutStream)
	Serializer(output).writeGraph(val, transients)

/**
*/
function deserializeGraph(transients: table|instance, input: @InStream) =
	Deserializer(input).readGraph(transients)

/**
*/
function serializeModule(mod: funcdef, name: string, output: @OutStream)
{
	if(!mod.isCacheable())
		throw ValueError("Only cacheable funcdefs can be serialized as modules")

	if(mod.isCached())
		throw ValueError("Only uncached funcdefs can be serialized as modules")

	output.writeExact(ModuleFourCC)

	local graph = [name, mod]
	local trans = {}

	serializeGraph(graph, trans, output)
}

local _littleBuf = memblock.new(4)

/**
*/
function deserializeModule(input: @InStream)
{
	input.readExact(_littleBuf)

	if(_littleBuf != ModuleFourCC)
		throw ValueError("Invalid magic number at beginning of module")

	local trans = {}

	local ret = deserializeGraph(trans, input)

	if(!isArray(ret) || #ret != 2 || !isString(ret[0]) || !isFuncDef(ret[1]))
		throw ValueError("Data deserialized from module is not in the proper format")

	local name, mod = ret.expand()

	if(!mod.isCacheable() || mod.isCached()) // somehow...? just to be sure.
		throw ValueError("Data deserialized from module has an invalid funcdef")

	return mod, name
}

/**
*/
@addMethods(_serializationtmp.ExtraSerializeMethods)
class Serializer
{
	__output
	__strBuf
	__objTable
	__objIndex = 0
	__trans
	__serializeFunc
	__rawBuf
	__wroteSignature = false

	this(output: @OutStream)
	{
		:setOutput(output)
		:__strBuf = memblock.new(256)
		:__serializeFunc = bindInstMethod(this, "_serialize")
		:__rawBuf = memblock.new(0)
	}

	function setOutput(output: @OutStream)
	{
		if(output as BinaryStream)
			:__output = output
		else
			:__output = BinaryStream(output)

		:__wroteSignature = false
	}

	function writeGraph(val, transients: table|instance)
	{
		if(val is transients)
			throw ValueError("Object to serialize is the same as the transients table")

		:__trans = transients
		:__objTable = {}
		:__objIndex = 0

		scope(exit)
			hash.clear(:__objTable)

		if(!:__wroteSignature)
		{
			:_writeSignature()
			:__wroteSignature = true
		}

		:_serialize(val)
		:__output.flush()
	}

	function _writeSignature()
	{
		:__output.writeUInt8(Endianness)
		:_integer(PlatformBits)
		:_integer(intSize)
		:_integer(floatSize)
		:_integer(SerialVersion)
	}

	function _tag(v: int)
		:__output.writeUInt8(v)

	function _integer(v: int)
	{
		local o = :__output

		do
		{
			local b = v & 0x7F
			v >>= 7
			local more = !((v == 0 && ((b & 0x40) == 0)) || (v == -1 && ((b & 0x40) != 0)))

			if(more)
				b |= 0x80

			o.writeUInt8(b)
		} while(more)
	}

	function _serialize(val)
	{
		if(local replacement = :__trans[val])
		{
			:_tag(TypeTags["transient"])
			:_serialize(replacement)
			return
		}

		local method = SerializeMethods[typeof(val)]
		assert(method !is null, "t: " ~ typeof(val))
		return :(method)(val)
	}

	function _serializeNull(_)
		:_tag(TypeTags["null"])

	function _serializeBool(v)
	{
		:_tag(TypeTags["bool"])
		:__output.writeUInt8(toInt(v))
	}

	function _serializeInt(v)
	{
		:_tag(TypeTags["int"])
		:_integer(v)
	}

	function _serializeFloat(v)
	{
		:_tag(TypeTags["float"])
		:__output.writeFloat64(v)
	}

	function _serializeNativeobj(v)
		throw TypeError("Attempting to serialize a nativeobj. Please use the transients table.")

	function _serializeString(v)
	{
		if(:_alreadyWritten(v))
			return

		:_tag(TypeTags["string"])
		local buf = :__strBuf
		utf8.encodeInto(v, buf, 0)
		:_integer(#buf)
		:__output.writeExact(buf)
	}

	function _serializeWeakref(v)
	{
		// although weakrefs are implemented as objects, their value-ness means that really the only way to properly
		// serialize/deserialize them is to treat them like a value: just embed them every time they show up.

		:_tag(TypeTags["weakref"])

		local obj = deref(v)

		if(obj is null)
			:__output.writeUInt8(0)
		else
		{
			:__output.writeUInt8(1)
			:_serialize(obj)
		}
	}

	function _serializeTable(v)
	{
		if(:_alreadyWritten(v))
			return

		:_tag(TypeTags["table"])
		:_integer(#v)

		foreach(key, val; v)
		{
			:_serialize(key)
			:_serialize(val)
		}
	}

	function _serializeNamespace(v)
	{
		if(:_alreadyWritten(v))
			return

		:_tag(TypeTags["namespace"])
			:_serialize(nameOf(v))

		if(v.super is null)
			:__output.writeUInt8(0)
		else
		{
			:__output.writeUInt8(1)
			:_serialize(v.super)
		}

		:_integer(#v)

		foreach(key, val; v)
		{
			:_serialize(key)
			:_serialize(val)
		}
	}

	function _serializeArray(v)
	{
		if(:_alreadyWritten(v))
			return

		:_tag(TypeTags["array"])
		:_integer(#v)

		foreach(val; v)
			:_serialize(val)
	}

	function _serializeMemblock(v)
	{
		if(:_alreadyWritten(v))
			return

		if(!v.ownData())
			throw ValueError("Attempting to serialize a memblock which does not own its data")

		:_tag(TypeTags["memblock"])
		:_integer(#v)
		:__output.writeExact(v)
	}

	function _serializeFunction(v)
	{
		if(:_alreadyWritten(v))
			return

		if(v.isNative())
			throw ValueError("Attempting to serialize a native function '{}'".format(nameOf(v)))

		:_tag(TypeTags["function"])
		:_nativeSerializeFunction(v)
	}

	function _serializeFuncdef(v)
	{
		if(:_alreadyWritten(v))
			return

		:_tag(TypeTags["funcdef"])
		:_nativeSerializeFuncdef(v)
	}

	function _serializeClass(v)
	{
		if(:_alreadyWritten(v))
			return

		:_tag(TypeTags["class"])
		:_serialize(nameOf(v))

		// TODO: relax the finalizer restriction, since finalizers aren't "native-only" any more
		if(object.isFrozen(v) && object.finalizable(v))
			throw ValueError("Attempting to serialize class '{}' which has a finalizer".format(nameOf(v)))

		if(v.super)
		{
			:__output.writeUInt8(1)
			:_serialize(v.super)
		}
		else
			:__output.writeUInt8(0)

		:_nativeSerializeClass(v)
		:__output.writeUInt8(toInt(object.isFrozen(v)))
	}

	function _serializeInstance(v)
	{
		if(:_alreadyWritten(v))
			return

		:_tag(TypeTags["instance"])
		:_integer(:_instSize(v)) // have to do this so we can deserialize properly
		:_serialize(v.super)

		if(hasField(v, "opSerialize") || hasMethod(v, "opSerialize"))
		{
			local s = v.opSerialize

			if(isFunction(s))
			{
				:__output.writeUInt8(1)
				v.opSerialize(:__output, :__serializeFunc)
				return
			}
			else if(isBool(s))
			{
				if(!s)
					throw ValueError("Attempting to serialize '{}' whose opSerialize field is false".format(rawToString(v)))
				// fall out, serialize literally
			}
			else
			{
				throw TypeError("Attempting to serialize '{}' whose opSerialize field is '{}', not bool or function".format(
					rawToString(v), typeof(s)))
			}
		}

		// TODO: relax the finalizer restriction, since finalizers aren't "native-only" any more
		if(object.finalizable(v))
			throw ValueError("Attempting to serialize '{}' which has a finalizer".format(rawToString(v)))

		:__output.writeUInt8(0)
		:_nativeSerializeInstance(v)
	}

	function _serializeThread(v)
	{
		if(:_alreadyWritten(v))
			return

		:_tag(TypeTags["thread"])

		:_nativeSerializeThread(v)
	}

	function _alreadyWritten(v)
	{
		if(local idx = :__objTable[v])
		{
			:_tag(TypeTags["backref"])
			:_integer(idx)
			return true
		}

		// writefln("objTable[{}] = {}", v, :__objIndex)

		:__objTable[v] = :__objIndex
		:__objIndex++
		return false
	}
}

/**
*/
@addMethods(_serializationtmp.ExtraDeserializeMethods)
class Deserializer
{
	__input
	__strBuf
	__objTable
	__trans
	__deserializeFunc
	__rawBuf
	__dummyObj
	__readSignature = false

	this(input: @InStream)
	{
		:setInput(input)
		:__strBuf = memblock.new(256)
		:__deserializeFunc = bindInstMethod(this, "_deserializeCB")
		:__rawBuf = memblock.new(0)
	}

	function setInput(input: @InStream)
	{
		if(input is :__input)
			return
		else if(input as BinaryStream)
			:__input = input
		else
			:__input = BinaryStream(input)

		:__readSignature = false
	}

	function _readSignature()
	{
		local endian = :__input.readUInt8()

		if(endian != Endianness)
			throw ValueError("Data was serialized with a different endianness")

		local bits = :_integer()

		if(bits != PlatformBits)
		{
			throw ValueError(
				"Data was serialized on a {}-bit platform; this is a {}-bit platform".format(bits, PlatformBits))
		}

		local size = :_integer()

		if(size != intSize)
		{
			throw ValueError(
				"Data was serialized from a Croc build with {}-bit ints; this build has {}-bit ints".format(size, intSize))
		}

		size = :_integer()

		if(size != floatSize)
		{
			throw ValueError(
				"Data was serialized from a Croc build with {}-bit floats; this build has {}-bit floats".format(size, floatSize))
		}

		local version = :_integer()

		if(version != SerialVersion)
			throw ValueError("Data was serialized from a Croc build with a different serial data format")
	}

	function _integer()
	{
		local i = :__input
		local ret = 0
		local shift = 0
		local b

		while(true)
		{
			if(shift >= IntBitSize)
				throw ValueError("Malformed data (overlong integer)")

			b = i.readUInt8()
			ret |= (b & 0x7F) << shift
			shift += 7

			if((b & 0x80) == 0)
				break
		}

		if(shift < IntBitSize && (b & 0x40))
			ret |= -(1 << shift)

		return ret
	}

	function _length()
	{
		local ret = :_integer()

		if(ret < 0 || ret > 0xFFFFFFFF)
			throw ValueError("Malformed data (length field has a value of {})".format(ret))

		return ret
	}

	function _tag() =
		:__input.readUInt8()

	function _checkTag(wanted: int)
	{
		local read = :_tag()

		if(read != wanted)
		{
			local w = RevTypeTags[wanted]
			local r = RevTypeTags[read]

			if(r is null)
				throw ValueError("Malformed data (expected type '{}' but found garbage instead)".format(w))
			else
				throw ValueError("Malformed data (expected type '{}' but found '{}' instead)".format(w, r))
		}
	}

	function _checkObjTag(wanted: int)
	{
		local w = RevTypeTags[wanted]
		local t = :_tag()
		local val

		if(t == wanted)
			return null
		else if(t == TypeTags["backref"])
			val = :_deserializeBackrefImpl()
		else if(t == TypeTags["transient"])
			val = :_deserializeTransientImpl()
		else
		{
			local r = RevTypeTags[t]

			if(r is null)
				throw ValueError("Malformed data (expected object of type '{}' but found garbage instead)".format(w))
			else
				throw ValueError("Malformed data (expected object of type '{}' but found '{}' instead)".format(r))
		}

		if(typeof(val) !is w)
			throw ValueError("Malformed data (expected type '{}' but found a backref to type '{}' instead)".format(w, typeof(val)))

		return val
	}

	function _addObject(val)
	{
		// writefln("objTable[{}] = {}", #:__objTable, typeof(val))
		:__objTable.append(val)
		return val
	}

	// callback function given to opDeserialize methods
	function _deserializeCB(type: string|null)
	{
		if(type is null)
			return :_deserialize()
		else if(local wanted = TypeTags[type])
		{
			if(local val = :_checkObjTag(wanted))
				return val
			else
				return :(DeserializeMethods[wanted])()
		}
		else
			throw ValueError("Invalid requested type '{}'".format(type))
	}

	function _deserialize()
	{
		local method = DeserializeMethods[:_tag()]

		if(method is null)
			throw ValueError("Malformed data (invalid type tag)")

		return :(method)()
	}

	function _deserializeTransientImpl()
	{
		local key = :_deserialize()
		local ret = :__trans[key]

		if(ret is null)
			throw ValueError("Malformed data or invalid transient table (transient key {r} does not exist)".format(key))

		return ret
	}

	function _deserializeBackrefImpl()
	{
		local idx = :_integer()

		if(idx < 0 || idx >= #:__objTable)
			throw ValueError("Malformed data (invalid back-reference)")

		return :__objTable[idx]
	}

	function _deserializeNull()      { :_checkTag(TypeTags["null"]);  return :_deserializeNullImpl()  }
	function _deserializeBool()      { :_checkTag(TypeTags["bool"]);  return :_deserializeBoolImpl()  }
	function _deserializeInt()       { :_checkTag(TypeTags["int"]);   return :_deserializeIntImpl()   }
	function _deserializeFloat()     { :_checkTag(TypeTags["float"]); return :_deserializeFloatImpl() }

	function _deserializeWeakref()   { :_checkTag(TypeTags["weakref"]); return :_deserializeWeakrefImpl() } // weirdo

	function _deserializeString()    { return :_checkObjTag(TypeTags["string"])    || :_deserializeStringImpl()    }
	function _deserializeTable()     { return :_checkObjTag(TypeTags["table"])     || :_deserializeTableImpl()     }
	function _deserializeNamespace() { return :_checkObjTag(TypeTags["namespace"]) || :_deserializeNamespaceImpl() }
	function _deserializeArray()     { return :_checkObjTag(TypeTags["array"])     || :_deserializeArrayImpl()     }
	function _deserializeMemblock()  { return :_checkObjTag(TypeTags["memblock"])  || :_deserializeMemblockImpl()  }
	function _deserializeFunction()  { return :_checkObjTag(TypeTags["function"])  || :_deserializeFunctionImpl()  }
	function _deserializeFuncdef()   { return :_checkObjTag(TypeTags["funcdef"])   || :_deserializeFuncdefImpl()   }
	function _deserializeClass()     { return :_checkObjTag(TypeTags["class"])     || :_deserializeClassImpl()     }
	function _deserializeInstance()  { return :_checkObjTag(TypeTags["instance"])  || :_deserializeInstanceImpl()  }
	function _deserializeThread()    { return :_checkObjTag(TypeTags["thread"])    || :_deserializeThreadImpl()    }
	function _deserializeUpvalue()   { return :_checkObjTag(TypeTags["upvalue"])   || :_deserializeUpvalueImpl()   }

	function _deserializeNullImpl() =
		null

	function _deserializeBoolImpl() =
		:__input.readUInt8() != 0 ? true : false

	function _deserializeIntImpl() =
		:_integer()

	function _deserializeFloatImpl() =
		:__input.readFloat64()

	function _deserializeWeakrefImpl()
	{
		if(:__input.readUInt8() != 0)
			return weakref(:_deserialize())
		else
			return weakref(:__dummyObj)
	}

	function _deserializeStringImpl()
	{
		#:__strBuf = :_length()
		:__input.readExact(:__strBuf)
		return :_addObject(utf8.decode(:__strBuf))
	}

	function _deserializeTableImpl()
	{
		local len = :_length()
		local ret = :_addObject({})

		for(i: 0 .. len)
		{
			local key, value = :_deserialize(), :_deserialize()
			ret[key] = value
		}

		return ret
	}

	// _deserializeNamespaceImpl is native

	function _deserializeArrayImpl()
	{
		local ret = :_addObject([])
		#ret = :_length()

		for(i: 0 .. #ret)
			ret[i] = :_deserialize()

		return ret
	}

	function _deserializeMemblockImpl()
	{
		local len = :_length()
		local ret = memblock.new(len)
		:__input.readExact(ret)
		return ret
	}

	// _deserializeFunctionImpl is native

	// _deserializeFuncdefImpl is native

	// _deserializeClassImpl is native

	// _deserializeInstanceImpl is native

	// _deserializeUpvalueImpl is native
}
`;