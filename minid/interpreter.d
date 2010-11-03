/******************************************************************************
This module contains most of the public "raw" API, as well as the MiniD
bytecode interpreter.

This module is $(B way) too big!

License:
Copyright (c) 2008 Jarrett Billingsley

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

module minid.interpreter;

import Float = tango.text.convert.Float;
import Integer = tango.text.convert.Integer;

version(MDExtendedCoro)
	import tango.core.Thread;

import tango.core.Exception;
import tango.core.Traits;
import tango.core.Tuple;
import tango.core.Vararg;
import tango.stdc.string;
import tango.text.Util;
import Utf = tango.text.convert.Utf;

import minid.alloc;
import minid.array;
import minid.classobj;
import minid.func;
import minid.gc;
import minid.instance;
import minid.namespace;
import minid.nativeobj;
import minid.opcodes;
import minid.string;
import minid.table;
import minid.thread;
import minid.types;
import minid.utils;
import minid.weakref;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

// ================================================================================================================================================
// VM-related functions

/**
Push the metatable for the given type.  If the type has no metatable, pushes null.  The type given must be
one of the "normal" types -- the "internal" types are illegal and an error will be thrown.

Params:
	type = The type whose metatable is to be pushed.

Returns:
	The stack index of the newly-pushed value (null if the type has no metatable, or a namespace if it does).
*/
word getTypeMT(MDThread* t, MDValue.Type type)
{
	mixin(FuncNameMix);

	if(!(type >= MDValue.Type.Null && type <= MDValue.Type.WeakRef))
		throwException(t, __FUNCTION__ ~ " - Cannot get metatable for type '{}'", MDValue.typeString(type));

	if(auto ns = t.vm.metaTabs[cast(uword)type])
		return pushNamespace(t, ns);
	else
		return pushNull(t);
}

/**
Sets the metatable for the given type to the namespace or null at the top of the stack.  Throws an
error if the type given is one of the "internal" types, or if the value at the top of the stack is
neither null nor a namespace.

Params:
	type = The type whose metatable is to be set.
*/
void setTypeMT(MDThread* t, MDValue.Type type)
{
	mixin(checkNumParams!("1"));

	if(!(type >= MDValue.Type.Null && type <= MDValue.Type.WeakRef))
		throwException(t, __FUNCTION__ ~ " - Cannot set metatable for type '{}'", MDValue.typeString(type));

	auto v = getValue(t, -1);

	if(v.type == MDValue.Type.Namespace)
		t.vm.metaTabs[cast(uword)type] = v.mNamespace;
	else if(v.type == MDValue.Type.Null)
		t.vm.metaTabs[cast(uword)type] = null;
	else
	{
		pushTypeString(t, -1);
		throwException(t, __FUNCTION__ ~ " - Metatable must be either a namespace or 'null', not '{}'", getString(t, -1));
	}

	pop(t);
}

/**
Import a module with the given name.  Works just like the import statement in MiniD.  Pushes the
module's namespace onto the stack.

Params:
	name = The name of the module to be imported.

Returns:
	The stack index of the imported module's namespace.
*/
word importModule(MDThread* t, char[] name)
{
	pushString(t, name);
	importModule(t, -1);
	insertAndPop(t, -2);
	return stackSize(t) - 1;
}

/**
Same as above, but uses a name on the stack rather than one provided as a parameter.

Params:
	name = The stack index of the string holding the name of the module to be imported.

Returns:
	The stack index of the imported module's namespace.
*/
word importModule(MDThread* t, word name)
{
	mixin(FuncNameMix);

	auto str = getStringObj(t, name);

	if(str is null)
	{
		pushTypeString(t, name);
		throwException(t, __FUNCTION__ ~ " - name must be a 'string', not a '{}'", getString(t, -1));
	}

	pushNull(t);
	importImpl(t, str, t.stackIndex - 1);

	return stackSize(t) - 1;
}

/**
Same as importModule, but doesn't leave the module namespace on the stack.

Params:
	name = The name of the module to be imported.
*/
void importModuleNoNS(MDThread* t, char[] name)
{
	pushString(t, name);
	importModule(t, -1);
	pop(t, 2);
}

/**
Same as above, but uses a name on the stack rather than one provided as a parameter.

Params:
	name = The stack index of the string holding the name of the module to be imported.
*/
void importModuleNoNS(MDThread* t, word name)
{
	importModule(t, name);
	pop(t);
}

/**
Pushes the VM's registry namespace onto the stack.  The registry is sort of a hidden global namespace only accessible
from native code and which native code may use for any purpose.

Returns:
	The stack index of the newly-pushed namespace.
*/
word getRegistry(MDThread* t)
{
	return pushNamespace(t, t.vm.registry);
}

/**
Allocates a block of memory using the given thread's VM's allocator function.  This memory is $(B not) garbage-collected.
You must free the memory returned by this function in order to avoid memory leaks.

The array returned by this function should not have its length set or be appended to (~=).

Params:
	size = The size, in bytes, of the block to allocate.

Returns:
	A void array representing the memory block.
*/
void[] allocMem(MDThread* t, uword size)
{
	return t.vm.alloc.allocArray!(void)(size);
}

/**
Resize a block of memory.  $(B Only call this on memory that has been allocated using the allocMem, _resizeMem or dupMem
functions.)  If you pass this function an empty (0-length) memory block, it will allocate memory.  If you resize an existing
block to a length of 0, it will deallocate that memory.

If you resize a block to a smaller size, its data will be truncated.  If you resize a block to a larger size, the empty
space will be uninitialized.

The array returned by this function through the mem parameter should not have its length set or be appended to (~=).

Params:
	mem = A reference to the memory block you want to reallocate.  This is a reference so that the original memory block
		reference that you pass in is updated.  This can be a 0-length array.

	size = The size, in bytes, of the new size of the memory block.
*/
void resizeMem(MDThread* t, ref void[] mem, uword size)
{
	t.vm.alloc.resizeArray(mem, size);
}

/**
Duplicate a block of memory.  This is safe to call on memory that was not allocated with the thread's VM's allocator.
The new block will be the same size and contain the same data as the old block.

The array returned by this function should not have its length set or be appended to (~=).

Params:
	mem = The block of memory to copy.  This is not required to have been allocated by allocMem, resizeMem, or _dupMem.

Returns:
	The new memory block.
*/
void[] dupMem(MDThread* t, void[] mem)
{
	return t.vm.alloc.dupArray(mem);
}

/**
Free a block of memory.  $(B Only call this on memory that has been allocated with allocMem, resizeMem, or dupMem.)
It's legal to free a 0-length block.

Params:
	mem = A reference to the memory block you want to free.  This is a reference so that the original memory block
		reference that you pass in is updated.  This can be a 0-length array.
*/
void freeMem(MDThread* t, ref void[] mem)
{
	t.vm.alloc.freeArray(mem);
}

/**
Creates a reference to a MiniD object.  A reference is like the native equivalent of MiniD's nativeobj.  Whereas a
nativeobj allows MiniD to hold a reference to a native object, a reference allows native code to hold a reference
to a MiniD object.

References are identified by unique integer values which are passed to the  $(D pushRef) and $(D removeRef) functions.
These are guaranteed to be probabilistically to be unique for the life of the program.  What I mean by that is that
if you created a million references per second, it would take you over half a million years before the reference
values wrapped around.  Aren'_t 64-bit integers great?

References prevent the referenced MiniD object from being collected, ever, so unless you want memory leaks, you must
call $(D removeRef) when your code no longer needs the object.  See $(minid.ex) for some reference helpers.

Params:
	idx = The stack index of the object to which a reference should be created.  If this refers to a value type,
		an exception will be thrown.

Returns:
	The new reference name for the given object.  You can create several references to the same object; it will not
	be collectible until all references to it have been removed.
*/
ulong createRef(MDThread* t, word idx)
{
	mixin(FuncNameMix);

	auto v = getValue(t, idx);

	if(!v.isObject())
	{
		pushTypeString(t, idx);
		throwException(t, __FUNCTION__ ~ " - Can only get references to reference types, not '{}'", getString(t, -1));
	}

	auto ret = t.vm.currentRef++;
	*t.vm.refTab.insert(t.vm.alloc, ret) = v.mBaseObj;
	return ret;
}

/**
Pushes the object associated with the given reference onto the stack and returns the slot of the pushed object.
If the given reference is invalid, an exception will be thrown.
*/
word pushRef(MDThread* t, ulong r)
{
	mixin(FuncNameMix);

	auto v = t.vm.refTab.lookup(r);

	if(v is null)
		throwException(t, __FUNCTION__ ~ " - Reference '{}' does not exist", r);

	return push(t, MDValue(*v));
}

/**
Removes the given reference.  When all references to an object are removed, it will no longer be considered to be
referenced by the host app and will be subject to normal GC rules.  If the given reference is invalid, an
exception will be thrown.
*/
void removeRef(MDThread* t, ulong r)
{
	mixin(FuncNameMix);

	if(!t.vm.refTab.remove(r))
		throwException(t, __FUNCTION__ ~ " - Reference '{}' does not exist", r);
}

// ================================================================================================================================================
// GC-related stuff

/**
Runs the garbage collector if necessary.

This will perform a garbage collection only if a sufficient amount of memory has been allocated since
the last collection.

Params:
	t = The thread to use to collect the garbage.  Garbage collection is vm-wide but requires a thread
		in order to be able to call finalization methods.

Returns:
	The number of bytes collected, which may be 0.
*/
public uword maybeGC(MDThread* t)
{
	uword ret = 0;

	if(t.vm.alloc.totalBytes >= t.vm.alloc.gcLimit)
	{
		ret = gc(t);

		if(t.vm.alloc.totalBytes > (t.vm.alloc.gcLimit >> 1))
			t.vm.alloc.gcLimit <<= 1;
	}

	return ret;
}

/**
Runs the garbage collector unconditionally.

Params:
	t = The thread to use to collect the garbage.  Garbage collection is vm-wide but requires a thread
		in order to be able to call finalization methods.

Returns:
	The number of bytes collected by this collection cycle.
*/
public uword gc(MDThread* t)
{
	auto beforeSize = t.vm.alloc.totalBytes;

	mark(t.vm);
	sweep(t.vm);
	runFinalizers(t);

	return beforeSize - t.vm.alloc.totalBytes;
}

// ================================================================================================================================================
// Stack manipulation

/**
Duplicates a value at the given stack index and pushes it onto the stack.

Params:
	slot = The _slot to duplicate.  Defaults to -1, which means the top of the stack.

Returns:
	The stack index of the newly-pushed _slot.
*/
word dup(MDThread* t, word slot = -1)
{
	auto s = fakeToAbs(t, slot);
	auto ret = pushNull(t);
	t.stack[t.stackIndex - 1] = t.stack[s];
	return ret;
}

/**
Swaps the two values at the given indices.  The first index defaults to the second-from-top
value.  The second index defaults to the top-of-stack.  So, if you call swap with no indices, it will
_swap the top two values.

Params:
	first = The first stack index.
	second = The second stack index.
*/
void swap(MDThread* t, word first = -2, word second = -1)
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
and everything after it up by a _slot.  This means the stack will stay the same size.  Similar to a
"rotate" operation common to many stack machines.

Throws an error if 'slot' corresponds to the 'this' parameter.  'this' can never be modified.

If 'slot' corresponds to the top-of-stack (but not 'this'), this function is a no-op.

Params:
	slot = The _slot in which the value at the top will be inserted.  If this refers to the top of the
		stack, this function does nothing.
*/
void insert(MDThread* t, word slot)
{
	mixin(checkNumParams!("1"));
	auto s = fakeToAbs(t, slot);

	if(s == t.stackBase)
		throwException(t, __FUNCTION__ ~ " - Cannot use 'this' as the destination");

	if(s == t.stackIndex - 1)
		return;

	auto tmp = t.stack[t.stackIndex - 1];
	memmove(&t.stack[s + 1], &t.stack[s], (t.stackIndex - s - 1) * MDValue.sizeof);
	t.stack[s] = tmp;
}

/**
Similar to insert, but combines the insertion with a pop operation that pops everything after the
newly-inserted value off the stack.

Throws an error if 'slot' corresponds to the 'this' parameter.  'this' can never be modified.

If 'slot' corresponds to the top-of-stack (but not 'this'), this function is a no-op.
*/
void insertAndPop(MDThread* t, word slot)
{
	mixin(checkNumParams!("1"));
	auto s = fakeToAbs(t, slot);

	if(s == t.stackBase)
		throwException(t, __FUNCTION__ ~ " - Cannot use 'this' as the destination");

	if(s == t.stackIndex - 1)
		return;

	t.stack[s] = t.stack[t.stackIndex - 1];
	t.stackIndex = s + 1;
}

/**
A more generic version of insert.  This allows you to _rotate dist items within the top
numSlots items on the stack.  The top dist items become the bottom dist items within that range
of indices.  So, if the stack looks something like "1 2 3 4 5 6", and you perform a _rotate with
5 slots and a distance of 3, the stack will become "1 4 5 6 2 3".  If the dist parameter is 1,
it behaves just like insert.

Attempting to _rotate more values than there are on the stack (excluding 'this') will throw an error.

If the distance is an even multiple of the number of slots, or if you _rotate 0 or 1 slots, this
function is a no-op.
*/
void rotate(MDThread* t, uword numSlots, uword dist)
{
	mixin(FuncNameMix);

	if(numSlots > (stackSize(t) - 1))
		throwException(t, __FUNCTION__ ~ " - Trying to rotate more values ({}) than can be rotated ({})", numSlots, stackSize(t) - 1);

	if(numSlots == 0)
		return;

	if(dist >= numSlots)
		dist %= numSlots;

	if(dist == 0)
		return;
	else if(dist == 1)
		return insert(t, -numSlots);

	auto slots = t.stack[t.stackIndex - numSlots .. t.stackIndex];

	if(dist <= 8)
	{
		MDValue[8] temp = void;
		temp[0 .. dist] = slots[$ - dist .. $];
		auto numOthers = numSlots - dist;
		memmove(&slots[$ - numOthers], &slots[0], numOthers * MDValue.sizeof);
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
Rotates all stack slots (excluding 'this').  This is the same as calling rotate with a numSlots
parameter of stackSize(_t) - 1.
*/
void rotateAll(MDThread* t, uword dist)
{
	rotate(t, stackSize(t) - 1, dist);
}

/**
Pops a number of items off the stack.  Throws an error if you try to _pop more items than there are
on the stack.  'this' is not counted; so if there is 'this' and one value, and you try to _pop 2
values, an error is thrown.

Params:
	n = The number of items to _pop.  Defaults to 1.  Must be greater than 0.
*/
void pop(MDThread* t, uword n = 1)
{
	mixin(FuncNameMix);

	if(n == 0)
		throwException(t, __FUNCTION__ ~ " - Trying to pop zero items");

	if(n > (t.stackIndex - (t.stackBase + 1)))
		throwException(t, __FUNCTION__ ~ " - Stack underflow");

	t.stackIndex -= n;
}

/**
Sets the thread's stack size to an absolute value.  The new stack size must be at least 1 (which
would leave 'this' on the stack and nothing else).  If the new stack size is smaller than the old
one, the old values are simply discarded.  If the new stack size is larger than the old one, the
new slots are filled with null.  Throws an error if you try to set the stack size to 0.

Params:
	newSize = The new stack size.  Must be greater than 0.
*/
void setStackSize(MDThread* t, uword newSize)
{
	mixin(FuncNameMix);

	if(newSize == 0)
		throwException(t, __FUNCTION__ ~ " - newSize must be nonzero");

	auto curSize = stackSize(t);

	if(newSize != curSize)
	{
		t.stackIndex = t.stackBase + newSize;

		if(newSize > curSize)
		{
			checkStack(t, t.stackIndex);
			t.stack[t.stackBase + curSize .. t.stackIndex] = MDValue.nullValue;
		}
	}
}

/**
Moves values from one thread to another.  The values are popped off the source thread's stack
and put on the destination thread's stack in the same order that they were on the source stack.

If there are fewer values on the source thread's stack than the number of values, an error will
be thrown in the source thread.

If the two threads belong to different VMs, an error will be thrown in the source thread.

If the two threads are the same thread object, or if 0 values are transferred, this function is
a no-op.

Params:
	src = The thread from which the values will be taken.
	dest = The thread onto whose stack the values will be pushed.
	num = The number of values to transfer.  There must be at least this many values on the source
		thread's stack.
*/
void transferVals(MDThread* src, MDThread* dest, uword num)
{
	if(src.vm !is dest.vm)
		throwException(src, "transferVals - Source and destination threads belong to different VMs");

	if(num == 0 || dest is src)
		return;

	mixin(checkNumParams!("num", "src"));
	checkStack(dest, dest.stackIndex + num);

	dest.stack[dest.stackIndex .. dest.stackIndex + num] = src.stack[src.stackIndex - num .. src.stackIndex];
	dest.stackIndex += num;
	src.stackIndex -= num;
}

// ================================================================================================================================================
// Pushing values onto the stack

/**
These push a value of the given type onto the stack.

Returns:
	The stack index of the newly-pushed value.
*/
word pushNull(MDThread* t)
{
	return push(t, MDValue.nullValue);
}

/// ditto
word pushBool(MDThread* t, bool v)
{
	return push(t, MDValue(v));
}

/// ditto
word pushInt(MDThread* t, mdint v)
{
	return push(t, MDValue(v));
}

/// ditto
word pushFloat(MDThread* t, mdfloat v)
{
	return push(t, MDValue(v));
}

/// ditto
word pushChar(MDThread* t, dchar v)
{
	return push(t, MDValue(v));
}

/// ditto
word pushString(MDThread* t, char[] v)
{
	return pushStringObj(t, createString(t, v));
}

/**
Push a formatted string onto the stack.  This works exactly like tango.text.convert.Layout (and in fact
calls it), except that the destination buffer is a MiniD string.

Params:
	fmt = The Tango-style format string.
	... = The arguments to be formatted.

Returns:
	The stack index of the newly-pushed string.
*/
word pushFormat(MDThread* t, char[] fmt, ...)
{
	return pushVFormat(t, fmt, _arguments, _argptr);
}

/**
A version of pushFormat meant to be called from variadic functions.

Params:
	fmt = The Tango-style format string.
	arguments = The array of TypeInfo for the variadic _arguments.
	argptr = The platform-specific argument pointer.

Returns:
	The stack index of the newly-pushed string.
*/
word pushVFormat(MDThread* t, char[] fmt, TypeInfo[] arguments, va_list argptr)
{
	uword numPieces = 0;

	uint sink(char[] data)
	{
		if(data.length > 0)
		{
			pushString(t, data);
			numPieces++;
		}

		return data.length;
	}

	safeCode(t, t.vm.formatter.convert(&sink, arguments, argptr, fmt));
	maybeGC(t);
	return cat(t, numPieces);
}

/**
Creates a new table object and pushes it onto the stack.

Params:
	size = The number of slots to preallocate in the table, as an optimization.

Returns:
	The stack index of the newly-created table.
*/
word newTable(MDThread* t, uword size = 0)
{
	maybeGC(t);
	return pushTable(t, table.create(t.vm.alloc, size));
}

/**
Creates a new array object and pushes it onto the stack.

Params:
	len = The length of the new array.

Returns:
	The stack index of the newly-created array.
*/
word newArray(MDThread* t, uword len)
{
	maybeGC(t);
	return pushArray(t, array.create(t.vm.alloc, len));
}

/**
Creates a new array object using values at the top of the stack.  Pops those values and pushes
the new array onto the stack.

Params:
	len = How many values on the stack to be put into the array, and the length of the resulting
		array.

Returns:
	The stack index of the newly-created array.
*/
word newArrayFromStack(MDThread* t, uword len)
{
	mixin(checkNumParams!("len"));
	maybeGC(t);
	auto a = array.create(t.vm.alloc, len);
	a.slice[] = t.stack[t.stackIndex - len .. t.stackIndex];
	pop(t, len);
	return pushArray(t, a);
}

/**
Creates a new native closure and pushes it onto the stack.

If you want to associate upvalues with the function, you should push them in order on
the stack before calling newFunction and then pass how many upvalues you pushed.
An example:

-----
// 1. Push any upvalues.  Here we have two.  Note that they are pushed in order:
// upvalue 0 will be 5 and upvalue 1 will be "hi" once the closure is created.
pushInt(t, 5);
pushString(t, "hi");

// 2. Call newFunction.
newFunction(t, &myFunc, "myFunc", 2);

// 3. Store the resulting closure somewhere.
setGlobal(t, "myFunc");
-----

This function pops any upvalues off the stack and leaves the new closure in their place.

The function's environment is, by default, the current environment (see pushEnvironment).
To use a different environment, see newFunctionWithEnv.

Params:
	func = The native function to be used in the closure.
	name = The _name to be given to the function.  This is just the 'debug' _name that
		shows up in error messages.  In order to make the function accessible, you have
		to actually put the resulting closure somewhere, like in the globals, or in
		a namespace.
	numUpvals = How many upvalues there are on the stack under the _name to be associated
		with this closure.  Defaults to 0.

Returns:
	The stack index of the newly-created closure.
*/
word newFunction(MDThread* t, NativeFunc func, char[] name, uword numUpvals = 0)
{
	pushEnvironment(t);
	return newFunctionWithEnv(t, func, name, numUpvals);
}

/**
Creates a new native closure with an explicit environment and pushes it onto the stack.

Very similar to newFunction, except that it also expects the environment for the function
(a namespace) to be on top of the stack.  Using newFunction's example, one would push
the environment namespace after step 1, and step 2 would call newFunctionWithEnv instead.

Params:
	func = The native function to be used in the closure.
	name = The _name to be given to the function.  This is just the 'debug' _name that
		shows up in error messages.  In order to make the function accessible, you have
		to actually put the resulting closure somewhere, like in the globals, or in
		a namespace.
	numUpvals = How many upvalues there are on the stack under the _name and environment to
		be associated with this closure.  Defaults to 0.

Returns:
	The stack index of the newly-created closure.
*/
word newFunctionWithEnv(MDThread* t, NativeFunc func, char[] name, uword numUpvals = 0)
{
	mixin(checkNumParams!("numUpvals + 1"));

	auto env = getNamespace(t, -1);

	if(env is null)
	{
		pushTypeString(t, -1);
		throwException(t, __FUNCTION__ ~ " - Environment must be a namespace, not a '{}'", getString(t, -1));
	}

	maybeGC(t);

	auto f = .func.create(t.vm.alloc, env, createString(t, name), func, numUpvals);
	f.nativeUpvals()[] = t.stack[t.stackIndex - 1 - numUpvals .. t.stackIndex - 1];
	pop(t, numUpvals + 1); // upvals and env.

	return pushFunction(t, f);
}

/**
Creates a new class and pushes it onto the stack.

After creating the class, you can then fill it with members by using fielda.

Params:
	base = The stack index of the _base class.  The _base can be `null`, in which case Object (defined
		in the _base library and which lives in the global namespace) will be used.  Otherwise it must
		be a class.

	name = The _name of the class.  Remember that you still have to store the class object somewhere,
		though, like in a global.

Returns:
	The stack index of the newly-created class.
*/
word newClass(MDThread* t, word base, char[] name)
{
	mixin(FuncNameMix);

	MDClass* b = void;

	if(isNull(t, base))
	{
		pushGlobal(t, "Object");
		b = getClass(t, -1);

		if(b is null)
		{
			pushTypeString(t, -1);
			throwException(t, __FUNCTION__ ~ " - 'Object' is not a class; it is a '{}'!", getString(t, -1));
		}

		pop(t);
	}
	else if(auto c = getClass(t, base))
		b = c;
	else
	{
		pushTypeString(t, base);
		throwException(t, __FUNCTION__ ~ " - Base must be 'null' or 'class', not '{}'", getString(t, -1));
	}

	maybeGC(t);
	return pushClass(t, classobj.create(t.vm.alloc, createString(t, name), b));
}

/**
Same as above, except it uses the global Object as the base.  The new class is left on the
top of the stack.
*/
word newClass(MDThread* t, char[] name)
{
	mixin(FuncNameMix);

	pushGlobal(t, "Object");
	auto b = getClass(t, -1);

	if(b is null)
	{
		pushTypeString(t, -1);
		throwException(t, __FUNCTION__ ~ " - 'Object' is not a class; it is a '{}'!", getString(t, -1));
	}

	pop(t);
	maybeGC(t);
	return pushClass(t, classobj.create(t.vm.alloc, createString(t, name), b));
}

/**
Creates an instance of a class and pushes it onto the stack.  This does $(I not) call any
constructors defined for the class; this simply allocates an instance.

MiniD instances can have two kinds of extra data associated with them for use by the host: extra
MiniD values and arbitrary bytes.  The structure of a MiniD instance is something like this:

-----
// ---------
// |       |
// |       | The data that's part of every instance - its parent class, fields, and finalizer.
// |       |
// +-------+
// |0: "x" | Extra MiniD values which can point into the MiniD heap.
// |1: 5   |
// +-------+
// |...    | Arbitrary byte data.
// ---------
-----

Both extra sections are optional, and no instances created from script classes will have them.

Extra MiniD values are useful for adding "members" to the instance which are not visible to the
scripts but which can still hold MiniD objects.  They will be scanned by the GC, so objects
referenced by these members will not be collected.  If you want to hold a reference to a native
D object, for instance, this would be the place to put it (wrapped in a NativeObject).

The arbitrary bytes associated with an instance are not scanned by either the D or the MiniD GC,
so don'_t store references to GC'ed objects there.  These bytes are useable for just about anything,
such as storing values which can'_t be stored in MiniD values -- structs, complex numbers, long
integers, whatever.

A clarification: You can store references to $(B heap) objects in the extra bytes, but you must not
store references to $(B GC'ed) objects there.  That is, you can 'malloc' some data and store the pointer
in the extra bytes, since that's not GC'ed memory.  You must however perform your own memory management for
such memory.  You can set up a finalizer function for instances in which you can perform memory management
for these references.

Params:
	base = The class from which this instance will be created.
	numValues = How many extra MiniD values will be associated with the instance.  See above.
	extraBytes = How many extra bytes to attach to the instance.  See above.
*/
word newInstance(MDThread* t, word base, uword numValues = 0, uword extraBytes = 0)
{
	mixin(FuncNameMix);

	auto b = getClass(t, base);

	if(b is null)
	{
		pushTypeString(t, base);
		throwException(t, __FUNCTION__ ~ " - expected 'class' for base, not '{}'", getString(t, -1));
	}

	maybeGC(t);
	return pushInstance(t, instance.create(t.vm.alloc, b, numValues, extraBytes));
}

/**
Creates a new namespace object and pushes it onto the stack.

The parent of the new namespace will be the current function environment, exactly
as in MiniD when you declare a namespace without an explicit parent.

Params:
	name = The _name of the namespace.

Returns:
	The stack index of the newly-created namespace.
*/
word newNamespace(MDThread* t, char[] name)
{
	auto ret = newNamespaceNoParent(t, name);
	getNamespace(t, ret).parent = getEnv(t);
	return ret;
}

/**
Creates a new namespace object with an explicit parent and pushes it onto the stack.

Params:
	parent = The stack index of the _parent.  The _parent can be null, in which case
		the new namespace will not have a _parent.  Otherwise it must be a namespace.
	name = The _name of the namespace.

Returns:
	The stack index of the newly-created namespace.
*/
word newNamespace(MDThread* t, word parent, char[] name)
{
	mixin(FuncNameMix);

	MDNamespace* p = void;

	if(isNull(t, parent))
		p = null;
	else if(auto ns = getNamespace(t, parent))
		p = ns;
	else
	{
		pushTypeString(t, parent);
		throwException(t, __FUNCTION__ ~ " - Parent must be null or namespace, not '{}'", getString(t, -1));
	}

	auto ret = newNamespaceNoParent(t, name);
	getNamespace(t, ret).parent = p;
	return ret;
}

/**
Creates a new namespace object with no parent and pushes it onto the stack.

This is very similar to newNamespace but creates a namespace without a parent.
This function expects no values to be on the stack.

Params:
	name = The _name of the namespace.

Returns:
	The stack index of the newly-created namespace.
*/
word newNamespaceNoParent(MDThread* t, char[] name)
{
	maybeGC(t);
	return pushNamespace(t, namespace.create(t.vm.alloc, createString(t, name), null));
}

/**
Creates a new thread object (coroutine) and pushes it onto the stack.

Params:
	func = The slot which contains the function to be used as the coroutine's body.
		If extended coroutine support is enabled, this can be a native or script function;
		otherwise, it must be a script function.

Returns:
	The stack index of the newly-created thread.
*/
word newThread(MDThread* t, word func)
{
	mixin(FuncNameMix);

	auto f = getFunction(t, func);

	if(f is null)
	{
		pushTypeString(t, func);
		throwException(t, __FUNCTION__ ~ " - Thread function must be of type 'function', not '{}'", getString(t, -1));
	}

	version(MDExtendedCoro) {} else
	{
		if(f.isNative)
			throwException(t, __FUNCTION__ ~ " - Native functions may not be used as the body of a coroutine");
	}

	maybeGC(t);
	
	auto nt = thread.create(t.vm, f);
	nt.hookFunc = t.hookFunc;
	nt.hooks = t.hooks;
	nt.hookDelay = t.hookDelay;
	nt.hookCounter = t.hookCounter;
	return pushThread(t, nt);
}

/**
Pushes the given thread onto this thread's stack.

Params:
	o = The thread to push.

Returns:
	The stack index of the newly-pushed value.
*/
word pushThread(MDThread* t, MDThread* o)
{
	return push(t, MDValue(o));
}

/**
Pushes a reference to a native (D) object onto the stack.

Params:
	o = The object to push.

Returns:
	The index of the newly-pushed value.
*/
word pushNativeObj(MDThread* t, Object o)
{
	maybeGC(t);
	return push(t, MDValue(nativeobj.create(t.vm, o)));
}

/**
Pushes a weak reference to the object at the given stack index onto the stack.  For value types (null,
bool, int, float, and char), weak references are unnecessary, and in these cases the value will simply
be pushed.  Otherwise the pushed value will be a weak reference object.

Params:
	idx = The stack index of the object to get a weak reference of.

Returns:
	The stack index of the newly-pushed value.
*/
word pushWeakRef(MDThread* t, word idx)
{
	switch(type(t, idx))
	{
		case
			MDValue.Type.Null,
			MDValue.Type.Bool,
			MDValue.Type.Int,
			MDValue.Type.Float,
			MDValue.Type.Char:

			return dup(t, idx);

		default:
			return pushWeakRefObj(t, weakref.create(t.vm, getValue(t, idx).mBaseObj));
	}
}

// ================================================================================================================================================
// Stack queries

/**
Given an index, returns the absolute index that corresponds to it.  This is useful for converting
relative (negative) indices to indices that will never change.  If the index is already absolute,
just returns it.  Throws an error if the index is out of range.
*/
word absIndex(MDThread* t, word idx)
{
	return cast(word)fakeToRel(t, idx);
}

/**
Sees if a given stack index (negative or positive) is valid.  Valid positive stack indices range
from [0 .. stackSize(t)$(RPAREN).  Valid negative stack indices range from [-stackSize(t) .. 0$(RPAREN).

*/
bool isValidIndex(MDThread* t, word idx)
{
	if(idx < 0)
		return idx >= -stackSize(t);
	else
		return idx < stackSize(t);
}

/**
Sees if the value at the given _slot is null.
*/
bool isNull(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.Null;
}

/**
Sees if the value at the given _slot is a bool.
*/
bool isBool(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.Bool;
}

/**
Sees if the value at the given _slot is an int.
*/
bool isInt(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.Int;
}

/**
Sees if the value at the given _slot is a float.
*/
bool isFloat(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.Float;
}

/**
Sees if the value at the given _slot is an int or a float.
*/
bool isNum(MDThread* t, word slot)
{
	auto type = type(t, slot);
	return type == MDValue.Type.Int || type == MDValue.Type.Float;
}

/**
Sees if the value at the given _slot is a char.
*/
bool isChar(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.Char;
}

/**
Sees if the value at the given _slot is a string.
*/
bool isString(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.String;
}

/**
Sees if the value at the given _slot is a table.
*/
bool isTable(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.Table;
}

/**
Sees if the value at the given _slot is an array.
*/
bool isArray(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.Array;
}

/**
Sees if the value at the given _slot is a function.
*/
bool isFunction(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.Function;
}

/**
Sees if the value at the given _slot is a class.
*/
bool isClass(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.Class;
}

/**
Sees if the value at the given _slot is an instance.
*/
bool isInstance(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.Instance;
}

/**
Sees if the value at the given _slot is a namespace.
*/
bool isNamespace(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.Namespace;
}

/**
Sees if the value at the given _slot is a thread.
*/
bool isThread(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.Thread;
}

/**
Sees if the value at the given _slot is a native object.
*/
bool isNativeObj(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.NativeObj;
}

/**
Sees if the value at the given _slot is a weak reference.
*/
bool isWeakRef(MDThread* t, word slot)
{
	return type(t, slot) == MDValue.Type.WeakRef;
}

/**
Gets the truth value of the value at the given _slot.  null, false, integer 0, floating point 0.0,
and character '\0' are considered false; everything else is considered true.  This is the same behavior
as within the language.
*/
bool isTrue(MDThread* t, word slot)
{
	return !getValue(t, slot).isFalse();
}

/**
Gets the _type of the value at the given _slot.  Value types are given by the MDValue.Type
enumeration defined in minid.types.
*/
MDValue.Type type(MDThread* t, word slot)
{
	return getValue(t, slot).type;
}

/**
Returns the boolean value at the given _slot, or throws an error if it isn'_t one.
*/
bool getBool(MDThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != MDValue.Type.Bool)
	{
		pushTypeString(t, slot);
		throwException(t, __FUNCTION__ ~ " - expected 'bool' but got '{}'", getString(t, -1));
	}

	return v.mBool;
}

/**
Returns the integer value at the given _slot, or throws an error if it isn'_t one.
*/
mdint getInt(MDThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != MDValue.Type.Int)
	{
		pushTypeString(t, slot);
		throwException(t, __FUNCTION__ ~ " - expected 'int' but got '{}'", getString(t, -1));
	}

	return v.mInt;
}

/**
Returns the float value at the given _slot, or throws an error if it isn'_t one.
*/
mdfloat getFloat(MDThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != MDValue.Type.Float)
	{
		pushTypeString(t, slot);
		throwException(t, __FUNCTION__ ~ " - expected 'float' but got '{}'", getString(t, -1));
	}

	return v.mFloat;
}

/**
Returns the numerical value at the given _slot.  This always returns an mdfloat, and will
implicitly cast int values to floats.  Throws an error if the value is neither an int
nor a float.
*/
mdfloat getNum(MDThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type == MDValue.Type.Float)
		return v.mFloat;
	else if(v.type == MDValue.Type.Int)
		return v.mInt;
	else
	{
		pushTypeString(t, slot);
		throwException(t, __FUNCTION__ ~ " - expected 'float' or 'int' but got '{}'", getString(t, -1));
	}

	assert(false);
}

/**
Returns the character value at the given _slot, or throws an error if it isn'_t one.
*/
dchar getChar(MDThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != MDValue.Type.Char)
	{
		pushTypeString(t, slot);
		throwException(t, __FUNCTION__ ~ " - expected 'char' but got '{}'", getString(t, -1));
	}

	return v.mChar;
}

/**
Returns the string value at the given _slot, or throws an error if it isn'_t one.

The returned string points into the MiniD heap.  It should NOT be modified in any way.  The returned
array reference should also not be stored on the D heap, as once the string object is removed from the
MiniD stack, there is no guarantee that the string data will be valid (MiniD might collect it, as it
has no knowledge of the reference held by D).  If you need the string value for a longer period of time,
you should dup it.
*/
char[] getString(MDThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != MDValue.Type.String)
	{
		pushTypeString(t, slot);
		throwException(t, __FUNCTION__ ~ " - expected 'string' but got '{}'", getString(t, -1));
	}

	return v.mString.toString();
}

/**
Returns the thread object at the given _slot, or throws an error if it isn'_t one.

The returned thread object points into the MiniD heap, and as such, if no reference to it is
held from the MiniD heap or stack, it may be collected, so be sure not to store the reference
away into a D data structure and then let the thread have its references dropped in MiniD.
This is really meant for access to threads so that you can call thread functions on them.
*/
MDThread* getThread(MDThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != MDValue.Type.Thread)
	{
		pushTypeString(t, slot);
		throwException(t, __FUNCTION__ ~ " - expected 'thread' but got '{}'", getString(t, -1));
	}

	return v.mThread;
}

/**
Returns the native D object at the given _slot, or throws an error if it isn'_t one.
*/
Object getNativeObj(MDThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != MDValue.Type.NativeObj)
	{
		pushTypeString(t, slot);
		throwException(t, __FUNCTION__ ~ " - expected 'nativeobj' but got '{}'", getString(t, -1));
	}

	return v.mNativeObj.obj;
}

// ================================================================================================================================================
// Statements

/**
An odd sort of protective function.  You can use this function to wrap a call to a library function etc. which
could throw an exception, but when you don't want to have to bother with catching the exception yourself.  Useful
for writing native MiniD libraries.

Say you had a function which opened a file:

-----
File f = OpenFile("filename");
-----

Say this function could throw an exception if it failed.  Since the interpreter can only catch (and make meaningful
stack traces about) exceptions which derive from MDException, any exceptions that this throws would just percolate
up out of the interpreter stack.  You could catch the exception yourself, but that's kind of tedious, especially when
you call a lot of native functions.

Instead, you can wrap the call to this unsafe function with a call to safeCode().

-----
File f = safeCode(t, OpenFile("filename"));
-----

What safeCode() does is it tries to execute the code it is passed.  If it succeeds, it simply returns any value that
the code returns.  If it throws an exception derived from MDException, it rethrows the exception.  And if it throws
an exception that derives from Exception, it throws a new MDException with the original exception's message as the
message.

If you want to wrap statements, you can use a delegate literal:

-----
safeCode(t,
{
	stmt1;
	stmt2;
	stmt3;
}());
-----

Be sure to include those empty parens after the delegate literal, due to the way D converts the expression to a lazy
parameter.  If you don't put the parens there, it will never actually call the delegate.

safeCode() is templated to allow any return value.

Params:
	code = The code to be executed.  This is a lazy parameter, so it's not actually executed until inside the call to
		safeCode.

Returns:
	Whatever the code parameter returns.
*/
T safeCode(T)(MDThread* t, lazy T code)
{
	try
		return code;
	catch(MDException e)
		throw e;
	catch(Exception e)
		throwException(t, "{}", e);

	assert(false);
}

/**
This structure is meant to be used as a helper to perform a MiniD-style foreach loop.
It preserves the semantics of the MiniD foreach loop and handles the foreach/opApply protocol
manipulations.

To use this, first you push the container -- what you would normally put on the right side
of the semicolon in a foreach loop in MiniD.  Just like in MiniD, this is one, two, or three
values, and if the first value is not a function, opApply is called on it with the second
value as a user parameter.

Then you can create an instance of this struct using the static opCall and iterate over it
with a D foreach loop.  Instead of getting values as the loop indices, you get indices of
stack slots that hold those values.  You can break out of the loop just as you'd expect,
and you can perform any manipulations you'd like in the loop body.

Example:
-----
// 1. Push the container.  We're just iterating through modules.customLoaders.
lookup(t, "modules.customLoaders");

// 2. Perform a foreach loop on a foreachLoop instance created with the thread and the number
// of items in the container.  We only pushed one value for the container, so we pass 1.
// Note that you must specify the index types (which must all be word), or else D can't infer
// the types for them.

foreach(word k, word v; foreachLoop(t, 1))
{
	// 3. Do whatever you want with k and v.
	pushToString(t, k);
	pushToString(t, v);
	Stdout.formatln("{}: {}", getString(t, -2), getString(t, -1));

	// here we're popping the strings we pushed.  You don't have to pop k and v or anything like that.
	pop(t, 2);
}
-----

Note a few things: the foreach loop will pop the container off the stack, so the above code is
stack-neutral (leaves the stack in the same state it was before it was run).  You don't have to
pop anything inside the foreach loop.  You shouldn't mess with stack values below k and v, since
foreachLoop keeps internal loop data there, but stack indices that were valid before the loop started
will still be accessible.  If you use only one index (like foreach(word v; ...)), it will work just
like in MiniD where an implicit index will be inserted before that one, and you will get the second
indices in v instead of the first.
*/
struct foreachLoop
{
	MDThread* t;
	uword numSlots;

	/**
	The struct constructor.

	Params:
		numSlots = How many slots on top of the stack should be interpreted as the container.  Must be
			1, 2, or 3.
	*/
	public static foreachLoop opCall(MDThread* t, uword numSlots)
	{
		foreachLoop ret = void;
		ret.t = t;
		ret.numSlots = numSlots;
		return ret;
	}

	/**
	The function that makes everything work.  This is templated to allow any number of indices, but
	the downside to that is that you must specify the types of the indices in the foreach loop that
	iterates over this structure.  All the indices must be of type 'word'.
	*/
	public int opApply(T)(T dg)
	{
		alias Unique!(ParameterTupleOf!(T)) TypeTest;
		static assert(TypeTest.length == 1 && is(TypeTest[0] == word), "foreachLoop - all indices must be of type 'word'");
		alias ParameterTupleOf!(T) Indices;

		static if(Indices.length == 1)
		{
			const numIndices = 2;
			const numParams = 1;
		}
		else
		{
			const numIndices = Indices.length;
			const numParams = Indices.length;
		}

		if(numSlots < 1 || numSlots > 3)
			throwException(t, "foreachLoop - numSlots may only be 1, 2, or 3, not {}", numSlots);

		mixin(checkNumParams!("numSlots"));

		// Make sure we have 3 stack slots for our temp data area
		if(numSlots < 3)
			setStackSize(t, stackSize(t) + (3 - numSlots));

		// ..and make sure to clean up
		scope(success)
			pop(t, 3);

		// Get opApply, if necessary
		auto src = absIndex(t, -3);

		if(!isFunction(t, src) && !isThread(t, src))
		{
			auto srcObj = &t.stack[t.stackIndex - 3];

			MDClass* proto;
			auto method = getMM(t, srcObj, MM.Apply, proto);

			if(method is null)
			{
				typeString(t, srcObj);
				throwException(t, "No implementation of {} for type '{}'", MetaNames[MM.Apply], getString(t, -1));
			}

			pushFunction(t, method);
			insert(t, -4);
			pop(t);
			auto reg = absIndex(t, -3);
			commonCall(t, reg + t.stackBase, 3, callPrologue(t, reg + t.stackBase, 3, 2, proto));

			if(!isFunction(t, src) && !isThread(t, src))
			{
				pushTypeString(t, src);
				throwException(t, "Invalid iterable type '{}' returned from opApply", getString(t, -1));
			}
		}

		if(isThread(t, src) && state(getThread(t, src)) != MDThread.State.Initial)
			throwException(t, "Attempting to iterate over a thread that is not in the 'initial' state");

		// Set up the indices tuple
		Indices idx;

		static if(Indices.length == 1)
			idx[0] = stackSize(t) + 1;
		else
		{
			foreach(i, T; Indices)
				idx[i] = stackSize(t) + i;
		}

		// Do the loop
		while(true)
		{
			auto funcReg = dup(t, src);
			dup(t, src + 1);
			dup(t, src + 2);
			rawCall(t, funcReg, numIndices);

			if(isFunction(t, src))
			{
				if(isNull(t, funcReg))
				{
					pop(t, numIndices);
					break;
				}
			}
			else
			{
				if(state(getThread(t, src)) == MDThread.State.Dead)
				{
					pop(t, numIndices);
					break;
				}
			}

			dup(t, funcReg);
			swap(t, src + 2);
			pop(t);

			auto ret = dg(idx);
			pop(t, numIndices);

			if(ret)
				return ret;
		}

		return 0;
	}
}

// ================================================================================================================================================
// Exception-related functions

/**
Throws a MiniD exception using the value at the top of the stack as the exception object.  Any type can
be thrown.  This will throw an actual D exception of type MDException as well, which can be caught in D
as normal ($(B Important:) see catchException for information on catching them).

You cannot use this function if another exception is still in flight, that is, it has not yet been caught with
catchException.  If you try, an Exception will be thrown -- that is, an instance of the D Exception class.

This function obviously does not return.
*/
void throwException(MDThread* t)
{
	mixin(checkNumParams!("1"));
	throwImpl(t, &t.stack[t.stackIndex - 1]);
}

/**
A shortcut for the very common case where you want to throw a formatted string.  This is equivalent to calling
pushVFormat on the arguments and then calling throwException.
*/
void throwException(MDThread* t, char[] fmt, ...)
{
	pushVFormat(t, fmt, _arguments, _argptr);
	throwException(t);
}

/**
When catching MiniD exceptions (those derived from MDException) in D, MiniD doesn'_t know that you've actually caught
one unless you tell it.  If you want to rethrow an exception without seeing what's in it, you can just throw the
D exception object.  But if you want to actually handle the exception, or rethrow it after seeing what's in it,
you $(B must call this function).  This informs MiniD that you have caught the exception that was in flight, and
pushes the exception object onto the stack, where you can inspect it and possibly rethrow it using throwException.

Note that if an exception occurred and you caught it, you might not know anything about what's on the stack.  It
might be garbage from a half-completed operation.  So you might want to store the size of the stack before a 'try'
block, then restore it in the 'catch' block so that the stack will be in a consistent state.

An exception must be in flight for this function to work.  If none is in flight, a MiniD exception is thrown. (For
some reason, that sounds funny.  "Error: there is no error!")

Returns:
	The stack index of the newly-pushed exception object.
*/
word catchException(MDThread* t)
{
	mixin(FuncNameMix);

	if(!t.vm.isThrowing)
		throwException(t, __FUNCTION__ ~ " - Attempting to catch an exception when none is in flight");

	auto ret = push(t, t.vm.exception);
	t.vm.exception = MDValue.nullValue;
	t.vm.isThrowing = false;
	return ret;
}

/**
After catching an exception, you can get a traceback, which is the sequence of functions that the exception was
thrown through before being caught.  Tracebacks work across coroutine boundaries.  They also work across tailcalls,
and it will be noted when this happens (in the traceback you'll see something like "<4 tailcalls>(?)" to indicate
that 4 tailcalls were performed between the previous function and the next function in the traceback).  Lastly tracebacks
work across native function calls, in which case the name of the function will be noted but no line number will be
given since that would be impossible; instead it is marked as "(native)".

When you call this function, it will push a string representing the traceback onto the given thread's stack, in this
sort of form:

-----
Traceback; function.that.threw.exception(9)
        at function.that.called.it(23)
        at <5 tailcalls>(?)
        at some.native.function(native)
-----

(Due to a DDoc bug, it's actually "Traceback:", not "Traceback;".)

Sometimes you'll get something like "$(LT)no location available$(GT)" in the traceback.  This might happen if some top-level
native API manipulations (that is, those outside the context of any executing function) cause an error.

When you call this function, the traceback information associated with this thread's VM is subsequently erased.  If
this function is called again, you will get an empty string.

Returns:
	The stack index of the newly-pushed traceback string.
*/
word getTraceback(MDThread* t)
{
	if(t.vm.traceback.length == 0)
		return pushString(t, "");

	pushString(t, "Traceback: ");
	pushDebugLocStr(t, t.vm.traceback[0]);

	foreach(ref l; t.vm.traceback[1 .. $])
	{
		pushString(t, "\n        at ");
		pushDebugLocStr(t, l);
	}

	auto ret = cat(t, t.vm.traceback.length * 2);
	t.vm.alloc.resizeArray(t.vm.traceback, 0);
	return ret;
}

// ================================================================================================================================================
// Variable-related functions

/**
Sets an upvalue in the currently-executing closure.  The upvalue is set to the value on top of the
stack, which is popped.

This function will fail if called at top-level (that is, outside of any executing closures).

Params:
	idx = The index of the upvalue to set.
*/
void setUpval(MDThread* t, uword idx)
{
	mixin(FuncNameMix);

	if(t.arIndex == 0)
		throwException(t, __FUNCTION__ ~ " - No function to set upvalue (can't call this function at top level)");

	mixin(checkNumParams!("1"));

	auto upvals = t.currentAR.func.nativeUpvals();

	if(idx >= upvals.length)
		throwException(t, __FUNCTION__ ~ " - Invalid upvalue index ({}, only have {})", idx, upvals.length);

	upvals[idx] = *getValue(t, -1);
	pop(t);
}

/**
Pushes an upvalue from the currently-executing closure.

This function will fail if called at top-level (that is, outside of any executing closures).

Params:
	idx = The index of the upvalue to set.

Returns:
	The stack index of the newly-pushed value.
*/
word getUpval(MDThread* t, uword idx)
{
	mixin(FuncNameMix);

	if(t.arIndex == 0)
		throwException(t, __FUNCTION__ ~ " - No function to get upvalue (can't call this function at top level)");

	assert(t.currentAR.func.isNative, "getUpval used on a non-native func");

	auto upvals = t.currentAR.func.nativeUpvals();

	if(idx >= upvals.length)
		throwException(t, __FUNCTION__ ~ " - Invalid upvalue index ({}, only have {})", idx, upvals.length);

	return push(t, upvals[idx]);
}

/**
Pushes the string representation of the type of the value at the given _slot.

Returns:
	The stack index of the newly-pushed string.
*/
word pushTypeString(MDThread* t, word slot)
{
	return typeString(t, getValue(t, slot));
}

/**
Pushes the environment of a closure on the call stack.

Note that if tailcalls have occurred, environments of certain functions will be unavailable, and attempting
to get them will throw an error.

If the _depth you specify if deeper than the call stack, or if there are no functions on the call stack,
the global namespace will be pushed.

Params:
	depth = The _depth into the call stack of the closure whose environment to get.  Defaults to 0, which
		means the currently-executing closure.  A _depth of 1 would mean the closure which called this
		closure, 2 the closure that called that one etc.

Returns:
	The stack index of the newly-pushed environment.
*/
word pushEnvironment(MDThread* t, uword depth = 0)
{
	return pushNamespace(t, getEnv(t, depth));
}

/**
Pushes a global variable with the given name.  Throws an error if the global cannot be found.

This function respects typical global lookup - that is, it starts at the current
function's environment and goes up the chain.

Params:
	name = The _name of the global to get.

Returns:
	The index of the newly-pushed value.
*/
word pushGlobal(MDThread* t, char[] name)
{
	pushString(t, name);
	return getGlobal(t);
}

/**
Same as pushGlobal, except expects the name of the global to be on top of the stack.  If the value
at the top of the stack is not a string, an error is thrown.  Replaces the name with the value of the
global if found.

Returns:
	The index of the retrieved value (the stack top).
*/
word getGlobal(MDThread* t)
{
	mixin(checkNumParams!("1"));

	auto v = getValue(t, -1);

	if(!v.type == MDValue.Type.String)
	{
		pushTypeString(t, -1);
		throwException(t, __FUNCTION__ ~ " - Global name must be a string, not a '{}'", getString(t, -1));
	}

	auto g = lookupGlobal(v.mString, getEnv(t));

	if(g is null)
		throwException(t, __FUNCTION__ ~ " - Attempting to get a nonexistent global '{}'", v.mString.toString());

	*v = *g;
	return stackSize(t) - 1;
}

/**
Sets a global variable with the given _name to the value on top of the stack, and pops that value.
Throws an error if the global cannot be found.  Remember that if this is the first time you are
trying to set the global, you have to use newGlobal instead, just like using a global declaration
in MiniD.

This function respects typical global lookup - that is, it starts at the current function's
environment and goes up the chain.

Params:
	name = The _name of the global to set.
*/
void setGlobal(MDThread* t, char[] name)
{
	mixin(checkNumParams!("1"));
	pushString(t, name);
	swap(t);
	setGlobal(t);
}

/**
Same as above, but expects the name of the global to be on the stack just below the value to set.
Pops both the name and the value.
*/
void setGlobal(MDThread* t)
{
	mixin(checkNumParams!("2"));

	auto n = getValue(t, -2);

	if(n.type != MDValue.Type.String)
	{
		pushTypeString(t, -2);
		throwException(t, __FUNCTION__ ~ " - Global name must be a string, not a '{}'", getString(t, -1));
	}

	auto g = lookupGlobal(n.mString, getEnv(t));

	if(g is null)
		throwException(t, __FUNCTION__ ~ " - Attempting to set a nonexistent global '{}'", n.mString.toString());

	*g = t.stack[t.stackIndex - 1];
	pop(t, 2);
}

/**
Declares a global variable with the given _name, sets it to the value on top of the stack, and pops
that value.  Throws an error if the global has already been declared.

This function works just like a global variable declaration in MiniD.  It creates a new entry
in the current environment if it succeeds.

Params:
	name = The _name of the global to set.
*/
void newGlobal(MDThread* t, char[] name)
{
	mixin(checkNumParams!("1"));
	pushString(t, name);
	swap(t);
	newGlobal(t);
}

/**
Same as above, but expects the name of the global to be on the stack under the value to be set.  Pops
both the name and the value off the stack.
*/
void newGlobal(MDThread* t)
{
	mixin(checkNumParams!("2"));

	auto n = getValue(t, -2);

	if(n.type != MDValue.Type.String)
	{
		pushTypeString(t, -2);
		throwException(t, __FUNCTION__ ~ " - Global name must be a string, not a '{}'", getString(t, -1));
	}

	auto env = getEnv(t);

	if(namespace.contains(env, n.mString))
		throwException(t, __FUNCTION__ ~ " - Attempting to declare a global '{}' that already exists", n.mString.toString());

	namespace.set(t.vm.alloc, env, n.mString, &t.stack[t.stackIndex - 1]);
	pop(t, 2);
}

/**
Searches for a global of the given _name.

By default, this follows normal global lookup, starting with the currently-executing function's environment,
but you can change where the lookup starts by using the depth parameter.

Params:
	name = The _name of the global to look for.
	depth = The _depth into the call stack of the closure in whose environment lookup should begin.  Defaults
		to 0, which means the currently-executing closure.  A _depth of 1 would mean the closure which called
		this closure, 2 the closure that called that one etc.

Returns:
	true if the global was found, in which case the containing namespace is on the stack.  False otherwise,
	in which case nothing will be on the stack.
*/
bool findGlobal(MDThread* t, char[] name, uword depth = 0)
{
	auto n = createString(t, name);
	auto ns = getEnv(t, depth);

	if(namespace.get(ns, n) !is null)
	{
		pushNamespace(t, ns);
		return true;
	}
	
	for(; ns.parent !is null; ns = ns.parent) {}

	if(namespace.get(ns, n) !is null)
	{
		pushNamespace(t, ns);
		return true;
	}

	return false;
}

// ================================================================================================================================================
// Table-related functions

/**
Removes all items from the given table object.

Params:
	tab = The stack index of the table object to clear.
*/
void clearTable(MDThread* t, word tab)
{
	mixin(FuncNameMix);

	auto tb = getTable(t, tab);

	if(tb is null)
	{
		pushTypeString(t, tab);
		throwException(t, __FUNCTION__ ~ " - tab must be a table, not a '{}'", getString(t, -1));
	}

	table.clear(t.vm.alloc, tb);
}

// ================================================================================================================================================
// Array-related functions

/**
Fills the array at the given index with the value at the top of the stack and pops that value.

Params:
	arr = The stack index of the array object to fill.
*/
void fillArray(MDThread* t, word arr)
{
	mixin(checkNumParams!("1"));
	auto a = getArray(t, arr);

	if(a is null)
	{
		pushTypeString(t, arr);
		throwException(t, __FUNCTION__ ~ " - arr must be an array, not a '{}'", getString(t, -1));
	}

	a.slice[] = t.stack[t.stackIndex - 1];
	pop(t);
}

// ================================================================================================================================================
// Function-related functions

/**
Pushes the environment namespace of a function closure.

Params:
	func = The stack index of the function whose environment is to be retrieved.

Returns:
	The stack index of the newly-pushed environment namespace.
*/
word getFuncEnv(MDThread* t, word func)
{
	mixin(FuncNameMix);

	if(auto f = getFunction(t, func))
		return pushNamespace(t, f.environment);

	pushTypeString(t, func);
	throwException(t, __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));

	assert(false);
}

/**
Sets the namespace at the top of the stack as the environment namespace of a function closure and pops
that namespace off the stack.

Params:
	func = The stack index of the function whose environment is to be set.
*/
void setFuncEnv(MDThread* t, word func)
{
	mixin(checkNumParams!("1"));

	auto ns = getNamespace(t, -1);

	if(ns is null)
	{
		pushTypeString(t, -1);
		throwException(t, __FUNCTION__ ~ " - Expected 'namespace' for environment, not '{}'", getString(t, -1));
	}

	auto f = getFunction(t, func);

	if(f is null)
	{
		pushTypeString(t, -1);
		throwException(t, __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));
	}

	f.environment = ns;
	pop(t);
}

/**
Gets the name of the function at the given stack index.  This is the name given in the declaration
of the function if it's a script function, or the name given to newFunction for native functions.
Some functions, like top-level module functions and nameless function literals, have automatically-
generated names which always start and end with angle brackets ($(LT) and $(GT)).
*/
char[] funcName(MDThread* t, word func)
{
	mixin(FuncNameMix);

	if(auto f = getFunction(t, func))
		return f.name.toString();

	pushTypeString(t, func);
	throwException(t, __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));

	assert(false);
}

/**
Gets the number of parameters that the function at the given stack index takes.  This is the number
of non-variadic arguments, not including 'this'.  For native functions, always returns 0.
*/
uword funcNumParams(MDThread* t, word func)
{
	mixin(FuncNameMix);

	if(auto f = getFunction(t, func))
		return .func.numParams(f);

	pushTypeString(t, func);
	throwException(t, __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));

	assert(false);
}

/**
Gets whether or not the given function takes variadic arguments.  For native functions, always returns
true.
*/
bool funcIsVararg(MDThread* t, word func)
{
	mixin(FuncNameMix);

	if(auto f = getFunction(t, func))
		return .func.isVararg(f);

	pushTypeString(t, func);
	throwException(t, __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));

	assert(false);
}

/**
Gets whether or not the given function is a native function.
*/
bool funcIsNative(MDThread* t, word func)
{
	mixin(FuncNameMix);

	if(auto f = getFunction(t, func))
		return .func.isNative(f);

	pushTypeString(t, func);
	throwException(t, __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));

	assert(false);
}

// ================================================================================================================================================
// Class-related functions

/**
Sets the finalizer function for the given class.  The finalizer of a class is called when an instance of that class
is about to be collected by the garbage collector and is used to clean up limited resources associated with it
(i.e. memory allocated on the C heap, file handles, etc.).  The finalizer function should be short and to-the-point
as to make finalization as quick as possible.  It should also not allocate very much memory, if any, as the
garbage collector is effectively disabled during execution of finalizers.  The finalizer function will only
ever be called once for each instance.  If the finalizer function causes the instance to be "resurrected", that is
the instance is reattached to the application's memory graph, it will still eventually be collected but its finalizer
function will $(B not) be run again.

Instances get the finalizer from the class that they are an instance of.  If you instantiate a class, and then
change its finalizer, the instances that were already created will use the old finalizer.

This function expects the finalizer function to be on the top of the stack.  If you want to remove the finalizer
function from a class, the value at the top of the stack can be null.

Params:
	cls = The class whose finalizer is to be set.
*/
void setFinalizer(MDThread* t, word cls)
{
	mixin(checkNumParams!("1"));

	if(!(isNull(t, -1) || isFunction(t, -1)))
	{
		pushTypeString(t, -1);
		throwException(t, __FUNCTION__ ~ " - Expected 'function' or 'null' for finalizer, not '{}'", getString(t, -1));
	}

	auto c = getClass(t, cls);

	if(c is null)
	{
		pushTypeString(t, cls);
		throwException(t, __FUNCTION__ ~ " - Expected 'class', not '{}'", getString(t, -1));
	}

	if(isNull(t, -1))
		c.finalizer = null;
	else
		c.finalizer = getFunction(t, -1);

	pop(t);
}

/**
Pushes the finalizer function associated with the given class, or null if no finalizer is set for
that class.

Params:
	cls = The class whose finalizer is to be retrieved.

Returns:
	The stack index of the newly-pushed finalizer function (or null if the class has none).
*/
word getFinalizer(MDThread* t, word cls)
{
	mixin(FuncNameMix);

	if(auto c = getClass(t, cls))
	{
		if(c.finalizer)
			return pushFunction(t, c.finalizer);
		else
			return pushNull(t);
	}

	pushTypeString(t, cls);
	throwException(t, __FUNCTION__ ~ " - Expected 'class', not '{}'", getString(t, -1));

	assert(false);
}

/**
Normally when you instantiate a MiniD class, by doing something like "A(5)" (or similarly, by
calling it as if it were a function using the native API), the following happens: the interpreter
calls newInstance on the class to allocate a new instance, then calls any constructor defined for
the class on the new instance with the given parameters, and finally it returns that new instance.

You can override this behavior using class allocators.  A class allocator takes any number of
parameters and must return a class instance.  The 'this' parameter passed to a class allocator is
the class which is being instantiated.  Class allocators reserve the right to call or not
call any constructor defined for the class.  In fact, they can do just about anything as long as
they return an instance.

Here is an example class allocator which performs the default behavior.

-----
uword allocator(MDThread* t, uword numParams)
{
	// new instance of the class held in 'this'
	newInstance(t, 0);

	// duplicate it so it can be used as a return value
	dup(t);

	// push a null for the 'this' slot of the impending method call
	pushNull(t);

	// rotate the stack so that we have
	// [inst] [inst] [null] [params...]
	rotateAll(t, 3);

	// call the constructor on the instance, ignoring any returns
	methodCall(t, 2, "constructor", 0);

	// now all that's left on the stack is the instance; return it
	return 1;
}
-----

Why would a class use an allocator?  Simple: if it needs to allocate extra values or bytes for
its instances.  Most of the native objects defined in the standard libraries use allocators to
do just this.

You can also imagine a case where the number of extra values or bytes is dependent upon the
parameters passed to the constructor, which is why class allocators get all the parameters.

This function expects the new class allocator to be on top of the stack.  It should be a function,
or null if you want to remove the given class's allocator.

Params:
	cls = The stack index of the class object whose allocator is to be set.
*/
void setAllocator(MDThread* t, word cls)
{
	mixin(checkNumParams!("1"));

	if(!(isNull(t, -1) || isFunction(t, -1)))
	{
		pushTypeString(t, -1);
		throwException(t, __FUNCTION__ ~ " - Expected 'function' or 'null' for finalizer, not '{}'", getString(t, -1));
	}

	auto c = getClass(t, cls);

	if(c is null)
	{
		pushTypeString(t, cls);
		throwException(t, __FUNCTION__ ~ " - Expected 'class', not '{}'", getString(t, -1));
	}

	if(isNull(t, -1))
		c.allocator = null;
	else
		c.allocator = getFunction(t, -1);

	pop(t);
}

/**
Pushes the allocator associated with the given class, or null if no allocator is set for
that class.

Params:
	cls = The class whose allocator is to be retrieved.

Returns:
	The stack index of the newly-pushed allocator function (or null if the class has none).
*/
word getAllocator(MDThread* t, word cls)
{
	mixin(FuncNameMix);

	if(auto c = getClass(t, cls))
	{
		if(c.allocator)
			return pushFunction(t, c.allocator);
		else
			return pushNull(t);
	}

	pushTypeString(t, cls);
	throwException(t, __FUNCTION__ ~ " - Expected 'class', not '{}'", getString(t, -1));

	assert(false);
}

/**
Gets the name of the class at the given stack index.
*/
char[] className(MDThread* t, word cls)
{
	mixin(FuncNameMix);

	if(auto c = getClass(t, cls))
		return c.name.toString();

	pushTypeString(t, cls);
	throwException(t, __FUNCTION__ ~ " - Expected 'class', not '{}'", getString(t, -1));

	assert(false);
}

// ================================================================================================================================================
// Instance-related functions

/**
Finds out how many extra values an instance has (see newInstance for info on that).  Throws an error
if the value at the given _slot isn'_t an instance.

Params:
	slot = The stack index of the instance whose number of values is to be retrieved.

Returns:
	The number of extra values associated with the given instance.
*/
uword numExtraVals(MDThread* t, word slot)
{
	mixin(FuncNameMix);

	if(auto i = getInstance(t, slot))
		return i.numValues;
	else
	{
		pushTypeString(t, slot);
		throwException(t, __FUNCTION__ ~ " - expected 'instance' but got '{}'", getString(t, -1));
	}

	assert(false);
}

/**
Pushes the idx th extra value from the instance at the given _slot.  Throws an error if the value at
the given _slot isn'_t an instance, or if the index is out of bounds.

Params:
	slot = The instance whose value is to be retrieved.
	idx = The index of the extra value to get.

Returns:
	The stack index of the newly-pushed value.
*/
word getExtraVal(MDThread* t, word slot, uword idx)
{
	mixin(FuncNameMix);

	if(auto i = getInstance(t, slot))
	{
		if(idx >= i.numValues)
			throwException(t, __FUNCTION__ ~ " - Value index out of bounds ({}, but only have {})", idx, i.numValues);

		return push(t, i.extraValues()[idx]);
	}
	else
	{
		pushTypeString(t, slot);
		throwException(t, __FUNCTION__ ~ " - expected 'instance' but got '{}'", getString(t, -1));
	}

	assert(false);
}

/**
Pops the value off the top of the stack and places it in the idx th extra value in the instance at the
given _slot.  Throws an error if the value at the given _slot isn'_t an instance, or if the index is out
of bounds.

Params:
	slot = The instance whose value is to be set.
	idx = The index of the extra value to set.
*/
void setExtraVal(MDThread* t, word slot, uword idx)
{
	mixin(checkNumParams!("1"));

	if(auto i = getInstance(t, slot))
	{
		if(idx >= i.numValues)
			throwException(t, __FUNCTION__ ~ " - Value index out of bounds ({}, but only have {})", idx, i.numValues);

		i.extraValues()[idx] = t.stack[t.stackIndex - 1];
		pop(t);
	}
	else
	{
		pushTypeString(t, slot);
		throwException(t, __FUNCTION__ ~ " - expected 'instance' but got '{}'", getString(t, -1));
	}
}

/**
Gets a void array of the extra bytes associated with the instance at the given _slot.  If the instance has
no extra bytes, returns null.  Throws an error if the value at the given _slot isn'_t an instance.

The returned void array points into the MiniD heap, so you should not store the returned reference
anywhere.

Params:
	slot = The instance whose data is to be retrieved.

Returns:
	A void array of the data, or null if the instance has none.
*/
void[] getExtraBytes(MDThread* t, word slot)
{
	mixin(FuncNameMix);

	if(auto i = getInstance(t, slot))
	{
		if(i.extraBytes == 0)
			return null;

		return i.extraData();
	}
	else
	{
		pushTypeString(t, slot);
		throwException(t, __FUNCTION__ ~ " - expected 'instance' but got '{}'", getString(t, -1));
	}

	assert(false);
}

// ================================================================================================================================================
// Namespace-related functions

/**
Removes all items from the given namespace object.

Params:
	ns = The stack index of the namespace object to clear.
*/
void clearNamespace(MDThread* t, word ns)
{
	mixin(FuncNameMix);

	auto n = getNamespace(t, ns);

	if(n is null)
	{
		pushTypeString(t, ns);
		throwException(t, __FUNCTION__ ~ " - ns must be a namespace, not a '{}'", getString(t, -1));
	}

	namespace.clear(t.vm.alloc, n);
}

/**
Removes the key at the top of the stack from the given object.  The key is popped.
The object must be a namespace or table.

Params:
	obj = The stack index of the object from which the key is to be removed.
*/
void removeKey(MDThread* t, word obj)
{
	mixin(checkNumParams!("1"));

	if(auto tab = getTable(t, obj))
	{
		pushTable(t, tab);
		dup(t, -2);
		pushNull(t);
		idxa(t, -3);
		pop(t, 2);
	}
	else if(auto ns = getNamespace(t, obj))
	{
		if(!isString(t, -1))
		{
			pushTypeString(t, -1);
			throwException(t, __FUNCTION__ ~ " - key must be a string, not a '{}'", getString(t, -1));
		}

		if(!opin(t, -1, obj))
		{
			pushToString(t, obj);
			throwException(t, __FUNCTION__ ~ " - key '{}' does not exist in namespace '{}'", getString(t, -2), getString(t, -1));
		}

		namespace.remove(ns, getStringObj(t, -1));
		pop(t);
	}
	else
	{
		pushTypeString(t, obj);
		throwException(t, __FUNCTION__ ~ " - obj must be a namespace or table, not a '{}'", getString(t, -1));
	}
}

/**
Gets the name of the namespace at the given stack index.  This is just the single name component that
it was created with (like "foo" for "namespace foo {}").
*/
char[] namespaceName(MDThread* t, word ns)
{
	mixin(FuncNameMix);

	if(auto n = getNamespace(t, ns))
		return n.name.toString();

	pushTypeString(t, ns);
	throwException(t, __FUNCTION__ ~ " - Expected 'namespace', not '{}'", getString(t, -1));

	assert(false);
}

/**
Pushes the "full" name of the given namespace, which includes all the parent namespace name components,
separated by dots.

Returns:
	The stack index of the newly-pushed name string.
*/
word namespaceFullname(MDThread* t, word ns)
{
	mixin(FuncNameMix);

	if(auto n = getNamespace(t, ns))
		return pushNamespaceNamestring(t, n);

	pushTypeString(t, ns);
	throwException(t, __FUNCTION__ ~ " - Expected 'namespace', not '{}'", getString(t, -1));

	assert(false);
}

// ================================================================================================================================================
// Thread-specific stuff

/**
Gets the current coroutine _state of the thread as a member of the MDThread.State enumeration.
*/
MDThread.State state(MDThread* t)
{
	return t.state;
}

/**
Gets a string representation of the current coroutine state of the thread.

The string returned is not on the MiniD heap, it's just a string literal.
*/
char[] stateString(MDThread* t)
{
	return MDThread.StateStrings[t.state];
}

/**
Gets the VM that the thread is associated with.
*/
MDVM* getVM(MDThread* t)
{
	return t.vm;
}

/**
Find how many calls deep the currently-executing function is nested.  Tailcalls are taken into account.

If called at top-level, returns 0.
*/
uword callDepth(MDThread* t)
{
	uword depth = 0;

	for(uword i = 0; i < t.arIndex; i++)
		depth += t.actRecs[i].numTailcalls + 1;

	return depth;
}

/**
Returns the number of items on the stack.  Valid positive stack indices range from [0 .. _stackSize(t)$(RPAREN).
Valid negative stack indices range from [-_stackSize(t) .. 0$(RPAREN).

Note that 'this' (stack index 0 or -_stackSize(t)) may not be overwritten or changed, although it can be used
with functions that don'_t modify their argument.
*/
uword stackSize(MDThread* t)
{
	assert(t.stackIndex > t.stackBase);
	return t.stackIndex - t.stackBase;
}

/**
Resets a dead thread to the initial state, optionally providing a new function to act as the body of the thread.

Params:
	slot = The stack index of the thread to be reset.  It must be in the 'dead' state.
	newFunction = If true, a function should be on top of the stack which should serve as the new body of the
		coroutine.  The default is false, in which case the coroutine will use the function with which it was
		created.
*/
void resetThread(MDThread* t, word slot, bool newFunction = false)
{
	mixin(FuncNameMix);

	auto other = getThread(t, slot);

	if(other is null)
	{
		pushTypeString(t, slot);
		throwException(t, __FUNCTION__ ~ " - Object at 'slot' must be a 'thread', not a '{}'", getString(t, -1));
	}

	if(state(other) != MDThread.State.Dead)
		throwException(t, __FUNCTION__ ~ " - Attempting to reset a {} coroutine (must be dead)", stateString(other));

	if(newFunction)
	{
		mixin(checkNumParams!("1"));

		auto f = getFunction(t, -1);

		if(f is null)
		{
			pushTypeString(t, -1);
			throwException(t, __FUNCTION__ ~ " - Attempting to reset a coroutine with a '{}' instead of a 'function'", getString(t, -1));
		}

		version(MDExtendedCoro) {} else
		{
			if(f.isNative)
				throwException(t, __FUNCTION__ ~ " - Native functions may not be used as the body of a coroutine");
		}

		other.coroFunc = f;
		pop(t);
	}

	version(MDExtendedCoro)
	{
		if(other.coroFiber)
		{
			assert(other.getFiber().state == Fiber.State.TERM);
			other.getFiber().reset();
		}
	}

	other.state = MDThread.State.Initial;
}

version(MDExtendedCoro)
{
	/**
	Yield out of a coroutine.  This function is not available in normal coroutine mode, only in extended mode.

	You cannot _yield out of a thread that is not currently executing, nor can you _yield out of the main thread of
	a VM.

	This function works very similarly to the call family of functions.  You push the values that you want to _yield
	on the stack, then pass how many you pushed and how many you want back.  It then returns how many values this
	coroutine was resumed with, and that many values will be on the stack.

	Example:
-----
// Let's translate `x = yield(5, "hi")` into API calls.

// 1. Push the values to be yielded.
pushInt(t, 5);
pushString(t, "hi");

// 2. Yield from the coroutine, telling that we are yielding 2 values and want 1 in return.
yield(t, 2, 1);

// 3. Do something with the return value.  setGlobal pops the return value off the stack, so now the
// stack is back the way it was when we started.
setGlobal(t, "x");
-----

	Params:
		numVals = The number of values that you are yielding.  These values should be on top of the stack, in order.
		numReturns = The number of return values you are expecting, or -1 for as many returns as you can get.

	Returns:
		How many values were returned.  If numReturns was >= 0, this is the same as numReturns.
	*/
	uword yield(MDThread* t, uword numVals, word numReturns)
	{
		mixin(checkNumParams!("numVals"));

		if(t is t.vm.mainThread)
			throwException(t, __FUNCTION__ ~ " - Attempting to yield out of the main thread");

		if(Fiber.getThis() !is t.getFiber())
			throwException(t, __FUNCTION__ ~ " - Attempting to yield the wrong thread");

		if(numReturns < -1)
			throwException(t, __FUNCTION__ ~ " - invalid number of returns (must be >= -1)");

		auto slot = t.stackIndex - numVals;

		yieldImpl(t, slot, numReturns, numVals);

		if(numReturns == -1)
			return t.stackIndex - slot;
		else
		{
			t.stackIndex = slot + numReturns;
			return numReturns;
		}
	}
}

/**
Halts the given thread.  If the given thread is currently running, throws a halt exception immediately;
otherwise, places a pending halt on the thread.
*/
void haltThread(MDThread* t)
{
	if(state(t) == MDThread.State.Running)
		throw new MDHaltException();
	else
		pendingHalt(t);
}

/**
Places a pending halt on the thread.  This does nothing if the thread is in the 'dead' state.
*/
void pendingHalt(MDThread* t)
{
	if(state(t) != MDThread.State.Dead && t.arIndex > 0)
		t.shouldHalt = true;
}

/**
Sees if the given thread has a pending halt.
*/
bool hasPendingHalt(MDThread* t)
{
	return t.shouldHalt;
}

// ================================================================================================================================================
// Weakref-related functions

/**
Works like the deref() function in the base library.  If the value at the given index is a
value type, just duplicates that value.  If the value at the given index is a weak reference,
pushes the object it refers to or 'null' if that object has been collected.  Throws an error
if the value at the given index is any other type.  This is meant to be an inverse to pushWeakRef,
hence the behavior with regards to value types.

Params:
	idx = The stack index of the object to dereference.

Returns:
	The stack index of the newly-pushed value.
*/
word deref(MDThread* t, word idx)
{
	mixin(FuncNameMix);

	switch(type(t, idx))
	{
		case
			MDValue.Type.Null,
			MDValue.Type.Bool,
			MDValue.Type.Int,
			MDValue.Type.Float,
			MDValue.Type.Char:

			return dup(t, idx);
			
		case MDValue.Type.WeakRef:
			if(auto o = getValue(t, idx).mWeakRef.obj)
				return push(t, MDValue(o));
			else
				return pushNull(t);
				
		default:
			pushTypeString(t, idx);
			throwException(t, __FUNCTION__ ~ " - idx must be a value type or weakref, not a '{}'", getString(t, -1));
	}

	assert(false);
}

// ================================================================================================================================================
// Atomic MiniD operations

/**
Push a string representation of any MiniD value onto the stack.

Params:
	slot = The stack index of the value to convert to a string.
	raw = If true, will not call toString metamethods.  Defaults to false, which means toString
		metamethods will be called.

Returns:
	The stack index of the newly-pushed string.
*/
word pushToString(MDThread* t, word slot, bool raw = false)
{
	// Dereferencing so that we don'_t potentially push an invalid stack object.
	auto v = *getValue(t, slot);
	return toStringImpl(t, v, raw);
}

/**
See if item is in container.  Works like the MiniD 'in' operator.  Calls opIn metamethods.

Params:
	item = The _item to look for (the lhs of 'in').
	container = The _object in which to look (the rhs of 'in').

Returns:
	true if item is in container, false otherwise.
*/
bool opin(MDThread* t, word item, word container)
{
	return inImpl(t, getValue(t, item), getValue(t, container));
}

/**
Compare two values at the given indices, and give the comparison value (negative for a < b, positive for a > b,
and 0 if a == b).  This is the exact behavior of the '<=>' operator in MiniD.  Calls opCmp metamethods.

Params:
	a = The index of the first object.
	b = The index of the second object.

Returns:
	The comparison value.
*/
mdint cmp(MDThread* t, word a, word b)
{
	return compareImpl(t, getValue(t, a), getValue(t, b));
}

/**
Test two values at the given indices for equality.  This is the exact behavior of the '==' operator in MiniD.
Calls opEquals metamethods.

Params:
	a = The index of the first object.
	b = The index of the second object.

Returns:
	true if equal, false otherwise.
*/
bool equals(MDThread* t, word a, word b)
{
	return equalsImpl(t, getValue(t, a), getValue(t, b));
}

/**
Test two values at the given indices for identity.  This is the exact behavior of the 'is' operator in MiniD.

Params:
	a = The index of the first object.
	b = The index of the second object.

Returns:
	true if identical, false otherwise.
*/
bool opis(MDThread* t, word a, word b)
{
	return cast(bool)getValue(t, a).opEquals(*getValue(t, b));
}

/**
Index the _container at the given index with the value at the top of the stack.  Replaces the value on the
stack with the result.  Calls opIndex metamethods.

-----
// x = a[6]
auto cont = pushGlobal(t, "a");
pushInt(t, 6);
idx(t, cont);
setGlobal(t, "x");
pop(t);
// The stack is how it was when we started.
-----

Params:
	container = The stack index of the _container object.
	raw = If true, no opIndex metamethods will be called.  Defaults to false.

Returns:
	The stack index that contains the result (the top of the stack).
*/
word idx(MDThread* t, word container, bool raw = false)
{
	mixin(checkNumParams!("1"));
	auto slot = t.stackIndex - 1;
	idxImpl(t, &t.stack[slot], getValue(t, container), &t.stack[slot], raw);
	return stackSize(t) - 1;
}

/**
Index-assign the _container at the given index with the key at the second-from-top of the stack and the
value at the top of the stack.  Pops both the key and the value from the stack.  Calls opIndexAssign
metamethods.

-----
// a[6] = 10
auto cont = pushGlobal(t, "a");
pushInt(t, 6);
pushInt(t, 10);
idxa(t, cont);
pop(t);
// The stack is how it was when we started.
-----

Params:
	container = The stack index of the _container object.
	raw = If true, no opIndex metamethods will be called.  Defaults to false.
*/
void idxa(MDThread* t, word container, bool raw = false)
{
	mixin(checkNumParams!("2"));
	auto slot = t.stackIndex - 2;
	idxaImpl(t, getValue(t, container), &t.stack[slot], &t.stack[slot + 1], raw);
	pop(t, 2);
}

/**
Shortcut for the common case where you need to index a _container with an integer index.  Pushes
the indexed value.

Params:
	container = The stack index of the _container object.
	idx = The integer index.
	raw = If true, no opIndex metamethods will be called.  Defaults to false.

Returns:
	The stack index of the newly-pushed indexed value.
*/
word idxi(MDThread* t, word container, mdint idx, bool raw = false)
{
	auto c = absIndex(t, container);
	pushInt(t, idx);
	return .idx(t, c, raw);
}

/**
Shortcut for the common case where you need to index-assign a _container with an integer index.  Pops
the value at the top of the stack and assigns it into the _container at the given index.

Params:
	container = The stack index of the _container object.
	idx = The integer index.
	raw = If true, no opIndexAssign metamethods will be called.  Defaults to false.
*/
void idxai(MDThread* t, word container, mdint idx, bool raw = false)
{
	auto c = absIndex(t, container);
	pushInt(t, idx);
	swap(t);
	idxa(t, c, raw);
}

/**
Get a _field with the given _name from the _container at the given index.  Pushes the result onto the stack.

-----
// x = a.y
pushGlobal(t, "a");
field(t, -1, "y");
setGlobal(t, "x");
pop(t);
// The stack is how it was when we started.
-----

Params:
	container = The stack index of the _container object.
	name = The _name of the _field to get.
	raw = If true, does not call opField metamethods.  Defaults to false, which means it will.

Returns:
	The stack index of the newly-pushed result.
*/
word field(MDThread* t, word container, char[] name, bool raw = false)
{
	auto c = fakeToAbs(t, container);
	pushString(t, name);
	return commonField(t, c, raw);
}

/**
Same as above, but expects the _field name to be at the top of the stack.  If the value at the top of the
stack is not a string, an error is thrown.  The _field value replaces the _field name, much like with idx.

Params:
	container = The stack index of the _container object.
	raw = If true, does not call opField metamethods.  Defaults to false, which means it will.

Returns:
	The stack index of the retrieved _field value.
*/
word field(MDThread* t, word container, bool raw = false)
{
	mixin(checkNumParams!("1"));

	if(!isString(t, -1))
	{
		pushTypeString(t, -1);
		throwException(t, __FUNCTION__ ~ " - Field name must be a string, not a '{}'", getString(t, -1));
	}

	return commonField(t, fakeToAbs(t, container), raw);
}

/**
Sets a field with the given _name in the _container at the given index to the value at the top of the stack.
Pops that value off the stack.  Calls opFieldAssign metamethods.

-----
// a.y = x
auto cont = pushGlobal(t, "a");
pushGlobal(t, "x");
fielda(t, cont, "y");
pop(t);
// The stack is how it was when we started.
-----

Params:
	container = The stack index of the _container object.
	name = The _name of the field to set.
	raw = If true, does not call opFieldAssign metamethods.  Defaults to false, which means it will.
*/
void fielda(MDThread* t, word container, char[] name, bool raw = false)
{
	mixin(checkNumParams!("1"));
	auto c = fakeToAbs(t, container);
	pushString(t, name);
	swap(t);
	commonFielda(t, c, raw);
}

/**
Same as above, but expects the field name to be in the second-from-top slot and the value to set at the top of
the stack, similar to idxa.  Throws an error if the field name is not a string.  Pops both the set value and the
field name off the stack, just like idxa.

Params:
	container = The stack index of the _container object.
	raw = If true, does not call opFieldAssign metamethods.  Defaults to false, which means it will.
*/
void fielda(MDThread* t, word container, bool raw = false)
{
	mixin(checkNumParams!("2"));

	if(!isString(t, -2))
	{
		pushTypeString(t, -2);
		throwException(t, __FUNCTION__ ~ " - Field name must be a string, not a '{}'", getString(t, -1));
	}

	commonFielda(t, fakeToAbs(t, container), raw);
}

/**
Pushes the length of the object at the given _slot.  Calls opLength metamethods.

Params:
	slot = The _slot of the object whose length is to be retrieved.

Returns:
	The stack index of the newly-pushed length.
*/
word pushLen(MDThread* t, word slot)
{
	auto o = fakeToAbs(t, slot);
	pushNull(t);
	lenImpl(t, &t.stack[t.stackIndex - 1], &t.stack[o]);
	return stackSize(t) - 1;
}

/**
Gets the integral length of the object at the given _slot.  Calls opLength metamethods.  If the length
of the object is not an integer, throws an error.

Params:
	slot = The _slot of the object whose length is to be retrieved.

Returns:
	The length of the object.
*/
mdint len(MDThread* t, word slot)
{
	mixin(FuncNameMix);

	pushLen(t, slot);

	if(!isInt(t, -1))
	{
		pushTypeString(t, -1);
		throwException(t, __FUNCTION__ ~ " - Expected length to be an int, but got '{}' instead", getString(t, -1));
	}

	auto ret = getInt(t, -1);
	pop(t);
	return ret;
}

/**
Sets the length of the object at the given _slot to the value at the top of the stack and pops that
value.  Calls opLengthAssign metamethods.

Params:
	slot = The _slot of the object whose length is to be set.
*/
void lena(MDThread* t, word slot)
{
	mixin(checkNumParams!("1"));
	auto o = fakeToAbs(t, slot);
	lenaImpl(t, &t.stack[o], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/**
Slice the object at the given slot.  The low index is the second-from-top value on the stack, and
the high index is the top value.  Either index can be null.  The indices are popped and the result
of the _slice operation is pushed.

Params:
	container = The slot of the object to be sliced.
*/
word slice(MDThread* t, word container)
{
	mixin(checkNumParams!("2"));
	auto slot = t.stackIndex - 2;
	sliceImpl(t, &t.stack[slot], getValue(t, container), &t.stack[slot], &t.stack[slot + 1]);
	pop(t);
	return stackSize(t) - 1;
}

/**
Slice-assign the object at the given slot.  The low index is the third-from-top value; the high is
the second-from-top; and the value to assign into the object is on the top.  Either index can be null.
Both indices and the value are popped.

Params:
	container = The slot of the object to be slice-assigned.
*/
void slicea(MDThread* t, word container)
{
	mixin(checkNumParams!("3"));
	auto slot = t.stackIndex - 3;
	sliceaImpl(t, getValue(t, container), &t.stack[slot], &t.stack[slot + 1], &t.stack[slot + 2]);
	pop(t, 3);
}

/**
These all perform the given mathematical operation on the two values at the given indices, and push
the result of that operation onto the stack.  Metamethods (including reverse versions) will be called.

Don'_t use these functions if you're looking to do some serious number crunching on ints and floats.  Just
get the values and do the computation in D.

Params:
	a = The slot of the first value.
	b = The slot of the second value.

Returns:
	The stack index of the newly-pushed result.
*/
word add(MDThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Add, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word sub(MDThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Sub, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word mul(MDThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Mul, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word div(MDThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Div, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word mod(MDThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Mod, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/**
Negates the value at the given index and pushes the result.  Calls opNeg metamethods.

Like the binary operations, don'_t use this unless you need the actual MiniD semantics, as it's
less efficient than just getting a number and negating it.

Params:
	o = The slot of the value to negate.

Returns:
	The stack index of the newly-pushed result.
*/
word neg(MDThread* t, word o)
{
	auto oslot = fakeToAbs(t, o);
	pushNull(t);
	negImpl(t, &t.stack[t.stackIndex - 1], &t.stack[oslot]);
	return stackSize(t) - 1;
}

/**
These all perform the given reflexive mathematical operation on the value at the given slot, using
the value at the top of the stack for the rhs.  The rhs is popped.  These call metamethods.

Like the other mathematical methods, it's more efficient to perform the operation directly on numbers
rather than to use these methods.  Use these only if you need the MiniD semantics.

Params:
	o = The slot of the object to perform the reflexive operation on.
*/
void addeq(MDThread* t, word o)
{
	mixin(checkNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.AddEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void subeq(MDThread* t, word o)
{
	mixin(checkNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.SubEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void muleq(MDThread* t, word o)
{
	mixin(checkNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.MulEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void diveq(MDThread* t, word o)
{
	mixin(checkNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.DivEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void modeq(MDThread* t, word o)
{
	mixin(checkNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.ModEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/**
These all perform the given bitwise operation on the two values at the given indices, _and push
the result of that operation onto the stack.  Metamethods (including reverse versions) will be called.

Don'_t use these functions if you're looking to do some serious number crunching on ints.  Just
get the values _and do the computation in D.

Params:
	a = The slot of the first value.
	b = The slot of the second value.

Returns:
	The stack index of the newly-pushed result.
*/
word and(MDThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.And, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word or(MDThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.Or, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word xor(MDThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.Xor, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word shl(MDThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.Shl, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word shr(MDThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.Shr, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word ushr(MDThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.UShr, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/**
Bitwise complements the value at the given index and pushes the result.  Calls opCom metamethods.

Like the binary operations, don'_t use this unless you need the actual MiniD semantics, as it's
less efficient than just getting a number and complementing it.

Params:
	o = The slot of the value to complement.
	
Returns:
	The stack index of the newly-pushed result.
*/
word com(MDThread* t, word o)
{
	auto oslot = fakeToAbs(t, o);
	pushNull(t);
	comImpl(t, &t.stack[t.stackIndex - 1], &t.stack[oslot]);
	return stackSize(t) - 1;
}

/**
These all perform the given reflexive bitwise operation on the value at the given slot, using
the value at the top of the stack for the rhs.  The rhs is popped.  These call metamethods.

Like the other bitwise methods, it's more efficient to perform the operation directly on numbers
rather than to use these methods.  Use these only if you need the MiniD semantics.

Params:
	o = The slot of the object to perform the reflexive operation on.
*/
void andeq(MDThread* t, word o)
{
	mixin(checkNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.AndEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void oreq(MDThread* t, word o)
{
	mixin(checkNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.OrEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void xoreq(MDThread* t, word o)
{
	mixin(checkNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.XorEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void shleq(MDThread* t, word o)
{
	mixin(checkNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.ShlEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void shreq(MDThread* t, word o)
{
	mixin(checkNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.ShrEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void ushreq(MDThread* t, word o)
{
	mixin(checkNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.UShrEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/**
Concatenates the top num parameters on the stack, popping them all and pushing the result on the stack.

If num is 1, this function does nothing.  If num is 0, it is an error.  Otherwise, the concatenation
works just like it does in MiniD.

-----
// x = "Hi, " ~ name ~ "!"
pushString(t, "Hi ");
pushGlobal(t, "name");
pushString(t, "!");
cat(t, 3);
setGlobal(t, "x");
-----

Params:
	num = How many values to concatenate.

Returns:
	The stack index of the resulting object.
*/
word cat(MDThread* t, uword num)
{
	mixin(FuncNameMix);

	if(num == 0)
		throwException(t, __FUNCTION__ ~ " - Cannot concatenate 0 things");

	mixin(checkNumParams!("num"));

	auto slot = t.stackIndex - num;

	if(num > 1)
	{
		catImpl(t, &t.stack[slot], slot, num);
		pop(t, num - 1);
	}

	return slot;
}

/**
Performs concatenation-assignment.  dest is the stack slot of the destination object (the object to
append to).  num is how many values there are on the right-hand side and is expected to be at least 1.
The RHS values are on the top of the stack.  Pops the RHS values off the stack.

-----
// x ~= "Hi, " ~ name ~ "!"
auto dest = pushGlobal(t, "x");
pushString(t, "Hi ");
pushGlobal(t, "name");
pushString(t, "!");
cateq(t, dest, 3); // 3 rhs values
setGlobal(t, "x"); // have to put the new value back (since it's a string)
-----

Params:
	num = How many values are on the RHS to be appended.
*/
void cateq(MDThread* t, word dest, uword num)
{
	mixin(FuncNameMix);

	if(num == 0)
		throwException(t, __FUNCTION__ ~ " - Cannot append 0 things");

	mixin(checkNumParams!("num"));
	catEqImpl(t, &t.stack[fakeToAbs(t, dest)], t.stackIndex - num, num);
	pop(t, num);
}

/**
Returns whether or not obj is an 'instance' and derives from base.  Throws an error if base is not a class.
Works just like the as operator in MiniD.

Params:
	obj = The stack index of the value to test.
	base = The stack index of the _base class.  Must be a 'class'.

Returns:
	true if obj is an 'instance' and it derives from base.  False otherwise.
*/
bool as(MDThread* t, word obj, word base)
{
	return asImpl(t, getValue(t, obj), getValue(t, base));
}

/**
Increments the value at the given _slot.  Calls opInc metamethods.

Params:
	slot = The stack index of the value to increment.
*/
void inc(MDThread* t, word slot)
{
	incImpl(t, getValue(t, slot));
}

/**
Decrements the value at the given _slot.  Calls opDec metamethods.

Params:
	slot = The stack index of the value to decrement.
*/
void dec(MDThread* t, word slot)
{
	decImpl(t, getValue(t, slot));
}

/**
Gets the class of instances, base class of classes, or the parent namespace of namespaces and
pushes it onto the stack. Throws an error if the value at the given _slot is not a class, instance,
or namespace.  Works just like "x.super" in MiniD.  For classes and namespaces, pushes null if
there is no base or parent.

Params:
	slot = The stack index of the instance, class, or namespace whose class, base, or parent to get.

Returns:
	The stack index of the newly-pushed value.
*/
word superOf(MDThread* t, word slot)
{
	return push(t, superOfImpl(t, getValue(t, slot)));
}

// ================================================================================================================================================
// Function calling

/**
Calls the object at the given _slot.  The parameters (including 'this') are assumed to be all the
values after that _slot to the top of the stack.

The 'this' parameter is, according to the language specification, null if no explicit context is given.
You must still push this null value, however.

An example of calling a function:

-----
// Let's translate `x = f(5, "hi")` into API calls.

// 1. Push the function (or any callable object -- like instances, threads).
auto slot = pushGlobal(t, "f");

// 2. Push the 'this' parameter.  This is 'null' if you don'_t care.  Notice in the MiniD code, we didn'_t
// put a 'with', so 'null' will be used as the context.
pushNull(t);

// 3. Push any params.
pushInt(t, 5);
pushString(t, "hi");

// 4. Call it.
rawCall(t, slot, 1);

// 5. Do something with the return values.  setGlobal pops the return value off the stack, so now the
// stack is back the way it was when we started.
setGlobal(t, "x");
-----

Params:
	slot = The _slot containing the object to call.
	numReturns = How many return values you want.  Can be -1, which means you'll get all returns.

Returns:
	The number of return values given by the function.  If numReturns was -1, this is exactly how
	many returns the function gave.  If numReturns was >= 0, this is the same as numReturns (and
	not exactly useful since you already know it).
*/
uword rawCall(MDThread* t, word slot, word numReturns)
{
	mixin(FuncNameMix);

	auto absSlot = fakeToAbs(t, slot);
	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwException(t, __FUNCTION__ ~ " - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwException(t, __FUNCTION__ ~ " - invalid number of returns (must be >= -1)");

	return commonCall(t, absSlot, numReturns, callPrologue(t, absSlot, numReturns, numParams, null));
}

/**
Calls a method of an object at the given _slot.  The parameters (including a spot for 'this') are assumed
to be all the values after that _slot to the top of the stack.

This function behaves identically to a method call within the language, including calling opMethod
metamethods if the method is not found.

The process of calling a method is very similar to calling a normal function.

-----
// Let's translate `o.f(3)` into API calls.

// 1. Push the object on which the method will be called.
auto slot = pushGlobal(t, "o");

// 2. Make room for 'this'.  If you want to call the method with a custom 'this', push it here.
// Otherwise, we'll let MiniD figure out the 'this' and we can just push null.
pushNull(t);

// 3. Push any params.
pushInt(t, 3);

// 4. Call it with the method name.  We didn'_t push a custom 'this', so we don'_t pass '_true' for that param.
methodCall(t, slot, "f", 0);

// We didn'_t ask for any return values, so the stack is how it was before we began.
-----

Params:
	slot = The _slot containing the object on which the method will be called.
	name = The _name of the method to call.
	numReturns = How many return values you want.  Can be -1, which means you'll get all returns.
	customThis = If true, the 'this' parameter you push after the object will be respected and
		passed as 'this' to the method (though the method will still be looked up in the object).
		The default is false, where the context will be determined automatically (i.e. it's
		the object on which the method is being called).

Returns:
	The number of return values given by the function.  If numReturns was -1, this is exactly how
	many returns the function gave.  If numReturns was >= 0, this is the same as numReturns (and
	not exactly useful since you already know it).
*/
uword methodCall(MDThread* t, word slot, char[] name, word numReturns, bool customThis = false)
{
	mixin(FuncNameMix);

	auto absSlot = fakeToAbs(t, slot);
	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwException(t, __FUNCTION__ ~ " - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwException(t, __FUNCTION__ ~ " - invalid number of returns (must be >= -1)");

	auto self = &t.stack[absSlot];
	auto methodName = createString(t, name);

	auto tmp = commonMethodCall(t, absSlot, self, self, methodName, numReturns, numParams, customThis);
	return commonCall(t, absSlot, numReturns, tmp);
}

/**
Same as above, but expects the name of the method to be on top of the stack (after the parameters).

The parameters and return value are the same as above.
*/
uword methodCall(MDThread* t, word slot, word numReturns, bool customThis = false)
{
	mixin(checkNumParams!("1"));
	auto absSlot = fakeToAbs(t, slot);

	if(!isString(t, -1))
	{
		pushTypeString(t, -1);
		throwException(t, __FUNCTION__ ~ " - Method name must be a string, not a '{}'", getString(t, -1));
	}

	auto methodName = t.stack[t.stackIndex - 1].mString;
	pop(t);

	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwException(t, __FUNCTION__ ~ " - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwException(t, __FUNCTION__ ~ " - invalid number of returns (must be >= -1)");

	auto self = &t.stack[absSlot];

	auto tmp = commonMethodCall(t, absSlot, self, self, methodName, numReturns, numParams, customThis);
	return commonCall(t, absSlot, numReturns, tmp);
}

/**
Performs a super call.  This function will only work if the currently-executing function was called as
a method of a value of type 'instance'.

This function works similarly to other kinds of calls, but it's somewhat odd.  Other calls have you push the
thing to call followed by 'this' or a spot for it.  This call requires you to just give it two empty slots.
It will fill them in (and what it puts in them is really kind of scary).  Regardless, when the super method is
called (if there is one), its 'this' parameter will be the currently-executing function's 'this' parameter.

The process of performing a supercall is not really that much different from other kinds of calls.

-----
// Let's translate `super.f(3)` into API calls.

// 1. Push a null.
auto slot = pushNull(t);

// 2. Push another null.  You can'_t call a super method with a custom 'this'.
pushNull(t);

// 3. Push any params.
pushInt(t, 3);

// 4. Call it with the method name.
superCall(t, slot, "f", 0);

// We didn'_t ask for any return values, so the stack is how it was before we began.
-----

Params:
	slot = The first empty _slot.  There should be another one on top of it.  Then come any parameters.
	name = The _name of the method to call.
	numReturns = How many return values you want.  Can be -1, which means you'll get all returns.

Returns:
	The number of return values given by the function.  If numReturns was -1, this is exactly how
	many returns the function gave.  If numReturns was >= 0, this is the same as numReturns (and
	not exactly useful since you already know it).
*/
uword superCall(MDThread* t, word slot, char[] name, word numReturns)
{
	mixin(FuncNameMix);

	// Invalid call?
	if(t.arIndex == 0 || t.currentAR.proto is null)
		throwException(t, __FUNCTION__ ~ " - Attempting to perform a supercall in a function where there is no super class");

	// Get num params
	auto absSlot = fakeToAbs(t, slot);
	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwException(t, __FUNCTION__ ~ " - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwException(t, __FUNCTION__ ~ " - invalid number of returns (must be >= -1)");

	// Get this
	auto _this = &t.stack[t.stackBase];

	if(_this.type != MDValue.Type.Instance && _this.type != MDValue.Type.Class)
	{
		pushTypeString(t, 0);
		throwException(t, __FUNCTION__ ~ " - Attempting to perform a supercall in a function where 'this' is a '{}', not an 'instance' or 'class'", getString(t, -1));
	}

	// Do the call
	auto methodName = createString(t, name);
	auto ret = commonMethodCall(t, absSlot, _this, &MDValue(t.currentAR.proto), methodName, numReturns, numParams, false);
	return commonCall(t, absSlot, numReturns, ret);
}

/**
Same as above, but expects the method name to be at the top of the stack (after the parameters).

The parameters and return value are the same as above.
*/
uword superCall(MDThread* t, word slot, word numReturns)
{
	// Get the method name
	mixin(checkNumParams!("1"));
	auto absSlot = fakeToAbs(t, slot);

	if(!isString(t, -1))
	{
		pushTypeString(t, -1);
		throwException(t, __FUNCTION__ ~ " - Method name must be a string, not a '{}'", getString(t, -1));
	}

	auto methodName = t.stack[t.stackIndex - 1].mString;
	pop(t);

	// Invalid call?
	if(t.arIndex == 0 || t.currentAR.proto is null)
		throwException(t, __FUNCTION__ ~ " - Attempting to perform a supercall in a function where there is no super class");

	// Get num params
	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwException(t, __FUNCTION__ ~ " - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwException(t, __FUNCTION__ ~ " - invalid number of returns (must be >= -1)");

	// Get this
	auto _this = &t.stack[t.stackBase];

	if(_this.type != MDValue.Type.Instance && _this.type != MDValue.Type.Class)
	{
		pushTypeString(t, 0);
		throwException(t, __FUNCTION__ ~ " - Attempting to perform a supercall in a function where 'this' is a '{}', not an 'instance' or 'class'", getString(t, -1));
	}

	// Do the call
	auto ret = commonMethodCall(t, absSlot, _this, &MDValue(t.currentAR.proto), methodName, numReturns, numParams, false);
	return commonCall(t, absSlot, numReturns, ret);
}

// ================================================================================================================================================
// Reflective functions

/**
Gets the fields namespace of the class or instance at the given slot.  Throws an exception if
the value at the given slot is not a class or instance.

Params:
	obj = The stack index of the value whose fields are to be retrieved.

Returns:
	The stack index of the newly-pushed fields namespace.
*/
word fieldsOf(MDThread* t, word obj)
{
	mixin(FuncNameMix);

	if(auto c = getClass(t, obj))
		return pushNamespace(t, classobj.fieldsOf(c));
	else if(auto i = getInstance(t, obj))
		return pushNamespace(t, instance.fieldsOf(t.vm.alloc, i));

	pushTypeString(t, obj);
	throwException(t, __FUNCTION__ ~ " - Expected 'class' or 'instance', not '{}'", getString(t, -1));

	assert(false);
}

/**
Sees if the object at the stack index `obj` has a field with the given name.  Does not take opField
metamethods into account.  Because of that, only works for tables, classes, instances, and namespaces.
If the object at the stack index `obj` is not one of those types, always returns false.  If this
function returns true, you are guaranteed that accessing a field of the given name on the given object
will succeed.

Params:
	obj = The stack index of the object to test.
	fieldName = The name of the field to look up.

Returns:
	true if the field exists in `obj`; false otherwise.
*/
bool hasField(MDThread* t, word obj, char[] fieldName)
{
	auto name = createString(t, fieldName);

	auto v = getValue(t, obj);

	switch(v.type)
	{
		case MDValue.Type.Table:
			return table.get(v.mTable, MDValue(name)) !is null;

		case MDValue.Type.Class:
			return classobj.getField(v.mClass, name) !is null;

		case MDValue.Type.Instance:
			return instance.getField(v.mInstance, name) !is null;

		case MDValue.Type.Namespace:
			return namespace.get(v.mNamespace, name) !is null;

		default:
			return false;
	}
}

/**
Sees if a method can be called on the object at stack index `obj`.  Does not take opMethod metamethods
into account, but does take type metatables into account.  In other words, if you look up a method in
an object and this function returns true, you are guaranteed that calling a method of that name on
that object will succeed.

Params:
	obj = The stack index of the obejct to test.
	methodName = The name of the method to look up.

Returns:
	true if the method can be called on `obj`; false otherwise.
*/
bool hasMethod(MDThread* t, word obj, char[] methodName)
{
	MDClass* dummy = void;
	return lookupMethod(t, getValue(t, obj), createString(t, methodName), dummy).type != MDValue.Type.Null;
}

// ================================================================================================================================================
// Debugging functions

/**
Sets or removes the debugging hook function for the given thread.

The hook function is used to "hook" into various points in the execution of MiniD scripts.
When the hook function is called, you can use the other debugging APIs to get information
about the call stack, the local variables and upvalues of functions on the call stack,
line information etc.  This way you can write a debugger for MiniD scripts.

There are a few different kind of events that you can hook into.  You can only have one hook
function on a thread, and that function will respond to all the types of events that you set
it to.

The kinds of events that you can hook into are listed in the MDThread.Hook enumeration, and
include the following:

$(UL
	$(LI $(B MDThread.Hook.Call) - This hook occurs when a function is just about to be
		called.  The top of the call stack will be the function that is about to be called,
		but the hook occurs before execution begins.)

	$(LI $(B MDThread.Hook.Ret) - This hook occurs when a function is just about to return.
		The hook is called just before the return actually occurs, so the top of the call stack
		will be the function that is about to return.  If you subscribe the hook function to
		this event, you will also get tail return events.)

	$(LI $(B MDThread.Hook.TailRet) - This hook occurs immediately after "return" hooks if the
		returning function has been tailcalled.  One "tail return" hook is called for each tailcall
		that occurred.  No real useful information will be available.  If you subscribe the
		hook function to this event, you will also get normal return events.)

	$(LI $(B MDThread.Hook.Delay) - This hook occurs after a given number of MiniD instructions
		have executed.  You set this delay as a parameter to setHookFunc, and if the delay is set
		to 0, this hook is not called.  This hook is also only ever called in MiniD script functions.)

	$(LI $(B MDThread.Hook.Line) - This hook occurs when execution of a script function reaches
		a new source line.  This is called before the first instruction associated with the given
		line occurs.  It's also called immediately after a function begins executing (before its
		first instruction executes) or if a jump to the beginning of a loop occurs.)
)

This function can be used to set or unset the hook function for the given thread.  In either case,
it expects for there to be one value at the top of the stack, which it will pop.  The value must
be a function or 'null'.  To unset the hook function, either have 'null' on the stack, or pass 0
for the mask parameter.

When the hook function is called, the thread that the hook is being called on is passed as the 'this'
parameter, and one parameter is passed.  This parameter is a string containing one of the following:
"call", "ret", "tailret", "delay", or "line", according to what kind of hook this is.  The hook function
is not required to return any values.

Params:
	mask = A bitwise OR-ing of the members of the MDThread.Hook enumeration as described above.
		The Delay value is ignored and will instead be set or unset based on the hookDelay parameter.
		If you have either the Ret or TailRet values, the function will be registered for all
		returns.  If this parameter is 0, the hook function will be removed from the thread.
		
	hookDelay = If this is nonzero, the Delay hook will be called every hookDelay MiniD instructions.
		Otherwise, if it's 0, the Delay hook will be disabled.
*/
void setHookFunc(MDThread* t, ubyte mask, uint hookDelay)
{
	mixin(checkNumParams!("1"));

	auto f = getFunction(t, -1);

	if(f is null && !isNull(t, -1))
	{
		pushTypeString(t, -1);
		throwException(t, __FUNCTION__ ~ " - hook func must be 'function' or 'null', not '{}'", getString(t, -1));
	}

	if(f is null || mask == 0)
	{
		t.hookDelay = 0;
		t.hookCounter = 0;
		t.hookFunc = null;
		t.hooks = 0;
	}
	else
	{
		if(hookDelay == 0)
			mask &= ~MDThread.Hook.Delay;
		else
			mask |= MDThread.Hook.Delay;

		if(mask & MDThread.Hook.TailRet)
		{
			mask |= MDThread.Hook.Ret;
			mask &= ~MDThread.Hook.TailRet;
		}

		t.hookDelay = hookDelay;
		t.hookCounter = hookDelay;
		t.hookFunc = f;
		t.hooks = mask;
	}

	pop(t);
}

/**
Pushes the hook function associated with the given thread, or null if no hook function is set for it.
*/
word getHookFunc(MDThread* t)
{
	if(t.hookFunc is null)
		return pushNull(t);
	else
		return pushFunction(t, t.hookFunc);
}

/**
Gets a bitwise OR-ing of all the hook types set for this thread, as declared in the MDThread.Hook
enumeration.  Note that the MDThread.Hook.TailRet flag will never be set, as tail return events
are also covered by MDThread.Hook.Ret.
*/
ubyte getHookMask(MDThread* t)
{
	return t.hooks;
}

/**
Gets the hook function delay, which is the number of instructions between each "Delay" hook event.
If the hook delay is 0, the delay hook event is disabled.
*/
uint getHookDelay(MDThread* t)
{
	return t.hookDelay;
}

debug
{
	import tango.io.Stdout;

	/**
	$(B Debug mode only.)  Prints out the contents of the stack to Stdout in the following format:

-----
[xxx:yyyy]: val: type
-----

	Where $(I xxx) is the absolute stack index; $(I yyyy) is the stack index relative to the currently-executing function's
	stack frame (negative numbers for lower slots, 0 is the first slot of the stack frame); $(I val) is a raw string
	representation of the value in that slot; and $(I type) is the type of that value.
	*/
	void printStack(MDThread* t)
	{
		Stdout.newline;
		Stdout("-----Stack Dump-----").newline;

		auto tmp = t.stackBase;
		t.stackBase = 0;
		auto top = t.stackIndex;

		for(uword i = 0; i < top; i++)
		{
			if(t.stack[i].type >= 0 && t.stack[i].type <= MDValue.Type.max)
			{
				pushToString(t, i, true);
				pushTypeString(t, i);
				Stdout.formatln("[{,3}:{,4}]: {}: {}", i, cast(word)i - cast(word)tmp, getString(t, -2), getString(t, -1));
				pop(t, 2);
			}
			else
				Stdout.formatln("[{,3}:{,4}]: {:x16}: {:x}", i, cast(word)i - cast(word)tmp, *cast(ulong*)&t.stack[i].mInt, t.stack[i].type);
		}

		t.stackBase = tmp;

		Stdout.newline;
	}

	/**
	$(B Debug mode only.)  Prints out the call stack in reverse, starting from the currently-executing function and
	going back, in the following format (without quotes; I have to put them to keep DDoc happy):

-----
"Record: name"
	"Base: base"
	"Saved Top: top"
	"Vararg Base: vargBase"
	"Returns Slot: retSlot"
	"Num Returns: numRets"
-----

	Where $(I name) is the name of the function at that level; $(I base) is the absolute stack index of where this activation
	record's stack frame begins; $(I top) is the absolute stack index of the end of its stack frame; $(I vargBase) is the
	absolute stack index of where its variadic args (if any) begin; $(I retSlot) is the absolute stack index where return
	values (if any) will started to be copied upon that function returning; and $(I numRets) being the number of returns that
	the calling function expects it to return (-1 meaning "as many as possible").

	This only prints out the current thread's call stack.  It does not take coroutine resumes and yields into account (since
	that's pretty much impossible).
	*/
	void printCallStack(MDThread* t)
	{
		Stdout.newline;
		Stdout("-----Call Stack-----").newline;

		for(word i = t.arIndex - 1; i >= 0; i--)
		{
			with(t.actRecs[i])
			{
				Stdout.formatln("Record {}", func.name.toString());
				Stdout.formatln("\tBase: {}", base);
				Stdout.formatln("\tSaved Top: {}", savedTop);
				Stdout.formatln("\tVararg Base: {}", vargBase);
				Stdout.formatln("\tReturns Slot: {}", returnSlot);
				Stdout.formatln("\tNum Returns: {}", numReturns);
			}
		}

		Stdout.newline;
	}
}

// ================================================================================================================================================
// Package
// ================================================================================================================================================

package:

MDString* createString(MDThread* t, char[] data)
{
	uword h = void;

	if(auto s = string.lookup(t, data, h))
		return s;

	uword cpLen = void;

	try
		cpLen = verify(data);
	catch(UnicodeException e)
		throwException(t, "Invalid UTF-8 sequence");

	return string.create(t, data, h, cpLen);
}

// Free all objects.
void freeAll(MDThread* t)
{
	for(auto pcur = &t.vm.alloc.gcHead; *pcur !is null; )
	{
		auto cur = *pcur;

		if((cast(MDBaseObject*)cur).mType == MDValue.Type.Instance)
		{
			auto i = cast(MDInstance*)cur;

			if(i.finalizer && ((cur.flags & GCBits.Finalized) == 0))
			{
				*pcur = cur.next;

				cur.flags |= GCBits.Finalized;
				cur.next = t.vm.alloc.finalizable;
				t.vm.alloc.finalizable = cur;
			}
			else
				pcur = &cur.next;
		}
		else
			pcur = &cur.next;
	}

	runFinalizers(t);
	assert(t.vm.alloc.finalizable is null);

	GCObject* next = void;

	for(auto cur = t.vm.alloc.gcHead; cur !is null; cur = next)
	{
		next = cur.next;
		free(t.vm, cur);
	}
}

word pushStringObj(MDThread* t, MDString* o)
{
	return push(t, MDValue(o));
}

word pushTable(MDThread* t, MDTable* o)
{
	return push(t, MDValue(o));
}

word pushArray(MDThread* t, MDArray* o)
{
	return push(t, MDValue(o));
}

word pushFunction(MDThread* t, MDFunction* o)
{
	return push(t, MDValue(o));
}

word pushClass(MDThread* t, MDClass* o)
{
	return push(t, MDValue(o));
}

word pushInstance(MDThread* t, MDInstance* o)
{
	return push(t, MDValue(o));
}

word pushNamespace(MDThread* t, MDNamespace* o)
{
	return push(t, MDValue(o));
}

word pushWeakRefObj(MDThread* t, MDWeakRef* o)
{
	return push(t, MDValue(o));
}

word pushFuncDef(MDThread* t, MDFuncDef* o)
{
	MDValue v;
	v.type = MDValue.Type.FuncDef;
	v.mBaseObj = cast(MDBaseObject*)o;
	return push(t, v);
}

MDString* getStringObj(MDThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.String)
		return v.mString;
	else
		return null;
}

MDTable* getTable(MDThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.Table)
		return v.mTable;
	else
		return null;
}

MDArray* getArray(MDThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.Array)
		return v.mArray;
	else
		return null;
}

MDFunction* getFunction(MDThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.Function)
		return v.mFunction;
	else
		return null;
}

MDClass* getClass(MDThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.Class)
		return v.mClass;
	else
		return null;
}

MDInstance* getInstance(MDThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.Instance)
		return v.mInstance;
	else
		return null;
}

MDNamespace* getNamespace(MDThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.Namespace)
		return v.mNamespace;
	else
		return null;
}

MDNativeObj* getNative(MDThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.NativeObj)
		return v.mNativeObj;
	else
		return null;
}

MDWeakRef* getWeakRef(MDThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.WeakRef)
		return v.mWeakRef;
	else
		return null;
}

MDFuncDef* getFuncDef(MDThread* t, word slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.FuncDef)
		return cast(MDFuncDef*)v.mBaseObj;
	else
		return null;
}

word push(MDThread* t, MDValue val)
{
	checkStack(t, t.stackIndex);
	t.stack[t.stackIndex] = val;
	t.stackIndex++;

	return cast(word)(t.stackIndex - 1 - t.stackBase);
}

MDValue* getValue(MDThread* t, word slot)
{
	return &t.stack[fakeToAbs(t, slot)];
}

// don't call this if t.calldepth == 0 or with depth >= t.calldepth
// returns null if the given index is a tailcall
ActRecord* getActRec(MDThread* t, uword depth)
{
	assert(t.arIndex != 0);

	if(depth == 0)
		return t.currentAR;

	for(word idx = t.arIndex - 1; idx >= 0; idx--)
	{
		if(depth == 0)
			return &t.actRecs[cast(uword)idx];
		else if(depth <= t.actRecs[cast(uword)idx].numTailcalls)
			return null;

		depth -= (t.actRecs[cast(uword)idx].numTailcalls + 1);
	}

	assert(false);
}

int pcToLine(ActRecord* ar, Instruction* pc)
{
	int line = 0;

	auto def = ar.func.scriptFunc;
	uword instructionIndex = pc - def.code.ptr - 1;

	if(instructionIndex < def.lineInfo.length)
		line = def.lineInfo[instructionIndex];

	return line;
}

int getDebugLine(MDThread* t, uword depth = 0)
{
	if(t.currentAR is null)
		return 0;

	auto ar = getActRec(t, depth);

	if(ar is null || ar.func is null || ar.func.isNative)
		return 0;
		
	return pcToLine(ar, ar.pc);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

void runFinalizers(MDThread* t)
{
	auto alloc = &t.vm.alloc;

	if(alloc.finalizable)
	{
		for(auto pcur = &alloc.finalizable; *pcur !is null; )
		{
			auto cur = *pcur;
			auto i = cast(MDInstance*)cur;

			*pcur = cur.next;
			cur.next = alloc.gcHead;
			alloc.gcHead = cur;

			cur.flags = (cur.flags & ~GCBits.Marked) | !alloc.markVal;

			// sanity check
			if(i.finalizer)
			{
				auto oldLimit = alloc.gcLimit;
				alloc.gcLimit = typeof(oldLimit).max;

				auto size = stackSize(t);

				try
				{
					pushFunction(t, i.finalizer);
					pushInstance(t, i);
					rawCall(t, -2, 0);
				}
				catch(MDException e)
				{
					// TODO: this seems like a bad idea.
					catchException(t);
					pop(t);
					setStackSize(t, size);
				}

				alloc.gcLimit = oldLimit;
			}
		}
	}
}

// ============================================================================
// Stack Manipulation

// Parsing mangles for fun and profit.
char[] _getJustName(char[] mangle)
{
	size_t idx = 1;
	size_t start = idx;
	size_t len = 0;

	while(idx < mangle.length && mangle[idx] >= '0' && mangle[idx] <= '9')
	{
		int size = mangle[idx++] - '0';

		while(mangle[idx] >= '0' && mangle[idx] <= '9')
			size = (size * 10) + (mangle[idx++] - '0');

		start = idx;
		len = size;
		idx += size;
	}

	if(start < mangle.length)
		return mangle[start .. start + len];
	else
		return "";
}

// Eheheh, I has a __FUNCTION__.
const char[] FuncNameMix = "static if(!is(typeof(__FUNCTION__))) { struct __FUNCTION {} const char[] __FUNCTION__ = _getJustName(__FUNCTION.mangleof); }";

// I'd still really like macros though.
template checkNumParams(char[] numParams, char[] t = "t")
{
	const char[] checkNumParams =
	"debug assert(" ~ t ~ ".stackIndex > " ~ t ~ ".stackBase, (printStack(" ~ t ~ "), printCallStack(" ~ t ~ "), \"fail.\"));" ~
	FuncNameMix ~
	"if((stackSize(" ~ t ~ ") - 1) < " ~ numParams ~ ")"
		"throwException(" ~ t ~ ", __FUNCTION__ ~ \" - not enough parameters (expected {}, only have {} stack slots)\", " ~ numParams ~ ", stackSize(" ~ t ~ ") - 1);";
}

RelStack fakeToRel(MDThread* t, word fake)
{
	assert(t.stackIndex > t.stackBase);

	auto size = stackSize(t);

	if(fake < 0)
		fake += size;

	if(fake < 0 || fake >= size)
		throwException(t, "Invalid stack index {} (stack size = {})", fake, size);

	return cast(RelStack)fake;
}

AbsStack fakeToAbs(MDThread* t, word fake)
{
	return fakeToRel(t, fake) + t.stackBase;
}

void checkStack(MDThread* t, AbsStack idx)
{
	if(idx >= t.stack.length)
		stackSize(t, idx * 2);
}

void stackSize(MDThread* t, uword size)
{
	auto oldBase = t.stack.ptr;
	t.vm.alloc.resizeArray(t.stack, size);
	auto newBase = t.stack.ptr;

	if(newBase !is oldBase)
		for(auto uv = t.upvalHead; uv !is null; uv = uv.nextuv)
			uv.value = (uv.value - oldBase) + newBase;
}

// ============================================================================
// Function Calling

MDNamespace* getEnv(MDThread* t, uword depth = 0)
{
	if(t.arIndex == 0)
		return t.vm.globals;
	else if(depth == 0)
		return t.currentAR.func.environment;

	for(word idx = t.arIndex - 1; idx >= 0; idx--)
	{
		if(depth == 0)
			return t.actRecs[cast(uword)idx].func.environment;
		else if(depth <= t.actRecs[cast(uword)idx].numTailcalls)
			throwException(t, "Attempting to get environment of function whose activation record was overwritten by a tail call");

		depth -= (t.actRecs[cast(uword)idx].numTailcalls + 1);
	}

	return t.vm.globals;
}

uword commonCall(MDThread* t, AbsStack slot, word numReturns, bool isScript)
{
	t.nativeCallDepth++;
	scope(exit) t.nativeCallDepth--;

	if(isScript)
		execute(t);

	maybeGC(t);

	if(numReturns == -1)
		return t.stackIndex - slot;
	else
	{
		t.stackIndex = slot + numReturns;
		return numReturns;
	}
}

bool commonMethodCall(MDThread* t, AbsStack slot, MDValue* self, MDValue* lookup, MDString* methodName, word numReturns, uword numParams, bool customThis)
{
	MDClass* proto;
	auto method = lookupMethod(t, lookup, methodName, proto);

	// Idea is like this:

	// If we're calling the real method, the object is moved to the 'this' slot and the method takes its place.

	// If we're calling opMethod, the object is left where it is (or the custom context is moved to its place),
	// the method name goes where the context was, and we use callPrologue2 with a closure that's not on the stack.

	if(method.type != MDValue.Type.Null)
	{
		if(!customThis)
			t.stack[slot + 1] = *self;

		t.stack[slot] = method;

		return callPrologue(t, slot, numReturns, numParams, proto);
	}
	else
	{
		auto mm = getMM(t, lookup, MM.Method, proto);

		if(mm is null)
		{
			typeString(t, lookup);
			throwException(t, "No implementation of method '{}' or {} for type '{}'", methodName.toString(), MetaNames[MM.Method], getString(t, -1));
		}

		if(customThis)
			t.stack[slot] = t.stack[slot + 1];
		else
			t.stack[slot] = *self;

		t.stack[slot + 1] = methodName;

		return callPrologue2(t, mm, slot, numReturns, slot, numParams + 1, proto);
	}
}

MDValue lookupMethod(MDThread* t, MDValue* v, MDString* name, out MDClass* proto)
{
	switch(v.type)
	{
		case MDValue.Type.Class:
			auto ret = getMethod(v.mClass, name, proto);

			if(ret.type != MDValue.Type.Null)
				return ret;

			goto default;

		case MDValue.Type.Instance:
			return getMethod(v.mInstance, name, proto);

		case MDValue.Type.Table:
			auto ret = getMethod(v.mTable, name);

			if(ret.type != MDValue.Type.Null)
				return ret;

			goto default;

		case MDValue.Type.Namespace:
			return getMethod(v.mNamespace, name);

		default:
			return getMethod(t, v.type, name);
	}
}

MDValue getMethod(MDClass* cls, MDString* name, out MDClass* proto)
{
	if(auto ret = classobj.getField(cls, name, proto))
		return *ret;
	else
		return MDValue.nullValue;
}

MDValue getMethod(MDInstance* inst, MDString* name, out MDClass* proto)
{
	MDValue dummy;

	if(auto ret = instance.getField(inst, name, dummy))
	{
		if(dummy == MDValue(inst))
			proto = inst.parent;
		else
		{
			assert(dummy.type == MDValue.Type.Class);
			proto = dummy.mClass;
		}

		return *ret;
	}
	else
		return MDValue.nullValue;
}

MDValue getMethod(MDTable* tab, MDString* name)
{
	if(auto ret = table.get(tab, MDValue(name)))
		return *ret;
	else
		return MDValue.nullValue;
}

MDValue getMethod(MDNamespace* ns, MDString* name)
{
	if(auto ret = namespace.get(ns, name))
		return *ret;
	else
		return MDValue.nullValue;
}

MDValue getMethod(MDThread* t, MDValue.Type type, MDString* name)
{
	auto mt = getMetatable(t, type);

	if(mt is null)
		return MDValue.nullValue;

	if(auto ret = namespace.get(mt, name))
		return *ret;
	else
		return MDValue.nullValue;
}

MDFunction* getMM(MDThread* t, MDValue* obj, MM method)
{
	MDClass* dummy = void;
	return getMM(t, obj, method, dummy);
}

MDFunction* getMM(MDThread* t, MDValue* obj, MM method, out MDClass* proto)
{
	auto name = t.vm.metaStrings[method];

	switch(obj.type)
	{
		case MDValue.Type.Instance:
			auto ret = getMethod(obj.mInstance, name, proto);

			if(ret.type == MDValue.Type.Function)
				return ret.mFunction;
			else
				return null;

		case MDValue.Type.Table:
			auto ret = getMethod(obj.mTable, name);
			
			if(ret.type == MDValue.Type.Function)
				return ret.mFunction;

			goto default;

		default:
			auto ret = getMethod(t, obj.type, name);
			
			if(ret.type == MDValue.Type.Function)
				return ret.mFunction;
			else
				return null;
	}
}

template tryMMParams(int numParams, int n = 1)
{
	static if(n <= numParams)
		const char[] tryMMParams = (n > 1 ? ", " : "") ~ "MDValue* src" ~ n.stringof ~ tryMMParams!(numParams, n + 1);
	else
		const char[] tryMMParams = "";
}

template tryMMSaves(int numParams, int n = 1)
{
	static if(n <= numParams)
		const char[] tryMMSaves = "\tauto srcsave" ~ n.stringof ~ " = *src" ~ n.stringof ~ ";\n" ~ tryMMSaves!(numParams, n + 1);
	else
		const char[] tryMMSaves = "";
}

template tryMMPushes(int numParams, int n = 1)
{
	static if(n <= numParams)
		const char[] tryMMPushes = "\tpush(t, srcsave" ~ n.stringof ~ ");\n" ~ tryMMPushes!(numParams, n + 1);
	else
		const char[] tryMMPushes = "";
}

template tryMMImpl(int numParams, bool hasDest)
{
	const char[] tryMMImpl =
	"bool tryMM(MDThread* t, MM mm, " ~ (hasDest? "MDValue* dest, " : "") ~ tryMMParams!(numParams) ~ ")\n"
	"{\n"
	"	MDClass* proto = null;"
	"	auto method = getMM(t, src1, mm, proto);\n"
	"\n"
	"	if(method is null)\n"
	"		return false;\n"
	"\n"
	~
	(hasDest?
		"	bool shouldLoad = void;\n"
		"	savePtr(t, dest, shouldLoad);\n"
	:
		"")
	~
	"\n"
	~ tryMMSaves!(numParams) ~
	"\n"
	"	auto funcSlot = pushFunction(t, method);\n"
	~ tryMMPushes!(numParams) ~
	"	commonCall(t, funcSlot + t.stackBase, " ~ (hasDest ? "1" : "0") ~ ", callPrologue(t, funcSlot + t.stackBase, " ~ (hasDest ? "1" : "0") ~ ", " ~ numParams.stringof ~ ", proto));\n"
	~
	(hasDest?
		"	if(shouldLoad)\n"
		"		loadPtr(t, dest);\n"
		"	*dest = t.stack[t.stackIndex - 1];\n"
		"	pop(t);\n"
	:
		"")
	~
	"	return true;\n"
	"}";
}

template tryMM_shim(int numParams, bool hasDest)
{
	mixin(tryMMImpl!(numParams, hasDest));
}

template tryMM(int numParams, bool hasDest)
{
	static assert(numParams > 0, "Need at least one param");
	alias tryMM_shim!(numParams, hasDest).tryMM tryMM;
}

bool callPrologue(MDThread* t, AbsStack slot, word numReturns, uword numParams, MDClass* proto)
{
	assert(numParams > 0);
	auto func = &t.stack[slot];

	switch(func.type)
	{
		case MDValue.Type.Function:
			return callPrologue2(t, func.mFunction, slot, numReturns, slot + 1, numParams, proto);

		case MDValue.Type.Class:
			auto cls = func.mClass;

			if(cls.allocator)
			{
				t.stack[slot] = cls.allocator;
				t.stack[slot + 1] = cls;
				rawCall(t, slot - t.stackBase, 1);

				if(!isInstance(t, slot - t.stackBase))
				{
					pushTypeString(t, slot - t.stackBase);
					throwException(t, "class allocator expected to return an 'instance', not a '{}'", getString(t, -1));
				}
			}
			else
			{
				auto inst = instance.create(t.vm.alloc, cls);

				// call any constructor
				auto ctor = classobj.getField(cls, t.vm.ctorString);

				if(ctor !is null)
				{
					if(ctor.type != MDValue.Type.Function)
					{
						typeString(t, ctor);
						throwException(t, "class constructor expected to be a 'function', not '{}'", getString(t, -1));
					}

					t.nativeCallDepth++;
					scope(exit) t.nativeCallDepth--;
					t.stack[slot] = ctor.mFunction;
					t.stack[slot + 1] = inst;

					// do this instead of rawCall so the proto is set correctly
					if(callPrologue(t, slot, 0, numParams, cls))
						execute(t);
				}

				t.stack[slot] = inst;
			}

			if(numReturns == -1)
				t.stackIndex = slot + 1;
			else
			{
				if(numReturns > 1)
					t.stack[slot + 1 .. slot + numReturns] = MDValue.nullValue;

				if(t.arIndex == 0)
				{
					t.state = MDThread.State.Dead;
					t.shouldHalt = false;
					t.stackIndex = slot + numReturns;

					if(t is t.vm.mainThread)
						t.vm.curThread = t;
				}
				else if(t.currentAR.savedTop < slot + numReturns)
					t.stackIndex = slot + numReturns;
				else
					t.stackIndex = t.currentAR.savedTop;
			}

			return false;

		case MDValue.Type.Thread:
			auto thread = func.mThread;

			if(thread is t)
				throwException(t, "Thread attempting to resume itself");

			if(thread is t.vm.mainThread)
				throwException(t, "Attempting to resume VM's main thread");

			if(thread.state != MDThread.State.Initial && thread.state != MDThread.State.Suspended)
				throwException(t, "Attempting to resume a {} coroutine", stateString(thread));

			auto ar = pushAR(t);

			ar.base = slot;
			ar.savedTop = t.stackIndex;
			ar.vargBase = slot;
			ar.returnSlot = slot;
			ar.func = null;
			ar.pc = null;
			ar.numReturns = numReturns;
			ar.proto = null;
			ar.numTailcalls = 0;
			ar.firstResult = 0;
			ar.numResults = 0;
			ar.unwindCounter = 0;
			ar.unwindReturn = null;

			t.stackIndex = slot;

			uword numRets = void;

			try
			{
				if(thread.state == MDThread.State.Initial)
				{
					checkStack(thread, cast(AbsStack)(numParams + 1));
					thread.stack[1 .. 1 + numParams] = t.stack[slot + 1 .. slot + 1 + numParams];
					thread.stackIndex += numParams;
				}
				else
				{
					// Get rid of 'this'
					numParams--;
					saveResults(thread, t, slot + 2, numParams);
				}

				auto savedState = t.state;
				t.state = MDThread.State.Waiting;

				scope(exit)
				{
					t.state = savedState;
					t.vm.curThread = t;
				}

				numRets = resume(thread, numParams);
			}
			catch(MDException e)
			{
				callEpilogue(t, false);
				throw e;
			}
			// Don't have to handle halt exceptions; they can't propagate out of a thread

			saveResults(t, thread, thread.stackIndex - numRets, numRets);
			thread.stackIndex -= numRets;

			callEpilogue(t, true);
			return false;

		default:
			auto method = getMM(t, func, MM.Call, proto);

			if(method is null)
			{
				typeString(t, func);
				throwException(t, "No implementation of {} for type '{}'", MetaNames[MM.Call], getString(t, -1));
			}

			t.stack[slot + 1] = *func;
			*func = method;
			return callPrologue2(t, method, slot, numReturns, slot + 1, numParams, proto);
	}
}

bool callPrologue2(MDThread* t, MDFunction* func, AbsStack returnSlot, word numReturns, AbsStack paramSlot, word numParams, MDClass* proto)
{
	const char[] wrapEH =
		"catch(MDException e)
		{
			t.vm.traceback.append(&t.vm.alloc, getDebugLoc(t));
			callEpilogue(t, false);
			throw e;
		}
		catch(MDHaltException e)
		{
			unwindEH(t);
			callEpilogue(t, false);
			throw e;
		}";


	if(!func.isNative)
	{
		// Script function
		auto funcDef = func.scriptFunc;
		auto ar = pushAR(t);

		if(funcDef.isVararg && numParams > funcDef.numParams)
		{
			// In this case, we move the formal parameters after the varargs and null out where the formal
			// params used to be.
			ar.base = paramSlot + numParams;
			ar.vargBase = paramSlot + funcDef.numParams;

			checkStack(t, ar.base + funcDef.stackSize - 1);

			auto oldParams = t.stack[paramSlot .. paramSlot + funcDef.numParams];
			t.stack[ar.base .. ar.base + funcDef.numParams] = oldParams;
			oldParams[] = MDValue.nullValue;

			// For nulling out the stack.
			numParams = funcDef.numParams;
		}
		else
		{
			// In this case, everything is where it needs to be already.
			ar.base = paramSlot;
			ar.vargBase = paramSlot;

			checkStack(t, ar.base + funcDef.stackSize - 1);

			// Compensate for too many params.
			if(numParams > funcDef.numParams)
				numParams = funcDef.numParams;

			// If we have too few params, the extra param slots will be nulled out.
		}

		// Null out the stack frame after the parameters.
		t.stack[ar.base + numParams .. ar.base + funcDef.stackSize] = MDValue.nullValue;

		// Fill in the rest of the activation record.
		ar.returnSlot = returnSlot;
		ar.func = func;
		ar.pc = funcDef.code.ptr;
		ar.numReturns = numReturns;
		ar.firstResult = 0;
		ar.numResults = 0;
		ar.proto = proto is null ? null : proto.parent;
		ar.numTailcalls = 0;
		ar.savedTop = ar.base + funcDef.stackSize;
		ar.unwindCounter = 0;
		ar.unwindReturn = null;

		// Set the stack indices.
		t.stackBase = ar.base;
		t.stackIndex = ar.savedTop;

		// Call any hook.
		mixin(
		"if(t.hooks & MDThread.Hook.Call)
		{
			try
				callHook(t, MDThread.Hook.Call);
		" ~ wrapEH ~ "
		}");

		return true;
	}
	else
	{
		// Native function
		t.stackIndex = paramSlot + numParams;
		checkStack(t, t.stackIndex);

		auto ar = pushAR(t);

		ar.base = paramSlot;
		ar.vargBase = paramSlot;
		ar.returnSlot = returnSlot;
		ar.func = func;
		ar.numReturns = numReturns;
		ar.firstResult = 0;
		ar.numResults = 0;
		ar.savedTop = t.stackIndex;
		ar.proto = proto is null ? null : proto.parent;
		ar.numTailcalls = 0;
		ar.unwindCounter = 0;
		ar.unwindReturn = null;

		t.stackBase = ar.base;

		uword actualReturns = void;

		mixin(
		"try
		{
			if(t.hooks & MDThread.Hook.Call)
				callHook(t, MDThread.Hook.Call);

			t.nativeCallDepth++;
			scope(exit) t.nativeCallDepth--;

			auto savedState = t.state;
			t.state = MDThread.State.Running;
			t.vm.curThread = t;
			scope(exit) t.state = savedState;

			actualReturns = func.nativeFunc(t);
		}" ~ wrapEH);

		saveResults(t, t, t.stackIndex - actualReturns, actualReturns);
		callEpilogue(t, true);
		return false;
	}
}

void callEpilogue(MDThread* t, bool needResults)
{
	if(t.hooks & MDThread.Hook.Ret)
		callReturnHooks(t);

	auto destSlot = t.currentAR.returnSlot;
	auto numExpRets = t.currentAR.numReturns;
	auto results = loadResults(t);

	bool isMultRet = false;

	if(numExpRets == -1)
	{
		isMultRet = true;
		numExpRets = results.length;
	}

	popAR(t);

	if(needResults)
	{
		t.numYields = results.length;

		auto stk = t.stack;

		if(numExpRets <= results.length)
			stk[destSlot .. destSlot + numExpRets] = results[0 .. numExpRets];
		else
		{
			stk[destSlot .. destSlot + results.length] = results[];
			stk[destSlot + results.length .. destSlot + numExpRets] = MDValue.nullValue;
		}
	}
	else
		t.numYields = 0;

	if(t.arIndex == 0)
	{
		t.state = MDThread.State.Dead;
		t.shouldHalt = false;
		t.stackIndex = destSlot + numExpRets;

		if(t is t.vm.mainThread)
			t.vm.curThread = t;
	}
	else if(needResults && (isMultRet || t.currentAR.savedTop < destSlot + numExpRets)) // last case happens in native -> native calls
		t.stackIndex = destSlot + numExpRets;
	else
		t.stackIndex = t.currentAR.savedTop;
}

void saveResults(MDThread* t, MDThread* from, AbsStack first, uword num)
{
	if(num == 0)
		return;

	if((t.results.length - t.resultIndex) < num)
	{
		auto newLen = t.results.length * 2;

		if(newLen - t.resultIndex < num)
			newLen = t.resultIndex + num;

		t.vm.alloc.resizeArray(t.results, newLen);
	}

	assert(t.currentAR.firstResult is 0 && t.currentAR.numResults is 0);

	auto tmp = from.stack[first .. first + num];
	t.results[t.resultIndex .. t.resultIndex + num] = tmp;
	t.currentAR.firstResult = t.resultIndex;
	t.currentAR.numResults = num;

	t.resultIndex += num;
}

MDValue[] loadResults(MDThread* t)
{
	auto first = t.currentAR.firstResult;
	auto num = t.currentAR.numResults;
	auto ret = t.results[first .. first + num];
	t.currentAR.firstResult = 0;
	t.currentAR.numResults = 0;
	t.resultIndex -= num;
	return ret;
}

void unwindEH(MDThread* t)
{
	while(t.trIndex > 0 && t.currentTR.actRecord >= t.arIndex)
		popTR(t);
}

// ============================================================================
// Implementations

word toStringImpl(MDThread* t, MDValue v, bool raw)
{
	char[80] buffer = void;

	switch(v.type)
	{
		case MDValue.Type.Null:  return pushString(t, "null");
		case MDValue.Type.Bool:  return pushString(t, v.mBool ? "true" : "false");
		case MDValue.Type.Int:   return pushString(t, Integer.format(buffer, v.mInt));
		case MDValue.Type.Float:
			uword pos = 0;

			auto size = t.vm.formatter.convert((char[] s)
			{
				if(pos + s.length > buffer.length)
					s.length = buffer.length - pos;

				buffer[pos .. pos + s.length] = s[];
				pos += s.length;
				return cast(uint)s.length; // the cast is there to make things work on x64 :P
			}, "{}", v.mFloat);

			return pushString(t, buffer[0 .. pos]);

		case MDValue.Type.Char:
			auto inbuf = v.mChar;
			
			if(!Utf.isValid(inbuf))
				throwException(t, "Character '{:X}' is not a valid Unicode codepoint", cast(uint)inbuf);

			uint ate = 0;
			return pushString(t, Utf.toString((&inbuf)[0 .. 1], buffer, &ate));

		case MDValue.Type.String:
			return push(t, v);

		default:
			if(!raw)
			{
				MDClass* proto;
				if(auto method = getMM(t, &v, MM.ToString, proto))
				{
					auto funcSlot = pushFunction(t, method);
					push(t, v);
					commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 1, proto));

					if(!isString(t, -1))
					{
						pushTypeString(t, -1);
						throwException(t, "toString was supposed to return a string, but returned a '{}'", getString(t, -1));
					}

					return stackSize(t) - 1;
				}
			}

			switch(v.type)
			{
				case MDValue.Type.Table: return pushFormat(t, "{} 0x{:X8}", MDValue.typeString(MDValue.Type.Table), cast(void*)v.mTable);
				case MDValue.Type.Array: return pushFormat(t, "{} 0x{:X8}", MDValue.typeString(MDValue.Type.Array), cast(void*)v.mArray);
				case MDValue.Type.Function:
					auto f = v.mFunction;

					if(f.isNative)
						return pushFormat(t, "native {} {}", MDValue.typeString(MDValue.Type.Function), f.name.toString());
					else
					{
						auto loc = f.scriptFunc.location;
						return pushFormat(t, "script {} {}({}({}:{}))", MDValue.typeString(MDValue.Type.Function), f.name.toString(), loc.file.toString(), loc.line, loc.col);
					}

				case MDValue.Type.Class:    return pushFormat(t, "{} {} (0x{:X8})", MDValue.typeString(MDValue.Type.Class), v.mClass.name.toString(), cast(void*)v.mClass);
				case MDValue.Type.Instance: return pushFormat(t, "{} of {} (0x{:X8})", MDValue.typeString(MDValue.Type.Instance), v.mInstance.parent.name.toString(), cast(void*)v.mInstance);
				case MDValue.Type.Namespace:
					if(raw)
						return pushFormat(t, "{} 0x{:X8}", MDValue.typeString(MDValue.Type.Namespace), cast(void*)v.mNamespace);
					else
					{
						pushString(t, MDValue.typeString(MDValue.Type.Namespace));
						pushChar(t, ' ');
						pushNamespaceNamestring(t, v.mNamespace);
						return cat(t, 3);
					}

				case MDValue.Type.Thread: return pushFormat(t, "{} 0x{:X8}", MDValue.typeString(MDValue.Type.Thread), cast(void*)v.mThread);
				case MDValue.Type.NativeObj: return pushFormat(t, "{} 0x{:X8}", MDValue.typeString(MDValue.Type.NativeObj), cast(void*)v.mNativeObj.obj);
				case MDValue.Type.WeakRef: return pushFormat(t, "{} 0x{:X8}", MDValue.typeString(MDValue.Type.WeakRef), cast(void*)v.mWeakRef);

				default: assert(false);
			}
	}
}

bool inImpl(MDThread* t, MDValue* item, MDValue* container)
{
	switch(container.type)
	{
		case MDValue.Type.String:
			if(item.type == MDValue.Type.Char)
				return string.contains(container.mString, item.mChar);
			else if(item.type == MDValue.Type.String)
				return string.contains(container.mString, item.mString.toString());
			else
			{
				typeString(t, item);
				throwException(t, "Can only use characters to look in strings, not '{}'", getString(t, -1));
			}

		case MDValue.Type.Table:
			return table.contains(container.mTable, *item);

		case MDValue.Type.Array:
			return array.contains(container.mArray, *item);

		case MDValue.Type.Namespace:
			if(item.type != MDValue.Type.String)
			{
				typeString(t, item);
				throwException(t, "Can only use strings to look in namespaces, not '{}'", getString(t, -1));
			}

			return namespace.contains(container.mNamespace, item.mString);

		default:
			MDClass* proto;
			auto method = getMM(t, container, MM.In, proto);

			if(method is null)
			{
				typeString(t, container);
				throwException(t, "No implementation of {} for type '{}'", MetaNames[MM.In], getString(t, -1));
			}

			auto containersave = *container;
			auto itemsave = *item;

			auto funcSlot = pushFunction(t, method);
			push(t, containersave);
			push(t, itemsave);
			commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 2, proto));

			auto ret = isTrue(t, -1);
			pop(t);
			return ret;
	}
}

void idxImpl(MDThread* t, MDValue* dest, MDValue* container, MDValue* key, bool raw)
{
	switch(container.type)
	{
		case MDValue.Type.Array:
			if(key.type != MDValue.Type.Int)
			{
				typeString(t, key);
				throwException(t, "Attempting to index an array with a '{}'", getString(t, -1));
			}

			auto index = key.mInt;
			auto arr = container.mArray;

			if(index < 0)
				index += arr.slice.length;

			if(index < 0 || index >= arr.slice.length)
				throwException(t, "Invalid array index {} (length is {})", key.mInt, arr.slice.length);

			*dest = arr.slice[cast(uword)index];
			return;

		case MDValue.Type.String:
			if(key.type != MDValue.Type.Int)
			{
				typeString(t, key);
				throwException(t, "Attempting to index a string with a '{}'", getString(t, -1));
			}

			auto index = key.mInt;
			auto str = container.mString;

			if(index < 0)
				index += str.cpLength;

			if(index < 0 || index >= str.cpLength)
				throwException(t, "Invalid string index {} (length is {})", key.mInt, str.cpLength);

			*dest = string.charAt(str, cast(uword)index);
			return;

		case MDValue.Type.Table:
			return tableIdxImpl(t, dest, container, key, raw);

		default:
			if(!raw && tryMM!(2, true)(t, MM.Index, dest, container, key))
				return;

			typeString(t, container);
			throwException(t, "Attempting to index a value of type '{}'", getString(t, -1));
	}
}

void tableIdxImpl(MDThread* t, MDValue* dest, MDValue* container, MDValue* key, bool raw)
{
	auto v = table.get(container.mTable, *key);

	if(v !is null)
		*dest = *v;
	else
	{
		if(raw)
			*dest = MDValue.nullValue;
		else if(auto method = getMM(t, container, MM.Index))
		{
			bool shouldLoad = void;
			savePtr(t, dest, shouldLoad);

			auto containersave = *container;
			auto keysave = *key;

			auto funcSlot = pushFunction(t, method);
			push(t, containersave);
			push(t, keysave);
			rawCall(t, funcSlot, 1);

			if(shouldLoad)
				loadPtr(t, dest);

			*dest = t.stack[t.stackIndex - 1];
			pop(t);
		}
		else
			*dest = MDValue.nullValue;
	}
}

void idxaImpl(MDThread* t, MDValue* container, MDValue* key, MDValue* value, bool raw)
{
	switch(container.type)
	{
		case MDValue.Type.Array:
			if(key.type != MDValue.Type.Int)
			{
				typeString(t, key);
				throwException(t, "Attempting to index-assign an array with a '{}'", getString(t, -1));
			}

			auto index = key.mInt;
			auto arr = container.mArray;

			if(index < 0)
				index += arr.slice.length;

			if(index < 0 || index >= arr.slice.length)
				throwException(t, "Invalid array index {} (length is {})", key.mInt, arr.slice.length);

			arr.slice[cast(uword)index] = *value;
			return;

		case MDValue.Type.Table:
			return tableIdxaImpl(t, container, key, value, raw);

		default:
			if(!raw && tryMM!(3, false)(t, MM.IndexAssign, container, key, value))
				return;

			typeString(t, container);
			throwException(t, "Attempting to index-assign a value of type '{}'", getString(t, -1));
	}
}

void tableIdxaImpl(MDThread* t, MDValue* container, MDValue* key, MDValue* value, bool raw)
{
	if(key.type == MDValue.Type.Null)
	{
		if(!raw && tryMM!(3, false)(t, MM.IndexAssign, container, key, value))
			return;

		throwException(t, "Attempting to index-assign a table with a key of type 'null'");
	}

	auto v = table.get(container.mTable, *key);

	if(v !is null)
	{
		if(value.type != MDValue.Type.Null)
			*v = *value;
		else
			table.remove(container.mTable, *key);
	}
	else if(value.type != MDValue.Type.Null &&
		!(value.type == MDValue.Type.WeakRef && value.mWeakRef.obj is null) &&
		!(key.type == MDValue.Type.WeakRef && key.mWeakRef.obj is null))
	{
		if(raw || !tryMM!(3, false)(t, MM.IndexAssign, container, key, value))
			table.set(t.vm.alloc, container.mTable, *key, *value);
	}
	// otherwise, do nothing (val is null and it doesn't exist)
}

word commonField(MDThread* t, AbsStack container, bool raw)
{
	auto slot = t.stackIndex - 1;
	fieldImpl(t, &t.stack[slot], &t.stack[container], t.stack[slot].mString, raw);
	return stackSize(t) - 1;
}

void commonFielda(MDThread* t, AbsStack container, bool raw)
{
	auto slot = t.stackIndex - 2;
	fieldaImpl(t, &t.stack[container], t.stack[slot].mString, &t.stack[slot + 1], raw);
	pop(t, 2);
}

void fieldImpl(MDThread* t, MDValue* dest, MDValue* container, MDString* name, bool raw)
{
	switch(container.type)
	{
		case MDValue.Type.Table:
			// This is right, tables do not have separate opField capabilities.
			return tableIdxImpl(t, dest, container, &MDValue(name), raw);

		case MDValue.Type.Class:
			auto v = classobj.getField(container.mClass, name);

			if(v is null)
			{
				typeString(t, container);
				throwException(t, "Attempting to access nonexistent field '{}' from '{}'", name.toString(), getString(t, -1));
			}

			return *dest = *v;

		case MDValue.Type.Instance:
			auto v = instance.getField(container.mInstance, name);

			if(v is null)
			{
				if(!raw && tryMM!(2, true)(t, MM.Field, dest, container, &MDValue(name)))
					return;

				typeString(t, container);
				throwException(t, "Attempting to access nonexistent field '{}' from '{}'", name.toString(), getString(t, -1));
			}

			return *dest = *v;


		case MDValue.Type.Namespace:
			auto v = namespace.get(container.mNamespace, name);

			if(v is null)
			{
				if(!raw && tryMM!(2, true)(t, MM.Field, dest, container, &MDValue(name)))
					return;

				toStringImpl(t, *container, false);
				throwException(t, "Attempting to access nonexistent field '{}' from '{}'", name.toString(), getString(t, -1));
			}

			return *dest = *v;

		default:
			if(!raw && tryMM!(2, true)(t, MM.Field, dest, container, &MDValue(name)))
				return;

			typeString(t, container);
			throwException(t, "Attempting to access field '{}' from a value of type '{}'", name.toString(), getString(t, -1));
	}
}

void fieldaImpl(MDThread* t, MDValue* container, MDString* name, MDValue* value, bool raw)
{
	switch(container.type)
	{
		case MDValue.Type.Table:
			// This is right, tables do not have separate opField capabilities.
			return tableIdxaImpl(t, container, &MDValue(name), value, raw);

		case MDValue.Type.Class:
			return classobj.setField(t.vm.alloc, container.mClass, name, value);

		case MDValue.Type.Instance:
			auto i = container.mInstance;

			MDValue owner;
			auto field = instance.getField(i, name, owner);

			if(field is null)
			{
				if(!raw && tryMM!(3, false)(t, MM.FieldAssign, container, &MDValue(name), value))
					return;
				else
					instance.setField(t.vm.alloc, i, name, value);
			}
			else if(owner != MDValue(i))
				instance.setField(t.vm.alloc, i, name, value);
			else
				*field = *value;
			return;

		case MDValue.Type.Namespace:
			return namespace.set(t.vm.alloc, container.mNamespace, name, value);

		default:
			if(!raw && tryMM!(3, false)(t, MM.FieldAssign, container, &MDValue(name), value))
				return;

			typeString(t, container);
			throwException(t, "Attempting to assign field '{}' into a value of type '{}'", name.toString(), getString(t, -1));
	}
}

mdint compareImpl(MDThread* t, MDValue* a, MDValue* b)
{
	if(a.type == MDValue.Type.Int)
	{
		if(b.type == MDValue.Type.Int)
			return Compare3(a.mInt, b.mInt);
		else if(b.type == MDValue.Type.Float)
			return Compare3(cast(mdfloat)a.mInt, b.mFloat);
	}
	else if(a.type == MDValue.Type.Float)
	{
		if(b.type == MDValue.Type.Int)
			return Compare3(a.mFloat, cast(mdfloat)b.mInt);
		else if(b.type == MDValue.Type.Float)
			return Compare3(a.mFloat, b.mFloat);
	}

	MDClass* proto;
	// Don'_t put an else here.  SRSLY.
	if(a.type == b.type)
	{
		switch(a.type)
		{
			case MDValue.Type.Null: return 0;
			case MDValue.Type.Bool: return (cast(mdint)a.mBool - cast(mdint)b.mBool);
			case MDValue.Type.Char: return Compare3(a.mChar, b.mChar);

			case MDValue.Type.String:
				if(a.mString is b.mString)
					return 0;

				return string.compare(a.mString, b.mString);

			case MDValue.Type.Table, MDValue.Type.Instance:
				if(auto method = getMM(t, a, MM.Cmp, proto))
					return commonCompare(t, method, a, b, proto);
				else if(auto method = getMM(t, b, MM.Cmp, proto))
					return -commonCompare(t, method, b, a, proto);
				break; // break to error

			default: break; // break to error
		}
	}
	else if((a.type == MDValue.Type.Instance || a.type == MDValue.Type.Table))
	{
		if(auto method = getMM(t, a, MM.Cmp, proto))
			return commonCompare(t, method, a, b, proto);
	}
	else if((b.type == MDValue.Type.Instance || b.type == MDValue.Type.Table))
	{
		if(auto method = getMM(t, b, MM.Cmp, proto))
			return -commonCompare(t, method, b, a, proto);
	}

	auto bsave = *b;
	typeString(t, a);
	typeString(t, &bsave);
	throwException(t, "Can't compare types '{}' and '{}'", getString(t, -2), getString(t, -1));
	assert(false);
}

mdint commonCompare(MDThread* t, MDFunction* method, MDValue* a, MDValue* b, MDClass* proto)
{
	auto asave = *a;
	auto bsave = *b;

	auto funcReg = pushFunction(t, method);
	push(t, asave);
	push(t, bsave);
	commonCall(t, funcReg + t.stackBase, 1, callPrologue(t, funcReg + t.stackBase, 1, 2, proto));

	auto ret = *getValue(t, -1);
	pop(t);

	if(ret.type != MDValue.Type.Int)
	{
		typeString(t, &ret);
		throwException(t, "{} is expected to return an int, but '{}' was returned instead", MetaNames[MM.Cmp], getString(t, -1));
	}

	return ret.mInt;
}

bool switchCmpImpl(MDThread* t, MDValue* a, MDValue* b)
{
	if(a.type != b.type)
		return false;

	if(a.opEquals(*b))
		return true;

	MDClass* proto;

	if(a.type == MDValue.Type.Instance || a.type == MDValue.Type.Table)
	{
		if(auto method = getMM(t, a, MM.Cmp, proto))
			return commonCompare(t, method, a, b, proto) == 0;
		else if(auto method = getMM(t, b, MM.Cmp, proto))
			return commonCompare(t, method, b, a, proto) == 0;
	}
	
	return false;
}

bool equalsImpl(MDThread* t, MDValue* a, MDValue* b)
{
	if(a.type == MDValue.Type.Int)
	{
		if(b.type == MDValue.Type.Int)
			return a.mInt == b.mInt;
		else if(b.type == MDValue.Type.Float)
			return (cast(mdfloat)a.mInt) == b.mFloat;
	}
	else if(a.type == MDValue.Type.Float)
	{
		if(b.type == MDValue.Type.Int)
			return a.mFloat == (cast(mdfloat)b.mInt);
		else if(b.type == MDValue.Type.Float)
			return a.mFloat == b.mFloat;
	}

	MDClass* proto;
	// Don'_t put an else here.  SRSLY.
	if(a.type == b.type)
	{
		switch(a.type)
		{
			case MDValue.Type.Null:   return true;
			case MDValue.Type.Bool:   return a.mBool == b.mBool;
			case MDValue.Type.Char:   return a.mChar == b.mChar;
			// Interning is fun.  We don'_t have to do a string comparison at all.
			case MDValue.Type.String: return a.mString is b.mString;

			case MDValue.Type.Table, MDValue.Type.Instance:
				if(auto method = getMM(t, a, MM.Equals, proto))
					return commonEquals(t, method, a, b, proto);
				else if(auto method = getMM(t, b, MM.Equals, proto))
					return commonEquals(t, method, b, a, proto);
				break; // break to error

			default: break; // break to error
		}
	}
	else if((a.type == MDValue.Type.Instance || a.type == MDValue.Type.Table))
	{
		if(auto method = getMM(t, a, MM.Equals, proto))
			return commonEquals(t, method, a, b, proto);
	}
	else if((b.type == MDValue.Type.Instance || b.type == MDValue.Type.Table))
	{
		if(auto method = getMM(t, b, MM.Equals, proto))
			return commonEquals(t, method, b, a, proto);
	}

	auto bsave = *b;
	typeString(t, a);
	typeString(t, &bsave);
	throwException(t, "Can't compare types '{}' and '{}' for equality", getString(t, -2), getString(t, -1));
	assert(false);
}

bool commonEquals(MDThread* t, MDFunction* method, MDValue* a, MDValue* b, MDClass* proto)
{
	auto asave = *a;
	auto bsave = *b;

	auto funcReg = pushFunction(t, method);
	push(t, asave);
	push(t, bsave);
	commonCall(t, funcReg + t.stackBase, 1, callPrologue(t, funcReg + t.stackBase, 1, 2, proto));

	auto ret = *getValue(t, -1);
	pop(t);

	if(ret.type != MDValue.Type.Bool)
	{
		typeString(t, &ret);
		throwException(t, "{} is expected to return a bool, but '{}' was returned instead", MetaNames[MM.Equals], getString(t, -1));
	}

	return ret.mBool;
}

void lenImpl(MDThread* t, MDValue* dest, MDValue* src)
{
	switch(src.type)
	{
		case MDValue.Type.String:    return *dest = cast(mdint)src.mString.cpLength;
		case MDValue.Type.Array:     return *dest = cast(mdint)src.mArray.slice.length;
		case MDValue.Type.Namespace: return *dest = cast(mdint)namespace.length(src.mNamespace);

		default:
			if(tryMM!(1, true)(t, MM.Length, dest, src))
				return;

			if(src.type == MDValue.Type.Table)
				return *dest = cast(mdint)table.length(src.mTable);

			typeString(t, src);
			throwException(t, "Can't get the length of a '{}'", getString(t, -1));
	}
}

void lenaImpl(MDThread* t, MDValue* dest, MDValue* len)
{
	switch(dest.type)
	{
		case MDValue.Type.Array:
			if(len.type != MDValue.Type.Int)
			{
				typeString(t, len);
				throwException(t, "Attempting to set the length of an array using a length of type '{}'", getString(t, -1));
			}

			auto l = len.mInt;

			if(l < 0)
				throwException(t, "Attempting to set the length of an array to a negative value ({})", l);

			return array.resize(t.vm.alloc, dest.mArray, cast(uword)l);

		default:
			if(tryMM!(2, false)(t, MM.LengthAssign, dest, len))
				return;

			typeString(t, dest);
			throwException(t, "Can't set the length of a '{}'", getString(t, -1));
	}
}

void sliceImpl(MDThread* t, MDValue* dest, MDValue* src, MDValue* lo, MDValue* hi)
{
	switch(src.type)
	{
		case MDValue.Type.Array:
			auto arr = src.mArray;
			mdint loIndex = void;
			mdint hiIndex = void;

			if(lo.type == MDValue.Type.Null && hi.type == MDValue.Type.Null)
				return *dest = *src;

			if(!correctIndices(loIndex, hiIndex, lo, hi, arr.slice.length))
			{
				auto hisave = *hi;
				typeString(t, lo);
				typeString(t, &hisave);
				throwException(t, "Attempting to slice an array with indices of type '{}' and '{}'", getString(t, -2), getString(t, -1));
			}

			if(loIndex > hiIndex || loIndex < 0 || loIndex > arr.slice.length || hiIndex < 0 || hiIndex > arr.slice.length)
				throwException(t, "Invalid slice indices [{} .. {}] (array length = {})", loIndex, hiIndex, arr.slice.length);

			return *dest = array.slice(t.vm.alloc, arr, cast(uword)loIndex, cast(uword)hiIndex);

		case MDValue.Type.String:
			auto str = src.mString;
			mdint loIndex = void;
			mdint hiIndex = void;

			if(lo.type == MDValue.Type.Null && hi.type == MDValue.Type.Null)
				return *dest = *src;

			if(!correctIndices(loIndex, hiIndex, lo, hi, str.cpLength))
			{
				auto hisave = *hi;
				typeString(t, lo);
				typeString(t, &hisave);
				throwException(t, "Attempting to slice a string with indices of type '{}' and '{}'", getString(t, -2), getString(t, -1));
			}

			if(loIndex > hiIndex || loIndex < 0 || loIndex > str.cpLength || hiIndex < 0 || hiIndex > str.cpLength)
				throwException(t, "Invalid slice indices [{} .. {}] (string length = {})", loIndex, hiIndex, str.cpLength);

			return *dest = string.slice(t, str, cast(uword)loIndex, cast(uword)hiIndex);

		default:
			if(tryMM!(3, true)(t, MM.Slice, dest, src, lo, hi))
				return;

			typeString(t, src);
			throwException(t, "Attempting to slice a value of type '{}'", getString(t, -1));
	}
}

void sliceaImpl(MDThread* t, MDValue* container, MDValue* lo, MDValue* hi, MDValue* value)
{
	switch(container.type)
	{
		case MDValue.Type.Array:
			auto arr = container.mArray;
			mdint loIndex = void;
			mdint hiIndex = void;
			
			if(!correctIndices(loIndex, hiIndex, lo, hi, arr.slice.length))
			{
				auto hisave = *hi;
				typeString(t, lo);
				typeString(t, &hisave);
				throwException(t, "Attempting to slice-assign an array with indices of type '{}' and '{}'", getString(t, -2), getString(t, -1));
			}

			if(loIndex > hiIndex || loIndex < 0 || loIndex > arr.slice.length || hiIndex < 0 || hiIndex > arr.slice.length)
				throwException(t, "Invalid slice-assign indices [{} .. {}] (array length = {})", loIndex, hiIndex, arr.slice.length);

			if(value.type == MDValue.Type.Array)
			{
				if((hiIndex - loIndex) != value.mArray.slice.length)
					throwException(t, "Array slice-assign lengths do not match (destination is {}, source is {})", hiIndex - loIndex, value.mArray.slice.length);

				return array.sliceAssign(arr, cast(uword)loIndex, cast(uword)hiIndex, value.mArray);
			}
			else
			{
				typeString(t, value);
				throwException(t, "Attempting to slice-assign a value of type '{}' into an array", getString(t, -1));
			}

		default:
			if(tryMM!(4, false)(t, MM.SliceAssign, container, lo, hi, value))
				return;

			typeString(t, container);
			throwException(t, "Attempting to slice-assign a value of type '{}'", getString(t, -1));
	}
}

void binOpImpl(MDThread* t, MM operation, MDValue* dest, MDValue* RS, MDValue* RT)
{
	mdfloat f1 = void;
	mdfloat f2 = void;

	if(RS.type == MDValue.Type.Int)
	{
		if(RT.type == MDValue.Type.Int)
		{
			auto i1 = RS.mInt;
			auto i2 = RT.mInt;

			switch(operation)
			{
				case MM.Add: return *dest = i1 + i2;
				case MM.Sub: return *dest = i1 - i2;
				case MM.Mul: return *dest = i1 * i2;

				case MM.Mod:
					if(i2 == 0)
						throwException(t, "Integer modulo by zero");

					return *dest = i1 % i2;

				case MM.Div:
					if(i2 == 0)
						throwException(t, "Integer divide by zero");

					return *dest = i1 / i2;

				default:
					assert(false);
			}
		}
		else if(RT.type == MDValue.Type.Float)
		{
			f1 = RS.mInt;
			f2 = RT.mFloat;
			goto _float;
		}
	}
	else if(RS.type == MDValue.Type.Float)
	{
		if(RT.type == MDValue.Type.Int)
		{
			f1 = RS.mFloat;
			f2 = RT.mInt;
			goto _float;
		}
		else if(RT.type == MDValue.Type.Float)
		{
			f1 = RS.mFloat;
			f2 = RT.mFloat;

			_float:
			switch(operation)
			{
				case MM.Add: return *dest = f1 + f2;
				case MM.Sub: return *dest = f1 - f2;
				case MM.Mul: return *dest = f1 * f2;
				case MM.Div: return *dest = f1 / f2;
				case MM.Mod: return *dest = f1 % f2;

				default:
					assert(false);
			}
		}
	}

	return commonBinOpMM(t, operation, dest, RS, RT);
}

void commonBinOpMM(MDThread* t, MM operation, MDValue* dest, MDValue* RS, MDValue* RT)
{
	bool swap = false;
	MDClass* proto;

	auto method = getMM(t, RS, operation, proto);

	if(method is null)
	{
		method = getMM(t, RT, MMRev[operation], proto);

		if(method !is null)
			swap = true;
		else
		{
			if(!MMCommutative[operation])
			{
				auto RTsave = *RT;
				typeString(t, RS);
				typeString(t, &RTsave);
				throwException(t, "Cannot perform the arithmetic operation '{}' on a '{}' and a '{}'", MetaNames[operation], getString(t, -2), getString(t, -1));
			}

			method = getMM(t, RS, MMRev[operation], proto);

			if(method is null)
			{
				method = getMM(t, RT, operation, proto);

				if(method is null)
				{
					auto RTsave = *RT;
					typeString(t, RS);
					typeString(t, &RTsave);
					throwException(t, "Cannot perform the arithmetic operation '{}' on a '{}' and a '{}'", MetaNames[operation], getString(t, -2), getString(t, -1));
				}

				swap = true;
			}
		}
	}

	bool shouldLoad = void;
	savePtr(t, dest, shouldLoad);

	auto RSsave = *RS;
	auto RTsave = *RT;

	auto funcSlot = pushFunction(t, method);

	if(swap)
	{
		push(t, RTsave);
		push(t, RSsave);
	}
	else
	{
		push(t, RSsave);
		push(t, RTsave);
	}

	commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 2, proto));
	
	if(shouldLoad)
		loadPtr(t, dest);

	*dest = t.stack[t.stackIndex - 1];
	pop(t);
}

void reflBinOpImpl(MDThread* t, MM operation, MDValue* dest, MDValue* src)
{
	mdfloat f1 = void;
	mdfloat f2 = void;

	if(dest.type == MDValue.Type.Int)
	{
		if(src.type == MDValue.Type.Int)
		{
			auto i2 = src.mInt;

			switch(operation)
			{
				case MM.AddEq: return dest.mInt += i2;
				case MM.SubEq: return dest.mInt -= i2;
				case MM.MulEq: return dest.mInt *= i2;

				case MM.ModEq:
					if(i2 == 0)
						throwException(t, "Integer modulo by zero");

					return dest.mInt %= i2;

				case MM.DivEq:
					if(i2 == 0)
						throwException(t, "Integer divide by zero");

					return dest.mInt /= i2;

				default: assert(false);
			}
		}
		else if(src.type == MDValue.Type.Float)
		{
			f1 = dest.mInt;
			f2 = src.mFloat;
			goto _float;
		}
	}
	else if(dest.type == MDValue.Type.Float)
	{
		if(src.type == MDValue.Type.Int)
		{
			f1 = dest.mFloat;
			f2 = src.mInt;
			goto _float;
		}
		else if(src.type == MDValue.Type.Float)
		{
			f1 = dest.mFloat;
			f2 = src.mFloat;

			_float:
			dest.type = MDValue.Type.Float;

			switch(operation)
			{
				case MM.AddEq: return dest.mFloat = f1 + f2;
				case MM.SubEq: return dest.mFloat = f1 - f2;
				case MM.MulEq: return dest.mFloat = f1 * f2;
				case MM.DivEq: return dest.mFloat = f1 / f2;
				case MM.ModEq: return dest.mFloat = f1 % f2;

				default: assert(false);
			}
		}
	}
	
	if(tryMM!(2, false)(t, operation, dest, src))
		return;

	auto srcsave = *src;
	typeString(t, dest);
	typeString(t, &srcsave);
	throwException(t, "Cannot perform the reflexive arithmetic operation '{}' on a '{}' and a '{}'", MetaNames[operation], getString(t, -2), getString(t, -1));
}

void negImpl(MDThread* t, MDValue* dest, MDValue* src)
{
	if(src.type == MDValue.Type.Int)
		return *dest = -src.mInt;
	else if(src.type == MDValue.Type.Float)
		return *dest = -src.mFloat;
		
	if(tryMM!(1, true)(t, MM.Neg, dest, src))
		return;

	typeString(t, src);
	throwException(t, "Cannot perform negation on a '{}'", getString(t, -1));
}

void binaryBinOpImpl(MDThread* t, MM operation, MDValue* dest, MDValue* RS, MDValue* RT)
{
	if(RS.type == MDValue.Type.Int && RT.type == MDValue.Type.Int)
	{
		switch(operation)
		{
			case MM.And:  return *dest = RS.mInt & RT.mInt;
			case MM.Or:   return *dest = RS.mInt | RT.mInt;
			case MM.Xor:  return *dest = RS.mInt ^ RT.mInt;
			case MM.Shl:  return *dest = RS.mInt << RT.mInt;
			case MM.Shr:  return *dest = RS.mInt >> RT.mInt;
			case MM.UShr: return *dest = RS.mInt >>> RT.mInt;
			default: assert(false);
		}
	}

	return commonBinOpMM(t, operation, dest, RS, RT);
}

void reflBinaryBinOpImpl(MDThread* t, MM operation, MDValue* dest, MDValue* src)
{
	if(dest.type == MDValue.Type.Int && src.type == MDValue.Type.Int)
	{
		switch(operation)
		{
			case MM.AndEq:  return dest.mInt &= src.mInt;
			case MM.OrEq:   return dest.mInt |= src.mInt;
			case MM.XorEq:  return dest.mInt ^= src.mInt;
			case MM.ShlEq:  return dest.mInt <<= src.mInt;
			case MM.ShrEq:  return dest.mInt >>= src.mInt;
			case MM.UShrEq: return dest.mInt >>>= src.mInt;
			default: assert(false);
		}
	}

	if(tryMM!(2, false)(t, operation, dest, src))
		return;

	auto srcsave = *src;
	typeString(t, dest);
	typeString(t, &srcsave);
	throwException(t, "Cannot perform reflexive binary operation '{}' on a '{}' and a '{}'", MetaNames[operation], getString(t, -2), getString(t, -1));
}

void comImpl(MDThread* t, MDValue* dest, MDValue* src)
{
	if(src.type == MDValue.Type.Int)
		return *dest = ~src.mInt;

	if(tryMM!(1, true)(t, MM.Com, dest, src))
		return;

	typeString(t, src);
	throwException(t, "Cannot perform bitwise complement on a '{}'", getString(t, -1));
}

void incImpl(MDThread* t, MDValue* dest)
{
	if(dest.type == MDValue.Type.Int)
		dest.mInt++;
	else if(dest.type == MDValue.Type.Float)
		dest.mFloat++;
	else
	{
		if(tryMM!(1, false)(t, MM.Inc, dest))
			return;

		typeString(t, dest);
		throwException(t, "Cannot increment a '{}'", getString(t, -1));
	}
}

void decImpl(MDThread* t, MDValue* dest)
{
	if(dest.type == MDValue.Type.Int)
		dest.mInt--;
	else if(dest.type == MDValue.Type.Float)
		dest.mFloat--;
	else
	{
		if(tryMM!(1, false)(t, MM.Dec, dest))
			return;

		typeString(t, dest);
		throwException(t, "Cannot decrement a '{}'", getString(t, -1));
	}
}

void catImpl(MDThread* t, MDValue* dest, AbsStack firstSlot, uword num)
{
	auto slot = firstSlot;
	auto endSlot = slot + num;
	auto endSlotm1 = endSlot - 1;
	auto stack = t.stack;

	bool shouldLoad = void;
	savePtr(t, dest, shouldLoad);

	while(slot < endSlotm1)
	{
		MDFunction* method = null;
		MDClass* proto = null;

		switch(stack[slot].type)
		{
			case MDValue.Type.String, MDValue.Type.Char:
				uword len = 0;
				uword idx = slot;

				for(; idx < endSlot; idx++)
				{
					if(stack[idx].type == MDValue.Type.String)
						len += stack[idx].mString.length;
					else if(stack[idx].type == MDValue.Type.Char)
					{
						if(!Utf.isValid(stack[idx].mChar))
							throwException(t, "Attempting to concatenate an invalid character (\\U{:x8})", cast(uint)stack[idx].mChar);

						len += charLen(stack[idx].mChar);
					}
					else
						break;
				}

				if(idx > (slot + 1))
				{
					stringConcat(t, stack[slot], stack[slot + 1 .. idx], len);
					slot = idx - 1;
				}

				if(slot == endSlotm1)
					break; // to exit function

				if(stack[slot + 1].type == MDValue.Type.Array)
					goto array;
				else if(stack[slot + 1].type == MDValue.Type.Instance || stack[slot + 1].type == MDValue.Type.Table)
					goto cat_r;
				else
				{
					typeString(t, &stack[slot + 1]);
					throwException(t, "Can't concatenate 'string/char' and '{}'", getString(t, -1));
				}

			case MDValue.Type.Array:
				array:
				uword idx = slot + 1;
				uword len = stack[slot].type == MDValue.Type.Array ? stack[slot].mArray.slice.length : 1;

				for(; idx < endSlot; idx++)
				{
					if(stack[idx].type == MDValue.Type.Array)
						len += stack[idx].mArray.slice.length;
					else if(stack[idx].type == MDValue.Type.Instance || stack[idx].type == MDValue.Type.Table)
					{
						method = getMM(t, &stack[idx], MM.Cat_r, proto);

						if(method is null)
							len++;
						else
							break;
					}
					else
						len++;
				}

				if(idx > (slot + 1))
				{
					arrayConcat(t, stack[slot .. idx], len);
					slot = idx - 1;
				}

				if(slot == endSlotm1)
					break; // to exit function

				assert(method !is null);
				goto cat_r;

			case MDValue.Type.Instance, MDValue.Type.Table:
				if(stack[slot + 1].type == MDValue.Type.Array)
				{
					method = getMM(t, &stack[slot], MM.Cat, proto);

					if(method is null)
						goto array;
				}

				bool swap = false;

				if(method is null)
				{
					method = getMM(t, &stack[slot], MM.Cat, proto);

					if(method is null)
					{
						if(stack[slot + 1].type != MDValue.Type.Instance && stack[slot + 1].type != MDValue.Type.Table)
						{
							typeString(t, &stack[slot + 1]);
							throwException(t, "Can't concatenate an 'instance/table' with a '{}'", getString(t, -1));
						}

						method = getMM(t, &stack[slot + 1], MM.Cat_r, proto);

						if(method is null)
						{
							typeString(t, &t.stack[slot]);
							typeString(t, &t.stack[slot + 1]);
							throwException(t, "Can't concatenate '{}' and '{}", getString(t, -2), getString(t, -1));
						}

						swap = true;
					}
				}

				auto src1save = stack[slot];
				auto src2save = stack[slot + 1];

				auto funcSlot = pushFunction(t, method);

				if(swap)
				{
					push(t, src2save);
					push(t, src1save);
				}
				else
				{
					push(t, src1save);
					push(t, src2save);
				}

				commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 2, proto));

				// stack might have changed.
				stack = t.stack;

				slot++;
				stack[slot] = stack[t.stackIndex - 1];
				pop(t);
				continue;

			default:
				// Basic
				if(stack[slot + 1].type == MDValue.Type.Array)
					goto array;
				else if(stack[slot + 1].type == MDValue.Type.Instance || stack[slot + 1].type == MDValue.Type.Table)
					goto cat_r;
				else
				{
					typeString(t, &t.stack[slot]);
					typeString(t, &t.stack[slot]);
					throwException(t, "Can't concatenate '{}' and '{}'", getString(t, -2), getString(t, -1));
				}

			cat_r:
				if(method is null)
				{
					method = getMM(t, &stack[slot + 1], MM.Cat_r, proto);

					if(method is null)
					{
						typeString(t, &t.stack[slot + 1]);
						throwException(t, "No implementation of {} for type '{}'", MetaNames[MM.Cat_r], getString(t, -1));
					}
				}

				auto objsave = stack[slot + 1];
				auto valsave = stack[slot];

				auto funcSlot = pushFunction(t, method);
				push(t, objsave);
				push(t, valsave);
				commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 2, proto));

				// stack might have changed.
				stack = t.stack;

				slot++;
				stack[slot] = stack[t.stackIndex - 1];
				pop(t);
				continue;
		}

		break;
	}
	
	if(shouldLoad)
		loadPtr(t, dest);

	*dest = stack[slot];
}

void arrayConcat(MDThread* t, MDValue[] vals, uword len)
{
	if(vals.length == 2 && vals[0].type == MDValue.Type.Array)
	{
		if(vals[1].type == MDValue.Type.Array)
			return vals[1] = array.cat(t.vm.alloc, vals[0].mArray, vals[1].mArray);
		else
			return vals[1] = array.cat(t.vm.alloc, vals[0].mArray, &vals[1]);
	}

	auto ret = array.create(t.vm.alloc, len);

	uword i = 0;

	foreach(ref v; vals)
	{
		if(v.type == MDValue.Type.Array)
		{
			auto a = v.mArray;

			ret.slice[i .. i + a.slice.length] = a.slice[];
			i += a.slice.length;
		}
		else
		{
			ret.slice[i] = v;
			i++;
		}
	}

	vals[$ - 1] = ret;
}

void stringConcat(MDThread* t, MDValue first, MDValue[] vals, uword len)
{
	auto tmpBuffer = t.vm.alloc.allocArray!(char)(len);
	scope(exit) t.vm.alloc.freeArray(tmpBuffer);
	uword i = 0;

	void add(ref MDValue v)
	{
		char[] s = void;

		if(v.type == MDValue.Type.String)
			s = v.mString.toString();
		else
		{
			dchar[1] inbuf = void;
			inbuf[0] = v.mChar;
			char[4] outbuf = void;
			uint ate = 0;
			s = Utf.toString(inbuf, outbuf, &ate);
		}

		tmpBuffer[i .. i + s.length] = s[];
		i += s.length;
	}

	add(first);

	foreach(ref v; vals)
		add(v);

	vals[$ - 1] = createString(t, tmpBuffer);
}

void catEqImpl(MDThread* t, MDValue* dest, AbsStack firstSlot, uword num)
{
	assert(num >= 1);

	auto slot = firstSlot;
	auto endSlot = slot + num;
	auto stack = t.stack;

	switch(dest.type)
	{
		case MDValue.Type.String, MDValue.Type.Char:
			uword len = void;

			if(dest.type == MDValue.Type.Char)
			{
				if(!Utf.isValid(dest.mChar))
					throwException(t, "Attempting to concatenate an invalid character (\\U{:x8})", dest.mChar);

				len = charLen(dest.mChar);
			}
			else
				len = dest.mString.length;

			for(uword idx = slot; idx < endSlot; idx++)
			{
				if(stack[idx].type == MDValue.Type.String)
					len += stack[idx].mString.length;
				else if(stack[idx].type == MDValue.Type.Char)
				{
					if(!Utf.isValid(stack[idx].mChar))
						throwException(t, "Attempting to concatenate an invalid character (\\U{:x8})", cast(uint)stack[idx].mChar);

					len += charLen(stack[idx].mChar);
				}
				else
				{
					typeString(t, &stack[idx]);
					throwException(t, "Can't append a '{}' to a 'string/char'", getString(t, -1));
				}
			}

			auto first = *dest;
			bool shouldLoad = void;
			savePtr(t, dest, shouldLoad);

			stringConcat(t, first, stack[slot .. endSlot], len);

			if(shouldLoad)
				loadPtr(t, dest);

			*dest = stack[endSlot - 1];
			return;

		case MDValue.Type.Array:
			return arrayAppend(t, dest.mArray, stack[slot .. endSlot]);

		case MDValue.Type.Instance, MDValue.Type.Table:
			MDClass* proto;
			auto method = getMM(t, dest, MM.CatEq, proto);

			if(method is null)
			{
				typeString(t, dest);
				throwException(t, "No implementation of {} for type '{}'", MetaNames[MM.CatEq], getString(t, -1));
			}

			bool shouldLoad = void;
			savePtr(t, dest, shouldLoad);

			checkStack(t, t.stackIndex);

			if(shouldLoad)
				loadPtr(t, dest);

			for(auto i = t.stackIndex; i > firstSlot; i--)
				t.stack[i] = t.stack[i - 1];

			t.stack[firstSlot] = *dest;

			t.nativeCallDepth++;
			scope(exit) t.nativeCallDepth--;

			if(callPrologue2(t, method, firstSlot, 0, firstSlot, num + 1, proto))
				execute(t);
			return;

		default:
			typeString(t, dest);
			throwException(t, "Can't append to a value of type '{}'", getString(t, -1));
	}
}

void arrayAppend(MDThread* t, MDArray* a, MDValue[] vals)
{
	uword len = a.slice.length;

	foreach(ref val; vals)
	{
		if(val.type == MDValue.Type.Array)
			len += val.mArray.slice.length;
		else
			len++;
	}

	uword i = a.slice.length;
	array.resize(t.vm.alloc, a, len);

	foreach(ref v; vals)
	{
		if(v.type == MDValue.Type.Array)
		{
			auto arr = v.mArray;
			a.slice[i .. i + arr.slice.length] = arr.slice[];
			i += arr.slice.length;
		}
		else
		{
			a.slice[i] = v;
			i++;
		}
	}
}

void throwImpl(MDThread* t, MDValue* ex, bool rethrowing = false)
{
	auto exSave = *ex;

	if(!rethrowing)
	{
		pushDebugLocStr(t, getDebugLoc(t));
		pushString(t, ": ");

		auto size = stackSize(t);

		try
			toStringImpl(t, exSave, false);
		catch(MDException e)
		{
			catchException(t);
			setStackSize(t, size);
			toStringImpl(t, exSave, true);
		}

		cat(t, 3);

		t.vm.alloc.resizeArray(t.vm.traceback, 0);

		// dup'ing since we're removing the only MiniD reference and handing it off to D
		t.vm.exMsg = getString(t, -1).dup;
		pop(t);
	}

	t.vm.exception = exSave;
	t.vm.isThrowing = true;
	throw new MDException(t.vm.exMsg);
}

void importImpl(MDThread* t, MDString* name, AbsStack dest)
{
	pushGlobal(t, "modules");
	field(t, -1, "load");
	insertAndPop(t, -2);
	pushNull(t);
	pushStringObj(t, name);
	rawCall(t, -3, 1);
	
	assert(isNamespace(t, -1));
	t.stack[dest] = getNamespace(t, -1);
	pop(t);
}

bool asImpl(MDThread* t, MDValue* o, MDValue* p)
{
	if(p.type != MDValue.Type.Class)
	{
		typeString(t, p);
		throwException(t, "Attempting to use 'as' with a '{}' instead of a 'class' as the type", getString(t, -1));
	}

	return o.type == MDValue.Type.Instance && instance.derivesFrom(o.mInstance, p.mClass);
}

MDValue superOfImpl(MDThread* t, MDValue* v)
{
	if(v.type == MDValue.Type.Class)
	{
		if(auto p = v.mClass.parent)
			return MDValue(p);
		else
			return MDValue.nullValue;
	}
	else if(v.type == MDValue.Type.Instance)
		return MDValue(v.mInstance.parent);
	else if(v.type == MDValue.Type.Namespace)
	{
		if(auto p = v.mNamespace.parent)
			return MDValue(p);
		else
			return MDValue.nullValue;
	}
	else
	{
		typeString(t, v);
		throwException(t, "Can only get super of classes, instances, and namespaces, not values of type '{}'", getString(t, -1));
	}

	assert(false);
}

// ============================================================================
// Helper functions

MDValue* lookupGlobal(MDString* name, MDNamespace* env)
{
	if(auto glob = namespace.get(env, name))
		return glob;

	auto ns = env;
	for(; ns.parent !is null; ns = ns.parent){}
	
	return namespace.get(ns, name);
}

void savePtr(MDThread* t, ref MDValue* ptr, out bool shouldLoad)
{
	if(ptr >= t.stack.ptr && ptr < t.stack.ptr + t.stack.length)
	{
		shouldLoad = true;
		ptr = cast(MDValue*)(cast(uword)ptr - cast(uword)t.stack.ptr);
	}
}

void loadPtr(MDThread* t, ref MDValue* ptr)
{
	ptr = cast(MDValue*)(cast(uword)ptr + cast(uword)t.stack.ptr);
}

MDNamespace* getMetatable(MDThread* t, MDValue.Type type)
{
	assert(type >= MDValue.Type.Null && type <= MDValue.Type.WeakRef);
	return t.vm.metaTabs[type];
}

bool correctIndices(out mdint loIndex, out mdint hiIndex, MDValue* lo, MDValue* hi, uword len)
{
	if(lo.type == MDValue.Type.Null)
		loIndex = 0;
	else if(lo.type == MDValue.Type.Int)
	{
		loIndex = lo.mInt;

		if(loIndex < 0)
			loIndex += len;
	}
	else
		return false;

	if(hi.type == MDValue.Type.Null)
		hiIndex = len;
	else if(hi.type == MDValue.Type.Int)
	{
		hiIndex = hi.mInt;

		if(hiIndex < 0)
			hiIndex += len;
	}
	else
		return false;

	return true;
}

uword charLen(dchar c)
{
	dchar[1] inbuf = void;
	inbuf[0] = c;
	char[4] outbuf = void;
	uint ate = 0;
	return Utf.toString(inbuf, outbuf, &ate).length;
}

word pushNamespaceNamestring(MDThread* t, MDNamespace* ns)
{
	uword namespaceName(MDNamespace* ns)
	{
		if(ns.name.cpLength == 0)
			return 0;

		uword n = 0;

		if(ns.parent)
		{
			auto ret = namespaceName(ns.parent);

			if(ret > 0)
			{
				pushChar(t, '.');
				n = ret + 1;
			}
		}

		pushStringObj(t, ns.name);
		n++;

		return n;
	}

	auto x = namespaceName(ns);
	
	if(x == 0)
		return pushString(t, "");
	else
		return cat(t, x);
}

word typeString(MDThread* t, MDValue* v)
{
	switch(v.type)
	{
		case MDValue.Type.Null,
			MDValue.Type.Bool,
			MDValue.Type.Int,
			MDValue.Type.Float,
			MDValue.Type.Char,
			MDValue.Type.String,
			MDValue.Type.Table,
			MDValue.Type.Array,
			MDValue.Type.Function,
			MDValue.Type.Namespace,
			MDValue.Type.Thread,
			MDValue.Type.WeakRef:
			
			return pushString(t, MDValue.typeString(v.type));

		case MDValue.Type.Class:
			// LEAVE ME UP HERE PLZ, don't inline, thx.
			auto n = v.mClass.name.toString();
			return pushFormat(t, "{} {}", MDValue.typeString(MDValue.Type.Class), n);

		case MDValue.Type.Instance:
			// don't inline me either.
			auto n = v.mInstance.parent.name.toString();
			return pushFormat(t, "{} of {}", MDValue.typeString(MDValue.Type.Instance), n);

		case MDValue.Type.NativeObj:
			pushString(t, MDValue.typeString(MDValue.Type.NativeObj));
			pushChar(t, ' ');

			if(auto o = v.mNativeObj.obj)
				pushString(t, o.classinfo.name);
			else
				pushString(t, "(??? null)");

			return cat(t, 3);

		default: assert(false);
	}
}

// ============================================================================
// Coroutines

version(MDExtendedCoro)
{
	class ThreadFiber : Fiber
	{
		MDThread* t;
		uword numParams;

		this(MDThread* t, uword numParams)
		{
			super(&run, 16384); // TODO: provide the stack size as a user-settable value
			this.t = t;
			this.numParams = numParams;
		}

		void run()
		{
			assert(t.state == MDThread.State.Initial);

			pushFunction(t, t.coroFunc);
			insert(t, 1);

			if(callPrologue(t, cast(AbsStack)1, -1, numParams, null))
				execute(t);
		}
	}
}

void yieldImpl(MDThread* t, AbsStack firstValue, word numReturns, word numValues)
{
	auto ar = pushAR(t);

	assert(t.arIndex > 1);
	*ar = t.actRecs[t.arIndex - 2];

	ar.func = null;
	ar.returnSlot = firstValue;
	ar.numReturns = numReturns;
	ar.firstResult = 0;
	ar.numResults = 0;

	if(numValues == -1)
		t.numYields = t.stackIndex - firstValue;
	else
	{
		t.stackIndex = firstValue + numValues;
		t.numYields = numValues;
	}

	t.state = MDThread.State.Suspended;

	version(MDExtendedCoro)
	{
		Fiber.yield();
		t.state = MDThread.State.Running;
		t.vm.curThread = t;
		callEpilogue(t, true);
	}
}

uword resume(MDThread* t, uword numParams)
{
	try
	{
		version(MDExtendedCoro)
		{
			if(t.state == MDThread.State.Initial)
			{
				if(t.coroFiber is null)
					t.coroFiber = nativeobj.create(t.vm, new ThreadFiber(t, numParams));
				else
				{
					auto f = cast(ThreadFiber)cast(void*)t.coroFiber.obj;
					f.t = t;
					f.numParams = numParams;
				}
			}

			t.getFiber().call();
		}
		else
		{
			if(t.state == MDThread.State.Initial)
			{
				pushFunction(t, t.coroFunc);
				insert(t, 1);
				auto result = callPrologue(t, cast(AbsStack)1, -1, numParams, null);
				assert(result == true, "resume callPrologue must return true");
				execute(t);
			}
			else
			{
				callEpilogue(t, true);
				execute(t, t.savedCallDepth);
			}
		}
	}
	catch(MDHaltException e)
	{
		assert(t.arIndex == 0);
		assert(t.upvalHead is null);
		assert(t.resultIndex == 0);
		assert(t.trIndex == 0);
		assert(t.nativeCallDepth == 0);
	}

	return t.numYields;
}

// ============================================================================
// Interpreter State

ActRecord* pushAR(MDThread* t)
{
	if(t.arIndex >= t.actRecs.length)
		t.vm.alloc.resizeArray(t.actRecs, t.actRecs.length * 2);

	t.currentAR = &t.actRecs[t.arIndex];
	t.arIndex++;
	return t.currentAR;
}

void popAR(MDThread* t)
{
	t.arIndex--;
	t.currentAR.func = null;
	t.currentAR.proto = null;

	if(t.arIndex > 0)
	{
		t.currentAR = &t.actRecs[t.arIndex - 1];
		t.stackBase = t.currentAR.base;
	}
	else
	{
		t.currentAR = null;
		t.stackBase = 0;
	}
}

TryRecord* pushTR(MDThread* t)
{
	if(t.trIndex >= t.tryRecs.length)
		t.vm.alloc.resizeArray(t.tryRecs, t.tryRecs.length * 2);

	t.currentTR = &t.tryRecs[t.trIndex];
	t.trIndex++;
	return t.currentTR;
}

protected final void popTR(MDThread* t)
{
	t.trIndex--;

	if(t.trIndex > 0)
		t.currentTR = &t.tryRecs[t.trIndex - 1];
	else
		t.currentTR = null;
}

void close(MDThread* t, AbsStack index)
{
	auto base = &t.stack[index];

	for(auto uv = t.upvalHead; uv !is null && uv.value >= base; uv = t.upvalHead)
	{
		t.upvalHead = uv.nextuv;
		uv.closedValue = *uv.value;
		uv.value = &uv.closedValue;
	}
}

MDUpval* findUpvalue(MDThread* t, uword num)
{
	auto slot = &t.stack[t.currentAR.base + num];
	auto puv = &t.upvalHead;

	for(auto uv = *puv; uv !is null && uv.value >= slot; puv = &uv.nextuv, uv = *puv)
		if(uv.value is slot)
			return uv;

	auto ret = t.vm.alloc.allocate!(MDUpval)();
	ret.value = slot;
	ret.nextuv = *puv;
	*puv = ret;
	return ret;
}

// ============================================================================
// Debugging

Location getDebugLoc(MDThread* t)
{
	if(t.currentAR is null || t.currentAR.func is null)
		return Location(createString(t, "<no location available>"), 0, Location.Type.Unknown);
	else
	{
		pushNamespaceNamestring(t, t.currentAR.func.environment);

		if(getString(t, -1) == "")
			dup(t);
		else
			pushChar(t, '.');

		pushStringObj(t, t.currentAR.func.name);

		cat(t, 3);
		auto s = getStringObj(t, -1);
		pop(t);

		if(t.currentAR.func.isNative)
			return Location(s, 0, Location.Type.Native);
		else
			return Location(s, getDebugLine(t), Location.Type.Script);
	}
}

void pushDebugLocStr(MDThread* t, Location loc)
{
	if(loc.col == Location.Type.Unknown)
		pushString(t, "<no location available>");
	else
	{
		pushStringObj(t, loc.file);

		if(loc.col == Location.Type.Native)
		{
			pushString(t, "(native)");
			cat(t, 2);
		}
		else
		{
			pushChar(t, '(');

			if(loc.line == -1)
				pushChar(t, '?');
			else
				pushFormat(t, "{}", loc.line);
				
			pushChar(t, ')');

			cat(t, 4);
		}
	}
}

void callHook(MDThread* t, MDThread.Hook hook)
{
	if(!t.hooksEnabled || !t.hookFunc)
		return;

	auto savedTop = t.stackIndex;
	t.hooksEnabled = false;

	pushFunction(t, t.hookFunc);
	pushThread(t, t);

	switch(hook)
	{
		case MDThread.Hook.Call:    pushString(t, "call"); break;
		case MDThread.Hook.Ret:     pushString(t, "ret"); break;
		case MDThread.Hook.TailRet: pushString(t, "tailret"); break;
		case MDThread.Hook.Delay:   pushString(t, "delay"); break;
		case MDThread.Hook.Line:    pushString(t, "line"); break;
		default: assert(false);
	}

	try
		rawCall(t, -3, 0);
	finally
	{
		t.hooksEnabled = true;
		t.stackIndex = savedTop;
	}
}

void callReturnHooks(MDThread* t)
{
	if(!t.hooksEnabled)
		return;

	callHook(t, MDThread.Hook.Ret);

	if(!t.currentAR.func.isNative)
	{
		while(t.currentAR.numTailcalls > 0)
		{
			t.currentAR.numTailcalls--;
			callHook(t, MDThread.Hook.TailRet);
		}
	}
}

// ============================================================================
// Main interpreter loop

void execute(MDThread* t, uword depth = 1)
{
	MDException currentException = null;
	bool rethrowingException = false;
	MDValue RS;
	MDValue RT;

	_exceptionRetry:
	t.state = MDThread.State.Running;
	t.vm.curThread = t;

	_reentry:
	auto stackBase = t.stackBase;
	auto constTable = t.currentAR.func.scriptFunc.constants;
	auto env = t.currentAR.func.environment;
	auto upvals = t.currentAR.func.scriptUpvals();
	auto pc = &t.currentAR.pc;

	try
	{
		MDValue* get(uint index)
		{
			switch(index & Instruction.locMask)
			{
				case Instruction.locLocal:
					assert((stackBase + (index & ~Instruction.locMask)) < t.stack.length, "invalid based stack index");
					return &t.stack[stackBase + (index & ~Instruction.locMask)];

				case Instruction.locConst:
					return &constTable[index & ~Instruction.locMask];

				case Instruction.locUpval:
					return upvals[index & ~Instruction.locMask].value;

				default:
					assert((index & Instruction.locMask) == Instruction.locGlobal, "get() location");

					auto name = constTable[index & ~Instruction.locMask].mString;

					if(auto glob = namespace.get(env, name))
						return glob;

					auto ns = env;
					for(; ns.parent !is null; ns = ns.parent){}

					if(auto glob = namespace.get(ns, name))
						return glob;

					throwException(t, "Attempting to get nonexistent global '{}'", name.toString());
			}

			assert(false);
		}

		const char[] GetRD = "((i.rd & 0x8000) == 0) ? (&t.stack[stackBase + (i.rd & ~Instruction.locMask)]) : get(i.rd)";
		const char[] GetRDplus1 = "(((i.rd + 1) & 0x8000) == 0) ? (&t.stack[stackBase + ((i.rd + 1) & ~Instruction.locMask)]) : get(i.rd + 1)";
		const char[] GetRS = "((i.rs & 0x8000) == 0) ? (((i.rs & 0x4000) == 0) ? (&t.stack[stackBase + (i.rs & ~Instruction.locMask)]) : (&constTable[i.rs & ~Instruction.locMask])) : (get(i.rs))";
		const char[] GetRT = "((i.rt & 0x8000) == 0) ? (((i.rt & 0x4000) == 0) ? (&t.stack[stackBase + (i.rt & ~Instruction.locMask)]) : (&constTable[i.rt & ~Instruction.locMask])) : (get(i.rt))";

		Instruction* oldPC = null;

		_interpreterLoop: while(true)
		{
			if(t.shouldHalt)
				throw new MDHaltException;

// 			Instruction* i = t.currentAR.pc++;
			pc = &t.currentAR.pc;
			Instruction* i = (*pc)++;

			if(t.hooksEnabled)
			{
				if(t.hooks & MDThread.Hook.Delay)
				{
					assert(t.hookCounter > 0);
					t.hookCounter--;

					if(t.hookCounter == 0)
					{
						t.hookCounter = t.hookDelay;
						callHook(t, MDThread.Hook.Delay);
					}
				}

				if(t.hooks & MDThread.Hook.Line)
				{
					auto curPC = t.currentAR.pc - 1;

					// when oldPC is null, it means we've either just started executing this func,
					// or we've come back from a yield, or we've just caught an exception, or something
					// like that.
					// When curPC < oldPC, we've jumped back, like to the beginning of a loop.

					if(curPC is t.currentAR.func.scriptFunc.code.ptr || curPC < oldPC || pcToLine(t.currentAR, curPC) != pcToLine(t.currentAR, curPC - 1))
						callHook(t, MDThread.Hook.Line);
				}
			}

// 			oldPC = t.currentAR.pc;
			oldPC = *pc;

			switch(i.opcode)
			{
				// Binary Arithmetic
				case Op.Add: binOpImpl(t, MM.Add, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Sub: binOpImpl(t, MM.Sub, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Mul: binOpImpl(t, MM.Mul, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Div: binOpImpl(t, MM.Div, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Mod: binOpImpl(t, MM.Mod, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;

				// Unary Arithmetic
				case Op.Neg: negImpl(t, mixin(GetRD), mixin(GetRS)); break;

				// Reflexive Arithmetic
				case Op.AddEq: reflBinOpImpl(t, MM.AddEq, mixin(GetRD), mixin(GetRS)); break;
				case Op.SubEq: reflBinOpImpl(t, MM.SubEq, mixin(GetRD), mixin(GetRS)); break;
				case Op.MulEq: reflBinOpImpl(t, MM.MulEq, mixin(GetRD), mixin(GetRS)); break;
				case Op.DivEq: reflBinOpImpl(t, MM.DivEq, mixin(GetRD), mixin(GetRS)); break;
				case Op.ModEq: reflBinOpImpl(t, MM.ModEq, mixin(GetRD), mixin(GetRS)); break;

				// Inc/Dec
				case Op.Inc: incImpl(t, mixin(GetRD)); break;
				case Op.Dec: decImpl(t, mixin(GetRD)); break;

				// Binary Bitwise
				case Op.And:  binaryBinOpImpl(t, MM.And,  mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Or:   binaryBinOpImpl(t, MM.Or,   mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Xor:  binaryBinOpImpl(t, MM.Xor,  mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Shl:  binaryBinOpImpl(t, MM.Shl,  mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.Shr:  binaryBinOpImpl(t, MM.Shr,  mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;
				case Op.UShr: binaryBinOpImpl(t, MM.UShr, mixin(GetRD), mixin(GetRS), mixin(GetRT)); break;

				// Unary Bitwise
				case Op.Com: comImpl(t, mixin(GetRD), mixin(GetRS)); break;

				// Reflexive Bitwise
				case Op.AndEq:  reflBinaryBinOpImpl(t, MM.AndEq,  mixin(GetRD), mixin(GetRS)); break;
				case Op.OrEq:   reflBinaryBinOpImpl(t, MM.OrEq,   mixin(GetRD), mixin(GetRS)); break;
				case Op.XorEq:  reflBinaryBinOpImpl(t, MM.XorEq,  mixin(GetRD), mixin(GetRS)); break;
				case Op.ShlEq:  reflBinaryBinOpImpl(t, MM.ShlEq,  mixin(GetRD), mixin(GetRS)); break;
				case Op.ShrEq:  reflBinaryBinOpImpl(t, MM.ShrEq,  mixin(GetRD), mixin(GetRS)); break;
				case Op.UShrEq: reflBinaryBinOpImpl(t, MM.UShrEq, mixin(GetRD), mixin(GetRS)); break;

				// Data Transfer
				case Op.Move: *mixin(GetRD) = *mixin(GetRS); break;
				case Op.MoveLocal: t.stack[stackBase + i.rd] = t.stack[stackBase + i.rs]; break;
				case Op.LoadConst: t.stack[stackBase + i.rd] = constTable[i.rs & ~Instruction.locMask]; break;

				case Op.LoadBool: *mixin(GetRD) = cast(bool)i.rs; break;
				case Op.LoadNull: *mixin(GetRD) = MDValue.nullValue; break;

				case Op.LoadNulls:
					auto start = stackBase + i.rd;
					t.stack[start .. start + i.imm] = MDValue.nullValue;
					break;

				case Op.NewGlobal:
					auto name = constTable[i.rt & ~Instruction.locMask].mString;

					if(namespace.contains(env, name))
						throwException(t, "Attempting to create global '{}' that already exists", name.toString());

					namespace.set(t.vm.alloc, env, name, mixin(GetRS));
					break;

				// Logical and Control Flow
				case Op.Import:
					RS = *mixin(GetRS);

					if(RS.type != MDValue.Type.String)
					{
						typeString(t, &RS);
						throwException(t, "Import expression must be a string value, not '{}'", getString(t, -1));
					}

					importImpl(t, RS.mString, stackBase + i.rd);
					break;

				case Op.Not: *mixin(GetRD) = mixin(GetRS).isFalse(); break;

				case Op.Cmp:
// 					auto jump = *t.currentAR.pc++;
					auto jump = (*pc)++;

					auto cmpValue = compareImpl(t, mixin(GetRS), mixin(GetRT));

					if(jump.rd)
					{
						switch(jump.opcode)
						{
// 							case Op.Je:  if(cmpValue == 0) t.currentAR.pc += jump.imm; break;
// 							case Op.Jle: if(cmpValue <= 0) t.currentAR.pc += jump.imm; break;
// 							case Op.Jlt: if(cmpValue < 0)  t.currentAR.pc += jump.imm; break;
							case Op.Je:  if(cmpValue == 0) (*pc) += jump.imm; break;
							case Op.Jle: if(cmpValue <= 0) (*pc) += jump.imm; break;
							case Op.Jlt: if(cmpValue < 0)  (*pc) += jump.imm; break;
							default: assert(false, "invalid 'cmp' jump");
						}
					}
					else
					{
						switch(jump.opcode)
						{
// 							case Op.Je:  if(cmpValue != 0) t.currentAR.pc += jump.imm; break;
// 							case Op.Jle: if(cmpValue > 0)  t.currentAR.pc += jump.imm; break;
// 							case Op.Jlt: if(cmpValue >= 0) t.currentAR.pc += jump.imm; break;
							case Op.Je:  if(cmpValue != 0) (*pc) += jump.imm; break;
							case Op.Jle: if(cmpValue > 0)  (*pc) += jump.imm; break;
							case Op.Jlt: if(cmpValue >= 0) (*pc) += jump.imm; break;
							default: assert(false, "invalid 'cmp' jump");
						}
					}
					break;

				case Op.Equals:
// 					auto jump = *t.currentAR.pc++;
					auto jump = (*pc)++;

					auto cmpValue = equalsImpl(t, mixin(GetRS), mixin(GetRT));

					if(cmpValue == cast(bool)jump.rd)
// 						t.currentAR.pc += jump.imm;
						(*pc) += jump.imm;
					break;

				case Op.Cmp3:
					// Doing this to ensure evaluation of mixin(GetRD) happens _after_ compareImpl has executed
					auto val = compareImpl(t, mixin(GetRS), mixin(GetRT));
					*mixin(GetRD) = val;
					break;

				case Op.SwitchCmp:
// 					auto jump = *t.currentAR.pc++;
					auto jump = (*pc)++;
					assert(jump.opcode == Op.Je && jump.rd == 1, "invalid 'swcmp' jump");

					if(switchCmpImpl(t, mixin(GetRS), mixin(GetRT)))
// 						t.currentAR.pc += jump.imm;
						(*pc) += jump.imm;

					break;

				case Op.Is:
// 					auto jump = *t.currentAR.pc++;
					auto jump = (*pc)++;
					assert(jump.opcode == Op.Je, "invalid 'is' jump");

					if(mixin(GetRS).opEquals(*mixin(GetRT)) == jump.rd)
// 						t.currentAR.pc += jump.imm;
						(*pc) += jump.imm;

					break;

				case Op.IsTrue:
// 					auto jump = *t.currentAR.pc++;
					auto jump = (*pc)++;
					assert(jump.opcode == Op.Je, "invalid 'istrue' jump");

					if(mixin(GetRS).isFalse() != cast(bool)jump.rd)
// 						t.currentAR.pc += jump.imm;
						(*pc) += jump.imm;

					break;

				case Op.Jmp:
					if(i.rd != 0)
// 						t.currentAR.pc += i.imm;
						(*pc) += i.imm;
					break;

				case Op.Switch:
					auto st = &t.currentAR.func.scriptFunc.switchTables[i.rt];

					if(auto ptr = st.offsets.lookup(*mixin(GetRS)))
// 						t.currentAR.pc += *ptr;
						(*pc) += *ptr;
					else
					{
						if(st.defaultOffset == -1)
							throwException(t, "Switch without default");

// 						t.currentAR.pc += st.defaultOffset;
						(*pc) += st.defaultOffset;
					}
					break;

				case Op.Close: close(t, stackBase + i.rd); break;

				case Op.For:
					auto idx = &t.stack[stackBase + i.rd];
					auto hi = idx + 1;
					auto step = hi + 1;

					if(idx.type != MDValue.Type.Int || hi.type != MDValue.Type.Int || step.type != MDValue.Type.Int)
						throwException(t, "Numeric for loop low, high, and step values must be integers");

					auto intIdx = idx.mInt;
					auto intHi = hi.mInt;
					auto intStep = step.mInt;

					if(intStep == 0)
						throwException(t, "Numeric for loop step value may not be 0");

					if(intIdx > intHi && intStep > 0 || intIdx < intHi && intStep < 0)
						intStep = -intStep;

					if(intStep < 0)
						*idx = intIdx + intStep;

					*step = intStep;
// 					t.currentAR.pc += i.imm;
					(*pc) += i.imm;
					break;

				case Op.ForLoop:
					auto idx = t.stack[stackBase + i.rd].mInt;
					auto hi = t.stack[stackBase + i.rd + 1].mInt;
					auto step = t.stack[stackBase + i.rd + 2].mInt;

					if(step > 0)
					{
						if(idx < hi)
						{
							t.stack[stackBase + i.rd + 3] = idx;
							t.stack[stackBase + i.rd] = idx + step;
// 							t.currentAR.pc += i.imm;
							(*pc) += i.imm;
						}
					}
					else
					{
						if(idx >= hi)
						{
							t.stack[stackBase + i.rd + 3] = idx;
							t.stack[stackBase + i.rd] = idx + step;
// 							t.currentAR.pc += i.imm;
							(*pc) += i.imm;
						}
					}
					break;

				case Op.Foreach:
					auto rd = i.rd;
					auto src = &t.stack[stackBase + rd];

					if(src.type != MDValue.Type.Function && src.type != MDValue.Type.Thread)
					{
						MDClass* proto;
						auto method = getMM(t, src, MM.Apply, proto);

						if(method is null)
						{
							typeString(t, src);
							throwException(t, "No implementation of {} for type '{}'", MetaNames[MM.Apply], getString(t, -1));
						}

						t.stack[stackBase + rd + 2] = t.stack[stackBase + rd + 1];
						t.stack[stackBase + rd + 1] = *src;
						t.stack[stackBase + rd] = method;

						t.stackIndex = stackBase + rd + 3;
						commonCall(t, stackBase + rd, 3, callPrologue(t, stackBase + rd, 3, 3, proto));
						t.stackIndex = t.currentAR.savedTop;

						src = &t.stack[stackBase + rd];

						if(src.type != MDValue.Type.Function && src.type != MDValue.Type.Thread)
						{
							typeString(t, src);
							throwException(t, "Invalid iterable type '{}' returned from opApply", getString(t, -1));
						}
					}

					if(src.type == MDValue.Type.Thread && src.mThread.state != MDThread.State.Initial)
						throwException(t, "Attempting to iterate over a thread that is not in the 'initial' state");

// 					t.currentAR.pc += i.imm;
					(*pc) += i.imm;
					break;

				case Op.ForeachLoop:
// 					auto jump = *t.currentAR.pc++;
					auto jump = (*pc)++;
					assert(jump.opcode == Op.Je && jump.rd == 1, "invalid 'foreachloop' jump");

					auto rd = i.rd;
					auto funcReg = rd + 3;
					auto src = &t.stack[stackBase + rd];

					t.stack[stackBase + funcReg + 2] = t.stack[stackBase + rd + 2];
					t.stack[stackBase + funcReg + 1] = t.stack[stackBase + rd + 1];
					t.stack[stackBase + funcReg] = t.stack[stackBase + rd];

					t.stackIndex = stackBase + funcReg + 3;
					rawCall(t, funcReg, i.imm);
					t.stackIndex = t.currentAR.savedTop;

					if(src.type == MDValue.Type.Function)
					{
						if(t.stack[stackBase + funcReg].type != MDValue.Type.Null)
						{
							t.stack[stackBase + rd + 2] = t.stack[stackBase + funcReg];
// 							t.currentAR.pc += i.imm;
							(*pc) += jump.imm;
						}
					}
					else
					{
						if(src.mThread.state != MDThread.State.Dead)
// 							t.currentAR.pc += i.imm;
							(*pc) += jump.imm;
					}
					break;

				// Exception Handling
				case Op.PushCatch:
					auto tr = pushTR(t);
					tr.isCatch = true;
					tr.slot = cast(RelStack)i.rd;
// 					tr.pc = t.currentAR.pc + i.imm;
					tr.pc = (*pc) + i.imm;
					tr.actRecord = t.arIndex;
					break;

				case Op.PushFinally:
					auto tr = pushTR(t);
					tr.isCatch = false;
					tr.slot = cast(RelStack)i.rd;
// 					tr.pc = t.currentAR.pc + i.imm;
					tr.pc = (*pc) + i.imm;
					tr.actRecord = t.arIndex;
					break;

				case Op.PopCatch: popTR(t); break;

				case Op.PopFinally:
					currentException = null;
					popTR(t);
					break;

				case Op.EndFinal:
					if(currentException !is null)
					{
						rethrowingException = true;
						throw currentException;
					}

					if(t.currentAR.unwindReturn !is null)
						goto _commonEHUnwind;

					break;

				case Op.Throw:
					rethrowingException = cast(bool)i.rt;
					throwImpl(t, mixin(GetRS), rethrowingException);
					break;

				// Function Calling
			{
				bool isScript = void;
				word numResults = void;

				case Op.Method, Op.MethodNC, Op.SuperMethod:
// 					auto call = *t.currentAR.pc++;
					auto call = (*pc)++;

					RT = *mixin(GetRT);

					if(RT.type != MDValue.Type.String)
					{
						typeString(t, &RT);
						throwException(t, "Attempting to get a method with a non-string name (type '{}' instead)", getString(t, -1));
					}

					auto methodName = RT.mString;
					auto self = mixin(GetRS);

					if(i.opcode != Op.SuperMethod)
						RS = *self;
					else
					{
						if(t.currentAR.proto is null)
							throwException(t, "Attempting to perform a supercall in a function where there is no super class");

						if(self.type != MDValue.Type.Instance && self.type != MDValue.Type.Class)
						{
							typeString(t, self);
							throwException(t, "Attempting to perform a supercall in a function where 'this' is a '{}', not an 'instance' or 'class'", getString(t, -1));
						}

						RS = t.currentAR.proto;
					}

					numResults = call.rt - 1;
					uword numParams = void;

					if(call.rs == 0)
						numParams = t.stackIndex - (stackBase + i.rd + 1);
					else
					{
						numParams = call.rs - 1;
						t.stackIndex = stackBase + i.rd + call.rs;
					}

					isScript = commonMethodCall(t, stackBase + i.rd, self, &RS, methodName, numResults, numParams, i.opcode == Op.MethodNC);

					if(call.opcode == Op.Call)
						goto _commonCall;
					else
						goto _commonTailcall;

				case Op.Call:
					numResults = i.rt - 1;
					uword numParams = void;

					if(i.rs == 0)
						numParams = t.stackIndex - (stackBase + i.rd + 1);
					else
					{
						numParams = i.rs - 1;
						t.stackIndex = stackBase + i.rd + i.rs;
					}

					auto self = &t.stack[stackBase + i.rd + 1];
					MDClass* proto = void;

					if(self.type == MDValue.Type.Instance)
						proto = self.mInstance.parent;
					else if(self.type == MDValue.Type.Class)
						proto = self.mClass;
					else
						proto = null;

					isScript = callPrologue(t, stackBase + i.rd, numResults, numParams, proto);

					// fall through
				_commonCall:
					maybeGC(t);

					if(isScript)
					{
						depth++;
						goto _reentry;
					}
					else
					{
						if(numResults >= 0)
							t.stackIndex = t.currentAR.savedTop;
					}
					break;

				case Op.Tailcall:
					numResults = i.rt - 1;
					uword numParams = void;

					if(i.rs == 0)
						numParams = t.stackIndex - (stackBase + i.rd + 1);
					else
					{
						numParams = i.rs - 1;
						t.stackIndex = stackBase + i.rd + i.rs;
					}

					auto self = &t.stack[stackBase + i.rd + 1];
					MDClass* proto = void;

					if(self.type == MDValue.Type.Instance)
						proto = self.mInstance.parent;
					else if(self.type == MDValue.Type.Class)
						proto = self.mClass;
					else
						proto = null;

					isScript = callPrologue(t, stackBase + i.rd, numResults, numParams, proto);

					// fall through
				_commonTailcall:
					maybeGC(t);

					if(isScript)
					{
						auto prevAR = t.currentAR - 1;
						close(t, prevAR.base);

						auto diff = cast(ptrdiff_t)(t.currentAR.returnSlot - prevAR.returnSlot);

						auto tc = prevAR.numTailcalls + 1;
						t.currentAR.numReturns = prevAR.numReturns;
						*prevAR = *t.currentAR;
						prevAR.numTailcalls = tc;
						prevAR.base -= diff;
						prevAR.savedTop -= diff;
						prevAR.vargBase -= diff;
						prevAR.returnSlot -= diff;

						popAR(t);

						//memmove(&t.stack[prevAR.returnSlot], &t.stack[prevAR.returnSlot + diff], (prevAR.savedTop - prevAR.returnSlot) * MDValue.sizeof);

						for(auto idx = prevAR.returnSlot; idx < prevAR.savedTop; idx++)
							t.stack[idx] = t.stack[idx + diff];

						goto _reentry;
					}

					// Do nothing for native calls.  The following return instruction will catch it.
					break;
			}
				
				case Op.SaveRets:
					auto firstResult = stackBase + i.rd;

					if(i.imm == 0)
					{
						saveResults(t, t, firstResult, t.stackIndex - firstResult);
						t.stackIndex = t.currentAR.savedTop;
					}
					else
						saveResults(t, t, firstResult, i.imm - 1);
					break;

				case Op.Ret:
					unwindEH(t);
					close(t, stackBase);
					callEpilogue(t, true);

					depth--;

					if(depth == 0)
						return;

					goto _reentry;

				case Op.Unwind:
// 					t.currentAR.unwindReturn = t.currentAR.pc;
					t.currentAR.unwindReturn = (*pc);
					t.currentAR.unwindCounter = i.uimm;

					// fall through
				_commonEHUnwind:
					while(t.currentAR.unwindCounter > 0)
					{
						assert(t.trIndex > 0);
						assert(t.currentTR.actRecord is t.arIndex);

						auto tr = *t.currentTR;
						popTR(t);
						close(t, t.stackBase + tr.slot);
						t.currentAR.unwindCounter--;

						if(!tr.isCatch)
						{
							// finally in the middle of an unwind
// 							t.currentAR.pc = tr.pc;
							(*pc) = tr.pc;
							continue _interpreterLoop;
						}
					}

// 					t.currentAR.pc = t.currentAR.unwindReturn;
					(*pc) = t.currentAR.unwindReturn;
					t.currentAR.unwindReturn = null;
					break;

				case Op.Vararg:
					auto numVarargs = stackBase - t.currentAR.vargBase;
					auto dest = stackBase + i.rd;

					uword numNeeded = void;

					if(i.uimm == 0)
					{
						numNeeded = numVarargs;
						t.stackIndex = dest + numVarargs;
						checkStack(t, t.stackIndex);
					}
					else
						numNeeded = i.uimm - 1;

					auto src = t.currentAR.vargBase;
					
					if(numNeeded <= numVarargs)
						memmove(&t.stack[dest], &t.stack[src], numNeeded * MDValue.sizeof);
					else
					{
						memmove(&t.stack[dest], &t.stack[src], numVarargs * MDValue.sizeof);
						t.stack[dest + numVarargs .. dest + numNeeded] = MDValue.nullValue;
					}

					break;

				case Op.VargLen: *mixin(GetRD) = cast(mdint)(stackBase - t.currentAR.vargBase); break;

				case Op.VargIndex:
					auto numVarargs = stackBase - t.currentAR.vargBase;

					RS = *mixin(GetRS);

					if(RS.type != MDValue.Type.Int)
					{
						typeString(t, &RS);
						throwException(t, "Attempting to index 'vararg' with a '{}'", getString(t, -1));
					}

					auto index = RS.mInt;

					if(index < 0)
						index += numVarargs;

					if(index < 0 || index >= numVarargs)
						throwException(t, "Invalid 'vararg' index: {} (only have {})", index, numVarargs);

					*mixin(GetRD) = t.stack[t.currentAR.vargBase + cast(uword)index];
					break;

				case Op.VargIndexAssign:
					auto numVarargs = stackBase - t.currentAR.vargBase;

					RS = *mixin(GetRS);

					if(RS.type != MDValue.Type.Int)
					{
						typeString(t, &RS);
						throwException(t, "Attempting to index 'vararg' with a '{}'", getString(t, -1));
					}

					auto index = RS.mInt;

					if(index < 0)
						index += numVarargs;

					if(index < 0 || index >= numVarargs)
						throwException(t, "Invalid 'vararg' index: {} (only have {})", index, numVarargs);

					t.stack[t.currentAR.vargBase + cast(uword)index] = *mixin(GetRT);
					break;

				case Op.VargSlice:
					auto numVarargs = stackBase - t.currentAR.vargBase;
					
					mdint lo = void;
					mdint hi = void;
					
					auto loSrc = mixin(GetRD);
					auto hiSrc = mixin(GetRDplus1);

					if(!correctIndices(lo, hi, loSrc, hiSrc, numVarargs))
					{
						typeString(t, loSrc);
						typeString(t, hiSrc);
						throwException(t, "Attempting to slice 'vararg' with '{}' and '{}'", getString(t, -2), getString(t, -1));
					}

					if(lo > hi || lo < 0 || lo > numVarargs || hi < 0 || hi > numVarargs)
						throwException(t, "Invalid vararg slice indices [{} .. {}]", lo, hi);

					auto sliceSize = cast(uword)(hi - lo);
					auto src = t.currentAR.vargBase + cast(uword)lo;
					auto dest = stackBase + cast(uword)i.rd;

					uword numNeeded = void;

					if(i.uimm == 0)
					{
						numNeeded = sliceSize;
						t.stackIndex = dest + sliceSize;
						checkStack(t, t.stackIndex);
					}
					else
						numNeeded = i.uimm - 1;

					if(numNeeded <= sliceSize)
						memmove(&t.stack[dest], &t.stack[src], numNeeded * MDValue.sizeof);
					else
					{
						memmove(&t.stack[dest], &t.stack[src], sliceSize * MDValue.sizeof);
						t.stack[dest + sliceSize .. dest + numNeeded] = MDValue.nullValue;
					}
					break;

				case Op.Yield:
					if(t is t.vm.mainThread)
						throwException(t, "Attempting to yield out of the main thread");

					version(MDExtendedCoro)
					{
						yieldImpl(t, stackBase + i.rd, i.rt - 1, i.rs - 1);
						break;
					}
					else
					{
						if(t.nativeCallDepth > 0)
							throwException(t, "Attempting to yield across native / metamethod call boundary");

						t.savedCallDepth = depth;
						yieldImpl(t, stackBase + i.rd, i.rt - 1, i.rs - 1);
						return;
					}

				case Op.CheckParams:
					auto val = &t.stack[stackBase];

					foreach(idx, mask; t.currentAR.func.scriptFunc.paramMasks)
					{
						if(!(mask & (1 << val.type)))
						{
							typeString(t, val);

							if(idx == 0)
								throwException(t, "'this' parameter: type '{}' is not allowed", getString(t, -1));
							else
								throwException(t, "Parameter {}: type '{}' is not allowed", idx, getString(t, -1));
						}

						val++;
					}
					break;

				case Op.CheckObjParam:
					RS = t.stack[stackBase + i.rs];
					
					if(RS.type != MDValue.Type.Instance)
						*mixin(GetRD) = true;
					else
					{
						RT = *mixin(GetRT);

						if(RT.type != MDValue.Type.Class)
						{
							typeString(t, &RT);
							throwException(t, "Parameter {}: instance type constraint type must be 'class', not '{}'", i.rs, getString(t, -1));
						}

						*mixin(GetRD) = instance.derivesFrom(RS.mInstance, RT.mClass);
					}
					break;

				case Op.ObjParamFail:
					typeString(t, &t.stack[stackBase + i.rs]);

					if(i.rs == 0)
						throwException(t, "'this' parameter: type '{}' is not allowed", getString(t, -1));
					else
						throwException(t, "Parameter {}: type '{}' is not allowed", i.rs, getString(t, -1));
						
					break;

				// Array and List Operations
				case Op.Length: lenImpl(t, mixin(GetRD), mixin(GetRS)); break;
				case Op.LengthAssign: lenaImpl(t, mixin(GetRD), mixin(GetRS)); break;
				case Op.Append: array.append(t.vm.alloc, t.stack[stackBase + i.rd].mArray, mixin(GetRS)); break;

				case Op.SetArray:
					auto sliceBegin = stackBase + i.rd + 1;
					auto a = t.stack[stackBase + i.rd].mArray;

					if(i.rs == 0)
					{
						array.setBlock(t.vm.alloc, a, i.rt, t.stack[sliceBegin .. t.stackIndex]);
						t.stackIndex = t.currentAR.savedTop;
					}
					else
						array.setBlock(t.vm.alloc, a, i.rt, t.stack[sliceBegin .. sliceBegin + i.rs - 1]);

					break;

				case Op.Cat:
					catImpl(t, mixin(GetRD), stackBase + i.rs, i.rt);
					maybeGC(t);
					break;

				case Op.CatEq:
					catEqImpl(t, mixin(GetRD), stackBase + i.rs, i.rt);
					maybeGC(t);
					break;

				case Op.Index: idxImpl(t, mixin(GetRD), mixin(GetRS), mixin(GetRT), false); break;
				case Op.IndexAssign: idxaImpl(t, mixin(GetRD), mixin(GetRS), mixin(GetRT), false); break;

				case Op.Field:
					RT = *mixin(GetRT);

					if(RT.type != MDValue.Type.String)
					{
						typeString(t, &RT);
						throwException(t, "Field name must be a string, not a '{}'", getString(t, -1));
					}

					fieldImpl(t, mixin(GetRD), mixin(GetRS), RT.mString, false);
					break;

				case Op.FieldAssign:
					RS = *mixin(GetRS);

					if(RS.type != MDValue.Type.String)
					{
						typeString(t, &RS);
						throwException(t, "Field name must be a string, not a '{}'", getString(t, -1));
					}

					fieldaImpl(t, mixin(GetRD), RS.mString, mixin(GetRT), false);
					break;

				case Op.Slice:
					auto base = &t.stack[stackBase + i.rs];
					sliceImpl(t, mixin(GetRD), base, base + 1, base + 2);
					break;

				case Op.SliceAssign:
					auto base = &t.stack[stackBase + i.rd];
					sliceaImpl(t, base, base + 1, base + 2, mixin(GetRS));
					break;

				case Op.NotIn:
					auto val = !inImpl(t, mixin(GetRS), mixin(GetRT));
					*mixin(GetRD) = val;
					break;

				case Op.In:
					auto val = inImpl(t, mixin(GetRS), mixin(GetRT));
					*mixin(GetRD) = val;
					break;

				// Value Creation
				case Op.NewArray:
					t.stack[stackBase + i.rd] = array.create(t.vm.alloc, i.uimm);
					maybeGC(t);
					break;

				case Op.NewTable:
					t.stack[stackBase + i.rd] = table.create(t.vm.alloc);
					maybeGC(t);
					break;

				case Op.Closure:
					auto newDef = t.currentAR.func.scriptFunc.innerFuncs[i.rs];

					auto funcEnv = env;

					if(i.rt != 0)
						funcEnv = t.stack[stackBase + i.rt].mNamespace;

					if(newDef.isPure)
					{
						if(newDef.cachedFunc is null)
							newDef.cachedFunc = func.create(t.vm.alloc, funcEnv, newDef);

						*mixin(GetRD) = newDef.cachedFunc;
					}
					else
					{
						auto n = func.create(t.vm.alloc, funcEnv, newDef);
						auto newUpvals = n.scriptUpvals();

						for(uword index = 0; index < newDef.numUpvals; index++)
						{
// 							assert(t.currentAR.pc.opcode == Op.Move, "invalid closure upvalue op");
							assert((*pc).opcode == Op.Move, "invalid closure upvalue op");

// 							if(t.currentAR.pc.rd)
							if((*pc).rd == 0)
// 								newUpvals[index] = findUpvalue(t, t.currentAR.pc.rs);
								newUpvals[index] = findUpvalue(t, (*pc).rs);
							else
							{
// 								assert(t.currentAR.pc.rd == 1, "invalid closure upvalue rd");
								assert((*pc).rd == 1, "invalid closure upvalue rd");
// 								newUpvals[index] = upvals[t.currentAR.pc.uimm];
								newUpvals[index] = upvals[(*pc).uimm];
							}

// 							t.currentAR.pc++;
							(*pc)++;
						}

						*mixin(GetRD) = n;
					}

					maybeGC(t);
					break;

				case Op.Class:
					RS = *mixin(GetRS);
					RT = *mixin(GetRT);

					if(RT.type != MDValue.Type.Class)
					{
						typeString(t, &RT);
						throwException(t, "Attempting to derive a class from a value of type '{}'", getString(t, -1));
					}
					else
						*mixin(GetRD) = classobj.create(t.vm.alloc, RS.mString, RT.mClass);

					maybeGC(t);
					break;

				case Op.Coroutine:
					RS = *mixin(GetRS);

					if(RS.type != MDValue.Type.Function)
					{
						typeString(t, &RS);
						throwException(t, "Coroutines must be created with a function, not '{}'", getString(t, -1));
					}

					version(MDExtendedCoro) {} else
					{
						if(RS.mFunction.isNative)
							throwException(t, "Native functions may not be used as the body of a coroutine");
					}

					auto nt = thread.create(t.vm, RS.mFunction);
					nt.hookFunc = t.hookFunc;
					nt.hooks = t.hooks;
					nt.hookDelay = t.hookDelay;
					nt.hookCounter = t.hookCounter;
					*mixin(GetRD) = nt;
					break;

				case Op.Namespace:
					auto name = constTable[i.rs].mString;
					RT = *mixin(GetRT);

					if(RT.type == MDValue.Type.Null)
						*mixin(GetRD) = namespace.create(t.vm.alloc, name);
					else if(RT.type != MDValue.Type.Namespace)
					{
						typeString(t, &RT);
						pushStringObj(t, name);
						throwException(t, "Attempted to use a '{}' as a parent namespace for namespace '{}'", getString(t, -2), getString(t, -1));
					}
					else
						*mixin(GetRD) = namespace.create(t.vm.alloc, name, RT.mNamespace);

					maybeGC(t);
					break;

				case Op.NamespaceNP:
					auto tmp = namespace.create(t.vm.alloc, constTable[i.rs].mString, env);
					*mixin(GetRD) = tmp;
					maybeGC(t);
					break;

				// Class stuff
				case Op.As:
					RS = *mixin(GetRS);

					if(asImpl(t, &RS, mixin(GetRT)))
						*mixin(GetRD) = RS;
					else
						*mixin(GetRD) = MDValue.nullValue;

					break;

				case Op.SuperOf:
					*mixin(GetRD) = superOfImpl(t, mixin(GetRS));
					break;

				case Op.Je:
				case Op.Jle:
				case Op.Jlt:
					assert(false, "lone conditional jump instruction");

				default:
					throwException(t, "Unimplemented opcode \"{}\"", i);
			}
		}
	}
	catch(MDException e)
	{
		t.currentAR.unwindCounter = 0;
		t.currentAR.unwindReturn = null;

		while(depth > 0)
		{
			if(t.trIndex > 0 && t.currentTR.actRecord is t.arIndex)
			{
				auto tr = *t.currentTR;
				popTR(t);

				auto base = t.stackBase + tr.slot;
				close(t, base);

				// remove any results that may have been saved
				loadResults(t);

				if(rethrowingException)
					rethrowingException = false;
				else
					t.vm.traceback.append(&t.vm.alloc, getDebugLoc(t));

				if(tr.isCatch)
				{
					t.stack[base] = t.vm.exception;
					t.vm.exception = MDValue.nullValue;
					t.vm.isThrowing = false;
					currentException = null;

					t.stack[base + 1 .. t.stackIndex] = MDValue.nullValue;
					t.currentAR.pc = tr.pc;
					goto _exceptionRetry;
				}
				else
				{
					currentException = e;
					t.currentAR.pc = tr.pc;
					goto _exceptionRetry;
				}
			}

			if(rethrowingException)
				rethrowingException = false;
			else if(t.currentAR && t.currentAR.func !is null)
			{
				t.vm.traceback.append(&t.vm.alloc, getDebugLoc(t));

				// as far as I can reason, it would be impossible to have tailcalls AND have rethrowingException == true, since you can't do a tailcall in a try block.
				if(t.currentAR.numTailcalls > 0)
				{
					pushFormat(t, "<{} tailcalls>", t.currentAR.numTailcalls);
					t.vm.traceback.append(&t.vm.alloc, Location(getStringObj(t, -1), -1, Location.Type.Script));
					pop(t);
				}
			}

			close(t, t.stackBase);
			callEpilogue(t, false);
			depth--;
		}

		throw e;
	}
	catch(MDHaltException e)
	{
		while(depth > 0)
		{
			close(t, t.stackBase);
			callEpilogue(t, false);
			depth--;
		}

		unwindEH(t);
		throw e;
	}
}