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

module minid.classobj;

import minid.alloc;
import minid.namespace;
import minid.string;
import minid.types;

struct classobj
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	package MDClass* create(ref Allocator alloc, MDString* name, MDClass* parent)
	{
		auto c = alloc.allocate!(MDClass)();
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

		return c;
	}

	package void free(ref Allocator alloc, MDClass* c)
	{
		alloc.free(c);
	}
	
	package MDValue* getField(MDClass* c, MDString* name)
	{
		MDClass* dummy = void;
		return getField(c, name, dummy);
	}

	package MDValue* getField(MDClass* c, MDString* name, out MDClass* owner)
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

	package void setField(ref Allocator alloc, MDClass* c, MDString* name, MDValue* value)
	{
		namespace.set(alloc, c.fields, name, value);
	}

	package MDNamespace* fieldsOf(MDClass* c)
	{
		return c.fields;
	}

	package bool next(MDClass* c, ref uword idx, ref MDString** key, ref MDValue* val)
	{
		return c.fields.data.next(idx, key, val);
	}
}