/******************************************************************************
This module contains internal implementation of the instance object.

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

module croc.types_instance;

import tango.math.Math;

import croc.base_alloc;
import croc.base_hash;
import croc.base_writebarrier;
import croc.types;
import croc.types_class;
import croc.types_namespace;
import croc.types_string;

struct instance
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

package:

	CrocInstance* create(ref Allocator alloc, CrocClass* parent)
	{
		assert(parent.isFrozen);

		CrocInstance* i = createPartial(alloc, InstanceSize(parent), parent.finalizer !is null);
		finishCreate(i, parent);

		return i;
	}

	CrocInstance* createPartial(ref Allocator alloc, uword size, bool finalizable)
	{
		assert(size >= CrocInstance.sizeof);

		if(finalizable)
			return alloc.allocateFinalizable!(CrocInstance)(size);
		else
			return alloc.allocate!(CrocInstance)(size);
	}

	bool finishCreate(CrocInstance* i, CrocClass* parent)
	{
		assert(parent.isFrozen);

		if(i.memSize != InstanceSize(parent))
			return false;

		i.parent = parent;

		if(parent.fields.length > 0)
		{
			auto instNodes = (cast(typeof(i.fields).Node*)(i + 1))[0 .. parent.fields.capacity()];
			parent.fields.dupInto(i.fields, instNodes);

			foreach(ref node; &i.fields.allNodes)
				node.modified |= KeyModified | (node.value.isGCObject() ? ValModified : 0);
		}

		return true;
	}

	typeof(CrocInstance.fields).Node* getField(CrocInstance* i, CrocString* name)
	{
		return i.fields.lookupNode(name);
	}

	typeof(CrocClass.fields).Node* getMethod(CrocInstance* i, CrocString* name)
	{
		return classobj.getMethod(i.parent, name);
	}

	void setField(ref Allocator alloc, CrocInstance* i, typeof(CrocInstance.fields).Node* slot, CrocValue* value)
	{
		if(slot.value != *value)
		{
			mixin(removeValueRef!("alloc", "slot"));
			slot.value = *value;

			if(value.isGCObject())
			{
				mixin(containerWriteBarrier!("alloc", "i"));
				slot.modified |= ValModified;
			}
			else
				slot.modified &= ~ValModified;
		}
	}

	bool nextField(CrocInstance* i, ref uword idx, ref CrocString** key, ref CrocValue* val)
	{
		return i.fields.next(idx, key, val);
	}

	bool derivesFrom(CrocInstance* i, CrocClass* c)
	{
		for(auto o = i.parent; o !is null; o = o.parent)
			if(o is c)
				return true;

		return false;
	}

	uword InstanceSize(CrocClass* parent)
	{
		return CrocInstance.sizeof + parent.fields.dataSize();
	}

	// =================================================================================================================
	// Helpers

	template removeKeyRef(char[] alloc, char[] slot)
	{
		const char[] removeKeyRef =
		"if(!(" ~ slot  ~ ".modified & KeyModified)) "
			~ alloc ~ ".decBuffer.add(" ~ alloc ~ ", cast(GCObject*)" ~ slot  ~ ".key);";
	}

	template removeValueRef(char[] alloc, char[] slot)
	{
		const char[] removeValueRef =
		"if(!(" ~ slot  ~ ".modified & ValModified) && " ~ slot  ~ ".value.isGCObject()) "
			~ alloc ~ ".decBuffer.add(" ~ alloc ~ ", " ~ slot  ~ ".value.toGCObject());";
	}
}