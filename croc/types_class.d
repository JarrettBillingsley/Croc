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
import croc.types;
import croc.types_namespace;
import croc.types_string;

struct classobj
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	package CrocClass* create(ref Allocator alloc, CrocString* name, CrocClass* parent)
	{
		auto c = alloc.allocate!(CrocClass)();
		c.name = name;
		c.parent = parent;

		if(parent)
		{
			c.allocator = parent.allocator;
			c.finalizer = parent.finalizer;
			c.fields = namespace.create(alloc, name, parent.fields);
		}
		else
			c.fields = namespace.create(alloc, name);
			
		c.hasInstances = false;

		return c;
	}

	package void free(ref Allocator alloc, CrocClass* c)
	{
		alloc.free(c);
	}
	
	package CrocValue* getField(CrocClass* c, CrocString* name)
	{
		CrocClass* dummy = void;
		return getField(c, name, dummy);
	}

	package CrocValue* getField(CrocClass* c, CrocString* name, out CrocClass* owner)
	{
		for(auto obj = c; obj !is null; obj = obj.parent)
		{
			if(auto ret = namespace.get(obj.fields, name))
			{
				owner = obj;
				return ret;
			}
		}

		return null;
	}

	package void setField(ref Allocator alloc, CrocClass* c, CrocString* name, CrocValue* value)
	{
		namespace.set(alloc, c.fields, name, value);
	}

	package CrocNamespace* fieldsOf(CrocClass* c)
	{
		return c.fields;
	}

	package bool next(CrocClass* c, ref uword idx, ref CrocString** key, ref CrocValue* val)
	{
		return c.fields.data.next(idx, key, val);
	}
}