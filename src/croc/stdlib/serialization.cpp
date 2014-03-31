
#include <string.h>
#include <type_traits>

#include "croc/api.h"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
#include "croc/stdlib/serialization.croc.hpp"

	namespace Ser
	{
	const char* _Output = "_output";
	const char* _RawBuf = "_rawBuf";

	template<typename T>
	void _integer(CrocThread* t, T v)
	{
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_pushInt(t, cast(crocint)v);
		croc_methodCall(t, -3, "_integer", 0);
	}

	template<typename T>
	void _pushit(CrocThread* t, T v)
	{
		push(Thread::from(t), Value::from(v));
	}

	template<>
	void _pushit<Value>(CrocThread* t, Value v)
	{
		push(Thread::from(t), v);
	}

	template<typename T>
	void _serialize(CrocThread* t, T v)
	{
		croc_dup(t, 0);
		croc_pushNull(t);
		_pushit(t, v);
		croc_methodCall(t, -3, "_serialize", 0);
	}

	void _writeUInt8(CrocThread* t, uint8_t b)
	{
		croc_field(t, 0, _Output);
		croc_pushNull(t);
		croc_pushInt(t, b);
		croc_methodCall(t, -3, "writeUInt8", 0);
	}

	template<typename T>
	void _serializeArray(CrocThread* t, DArray<T> arr)
	{
		_integer(t, arr.length);

		for(auto &val: arr)
			_serialize(t, val);
	}

	template<>
	void _serializeArray<uword>(CrocThread* t, DArray<uword> arr)
	{
		_integer(t, arr.length);

		for(auto &val: arr)
			_integer(t, val);
	}

	void _append(CrocThread* t, DArray<uint8_t> arr)
	{
		croc_field(t, 0, _Output);
		croc_pushNull(t);
		croc_field(t, 0, _RawBuf);
		croc_memblock_reviewNativeArray(t, -1, cast(void*)arr.ptr, arr.length);
		croc_methodCall(t, -3, "writeExact", 0);
	}

	word_t _nativeSerializeFunction(CrocThread* t)
	{
		auto t_ = Thread::from(t);
		auto v = getFunction(t_, 1);

		// we do this first so we can allocate it at the beginning of deserialization
		_integer(t, v->numUpvals);
		_serialize(t, v->scriptFunc);

		if(v->environment == t_->vm->globals)
			_writeUInt8(t, 0);
		else
		{
			_writeUInt8(t, 1);
			_serialize(t, v->environment);
		}

		for(auto upval: v->scriptUpvals())
			_serialize(t, cast(GCObject*)upval);

		return 0;
	}

	word_t _nativeSerializeFuncdef(CrocThread* t)
	{
		auto t_ = Thread::from(t);
		auto v = getFuncdef(t_, 1);

		_serialize(t, v->locFile);
		_integer(t, v->locLine);
		_integer(t, v->locCol);
		_writeUInt8(t, cast(uint8_t)v->isVararg);
		_serialize(t, v->name);
		_integer(t, v->numParams);
		_serializeArray(t, v->paramMasks);

		_integer(t, v->upvals.length);

		for(auto &uv: v->upvals)
		{
			_writeUInt8(t, cast(uint8_t)uv.isUpval);
			_integer(t, uv.index);
		}

		_integer(t, v->stackSize);
		_serializeArray(t, v->innerFuncs);
		_serializeArray(t, v->constants);
		_integer(t, v->code.length);
		_append(t, v->code.template as<uint8_t>());

		if(auto e = v->environment)
		{
			_writeUInt8(t, 1);
			_serialize(t, e);
		}
		else
			_writeUInt8(t, 0);

		if(auto f = v->cachedFunc)
		{
			_writeUInt8(t, 1);
			_serialize(t, f);
		}
		else
			_writeUInt8(t, 0);

		_integer(t, v->switchTables.length);

		for(auto &st: v->switchTables)
		{
			_integer(t, st.offsets.length());

			for(auto node: st.offsets)
			{
				_serialize(t, node->key);
				_integer(t, node->value);
			}

			_integer(t, st.defaultOffset);
		}

		_integer(t, v->lineInfo.length);
		_append(t, v->lineInfo.template as<uint8_t>());
		_serializeArray(t, v->upvalNames);

		_integer(t, v->locVarDescs.length);

		for(auto &desc: v->locVarDescs)
		{
			_serialize(t, desc.name);
			_integer(t, desc.pcStart);
			_integer(t, desc.pcEnd);
			_integer(t, desc.reg);
		}

		return 0;
	}

	word_t _nativeSerializeClass(CrocThread* t)
	{
		auto v = getClass(Thread::from(t), 1);

		uword index = 0;
		String** key;
		Value* value;

		_integer(t, v->methods.length());

		while(v->nextMethod(index, key, value))
		{
			_serialize(t, *key);
			_serialize(t, *value);
		}

		_integer(t, v->fields.length());
		index = 0;

		while(v->nextField(index, key, value))
		{
			_serialize(t, *key);
			_serialize(t, *value);
		}

		_integer(t, v->hiddenFields.length());
		index = 0;

		while(v->nextHiddenField(index, key, value))
		{
			_serialize(t, *key);
			_serialize(t, *value);
		}

		return 0;
	}

	word_t _nativeSerializeInstance(CrocThread* t)
	{
		auto v = getInstance(Thread::from(t), 1);

		uword index = 0;
		String** key;
		Value* value;

		_integer(t, v->fields->length());

		while(v->nextField(index, key, value))
		{
			_serialize(t, *key);
			_serialize(t, *value);
		}

		if(v->hiddenFieldsData == nullptr)
			_integer(t, 0);
		else
		{
			_integer(t, v->parent->hiddenFields.length());
			index = 0;

			while(v->nextHiddenField(index, key, value))
			{
				_serialize(t, *key);
				_serialize(t, *value);
			}
		}

		return 0;
	}

	// void _serializeStack(CrocThread* t, CrocThread* v)
	// {
	// 	_integer(t, v->stackIndex);
	// 	_integer(t, v->stackBase);
	// 	uword stackTop;

	// 	if(v->arIndex > 0)
	// 		stackTop = v->currentAR->savedTop;
	// 	else
	// 		stackTop = v->stackIndex;

	// 	_integer(t, stackTop);

	// 	for(auto &val: v->stack.slice(0, stackTop))
	// 		_serialize(t, val);
	// }

	// void _serializeCallStack(CrocThread* t, CrocThread* v)
	// {
	// 	// version(CrocExtendedThreads) {} else
	// 		_integer(t, v->savedCallDepth);

	// 	_integer(t, v->arIndex);

	// 	for(auto &rec: v->actRecs.slice(0, v->arIndex))
	// 	{
	// 		_integer(t, rec.base);
	// 		_integer(t, rec.savedTop);
	// 		_integer(t, rec.vargBase);
	// 		_integer(t, rec.returnSlot);

	// 		if(rec.func == nullptr)
	// 			_writeUInt8(t, 0);
	// 		else
	// 		{
	// 			_writeUInt8(t, 1);
	// 			_serialize(t, rec.func);
	// 			uword diff = rec.pc - rec.func->scriptFunc->code.ptr;
	// 			_integer(t, diff);
	// 		}

	// 		_integer(t, rec.numReturns);
	// 		_integer(t, rec.numTailcalls);
	// 		_integer(t, rec.firstResult);
	// 		_integer(t, rec.numResults);
	// 		_integer(t, rec.unwindCounter);

	// 		if(rec.unwindReturn)
	// 		{
	// 			_writeUInt8(t, 1);
	// 			uword diff = rec.unwindReturn - rec.func->scriptFunc->code.ptr;
	// 			_integer(t, diff);
	// 		}
	// 		else
	// 			_writeUInt8(t, 0);
	// 	}
	// }

	// void _serializeEHStack(CrocThread* t, CrocThread* v)
	// {
	// 	_integer(t, v.trIndex);

	// 	foreach(ref rec; v.tryRecs[0 .. v.trIndex])
	// 	{
	// 		_writeUInt8(t, cast(uint8_t)rec.isCatch);
	// 		_integer(t, rec.slot);
	// 		_integer(t, rec.actRecord);

	// 		uword diff = rec.pc - v.actRecs[rec.actRecord].func.scriptFunc.code.ptr;
	// 		_integer(t, diff);
	// 	}
	// }

	// void _serializeResultStack(CrocThread* t, CrocThread* v)
	// {
	// 	_integer(t, v.resultIndex);

	// 	foreach(ref val; v.results[0 .. v.resultIndex])
	// 		_serialize(t, val);
	// }

	// void _serializeCoroFunc(CrocThread* t, CrocThread* v)
	// {
	// 	if(v.coroFunc)
	// 	{
	// 		_writeUInt8(t, 1);
	// 		_serialize(t, v.coroFunc);
	// 	}
	// 	else
	// 		_writeUInt8(t, 0);
	// }

	// void _serializeUpvals(CrocThread* t, CrocThread* v)
	// {
	// 	uword numUpvals = 0;

	// 	for(auto uv = t.upvalHead; uv !is null; uv = uv.nextuv)
	// 		numUpvals++;

	// 	_integer(t, numUpvals);

	// 	for(auto uv = t.upvalHead; uv !is null; uv = uv.nextuv)
	// 	{
	// 		assert(uv.value !is &uv.closedValue);
	// 		_serialize(t, CrocValue(cast(CrocBaseObject*)uv));
	// 		uword diff = uv.value - v.stack.ptr;
	// 		_integer(t, diff);
	// 	}
	// }

	// word_t _nativeSerializeThread(CrocThread* t)
	// {
	// 	auto v = getThread(t, 1);

	// 	if(t is v)
	// 		croc_eh_throwStd(t, "ValueError", "Attempting to serialize the currently-executing thread");

	// 	version(CrocExtendedThreads)
	// 		croc_eh_throwStd(t, "ValueError", "Attempting to serialize an extended thread");

	// 	if(v.nativeCallDepth > 0)
	// 	{
	// 		croc_eh_throwStd(t, "ValueError",
	// 			"Attempting to serialize a thread with at least one native or metamethod call on its call stack");
	// 	}

	// 	if(v.hookFunc !is null)
	// 		croc_eh_throwStd(t, "ValueError", "Attempting to serialize a thread with a debug hook function");

	// 	_writeUInt8(t, cast(uint8_t)v.shouldHalt);
	// 	_integer(t, v.state);

	// 	_serializeStack(t, v);

	// 	_integer(t, v.numYields);

	// 	_serializeResultStack(t, v);
	// 	_serializeCallStack(t, v);
	// 	_serializeEHStack(t, v);
	// 	_serializeCoroFunc(t, v);
	// 	_serializeUpvals(t, v);

	// 	return 0;
	// }

	word_t _serializeUpval(CrocThread* t)
	{
		if(!croc_isValidIndex(t, 1))
		{
			croc_eh_throwStd(t, "ParamError", "Too few parameters (expected at least 1, got %" CROC_SIZE_T_FORMAT ")",
				croc_getStackSize(t) - 1);
		}

		auto uv = *getValue(Thread::from(t), 1);

		if(uv.type != CrocType_Upval)
			croc_eh_throwStd(t, "TypeError", "Expected upval for parameter");

		croc_dup(t, 0);
		croc_pushNull(t);
		croc_dup(t, 1);
		croc_methodCall(t, -3, "_alreadyWritten", 1);

		if(croc_getBool(t, -1))
			return 0;

		croc_popTop(t);

		croc_dup(t, 0);
		croc_pushNull(t);
		croc_pushInt(t, CrocType_Upval);
		croc_methodCall(t, -3, "_tag", 0);

		croc_dup(t, 0);
		croc_pushNull(t);
		push(Thread::from(t), *(cast(Upval*)uv.mGCObj)->value);
		croc_methodCall(t, -3, "_serialize", 0);

		return 0;
	}

	word_t _instSize(CrocThread* t)
	{
		croc_pushInt(t, getInstance(Thread::from(t), 1)->parent->numInstanceFields * sizeof(Array::Slot));
		return 1;
	}
	}

	namespace Deser
	{
	const char* _Input = "_input";
	const char* _RawBuf = "_rawBuf";
	const char* _Trans = "_trans";
	const char* _ObjTable = "_objTable";
	const char* _DummyObj = "_dummyObj";
	const char* _DeserializeFunc = "_deserializeFunc";

	word_t _readGraph(CrocThread* t)
	{
		if(!croc_isValidIndex(t, 1))
		{
			croc_eh_throwStd(t, "ParamError", "Too few parameters (expected at least 1, got %" CROC_SIZE_T_FORMAT ")",
				croc_getStackSize(t) - 1);
		}

		if(!croc_isTable(t, 1) && !croc_isInstance(t, 1))
		{
			croc_pushTypeString(t, 1);
			croc_eh_throwStd(t, "TypeError", "Expected type 'table|instance' for parameter 1, not '%s'",
				croc_getString(t, -1));
		}

		croc_dup(t, 1);       croc_fielda(t, 0, _Trans);
		croc_array_new(t, 0); croc_fielda(t, 0, _ObjTable);
		croc_table_new(t, 0); croc_fielda(t, 0, _DummyObj);

		Thread::from(t)->vm->disableGC();

		auto slot = croc_pushNull(t);
		auto failed = tryCode(Thread::from(t), slot, [&]
		{
			croc_dup(t, 0);
			croc_pushNull(t);
			croc_methodCall(t, -2, "_readSignature", 0);
			croc_dup(t, 0);
			croc_pushNull(t);
			croc_methodCall(t, -2, "_deserialize", 1);
		});

		Thread::from(t)->vm->enableGC();
		croc_field(t, 0, _ObjTable);
		croc_lenai(t, -1, 0);
		croc_popTop(t);
		croc_pushNull(t);
		croc_fielda(t, 0, _DummyObj);

		if(failed)
			croc_eh_rethrow(t);

		croc_remove(t, -2); // eh slot
		croc_gc_collectFull(t);
		return 1;
	}

	crocint _integer(CrocThread* t)
	{
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "_integer", 1);
		auto ret = croc_getInt(t, -1);
		croc_popTop(t);
		return ret;
	}

	uword _length(CrocThread* t)
	{
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "_length", 1);
		auto ret = cast(uword)croc_getInt(t, -1);
		croc_popTop(t);
		return ret;
	}

	word _deserialize(CrocThread* t)
	{
		auto ret = croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "_deserialize", 1);
		return ret;
	}

	uint8_t _readUInt8(CrocThread* t)
	{
		croc_field(t, 0, _Input);
		croc_pushNull(t);
		croc_methodCall(t, -2, "readUInt8", 1);
		auto ret = cast(uint8_t)croc_getInt(t, -1);
		croc_popTop(t);
		return ret;
	}

	void _readBlock(CrocThread* t, DArray<uint8_t> arr)
	{
		croc_field(t, 0, _Input);
		croc_pushNull(t);
		croc_field(t, 0, _RawBuf);
		croc_memblock_reviewNativeArray(t, -1, arr.ptr, arr.length);
		croc_methodCall(t, -3, "readExact", 0);
	}

	void _addObject(CrocThread* t, GCObject* obj)
	{
		croc_dup(t, 0);
		croc_pushNull(t);
		push(Thread::from(t), Value::from(obj));
		croc_methodCall(t, -3, "_addObject", 0);
	}

	void _deserializeObj(CrocThread* t, const char* methodName)
	{
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, methodName, 1);
	}

	String* _deserializeString(CrocThread* t)
	{
		_deserializeObj(t, "_deserializeString");
		auto ret = getStringObj(Thread::from(t), -1);
		croc_popTop(t);
		return ret;
	}

	word_t _deserializeNamespaceImpl(CrocThread* t)
	{
		auto t_ = Thread::from(t);
		auto ret = Namespace::createPartial(t_->vm->mem);
		_addObject(t, cast(GCObject*)ret);

		auto name = _deserializeString(t);
		Namespace* parent = nullptr;

		if(_readUInt8(t) != 0)
		{
			_deserializeObj(t, "_deserializeNamespace");
			parent = getNamespace(t_, -1); assert(parent != nullptr);
			croc_popTop(t);
		}

		Namespace::finishCreate(ret, name, parent);
		push(t_, Value::from(ret));

		auto len = _length(t);

		for(uword i = 0; i < len; i++)
		{
			_deserializeObj(t, "_deserializeString");
			_deserialize(t);
			croc_fieldaStk(t, -3);
		}

		return 1;
	}

	word_t _deserializeFunctionImpl(CrocThread* t)
	{
		auto t_ = Thread::from(t);
		auto numUpvals = _length(t);
		auto ret = Function::createPartial(t_->vm->mem, numUpvals);
		_addObject(t, cast(GCObject*)ret);

		_deserializeObj(t, "_deserializeFuncdef");

		if(_readUInt8(t) != 0)
			_deserializeObj(t, "_deserializeNamespace");
		else
			push(t_, Value::from(t_->vm->globals));

		auto def = getFuncdef(t_, -2);   assert(def != nullptr);
		auto env = getNamespace(t_, -1); assert(env != nullptr);
		Function::finishCreate(t_->vm->mem, ret, env, def);
		croc_pop(t, 2);

		for(auto &val: ret->scriptUpvals())
		{
			_deserializeObj(t, "_deserializeUpval");
			val = cast(Upval*)getValue(t_, -1)->mGCObj;
			croc_popTop(t);
		}

		push(t_, Value::from(ret));
		return 1;
	}

	word_t _deserializeFuncdefImpl(CrocThread* t)
	{
		auto t_ = Thread::from(t);
		auto def = Funcdef::create(t_->vm->mem);
		_addObject(t, cast(GCObject*)def);

		def->locFile = _deserializeString(t);
		def->locLine = _length(t);
		def->locCol = _length(t);
		def->isVararg = cast(bool)_readUInt8(t);
		def->name = _deserializeString(t);
		def->numParams = _length(t);

		def->paramMasks.resize(t_->vm->mem, _length(t));

		for(auto &mask: def->paramMasks)
			mask = _length(t);

		def->upvals.resize(t_->vm->mem, _length(t));

		for(auto &uv: def->upvals)
		{
			uv.isUpval = cast(bool)_readUInt8(t);
			uv.index = _length(t);
		}

		def->stackSize = _length(t);

		def->innerFuncs.resize(t_->vm->mem, _length(t));

		for(auto &func: def->innerFuncs)
		{
			_deserializeObj(t, "_deserializeFuncdef");
			func = getFuncdef(t_, -1); assert(func != nullptr);
			croc_popTop(t);
		}

		def->constants.resize(t_->vm->mem, _length(t));

		for(auto &val: def->constants)
		{
			_deserialize(t);
			val = *getValue(t_, -1);
			croc_popTop(t);
		}

		def->code.resize(t_->vm->mem, _length(t));
		_readBlock(t, def->code.template as<uint8_t>());

		if(_readUInt8(t) != 0)
		{
			_deserializeObj(t, "_deserializeNamespace");
			def->environment = getNamespace(t_, -1); assert(def->environment != nullptr);
			croc_popTop(t);
		}

		if(_readUInt8(t) != 0)
		{
			_deserializeObj(t, "_deserializeFunction");
			def->cachedFunc = getFunction(t_, -1); assert(def->cachedFunc != nullptr);
			croc_popTop(t);
		}

		def->switchTables.resize(t_->vm->mem, _length(t));

		for(auto &st: def->switchTables)
		{
			auto numOffsets = _length(t);

			for(uword i = 0; i < numOffsets; i++)
			{
				_deserialize(t);
				auto offs = cast(word)_integer(t);
				*st.offsets.insert(t_->vm->mem, *getValue(t_, -1)) = offs;
				croc_popTop(t);
			}

			st.defaultOffset = cast(word)_integer(t);
		}

		def->lineInfo.resize(t_->vm->mem, _length(t));
		_readBlock(t, def->lineInfo.template as<uint8_t>());

		def->upvalNames.resize(t_->vm->mem, _length(t));

		for(auto &name: def->upvalNames)
			name = _deserializeString(t);

		def->locVarDescs.resize(t_->vm->mem, _length(t));

		for(auto &desc: def->locVarDescs)
		{
			desc.name = _deserializeString(t);
			desc.pcStart = _length(t);
			desc.pcEnd = _length(t);
			desc.reg = _length(t);
		}

		push(t_, Value::from(def));
		return 1;
	}

	word_t _deserializeClassImpl(CrocThread* t)
	{
		auto t_ = Thread::from(t);
		auto v = Class::create(t_->vm->mem, nullptr);
		_addObject(t, cast(GCObject*)v);

		v->name = _deserializeString(t);

		auto numMethods = _length(t);

		for(uword i = 0; i < numMethods; i++)
		{
			auto name = _deserializeString(t);
			_deserialize(t);

			if(!v->addMethod(t_->vm->mem, name, *getValue(t_, -1), false))
			{
				croc_eh_throwStd(t, "ValueError", "Malformed data (class %s already has a method '%s')",
					v->name->toCString(), name->toCString());
			}

			croc_popTop(t);
		}

		auto numFields = _length(t);

		for(uword i = 0; i < numFields; i++)
		{
			auto name = _deserializeString(t);
			_deserialize(t);

			if(!v->addField(t_->vm->mem, name, *getValue(t_, -1), false))
			{
				croc_eh_throwStd(t, "ValueError", "Malformed data (class %s already has a field '%s')",
					v->name->toCString(), name->toCString());
			}

			croc_popTop(t);
		}

		auto numHiddenFields = _length(t);

		for(uword i = 0; i < numHiddenFields; i++)
		{
			auto name = _deserializeString(t);
			_deserialize(t);

			if(!v->addHiddenField(t_->vm->mem, name, *getValue(t_, -1)))
			{
				croc_eh_throwStd(t, "ValueError", "Malformed data (class %s already has a hidden field '%s')",
					v->name->toCString(), name->toCString());
			}

			croc_popTop(t);
		}

		if(_readUInt8(t) != 0)
			v->freeze(t_->vm->mem);

		push(t_, Value::from(v));
		return 1;
	}

	word_t _deserializeInstanceImpl(CrocThread* t)
	{
		auto t_ = Thread::from(t);
		auto size = _length(t);

		if(size < sizeof(Instance) || size >= (1 << 20)) // 1MB should be a reasonably insane upper bound :P
			croc_eh_throwStd(t, "ValueError", "Malformed data (invalid instance size)");

		auto v = Instance::createPartial(t_->vm->mem, size, false); // always false for now, might change later
		_addObject(t, cast(GCObject*)v);

		_deserializeObj(t, "_deserializeClass");
		auto parent = getClass(t_, -1); assert(parent != nullptr);

		if(!parent->isFrozen)
			croc_eh_throwStd(t, "ValueError", "Malformed data (instance of an unfrozen class somehow exists)");

		if(!Instance::finishCreate(v, parent))
			croc_eh_throwStd(t, "ValueError",
				"Malformed data (instance size %" CROC_SIZE_T_FORMAT
					" does not match base class size %" CROC_SIZE_T_FORMAT ")",
				v->memSize, sizeof(Instance) + parent->numInstanceFields * sizeof(Array::Slot));

		if(_readUInt8(t) != 0)
		{
			push(t_, Value::from(v));

			if(!croc_hasMethod(t, -1, "opDeserialize"))
			{
				croc_pushTypeString(t, -1);
				croc_eh_throwStd(t, "ValueError",
					"'%s' was serialized with opSerialize, but does not have a matching opDeserialize",
					croc_getString(t, -1));
			}

			croc_pushNull(t);
			croc_field(t, 0, _Input);
			croc_field(t, 0, _DeserializeFunc);
			croc_methodCall(t, -4, "opDeserialize", 0);
		}
		else
		{
			auto numFields = _length(t);

			for(uword i = 0; i < numFields; i++)
			{
				auto name = _deserializeString(t);
				_deserialize(t);

				if(v->getField(name) == nullptr)
				{
					croc_eh_throwStd(t, "ValueError", "Malformed data (no field '%s' in instance of class '%s')",
						name->toCString(), parent->name->toCString());
				}

				v->setField(t_->vm->mem, name, *getValue(t_, -1));
				croc_popTop(t);
			}

			auto numHiddenFields = _length(t);

			for(uword i = 0; i < numHiddenFields; i++)
			{
				auto name = _deserializeString(t);
				_deserialize(t);

				if(v->getHiddenField(name) == nullptr)
				{
					croc_eh_throwStd(t, "ValueError", "Malformed data (no hidden field '%s' in instance of class '%s')",
						name->toCString(), parent->name->toCString());
				}

				v->setHiddenField(t_->vm->mem, name, *getValue(t_, -1));
				croc_popTop(t);
			}
		}

		push(t_, Value::from(v));
		return 1;
	}

	word_t _limitedSize(CrocThread* t, uword max, const char* msg)
	{
		auto ret = _length(t);

		if(ret >= max)
			croc_eh_throwStd(t, "ValueError", "Malformed data (%s)", msg);

		return ret;
	}

	// void _deserializeStack(CrocThread* t, CrocThread* ret)
	// {
	// 	// TODO: define some "max stack size" for threads so that we know when stuff is borked
	// 	auto stackIndex = _limitedSize(t, 100_000, "invalid thread stack size");
	// 	auto stackBase = _limitedSize(t, stackIndex, "invalid thread stack base");
	// 	auto stackTop = _limitedSize(t, 100_000, "invalid thread stack top");

	// 	t_->vm->mem.resizeArray(ret.stack, stackTop < 20 ? 20 : stackTop);
	// 	ret.stackIndex = stackIndex;
	// 	ret.stackBase = stackBase;

	// 	foreach(ref val; ret.stack[0 .. stackTop])
	// 	{
	// 		_deserialize(t);
	// 		val = *getValue(t_, -1);
	// 		croc_popTop(t);
	// 	}
	// }

	// void _deserializeActRec(CrocThread* t, CrocThread* ret, ref ActRecord rec)
	// {
	// 	rec.base = _limitedSize(t, ret.stackIndex, "invalid call record base slot");
	// 	rec.savedTop = _limitedSize(t, 100_000, "invalid call record saved top slot");
	// 	rec.vargBase = _limitedSize(t, rec.base + 1, "invalid call record variadic base slot");
	// 	rec.returnSlot = _limitedSize(t, 100_000, "invalid call record return value slot");

	// 	if(_readUInt8(t))
	// 	{
	// 		_deserializeObj(t, "_deserializeFunction");
	// 		rec.func = getFunction(t, -1);
	// 		croc_popTop(t);

	// 		auto diff = _limitedSize(t, rec.func.scriptFunc.code.length, "invalid call record instruction pointer");
	// 		rec.pc = rec.func.scriptFunc.code.ptr + diff;
	// 	}
	// 	else
	// 	{
	// 		rec.func = nullptr;
	// 		rec.pc = nullptr;
	// 	}

	// 	rec.numReturns = cast(word)_integer(t);

	// 	if(rec.numReturns < -1 || rec.numReturns > 100_000)
	// 		croc_eh_throwStd(t, "ValueError", "Malformed data (invalid call record number of returns)");

	// 	rec.numTailcalls = _length(t);
	// 	rec.firstResult = _length(t);

	// 	if(ret.resultIndex > 0 && rec.firstResult >= ret.resultIndex)
	// 		croc_eh_throwStd(t, "ValueError", "Malformed data (invalid call record result index)");

	// 	rec.numResults = _length(t);

	// 	if(rec.numResults > 0 && rec.numResults > (ret.resultIndex - rec.firstResult))
	// 		croc_eh_throwStd(t, "ValueError", "Malformed data (invalid call record number of results)");

	// 	rec.unwindCounter = _length(t); // check later

	// 	if(_readUInt8(t))
	// 	{
	// 		auto diff = _limitedSize(t, rec.func.scriptFunc.code.length, "invalid call record EH return pointer");
	// 		rec.unwindReturn = rec.func.scriptFunc.code.ptr + diff;
	// 	}
	// 	else
	// 		rec.unwindReturn = nullptr;
	// }

	// void _checkActRecs(CrocThread* t, CrocThread* ret)
	// {
	// 	auto ars = ret.actRecs[0 .. ret.arIndex];

	// 	// forall act rec i:
	// 	foreach(i, ar; ars)
	// 	{
	// 		auto prevBase = (i > 0) ? ars[i - 1].base : 0;
	// 		auto nextBase = (i + 1 < ars.length) ? ars[i + 1].base : ret.stackIndex;

	// 		// base_i <= base_(i + 1)
	// 		if(ar.base > nextBase)
	// 			croc_eh_throwStd(t, "ValueError", "invalid call record base slot");

	// 		// base_(i-1) <= returnSlot_i < base_(i + 1)
	// 		// TODO: determine if this is actually true :P

	// 		// unwindCounter_i <= number of EH frames this call record has
	// 		// TODO:
	// 	}
	// }

	// void _deserializeCallStack(CrocThread* t, CrocThread* ret)
	// {
	// 	// TODO: define some "recursion limit" for threads so that we know when stuff is borked

	// 	version(CrocExtendedThreads) {} else
	// 		ret.savedCallDepth = _limitedSize(t, 100_000, "invalid thread saved call stack size");

	// 	ret.arIndex = _limitedSize(t, 100_000, "invalid thread call stack size");

	// 	t_->vm->mem.resizeArray(ret.actRecs, ret.arIndex < 10 ? 10 : ret.arIndex);

	// 	if(ret.arIndex > 0)
	// 		ret.currentAR = &ret.actRecs[ret.arIndex - 1];
	// 	else
	// 		ret.currentAR = nullptr;

	// 	foreach(ref rec; ret.actRecs[0 .. ret.arIndex])
	// 		_deserializeActRec(t, ret, rec);

	// 	_checkActRecs(t, ret);
	// }

	// void _deserializeEHStack(CrocThread* t, CrocThread* ret)
	// {
	// 	// TODO: define some EH frame limit so that we know when stuff is borked
	// 	ret.trIndex = _limitedSize(t, 5_000, "invalid thread exception handling stack size");
	// 	t_->vm->mem.resizeArray(ret.tryRecs, ret.trIndex < 10 ? 10 : ret.trIndex);

	// 	if(ret.trIndex > 0)
	// 		ret.currentTR = &ret.tryRecs[ret.trIndex - 1];
	// 	else
	// 		ret.currentTR = nullptr;

	// 	foreach(ref rec; ret.tryRecs[0 .. ret.trIndex])
	// 	{
	// 		rec.isCatch = cast(bool)_readUInt8(t);
	// 		rec.slot = _limitedSize(t, ret.stackIndex, "invalid thread EH frame stack slot");
	// 		rec.actRecord = _limitedSize(t, ret.arIndex, "invalid thread EH frame call record index");

	// 		auto func = ret.actRecs[rec.actRecord].func;

	// 		if(func == nullptr || func.isNative)
	// 			croc_eh_throwStd(t, "ValueError", "Malformed data (invalid thread EH frame call record index)");

	// 		auto diff = _limitedSize(t, func.scriptFunc.code.length, "invalid thread EH frame instruction pointer");
	// 		rec.pc = func.scriptFunc.code.ptr + diff;
	// 	}
	// }

	// void _deserializeResultStack(CrocThread* t, CrocThread* ret)
	// {
	// 	// TODO: define some result stack limit
	// 	ret.resultIndex = _limitedSize(t, 10_000, "invalid thread result stack size");
	// 	t_->vm->mem.resizeArray(ret.results, ret.resultIndex < 8 ? 8 : ret.resultIndex);

	// 	foreach(ref val; ret.results[0 .. ret.resultIndex])
	// 	{
	// 		_deserialize(t);
	// 		val = *getValue(t_, -1);
	// 		croc_popTop(t);
	// 	}
	// }

	// void _deserializeCoroFunc(CrocThread* t, CrocThread* ret)
	// {
	// 	if(_readUInt8(t))
	// 	{
	// 		_deserializeObj(t, "_deserializeFunction");
	// 		auto func = getFunction(t, -1);

	// 		if(func.isNative)
	// 			croc_eh_throwStd(t, "ValueError", "Malformed data (invalid thread main function)");

	// 		ret.coroFunc = func;
	// 		croc_popTop(t);
	// 	}
	// 	else
	// 		ret.coroFunc = nullptr;
	// }

	// void _deserializeUpvals(CrocThread* t, CrocThread* ret)
	// {
	// 	// TODO: define an upval stack size or something
	// 	auto numUpvals = _limitedSize(t, 100_000, "invalid thread upval stack size");

	// 	CrocUpval* cur = nullptr;
	// 	auto next = &t.upvalHead;

	// 	for(uword i = 0; i < numUpvals; i++)
	// 	{
	// 		_deserializeObj(t, "_deserializeUpvalue");
	// 		auto uv = cast(CrocUpval*)getValue(t_, -1).mBaseObj;
	// 		croc_popTop(t);

	// 		auto diff = _limitedSize(t, ret.stackIndex, "invalid thread upval slot");
	// 		uv.value = ret.stack.ptr + diff;

	// 		if(cur && uv.value <= cur.value)
	// 			croc_eh_throwStd(t, "ValueError", "Malformed data (invalid thread upval list)");

	// 		*next = uv;
	// 		next = &uv.nextuv;
	// 		cur = uv;
	// 	}

	// 	*next = nullptr;
	// }

	// word_t _deserializeThreadImpl(CrocThread* t)
	// {
	// 	version(CrocExtendedThreads)
	// 		croc_eh_throwStd(t, "ValueError", "Attempting to deserialize a thread while extended threads were compiled in");

	// 	auto ret = thread.createPartial(t.vm);
	// 	_addObject(t, cast(GCObject*)ret);

	// 	ret.shouldHalt = cast(bool)_readUInt8(t);

	// 	auto state = _limitedSize(t, CrocThread.State.max + 1, "invalid thread state");

	// 	if(state == CrocThread.State.Running)
	// 		croc_eh_throwStd(t, "ValueError", "Malformed data (invalid thread state)");

	// 	ret.state = cast(CrocThread.State)state;

	// 	_deserializeStack(t, ret);

	// 	ret.numYields = _limitedSize(t, ret.stackIndex, "invalid yield count");

	// 	_deserializeResultStack(t, ret);
	// 	_deserializeCallStack(t, ret);
	// 	_deserializeEHStack(t, ret);
	// 	_deserializeCoroFunc(t, ret);
	// 	_deserializeUpvals(t, ret);

	// 	pushThread(t, ret);
	// 	return 1;
	// }

	word_t _deserializeUpvalImpl(CrocThread* t)
	{
		auto t_ = Thread::from(t);
		auto uv = ALLOC_OBJ(t_->vm->mem, Upval);
		uv->type = CrocType_Upval;
		uv->nextuv = nullptr;
		uv->value = &uv->closedValue;
		_addObject(t, cast(GCObject*)uv);
		_deserialize(t);
		uv->closedValue = *getValue(t_, -1);
		push(t_, Value::from(cast(GCObject*)uv));
		return 1;
	}
	}

	CrocRegisterFunc _serializeFuncs[] =
	{
		{"_nativeSerializeFunction", 1, &Ser::_nativeSerializeFunction},
		{"_nativeSerializeFuncdef",  1, &Ser::_nativeSerializeFuncdef },
		{"_nativeSerializeClass",    1, &Ser::_nativeSerializeClass   },
		{"_nativeSerializeInstance", 1, &Ser::_nativeSerializeInstance},
		// {"_nativeSerializeThread",   1, &Ser::_nativeSerializeThread  },
		{"_serializeUpval",          1, &Ser::_serializeUpval       },
		{"_instSize",                1, &Ser::_instSize               },
		{nullptr, 0, nullptr}
	};

	CrocRegisterFunc _deserializeFuncs[] =
	{
		{"_deserializeNamespaceImpl", 0, &Deser::_deserializeNamespaceImpl},
		{"_deserializeFunctionImpl",  0, &Deser::_deserializeFunctionImpl },
		{"_deserializeFuncdefImpl",   0, &Deser::_deserializeFuncdefImpl  },
		{"_deserializeClassImpl",     0, &Deser::_deserializeClassImpl    },
		{"_deserializeInstanceImpl",  0, &Deser::_deserializeInstanceImpl },
		// {"_deserializeThreadImpl",    0, &Deser::_deserializeThreadImpl   },
		{"_deserializeUpvalImpl",     0, &Deser::_deserializeUpvalImpl    },
		{"readGraph",                 1, &Deser::_readGraph               },
		{nullptr, 0, nullptr}
	};
	}

	void initSerializationLib(CrocThread* t)
	{
		croc_table_new(t, 0);
			croc_table_new(t, 0);
				croc_pushInt(t, 254);                croc_fielda(t, -2, "transient");
				croc_pushInt(t, 255);                croc_fielda(t, -2, "backref");

				croc_pushInt(t, CrocType_Null);      croc_fielda(t, -2, "null");
				croc_pushInt(t, CrocType_Bool);      croc_fielda(t, -2, "bool");
				croc_pushInt(t, CrocType_Int);       croc_fielda(t, -2, "int");
				croc_pushInt(t, CrocType_Float);     croc_fielda(t, -2, "float");

				croc_pushInt(t, CrocType_Nativeobj); croc_fielda(t, -2, "nativeobj");
				croc_pushInt(t, CrocType_String);    croc_fielda(t, -2, "string");
				croc_pushInt(t, CrocType_Weakref);   croc_fielda(t, -2, "weakref");

				croc_pushInt(t, CrocType_Table);     croc_fielda(t, -2, "table");
				croc_pushInt(t, CrocType_Namespace); croc_fielda(t, -2, "namespace");
				croc_pushInt(t, CrocType_Array);     croc_fielda(t, -2, "array");
				croc_pushInt(t, CrocType_Memblock);  croc_fielda(t, -2, "memblock");
				croc_pushInt(t, CrocType_Function);  croc_fielda(t, -2, "function");
				croc_pushInt(t, CrocType_Funcdef);   croc_fielda(t, -2, "funcdef");
				croc_pushInt(t, CrocType_Class);     croc_fielda(t, -2, "class");
				croc_pushInt(t, CrocType_Instance);  croc_fielda(t, -2, "instance");
				croc_pushInt(t, CrocType_Thread);    croc_fielda(t, -2, "thread");

				croc_pushInt(t, CrocType_Upval);     croc_fielda(t, -2, "upval");
			croc_fielda(t, -2, "TypeTags");

			croc_table_new(t, 0);
				croc_ex_registerFields(t, _serializeFuncs);
			croc_fielda(t, -2, "ExtraSerializeMethods");

			croc_table_new(t, 0);
				croc_ex_registerFields(t, _deserializeFuncs);
			croc_fielda(t, -2, "ExtraDeserializeMethods");

			union
			{
				uint32_t i;
				char c[4];
			} test = {0x01020304};

			croc_pushInt(t, test.c[0] == 4 ? 0 : 1); // 1 for big-endian, 0 for little
			croc_fielda(t, -2, "Endianness");

			croc_pushInt(t, sizeof(uword) * 8);
			croc_fielda(t, -2, "PlatformBits");
		croc_newGlobal(t, "_serializationtmp");

		croc_ex_importFromString(t, "serialization", serialization_croc_text, "serialization.croc");

		croc_pushGlobal(t, "_G");
		croc_pushString(t, "_serializationtmp");
		croc_removeKey(t, -2);
		croc_popTop(t);

// 		croc_ex_makeModule(t, "json", &loader);
// 		croc_ex_importNS(t, "json");
// #ifdef CROC_BUILTIN_DOCS
// 		CrocDoc doc;
// 		croc_ex_doc_init(t, &doc, __FILE__);
// 		croc_ex_doc_push(&doc,
// 		DModule("json")
// 		R"(\link[http://en.wikipedia.org/wiki/JSON]{JSON} is a standard for structured data interchange based on the
// 		JavaScript object notation. This library allows you to convert to and from JSON.)");
// 			docFields(&doc, _globalFuncs);
// 		croc_ex_doc_pop(&doc, -1);
// 		croc_ex_doc_finish(&doc);
// #endif
// 		croc_popTop(t);
	}
}