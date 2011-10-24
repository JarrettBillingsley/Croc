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

debug import tango.io.Stdout;
debug = PHASES;

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

void dumpMem(void* p, uword len)
{
	foreach(b; (cast(ubyte*)p)[0 .. len])
		Stdout.format("{:x2} ", b);
	Stdout.newline.flush;
}

void gcCycle(CrocVM* vm)
{
	debug(PHASES) Stdout.formatln("======================= BEGIN ===============================").flush;
	Stdout.formatln("Nursery pointers: {} .. {} .. {}", vm.alloc.nurseryStart, vm.alloc.nurseryPtr, vm.alloc.nurseryEnd);
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
	debug(PHASES) Stdout.formatln("ROOTS").flush;

	visitRoots(vm, (GCObject** obj)
	{
		if((*obj).gcflags & GCFlags.Forwarded)
			*obj = (*obj).forwardPointer;
		else if(((*obj).gcflags & GCFlags.InRC) == 0)
			*obj = copyOutOfNursery(vm, *obj);
			
// 		if((cast(CrocBaseObject*)*obj).mType == CrocValue.Type.Namespace)
// 		{
// 			auto ns = cast(CrocNamespace*)*obj;
// 			Stdout.formatln("Parent of {} ({}) after root visit: {}", ns.name.toString(), *obj, ns.parent);
// 			Stdout("dump: "); dumpMem(ns, ns.memSize);
// 		}

		newRoots.add(vm.alloc, *obj);
	});

	// PROCESS MODIFIED BUFFER. Go through the modified buffer, unlogging each. For each object pointed to by an object, if it's in the nursery, copy it
	// 	out (or just forward if that's already happened). Increment all the reference counts (spurious increments to RC space objects will be undone
	// 	by the queued decrements created during the mutation phase by the write barrier).
	debug(PHASES) Stdout.formatln("MODBUFFER").flush;
	while(!modBuffer.isEmpty())
	{
		auto obj = modBuffer.remove();
		assert((obj.gcflags & GCFlags.ColorMask) != GCFlags.Green);

		Stdout.formatln("{} {}", obj, CrocValue.typeStrings[(cast(CrocBaseObject*)obj).mType]).flush;

		obj.gcflags |= GCFlags.Unlogged;

// 		if(obj is cast(GCObject*)vm.globals)
// 			Stdout.formatln("visiting globalssssss").flush;

		visitObj(obj, (GCObject** slot)
		{
			if((*slot).gcflags & GCFlags.Forwarded)
				*slot = (*slot).forwardPointer;
			else if(((*slot).gcflags & GCFlags.InRC) == 0)
				*slot = copyOutOfNursery(vm, *slot);
				
// 			Stdout.formatln("Object moved to {}", *slot);

			rcIncrement(*slot);

// 			if((cast(CrocBaseObject*)*slot).mType == CrocValue.Type.String)
				Stdout.formatln("Visited {} through {}, rc is now {}", *slot, obj, (*slot).refCount).flush;
		});
	}

	// PROCESS OLD ROOT BUFFER. Move all objects from the old root buffer into the decrement buffer.
	debug(PHASES) Stdout.formatln("OLDROOTS").flush;
	decBuffer.append(vm.alloc, *oldRoots);
	oldRoots.reset();

	// PROCESS NEW ROOT BUFFER. Go through the new root buffer, incrementing their RCs, and put them all in the old root buffer.
	debug(PHASES) Stdout.formatln("NEWROOTS").flush;
	foreach(obj; *newRoots)
	{
		assert(!(obj >= vm.alloc.nurseryStart && obj < vm.alloc.nurseryEnd));
		rcIncrement(obj);

// 		if((cast(CrocBaseObject*)obj).mType == CrocValue.Type.String)
			Stdout.formatln("Incremented {}, rc is now {}", obj, obj.refCount).flush;
	}

	// heehee sneaky
	vm.oldRootIdx = 1 - vm.oldRootIdx;
	}

	// PROCESS DECREMENT BUFFER. Go through the decrement buffer, decrementing their RCs. If an RC hits 0, if it's not finalizable, queue decrements for
	// 	any RC objects it points to, and free it. If it is finalizable, put it on the finalize list. If an RC is nonzero after being decremented, mark
	// 	it as a possible cycle root as follows: if its color is not purple, color it purple, and if it's not already buffered, mark it buffered and
	// 	put it in the possible cycle buffer.
	
	debug(PHASES) Stdout.formatln("DECBUFFER").flush;

	while(!decBuffer.isEmpty())
	{
		auto obj = decBuffer.remove();

// 		if((cast(CrocBaseObject*)obj).mType == CrocValue.Type.String)
			Stdout.formatln("About to decrement {}, rc is {}", obj, obj.refCount).flush;

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

// 				Stdout.write("Normal ");
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
	
	debug(PHASES) Stdout.formatln("NURSERY").flush;

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
	debug(PHASES) Stdout.formatln("CYCLES").flush;
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

// 	string.dumpTable(vm);
	debug(PHASES) Stdout.formatln("======================= END =================================").flush;
}

// WRITE BARRIER: At mutation time, any time we update a slot in an unlogged object (only objects in RC space can be unlogged; we ignore nursery
// objects), we log it by putting it in the modified buffer and queueing decrements for any RC objects it points to before modification. Then set
// its state to logged to prevent it from being added again, and finally, store the new object in the slot.
//
// During collection, it will then increment all the slots after modification; thus the previous values will be decremented and the current values
// incremented. If a slot wasn't changed, it will be a no-op (inc followed by dec). If a slot was changed, the old object will be decremented, and
// the new will be incremented. This is the implementation of coalescing.

// void writeBarrier(ref Allocator alloc, GCObject* srcObj, GCObject** srcSlot, GCObject* newVal)
// {
// 	if(*srcSlot is newVal)
// 		return;
// 
// 	if(srcObj.gcflags & GCFlags.Unlogged)
// 		writeBarrierSlow(alloc, srcObj);
//
// 	*srcSlot = newVal;
// }

// template writeBarrier(char[] alloc, char[] srcObj, char[] srcSlot, char[] newVal)
// {
// 	const char[] writeBarrier =
// 	"if(" ~ srcSlot ~ " !is newVal)\n"
// 	"{\n"
// 	"	if(" ~ srcObj ~ ".gcflags & GCFlags.Unlogged)\n"
// 	"		writeBarrierSlow(" ~ alloc ~ ", " ~ srcObj ~ ");\n"
//
// 	"	" ~ srcSlot ~ " = " ~ newVal ~ ";\n"
// 	"}";
// }

template writeBarrier(char[] alloc, char[] srcObj)
{
	const char[] writeBarrier =
	"if(" ~ srcObj ~ ".gcflags & GCFlags.Unlogged)\n"
	"	writeBarrierSlow(" ~ alloc ~ ", cast(GCObject*)" ~ srcObj ~ ");\n";
}

void writeBarrierSlow(ref Allocator alloc, GCObject* srcObj)
{
	alloc.modBuffer.add(alloc, srcObj);

// 	if((cast(CrocBaseObject*)srcObj).mType == CrocValue.Type.Namespace)
// 	{
// 		auto ns = cast(CrocNamespace*)srcObj;
// 		Stdout.formatln("Parent of {} ({}) before write barrier: {}", ns.name.toString(), srcObj, ns.parent);
// 	}

	visitObj(srcObj, (GCObject** slot)
	{
		if((*slot).gcflags & GCFlags.InRC)
		{
			if((cast(CrocBaseObject*)*slot).mType == CrocValue.Type.String)
				Stdout.formatln("adding string {} to dec buffer", *slot).flush;
			alloc.decBuffer.add(alloc, *slot);
		}
	});
	
// 	if((cast(CrocBaseObject*)srcObj).mType == CrocValue.Type.Namespace)
// 	{
// 		auto ns = cast(CrocNamespace*)srcObj;
// 		Stdout.formatln("Parent of {} ({}) after write barrier: {}", ns.name.toString(), srcObj, ns.parent);
// 	}

	srcObj.gcflags &= ~GCFlags.Unlogged;
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

	if((ret.gcflags & GCFlags.ColorMask) != GCFlags.Green)
		vm.alloc.modBuffer.add(vm.alloc, ret);
// 	vm.alloc.decBuffer.add(vm.alloc, ret);

	obj.gcflags = GCFlags.Forwarded;
	obj.forwardPointer = ret;

	switch((cast(CrocBaseObject*)obj).mType)
	{
		case CrocValue.Type.String:
			auto o = cast(CrocString*)ret;
			// TODO: string returning problem
			vm.stringTab.remove(o.toString());
			*vm.stringTab.insert(vm.alloc, o.toString()) = o;
			break;

		case CrocValue.Type.WeakRef:   auto o = cast(CrocWeakRef*)ret; *vm.weakRefTab.lookup(o.obj) = o; break;
		case CrocValue.Type.NativeObj: auto o = cast(CrocNativeObj*)ret; vm.nativeObjs[o.obj] = o; break;
		case CrocValue.Type.Upvalue:
			auto old = cast(CrocUpval*)obj;

			if(old.value is &old.closedValue)
			{
				auto n = cast(CrocUpval*)ret;
				n.value = &n.closedValue;
			}
			break;

		default: break;
	}

	Stdout.formatln("object at {} is now at {} and its refcount is {}", obj, ret, ret.refCount).flush;

	return ret;
}

// Free an object.
void free(CrocVM* vm, GCObject* o)
{
// 	if((cast(CrocBaseObject*)o).mType == CrocValue.Type.String)
// 		Stdout.formatln("FREE: {} at {}: \"{}\"", CrocValue.typeStrings[(cast(CrocBaseObject*)o).mType], o, (cast(CrocString*)o).toString()).flush;
// 	else
		Stdout.formatln("FREE: {} at {}", CrocValue.typeStrings[(cast(CrocBaseObject*)o).mType], o).flush;

	finalizeBuiltin(vm, o);
	vm.alloc.free(o);
}

void finalizeBuiltin(CrocVM* vm, GCObject* o)
{
	if(auto r = vm.weakRefTab.lookup(cast(CrocBaseObject*)o))
	{
		(*r).obj = null;
		vm.weakRefTab.remove(cast(CrocBaseObject*)o);
	}

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

		default: debug Stdout.formatln("{}", (cast(CrocBaseObject*)o).mType).flush; assert(false);
	}
}

void rcIncrement(GCObject* obj)
{
	assert((obj.gcflags & GCFlags.InRC) && (obj.gcflags & GCFlags.Forwarded) == 0);

	obj.refCount++;

	if((obj.gcflags & GCFlags.ColorMask) != GCFlags.Green)
		obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Black;
}

// ================================================================================================================================================
// Cycle collection

void collectCycles(CrocVM* vm)
{
	auto cycleRoots = &vm.cycleRoots;

	// Mark
	for(auto it = cycleRoots.iterator(); it.hasNext(); )
	{
		auto obj = it.next();
		assert((obj.gcflags & GCFlags.Forwarded) == 0);

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
	assert((obj.gcflags & GCFlags.Forwarded) == 0);
	assert((obj.gcflags & GCFlags.ColorMask) != GCFlags.Green);
	assert((cast(CrocBaseObject*)obj).mType != CrocValue.Type.String);
// 	if((obj.gcflags & GCFlags.ColorMask) == GCFlags.Green)
// 		return;

	if((obj.gcflags & GCFlags.ColorMask) != GCFlags.Grey)
	{
		obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Grey;

		visitObj(obj, (GCObject** slot)
		{
			if(((*slot).gcflags & GCFlags.ColorMask) != GCFlags.Green)
			{
				(*slot).refCount--;

				if((*slot).refCount == -1)
				{
					Stdout.formatln("oh no, it's {}", (*slot));
					assert(false);
				}

				markGray(*slot);
			}
		});
	}
}

void cycleScan(GCObject* obj)
{
	assert((obj.gcflags & GCFlags.Forwarded) == 0);

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
	assert((obj.gcflags & GCFlags.Forwarded) == 0);
	assert((obj.gcflags & GCFlags.ColorMask) != GCFlags.Green);
	assert((cast(CrocBaseObject*)obj).mType != CrocValue.Type.String);
// 	if((obj.gcflags & GCFlags.ColorMask) == GCFlags.Green)
// 		return;

	obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Black;

	visitObj(obj, (GCObject** slot)
	{
		auto color = (*slot).gcflags & GCFlags.ColorMask;

		if(color != GCFlags.Green)
		{
			(*slot).refCount++;

			if(color != GCFlags.Black)
				cycleScanBlack(*slot);
		}
	});
}

void collectCycleWhite(CrocVM* vm, GCObject* obj)
{
	assert((obj.gcflags & GCFlags.Forwarded) == 0);

	auto color = obj.gcflags & GCFlags.ColorMask;

	if(color == GCFlags.Green)
	{
		// It better not be in the roots. that'd be impossible.
		assert((obj.gcflags & GCFlags.CycleLogged) == 0);
		if(--obj.refCount == 0)
		{
// 			Stdout.write("Cycle (green) ");
			free(vm, obj);
		}
	}
	else if(color == GCFlags.White && (obj.gcflags & GCFlags.CycleLogged) == 0)
	{
		if((obj.gcflags & GCFlags.Finalizable) && (obj.gcflags & GCFlags.Finalized) == 0)
			throw new /* CrocFatal */Exception("Unfinalized finalizable object in cycle!");

		obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Black;

		visitObj(obj, (GCObject** slot)
		{
			collectCycleWhite(vm, *slot);
		});

// 		Stdout.write("Cycle (white) ");
		free(vm, obj);
	}
}

// ================================================================================================================================================
// Visiting

// For visiting CrocValues. Visits it only if it's an object.
template ValueCallback(char[] name)
{
	const ValueCallback =
	"if(" ~ name ~ ".isObject())
	{
		auto obj = " ~ name ~ ".toGCObject();
		callback(&obj);
		" ~ name ~ ".mBaseObj = cast(CrocBaseObject*)obj;
	}";
}

// For visiting pointers. Visits it only if it's non-null.
template CondCallback(char[] name)
{
	const CondCallback =
	"if(" ~ name ~ " !is null) callback(cast(GCObject**)&" ~ name ~ ");";
}

// Visit the roots of this VM.
void visitRoots(CrocVM* vm, void delegate(GCObject**) callback)
{
// 	Stdout.formatln("globals unlogged? {}", vm.globals.gcflags & GCFlags.Unlogged).flush;
	callback(cast(GCObject**)&vm.globals);
// 	visitNamespace(vm.globals, callback);
	callback(cast(GCObject**)&vm.mainThread);
	// TODO: visit ALL the threads!
	visitThread(vm.mainThread, callback);

	foreach(ref mt; vm.metaTabs)
		mixin(CondCallback!("mt"));

	foreach(ref s; vm.metaStrings)
		callback(cast(GCObject**)&s);

	// TODO: change vm.exception to a CrocInstance*
	if(vm.isThrowing)
		mixin(ValueCallback!("vm.exception"));

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

// Dynamically dispatch the appropriate visiting method at runtime from a GCObject*.
void visitObj(GCObject* o, void delegate(GCObject**) callback)
{
// 	Stdout.formatln("hmmm {} {:b} {} {}", (cast(CrocBaseObject*)o).mType, o.gcflags, ((cast(CrocBaseObject*)o).mType == CrocValue.Type.Function) ? (cast(CrocFunction*)o).name.toString() : "", o.refCount).flush;

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
		default: debug Stdout.formatln("{} {:b} {}", (cast(CrocBaseObject*)o).mType, o.gcflags & GCFlags.ColorMask, o.refCount).flush; assert(false);
	}
}

// Visit a table.
void visitTable(CrocTable* o, void delegate(GCObject**) callback)
{
	// TODO: change the mechanism for weakref determination

	foreach(ref key, ref val; o.data)
	{
		mixin(ValueCallback!("key"));
		mixin(ValueCallback!("val"));
	}
}

// Visit an array.
void visitArray(CrocArray* o, void delegate(GCObject**) callback)
{
	foreach(ref val; o.toArray())
		mixin(ValueCallback!("val"));
}

// Visit a function.
void visitFunction(CrocFunction* o, void delegate(GCObject**) callback)
{
	mixin(CondCallback!("o.environment"));

// 	if(o.name !is null)
// 		Stdout.formatln("function {}'s ({}) name is: {} {:b} at {}", o, o.isNative ? null : o.scriptFunc, o.name.toString, o.name.gcflags, o.name).flush;
	mixin(CondCallback!("o.name"));

	if(o.isNative)
	{
		foreach(ref uv; o.nativeUpvals())
			mixin(ValueCallback!("uv"));
	}
	else
	{
		mixin(CondCallback!("o.scriptFunc"));

		foreach(ref uv; o.scriptUpvals())
			mixin(CondCallback!("uv"));
	}
}

// Visit a class.
void visitClass(CrocClass* o, void delegate(GCObject**) callback)
{
	mixin(CondCallback!("o.name"));
	mixin(CondCallback!("o.parent"));
	mixin(CondCallback!("o.fields"));
	mixin(CondCallback!("o.allocator"));
	mixin(CondCallback!("o.finalizer"));
}

// Visit an instance.
void visitInstance(CrocInstance* o, void delegate(GCObject**) callback)
{
	mixin(CondCallback!("o.parent"));
	mixin(CondCallback!("o.fields"));

	foreach(ref val; o.extraValues())
		mixin(ValueCallback!("val"));
}

// Visit a namespace.
void visitNamespace(CrocNamespace* o, void delegate(GCObject**) callback)
{
// 	Stdout.format("before visit {}\ndump: ", o); dumpMem(o, o.memSize);

	foreach(ref key, ref val; o.data)
	{
// 		Stdout.format("visiting {}\ndump: ", key.toString()); dumpMem(o, o.memSize);
		callback(cast(GCObject**)&key);
// 		Stdout.format("done visiting {}\ndump: ", key.toString()); dumpMem(o, o.memSize);

// 		if(val.isObject())
// 			Stdout.formatln("value's addr is {}", val.toGCObject());
		mixin(ValueCallback!("val"));
// 		Stdout.format("done visiting {}'s value\ndump: ", key.toString()); dumpMem(o, o.memSize);
	}

// 	Stdout("after visit\ndump: "); dumpMem(o, o.memSize);

	assert(o.mType is CrocValue.Type.Namespace);

// 	Stdout.formatln("HERFA {}", o.parent).flush;
// 	Stdout("dump: "); dumpMem(o, o.memSize);
	mixin(CondCallback!("o.parent"));
// 	Stdout.formatln("DERFA {}", o.parent).flush;
	mixin(CondCallback!("o.name"));
}

// Visit a thread.
void visitThread(CrocThread* o, void delegate(GCObject**) callback)
{
	foreach(ref ar; o.actRecs[0 .. o.arIndex])
	{
		mixin(CondCallback!("ar.func"));
		mixin(CondCallback!("ar.proto"));
	}

	foreach(i, ref val; o.stack[0 .. o.stackIndex])
	{
		Stdout.formatln("Stack {}: {}", i, val).flush;
		mixin(ValueCallback!("val"));
	}
	
	Stdout.formatln("DONE WITH STACK").flush;

	// I guess this can't _hurt_..
	
	o.stack[o.stackIndex .. $] = CrocValue.nullValue;

	foreach(ref val; o.results[0 .. o.resultIndex])
		mixin(ValueCallback!("val"));

	for(auto puv = &o.upvalHead; *puv !is null; puv = &(*puv).nextuv)
		callback(cast(GCObject**)puv);

	mixin(CondCallback!("o.coroFunc"));
	mixin(CondCallback!("o.hookFunc"));

	version(CrocExtendedCoro)
		mixin(CondCallback!("o.coroFiber"));
}

// Visit an upvalue.
void visitUpvalue(CrocUpval* o, void delegate(GCObject**) callback)
{
	mixin(ValueCallback!("o.value"));
}

// Visit a function definition.
void visitFuncDef(CrocFuncDef* o, void delegate(GCObject**) callback)
{
	mixin(CondCallback!("o.locFile"));
	mixin(CondCallback!("o.name"));

	foreach(ref f; o.innerFuncs)
		mixin(CondCallback!("f"));

	foreach(ref val; o.constants)
		mixin(ValueCallback!("val"));

	foreach(ref st; o.switchTables)
		foreach(ref key, _; st.offsets)
			mixin(ValueCallback!("key"));

	foreach(name; o.upvalNames)
		mixin(CondCallback!("name"));

	foreach(ref desc; o.locVarDescs)
		mixin(CondCallback!("desc.name"));

	mixin(CondCallback!("o.environment"));
	mixin(CondCallback!("o.cachedFunc"));
}