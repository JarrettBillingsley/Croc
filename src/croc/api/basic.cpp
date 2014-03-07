
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/basic.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
extern "C"
{
	void croc_foreachBegin(CrocThread* t_, word_t* state, uword_t numContainerVals)
	{
		auto t = Thread::from(t_);

		if(numContainerVals < 1 || numContainerVals > 3)
			croc_eh_throwStd(t_, "RangeError", "%s - numSlots may only be 1, 2, or 3, not %u",
				__FUNCTION__, numContainerVals);

		API_CHECK_NUM_PARAMS(numContainerVals);

		// Make sure we have 3 stack slots for our temp data area
		if(numContainerVals < 3)
			croc_setStackSize(t_, croc_getStackSize(t_) + (3 - numContainerVals));

		// Call opApply if needed
		auto src = getValue(t, -3);

		if(src->type != CrocType_Function && src->type != CrocType_Thread)
		{
			auto method = getMM(t, *src, MM_Apply);

			if(method == nullptr)
			{
				pushTypeStringImpl(t, *src);
				croc_eh_throwStd(t_, "TypeError", "No implementation of %s for type '%s'",
					MetaNames[MM_Apply], croc_getString(t_, -1));
			}

			push(t, Value::from(method));
			croc_insert(t_, -4);
			croc_popTop(t_);
			auto reg = t->stackIndex - 3;
			commonCall(t, reg, 3, callPrologue(t, reg, 3, 2));
			src = getValue(t, -3);

			if(src->type != CrocType_Function && src->type != CrocType_Thread)
			{
				pushTypeStringImpl(t, *src);
				croc_eh_throwStd(t_, "TypeError", "Invalid iterable type '%s' returned from opApply",
					croc_getString(t_, -1));
			}
		}

		if(src->type == CrocType_Thread && src->mThread->state != CrocThreadState_Initial)
			croc_eh_throwStd(t_, "StateError",
				"Attempting to iterate over a thread that is not in the 'initial' state");

		*state = croc_getStackSize(t_);
	}

	int croc_foreachNext(CrocThread* t_, word_t* state, uword_t numIndices)
	{
		auto t = Thread::from(t_);

		if(numIndices == 0)
			croc_eh_throwStd(t_, "ApiError", "%s - Cannot have 0 indices", __FUNCTION__);

		// Get rid of any gunk left on the stack after previous loop
		auto size = croc_getStackSize(t_);

		if(cast(word_t)size > *state)
			croc_pop(t_, size - *state);

		// Neeeext
		auto src = *state - 3;
		auto funcReg = croc_dup(t_, src);
		croc_dup(t_, src + 1);
		croc_dup(t_, src + 2);
		croc_call(t_, funcReg, numIndices == 1 ? 2 : numIndices);

		if(croc_isFunction(t_, src))
		{
			if(croc_isNull(t_, funcReg))
			{
				croc_pop(t_, numIndices);
				return false;
			}
		}
		else
		{
			if(getThread(t, src)->state == CrocThreadState_Dead)
			{
				croc_pop(t_, numIndices);
				return false;
			}
		}

		croc_dup(t_, funcReg);
		croc_swapTopWith(t_, src + 2);
		croc_popTop(t_);

		if(numIndices == 1)
			croc_insertAndPop(t_, -2);

		return true;
	}

	void croc_foreachEnd(CrocThread* t_, word_t* state)
	{
		// auto t = Thread::from(t_);
		auto diff = cast(word_t)croc_getStackSize(t_) - *state;

		if(diff != 0)
			croc_eh_throwStd(t_, "ApiError", "%s - stack size changed by %d slots between begin and end of foreach",
				__FUNCTION__, diff);

		croc_pop(t_, 3);
	}

	void croc_removeKey(CrocThread* t_, word_t obj)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);

		if(auto tab = getTable(t, obj))
		{
			tab->idxa(t->vm->mem, *getValue(t, -1), Value::nullValue);
			croc_popTop(t_);
		}
		else if(auto ns = getNamespace(t, obj))
		{
			API_CHECK_PARAM(key, -1, String, "key");

			if(!ns->contains(key))
			{
				croc_pushToString(t_, obj);
				croc_eh_throwStd(t_, "FieldError",
					"%s - key '%s' does not exist in namespace '%s'",
					__FUNCTION__, croc_getString(t_, -2), croc_getString(t_, -1));
			}

			ns->remove(t->vm->mem, key);
			croc_popTop(t_);
		}
		else
			API_PARAM_TYPE_ERROR(obj, "obj", "table|namespace");
	}

	word_t croc_pushToString(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		return toStringImpl(t, *getValue(t, slot), false);
	}

	word_t croc_pushToStringRaw(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		return toStringImpl(t, *getValue(t, slot), true);
	}

	int croc_in(CrocThread* t_, word_t item, word_t container)
	{
		auto t = Thread::from(t_);
		return inImpl(t, *getValue(t, item), *getValue(t, container));
	}

	crocint_t croc_cmp(CrocThread* t_, word_t a, word_t b)
	{
		auto t = Thread::from(t_);
		return cmpImpl(t, *getValue(t, a), *getValue(t, b));
	}

	int croc_equals(CrocThread* t_, word_t a, word_t b)
	{
		auto t = Thread::from(t_);
		return equalsImpl(t, *getValue(t, a), *getValue(t, b));
	}

	int croc_is(CrocThread* t_, word_t a, word_t b)
	{
		auto t = Thread::from(t_);
		return *getValue(t, a) == *getValue(t, b);
	}

	word_t croc_idx(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		auto slot = t->stackIndex - 1;
		idxImpl(t, slot, *getValue(t, container), t->stack[slot]);
		return croc_getStackSize(t_) - 1;
	}

	void croc_idxa(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		auto slot = t->stackIndex - 2;
		idxaImpl(t, fakeToAbs(t, container), t->stack[slot], t->stack[slot + 1]);
		croc_pop(t_, 2);
	}

	word_t croc_idxi(CrocThread* t, word_t container, crocint_t idx)
	{
		container = croc_absIndex(t, container);
		croc_pushInt(t, idx);
		return croc_idx(t, container);
	}

	void croc_idxai(CrocThread* t_, word_t container, crocint_t idx)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		container = croc_absIndex(t_, container);
		croc_pushInt(t_, idx);
		croc_swapTop(t_);
		croc_idxa(t_, container);
	}

	word_t croc_slice(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		auto slot = t->stackIndex - 2;
		sliceImpl(t, slot, *getValue(t, container), t->stack[slot], t->stack[slot + 1]);
		croc_pop(t_, 2);
		return croc_getStackSize(t_) - 1;
	}

	void croc_slicea(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(3);
		auto slot = t->stackIndex - 3;
		sliceaImpl(t, *getValue(t, container), t->stack[slot], t->stack[slot + 1], t->stack[slot + 2]);
		croc_pop(t_, 3);
	}

	word_t croc_field(CrocThread* t_, word_t container, const char* name)
	{
		auto t = Thread::from(t_);
		container = fakeToAbs(t, container);
		croc_pushString(t_, name);
		auto slot = t->stackIndex - 1;
		fieldImpl(t, slot, t->stack[container], t->stack[slot].mString, false);
		return croc_getStackSize(t_) - 1;
	}

	word_t croc_fieldStk(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(name, -1, String, "field name");
		auto slot = t->stackIndex - 1;
		fieldImpl(t, slot, t->stack[fakeToAbs(t, container)], name, false);
		return croc_getStackSize(t_) - 1;
	}

	void croc_fielda(CrocThread* t_, word_t container, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		container = fakeToAbs(t, container);
		croc_pushString(t_, name);
		auto slot = t->stackIndex - 2;
		fieldaImpl(t, container, t->stack[slot + 1].mString, t->stack[slot], false);
		croc_pop(t_, 2);
	}

	void croc_fieldaStk(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(name, -2, String, "field name");
		fieldaImpl(t, fakeToAbs(t, container), name, t->stack[t->stackIndex - 1], false);
		croc_pop(t_, 2);
	}

	word_t croc_rawField(CrocThread* t_, word_t container, const char* name)
	{
		auto t = Thread::from(t_);
		container = fakeToAbs(t, container);
		croc_pushString(t_, name);
		auto slot = t->stackIndex - 1;
		fieldImpl(t, slot, t->stack[container], t->stack[slot].mString, true);
		return croc_getStackSize(t_) - 1;
	}

	word_t croc_rawFieldStk(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(name, -1, String, "field name");
		auto slot = t->stackIndex - 1;
		fieldImpl(t, slot, t->stack[container], name, true);
		return croc_getStackSize(t_) - 1;
	}

	void croc_rawFielda(CrocThread* t_, word_t container, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		container = fakeToAbs(t, container);
		croc_pushString(t_, name);
		auto slot = t->stackIndex - 2;
		fieldaImpl(t, container, t->stack[slot + 1].mString, t->stack[slot], true);
		croc_pop(t_, 2);
	}

	void croc_rawFieldaStk(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(name, -2, String, "field name");
		fieldaImpl(t, fakeToAbs(t, container), name, t->stack[t->stackIndex - 1], true);
		croc_pop(t_, 2);
	}

	word_t croc_hfield(CrocThread* t, word_t container, const char* name)
	{
		container = croc_absIndex(t, container);
		croc_pushString(t, name);
		return croc_hfieldStk(t, container);
	}

	word_t croc_hfieldStk(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(name, -1, String, "hidden field name");

		auto obj = t->stack[fakeToAbs(t, container)];

		switch(obj.type)
		{
			case CrocType_Class: {
				auto c = obj.mClass;
				auto v = c->getHiddenField(name);

				if(v == nullptr)
					croc_eh_throwStd(t_, "FieldError",
						"%s - Attempting to access nonexistent hidden field '%s' from class '%s'",
						__FUNCTION__, name->toCString(), c->name->toCString());

				t->stack[t->stackIndex - 1] = *v;
				break;
			}
			case CrocType_Instance: {
				auto i = obj.mInstance;
				auto v = i->getHiddenField(name);

				if(v == nullptr)
					croc_eh_throwStd(t_, "FieldError",
						"%s - Attempting to access nonexistent hidden field '%s' from instance of class '%s'",
						__FUNCTION__, name->toCString(), i->parent->name->toCString());

				t->stack[t->stackIndex - 1] = *v;
				break;
			}
			default:
				API_PARAM_TYPE_ERROR(container, "container", "class|instance");
		}

		return croc_getStackSize(t_) - 1;
	}

	void croc_hfielda(CrocThread* t_, word_t container, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		container = croc_absIndex(t_, container);
		croc_pushString(t_, name);
		croc_swapTop(t_);
		croc_hfieldaStk(t_, container);
	}

	void croc_hfieldaStk(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(name, -2, String, "hidden field name");

		auto obj = t->stack[fakeToAbs(t, container)];
		auto value = t->stack[t->stackIndex - 1];

		switch(obj.type)
		{
			case CrocType_Class: {
				auto c = obj.mClass;

				if(!c->setHiddenField(t->vm->mem, name, value))
					croc_eh_throwStd(t_, "FieldError",
						"%s - Attempting to assign to nonexistent hidden field '%s' in class '%s'",
						__FUNCTION__, name->toCString(), c->name->toCString());
				break;
			}
			case CrocType_Instance: {
				auto i = obj.mInstance;

				if(!i->setHiddenField(t->vm->mem, name, value))
					croc_eh_throwStd(t_, "FieldError",
						"%s - Attempting to assign to nonexistent hidden field '%s' in instance of class '%s'",
						__FUNCTION__, name->toCString(), i->parent->name->toCString());
				break;
			}
			default:
				API_PARAM_TYPE_ERROR(container, "container", "class|instance");
		}

		croc_pop(t_, 2);
	}

	word_t croc_pushLen(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		auto o = *getValue(t, slot);
		croc_pushNull(t_);
		lenImpl(t, t->stackIndex - 1, o);
		return croc_getStackSize(t_) - 1;
	}

	crocint_t croc_len(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);

		croc_pushLen(t_, slot);
		auto len = t->stack[t->stackIndex - 1];

		if(len.type != CrocType_Int)
		{
			croc_pushTypeString(t_, -1);
			croc_eh_throwStd(t_, "TypeError", "%s - Expected length to be an int, but got '%s' instead",
				__FUNCTION__, croc_getString(t_, -1));
		}

		auto ret = len.mInt;
		croc_popTop(t_);
		return ret;
	}

	void croc_lena(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		lenaImpl(t, *getValue(t, slot), t->stack[t->stackIndex - 1]);
		croc_popTop(t_);
	}

	void croc_lenai(CrocThread* t, word_t slot, crocint_t length)
	{
		slot = croc_absIndex(t, slot);
		croc_pushInt(t, length);
		croc_lena(t, slot);
	}

	word_t croc_cat(CrocThread* t_, uword_t num)
	{
		auto t = Thread::from(t_);

		if(num == 0)
			croc_eh_throwStd(t_, "ApiError", "%s - Cannot concatenate 0 things", __FUNCTION__);

		API_CHECK_NUM_PARAMS(num);

		auto slot = t->stackIndex - num;

		if(num > 1)
		{
			catImpl(t, slot, slot, num);
			croc_pop(t_, num - 1);
		}

		return slot - t->stackBase;
	}

	void croc_cateq(CrocThread* t_, word_t dest, uword_t num)
	{
		auto t = Thread::from(t_);

		if(num == 0)
			croc_eh_throwStd(t_, "ApiError", "%s - Cannot append 0 things", __FUNCTION__);

		API_CHECK_NUM_PARAMS(num);
		catEqImpl(t, fakeToAbs(t, dest), t->stackIndex - num, num);
		croc_pop(t_, num);
	}
}
}