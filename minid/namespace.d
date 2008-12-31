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

module minid.namespace;

import minid.alloc;
import minid.types;

struct namespace
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	// Create a new namespace object.
	package MDNamespace* create(ref Allocator alloc, MDString* name, MDNamespace* parent = null)
	{
		assert(name !is null);

		auto ns = alloc.allocate!(MDNamespace);
		ns.parent = parent;
		ns.name = name;
		return ns;
	}

	// Free a namespace object.
	package void free(ref Allocator alloc, MDNamespace* ns)
	{
		ns.data.clear(alloc);
		alloc.free(ns);
	}

	// Get a pointer to the value of a key-value pair, or null if it doesn't exist.
	package MDValue* get(MDNamespace* ns, MDString* key)
	{
		return ns.data.lookup(key);
	}
	
	// Sets a key-value pair.
	package void set(ref Allocator alloc, MDNamespace* ns, MDString* key, MDValue* value)
	{
		*ns.data.insert(alloc, key) = *value;
	}

	// Remove a key-value pair from the namespace.
	package void remove(MDNamespace* ns, MDString* key)
	{
		ns.data.remove(key);
	}
	
	// Clears all items from the namespace.
	package void clear(ref Allocator alloc, MDNamespace* ns)
	{
		ns.data.clear(alloc);
	}
	
	// Returns `true` if the key exists in the table.
	package bool contains(MDNamespace* ns, MDString* key)
	{
		return ns.data.lookup(key) !is null;
	}
	
	package bool next(MDNamespace* ns, ref uword idx, ref MDString** key, ref MDValue* val)
	{
		return ns.data.next(idx, key, val);
	}
	
	package uword length(MDNamespace* ns)
	{
		return ns.data.length();
	}
}