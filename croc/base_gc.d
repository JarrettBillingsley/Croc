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
// debug = PHASES;
// debug = INCDEC;
// debug = FREES;

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

enum GCCycleType
{
	Normal,
	BeginCleanup,
	ContinueCleanup,
	FinishCleanup
}

void gcCycle(CrocVM* vm, GCCycleType cycleType)
{
	debug(PHASES) static counter = 0;
	debug(PHASES) Stdout.formatln("======================= BEGIN {} =============================== {}", ++counter, cast(uint)cycleType).flush;
	debug(PHASES) Stdout.formatln("Nursery: {} bytes allocated out of {}", vm.alloc.nurseryBytes, vm.alloc.nurseryLimit);
	assert(vm.inGCCycle);
	assert(vm.alloc.gcDisabled == 0);

	// Upon entry:
	// 	modified buffer contains all objects that were logged between collections.
	// 	decrement buffer can have stuff in it.
	// 	old root buffer contains last collection's new roots.
	// 	new root buffer is empty.
	// 	possible cycle buffer is empty ONLY IF WE RAN A CYCLE COLLECTION LAST TIME HERPDERP
	// 	finalize buffer is empty.

	auto modBuffer = &vm.alloc.modBuffer;
	auto decBuffer = &vm.alloc.decBuffer;
	auto cycleRoots = &vm.cycleRoots;
	auto toFinalize = &vm.toFinalize;

	{ // block to control scope of old/newRoots
	auto oldRoots = &vm.roots[vm.oldRootIdx];
	auto newRoots = &vm.roots[1 - vm.oldRootIdx];

	assert(newRoots.isEmpty());
// 	assert(cycleRoots.isEmpty());
	assert(toFinalize.isEmpty());

	// ROOT PHASE. Go through roots, including stacks, and for each object reference, if it's in the nursery, copy it out and leave a forwarding address.
	// Regardless of whether it's a nursery object or not, put it in the new root buffer.
	debug(PHASES) Stdout.formatln("ROOTS").flush;

	switch(cycleType)
	{
		case GCCycleType.Normal:
			visitRoots(vm, (GCObject* obj)
			{
				if((obj.gcflags & GCFlags.InRC) == 0)
					nurseryToRC(vm, obj);

				newRoots.add(vm.alloc, obj);
			});
			break;

		case GCCycleType.BeginCleanup:
			namespace.clear(vm.alloc, vm.globals);
			goto case GCCycleType.Normal;

		case GCCycleType.ContinueCleanup:
			namespace.clear(vm.alloc, vm.registry);
			vm.refTab.clear(vm.alloc);
			goto case GCCycleType.Normal;

		case GCCycleType.FinishCleanup:
			break;

		default: assert(false);
	}

	// PROCESS MODIFIED BUFFER. Go through the modified buffer, unlogging each. For each object pointed to by an object, if it's in the nursery, copy it
	// 	out (or just forward if that's already happened). Increment all the reference counts (spurious increments to RC space objects will be undone
	// 	by the queued decrements created during the mutation phase by the write barrier).
	debug(PHASES) Stdout.formatln("MODBUFFER").flush;
	while(!modBuffer.isEmpty())
	{
		auto obj = modBuffer.remove();
		assert((obj.gcflags & GCFlags.ColorMask) != GCFlags.Green);

		debug(INCDEC) Stdout.formatln("let's look at {} {}", CrocValue.typeStrings[(cast(CrocBaseObject*)obj).mType], obj).flush;

		obj.gcflags |= GCFlags.Unlogged;

		visitObj(obj, (GCObject* slot)
		{
			if((slot.gcflags & GCFlags.InRC) == 0)
				nurseryToRC(vm, slot);

			debug(INCDEC) Stdout.formatln("Visited {} through {}, rc will be {}", slot, obj, slot.refCount + 1).flush;

			rcIncrement(slot);
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
		assert(obj.gcflags & GCFlags.InRC);
		rcIncrement(obj);

		debug(INCDEC) Stdout.formatln("Incremented {}, rc is now {}", obj, obj.refCount).flush;
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

		debug(INCDEC) Stdout.formatln("About to decrement {}, rc will be {}", obj, obj.refCount - 1).flush;

		if(--obj.refCount == 0)
		{
			// Ref count hit 0. It's garbage.

			if((obj.gcflags & GCFlags.Finalizable) && (obj.gcflags & GCFlags.Finalized) == 0)
			{
				obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Black;
				toFinalize.add(vm.alloc, cast(CrocInstance*)obj);
			}
			else
			{
				visitObj(obj, (GCObject* slot)
				{
					decBuffer.add(vm.alloc, slot);
				});

				if(obj.gcflags & GCFlags.CycleLogged)
					obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Black;
				else if(!(obj.gcflags & GCFlags.JustMoved)) // If it just moved out of the nursery, we'll let the nursery phase sweep it up
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

	foreach(obj; vm.alloc.nursery)
	{
		if(obj.gcflags & GCFlags.InRC && obj.refCount > 0)
		{
			obj.gcflags &= ~GCFlags.JustMoved;
			continue;
		}

		assert((obj.gcflags & GCFlags.Finalizable) == 0);
		assert((obj.gcflags & GCFlags.CycleLogged) == 0);
		free(vm, obj);
	}

	vm.alloc.clearNurserySpace();

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
		assert(vm.toFree.isEmpty());

	debug(PHASES) Stdout.formatln("======================= END {} =================================", counter).flush;
}

// WRITE BARRIER: At mutation time, any time we update a slot in an unlogged object (only objects in RC space can be unlogged; we ignore nursery
// objects), we log it by putting it in the modified buffer and queueing decrements for any RC objects it points to before modification. Then set
// its state to logged to prevent it from being added again, and finally, store the new object in the slot.
//
// During collection, it will then increment all the slots after modification; thus the previous values will be decremented and the current values
// incremented. If a slot wasn't changed, it will be a no-op (inc followed by dec). If a slot was changed, the old object will be decremented, and
// the new will be incremented. This is the implementation of coalescing.

template writeBarrier(char[] alloc, char[] srcObj)
{
	const char[] writeBarrier =
	"if(" ~ srcObj ~ ".gcflags & GCFlags.Unlogged)\n"
	"	writeBarrierSlow(" ~ alloc ~ ", cast(GCObject*)" ~ srcObj ~ ");\n";
}

void writeBarrierSlow(ref Allocator alloc, GCObject* srcObj)
{
	alloc.modBuffer.add(alloc, srcObj);

	visitObj(srcObj, (GCObject* slot)
	{
		if(slot.gcflags & GCFlags.InRC)
			alloc.decBuffer.add(alloc, slot);
	});

	srcObj.gcflags &= ~GCFlags.Unlogged;
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

void nurseryToRC(CrocVM* vm, GCObject* obj)
{
	assert((obj.gcflags & GCFlags.InRC) == 0);

	vm.alloc.makeRC(obj);

	obj.gcflags |= GCFlags.InRC | GCFlags.Unlogged;
	obj.refCount = 0;

	if((obj.gcflags & GCFlags.ColorMask) != GCFlags.Green)
		vm.alloc.modBuffer.add(vm.alloc, obj);

	debug(INCDEC) Stdout.formatln("object at {} is now in RC and its refcount is {}", obj, obj.refCount).flush;
}

// Free an object.
void free(CrocVM* vm, GCObject* o)
{
	debug(FREES) Stdout.formatln("FREE: {} at {}", CrocValue.typeStrings[(cast(CrocBaseObject*)o).mType], o).flush;

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
		case CrocValue.Type.Memblock:  memblock.free(vm.alloc, cast(CrocMemblock*)o); return;
		case CrocValue.Type.Namespace: namespace.free(vm.alloc, cast(CrocNamespace*)o); return;
		case CrocValue.Type.Thread:    thread.free(cast(CrocThread*)o); return;
		case CrocValue.Type.NativeObj: nativeobj.free(vm, cast(CrocNativeObj*)o); return;
		case CrocValue.Type.WeakRef:   weakref.free(vm, cast(CrocWeakRef*)o); return;
		case CrocValue.Type.FuncDef:   funcdef.free(vm.alloc, cast(CrocFuncDef*)o); return;
		case CrocValue.Type.Function:
		case CrocValue.Type.Class:
		case CrocValue.Type.Instance:
		case CrocValue.Type.Upvalue:   vm.alloc.free(o); return;

		default: debug Stdout.formatln("{}", (cast(CrocBaseObject*)o).mType).flush; assert(false);
	}
}

void rcIncrement(GCObject* obj)
{
	assert(obj.gcflags & GCFlags.InRC);

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
		assert(obj.gcflags & GCFlags.InRC);

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
		cycleScan(vm, obj);

	// Collect
	while(!cycleRoots.isEmpty())
	{
		auto obj = cycleRoots.remove();
		obj.gcflags &= ~GCFlags.CycleLogged;
		collectCycleWhite(vm, obj);
	}

	// Free
	while(!vm.toFree.isEmpty())
	{
		auto obj = vm.toFree.remove();
		free(vm, obj);
	}
}

void markGray(GCObject* obj)
{
	assert(obj.gcflags & GCFlags.InRC);
	assert((obj.gcflags & GCFlags.ColorMask) != GCFlags.Green);
	assert((cast(CrocBaseObject*)obj).mType != CrocValue.Type.String);

	if((obj.gcflags & GCFlags.ColorMask) != GCFlags.Grey)
	{
		obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Grey;

		visitObj(obj, (GCObject* slot)
		{
			if((slot.gcflags & GCFlags.ColorMask) != GCFlags.Green)
			{
				slot.refCount--;
				assert(slot.refCount != -1);
				markGray(slot);
			}
		});
	}
}

void cycleScan(CrocVM* vm, GCObject* obj)
{
	assert(obj.gcflags & GCFlags.InRC);

	if((obj.gcflags & GCFlags.ColorMask) == GCFlags.Grey)
	{
		if(obj.refCount > 0)
			cycleScanBlack(obj);
		else if((obj.gcflags & GCFlags.Finalizable) && (obj.gcflags & GCFlags.Finalized) == 0)
		{
			vm.toFinalize.add(vm.alloc, cast(CrocInstance*)obj);
			cycleScanBlack(obj);
		}
		else
		{
			obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.White;

			visitObj(obj, (GCObject* slot)
			{
				cycleScan(vm, slot);
			});
		}
	}
}

void cycleScanBlack(GCObject* obj)
{
	assert(obj.gcflags & GCFlags.InRC);
	assert((obj.gcflags & GCFlags.ColorMask) != GCFlags.Green);
	assert((cast(CrocBaseObject*)obj).mType != CrocValue.Type.String);

	obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Black;

	visitObj(obj, (GCObject* slot)
	{
		auto color = slot.gcflags & GCFlags.ColorMask;

		if(color != GCFlags.Green)
		{
			slot.refCount++;

			if(color != GCFlags.Black)
				cycleScanBlack(slot);
		}
	});
}

void collectCycleWhite(CrocVM* vm, GCObject* obj)
{
	assert(obj.gcflags & GCFlags.InRC);

	auto color = obj.gcflags & GCFlags.ColorMask;

	if(color == GCFlags.Green)
	{
		// It better not be in the roots. that'd be impossible.
		assert((obj.gcflags & GCFlags.CycleLogged) == 0);
		if(--obj.refCount == 0)
			free(vm, obj);
	}
	else if(color == GCFlags.White && !(obj.gcflags & GCFlags.CycleLogged))
	{
		if((obj.gcflags & GCFlags.Finalizable) && (obj.gcflags & GCFlags.Finalized) == 0)
			throw new CrocFatalException("Unfinalized finalizable object (instance of " ~ (cast(CrocInstance*)obj).parent.name.toString() ~ ") in cycle!");

		obj.gcflags = (obj.gcflags & ~GCFlags.ColorMask) | GCFlags.Black;

		visitObj(obj, (GCObject* slot)
		{
			collectCycleWhite(vm, slot);
		});

		vm.toFree.add(vm.alloc, obj);
	}
}

// ================================================================================================================================================
// Visiting

import tango.io.stream.TextFile;
import croc.base_hash;

void dumpObjGraph(CrocVM* vm, char[] filename)
{
	scope f = new TextFileOutput(filename);
	Hash!(GCObject*, bool) visited;

	f.write(`digraph d
{
	fontname = Helvetica
	fontsize = 10
	label = "roots"
	rankdir = "TB"
	compound = true
	aspect = 1
	node [fontname = "Helvetica-Bold", fontsize = 12]
	Roots [style = filled, fillcolor = grey]
	`);

	void writeNodeName(GCObject* o)
	{
		auto obj = cast(CrocBaseObject*)o;

		f.write("\"");

		switch(obj.mType)
		{
			case CrocValue.Type.String:    f.format("string ({})", o); break;
			case CrocValue.Type.Table:     f.format("table ({})", o); break;
			case CrocValue.Type.Array:     f.format("array ({})", o); break;
			case CrocValue.Type.Memblock:  f.format("memblock ({})", o); break;
			case CrocValue.Type.Function:  f.format("function {} ({})", (cast(CrocFunction*)obj).name.toString(), o); break;
			case CrocValue.Type.Class:     f.format("class {} ({})", (cast(CrocClass*)obj).name.toString(), o); break;
			case CrocValue.Type.Instance:  f.format("instance of {} ({})", (cast(CrocInstance*)obj).parent.name.toString(), o); break;
			case CrocValue.Type.Namespace: f.format("namespace {} ({})", (cast(CrocNamespace*)obj).name.toString(), o); break;
			case CrocValue.Type.Thread:    f.format("thread ({})", o); break;
			case CrocValue.Type.NativeObj: f.format("nativeobj ({})", o); break;
			case CrocValue.Type.WeakRef:   f.format("weakref ({})", o); break;
			case CrocValue.Type.FuncDef:   f.format("funcdef {} ({})", (cast(CrocFuncDef*)obj).name.toString(), o); break;
			case CrocValue.Type.Upvalue:   f.format("upvalue ({})", o); break;
			default:                       f.format("??? {} ({})", obj.mType, o); break;
		}

		f.format(" {}\"", obj.refCount);
	}

	void visitIt(GCObject* obj)
	{
		if(visited.lookup(obj))
			return;

		*visited.insert(vm.alloc, obj) = true;

		writeNodeName(obj);

		char[] color;

		switch(obj.gcflags & GCFlags.ColorMask)
		{
			case GCFlags.Black: color = "gray30"; break;
			case GCFlags.White: color = "white"; break;
			case GCFlags.Grey: color = "gray76"; break;
			case GCFlags.Purple: color = "purple"; break;
			case GCFlags.Green: color = "green"; break;
			default: assert(false);
		}

		f.formatln(" [style = filled, fillcolor = {}]", color);

		switch((cast(CrocBaseObject*)obj).mType)
		{
			case CrocValue.Type.String, CrocValue.Type.Memblock, CrocValue.Type.NativeObj, CrocValue.Type.WeakRef, CrocValue.Type.Null: return;
			default: break;
		}

		visitObj(obj, (GCObject* slot)
		{
			visitIt(slot);

			writeNodeName(obj);
			f.write(" -> ");
			writeNodeName(slot);
			f.newline;
		});
	}

	visitRoots(vm, (GCObject* obj)
	{
		if((cast(CrocBaseObject*)obj).mType == CrocValue.Type.String || (cast(CrocBaseObject*)obj).mType == CrocValue.Type.Null)
			return;

		f.write("Roots -> ");
		writeNodeName(obj);
		f.newline;
		visitIt(obj);
	});

	f.write("}");

	visited.clear(vm.alloc);
	f.flush();
	f.close();
}

// For visiting CrocValues. Visits it only if it's an object.
template ValueCallback(char[] name)
{
	const ValueCallback = "if(" ~ name ~ ".isObject()) callback(" ~ name ~ ".toGCObject());";
}

// For visiting pointers. Visits it only if it's non-null.
template CondCallback(char[] name)
{
	const CondCallback = "if(" ~ name ~ " !is null) callback(cast(GCObject*)" ~ name ~ ");";
}

// Visit the roots of this VM.
void visitRoots(CrocVM* vm, void delegate(GCObject*) callback)
{
	callback(cast(GCObject*)vm.globals);
	callback(cast(GCObject*)vm.mainThread);

	// We visit all the threads, but the threads themselves (except the main thread, visited above) are not roots. allThreads is basically a table of weak refs
	foreach(thread, _; vm.allThreads)
		visitThread(thread, callback, true);

	foreach(ref mt; vm.metaTabs)
		mixin(CondCallback!("mt"));

	foreach(ref s; vm.metaStrings)
		callback(cast(GCObject*)s);

	if(vm.isThrowing)
		callback(cast(GCObject*)vm.exception);

	callback(cast(GCObject*)vm.registry);

	foreach(ref val; vm.refTab)
		callback(cast(GCObject*)val);

	callback(cast(GCObject*)vm.object);
	callback(cast(GCObject*)vm.throwable);
	callback(cast(GCObject*)vm.location);

	foreach(ref k, ref v; vm.stdExceptions)
	{
		callback(cast(GCObject*)k);
		callback(cast(GCObject*)v);
	}
}

// Dynamically dispatch the appropriate visiting method at runtime from a GCObject*.
void visitObj(GCObject* o, void delegate(GCObject*) callback)
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
		case CrocValue.Type.Thread:    return visitThread(cast(CrocThread*)o,       callback, false);
		case CrocValue.Type.FuncDef:   return visitFuncDef(cast(CrocFuncDef*)o,     callback);
		case CrocValue.Type.Upvalue:   return visitUpvalue(cast(CrocUpval*)o,       callback);
		default: debug Stdout.formatln("{} {:b} {}", (cast(CrocBaseObject*)o).mType, o.gcflags & GCFlags.ColorMask, o.refCount).flush; assert(false);
	}
}

// Visit a table.
void visitTable(CrocTable* o, void delegate(GCObject*) callback)
{
	// TODO: change the mechanism for weakref determination

	foreach(ref key, ref val; o.data)
	{
		mixin(ValueCallback!("key"));
		mixin(ValueCallback!("val"));
	}
}

// Visit an array.
void visitArray(CrocArray* o, void delegate(GCObject*) callback)
{
	foreach(ref val; o.toArray())
		mixin(ValueCallback!("val"));
}

// Visit a function.
void visitFunction(CrocFunction* o, void delegate(GCObject*) callback)
{
	mixin(CondCallback!("o.environment"));
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
void visitClass(CrocClass* o, void delegate(GCObject*) callback)
{
	mixin(CondCallback!("o.name"));
	mixin(CondCallback!("o.parent"));
	mixin(CondCallback!("o.fields"));
	mixin(CondCallback!("o.allocator"));
	mixin(CondCallback!("o.finalizer"));
}

// Visit an instance.
void visitInstance(CrocInstance* o, void delegate(GCObject*) callback)
{
	mixin(CondCallback!("o.parent"));
	mixin(CondCallback!("o.fields"));

	foreach(ref val; o.extraValues())
		mixin(ValueCallback!("val"));
}

// Visit a namespace.
void visitNamespace(CrocNamespace* o, void delegate(GCObject*) callback)
{
	foreach(ref key, ref val; o.data)
	{
		callback(cast(GCObject*)key);
		mixin(ValueCallback!("val"));
	}

	assert(o.mType is CrocValue.Type.Namespace);

	mixin(CondCallback!("o.parent"));
	mixin(CondCallback!("o.name"));
}

// Visit a thread.
void visitThread(CrocThread* o, void delegate(GCObject*) callback, bool isRoots)
{
	foreach(ref ar; o.actRecs[0 .. o.arIndex])
	{
		mixin(CondCallback!("ar.func"));
		mixin(CondCallback!("ar.proto"));
	}

	if(isRoots)
	{
		foreach(i, ref val; o.stack[0 .. o.stackIndex])
			mixin(ValueCallback!("val"));
	}

	// I guess this can't _hurt_..

	o.stack[o.stackIndex .. $] = CrocValue.nullValue;

	foreach(ref val; o.results[0 .. o.resultIndex])
		mixin(ValueCallback!("val"));

	for(auto puv = &o.upvalHead; *puv !is null; puv = &(*puv).nextuv)
		callback(cast(GCObject*)*puv);

	mixin(CondCallback!("o.coroFunc"));
	mixin(CondCallback!("o.hookFunc"));

	version(CrocExtendedCoro)
		mixin(CondCallback!("o.coroFiber"));
}

// Visit an upvalue.
void visitUpvalue(CrocUpval* o, void delegate(GCObject*) callback)
{
	mixin(ValueCallback!("o.value"));
}

// Visit a function definition.
void visitFuncDef(CrocFuncDef* o, void delegate(GCObject*) callback)
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