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

module croc.types_instance;

import tango.math.Math;

import croc.base_alloc;
import croc.base_gc;
import croc.types;
import croc.types_class;
import croc.types_namespace;
import croc.types_string;

struct instance
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	package CrocInstance* create(CrocVM* vm, CrocClass* parent, uword numValues = 0, uword extraBytes = 0)
	{
		CrocInstance* i;

		if(parent.finalizer)
			i = vm.alloc.allocateFinalizable!(CrocInstance)(InstanceSize(numValues, extraBytes));
		else
			i = vm.alloc.allocate!(CrocInstance)(InstanceSize(numValues, extraBytes));

		mixin(writeBarrier!("vm.alloc", "i"));
		i.parent = parent;
		i.numValues = numValues;
		i.extraBytes = extraBytes;
		i.extraValues()[] = CrocValue.nullValue;

		return i;
	}

	package CrocValue* getField(CrocInstance* i, CrocString* name)
	{
		CrocValue dummy;
		return getField(i, name, dummy);
	}

	package CrocValue* getField(CrocInstance* i, CrocString* name, out CrocValue owner)
	{
		if(i.fields !is null)
		{
			if(auto ret = namespace.get(i.fields, name))
			{
				owner = i;
				return ret;
			}
		}

		CrocClass* dummy;
		auto ret = classobj.getField(i.parent, name, dummy);

		if(dummy !is null)
			owner = dummy;

		return ret;
	}

	package void setField(ref Allocator alloc, CrocInstance* i, CrocString* name, CrocValue* value)
	{
		if(i.fields is null)
		{
			mixin(writeBarrier!("alloc", "i"));
			i.fields = namespace.create(alloc, i.parent.name);
		}

		namespace.set(alloc, i.fields, name, value);
	}

	package void setField(ref Allocator alloc, CrocInstance* i, CrocValue* slot, CrocValue* value)
	{
		// the only way this overload could be called is if the slot already exists in the instance
		assert(i.fields !is null);

		namespace.set(alloc, i.fields, slot, value);
	}
	
	package void setExtraVal(ref Allocator alloc, CrocInstance* i, uword idx, CrocValue* value)
	{
		auto dest = &i.extraValues()[idx];
		
		if(*dest != *value)
		{
			mixin(writeBarrier!("alloc", "i"));
			*dest = *value;
		}
	}

	package bool derivesFrom(CrocInstance* i, CrocClass* c)
	{
		for(auto o = i.parent; o !is null; o = o.parent)
			if(o is c)
				return true;

		return false;
	}

	package CrocNamespace* fieldsOf(ref Allocator alloc, CrocInstance* i)
	{
		if(i.fields is null)
		{
			mixin(writeBarrier!("alloc", "i"));
			i.fields = namespace.create(alloc, i.parent.name);
		}

		return i.fields;
	}

	package bool next(CrocInstance* i, ref uword idx, ref CrocString** key, ref CrocValue* val)
	{
		if(i.fields is null)
			return false;

		return i.fields.data.next(idx, key, val);
	}
	
	package uword InstanceSize(uword numValues, uword extraBytes)
	{
		return CrocInstance.sizeof + (numValues * CrocValue.sizeof) + extraBytes;
	}
}