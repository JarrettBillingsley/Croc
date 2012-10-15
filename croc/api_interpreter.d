/******************************************************************************
This module contains most of the public "raw" API, as well as the Croc
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

module croc.api_interpreter;

import tango.core.Exception;
import tango.core.Memory;
import tango.core.Traits;
import tango.core.Tuple;
import tango.core.Vararg;

import croc.api_checks;
import croc.api_debug;
import croc.api_stack;
import croc.base_alloc;
import croc.base_gc;
import croc.base_metamethods;
import croc.interpreter;
import croc.types;
import croc.types_array;
import croc.types_class;
import croc.types_function;
import croc.types_instance;
import croc.types_memblock;
import croc.types_namespace;
import croc.types_nativeobj;
import croc.types_string;
import croc.types_table;
import croc.types_thread;
import croc.types_weakref;
import croc.utils;

private
{
	extern(C) void* rt_stackBottom();
	extern(C) void* rt_stackTop();
}

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

// ================================================================================================================================================
// VM-related functions

/**
Push the metatable for the given type. If the type has no metatable, pushes null. The type given must be
one of the "normal" types -- the "internal" types are illegal and an error will be thrown.

Params:
	type = The type whose metatable is to be pushed.

Returns:
	The stack index of the newly-pushed value (null if the type has no metatable, or a namespace if it does).
*/
word getTypeMT(CrocThread* t, CrocValue.Type type)
{
	mixin(FuncNameMix);

	// ORDER CROCVALUE TYPE
	if(!(type >= CrocValue.Type.FirstUserType && type <= CrocValue.Type.LastUserType))
	{
		if(type >= CrocValue.Type.min && type <= CrocValue.Type.max)
			throwStdException(t, "TypeException", __FUNCTION__ ~ " - Cannot get metatable for type '{}'", CrocValue.typeStrings[type]);
		else
			throwStdException(t, "ApiError", __FUNCTION__ ~ " - Invalid type '{}'", type);
	}

	if(auto ns = t.vm.metaTabs[cast(uword)type])
		return push(t, CrocValue(ns));
	else
		return pushNull(t);
}

/**
Sets the metatable for the given type to the namespace or null at the top of the stack. Throws an
error if the type given is one of the "internal" types, or if the value at the top of the stack is
neither null nor a namespace.

Params:
	type = The type whose metatable is to be set.
*/
void setTypeMT(CrocThread* t, CrocValue.Type type)
{
	mixin(apiCheckNumParams!("1"));

	// ORDER CROCVALUE TYPE
	if(!(type >= CrocValue.Type.FirstUserType && type <= CrocValue.Type.LastUserType))
	{
		if(type >= CrocValue.Type.min && type <= CrocValue.Type.max)
			throwStdException(t, "TypeException", __FUNCTION__ ~ " - Cannot set metatable for type '{}'", CrocValue.typeStrings[type]);
		else
			throwStdException(t, "ApiError", __FUNCTION__ ~ " - Invalid type '{}'", type);
	}

	auto v = getValue(t, -1);

	if(v.type == CrocValue.Type.Namespace)
		t.vm.metaTabs[cast(uword)type] = v.mNamespace;
	else if(v.type == CrocValue.Type.Null)
		t.vm.metaTabs[cast(uword)type] = null;
	else
		mixin(apiParamTypeError!("-1", "metatable", "namespace|null"));

	pop(t);
}

/**
Pushes the VM's registry namespace onto the stack. The registry is sort of a hidden global namespace only accessible
from native code and which native code may use for any purpose.

Returns:
	The stack index of the newly-pushed namespace.
*/
word getRegistry(CrocThread* t)
{
	return push(t, CrocValue(t.vm.registry));
}

/**
Allocates a block of memory using the given thread's VM's allocator function. This memory is $(B not) garbage-collected.
You must free the memory returned by this function in order to avoid memory leaks.

The array returned by this function should not have its length set or be appended to (~=).

Params:
	size = The size, in bytes, of the block to allocate.

Returns:
	A void array representing the memory block.
*/
void[] allocMem(CrocThread* t, uword size)
{
	return t.vm.alloc.allocArray!(void)(size);
}

/**
Resize a block of memory. $(B Only call this on memory that has been allocated using the allocMem, _resizeMem or dupMem
functions.)  If you pass this function an empty (0-length) memory block, it will allocate memory. If you resize an existing
block to a length of 0, it will deallocate that memory.

If you resize a block to a smaller size, its data will be truncated. If you resize a block to a larger size, the empty
space will be uninitialized.

The array returned by this function through the mem parameter should not have its length set or be appended to (~=).

Params:
	mem = A reference to the memory block you want to reallocate. This is a reference so that the original memory block
		reference that you pass in is updated. This can be a 0-length array.

	size = The size, in bytes, of the new size of the memory block.
*/
void resizeMem(CrocThread* t, ref void[] mem, uword size)
{
	t.vm.alloc.resizeArray(mem, size);
}

/**
Duplicate a block of memory. This is safe to call on memory that was not allocated with the thread's VM's allocator.
The new block will be the same size and contain the same data as the old block.

The array returned by this function should not have its length set or be appended to (~=).

Params:
	mem = The block of memory to copy. This is not required to have been allocated by allocMem, resizeMem, or _dupMem.

Returns:
	The new memory block.
*/
void[] dupMem(CrocThread* t, void[] mem)
{
	return t.vm.alloc.dupArray(mem);
}

/**
Free a block of memory. $(B Only call this on memory that has been allocated with allocMem, resizeMem, or dupMem.)
It's legal to free a 0-length block.

Params:
	mem = A reference to the memory block you want to free. This is a reference so that the original memory block
		reference that you pass in is updated. This can be a 0-length array.
*/
void freeMem(CrocThread* t, ref void[] mem)
{
	t.vm.alloc.freeArray(mem);
}

/**
Creates a reference to a Croc object. A reference is like the native equivalent of Croc's nativeobj. Whereas a
nativeobj allows Croc to hold a reference to a native object, a reference allows native code to hold a reference
to a Croc object.

References are identified by unique integer values which are passed to the  $(D pushRef) and $(D removeRef) functions.
These are guaranteed to be probabilistically to be unique for the life of the program. What I mean by that is that
if you created a million references per second, it would take you over half a million years before the reference
values wrapped around. Aren'_t 64-bit integers great?

References prevent the referenced Croc object from being collected, ever, so unless you want memory leaks, you must
call $(D removeRef) when your code no longer needs the object. See $(croc.ex) for some reference helpers.

Params:
	idx = The stack index of the object to which a reference should be created. If this refers to a value type,
		an exception will be thrown.

Returns:
	The new reference name for the given object. You can create several references to the same object; it will not
	be collectible until all references to it have been removed.
*/
ulong createRef(CrocThread* t, word idx)
{
	mixin(FuncNameMix);

	auto v = getValue(t, idx);

	if(!v.isGCObject())
	{
		pushTypeString(t, idx);
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - Can only get references to reference types, not '{}'", getString(t, -1));
	}

	auto ret = t.vm.currentRef++;
	*t.vm.refTab.insert(t.vm.alloc, ret) = v.mBaseObj;
	return ret;
}

/**
Pushes the object associated with the given reference onto the stack and returns the slot of the pushed object.
If the given reference is invalid, an exception will be thrown.
*/
word pushRef(CrocThread* t, ulong r)
{
	mixin(FuncNameMix);

	auto v = t.vm.refTab.lookup(r);

	if(v is null)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - Reference '{}' does not exist", r);

	return push(t, CrocValue(*v));
}

/**
Removes the given reference. When all references to an object are removed, it will no longer be considered to be
referenced by the host app and will be subject to normal GC rules. If the given reference is invalid, an
exception will be thrown.
*/
void removeRef(CrocThread* t, ulong r)
{
	mixin(FuncNameMix);

	if(!t.vm.refTab.remove(r))
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - Reference '{}' does not exist", r);
}


word pushThrowableClass(CrocThread* t)
{
	return push(t, CrocValue(t.vm.throwable));
}

word pushLocationClass(CrocThread* t)
{
	return push(t, CrocValue(t.vm.location));
}

// ================================================================================================================================================
// GC-related stuff

/**
Runs the garbage collector if necessary.

This will perform a garbage collection only if a sufficient amount of memory has been allocated since
the last collection.

Params:
	t = The thread to use to collect the garbage. Garbage collection is vm-wide but requires a thread
		in order to be able to call finalization methods.

Returns:
	The number of bytes collected, which may be 0.
*/
uword maybeGC(CrocThread* t)
{
	if(t.vm.alloc.gcDisabled > 0)
		return 0;

	if(t.vm.alloc.couldUseGC())
		return gc(t);
	else
		return 0;
}

/**
Runs the garbage collector unconditionally.

Params:
	t = The thread to use to collect the garbage. Garbage collection is vm-wide but requires a thread
		in order to be able to call finalization methods.
	fullCollect = If true, forces a full garbage collection this cycle. In the case of the currently-implemented
		GC, this forces the collector to run a cyclic garbage collection phase. Cyclic garbage must be scanned
		for occasionally when using a reference counting scheme, but it can be time-consuming. Normally it is only
		scanned for occasionally, but you can force it to occur.

Returns:
	The number of bytes collected by this collection cycle.
*/
uword gc(CrocThread* t, bool fullCollect = false)
{
	if(t.vm.alloc.gcDisabled > 0)
		return 0;

	auto beforeSize = t.vm.alloc.totalBytes;
	gcCycle(t.vm, fullCollect ? GCCycleType.Full : GCCycleType.Normal);
	runFinalizers(t);

	t.vm.stringTab.minimize(t.vm.alloc);
	t.vm.weakRefTab.minimize(t.vm.alloc);
	t.vm.allThreads.minimize(t.vm.alloc);

	auto ret = beforeSize > t.vm.alloc.totalBytes ? beforeSize - t.vm.alloc.totalBytes : 0; // This is.. possible? TODO: figure out how.

	getRegistry(t);
	field(t, -1, "gc.postGCCallbacks");

	foreach(word v; foreachLoop(t, 1))
	{
		dup(t, v);
		pushNull(t);
		rawCall(t, -2, 0);
	}

	pop(t);

	return ret;
}

/**
Changes various limits used by the garbage collector. Most have an effect on how often GC collections are run. You can set
these limits to better suit your program, or to enforce certain behaviors, but setting them incorrectly can cause the GC to
thrash, collecting way too often and hogging the CPU. Be careful.

Params:
	type = The type of limit to be set. The valid types are as follows:
	$(UL
		$(LI "nurseryLimit" - The size, in bytes, of the nursery generation. Defaults to 512KB. Most objects are initially
			allocated in the nursery. When the nursery fills up (the number of bytes allocated exceeds this limit), a collection
			will be triggered. Setting the nursery limit higher will cause collections to run less often, but they will take
			longer to complete. Setting the nursery limit lower will put more pressure on the older generation as it will not
			give young objects a chance to die off, as they usually do. Setting the nursery limit to 0 will cause a collection
			to be triggered on every allocation. That's probably bad.)

		$(LI "metadataLimit" - The size, in bytes, of the GC metadata. Defaults to 128KB. The metadata includes two buffers: one
			keeps track of which old-generation objects have been modified; the other keeps track of which old-generation objects
			need to have their reference counts decreased. This is pretty low-level stuff, but generally speaking, the more object
			mutation your program has, the faster these buffers will fill up. When they do, a collection is triggered. Much like
			the nursery limit, setting this value higher will cause collections to occur less often but they will take longer.
			Setting it lower will put more pressure on the older generation, as it will tend to pull objects out of the nursery
			before they can have a chance to die off. Setting the metadata limit to 0 will cause a collection to be triggered on
			every mutation. That's also probably bad!)

		$(LI "nurserySizeCutoff" - The maximum size, in bytes, of an object that can be allocated in the nursery. Defaults to 256.
			If an object is bigger than this, it will be allocated directly in the old generation instead. This avoids having large
			objects fill up the nursery and causing more collections than necessary. Chances are this won't happen too often, unless
			you're allocating really huge class instances. Setting this value to 0 will effectively turn the GC algorithm into a
			regular deferred reference counting GC, with only one generation. Maybe that'd be useful for you?)

		$(LI "cycleCollectInterval" - Since the Croc reference implementation uses a form of reference counting to do garbage
			collection, it must detect cyclic garbage (which would otherwise never be freed). Cyclic garbage usually forms only a
			small part of all garbage, but ignoring it would cause memory leaks. In order to avoid that, the GC must occasionally
			run a separate cycle collection algorithm during the GC cycle. This is triggered when enough potential cyclic garbage is
			buffered (see the next limit type for that), or every $(I n) collections, whichever comes first. This limit is that $(I n).
			It defaults to 50; that is, every 50 garbage collection cycles, a cycle collection will be forced, regardless of how much
			potential cyclic garbage has been buffered. Setting this limit to 0 will force a cycle collection at every GC cycle, which
			isn't that great for performance. Setting this limit very high will cause cycle collections only to be triggered if
			enough potential cyclic garbage is buffered, but it's then possible that that garbage can hang around until program end,
			wasting memory.)

		$(LI "cycleMetadataLimit" - As explained above, the GC will buffer potential cyclic garbage during normal GC cycles, and then
			when a cycle collection is initiated, it will look at that buffered garbage and determine whether it really is garbage.
			This limit is similar to metadataLimit in that it measures the size of a buffer, and when that buffer size crosses this
			limit, a cycle collection is triggered. This defaults to 128KB. The more cyclic garbage your program produces, the faster
			this buffer will fill up. Note that Croc is somewhat smart about what it considers potential cyclic garbage; only objects
			whose reference counts decrease to a non-zero value are candidates for cycle collection. Of course, this is only a heuristic,
			and can have false positives, meaning non-cyclic objects (living or dead) can be scanned by the cycle collector as well.
			Thus the cycle collector must be run to reclaim ALL dead objects.)
	)

	lim = The limit value. Its meaning is determined by the type parameter.

Returns:
	The previous value of the limit that was set.
*/
uword gcLimit(CrocThread* t, char[] type, uword lim)
{
	switch(type)
	{
		case "nurseryLimit":         auto ret = t.vm.alloc.nurseryLimit;       t.vm.alloc.nurseryLimit = lim;       return ret;
		case "metadataLimit":        auto ret = t.vm.alloc.metadataLimit;      t.vm.alloc.metadataLimit = lim;      return ret;
		case "nurserySizeCutoff":    auto ret = t.vm.alloc.nurserySizeCutoff;  t.vm.alloc.nurserySizeCutoff = lim;  return ret;
		case "cycleCollectInterval": auto ret = t.vm.alloc.nextCycleCollect;   t.vm.alloc.nextCycleCollect = lim;   return ret;
		case "cycleMetadataLimit":   auto ret = t.vm.alloc.cycleMetadataLimit; t.vm.alloc.cycleMetadataLimit = lim; return ret;
		default: throwStdException(t, "ValueException", "Invalid limit type '{}'", type);
	}

	assert(false);
}

/**
Gets the current values of various GC limits. For an explanation of the valid limit types, see the other overload of this function.

Params:
	type = See the other overload of gcLimit.

Returns:
	The current value of the given limit.
*/
uword gcLimit(CrocThread* t, char[] type)
{
	switch(type)
	{
		case "nurseryLimit":         return t.vm.alloc.nurseryLimit;
		case "metadataLimit":        return t.vm.alloc.metadataLimit;
		case "nurserySizeCutoff":    return t.vm.alloc.nurserySizeCutoff;
		case "cycleCollectInterval": return t.vm.alloc.nextCycleCollect;
		case "cycleMetadataLimit":   return t.vm.alloc.cycleMetadataLimit;
		default: throwStdException(t, "ValueException", "Invalid limit type '{}'", type);
	}

	assert(false);
}

// ================================================================================================================================================
// Pushing values onto the stack

/**
These push a value of the given type onto the stack.

Returns:
	The stack index of the newly-pushed value.
*/
word pushNull(CrocThread* t)
{
	return push(t, CrocValue.nullValue);
}

/// ditto
word pushBool(CrocThread* t, bool v)
{
	return push(t, CrocValue(v));
}

/// ditto
word pushInt(CrocThread* t, crocint v)
{
	return push(t, CrocValue(v));
}

/// ditto
word pushFloat(CrocThread* t, crocfloat v)
{
	return push(t, CrocValue(v));
}

/// ditto
word pushChar(CrocThread* t, dchar v)
{
	return push(t, CrocValue(v));
}

/// ditto
word pushString(CrocThread* t, char[] v)
{
	return push(t, CrocValue(createString(t, v)));
}

/**
Push a formatted string onto the stack. This works exactly like tango.text.convert.Layout (and in fact
calls it), except that the destination buffer is a Croc string.

Params:
	fmt = The Tango-style format string.
	... = The arguments to be formatted.

Returns:
	The stack index of the newly-pushed string.
*/
word pushFormat(CrocThread* t, char[] fmt, ...)
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
word pushVFormat(CrocThread* t, char[] fmt, TypeInfo[] arguments, va_list argptr)
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

	try
		t.vm.formatter.convert(&sink, arguments, argptr, fmt);
	catch(CrocException e)
		throw e;
	catch(Exception e)
		throwStdException(t, "ValueException", "Error during string formatting: {}", e);

	maybeGC(t);

	if(numPieces == 0)
		return pushString(t, "");
	else
		return cat(t, numPieces);
}

/**
Creates a new table object and pushes it onto the stack.

Params:
	size = The number of slots to preallocate in the table, as an optimization.

Returns:
	The stack index of the newly-created table.
*/
word newTable(CrocThread* t, uword size = 0)
{
	maybeGC(t);
	return push(t, CrocValue(table.create(t.vm.alloc, size)));
}

/**
Creates a new array object and pushes it onto the stack.

Params:
	len = The length of the new array.

Returns:
	The stack index of the newly-created array.
*/
word newArray(CrocThread* t, uword len)
{
	maybeGC(t);
	return push(t, CrocValue(array.create(t.vm.alloc, len)));
}

/**
Creates a new array object using values at the top of the stack. Pops those values and pushes
the new array onto the stack.

Params:
	len = How many values on the stack to be put into the array, and the length of the resulting
		array.

Returns:
	The stack index of the newly-created array.
*/
word newArrayFromStack(CrocThread* t, uword len)
{
	mixin(apiCheckNumParams!("len"));
	maybeGC(t);
	auto a = array.create(t.vm.alloc, len);
	array.sliceAssign(t.vm.alloc, a, 0, len, t.stack[t.stackIndex - len .. t.stackIndex]);
	pop(t, len);
	return push(t, CrocValue(a));
}

/**
Creates a new memblock object and pushes it onto the stack.

Params:
	len = The length of the memblock in bytes. Can be 0.

Returns:
	The stack index of the newly-created memblock.
*/
word newMemblock(CrocThread* t, uword len)
{
	maybeGC(t);
	return push(t, CrocValue(memblock.create(t.vm.alloc, len)));
}

/**
Creates a new memblock object whose data is a copy of a native array. The resulting memblock will
own its data and the original array will not be referenced in any way.

Params:
	arr = The source data array.

Returns:
	The stack index of the newly-created memblock.
*/
word memblockFromNativeArray(CrocThread* t, void[] arr)
{
	auto ret = newMemblock(t, arr.length);
	auto data = cast(void[])getMemblock(t, ret).data;
	data[] = arr[];
	return ret;
}

/**
Creates a new memblock object whose data is a view into a native array.

This means that $(B the memblock will point into the native heap.) As a result, it is the responsibility
of the host program to ensure that this data is valid for the lifetime of the memblock. If it becomes
invalid, script code can crash the host. The resulting memblock will $(B not) own its data.

Params:
	arr = The array to create a view of.

Returns:
	The stack index of the newly-created memblock.
*/
word memblockViewNativeArray(CrocThread* t, void[] arr)
{
	return push(t, CrocValue(memblock.createView(t.vm.alloc, arr)));
}

/**
Creates a new native closure and pushes it onto the stack.

If you want to associate upvalues with the function, you should push them in order on
the stack before calling newFunction and then pass how many upvalues you pushed.
An example:

-----
// 1. Push any upvalues. Here we have two. Note that they are pushed in order:
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
	name = The _name to be given to the function. This is just the 'debug' _name that
		shows up in error messages. In order to make the function accessible, you have
		to actually put the resulting closure somewhere, like in the globals, or in
		a namespace.
	numUpvals = How many upvalues there are on the stack under the _name to be associated
		with this closure. Defaults to 0.

Returns:
	The stack index of the newly-created closure.
*/
word newFunction(CrocThread* t, NativeFunc func, char[] name, uword numUpvals = 0)
{
	pushEnvironment(t);
	return newFunctionWithEnv(t, func, name, numUpvals);
}

/**
Same as above, but allows you to set the maximum allowable number of parameters that can
be passed to this function. If more than numParams parameters are passed to this function,
an exception will be thrown. If fewer are passed, it is not an error.
*/
word newFunction(CrocThread* t, uint numParams, NativeFunc func, char[] name, uword numUpvals = 0)
{
	pushEnvironment(t);
	return newFunctionWithEnv(t, numParams, func, name, numUpvals);
}

/**
Creates a new native closure with an explicit environment and pushes it onto the stack.

Very similar to newFunction, except that it also expects the environment for the function
(a namespace) to be on top of the stack. Using newFunction's example, one would push
the environment namespace after step 1, and step 2 would call newFunctionWithEnv instead.

Params:
	func = The native function to be used in the closure.
	name = The _name to be given to the function. This is just the 'debug' _name that
		shows up in error messages. In order to make the function accessible, you have
		to actually put the resulting closure somewhere, like in the globals, or in
		a namespace.
	numUpvals = How many upvalues there are on the stack under the _name and environment to
		be associated with this closure. Defaults to 0.

Returns:
	The stack index of the newly-created closure.
*/
word newFunctionWithEnv(CrocThread* t, NativeFunc func, char[] name, uword numUpvals = 0)
{
	return newFunctionWithEnv(t, .func.MaxParams, func, name, numUpvals);
}

/**
Same as above, but allows you to set the maximum allowable number of parameters that can
be passed to this function. See newFunction for more details.
*/
word newFunctionWithEnv(CrocThread* t, uint numParams, NativeFunc func, char[] name, uword numUpvals = 0)
{
	mixin(apiCheckNumParams!("numUpvals + 1"));

	auto env = getNamespace(t, -1);

	if(env is null)
		mixin(apiParamTypeError!("-1", "environment", "namespace"));

	maybeGC(t);

	auto f = .func.create(t.vm.alloc, env, createString(t, name), func, numUpvals, numParams);
	f.nativeUpvals()[] = t.stack[t.stackIndex - 1 - numUpvals .. t.stackIndex - 1];
	pop(t, numUpvals + 1); // upvals and env.

	return push(t, CrocValue(f));
}

/**
Creates a new script function closure and pushes it on the stack.

The given function definition may not have any upvalues. If it does, an error will be thrown.

If the definition is cacheable and there is already an instantiation of it, then the cached instantiation
will be pushed. Otherwise, a new closure will be created (and cached if the definition is cacheable). In the
case that a new closure is created, its environment will be the current environment. To use a different
environment, use newFunctionWithEnv.

Params:
	funcDef: The stack index of the function definition object.

Returns:
	The stack index of the new closure.
*/
word newFunction(CrocThread* t, word funcDef)
{
	funcDef = absIndex(t, funcDef);
	pushEnvironment(t);
	return newFunctionWithEnv(t, funcDef);
}

/**
Same as above, except it expects an explicit environment object to be at the top of the stack. This environment
is popped and the new closure is pushed in its place. If the given function definition is cacheable and has a
cached instantiation already, the environment on the stack is ignored. This is because such a situation is impossible
within the language. In Croc, if a function is judged to be cacheable, then it is impossible to create closures
of it with different environments.

Params:
	funcDef: The stack index of the function definition object.

Returns:
	The stack index of the new closure.
*/
word newFunctionWithEnv(CrocThread* t, word funcDef)
{
	mixin(apiCheckNumParams!("1"));

	funcDef = absIndex(t, funcDef);
	auto def = getFuncDef(t, funcDef);

	if(def is null)
	{
		pushTypeString(t, funcDef);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - funcDef must be a function definition, not a '{}'", getString(t, -1));
	}

	if(def.numUpvals > 0)
		throwStdException(t, "ValueException", __FUNCTION__ ~ " - Function definition may not have any upvalues");

	auto env = getNamespace(t, -1);

	if(env is null)
	{
		pushTypeString(t, -1);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Environment must be a namespace, not a '{}'", getString(t, -1));
	}

	maybeGC(t);
	auto ret = .func.create(t.vm.alloc, env, def);

	if(ret is null)
	{
		pushToString(t, funcDef);
		throwStdException(t, "RuntimeException", __FUNCTION__ ~ " - Attempting to instantiate {} with a different namespace than was associated with it", getString(t, -1));
	}

	pop(t);
	return push(t, CrocValue(ret));
}

/**
Creates a new class and pushes it onto the stack.

After creating the class, you can then fill it with members by using fielda.

Params:
	base = The stack index of the _base class. The _base can be `null`, in which case the new class will have no base
		class. Otherwise it must be a class.

	name = The _name of the class. Remember that you still have to store the class object somewhere,
		though, like in a global.

Returns:
	The stack index of the newly-created class.
*/
word newClass(CrocThread* t, word base, char[] name)
{
	mixin(FuncNameMix);

	CrocClass* b = void;

	if(isNull(t, base))
		b = null;
	else if(auto c = getClass(t, base))
		b = c;
	else
	{
		pushTypeString(t, base);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Base must be 'null' or 'class', not '{}'", getString(t, -1));
	}

	maybeGC(t);
	return push(t, CrocValue(classobj.create(t.vm.alloc, createString(t, name), b)));
}

/**
Same as above, except it uses null as the base. The new class is left on the top of the stack.
*/
word newClass(CrocThread* t, char[] name)
{
	mixin(FuncNameMix);
	maybeGC(t);
	return push(t, CrocValue(classobj.create(t.vm.alloc, createString(t, name), null)));
}

/**
Creates an instance of a class and pushes it onto the stack. This does $(I not) call any
constructors defined for the class; this simply allocates an instance.

Croc instances can have two kinds of extra data associated with them for use by the host: extra
Croc values and arbitrary bytes. The structure of a Croc instance is something like this:

-----
// ---------
// |       |
// |       | The data that's part of every instance - its parent class, fields, and finalizer.
// |       |
// +-------+
// |0: "x" | Extra Croc values which can point into the Croc heap.
// |1: 5   |
// +-------+
// |...   | Arbitrary byte data.
// ---------
-----

Both extra sections are optional, and no instances created from script classes will have them.

Extra Croc values are useful for adding "members" to the instance which are not visible to the
scripts but which can still hold Croc objects. They will be scanned by the GC, so objects
referenced by these members will not be collected. If you want to hold a reference to a native
D object, for instance, this would be the place to put it (wrapped in a NativeObject).

The arbitrary bytes associated with an instance are not scanned by either the D or the Croc GC,
so don'_t store references to GC'ed objects there. These bytes are useable for just about anything,
such as storing values which can'_t be stored in Croc values -- structs, complex numbers, long
integers, whatever.

A clarification: You can store references to $(B heap) objects in the extra bytes, but you must not
store references to $(B GC'ed) objects there. That is, you can 'malloc' some data and store the pointer
in the extra bytes, since that's not GC'ed memory. You must however perform your own memory management for
such memory. You can set up a finalizer function for instances in which you can perform memory management
for these references.

Params:
	base = The class from which this instance will be created.
	numValues = How many extra Croc values will be associated with the instance. See above.
	extraBytes = How many extra bytes to attach to the instance. See above.
*/
word newInstance(CrocThread* t, word base)
{
	mixin(FuncNameMix);

	auto b = getClass(t, base);

	if(b is null)
	{
		pushTypeString(t, base);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - expected 'class' for base, not '{}'", getString(t, -1));
	}

	maybeGC(t);
	return push(t, CrocValue(instance.create(t.vm, b)));
}

/**
Creates a new namespace object and pushes it onto the stack.

The parent of the new namespace will be the current function environment, exactly
as in Croc when you declare a namespace without an explicit parent.

Params:
	name = The _name of the namespace.

Returns:
	The stack index of the newly-created namespace.
*/
word newNamespace(CrocThread* t, char[] name)
{
	push(t, CrocValue(getEnv(t)));
	newNamespace(t, -1, name);
	insertAndPop(t, -2);
	return stackSize(t) - 1;
}

/**
Creates a new namespace object with an explicit parent and pushes it onto the stack.

Params:
	parent = The stack index of the _parent. The _parent can be null, in which case
		the new namespace will not have a _parent. Otherwise it must be a namespace.
	name = The _name of the namespace.

Returns:
	The stack index of the newly-created namespace.
*/
word newNamespace(CrocThread* t, word parent, char[] name)
{
	mixin(FuncNameMix);

	CrocNamespace* p = void;

	if(isNull(t, parent))
		p = null;
	else if(isNamespace(t, parent))
		p = getNamespace(t, parent);
	else
	{
		pushTypeString(t, parent);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Parent must be null or namespace, not '{}'", getString(t, -1));
	}

	maybeGC(t);
	return push(t, CrocValue(namespace.create(t.vm.alloc, createString(t, name), p)));
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
word newNamespaceNoParent(CrocThread* t, char[] name)
{
	pushNull(t);
	newNamespace(t, -1, name);
	insertAndPop(t, -2);
	return stackSize(t) - 1;
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
word newThread(CrocThread* t, word func)
{
	mixin(FuncNameMix);

	auto f = getFunction(t, func);

	if(f is null)
	{
		pushTypeString(t, func);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Thread function must be of type 'function', not '{}'", getString(t, -1));
	}

	if(f.isNative)
		throwStdException(t, "ValueException", __FUNCTION__ ~ " - Native functions may not be used as the body of a coroutine");

	maybeGC(t);

	auto nt = thread.create(t.vm, f);
	thread.setHookFunc(t.vm.alloc, nt, t.hookFunc);
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
word pushThread(CrocThread* t, CrocThread* o)
{
	return push(t, CrocValue(o));
}

/**
Pushes a reference to a native (D) object onto the stack.

Params:
	o = The object to push.

Returns:
	The index of the newly-pushed value.
*/
word pushNativeObj(CrocThread* t, Object o)
{
	mixin(FuncNameMix);

	if((cast(void*)o) >= rt_stackTop() && (cast(void*)o) <= rt_stackBottom())
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - Attempting to push a native object that points to a scope-allocated class instance");

	maybeGC(t);
	return push(t, CrocValue(nativeobj.create(t.vm, o)));
}

/**
Pushes a weak reference to the object at the given stack index onto the stack. For value types (null,
bool, int, float, and char), weak references are unnecessary, and in these cases the value will simply
be pushed. Otherwise the pushed value will be a weak reference object.

Params:
	idx = The stack index of the object to get a weak reference of.

Returns:
	The stack index of the newly-pushed value.
*/
word pushWeakRef(CrocThread* t, word idx)
{
	return push(t, weakref.makeref(t.vm, *getValue(t, idx)));
}

/**
*/
word pushLocationObject(CrocThread* t, char[] file, int line, int col)
{
	auto ret = push(t, CrocValue(t.vm.location));
	pushNull(t);
	pushString(t, file);
	pushInt(t, line);
	pushInt(t, col);
	rawCall(t, ret, 1);
	return ret;
}

// ================================================================================================================================================
// Stack queries

/**
Sees if the value at the given _slot is null.
*/
bool isNull(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.Null;
}

/**
Sees if the value at the given _slot is a bool.
*/
bool isBool(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.Bool;
}

/**
Sees if the value at the given _slot is an int.
*/
bool isInt(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.Int;
}

/**
Sees if the value at the given _slot is a float.
*/
bool isFloat(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.Float;
}

/**
Sees if the value at the given _slot is an int or a float.
*/
bool isNum(CrocThread* t, word slot)
{
	auto type = type(t, slot);
	return type == CrocValue.Type.Int || type == CrocValue.Type.Float;
}

/**
Sees if the value at the given _slot is a char.
*/
bool isChar(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.Char;
}

/**
Sees if the value at the given _slot is a string.
*/
bool isString(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.String;
}

/**
Sees if the value at the given _slot is a table.
*/
bool isTable(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.Table;
}

/**
Sees if the value at the given _slot is an array.
*/
bool isArray(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.Array;
}

/**
Sees if the value at the given _slot is a memblock.
*/
bool isMemblock(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.Memblock;
}

/**
Sees if the value at the given _slot is a function.
*/
bool isFunction(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.Function;
}

/**
Sees if the value at the given _slot is a class.
*/
bool isClass(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.Class;
}

/**
Sees if the value at the given _slot is an instance.
*/
bool isInstance(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.Instance;
}

/**
Sees if the value at the given _slot is a namespace.
*/
bool isNamespace(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.Namespace;
}

/**
Sees if the value at the given _slot is a thread.
*/
bool isThread(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.Thread;
}

/**
Sees if the value at the given _slot is a native object.
*/
bool isNativeObj(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.NativeObj;
}

/**
Sees if the value at the given _slot is a weak reference.
*/
bool isWeakRef(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.WeakRef;
}

/**
Sees if the value at the given _slot is a function definition.
*/
bool isFuncDef(CrocThread* t, word slot)
{
	return type(t, slot) == CrocValue.Type.FuncDef;
}

/**
Gets the truth value of the value at the given _slot. null, false, integer 0, floating point 0.0,
and character '\0' are considered false; everything else is considered true. This is the same behavior
as within the language.
*/
bool isTrue(CrocThread* t, word slot)
{
	return !getValue(t, slot).isFalse();
}

/**
Gets the _type of the value at the given _slot. Value types are given by the CrocValue.Type
enumeration defined in croc.types.
*/
CrocValue.Type type(CrocThread* t, word slot)
{
	return getValue(t, slot).type;
}

/**
Returns the boolean value at the given _slot, or throws an error if it isn'_t one.
*/
bool getBool(CrocThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != CrocValue.Type.Bool)
	{
		pushTypeString(t, slot);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - expected 'bool' but got '{}'", getString(t, -1));
	}

	return v.mBool;
}

/**
Returns the integer value at the given _slot, or throws an error if it isn'_t one.
*/
crocint getInt(CrocThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != CrocValue.Type.Int)
	{
		pushTypeString(t, slot);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - expected 'int' but got '{}'", getString(t, -1));
	}

	return v.mInt;
}

/**
Returns the float value at the given _slot, or throws an error if it isn'_t one.
*/
crocfloat getFloat(CrocThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != CrocValue.Type.Float)
	{
		pushTypeString(t, slot);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - expected 'float' but got '{}'", getString(t, -1));
	}

	return v.mFloat;
}

/**
Returns the numerical value at the given _slot. This always returns an crocfloat, and will
implicitly cast int values to floats. Throws an error if the value is neither an int
nor a float.
*/
crocfloat getNum(CrocThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type == CrocValue.Type.Float)
		return v.mFloat;
	else if(v.type == CrocValue.Type.Int)
		return v.mInt;
	else
	{
		pushTypeString(t, slot);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - expected 'float' or 'int' but got '{}'", getString(t, -1));
	}

	assert(false);
}

/**
Returns the character value at the given _slot, or throws an error if it isn'_t one.
*/
dchar getChar(CrocThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != CrocValue.Type.Char)
	{
		pushTypeString(t, slot);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - expected 'char' but got '{}'", getString(t, -1));
	}

	return v.mChar;
}

/**
Returns the string value at the given _slot, or throws an error if it isn'_t one.

The returned string points into the Croc heap. It should NOT be modified in any way. The returned
array reference should also not be stored on the D heap, as once the string object is removed from the
Croc stack, there is no guarantee that the string data will be valid (Croc might collect it, as it
has no knowledge of the reference held by D). If you need the string value for a longer period of time,
you should dup it.
*/
char[] getString(CrocThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != CrocValue.Type.String)
	{
		pushTypeString(t, slot);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - expected 'string' but got '{}'", getString(t, -1));
	}

	return v.mString.toString();
}

/**
Returns the thread object at the given _slot, or throws an error if it isn'_t one.

The returned thread object points into the Croc heap, and as such, if no reference to it is
held from the Croc heap or stack, it may be collected, so be sure not to store the reference
away into a D data structure and then let the thread have its references dropped in Croc.
This is really meant for access to threads so that you can call thread functions on them.
*/
CrocThread* getThread(CrocThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != CrocValue.Type.Thread)
	{
		pushTypeString(t, slot);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - expected 'thread' but got '{}'", getString(t, -1));
	}

	return v.mThread;
}

/**
Returns the native D object at the given _slot, or throws an error if it isn'_t one.
*/
Object getNativeObj(CrocThread* t, word slot)
{
	mixin(FuncNameMix);

	auto v = getValue(t, slot);

	if(v.type != CrocValue.Type.NativeObj)
	{
		pushTypeString(t, slot);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - expected 'nativeobj' but got '{}'", getString(t, -1));
	}

	return v.mNativeObj.obj;
}

// ================================================================================================================================================
// Statements

/**
This structure is meant to be used as a helper to perform a Croc-style foreach loop.
It preserves the semantics of the Croc foreach loop and handles the foreach/opApply protocol
manipulations.

To use this, first you push the container -- what you would normally put on the right side
of the semicolon in a foreach loop in Croc. Just like in Croc, this is one, two, or three
values, and if the first value is not a function, opApply is called on it with the second
value as a user parameter.

Then you can create an instance of this struct using the static opCall and iterate over it
with a D foreach loop. Instead of getting values as the loop indices, you get indices of
stack slots that hold those values. You can break out of the loop just as you'd expect,
and you can perform any manipulations you'd like in the loop body.

Example:
-----
// 1. Push the container. We're just iterating through modules.customLoaders.
lookup(t, "modules.customLoaders");

// 2. Perform a foreach loop on a foreachLoop instance created with the thread and the number
// of items in the container. We only pushed one value for the container, so we pass 1.
// Note that you must specify the index types (which must all be word), or else D can't infer
// the types for them.

foreach(word k, word v; foreachLoop(t, 1))
{
	// 3. Do whatever you want with k and v.
	pushToString(t, k);
	pushToString(t, v);
	Stdout.formatln("{}: {}", getString(t, -2), getString(t, -1));

	// here we're popping the strings we pushed. You don't have to pop k and v or anything like that.
	pop(t, 2);
}
-----

Note a few things: the foreach loop will pop the container off the stack, so the above code is
stack-neutral (leaves the stack in the same state it was before it was run). You don't have to
pop anything inside the foreach loop. You shouldn't mess with stack values below k and v, since
foreachLoop keeps internal loop data there, but stack indices that were valid before the loop started
will still be accessible. If you use only one index (like foreach(word v; ...)), it will work just
like in Croc where an implicit index will be inserted before that one, and you will get the second
indices in v instead of the first.
*/
struct foreachLoop
{
private:
	CrocThread* t;
	uword numSlots;

public:
	/**
	The struct constructor.

	Params:
		numSlots = How many slots on top of the stack should be interpreted as the container. Must be
			1, 2, or 3.
	*/
	static foreachLoop opCall(CrocThread* t, uword numSlots)
	{
		foreachLoop ret = void;
		ret.t = t;
		ret.numSlots = numSlots;
		return ret;
	}

	/**
	The function that makes everything work. This is templated to allow any number of indices, but
	the downside to that is that you must specify the types of the indices in the foreach loop that
	iterates over this structure. All the indices must be of type 'word'.
	*/
	int opApply(T)(T dg)
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
			throwStdException(t, "RangeException", "foreachLoop - numSlots may only be 1, 2, or 3, not {}", numSlots);

		mixin(apiCheckNumParams!("numSlots"));

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

			CrocClass* proto;
			auto method = getMM(t, srcObj, MM.Apply, proto);

			if(method is null)
			{
				typeString(t, srcObj);
				throwStdException(t, "MethodException", "No implementation of {} for type '{}'", MetaNames[MM.Apply], getString(t, -1));
			}

			push(t, CrocValue(method));
			insert(t, -4);
			pop(t);
			auto reg = absIndex(t, -3);
			commonCall(t, reg + t.stackBase, 3, callPrologue(t, reg + t.stackBase, 3, 2, proto));

			if(!isFunction(t, src) && !isThread(t, src))
			{
				pushTypeString(t, src);
				throwStdException(t, "TypeException", "Invalid iterable type '{}' returned from opApply", getString(t, -1));
			}
		}

		if(isThread(t, src) && state(getThread(t, src)) != CrocThread.State.Initial)
			throwStdException(t, "StateException", "Attempting to iterate over a thread that is not in the 'initial' state");

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
				if(state(getThread(t, src)) == CrocThread.State.Dead)
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
Throws a Croc exception using the value at the top of the stack as the exception object. Any type can
be thrown. This will throw an actual D exception of type CrocException as well, which can be caught in D
as normal ($(B Important:) see catchException for information on catching them).

You cannot use this function if another exception is still in flight, that is, it has not yet been caught with
catchException. If you try, an Exception will be thrown -- that is, an instance of the D Exception class.

This function obviously does not return.
*/
void throwException(CrocThread* t)
{
	mixin(apiCheckNumParams!("1"));
	throwImpl(t, t.stack[t.stackIndex - 1]);
}

/**
Throws a new instance of one of the standard exception classes.
*/
void throwStdException(CrocThread* t, char[] exName, char[] fmt, ...)
{
	getStdException(t, exName);
	pushNull(t);
	pushVFormat(t, fmt, _arguments, _argptr);
	rawCall(t, -3, 1);
	throwException(t);
}

/**
Gets one of the standard exception classes and pushes it onto the stack. If the given name does not name a standard
exception, an ApiError will be thrown.

Params:
	exName = The class name of the exception to push.

Returns:
	The stack index of the newly-pushed class.
*/
word getStdException(CrocThread* t, char[] exName)
{
	auto ex = t.vm.stdExceptions.lookup(createString(t, exName));

	if(ex is null)
	{
		auto check = t.vm.stdExceptions.lookup(createString(t, "ApiError"));

		if(check is null)
			throw new CrocException("Fatal -- exception thrown before exception library was loaded");

		throwStdException(t, "ApiError", "Unknown standard exception type '{}'", exName);
	}

	return push(t, CrocValue(*ex));
}

/**
This function returns whether or not an exception is in flight in the given thread's VM.
*/
bool isThrowing(CrocThread* t)
{
	return t.vm.isThrowing;
}

/**
When catching Croc exceptions (those derived from CrocException) in D, Croc doesn'_t know that you've actually caught
one unless you tell it. If you want to rethrow an exception without seeing what's in it, you can just throw the
D exception object. But if you want to actually handle the exception, or rethrow it after seeing what's in it,
you $(B must call this function). This informs Croc that you have caught the exception that was in flight, and
pushes the exception object onto the stack, where you can inspect it and possibly rethrow it using throwException.

Note that if an exception occurred and you caught it, you might not know anything about what's on the stack. It
might be garbage from a half-completed operation. So you might want to store the size of the stack before a 'try'
block, then restore it in the 'catch' block so that the stack will be in a consistent state.

An exception must be in flight for this function to work. If none is in flight, a Croc exception is thrown. (For
some reason, that sounds funny. "Error: there is no error!")

Returns:
	The stack index of the newly-pushed exception object.
*/
word catchException(CrocThread* t)
{
	mixin(FuncNameMix);

	if(!t.vm.isThrowing)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - Attempting to catch an exception when none is in flight");

	auto ret = push(t, CrocValue(t.vm.exception));
	t.vm.exception = null;
	t.vm.isThrowing = false;
	return ret;
}

// ================================================================================================================================================
// Variable-related functions

/**
Sets an upvalue in the currently-executing closure. The upvalue is set to the value on top of the
stack, which is popped.

This function will fail if called at top-level (that is, outside of any executing closures).

Params:
	idx = The index of the upvalue to set.
*/
void setUpval(CrocThread* t, uword idx)
{
	mixin(FuncNameMix);

	if(t.arIndex == 0)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - No function to set upvalue (can't call this function at top level)");

	mixin(apiCheckNumParams!("1"));

	if(idx >= t.currentAR.func.nativeUpvals().length)
		throwStdException(t, "BoundsException", __FUNCTION__ ~ " - Invalid upvalue index ({}, only have {})", idx, t.currentAR.func.nativeUpvals().length);

	func.setNativeUpval(t.vm.alloc, t.currentAR.func, idx, getValue(t, -1));
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
word getUpval(CrocThread* t, uword idx)
{
	mixin(FuncNameMix);

	if(t.arIndex == 0)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - No function to get upvalue (can't call this function at top level)");

	assert(t.currentAR.func.isNative, "getUpval used on a non-native func");

	auto upvals = t.currentAR.func.nativeUpvals();

	if(idx >= upvals.length)
		throwStdException(t, "BoundsException", __FUNCTION__ ~ " - Invalid upvalue index ({}, only have {})", idx, upvals.length);

	return push(t, upvals[idx]);
}

/**
Pushes the string representation of the type of the value at the given _slot.

Returns:
	The stack index of the newly-pushed string.
*/
word pushTypeString(CrocThread* t, word slot)
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
	depth = The _depth into the call stack of the closure whose environment to get. Defaults to 0, which
		means the currently-executing closure. A _depth of 1 would mean the closure which called this
		closure, 2 the closure that called that one etc.

Returns:
	The stack index of the newly-pushed environment.
*/
word pushEnvironment(CrocThread* t, uword depth = 0)
{
	return push(t, CrocValue(getEnv(t, depth)));
}

/**
Pushes a global variable with the given name. Throws an error if the global cannot be found.

This function respects typical global lookup - that is, it starts at the current
function's environment and goes up the chain.

Params:
	name = The _name of the global to get.

Returns:
	The index of the newly-pushed value.
*/
word pushGlobal(CrocThread* t, char[] name)
{
	pushString(t, name);
	return getGlobal(t);
}

/**
Same as pushGlobal, except expects the name of the global to be on top of the stack. If the value
at the top of the stack is not a string, an error is thrown. Replaces the name with the value of the
global if found.

Returns:
	The index of the retrieved value (the stack top).
*/
word getGlobal(CrocThread* t)
{
	mixin(apiCheckNumParams!("1"));

	auto v = getValue(t, -1);

	if(!v.type == CrocValue.Type.String)
	{
		pushTypeString(t, -1);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Global name must be a string, not a '{}'", getString(t, -1));
	}

	*v = *getGlobalImpl(t, v.mString, getEnv(t));
	return stackSize(t) - 1;
}

/**
Sets a global variable with the given _name to the value on top of the stack, and pops that value.
Throws an error if the global cannot be found. Remember that if this is the first time you are
trying to set the global, you have to use newGlobal instead, just like using a global declaration
in Croc.

This function respects typical global lookup - that is, it starts at the current function's
environment and goes up the chain.

Params:
	name = The _name of the global to set.
*/
void setGlobal(CrocThread* t, char[] name)
{
	mixin(apiCheckNumParams!("1"));
	pushString(t, name);
	swap(t);
	setGlobal(t);
}

/**
Same as above, but expects the name of the global to be on the stack just below the value to set.
Pops both the name and the value.
*/
void setGlobal(CrocThread* t)
{
	mixin(apiCheckNumParams!("2"));

	auto n = getValue(t, -2);

	if(n.type != CrocValue.Type.String)
	{
		pushTypeString(t, -2);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Global name must be a string, not a '{}'", getString(t, -1));
	}

	setGlobalImpl(t, n.mString, getEnv(t), &t.stack[t.stackIndex - 1]);
	pop(t, 2);
}

/**
Declares a global variable with the given _name, sets it to the value on top of the stack, and pops
that value. Throws an error if the global has already been declared.

This function works just like a global variable declaration in Croc. It creates a new entry
in the current environment if it succeeds.

Params:
	name = The _name of the global to set.
*/
void newGlobal(CrocThread* t, char[] name)
{
	mixin(apiCheckNumParams!("1"));
	pushString(t, name);
	swap(t);
	newGlobal(t);
}

/**
Same as above, but expects the name of the global to be on the stack under the value to be set. Pops
both the name and the value off the stack.
*/
void newGlobal(CrocThread* t)
{
	mixin(apiCheckNumParams!("2"));

	auto n = getValue(t, -2);

	if(n.type != CrocValue.Type.String)
	{
		pushTypeString(t, -2);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Global name must be a string, not a '{}'", getString(t, -1));
	}

	newGlobalImpl(t, n.mString, getEnv(t), &t.stack[t.stackIndex - 1]);
	pop(t, 2);
}

/**
Searches for a global of the given _name.

By default, this follows normal global lookup, starting with the currently-executing function's environment,
but you can change where the lookup starts by using the depth parameter.

Params:
	name = The _name of the global to look for.
	depth = The _depth into the call stack of the closure in whose environment lookup should begin. Defaults
		to 0, which means the currently-executing closure. A _depth of 1 would mean the closure which called
		this closure, 2 the closure that called that one etc.

Returns:
	true if the global was found, in which case the containing namespace is on the stack. False otherwise,
	in which case nothing will be on the stack.
*/
bool findGlobal(CrocThread* t, char[] name, uword depth = 0)
{
	auto n = createString(t, name);
	auto ns = getEnv(t, depth);

	if(namespace.get(ns, n) !is null)
	{
		push(t, CrocValue(ns));
		return true;
	}

	for(; ns.parent !is null; ns = ns.parent) {}

	if(namespace.get(ns, n) !is null)
	{
		push(t, CrocValue(ns));
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
void clearTable(CrocThread* t, word tab)
{
	mixin(FuncNameMix);

	auto tb = getTable(t, tab);

	if(tb is null)
	{
		pushTypeString(t, tab);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - tab must be a table, not a '{}'", getString(t, -1));
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
void fillArray(CrocThread* t, word arr)
{
	mixin(apiCheckNumParams!("1"));
	auto a = getArray(t, arr);

	if(a is null)
	{
		pushTypeString(t, arr);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - arr must be an array, not a '{}'", getString(t, -1));
	}

	array.fill(t.vm.alloc, a, t.stack[t.stackIndex - 1]);
	pop(t);
}

// ================================================================================================================================================
// Memblock-related functions

/**
Gets a memblock's data array. This is one of the few places in the native API where
pointers to internal Croc data are exposed, and as with all of them, BE CAREFUL. Do
not resize this array, either by setting its .length or by appending to it. Bad things
will happen. Do not store this array reference away unless you're SURE that the memblock
it belongs to won't be collected. You are free to modify the data any way you like.

Params:
	slot = The stack index of the memblock.

Returns:
	The memblock's data array.
*/
ubyte[] getMemblockData(CrocThread* t, word slot)
{
	mixin(apiCheckNumParams!("1"));
	auto m = getMemblock(t, slot);

	if(m is null)
	{
		pushTypeString(t, slot);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - slot must be a memblock, not a '{}'", getString(t, -1));
	}

	return m.data;
}

/**
Similar to memblockViewNativeArray, except it changes an existing memblock's data array instead of creating
a new memblock object. The memblock's data will become a view into a native array.

This means that $(B the memblock will point into the native heap.) As a result, it is the responsibility
of the host program to ensure that this data is valid for the lifetime of the memblock. If it becomes
invalid, script code can crash the host. The resulting memblock will $(B not) own its data. The memblock's
previous data, if any, is freed.

Params:
	slot = The stack index of the existing memblock.
	arr = The array to become the data of the memblock.
*/
void memblockReviewNativeArray(CrocThread* t, word slot, void[] arr)
{
	mixin(apiCheckNumParams!("1"));
	auto m = getMemblock(t, slot);

	if(m is null)
	{
		pushTypeString(t, slot);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - slot must be a memblock, not a '{}'", getString(t, -1));
	}

	memblock.view(t.vm.alloc, m, arr);
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
word getFuncEnv(CrocThread* t, word func)
{
	mixin(FuncNameMix);

	if(auto f = getFunction(t, func))
		return push(t, CrocValue(f.environment));

	pushTypeString(t, func);
	throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));

	assert(false);
}

/**
Sets the namespace at the top of the stack as the environment namespace of a native function closure and pops
that namespace off the stack. Script function closures cannot have their environments changed.

Params:
	func = The stack index of the native function whose environment is to be set.
*/
void setFuncEnv(CrocThread* t, word func)
{
	mixin(apiCheckNumParams!("1"));

	auto ns = getNamespace(t, -1);

	if(ns is null)
	{
		pushTypeString(t, -1);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'namespace' for environment, not '{}'", getString(t, -1));
	}

	auto f = getFunction(t, func);

	if(f is null)
	{
		pushTypeString(t, -1);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));
	}

	if(!f.isNative)
		throwStdException(t, "ValueException", __FUNCTION__ ~ " - Cannot change the environment of a script function");

	.func.setEnvironment(t.vm.alloc, f, ns);
	pop(t);
}

/**
Pushes the function definition that this function was made from. Pushes null if the function is native.

Params:
	func = The stack index of the function whose definition is to be retrieved.

Returns:
	The stack index of the newly-pushed function definition.
*/
void funcDef(CrocThread* t, word func)
{
	mixin(FuncNameMix);

	if(auto f = getFunction(t, func))
	{
		if(f.isNative)
			return pushNull(t);
		else
			return push(t, CrocValue(f.scriptFunc));
	}

	pushTypeString(t, func);
	throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));

	assert(false);
}

/**
Gets the name of the function at the given stack index. This is the name given in the declaration
of the function if it's a script function, or the name given to newFunction for native functions.
Some functions, like top-level module functions and nameless function literals, have automatically-
generated names which always start and end with angle brackets ($(LT) and $(GT)).
*/
char[] funcName(CrocThread* t, word func)
{
	mixin(FuncNameMix);

	if(auto f = getFunction(t, func))
		return f.name.toString();

	pushTypeString(t, func);
	throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));

	assert(false);
}

/**
Gets the number of parameters that the function at the given stack index takes. This is the number
of non-variadic arguments, not including 'this'. For variadic native functions, returns a large number.
*/
uword funcNumParams(CrocThread* t, word func)
{
	mixin(FuncNameMix);

	if(auto f = getFunction(t, func))
		return f.numParams - 1;

	pushTypeString(t, func);
	throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));

	assert(false);
}

/**
Gets the maximum allowable number of parameters that can be passed to the function at the given stack
index. For variadic functions (script or native), this returns a large number.
*/
uword funcMaxParams(CrocThread* t, word func)
{
	mixin(FuncNameMix);

	if(auto f = getFunction(t, func))
		return f.maxParams - 1;

	pushTypeString(t, func);
	throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));

	assert(false);
}

/**
Gets whether or not the given function takes variadic arguments. For native functions, always returns
true.
*/
bool funcIsVararg(CrocThread* t, word func)
{
	mixin(FuncNameMix);

	if(auto f = getFunction(t, func))
		return .func.isVararg(f);

	pushTypeString(t, func);
	throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));

	assert(false);
}

/**
Gets whether or not the given function is a native function.
*/
bool funcIsNative(CrocThread* t, word func)
{
	mixin(FuncNameMix);

	if(auto f = getFunction(t, func))
		return .func.isNative(f);

	pushTypeString(t, func);
	throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'function', not '{}'", getString(t, -1));

	assert(false);
}

// ================================================================================================================================================
// Class-related functions

/**
Sets the finalizer function for the given class. The finalizer of a class is called when an instance of that class
is about to be collected by the garbage collector and is used to clean up limited resources associated with it
(i.e. memory allocated on the C heap, file handles, etc.). The finalizer function should be short and to-the-point
as to make finalization as quick as possible. It should also not allocate very much memory, if any, as the
garbage collector is effectively disabled during execution of finalizers. The finalizer function will only
ever be called once for each instance. If the finalizer function causes the instance to be "resurrected", that is
the instance is reattached to the application's memory graph, it will still eventually be collected but its finalizer
function will $(B not) be run again.

You can only set a class's finalizer once. Once it has been set, it cannot be unset or changed.

This function expects the finalizer function to be on the top of the stack. The function is popped from the stack.

Params:
	cls = The class whose finalizer is to be set.
*/
void setFinalizer(CrocThread* t, word cls)
{
	mixin(apiCheckNumParams!("1"));

	if(!isFunction(t, -1))
	{
		pushTypeString(t, -1);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'function' for finalizer, not '{}'", getString(t, -1));
	}

	auto c = getClass(t, cls);

	if(c is null)
	{
		pushTypeString(t, cls);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'class', not '{}'", getString(t, -1));
	}

	if(c.isFrozen)
		throwStdException(t, "StateException", __FUNCTION__ ~ " - Attempting to change the finalizer of class {} which has been frozen", className(t, cls));

	classobj.setFinalizer(t.vm.alloc, c, getFunction(t, -1));
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
word getFinalizer(CrocThread* t, word cls)
{
	mixin(FuncNameMix);

	if(auto c = getClass(t, cls))
	{
		if(c.finalizer)
			return push(t, CrocValue(c.finalizer));
		else
			return pushNull(t);
	}

	pushTypeString(t, cls);
	throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'class', not '{}'", getString(t, -1));

	assert(false);
}

/**
Gets the name of the class at the given stack index.
*/
char[] className(CrocThread* t, word cls)
{
	mixin(FuncNameMix);

	if(auto c = getClass(t, cls))
		return c.name.toString();

	pushTypeString(t, cls);
	throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'class', not '{}'", getString(t, -1));

	assert(false);
}

/**

*/
void addField(CrocThread* t, word cls, char[] name)
{
	mixin(apiCheckNumParams!("1"));
	auto c = absIndex(t, cls);
	pushString(t, name);
	swap(t);
	_addFieldOrMethod(t, c, false);
}

/**

*/
void addField(CrocThread* t, word cls)
{
	_addFieldOrMethod(t, cls, false);
}

/**

*/
void addMethod(CrocThread* t, word cls, char[] name, bool isPublic = true)
{
	mixin(apiCheckNumParams!("1"));
	auto c = absIndex(t, cls);
	pushString(t, name);
	swap(t);
	_addFieldOrMethod(t, c, true);
}

/**

*/
void addMethod(CrocThread* t, word cls)
{
	_addFieldOrMethod(t, cls, true);
}

private void _addFieldOrMethod(CrocThread* t, word cls, bool isMethod)
{
	mixin(apiCheckNumParams!("2"));

	if(!isClass(t, cls))
	{
		pushTypeString(t, cls);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'class', not '{}'", getString(t, -1));
	}

	if(!isString(t, -2))
	{
		pushTypeString(t, -2);

		if(isMethod)
			throwStdException(t, "TypeException", __FUNCTION__ ~ " - Method name must be a string, not a '{}'", getString(t, -1));
		else
			throwStdException(t, "TypeException", __FUNCTION__ ~ " - Field name must be a string, not a '{}'", getString(t, -1));
	}

	auto c = getClass(t, cls);

	if(c.isFrozen)
	{
		if(isMethod)
			throwStdException(t, "StateException", __FUNCTION__ ~ " - Attempting to add a method to class '{}' which is frozen", c.name.toString());
		else
			throwStdException(t, "StateException", __FUNCTION__ ~ " - Attempting to add a field to class '{}' which is frozen", c.name.toString());
	}

	auto name = getStringObj(t, -2);
	auto nameStr = name.toString();
	bool isPublic = true;

	if(nameStr.length >= 2 && nameStr[0] == '_' && nameStr[1] != '_')
	{
		isPublic = false;
		push(t, CrocValue(c.name));
		push(t, CrocValue(name));
		cat(t, 2);
		swap(t, -3);
		pop(t);
		name = getStringObj(t, -2);
	}

	if(isMethod)
	{
		if(!classobj.addMethod(t.vm.alloc, c, name, getValue(t, -1), isPublic))
			throwStdException(t, "FieldException", __FUNCTION__ ~ " - Attempting to add a method '{}' which already exists to class '{}'", name.toString(), c.name.toString());
	}
	else
	{
		if(!classobj.addField(t.vm.alloc, c, name, getValue(t, -1), isPublic))
			throwStdException(t, "FieldException", __FUNCTION__ ~ " - Attempting to add a field '{}' which already exists to class '{}'", name.toString(), c.name.toString());
	}

	pop(t, 2);
}

// ================================================================================================================================================
// Instance-related functions

// ================================================================================================================================================
// Namespace-related functions

/**
Removes all items from the given namespace object.

Params:
	ns = The stack index of the namespace object to clear.
*/
void clearNamespace(CrocThread* t, word ns)
{
	mixin(FuncNameMix);

	auto n = getNamespace(t, ns);

	if(n is null)
	{
		pushTypeString(t, ns);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - ns must be a namespace, not a '{}'", getString(t, -1));
	}

	namespace.clear(t.vm.alloc, n);
}

/**
Removes the key at the top of the stack from the given object. The key is popped.
The object must be a namespace or table.

Params:
	obj = The stack index of the object from which the key is to be removed.
*/
void removeKey(CrocThread* t, word obj)
{
	mixin(apiCheckNumParams!("1"));

	if(auto tab = getTable(t, obj))
	{
		push(t, CrocValue(tab));
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
			throwStdException(t, "TypeException", __FUNCTION__ ~ " - key must be a string, not a '{}'", getString(t, -1));
		}

		if(!opin(t, -1, obj))
		{
			pushToString(t, obj);
			throwStdException(t, "FieldException", __FUNCTION__ ~ " - key '{}' does not exist in namespace '{}'", getString(t, -2), getString(t, -1));
		}

		namespace.remove(t.vm.alloc, ns, getStringObj(t, -1));
		pop(t);
	}
	else
	{
		pushTypeString(t, obj);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - obj must be a namespace or table, not a '{}'", getString(t, -1));
	}
}

/**
Gets the name of the namespace at the given stack index. This is just the single name component that
it was created with (like "foo" for "namespace foo {}").
*/
char[] namespaceName(CrocThread* t, word ns)
{
	mixin(FuncNameMix);

	if(auto n = getNamespace(t, ns))
		return n.name.toString();

	pushTypeString(t, ns);
	throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'namespace', not '{}'", getString(t, -1));

	assert(false);
}

/**
Pushes the "full" name of the given namespace, which includes all the parent namespace name components,
separated by dots.

Returns:
	The stack index of the newly-pushed name string.
*/
word namespaceFullname(CrocThread* t, word ns)
{
	mixin(FuncNameMix);

	if(auto n = getNamespace(t, ns))
		return pushNamespaceNamestring(t, n);

	pushTypeString(t, ns);
	throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'namespace', not '{}'", getString(t, -1));

	assert(false);
}

// ================================================================================================================================================
// Thread-specific stuff

/**
Gets the current coroutine _state of the thread as a member of the CrocThread.State enumeration.
*/
CrocThread.State state(CrocThread* t)
{
	return t.state;
}

/**
Gets a string representation of the current coroutine state of the thread.

The string returned is not on the Croc heap, it's just a string literal, but it's in ROM.
*/
char[] stateString(CrocThread* t)
{
	return CrocThread.StateStrings[t.state];
}

/**
Gets the VM that the thread is associated with.
*/
CrocVM* getVM(CrocThread* t)
{
	return t.vm;
}

/**
Find how many calls deep the currently-executing function is nested. Tailcalls are taken into account.

If called at top-level, returns 0.
*/
uword callDepth(CrocThread* t)
{
	uword depth = 0;

	for(uword i = 0; i < t.arIndex; i++)
		depth += t.actRecs[i].numTailcalls + 1;

	return depth;
}

/**
Resets a dead thread to the initial state, optionally providing a new function to act as the body of the thread.

Params:
	slot = The stack index of the thread to be reset. It must be in the 'dead' state.
	newFunction = If true, a function should be on top of the stack which should serve as the new body of the
		coroutine. The default is false, in which case the coroutine will use the function with which it was
		created.
*/
void resetThread(CrocThread* t, word slot, bool newFunction = false)
{
	mixin(FuncNameMix);

	auto other = getThread(t, slot);

	if(other is null)
	{
		pushTypeString(t, slot);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Object at 'slot' must be a 'thread', not a '{}'", getString(t, -1));
	}

	if(t.vm !is other.vm)
		throwStdException(t, "ValueException", __FUNCTION__ ~ " - Attempting to reset a coroutine that belongs to a different VM");

	if(state(other) != CrocThread.State.Dead)
		throwStdException(t, "StateException", __FUNCTION__ ~ " - Attempting to reset a {} coroutine (must be dead)", stateString(other));

	if(newFunction)
	{
		mixin(apiCheckNumParams!("1"));

		auto f = getFunction(t, -1);

		if(f is null)
		{
			pushTypeString(t, -1);
			throwStdException(t, "TypeException", __FUNCTION__ ~ " - Attempting to reset a coroutine with a '{}' instead of a 'function'", getString(t, -1));
		}

		if(f.isNative)
			throwStdException(t, "ValueException", __FUNCTION__ ~ " - Native functions may not be used as the body of a coroutine");

		thread.setCoroFunc(t.vm.alloc, other, f);
		pop(t);
	}

	other.state = CrocThread.State.Initial;
}

/**
Halts the given thread. If the given thread is currently running, throws a halt exception immediately;
otherwise, places a pending halt on the thread.
*/
void haltThread(CrocThread* t)
{
	if(state(t) == CrocThread.State.Running)
		throw new CrocHaltException();
	else
		pendingHalt(t);
}

/**
Places a pending halt on the thread. This does nothing if the thread is in the 'dead' state.
*/
void pendingHalt(CrocThread* t)
{
	if(state(t) != CrocThread.State.Dead && t.arIndex > 0)
		t.shouldHalt = true;
}

/**
Sees if the given thread has a pending halt.
*/
bool hasPendingHalt(CrocThread* t)
{
	return t.shouldHalt;
}

// ================================================================================================================================================
// Weakref-related functions

/**
Works like the deref() function in the base library. If the value at the given index is a
value type, just duplicates that value. If the value at the given index is a weak reference,
pushes the object it refers to or 'null' if that object has been collected. Throws an error
if the value at the given index is any other type. This is meant to be an inverse to pushWeakRef,
hence the behavior with regards to value types.

Params:
	idx = The stack index of the object to dereference.

Returns:
	The stack index of the newly-pushed value.
*/
word deref(CrocThread* t, word idx)
{
	mixin(FuncNameMix);

	switch(type(t, idx))
	{
		case
			CrocValue.Type.Null,
			CrocValue.Type.Bool,
			CrocValue.Type.Int,
			CrocValue.Type.Float,
			CrocValue.Type.Char,
			CrocValue.Type.String,
			CrocValue.Type.NativeObj,
			CrocValue.Type.Upvalue:

			return dup(t, idx);

		case CrocValue.Type.WeakRef:
			if(auto o = getValue(t, idx).mWeakRef.obj)
				return push(t, CrocValue(o));
			else
				return pushNull(t);

		default:
			pushTypeString(t, idx);
			throwStdException(t, "TypeException", __FUNCTION__ ~ " - idx must be a weakref or non-weakref-able type, not a '{}'", getString(t, -1));
	}

	assert(false);
}

// ================================================================================================================================================
// Funcdef-related functions

/**
Gets the name of the function definition at the given stack index. This is the name given in the declaration
of the function. Some functions, like top-level module functions and nameless function literals, have automatically-
generated names which always start and end with angle brackets ($(LT) and $(GT)).
*/
char[] funcDefName(CrocThread* t, word funcDef)
{
	mixin(FuncNameMix);

	if(auto f = getFuncDef(t, funcDef))
		return f.name.toString();

	pushTypeString(t, funcDef);
	throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected 'funcdef', not '{}'", getString(t, -1));

	assert(false);
}

// ================================================================================================================================================
// Atomic Croc operations

/**
Push a string representation of any Croc value onto the stack.

Params:
	slot = The stack index of the value to convert to a string.
	raw = If true, will not call toString metamethods. Defaults to false, which means toString
		metamethods will be called.

Returns:
	The stack index of the newly-pushed string.
*/
word pushToString(CrocThread* t, word slot, bool raw = false)
{
	// Dereferencing so that we don'_t potentially push an invalid stack object.
	auto v = *getValue(t, slot);
	return toStringImpl(t, v, raw);
}

/**
See if item is in container. Works like the Croc 'in' operator. Calls opIn metamethods.

Params:
	item = The _item to look for (the lhs of 'in').
	container = The _object in which to look (the rhs of 'in').

Returns:
	true if item is in container, false otherwise.
*/
bool opin(CrocThread* t, word item, word container)
{
	return inImpl(t, getValue(t, item), getValue(t, container));
}

/**
Compare two values at the given indices, and give the comparison value (negative for a < b, positive for a > b,
and 0 if a == b). This is the exact behavior of the '<=>' operator in Croc. Calls opCmp metamethods.

Params:
	a = The index of the first object.
	b = The index of the second object.

Returns:
	The comparison value.
*/
crocint cmp(CrocThread* t, word a, word b)
{
	return compareImpl(t, getValue(t, a), getValue(t, b));
}

/**
Test two values at the given indices for equality. This is the exact behavior of the '==' operator in Croc.
Calls opEquals metamethods.

Params:
	a = The index of the first object.
	b = The index of the second object.

Returns:
	true if equal, false otherwise.
*/
bool equals(CrocThread* t, word a, word b)
{
	return equalsImpl(t, getValue(t, a), getValue(t, b));
}

/**
Test two values at the given indices for identity. This is the exact behavior of the 'is' operator in Croc.

Params:
	a = The index of the first object.
	b = The index of the second object.

Returns:
	true if identical, false otherwise.
*/
bool opis(CrocThread* t, word a, word b)
{
	return cast(bool)getValue(t, a).opEquals(*getValue(t, b));
}

/**
Index the _container at the given index with the value at the top of the stack. Replaces the value on the
stack with the result. Calls opIndex metamethods.

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
word idx(CrocThread* t, word container)
{
	mixin(apiCheckNumParams!("1"));
	auto slot = t.stackIndex - 1;
	idxImpl(t, slot, getValue(t, container), &t.stack[slot]);
	return stackSize(t) - 1;
}

/**
Index-assign the _container at the given index with the key at the second-from-top of the stack and the
value at the top of the stack. Pops both the key and the value from the stack. Calls opIndexAssign
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
void idxa(CrocThread* t, word container)
{
	mixin(apiCheckNumParams!("2"));
	auto slot = t.stackIndex - 2;
	idxaImpl(t, fakeToAbs(t, container), &t.stack[slot], &t.stack[slot + 1]);
	pop(t, 2);
}

/**
Shortcut for the common case where you need to index a _container with an integer index. Pushes
the indexed value.

Params:
	container = The stack index of the _container object.
	idx = The integer index.

Returns:
	The stack index of the newly-pushed indexed value.
*/
word idxi(CrocThread* t, word container, crocint idx)
{
	auto c = absIndex(t, container);
	pushInt(t, idx);
	return .idx(t, c);
}

/**
Shortcut for the common case where you need to index-assign a _container with an integer index. Pops
the value at the top of the stack and assigns it into the _container at the given index.

Params:
	container = The stack index of the _container object.
	idx = The integer index.
*/
void idxai(CrocThread* t, word container, crocint idx)
{
	auto c = absIndex(t, container);
	pushInt(t, idx);
	swap(t);
	idxa(t, c);
}

/**
Get a _field with the given _name from the _container at the given index. Pushes the result onto the stack.

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
	raw = If true, does not call opField metamethods. Defaults to false, which means it will.

Returns:
	The stack index of the newly-pushed result.
*/
word field(CrocThread* t, word container, char[] name, bool raw = false)
{
	auto c = fakeToAbs(t, container);
	pushString(t, name);
	return commonField(t, c, raw);
}

/**
Same as above, but expects the _field name to be at the top of the stack. If the value at the top of the
stack is not a string, an error is thrown. The _field value replaces the _field name, much like with idx.

Params:
	container = The stack index of the _container object.
	raw = If true, does not call opField metamethods. Defaults to false, which means it will.

Returns:
	The stack index of the retrieved _field value.
*/
word field(CrocThread* t, word container, bool raw = false)
{
	mixin(apiCheckNumParams!("1"));

	if(!isString(t, -1))
	{
		pushTypeString(t, -1);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Field name must be a string, not a '{}'", getString(t, -1));
	}

	return commonField(t, fakeToAbs(t, container), raw);
}

/**
Sets a field with the given _name in the _container at the given index to the value at the top of the stack.
Pops that value off the stack. Calls opFieldAssign metamethods.

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
	raw = If true, does not call opFieldAssign metamethods. Defaults to false, which means it will.
*/
void fielda(CrocThread* t, word container, char[] name, bool raw = false)
{
	mixin(apiCheckNumParams!("1"));
	auto c = fakeToAbs(t, container);
	pushString(t, name);
	swap(t);
	commonFielda(t, c, raw);
}

/**
Same as above, but expects the field name to be in the second-from-top slot and the value to set at the top of
the stack, similar to idxa. Throws an error if the field name is not a string. Pops both the set value and the
field name off the stack, just like idxa.

Params:
	container = The stack index of the _container object.
	raw = If true, does not call opFieldAssign metamethods. Defaults to false, which means it will.
*/
void fielda(CrocThread* t, word container, bool raw = false)
{
	mixin(apiCheckNumParams!("2"));

	if(!isString(t, -2))
	{
		pushTypeString(t, -2);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Field name must be a string, not a '{}'", getString(t, -1));
	}

	commonFielda(t, fakeToAbs(t, container), raw);
}

/**
Pushes the length of the object at the given _slot. Calls opLength metamethods.

Params:
	slot = The _slot of the object whose length is to be retrieved.

Returns:
	The stack index of the newly-pushed length.
*/
word pushLen(CrocThread* t, word slot)
{
	auto o = fakeToAbs(t, slot);
	pushNull(t);
	lenImpl(t, t.stackIndex - 1, &t.stack[o]);
	return stackSize(t) - 1;
}

/**
Gets the integral length of the object at the given _slot. Calls opLength metamethods. If the length
of the object is not an integer, throws an error.

Params:
	slot = The _slot of the object whose length is to be retrieved.

Returns:
	The length of the object.
*/
crocint len(CrocThread* t, word slot)
{
	mixin(FuncNameMix);

	pushLen(t, slot);

	if(!isInt(t, -1))
	{
		pushTypeString(t, -1);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected length to be an int, but got '{}' instead", getString(t, -1));
	}

	auto ret = getInt(t, -1);
	pop(t);
	return ret;
}

/**
Sets the length of the object at the given _slot to the value at the top of the stack and pops that
value. Calls opLengthAssign metamethods.

Params:
	slot = The _slot of the object whose length is to be set.
*/
void lena(CrocThread* t, word slot)
{
	mixin(apiCheckNumParams!("1"));
	auto o = fakeToAbs(t, slot);
	lenaImpl(t, o, &t.stack[t.stackIndex - 1]);
	pop(t);
}

/**
Same as above, but allows you to set the length with an integer parameter directly rather than having
to push it onto the stack. Calls opLengthAssign metamethods.

Params:
	slot = The _slot of the object whose length is to be set.
	length = The new integral length.
*/
void lenai(CrocThread* t, word slot, crocint length)
{
	slot = absIndex(t, slot);
	pushInt(t, length);
	lena(t, slot);
}

/**
Slice the object at the given slot. The low index is the second-from-top value on the stack, and
the high index is the top value. Either index can be null. The indices are popped and the result
of the _slice operation is pushed.

Params:
	container = The slot of the object to be sliced.
*/
word slice(CrocThread* t, word container)
{
	mixin(apiCheckNumParams!("2"));
	auto slot = t.stackIndex - 2;
	sliceImpl(t, slot, getValue(t, container), &t.stack[slot], &t.stack[slot + 1]);
	pop(t);
	return stackSize(t) - 1;
}

/**
Slice-assign the object at the given slot. The low index is the third-from-top value; the high is
the second-from-top; and the value to assign into the object is on the top. Either index can be null.
Both indices and the value are popped.

Params:
	container = The slot of the object to be slice-assigned.
*/
void slicea(CrocThread* t, word container)
{
	mixin(apiCheckNumParams!("3"));
	auto slot = t.stackIndex - 3;
	sliceaImpl(t, getValue(t, container), &t.stack[slot], &t.stack[slot + 1], &t.stack[slot + 2]);
	pop(t, 3);
}

/**
These all perform the given mathematical operation on the two values at the given indices, and push
the result of that operation onto the stack. Metamethods (including reverse versions) will be called.

Don'_t use these functions if you're looking to do some serious number crunching on ints and floats. Just
get the values and do the computation in D.

Params:
	a = The slot of the first value.
	b = The slot of the second value.

Returns:
	The stack index of the newly-pushed result.
*/
word add(CrocThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Add, t.stackIndex - 1, &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word sub(CrocThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Sub, t.stackIndex - 1, &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word mul(CrocThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Mul, t.stackIndex - 1, &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word div(CrocThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Div, t.stackIndex - 1, &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word mod(CrocThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binOpImpl(t, MM.Mod, t.stackIndex - 1, &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/**
Negates the value at the given index and pushes the result. Calls opNeg metamethods.

Like the binary operations, don'_t use this unless you need the actual Croc semantics, as it's
less efficient than just getting a number and negating it.

Params:
	o = The slot of the value to negate.

Returns:
	The stack index of the newly-pushed result.
*/
word neg(CrocThread* t, word o)
{
	auto oslot = fakeToAbs(t, o);
	pushNull(t);
	negImpl(t, t.stackIndex - 1, &t.stack[oslot]);
	return stackSize(t) - 1;
}

/**
These all perform the given reflexive mathematical operation on the value at the given slot, using
the value at the top of the stack for the rhs. The rhs is popped. These call metamethods.

Like the other mathematical methods, it's more efficient to perform the operation directly on numbers
rather than to use these methods. Use these only if you need the Croc semantics.

Params:
	o = The slot of the object to perform the reflexive operation on.
*/
void addeq(CrocThread* t, word o)
{
	mixin(apiCheckNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.AddEq, oslot, &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void subeq(CrocThread* t, word o)
{
	mixin(apiCheckNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.SubEq, oslot, &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void muleq(CrocThread* t, word o)
{
	mixin(apiCheckNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.MulEq, oslot, &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void diveq(CrocThread* t, word o)
{
	mixin(apiCheckNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.DivEq, oslot, &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void modeq(CrocThread* t, word o)
{
	mixin(apiCheckNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinOpImpl(t, MM.ModEq, oslot, &t.stack[t.stackIndex - 1]);
	pop(t);
}

/**
These all perform the given bitwise operation on the two values at the given indices, _and push
the result of that operation onto the stack. Metamethods (including reverse versions) will be called.

Don'_t use these functions if you're looking to do some serious number crunching on ints. Just
get the values _and do the computation in D.

Params:
	a = The slot of the first value.
	b = The slot of the second value.

Returns:
	The stack index of the newly-pushed result.
*/
word and(CrocThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.And, t.stackIndex - 1, &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word or(CrocThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.Or, t.stackIndex - 1, &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word xor(CrocThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.Xor, t.stackIndex - 1, &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word shl(CrocThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.Shl, t.stackIndex - 1, &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word shr(CrocThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.Shr, t.stackIndex - 1, &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/// ditto
word ushr(CrocThread* t, word a, word b)
{
	auto aslot = fakeToAbs(t, a);
	auto bslot = fakeToAbs(t, b);
	pushNull(t);
	binaryBinOpImpl(t, MM.UShr, t.stackIndex - 1, &t.stack[aslot], &t.stack[bslot]);
	return stackSize(t) - 1;
}

/**
Bitwise complements the value at the given index and pushes the result. Calls opCom metamethods.

Like the binary operations, don'_t use this unless you need the actual Croc semantics, as it's
less efficient than just getting a number and complementing it.

Params:
	o = The slot of the value to complement.

Returns:
	The stack index of the newly-pushed result.
*/
word com(CrocThread* t, word o)
{
	auto oslot = fakeToAbs(t, o);
	pushNull(t);
	comImpl(t, t.stackIndex - 1, &t.stack[oslot]);
	return stackSize(t) - 1;
}

/**
These all perform the given reflexive bitwise operation on the value at the given slot, using
the value at the top of the stack for the rhs. The rhs is popped. These call metamethods.

Like the other bitwise methods, it's more efficient to perform the operation directly on numbers
rather than to use these methods. Use these only if you need the Croc semantics.

Params:
	o = The slot of the object to perform the reflexive operation on.
*/
void andeq(CrocThread* t, word o)
{
	mixin(apiCheckNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.AndEq, oslot, &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void oreq(CrocThread* t, word o)
{
	mixin(apiCheckNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.OrEq, oslot, &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void xoreq(CrocThread* t, word o)
{
	mixin(apiCheckNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.XorEq, oslot, &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void shleq(CrocThread* t, word o)
{
	mixin(apiCheckNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.ShlEq, oslot, &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void shreq(CrocThread* t, word o)
{
	mixin(apiCheckNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.ShrEq, oslot, &t.stack[t.stackIndex - 1]);
	pop(t);
}

/// ditto
void ushreq(CrocThread* t, word o)
{
	mixin(apiCheckNumParams!("1"));
	auto oslot = fakeToAbs(t, o);
	reflBinaryBinOpImpl(t, MM.UShrEq, oslot, &t.stack[t.stackIndex - 1]);
	pop(t);
}

/**
Concatenates the top num parameters on the stack, popping them all and pushing the result on the stack.

If num is 1, this function does nothing. If num is 0, it is an error. Otherwise, the concatenation
works just like it does in Croc.

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
word cat(CrocThread* t, uword num)
{
	mixin(FuncNameMix);

	if(num == 0)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - Cannot concatenate 0 things");

	mixin(apiCheckNumParams!("num"));

	auto slot = t.stackIndex - num;

	if(num > 1)
	{
		catImpl(t, slot, slot, num);
		pop(t, num - 1);
	}

	return slot - t.stackBase;
}

/**
Performs concatenation-assignment. dest is the stack slot of the destination object (the object to
append to). num is how many values there are on the right-hand side and is expected to be at least 1.
The RHS values are on the top of the stack. Pops the RHS values off the stack.

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
void cateq(CrocThread* t, word dest, uword num)
{
	mixin(FuncNameMix);

	if(num == 0)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - Cannot append 0 things");

	mixin(apiCheckNumParams!("num"));
	catEqImpl(t, fakeToAbs(t, dest), t.stackIndex - num, num);
	pop(t, num);
}

/**
Returns whether or not obj is an 'instance' and derives from base. Throws an error if base is not a class.
Works just like the as operator in Croc.

Params:
	obj = The stack index of the value to test.
	base = The stack index of the _base class. Must be a 'class'.

Returns:
	true if obj is an 'instance' and it derives from base. False otherwise.
*/
bool as(CrocThread* t, word obj, word base)
{
	return asImpl(t, getValue(t, obj), getValue(t, base));
}

/**
Increments the value at the given _slot. Calls opInc metamethods.

Params:
	slot = The stack index of the value to increment.
*/
void inc(CrocThread* t, word slot)
{
	incImpl(t, fakeToAbs(t, slot));
}

/**
Decrements the value at the given _slot. Calls opDec metamethods.

Params:
	slot = The stack index of the value to decrement.
*/
void dec(CrocThread* t, word slot)
{
	decImpl(t, fakeToAbs(t, slot));
}

/**
Gets the class of instances, base class of classes, or the parent namespace of namespaces and
pushes it onto the stack. Throws an error if the value at the given _slot is not a class, instance,
or namespace. Works just like "x.super" in Croc. For classes and namespaces, pushes null if
there is no base or parent.

Params:
	slot = The stack index of the instance, class, or namespace whose class, base, or parent to get.

Returns:
	The stack index of the newly-pushed value.
*/
word superOf(CrocThread* t, word slot)
{
	return push(t, superOfImpl(t, getValue(t, slot)));
}

// ================================================================================================================================================
// Function calling

/**
Calls the object at the given _slot. The parameters (including 'this') are assumed to be all the
values after that _slot to the top of the stack.

The 'this' parameter is, according to the language specification, null if no explicit context is given.
You must still push this null value, however.

An example of calling a function:

-----
// Let's translate `x = f(5, "hi")` into API calls.

// 1. Push the function (or any callable object -- like instances, threads).
auto slot = pushGlobal(t, "f");

// 2. Push the 'this' parameter. This is 'null' if you don'_t care. Notice in the Croc code, we didn'_t
// put a 'with', so 'null' will be used as the context.
pushNull(t);

// 3. Push any params.
pushInt(t, 5);
pushString(t, "hi");

// 4. Call it.
rawCall(t, slot, 1);

// 5. Do something with the return values. setGlobal pops the return value off the stack, so now the
// stack is back the way it was when we started.
setGlobal(t, "x");
-----

Params:
	slot = The _slot containing the object to call.
	numReturns = How many return values you want. Can be -1, which means you'll get all returns.

Returns:
	The number of return values given by the function. If numReturns was -1, this is exactly how
	many returns the function gave. If numReturns was >= 0, this is the same as numReturns (and
	not exactly useful since you already know it).
*/
uword rawCall(CrocThread* t, word slot, word numReturns)
{
	mixin(FuncNameMix);

	auto absSlot = fakeToAbs(t, slot);
	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - invalid number of returns (must be >= -1)");

	return commonCall(t, absSlot, numReturns, callPrologue(t, absSlot, numReturns, numParams, null));
}

/**
Calls a method of an object at the given _slot. The parameters (including a spot for 'this') are assumed
to be all the values after that _slot to the top of the stack.

This function behaves identically to a method call within the language, including calling opMethod
metamethods if the method is not found.

The process of calling a method is very similar to calling a normal function.

-----
// Let's translate `o.f(3)` into API calls.

// 1. Push the object on which the method will be called.
auto slot = pushGlobal(t, "o");

// 2. Make room for 'this'.
pushNull(t);

// 3. Push any params.
pushInt(t, 3);

// 4. Call it with the method name.
methodCall(t, slot, "f", 0);

// We didn'_t ask for any return values, so the stack is how it was before we began.
-----

Params:
	slot = The _slot containing the object on which the method will be called.
	name = The _name of the method to call.
	numReturns = How many return values you want. Can be -1, which means you'll get all returns.

Returns:
	The number of return values given by the function. If numReturns was -1, this is exactly how
	many returns the function gave. If numReturns was >= 0, this is the same as numReturns (and
	not exactly useful since you already know it).
*/
uword methodCall(CrocThread* t, word slot, char[] name, word numReturns)
{
	mixin(FuncNameMix);

	auto absSlot = fakeToAbs(t, slot);
	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - invalid number of returns (must be >= -1)");

	auto self = &t.stack[absSlot];
	auto methodName = createString(t, name);

	auto tmp = commonMethodCall(t, absSlot, self, self, methodName, numReturns, numParams);
	return commonCall(t, absSlot, numReturns, tmp);
}

/**
Same as above, but expects the name of the method to be on top of the stack (after the parameters).

The parameters and return value are the same as above.
*/
uword methodCall(CrocThread* t, word slot, word numReturns)
{
	mixin(apiCheckNumParams!("1"));
	auto absSlot = fakeToAbs(t, slot);

	if(!isString(t, -1))
	{
		pushTypeString(t, -1);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Method name must be a string, not a '{}'", getString(t, -1));
	}

	auto methodName = t.stack[t.stackIndex - 1].mString;
	pop(t);

	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - invalid number of returns (must be >= -1)");

	auto self = &t.stack[absSlot];

	auto tmp = commonMethodCall(t, absSlot, self, self, methodName, numReturns, numParams);
	return commonCall(t, absSlot, numReturns, tmp);
}

/**
Performs a super call. This function will only work if the currently-executing function was called as
a method of a value of type 'instance'.

This function works similarly to other kinds of calls, but it's somewhat odd. Other calls have you push the
thing to call followed by 'this' or a spot for it. This call requires you to just give it two empty slots.
It will fill them in (and what it puts in them is really kind of scary). Regardless, when the super method is
called (if there is one), its 'this' parameter will be the currently-executing function's 'this' parameter.

The process of performing a supercall is not really that much different from other kinds of calls.

-----
// Let's translate `super.f(3)` into API calls.

// 1. Push a null.
auto slot = pushNull(t);

// 2. Push another null. You can'_t call a super method with a custom 'this'.
pushNull(t);

// 3. Push any params.
pushInt(t, 3);

// 4. Call it with the method name.
superCall(t, slot, "f", 0);

// We didn'_t ask for any return values, so the stack is how it was before we began.
-----

Params:
	slot = The first empty _slot. There should be another one on top of it. Then come any parameters.
	name = The _name of the method to call.
	numReturns = How many return values you want. Can be -1, which means you'll get all returns.

Returns:
	The number of return values given by the function. If numReturns was -1, this is exactly how
	many returns the function gave. If numReturns was >= 0, this is the same as numReturns (and
	not exactly useful since you already know it).
*/
uword superCall(CrocThread* t, word slot, char[] name, word numReturns)
{
	mixin(FuncNameMix);

	// Invalid call?
	if(t.arIndex == 0 || t.currentAR.proto is null)
		throwStdException(t, "RuntimeException", __FUNCTION__ ~ " - Attempting to perform a supercall in a function where there is no super class");

	// Get num params
	auto absSlot = fakeToAbs(t, slot);
	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - invalid number of returns (must be >= -1)");

	// Get this
	auto _this = &t.stack[t.stackBase];

	if(_this.type != CrocValue.Type.Instance && _this.type != CrocValue.Type.Class)
	{
		pushTypeString(t, 0);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Attempting to perform a supercall in a function where 'this' is a '{}', not an 'instance' or 'class'", getString(t, -1));
	}

	// Do the call
	auto methodName = createString(t, name);
	auto ret = commonMethodCall(t, absSlot, _this, &CrocValue(t.currentAR.proto), methodName, numReturns, numParams);
	return commonCall(t, absSlot, numReturns, ret);
}

/**
Same as above, but expects the method name to be at the top of the stack (after the parameters).

The parameters and return value are the same as above.
*/
uword superCall(CrocThread* t, word slot, word numReturns)
{
	// Get the method name
	mixin(apiCheckNumParams!("1"));
	auto absSlot = fakeToAbs(t, slot);

	if(!isString(t, -1))
	{
		pushTypeString(t, -1);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Method name must be a string, not a '{}'", getString(t, -1));
	}

	auto methodName = t.stack[t.stackIndex - 1].mString;
	pop(t);

	// Invalid call?
	if(t.arIndex == 0 || t.currentAR.proto is null)
		throwStdException(t, "RuntimeException", __FUNCTION__ ~ " - Attempting to perform a supercall in a function where there is no super class");

	// Get num params
	auto numParams = t.stackIndex - (absSlot + 1);

	if(numParams < 1)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - too few parameters (must have at least 1 for the context)");

	if(numReturns < -1)
		throwStdException(t, "ApiError", __FUNCTION__ ~ " - invalid number of returns (must be >= -1)");

	// Get this
	auto _this = &t.stack[t.stackBase];

	if(_this.type != CrocValue.Type.Instance && _this.type != CrocValue.Type.Class)
	{
		pushTypeString(t, 0);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - Attempting to perform a supercall in a function where 'this' is a '{}', not an 'instance' or 'class'", getString(t, -1));
	}

	// Do the call
	auto ret = commonMethodCall(t, absSlot, _this, &CrocValue(t.currentAR.proto), methodName, numReturns, numParams);
	return commonCall(t, absSlot, numReturns, ret);
}

// ================================================================================================================================================
// Reflective functions

/**

*/
char[] nameOf(CrocThread* t, word obj)
{
	mixin(FuncNameMix);

	switch(getValue(t, obj).type)
	{
		case CrocValue.Type.Function:  return funcName(t, obj);
		case CrocValue.Type.Class:     return className(t, obj);
		case CrocValue.Type.Namespace: return namespaceName(t, obj);
		case CrocValue.Type.FuncDef:   return funcDefName(t, obj);
		default:
			pushTypeString(t, obj);
			throwStdException(t, "TypeException", __FUNCTION__ ~ " - Expected function, class, namespace, or funcdef, not '{}'", getString(t, -1));
	}

	assert(false);
}

/**
Sees if the object at the stack index `obj` has a field with the given name. Does not take opField
metamethods into account. Because of that, only works for tables, classes, instances, and namespaces.
If the object at the stack index `obj` is not one of those types, always returns false. If this
function returns true, you are guaranteed that accessing a field of the given name on the given object
will succeed.

Params:
	obj = The stack index of the object to test.
	fieldName = The name of the field to look up.

Returns:
	true if the field exists in `obj`; false otherwise.
*/
bool hasField(CrocThread* t, word obj, char[] fieldName)
{
	auto name = createString(t, fieldName);

	auto v = getValue(t, obj);

	switch(v.type)
	{
		case CrocValue.Type.Table:     return table.get(v.mTable, CrocValue(name)) !is null;
		case CrocValue.Type.Class:     return classobj.getField(v.mClass, name) !is null;
		case CrocValue.Type.Instance:  return instance.getField(v.mInstance, name) !is null;
		case CrocValue.Type.Namespace: return namespace.get(v.mNamespace, name) !is null;
		default:                       return false;
	}
}

/**
Sees if a method can be called on the object at stack index `obj`. Does not take opMethod metamethods
into account, but does take type metatables into account. In other words, if you look up a method in
an object and this function returns true, you are guaranteed that calling a method of that name on
that object will succeed.

Params:
	obj = The stack index of the obejct to test.
	methodName = The name of the method to look up.

Returns:
	true if the method can be called on `obj`; false otherwise.
*/
bool hasMethod(CrocThread* t, word obj, char[] methodName)
{
	CrocClass* dummy = void;
	return lookupMethod(t, getValue(t, obj), createString(t, methodName), dummy).type != CrocValue.Type.Null;
}

// ================================================================================================================================================
// Package
// ================================================================================================================================================

package:

CrocString* createString(CrocThread* t, char[] data)
{
	uword h = void;

	if(auto s = string.lookup(t.vm, data, h))
		return s;

	uword cpLen = void;

	try
		cpLen = verify(data);
	catch(UnicodeException e)
		throwStdException(t, "UnicodeException", "Invalid UTF-8 sequence");

	return string.create(t.vm, data, h, cpLen);
}
