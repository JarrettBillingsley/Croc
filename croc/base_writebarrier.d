/******************************************************************************
This contains the write barrier, as well as the visiting functions used to
visit object slots.

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

module croc.base_writebarrier;

import croc.base_alloc;
import croc.types;

debug import tango.io.Stdout;

// ================================================================================================================================================
// Package
// ================================================================================================================================================

package:

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
	"assert(" ~ srcObj ~ ".mType != CrocValue.Type.Array && " ~ srcObj ~ ".mType != CrocValue.Type.Table);\n"
	"if(" ~ srcObj ~ ".gcflags & GCFlags.Unlogged)\n"
	"	writeBarrierSlow(" ~ alloc ~ ", cast(GCObject*)" ~ srcObj ~ ");\n";
}

template containerWriteBarrier(char[] alloc, char[] srcObj)
{
	const char[] containerWriteBarrier =
	"if(" ~ srcObj ~ ".gcflags & GCFlags.Unlogged) {\n"
	"	" ~ alloc ~ ".modBuffer.add(" ~ alloc ~ ", cast(GCObject*)" ~ srcObj ~ ");\n"
	"	" ~ srcObj ~ ".gcflags &= ~GCFlags.Unlogged;\n"
	"}";
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
// Visiting

// For visiting CrocValues. Visits it only if it's an object.
template ValueCallback(char[] name)
{
	const ValueCallback = "if(" ~ name ~ ".isGCObject()) callback(" ~ name ~ ".toGCObject());";
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
void visitObj(bool isModifyPhase = false)(GCObject* o, void delegate(GCObject*) callback)
{
	// Green objects have no references to other objects.
	if((o.gcflags & GCFlags.ColorMask) == GCFlags.Green)
		return;

	switch((cast(CrocBaseObject*)o).mType)
	{
		case CrocValue.Type.Table:     return visitTable(cast(CrocTable*)o,         callback, isModifyPhase);
		case CrocValue.Type.Array:     return visitArray(cast(CrocArray*)o,         callback, isModifyPhase);
		case CrocValue.Type.Function:  return visitFunction(cast(CrocFunction*)o,   callback);
		case CrocValue.Type.Class:     return visitClass(cast(CrocClass*)o,         callback, isModifyPhase);
		case CrocValue.Type.Instance:  return visitInstance(cast(CrocInstance*)o,   callback, isModifyPhase);
		case CrocValue.Type.Namespace: return visitNamespace(cast(CrocNamespace*)o, callback, isModifyPhase);
		case CrocValue.Type.Thread:    return visitThread(cast(CrocThread*)o,       callback, false);
		case CrocValue.Type.FuncDef:   return visitFuncDef(cast(CrocFuncDef*)o,     callback);
		case CrocValue.Type.Upvalue:   return visitUpvalue(cast(CrocUpval*)o,       callback);
		default: debug Stdout.formatln("{} {:b} {}", (cast(CrocBaseObject*)o).mType, o.gcflags & GCFlags.ColorMask, o.refCount).flush; assert(false);
	}
}

// Visit a table.
void visitTable(CrocTable* o, void delegate(GCObject*) callback, bool isModifyPhase)
{
	if(isModifyPhase)
	{
		foreach(ref key, ref val; &o.data.modifiedSlots)
		{
			mixin(ValueCallback!("key"));
			mixin(ValueCallback!("val"));
		}
	}
	else
	{
		foreach(ref key, ref val; o.data)
		{
			mixin(ValueCallback!("key"));
			mixin(ValueCallback!("val"));
		}
	}
}

// Visit an array.
void visitArray(CrocArray* o, void delegate(GCObject*) callback, bool isModifyPhase)
{
	if(isModifyPhase)
	{
		foreach(ref slot; o.toArray())
		{
			if(!slot.modified)
				continue;

			mixin(ValueCallback!("slot.value"));
			slot.modified = false;
		}
	}
	else
	{
		foreach(ref slot; o.toArray())
			mixin(ValueCallback!("slot.value"));
	}
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
void visitClass(CrocClass* o, void delegate(GCObject*) callback, bool isModifyPhase)
{
	if(isModifyPhase)
	{
		if(o.visitedOnce == false)
		{
			o.visitedOnce = true;
			mixin(CondCallback!("o.name"));
			mixin(CondCallback!("o.parent"));
		}

		foreach(ref key, ref val; &o.fields.modifiedSlots)
		{
			mixin(CondCallback!("key"));
			mixin(ValueCallback!("val.value"));
		}

		foreach(ref key, ref val; &o.methods.modifiedSlots)
		{
			mixin(CondCallback!("key"));
			mixin(ValueCallback!("val.value"));
		}
	}
	else
	{
		mixin(CondCallback!("o.name"));
		mixin(CondCallback!("o.parent"));

		foreach(ref key, ref val; o.fields)
		{
			mixin(CondCallback!("key"));
			mixin(ValueCallback!("val.value"));
		}

		foreach(ref key, ref val; o.methods)
		{
			mixin(CondCallback!("key"));
			mixin(ValueCallback!("val.value"));
		}
	}

	mixin(CondCallback!("o.finalizer"));
}

// Visit an instance.
void visitInstance(CrocInstance* o, void delegate(GCObject*) callback, bool isModifyPhase)
{
	if(isModifyPhase)
	{
		if(o.visitedOnce == false)
		{
			o.visitedOnce = true;
			mixin(CondCallback!("o.parent"));
		}

		foreach(ref key, ref val; &o.fields.modifiedSlots)
		{
			mixin(CondCallback!("key"));
			mixin(ValueCallback!("val.value"));
		}
	}
	else
	{
		mixin(CondCallback!("o.parent"));

		foreach(ref key, ref val; o.fields)
		{
			mixin(CondCallback!("key"));
			mixin(ValueCallback!("val.value"));
		}
	}
}

// Visit a namespace.
void visitNamespace(CrocNamespace* o, void delegate(GCObject*) callback, bool isModifyPhase)
{
	if(isModifyPhase)
	{
		// These two slots are only set once, when the namespace is first created, and are never touched again, so we only have to visit them once
		if(o.visitedOnce == false)
		{
			o.visitedOnce = true;
			mixin(CondCallback!("o.parent"));
			mixin(CondCallback!("o.name"));
		}

		foreach(ref key, ref val; &o.data.modifiedSlots)
		{
			mixin(CondCallback!("key"));
			mixin(ValueCallback!("val"));
		}
	}
	else
	{
		mixin(CondCallback!("o.parent"));
		mixin(CondCallback!("o.name"));

		foreach(ref key, ref val; o.data)
		{
			callback(cast(GCObject*)key);
			mixin(ValueCallback!("val"));
		}
	}
}

// Visit a thread.
void visitThread(CrocThread* o, void delegate(GCObject*) callback, bool isRoots)
{
	if(isRoots)
	{
		foreach(ref ar; o.actRecs[0 .. o.arIndex])
		{
			mixin(CondCallback!("ar.func"));
			mixin(CondCallback!("ar.proto"));
		}

		foreach(i, ref val; o.stack[0 .. o.stackIndex])
			mixin(ValueCallback!("val"));

		// I guess this can't _hurt_..
		o.stack[o.stackIndex .. $] = CrocValue.nullValue;

		foreach(ref val; o.results[0 .. o.resultIndex])
			mixin(ValueCallback!("val"));

		for(auto puv = &o.upvalHead; *puv !is null; puv = &(*puv).nextuv)
			callback(cast(GCObject*)*puv);
	}
	else
	{
		mixin(CondCallback!("o.coroFunc"));
		mixin(CondCallback!("o.hookFunc"));
	}
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