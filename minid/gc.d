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

module minid.gc;

import minid.alloc;
import minid.array;
import minid.func;
import minid.funcdef;
import minid.namespace;
import minid.nativeobj;
import minid.obj;
import minid.string;
import minid.table;
import minid.thread;
import minid.types;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

/**
Runs the garbage collector of the VM if necessary.

This will perform a garbage collection only if a sufficient number of objects have been allocated since
the last collection.

Params:
	vm = The VM whose garbage is to be collected.
*/
public void maybeGC(MDVM* vm)
{
	if(vm.alloc.gcCount >= vm.alloc.gcLimit)
	{
		gc(vm);

		if(vm.alloc.gcCount > (vm.alloc.gcLimit >> 1))
			vm.alloc.gcLimit <<= 1;
	}
}

/**
Runs the VM's garbage collector unconditionally.

Params:
	vm = The VM whose garbage is to be collected.
*/
public void gc(MDVM* vm)
{
	mark(vm);
	sweep(vm);
}

/**
Find out how many bytes of memory the given VM has allocated.
*/
public size_t bytesAllocated(MDVM* vm)
{
	return vm.alloc.totalBytes;
}

// ================================================================================================================================================
// Package
// ================================================================================================================================================

// Free all objects.
package void freeAll(MDVM* vm)
{
	GCObject* next = void;

	for(auto cur = vm.alloc.gcHead; cur !is null; cur = next)
	{
		next = cur.next;
		free(vm, cur);
	}
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

// For marking MDValues.  Marks it only if it's an object.
private template CondMark(char[] name)
{
	const CondMark =
	"if(" ~ name ~ ".isObject())
	{
		auto obj = " ~ name ~ ".toGCObject();

		if(obj.marked != vm.alloc.markVal)
			markObj(vm, obj);
	}";
}

// Dynamically dispatch the appropriate marking method at runtime from a GCObject*.
private void markObj(MDVM* vm, GCObject* o)
{
	switch((cast(MDBaseObject*)o).mType)
	{
		case MDValue.Type.String, MDValue.Type.NativeObj:
			// These are trivial, just mark them here.
			o.marked = vm.alloc.markVal;
			return;

		case MDValue.Type.Table:     markObj(vm, cast(MDTable*)o); return;
		case MDValue.Type.Array:     markObj(vm, cast(MDArray*)o); return;
		case MDValue.Type.Function:  markObj(vm, cast(MDFunction*)o); return;
		case MDValue.Type.Object:    markObj(vm, cast(MDObject*)o); return;
		case MDValue.Type.Namespace: markObj(vm, cast(MDNamespace*)o); return;
		case MDValue.Type.Thread:    markObj(vm, cast(MDThread*)o); return;

		case MDValue.Type.Upvalue:   markObj(vm, cast(MDUpval*)o); return;
		case MDValue.Type.FuncDef:   markObj(vm, cast(MDFuncDef*)o); return;
		default: assert(false);
	}
}

// Mark a string.
private void markObj(MDVM* vm, MDString* o)
{
	o.marked = vm.alloc.markVal;
}

// Mark a table.
private void markObj(MDVM* vm, MDTable* o)
{
	o.marked = vm.alloc.markVal;

	foreach(ref key, ref val; o.data)
	{
		mixin(CondMark!("key"));
		mixin(CondMark!("val"));
	}
}

// Mark an array.
private void markObj(MDVM* vm, MDArray* o)
{
	o.marked = vm.alloc.markVal;
	o.data.marked = vm.alloc.markVal;

	foreach(ref val; o.slice)
	{
		mixin(CondMark!("val"));
	}
}

// Mark a function.
private void markObj(MDVM* vm, MDFunction* o)
{
	o.marked = vm.alloc.markVal;
	markObj(vm, o.environment);

	if(o.name)
		markObj(vm, o.name);

	if(o.attrs)
		markObj(vm, o.attrs);

	if(o.isNative)
	{
		foreach(ref uv; o.nativeUpvals())
		{
			mixin(CondMark!("uv"));
		}
	}
	else
	{
		markObj(vm, o.scriptFunc);

		foreach(uv; o.scriptUpvals)
			markObj(vm, uv);
	}
}

// Mark an object.
private void markObj(MDVM* vm, MDObject* o)
{
	o.marked = vm.alloc.markVal;

	if(o.name)        markObj(vm, o.name);
	if(o.proto)       markObj(vm, o.proto);
	if(o.fields)      markObj(vm, o.fields);
	if(o.attrs)       markObj(vm, o.attrs);

	foreach(ref val; o.extraValues())
	{
		mixin(CondMark!("val"));
	}
}

// Mark a namespace.
private void markObj(MDVM* vm, MDNamespace* o)
{
	o.marked = vm.alloc.markVal;

	foreach(key, ref val; o.data)
	{
		markObj(vm, key);
		mixin(CondMark!("val"));
	}

	if(o.parent) markObj(vm, o.parent);
	if(o.attrs)  markObj(vm, o.attrs);

	markObj(vm, o.name);
}

// Mark a thread.
private void markObj(MDVM* vm, MDThread* o)
{
	o.marked = vm.alloc.markVal;

	foreach(ref ar; o.actRecs[0 .. o.arIndex])
	{
		markObj(vm, ar.func);

		if(ar.proto)
			markObj(vm, ar.proto);
	}

	foreach(ref val; o.stack[0 .. o.stackIndex])
	{
		mixin(CondMark!("val"));
	}

	o.stack[o.stackIndex .. $] = MDValue.nullValue;

	foreach(ref val; o.results[0 .. o.resultIndex])
	{
		mixin(CondMark!("val"));
	}

	for(auto uv = o.upvalHead; uv !is null; uv = uv.next)
	{
		mixin(CondMark!("uv.value"));
	}

	if(o.coroFunc)
		markObj(vm, o.coroFunc);

	version(MDRestrictedCoro) {} else
	{
		if(o.coroFiber)
			markObj(vm, o.coroFiber);
	}
}

// Mark a native object.
private void markObj(MDVM* vm, MDNativeObj* o)
{
	o.marked = vm.alloc.markVal;
}

// Mark an upvalue.
private void markObj(MDVM* vm, MDUpval* o)
{
	o.marked = vm.alloc.markVal;
	mixin(CondMark!("o.value"));
}

// Mark a function definition.
private void markObj(MDVM* vm, MDFuncDef* o)
{
	o.marked = vm.alloc.markVal;

	markObj(vm, o.location.fileName);
	markObj(vm, o.name);

	foreach(f; o.innerFuncs)
		markObj(vm, f);

	foreach(ref val; o.constants)
	{
		mixin(CondMark!("val"));
	}

	foreach(ref st; o.switchTables)
		foreach(key, _; st.offsets)
		{
			mixin(CondMark!("key"));
		}

	foreach(name; o.upvalNames)
		markObj(vm, name);

	foreach(desc; o.locVarDescs)
		markObj(vm, desc.name);

	// Don't need to mark the cached func here, since if we're marking this func def,
	// we must have marked its cached func (if any).
}

// Perform the mark phase of garbage collection.
private void mark(MDVM* vm)
{
	foreach(mt; vm.metaTabs)
		if(mt)
			markObj(vm, mt);

	foreach(s; vm.metaStrings)
		markObj(vm, s);

	markObj(vm, vm.globals);
	markObj(vm, vm.mainThread);
	
	if(vm.isThrowing)
	{
		mixin(CondMark!("vm.exception"));
	}
}

// Perform the sweep phase of garbage collection.
private void sweep(MDVM* vm)
{
	for(auto pcur = &vm.alloc.gcHead; *pcur !is null; )
	{
		auto cur = *pcur;

		if(cur.marked != vm.alloc.markVal)
		{
			*pcur = cur.next;
			free(vm, cur);
		}
		else
			pcur = &cur.next;
	}

	vm.stringTab.minimize(vm.alloc);
	vm.alloc.markVal = !vm.alloc.markVal;
}

debug import tango.io.Stdout;

// Free an object.
private void free(MDVM* vm, GCObject* o)
{
	switch((cast(MDBaseObject*)o).mType)
	{
		case MDValue.Type.String:    string.free(vm, cast(MDString*)o); return;
		case MDValue.Type.Table:     table.free(vm.alloc, cast(MDTable*)o); return;
		case MDValue.Type.Array:     array.free(vm.alloc, cast(MDArray*)o); return;
		case MDValue.Type.Function:  func.free(vm.alloc, cast(MDFunction*)o); return;
		case MDValue.Type.Object:    obj.free(vm.alloc, cast(MDObject*)o); return;
		case MDValue.Type.Namespace: namespace.free(vm.alloc, cast(MDNamespace*)o); return;
		case MDValue.Type.Thread:    thread.free(cast(MDThread*)o); return;
		case MDValue.Type.NativeObj: nativeobj.free(vm, cast(MDNativeObj*)o); return;

		case MDValue.Type.Upvalue:   vm.alloc.free(cast(MDUpval*)o); return;
		case MDValue.Type.FuncDef:   funcdef.free(vm.alloc, cast(MDFuncDef*)o); return;
		case MDValue.Type.ArrayData: array.freeData(vm.alloc, cast(MDArrayData*)o); return;

		default: debug Stdout.formatln("{}", (cast(MDBaseObject*)o).mType); assert(false);
	}
}