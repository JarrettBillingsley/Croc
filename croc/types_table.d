/******************************************************************************
This module contains internal implementation of the table object.

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

module croc.types_table;

import croc.base_alloc;
import croc.base_writebarrier;
import croc.base_hash;
import croc.types;

struct table
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

package:

	// Create a new table object with `size` slots preallocated in it.
	CrocTable* create(ref Allocator alloc, uword size = 0)
	{
		auto t = alloc.allocate!(CrocTable);
		t.data.prealloc(alloc, size);
		return t;
	}

	// Duplicate an existing table efficiently.
	CrocTable* dup(ref Allocator alloc, CrocTable* src)
	{
		auto t = alloc.allocate!(CrocTable);
		t.data.prealloc(alloc, src.data.capacity());

		assert(t.data.capacity() == src.data.capacity());
		src.data.dupInto(t.data);

		// At this point we've basically done the equivalent of inserting every key-value pair from src into t,
		// so we have to do run through the new table and do the "insert" write barrier stuff.

		foreach(ref node; &t.data.allNodes)
		{
			if(node.key.isGCObject() || node.value.isGCObject())
			{
				mixin(containerWriteBarrier!("alloc", "t"));
				node.modified |= (node.key.isGCObject() ? KeyModified : 0) | (node.value.isGCObject() ? ValModified : 0);
			}
		}

		return t;
	}

	// Free a table object.
	void free(ref Allocator alloc, CrocTable* t)
	{
		t.data.clear(alloc);
		alloc.free(t);
	}

	// Get a pointer to the value of a key-value pair, or null if it doesn't exist.
	CrocValue* get(CrocTable* t, CrocValue key)
	{
		return t.data.lookup(key);
	}

	void idxa(ref Allocator alloc, CrocTable* t, ref CrocValue key, ref CrocValue val)
	{
		auto node = t.data.lookupNode(key);

		if(node !is null)
		{
			if(val.type == CrocValue.Type.Null)
			{
				// Remove
				mixin(removeKeyRef!("alloc", "node"));
				mixin(removeValueRef!("alloc", "node"));
				t.data.remove(key);
			}
			else if(node.value != val)
			{
				// Update
				mixin(removeValueRef!("alloc", "node"));
				node.value = val;

				if(val.isGCObject())
				{
					mixin(containerWriteBarrier!("alloc", "t"));
					node.modified |= ValModified;
				}
				else
					node.modified &= ~ValModified;
			}
		}
		else if(val.type != CrocValue.Type.Null)
		{
			// Insert
			node = t.data.insertNode(alloc, key);
			node.value = val;

			if(key.isGCObject() || val.isGCObject())
			{
				mixin(containerWriteBarrier!("alloc", "t"));
				node.modified |= (key.isGCObject() ? KeyModified : 0) | (val.isGCObject() ? ValModified : 0);
			}
		}

		// otherwise, do nothing (val is null and key doesn't exist)
	}

	// remove all key-value pairs from the table.
	void clear(ref Allocator alloc, CrocTable* t)
	{
		foreach(ref node; &t.data.allNodes)
		{
			mixin(removeKeyRef!("alloc", "node"));
			mixin(removeValueRef!("alloc", "node"));
		}

		t.data.clear(alloc);
	}

	// Returns `true` if the key exists in the table.
	bool contains(CrocTable* t, ref CrocValue key)
	{
		return t.data.lookup(key) !is null;
	}

	// Get the number of key-value pairs in the table.
	uword length(CrocTable* t)
	{
		return t.data.length();
	}

	bool next(CrocTable* t, ref size_t idx, ref CrocValue* key, ref CrocValue* val)
	{
		return t.data.next(idx, key, val);
	}

	template removeKeyRef(char[] alloc, char[] slot)
	{
		const char[] removeKeyRef =
		"if(!(" ~ slot  ~ ".modified & KeyModified) && " ~ slot  ~ ".key.isGCObject()) " ~ alloc ~ ".decBuffer.add(" ~ alloc ~ ", " ~ slot  ~ ".key.toGCObject());";
	}

	template removeValueRef(char[] alloc, char[] slot)
	{
		const char[] removeValueRef =
		"if(!(" ~ slot  ~ ".modified & ValModified) && " ~ slot  ~ ".value.isGCObject()) " ~ alloc ~ ".decBuffer.add(" ~ alloc ~ ", " ~ slot  ~ ".value.toGCObject());";
	}
}