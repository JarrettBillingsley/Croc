/******************************************************************************
This module just contains some helper functions used by the standard library.

License:
Copyright (c) 2011 Jarrett Billingsley

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

module croc.stdlib_utils;

import tango.core.Traits;
import tango.text.Util;

import croc.ex;
import croc.api_interpreter;
import croc.api_stack;
import croc.types;

struct RegisterFunc
{
	char[] name;
	NativeFunc func;
	uword maxParams = uword.max;
	uword numUpvals = 0;
}

private void _pushFunc(CrocThread* t, RegisterFunc f)
{
	if(f.maxParams == uword.max)
		newFunction(t, f.func, f.name, f.numUpvals);
	else
		newFunction(t, f.maxParams, f.func, f.name, f.numUpvals);
}

void register(CrocThread* t, RegisterFunc f)
{
	_pushFunc(t, f);
	newGlobal(t, f.name);
}

void registerField(CrocThread* t, RegisterFunc f)
{
	_pushFunc(t, f);
	fielda(t, -2, f.name);
}

void registerGlobals(CrocThread* t, RegisterFunc[] funcs...)
{
	foreach(ref func; funcs)
	{
		if(func.numUpvals > 0)
			throwStdException(t, "Exception", "registerGlobals - can't register function '{}' as it has upvalues. Use register instead", func.name);

		register(t, func);
	}
}

void registerFields(CrocThread* t, RegisterFunc[] funcs...)
{
	foreach(ref func; funcs)
	{
		if(func.numUpvals > 0)
			throwStdException(t, "Exception", "registerFields - can't register function '{}' as it has upvalues. Use registerField instead", func.name);

		registerField(t, func);
	}
}

void docGlobals(CrocThread* t, CrocDoc doc, CrocDoc.Docs[] docs...)
{
	foreach(ref d; docs)
	{
		auto pos = d.name.locatePrior('.');
		pos = pos == d.name.length ? 0 : pos + 1;

		pushGlobal(t, d.name[pos .. $]);
		doc(-1, d);
		pop(t);
	}
}

void docFields(CrocThread* t, CrocDoc doc, CrocDoc.Docs[] docs...)
{
	foreach(ref d; docs)
	{
		auto pos = d.name.locatePrior('.');
		pos = pos == d.name.length ? 0 : pos + 1;

		field(t, -1, d.name[pos .. $]);
		doc(-1, d);
		pop(t);
	}
}