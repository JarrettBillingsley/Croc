/******************************************************************************
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
import tango.core.Thread;
import tango.core.Vararg;
import tango.stdc.string;
import Utf = tango.text.convert.Utf;

import minid.array;
import minid.func;
import minid.gc;
import minid.namespace;
import minid.nativeobj;
import minid.obj;
import minid.opcodes;
import minid.string;
import minid.table;
import minid.thread;
import minid.types;
import minid.utils;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

/**
Gets the current coroutine state of the thread as a member of the MDThread.State enumeration.
*/
public MDThread.State state(MDThread* t)
{
	return t.state;
}

/**
Gets a string representation of the current coroutine state of the thread.

The string returned is not on the MiniD heap, it's just a string literal.
*/
public dchar[] stateString(MDThread* t)
{
	return MDThread.StateStrings[t.state];
}

/**
Gets the VM that the thread is associated with.
*/
public MDVM* getVM(MDThread* t)
{
	return t.vm;
}

/**
These push a value of the given type onto the stack.

Returns:
	The stack index of the newly-pushed value.
*/
public nint pushNull(MDThread* t)
{
	return push(t, MDValue.nullValue);
}

/// ditto
public nint pushBool(MDThread* t, bool v)
{
	return push(t, MDValue(v));
}

/// ditto
public nint pushInt(MDThread* t, mdint v)
{
	return push(t, MDValue(v));
}

/// ditto
public nint pushFloat(MDThread* t, mdfloat v)
{
	return push(t, MDValue(v));
}

/// ditto
public nint pushChar(MDThread* t, dchar v)
{
	return push(t, MDValue(v));
}

/// ditto
public nint pushString(MDThread* t, dchar[] v)
{
	return pushStringObj(t, string.create(t.vm, v));
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
public nint pushFormat(MDThread* t, dchar[] fmt, ...)
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
public nint pushVFormat(MDThread* t, dchar[] fmt, TypeInfo[] arguments, va_list argptr)
{
	size_t numPieces = 0;

	uint sink(dchar[] data)
	{
		pushString(t, data);
		numPieces++;
		return data.length;
	}

	t.vm.formatter.convert(&sink, arguments, argptr, fmt);
	maybeGC(t.vm);
	return cat(t, numPieces);
}

/**
Creates a new table object and pushes it onto the stack.

Params:
	size = The number of slots to preallocate in the table, as an optimization.

Returns:
	The stack index of the newly-created table.
*/
public nint newTable(MDThread* t, size_t size = 0)
{
	maybeGC(t.vm);
	return pushTable(t, table.create(t.vm.alloc, size));
}

/**
Creates a new array object and pushes it onto the stack.

Params:
	length = The length of the new array.

Returns:
	The stack index of the newly-created array.
*/
public nint newArray(MDThread* t, size_t length)
{
	maybeGC(t.vm);
	return pushArray(t, array.create(t.vm.alloc, length));
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
public nint newFunction(MDThread* t, NativeFunc func, dchar[] name, size_t numUpvals = 0)
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
public nint newFunctionWithEnv(MDThread* t, NativeFunc func, dchar[] name, size_t numUpvals = 0)
{
	checkNumParams(t, numUpvals + 1);

	auto env = getNamespace(t, -1);

	if(env is null)
	{
		pushTypeString(t, -1);
		throwException(t, "newFunctionWithEnv - Environment must be a namespace, not a '{}'", getString(t, -1));
	}

	maybeGC(t.vm);

	auto f = .func.create(t.vm.alloc, env, string.create(t.vm, name), func, numUpvals);
	f.nativeUpvals()[] = getLocals(t)[$ - 1 - numUpvals .. $ - 1];
	pop(t, numUpvals + 1); // upvals and env.

	return pushFunction(t, f);
}

/**
Creates a new object and pushes it onto the stack.

MiniD objects can have two kinds of extra data associated with them for use by the host: extra
MiniD values and arbitrary bytes.  The structure of a MiniD object is something like this:

-----
// ---------
// |       |
// |       | The data that's part of every object - the fields, proto, name, and attributes.
// |       |
// +-------+
// |0: "x" | Extra MiniD values which can point into the MiniD heap.
// |1: 5   |
// +-------+
// |...    | Arbitrary byte data.
// ---------
-----

Both extra sections are optional, and no objects created by scripts will have them.

Extra MiniD values are useful for adding "members" to the object which are not visible to the
scripts but which can still hold MiniD objects.  They will be scanned by the GC, so objects
referenced by these members will not be collected.  If you want to hold a reference to a native
D object, for instance, this would be the place to put it (wrapped in a NativeObject).

The arbitrary bytes associated with an object are not scanned by either the D or the MiniD GC,
so don'_t store references to GC'ed objects there.  These bytes are useable for just about anything,
such as storing values which can'_t be stored in MiniD values -- structs, complex numbers, long
integers, whatever.

You can store references to $(B heap) objects in the extra bytes, but you must not store references
to $(B GC'ed) objects there.  That is, you can 'malloc' some data and store the pointer in the
extra bytes, since that's not GC'ed memory.  You must however perform your own memory management for
such memory.  You can set up a finalizer function for objects in which you can perform memory management
for these references.

Params:
	proto = The stack index of the _proto object.  The _proto can be `null`, in which case Object (defined
		in the base library and which lives in the global namespace) will be used.  Otherwise it must
		be an object.
	name = The _name of the new object.  If this parameter is null or the empty string, the _name will
		be taken from the _proto.
	numValues = How many extra MiniD values will be associated with the object.  See above.
	extraBytes = How many extra bytes to attach to the object.  See above.

Returns:
	The stack index of the newly-created object.
*/
public nint newObject(MDThread* t, nint proto, dchar[] name = null, size_t numValues = 0, size_t extraBytes = 0)
{
	MDObject* p = void;

	if(isNull(t, proto))
	{
		pushGlobal(t, "Object");
		p = getObject(t, -1);

		if(p is null)
		{
			pushTypeString(t, -1);
			throwException(t, "newObject - 'Object' is not an object; it is a '{}'!", getString(t, -1));
		}

		pop(t);
	}
	else if(auto o = getObject(t, proto))
		p = o;
	else
	{
		pushTypeString(t, proto);
		throwException(t, "newObject - Proto must be null or object", getString(t, -1));
	}

	MDString* n = void;

	if(name.ptr is null || name.length == 0)
		n = p.name;
	else
		n = string.create(t.vm, name);

	maybeGC(t.vm);
	return pushObject(t, obj.create(t.vm.alloc, n, p, numValues, extraBytes));
}

public nint newObject(MDThread* t, dchar[] name = null, size_t numValues = 0, size_t extraBytes = 0)
{
	pushGlobal(t, "Object");
	auto p = getObject(t, -1);

	if(p is null)
	{
		pushTypeString(t, -1);
		throwException(t, "newObject - 'Object' is not an object; it is a '{}'!", getString(t, -1));
	}

	pop(t);

	MDString* n = void;

	if(name.ptr is null || name.length == 0)
		n = p.name;
	else
		n = string.create(t.vm, name);

	maybeGC(t.vm);
	return pushObject(t, obj.create(t.vm.alloc, n, p, numValues, extraBytes));
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
public nint newNamespace(MDThread* t, dchar[] name)
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
public nint newNamespace(MDThread* t, nint parent, dchar[] name)
{
	MDNamespace* p = void;

	if(isNull(t, parent))
		p = null;
	else if(auto ns = getNamespace(t, parent))
		p = ns;
	else
	{
		pushTypeString(t, parent);
		throwException(t, "newNamespace - Parent must be null or namespace, not '{}'", getString(t, -1));
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
public nint newNamespaceNoParent(MDThread* t, dchar[] name)
{
	maybeGC(t.vm);
	return pushNamespace(t, namespace.create(t.vm.alloc, string.create(t.vm, name), null));
}

/**
Creates a new thread object (coroutine) and pushes it onto the stack.

Params:
	func = The slot which contains the function to be used as the coroutine's body.
		This can be either a MiniD or native function.

Returns:
	The stack index of the newly-created thread.
*/
public nint newThread(MDThread* t, nint func)
{
	auto f = getFunction(t, func);

	if(f is null)
	{
		pushTypeString(t, func);
		throwException(t, "newThread - Thread function must be of type 'function', not '{}'", getString(t, -1));
	}

	maybeGC(t.vm);

	return pushThread(t, thread.create(t.vm, f));
}

/**
Push the given thread onto this thread's stack.

Params:
	o = The thread to push.
	
Returns:
	The stack index of the newly-pushed value.
*/
public nint pushThread(MDThread* t, MDThread* o)
{
	return push(t, MDValue(o));
}

/**
Push a reference to a native (D) object onto the stack.

Params:
	o = The object to push.

Returns:
	The index of the newly-pushed value.
*/
public nint pushNativeObj(MDThread* t, Object o)
{
	maybeGC(t.vm);
	return push(t, MDValue(nativeobj.create(t.vm, o)));
}

/**
Duplicate a value at the given stack index and push it onto the stack.

Params:
	slot = The _slot to duplicate.  Defaults to -1, which means the top of the stack.

Returns:
	The stack index of the newly-pushed _slot.
*/
public nint dup(MDThread* t, nint slot = -1)
{
	auto s = fakeToAbs(t, slot);
	auto ret = pushNull(t);
	t.stack[t.stackIndex - 1] = t.stack[s];
	return ret;
}

/**
Insert the value at the top of the stack into the given _slot, shifting up the values in that _slot
and everything after it up by a _slot.  This means the stack will stay the same size.  Similar to a
"rotate" operation common to many stack machines.

Throws an error if 'slot' corresponds to the 'this' parameter.  'this' can never be modified.

If 'slot' corresponds to the top-of-stack (but not 'this'), this function is a no-op.

Params:
	slot = The _slot in which the value at the top will be inserted.  If this refers to the top of the
		stack, this function does nothing.
*/
public void insert(MDThread* t, nint slot)
{
	checkNumParams(t, 1);
	auto s = fakeToAbs(t, slot);

	if(s == t.stackBase)
		throwException(t, "insert - Cannot use 'this' as the destination");

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
public void insertAndPop(MDThread* t, nint slot)
{
	checkNumParams(t, 1);
	auto s = fakeToAbs(t, slot);

	if(s == t.stackBase)
		throwException(t, "insert - Cannot use 'this' as the destination");

	if(s == t.stackIndex - 1)
		return;

	t.stack[s] = t.stack[t.stackIndex - 1];
	t.stackIndex = s + 1;
}

/**
Pop a number of items off the stack.  Throws an error if you try to pop more items than there are
on the stack.  'this' is not counted; so if there is 'this' and one value, and you try to pop 2
values, an error is thrown.

Params:
	n = The number of items to _pop.  Defaults to 1.  Must be greater than 0.
*/
public void pop(MDThread* t, size_t n = 1)
{
	assert(n > 0);

	if(n > (t.stackIndex - (t.stackBase + 1)))
		throwException(t, "pop - Stack underflow");

	t.stackIndex -= n;
}

/**
Given an index, returns the absolute index that corresponds to it.  This is useful for converting
relative (negative) indices to indices that will never change.  If the index is already absolute,
just returns it.  Throws an error if the index is out of range.
*/
public nint absIndex(MDThread* t, nint idx)
{
	return cast(nint)fakeToRel(t, idx);
}

/**
Sees if a given stack index (negative or positive) is valid.  Valid positive stack indices range
from [0 .. stackSize(t)$(RPAREN).  Valid negative stack indices range from [-stackSize(t) .. 0$(RPAREN).

*/
public bool isValidIndex(MDThread* t, nint idx)
{
	if(idx < 0)
		return idx >= -stackSize(t);
	else
		return idx < stackSize(t);
}

/**
Calls the object at the given _slot.  The parameters (including 'this') are assumed to be all the
values after that _slot to the top of the stack.

The 'this' parameter is, according to the language specification, null if no explicit context is given.
You must still push this null value, however.

An example of calling a function:

-----
// Let's translate `x = f(5, "hi")` into API calls.

// 1. Push the function (or any callable object -- like objects, threads).
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
public size_t rawCall(MDThread* t, nint slot, nint numReturns)
{
	auto absSlot = fakeToAbs(t, slot);
	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwException(t, "rawCall - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwException(t, "rawCall - invalid number of returns (must be >= -1)");

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
public size_t methodCall(MDThread* t, nint slot, dchar[] name, nint numReturns, bool customThis = false)
{
	auto absSlot = fakeToAbs(t, slot);
	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwException(t, "methodCall - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwException(t, "methodCall - invalid number of returns (must be >= -1)");

	auto self = &t.stack[absSlot];
	auto methodName = string.create(t.vm, name);

	auto tmp = commonMethodCall(t, absSlot, self, self, methodName, numReturns, numParams, customThis);
	return commonCall(t, absSlot, numReturns, tmp);
}

/**
Same as above, but expects the name of the method to be on top of the stack (after the parameters).

The parameters and return value are the same as above.
*/
public size_t methodCall(MDThread* t, nint slot, nint numReturns, bool customThis = false)
{
	checkNumParams(t, 1);
	auto absSlot = fakeToAbs(t, slot);

	if(!isString(t, -1))
	{
		pushTypeString(t, -1);
		throwException(t, "methodCall - Method name must be a string, not a '{}'", getString(t, -1));
	}

	auto methodName = t.stack[t.stackIndex - 1].mString;
	pop(t);

	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwException(t, "methodCall - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwException(t, "methodCall - invalid number of returns (must be >= -1)");

	auto self = &t.stack[absSlot];

	auto tmp = commonMethodCall(t, absSlot, self, self, methodName, numReturns, numParams, customThis);
	return commonCall(t, absSlot, numReturns, tmp);
}

/**
Performs a super call.  This function will only work if the currently-executing function was called as
a method of a value of type 'object'.

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
public size_t superCall(MDThread* t, nint slot, dchar[] name, nint numReturns)
{
	// Invalid call?
	if(t.arIndex == 0 || t.currentAR.proto is null)
		throwException(t, "superCall - Attempting to perform a supercall in a function where there is no super object");

	// Get num params
	auto absSlot = fakeToAbs(t, slot);
	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwException(t, "superCall - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwException(t, "superCall - invalid number of returns (must be >= -1)");

	// Get this
	auto _this = &t.stack[t.stackBase];

	if(_this.type != MDValue.Type.Object)
	{
		pushTypeString(t, 0);
		throwException(t, "superCall - Attempting to perform a supercall in a function where 'this' is a '{}', not an 'object'", getString(t, -1));
	}

	// Do the call
	auto methodName = string.create(t.vm, name);
	auto ret = commonMethodCall(t, absSlot, _this, &MDValue(t.currentAR.proto), methodName, numReturns, numParams, false);
	return commonCall(t, absSlot, numReturns, ret);
}

/**
Same as above, but expects the method name to be at the top of the stack (after the parameters).

The parameters and return value are the same as above.
*/
public size_t superCall(MDThread* t, nint slot, nint numReturns)
{
	// Get the method name
	checkNumParams(t, 1);
	auto absSlot = fakeToAbs(t, slot);

	if(!isString(t, -1))
	{
		pushTypeString(t, -1);
		throwException(t, "superCall - Method name must be a string, not a '{}'", getString(t, -1));
	}

	auto methodName = t.stack[t.stackIndex - 1].mString;
	pop(t);

	// Invalid call?
	if(t.arIndex == 0 || t.currentAR.proto is null)
		throwException(t, "superCall - Attempting to perform a supercall in a function where there is no super object");

	// Get num params
	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwException(t, "superCall - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwException(t, "superCall - invalid number of returns (must be >= -1)");

	// Get this
	auto _this = &t.stack[t.stackBase];

	if(_this.type != MDValue.Type.Object)
	{
		pushTypeString(t, 0);
		throwException(t, "superCall - Attempting to perform a supercall in a function where 'this' is a '{}', not an 'object'", getString(t, -1));
	}

	// Do the call
	auto ret = commonMethodCall(t, absSlot, _this, &MDValue(t.currentAR.proto), methodName, numReturns, numParams, false);
	return commonCall(t, absSlot, numReturns, ret);
}

/**
Sets an upvalue in the currently-executing closure.  The upvalue is set to the value on top of the
stack, which is popped.

This function will fail if called at top-level (that is, outside of any executing closures).

Params:
	idx = The index of the upvalue to set.
*/
public void setUpval(MDThread* t, size_t idx)
{
	if(t.arIndex == 0)
		throwException(t, "setUpval - No function to set upvalue (can't call this function at top level)");

	checkNumParams(t, 1);

	auto upvals = t.currentAR.func.nativeUpvals();

	if(idx >= upvals.length)
		throwException(t, "setUpval - Invalid upvalue index ({}, only have {})", idx, upvals.length);

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
public nint getUpval(MDThread* t, size_t idx)
{
	if(t.arIndex == 0)
		throwException(t, "getUpval - No function to get upvalue (can't call this function at top level)");

	assert(t.currentAR.func.isNative, "getUpval used on a non-native func");

	auto upvals = t.currentAR.func.nativeUpvals();

	if(idx >= upvals.length)
		throwException(t, "getUpval - Invalid upvalue index ({}, only have {})", idx, upvals.length);

	return push(t, upvals[idx]);
}

/**
Sees if the value at the given _slot is null.
*/
public bool isNull(MDThread* t, nint slot)
{
	return type(t, slot) == MDValue.Type.Null;
}

/**
Sees if the value at the given _slot is a bool.
*/
public bool isBool(MDThread* t, nint slot)
{
	return type(t, slot) == MDValue.Type.Bool;
}

/**
Sees if the value at the given _slot is an int.
*/
public bool isInt(MDThread* t, nint slot)
{
	return type(t, slot) == MDValue.Type.Int;
}

/**
Sees if the value at the given _slot is a float.
*/
public bool isFloat(MDThread* t, nint slot)
{
	return type(t, slot) == MDValue.Type.Float;
}

/**
Sees if the value at the given _slot is an int or a float.
*/
public bool isNum(MDThread* t, nint slot)
{
	auto type = type(t, slot);
	return type == MDValue.Type.Int || type == MDValue.Type.Float;
}

/**
Sees if the value at the given _slot is a char.
*/
public bool isChar(MDThread* t, nint slot)
{
	return type(t, slot) == MDValue.Type.Char;
}

/**
Sees if the value at the given _slot is a string.
*/
public bool isString(MDThread* t, nint slot)
{
	return type(t, slot) == MDValue.Type.String;
}

/**
Sees if the value at the given _slot is a table.
*/
public bool isTable(MDThread* t, nint slot)
{
	return type(t, slot) == MDValue.Type.Table;
}

/**
Sees if the value at the given _slot is an array.
*/
public bool isArray(MDThread* t, nint slot)
{
	return type(t, slot) == MDValue.Type.Array;
}

/**
Sees if the value at the given _slot is a function.
*/
public bool isFunction(MDThread* t, nint slot)
{
	return type(t, slot) == MDValue.Type.Function;
}

/**
Sees if the value at the given _slot is an object.
*/
public bool isObject(MDThread* t, nint slot)
{
	return type(t, slot) == MDValue.Type.Object;
}

/**
Sees if the value at the given _slot is a namespace.
*/
public bool isNamespace(MDThread* t, nint slot)
{
	return type(t, slot) == MDValue.Type.Namespace;
}

/**
Sees if the value at the given _slot is a thread.
*/
public bool isThread(MDThread* t, nint slot)
{
	return type(t, slot) == MDValue.Type.Thread;
}

/**
Sees if the value at the given _slot is a native object.
*/
public bool isNativeObj(MDThread* t, nint slot)
{
	return type(t, slot) == MDValue.Type.NativeObj;
}

/**
Gets the truth value of the value at the given _slot.  null, false, integer 0, floating point 0.0,
and character '\0' are considered false; everything else is considered true.  This is the same behavior
as within the language.
*/
public bool isTrue(MDThread* t, nint slot)
{
	return !getValue(t, slot).isFalse();
}

/**
Gets the _type of the value at the given _slot.
*/
public MDValue.Type type(MDThread* t, nint slot)
{
	return getValue(t, slot).type;
}

/**
Pushes the string representation of the type of the value at the given _slot.

Returns:
	The stack index of the newly-pushed string.
*/
public nint pushTypeString(MDThread* t, nint slot)
{
	return typeString(t, getValue(t, slot));
}

/**
Returns the boolean value at the given _slot, or throws an error if it isn'_t one.
*/
public bool getBool(MDThread* t, nint slot)
{
	auto v = getValue(t, slot);

	if(v.type != MDValue.Type.Bool)
	{
		pushTypeString(t, slot);
		throwException(t, "getBool - expected 'bool' but got '{}'", getString(t, -1));
	}

	return v.mBool;
}

/**
Returns the integer value at the given _slot, or throws an error if it isn'_t one.
*/
public mdint getInt(MDThread* t, nint slot)
{
	auto v = getValue(t, slot);

	if(v.type != MDValue.Type.Int)
	{
		pushTypeString(t, slot);
		throwException(t, "getInt - expected 'int' but got '{}'", getString(t, -1));
	}

	return v.mInt;
}

/**
Returns the float value at the given _slot, or throws an error if it isn'_t one.
*/
public mdfloat getFloat(MDThread* t, nint slot)
{
	auto v = getValue(t, slot);

	if(v.type != MDValue.Type.Float)
	{
		pushTypeString(t, slot);
		throwException(t, "getFloat - expected 'float' but got '{}'", getString(t, -1));
	}

	return v.mFloat;
}

/**
Returns the character value at the given _slot, or throws an error if it isn'_t one.
*/
public dchar getChar(MDThread* t, nint slot)
{
	auto v = getValue(t, slot);

	if(v.type != MDValue.Type.Char)
	{
		pushTypeString(t, slot);
		throwException(t, "getChar - expected 'char' but got '{}'", getString(t, -1));
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
public dchar[] getString(MDThread* t, nint slot)
{
	auto v = getValue(t, slot);

	if(v.type != MDValue.Type.String)
	{
		pushTypeString(t, slot);
		throwException(t, "getString - expected 'string' but got '{}'", getString(t, -1));
	}

	return v.mString.toString32();
}

/**
Returns the native D object at the given _slot, or throws an error if it isn'_t one.
*/
public Object getNativeObj(MDThread* t, nint slot)
{
	auto v = getValue(t, slot);

	if(v.type != MDValue.Type.NativeObj)
	{
		pushTypeString(t, slot);
		throwException(t, "getNativeObj - expected 'nativeobj' but got '{}'", getString(t, -1));
	}

	return v.mNativeObj.obj;
}

/**
Finds out how many extra values an object has (see newObject for info on that).  Throws an error
if the value at the given _slot isn'_t an object.

Params:
	slot = The stack index of the object whose number of values is to be retrieved.

Returns:
	The number of extra values associated with the given object.
*/
public size_t numExtraVals(MDThread* t, nint slot)
{
	if(auto o = getObject(t, slot))
		return o.numValues;
	else
	{
		pushTypeString(t, slot);
		throwException(t, "numExtraVals - expected 'object' but got '{}'", getString(t, -1));
	}
		
	assert(false);
}

/**
Pushes the idx th extra value from the object at the given _slot.  Throws an error if the value at
the given _slot isn'_t an object, or if the index is out of bounds.

Params:
	slot = The object whose value is to be retrieved.
	idx = The index of the extra value to get.

Returns:
	The stack index of the newly-pushed value.
*/
public nint pushExtraVal(MDThread* t, nint slot, size_t idx)
{
	if(auto o = getObject(t, slot))
	{
		if(idx > o.numValues)
			throwException(t, "pushExtraVal - Value index out of bounds ({}, but only have {})", idx, o.numValues);

		return push(t, o.extraValues()[idx]);
	}
	else
	{
		pushTypeString(t, slot);
		throwException(t, "pushExtraVal - expected 'object' but got '{}'", getString(t, -1));
	}
		
	assert(false);
}

/**
Pops the value off the top of the stack and places it in the idx th extra value in the object at the
given _slot.  Throws an error if the value at the given _slot isn'_t an object, or if the index is out
of bounds.

Params:
	slot = The object whose value is to be set.
	idx = The index of the extra value to set.
*/
public void setExtraVal(MDThread* t, nint slot, size_t idx)
{
	checkNumParams(t, 1);

	if(auto o = getObject(t, slot))
	{
		if(idx > o.numValues)
			throwException(t, "setExtraVal - Value index out of bounds ({}, but only have {})", idx, o.numValues);

		o.extraValues()[idx] = t.stack[t.stackIndex - 1];
		pop(t);
	}
	else
	{
		pushTypeString(t, slot);
		throwException(t, "setExtraVal - expected 'object' but got '{}'", getString(t, -1));
	}
}

/**
Gets a void array of the extra bytes associated with the object at the given _slot.  If the object has
no extra bytes, returns null.  Throws an error if the value at the given _slot isn'_t an object.

The returned void array points into the MiniD heap, so you should not store the returned reference
anywhere.

Params:
	slot = The object whose data is to be retrieved.

Returns:
	A void array of the data, or null if the object has none.
*/
public void[] getExtraBytes(MDThread* t, nint slot)
{
	if(auto o = getObject(t, slot))
	{
		if(o.extraBytes == 0)
			return null;

		return o.extraData();
	}
	else
	{
		pushTypeString(t, slot);
		throwException(t, "getExtraBytes - expected 'object' but got '{}'", getString(t, -1));
	}
		
	assert(false);
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
public nint pushEnvironment(MDThread* t, size_t depth = 0)
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
public nint pushGlobal(MDThread* t, dchar[] name)
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
public nint getGlobal(MDThread* t)
{
	checkNumParams(t, 1);

	auto v = getValue(t, -1);

	if(!v.type == MDValue.Type.String)
	{
		pushTypeString(t, -1);
		throwException(t, "getGlobal - Global name must be a string, not a '{}'", getString(t, -1));
	}

	auto g = lookupGlobal(v.mString, getEnv(t));

	if(g is null)
		throwException(t, "getGlobal - Attempting to get a nonexistent global '{}'", v.mString.toString32());

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
public void setGlobal(MDThread* t, dchar[] name)
{
	checkNumParams(t, 1);
	pushString(t, name);
	insert(t, -2);
	setGlobal(t);
}

/**
Same as above, but expects the name of the global to be on the stack just below the value to set.
Pops both the name and the value.
*/
public void setGlobal(MDThread* t)
{
	checkNumParams(t, 2);

	auto n = getValue(t, -2);

	if(n.type != MDValue.Type.String)
	{
		pushTypeString(t, -2);
		throwException(t, "setGlobal - Global name must be a string, not a '{}'", getString(t, -1));
	}

	auto g = lookupGlobal(n.mString, getEnv(t));

	if(g is null)
		throwException(t, "setGlobal - Attempting to set a nonexistent global '{}'", n.mString.toString32());

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
public void newGlobal(MDThread* t, dchar[] name)
{
	checkNumParams(t, 1);
	pushString(t, name);
	insert(t, -2);
	newGlobal(t);
}

/**
Same as above, but expects the name of the global to be on the stack under the value to be set.  Pops
both the name and the value off the stack.
*/
public void newGlobal(MDThread* t)
{
	checkNumParams(t, 2);

	auto n = getValue(t, -2);

	if(n.type != MDValue.Type.String)
	{
		pushTypeString(t, -2);
		throwException(t, "newGlobal - Global name must be a string, not a '{}'", getString(t, -1));
	}

	auto env = getEnv(t);

	if(namespace.contains(env, n.mString))
		throwException(t, "newGlobal - Attempting to declare a global '{}' that already exists", n.mString.toString32());

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
public bool findGlobal(MDThread* t, dchar[] name, size_t depth = 0)
{
	auto n = string.create(t.vm, name);

	for(auto ns = getEnv(t, depth); ns !is null; ns = ns.parent)
	{
		if(namespace.get(ns, n) !is null)
		{
			pushNamespace(t, ns);
			return true;
		}
	}

	return false;
}

/**
Find how many calls deep the currently-executing function is nested.  Tailcalls are taken into account.

If called at top-level, returns 0.
*/
public size_t callDepth(MDThread* t)
{
	size_t depth = 0;

	for(size_t i = 0; i < t.arIndex; i++)
		depth += t.actRecs[i].numTailcalls + 1;

	return depth;
}

/**
Returns the number of items on the stack.  Valid positive stack indices range from [0 .. _stackSize(t)$(RPAREN).
Valid negative stack indices range from [-_stackSize(t) .. 0$(RPAREN).

Note that 'this' (stack index 0 or -_stackSize(t)) may not be overwritten or changed, although it can be used
with functions that don'_t modify their argument.
*/
public size_t stackSize(MDThread* t)
{
	assert(t.stackIndex > t.stackBase);
	return t.stackIndex - t.stackBase;
}

/**
Push a string representation of any MiniD value onto the stack.

Params:
	slot = The stack index of the value to convert to a string.
	raw = If true, will not call toString metamethods.  Defaults to false, which means toString
		metamethods will be called.

Returns:
	The stack index of the newly-pushed string.
*/
public nint pushToString(MDThread* t, nint slot, bool raw = false)
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
public bool opin(MDThread* t, nint item, nint container)
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
public nint cmp(MDThread* t, nint a, nint b)
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
public bool equals(MDThread* t, nint a, nint b)
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
public bool opis(MDThread* t, nint a, nint b)
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

Returns:
	The stack index that contains the result (the top of the stack).
*/
public nint idx(MDThread* t, nint container, bool raw = false)
{
	checkNumParams(t, 1);
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
*/
public void idxa(MDThread* t, nint container, bool raw = false)
{
	checkNumParams(t, 2);
	auto slot = t.stackIndex - 2;
	idxaImpl(t, getValue(t, container), &t.stack[slot], &t.stack[slot + 1], raw);
	pop(t, 2);
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
public nint field(MDThread* t, nint container, dchar[] name, bool raw = false)
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
public nint field(MDThread* t, nint container, bool raw = false)
{
	checkNumParams(t, 1);

	if(!isString(t, -1))
	{
		pushTypeString(t, -1);
		throwException(t, "field - Field name must be a string, not a '{}'", getString(t, -1));
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
public void fielda(MDThread* t, nint container, dchar[] name, bool raw = false)
{
	checkNumParams(t, 1);
	auto c = fakeToAbs(t, container);
	pushString(t, name);
	insert(t, -2);
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
public void fielda(MDThread* t, nint container, bool raw = false)
{
	checkNumParams(t, 2);

	if(!isString(t, -2))
	{
		pushTypeString(t, -2);
		throwException(t, "fielda - Field name must be a string, not a '{}'", getString(t, -1));
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
public nint pushLen(MDThread* t, nint slot)
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
public mdint len(MDThread* t, nint slot)
{
	pushLen(t, slot);

	if(!isInt(t, -1))
	{
		pushTypeString(t, -1);
		throwException(t, "len - Expected length to be an int, but got '{}' instead", getString(t, -1));
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
public void lena(MDThread* t, nint slot)
{
	checkNumParams(t, 1);
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
public nint slice(MDThread* t, nint container)
{
	checkNumParams(t, 2);
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
public void slicea(MDThread* t, nint container)
{
	checkNumParams(t, 3);
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
public nint add(MDThread* t, nint a, nint b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Add, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
public nint sub(MDThread* t, nint a, nint b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Sub, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
public nint mul(MDThread* t, nint a, nint b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Mul, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
public nint div(MDThread* t, nint a, nint b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Div, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
public nint mod(MDThread* t, nint a, nint b)
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
public nint neg(MDThread* t, nint o)
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
public void addeq(MDThread* t, nint o)
{
	checkNumParams(t, 1);
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.AddEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
public void subeq(MDThread* t, nint o)
{
	checkNumParams(t, 1);
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.SubEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
public void muleq(MDThread* t, nint o)
{
	checkNumParams(t, 1);
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.MulEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
public void diveq(MDThread* t, nint o)
{
	checkNumParams(t, 1);
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.DivEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
public void modeq(MDThread* t, nint o)
{
	checkNumParams(t, 1);
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
public nint and(MDThread* t, nint a, nint b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.And, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
public nint or(MDThread* t, nint a, nint b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.Or, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
public nint xor(MDThread* t, nint a, nint b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.Xor, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
public nint shl(MDThread* t, nint a, nint b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.Shl, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
public nint shr(MDThread* t, nint a, nint b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.Shr, &t.stack[t.stackIndex - 1], &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
public nint ushr(MDThread* t, nint a, nint b)
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
public nint com(MDThread* t, nint o)
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
public void andeq(MDThread* t, nint o)
{
	checkNumParams(t, 1);
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.AndEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
public void oreq(MDThread* t, nint o)
{
	checkNumParams(t, 1);
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.OrEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
public void xoreq(MDThread* t, nint o)
{
	checkNumParams(t, 1);
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.XorEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
public void shleq(MDThread* t, nint o)
{
	checkNumParams(t, 1);
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.ShlEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
public void shreq(MDThread* t, nint o)
{
	checkNumParams(t, 1);
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.ShrEq, &t.stack[oslot], &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
public void ushreq(MDThread* t, nint o)
{
	checkNumParams(t, 1);
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
public nint cat(MDThread* t, size_t num)
{
	if(num == 0)
		throwException(t, "cat - Cannot concatenate 0 things");

	checkNumParams(t, num);

	auto slot = t.stackIndex - num;

	if(num > 1)
	{
		catImpl(t, &t.stack[slot], slot, num);
		pop(t, num - 1);
	}

	return slot;
}

/**
Performs concatenation-assignment.  num is how many values there are on the right-hand side and is expected to
be at least 1.  The RHS values are on the top of the stack.  The destination is the slot immediately before the
RHS values.  Pops the RHS values off the stack, leaving the destination.

-----
// x ~= "Hi, " ~ name ~ "!"
pushGlobal(t, "x"); // destination comes first
pushString(t, "Hi ");
pushGlobal(t, "name");
pushString(t, "!");
cateq(t, 3); // 3 rhs values
setGlobal(t, "x"); // value on the stack may be different, so set it
-----

Params:
	num = How many values are on the RHS to be appended.
*/
public void cateq(MDThread* t, size_t num)
{
	if(num == 0)
		throwException(t, "cateq - Cannot append 0 things");

	checkNumParams(t, num + 1);

	auto slot = t.stackIndex - (num + 1);

	catEqImpl(t, slot, num + 1);
	pop(t, num);
}

/**
Returns whether or not obj is an 'object' and derives from proto.  Throws an error if proto is not an object.
Works just like the as operator in MiniD.

Params:
	obj = The stack index of the value to test.
	proto = The stack index of the _proto object.  Must be an 'object'.

Returns:
	true if obj is an 'object' and it derives from proto.  False otherwise.
*/
public bool as(MDThread* t, nint obj, nint proto)
{
	return asImpl(t, getValue(t, obj), getValue(t, proto));
}

/**
Increments the value at the given _slot.  Calls opInc metamethods.

Params:
	slot = The stack index of the value to increment.
*/
public void inc(MDThread* t, nint slot)
{
	incImpl(t, getValue(t, slot));
}

/**
Decrements the value at the given _slot.  Calls opDec metamethods.

Params:
	slot = The stack index of the value to decrement.
*/
public void dec(MDThread* t, nint slot)
{
	decImpl(t, getValue(t, slot));
}

/**
Gets the proto object of objects or the parent namespace of namespaces and pushes it onto the stack.
Throws an error if the value at the given _slot is neither an object nor a namespace.  Pushes null if
the object or namespace has no proto or parent.  Works just like "x.super" in MiniD.

Params:
	slot = The stack index of the object or namespace whose proto or parent to get.

Returns:
	The stack index of the newly-pushed value.
*/
public nint superof(MDThread* t, nint slot)
{
	return push(t, superofImpl(t, getValue(t, slot)));
}

/**
Throw a MiniD exception using the value at the top of the stack as the exception object.  Any type can
be thrown.  This will throw an actual D exception of type MDException as well, which can be caught in D
as normal ($(B Important:) see catchException for information on catching them).

You cannot use this function if another exception is still in flight, that is, it has not yet been caught with
catchException.  If you try, an Exception will be thrown -- that is, an instance of the D Exception class.

This function obviously does not return.
*/
public void throwException(MDThread* t)
{
	//debug *(cast(byte*)null) = 0;

	if(t.vm.isThrowing)
		// no, don'_t use throwException.  We want this to be a non-MiniD exception.
		throw new Exception("throwException - Attempting to throw an exception while one is already in flight");

	checkNumParams(t, 1);
	throwImpl(t, &t.stack[t.stackIndex - 1]);
}

/**
A shortcut for the very common case where you want to throw a formatted string.  This is equivalent to calling
pushVFormat on the arguments and then throwException.
*/
public void throwException(MDThread* t, dchar[] fmt, ...)
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
might be garbage from a half-completed operation.  So you might want to store the size of the stack before a '_try'
block, then restore it in the 'catch' block so that the stack will be in a consistent state.

An exception must be in flight for this function to work.  If none is in flight, a MiniD exception is thrown. (For
some reason, that sounds funny.  "Error: there is no error!")

Returns:
	The stack index of the newly-pushed exception object.
*/
public nint catchException(MDThread* t)
{
	if(!t.vm.isThrowing)
		throwException(t, "catchException - Attempting to catch an exception when none is in flight");

	auto ret = push(t, t.vm.exception);
	t.vm.exception = MDValue.nullValue;
	t.vm.isThrowing = false;
	return ret;
}

/**
Push the metatable for the given type.  If the type has no metatable, pushes null.  The type given must be
one of the "normal" types -- the "internal" types are illegal and an error will be thrown.

Params:
	type = The type whose metatable is to be pushed.
	
Returns:
	The stack index of the newly-pushed value (null if the type has no metatable, or a namespace if it does).
*/
public nint pushTypeMT(MDThread* t, MDValue.Type type)
{
	if(!(type >= MDValue.Type.Null && type <= MDValue.Type.NativeObj))
		throwException(t, "pushTypeMT - Cannot get metatable for type '{}'", MDValue.typeString(type));

	if(auto ns = t.vm.metaTabs[cast(size_t)type])
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
public void setTypeMT(MDThread* t, MDValue.Type type)
{
	checkNumParams(t, 1);

	if(!(type >= MDValue.Type.Null && type <= MDValue.Type.NativeObj))
		throwException(t, "setTypeMT - Cannot set metatable for type '{}'", MDValue.typeString(type));

	auto v = getValue(t, -1);

	if(v.type == MDValue.Type.Namespace)
		t.vm.metaTabs[cast(size_t)type] = v.mNamespace;
	else if(v.type == MDValue.Type.Null)
		t.vm.metaTabs[cast(size_t)type] = null;
	else
	{
		pushTypeString(t, -1);
		throwException(t, "setTypeMT - Metatable must be either a namespace or 'null', not '{}'", getString(t, -1));
	}
	
	pop(t);
}

/**
Sees if the object at the stack index `obj` has a field with the given name.  Does not take opField
metamethods into account.  Because of that, only works for tables, objects, and namespaces.  If
the object at the stack index `obj` is not one of those types, always returns false.  If this function
returns true, you are guaranteed that accessing a field of the given name on the given object will
succeed.

Params:
	obj = The stack index of the object to test.
	fieldName = The name of the field to look up.

Returns:
	true if the field exists in `obj`; false otherwise.
*/
public bool hasField(MDThread* t, nint obj, dchar[] fieldName)
{
	auto name = string.create(t.vm, fieldName);

	auto v = getValue(t, obj);

	switch(v.type)
	{
		case MDValue.Type.Table:
			return table.get(v.mTable, MDValue(name)) !is null;

		case MDValue.Type.Object:
			MDObject* dummy;
			return .obj.getField(v.mObject, name, dummy) !is null;

		case MDValue.Type.Namespace:
			return namespace.get(v.mNamespace, name) !is null;

		default:
			return false;
	}

	assert(false);
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
public bool hasMethod(MDThread* t, nint obj, dchar[] methodName)
{
	MDObject* proto = void;
	auto n = string.create(t.vm, methodName);
	auto method = lookupMethod(t, getValue(t, obj), n, proto);
	return method !is null;
}

// TODO: 'yield'
// TODO: imports
// TODO: foreach loops
// TODO: tracebacks
// TODO: thread halting

// TODO: get/set attrs
// TODO: get/set finalizers for objects
// TODO: get/set function env

debug
{
	import tango.io.Stdout;
	
	/**
	$(B Debug mode only.)  Print out the contents of the stack to Stdout in the following format:
	
-----
[xxx:yyyy]: val: type
-----

	Where $(I xxx) is the absolute stack index; $(I yyyy) is the stack index relative to the currently-executing function's
	stack frame (negative numbers for lower slots, 0 is the first slot of the stack frame); $(I val) is a raw string
	representation of the value in that slot; and $(I type) is the type of that value.
	*/
	public void printStack(MDThread* t)
	{
		Stdout.newline;
		Stdout("-----Stack Dump-----").newline;

		auto tmp = t.stackBase;
		t.stackBase = cast(AbsStack)0;
		auto top = t.stackIndex;

		for(size_t i = 0; i < top; i++)
		{
			if(t.stack[i].type >= 0 && t.stack[i].type <= MDValue.Type.max)
			{
				pushToString(t, i, true);
				pushTypeString(t, i);
				Stdout.formatln("[{,3}:{,4}]: {}: {}", i, cast(int)i - cast(int)tmp, getString(t, -2), getString(t, -1));
				pop(t, 2);
			}
			else
				Stdout.formatln("[{,3}:{,4}]: {:x16}: {:x}", i, cast(int)i - cast(int)tmp, *cast(ulong*)&t.stack[i].mInt, t.stack[i].type);
		}

		t.stackBase = cast(AbsStack)tmp;

		Stdout.newline;
	}

	/**
	$(B Debug mode only.)  Print out the call stack in reverse, starting from the currently-executing function and
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
	*/
	public void printCallStack(MDThread* t)
	{
		Stdout.newline;
		Stdout("-----Call Stack-----").newline;

		for(int i = t.arIndex - 1; i >= 0; i--)
		{
			with(t.actRecs[i])
			{
				Stdout.formatln("Record {}", func.name.toString32());
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

package nint pushStringObj(MDThread* t, MDString* o)
{
	return push(t, MDValue(o));
}

package nint pushTable(MDThread* t, MDTable* o)
{
	return push(t, MDValue(o));
}

package nint pushArray(MDThread* t, MDArray* o)
{
	return push(t, MDValue(o));
}

package nint pushFunction(MDThread* t, MDFunction* o)
{
	return push(t, MDValue(o));
}

package nint pushObject(MDThread* t, MDObject* o)
{
	return push(t, MDValue(o));
}

package nint pushNamespace(MDThread* t, MDNamespace* o)
{
	return push(t, MDValue(o));
}

package MDString* getStringObj(MDThread* t, nint slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.String)
		return v.mString;
	else
		return null;
}

package MDTable* getTable(MDThread* t, nint slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.Table)
		return v.mTable;
	else
		return null;
}

package MDArray* getArray(MDThread* t, nint slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.Array)
		return v.mArray;
	else
		return null;
}

package MDFunction* getFunction(MDThread* t, nint slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.Function)
		return v.mFunction;
	else
		return null;
}

package MDObject* getObject(MDThread* t, nint slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.Object)
		return v.mObject;
	else
		return null;
}

package MDNamespace* getNamespace(MDThread* t, nint slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.Namespace)
		return v.mNamespace;
	else
		return null;
}

package MDThread* getThread(MDThread* t, nint slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.Thread)
		return v.mThread;
	else
		return null;
}

package MDNativeObj* getNative(MDThread* t, nint slot)
{
	auto v = &t.stack[fakeToAbs(t, slot)];

	if(v.type == MDValue.Type.NativeObj)
		return v.mNativeObj;
	else
		return null;
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

// Stack manipulation
private nint push(MDThread* t, ref MDValue val)
{
	assert(!((&val >= t.stack.ptr) && (&val < t.stack.ptr + t.stack.length)), "trying to push a value that's on the stack");
	checkStack(t, t.stackIndex);
	t.stack[t.stackIndex] = val;
	t.stackIndex++;

	return cast(nint)(t.stackIndex - 1 - t.stackBase);
}

private void checkNumParams(MDThread* t, size_t n)
{
	assert(t.stackIndex > t.stackBase);

	// Don'_t count 'this'
	if((stackSize(t) - 1) < n)
		throwException(t, "Not enough parameters (expected {}, only have {})", n, stackSize(t) - 1);
}

private RelStack fakeToRel(MDThread* t, nint fake)
{
	assert(t.stackIndex > t.stackBase);

	auto size = stackSize(t);

	if(fake < 0)
		fake += size;

	if(fake < 0 || fake >= size)
		throwException(t, "Invalid index");

	return cast(RelStack)fake;
}

private AbsStack fakeToAbs(MDThread* t, nint fake)
{
	return fakeToRel(t, fake) + t.stackBase;
}

private MDValue[] getLocals(MDThread* t)
{
	return t.stack[t.stackBase .. t.stackIndex];
}

private MDNamespace* getEnv(MDThread* t, size_t depth = 0)
{
	if(t.arIndex == 0)
		return t.vm.globals;
	else if(depth == 0)
		return t.currentAR.func.environment;

	for(nint idx = t.arIndex; idx > 0; idx--)
	{
		if(depth == 0)
			return t.actRecs[cast(size_t)idx].func.environment;
		else if(depth <= t.actRecs[cast(size_t)idx].numTailcalls)
			throwException(t, "Attempting to get environment of function whose activation record was overwritten by a tail call");

		depth -= (t.actRecs[cast(size_t)idx].numTailcalls + 1);
	}

	return t.vm.globals;
}

private size_t commonCall(MDThread* t, AbsStack slot, nint numReturns, bool isScript)
{
	if(isScript)
		execute(t);

	maybeGC(t.vm);

	if(numReturns == -1)
		return t.stackIndex - slot;
	else
	{
		t.stackIndex = slot + numReturns;
		return numReturns;
	}
}

private bool commonMethodCall(MDThread* t, AbsStack slot, MDValue* self, MDValue* lookup, MDString* methodName, nint numReturns, size_t numParams, bool customThis)
{
	MDObject* proto = void;
	auto method = lookupMethod(t, lookup, methodName, proto);

	// Idea is like this:

	// If we're calling the real method, the object is moved to the 'this' slot and the method takes its place.

	// If we're calling opMethod, the object is left where it is (or the custom context is moved to its place),
	// the method name goes where the context was, and we use callPrologue2 with a closure that's not on the stack.

	if(method !is null)
	{
		if(!customThis)
			t.stack[slot + 1] = *self;

		t.stack[slot] = method;

		return callPrologue(t, slot, numReturns, numParams, proto);
	}
	else
	{
		method = getMM(t, lookup, MM.Method, proto);

		if(method is null)
		{
			typeString(t, lookup);
			throwException(t, "No implementation of method '{}' or {} for type '{}'", methodName.toString32(), MetaNames[MM.Method], getString(t, -1));
		}

		if(customThis)
			t.stack[slot] = t.stack[slot + 1];
		else
			t.stack[slot] = *self;

		t.stack[slot + 1] = methodName;

		return callPrologue2(t, method, slot, numReturns, slot, numParams + 1, proto);
	}
}

private MDValue* getValue(MDThread* t, nint slot)
{
	return &t.stack[fakeToAbs(t, slot)];
}

private nint typeString(MDThread* t, MDValue* v)
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
			MDValue.Type.Thread:
			
			return pushString(t, MDValue.typeString(v.type));

		case MDValue.Type.Object:
			// LEAVE ME UP HERE PLZ
			auto n = v.mObject.name;
			// KTHXbye
			pushString(t, MDValue.typeString(MDValue.Type.Object));
			pushChar(t, ' ');
			pushStringObj(t, n);
			return cat(t, 3);

		case MDValue.Type.NativeObj:
			pushString(t, MDValue.typeString(MDValue.Type.NativeObj));
			pushChar(t, ' ');

			if(auto o = v.mNativeObj.obj)
			{
				dchar[96] buffer = void;

				// The 'ate' parameter will prevent toString32 from reallocating the buffer on the heap.
				auto n = o.classinfo.name;
				uint ate = void;
				auto s = Utf.toString32(n, buffer, &ate);

				// Ellipsis!
				if(ate < n.length && s.length >= 3)
					s[$ - 3 .. $] = "...";

				pushString(t, s);
			}
			else
				pushString(t, "(??? null)");

			return cat(t, 3);

		default: assert(false);
	}

	assert(false);
}

private MDValue* lookupGlobal(MDString* name, MDNamespace* env)
{
	for(auto ns = env; ns !is null; ns = ns.parent)
		if(auto glob = namespace.get(ns, name))
			return glob;

	return null;
}

private nint toStringImpl(MDThread* t, MDValue v, bool raw)
{
	dchar[80] buffer = void;

	switch(v.type)
	{
		case MDValue.Type.Null:  return pushString(t, "null");
		case MDValue.Type.Bool:  return pushString(t, v.mBool ? "true"d : "false"d);
		case MDValue.Type.Int:   return pushString(t, Integer.format(buffer, v.mInt));
		case MDValue.Type.Float: return pushString(t, Float.truncate(Float.format(buffer, v.mFloat, 6)));

		case MDValue.Type.Char:
			buffer[0] = v.mChar;
			return pushString(t, buffer[0 .. 1]);

		case MDValue.Type.String:
			return push(t, v);

		default:
			if(!raw)
			{
				if(auto method = getMM(t, &v, MM.ToString))
				{
					auto funcSlot = pushFunction(t, method);
					push(t, v);
					rawCall(t, funcSlot, 1);

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
						return pushFormat(t, "native {} {}", MDValue.typeString(MDValue.Type.Function), f.name.toString32());
					else
						return pushFormat(t, "script {} {}({})", MDValue.typeString(MDValue.Type.Function), f.name.toString32(), /* script.func.mLocation.toString() */ "POOPY PEE!"); // TODO: this.

				case MDValue.Type.Object: return pushFormat(t, "{} {} (0x{:X8})", MDValue.typeString(MDValue.Type.Object), v.mObject.name.toString32(), cast(void*)v.mObject);
				case MDValue.Type.Namespace:
					size_t namespaceName(MDNamespace* ns)
					{
						if(ns.name.length == 0)
							return 0;

						size_t n = 0;

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
					
					if(raw)
						return pushFormat(t, "{} 0x{:X8}", MDValue.typeString(MDValue.Type.Namespace), cast(void*)v.mNamespace);
					else
					{
						pushString(t, MDValue.typeString(MDValue.Type.Namespace));
						pushChar(t, ' ');
						return cat(t, namespaceName(v.mNamespace) + 2);
					}

				case MDValue.Type.Thread: return pushFormat(t, "{} 0x{:X8}", MDValue.typeString(MDValue.Type.Thread), cast(void*)v.mThread);
				case MDValue.Type.NativeObj: return pushFormat(t, "{} 0x{:X8}", MDValue.typeString(MDValue.Type.NativeObj), cast(void*)v.mNativeObj.obj);

				default: assert(false);
			}
	}

	assert(false);
}

private bool inImpl(MDThread* t, MDValue* item, MDValue* container)
{
	switch(container.type)
	{
		case MDValue.Type.String:
			if(item.type != MDValue.Type.Char)
			{
				typeString(t, item);
				throwException(t, "Can only use characters to look in strings, not '{}'", getString(t, -1));
			}

			return string.contains(container.mString, item.mChar);

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
			auto method = getMM(t, container, MM.In);

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
			rawCall(t, funcSlot, 1);
			
			auto ret = isTrue(t, -1);
			pop(t);
			return ret;
	}
	
	assert(false);
}

private void idxImpl(MDThread* t, MDValue* dest, MDValue* container, MDValue* key, bool raw)
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

			*dest = arr.slice[cast(size_t)index];
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
				index += str.length;

			if(index < 0 || index >= str.length)
				throwException(t, "Invalid string index {} (length is {})", key.mInt, str.length);

			*dest = str.toString32()[cast(size_t)index];
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

private void idxaImpl(MDThread* t, MDValue* container, MDValue* key, MDValue* value, bool raw)
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

			arr.slice[cast(size_t)index] = *value;
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

private nint commonField(MDThread* t, AbsStack container, bool raw)
{
	auto slot = t.stackIndex - 1;
	fieldImpl(t, &t.stack[slot], &t.stack[container], t.stack[slot].mString, raw);
	return stackSize(t) - 1;
}

private void commonFielda(MDThread* t, AbsStack container, bool raw)
{
	auto slot = t.stackIndex - 2;
	fieldaImpl(t, &t.stack[container], t.stack[slot].mString, &t.stack[slot + 1], raw);
	pop(t, 2);
}

private void fieldImpl(MDThread* t, MDValue* dest, MDValue* container, MDString* name, bool raw)
{
	switch(container.type)
	{
		case MDValue.Type.Table:
			// This is right, tables do not have separate opField capabilities.
			return tableIdxImpl(t, dest, container, &MDValue(name), raw);

		case MDValue.Type.Object:
			auto v = obj.getField(container.mObject, name);

			if(v is null)
			{
				if(!raw && tryMM!(2, true)(t, MM.Field, dest, container, &MDValue(name)))
					return;

				typeString(t, container);
				throwException(t, "Attempting to access nonexistent field '{}' from '{}'", name.toString32(), getString(t, -1));
			}

			return *dest = *v;

		case MDValue.Type.Namespace:
			auto v = namespace.get(container.mNamespace, name);

			if(v is null)
			{
				if(!raw && tryMM!(2, true)(t, MM.Field, dest, container, &MDValue(name)))
					return;

				toStringImpl(t, *container, false);
				throwException(t, "Attempting to access nonexistent field '{}' from '{}'", name.toString32(), getString(t, -1));
			}

			return *dest = *v;

		default:
			if(!raw && tryMM!(2, true)(t, MM.Field, dest, container, &MDValue(name)))
				return;
				
			typeString(t, container);
			throwException(t, "Attempting to access field '{}' from a value of type '{}'", name.toString32(), getString(t, -1));
	}
}

private void fieldaImpl(MDThread* t, MDValue* container, MDString* name, MDValue* value, bool raw)
{
	switch(container.type)
	{
		case MDValue.Type.Table:
			// This is right, tables do not have separate opField capabilities.
			return tableIdxaImpl(t, container, &MDValue(name), value, raw);

		case MDValue.Type.Object:
			auto o = container.mObject;

			MDObject* owner = void;
			auto field = obj.getField(o, name, owner);

			if(field is null)
			{
				if(!raw && tryMM!(3, false)(t, MM.FieldAssign, container, &MDValue(name), value))
					return;
				else
					obj.setField(t.vm, o, name, value);
			}
			else if(owner !is o)
				obj.setField(t.vm, o, name, value);
			else
				*field = *value;
			return;

		case MDValue.Type.Namespace:
			return namespace.set(t.vm.alloc, container.mNamespace, name, value);

		default:
			if(!raw && tryMM!(3, false)(t, MM.FieldAssign, container, &MDValue(name), value))
				return;

			typeString(t, container);
			throwException(t, "Attempting to assign field '{}' into a value of type '{}'", name.toString32(), getString(t, -1));
	}
}

private mdint compareImpl(MDThread* t, MDValue* a, MDValue* b)
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

			case MDValue.Type.Table, MDValue.Type.Object:
				if(auto method = getMM(t, a, MM.Cmp))
					return commonCompare(t, method, a, b);
				else if(auto method = getMM(t, b, MM.Cmp))
					return -commonCompare(t, method, b, a);
				break; // break to error

			default: break; // break to error
		}
	}
	else if((a.type == MDValue.Type.Object || a.type == MDValue.Type.Table))
	{
		if(auto method = getMM(t, a, MM.Cmp))
			return commonCompare(t, method, a, b);
	}
	else if((b.type == MDValue.Type.Object || b.type == MDValue.Type.Table))
	{
		if(auto method = getMM(t, b, MM.Cmp))
			return -commonCompare(t, method, b, a);
	}

	auto bsave = *b;
	typeString(t, a);
	typeString(t, &bsave);
	throwException(t, "Can't compare types '{}' and '{}'", getString(t, -2), getString(t, -1));
	assert(false);
}

private bool switchCmpImpl(MDThread* t, MDValue* a, MDValue* b)
{
	if(a.type != b.type)
		return false;
		
	if(a.opEquals(*b))
		return true;

	if(a.type == MDValue.Type.Object || a.type == MDValue.Type.Table)
	{
		if(auto method = getMM(t, a, MM.Cmp))
			return commonCompare(t, method, a, b) == 0;
		else if(auto method = getMM(t, b, MM.Cmp))
			return commonCompare(t, method, b, a) == 0;
	}

	return false;
}

private bool equalsImpl(MDThread* t, MDValue* a, MDValue* b)
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

			case MDValue.Type.Table, MDValue.Type.Object:
				if(auto method = getMM(t, a, MM.Equals))
					return commonEquals(t, method, a, b);
				else if(auto method = getMM(t, b, MM.Equals))
					return commonEquals(t, method, b, a);
				break; // break to error

			default: break; // break to error
		}
	}
	else if((a.type == MDValue.Type.Object || a.type == MDValue.Type.Table))
	{
		if(auto method = getMM(t, a, MM.Equals))
			return commonEquals(t, method, a, b);
	}
	else if((b.type == MDValue.Type.Object || b.type == MDValue.Type.Table))
	{
		if(auto method = getMM(t, b, MM.Equals))
			return commonEquals(t, method, b, a);
	}

	auto bsave = *b;
	typeString(t, a);
	typeString(t, &bsave);
	throwException(t, "Can't compare types '{}' and '{}' for equality", getString(t, -2), getString(t, -1));
	assert(false);
}

private void lenImpl(MDThread* t, MDValue* dest, MDValue* src)
{
	switch(src.type)
	{
		case MDValue.Type.String:    return *dest = cast(mdint)src.mString.length;
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

private void lenaImpl(MDThread* t, MDValue* dest, MDValue* len)
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

			return array.resize(t.vm.alloc, dest.mArray, cast(size_t)l);

		default:
			if(tryMM!(2, false)(t, MM.LengthAssign, dest, len))
				return;

			typeString(t, dest);
			throwException(t, "Can't set the length of a '{}'", getString(t, -1));
	}
}

private void sliceImpl(MDThread* t, MDValue* dest, MDValue* src, MDValue* lo, MDValue* hi)
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

			return *dest = array.slice(t.vm.alloc, arr, cast(size_t)loIndex, cast(size_t)hiIndex);

		case MDValue.Type.String:
			auto str = src.mString;
			mdint loIndex = void;
			mdint hiIndex = void;

			if(lo.type == MDValue.Type.Null && hi.type == MDValue.Type.Null)
				return *dest = *src;

			if(!correctIndices(loIndex, hiIndex, lo, hi, str.length))
			{
				auto hisave = *hi;
				typeString(t, lo);
				typeString(t, &hisave);
				throwException(t, "Attempting to slice a string with indices of type '{}' and '{}'", getString(t, -2), getString(t, -1));
			}

			if(loIndex > hiIndex || loIndex < 0 || loIndex > str.length || hiIndex < 0 || hiIndex > str.length)
				throwException(t, "Invalid slice indices [{} .. {}] (string length = {})", loIndex, hiIndex, str.length);

			return *dest = string.slice(t.vm, str, cast(size_t)loIndex, cast(size_t)hiIndex);

		default:
			if(tryMM!(3, 1)(t, MM.Slice, dest, src, lo, hi))
				return;

			typeString(t, src);
			throwException(t, "Attempting to slice a value of type '{}'", getString(t, -1));
	}
}

private void sliceaImpl(MDThread* t, MDValue* container, MDValue* lo, MDValue* hi, MDValue* value)
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

				return array.sliceAssign(arr, cast(size_t)loIndex, cast(size_t)hiIndex, value.mArray);
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

private void binOpImpl(MDThread* t, MM operation, MDValue* dest, MDValue* RS, MDValue* RT)
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

					return MDValue(i1 % i2);

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

private void reflBinOpImpl(MDThread* t, MM operation, MDValue* dest, MDValue* src)
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

private void negImpl(MDThread* t, MDValue* dest, MDValue* src)
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

private void binaryBinOpImpl(MDThread* t, MM operation, MDValue* dest, MDValue* RS, MDValue* RT)
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

private void reflBinaryBinOpImpl(MDThread* t, MM operation, MDValue* dest, MDValue* src)
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

private void comImpl(MDThread* t, MDValue* dest, MDValue* src)
{
	if(src.type == MDValue.Type.Int)
		return *dest = ~src.mInt;

	if(tryMM!(1, true)(t, MM.Com, dest, src))
		return;

	typeString(t, src);
	throwException(t, "Cannot perform bitwise complement on a '{}'", getString(t, -1));
}

private void incImpl(MDThread* t, MDValue* dest)
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

private void decImpl(MDThread* t, MDValue* dest)
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

private void catImpl(MDThread* t, MDValue* dest, AbsStack firstSlot, size_t num)
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

		switch(stack[slot].type)
		{
			case MDValue.Type.String, MDValue.Type.Char:
				size_t idx = slot + 1;
				size_t len = stack[slot].type == MDValue.Type.Char ? 1 : stack[slot].mString.length;

				for(; idx < endSlot; idx++)
				{
					if(stack[idx].type == MDValue.Type.String)
						len += stack[idx].mString.length;
					else if(stack[idx].type == MDValue.Type.Char)
						len++;
					else
						break;
				}

				if(idx > (slot + 1))
				{
					stringConcat(t, stack[slot .. idx], len);
					slot = idx - 1;
				}

				if(slot == endSlotm1)
					break; // to exit function

				if(stack[slot + 1].type == MDValue.Type.Array)
					goto array;
				else if(stack[slot + 1].type == MDValue.Type.Object || stack[slot + 1].type == MDValue.Type.Table)
					goto cat_r;
				else
				{
					typeString(t, &stack[slot + 1]);
					throwException(t, "Can't concatenate 'string/char' and '{}'", getString(t, -1));
				}

			case MDValue.Type.Array:
				array:
				size_t idx = slot + 1;
				size_t len = stack[slot].type == MDValue.Type.Array ? stack[slot].mArray.slice.length : 1;

				for(; idx < endSlot; idx++)
				{
					if(stack[idx].type == MDValue.Type.Array)
						len += stack[idx].mArray.slice.length;
					else if(stack[idx].type == MDValue.Type.Object || stack[idx].type == MDValue.Type.Table)
					{
						method = getMM(t, &stack[idx], MM.Cat_r);

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

			case MDValue.Type.Object, MDValue.Type.Table:
				if(stack[slot + 1].type == MDValue.Type.Array)
				{
					method = getMM(t, &stack[slot], MM.Cat);

					if(method is null)
						goto array;
				}

				bool swap = false;

				if(method is null)
				{
					method = getMM(t, &stack[slot], MM.Cat);

					if(method is null)
					{
						if(stack[slot + 1].type != MDValue.Type.Object && stack[slot + 1].type != MDValue.Type.Table)
						{
							typeString(t, &stack[slot + 1]);
							throwException(t, "Can't concatenate an 'object/table' with a '{}'", getString(t, -1));
						}
	
						method = getMM(t, &stack[slot + 1], MM.Cat_r);
	
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

				rawCall(t, funcSlot, 1);

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
				else if(stack[slot + 1].type == MDValue.Type.Object || stack[slot + 1].type == MDValue.Type.Table)
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
					method = getMM(t, &stack[slot + 1], MM.Cat_r);

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
				rawCall(t, funcSlot, 1);

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

private void catEqImpl(MDThread* t, AbsStack firstSlot, size_t num)
{
	assert(num >= 2);

	// dest is stack[firstSlot]
	auto slot = firstSlot;
	auto endSlot = slot + num;
	auto stack = t.stack;

	auto dest = &t.stack[slot];

	switch(dest.type)
	{
		case MDValue.Type.String, MDValue.Type.Char:
			size_t len = dest.type == MDValue.Type.Char ? 1 : dest.mString.length;

			for(size_t idx = slot + 1; idx < endSlot; idx++)
			{
				if(stack[idx].type == MDValue.Type.String)
					len += stack[idx].mString.length;
				else if(stack[idx].type == MDValue.Type.Char)
					len++;
				else
				{
					typeString(t, &stack[idx]);
					throwException(t, "Can't append a '{}' to a 'string/char'", getString(t, -1));
				}
			}
			
			stringConcat(t, stack[slot .. endSlot], len);
			stack[slot] = stack[endSlot - 1];
			return;

		case MDValue.Type.Array:
			return arrayAppend(t, stack[slot .. endSlot]);

		case MDValue.Type.Object, MDValue.Type.Table:
			auto method = getMM(t, dest, MM.CatEq);
			
			if(method is null)
			{
				typeString(t, dest);
				throwException(t, "No implementation of {} for type '{}'", MetaNames[MM.CatEq], getString(t, -1));
			}
				
			if(callPrologue2(t, method, firstSlot, 0, firstSlot, num, null))
				execute(t);
			return;

		default:
			typeString(t, dest);
			throwException(t, "Can't append to a value of type '{}'", getString(t, -1));
	}
}

private bool asImpl(MDThread* t, MDValue* o, MDValue* p)
{
	if(p.type != MDValue.Type.Object)
	{
		typeString(t, p);
		throwException(t, "Attempting to use 'as' with a '{}' instead of an 'object' as the type", getString(t, -1));
	}

	return o.type == MDValue.Type.Object && obj.derivesFrom(o.mObject, p.mObject);
}

private MDValue superofImpl(MDThread* t, MDValue* v)
{
	if(v.type == MDValue.Type.Object)
	{
		if(auto p = v.mObject.proto)
			return MDValue(p);
		else
			return MDValue.nullValue;
	}
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
		throwException(t, "Can only get super of objects and namespaces, not values of type '{}'", getString(t, -1));
	}
		
	assert(false);
}

// Internal funcs
private void savePtr(MDThread* t, ref MDValue* ptr, out bool shouldLoad)
{
	if(ptr >= t.stack.ptr && ptr < t.stack.ptr + t.stack.length)
	{
		shouldLoad = true;
		ptr = cast(MDValue*)(cast(size_t)ptr - cast(size_t)t.stack.ptr);
	}
}

private void loadPtr(MDThread* t, ref MDValue* ptr)
{
	ptr = cast(MDValue*)(cast(size_t)ptr + cast(size_t)t.stack.ptr);
}

private void checkStack(MDThread* t, AbsStack idx)
{
	if(idx >= t.stack.length)
		stackSize(t, idx * 2);
}

private void stackSize(MDThread* t, size_t size)
{
	auto oldBase = t.stack.ptr;
	t.vm.alloc.resizeArray(t.stack, size);
	auto newBase = t.stack.ptr;

	if(newBase !is oldBase)
		for(auto uv = t.upvalHead; uv !is null; uv = uv.next)
			uv.value = (uv.value - oldBase) + newBase;
}

private class ThreadFiber : Fiber
{
	private MDThread* t;

	private this(MDThread* t)
	{
		super(&run);
		this.t = t;
	}

	private void run()
	{
		assert(t.state == MDThread.State.Initial);
		t.stack[0] = t.coroFunc;
		rawCall(t, 0, -1);
	}
}

private nuint resume(MDThread* t, size_t numParams)
{
	if(t.coroFiber is null)
		t.coroFiber = nativeobj.create(t.vm, new ThreadFiber(t));
	else
		(cast(ThreadFiber)cast(void*)t.coroFiber.obj).t = t;

	t.getFiber().call();
	return t.numYields;

// 	if(t.state == MDThread.State.Initial)
// 	{
// 
// 
// 		if(t.coroFunc.isNative)
// 		{
// 			mixin(Unimpl);
// // 			assert(mCoroFiber !is null, "no coroutine fiber for native coroutine");
// //
// // 			nativeCallPrologue(mCoroFunc, 0, -1, 1, numParams, MDValue.nullValue);
// // 			mCoroFiber.call();
// //
// // 			if(mCoroFiber.state == Fiber.State.HOLD)
// // 				mState = State.Suspended;
// // 			else if(mCoroFiber.state == Fiber.State.TERM)
// // 				mState = State.Dead;
// 		}
// 		else
// 		{
// 			auto result = callPrologue(t, cast(AbsStack)0, -1, numParams, null);
// 			assert(result == true, "resume callPrologue must return true");
// 			execute(t);
// 		}
// 
// 		return t.numYields;
// 	}
// 	else
// 	{
// 		if(t.coroFunc.isNative)
// 		{
// 			mixin(Unimpl);
// // 			mCoroFiber.call();
// //
// // 			if(mCoroFiber.state == Fiber.State.HOLD)
// // 				mState = State.Suspended;
// // 			else if(mCoroFiber.state == Fiber.State.TERM)
// // 				mState = State.Dead;
// 		}
// 		else
// 		{
// 			callEpilogue(t, true);
// 			execute(t, t.savedCallDepth);
// 		}
// 
// 		return t.numYields;
// 	}
}

private MDNamespace* getMetatable(MDThread* t, MDValue.Type type)
{
	assert(type >= MDValue.Type.Null && type <= MDValue.Type.NativeObj);
	return t.vm.metaTabs[type];
}

private MDFunction* lookupMethod(MDThread* t, MDValue* v, MDString* name, out MDObject* proto)
{
	switch(v.type)
	{
		case MDValue.Type.Object:
			return getMethod(v.mObject, name, proto);

		case MDValue.Type.Table:
			if(auto ret = getMethod(v.mTable, name))
				return ret;

			goto default;

		case MDValue.Type.Namespace:
			return getMethod(v.mNamespace, name);

		default:
			return getMethod(t, v.type, name);
	}

	assert(false);
}

private MDFunction* getMM(MDThread* t, MDValue* obj, MM method)
{
	MDObject* dummy = void;
	return getMM(t, obj, method, dummy);
}

private MDFunction* getMM(MDThread* t, MDValue* obj, MM method, out MDObject* proto)
{
	auto name = t.vm.metaStrings[method];

	switch(obj.type)
	{
		case MDValue.Type.Object:
			return getMethod(obj.mObject, name, proto);

		case MDValue.Type.Table:
			if(auto ret = getMethod(obj.mTable, name))
				return ret;

			goto default;

		default:
			return getMethod(t, obj.type, name);
	}

	assert(false);
}

private MDFunction* getMethod(MDObject* obj, MDString* name, out MDObject* proto)
{
	auto ret = .obj.getField(obj, name, proto);

	if(ret is null || ret.type != MDValue.Type.Function)
		return null;
	else
		return ret.mFunction;
}

private MDFunction* getMethod(MDTable* tab, MDString* name)
{
	auto ret = table.get(tab, MDValue(name));

	if(ret is null || ret.type != MDValue.Type.Function)
		return null;
	else
		return ret.mFunction;
}

private MDFunction* getMethod(MDNamespace* ns, MDString* name)
{
	auto ret = namespace.get(ns, name);

	if(ret is null || ret.type != MDValue.Type.Function)
		return null;
	else
		return ret.mFunction;
}

private MDFunction* getMethod(MDThread* t, MDValue.Type type, MDString* name)
{
	auto mt = getMetatable(t, type);

	if(mt is null)
		return null;

	auto ret = namespace.get(mt, name);

	if(ret is null || ret.type != MDValue.Type.Function)
		return null;
	else
		return ret.mFunction;
}

// Calling and execution
private bool callPrologue(MDThread* t, AbsStack slot, nint numReturns, size_t numParams, MDObject* proto)
{
	assert(numParams > 0);
	auto func = &t.stack[slot];

	switch(func.type)
	{
		case MDValue.Type.Function:
			return callPrologue2(t, func.mFunction, slot, numReturns, slot + 1, numParams, proto);
			
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

			t.stackIndex = slot;

			size_t numRets = void;

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
					t.state = savedState;

				numRets = resume(thread, numParams);
			}
			catch(MDException e)
			{
				callEpilogue(t, false);
				throw e;
			}
			// Don't have to handle halt exceptions; they can't propagate out of a thread

			assert((thread.stackIndex - thread.currentAR.base) >= numRets, "thread finished resuming stack underflow");

			saveResults(t, thread, thread.stackIndex - numRets, numRets);
			thread.stackIndex -= numRets;

			callEpilogue(t, true);
			return false;

		default:
			auto method = getMM(t, func, MM.Call);

			if(method is null)
			{
				typeString(t, func);
				throwException(t, "No implementation of {} for type '{}'", MetaNames[MM.Call], getString(t, -1));
			}

			t.stack[slot + 1] = *func;
			*func = method;
			return callPrologue2(t, method, slot, numReturns, slot + 1, numParams, proto);
	}

	assert(false);
}

private bool callPrologue2(MDThread* t, MDFunction* func, AbsStack returnSlot, nint numReturns, AbsStack paramSlot, nint numParams, MDObject* proto)
{
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
		ar.proto = proto is null ? null : proto.proto;
		ar.numTailcalls = 0;
		ar.savedTop = ar.base + funcDef.stackSize;

		// Set the stack indices.
		t.stackBase = ar.base;
		t.stackIndex = ar.savedTop;
		return true;
	}
	else
	{
		// Native function
		nativeCallPrologue(t, func, returnSlot, numReturns, paramSlot, numParams, proto);
		
		size_t actualReturns = void;

		try
			actualReturns = func.nativeFunc(t, numParams - 1);
		catch(MDException e)
		{
			callEpilogue(t, false);
			throw e;
		}
		catch(MDHaltException e)
		{
			// TODO: investigate?
// 			if(t.nativeCallDepth > 0)
// 			{
				callEpilogue(t, false);
				throw e;
// 			}
//
// 			saveResults(t, t, cast(AbsStack)0, 0);
// 			callEpilogue(t, true);
//
// 			if(t.arIndex > 0)
// 				throw e;
//
// 			return false;
		}

		saveResults(t, t, t.stackIndex - actualReturns, actualReturns);
		callEpilogue(t, true);
		return false;
	}
}

private void nativeCallPrologue(MDThread* t, MDFunction* closure, AbsStack returnSlot, nint numReturns, AbsStack paramSlot, nint numParams, MDObject* proto)
{
	t.stackIndex = paramSlot + numParams;
	checkStack(t, t.stackIndex);

	auto ar = pushAR(t);

	ar.base = paramSlot;
	ar.vargBase = paramSlot;
	ar.returnSlot = returnSlot;
	ar.func = closure;
	ar.numReturns = numReturns;
	ar.firstResult = 0;
	ar.numResults = 0;
	ar.savedTop = t.stackIndex;
	ar.proto = proto is null ? null : proto.proto;
	ar.numTailcalls = 0;
	
	t.stackBase = t.currentAR.base;
}

private void callEpilogue(MDThread* t, bool needResults)
{
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
	}
	else
	{
		if(isMultRet)
			t.stackIndex = destSlot + numExpRets;
		else
			t.stackIndex = t.currentAR.savedTop;
	}
}

private void saveResults(MDThread* t, MDThread* from, AbsStack first, size_t num)
{
	if(num == 0)
		return;

	if((t.results.length - t.resultIndex) < num)
		t.vm.alloc.resizeArray(t.results, t.results.length * 2);

	assert(t.currentAR.firstResult is 0 && t.currentAR.numResults is 0);

	t.results[t.resultIndex .. t.resultIndex + num] = from.stack[first .. first + num];

	t.currentAR.firstResult = t.resultIndex;
	t.currentAR.numResults = num;

	t.resultIndex += num;
}

private MDValue[] loadResults(MDThread* t)
{
	auto first = t.currentAR.firstResult;
	auto num = t.currentAR.numResults;
	auto ret = t.results[first .. first + num];
	t.currentAR.firstResult = 0;
	t.currentAR.numResults = 0;
	t.resultIndex -= num;
	return ret;
}

private ActRecord* pushAR(MDThread* t)
{
	if(t.arIndex >= t.actRecs.length)
		t.vm.alloc.resizeArray(t.actRecs, t.actRecs.length * 2);

	t.currentAR = &t.actRecs[t.arIndex];
	t.arIndex++;
	return t.currentAR;
}

private void popAR(MDThread* t)
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
		t.stackBase = cast(AbsStack)0;
	}
}

private TryRecord* pushTR(MDThread* t)
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
	"private bool tryMM(MDThread* t, MM mm, " ~ (hasDest? "MDValue* dest, " : "") ~ tryMMParams!(numParams) ~ ")\n"
	"{\n"
	"	auto method = getMM(t, src1, mm);\n"
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
	"	rawCall(t, funcSlot, " ~ (hasDest ? "1" : "0") ~ ");\n"
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

private mdint commonCompare(MDThread* t, MDFunction* method, MDValue* a, MDValue* b)
{
	auto asave = *a;
	auto bsave = *b;

	auto funcReg = pushFunction(t, method);
	push(t, asave);
	push(t, bsave);
	rawCall(t, funcReg, 1);

	auto ret = *getValue(t, -1);
	pop(t);

	if(ret.type != MDValue.Type.Int)
	{
		typeString(t, &ret);
		throwException(t, "{} is expected to return an int, but '{}' was returned instead", MetaNames[MM.Cmp], getString(t, -1));
	}

	return ret.mInt;
}

private bool commonEquals(MDThread* t, MDFunction* method, MDValue* a, MDValue* b)
{
	auto asave = *a;
	auto bsave = *b;

	auto funcReg = pushFunction(t, method);
	push(t, asave);
	push(t, bsave);
	rawCall(t, funcReg, 1);

	auto ret = *getValue(t, -1);
	pop(t);

	if(ret.type != MDValue.Type.Bool)
	{
		typeString(t, &ret);
		throwException(t, "{} is expected to return a bool, but '{}' was returned instead", MetaNames[MM.Equals], getString(t, -1));
	}

	return ret.mBool;
}

private void tableIdxImpl(MDThread* t, MDValue* dest, MDValue* container, MDValue* key, bool raw)
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

private void tableIdxaImpl(MDThread* t, MDValue* container, MDValue* key, MDValue* value, bool raw)
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
	else
	{
		if(raw || !tryMM!(3, false)(t, MM.IndexAssign, container, key, value))
			table.set(t.vm.alloc, container.mTable, *key, *value);
	}
}

private bool correctIndices(out mdint loIndex, out mdint hiIndex, MDValue* lo, MDValue* hi, size_t len)
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

private void commonBinOpMM(MDThread* t, MM operation, MDValue* dest, MDValue* RS, MDValue* RT)
{
	// mm
	bool swap = false;

	debug Stdout.formatln("stack = {}, RS = {}", t.stack.ptr, RS);
	auto method = getMM(t, RS, operation);

	if(method is null)
	{
		method = getMM(t, RT, MMRev[operation]);

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

			method = getMM(t, RS, MMRev[operation]);

			if(method is null)
			{
				method = getMM(t, RT, operation);

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
		push(t, *RT);
		push(t, *RS);
	}
	else
	{
		push(t, *RS);
		push(t, *RT);
	}

	rawCall(t, funcSlot, 1);
	
	if(shouldLoad)
		loadPtr(t, dest);

	*dest = t.stack[t.stackIndex - 1];
	pop(t);
}

private void arrayConcat(MDThread* t, MDValue[] vals, size_t len)
{
	if(vals.length == 2 && vals[0].type == MDValue.Type.Array)
	{
		if(vals[1].type == MDValue.Type.Array)
			return vals[1] = array.cat(t.vm.alloc, vals[0].mArray, vals[1].mArray);
		else
			return vals[1] = array.cat(t.vm.alloc, vals[0].mArray, &vals[1]);
	}

	auto ret = array.create(t.vm.alloc, len);

	size_t i = 0;

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

private void stringConcat(MDThread* t, MDValue[] vals, size_t len)
{
	auto tmpBuffer = t.vm.alloc.allocArray!(dchar)(len);

	size_t i = 0;

	foreach(ref v; vals)
	{
		if(v.type == MDValue.Type.String)
		{
			auto s = v.mString;
			tmpBuffer[i .. i + s.length] = s.toString32()[];
			i += s.length;
		}
		else
		{
			tmpBuffer[i] = v.mChar;
			i++;
		}
	}

	vals[$ - 1] = string.create(t.vm, tmpBuffer);
	t.vm.alloc.freeArray(tmpBuffer);
}

private void arrayAppend(MDThread* t, MDValue[] vals)
{
	size_t len = 0;

	foreach(ref val; vals)
	{
		if(val.type == MDValue.Type.Array)
			len += val.mArray.slice.length;
		else
			len++;
	}

	auto ret = vals[0].mArray;
	size_t i = ret.slice.length;

	array.resize(t.vm.alloc, ret, len);

	foreach(ref v; vals[1 .. $])
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
}

private void close(MDThread* t, AbsStack index)
{
	auto base = &t.stack[index];

	for(auto uv = t.upvalHead; uv !is null && uv.value >= base; uv = t.upvalHead)
	{
		t.upvalHead = uv.next;

		if(uv.prev)
			uv.prev.next = uv.next;

		if(uv.next)
			uv.next.prev = uv.prev;

		uv.closedValue = *uv.value;
		uv.value = &uv.closedValue;
	}
}

private MDUpval* findUpvalue(MDThread* t, size_t num)
{
	auto slot = &t.stack[t.currentAR.base + num];

	for(auto uv = t.upvalHead; uv !is null && uv.value >= slot; uv = uv.next)
	{
		if(uv.value is slot)
			return uv;
	}

	auto ret = t.vm.alloc.allocate!(MDUpval)();
	ret.value = slot;

	if(t.upvalHead !is null)
	{
		ret.next = t.upvalHead;
		ret.next.prev = ret;
	}

	t.upvalHead = ret;
	return ret;
}

private void throwImpl(MDThread* t, MDValue* ex)
{
	toStringImpl(t, *ex, true);
	auto msg = Utf.toString(getString(t, -1));
	pop(t);

	t.vm.exception = *ex;
	t.vm.isThrowing = true;

	// TODO: create traceback here

	throw new MDException(msg);
}

private void execute(MDThread* t, size_t depth = 1)
{
	MDException currentException = null;
	bool isReturning = false;
	MDValue RS;
	MDValue RT;

	_exceptionRetry:
	t.state = MDThread.State.Running;

	_reentry:
	auto stackBase = t.stackBase;
	auto constTable = t.currentAR.func.scriptFunc.constants;
	auto env = t.currentAR.func.environment;

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
					return t.currentAR.func.scriptUpvals()[index & ~Instruction.locMask].value;

				default:
					assert((index & Instruction.locMask) == Instruction.locGlobal, "get() location");

					auto name = constTable[index & ~Instruction.locMask].mString;

					for(auto ns = env; ns !is null; ns = ns.parent)
						if(auto glob = namespace.get(ns, name))
							return glob;

					throwException(t, "Attempting to get nonexistent global '{}'", name.toString32());
			}

			assert(false);
		}

		while(true)
		{
			if(t.shouldHalt)
				throw new MDHaltException(); // TODO: maybe just allocate this once?

			auto i = t.currentAR.pc;
			t.currentAR.pc++;

			switch(i.opcode)
			{
				// Binary Arithmetic
				case Op.Add: binOpImpl(t, MM.Add, get(i.rd), get(i.rs), get(i.rt)); break;
				case Op.Sub: binOpImpl(t, MM.Sub, get(i.rd), get(i.rs), get(i.rt)); break;
				case Op.Mul: binOpImpl(t, MM.Mul, get(i.rd), get(i.rs), get(i.rt)); break;
				case Op.Div: binOpImpl(t, MM.Div, get(i.rd), get(i.rs), get(i.rt)); break;
				case Op.Mod: binOpImpl(t, MM.Mod, get(i.rd), get(i.rs), get(i.rt)); break;

				// Unary Arithmetic
				case Op.Neg: negImpl(t, get(i.rd), get(i.rs)); break;

				// Reflexive Arithmetic
				case Op.AddEq: reflBinOpImpl(t, MM.AddEq, get(i.rd), get(i.rs)); break;
				case Op.SubEq: reflBinOpImpl(t, MM.SubEq, get(i.rd), get(i.rs)); break;
				case Op.MulEq: reflBinOpImpl(t, MM.MulEq, get(i.rd), get(i.rs)); break;
				case Op.DivEq: reflBinOpImpl(t, MM.DivEq, get(i.rd), get(i.rs)); break;
				case Op.ModEq: reflBinOpImpl(t, MM.ModEq, get(i.rd), get(i.rs)); break;

				// Inc/Dec
				case Op.Inc: incImpl(t, get(i.rd)); break;
				case Op.Dec: decImpl(t, get(i.rd)); break;

				// Binary Bitwise
				case Op.And:  binaryBinOpImpl(t, MM.And,  get(i.rd), get(i.rs), get(i.rt)); break;
				case Op.Or:   binaryBinOpImpl(t, MM.Or,   get(i.rd), get(i.rs), get(i.rt)); break;
				case Op.Xor:  binaryBinOpImpl(t, MM.Xor,  get(i.rd), get(i.rs), get(i.rt)); break;
				case Op.Shl:  binaryBinOpImpl(t, MM.Shl,  get(i.rd), get(i.rs), get(i.rt)); break;
				case Op.Shr:  binaryBinOpImpl(t, MM.Shr,  get(i.rd), get(i.rs), get(i.rt)); break;
				case Op.UShr: binaryBinOpImpl(t, MM.UShr, get(i.rd), get(i.rs), get(i.rt)); break;

				// Unary Bitwise
				case Op.Com: comImpl(t, get(i.rd), get(i.rs)); break;

				// Reflexive Bitwise
				case Op.AndEq:  reflBinaryBinOpImpl(t, MM.AndEq,  get(i.rd), get(i.rs)); break;
				case Op.OrEq:   reflBinaryBinOpImpl(t, MM.OrEq,   get(i.rd), get(i.rs)); break;
				case Op.XorEq:  reflBinaryBinOpImpl(t, MM.XorEq,  get(i.rd), get(i.rs)); break;
				case Op.ShlEq:  reflBinaryBinOpImpl(t, MM.ShlEq,  get(i.rd), get(i.rs)); break;
				case Op.ShrEq:  reflBinaryBinOpImpl(t, MM.ShrEq,  get(i.rd), get(i.rs)); break;
				case Op.UShrEq: reflBinaryBinOpImpl(t, MM.UShrEq, get(i.rd), get(i.rs)); break;

				// Data Transfer
				case Op.Move: *get(i.rd) = *get(i.rs); break;
				case Op.MoveLocal: t.stack[stackBase + i.rd] = t.stack[stackBase + i.rs]; break;
				case Op.LoadConst: t.stack[stackBase + i.rd] = constTable[i.rs & ~Instruction.locMask]; break;

				case Op.CondMove:
					auto RD = get(i.rd);

					if(RD.type == MDValue.Type.Null)
						*RD = *get(i.rs);
					break;

				case Op.LoadBool: *get(i.rd) = cast(bool)i.rs; break;
				case Op.LoadNull: *get(i.rd) = MDValue.nullValue; break;

				case Op.LoadNulls:
					auto start = stackBase + i.rd;
					t.stack[start .. start + i.imm] = MDValue.nullValue;
					break;

				case Op.NewGlobal:
					auto name = constTable[i.rt & ~Instruction.locMask].mString;

					if(namespace.contains(env, name))
						throwException(t, "Attempting to create global '{}' that already exists", name.toString32());

					namespace.set(t.vm.alloc, env, name, get(i.rs));
					break;

				// Logical and Control Flow
				case Op.Import:
					// TODO: this.
					assert(false, "Op.Import unimplemented");
// 					assert(t.stackIndex == t.currentAR.savedTop, "import: stack index not at top");
//
// 					RS = get(i.rs);
//
// 					if(RS.type != MDValue.Type.String)
// 					{
// 						typeString(t, &RS);
// 						throwException(t, "Import expression must be a string value, not '{}'", getString(t, -1));
// 					}
//
// 					try
// 						t.stack[stackBase + i.rd] = importModule(t, RS.mString);
// 					catch(MDRuntimeException e)
// 						throw e;
// 					catch(MDException e)
// 						throw new MDRuntimeException(startTraceback(), &e.value);

				case Op.Not: *get(i.rd) = get(i.rs).isFalse(); break;

				case Op.Cmp:
					auto jump = t.currentAR.pc;
					t.currentAR.pc++;

					auto cmpValue = compareImpl(t, get(i.rs), get(i.rt));

					if(jump.rd)
					{
						switch(jump.opcode)
						{
							case Op.Je:  if(cmpValue == 0) t.currentAR.pc += jump.imm; break;
							case Op.Jle: if(cmpValue <= 0) t.currentAR.pc += jump.imm; break;
							case Op.Jlt: if(cmpValue < 0)  t.currentAR.pc += jump.imm; break;
							default: assert(false, "invalid 'cmp' jump");
						}
					}
					else
					{
						switch(jump.opcode)
						{
							case Op.Je:  if(cmpValue != 0) t.currentAR.pc += jump.imm; break;
							case Op.Jle: if(cmpValue > 0)  t.currentAR.pc += jump.imm; break;
							case Op.Jlt: if(cmpValue >= 0) t.currentAR.pc += jump.imm; break;
							default: assert(false, "invalid 'cmp' jump");
						}
					}
					break;

				case Op.Cmp3:
					// Doing this to ensure evaluation of get(i.rd) happens _after_ compareImpl has executed
					auto val = compareImpl(t, get(i.rs), get(i.rt));
					*get(i.rd) = val;
					break;

				case Op.SwitchCmp:
					auto jump = t.currentAR.pc;
					t.currentAR.pc++;
					assert(jump.opcode == Op.Je && jump.rd == 1, "invalid 'swcmp' jump");

					if(switchCmpImpl(t, get(i.rs), get(i.rt)) == 0)
						t.currentAR.pc += jump.imm;

					break;

				case Op.Is:
					auto jump = t.currentAR.pc;
					t.currentAR.pc++;
					assert(jump.opcode == Op.Je, "invalid 'is' jump");

					if(get(i.rs).opEquals(*get(i.rt)) == jump.rd)
						t.currentAR.pc += jump.imm;

					break;

				case Op.IsTrue:
					auto jump = t.currentAR.pc;
					t.currentAR.pc++;
					assert(jump.opcode == Op.Je, "invalid 'istrue' jump");

					if(get(i.rs).isFalse() != cast(bool)jump.rd)
						t.currentAR.pc += jump.imm;

					break;

				case Op.Jmp:
					if(i.rd != 0)
						t.currentAR.pc += i.imm;
					break;

				case Op.Switch:
					auto st = &t.currentAR.func.scriptFunc.switchTables[i.rt];

					if(auto ptr = st.offsets.lookup(*get(i.rs)))
						t.currentAR.pc += *ptr;
					else
					{
						if(st.defaultOffset == -1)
							throwException(t, "Switch without default");

						t.currentAR.pc += st.defaultOffset;
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
					t.currentAR.pc += i.imm;
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
							t.currentAR.pc += i.imm;
						}
					}
					else
					{
						if(idx >= hi)
						{
							t.stack[stackBase + i.rd + 3] = idx;
							t.stack[stackBase + i.rd] = idx + step;
							t.currentAR.pc += i.imm;
						}
					}
					break;

				case Op.Foreach:
					auto jump = t.currentAR.pc;
					t.currentAR.pc++;
					assert(jump.opcode == Op.Je && jump.rd == 1, "invalid 'foreach' jump");

					auto rd = i.rd;
					auto funcReg = rd + 3;
					auto src = &t.stack[stackBase + rd];

					if(src.type != MDValue.Type.Function)
					{
						auto method = getMM(t, src, MM.Apply);

						if(method is null)
						{
							typeString(t, src);
							throwException(t, "No implementation of {} for type '{}'", MetaNames[MM.Apply], getString(t, -1));
						}

						t.stack[stackBase + rd + 2] = t.stack[stackBase + rd + 1];
						t.stack[stackBase + rd + 1] = *src;
						t.stack[stackBase + rd] = method;

						t.stackIndex = stackBase + rd + 3;
						rawCall(t, rd, 3);
						t.stackIndex = t.currentAR.savedTop;
					}

					t.stack[stackBase + funcReg + 2] = t.stack[stackBase + rd + 2];
					t.stack[stackBase + funcReg + 1] = t.stack[stackBase + rd + 1];
					t.stack[stackBase + funcReg] = t.stack[stackBase + rd];

					t.stackIndex = stackBase + funcReg + 3;
					rawCall(t, funcReg, i.imm);
					t.stackIndex = t.currentAR.savedTop;

					if(t.stack[stackBase + funcReg].type != MDValue.Type.Null)
					{
						t.stack[stackBase + rd + 2] = t.stack[stackBase + funcReg];
						t.currentAR.pc += jump.imm;
					}
					break;

				// Exception Handling
				case Op.PushCatch:
					auto tr = pushTR(t);
					tr.isCatch = true;
					tr.catchVarSlot = cast(RelStack)i.rd;
					tr.pc = t.currentAR.pc + i.imm;
					break;

				case Op.PushFinally:
					auto tr = pushTR(t);
					tr.isCatch = false;
					tr.pc = t.currentAR.pc + i.imm;
					break;

				case Op.PopCatch: popTR(t); break;

				case Op.PopFinally:
					currentException = null;
					popTR(t);
					break;

				case Op.EndFinal:
					if(currentException !is null)
						throw currentException;

					if(isReturning)
					{
						if(t.trIndex > 0)
						{
							while(t.currentTR.actRecord is t.arIndex)
							{
								auto tr = *t.currentTR;
								popTR(t);

								if(!tr.isCatch)
								{
									t.currentAR.pc = tr.pc;
									goto _exceptionRetry;
								}
							}
						}

						close(t, stackBase);
						callEpilogue(t, true);

						depth--;

						if(depth == 0)
							return;

						isReturning = false;
						goto _reentry;
					}
					break;

				case Op.Throw: throwImpl(t, get(i.rs)); break;

				// Function Calling
			{
				bool isScript = void;
				nint numResults = void;

				case Op.Method, Op.MethodNC, Op.SuperMethod:
					auto call = t.currentAR.pc;
					t.currentAR.pc++;

					RT = *get(i.rt);

					if(RT.type != MDValue.Type.String)
					{
						typeString(t, &RT);
						throwException(t, "Attempting to get a method with a non-string name (type '{}' instead)", getString(t, -1));
					}

					auto methodName = RT.mString;
					auto self = get(i.rs);

					if(i.opcode != Op.SuperMethod)
						RS = *self;
					else
					{
						if(t.currentAR.proto is null)
							throwException(t, "Attempting to perform a supercall in a function where there is no super object");

						if(self.type != MDValue.Type.Object)
						{
							typeString(t, self);
							throwException(t, "Attempting to perform a supercall in a function where 'this' is a '{}', not an 'object'", getString(t, -1));
						}

						RS = t.currentAR.proto;
					}

					numResults = call.rt - 1;
					size_t numParams = void;

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
					size_t numParams = void;

					if(i.rs == 0)
						numParams = t.stackIndex - (stackBase + i.rd + 1);
					else
					{
						numParams = i.rs - 1;
						t.stackIndex = stackBase + i.rd + i.rs;
					}

					isScript = callPrologue(t, stackBase + i.rd, numResults, numParams, null);

					// fall through
				_commonCall:
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
					size_t numParams = void;

					if(i.rs == 0)
						numParams = t.stackIndex - (stackBase + i.rd + 1);
					else
					{
						numParams = i.rs - 1;
						t.stackIndex = stackBase + i.rd + i.rs;
					}

					isScript = callPrologue(t, stackBase + i.rd, numResults, numParams, null);

					// fall through
				_commonTailcall:
					if(isScript)
					{
						auto prevAR = t.currentAR - 1;
						close(t, prevAR.base);

						ptrdiff_t diff = cast(ptrdiff_t)(t.currentAR.returnSlot - prevAR.returnSlot);

						auto tc = prevAR.numTailcalls + 1;
						*prevAR = *t.currentAR;
						prevAR.numTailcalls = tc;

						prevAR.base -= diff;
						prevAR.savedTop -= diff;
						prevAR.vargBase -= diff;
						prevAR.returnSlot -= diff;

						for(auto idx = prevAR.returnSlot; idx < prevAR.savedTop; idx++)
							t.stack[idx] = t.stack[idx + diff];

						goto _reentry;
					}
					
					// Do nothing for native calls.  The following return instruction will catch it.
					break;
			}

				case Op.Ret:
					auto firstResult = stackBase + i.rd;

					if(i.imm == 0)
					{
						saveResults(t, t, firstResult, t.stackIndex - firstResult);
						t.stackIndex = t.currentAR.savedTop;
					}
					else
						saveResults(t, t, firstResult, i.imm - 1);

					isReturning = true;

					if(t.trIndex > 0)
					{
						while(t.currentTR.actRecord is t.arIndex)
						{
							auto tr = *t.currentTR;
							popTR(t);

							if(!tr.isCatch)
							{
								t.currentAR.pc = tr.pc;
								goto _exceptionRetry;
							}
						}
					}

					close(t, stackBase);
					callEpilogue(t, true);
					
					depth--;

					if(depth == 0)
						return;

					isReturning = false;
					goto _reentry;

				case Op.Vararg:
					auto numVarargs = stackBase - t.currentAR.vargBase;
					auto dest = stackBase + i.rd;

					size_t numNeeded = void;

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
						t.stack[dest .. dest + numNeeded] = t.stack[src .. src + numNeeded];
					else
					{
						t.stack[dest .. dest + numVarargs] = t.stack[src .. src + numVarargs];
						t.stack[dest + numVarargs .. dest + numNeeded] = MDValue.nullValue;
					}

					break;

				case Op.VargLen: *get(i.rd) = cast(mdint)(stackBase - t.currentAR.vargBase); break;

				case Op.VargIndex:
					auto numVarargs = stackBase - t.currentAR.vargBase;

					RS = *get(i.rs);

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

					*get(i.rd) = t.stack[t.currentAR.vargBase + index];
					break;

				case Op.VargIndexAssign:
					auto numVarargs = stackBase - t.currentAR.vargBase;

					RS = *get(i.rs);

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

					t.stack[t.currentAR.vargBase + index] = *get(i.rt);
					break;

				case Op.VargSlice:
					auto numVarargs = stackBase - t.currentAR.vargBase;
					
					mdint lo = void;
					mdint hi = void;

					if(!correctIndices(lo, hi, get(i.rd), get(i.rd + 1), numVarargs))
					{
						typeString(t, &RS);
						typeString(t, &RT);
						throwException(t, "Attempting to slice 'vararg' with '{}' and '{}'", getString(t, -2), getString(t, -1));
					}

					if(lo > hi || lo < 0 || lo > numVarargs || hi < 0 || hi > numVarargs)
						throwException(t, "Invalid vararg slice indices [{} .. {}]", lo, hi);

					auto sliceSize = hi - lo;
					auto src = stackBase + lo;
					auto dest = stackBase + i.rd;

					size_t numNeeded = void;

					if(i.uimm == 0)
					{
						numNeeded = sliceSize;
						t.stackIndex = dest + sliceSize;
						checkStack(t, t.stackIndex);
					}
					else
						numNeeded = i.uimm - 1;

					if(numNeeded <= sliceSize)
						t.stack[dest .. dest + numNeeded] = t.stack[src .. src + numNeeded];
					else
					{
						t.stack[dest .. dest + sliceSize] = t.stack[src .. src + sliceSize];
						t.stack[dest + sliceSize .. dest + numNeeded] = MDValue.nullValue;
					}
					break;

				case Op.Yield:
					auto firstValue = stackBase + i.rd;
					auto ar = pushAR(t);

					assert(t.arIndex > 1);
					*ar = t.actRecs[t.arIndex - 2];

					ar.returnSlot = firstValue;
					ar.numReturns = i.rt - 1;
					ar.firstResult = 0;
					ar.numResults = 0;

					if(i.rs == 0)
						t.numYields = t.stackIndex - firstValue;
					else
					{
						t.stackIndex = firstValue + i.rs - 1;
						t.numYields = i.rs - 1;
					}

					t.state = MDThread.State.Suspended;
					Fiber.yield();
					t.state = MDThread.State.Running;
					callEpilogue(t, true);
					break;

				case Op.CheckParams:
					foreach(idx, mask; t.currentAR.func.scriptFunc.paramMasks)
					{
						auto val = &t.stack[(stackBase + idx)];

						if(!(mask & (1 << val.type)))
						{
							typeString(t, val);

							if(idx == 0)
								throwException(t, "'this' parameter: type '{}' is not allowed", getString(t, -1));
							else
								throwException(t, "Parameter {}: type '{}' is not allowed", idx, getString(t, -1));
						}
					}
					break;

				case Op.CheckObjParam:
					RS = t.stack[(stackBase + i.rs)];
					RT = *get(i.rt);

					assert(RS.type == MDValue.Type.Object, "oops.  why wasn't this checked?");

					if(RT.type != MDValue.Type.Object)
					{
						typeString(t, &RT);
						throwException(t, "Parameter {}: object constraint type must be 'object', not '{}'", i.rs, getString(t, -1));
					}

					if(!obj.derivesFrom(RS.mObject, RT.mObject))
					{
						typeString(t, &RS);
						throwException(t, "Parameter {}: type '{}' is not allowed", i.rs, getString(t, -1));
					}
					break;

				// Array and List Operations
				case Op.Length: lenImpl(t, get(i.rd), get(i.rs)); break;
				case Op.LengthAssign: lenaImpl(t, get(i.rd), get(i.rs)); break;
				case Op.Append: array.append(t.vm.alloc, t.stack[(stackBase + i.rd)].mArray, get(i.rs)); break;

				case Op.SetArray:
					auto sliceBegin = stackBase + i.rd + 1;
					auto a = t.stack[(stackBase + i.rd)].mArray;

					if(i.rs == 0)
					{
						array.setBlock(t.vm.alloc, a, i.rt, t.stack[sliceBegin .. t.stackIndex]);
						t.stackIndex = t.currentAR.savedTop;
					}
					else
						array.setBlock(t.vm.alloc, a, i.rt, t.stack[sliceBegin .. sliceBegin + i.rs - 1]);

					break;

				case Op.SetAttrs:
					auto RD = get(i.rd);

					if(RD.type == MDValue.Type.Object)
						RD.mObject.attrs = get(i.rs).mTable;
					else if(RD.type == MDValue.Type.Namespace)
						RD.mNamespace.attrs = get(i.rs).mTable;
					else
						assert(false, "invalid setattrs dest");
					break;

				case Op.Cat:
					catImpl(t, get(i.rd), stackBase + i.rs, i.rt);
					maybeGC(t.vm);
					break;

				case Op.CatEq:
					assert(i.rd == i.rs - 1);
					catEqImpl(t, stackBase + i.rd, i.rt + 1);
					maybeGC(t.vm);
					break;

				case Op.Index: idxImpl(t, get(i.rd), get(i.rs), get(i.rt), false); break;
				case Op.IndexAssign: idxaImpl(t, get(i.rd), get(i.rs), get(i.rt), false); break;

				case Op.Field:
					RT = *get(i.rt);

					if(RT.type != MDValue.Type.String)
					{
						typeString(t, &RT);
						throwException(t, "Field name must be a string, not a '{}'", getString(t, -1));
					}

					fieldImpl(t, get(i.rd), get(i.rs), RT.mString, false);
					break;

				case Op.FieldAssign:
					RS = *get(i.rs);

					if(RS.type != MDValue.Type.String)
					{
						typeString(t, &RS);
						throwException(t, "Field name must be a string, not a '{}'", getString(t, -1));
					}
					
					fieldaImpl(t, get(i.rd), RS.mString, get(i.rt), false);
					break;

				case Op.Slice:
					auto base = &t.stack[stackBase + i.rs];
					sliceImpl(t, get(i.rd), base, base + 1, base + 2);
					break;

				case Op.SliceAssign:
					auto base = &t.stack[stackBase + i.rd];
					sliceaImpl(t, base, base + 1, base + 2, get(i.rs));
					break;

				case Op.NotIn:
					auto val = !inImpl(t, get(i.rs), get(i.rt));
					*get(i.rd) = val;
					break;

				case Op.In:
					auto val = inImpl(t, get(i.rs), get(i.rt));
					*get(i.rd) = val;
					break;

				// Value Creation
				case Op.NewArray:
					t.stack[stackBase + i.rd] = array.create(t.vm.alloc, i.uimm);
					maybeGC(t.vm);
					break;

				case Op.NewTable:
					t.stack[stackBase + i.rd] = table.create(t.vm.alloc);
					maybeGC(t.vm);
					break;

				case Op.Closure:
					auto newDef = t.currentAR.func.scriptFunc.innerFuncs[i.rs];
					auto n = func.create(t.vm.alloc, env, newDef);
					auto upvals = n.scriptUpvals();
					auto currentUpvals = t.currentAR.func.scriptUpvals();

					for(size_t index = 0; index < newDef.numUpvals; index++)
					{
						assert(t.currentAR.pc.opcode == Op.Move, "invalid closure upvalue op");

						if(t.currentAR.pc.rd == 0)
							upvals[index] = findUpvalue(t, t.currentAR.pc.rs);
						else
						{
							assert(t.currentAR.pc.rd == 1, "invalid closure upvalue rd");
							upvals[index] = currentUpvals[t.currentAR.pc.uimm];
						}

						t.currentAR.pc++;
					}

					if(i.rt != 0)
						n.attrs = get(i.rt - 1).mTable;

					*get(i.rd) = n;
					maybeGC(t.vm);
					break;

				case Op.SetEnv: get(i.rd).mFunction.environment = get(i.rs).mNamespace; break;

				case Op.Object:
					RS = *get(i.rs);
					RT = *get(i.rt);

					if(RT.type != MDValue.Type.Object)
					{
						typeString(t, &RT);
						throwException(t, "Attempting to derive an object from a value of type '{}'", getString(t, -1));
					}
					else
					{
						if(RS.type == MDValue.Type.Null)
							*get(i.rd) = obj.create(t.vm.alloc, RT.mObject.name, RT.mObject);
						else
							*get(i.rd) = obj.create(t.vm.alloc, RS.mString, RT.mObject);
					}

					maybeGC(t.vm);
					break;

				case Op.Coroutine:
					RS = *get(i.rs);

					if(RS.type != MDValue.Type.Function)
					{
						typeString(t, &RS);
						throwException(t, "Coroutines must be created with a function, not '{}'", getString(t, -1));
					}

					*get(i.rd) = thread.create(t.vm, RS.mFunction);
					break;

				case Op.Namespace:
					RS = *get(i.rs);
					RT = *get(i.rt);

					if(RT.type == MDValue.Type.Null)
						*get(i.rd) = namespace.create(t.vm.alloc, RS.mString);
					else if(RT.type != MDValue.Type.Namespace)
					{
						typeString(t, &RT);
						toStringImpl(t, RS, false);
						throwException(t, "Attempted to use a '{}' as a parent namespace for namespace '{}'", getString(t, -2), getString(t, -1));
					}
					else
						*get(i.rd) = namespace.create(t.vm.alloc, RS.mString, RT.mNamespace);

					maybeGC(t.vm);
					break;

				case Op.NamespaceNP:
					auto tmp = namespace.create(t.vm.alloc, get(i.rs).mString, env);
					*get(i.rd) = tmp;
					maybeGC(t.vm);
					break;

				// Class stuff
				case Op.As:
					RS = *get(i.rs);
					RT = *get(i.rt);

					if(RT.type != MDValue.Type.Object)
					{
						typeString(t, &RT);
						throwException(t, "Attempted to use 'as' with a '{}' as the type, not 'object'", getString(t, -1));
					}

					if(RS.type == MDValue.Type.Object && obj.derivesFrom(RS.mObject, RT.mObject))
						*get(i.rd) = RS;
					else
						*get(i.rd) = MDValue.nullValue;

					break;

				case Op.SuperOf:
					RS = *get(i.rs);

					if(RS.type == MDValue.Type.Object)
					{
						if(auto p = RS.mObject.proto)
							*get(i.rd) = p;
						else
							*get(i.rd) = MDValue.nullValue;
					}
					else if(RS.type == MDValue.Type.Namespace)
					{
						if(auto p = RS.mNamespace.parent)
							*get(i.rd) = p;
						else
							*get(i.rd) = MDValue.nullValue;
					}
					else
					{
						typeString(t, &RS);
						throwException(t, "Can only get super of objects and namespaces, not '{}'", getString(t, -1));
					}
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
		while(depth > 0)
		{
			while(t.currentTR.actRecord is t.arIndex)
			{
				auto tr = *t.currentTR;
				popTR(t);

				if(tr.isCatch)
				{
					auto base = stackBase + tr.catchVarSlot;

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

			callEpilogue(t, false);

// TODO: this
// 			if(t.currentAR.func !is null)
// 			{
// 				mContext.mTraceback ~= getDebugLocation();
//
// 				for(int call = 0; call < mCurrentAR.numTailcalls; call++)
// 					mContext.mTraceback ~= Location("<tailcall>", 0, 0);
// 			}

			depth--;
		}

		throw e;
	}
	catch(MDHaltException e)
	{
		while(depth > 0)
		{
			callEpilogue(t, false);
			depth--;
		}

		// TODO: investigate?
// 		if(t.nativeCallDepth > 0)
			throw e;

// 		return;
	}
}

const Unimpl = "assert(false, \"unimplemented!\");";