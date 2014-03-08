
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
	word_t _newClass(CrocThread* t)
	{
		auto name = croc_ex_checkStringParam(t, 1);
		auto size = croc_getStackSize(t);

		for(word slot = 2; slot < cast(word)size; slot++)
			croc_ex_checkParam(t, slot, CrocType_Class);

		croc_class_new(t, name, size - 2);
		return 1;
	}

	word_t _classFieldsOfIter(CrocThread* t)
	{
		croc_pushUpval(t, 0);
		auto c = getClass(Thread::from(t), -1);
		croc_pushUpval(t, 1);
		auto index = cast(uword)croc_getInt(t, -1);
		croc_pop(t, 2);

		String** key;
		Value* value;

		if(c->nextField(index, key, value))
		{
			croc_pushInt(t, index);
			croc_setUpval(t, 1);

			push(Thread::from(t), Value::from(*key));
			push(Thread::from(t), *value);
			return 2;
		}

		return 0;
	}

	word_t _instanceFieldsOfIter(CrocThread* t)
	{
		croc_pushUpval(t, 0);
		auto c = getInstance(Thread::from(t), -1);
		croc_pushUpval(t, 1);
		auto index = cast(uword)croc_getInt(t, -1);
		croc_pop(t, 2);

		String** key;
		Value* value;

		if(c->nextField(index, key, value))
		{
			croc_pushInt(t, index);
			croc_setUpval(t, 1);

			push(Thread::from(t), Value::from(*key));
			push(Thread::from(t), *value);
			return 2;
		}

		return 0;
	}

	word_t _fieldsOf(CrocThread* t)
	{
		croc_ex_checkAnyParam(t, 1);
		croc_dup(t, 1);
		croc_pushInt(t, 0);

		if(croc_isClass(t, 1))
			croc_function_new(t, "fieldsOfClassIter", 1, &_classFieldsOfIter, 2);
		else if(croc_isInstance(t, 1))
			croc_function_new(t, "fieldsOfInstanceIter", 1, &_instanceFieldsOfIter, 2);
		else
			croc_ex_paramTypeError(t, 1, "class|instance");

		return 1;
	}

	word_t _methodsOfIter(CrocThread* t)
	{
		croc_pushUpval(t, 0);
		auto c = getClass(Thread::from(t), -1);
		croc_pushUpval(t, 1);
		auto index = cast(uword)croc_getInt(t, -1);
		croc_pop(t, 2);

		String** key;
		Value* value;

		while(c->nextMethod(index, key, value))
		{
			croc_pushInt(t, index);
			croc_setUpval(t, 1);

			push(Thread::from(t), Value::from(*key));
			push(Thread::from(t), *value);
			return 2;
		}

		return 0;
	}

	word_t _methodsOf(CrocThread* t)
	{
		croc_ex_checkAnyParam(t, 1);

		if(croc_isClass(t, 1))
			croc_dup(t, 1);
		else if(croc_isInstance(t, 1))
			croc_superOf(t, 1);
		else
			croc_ex_paramTypeError(t, 1, "class|instance");

		croc_pushInt(t, 0);
		croc_function_new(t, "methodsOfIter", 1, &_methodsOfIter, 2);
		return 1;
	}

	word_t _rawSetField(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Instance);
		croc_ex_checkStringParam(t, 2);
		croc_ex_checkAnyParam(t, 3);
		croc_dup(t, 2);
		croc_dup(t, 3);
		croc_rawFieldaStk(t, 1);
		return 0;
	}

	word_t _rawGetField(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Instance);
		croc_ex_checkStringParam(t, 2);
		croc_dup(t, 2);
		croc_rawFieldStk(t, 1);
		return 1;
	}

	word_t _addMethod(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Class);
		croc_ex_checkStringParam(t, 2);
		croc_ex_checkAnyParam(t, 3);
		croc_dup(t, 2);
		croc_dup(t, 3);
		croc_class_addMethodStk(t, 1);
		return 0;
	}

	word_t _addField(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Class);
		croc_ex_checkStringParam(t, 2);

		if(!croc_isValidIndex(t, 3))
			croc_pushNull(t);

		croc_dup(t, 2);
		croc_dup(t, 3);
		croc_class_addFieldStk(t, 1);
		return 0;
	}

	word_t _addMethodOverride(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Class);
		croc_ex_checkStringParam(t, 2);
		croc_ex_checkAnyParam(t, 3);
		croc_dup(t, 2);
		croc_dup(t, 3);
		croc_class_addMethodOStk(t, 1);
		return 0;
	}

	word_t _addFieldOverride(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Class);
		croc_ex_checkStringParam(t, 2);

		if(!croc_isValidIndex(t, 3))
			croc_pushNull(t);

		croc_dup(t, 2);
		croc_dup(t, 3);
		croc_class_addFieldOStk(t, 1);
		return 0;
	}

	word_t _removeMember(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Class);
		croc_ex_checkStringParam(t, 2);
		croc_dup(t, 2);
		croc_class_removeMemberStk(t, 1);
		return 0;
	}

	word_t _freeze(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Class);
		croc_class_freeze(t, 1);
		croc_dup(t, 1);
		return 1;
	}

	word_t _isFrozen(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Class);
		croc_pushBool(t, croc_class_isFrozen(t, 1));
		return 1;
	}

	word_t _isFinalizable(CrocThread* t)
	{
		croc_ex_checkAnyParam(t, 1);

		if(croc_isClass(t, 1))
		{
			croc_class_freeze(t, 1);
			croc_pushBool(t, getClass(Thread::from(t), 1)->finalizer != nullptr);
		}
		else if(croc_isInstance(t, 1))
			croc_pushBool(t, getInstance(Thread::from(t), 1)->parent->finalizer != nullptr);
		else
			croc_ex_paramTypeError(t, 1, "class|instance");

		return 1;
	}

	word_t _instanceOf(CrocThread* t)
	{
		croc_ex_checkParam(t, 2, CrocType_Class);

		if(croc_isInstance(t, 1))
		{
			croc_superOf(t, 1);
			croc_pushBool(t, croc_is(t, -1, 2));
		}
		else
			croc_pushBool(t, false);

		return 1;
	}

	const CrocRegisterFunc _globalFuncs[] =
	{
		{"newClass",          -1, &_newClass         },
		{"fieldsOf",           1, &_fieldsOf         },
		{"methodsOf",          1, &_methodsOf        },
		{"rawSetField",        3, &_rawSetField      },
		{"rawGetField",        2, &_rawGetField      },
		{"addMethod",          3, &_addMethod        },
		{"addField",           3, &_addField         },
		{"addMethodOverride",  3, &_addMethodOverride},
		{"addFieldOverride",   3, &_addFieldOverride },
		{"removeMember",       2, &_removeMember     },
		{"freeze",             1, &_freeze           },
		{"isFrozen",           1, &_isFrozen         },
		{"isFinalizable",      1, &_isFinalizable    },
		{"instanceOf",         2, &_instanceOf       },
		{nullptr, 0, nullptr}
	};

	word loader(CrocThread* t)
	{
		croc_ex_registerGlobals(t, _globalFuncs);
		return 0;
	}
	}

	void initObjectLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "object", &loader);
		croc_ex_importNoNS(t, "object");
	}
}