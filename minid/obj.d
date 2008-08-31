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

module minid.obj;

import minid.alloc;
import minid.namespace;
import minid.string;
import minid.types;

struct obj
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	package MDObject* create(ref Allocator alloc, MDString* name, MDObject* proto, uword numValues = 0, uword extraBytes = 0)
	{
		auto o = alloc.allocate!(MDObject)(ObjectSize(numValues, extraBytes));
		o.name = name;
		o.proto = proto;
		o.numValues = numValues;
		o.extraBytes = extraBytes;
		
		if(o.proto)
			o.finalizer = o.proto.finalizer;
			
		return o;
	}

	package void free(ref Allocator alloc, MDObject* o)
	{
		alloc.free(o, ObjectSize(o.numValues, o.extraBytes));
	}
	
	package MDValue* getField(MDObject* o, MDString* name)
	{
		MDObject* dummy = void;
		return getField(o, name, dummy);
	}

	package MDValue* getField(MDObject* o, MDString* name, out MDObject* proto)
	{
		for(auto obj = o; obj !is null; obj = obj.proto)
		{
			if(obj.fields !is null)
			{
				if(auto ret = namespace.get(obj.fields, name))
				{
					proto = obj;
					return ret;
				}
			}
		}

		return null;
	}
	
	package void setField(MDVM* vm, MDObject* o, MDString* name, MDValue* value)
	{
		if(o.fields is null)
			o.fields = namespace.create(vm.alloc, string.create(vm, ""));
			
		namespace.set(vm.alloc, o.fields, name, value);
	}
	
	package bool derivesFrom(MDObject* o, MDObject* p)
	{
		for( ; o !is null; o = o.proto)
			if(o is p)
				return true;

		return false;
	}
	
	package MDNamespace* fieldsOf(MDObject* o)
	{
		return o.fields;
	}
	
	package bool next(MDObject* o, ref uword idx, ref MDString** key, ref MDValue* val)
	{
		if(o.fields is null)
			return false;

		return o.fields.data.next(idx, key, val);
	}

	// ================================================================================================================================================
	// Private
	// ================================================================================================================================================

	private uword ObjectSize(uword numValues, uword extraBytes)
	{
		return MDObject.sizeof + (numValues * MDValue.sizeof) + extraBytes;
	}
}