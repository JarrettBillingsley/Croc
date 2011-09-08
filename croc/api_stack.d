/******************************************************************************
This module contains "pure" stack manipulation APIs (both public and private).
They are pure in the sense that they do not deal with particular types, only
with moving values around on the stack.

License:
Copyright (c) 2011 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module croc.api_stack;

import tango.stdc.string;

import croc.api_checks;
import croc.api_debug;
import croc.api_interpreter;
import croc.types;
import croc.utils;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

/**
Returns the number of items on the stack. Valid positive stack indices range from [0 .. _stackSize(t)$(RPAREN).
Valid negative stack indices range from [-_stackSize(t) .. 0$(RPAREN).

Note that 'this' (stack index 0 or -_stackSize(t)) may not be overwritten or changed, although it can be used
with functions that don'_t modify their argument.
*/
uword stackSize(CrocThread* t)
{
	assert(t.stackIndex > t.stackBase);
	return t.stackIndex - t.stackBase;
}

/**
Sets the thread's stack size to an absolute value. The new stack size must be at least 1 (which
would leave 'this' on the stack and nothing else). If the new stack size is smaller than the old
one, the old values are simply discarded. If the new stack size is larger than the old one, the
new slots are filled with null. Throws an error if you try to set the stack size to 0.

Params:
	newSize = The new stack size. Must be greater than 0.
*/
void setStackSize(CrocThread* t, uword newSize)
{
	mixin(FuncNameMix);

	if(newSize == 0)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - newSize must be nonzero");

	auto curSize = stackSize(t);

	if(newSize != curSize)
	{
		t.stackIndex = t.stackBase + newSize;

		if(newSize > curSize)
		{
			checkStack(t, t.stackIndex);
			t.stack[t.stackBase + curSize .. t.stackIndex] = CrocValue.nullValue;
		}
	}
}

/**
Given an index, returns the absolute index that corresponds to it. This is useful for converting
relative (negative) indices to indices that will never change. If the index is already absolute,
just returns it. Throws an error if the index is out of range.
*/
word absIndex(CrocThread* t, word idx)
{
	return cast(word)fakeToRel(t, idx);
}

/**
Sees if a given stack index (negative or positive) is valid. Valid positive stack indices range
from [0 .. stackSize(t)$(RPAREN). Valid negative stack indices range from [-stackSize(t) .. 0$(RPAREN).

*/
bool isValidIndex(CrocThread* t, word idx)
{
	if(idx < 0)
		return idx >= -stackSize(t);
	else
		return idx < stackSize(t);
}

/**
Duplicates a value at the given stack index and pushes it onto the stack.

Params:
	slot = The _slot to duplicate. Defaults to -1, which means the top of the stack.

Returns:
	The stack index of the newly-pushed _slot.
*/
word dup(CrocThread* t, word slot = -1)
{
	auto s = fakeToAbs(t, slot);
	auto ret = pushNull(t);
	t.stack[t.stackIndex - 1] = t.stack[s];
	return ret;
}

/**
Swaps the two values at the given indices. The first index defaults to the second-from-top
value. The second index defaults to the top-of-stack. So, if you call swap with no indices, it will
_swap the top two values.

Params:
	first = The first stack index.
	second = The second stack index.
*/
void swap(CrocThread* t, word first = -2, word second = -1)
{
	auto f = fakeToAbs(t, first);
	auto s = fakeToAbs(t, second);

	if(f == s)
		return;

	auto tmp = t.stack[f];
	t.stack[f] = t.stack[s];
	t.stack[s] = tmp;
}

/**
Inserts the value at the top of the stack into the given _slot, shifting up the values in that _slot
and everything after it up by a _slot. This means the stack will stay the same size. Similar to a
"rotate" operation common to many stack machines.

Throws an error if 'slot' corresponds to the 'this' parameter. 'this' can never be modified.

If 'slot' corresponds to the top-of-stack (but not 'this'), this function is a no-op.

Params:
	slot = The _slot in which the value at the top will be inserted. If this refers to the top of the
		stack, this function does nothing.
*/
void insert(CrocThread* t, word slot)
{
	mixin(apiCheckNumParams!("1"));
	auto s = fakeToAbs(t, slot);

	if(s == t.stackBase)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - Cannot use 'this' as the destination");

	if(s == t.stackIndex - 1)
		return;

	auto tmp = t.stack[t.stackIndex - 1];
	memmove(&t.stack[s + 1], &t.stack[s], (t.stackIndex - s - 1) * CrocValue.sizeof);
	t.stack[s] = tmp;
}

/**
Similar to insert, but combines the insertion with a pop operation that pops everything after the
newly-inserted value off the stack.

Throws an error if 'slot' corresponds to the 'this' parameter. 'this' can never be modified.

If 'slot' corresponds to the top-of-stack (but not 'this'), this function is a no-op.
*/
void insertAndPop(CrocThread* t, word slot)
{
	mixin(apiCheckNumParams!("1"));
	auto s = fakeToAbs(t, slot);

	if(s == t.stackBase)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - Cannot use 'this' as the destination");

	if(s == t.stackIndex - 1)
		return;

	t.stack[s] = t.stack[t.stackIndex - 1];
	t.stackIndex = s + 1;
}

/**
The opposite of insert. This moves a value out of the middle of the stack to the top, shifting
everything after it down to fill its place. So if the top of the stack is something like
"1 2 3 4" and you move slot -3 to the top, it will then look like "1 3 4 2".

Throws an error if 'slot' corresponds to the 'this' parameter. 'this' cannot be moved (but you
can dup it instead). 

If 'slot' corresponds to the top-of-stack (but not 'this'), this function is a no-op.
*/
void moveToTop(CrocThread* t, word slot)
{
	mixin(apiCheckNumParams!("1"));
	auto s = fakeToAbs(t, slot);

	if(s == t.stackBase)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - Cannot move 'this' to the top of the stack");

	if(s == t.stackIndex - 1)
		return;

	auto tmp = t.stack[s];
	memmove(&t.stack[s], &t.stack[s + 1], (t.stackIndex - s - 1) * CrocValue.sizeof);
	t.stack[t.stackIndex - 1] = tmp;
}

/**
A more generic version of insert. This allows you to _rotate dist items within the top
numSlots items on the stack. The top dist items become the bottom dist items within that range
of indices. So, if the stack looks something like "1 2 3 4 5 6", and you perform a _rotate with
5 slots and a distance of 3, the stack will become "1 4 5 6 2 3". If the dist parameter is 1,
it behaves just like insert. Additionally, if the dist parameter is one less than numSlots, this
works just like moveToTop.

Attempting to _rotate more values than there are on the stack (excluding 'this') will throw an error.

If the distance is an even multiple of the number of slots, or if you _rotate 0 or 1 slots, this
function is a no-op.
*/
void rotate(CrocThread* t, uword numSlots, uword dist)
{
	mixin(FuncNameMix);

	if(numSlots > (stackSize(t) - 1))
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - Trying to rotate more values ({}) than can be rotated ({})", numSlots, stackSize(t) - 1);

	if(numSlots == 0)
		return;

	if(dist >= numSlots)
		dist %= numSlots;

	if(dist == 0)
		return;
	else if(dist == 1)
		return insert(t, -numSlots);
	else if(dist == numSlots - 1)
		return moveToTop(t, -numSlots);

	auto slots = t.stack[t.stackIndex - numSlots .. t.stackIndex];

	if(dist <= 8)
	{
		CrocValue[8] temp = void;
		temp[0 .. dist] = slots[$ - dist .. $];
		auto numOthers = numSlots - dist;
		memmove(&slots[$ - numOthers], &slots[0], numOthers * CrocValue.sizeof);
		slots[0 .. dist] = temp[0 .. dist];
	}
	else
	{
		dist = numSlots - dist;
		uword c = 0;

		for(uword v = 0; c < slots.length; v++)
		{
			auto i = v;
			auto j = v + dist;
			auto tmp = slots[v];
			c++;

			while(j != v)
			{
				slots[i] = slots[j];
				i = j;
				j += dist;

				if(j >= slots.length)
					j -= slots.length;

				c++;
			}

			slots[i] = tmp;
		}
	}
}

/**
Rotates all stack slots (excluding 'this'). This is the same as calling rotate with a numSlots
parameter of stackSize(_t) - 1.
*/
void rotateAll(CrocThread* t, uword dist)
{
	rotate(t, stackSize(t) - 1, dist);
}

/**
Pops a number of items off the stack. Throws an error if you try to _pop more items than there are
on the stack. 'this' is not counted; so if there is 'this' and one value, and you try to _pop 2
values, an error is thrown.

Params:
	n = The number of items to _pop. Defaults to 1. Must be greater than 0.
*/
void pop(CrocThread* t, uword n = 1)
{
	mixin(FuncNameMix);

	if(n == 0)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - Trying to pop zero items");

	if(n > (t.stackIndex - (t.stackBase + 1)))
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - Stack underflow");

	t.stackIndex -= n;
}

/**
Moves values from one thread to another. The values are popped off the source thread's stack
and put on the destination thread's stack in the same order that they were on the source stack.

If there are fewer values on the source thread's stack than the number of values, an error will
be thrown in the source thread.

If the two threads belong to different VMs, an error will be thrown in the source thread.

If the two threads are the same thread object, or if 0 values are transferred, this function is
a no-op.

Params:
	src = The thread from which the values will be taken.
	dest = The thread onto whose stack the values will be pushed.
	num = The number of values to transfer. There must be at least this many values on the source
		thread's stack.
*/
void transferVals(CrocThread* src, CrocThread* dest, uword num)
{
	if(src.vm !is dest.vm)
		throwStdException(src, "ApiError", "transferVals - Source and destination threads belong to different VMs");

	if(num == 0 || dest is src)
		return;

	mixin(apiCheckNumParams!("num", "src"));
	checkStack(dest, dest.stackIndex + num);

	dest.stack[dest.stackIndex .. dest.stackIndex + num] = src.stack[src.stackIndex - num .. src.stackIndex];
	dest.stackIndex += num;
	src.stackIndex -= num;
}

// ================================================================================================================================================
// Package
// ================================================================================================================================================

package:

void checkStack(CrocThread* t, AbsStack idx)
{
	if(idx >= t.stack.length)
	{
		uword size = idx * 2;
		auto oldBase = t.stack.ptr;
		t.vm.alloc.resizeArray(t.stack, size);
		auto newBase = t.stack.ptr;

		if(newBase !is oldBase)
			for(auto uv = t.upvalHead; uv !is null; uv = uv.nextuv)
				uv.value = (uv.value - oldBase) + newBase;
	}
}

RelStack fakeToRel(CrocThread* t, word fake)
{
	assert(t.stackIndex > t.stackBase);

	auto size = stackSize(t);

	if(fake < 0)
		fake += size;

	if(fake < 0 || fake >= size)
		throwStdException(t, "ApiError", "Invalid stack index {} (stack size = {})", fake, size);

	return cast(RelStack)fake;
}

AbsStack fakeToAbs(CrocThread* t, word fake)
{
	return fakeToRel(t, fake) + t.stackBase;
}

word push(CrocThread* t, CrocValue val)
{
	checkStack(t, t.stackIndex);
	t.stack[t.stackIndex] = val;
	t.stackIndex++;

	return cast(word)(t.stackIndex - 1 - t.stackBase);
}

CrocValue* getValue(CrocThread* t, word slot)
{
	return &t.stack[fakeToAbs(t, slot)];
}

CrocString* getStringObj(CrocThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == CrocValue.Type.String)
		return v.mString;
	else
		return null;
}

CrocTable* getTable(CrocThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == CrocValue.Type.Table)
		return v.mTable;
	else
		return null;
}

CrocArray* getArray(CrocThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == CrocValue.Type.Array)
		return v.mArray;
	else
		return null;
}

CrocMemblock* getMemblock(CrocThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == CrocValue.Type.Memblock)
		return v.mMemblock;
	else
		return null;
}

CrocFunction* getFunction(CrocThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == CrocValue.Type.Function)
		return v.mFunction;
	else
		return null;
}

CrocClass* getClass(CrocThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == CrocValue.Type.Class)
		return v.mClass;
	else
		return null;
}

CrocInstance* getInstance(CrocThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == CrocValue.Type.Instance)
		return v.mInstance;
	else
		return null;
}

CrocNamespace* getNamespace(CrocThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == CrocValue.Type.Namespace)
		return v.mNamespace;
	else
		return null;
}

CrocNativeObj* getNative(CrocThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == CrocValue.Type.NativeObj)
		return v.mNativeObj;
	else
		return null;
}

CrocWeakRef* getWeakRef(CrocThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == CrocValue.Type.WeakRef)
		return v.mWeakRef;
	else
		return null;
}

CrocFuncDef* getFuncDef(CrocThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == CrocValue.Type.FuncDef)
		return v.mFuncDef;
	else
		return null;
}