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
import croc.base_gc;
import croc.types;

struct table
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	// Create a new table object with `size` slots preallocated in it.
	package CrocTable* create(ref Allocator alloc, uword size = 0)
	{
		auto t = alloc.allocate!(CrocTable);
		mixin(writeBarrier!("alloc", "t"));
		t.data.prealloc(alloc, size);
		return t;
	}

	// Finalize a table object.
	package void finalize(ref Allocator alloc, CrocTable* t)
	{
		t.data.clear(alloc);
	}

	// Get a pointer to the value of a key-value pair, or null if it doesn't exist.
	package CrocValue* get_x(CrocTable* t, CrocValue key)
	{
		return t.data.lookup(key);
	}

	// Insert a key-value pair (or update one if it already exists).
	package void set(ref Allocator alloc, CrocTable* t, ref CrocValue key, ref CrocValue value)
	{
		assert(value.type != CrocValue.Type.Null);
		auto slot = t.data.insert(alloc, key);

		if(*slot != value)
		{
			mixin(writeBarrier!("alloc", "t"));
			*slot = value;
		}
	}
	
	// Insert a key-value pair (or update one if it already exists).
	package void set(ref Allocator alloc, CrocTable* t, CrocValue* slot, ref CrocValue value)
	{
		assert(value.type != CrocValue.Type.Null);

		if(*slot != value)
		{
			mixin(writeBarrier!("alloc", "t"));
			*slot = value;
		}
	}

	// Remove a key-value pair from the table.
	package void remove(ref Allocator alloc, CrocTable* t, ref CrocValue key)
	{
		mixin(writeBarrier!("alloc", "t"));
		t.data.remove(key);
	}

	// remove all key-value pairs from the table.
	package void clear(ref Allocator alloc, CrocTable* t)
	{
		if(t.data.length > 0)
			mixin(writeBarrier!("alloc", "t"));

		t.data.clear(alloc);
	}

	// Returns `true` if the key exists in the table.
	package bool contains(CrocTable* t, ref CrocValue key)
	{
		return t.data.lookup(key) !is null;
	}

	// Get the number of key-value pairs in the table.
	package uword length(CrocTable* t)
	{
		return t.data.length();
	}

	// Removes any key-value pairs that have null weak references.
	package void normalize(ref Allocator alloc, CrocTable* t)
	{
		uword i = 0;
		CrocValue* k = void;
		CrocValue* v = void;
		bool removedAny = false;

		while(t.data.next(i, k, v))
		{
			if((k.type == CrocValue.Type.WeakRef && k.mWeakRef.obj is null) ||
				(v.type == CrocValue.Type.WeakRef && v.mWeakRef.obj is null))
			{
				if(!removedAny)
				{
					removedAny = true;
					mixin(writeBarrier!("alloc", "t"));
				}

				t.data.remove(*k);
				i--;
			}
		}
	}

	package bool next(CrocTable* t, ref size_t idx, ref CrocValue* key, ref CrocValue* val)
	{
		return t.data.next(idx, key, val);
	}
}