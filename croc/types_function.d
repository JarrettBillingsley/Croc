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
import croc.types;

struct func
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	package const uint MaxParams = uint.max - 1;

	// Create a script function.
	package CrocFunction* create(ref Allocator alloc, CrocNamespace* env, CrocFuncDef* def)
	{
		if(def.environment && def.environment !is env)
			return null;

		if(def.cachedFunc)
			return def.cachedFunc;

		auto f = alloc.allocate!(CrocFunction)(ScriptClosureSize(def.numUpvals));
		f.isNative = false;
		f.environment = env;
		f.name = def.name;
		f.numUpvals = def.numUpvals;
		f.numParams = def.numParams;

		if(def.isVararg)
			f.maxParams = MaxParams + 1;
		else
			f.maxParams = def.numParams;

		f.scriptFunc = def;
		f.scriptUpvals()[] = null;

		if(def.environment is null)
			def.environment = env;

		if(def.numUpvals == 0)
			def.cachedFunc = f;

		return f;
	}

	// Create a native function.
	package CrocFunction* create(ref Allocator alloc, CrocNamespace* env, CrocString* name, NativeFunc func, uword numUpvals, uword numParams)
	{
		auto f = alloc.allocate!(CrocFunction)(NativeClosureSize(numUpvals));
		f.isNative = true;
		f.environment = env;
		f.name = name;
		f.numUpvals = numUpvals;
		f.numParams = numParams + 1; // +1 to include 'this'
		f.maxParams = f.numParams;

		f.nativeFunc = func;
		f.nativeUpvals()[] = CrocValue.nullValue;

		return f;
	}

	// Free a function.
	package void free(ref Allocator alloc, CrocFunction* f)
	{
		if(f.isNative)
			alloc.free(f, NativeClosureSize(f.numUpvals));
		else
			alloc.free(f, ScriptClosureSize(f.numUpvals));
	}

	package bool isNative(CrocFunction* f)
	{
		return f.isNative;
	}

	package bool isVararg(CrocFunction* f)
	{
		if(f.isNative)
			return f.numParams == MaxParams + 1;
		else
			return f.scriptFunc.isVararg;
	}

	package uword ScriptClosureSize(uword numUpvals)
	{
		return CrocFunction.sizeof + ((CrocUpval*).sizeof * numUpvals);
	}

	package uword NativeClosureSize(uword numUpvals)
	{
		return CrocFunction.sizeof + (CrocValue.sizeof * numUpvals);
	}
}