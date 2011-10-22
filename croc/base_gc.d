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
import croc.types_memblock;
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

/*
Buffers which grow during the mutation phase:
	modified buffer (RC space objects whose reference fields were modified during the mutation phase; filled by the write barrier)
	decrement buffer (objects which have a queued decrement, can be here more than once I suppose)

Buffers which are only changed/used during the collection phase:
	old root buffer (objects that were roots _last_ collection cycle)
	new root buffer (objects that are roots _this_ collection cycle)
	possible cycle buffer (objects which may be part of cycles)
	finalize buffer (finalizable objects which have died and need to be finalized)
*/

void gcCycle(CrocVM* vm)
{
	assert(vm.inGCCycle);
	assert(vm.alloc.gcDisabled == 0);

	// Upon entry:
	// 	modified buffer contains all objects that were logged between collections.
	// 	decrement buffer can have stuff in it.
	// 	old root buffer contains last collection's new roots.
	// 	new root buffer is empty.
	// 	possible cycle buffer is empty.
	// 	finalize buffer is empty.

	auto modBuffer = &vm.alloc.modBuffer;
	auto decBuffer = &vm.alloc.decBuffer;
	auto cycleRoots = &vm.cycleRoots;
	auto toFinalize = &vm.toFinalize;

	{ // block to control scope of old/newRoots
	auto oldRoots = &vm.roots[vm.oldRootIdx];
	auto newRoots = &vm.roots[1 - vm.oldRootIdx];

	assert(newRoots.isEmpty());
	assert(cycleRoots.isEmpty());
	assert(toFinalize.isEmpty());

	// ROOT PHASE. Go through roots, including stacks, and for each object reference, if it's in the nursery, copy it out and leave a forwarding address.
	// 	Regardless of whether it's a nursery object or not, put it in the new root buffer.

	visitRoots(vm, (GCObject** obj)
	{
		if(((*obj).gcflags & GCFlags.InRC) == 0)
			*obj = copyOutOfNursery(vm, *obj);

		newRoots.add(vm.alloc, *obj);
	});

	// PROCESS MODIFIED BUFFER. Go through the modified buffer, unlogging each. For each object pointed to by an object, if it's in the nursery, copy it
	// 	out (or just forward if that's already happened). Increment all the reference counts (spurious increments to RC space objects will be undone
	// 	by the queued decrements created during the mutation phase by the write barrier).
	foreach(obj; *modBuffer)
	{
		obj.gcflags |= GCFlags.Unlogged;

		visitObj(obj, (GCObject** slot)
		{
			if((*slot).gcflags & GCFlags.Forwarded)
				*slot = (*slot).forwardPointer;
			else if(((*slot).gcflags & GCFlags.InRC) == 0)
				*slot = copyOutOfNursery(vm, *slot);

			rcIncrement(*slot);
		});
	}

	modBuffer.reset();

	// PROCESS OLD ROOT BUFFER. Move all objects from the old root buffer into the decrement buffer.
	decBuffer.append(vm.alloc, *oldRoots);
	oldRoots.reset();

	// PROCESS NEW ROOT BUFFER. Go through the new root buffer, incrementing their RCs, and put them all in the old root buffer.
	foreach(obj; *newRoots)
		rcIncrement(obj);

	// heehee sneaky
	vm.oldRootIdx = 1 - vm.oldRootIdx;
	}

	// PROCESS DECREMENT BUFFER. Go through the decrement buffer, decrementing their RCs. If an RC hits 0, if it's not finalizable, queue decrements for
	// 	any RC objects it points to, and free it. If it is finalizable, put it on the finalize list. If an RC is nonzero after being decremented, mark
	// 	it as a possible cycle root as follows: if its color is not purple, color it purple, and if it's not already buffered, mark it buffered and
	// 	put it in the possible cycle buffer.

	while(!decBuffer.isEmpty())
	{
		auto obj = decBuffer.remove();

		if(--obj.refCount == 0)
		{
			// Ref count hit 0. It's garbage.

			// TODO: figure out if it's possible for a finalizable object's members to be collected before it is. I doubt it buuuut..
			if((obj.gcflags & GCFlags.Finalizable) && (obj.gcflags & GCFlags.Finalized) == 0)
			{
				obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Black;
				toFinalize.add(vm.alloc, cast(CrocInstance*)obj);
			}
			else
			{
				visitObj(obj, (GCObject** slot)
				{
					decBuffer.add(vm.alloc, *slot);
				});

				free(vm, obj);
			}
		}
		else
		{
			// Ref count hasn't hit 0 yet, which means it's a potential cycle root (unless it's acyclic).
			debug assert(obj.refCount != typeof(obj.refCount).max);

			auto color = obj.gcflags & GCFlags.ColorMask;

			if(color != GCFlags.Green && color != GCFlags.Purple)
			{
				obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Purple;

				if((obj.gcflags & GCFlags.CycleLogged) == 0)
				{
					obj.gcflags |= GCFlags.CycleLogged;
					cycleRoots.add(vm.alloc, obj);
				}
			}
		}
	}

	for(void* ptr = vm.alloc.nurseryStart; ptr < vm.alloc.nurseryPtr; )
	{
		auto obj = cast(GCObject*)ptr;

		if((obj.gcflags & GCFlags.Forwarded) == 0)
		{
			assert((obj.gcflags & GCFlags.Finalizable) == 0);
			finalizeBuiltin(vm, obj);
		}

		ptr = cast(void*)((cast(uword)ptr + obj.memSize + Allocator.nurseryAlignment) & ~Allocator.nurseryAlignment);
	}

	vm.alloc.clearNurserySpace();

	// TODO: possibly grow nursery at this point

	// CYCLE DETECT. Mark, scan, and collect as described in Bacon and Rajan. When collecting, if something is finalizable, BITCH AND MOAN,
	// 	cause finalizable objects in cycles mean having to solve the halting problem. That sounds like a buuuuug.

	// TODO: determine whether we have to do a cycle collection or not (cycleRoots size threshold and/or number of collections since last?)
// 	if(cycleCollectionEnabled)
		collectCycles(vm);

	// At this point:
	// 	modified buffer is empty.
	// 	decrement buffer is empty.
	// 	old root buffer is what the new root buffer was after the root phase.
	// 	new root buffer is empty.
	// 	possible cycle buffer is empty if we did a cycle collection.
	assert(modBuffer.isEmpty());
	assert(decBuffer.isEmpty());
	assert(vm.roots[1 - vm.oldRootIdx].isEmpty());

// 	debug if(cycleCollectionEnabled)
		assert(cycleRoots.isEmpty());
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

GCObject* copyOutOfNursery(CrocVM* vm, GCObject* obj)
{
	assert((obj.gcflags & GCFlags.InRC) == 0);

	auto ret = vm.alloc.copyToRC(obj);

	ret.gcflags |= GCFlags.InRC | GCFlags.Unlogged;
	ret.refCount = 0;

	obj.gcflags = GCFlags.Forwarded;
	obj.forwardPointer = ret;

	switch((cast(CrocBaseObject*)obj).mType)
	{
		case CrocValue.Type.String:  auto o = cast(CrocString*)ret; *vm.stringTab.lookup(o.toString()) = o; break;
		case CrocValue.Type.WeakRef: auto o = cast(CrocWeakRef*)ret; *vm.weakRefTab.lookup(o.obj) = o; break;
		case CrocValue.Type.NativeObj: auto o = cast(CrocNativeObj*)ret; vm.nativeObjs[o.obj] = o; break;
		default: break;
	}

	return ret;
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

	finalizeBuiltin(vm, o);
	vm.alloc.free(o);
}

void finalizeBuiltin(CrocVM* vm, GCObject* o)
{
	switch((cast(CrocBaseObject*)o).mType)
	{
		case CrocValue.Type.String:    string.finalize(vm, cast(CrocString*)o); return;
		case CrocValue.Type.Table:     table.finalize(vm.alloc, cast(CrocTable*)o); return;
		case CrocValue.Type.Array:     array.finalize(vm.alloc, cast(CrocArray*)o); return;
		case CrocValue.Type.Memblock:  memblock.finalize(vm.alloc, cast(CrocMemblock*)o); return;
		case CrocValue.Type.Namespace: namespace.finalize(vm.alloc, cast(CrocNamespace*)o); return;
		case CrocValue.Type.Thread:    thread.finalize(cast(CrocThread*)o); return;
		case CrocValue.Type.NativeObj: nativeobj.finalize(vm, cast(CrocNativeObj*)o); return;
		case CrocValue.Type.WeakRef:   weakref.finalize(vm, cast(CrocWeakRef*)o); return;
		case CrocValue.Type.FuncDef:   funcdef.finalize(vm.alloc, cast(CrocFuncDef*)o); return;

		case
			CrocValue.Type.Function,
			CrocValue.Type.Class,
			CrocValue.Type.Instance,
			CrocValue.Type.Upvalue: break;


		default: debug Stdout.formatln("{}", (cast(CrocBaseObject*)o).mType); assert(false);
	}
}

void rcIncrement(GCObject* obj)
{
	obj.refCount++;

	if((obj.gcflags & GCFlags.Green) == 0)
		obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Black;
}

void collectCycles(CrocVM* vm)
{
	auto cycleRoots = &vm.cycleRoots;

	// Mark
	for(auto it = cycleRoots.iterator(); it.hasNext(); )
	{
		auto obj = it.next();

		if((obj.gcflags & GCFlags.ColorMask) == GCFlags.Purple)
			markGray(obj);
		else
		{
			obj.gcflags &= ~GCFlags.CycleLogged;
			it.removeCurrent();

			if((obj.gcflags & GCFlags.ColorMask) == GCFlags.Black && obj.refCount == 0)
				free(vm, obj);
		}
	}

	// Scan
	foreach(obj; *cycleRoots)
		cycleScan(obj);

	// Collect
	while(!cycleRoots.isEmpty())
	{
		auto obj = cycleRoots.remove();
		obj.gcflags &= ~GCFlags.CycleLogged;
		collectCycleWhite(vm, obj);
	}
}

void markGray(GCObject* obj)
{
	if((obj.gcflags & GCFlags.ColorMask) == GCFlags.Green)
		return;

	if((obj.gcflags & GCFlags.ColorMask) != GCFlags.Grey)
	{
		obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Grey;

		visitObj(obj, (GCObject** slot)
		{
			(*slot).refCount--;
			markGray(*slot);
		});
	}
}

void cycleScan(GCObject* obj)
{
	if((obj.gcflags & GCFlags.ColorMask) == GCFlags.Grey)
	{
		if(obj.refCount > 0)
			cycleScanBlack(obj);
		else
		{
			obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.White;

			visitObj(obj, (GCObject** slot)
			{
				cycleScan(*slot);
			});
		}
	}
}

void cycleScanBlack(GCObject* obj)
{
	if((obj.gcflags & GCFlags.ColorMask) == GCFlags.Green)
		return;

	obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Black;

	visitObj(obj, (GCObject** slot)
	{
		(*slot).refCount++;

		if(((*slot).gcflags & GCFlags.ColorMask) != GCFlags.Black)
			cycleScanBlack(*slot);
	});
}

void collectCycleWhite(CrocVM* vm, GCObject* obj)
{
	auto color = obj.gcflags & GCFlags.ColorMask;

	if((color == GCFlags.White || color == GCFlags.Green) && (obj.gcflags & GCFlags.CycleLogged) == 0)
	{
		if((obj.gcflags & GCFlags.Finalizable) && (obj.gcflags & GCFlags.Finalized) == 0)
			throw new /* CrocFatal */Exception("Unfinalized finalizable object in cycle!");

		obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Black;

		if(color != GCFlags.Green)
		{
			visitObj(obj, (GCObject** slot)
			{
				collectCycleWhite(vm, *slot);
			});
		}

		free(vm, obj);
	}
}

//
// // Perform the sweep phase of garbage collection.
// void sweep(CrocVM* vm)
// {
// 	auto markVal = vm.alloc.markVal;
//
// 	for(auto pcur = &vm.alloc.gcHead; *pcur !is null; )
// 	{
// 		auto cur = *pcur;
//
// 		if((cur.flags & GCBits.Marked) ^ markVal)
// 		{
// 			*pcur = cur.next;
// 			free(vm, cur);
// 		}
// 		else
// 			pcur = &cur.next;
// 	}
//
//
// 	vm.alloc.markVal = markVal == 0 ? GCBits.Marked : 0;
// }
//

// Visit the roots of this VM.
void visitRoots(CrocVM* vm, void delegate(GCObject**) callback)
{
	callback(cast(GCObject**)&vm.globals);
	callback(cast(GCObject**)&vm.mainThread);

	// TODO: visit ALL the threads!
	visitThread(vm.mainThread, callback);

	foreach(ref mt; vm.metaTabs)
		if(mt)
			callback(cast(GCObject**)&mt);

	foreach(ref s; vm.metaStrings)
		callback(cast(GCObject**)&s);

	// TODO: change vm.exception to a CrocInstance*
	if(vm.isThrowing)
		mixin(CondCallback!("vm.exception"));

	callback(cast(GCObject**)&vm.registry);

	foreach(ref val; vm.refTab)
		callback(cast(GCObject**)&val);

	callback(cast(GCObject**)&vm.object);
	callback(cast(GCObject**)&vm.throwable);
	callback(cast(GCObject**)&vm.location);

	foreach(ref k, ref v; vm.stdExceptions)
	{
		callback(cast(GCObject**)&k);
		callback(cast(GCObject**)&v);
	}
}

// For visiting CrocValues. Visits it only if it's an object.
template CondCallback(char[] name)
{
	const CondCallback =
	"if(" ~ name ~ ".isObject())
	{
		auto obj = " ~ name ~ ".toGCObject();
		callback(&obj);
		" ~ name ~ ".mBaseObj = cast(CrocBaseObject*)obj;
	}";
}

// Dynamically dispatch the appropriate visiting method at runtime from a GCObject*.
void visitObj(GCObject* o, void delegate(GCObject**) callback)
{
	// Green objects have no references to other objects.
	if((o.gcflags & GCFlags.ColorMask) == GCFlags.Green)
		return;

	switch((cast(CrocBaseObject*)o).mType)
	{
		case CrocValue.Type.Table:     return visitTable(cast(CrocTable*)o,         callback);
		case CrocValue.Type.Array:     return visitArray(cast(CrocArray*)o,         callback);
		case CrocValue.Type.Function:  return visitFunction(cast(CrocFunction*)o,   callback);
		case CrocValue.Type.Class:     return visitClass(cast(CrocClass*)o,         callback);
		case CrocValue.Type.Instance:  return visitInstance(cast(CrocInstance*)o,   callback);
		case CrocValue.Type.Namespace: return visitNamespace(cast(CrocNamespace*)o, callback);
		case CrocValue.Type.Thread:    return visitThread(cast(CrocThread*)o,       callback);
		case CrocValue.Type.FuncDef:   return visitFuncDef(cast(CrocFuncDef*)o,     callback);
		case CrocValue.Type.Upvalue:   return visitUpvalue(cast(CrocUpval*)o,       callback);
		default: debug Stdout.formatln("{} {:x}", (cast(CrocBaseObject*)o).mType, o.gcflags & GCFlags.ColorMask); assert(false);
	}
}

// Visit a table.
void visitTable(CrocTable* o, void delegate(GCObject**) callback)
{
	// TODO: change the mechanism for weakref determination
// 	bool anyWeakRefs = false;

	foreach(ref key, ref val; o.data)
	{
		mixin(CondCallback!("key"));
		mixin(CondCallback!("val"));

// 		if(!anyWeakRefs && key.type == CrocValue.Type.WeakRef || val.type == CrocValue.Type.WeakRef)
// 			anyWeakRefs = true;
	}

// 	if(anyWeakRefs)
// 	{
// 		o.nextTab = vm.toBeNormalized;
// 		vm.toBeNormalized = o;
// 	}
}

// Visit an array.
void visitArray(CrocArray* o, void delegate(GCObject**) callback)
{
	foreach(ref val; o.toArray())
		mixin(CondCallback!("val"));
}

// Visit a function.
void visitFunction(CrocFunction* o, void delegate(GCObject**) callback)
{
	callback(cast(GCObject**)&o.environment);

	if(o.name)
		callback(cast(GCObject**)&o.name);

	if(o.isNative)
	{
		foreach(ref uv; o.nativeUpvals())
			mixin(CondCallback!("uv"));
	}
	else
	{
		callback(cast(GCObject**)&o.scriptFunc);

		foreach(ref uv; o.scriptUpvals)
			callback(cast(GCObject**)&uv);
	}
}

// Visit a class.
void visitClass(CrocClass* o, void delegate(GCObject**) callback)
{
	if(o.name)      callback(cast(GCObject**)&o.name);
	if(o.parent)    callback(cast(GCObject**)&o.parent);
	if(o.fields)    callback(cast(GCObject**)&o.fields);
	if(o.allocator) callback(cast(GCObject**)&o.allocator);
	if(o.finalizer) callback(cast(GCObject**)&o.finalizer);
}

// Visit an instance.
void visitInstance(CrocInstance* o, void delegate(GCObject**) callback)
{
	if(o.parent) callback(cast(GCObject**)&o.parent);
	if(o.fields) callback(cast(GCObject**)&o.fields);

	foreach(ref val; o.extraValues())
		mixin(CondCallback!("val"));
}

// Visit a namespace.
void visitNamespace(CrocNamespace* o, void delegate(GCObject**) callback)
{
	foreach(ref key, ref val; o.data)
	{
		callback(cast(GCObject**)&key);
		mixin(CondCallback!("val"));
	}

	if(o.parent) callback(cast(GCObject**)&o.parent);
	callback(cast(GCObject**)&o.name);
}

// Visit a thread.
void visitThread(CrocThread* o, void delegate(GCObject**) callback)
{
	foreach(ref ar; o.actRecs[0 .. o.arIndex])
	{
		if(ar.func)
			callback(cast(GCObject**)&ar.func);

		if(ar.proto)
			callback(cast(GCObject**)&ar.proto);
	}

	foreach(ref val; o.stack[0 .. o.stackIndex])
		mixin(CondCallback!("val"));

	// I guess this can't _hurt_..
	o.stack[o.stackIndex .. $] = CrocValue.nullValue;

	foreach(ref val; o.results[0 .. o.resultIndex])
		mixin(CondCallback!("val"));

	for(auto uv = o.upvalHead; uv !is null; uv = uv.nextuv)
		visitUpvalue(uv, callback);

	if(o.coroFunc)
		callback(cast(GCObject**)&o.coroFunc);

	if(o.hookFunc)
		callback(cast(GCObject**)&o.hookFunc);

	version(CrocExtendedCoro)
	{
		if(o.coroFiber)
			callback(cast(GCObject**)&o.coroFiber);
	}
}

// Visit an upvalue.
void visitUpvalue(CrocUpval* o, void delegate(GCObject**) callback)
{
	mixin(CondCallback!("o.value"));
}

// Visit a function definition.
void visitFuncDef(CrocFuncDef* o, void delegate(GCObject**) callback)
{
	if(o.locFile)
		callback(cast(GCObject**)&o.locFile);

	if(o.name)
		callback(cast(GCObject**)&o.name);

	foreach(ref f; o.innerFuncs)
		if(f)
			callback(cast(GCObject**)&f);

	foreach(ref val; o.constants)
		mixin(CondCallback!("val"));

	foreach(ref st; o.switchTables)
		foreach(ref key, _; st.offsets)
			mixin(CondCallback!("key"));

	foreach(name; o.upvalNames)
		if(name)
			callback(cast(GCObject**)&name);

	foreach(ref desc; o.locVarDescs)
		if(desc.name)
			callback(cast(GCObject**)&desc.name);

	if(o.environment)
		callback(cast(GCObject**)&o.environment);

	if(o.cachedFunc)
		callback(cast(GCObject**)&o.cachedFunc);
}