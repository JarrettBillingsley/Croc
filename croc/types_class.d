/******************************************************************************
This module contains internal implementation of the class object.

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

module croc.types_class;

import croc.base_alloc;
import croc.base_hash;
import croc.base_writebarrier;
import croc.types;
import croc.types_string;

struct classobj
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

package:

	CrocClass* create(ref Allocator alloc, CrocString* name, CrocClass* parent)
	{
		auto c = alloc.allocate!(CrocClass)();
		c.name = name;
		c.parent = parent;

		if(parent)
		{
			freeze(parent);
			c.finalizer = parent.finalizer;

			if(parent.fields.length)
			{
				mixin(containerWriteBarrier!("alloc", "c"));

				c.fields.prealloc(alloc, parent.fields.capacity());
				assert(c.fields.capacity() == parent.fields.capacity());
				parent.fields.dupInto(c.fields);

				foreach(ref node; &c.fields.allNodes)
					node.modified |= KeyModified | (node.value.value.isGCObject() ? ValModified : 0);
			}

			if(parent.methods.length)
			{
				mixin(containerWriteBarrier!("alloc", "c"));

				c.methods.prealloc(alloc, parent.methods.capacity());
				assert(c.methods.capacity() == parent.methods.capacity());
				parent.methods.dupInto(c.methods);

				foreach(ref node; &c.methods.allNodes)
					node.modified |= KeyModified | (node.value.value.isGCObject() ? ValModified : 0);
			}
		}

		return c;
	}

	void free(ref Allocator alloc, CrocClass* c)
	{
		c.fields.clear(alloc);
		c.methods.clear(alloc);
		alloc.free(c);
	}

	void freeze(CrocClass* c)
	{
		c.isFrozen = true;
	}

	void setFinalizer(ref Allocator alloc, CrocClass* c, CrocFunction* f)
	{
		assert(!c.isFrozen);

		if(c.finalizer !is f)
		{
			mixin(writeBarrier!("alloc", "c"));
			c.finalizer = f;
		}
	}

	bool derivesFrom(CrocClass* c, CrocClass* other)
	{
		for(auto o = c.parent; o !is null; o = o.parent)
			if(o is other)
				return true;

		return false;
	}

	// =================================================================================================================
	// Common stuff

	typeof(CrocClass.fields).Node* commonGetField(char[] member)(CrocClass* c, CrocString* name)
	{
		return mixin("c." ~ member).lookupNode(name);
	}

	void commonSetField(ref Allocator alloc, CrocClass* c, typeof(CrocClass.fields).Node* slot, CrocValue* value)
	{
		if(slot.value.value != *value)
		{
			mixin(removeValueRef!("alloc", "slot"));
			slot.value.value = *value;
			slot.value.proto = c;

			if(value.isGCObject())
			{
				mixin(containerWriteBarrier!("alloc", "c"));
				slot.modified |= ValModified;
			}
			else
				slot.modified &= ~ValModified;
		}
	}

	bool commonAddField(char[] member)(ref Allocator alloc, CrocClass* c, CrocString* name, CrocValue* value, bool isPublic)
	{
		assert(!c.isFrozen);

		if(auto val = c.fields.lookup(name))
		{
			if(val.proto is c)
				return false;
		}
		else if(auto val = c.methods.lookup(name))
		{
			if(val.proto is c)
				return false;
		}

		mixin(containerWriteBarrier!("alloc", "c"));
		auto slot = mixin("c." ~ member).insertNode(alloc, name);
		slot.value.value = *value;
		slot.value.proto = c;
		slot.value.isPublic = isPublic;
		slot.modified |= KeyModified | (value.isGCObject() ? ValModified : 0);

		return true;
	}

	bool commonRemoveField(char[] member)(ref Allocator alloc, CrocClass* c, CrocString* name)
	{
		if(auto slot = mixin("c." ~ member).lookupNode(name))
		{
			mixin(removeKeyRef!("alloc", "slot"));
			mixin(removeValueRef!("alloc", "slot"));
			(mixin("c." ~ member)).remove(name);
			return true;
		}
		else
			return false;
	}

	bool commonNextField(char[] member)(CrocClass* c, ref uword idx, ref CrocString** key, ref FieldValue* val)
	{
		return mixin("c." ~ member).next(idx, key, val);
	}

	// =================================================================================================================
	// Blerf

	alias commonGetField!("fields") getField;
	alias commonGetField!("methods") getMethod;

	alias commonSetField setField;
	alias setField setMethod;

	alias commonAddField!("fields") addField;
	alias commonAddField!("methods") addMethod;

	bool removeFieldOrMethod(ref Allocator alloc, CrocClass* c, CrocString* name)
	{
		assert(!c.isFrozen);

		return
			commonRemoveField!("fields")(alloc, c, name) ||
			commonRemoveField!("methods")(alloc, c, name);
	}

	alias commonNextField!("fields") nextField;
	alias commonNextField!("methods") nextMethod;

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
		"if(!(" ~ slot  ~ ".modified & ValModified) && " ~ slot  ~ ".value.value.isGCObject()) "
			~ alloc ~ ".decBuffer.add(" ~ alloc ~ ", " ~ slot  ~ ".value.value.toGCObject());";
	}
}