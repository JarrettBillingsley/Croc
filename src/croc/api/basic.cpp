
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/basic.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** This, \ref croc_foreachNext, and \ref croc_foreachEnd are used together to perform the equivalent of the Croc
	\c 'foreach; loop.

	Here's how you use them:

	1. Push the container value(es) that you want to iterate over (the equivalent of the stuff after the semicolon in
		the Croc \c 'foreach' loop.
	2. Call \c croc_foreachBegin, telling it how many values you pushed, and store the value it returns.
	3. In a loop, call \ref croc_foreachNext with the value that \c croc_foreachBegin returned and the number of indices
		you want. Use the return value from \c croc_foreachNext to determine if the loop should continue.
	4. Inside the loop, access the indices as normal stack slots.
	5. When you leave the loop (either by exiting normally or by breaking), call \ref croc_foreachEnd to clean up.

	It sounds complex, but it's easier in an example. Let's translate the following loop into API calls.

	\code{.croc}
	// Assume a is a global that holds [1, 2, 3]
	foreach(i, val; a)
		writeln(i, ": ", val)
	\endcode

	In the native API:

	\code{.c}
	word_t state;

	...

	croc_pushGlobal(t, "a"); // push the container
	for(state = croc_foreachBegin(t, 1); // 1 since we pushed 1 value; save the state!
		croc_foreachNext(t, state, 2); ) // pass the state, and 2 to mean 2 indices
	{
		// In here, the top two stack slots contain the two indices we asked for (the index and value).
		croc_pushGlobal(t, "writeln");
		croc_pushNull(t);
		croc_dup(t, -4); // key
		croc_pushString(t, ": ");
		croc_dup(t, -5); // value
		croc_call(t, -5, 0);

		// Don't have to clean up the stack here, croc_foreachNext will do it for us
	}
	// clean up!
	croc_foreachEnd(t, state);

	// Now the stack is the same as it was before the initial croc_pushGlobal
	\endcode

	\param numContainerVals is how many values you pushed for the container. This must be 1, 2, or 3, and there must be
		that many values on top of the stack.
	\returns a value used to keep track of the state of the foreach loop. There will also be some values on the stack
		which you shouldn't mess with. */
	word_t croc_foreachBegin(CrocThread* t_, uword_t numContainerVals)
	{
		auto t = Thread::from(t_);

		if(numContainerVals < 1 || numContainerVals > 3)
			croc_eh_throwStd(t_, "RangeError", "%s - numSlots may only be 1, 2, or 3, not %" CROC_SIZE_T_FORMAT,
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

		return croc_getStackSize(t_);
	}

	/** Gets the next values in a foreach loop, as demonstrated in \ref croc_foreachBegin.

	\param state is the value that was returned from \ref croc_foreachBegin.
	\param numIndices is how many indices you want. In Croc, this would be the number of variables to the left of the
		semicolon in the \c 'foreach'. You can indeed pass 1 for this parameter, and it will work the same way as in
		Croc; the first index returned from the iterator function will be ignored, and only the second index will be on
		top of the stack.
	\returns nonzero if the loop should continue. */
	int croc_foreachNext(CrocThread* t_, word_t state, uword_t numIndices)
	{
		auto t = Thread::from(t_);

		if(numIndices == 0)
			croc_eh_throwStd(t_, "ApiError", "%s - Cannot have 0 indices", __FUNCTION__);

		// Get rid of any gunk left on the stack after previous loop
		croc_setStackSize(t_, state);
		// auto size = croc_getStackSize(t_);

		// if(cast(word_t)size > state)
		// 	croc_pop(t_, size - state);

		// Neeeext
		auto src = state - 3;
		auto funcReg = croc_dup(t_, src);
		croc_dup(t_, src + 1);
		croc_dup(t_, src + 2);
		croc_call(t_, funcReg, numIndices == 1 ? 2 : numIndices);

		if(croc_isFunction(t_, src) ? croc_isNull(t_, funcReg) : getThread(t, src)->state == CrocThreadState_Dead)
		{
			croc_pop(t_, numIndices == 1 ? 2 : numIndices);
			return false;
		}

		croc_dup(t_, funcReg);
		croc_swapTopWith(t_, src + 2);
		croc_popTop(t_);

		if(numIndices == 1)
			croc_insertAndPop(t_, -2);

		return true;
	}

	/** Cleans up a foreach loop, as demonstrated in \ref croc_foreachBegin. You should call this no matter how you exit
	the loop (unless you return from a native function inside the loop... then you don't have to). This will check that
	the stack is in the appropriate configuration and will pop the bookkeeping variables that \ref croc_foreachBegin
	pushed.

	\param state is the value that was returned from \ref croc_foreachBegin. */
	void croc_foreachEnd(CrocThread* t_, word_t state)
	{
		auto diff = cast(word_t)croc_getStackSize(t_) - state;

		if(diff < 0)
			croc_eh_throwStd(t_, "ApiError",
				"%s - stack size smaller by %" CROC_SSIZE_T_FORMAT " slots between begin and end of foreach",
				__FUNCTION__, diff);

		// croc_pop(t_, 3);
		croc_setStackSize(t_, state - 3);
	}

	/** Removes the key-value pair from the table or namespace at slot \c obj whose key is the value on top of the
	stack, then pops that value.

	For tables, you can also do this by index-assigning \c null into a key, but for namespaces this is the only way to
	remove a key-value pair. */
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

	/** Pushes a string representation of the value at \c slot by essentially calling the Croc \c toString on it. */
	word_t croc_pushToString(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		return toStringImpl(t, *getValue(t, slot), false);
	}

	/** Pushes a raw string representation of the value at \c slot by essentially calling the Croc \c rawToString on
	it. */
	word_t croc_pushToStringRaw(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		return toStringImpl(t, *getValue(t, slot), true);
	}

	/** The equivalent of Croc's \c 'in' operator. Calls \c opIn metamethods if necessary.

	\returns nonzero if the value at \c item is in the value at \c container. */
	int croc_in(CrocThread* t_, word_t item, word_t container)
	{
		auto t = Thread::from(t_);
		return inImpl(t, *getValue(t, item), *getValue(t, container));
	}

	/** The equivalent of Croc's \c <=> operator. Calls \c opCmp metamethods if necessary.

	\returns a comparison value (negative for less, 0 for equal, positive for greater) of the result of comparing the
		values at \c a and \c b. */
	crocint_t croc_cmp(CrocThread* t_, word_t a, word_t b)
	{
		auto t = Thread::from(t_);
		return cmpImpl(t, *getValue(t, a), *getValue(t, b));
	}

	/** The equivalent of Croc's \c == operator. Calls \c opEquals metamethods if necessary.

	\returns nonzero if the values at \c a and \c b are equal. */
	int croc_equals(CrocThread* t_, word_t a, word_t b)
	{
		auto t = Thread::from(t_);
		return equalsImpl(t, *getValue(t, a), *getValue(t, b));
	}

	/** The equivalent of Croc's \c is operator.

	\returns nonzero if the values at \c a and \c b are identical. */
	int croc_is(CrocThread* t_, word_t a, word_t b)
	{
		auto t = Thread::from(t_);
		return *getValue(t, a) == *getValue(t, b);
	}

	/** The equivalent of Croc's \c a[b] operation. This expects the index to be on top of the stack, and it is replaced
	with the result of the indexing operation. Calls \c opIndex metamethods if necessary.

	\param container is the object to index.
	\returns the stack index of the resulting value. */
	word_t croc_idx(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		auto slot = t->stackIndex - 1;
		idxImpl(t, slot, *getValue(t, container), t->stack[slot]);
		return croc_getStackSize(t_) - 1;
	}

	/* The equivalent of Croc's <tt>a[b] = c</tt> operation. This expects the value to be assigned (\c c) to be on top
	of the stack, and the index (\c b) below it. Calls \c opIndexAssign metamethods if necessary. Pops both the value
	and the index from the top of the stack.

	\param container is the object to index-assign. */
	void croc_idxa(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		auto slot = t->stackIndex - 2;
		idxaImpl(t, fakeToAbs(t, container), t->stack[slot], t->stack[slot + 1]);
		croc_pop(t_, 2);
	}

	/** A convenience function when you want to index a container using an integer index. Pushes the result of indexing
	on top of the stack.

	\param container is the object to index.
	\param idx is the integer index.
	\returns the stack index of the pushed value. */
	word_t croc_idxi(CrocThread* t, word_t container, crocint_t idx)
	{
		container = croc_absIndex(t, container);
		croc_pushInt(t, idx);
		return croc_idx(t, container);
	}

	/** A convenience function when you want to index-assign a container using an integer index. Expects the value to
	be on top of the stack, and pops it.

	\param container is the object to index-assign.
	\param idx is the integer index. */
	void croc_idxai(CrocThread* t_, word_t container, crocint_t idx)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		container = croc_absIndex(t_, container);
		croc_pushInt(t_, idx);
		croc_swapTop(t_);
		croc_idxa(t_, container);
	}

	/** The equivalent of Croc's <tt>a[b .. c]</tt> operation. Expects the slice indices on top of the stack (the high
	index on top, and the low index below it). Calls \c opSlice metamethods if necessary. Pops the slice indices and
	pushes the result.

	\param container is the object to slice.
	\returns the stack index of the resulting value. */
	word_t croc_slice(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		auto slot = t->stackIndex - 2;
		sliceImpl(t, slot, *getValue(t, container), t->stack[slot], t->stack[slot + 1]);
		croc_popTop(t_);
		return croc_getStackSize(t_) - 1;
	}

	/** The equivalent of Croc's <tt>a[b .. c] = d</tt> operation. Expects the value to be assigned into the slice on
	top, and the slice indices below it (the high index below the value, and the low index below that). Calls \c
	opSliceAssign metamethods if necessary. Pops all three values.

	\param container is the object to slice-assign. */
	void croc_slicea(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(3);
		auto slot = t->stackIndex - 3;
		sliceaImpl(t, *getValue(t, container), t->stack[slot], t->stack[slot + 1], t->stack[slot + 2]);
		croc_pop(t_, 3);
	}

	/** The equivalent of Croc's <tt>a.(name)</tt> operation, this gets the field named \c name from the object in
	\c container and pushes the result. Calls any \c opField metamethods if necessary.

	\returns the stack index of the pushed value. */
	word_t croc_field(CrocThread* t_, word_t container, const char* name)
	{
		auto t = Thread::from(t_);
		container = fakeToAbs(t, container);
		croc_pushString(t_, name);
		auto slot = t->stackIndex - 1;
		fieldImpl(t, slot, t->stack[container], t->stack[slot].mString, false);
		return croc_getStackSize(t_) - 1;
	}

	/** Same as \ref croc_field, but expects the field name to be on top of the stack, which is replaced with the result
	of the field access (like how \ref croc_idx works).

	\returns the stack index of the resulting value. */
	word_t croc_fieldStk(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(name, -1, String, "field name");
		auto slot = t->stackIndex - 1;
		fieldImpl(t, slot, t->stack[fakeToAbs(t, container)], name, false);
		return croc_getStackSize(t_) - 1;
	}

	/** The equivalent of Croc's <tt>a.(name) = b</tt> operation, this sets the field named \c name in \c container to
	the value on top of the stack, and then pops that value. Calls any \c opFieldAssign metamethods if necessary. */
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

	/** Same as \ref croc_fielda, but expects the value on top of the stack and the name of the field to assign to be
	in the slot below it (like how \ref croc_idxa works). Pops both the name and value. */
	void croc_fieldaStk(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(name, -2, String, "field name");
		fieldaImpl(t, fakeToAbs(t, container), name, t->stack[t->stackIndex - 1], false);
		croc_pop(t_, 2);
	}

	/** Same as \ref croc_field, but does not call any \c opField metamethods. */
	word_t croc_rawField(CrocThread* t_, word_t container, const char* name)
	{
		auto t = Thread::from(t_);
		container = fakeToAbs(t, container);
		croc_pushString(t_, name);
		auto slot = t->stackIndex - 1;
		fieldImpl(t, slot, t->stack[container], t->stack[slot].mString, true);
		return croc_getStackSize(t_) - 1;
	}

	/** Same as \ref croc_fieldStk, but does not call any \c opField metamethods. */
	word_t croc_rawFieldStk(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(name, -1, String, "field name");
		auto slot = t->stackIndex - 1;
		fieldImpl(t, slot, t->stack[container], name, true);
		return croc_getStackSize(t_) - 1;
	}

	/** Same as \ref croc_fielda, but does not call any \c opFieldAssign metamethods. */
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

	/** Same as \ref croc_fieldaStk, but does not call any \c opFieldAssign metamethods. */
	void croc_rawFieldaStk(CrocThread* t_, word_t container)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(name, -2, String, "field name");
		fieldaImpl(t, fakeToAbs(t, container), name, t->stack[t->stackIndex - 1], true);
		croc_pop(t_, 2);
	}

	/** Gets the hidden field named \c name from the class or instance in \c container and pushes it.

	\returns the stack index of the pushed value. */
	word_t croc_hfield(CrocThread* t, word_t container, const char* name)
	{
		container = croc_absIndex(t, container);
		croc_pushString(t, name);
		return croc_hfieldStk(t, container);
	}

	/** Same as \ref croc_hfield, but expects the name on top of the stack and replaces the name with the value of the
	field (like \ref croc_fieldStk).

	\returns the stack index of the resulting value.*/
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

	/** Assigns the value on top of the stack into hidden field named \c name into the class or instance in \c container
	and pops the value (like \ref croc_fielda). */
	void croc_hfielda(CrocThread* t_, word_t container, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		container = croc_absIndex(t_, container);
		croc_pushString(t_, name);
		croc_swapTop(t_);
		croc_hfieldaStk(t_, container);
	}

	/** Same as \ref croc_hfielda but expects the value to be on top of the stack and the name of the hidden field to be
	below it, and pops both (like \ref croc_fieldaStk). */
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

	/** The equivalent of Croc's \c # operator, this pushes the length of the object in \c slot, calling \c opLength
	metamethods if necessary.

	\returns the stack index of the pushed length. */
	word_t croc_pushLen(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		auto o = *getValue(t, slot);
		croc_pushNull(t_);
		lenImpl(t, t->stackIndex - 1, o);
		return croc_getStackSize(t_) - 1;
	}

	/** Similar to croc_pushLen, except it expects the length to be an integer (throwing an error if not), and doesn't
	push the length onto the stack, instead returning it.

	\returns the length of the object at \c slot. */
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

	/** Sets the length of the object at \c slot to the value on top of the stack, calling \c opLengthAssign metamethods
	if necessary, and pops the length. */
	void croc_lena(CrocThread* t_, word_t slot)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		lenaImpl(t, *getValue(t, slot), t->stack[t->stackIndex - 1]);
		croc_popTop(t_);
	}

	/** Same as \ref croc_lena, but this is a convenience function which sets the length of the object at \c slot to the
	length given by \c length instead of using a value on the stack. The stack is left unchanged. */
	void croc_lenai(CrocThread* t, word_t slot, crocint_t length)
	{
		slot = croc_absIndex(t, slot);
		croc_pushInt(t, length);
		croc_lena(t, slot);
	}

	/** The equivalent of Croc's \c ~ operator, this concatenates the top \c num values on the stack, calling \c opCat
	and \c opCat_r metamethods as necessary. The top \c num values are popped, and the result of concatenation is pushed
	in their place.

	\returns the stack index of the resulting value. */
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

	/** The equivalent of Croc's \c ~= operator, this appends the top \c num values to the object in \c dest, calling
	\c opCatAssign metamethods as necessary. The top \c num values are popped. */
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