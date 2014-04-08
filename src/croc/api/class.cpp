
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/class.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

namespace
{
	void addFieldOrMethod(Thread* t, word cls, bool isMethod, bool isOverride)
	{
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(c, cls, Class, "cls");
		API_CHECK_PARAM(name, -2, String, isMethod ? "method name" : "field name");

		if(c->isFrozen)
		{
			if(isMethod)
				croc_eh_throwStd(*t, "StateError", "%s - Attempting to add a method to class '%s' which is frozen",
					__FUNCTION__, c->name->toCString());
			else
				croc_eh_throwStd(*t, "StateError", "%s - Attempting to add a field to class '%s' which is frozen",
					__FUNCTION__, c->name->toCString());
		}

		auto okay = isMethod ?
			c->addMethod(t->vm->mem, name, *getValue(t, -1), isOverride) :
			c->addField (t->vm->mem, name, *getValue(t, -1), isOverride);

		if(!okay)
		{
			if(isOverride)
			{
				croc_eh_throwStd(*t, "FieldError",
					"%s - Attempting to override %s '%s' in class '%s', but no such member already exists",
					__FUNCTION__, isMethod ? "method" : "field", name->toCString(), c->name->toCString());
			}
			else
			{
				croc_eh_throwStd(*t, "FieldError",
					"%s - Attempting to add a %s '%s' which already exists to class '%s'",
					__FUNCTION__, isMethod ? "method" : "field", name->toCString(), c->name->toCString());
			}
		}

		croc_pop(*t, 2);
	}
}

extern "C"
{
	/** Creates and pushes a new class named \c name, using the top \c numBases classes as its bases. The bases (if any)
	are popped before the new class is pushed.

	\returns the stack index of the pushed value. */
	word_t croc_class_new(CrocThread* t_, const char* name, uword_t numBases)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(numBases);
		auto cls = Class::create(t->vm->mem, String::create(t->vm, atoda(name)));
		push(t, Value::from(cls));

		if(numBases > 0)
		{
			croc_insert(t_, -numBases - 1);
			auto stackSize = croc_getStackSize(t_);

			for(word slot = stackSize - numBases; slot < cast(word)stackSize; slot++)
			{
				API_CHECK_PARAM(base, slot, Class, "base");
				classDeriveImpl(t, cls, base);
			}

			croc_pop(t_, numBases);
		}

		croc_gc_maybeCollect(t_);
		return croc_getStackSize(t_) - 1;
	}

	/** Adds a field named \c name to the unfrozen class at \c cls, assigning it the value on top of the stack and
	popping that value. */
	void croc_class_addField(CrocThread* t_, word_t cls, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		cls = croc_absIndex(t_, cls);
		croc_pushString(t_, name);
		croc_swapTop(t_);
		addFieldOrMethod(t, cls, false, false);
	}

	/** Same as \ref croc_class_addField, but expects the name as a string on the stack below the value (like how
	\ref croc_fielda works). Pops both. */
	void croc_class_addFieldStk(CrocThread* t_, word_t cls)
	{
		addFieldOrMethod(Thread::from(t_), cls, false, false);
	}

	/** Adds a method named \c name to the unfrozen class at \c cls, assigning it the value on top of the stack and
	popping that value. The value can be any type, not just functions. */
	void croc_class_addMethod(CrocThread* t_, word_t cls, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		cls = croc_absIndex(t_, cls);
		croc_pushString(t_, name);
		croc_swapTop(t_);
		addFieldOrMethod(t, cls, true, false);
	}

	/** Same as \ref croc_class_addMethod, but expects the name as a string on the stack below the value (like how
	\ref croc_fielda works). Pops both. */
	void croc_class_addMethodStk(CrocThread* t_, word_t cls)
	{
		addFieldOrMethod(Thread::from(t_), cls, true, false);
	}

	/** Same as \ref croc_class_addField, but overrides any existing field (like the 'override' keyword in Croc). */
	void croc_class_addFieldO(CrocThread* t_, word_t cls, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		cls = croc_absIndex(t_, cls);
		croc_pushString(t_, name);
		croc_swapTop(t_);
		addFieldOrMethod(t, cls, false, true);
	}

	/** Same as \ref croc_class_addFieldStk, but overrides any existing field (like the 'override' keyword in Croc). */
	void croc_class_addFieldOStk(CrocThread* t_, word_t cls)
	{
		addFieldOrMethod(Thread::from(t_), cls, false, true);
	}

	/** Same as \ref croc_class_addMethod, but overrides any existing field (like the 'override' keyword in Croc). */
	void croc_class_addMethodO(CrocThread* t_, word_t cls, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		cls = croc_absIndex(t_, cls);
		croc_pushString(t_, name);
		croc_swapTop(t_);
		addFieldOrMethod(t, cls, true, true);
	}

	/** Same as \ref croc_class_addMethodStk, but overrides any existing field (like the 'override' keyword in Croc). */
	void croc_class_addMethodOStk(CrocThread* t_, word_t cls)
	{
		addFieldOrMethod(Thread::from(t_), cls, true, true);
	}

	/** Removes the member (field or method) named \c name from the unfrozen class at \c cls. */
	void croc_class_removeMember(CrocThread* t, word_t cls, const char* name)
	{
		cls = croc_absIndex(t, cls);
		croc_pushString(t, name);
		croc_class_removeMemberStk(t, cls);
	}

	/** Same as \ref croc_class_removeMember, but expects the member name as a string on top of the stack, and pops the
	name. */
	void croc_class_removeMemberStk(CrocThread* t_, word_t cls)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(c, cls, Class, "cls");
		API_CHECK_PARAM(name, -1, String, "member name");

		if(c->isFrozen)
			croc_eh_throwStd(t_, "StateError", "%s - Attempting to remove a member from class '%s' which is frozen",
				__FUNCTION__, c->name->toCString());

		if(!c->removeMember(t->vm->mem, name))
			croc_eh_throwStd(t_, "FieldError", "%s - No member named '%s' exists in class '%s'",
				__FUNCTION__, name->toCString(), c->name->toCString());

		croc_popTop(t_);
	}

	/** Same as \ref croc_class_addField, but adds a hidden field instead. */
	void croc_class_addHField(CrocThread* t_, word_t cls, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		cls = croc_absIndex(t_, cls);
		croc_pushString(t_, name);
		croc_swapTop(t_);
		croc_class_addHFieldStk(t_, cls);
	}

	/** Same as \ref croc_class_addFieldStk, but adds a hidden field instead. */
	void croc_class_addHFieldStk(CrocThread* t_, word_t cls)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(c, cls, Class, "cls");
		API_CHECK_PARAM(name, -2, String, "hidden field name");

		if(c->isFrozen)
			croc_eh_throwStd(t_, "StateError", "%s - Attempting to add a hidden field to class '%s' which is frozen",
				__FUNCTION__, c->name->toCString());

		if(!c->addHiddenField(t->vm->mem, name, *getValue(t, -1)))
			croc_eh_throwStd(t_, "FieldError",
				"%s - Attempting to add a hidden field '%s' which already exists to class '%s'",
				__FUNCTION__, name->toCString(), c->name->toCString());

		croc_pop(t_, 2);
	}

	/** Same as \ref croc_class_removeMember, but removes a hidden field instead. */
	void croc_class_removeHField(CrocThread* t, word_t cls, const char* name)
	{
		cls = croc_absIndex(t, cls);
		croc_pushString(t, name);
		croc_class_removeHFieldStk(t, cls);
	}

	/** Same as \ref croc_class_removeMemberStk, but removes a hidden field instead. */
	void croc_class_removeHFieldStk(CrocThread* t_, word_t cls)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(c, cls, Class, "cls");
		API_CHECK_PARAM(name, -1, String, "member name");

		if(c->isFrozen)
			croc_eh_throwStd(t_, "StateError",
				"%s - Attempting to remove a hidden field from class '%s' which is frozen",
				__FUNCTION__, c->name->toCString());

		if(!c->removeHiddenField(t->vm->mem, name))
			croc_eh_throwStd(t_, "FieldError", "%s - No hidden field named '%s' exists in class '%s'",
				__FUNCTION__, name->toCString(), c->name->toCString());

		croc_popTop(t_);
	}

	/** Forcefully freezes the class at \c cls, or does nothing if it's already frozen. */
	void croc_class_freeze(CrocThread* t_, word_t cls)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(c, cls, Class, "cls");
		freezeImpl(t, c);
	}

	/** \returns nonzero if the class at \c cls is frozen. */
	int croc_class_isFrozen(CrocThread* t_, word_t cls)
	{
		auto t = Thread::from(t_);
		API_CHECK_PARAM(c, cls, Class, "cls");
		return c->isFrozen;
	}
}