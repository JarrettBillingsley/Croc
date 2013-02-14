/******************************************************************************
This module contains internal implementation of the function object.

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

module croc.types_function;

import croc.base_alloc;
import croc.base_writebarrier;
import croc.types;

struct func
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

package:

	const uint MaxParams = uint.max - 1;

	// Create a script function.
	CrocFunction* create(ref Allocator alloc, CrocNamespace* env, CrocFuncDef* def)
	{
		if(def.environment && def.environment !is env)
			return null;

		if(def.cachedFunc)
			return def.cachedFunc;

		auto f = createPartial(alloc, def.upvals.length);
		finishCreate(alloc, f, env, def);
		return f;
	}

	// Partially construct a script closure. This is used by the serialization system.
	CrocFunction* createPartial(ref Allocator alloc, uword numUpvals)
	{
		auto f = alloc.allocate!(CrocFunction)(ScriptClosureSize(numUpvals));
		f.scriptUpvals()[] = null;
		f.isNative = false;
		f.numUpvals = numUpvals;
		return f;
	}

	// Finish constructing a script closure. Also used by serialization.
	void finishCreate(ref Allocator alloc, CrocFunction* f, CrocNamespace* env, CrocFuncDef* def)
	{
		f.environment = env;
		f.name = def.name;
		f.numParams = def.numParams;

		if(def.isVararg)
			f.maxParams = MaxParams + 1;
		else
			f.maxParams = def.numParams;

		f.scriptFunc = def;

		if(def.environment is null)
		{
			mixin(writeBarrier!("alloc", "def"));
			def.environment = env;
		}

		if(def.upvals.length == 0 && def.cachedFunc is null)
		{
			mixin(writeBarrier!("alloc", "def"));
			def.cachedFunc = f;
		}
	}

	// Create a native function.
	CrocFunction* create(ref Allocator alloc, CrocNamespace* env, CrocString* name, NativeFunc func, uword numUpvals, uword numParams)
	{
		auto f = alloc.allocate!(CrocFunction)(NativeClosureSize(numUpvals));
		f.nativeUpvals()[] = CrocValue.nullValue;

		f.isNative = true;
		f.environment = env;
		f.name = name;
		f.numUpvals = numUpvals;
		f.numParams = numParams + 1; // +1 to include 'this'
		f.maxParams = f.numParams;

		f.nativeFunc = func;

		return f;
	}

	void setNativeUpval(ref Allocator alloc, CrocFunction* f, uword idx, CrocValue* val)
	{
		auto slot = &f.nativeUpvals()[idx];

		if(*slot != *val)
		{
			if((*slot).isGCObject() || val.isGCObject())
				mixin(writeBarrier!("alloc", "f"));

			*slot = *val;
		}
	}

	void setEnvironment(ref Allocator alloc, CrocFunction* f, CrocNamespace* ns)
	{
		if(f.environment !is ns)
		{
			mixin(writeBarrier!("alloc", "f"));
			f.environment = ns;
		}
	}

	bool isNative(CrocFunction* f)
	{
		return f.isNative;
	}

	bool isVararg(CrocFunction* f)
	{
		if(f.isNative)
			return f.numParams == MaxParams + 1;
		else
			return f.scriptFunc.isVararg;
	}

	uword ScriptClosureSize(uword numUpvals)
	{
		return CrocFunction.sizeof + ((CrocUpval*).sizeof * numUpvals);
	}

	uword NativeClosureSize(uword numUpvals)
	{
		return CrocFunction.sizeof + (CrocValue.sizeof * numUpvals);
	}
}