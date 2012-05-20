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

void register(CrocThread* t, char[] name, NativeFunc func, uword numUpvals = 0)
{
	newFunction(t, func, name, numUpvals);
	newGlobal(t, name);
}

void register(CrocThread* t, uword numParams, char[] name, NativeFunc func, uword numUpvals = 0)
{
	newFunction(t, numParams, func, name, numUpvals);
	newGlobal(t, name);
}

void registerField(CrocThread* t, char[] name, NativeFunc func, uword numUpvals = 0, char[] fieldName = null)
{
	newFunction(t, func, name, numUpvals);
	fielda(t, -2, fieldName ? fieldName : name);
}

void registerField(CrocThread* t, uword numParams, char[] name, NativeFunc func, uword numUpvals = 0, char[] fieldName = null)
{
	if(fieldName is null)
		fieldName = name;
	newFunction(t, numParams, func, name, numUpvals);
	fielda(t, -2, fieldName ? fieldName : name);
}

template Register(char[] funcName, uword numUpvals = 0, char[] crocName = funcName)
{
	const char[] Register =
	CommonRegister!(funcName, numUpvals, crocName, "") ~
	"newGlobal(t, \"" ~ crocName ~ "\");";
}

template Register(uword numParams, char[] funcName, uword numUpvals = 0, char[] crocName = funcName)
{
	const char[] Register =
	CommonRegister!(funcName, numUpvals, crocName, ctfe_i2a(numParams)) ~
	"newGlobal(t, \"" ~ crocName ~ "\");";
}

template RegisterField(char[] funcName, uword numUpvals = 0, char[] crocName = funcName, char[] fieldName = crocName)
{
	const char[] RegisterField =
	CommonRegister!(funcName, numUpvals, crocName, "") ~
	"fielda(t, -2, \"" ~ fieldName ~ "\");";
}

template RegisterField(uword numParams, char[] funcName, uword numUpvals = 0, char[] crocName = funcName, char[] fieldName = crocName)
{
	const char[] RegisterField =
	CommonRegister!(funcName, numUpvals, crocName, ctfe_i2a(numParams)) ~
	"fielda(t, -2, \"" ~ fieldName ~ "\");";
}

template CommonRegister(char[] funcName, uword numUpvals = 0, char[] crocName, char[] numParams)
{
	const char[] CommonRegister =
	"newFunction(t, " ~ (numParams.length == 0 ? "" : numParams ~ ", ") ~ "&" ~ funcName ~ ", \"" ~ crocName ~ "\", " ~ ctfe_i2a(numUpvals) ~ ");\n";
// 	"version(CrocBuiltinDocs) doc(-1, " ~ funcName ~ "_docs);\n";
}

struct RegisterFunc
{
	char[] name;
	NativeFunc func;
	uword maxParams = uword.max;
	uword numUpvals = 0;
}

void registerGlobals(CrocThread* t, RegisterFunc[] funcs...)
{
	foreach(ref func; funcs)
	{
		if(func.maxParams == uword.max)
			register(t, func.name, func.func, func.numUpvals);
		else
			register(t, func.maxParams, func.name, func.func, func.numUpvals);
	}
}

void registerFields(CrocThread* t, RegisterFunc[] funcs...)
{
	foreach(ref func; funcs)
	{
		if(func.maxParams == uword.max)
			registerField(t, func.name, func.func, func.numUpvals);
		else
			registerField(t, func.maxParams, func.name, func.func, func.numUpvals);
	}
}

void docGlobals(CrocThread* t, CrocDoc doc, CrocDoc.Docs[] docs)
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

void docFields(CrocThread* t, CrocDoc doc, CrocDoc.Docs[] docs)
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