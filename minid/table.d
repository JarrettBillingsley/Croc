/******************************************************************************
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

module minid.table;

import minid.alloc;
import minid.types;

struct table
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	// Create a new table object with `size` slots preallocated in it.
	package MDTable* create(ref Allocator alloc, uword size = 0)
	{
		auto t = alloc.allocate!(MDTable);
		t.data.prealloc(alloc, size);
		return t;
	}

	// Free a table object.
	package void free(ref Allocator alloc, MDTable* t)
	{
		t.data.clear(alloc);
		alloc.free(t);
	}

	// Get a pointer to the value of a key-value pair, or null if it doesn't exist.
	package MDValue* get(MDTable* t, ref MDValue key)
	{
		return t.data.lookup(key);
	}
	
	// Insert a key-value pair (or update one if it already exists).
	package void set(ref Allocator alloc, MDTable* t, ref MDValue key, ref MDValue value)
	{
		assert(value.type != MDValue.Type.Null);
		*t.data.insert(alloc, key) = value;
	}

	// Remove a key-value pair from the table.
	package void remove(MDTable* t, ref MDValue key)
	{
		t.data.remove(key);
	}
	
	// remove all key-value pairs from the table.
	package void clear(ref Allocator alloc, MDTable* t)
	{
		t.data.clear(alloc);
	}

	// Returns `true` if the key exists in the table.
	package bool contains(MDTable* t, ref MDValue key)
	{
		return t.data.lookup(key) !is null;
	}

	// Get the number of key-value pairs in the table.
	package uword length(MDTable* t)
	{
		return t.data.length();
	}

	// Removes any key-value pairs that have null weak references.
	package void normalize(MDTable* t)
	{
		uword i = 0;
		MDValue* k = void;
		MDValue* v = void;

		while(t.data.next(i, k, v))
		{
			if((k.type == MDValue.Type.WeakRef && k.mWeakRef.obj is null) ||
				(v.type == MDValue.Type.WeakRef && v.mWeakRef.obj is null))
			{
				t.data.remove(*k);
				i--;
			}
		}
	}

	package bool next(MDTable* t, ref size_t idx, ref MDValue* key, ref MDValue* val)
	{
		return t.data.next(idx, key, val);
	}
}