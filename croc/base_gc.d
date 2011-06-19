/******************************************************************************
This module contains most of the implementation of the Croc garbage collector.
Some of it is defined in croc.interpreter, since D hates circular imports.

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

module croc.base_gc;

import croc.base_alloc;
import croc.types;
import croc.types_array;
import croc.types_class;
import croc.types_funcdef;
import croc.types_function;
import croc.types_instance;
import croc.types_namespace;
import croc.types_nativeobj;
import croc.types_string;
import croc.types_table;
import croc.types_thread;
import croc.types_weakref;

// ================================================================================================================================================
// Package
// ================================================================================================================================================

package:

// Perform the mark phase of garbage collection.
void mark(CrocVM* vm)
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
	
	foreach(val; vm.refTab)
		markObj(vm, cast(GCObject*)val);

	if(vm.isThrowing)
		mixin(CondMark!("vm.exception"));
}

// Perform the sweep phase of garbage collection.
void sweep(CrocVM* vm)
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
void free(CrocVM* vm, GCObject* o)
{
	if(auto r = vm.weakRefTab.lookup(cast(CrocBaseObject*)o))
	{
		(*r).obj = null;
		vm.weakRefTab.remove(cast(CrocBaseObject*)o);
	}

	switch((cast(CrocBaseObject*)o).mType)
	{
		case CrocValue.Type.String:    string.free(vm, cast(CrocString*)o); return;
		case CrocValue.Type.Table:     table.free(vm.alloc, cast(CrocTable*)o); return;
		case CrocValue.Type.Array:     array.free(vm.alloc, cast(CrocArray*)o); return;
		case CrocValue.Type.Function:  func.free(vm.alloc, cast(CrocFunction*)o); return;
		case CrocValue.Type.Class:     classobj.free(vm.alloc, cast(CrocClass*)o); return;

		case CrocValue.Type.Instance:
			auto i = cast(CrocInstance*)o;

			if(i.parent.finalizer && ((o.flags & GCBits.Finalized) == 0))
			{
				o.flags |= GCBits.Finalized;
				o.next = vm.alloc.finalizable;
				vm.alloc.finalizable = o;
			}
			else
				instance.free(vm.alloc, i);

			return;

		case CrocValue.Type.Namespace: namespace.free(vm.alloc, cast(CrocNamespace*)o); return;
		case CrocValue.Type.Thread:    thread.free(cast(CrocThread*)o); return;
		case CrocValue.Type.NativeObj: nativeobj.free(vm, cast(CrocNativeObj*)o); return;
		case CrocValue.Type.WeakRef:   weakref.free(vm, cast(CrocWeakRef*)o); return;
		case CrocValue.Type.FuncDef:   funcdef.free(vm.alloc, cast(CrocFuncDef*)o); return;

		case CrocValue.Type.Upvalue:   vm.alloc.free(cast(CrocUpval*)o); return;

		default: debug Stdout.formatln("{}", (cast(CrocBaseObject*)o).mType); assert(false);
	}
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

// For marking CrocValues.  Marks it only if it's an object.
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
void markObj(CrocVM* vm, GCObject* o)
{
	switch((cast(CrocBaseObject*)o).mType)
	{
		case CrocValue.Type.String, CrocValue.Type.NativeObj, CrocValue.Type.WeakRef:
			// These are trivial, just mark them here.
			o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;
			return;

		case CrocValue.Type.Table:     markObj(vm, cast(CrocTable*)o); return;
		case CrocValue.Type.Array:     markObj(vm, cast(CrocArray*)o); return;
		case CrocValue.Type.Function:  markObj(vm, cast(CrocFunction*)o); return;
		case CrocValue.Type.Class:     markObj(vm, cast(CrocClass*)o); return;
		case CrocValue.Type.Instance:  markObj(vm, cast(CrocInstance*)o); return;
		case CrocValue.Type.Namespace: markObj(vm, cast(CrocNamespace*)o); return;
		case CrocValue.Type.Thread:    markObj(vm, cast(CrocThread*)o); return;

		case CrocValue.Type.Upvalue:   markObj(vm, cast(CrocUpval*)o); return;
		case CrocValue.Type.FuncDef:   markObj(vm, cast(CrocFuncDef*)o); return;
		default: assert(false);
	}
}

// Mark a string.
void markObj(CrocVM* vm, CrocString* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;
}

// Mark a table.
void markObj(CrocVM* vm, CrocTable* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;

	bool anyWeakRefs = false;

	foreach(ref key, ref val; o.data)
	{
		mixin(CondMark!("key"));
		mixin(CondMark!("val"));

		if(!anyWeakRefs && key.type == CrocValue.Type.WeakRef || val.type == CrocValue.Type.WeakRef)
			anyWeakRefs = true;
	}

	if(anyWeakRefs)
	{
		o.nextTab = vm.toBeNormalized;
		vm.toBeNormalized = o;
	}
}

// Mark an array.
void markObj(CrocVM* vm, CrocArray* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;

	foreach(ref val; o.toArray())
		mixin(CondMark!("val"));
}

// Mark a function.
void markObj(CrocVM* vm, CrocFunction* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;
	markObj(vm, o.environment);

	if(o.name)
		markObj(vm, o.name);

	if(o.isNative)
	{
		foreach(ref uv; o.nativeUpvals())
			mixin(CondMark!("uv"));
	}
	else
	{
		markObj(vm, o.scriptFunc);

		foreach(uv; o.scriptUpvals)
			markObj(vm, uv);
	}
}

// Mark a class.
void markObj(CrocVM* vm, CrocClass* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;

	if(o.name)      markObj(vm, o.name);
	if(o.parent)    markObj(vm, o.parent);
	if(o.fields)    markObj(vm, o.fields);
	if(o.allocator) markObj(vm, o.allocator);
	if(o.finalizer) markObj(vm, o.finalizer);
}

// Mark an instance.
void markObj(CrocVM* vm, CrocInstance* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;

	if(o.parent)    markObj(vm, o.parent);
	if(o.fields)    markObj(vm, o.fields);

	foreach(ref val; o.extraValues())
		mixin(CondMark!("val"));
}

// Mark a namespace.
void markObj(CrocVM* vm, CrocNamespace* o)
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
void markObj(CrocVM* vm, CrocThread* o)
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
		mixin(CondMark!("val"));

	// I guess this can't _hurt_..
	o.stack[o.stackIndex .. $] = CrocValue.nullValue;

	foreach(ref val; o.results[0 .. o.resultIndex])
		mixin(CondMark!("val"));

	for(auto uv = o.upvalHead; uv !is null; uv = uv.nextuv)
		markObj(vm, uv);

	if(o.coroFunc)
		markObj(vm, o.coroFunc);

	if(o.hookFunc)
		markObj(vm, o.hookFunc);

	version(CrocExtendedCoro)
	{
		if(o.coroFiber)
			markObj(vm, o.coroFiber);
	}
}

// Mark a native object.
void markObj(CrocVM* vm, CrocNativeObj* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;
}

// Mark a weak reference.
void markObj(CrocVM* vm, CrocWeakRef* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;
}

// Mark an upvalue.
void markObj(CrocVM* vm, CrocUpval* o)
{
	o.flags = (o.flags & ~GCBits.Marked) | vm.alloc.markVal;
	mixin(CondMark!("o.value"));
}

// Mark a function definition.
void markObj(CrocVM* vm, CrocFuncDef* o)
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

	if(o.environment && ((o.environment.flags & GCBits.Marked) ^ vm.alloc.markVal))
		markObj(vm, o.environment);

	if(o.cachedFunc && ((o.cachedFunc.flags & GCBits.Marked) ^ vm.alloc.markVal))
		markObj(vm, o.cachedFunc);
}