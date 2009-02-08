/******************************************************************************
This module contains most of the implementation of the MiniD garbage collector.
Some of it is defined in minid.interpreter, since D hates circular imports.

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
import minid.classobj;
import minid.func;
import minid.funcdef;
import minid.instance;
import minid.namespace;
import minid.nativeobj;
import minid.string;
import minid.table;
import minid.thread;
import minid.types;
import minid.weakref;

// ================================================================================================================================================
// Package
// ================================================================================================================================================

package:

// Perform the mark phase of garbage collection.
void mark(MDVM* vm)
{
	vm.toBeNormalized = null;

	foreach(mt; vm.metaTabs)
		if(mt)
			markObj(vm, mt);

	foreach(s; vm.metaStrings)
		markObj(vm, s);

	foreach(ref l; vm.traceback)
		markObj(vm, l.file);

	markObj(vm, vm.globals);
	markObj(vm, vm.mainThread);
	markObj(vm, vm.registry);
	
	if(vm.isThrowing)
	{
		mixin(CondMark!("vm.exception"));
	}
}

// Perform the sweep phase of garbage collection.
void sweep(MDVM* vm)
{
	auto markVal = vm.alloc.markVal;

	for(auto pcur = &vm.alloc.gcHead; *pcur !is null; )
	{
		auto cur = *pcur;

		if((cur.flags & GCBits.Marked) ^ markVal)
		{
			*pcur = cur.next;
			free(vm, cur);
		}
		else
			pcur = &cur.next;
	}

	vm.stringTab.minimize(vm.alloc);
	vm.weakRefTab.minimize(vm.alloc);
	
	for(auto t = vm.toBeNormalized; t !is null; t = t.nextTab)
		table.normalize(t);

	vm.alloc.markVal = markVal == 0 ? GCBits.Marked : 0;
}

debug import tango.io.Stdout;

// Free an object.
void free(MDVM* vm, GCObject* o)
{
	if(auto r = vm.weakRefTab.lookup(cast(MDBaseObject*)o))
	{
		(*r).obj = null;
		vm.weakRefTab.remove(cast(MDBaseObject*)o);
	}

	switch((cast(MDBaseObject*)o).mType)
	{
		case MDValue.Type.String:    string.free(vm, cast(MDString*)o); return;
		case MDValue.Type.Table:     table.free(vm.alloc, cast(MDTable*)o); return;
		case MDValue.Type.Array:     array.free(vm.alloc, cast(MDArray*)o); return;
		case MDValue.Type.Function:  func.free(vm.alloc, cast(MDFunction*)o); return;
		case MDValue.Type.Class:     classobj.free(vm.alloc, cast(MDClass*)o); return;

		case MDValue.Type.Instance:
			auto i = cast(MDInstance*)o;

			if(i.finalizer && ((o.flags & GCBits.Finalized) == 0))
			{
				o.flags |= GCBits.Finalized;
				o.next = vm.alloc.finalizable;
				vm.alloc.finalizable = o;
			}
			else
				instance.free(vm.alloc, i);

			return;

		case MDValue.Type.Namespace: namespace.free(vm.alloc, cast(MDNamespace*)o); return;
		case MDValue.Type.Thread:    thread.free(cast(MDThread*)o); return;
		case MDValue.Type.NativeObj: nativeobj.free(vm, cast(MDNativeObj*)o); return;
		case MDValue.Type.WeakRef:   weakref.free(vm, cast(MDWeakRef*)o); return;

		case MDValue.Type.Upvalue:   vm.alloc.free(cast(MDUpval*)o); return;
		case MDValue.Type.FuncDef:   funcdef.free(vm.alloc, cast(MDFuncDef*)o); return;
		case MDValue.Type.ArrayData: array.freeData(vm.alloc, cast(MDArrayData*)o); return;

		default: debug Stdout.formatln("{}", (cast(MDBaseObject*)o).mType); assert(false);
	}
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

// For marking MDValues.  Marks it only if it's an object.
template CondMark(char[] name)
{
	const CondMark =
	"if(" ~ name ~ ".isObject())
	{
		auto obj = " ~ name ~ ".toGCObject();

		if((obj.flags & GCBits.Marked) ^ vm.alloc.markVal)
			markObj(vm, obj);
	}";
}

// Dynamically dispatch the appropriate marking method at runtime from a GCObject*.
void markObj(MDVM* vm, GCObject* o)
{
	switch((cast(MDBaseObject*)o).mType)
	{
		case MDValue.Type.String, MDValue.Type.NativeObj, MDValue.Type.WeakRef:
			// These are trivial, just mark them here.
			o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;
			return;

		case MDValue.Type.Table:     markObj(vm, cast(MDTable*)o); return;
		case MDValue.Type.Array:     markObj(vm, cast(MDArray*)o); return;
		case MDValue.Type.Function:  markObj(vm, cast(MDFunction*)o); return;
		case MDValue.Type.Class:     markObj(vm, cast(MDClass*)o); return;
		case MDValue.Type.Instance:  markObj(vm, cast(MDInstance*)o); return;
		case MDValue.Type.Namespace: markObj(vm, cast(MDNamespace*)o); return;
		case MDValue.Type.Thread:    markObj(vm, cast(MDThread*)o); return;

		case MDValue.Type.Upvalue:   markObj(vm, cast(MDUpval*)o); return;
		case MDValue.Type.FuncDef:   markObj(vm, cast(MDFuncDef*)o); return;
		default: assert(false);
	}
}

// Mark a string.
void markObj(MDVM* vm, MDString* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;
}

// Mark a table.
void markObj(MDVM* vm, MDTable* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;

	bool anyWeakRefs = false;

	foreach(ref key, ref val; o.data)
	{
		mixin(CondMark!("key"));
		mixin(CondMark!("val"));

		if(!anyWeakRefs && key.type == MDValue.Type.WeakRef || val.type == MDValue.Type.WeakRef)
			anyWeakRefs = true;
	}

	if(anyWeakRefs)
	{
		o.nextTab = vm.toBeNormalized;
		vm.toBeNormalized = o;
	}
}

// Mark an array.
void markObj(MDVM* vm, MDArray* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;
	o.data.flags = (o.data.flags & ~GCBits.Marked) | vm.alloc.markVal;

	foreach(ref val; o.slice)
	{
		mixin(CondMark!("val"));
	}
}

// Mark a function.
void markObj(MDVM* vm, MDFunction* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;
	markObj(vm, o.environment);

	if(o.name)
		markObj(vm, o.name);

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

// Mark a class.
void markObj(MDVM* vm, MDClass* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;

	if(o.name)      markObj(vm, o.name);
	if(o.parent)    markObj(vm, o.parent);
	if(o.fields)    markObj(vm, o.fields);
	if(o.allocator) markObj(vm, o.allocator);
	if(o.finalizer) markObj(vm, o.finalizer);
}

// Mark an instance.
void markObj(MDVM* vm, MDInstance* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;

	if(o.parent)    markObj(vm, o.parent);
	if(o.fields)    markObj(vm, o.fields);
	if(o.finalizer) markObj(vm, o.finalizer);

	foreach(ref val; o.extraValues())
	{
		mixin(CondMark!("val"));
	}
}

// Mark a namespace.
void markObj(MDVM* vm, MDNamespace* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;

	foreach(key, ref val; o.data)
	{
		markObj(vm, key);
		mixin(CondMark!("val"));
	}

	if(o.parent) markObj(vm, o.parent);
	markObj(vm, o.name);
}

// Mark a thread.
void markObj(MDVM* vm, MDThread* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;

	foreach(ref ar; o.actRecs[0 .. o.arIndex])
	{
		if(ar.func)
			markObj(vm, ar.func);

		if(ar.proto)
			markObj(vm, ar.proto);
	}

	foreach(ref val; o.stack[0 .. o.stackIndex])
	{
		mixin(CondMark!("val"));
	}

	// I guess this can't _hurt_..
	o.stack[o.stackIndex .. $] = MDValue.nullValue;

	foreach(ref val; o.results[0 .. o.resultIndex])
	{
		mixin(CondMark!("val"));
	}

	for(auto uv = o.upvalHead; uv !is null; uv = uv.nextuv)
	{
		mixin(CondMark!("uv.value"));
	}

	if(o.coroFunc)
		markObj(vm, o.coroFunc);
		
	if(o.hookFunc)
		markObj(vm, o.hookFunc);

	version(MDExtendedCoro)
	{
		if(o.coroFiber)
			markObj(vm, o.coroFiber);
	}
}

// Mark a native object.
void markObj(MDVM* vm, MDNativeObj* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;
}

// Mark a weak reference.
void markObj(MDVM* vm, MDWeakRef* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;
}

// Mark an upvalue.
void markObj(MDVM* vm, MDUpval* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;
	mixin(CondMark!("o.value"));
}

// Mark a function definition.
void markObj(MDVM* vm, MDFuncDef* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;

	if(o.location.file)
		markObj(vm, o.location.file);
		
	if(o.name)
		markObj(vm, o.name);

	foreach(f; o.innerFuncs)
		if(f)
			markObj(vm, f);

	foreach(ref val; o.constants)
	{
		if(val.isObject())
		{
			auto obj = val.toGCObject();

			if(obj && ((obj.flags & GCBits.Marked) ^ vm.alloc.markVal))
				markObj(vm, obj);
		}
	}

	foreach(ref st; o.switchTables)
	{
		foreach(key, _; st.offsets)
		{
			if(key.isObject())
			{
				auto obj = key.toGCObject();

				if(obj && ((obj.flags & GCBits.Marked) ^ vm.alloc.markVal))
					markObj(vm, obj);
			}
		}
	}

	foreach(name; o.upvalNames)
		if(name)
			markObj(vm, name);

	foreach(ref desc; o.locVarDescs)
		if(desc.name)
			markObj(vm, desc.name);

	if(o.cachedFunc && ((o.cachedFunc.flags & GCBits.Marked) ^ vm.alloc.markVal))
		markObj(vm, o.cachedFunc);
}