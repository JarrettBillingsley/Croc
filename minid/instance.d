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

module minid.instance;

import tango.math.Math;

import minid.alloc;
import minid.classobj;
import minid.namespace;
import minid.string;
import minid.types;

struct instance
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	package MDInstance* create(ref Allocator alloc, MDClass* parent, uword numValues = 0, uword extraBytes = 0)
	{
		auto i = alloc.allocate!(MDInstance)(InstanceSize(numValues, extraBytes));

		i.parent = parent;
		i.parent.hasInstances = true;
		i.numValues = numValues;
		i.extraBytes = extraBytes;
		i.extraValues()[] = MDValue.nullValue;

		return i;
	}

	package void free(ref Allocator alloc, MDInstance* i)
	{
		alloc.free(i, InstanceSize(i.numValues, i.extraBytes));
	}

	package MDValue* getField(MDInstance* i, MDString* name)
	{
		MDValue dummy;
		return getField(i, name, dummy);
	}

	package MDValue* getField(MDInstance* i, MDString* name, out MDValue owner)
	{
		if(i.fields !is null)
		{
			if(auto ret = namespace.get(i.fields, name))
			{
				owner = i;
				return ret;
			}
		}

		MDClass* dummy;
		auto ret = classobj.getField(i.parent, name, dummy);

		if(dummy !is null)
			owner = dummy;

		return ret;
	}

	package void setField(ref Allocator alloc, MDInstance* i, MDString* name, MDValue* value)
	{
		if(i.fields is null)
			i.fields = namespace.create(alloc, i.parent.name);

		namespace.set(alloc, i.fields, name, value);
	}

	package bool derivesFrom(MDInstance* i, MDClass* c)
	{
		for(auto o = i.parent; o !is null; o = o.parent)
			if(o is c)
				return true;

		return false;
	}

	package MDNamespace* fieldsOf(ref Allocator alloc, MDInstance* i)
	{
		if(i.fields is null)
			i.fields = namespace.create(alloc, i.parent.name);

		return i.fields;
	}

	package bool next(MDInstance* i, ref uword idx, ref MDString** key, ref MDValue* val)
	{
		if(i.fields is null)
			return false;

		return i.fields.data.next(idx, key, val);
	}
	
	package uword InstanceSize(uword numValues, uword extraBytes)
	{
		return MDInstance.sizeof + (numValues * MDValue.sizeof) + extraBytes;
	}
}