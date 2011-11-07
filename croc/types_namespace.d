/******************************************************************************
This module contains internal implementation of the namespace object.

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

module croc.types_namespace;

import croc.base_alloc;
import croc.base_gc;
import croc.base_hash;
import croc.types;

struct namespace
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	// Create a new namespace object.
	package CrocNamespace* create(ref Allocator alloc, CrocString* name, CrocNamespace* parent = null)
	{
		assert(name !is null);

		auto ns = alloc.allocate!(CrocNamespace);
		ns.parent = parent;
		ns.name = name;
		return ns;
	}

	// Free a namespace object.
	package void free(ref Allocator alloc, CrocNamespace* ns)
	{
		ns.data.clear(alloc);
		alloc.free(ns);
	}

	// Get a pointer to the value of a key-value pair, or null if it doesn't exist.
	package CrocValue* get(CrocNamespace* ns, CrocString* key)
	{
		return ns.data.lookup(key);
	}

	// Sets a key-value pair.
	package void set(ref Allocator alloc, CrocNamespace* ns, CrocString* key, CrocValue* value)
	{
		if(setIfExists(alloc, ns, key, value))
			return;

		mixin(containerWriteBarrier!("alloc", "ns"));
		auto node = ns.data.insertNode(alloc, key);
		node.value = *value;
		node.modified |= KeyModified | (value.isObject() ? ValModified : 0);
	}

	package bool setIfExists(ref Allocator alloc, CrocNamespace* ns, CrocString* key, CrocValue* value)
	{
		auto node = ns.data.lookupNode(key);

		if(node is null)
			return false;

		if(node.value != *value)
		{
			mixin(removeValueRef!("alloc", "node"));
			node.value = *value;

			if(value.isObject())
			{
				mixin(containerWriteBarrier!("alloc", "ns"));
				node.modified |= ValModified;
			}
			else
				node.modified &= ~ValModified;
		}

		return true;
	}

	// Remove a key-value pair from the namespace.
	package void remove(ref Allocator alloc, CrocNamespace* ns, CrocString* key)
	{
		if(auto node = ns.data.lookupNode(key))
		{
			mixin(removeKeyRef!("alloc", "node"));
			mixin(removeValueRef!("alloc", "node"));
			ns.data.remove(key);
		}
	}

	// Clears all items from the namespace.
	package void clear(ref Allocator alloc, CrocNamespace* ns)
	{
		foreach(ref node; &ns.data.allNodes)
		{
			mixin(removeKeyRef!("alloc", "node"));
			mixin(removeValueRef!("alloc", "node"));
		}

		ns.data.clear(alloc);
	}

	// Returns `true` if the key exists in the table.
	package bool contains(CrocNamespace* ns, CrocString* key)
	{
		return ns.data.lookup(key) !is null;
	}

	package bool next(CrocNamespace* ns, ref uword idx, ref CrocString** key, ref CrocValue* val)
	{
		return ns.data.next(idx, key, val);
	}

	package uword length(CrocNamespace* ns)
	{
		return ns.data.length();
	}

	package template removeKeyRef(char[] alloc, char[] slot)
	{
		const char[] removeKeyRef =
		"if(!(" ~ slot  ~ ".modified & KeyModified)) " ~ alloc ~ ".decBuffer.add(" ~ alloc ~ ", cast(GCObject*)" ~ slot  ~ ".key);";
	}

	package template removeValueRef(char[] alloc, char[] slot)
	{
		const char[] removeValueRef =
		"if(!(" ~ slot  ~ ".modified & ValModified) && " ~ slot  ~ ".value.isObject()) " ~ alloc ~ ".decBuffer.add(" ~ alloc ~ ", " ~ slot  ~ ".value.toGCObject());";
	}

}