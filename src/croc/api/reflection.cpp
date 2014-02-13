
#include "croc/api.h"
#include "croc/internal/apichecks.hpp"
#include "croc/internal/basic.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

namespace croc
{
extern "C"
{
	const char* croc_getNameOf(CrocThread* t_, word_t obj)
	{
		auto t = Thread::from(t_);
		auto v = *getValue(t, obj);

		switch(v.type)
		{
			case CrocType_Function:  return v.mFunction->name->toCString();
			case CrocType_Class:     return v.mClass->name->toCString();
			case CrocType_Namespace: return v.mNamespace->name->toCString();
			case CrocType_Funcdef:   return v.mFuncdef->name->toCString();
			default: API_PARAM_TYPE_ERROR(obj, "obj", "namespace|function|funcdef|class");
			assert(false);
		}
	}

	const char* croc_getNameOfn(CrocThread* t_, word_t obj, uword_t* len)
	{
		auto t = Thread::from(t_);
		auto v = *getValue(t, obj);
		String* name;

		switch(v.type)
		{
			case CrocType_Function:  name = v.mFunction->name; break;
			case CrocType_Class:     name = v.mClass->name; break;
			case CrocType_Namespace: name = v.mNamespace->name; break;
			case CrocType_Funcdef:   name = v.mFuncdef->name; break;
			default: API_PARAM_TYPE_ERROR(obj, "obj", "namespace|function|funcdef|class");
			assert(false);
		}

		*len = name->length;
		return name->toCString();
	}

	namespace
	{
		int hasFieldImpl(Value v, String* name)
		{
			switch(v.type)
			{
				case CrocType_Table:     return v.mTable->get(Value::from(name)) != nullptr;
				case CrocType_Class:     return v.mClass->getField(name) != nullptr;
				case CrocType_Instance:  return v.mInstance->getField(name) != nullptr;
				case CrocType_Namespace: return v.mNamespace->get(name) != nullptr;
				default:                 return false;
			}
		}
	}

	int croc_hasField(CrocThread* t_, word_t obj, const char* fieldName)
	{
		auto t = Thread::from(t_);
		auto v = *getValue(t, obj);
		auto name = String::create(t->vm, atoda(fieldName));
		return hasFieldImpl(v, name);
	}

	int croc_hasFieldStk(CrocThread* t_, word_t obj, word_t name)
	{
		auto t = Thread::from(t_);
		auto v = *getValue(t, obj);
		API_CHECK_PARAM(nameStr, name, String, "field name");
		return hasFieldImpl(v, nameStr);
	}

	int croc_hasMethod(CrocThread* t_, word_t obj, const char* methodName)
	{
		auto t = Thread::from(t_);
		auto name = String::create(t->vm, atoda(methodName));
		return lookupMethod(t, *getValue(t, obj), name).type != CrocType_Null;
	}

	int croc_hasMethodStk(CrocThread* t_, word_t obj, word_t name)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(nameStr, name, String, "method name");
		return lookupMethod(t, *getValue(t, obj), nameStr).type != CrocType_Null;
	}

	int croc_isInstanceOf(CrocThread* t_, word_t obj, word_t base)
	{
		auto t = Thread::from(t_);
		auto inst = *getValue(t, obj);
		API_CHECK_PARAM(cls, base, Class, "base");
		return inst.type == CrocType_Instance && inst.mInstance->parent == cls;
	}

	word_t croc_superOf(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		return push(t, superOfImpl(t, *getValue(t, slot)));
	}
}
}