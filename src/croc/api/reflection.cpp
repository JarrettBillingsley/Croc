
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/basic.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** \returns the name of the value at slot \c obj. The value must be a function, funcdef, class, or namespace.

	<b>The string returned from this points into Croc's memory. Do not modify this string, and do not store the pointer
	unless you know it won't be collected!</b> */
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
			return 0; // dummy
		}
	}

	/** Like \ref croc_getNameOf, but returns the length of the string in bytes through the \c len parameter.

	<b>The string returned from this points into Croc's memory. Do not modify this string, and do not store the pointer
	unless you know it won't be collected!</b> */
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
			name = nullptr; // dummy
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

		int hasHFieldImpl(Thread* t, word_t slot, String* name)
		{
			auto v = *getValue(t, slot);

			switch(v.type)
			{
				case CrocType_Class:     return v.mClass->getHiddenField(name) != nullptr;
				case CrocType_Instance:  return v.mInstance->getHiddenField(name) != nullptr;
				default: API_PARAM_TYPE_ERROR(slot, "object", "class|instance");
				return 0; // dummy
			}
		}
	}

	/** \returns nonzero if the object in slot \c obj has a field named \c fieldName. Does not take \c opField
	metamethods into account. */
	int croc_hasField(CrocThread* t_, word_t obj, const char* fieldName)
	{
		auto t = Thread::from(t_);
		auto v = *getValue(t, obj);
		auto name = String::create(t->vm, atoda(fieldName));
		return hasFieldImpl(v, name);
	}

	/** \returns nonzero if the object in slot \c obj has a field named the string in slot \c name. Does not take \c
	opField metamethods into account. */
	int croc_hasFieldStk(CrocThread* t_, word_t obj, word_t name)
	{
		auto t = Thread::from(t_);
		auto v = *getValue(t, obj);
		API_CHECK_PARAM(nameStr, name, String, "field name");
		return hasFieldImpl(v, nameStr);
	}

	/** \returns nonzero if the object in slot \c obj can have the method named \c methodName called on it. Does not
	take \c opMethod metamethods into account. */
	int croc_hasMethod(CrocThread* t_, word_t obj, const char* methodName)
	{
		auto t = Thread::from(t_);
		auto name = String::create(t->vm, atoda(methodName));
		return lookupMethod(t, *getValue(t, obj), name).type != CrocType_Null;
	}

	/** \returns nonzero if the object in slot \c obj can have the method named the string in slot \c name called on it.
	Does not take \c opMethod metamethods into account. */
	int croc_hasMethodStk(CrocThread* t_, word_t obj, word_t name)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(nameStr, name, String, "method name");
		return lookupMethod(t, *getValue(t, obj), nameStr).type != CrocType_Null;
	}

	/** \returns nonzero if the class or instance in slot \c obj has a hidden field named \c fieldName. */
	int croc_hasHField(CrocThread* t_, word_t obj, const char* fieldName)
	{
		auto t = Thread::from(t_);
		auto name = String::create(t->vm, atoda(fieldName));
		return hasHFieldImpl(t, obj, name);
	}

	/** \returns nonzero if the class or instance in slot \c obj has a hidden field named the string in slot \c name. */
	int croc_hasHFieldStk(CrocThread* t_, word_t obj, word_t name)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(nameStr, name, String, "hidden field name");
		return hasHFieldImpl(t, obj, nameStr);
	}

	/** \returns nonzero if the value in slot \c obj is an instance, and the class it was instantiated from is the class
	in slot \c base. Note that this returns false if \c obj is not an instance, instead of throwing an error. */
	int croc_isInstanceOf(CrocThread* t_, word_t obj, word_t base)
	{
		auto t = Thread::from(t_);
		auto inst = *getValue(t, obj);
		API_CHECK_PARAM(cls, base, Class, "base");
		return inst.type == CrocType_Instance && inst.mInstance->parent == cls;
	}

	/** Works just like the <tt>a.super</tt> expression in Croc. Gets the super of the object in \c slot and pushes it.

	\returns the stack index of the pushed value. */
	word_t croc_superOf(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		return push(t, superOfImpl(t, *getValue(t, slot)));
	}
}