
#include "croc/api.h"
#include "croc/internal/apichecks.hpp"
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

	// word_t croc_pushToString(CrocThread* t_, word_t slot)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// word_t croc_pushToStringRaw(CrocThread* t_, word_t slot)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// int croc_in(CrocThread* t_, word_t item, word_t container)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// crocint_t croc_cmp(CrocThread* t_, word_t a, word_t b)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// int croc_equals(CrocThread* t_, word_t a, word_t b)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// int croc_is(CrocThread* t_, word_t a, word_t b)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// word_t croc_idx(CrocThread* t_, word_t container)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// void croc_idxa(CrocThread* t_, word_t container)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// word_t croc_idxi(CrocThread* t_, word_t container, crocint_t idx)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// void croc_idxai(CrocThread* t_, word_t container, crocint_t idx)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// word_t croc_slice(CrocThread* t_, word_t container)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// void croc_slicea(CrocThread* t_, word_t container)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// word_t croc_field(CrocThread* t_, word_t container, const char* name)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// word_t croc_fieldStk(CrocThread* t_, word_t container)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// void croc_fielda(CrocThread* t_, word_t container, const char* name)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// void croc_fieldaStk(CrocThread* t_, word_t container)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// word_t croc_rawField(CrocThread* t_, word_t container, const char* name)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// word_t croc_rawFieldStk(CrocThread* t_, word_t container)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// void croc_rawFielda(CrocThread* t_, word_t container, const char* name)
	// {
	// 	auto t = Thread::from(t_);
	// }

	// void croc_rawFieldaStk(CrocThread* t_, word_t container)
	// {
	// 	auto t = Thread::from(t_);
	// }

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