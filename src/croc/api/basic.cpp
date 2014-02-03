
#include "croc/api.h"
#include "croc/internal/apichecks.hpp"
#include "croc/internal/basic.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

namespace croc
{
extern "C"
{
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
				assert(false); // TODO:ex
				// pushToString(t, obj);
				// throwStdException(t, "FieldError", __FUNCTION__ ~ " - key '{}' does not exist in namespace '{}'", getString(t, -2), getString(t, -1));
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

	// word_t croc_hfield(CrocThread* t_, word_t container, const char* name)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// word_t croc_hfieldStk(CrocThread* t_, word_t container)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// void croc_hfielda(CrocThread* t_, word_t container, const char* name)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// void croc_hfieldaStk(CrocThread* t_, word_t container)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// word_t croc_pushLen(CrocThread* t_, word_t slot)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// crocint_t croc_len(CrocThread* t_, word_t slot)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// void croc_lena(CrocThread* t_, word_t slot)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// void croc_lenai(CrocThread* t_, word_t slot, crocint_t length)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// word_t croc_cat(CrocThread* t_, uword_t num)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// void croc_cateq(CrocThread* t_, word_t dest, uword_t num)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// int croc_instanceOf(CrocThread* t_, word_t obj, word_t base)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// word_t croc_superOf(CrocThread* t_, word_t slot)
	// {
	// 	auto t = Thread::from(t_);
	// }
}
}