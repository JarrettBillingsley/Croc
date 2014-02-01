/******************************************************************************
This module contains the "icky" parts of the Croc 'serialization' library that
mess with Croc's internals.

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

import tango.core.Traits;

import croc.api_interpreter;
import croc.api_stack;
import croc.types;
import croc.types_class;
import croc.types_funcdef;
import croc.types_function;
import croc.types_instance;
import croc.types_namespace;
import croc.types_thread;
import croc.vm;

// =====================================================================================================================
// Protected
// =====================================================================================================================

protected:

struct Ser
{
static:
	const _Output = "_output";
	const _RawBuf = "_rawBuf";

	void _integer(T)(CrocThread* t, T v)
	{
		dup(t, 0);
		pushNull(t);
		pushInt(t, v);
		methodCall(t, -3, "_integer", 0);
	}

	void _serialize(T)(CrocThread* t, T v)
	{
		dup(t, 0);
		pushNull(t);

		static if(is(T == CrocValue))
			push(t, v);
		else
			push(t, CrocValue(v));

		methodCall(t, -3, "_serialize", 0);
	}

	void _writeUInt8(CrocThread* t, ubyte b)
	{
		field(t, 0, _Output);
		pushNull(t);
		pushInt(t, b);
		methodCall(t, -3, "writeUInt8", 0);
	}

	void _serializeArray(T)(CrocThread* t, T[] arr)
	{
		_integer(t, arr.length);

		foreach(ref val; arr)
		{
			static if(isIntegerType!(T))
				_integer(t, val);
			else
				_serialize(t, val);
		}
	}

	void _append(CrocThread* t, void[] arr)
	{
		field(t, 0, _Output);
		pushNull(t);
		field(t, 0, _RawBuf);
		memblockReviewNativeArray(t, -1, arr);
		methodCall(t, -3, "writeExact", 0);
	}

	uword _nativeSerializeFunction(CrocThread* t)
	{
		auto v = getFunction(t, 1);

		// we do this first so we can allocate it at the beginning of deserialization
		_integer(t, v.numUpvals);
		_serialize(t, v.scriptFunc);

		if(v.environment is t.vm.globals)
			_writeUInt8(t, 0);
		else
		{
			_writeUInt8(t, 1);
			_serialize(t, v.environment);
		}

		foreach(upval; v.scriptUpvals)
			_serialize(t, cast(CrocBaseObject*)upval);

		return 0;
	}

	uword _nativeSerializeFuncdef(CrocThread* t)
	{
		auto v = getFuncDef(t, 1);

		_serialize(t, v.locFile);
		_integer(t, v.locLine);
		_integer(t, v.locCol);
		_writeUInt8(t, cast(ubyte)v.isVararg);
		_serialize(t, v.name);
		_integer(t, v.numParams);
		_serializeArray(t, v.paramMasks);

		_integer(t, v.upvals.length);

		foreach(ref uv; v.upvals)
		{
			_writeUInt8(t, cast(ubyte)uv.isUpvalue);
			_integer(t, uv.index);
		}

		_integer(t, v.stackSize);
		_serializeArray(t, v.innerFuncs);
		_serializeArray(t, v.constants);
		_integer(t, v.code.length);
		_append(t, v.code);

		if(auto e = v.environment)
		{
			_writeUInt8(t, 1);
			_serialize(t, e);
		}
		else
			_writeUInt8(t, 0);

		if(auto f = v.cachedFunc)
		{
			_writeUInt8(t, 1);
			_serialize(t, f);
		}
		else
			_writeUInt8(t, 0);

		_integer(t, v.switchTables.length);

		foreach(ref st; v.switchTables)
		{
			_integer(t, st.offsets.length);

			foreach(ref k, v; st.offsets)
			{
				_serialize(t, k);
				_integer(t, v);
			}

			_integer(t, st.defaultOffset);
		}

		_integer(t, v.lineInfo.length);
		_append(t, v.lineInfo);
		_serializeArray(t, v.upvalNames);

		_integer(t, v.locVarDescs.length);

		foreach(ref desc; v.locVarDescs)
		{
			_serialize(t, desc.name);
			_integer(t, desc.pcStart);
			_integer(t, desc.pcEnd);
			_integer(t, desc.reg);
		}

		return 0;
	}

	uword _nativeSerializeClass(CrocThread* t)
	{
		auto v = getClass(t, 1);

		uword index = 0;
		CrocString** key = void;
		CrocValue* value = void;

		_integer(t, v.methods.length);

		while(classobj.nextMethod(v, index, key, value))
		{
			_serialize(t, *key);
			_serialize(t, *value);
		}

		_integer(t, v.fields.length);
		index = 0;

		while(classobj.nextField(v, index, key, value))
		{
			_serialize(t, *key);
			_serialize(t, *value);
		}

		return 0;
	}

	uword _nativeSerializeInstance(CrocThread* t)
	{
		auto v = getInstance(t, 1);

		uword index = 0;
		CrocString** key = void;
		CrocValue* value = void;

		_integer(t, v.fields.length);

		while(instance.nextField(v, index, key, value))
		{
			_serialize(t, *key);
			_serialize(t, *value);
		}

		return 0;
	}

	void _serializeStack(CrocThread* t, CrocThread* v)
	{
		_integer(t, v.stackIndex);
		_integer(t, v.stackBase);
		uword stackTop = void;

		if(v.arIndex > 0)
			stackTop = v.currentAR.savedTop;
		else
			stackTop = v.stackIndex;

		_integer(t, stackTop);

		foreach(ref val; v.stack[0 .. stackTop])
			_serialize(t, val);
	}

	void _serializeCallStack(CrocThread* t, CrocThread* v)
	{
		version(CrocExtendedThreads) {} else
			_integer(t, v.savedCallDepth);

		_integer(t, v.arIndex);

		foreach(ref rec; v.actRecs[0 .. v.arIndex])
		{
			_integer(t, rec.base);
			_integer(t, rec.savedTop);
			_integer(t, rec.vargBase);
			_integer(t, rec.returnSlot);

			if(rec.func is null)
				_writeUInt8(t, 0);
			else
			{
				_writeUInt8(t, 1);
				_serialize(t, rec.func);
				uword diff = rec.pc - rec.func.scriptFunc.code.ptr;
				_integer(t, diff);
			}

			_integer(t, rec.numReturns);
			_integer(t, rec.numTailcalls);
			_integer(t, rec.firstResult);
			_integer(t, rec.numResults);
			_integer(t, rec.unwindCounter);

			if(rec.unwindReturn)
			{
				_writeUInt8(t, 1);
				uword diff = rec.unwindReturn - rec.func.scriptFunc.code.ptr;
				_integer(t, diff);
			}
			else
				_writeUInt8(t, 0);
		}
	}

	void _serializeEHStack(CrocThread* t, CrocThread* v)
	{
		_integer(t, v.trIndex);

		foreach(ref rec; v.tryRecs[0 .. v.trIndex])
		{
			_writeUInt8(t, cast(ubyte)rec.isCatch);
			_integer(t, rec.slot);
			_integer(t, rec.actRecord);

			uword diff = rec.pc - v.actRecs[rec.actRecord].func.scriptFunc.code.ptr;
			_integer(t, diff);
		}
	}

	void _serializeResultStack(CrocThread* t, CrocThread* v)
	{
		_integer(t, v.resultIndex);

		foreach(ref val; v.results[0 .. v.resultIndex])
			_serialize(t, val);
	}

	void _serializeCoroFunc(CrocThread* t, CrocThread* v)
	{
		if(v.coroFunc)
		{
			_writeUInt8(t, 1);
			_serialize(t, v.coroFunc);
		}
		else
			_writeUInt8(t, 0);
	}

	void _serializeUpvals(CrocThread* t, CrocThread* v)
	{
		uword numUpvals = 0;

		for(auto uv = t.upvalHead; uv !is null; uv = uv.nextuv)
			numUpvals++;

		_integer(t, numUpvals);

		for(auto uv = t.upvalHead; uv !is null; uv = uv.nextuv)
		{
			assert(uv.value !is &uv.closedValue);
			_serialize(t, CrocValue(cast(CrocBaseObject*)uv));
			uword diff = uv.value - v.stack.ptr;
			_integer(t, diff);
		}
	}

	uword _nativeSerializeThread(CrocThread* t)
	{
		auto v = getThread(t, 1);

    	if(t is v)
    		throwStdException(t, "ValueError", "Attempting to serialize the currently-executing thread");

		version(CrocExtendedThreads)
			throwStdException(t, "ValueError", "Attempting to serialize an extended thread");

		if(v.nativeCallDepth > 0)
		{
			throwStdException(t, "ValueError",
				"Attempting to serialize a thread with at least one native or metamethod call on its call stack");
		}

		if(v.hookFunc !is null)
			throwStdException(t, "ValueError", "Attempting to serialize a thread with a debug hook function");

		_writeUInt8(t, cast(ubyte)v.shouldHalt);
		_integer(t, v.state);

		_serializeStack(t, v);

		_integer(t, v.numYields);

		_serializeResultStack(t, v);
		_serializeCallStack(t, v);
		_serializeEHStack(t, v);
		_serializeCoroFunc(t, v);
		_serializeUpvals(t, v);

		return 0;
	}

	uword _serializeUpvalue(CrocThread* t)
	{
		if(!isValidIndex(t, 1))
		{
			throwStdException(t, "ParamError",
				"Too few parameters (expected at least {}, got {})", 1, stackSize(t) - 1);
		}

		auto uv = *getValue(t, 1);

		if(uv.type != CrocValue.Type.Upvalue)
			throwStdException(t, "TypeError", "Expected upvalue for parameter");

		dup(t, 0);
		pushNull(t);
		dup(t, 1);
		methodCall(t, -3, "_alreadyWritten", 1);

		if(getBool(t, -1))
			return 0;

		pop(t);

		dup(t, 0);
		pushNull(t);
		pushInt(t, CrocValue.Type.Upvalue);
		methodCall(t, -3, "_tag", 0);

		dup(t, 0);
		pushNull(t);
		push(t, *(cast(CrocUpval*)getValue(t, 1).mBaseObj).value);
		methodCall(t, -3, "_serialize", 0);

		return 0;
	}

	uword _instSize(CrocThread* t)
	{
		pushInt(t, getInstance(t, 1).memSize);
		return 1;
	}
}

struct Deser
{
static:
	const _Input = "_input";
	const _RawBuf = "_rawBuf";
	const _Trans = "_trans";
	const _ObjTable = "_objTable";
	const _DummyObj = "_dummyObj";
	const _DeserializeFunc = "_deserializeFunc";
	const _SignatureRead = "_signatureRead";

	uword _readGraph(CrocThread* t)
	{
		if(!isValidIndex(t, 1))
		{
			throwStdException(t, "ParamError",
				"Too few parameters (expected at least {}, got {})", 1, stackSize(t) - 1);
		}

		if(!isTable(t, 1) && !isInstance(t, 1))
		{
			pushTypeString(t, 1);
			throwStdException(t, "TypeError",
				"Expected type 'table|instance' for parameter 1, not '{}'", getString(t, -1));
		}

		dup(t, 1);      fielda(t, 0, _Trans);
		newArray(t, 0); fielda(t, 0, _ObjTable);
		newTable(t);    fielda(t, 0, _DummyObj);

		{
			disableGC(t.vm);

			scope(exit)
			{
				enableGC(t.vm);
				field(t, 0, _ObjTable);
				lenai(t, -1, 0);
				pop(t);
				pushNull(t);
				fielda(t, 0, _DummyObj);
			}

			field(t, 0, _SignatureRead);

			if(!getBool(t, -1))
			{
				dup(t, 0);
				pushNull(t);
				methodCall(t, -2, "_readSignature", 0);

				pushBool(t, true);
				fielda(t, 0, _SignatureRead);
			}

			pop(t);

			dup(t, 0);
			pushNull(t);
			methodCall(t, -2, "_deserialize", 1);
		}

		gc(t, true);
		return 1;
	}

	crocint _integer(CrocThread* t)
	{
		dup(t, 0);
		pushNull(t);
		methodCall(t, -2, "_integer", 1);
		auto ret = getInt(t, -1);
		pop(t);
		return ret;
	}

	uword _length(CrocThread* t)
	{
		dup(t, 0);
		pushNull(t);
		methodCall(t, -2, "_length", 1);
		auto ret = cast(uword)getInt(t, -1);
		pop(t);
		return ret;
	}

	word _deserialize(CrocThread* t)
	{
		auto ret = dup(t, 0);
		pushNull(t);
		methodCall(t, -2, "_deserialize", 1);
		return ret;
	}

	ubyte _readUInt8(CrocThread* t)
	{
		field(t, 0, _Input);
		pushNull(t);
		methodCall(t, -2, "readUInt8", 1);
		auto ret = cast(ubyte)getInt(t, -1);
		pop(t);
		return ret;
	}

	void _readBlock(CrocThread* t, void[] arr)
	{
		field(t, 0, _Input);
		pushNull(t);
		field(t, 0, _RawBuf);
		memblockReviewNativeArray(t, -1, arr);
		methodCall(t, -3, "readExact", 0);
	}

	void _addObject(CrocThread* t, CrocBaseObject* obj)
	{
		dup(t, 0);
		pushNull(t);
		push(t, CrocValue(obj));
		methodCall(t, -3, "_addObject", 0);
	}

	void _deserializeObj(CrocThread* t, char[] methodName)
	{
		dup(t, 0);
		pushNull(t);
		methodCall(t, -2, methodName, 1);
	}

	CrocString* _deserializeString(CrocThread* t)
	{
		_deserializeObj(t, "_deserializeString");
		auto ret = getStringObj(t, -1);
		pop(t);
		return ret;
	}

	uword _deserializeNamespaceImpl(CrocThread* t)
	{
		auto ret = namespace.createPartial(t.vm.alloc);
		_addObject(t, cast(CrocBaseObject*)ret);

		auto name = _deserializeString(t);
		CrocNamespace* parent = null;

		if(_readUInt8(t) != 0)
		{
			_deserializeObj(t, "_deserializeNamespace");
			parent = getNamespace(t, -1); assert(parent !is null);
			pop(t);
		}

		namespace.finishCreate(ret, name, parent);
		push(t, CrocValue(ret));

		auto len = _length(t);

		for(uword i = 0; i < len; i++)
		{
			_deserializeObj(t, "_deserializeString");
			_deserialize(t);
			fielda(t, -3);
		}

		return 1;
	}

	uword _deserializeFunctionImpl(CrocThread* t)
	{
		auto numUpvals = _length(t);
		auto ret = func.createPartial(t.vm.alloc, numUpvals);
		_addObject(t, cast(CrocBaseObject*)ret);

		_deserializeObj(t, "_deserializeFuncdef");

		if(_readUInt8(t) != 0)
			_deserializeObj(t, "_deserializeNamespace");
		else
			push(t, CrocValue(t.vm.globals));

		auto def = getFuncDef(t, -2);   assert(def !is null);
		auto env = getNamespace(t, -1); assert(env !is null);
		func.finishCreate(t.vm.alloc, ret, env, def);
		pop(t, 2);

		foreach(ref val; ret.scriptUpvals())
		{
			_deserializeObj(t, "_deserializeUpvalue");
			val = cast(CrocUpval*)getValue(t, -1).mBaseObj;
			pop(t);
		}

		push(t, CrocValue(ret));
		return 1;
	}

	uword _deserializeFuncdefImpl(CrocThread* t)
	{
		auto def = funcdef.create(t.vm.alloc);
		_addObject(t, cast(CrocBaseObject*)def);

		def.locFile = _deserializeString(t);
		def.locLine = _length(t);
		def.locCol = _length(t);
		def.isVararg = cast(bool)_readUInt8(t);
		def.name = _deserializeString(t);
		def.numParams = _length(t);

		t.vm.alloc.resizeArray(def.paramMasks, _length(t));

		foreach(ref mask; def.paramMasks)
			mask = _length(t);

		t.vm.alloc.resizeArray(def.upvals, _length(t));

		foreach(ref uv; def.upvals)
		{
			uv.isUpvalue = cast(bool)_readUInt8(t);
			uv.index = _length(t);
		}

		def.stackSize = _length(t);

		t.vm.alloc.resizeArray(def.innerFuncs, _length(t));

		foreach(ref func; def.innerFuncs)
		{
			_deserializeObj(t, "_deserializeFuncdef");
			func = getFuncDef(t, -1); assert(func !is null);
			pop(t);
		}

		t.vm.alloc.resizeArray(def.constants, _length(t));

		foreach(ref val; def.constants)
		{
			_deserialize(t);
			val = *getValue(t, -1);
			pop(t);
		}

		t.vm.alloc.resizeArray(def.code, _length(t));
		_readBlock(t, def.code);

		if(_readUInt8(t) != 0)
		{
			_deserializeObj(t, "_deserializeNamespace");
			def.environment = getNamespace(t, -1); assert(def.environment !is null);
			pop(t);
		}

		if(_readUInt8(t) != 0)
		{
			_deserializeObj(t, "_deserializeFunction");
			def.cachedFunc = getFunction(t, -1); assert(def.cachedFunc !is null);
			pop(t);
		}

		t.vm.alloc.resizeArray(def.switchTables, _length(t));

		foreach(ref st; def.switchTables)
		{
			auto numOffsets = _length(t);

			for(uword i = 0; i < numOffsets; i++)
			{
				_deserialize(t);
				auto offs = cast(word)_integer(t);
				*st.offsets.insert(t.vm.alloc, *getValue(t, -1)) = offs;
				pop(t);
			}

			st.defaultOffset = cast(word)_integer(t);
		}

		t.vm.alloc.resizeArray(def.lineInfo, _length(t));
		_readBlock(t, def.lineInfo);

		t.vm.alloc.resizeArray(def.upvalNames, _length(t));

		foreach(ref name; def.upvalNames)
			name = _deserializeString(t);

		t.vm.alloc.resizeArray(def.locVarDescs, _length(t));

		foreach(ref desc; def.locVarDescs)
		{
			desc.name = _deserializeString(t);
			desc.pcStart = _length(t);
			desc.pcEnd = _length(t);
			desc.reg = _length(t);
		}

		push(t, CrocValue(def));
		return 1;
	}

	uword _deserializeClassImpl(CrocThread* t)
	{
		auto v = classobj.create(t.vm.alloc, null);
		_addObject(t, cast(CrocBaseObject*)v);

		v.name = _deserializeString(t);

		auto numMethods = _length(t);

		for(uword i = 0; i < numMethods; i++)
		{
			auto name = _deserializeString(t);
			_deserialize(t);

			if(!classobj.addMethod(t.vm.alloc, v, name, getValue(t, -1), false))
			{
				throwStdException(t, "ValueError", "Malformed data (class {} already has a method '{}')",
					v.name.toString(), name.toString());
			}

			pop(t);
		}

		auto numFields = _length(t);

		for(uword i = 0; i < numFields; i++)
		{
			auto name = _deserializeString(t);
			_deserialize(t);

			if(!classobj.addField(t.vm.alloc, v, name, getValue(t, -1), false))
			{
				throwStdException(t, "ValueError", "Malformed data (class {} already has a field '{}')",
					v.name.toString(), name.toString());
			}

			pop(t);
		}

		if(_readUInt8(t) != 0)
			classobj.freeze(v);

		push(t, CrocValue(v));
		return 1;
	}

	uword _deserializeInstanceImpl(CrocThread* t)
	{
		auto size = _length(t);

		if(size < CrocInstance.sizeof || size >= (1 << 20)) // 1MB should be a reasonably insane upper bound :P
			throwStdException(t, "ValueError", "Malformed data (invalid instance size)");

		auto v = instance.createPartial(t.vm.alloc, size, false); // always false for now, might change later
		_addObject(t, cast(CrocBaseObject*)v);

		_deserializeObj(t, "_deserializeClass");
		auto parent = getClass(t, -1); assert(parent !is null);

		if(!parent.isFrozen)
			throwStdException(t, "ValueError", "Malformed data (instance of an unfrozen class somehow exists)");

		if(!instance.finishCreate(v, parent))
			throwStdException(t, "ValueError", "Malformed data (instance size does not match base class size)");

		if(_readUInt8(t) != 0)
		{
			push(t, CrocValue(v));

			if(!hasMethod(t, -1, "opDeserialize"))
			{
				pushToString(t, -1, true);
				throwStdException(t, "ValueError",
					"'{}' was serialized with opSerialize, but does not have a matching opDeserialize", getString(t, -1));
			}

			pushNull(t);
			field(t, 0, _Input);
			field(t, 0, _DeserializeFunc);
			methodCall(t, -4, "opDeserialize", 0);
		}
		else
		{
			auto numFields = _length(t);

			for(uword i = 0; i < numFields; i++)
			{
				auto name = _deserializeString(t);
				_deserialize(t);

				auto slot = instance.getField(v, name);

				if(slot is null)
				{
					throwStdException(t, "ValueError", "Malformed data (no field '{}' in instance of class '{}')",
						name.toString(), parent.name.toString());
				}

				instance.setField(t.vm.alloc, v, slot, getValue(t, -1));
				pop(t);
			}
		}

		push(t, CrocValue(v));
		return 1;
	}

	uword _limitedSize(CrocThread* t, uword max, char[] msg)
	{
		auto ret = _length(t);

		if(ret >= max)
			throwStdException(t, "ValueError", "Malformed data ({})", msg);

		return ret;
	}

	void _deserializeStack(CrocThread* t, CrocThread* ret)
	{
		// TODO: define some "max stack size" for threads so that we know when stuff is borked
		auto stackIndex = _limitedSize(t, 100_000, "invalid thread stack size");
		auto stackBase = _limitedSize(t, stackIndex, "invalid thread stack base");
		auto stackTop = _limitedSize(t, 100_000, "invalid thread stack top");

		t.vm.alloc.resizeArray(ret.stack, stackTop < 20 ? 20 : stackTop);
		ret.stackIndex = stackIndex;
		ret.stackBase = stackBase;

		foreach(ref val; ret.stack[0 .. stackTop])
		{
			_deserialize(t);
			val = *getValue(t, -1);
			pop(t);
		}
	}

	void _deserializeActRec(CrocThread* t, CrocThread* ret, ref ActRecord rec)
	{
		rec.base = _limitedSize(t, ret.stackIndex, "invalid call record base slot");
		rec.savedTop = _limitedSize(t, 100_000, "invalid call record saved top slot");
		rec.vargBase = _limitedSize(t, rec.base + 1, "invalid call record variadic base slot");
		rec.returnSlot = _limitedSize(t, 100_000, "invalid call record return value slot");

		if(_readUInt8(t))
		{
			_deserializeObj(t, "_deserializeFunction");
			rec.func = getFunction(t, -1);
			pop(t);

			auto diff = _limitedSize(t, rec.func.scriptFunc.code.length, "invalid call record instruction pointer");
			rec.pc = rec.func.scriptFunc.code.ptr + diff;
		}
		else
		{
			rec.func = null;
			rec.pc = null;
		}

		rec.numReturns = cast(word)_integer(t);

		if(rec.numReturns < -1 || rec.numReturns > 100_000)
			throwStdException(t, "ValueError", "Malformed data (invalid call record number of returns)");

		rec.numTailcalls = _length(t);
		rec.firstResult = _length(t);

		if(ret.resultIndex > 0 && rec.firstResult >= ret.resultIndex)
			throwStdException(t, "ValueError", "Malformed data (invalid call record result index)");

		rec.numResults = _length(t);

		if(rec.numResults > 0 && rec.numResults > (ret.resultIndex - rec.firstResult))
			throwStdException(t, "ValueError", "Malformed data (invalid call record number of results)");

		rec.unwindCounter = _length(t); // check later

		if(_readUInt8(t))
		{
			auto diff = _limitedSize(t, rec.func.scriptFunc.code.length, "invalid call record EH return pointer");
			rec.unwindReturn = rec.func.scriptFunc.code.ptr + diff;
		}
		else
			rec.unwindReturn = null;
	}

	void _checkActRecs(CrocThread* t, CrocThread* ret)
	{
		auto ars = ret.actRecs[0 .. ret.arIndex];

		// forall act rec i:
		foreach(i, ar; ars)
		{
			auto prevBase = (i > 0) ? ars[i - 1].base : 0;
			auto nextBase = (i + 1 < ars.length) ? ars[i + 1].base : ret.stackIndex;

			// base_i <= base_(i + 1)
			if(ar.base > nextBase)
				throwStdException(t, "ValueError", "invalid call record base slot");

			// base_(i-1) <= returnSlot_i < base_(i + 1)
			// TODO: determine if this is actually true :P

			// unwindCounter_i <= number of EH frames this call record has
			// TODO:
		}
	}

	void _deserializeCallStack(CrocThread* t, CrocThread* ret)
	{
		// TODO: define some "recursion limit" for threads so that we know when stuff is borked

		version(CrocExtendedThreads) {} else
			ret.savedCallDepth = _limitedSize(t, 100_000, "invalid thread saved call stack size");

		ret.arIndex = _limitedSize(t, 100_000, "invalid thread call stack size");

		t.vm.alloc.resizeArray(ret.actRecs, ret.arIndex < 10 ? 10 : ret.arIndex);

		if(ret.arIndex > 0)
			ret.currentAR = &ret.actRecs[ret.arIndex - 1];
		else
			ret.currentAR = null;

		foreach(ref rec; ret.actRecs[0 .. ret.arIndex])
			_deserializeActRec(t, ret, rec);

		_checkActRecs(t, ret);
	}

	void _deserializeEHStack(CrocThread* t, CrocThread* ret)
	{
		// TODO: define some EH frame limit so that we know when stuff is borked
		ret.trIndex = _limitedSize(t, 5_000, "invalid thread exception handling stack size");
		t.vm.alloc.resizeArray(ret.tryRecs, ret.trIndex < 10 ? 10 : ret.trIndex);

		if(ret.trIndex > 0)
			ret.currentTR = &ret.tryRecs[ret.trIndex - 1];
		else
			ret.currentTR = null;

		foreach(ref rec; ret.tryRecs[0 .. ret.trIndex])
		{
			rec.isCatch = cast(bool)_readUInt8(t);
			rec.slot = _limitedSize(t, ret.stackIndex, "invalid thread EH frame stack slot");
			rec.actRecord = _limitedSize(t, ret.arIndex, "invalid thread EH frame call record index");

			auto func = ret.actRecs[rec.actRecord].func;

			if(func is null || func.isNative)
				throwStdException(t, "ValueError", "Malformed data (invalid thread EH frame call record index)");

			auto diff = _limitedSize(t, func.scriptFunc.code.length, "invalid thread EH frame instruction pointer");
			rec.pc = func.scriptFunc.code.ptr + diff;
		}
	}

	void _deserializeResultStack(CrocThread* t, CrocThread* ret)
	{
		// TODO: define some result stack limit
		ret.resultIndex = _limitedSize(t, 10_000, "invalid thread result stack size");
		t.vm.alloc.resizeArray(ret.results, ret.resultIndex < 8 ? 8 : ret.resultIndex);

		foreach(ref val; ret.results[0 .. ret.resultIndex])
		{
			_deserialize(t);
			val = *getValue(t, -1);
			pop(t);
		}
	}

	void _deserializeCoroFunc(CrocThread* t, CrocThread* ret)
	{
		if(_readUInt8(t))
		{
			_deserializeObj(t, "_deserializeFunction");
			auto func = getFunction(t, -1);

			if(func.isNative)
				throwStdException(t, "ValueError", "Malformed data (invalid thread main function)");

			ret.coroFunc = func;
			pop(t);
		}
		else
			ret.coroFunc = null;
	}

	void _deserializeUpvals(CrocThread* t, CrocThread* ret)
	{
		// TODO: define an upval stack size or something
		auto numUpvals = _limitedSize(t, 100_000, "invalid thread upval stack size");

		CrocUpval* cur = null;
		auto next = &t.upvalHead;

		for(uword i = 0; i < numUpvals; i++)
		{
			_deserializeObj(t, "_deserializeUpvalue");
			auto uv = cast(CrocUpval*)getValue(t, -1).mBaseObj;
			pop(t);

			auto diff = _limitedSize(t, ret.stackIndex, "invalid thread upval slot");
			uv.value = ret.stack.ptr + diff;

			if(cur && uv.value <= cur.value)
				throwStdException(t, "ValueError", "Malformed data (invalid thread upval list)");

			*next = uv;
			next = &uv.nextuv;
			cur = uv;
		}

		*next = null;
	}

	uword _deserializeThreadImpl(CrocThread* t)
	{
		version(CrocExtendedThreads)
			throwStdException(t, "ValueError", "Attempting to deserialize a thread while extended threads were compiled in");

		auto ret = thread.createPartial(t.vm);
		_addObject(t, cast(CrocBaseObject*)ret);

		ret.shouldHalt = cast(bool)_readUInt8(t);

		auto state = _limitedSize(t, CrocThread.State.max + 1, "invalid thread state");

		if(state == CrocThread.State.Running)
			throwStdException(t, "ValueError", "Malformed data (invalid thread state)");

		ret.state = cast(CrocThread.State)state;

		_deserializeStack(t, ret);

		ret.numYields = _limitedSize(t, ret.stackIndex, "invalid yield count");

		_deserializeResultStack(t, ret);
		_deserializeCallStack(t, ret);
		_deserializeEHStack(t, ret);
		_deserializeCoroFunc(t, ret);
		_deserializeUpvals(t, ret);

		pushThread(t, ret);
		return 1;
	}

	uword _deserializeUpvalueImpl(CrocThread* t)
	{
		auto uv = t.vm.alloc.allocate!(CrocUpval)();
		uv.value = &uv.closedValue;
		_addObject(t, cast(CrocBaseObject*)uv);
		_deserialize(t);

		throwStdException(t, "ValueError", "Wangs!");
		uv.closedValue = *getValue(t, -1);
		push(t, CrocValue(cast(CrocBaseObject*)uv));
		return 1;
	}
}