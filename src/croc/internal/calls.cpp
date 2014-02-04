
#include "croc/base/metamethods.hpp"
#include "croc/internal/calls.hpp"

namespace croc
{
	Namespace* getEnv(Thread* t, uword depth)
	{
		if(t->arIndex == 0)
			return t->vm->globals;
		else if(depth == 0)
			return t->currentAR->func->environment;

		for(word idx = t->arIndex - 1; idx >= 0; idx--)
		{
			if(depth == 0)
				return t->actRecs[cast(uword)idx].func->environment;
			else if(depth <= t->actRecs[cast(uword)idx].numTailcalls)
				assert(false); // TODO:ex
				// throwStdException(t, "RuntimeError", "Attempting to get environment of function whose activation record was overwritten by a tail call");

			depth -= (t->actRecs[cast(uword)idx].numTailcalls + 1);
		}

		return t->vm->globals;
	}

	Value lookupMethod(Thread* t, Value v, String* name)
	{
		switch(v.type)
		{
			case CrocType_Class:
				if(auto ret = v.mClass->getMethod(name))
					return ret->value;
				else
					return Value::nullValue;

			case CrocType_Instance:
				return getInstanceMethod(t, v.mInstance, name);

			case CrocType_Namespace:
				if(auto ret = v.mNamespace->get(name))
					return *ret;
				else
					return Value::nullValue;

			case CrocType_Table:
				if(auto ret = v.mTable->get(Value::from(name)))
					return *ret;
				// fall through
			default:
				return getGlobalMetamethod(t, v.type, name);
		}
	}

	Value getInstanceMethod(Thread* t, Instance* inst, String* name)
	{
		(void)t;
		if(auto ret = inst->getMethod(name))
			return ret->value;
		else
			return Value::nullValue;
	}

	Value getGlobalMetamethod(Thread* t, CrocType type, String* name)
	{
		if(auto mt = getMetatable(t, type))
		{
			if(auto ret = mt->get(name))
				return *ret;
		}

		return Value::nullValue;
	}

	Function* getMM(Thread* t, Value obj, Metamethod method)
	{
		auto name = t->vm->metaStrings[method];
		Value ret;

		if(obj.type == CrocType_Instance)
			ret = getInstanceMethod(t, obj.mInstance, name);
		else
			ret = getGlobalMetamethod(t, obj.type, name);

		if(ret.type == CrocType_Function)
			return ret.mFunction;

		return nullptr;
	}

	Namespace* getMetatable(Thread* t, CrocType type)
	{
		// ORDER CROCTYPE
		assert(type >= CrocType_FirstUserType && type <= CrocType_LastUserType);
		return t->vm->metaTabs[type];
	}
}