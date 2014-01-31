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

		if(parent)
		{
			assert(parent.isFrozen);
			assert(parent.finalizer is null);

			if(parent.fields.length)
			{
				// mixin(containerWriteBarrier!("alloc", "c"));

				c.fields.prealloc(alloc, parent.fields.capacity());
				assert(c.fields.capacity() == parent.fields.capacity());
				parent.fields.dupInto(c.fields);

				foreach(ref node; &c.fields.allNodes)
					node.modified |= KeyModified | (node.value.isGCObject() ? ValModified : 0);
			}

			if(parent.hiddenFields.length)
			{
				// mixin(containerWriteBarrier!("alloc", "c"));

				c.hiddenFields.prealloc(alloc, parent.hiddenFields.capacity());
				assert(c.hiddenFields.capacity() == parent.hiddenFields.capacity());
				parent.hiddenFields.dupInto(c.hiddenFields);

				foreach(ref node; &c.hiddenFields.allNodes)
					node.modified |= KeyModified | (node.value.isGCObject() ? ValModified : 0);
			}

			if(parent.methods.length)
			{
				// mixin(containerWriteBarrier!("alloc", "c"));

				c.methods.prealloc(alloc, parent.methods.capacity());
				assert(c.methods.capacity() == parent.methods.capacity());
				parent.methods.dupInto(c.methods);

				foreach(ref node; &c.methods.allNodes)
					node.modified |= KeyModified | (node.value.isGCObject() ? ValModified : 0);
			}
		}

		return c;
	}

	void free(ref Allocator alloc, CrocClass* c)
	{
		c.hiddenFields.clear(alloc);
		c.fields.clear(alloc);
		c.methods.clear(alloc);
		alloc.free(c);
	}

	void freeze(CrocClass* c)
	{
		c.isFrozen = true;
	}

	// =================================================================================================================
	// Common stuff

	typeof(CrocClass.fields).Node* getMember(char[] member)(CrocClass* c, CrocString* name)
	{
		return mixin("c." ~ member).lookupNode(name);
	}

	void setMember(ref Allocator alloc, CrocClass* c, typeof(CrocClass.fields).Node* slot, CrocValue* value)
	{
		if(slot.value != *value)
		{
			mixin(removeValueRef!("alloc", "slot"));
			slot.value = *value;

			if(value.isGCObject())
			{
				mixin(containerWriteBarrier!("alloc", "c"));
				slot.modified |= ValModified;
			}
			else
				slot.modified &= ~ValModified;
		}
	}

	bool addMember(char[] member)(ref Allocator alloc, CrocClass* c, CrocString* name, CrocValue* value)
	{
		assert(!c.isFrozen);

		static if(member == "fields")
		{
			if(c.methods.lookup(name))
				return false;
			else if(auto slot = c.fields.lookupNode(name))
			{
				setMember(alloc, c, slot, value);
				return true;
			}
		}
		else static if(member == "methods")
		{
			if(c.fields.lookup(name))
				return false;
			else if(auto slot = c.methods.lookupNode(name))
			{
				setMember(alloc, c, slot, value);
				return true;
			}
		}
		else static if(member == "hiddenFields")
		{
			if(auto slot = c.hiddenFields.lookupNode(name))
			{
				setMember(alloc, c, slot, value);
				return true;
			}
		}

		mixin(containerWriteBarrier!("alloc", "c"));
		auto slot = mixin("c." ~ member).insertNode(alloc, name);
		slot.value = *value;
		slot.modified |= KeyModified | (value.isGCObject() ? ValModified : 0);

		return true;
	}

	bool commonRemoveMember(char[] member)(ref Allocator alloc, CrocClass* c, CrocString* name)
	{
		assert(!c.isFrozen);

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

	bool nextMember(char[] member)(CrocClass* c, ref uword idx, ref CrocString** key, ref CrocValue* val)
	{
		return mixin("c." ~ member).next(idx, key, val);
	}

	// =================================================================================================================
	// Blerf

	alias getMember!("fields") getField;
	alias getMember!("methods") getMethod;
	alias getMember!("hiddenFields") getHiddenField;

	alias setMember setField;
	alias setMember setMethod;
	alias setMember setHiddenField;

	alias addMember!("fields") addField;
	alias addMember!("methods") addMethod;
	alias addMember!("hiddenFields") addHiddenField;

	bool removeMember(ref Allocator alloc, CrocClass* c, CrocString* name)
	{
		return
			commonRemoveMember!("fields")(alloc, c, name) ||
			commonRemoveMember!("methods")(alloc, c, name);
	}

	alias commonRemoveMember!("hiddenFields") removeHiddenField;

	alias nextMember!("fields") nextField;
	alias nextMember!("methods") nextMethod;
	alias nextMember!("hiddenFields") nextHiddenField;

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